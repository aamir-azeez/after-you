import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { TRANSFER_TTL, TRANSFER_MAX_BYTES, TRANSFER_MAX_OPERATIONS } from "../src/photo-transfer";
const key = () => crypto.randomUUID();
function value<T>(result: Outcome<T>): T { if (!result.ok) throw new Error(result.code); return result.value; }
type Account = { player_id: string; device_token: string; recovery_code: string };
let ip = 0;
async function call(path: string, method = "GET", owner?: Account, data?: unknown, settings: Partial<Env> = {}) {
  const configured = { ...env, ...settings }; Object.assign(configured, { PHOTO_TRANSFER_ENABLED: "true", ...settings });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + ++ip,
    ...(owner ? { "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token } : {}) }, body: data === undefined ? undefined : JSON.stringify(data) }), configured);
}
async function account() { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function setup() {
  const owner = await account(), transfer = env.PHOTO_TRANSFERS.getByName(owner.player_id), device = await digest(owner.device_token), sessionId = key();
  const session = value(await transfer.start(owner.player_id, device, { schema_version: 1, idempotency_key: sessionId }));
  return { owner, transfer, device, sessionId, session };
}
async function entry(owner: Account, id = "1".repeat(64)) {
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  return { entry_id: id, room_id: "R".repeat(22), turn_id: "t0-0-a", recording_hash: "a".repeat(64), photo_revision: 0, photo_owner: owner.player_id,
    local_only: true, sha256, width: 8, height: 8, byte_length: bytes.length, created_at: new Date().toISOString(), jpeg_base64: btoa(String.fromCharCode(...bytes)), deleted: false };
}
const body = (entries: unknown[]) => ({ schema_version: 1, idempotency_key: key(), entries });
afterEach(async () => { await reset(); });
describe("temporary owner photo transfer", () => {
  it("preserves exact bytes and visibility, inventory omits bytes, and durable restore ACK alone removes current entries", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), request = body([{ ...photo, deleted: true }]);
    const accepted = value(await transfer.upload(owner.player_id, device, sessionId, request));
    expect(accepted.receipt.request_hash).toBe(await digest(canonicalJson({ operation: "upload", session_id: sessionId, ...request })));
    expect(JSON.stringify(accepted)).not.toContain(photo.jpeg_base64);
    const inventory = value(await transfer.inventory(owner.player_id, device));
    expect(inventory.entry_count).toBe(1); expect(inventory.entries[0]).toMatchObject({ deleted: true, local_only: true, sha256: photo.sha256 }); expect(inventory.entries[0]).not.toHaveProperty("jpeg_base64");
    const read = value(await transfer.read(owner.player_id, device, { schema_version: 1, entry_ids: [photo.entry_id] }));
    expect(read.entries[0].jpeg_base64).toBe(photo.jpeg_base64);
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(1); // Fetch is never ACK.
    const ack = body(accepted.receipt.entries), removed = value(await transfer.acknowledge(owner.player_id, device, ack));
    expect(removed.receipt.request_hash).toBe(await digest(canonicalJson({ operation: "restore_ack", session_id: null, ...ack })));
    expect(value(await transfer.acknowledge(owner.player_id, device, ack))).toEqual(removed);
    expect(value(await transfer.operation(owner.player_id, device, request.idempotency_key))).toEqual(accepted);
    expect(value(await transfer.upload(owner.player_id, device, sessionId, request))).toEqual(accepted); // No resurrection.
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(0);
    expect(await transfer.read(owner.player_id, device, { schema_version: 1, entry_ids: [photo.entry_id] })).toMatchObject({ ok: false, status: 404 });
  });
  it("binds account/device after recovery and rejects wrong owner, stale credentials and arbitrary future schema", async () => {
    const { owner, transfer, device, sessionId } = await setup(), other = await account(), photo = await entry(owner);
    expect(await transfer.upload(other.player_id, await digest(other.device_token), sessionId, body([photo]))).toMatchObject({ ok: false, status: 403 });
    expect(await transfer.inventory(owner.player_id, "0".repeat(64))).toMatchObject({ ok: false, status: 401 });
    expect(await transfer.upload(owner.player_id, device, sessionId, { ...body([photo]), schema_version: 2 })).toMatchObject({ ok: false, code: "unsupported_transfer_version" });
    value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    const next = "n".repeat(43), recovery = "z".repeat(43);
    value(await env.PLAYERS.getByName(owner.player_id).recover(await digest(owner.recovery_code), await digest(next), await digest(recovery), "f".repeat(64)));
    expect(await transfer.inventory(owner.player_id, device)).toMatchObject({ ok: false, status: 401 });
    expect(value(await transfer.inventory(owner.player_id, await digest(next))).entry_count).toBe(1);
  });
  it("protects exact retry and same-ID replacement from stale restore ACK, atomically for the batch", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), first = body([photo]);
    const a = value(await transfer.upload(owner.player_id, device, sessionId, first));
    expect(await transfer.upload(owner.player_id, device, sessionId, { ...first, entries: [{ ...photo, deleted: true }] })).toMatchObject({ ok: false, code: "idempotency_key_reused" });
    const b = value(await transfer.upload(owner.player_id, device, sessionId, body([{ ...photo, deleted: true }])));
    expect(b.receipt.entries[0].entry_revision).toBeGreaterThan(a.receipt.entries[0].entry_revision);
    expect(await transfer.acknowledge(owner.player_id, device, body(a.receipt.entries))).toMatchObject({ ok: false, code: "stale_transfer_ack" });
    const bad = body([...b.receipt.entries, { entry_id: "f".repeat(64), sha256: photo.sha256, entry_revision: 1 }]);
    expect(await transfer.acknowledge(owner.player_id, device, bad)).toMatchObject({ ok: false, code: "stale_transfer_ack" });
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(1);
    value(await transfer.acknowledge(owner.player_id, device, body(b.receipt.entries)));
  });
  it("starts once24h, resumes same key, and deduplicates unchanged entries without new revision, expiry or write allowance", async () => {
    const { owner, transfer, device, sessionId, session } = await setup(), photo = await entry(owner);
    expect(value(await transfer.start(owner.player_id, device, { schema_version: 1, idempotency_key: sessionId }))).toEqual(session);
    expect(await transfer.start(owner.player_id, device, { schema_version: 1, idempotency_key: key() })).toMatchObject({ ok: false, status: 429, code: "transfer_cooldown" });
    const first = value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    const old = value(await transfer.inventory(owner.player_id, device)).entries[0];
    const second = value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    expect(second.receipt.entries).toEqual(first.receipt.entries); expect(value(await transfer.inventory(owner.player_id, device)).entries[0]).toEqual(old);
    await runInDurableObject(transfer, (_, ctx) => { expect(JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_control").one().data).accepted_writes).toBe(1); });
  });
  it("rejects bad framing/checksum/metadata, excess batch/bytes and duplicate IDs without storing partial entries", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner);
    for (const invalid of [{ ...photo, sha256: "0".repeat(64) }, { ...photo, width: 9 }, { ...photo, jpeg_base64: "bad" }, { ...photo, photo_owner: "X".repeat(22) }, { ...photo, created_at: "2026-09-15T00:00:00Z" }]) {
      expect(await transfer.upload(owner.player_id, device, sessionId, body([invalid]))).toMatchObject({ ok: false, status: 400 });
    }
    expect(await transfer.upload(owner.player_id, device, sessionId, body([photo, photo]))).toMatchObject({ ok: false, code: "duplicate_transfer_entry" });
    expect(await transfer.upload(owner.player_id, device, sessionId, body(Array(17).fill(photo)))).toMatchObject({ ok: false, code: "invalid_transfer_batch" });
    expect(await transfer.upload(owner.player_id, device, sessionId, body([{ ...photo, jpeg_base64: "A".repeat(1024 * 1024) }]))).toMatchObject({ ok: false, status: 413 });
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(0);
  });
  it("keeps newest1000 own entries, leaves other accounts intact and reports exact own evictions", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), other = await setup();
    const otherPhoto = await entry(other.owner); value(await other.transfer.upload(other.owner.player_id, other.device, other.sessionId, body([otherPhoto])));
    // Storage-level bounded capacity fixture, not1000 decoder calls.
    await runInDurableObject(transfer, (_, ctx) => {
      for (let i = 1; i <= 1000; i++) { const id = i.toString(16).padStart(64, "0"); ctx.storage.sql.exec("INSERT INTO transfer_entries VALUES (?,?)", id, JSON.stringify({ ...photo, entry_id: id, created_at: "2000-01-01T00:00:00.000Z", entry_revision: i, expires_at: new Date(Date.now() + TRANSFER_TTL).toISOString() })); }
    });
    const result = value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    expect(result.receipt.evicted_entry_ids).toHaveLength(1); expect(result.receipt.evicted_entry_ids).not.toContain(photo.entry_id);
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(1000);
    expect(value(await other.transfer.inventory(other.owner.player_id, other.device)).entry_count).toBe(1);
  });
  it("holds session/storage/history capacity while reserved cleanup receipts still permit ACK", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), accepted = value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    await runInDurableObject(transfer, (_, ctx) => {
      const c = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_control").one().data); c.accepted_writes = 1000; ctx.storage.sql.exec("UPDATE transfer_control SET data=?", JSON.stringify(c));
    });
    expect(await transfer.upload(owner.player_id, device, sessionId, body([{ ...photo, entry_id: "2".repeat(64) }]))).toMatchObject({ ok: false, code: "transfer_session_full" });
    expect(value(await transfer.upload(owner.player_id, device, sessionId, body([photo]))).receipt.entries).toEqual(accepted.receipt.entries);
    value(await transfer.acknowledge(owner.player_id, device, body(accepted.receipt.entries)));
  });
  it("expires entries without extending retries and deallocates the database before releasing its admission reservation", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner); value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    let token = "";
    await runInDurableObject(transfer, async (_, ctx) => {
      const c = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_control").one().data); token = c.reservation;
      c.session.expires_at = "2000-01-01T00:00:00.000Z"; ctx.storage.sql.exec("UPDATE transfer_control SET data=?", JSON.stringify(c));
      ctx.storage.sql.exec("UPDATE transfer_entries SET data=json_set(data,'$.expires_at','2000-01-01T00:00:00.000Z')"); ctx.storage.sql.exec("UPDATE transfer_operations SET expires_at=1");
      await ctx.storage.setAlarm(Date.now() + 86400000); // No real past alarm competes with deterministic cleanup.
    });
    expect(await transfer.expireReservation(owner.player_id, token)).toBe(true);
    await runInDurableObject(transfer, async (instance, ctx) => {
      expect(ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name LIKE 'transfer_%'").toArray()).toEqual([]);
      await instance.alarm(); // Lost-success alarm retry must neither fail nor recreate storage.
      expect(ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name LIKE 'transfer_%'").toArray()).toEqual([]);
    });
    const ledger = env.PHOTO_TRANSFER_BUDGET.getByName("photo-transfer-budget-v1");
    await runInDurableObject(ledger, (_, ctx) => { expect(ctx.storage.sql.exec("SELECT owner FROM reservations WHERE owner=?", owner.player_id).toArray()).toEqual([]); });
  });
  it("reserves single-item ACK receipts at the operation cap and rolls back rejected uploads", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), accepted = value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    await runInDurableObject(transfer, (_, ctx) => {
      for (let i = 1; i < TRANSFER_MAX_OPERATIONS - 1; i++) ctx.storage.sql.exec("INSERT INTO transfer_operations VALUES (?,?,?)", "synthetic-" + i, Date.now() + TRANSFER_TTL, "{}");
    });
    expect(await transfer.upload(owner.player_id, device, sessionId, body([{ ...photo, entry_id: "2".repeat(64) }]))).toMatchObject({ ok: false, code: "transfer_history_full" });
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(1);
    value(await transfer.acknowledge(owner.player_id, device, body(accepted.receipt.entries)));
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(0);
  });
  it("bounds new-key upload receipt spam without blocking exact retries or restore ACK", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), request = body([photo]);
    const accepted = value(await transfer.upload(owner.player_id, device, sessionId, request));
    await runInDurableObject(transfer, (_, ctx) => {
      const c = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_control").one().data); c.upload_operations = 256; ctx.storage.sql.exec("UPDATE transfer_control SET data=?", JSON.stringify(c));
    });
    expect(await transfer.upload(owner.player_id, device, sessionId, body([photo]))).toMatchObject({ ok: false, code: "transfer_session_request_limit" });
    expect(value(await transfer.upload(owner.player_id, device, sessionId, request))).toEqual(accepted);
    value(await transfer.acknowledge(owner.player_id, device, body(accepted.receipt.entries)));
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(0);
  });
  it("holds aggregate serialized capacity atomically while ACK still clears an existing image", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), accepted = value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    await runInDurableObject(transfer, (_, ctx) => {
      const used = ctx.storage.sql.exec<{ n: number }>("SELECT (SELECT SUM(LENGTH(CAST(data AS BLOB))) FROM transfer_entries)+(SELECT SUM(LENGTH(CAST(data AS BLOB))) FROM transfer_operations)+(SELECT SUM(LENGTH(CAST(data AS BLOB))) FROM transfer_control) AS n").one().n;
      let padding = TRANSFER_MAX_BYTES - used - 512 - 50, index = 0;
      // Explicit storage capacity injection. Each SQLite row stays below2MiB.
      while (padding > 0) { const size = Math.min(padding, 1024 * 1024); ctx.storage.sql.exec("INSERT INTO transfer_operations VALUES (?,?,?)", "synthetic-padding-" + index++, Date.now() + TRANSFER_TTL, " ".repeat(size)); padding -= size; }
    });
    expect(await transfer.upload(owner.player_id, device, sessionId, body([{ ...photo, deleted: true }]))).toMatchObject({ ok: false, code: "transfer_storage_full" });
    expect(value(await transfer.inventory(owner.player_id, device)).entries[0].deleted).toBe(false);
    value(await transfer.acknowledge(owner.player_id, device, body(accepted.receipt.entries)));
    expect(value(await transfer.inventory(owner.player_id, device)).entry_count).toBe(0);
  });
  it("retains unexpired lost-ACK receipts and reservation until their full14-day lifetime", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), accepted = value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    const ack = body(accepted.receipt.entries); const receipt = value(await transfer.acknowledge(owner.player_id, device, ack));
    let token = ""; await runInDurableObject(transfer, (_, ctx) => { const c = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_control").one().data); token = c.reservation; c.session.expires_at = "2000-01-01T00:00:00.000Z"; ctx.storage.sql.exec("UPDATE transfer_control SET data=?", JSON.stringify(c)); });
    expect(await transfer.expireReservation(owner.player_id, token)).toBe(false);
    expect(value(await transfer.operation(owner.player_id, device, ack.idempotency_key))).toEqual(receipt);
  });
  it("removes transfer bytes and reservations before confirmed identity deletion, without deleting another owner", async () => {
    const a = await setup(), b = await setup(), photo = await entry(a.owner); value(await a.transfer.upload(a.owner.player_id, a.device, a.sessionId, body([photo])));
    const response = await call("/v1/identity", "DELETE", a.owner); expect(response.status).toBe(200);
    expect(await a.transfer.inventory(a.owner.player_id, a.device)).toMatchObject({ ok: false, status: 401 });
    expect(value(await b.transfer.inventory(b.owner.player_id, b.device)).session?.session_id).toBe(b.sessionId);
    await runInDurableObject(a.transfer, (_, ctx) => { expect(ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name LIKE 'transfer_%'").toArray()).toEqual([]); });
  });
  it("keeps writes disabled by default, allows reads/cleanup with flagoff, and scopes upload/ACK rates independently", async () => {
    const { owner, transfer, device, sessionId } = await setup(), photo = await entry(owner), accepted = value(await transfer.upload(owner.player_id, device, sessionId, body([photo])));
    expect((await call("/v1/photo-transfer/sessions", "POST", owner, { schema_version: 1, idempotency_key: key() }, { PHOTO_TRANSFER_ENABLED: "false" })).status).toBe(503);
    expect((await call("/v1/photo-transfer", "GET", owner, undefined, { PHOTO_TRANSFER_ENABLED: "false" })).status).toBe(200);
    const blocked = { limit: async () => ({ success: false }) } as RateLimit;
    const read = await call("/v1/photo-transfer/read", "POST", owner, { schema_version: 1, entry_ids: [photo.entry_id] }, { PHOTO_TRANSFER_LIMITER: blocked }); expect(read.status).toBe(429); expect(read.headers.get("Retry-After")).toBe("60");
    const ack = await call("/v1/photo-transfer/restore-ack", "POST", owner, body(accepted.receipt.entries), { PHOTO_TRANSFER_LIMITER: blocked, PHOTO_TRANSFER_ENABLED: "false" }); expect(ack.status).toBe(200);
  });
  it("fails admission daily/total capacity closed without evicting existing reservations", async () => {
    const ledger = env.PHOTO_TRANSFER_BUDGET.getByName("photo-transfer-budget-v1"), owner = "X".repeat(22);
    value(await ledger.reserve(owner, key(), key()));
    await runInDurableObject(ledger, (_, ctx) => { ctx.storage.sql.exec("UPDATE admissions SET count=24"); });
    expect(await ledger.reserve("Y".repeat(22), key(), key())).toMatchObject({ ok: false, code: "transfer_daily_capacity" });
    await runInDurableObject(ledger, (_, ctx) => {
      ctx.storage.sql.exec("UPDATE admissions SET count=0");
      for (let i = 0; i < 63; i++) ctx.storage.sql.exec("INSERT INTO reservations VALUES (?,?,?,?)", i.toString(16).padStart(22, "0"), key(), Date.now() + TRANSFER_TTL, key());
    });
    expect(await ledger.reserve("Y".repeat(22), key(), key())).toMatchObject({ ok: false, code: "transfer_service_full" });
    await runInDurableObject(ledger, (_, ctx) => { expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM reservations").one().n).toBe(64); });
  });
});
