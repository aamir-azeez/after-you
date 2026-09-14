import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { checkPhoto, jpegFrame, MAX_PHOTO_BYTES } from "../src/v2/photo-image";
import { type PhotoMutation } from "../src/v2/photos";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { RoomSnapshotV2, MutationV2 } from "../src/v2/room";
import type { RoomV2Archive } from "../src/v2/snapshot";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";

const HOST = "H".repeat(22), GUEST = "G".repeat(22), ROOM = "r".repeat(22), INVITE = "A1".repeat(10), SOURCE = "e".repeat(40);
function value<T>(result: Outcome<T>): T { if (!result.ok) throw new Error(result.code); return result.value; }
const stub = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
type Stub = ReturnType<typeof stub>;
const key = () => crypto.randomUUID();
function b64(bytes: Uint8Array): string { let raw = ""; for (const byte of bytes) raw += String.fromCharCode(byte); return btoa(raw); }
async function image(bytes: Uint8Array) {
  const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  return { jpeg_base64: b64(bytes), sha256: hash };
}
// Synthetic pixel blocks only. No photographs, account values or private files.
function synthetic(edge = 8, blue = 120): Uint8Array {
  const data = new Uint8Array(edge * edge * 4);
  for (let i = 0; i < data.length; i += 4) { const x = i / 4 % edge, y = Math.floor(i / 4 / edge); data[i] = Math.floor(x / 16) % 2 * 180; data[i + 1] = Math.floor(y / 16) % 2 * 180; data[i + 2] = blue; data[i + 3] = 255; }
  return new Uint8Array(encode({ data, width: edge, height: edge }, 50).data);
}
function marker(bytes: Uint8Array, wanted: number): number {
  let offset = 2;
  while (offset + 3 < bytes.length) { if (bytes[offset + 1] === wanted) return offset; offset += 2 + bytes[offset + 2] * 256 + bytes[offset + 3]; }
  throw new Error("synthetic fixture marker missing");
}
async function setup() {
  const room = stub(); value(await room.initialize(ROOM, HOST, INVITE)); const state = value(await room.join(GUEST, INVITE));
  const accepted = value(await room.commit(HOST, { base_revision: state.revision, branch: state.branch, idempotency_key: key(), recording: firstA }));
  return { room, state: accepted.room };
}
async function upload(bytes = synthetic(), expectedRevision = 0, expectedHash: string | null = null) {
  return { idempotency_key: key(), recording_hash: firstA.recording_hash, expected_photo_revision: expectedRevision, expected_photo_hash: expectedHash, ...await image(bytes) };
}
function removal(photo: PhotoMutation) { return { idempotency_key: key(), recording_hash: firstA.recording_hash, expected_photo_revision: photo.receipt.photo_revision, expected_photo_hash: photo.receipt.photo_hash }; }
async function archive(room: Stub): Promise<RoomV2Archive> { return JSON.parse(value(await room.exportSnapshot(SOURCE))) as RoomV2Archive; }
async function encoded(data: RoomV2Archive) { data.checksum.value = await digest(canonicalJson(data.payload)); return canonicalJson(data); }
afterEach(async () => { await reset(); });

describe("strict optional photo image profile", () => {
  it("derives exact dimensions/checksum from a fully decoded fixed-JFIF baseline image", async () => {
    const bytes = synthetic(), payload = await image(bytes), checked = await checkPhoto(payload.jpeg_base64, payload.sha256);
    expect(checked).toEqual({ ...payload, width: 8, height: 8, byte_length: bytes.length });
    const app = marker(bytes, 0xe0), length = bytes[app + 2] * 256 + bytes[app + 3];
    const stripped = new Uint8Array([...bytes.slice(0, app), ...bytes.slice(app + length + 2)]), clean = await image(stripped);
    expect(await checkPhoto(clean.jpeg_base64, clean.sha256)).toMatchObject({ width: 8, height: 8 });
  });
  it("rejects every metadata APP/COM segment and nonfixed JFIF thumbnails", async () => {
    for (const tag of [...Array.from({ length: 15 }, (_, i) => 0xe1 + i), 0xfe]) {
      const bytes = new Uint8Array([255, 216, 255, tag, 0, 6, 69, 88, 73, 70, ...synthetic().slice(2)]), payload = await image(bytes);
      await expect(checkPhoto(payload.jpeg_base64, payload.sha256)).rejects.toMatchObject({ status: 400 });
    }
    const thumb = synthetic(); thumb[marker(thumb, 0xe0) + 16] = 1; expect(() => jpegFrame(thumb)).toThrow();
  });
  it("rejects oversized dimensions, oversized bytes, progressive input, missing end and trailing data", async () => {
    const big = synthetic(); const sof = marker(big, 0xc0); big[sof + 7] = 3; big[sof + 8] = 193;
    expect(() => jpegFrame(big)).toThrow();
    const progressive = synthetic(); progressive[marker(progressive, 0xc0) + 1] = 0xc2;
    for (const bytes of [new Uint8Array(MAX_PHOTO_BYTES + 1), progressive, synthetic().slice(0, -2), new Uint8Array([...synthetic(), 0])]) expect(() => jpegFrame(bytes)).toThrow();
  });
  it("rejects malformed entropy even when its outer JPEG framing is complete", async () => {
    const bytes = synthetic(), sos = marker(bytes, 0xda), end = sos + 2 + bytes[sos + 2] * 256 + bytes[sos + 3];
    const broken = new Uint8Array([...bytes.slice(0, end), 0, 255, 217]), payload = await image(broken);
    expect(jpegFrame(broken)).toEqual({ width: 8, height: 8 });
    await expect(checkPhoto(payload.jpeg_base64, payload.sha256)).rejects.toMatchObject({ code: "invalid_photo_jpeg" });
  });
  it("rejects data URLs, noncanonical encoding, false checksums and client metadata additions", async () => {
    const { room } = await setup(), body = await upload();
    await expect(checkPhoto("data:image/jpeg;base64," + body.jpeg_base64, body.sha256)).rejects.toMatchObject({ code: "invalid_photo_encoding" });
    await expect(checkPhoto(body.jpeg_base64 + "\n", body.sha256)).rejects.toMatchObject({ code: "invalid_photo_encoding" });
    await expect(checkPhoto(body.jpeg_base64, "0".repeat(64))).rejects.toMatchObject({ code: "photo_checksum_mismatch" });
    expect(await room.updatePhoto(HOST, "t0-0-a", { ...body, width: 8 })).toMatchObject({ ok: false, status: 400 });
  });
});

describe("optional photos in the actual RoomV2 runtime", () => {
  it("requires an accepted owned immutable turn before decoding and limits read access to members", async () => {
    const { room } = await setup(), body = await upload();
    expect(await room.updatePhoto("X".repeat(22), "t0-0-a", body)).toMatchObject({ ok: false, code: "room_not_found" });
    expect(await room.updatePhoto(GUEST, "t0-0-a", { ...body, jpeg_base64: "bad" })).toMatchObject({ ok: false, code: "turn_not_found" });
    expect(await room.updatePhoto(HOST, "t0-0-b", body)).toMatchObject({ ok: false, code: "turn_not_found" });
    expect(await room.updatePhoto(HOST, "t0-0-a", { ...body, recording_hash: "0".repeat(64) })).toMatchObject({ ok: false, code: "photo_recording_mismatch" });
    value(await room.updatePhoto(HOST, "t0-0-a", body));
    expect(value(await room.photo(GUEST, "t0-0-a"))).toMatchObject({ photo: { sha256: body.sha256 }, jpeg_base64: body.jpeg_base64 });
    expect(await room.photo("X".repeat(22), "t0-0-a")).toMatchObject({ ok: false, status: 404 });
  });
  it("reconciles lost replies and preserves receipts across replacement without changing gameplay revision", async () => {
    const { room, state } = await setup(), first = await upload();
    await room.updatePhoto(HOST, "t0-0-a", first); // Deliberately ignore acknowledgement.
    const receipt = value(await room.photoOperation(HOST, first.idempotency_key));
    expect(receipt.receipt).toMatchObject({ photo_revision: 1, photo_hash: first.sha256 });
    const second = await upload(synthetic(8, 180), 1, first.sha256), replaced = value(await room.updatePhoto(HOST, "t0-0-a", second));
    const oldRetry = value(await room.updatePhoto(HOST, "t0-0-a", first));
    expect(oldRetry.receipt).toEqual(receipt.receipt); expect(oldRetry.photo?.sha256).toBe(replaced.photo?.sha256);
    expect(await room.updatePhoto(HOST, "t0-0-a", { ...first, sha256: second.sha256, jpeg_base64: second.jpeg_base64 })).toMatchObject({ ok: false, code: "idempotency_key_reused" });
    expect(value(await room.snapshot(HOST))).toEqual(state);
    expect(await room.photoOperation(GUEST, first.idempotency_key)).toMatchObject({ ok: false, status: 404 });
  });
  it("requires version and old hash on replacement/deletion, including same-bytes ABA and delete retries", async () => {
    const { room } = await setup(), first = await upload(), a = value(await room.updatePhoto(HOST, "t0-0-a", first));
    const staleDelete = removal(a), b = await upload(synthetic(8, 40), 1, first.sha256);
    value(await room.updatePhoto(HOST, "t0-0-a", b));
    const again = await upload(synthetic(), 2, b.sha256); const third = value(await room.updatePhoto(HOST, "t0-0-a", again));
    expect(await room.updatePhoto(HOST, "t0-0-a", staleDelete, true)).toMatchObject({ ok: false, code: "stale_photo_revision" });
    const remove = removal(third), deleted = value(await room.updatePhoto(HOST, "t0-0-a", remove, true));
    expect(deleted.photo).toMatchObject({ sha256: null, photo_revision: 4, byte_length: 0 });
    const next = await upload(synthetic(8, 10), 4, null); value(await room.updatePhoto(HOST, "t0-0-a", next));
    expect(value(await room.updatePhoto(HOST, "t0-0-a", remove, true)).receipt).toEqual(deleted.receipt);
    expect(value(await room.photo(HOST, "t0-0-a")).photo?.sha256).toBe(next.sha256);
  });
  it("keeps accepted historical-turn photos tied to that immutable recording across a fork", async () => {
    const { room, state } = await setup(), body = await upload();
    value(await room.fork(HOST, { base_revision: state.revision, branch: 0, stage_index: 0, idempotency_key: key() }));
    value(await room.updatePhoto(HOST, "t0-0-a", body));
    expect(value(await room.photo(GUEST, "t0-0-a")).photo?.recording_hash).toBe(firstA.recording_hash);
    expect(await room.updatePhoto(HOST, "t1-0-a", body)).toMatchObject({ ok: false, code: "turn_not_found" });
  });
  it("rejects explicit retained-history capacity without removing old image bytes", async () => {
    const { room } = await setup(), body = await upload(); value(await room.updatePhoto(HOST, "t0-0-a", body));
    // Storage-level capacity fault injection isolates this limit without running256 user edits.
    await runInDurableObject(room, async (_, ctx) => {
      for (let i = 1; i < 256; i++) ctx.storage.sql.exec("INSERT INTO photo_operations VALUES (?,?,?)", "synthetic-"+i, "h", "{}");
    });
    expect(await room.updatePhoto(HOST, "t0-0-a", await upload(synthetic(8, 90), 1, body.sha256))).toMatchObject({ ok: false, code: "photo_history_full" });
    expect(value(await room.photo(HOST, "t0-0-a")).jpeg_base64).toBe(body.jpeg_base64);
  });
  it("reports active-photo capacity explicitly without evicting any stored memory", async () => {
    const { room } = await setup(), body = await upload();
    // Isolated storage-capacity injection; these are not gameplay acceptance fixtures.
    await runInDurableObject(room, async (_, ctx) => {
      for (let i = 0; i < 32; i++) ctx.storage.sql.exec("INSERT INTO photos VALUES (?,?)", "capacity-"+i, '{"sha256":"synthetic"}');
    });
    expect(await room.updatePhoto(HOST, "t0-0-a", body)).toMatchObject({ ok: false, code: "photo_room_full" });
    await runInDurableObject(room, async (_, ctx) => { expect(ctx.storage.sql.exec("SELECT turn_id FROM photos").toArray()).toHaveLength(32); expect(ctx.storage.sql.exec("SELECT * FROM photo_operations").toArray()).toEqual([]); });
  });
  it("reserves deletion capacity when immutable upload receipts reach their limit", async () => {
    const { room } = await setup(), initial = await upload(); let current = value(await room.updatePhoto(HOST, "t0-0-a", initial));
    for (let revision = 1; revision < 255; revision++) {
      current = value(await room.updatePhoto(HOST, "t0-0-a", { ...initial, idempotency_key: key(), expected_photo_revision: revision, expected_photo_hash: initial.sha256 }));
    }
    const rejected = { ...initial, idempotency_key: key(), expected_photo_revision: 255, expected_photo_hash: initial.sha256 };
    expect(await room.updatePhoto(HOST, "t0-0-a", rejected)).toMatchObject({ ok: false, code: "photo_history_full" });
    const deleted = value(await room.updatePhoto(HOST, "t0-0-a", removal(current), true));
    expect(deleted.photo).toMatchObject({ photo_revision: 256, sha256: null });
    const snapshot = await archive(room), target = stub();
    expect(await target.restoreSnapshot(await encoded(snapshot), ROOM)).toMatchObject({ ok: true });
    expect(value(await target.photo(HOST, "t0-0-a")).jpeg_base64).toBeNull();
  }, 30000);
  it("rolls back a failed atomic receipt insertion without changing photo state", async () => {
    const { room } = await setup(), body = await upload();
    await runInDurableObject(room, async (_, ctx) => { ctx.storage.sql.exec("CREATE TRIGGER fail_photo_receipt BEFORE INSERT ON photo_operations BEGIN SELECT RAISE(ABORT,'synthetic_failure'); END"); });
    expect(await room.updatePhoto(HOST, "t0-0-a", body)).toMatchObject({ ok: false, status: 500, code: "photo_storage_error" });
    expect(value(await room.photo(HOST, "t0-0-a"))).toEqual({ photo: null, jpeg_base64: null });
  });
  it("erases all bytes and receipts on room deletion, including a racing validated upload", async () => {
    const { room } = await setup(), body = await upload();
    await Promise.all([room.updatePhoto(HOST, "t0-0-a", body), room.eraseForPlayer(GUEST)]);
    expect(await room.photo(HOST, "t0-0-a")).toMatchObject({ ok: false, status: 404 });
    await runInDurableObject(room, async (_, ctx) => { expect(ctx.storage.sql.exec("SELECT * FROM photos").toArray()).toEqual([]); expect(ctx.storage.sql.exec("SELECT * FROM photo_operations").toArray()).toEqual([]); });
  });
});

describe("portable photo snapshots", () => {
  it("measures the maximum retained image count at the largest allowed edge in actual local workerd", async (context) => {
    const bytes = synthetic(960), payload = await image(bytes), room = stub();
    expect(bytes.length).toBeLessThanOrEqual(MAX_PHOTO_BYTES);
    let state = value(await room.initialize(ROOM, HOST, INVITE));
    const uploadTimes: number[] = [];
    for (let branch = 0; branch < 32; branch++) {
      state = value(await room.commit(HOST, { base_revision: state.revision, branch, idempotency_key: key(), recording: firstA })).room;
      const start = performance.now();
      value(await room.updatePhoto(HOST, `t${branch}-0-a`, { idempotency_key: key(), recording_hash: firstA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, ...payload }));
      uploadTimes.push(performance.now() - start);
      if (branch < 31) state = value(await room.fork(HOST, { base_revision: state.revision, branch, stage_index: 0, idempotency_key: key() })).room;
    }
    const exportStart = performance.now(), serialized = value(await room.exportSnapshot(SOURCE)), exportMs = performance.now() - exportStart;
    const target = stub(), restoreStart = performance.now();
    expect(await target.restoreSnapshot(serialized, ROOM)).toMatchObject({ ok: true });
    const restoreMs = performance.now() - restoreStart;
    expect(value(await target.photo(HOST, "t31-0-a")).photo?.width).toBe(960);
    Object.assign(context.task.meta, { local_workerd_timing: { scope: "RPC elapsed milliseconds; synthetic 960px; 32 retained images; not deployed CPU accounting", jpeg_bytes: bytes.length, archive_bytes: serialized.length, upload_cold_ms: uploadTimes[0], upload_warm_ms: uploadTimes.slice(-3), export_ms: exportMs, restore_ms: restoreMs } });
  }, 30000);
  it("roundtrips exact JPEG strings, tombstones, rowids and stable receipts into another evicted object", async () => {
    const { room } = await setup(), body = await upload(), photo = value(await room.updatePhoto(HOST, "t0-0-a", body));
    await runInDurableObject(room, async (_, ctx) => { ctx.storage.sql.exec("UPDATE photos SET rowid=9007199254740993"); });
    const original = await archive(room), target = stub();
    expect(original.payload).toMatchObject({ format_version: 4, database_schema_version: 3 });
    expect(await target.restoreSnapshot(await encoded(original), ROOM)).toMatchObject({ ok: true });
    await evictDurableObject(target);
    expect((await archive(target)).payload.tables).toEqual(original.payload.tables);
    expect(value(await target.photoOperation(HOST, body.idempotency_key))).toEqual(photo);
    value(await target.updatePhoto(HOST, "t0-0-a", removal(photo), true));
    const erased = await archive(target), other = stub(); expect(await other.restoreSnapshot(await encoded(erased), ROOM)).toMatchObject({ ok: true });
    expect(value(await other.photo(GUEST, "t0-0-a"))).toMatchObject({ photo: { sha256: null, photo_revision: 2 }, jpeg_base64: null });
  });
  it("accepts old format3/schema2 archives with empty photo tables and migrates deployed schema2 without row loss", async () => {
    const { room, state } = await setup(), old = await archive(room);
    old.payload.format_version = 3; old.payload.database_schema_version = 2; old.payload.tables = old.payload.tables.slice(0, 4);
    const target = stub(); expect(await target.restoreSnapshot(await encoded(old), ROOM)).toMatchObject({ ok: true });
    expect(value(await target.snapshot(HOST))).toEqual(state); expect(value(await target.photo(HOST, "t0-0-a"))).toEqual({ photo: null, jpeg_base64: null });
    await runInDurableObject(room, async (_, ctx) => { ctx.storage.sql.exec("DROP TABLE photos"); ctx.storage.sql.exec("DROP TABLE photo_operations"); ctx.storage.sql.exec("UPDATE metadata SET schema_version=2"); });
    await evictDurableObject(room); expect(value(await room.snapshot(HOST))).toEqual(state);
    expect((await archive(room)).payload.tables.slice(0, 4)).toEqual(old.payload.tables);
  });
  it("rejects tampered image content, dimensions, orphan photos and missing receipts without partial restore", async () => {
    const { room } = await setup(); value(await room.updatePhoto(HOST, "t0-0-a", await upload())); const source = await archive(room);
    for (const kind of ["bytes", "width", "owner", "receipt", "tombstone"] as const) {
      const changed = structuredClone(source), row = changed.payload.tables[4].rows[0], raw = JSON.parse(String(row.data));
      if (kind === "bytes") raw.jpeg_base64 = "ZmFrZQ==";
      if (kind === "width") raw.width = 77;
      if (kind === "owner") raw.owner_player_id = GUEST;
      if (kind === "receipt") changed.payload.tables[5].rows = [];
      if (kind === "tombstone") changed.payload.tables[0].rows[0].data = '{"deleted":true}';
      row.data = JSON.stringify(raw);
      const target = stub(); expect(await target.restoreSnapshot(await encoded(changed), ROOM)).toMatchObject({ ok: false, status: 400 });
      expect((await archive(target)).payload.summary.state).toBe("empty");
    }
  });
});

describe("public authenticated photo routes", () => {
  it("requires auth, keeps paused uploads separate from deletes, and identity deletion erases media", async () => {
    type Account = { player_id: string; device_token: string };
    let address = 10;
    async function call(path: string, method: string, account?: Account, body?: unknown, enabled = true, photos = true) {
      const config: Env = { ...env }; Object.assign(config, { V2_ROOMS_ENABLED: enabled ? "true" : "false", RELAY_PHOTOS_ENABLED: photos ? "true" : "false" });
      return worker.fetch(new Request("https://after-you.test"+path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP":"203.0.113."+(address++), ...(account ? { "X-Player-Id":account.player_id, Authorization:"Bearer "+account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), config);
    }
    const host = await (await call("/v1/identity", "POST", undefined, {})).json<Account>();
    const initial = await (await call("/v2/rooms", "POST", host, { idempotency_key:key(), level_id:RELAY.id, level_version:2, definition_hash:DEFINITION_HASH }, true, false)).json<RoomSnapshotV2>();
    const accepted = await (await call(`/v2/rooms/${initial.room_id}/turns`, "POST", host, { base_revision:initial.revision, branch:0, idempotency_key:key(), recording:firstA }, true, false)).json<MutationV2>();
    const path = `/v2/rooms/${initial.room_id}/photos/${accepted.receipt.turn_id}`, body = await upload();
    expect((await call(path,"GET")).status).toBe(401);
    expect((await call(path,"POST",host,body,false)).status).toBe(503);
    const paused = await call(path,"POST",host,body,true,false);
    expect(paused.status).toBe(503); expect(await paused.json()).toMatchObject({ error: { code:"photo_uploads_disabled", retryable:true } });
    expect((await (await call("/v2/capabilities","GET",host,undefined,true,false)).json<{photo_uploads_enabled:boolean}>()).photo_uploads_enabled).toBe(false);
    expect((await (await call("/v2/capabilities","GET",host)).json<{photo_uploads_enabled:boolean}>()).photo_uploads_enabled).toBe(true);
    const result = await call(path,"POST",host,body); expect(result.status).toBe(200); expect(result.headers.get("Cache-Control")).toBe("no-store");
    const photo = await result.json<PhotoMutation>();
    expect((await call(path,"GET",host,undefined,true,false)).status).toBe(200);
    expect((await call(`/v2/rooms/${initial.room_id}/photo-operations/${body.idempotency_key}`,"GET",host,undefined,true,false)).status).toBe(200);
    expect((await call(path,"DELETE",host,removal(photo),false,false)).status).toBe(200);
    value(await env.ROOMS_V2.getByName(initial.room_id).updatePhoto(host.player_id, "t0-0-a", await upload(synthetic(), 2, null)));
    expect((await call("/v1/identity","DELETE",host)).status).toBe(200);
    const room = env.ROOMS_V2.getByName(initial.room_id);
    await runInDurableObject(room, async (_, ctx) => { expect(ctx.storage.sql.exec("SELECT * FROM photos").toArray()).toEqual([]); expect(ctx.storage.sql.exec("SELECT * FROM photo_operations").toArray()).toEqual([]); });
  });
});
