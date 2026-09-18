import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, type Outcome } from "../src/protocol";
import { RELAY_KEY, acceptedRecording, chapter, checkpointV2, initialCheckpoint, recordingV2 } from "../src/v2/protocol";
import { FIRST_STEPS, FIRST_STEPS_HASH, adapter } from "../src/v2/protocol-first-steps";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import type { RoomV2Archive } from "../src/v2/snapshot";
import type { PortableSnapshot } from "../src/snapshot";
import liftA from "../../game/tests/fixtures/first_steps/a-little-lift-a.json";
import liftB from "../../game/tests/fixtures/first_steps/a-little-lift-b.json";
import seedA from "../../game/tests/fixtures/first_steps/a-place-to-grow-a.json";
import seedB from "../../game/tests/fixtures/first_steps/a-place-to-grow-b.json";
import middle from "../../game/tests/fixtures/first_steps/lift-checkpoint.json";
import final from "../../game/tests/fixtures/first_steps/final-checkpoint.json";
import initial from "../../game/tests/fixtures/first_steps/initial-checkpoint.json";
import relayA from "../../game/tests/fixtures/v2/relay-a.json";
import cumulativeA from "../../game/tests/fixtures/first_steps/cumulative-lift-a.json";
import cumulativeB from "../../game/tests/fixtures/first_steps/cumulative-lift-b.json";
import cumulativeCheckpoint from "../../game/tests/fixtures/first_steps/cumulative-lift-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
const key = () => crypto.randomUUID(), source = "e".repeat(40), descriptor = adapter.key;
let requestNo = 0;
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
async function call(path: string, method = "GET", account?: Account, body?: unknown, firstSteps = true, rooms = env.ROOMS_V2): Promise<Response> {
  const configured: Env = { ...env, ROOMS_V2: rooms };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", FIRST_STEPS_ENABLED: String(firstSteps), RELAY_PHOTOS_ENABLED: "true" });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + ++requestNo,
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function newRoom(host: Account, chapterKey = descriptor, idempotency_key = key(), simulation_version?: number): Promise<RoomSnapshotV2> {
  const response = await call("/v2/rooms", "POST", host, { ...chapterKey, idempotency_key, ...(simulation_version === undefined ? {} : { simulation_version }) }); expect(response.status).toBe(200); return response.json<RoomSnapshotV2>();
}
function turn(room: RoomSnapshotV2, recording: unknown, checkpoint?: unknown) { return { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) }; }
async function submit(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, turn(room, recording, checkpoint)); expect(response.status).toBe(200); return response.json<MutationV2>();
}
async function pair(cumulative = false) {
  const host = await account(), guest = await account(), room = await newRoom(host, descriptor, key(), cumulative ? 5 : undefined);
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, ...(cumulative ? { supported_simulation_versions: [2, 4, 5] } : {}) }); expect(joined.status).toBe(200);
  return { host, guest, room: await joined.json<RoomSnapshotV2>() };
}
async function complete() {
  const { host, guest, room } = await pair();
  const a = await submit(room, host, liftA), b = await submit(a.room, guest, liftB, middle);
  const c = await submit(b.room, guest, seedA), d = await submit(c.room, host, seedB, final);
  return { host, guest, initial: room, room: d.room, responses: [a, b, c, d] };
}
async function rehash<T extends Record<string, unknown>>(input: T, hashKey = "recording_hash"): Promise<T> {
  const copy = structuredClone(input), body: Record<string, unknown> = { ...copy }; delete body[hashKey]; if (hashKey === "checkpoint_hash") delete body.proof;
  return { ...copy, [hashKey]: await digest(canonicalJson(body)) };
}
async function signed(archive: PortableSnapshot | RoomV2Archive): Promise<string> { archive.checksum.value = await digest(canonicalJson(archive.payload)); return canonicalJson(archive); }
afterEach(async () => { await reset(); });

describe("First Steps immutable chapter dispatch", () => {
  it("accepts explicit cumulative rules while preserving legacy capability metadata and recordings", async () => {
    expect(adapter.simulation_version).toBe(4);
    expect(adapter.supported_simulation_versions).toEqual([4, 5]);
    for (const record of [liftA, liftB, cumulativeA, cumulativeB]) {
      expect(await recordingV2(record, descriptor)).toEqual(record);
    }
    const a = await recordingV2(cumulativeA), b = await recordingV2(cumulativeB);
    expect(await checkpointV2(cumulativeCheckpoint, initialCheckpoint(descriptor), a, b)).toEqual(cumulativeCheckpoint);
    await expect(recordingV2(await rehash({ ...cumulativeA, simulation_version: 6 }), descriptor)).rejects.toMatchObject({ code: "unsupported_simulation_version" });
    await expect(recordingV2({ ...cumulativeA, simulation_version: 4 }, descriptor)).rejects.toMatchObject({ code: "recording_hash_mismatch" });
    await expect(checkpointV2(cumulativeCheckpoint, initialCheckpoint(descriptor), a, { ...b, simulation_version: 4 })).rejects.toMatchObject({ code: "unsupported_simulation_version" });
    const { host, guest, room } = await pair(true);
    const acceptedSource = await submit(room, host, cumulativeA);
    expect(acceptedSource.room.recording_a).toEqual(cumulativeA);
    const completed = await submit(acceptedSource.room, guest, cumulativeB, cumulativeCheckpoint);
    expect(completed.room.stage_index).toBe(1);
    expect(completed.room.checkpoint).toEqual(cumulativeCheckpoint);
    expect(completed.room.simulation_version).toBe(5);
    const stub = env.ROOMS_V2.getByName(room.room_id), restored = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    const archive = value(await stub.exportSnapshot(source));
    expect(await restored.restoreSnapshot(archive, room.room_id)).toMatchObject({ ok: true });
    expect(value(await restored.snapshot(guest.player_id))).toEqual(completed.room);
    const tampered = JSON.parse(archive) as RoomV2Archive;
    const state = JSON.parse(String(tampered.payload.tables[0].rows[0].data)); delete state.simulation_version;
    tampered.payload.tables[0].rows[0].data = JSON.stringify(state);
    expect(await env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()).restoreSnapshot(await signed(tampered), room.room_id)).toMatchObject({ ok: false, code: "snapshot_simulation_mismatch" });
    const capabilities = await (await call("/v2/capabilities", "GET", host)).json<{ chapters: Record<string, unknown>[] }>();
    expect(capabilities.chapters[1]).toMatchObject({ simulation_version: 4, supported_simulation_versions: [4, 5] });
  });
  it("pins new rooms without upgrading old rooms or consuming unsupported clients' guest slots", async () => {
    const host = await account(), guest = await account(), idempotency_key = key();
    expect((await call("/v2/rooms", "POST", host, { ...descriptor, idempotency_key: key(), simulation_version: 4 })).status).toBe(422);
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual([]);
    const room = await newRoom(host, descriptor, idempotency_key, 5);
    expect(await newRoom(host, descriptor, idempotency_key, 5)).toEqual(room);
    expect((await call("/v2/rooms", "POST", host, { ...descriptor, idempotency_key })).status).toBe(409);
    const denied = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code });
    expect(denied.status).toBe(422); expect(await denied.json()).toMatchObject({ error: { code: "unsupported_simulation_version" } });
    expect(value(await env.ROOMS_V2.getByName(room.room_id).snapshot(host.player_id))).toEqual(room);
    expect(await env.PLAYERS.getByName(guest.player_id).listRooms()).toEqual([]);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: [2, 4, 5] });
    expect(joined.status).toBe(200);
    const live = await joined.json<RoomSnapshotV2>();
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, turn(live, liftA))).status).toBe(422);
    const accepted = await submit(live, host, cumulativeA);
    const forked = await call(`/v2/rooms/${room.room_id}/fork`, "POST", host, { base_revision: accepted.room.revision, branch: accepted.room.branch, stage_index: 0, idempotency_key: key() });
    expect(forked.status).toBe(200); expect((await forked.json<MutationV2>()).room.simulation_version).toBe(5);
    const old = await pair();
    expect(old.room.simulation_version).toBeUndefined();
    expect((await call(`/v2/rooms/${old.room.room_id}/turns`, "POST", old.host, turn(old.room, cumulativeA))).status).toBe(422);
    const oldA = await submit(old.room, old.host, liftA), oldB = await submit(oldA.room, old.guest, liftB, middle);
    expect(oldB.room.simulation_version).toBeUndefined();
    const player = env.PLAYERS.getByName(host.player_id), playerArchive = value(await player.exportSnapshot(source));
    const playerCopy = env.PLAYERS.get(env.PLAYERS.newUniqueId());
    expect(await playerCopy.restoreSnapshot(playerArchive, host.player_id)).toMatchObject({ ok: true });
    expect(value(await playerCopy.reserveChapterRoom(idempotency_key, { room_id: "z".repeat(22), invite_code: "F".repeat(20), host: true, api_version: 2 }, descriptor, 5)).simulation_version).toBe(5);
    expect(await playerCopy.reserveChapterRoom(idempotency_key, { room_id: "z".repeat(22), invite_code: "F".repeat(20), host: true, api_version: 2 }, descriptor)).toMatchObject({ ok: false, code: "idempotency_simulation_mismatch" });
  });
  it("matches the exact Godot catalog, initial state, all four recording hashes and nested checkpoint proofs", async () => {
    expect(await digest(canonicalJson(FIRST_STEPS))).toBe(FIRST_STEPS_HASH);
    expect(initialCheckpoint(descriptor)).toEqual(initial);
    expect(chapter(RELAY_KEY).simulation_version).toBe(2); expect(chapter(descriptor).simulation_version).toBe(4);
    for (const fixture of [liftA, liftB, seedA, seedB]) { const parsed = await recordingV2(fixture, descriptor); expect(parsed).toEqual(fixture); expect(acceptedRecording(parsed)).toBe(true); }
    const a = await recordingV2(liftA), b = await recordingV2(liftB);
    expect(a.outcome.threw_seed).toBe(false); expect(a.source_recording_hash).toBe("");
    const checkpoint = await checkpointV2(middle, initialCheckpoint(descriptor), a, b); expect(checkpoint).toEqual(middle);
    expect(await checkpointV2(final, checkpoint, await recordingV2(seedA), await recordingV2(seedB))).toEqual(final);
    expect(await recordingV2(relayA, RELAY_KEY)).toEqual(relayA);
  });
  it("keeps the rollout hidden/default-off while preserving preview5 Relay capability semantics", async () => {
    const host = await account();
    const off = await (await call("/v2/capabilities", "GET", host, undefined, false)).json<{ api_version: number; recording_version: number; simulation_version: number; chapters: Record<string, unknown>[] }>();
    expect(off).toMatchObject({ api_version: 2, recording_version: 2, simulation_version: 2 }); expect(off.chapters).toHaveLength(1); expect(off.chapters[0]).toMatchObject(RELAY_KEY);
    expect((await call("/v2/rooms", "POST", host, { ...descriptor, idempotency_key: key() }, false)).status).toBe(503);
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual([]);
    expect((await call("/v2/rooms", "POST", host, { ...RELAY_KEY, idempotency_key: key() }, false)).status).toBe(200);
    const on = await (await call("/v2/capabilities", "GET", host)).json<{ chapters: Record<string, unknown>[] }>();
    expect(on.chapters).toHaveLength(2); expect(on.chapters[1]).toMatchObject({ ...descriptor, premium: false, recording_version: 4, simulation_version: 4 });
  });
  it("binds the complete chapter creation intent before a lost response and rejects key reuse across chapters", async () => {
    const host = await account(), idempotency_key = key(), first = await newRoom(host, descriptor, idempotency_key);
    expect(await newRoom(host, descriptor, idempotency_key)).toEqual(first);
    const mismatch = await call("/v2/rooms", "POST", host, { ...RELAY_KEY, idempotency_key }); expect(mismatch.status).toBe(409); expect(await mismatch.json()).toEqual({ error: { code: "idempotency_chapter_mismatch", retryable: false } });
    expect((await call("/v1/rooms", "POST", host, { idempotency_key })).status).toBe(409);
    const player = env.PLAYERS.getByName(host.player_id);
    expect(await player.listRooms()).toHaveLength(1);
    const archive = JSON.parse(value(await player.exportSnapshot(source))) as PortableSnapshot;
    expect(archive.payload.format_version).toBe(3);
    expect(JSON.parse(String(archive.payload.tables[2].rows[0].data))).toMatchObject({ creation_schema: 1, chapter: descriptor, link: { room_id: first.room_id, api_version: 2 } });
    expect(await env.ROOMS_V2.getByName(first.room_id).initialize(first.room_id, host.player_id, first.invite_code!, RELAY_KEY)).toMatchObject({ ok: false, code: "idempotency_chapter_mismatch" });
  });
  it("resumes a reserved creation without changing its room ID and preserves historical raw Relay creation rows", async () => {
    const host = await account(), player = env.PLAYERS.getByName(host.player_id), idempotency_key = key();
    const link = { room_id: "r".repeat(22), invite_code: "A".repeat(20), host: true, api_version: 2 };
    value(await player.reserveChapterRoom(idempotency_key, link, descriptor));
    const room = await newRoom(host, descriptor, idempotency_key); expect(room.room_id).toBe(link.room_id);
    const oldKey = key(), old = { ...link, room_id: "s".repeat(22) }; value(await player.reserveRoom(oldKey, old));
    const before = await runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM creations WHERE request_key=?", oldKey).one().data);
    expect((await newRoom(host, RELAY_KEY, oldKey)).room_id).toBe(old.room_id);
    expect((await call("/v2/rooms", "POST", host, { ...descriptor, idempotency_key: oldKey })).status).toBe(409);
    const after = await runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM creations WHERE request_key=?", oldKey).one().data); expect(after).toBe(before);
  });
  it("keeps new Relay creation rows and Player archives in the old compatible format with First Steps off", async () => {
    const host = await account(), idempotency_key = key();
    const created = await call("/v2/rooms", "POST", host, { ...RELAY_KEY, idempotency_key }, false); expect(created.status).toBe(200);
    const room = await created.json<RoomSnapshotV2>(), player = env.PLAYERS.getByName(host.player_id);
    const archive = JSON.parse(value(await player.exportSnapshot(source))) as PortableSnapshot;
    expect(archive.payload.format_version).toBe(2);
    expect(JSON.parse(String(archive.payload.tables[2].rows[0].data))).toEqual({ room_id: room.room_id, invite_code: room.invite_code, host: true, api_version: 2 });
    expect(await (await call("/v2/rooms", "POST", host, { ...RELAY_KEY, idempotency_key }, false)).json()).toEqual(room);
    expect((await call("/v2/rooms", "POST", host, { ...descriptor, idempotency_key })).status).toBe(409);
    expect((await call("/v1/rooms", "POST", host, { idempotency_key })).status).toBe(409);
    expect((JSON.parse(value(await player.exportSnapshot(source))) as PortableSnapshot).payload.tables).toEqual(archive.payload.tables);
  });
  it("runs the full two-stage role reversal and keeps stable receipts after advancement and creation disable", async () => {
    const done = await complete(); expect(done.room).toMatchObject({ ...descriptor, stage_index: 2, active_role: "complete", revision: 5, checkpoint: final });
    expect(done.responses[1].room.active_player_id).toBe(done.guest.player_id); expect(done.responses[2].room.active_player_id).toBe(done.host.player_id);
    const path = `/v2/rooms/${done.room.room_id}`;
    expect(await (await call(path, "GET", done.host, undefined, false)).json()).toEqual(done.room);
    const receipt = done.responses[0].receipt;
    expect(await (await call(`${path}/operations/${receipt.idempotency_key}`, "GET", done.host, undefined, false)).json()).toEqual({ receipt, room: done.room });
    const retry = { ...turn(done.initial, liftA), idempotency_key: receipt.idempotency_key };
    expect(await (await call(`${path}/turns`, "POST", done.host, retry, false)).json()).toEqual({ receipt, room: done.room });
    expect((await call(path, "GET", await account())).status).toBe(404);
  });
  it("rejects cross-chapter/schema/outcome substitutions without changing a room", async () => {
    const { host, room } = await pair(), path = `/v2/rooms/${room.room_id}/turns`;
    for (const record of [relayA, { ...liftA, simulation_version: 2 }, { ...liftA, stage_version: 2 }, await rehash({ ...liftA, outcome: { ...liftA.outcome, supplied_power: false, threw_seed: true } })]) {
      expect((await call(path, "POST", host, turn(room, record))).status).toBe(422);
    }
    expect(await (await call(`/v2/rooms/${room.room_id}`, "GET", host)).json()).toMatchObject({ revision: 1, active_role: "a" });
    await expect(recordingV2(liftA, RELAY_KEY)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
  });
  it("validates vertical surfaces and activated mechanisms while retaining arbitrary valid endpoints", async () => {
    const a = await recordingV2(liftA), b = await recordingV2(liftB), previous = initialCheckpoint(descriptor);
    const invalids = [
      { ...middle, mechanisms: { ...middle.mechanisms, garden_open: true } },
      { ...middle, players: { ...middle.players, p1: { ...middle.players.p1, height: 0 } } },
      { ...middle, seed: { ...middle.seed, status: "planted" } },
      { ...middle, proof: { ...middle.proof, checkpoint: { ...middle.proof.checkpoint, stage_index: 1 } } }
    ];
    for (const invalid of invalids) await expect(checkpointV2(await rehash(invalid, "checkpoint_hash"), previous, a, b)).rejects.toBeDefined();
    const moved = await rehash({ ...middle, players: { ...middle.players, p1: { ...middle.players.p1, x: 240 } } }, "checkpoint_hash");
    // This service validates structure/dependencies, never claims server physics.
    expect(await checkpointV2(moved, previous, a, b)).toEqual(moved);
    let deep: unknown = {}; for (let i = 0; i < 25; i++) deep = { checkpoint: deep };
    await expect(checkpointV2({ ...middle, proof: deep }, previous, a, b)).rejects.toMatchObject({ status: 413 });
  });
  it("roundtrips raw RoomV2 rows, forks, old receipts and new checkpoint proofs in format5", async () => {
    const done = await complete(), stub = env.ROOMS_V2.getByName(done.room.room_id);
    const fork = value(await stub.fork(done.host.player_id, { base_revision: done.room.revision, branch: 0, stage_index: 1, idempotency_key: key() }));
    const a = value(await stub.commit(done.guest.player_id, turn(fork.room, seedA)));
    value(await stub.commit(done.host.player_id, turn(a.room, seedB, final)));
    await runInDurableObject(stub, async (_, ctx) => { const row = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one(); ctx.storage.sql.exec("UPDATE room SET data=?", JSON.stringify(JSON.parse(row.data), null, 2)); });
    const archive = value(await stub.exportSnapshot(source)), original = JSON.parse(archive) as RoomV2Archive, target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(original.payload).toMatchObject({ format_version: 5, database_schema_version: 3 });
    expect(await target.restoreSnapshot(archive, done.room.room_id)).toMatchObject({ ok: true }); await evictDurableObject(target);
    expect((JSON.parse(value(await target.exportSnapshot(source))) as RoomV2Archive).payload.tables).toEqual(original.payload.tables);
    expect(value(await target.operation(done.host.player_id, done.responses[0].receipt.idempotency_key)).receipt).toEqual(done.responses[0].receipt);
    expect(value(await target.collection(done.host.player_id)).pairs).toHaveLength(3);
    const old = structuredClone(original); old.payload.format_version = 4;
    expect(await env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()).restoreSnapshot(await signed(old), done.room.room_id)).toMatchObject({ ok: false, code: "unsupported_snapshot_format" });
    expect(await target.restoreSnapshot(archive, done.room.room_id)).toMatchObject({ ok: false, code: "snapshot_target_not_empty" });
  });
  it("roundtrips Player creation intents exactly and refuses malformed or downgraded archives", async () => {
    const host = await account(), room = await newRoom(host), player = env.PLAYERS.getByName(host.player_id);
    const archive = JSON.parse(value(await player.exportSnapshot(source))) as PortableSnapshot, target = env.PLAYERS.get(env.PLAYERS.newUniqueId());
    expect(await target.restoreSnapshot(await signed(archive), host.player_id)).toMatchObject({ ok: true });
    expect((JSON.parse(value(await target.exportSnapshot(source))) as PortableSnapshot).payload.tables).toEqual(archive.payload.tables);
    expect(value(await target.reserveChapterRoom(String(archive.payload.tables[2].rows[0].request_key), { room_id: "z".repeat(22), invite_code: "F".repeat(20), host: true, api_version: 2 }, descriptor)).link.room_id).toBe(room.room_id);
    const downgraded = structuredClone(archive); downgraded.payload.format_version = 2;
    expect(await env.PLAYERS.get(env.PLAYERS.newUniqueId()).restoreSnapshot(await signed(downgraded), host.player_id)).toMatchObject({ ok: false, code: "unsupported_snapshot_format" });
    const bad = structuredClone(archive), row = bad.payload.tables[2].rows[0], intent = JSON.parse(String(row.data)); intent.chapter.level_version = 99; row.data = JSON.stringify(intent);
    expect(await env.PLAYERS.get(env.PLAYERS.newUniqueId()).restoreSnapshot(await signed(bad), host.player_id)).toMatchObject({ ok: false });
  });
  it("retains accepted-turn photo ownership, retries, deletion and portable bytes in the new chapter", async () => {
    const { host, guest, room } = await pair(), accepted = await submit(room, host, liftA), stub = env.ROOMS_V2.getByName(room.room_id);
    const jpeg = new Uint8Array(encode({ width: 2, height: 2, data: new Uint8Array(16).fill(255) }, 50).data);
    const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", jpeg))].map(value => value.toString(16).padStart(2, "0")).join("");
    const upload = { idempotency_key: key(), recording_hash: liftA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, sha256: hash, jpeg_base64: btoa(String.fromCharCode(...jpeg)) };
    expect(await stub.updatePhoto(guest.player_id, "t0-0-a", upload)).toMatchObject({ ok: false, code: "turn_not_found" });
    const photo = value(await stub.updatePhoto(host.player_id, "t0-0-a", upload)); expect(value(await stub.updatePhoto(host.player_id, "t0-0-a", upload))).toEqual(photo);
    expect(value(await stub.snapshot(host.player_id))).toEqual(accepted.room);
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()); expect(await target.restoreSnapshot(value(await stub.exportSnapshot(source)), room.room_id)).toMatchObject({ ok: true });
    expect(await target.photo(guest.player_id, "t0-0-a")).toEqual(await stub.photo(guest.player_id, "t0-0-a"));
    expect((await call("/v1/identity", "DELETE", guest)).status).toBe(200);
    expect(await stub.photo(host.player_id, "t0-0-a")).toMatchObject({ ok: false }); expect(await stub.snapshot(host.player_id)).toMatchObject({ ok: false });
    const erased = JSON.parse(value(await stub.exportSnapshot(source))) as RoomV2Archive; expect(erased.payload.summary.state).toBe("deleted"); expect(erased.payload.tables.slice(1).every(table => table.rows.length === 0)).toBe(true);
    expect((await call("/v2/capabilities", "GET", host)).status).toBe(200);
  });
  it("keeps chapter ownership through credential rotation without reinterpreting recordings", async () => {
    const host = await account(), room = await newRoom(host), accepted = await submit(room, host, liftA);
    const next = { player_id: host.player_id, device_token: randomToken(32), recovery_code: randomToken(32) };
    const recover = { player_id: host.player_id, recovery_code: host.recovery_code, next_device_token: next.device_token, next_recovery_code: next.recovery_code, idempotency_key: key() };
    expect((await call("/v1/identity/recover", "POST", undefined, recover)).status).toBe(200);
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", host)).status).toBe(401);
    expect(await (await call(`/v2/rooms/${room.room_id}`, "GET", next)).json()).toEqual(accepted.room);
    expect((await call(`/v2/rooms/${room.room_id}/operations/${accepted.receipt.idempotency_key}`, "GET", next)).status).toBe(200);
  });
  it("rejects initialization after deletion wins the cross-object creation race", async () => {
    const host = await account(); let erased = false;
    const rooms = { getByName(name: string) { const stub = env.ROOMS_V2.getByName(name); return { async initialize(...args: Parameters<typeof stub.initialize>) {
      expect((await call("/v1/identity", "DELETE", host)).status).toBe(200); erased = true; return stub.initialize(...args);
    } }; } } as Env["ROOMS_V2"];
    const response = await call("/v2/rooms", "POST", host, { ...descriptor, idempotency_key: key() }, true, rooms);
    expect(erased).toBe(true); expect(response.status).toBe(410);
    expect((await call("/v2/rooms", "GET", host)).status).toBe(401);
  });
  it("holds unsupported stored chapter versions without pruning links or changing membership", async () => {
    const host = await account(), guest = await account(), room = await newRoom(host), stub = env.ROOMS_V2.getByName(room.room_id);
    const member = await account(); expect((await call("/v2/rooms/join", "POST", member, { invite_code: room.invite_code })).status).toBe(200);
    const before = await runInDurableObject(stub, async (_, ctx) => {
      const raw = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data); raw.level_version = 99;
      const data = JSON.stringify(raw); ctx.storage.sql.exec("UPDATE room SET data=?", data); return data;
    });
    expect(await stub.snapshot(host.player_id)).toMatchObject({ ok: false, status: 422, code: "unsupported_chapter" });
    expect((await call("/v2/rooms", "GET", host)).status).toBe(422); expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toHaveLength(1);
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(422);
    expect(await env.PLAYERS.getByName(guest.player_id).listRooms()).toEqual([]);
    expect((await call("/v2/rooms/join", "POST", member, { invite_code: room.invite_code })).status).toBe(422);
    expect(await env.PLAYERS.getByName(member.player_id).listRooms()).toHaveLength(1);
    expect(await runInDurableObject(stub, async (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data)).toBe(before);
  });
});
