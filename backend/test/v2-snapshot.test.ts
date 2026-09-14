import { env } from "cloudflare:workers";
import { reset, evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { MAX_ROOM_V2_ARCHIVE_BYTES, type RoomV2Archive } from "../src/v2/snapshot";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

const host = "A".repeat(22), guest = "B".repeat(22), roomId = "c".repeat(22), sourceCommit = "d".repeat(40), invite = "E".repeat(20);
const room = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
type Stub = ReturnType<typeof room>;
function unwrap<T>(result: Outcome<T>): T { if (!result.ok) throw new Error(result.code); return result.value; }
async function exported(stub: Stub): Promise<string> { return unwrap(await stub.exportSnapshot(sourceCommit)); }
async function encoded(archive: RoomV2Archive): Promise<string> { archive.checksum.value = await digest(canonicalJson(archive.payload)); return canonicalJson(archive); }
const parsed = (value: string): RoomV2Archive => JSON.parse(value) as RoomV2Archive;
async function begin() { const stub = room(); unwrap(await stub.initialize(roomId, host, invite)); const state = unwrap(await stub.join(guest, invite)); return { stub, state }; }
async function submit(stub: Stub, state: RoomSnapshotV2, owner: string, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  return unwrap(await stub.commit(owner, { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) }));
}
async function completed() {
  const { stub, state } = await begin();
  const a = await submit(stub, state, host, firstA), b = await submit(stub, a.room, guest, firstB, middle);
  const c = await submit(stub, b.room, guest, secondA), d = await submit(stub, c.room, host, secondB, final);
  return { stub, state: d.room, receipts: [a.receipt, b.receipt, c.receipt, d.receipt] };
}
afterEach(async () => { await reset(); });

describe("RoomV2 binding-only portable archives", () => {
  it("keeps numeric SQLite row order after every replay table exceeds nine rows", async () => {
    const { stub, state: initial } = await completed(); let state = initial;
    for (let branch = 1; branch < 6; branch++) {
      state = unwrap(await stub.fork(host, { base_revision: state.revision, branch: state.branch, stage_index: 0, idempotency_key: crypto.randomUUID() })).room;
      state = (await submit(stub, state, host, firstA)).room;
      state = (await submit(stub, state, guest, firstB, middle)).room;
      state = (await submit(stub, state, guest, secondA)).room;
      state = (await submit(stub, state, host, secondB, final)).room;
    }
    const serialized = await exported(stub), archive = parsed(serialized), target = room();
    for (const name of ["turns", "pairs", "operations"]) {
      const rows = archive.payload.tables.find(table => table.name === name)!.rows;
      expect(rows.length).toBeGreaterThan(9);
      expect(rows.map(row => row.rowid)).toEqual(rows.map((_, index) => String(index + 1)));
    }
    expect(await target.restoreSnapshot(serialized, roomId)).toMatchObject({ ok: true });
    expect(parsed(await exported(target)).payload.tables).toEqual(archive.payload.tables);
    expect(unwrap(await target.snapshot(host))).toEqual(state);
  });
  it("restores both pairs, retained receipt retries and exact raw row bytes across eviction", async () => {
    const { stub, state, receipts } = await completed();
    await runInDurableObject(stub, async (_, ctx) => {
      const raw = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data;
      ctx.storage.sql.exec("UPDATE room SET data=?", JSON.stringify(JSON.parse(raw), null, 2));
      ctx.storage.sql.exec("UPDATE operations SET rowid=CAST(? AS INTEGER) WHERE rowid=4", "9223372036854775806");
    });
    const archive = await exported(stub), original = parsed(archive), target = room();
    expect(original.payload.summary).toEqual({ state: "active", revision: 5, branch: 0 });
    expect(original.payload.tables[0].rows[0].data).toContain("\n");
    expect(original.payload.tables[3].rows[3].rowid).toBe("9223372036854775806");
    expect(await target.restoreSnapshot(archive, roomId)).toMatchObject({ ok: true });
    await evictDurableObject(target);
    const restored = parsed(await exported(target));
    expect(restored.payload.tables).toEqual(original.payload.tables);
    expect(unwrap(await target.snapshot(host))).toEqual(state);
    expect(unwrap(await target.pairRecording(guest, "p0-0"))).toMatchObject({ a: firstA, b: firstB, checkpoint: middle });
    expect(unwrap(await target.operation(host, receipts[0].idempotency_key))).toEqual({ receipt: receipts[0], room: state });
  });
  it("keeps historical pairs and fork receipts when a stage is replaced", async () => {
    const { stub, state, receipts } = await completed();
    const fork = unwrap(await stub.fork(host, { base_revision: state.revision, branch: state.branch, stage_index: 1, idempotency_key: crypto.randomUUID() }));
    const a = await submit(stub, fork.room, guest, secondA), b = await submit(stub, a.room, host, secondB, final);
    const target = room(); expect(await target.restoreSnapshot(await exported(stub), roomId)).toMatchObject({ ok: true });
    expect(unwrap(await target.snapshot(host))).toEqual(b.room);
    expect(unwrap(await target.collection(host)).pairs).toHaveLength(3);
    expect(unwrap(await target.operation(host, receipts[3].idempotency_key)).receipt).toEqual(receipts[3]);
    expect(unwrap(await target.operation(host, fork.receipt.idempotency_key)).receipt).toEqual(fork.receipt);
    const reset = unwrap(await target.fork(guest, { base_revision: b.room.revision, branch: b.room.branch, stage_index: 0, idempotency_key: crypto.randomUUID() }));
    const emptyAttemptTarget = room(); expect(await emptyAttemptTarget.restoreSnapshot(await exported(target), roomId)).toMatchObject({ ok: true });
    expect(unwrap(await emptyAttemptTarget.snapshot(guest))).toEqual(reset.room);
  });
  it("retains a host contribution made before the guest joined", async () => {
    const source = room(), state = unwrap(await source.initialize(roomId, host, invite));
    const a = await submit(source, state, host, firstA), target = room();
    expect(await target.restoreSnapshot(await exported(source), roomId)).toMatchObject({ ok: true });
    expect(unwrap(await target.snapshot(host))).toEqual(a.room);
    expect(unwrap(await target.join(guest, invite))).toMatchObject({ active_role: "b", recording_a: firstA });
  });
  it("preserves empty and deleted states without resurrecting a room", async () => {
    const empty = room(), emptyTarget = room();
    expect(await emptyTarget.restoreSnapshot(await exported(empty), null)).toMatchObject({ ok: true });
    const { stub } = await begin(); expect(await stub.eraseForPlayer(host)).toMatchObject({ ok: true });
    const target = room(); expect(await target.restoreSnapshot(await exported(stub), null)).toMatchObject({ ok: true });
    expect(await target.initialize(roomId, host, invite)).toMatchObject({ ok: false, code: "room_deleted" });
  });
  it("rejects a hidden current-branch A instead of restoring a duplicate-insert trap", async () => {
    const { stub, state } = await begin(); await submit(stub, state, host, firstA);
    const archive = parsed(await exported(stub));
    const stored = JSON.parse(String(archive.payload.tables[0].rows[0].data));
    stored.a_turn_id = null; archive.payload.tables[0].rows[0].data = JSON.stringify(stored);
    const target = room(); expect(await target.restoreSnapshot(await encoded(archive), roomId)).toMatchObject({ ok: false });
    expect(parsed(await exported(target)).payload.summary.state).toBe("empty");
  });
  it("rejects wrong identities, changed checksums and nonempty targets without modifying rows", async () => {
    const { stub } = await completed(), archive = await exported(stub), target = room();
    expect(await target.restoreSnapshot(archive, "Z".repeat(22))).toMatchObject({ ok: false, code: "snapshot_identity_mismatch" });
    const changed = parsed(archive); changed.payload.source_commit = "a".repeat(40);
    expect(await target.restoreSnapshot(canonicalJson(changed), roomId)).toMatchObject({ ok: false, code: "snapshot_checksum_mismatch" });
    expect(await target.restoreSnapshot(archive, roomId)).toMatchObject({ ok: true });
    const before = parsed(await exported(target)).payload.tables;
    expect(await target.restoreSnapshot(archive, roomId)).toMatchObject({ ok: false, code: "snapshot_target_not_empty" });
    expect(parsed(await exported(target)).payload.tables).toEqual(before);
  });
  it("never overwrites a room initialized while archive validation is awaiting hashes", async () => {
    const { stub } = await completed(), archive = await exported(stub), target = room();
    const [restored, initialized] = await Promise.all([target.restoreSnapshot(archive, roomId), target.initialize("z".repeat(22), guest, invite)]);
    const state = unwrap(await target.snapshot(guest));
    if (restored.ok) { expect(initialized).toMatchObject({ ok: false }); expect(state).toMatchObject({ room_id: roomId, revision: 5, stage_index: 2 }); }
    else { expect(restored.code).toBe("snapshot_target_not_empty"); expect(initialized.ok).toBe(true); expect(state).toMatchObject({ room_id: "z".repeat(22), revision: 0, guest_id: null }); expect(unwrap(await target.collection(guest)).pairs).toEqual([]); }
  });
  it("rejects malformed and missing lineage/receipt rows even when the envelope is rehashed", async () => {
    const { stub } = await completed(), archive = parsed(await exported(stub));
    const variants: RoomV2Archive[] = [];
    let change = structuredClone(archive); change.payload.tables[3].rows.pop(); variants.push(change);
    change = structuredClone(archive); change.payload.tables[2].rows.shift(); variants.push(change);
    change = structuredClone(archive); change.payload.tables[1].rows[0].player_id = guest; variants.push(change);
    change = structuredClone(archive); change.payload.tables[0].schema = "CREATE TABLE evil (secret TEXT)"; variants.push(change);
    change = structuredClone(archive); change.payload.tables[0].rows[0].data = String(change.payload.tables[0].rows[0].data).replace('"revision":5', '"revision":5,"revision":5'); variants.push(change);
    for (const variant of variants) {
      const target = room(); expect(await target.restoreSnapshot(await encoded(variant), roomId)).toMatchObject({ ok: false });
      expect(parsed(await exported(target)).payload.summary.state).toBe("empty");
    }
  });
  it("rejects unexpected tables, hidden KV and alarms without silently dropping them", async () => {
    for (const extra of ["table", "kv", "alarm"] as const) {
      const { stub } = await begin();
      await runInDurableObject(stub, async (_, ctx) => {
        if (extra === "table") ctx.storage.sql.exec("CREATE TABLE surprise (value TEXT)");
        if (extra === "kv") ctx.storage.kv.put("extra", "retained");
        if (extra === "alarm") await ctx.storage.setAlarm(Date.now() + 3600000);
      });
      expect(await stub.exportSnapshot(sourceCommit)).toMatchObject({ ok: false, code: `unsupported_storage_${extra === "table" ? "schema" : extra}` });
    }
  });
  it("bounds inputs and never exposes maintenance through normal HTTP routes", async () => {
    const target = room();
    expect(await target.restoreSnapshot(" ".repeat(MAX_ROOM_V2_ARCHIVE_BYTES + 1), null)).toMatchObject({ ok: false, code: "snapshot_too_large" });
    expect(await target.exportSnapshot("not-a-source-commit")).toMatchObject({ ok: false, code: "invalid_source_commit" });
    expect(await target.restoreSnapshot('['.repeat(40) + '0' + ']'.repeat(40), null)).toMatchObject({ ok: false, code: "snapshot_structure_limit" });
    // The public route dispatcher's operation allowlist has no archive method;
    // executable restore access is exclusively an authenticated Worker binding.
    const { routeV2 } = await import("../src/v2/routes");
    await expect(routeV2(new Request(`https://after-you.test/v2/rooms/${roomId}/restoreSnapshot`, { method: "POST", body: "{}" }), `/v2/rooms/${roomId}/restoreSnapshot`, host, env)).rejects.toMatchObject({ status: 404, code: "not_found" });
  });
});
