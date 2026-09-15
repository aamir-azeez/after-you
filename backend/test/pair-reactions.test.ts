import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { RELAY_KEY } from "../src/v2/protocol";
import { adapter } from "../src/v2/protocol-first-steps";
import type { RoomSnapshotV2, MutationV2 } from "../src/v2/room";
import type { PairReactions, ReactionMutation } from "../src/v2/reactions";
import type { RoomV2Archive } from "../src/v2/snapshot";
import relayA from "../../game/tests/fixtures/v2/relay-a.json";
import relayB from "../../game/tests/fixtures/v2/relay-b.json";
import relayCheckpoint from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import liftA from "../../game/tests/fixtures/first_steps/a-little-lift-a.json";
import liftB from "../../game/tests/fixtures/first_steps/a-little-lift-b.json";
import liftCheckpoint from "../../game/tests/fixtures/first_steps/lift-checkpoint.json";
import seedA from "../../game/tests/fixtures/first_steps/a-place-to-grow-a.json";

const HOST = "H".repeat(22), GUEST = "G".repeat(22), ROOM = "R".repeat(22), INVITE = "AB".repeat(10), SOURCE = "e".repeat(40);
const key = () => crypto.randomUUID();
const stub = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
type Stub = ReturnType<typeof stub>;
function value<T>(result: Outcome<T>): T { if (!result.ok) throw new Error(result.code); return result.value; }
function body(a: { recording_hash: string } = liftA, b: { recording_hash: string } = liftB, reaction = "love", expected = 0, idempotency_key = key()) {
  return { idempotency_key, a_hash: a.recording_hash, b_hash: b.recording_hash, expected_reaction_revision: expected, reaction };
}
async function setup(firstSteps = true) {
  const room = stub(), a = firstSteps ? liftA : relayA, b = firstSteps ? liftB : relayB, checkpoint = firstSteps ? liftCheckpoint : relayCheckpoint;
  value(await room.initialize(ROOM, HOST, INVITE, firstSteps ? adapter.key : RELAY_KEY));
  let state = value(await room.join(GUEST, INVITE));
  state = value(await room.commit(HOST, { base_revision: state.revision, branch: 0, idempotency_key: key(), recording: a })).room;
  const accepted = value(await room.commit(GUEST, { base_revision: state.revision, branch: 0, idempotency_key: key(), recording: b, checkpoint }));
  return { room, state: value(await room.snapshot(HOST)), a, b, accepted };
}
async function exported(room: Stub): Promise<RoomV2Archive> { return JSON.parse(value(await room.exportSnapshot(SOURCE))) as RoomV2Archive; }
async function encoded(archive: RoomV2Archive): Promise<string> { archive.checksum.value = await digest(canonicalJson(archive.payload)); return canonicalJson(archive); }
type Account = { player_id: string; device_token: string; recovery_code: string };
let ip = 0;
async function call(path: string, method = "GET", owner?: Account, data?: unknown, enabled = true, presets = true): Promise<Response> {
  const configured = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: String(enabled), FIRST_STEPS_ENABLED: "true", PRESET_REACTIONS_ENABLED: String(presets) });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + ++ip,
    ...(owner ? { "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token } : {}) }, body: data === undefined ? undefined : JSON.stringify(data) }), configured);
}
async function account(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
afterEach(async () => { await reset(); });

describe("completed chapter pair preset reactions", () => {
  it("keeps unused Relay and First Steps room snapshots and archive formats unchanged", async () => {
    for (const firstSteps of [false, true]) {
      const { room, state } = await setup(firstSteps), before = await exported(room);
      expect(before.payload).toMatchObject({ format_version: firstSteps ? 5 : 4, database_schema_version: 3 });
      expect(value(await room.reactions(GUEST, "p0-0")).reactions).toEqual([]);
      expect(await room.react(GUEST, "p0-0", { ...body(), reaction: "arbitrary message" })).toMatchObject({ ok: false, status: 400 });
      expect((await exported(room)).payload.tables).toEqual(before.payload.tables);
      expect(value(await room.snapshot(HOST))).toEqual(state);
      const target = stub(); expect(await target.restoreSnapshot(await encoded(before), ROOM)).toMatchObject({ ok: true });
      expect((await exported(target)).payload).toMatchObject({ format_version: firstSteps ? 5 : 4, database_schema_version: 3 });
    }
  });
  it("shows both members' concurrent presets with independent revisions and no gameplay/photo/alarm changes", async () => {
    for (const firstSteps of [false, true]) {
      const { room, state, a, b, accepted } = await setup(firstSteps), before = await exported(room);
      const [host, guest] = await Promise.all([room.react(HOST, "p0-0", body(a, b)), room.react(GUEST, "p0-0", body(a, b, "sparkles"))]);
      expect(value(host).receipt.reaction_revision).toBe(1); expect(value(guest).receipt.reaction_revision).toBe(1);
      expect(value(await room.reactions(GUEST, "p0-0")).reactions).toMatchObject([{ player_id: HOST, reaction: "love", reaction_revision: 1 }, { player_id: GUEST, reaction: "sparkles", reaction_revision: 1 }]);
      expect(value(await room.snapshot(HOST))).toEqual(state);
      expect(value(await room.operation(GUEST, accepted.receipt.idempotency_key)).receipt).toEqual(accepted.receipt);
      const after = await exported(room); expect(after.payload).toMatchObject({ format_version: 6, database_schema_version: 4 });
      expect(after.payload.tables.slice(0, 6)).toEqual(before.payload.tables);
      await runInDurableObject(room, async (_, ctx) => { expect(await ctx.storage.getAlarm()).toBeNull(); expect(ctx.storage.sql.exec("SELECT * FROM notification_outbox").toArray()).toEqual([]); });
    }
  });
  it("reconciles lost acknowledgements after replacement, stage advance and fork without overwriting the newer preset", async () => {
    const { room, state } = await setup(), first = body(); await room.react(HOST, "p0-0", first);
    const accepted = value(await room.reactionOperation(HOST, first.idempotency_key));
    const second = body(liftA, liftB, "again", 1); value(await room.react(HOST, "p0-0", second));
    const next = value(await room.commit(GUEST, { base_revision: state.revision, branch: 0, idempotency_key: key(), recording: seedA }));
    value(await room.fork(HOST, { base_revision: next.room.revision, branch: 0, stage_index: 0, idempotency_key: key() }));
    const retry = value(await room.react(HOST, "p0-0", first));
    expect(retry.receipt).toEqual(accepted.receipt); expect(retry.state.reactions[0]).toMatchObject({ reaction: "again", reaction_revision: 2 });
    expect(await room.react(HOST, "p0-0", { ...first, reaction: "sparkles" })).toMatchObject({ ok: false, code: "idempotency_key_reused" });
    expect(await room.reactionOperation(GUEST, first.idempotency_key)).toMatchObject({ ok: false, status: 404 });
  });
  it("rejects outsiders, incomplete or substituted pairs, own stale writes and unsupported presets", async () => {
    const { room } = await setup(), initial = body();
    expect(await room.reactions("X".repeat(22), "p0-0")).toMatchObject({ ok: false, status: 404 });
    expect(await room.react("X".repeat(22), "p0-0", initial)).toMatchObject({ ok: false, status: 404 });
    expect(await room.react(HOST, "p0-1", initial)).toMatchObject({ ok: false, code: "pair_not_found" });
    expect(await room.react(HOST, "p0-0", { ...initial, a_hash: "f".repeat(64) })).toMatchObject({ ok: false, code: "reaction_pair_mismatch" });
    for (const invalid of [{ ...initial, reaction: "hello" }, { ...initial, reaction: null }, { ...initial, text: "hello" }, { ...initial, expected_reaction_revision: -1 }, { ...initial, base_revision: 3 }]) expect(await room.react(HOST, "p0-0", invalid)).toMatchObject({ ok: false, status: 400 });
    value(await room.react(HOST, "p0-0", initial));
    expect(await room.react(HOST, "p0-0", body())).toMatchObject({ ok: false, code: "stale_reaction_revision" });
    expect(value(await room.react(GUEST, "p0-0", body())).receipt.reaction_revision).toBe(1);
  });
  it("holds full histories explicitly while an exact previously accepted retry still succeeds", async () => {
    const { room } = await setup(), initial = body(), saved = value(await room.react(HOST, "p0-0", initial));
    await runInDurableObject(room, async (_, ctx) => { for (let i = 1; i < 256; i++) ctx.storage.sql.exec("INSERT INTO reaction_operations VALUES (?,?,?)", "synthetic-capacity-" + i, "h", "{}"); });
    expect(await room.react(HOST, "p0-0", body(liftA, liftB, "again", 1))).toMatchObject({ ok: false, code: "reaction_history_full" });
    expect(value(await room.react(HOST, "p0-0", initial)).receipt).toEqual(saved.receipt);
    expect(value(await room.reactions(HOST, "p0-0")).reactions[0].reaction).toBe("love");
  });
  it("atomically rolls back the first schema migration and subsequent failed receipt writes", async () => {
    const { room } = await setup();
    await runInDurableObject(room, async (_, ctx) => { ctx.storage.sql.exec("CREATE TRIGGER fail_reaction_migration BEFORE UPDATE ON metadata BEGIN SELECT RAISE(ABORT,'synthetic_reaction_failure'); END"); });
    expect(await room.react(HOST, "p0-0", body())).toMatchObject({ ok: false, status: 500 });
    await runInDurableObject(room, async (_, ctx) => {
      expect(ctx.storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata").one().schema_version).toBe(3);
      expect(ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name='pair_reactions'").toArray()).toEqual([]);
      ctx.storage.sql.exec("DROP TRIGGER fail_reaction_migration");
    });
    value(await room.react(HOST, "p0-0", body())); const before = value(await room.reactions(HOST, "p0-0"));
    await runInDurableObject(room, async (_, ctx) => { ctx.storage.sql.exec("CREATE TRIGGER fail_reaction_receipt BEFORE INSERT ON reaction_operations BEGIN SELECT RAISE(ABORT,'synthetic_reaction_failure'); END"); });
    expect(await room.react(HOST, "p0-0", body(liftA, liftB, "again", 1))).toMatchObject({ ok: false, status: 500 });
    expect(value(await room.reactions(HOST, "p0-0"))).toEqual(before);
  });
  it("erases sidecars/receipts when either member deletes the room, including a hash-await race", async () => {
    const { room } = await setup(); value(await room.react(HOST, "p0-0", body()));
    await Promise.all([room.react(GUEST, "p0-0", body()), room.eraseForPlayer(HOST)]);
    expect(await room.reactions(GUEST, "p0-0")).toMatchObject({ ok: false, status: 404 });
    const archive = await exported(room); expect(archive.payload).toMatchObject({ format_version: 6, database_schema_version: 4, summary: { state: "deleted" } });
    expect(archive.payload.tables.slice(1).every(table => table.rows.length === 0)).toBe(true);
    const target = stub(); expect(await target.restoreSnapshot(await encoded(archive), null)).toMatchObject({ ok: true });
    expect(await target.initialize(ROOM, HOST, INVITE)).toMatchObject({ ok: false, code: "room_deleted" });
  });
});

describe("reaction portable archives", () => {
  it("roundtrips exact old/new raw rows, numeric row order and immutable receipts through eviction", async () => {
    const { room, state } = await setup(); let first: ReactionMutation | null = null;
    for (let revision = 0; revision < 12; revision++) { const result = value(await room.react(HOST, "p0-0", body(liftA, liftB, revision % 2 ? "again" : "love", revision))); first ??= result; }
    await runInDurableObject(room, async (_, ctx) => {
      const raw = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM pair_reactions").one().data;
      ctx.storage.sql.exec("UPDATE pair_reactions SET data=?", JSON.stringify(JSON.parse(raw), null, 2));
      ctx.storage.sql.exec("UPDATE reaction_operations SET rowid=9223372036854775806 WHERE rowid=12");
    });
    const archive = await exported(room), target = stub(); expect(archive.payload.tables[7].rows.at(-1)?.rowid).toBe("9223372036854775806");
    expect(await target.restoreSnapshot(await encoded(archive), ROOM)).toMatchObject({ ok: true }); await evictDurableObject(target);
    expect((await exported(target)).payload.tables).toEqual(archive.payload.tables); expect(value(await target.snapshot(HOST))).toEqual(state);
    expect(value(await target.reactionOperation(HOST, first!.receipt.idempotency_key)).receipt).toEqual(first!.receipt);
    expect(await target.restoreSnapshot(await encoded(archive), ROOM)).toMatchObject({ ok: false, code: "snapshot_target_not_empty" });
  });
  it("imports original schema2/format3 without creating reaction tables", async () => {
    const { room } = await setup(false), archive = await exported(room);
    archive.payload.format_version = 3; archive.payload.database_schema_version = 2; archive.payload.tables = archive.payload.tables.slice(0, 4);
    const target = stub(); expect(await target.restoreSnapshot(await encoded(archive), ROOM)).toMatchObject({ ok: true });
    expect((await exported(target)).payload).toMatchObject({ format_version: 4, database_schema_version: 3 });
    expect(value(await target.reactions(GUEST, "p0-0")).reactions).toEqual([]);
  });
  it("rejects downgraded, orphan, forged and missing-receipt archives without partial migration", async () => {
    const { room } = await setup(); value(await room.react(HOST, "p0-0", body())); const original = await exported(room);
    const changes: ((copy: RoomV2Archive) => void)[] = [
      copy => { copy.payload.format_version = 5; copy.payload.database_schema_version = 3; },
      copy => { copy.payload.tables[7].rows = []; },
      copy => { const row = copy.payload.tables[6].rows[0], data = JSON.parse(String(row.data)); data.b_hash = "f".repeat(64); row.data = JSON.stringify(data); },
      copy => { const row = copy.payload.tables[7].rows[0], receipt = JSON.parse(String(row.receipt)); receipt.reaction = "again"; row.receipt = JSON.stringify(receipt); },
      copy => { const row = copy.payload.tables[6].rows[0], data = JSON.parse(String(row.data)); data.player_id = "X".repeat(22); row.data = JSON.stringify(data); },
      copy => { copy.payload.tables[6].schema += " "; }
    ];
    for (const change of changes) {
      const copy = structuredClone(original); change(copy); const target = stub();
      expect(await target.restoreSnapshot(await encoded(copy), ROOM)).toMatchObject({ ok: false });
      expect((await exported(target)).payload).toMatchObject({ database_schema_version: 3, summary: { state: "empty" } });
    }
  });
});

describe("normal authenticated reaction routes", () => {
  it("requires two-member access, advertises capability, honors the mutation gate and deletes through identity erasure", async () => {
    const host = await account(), guest = await account(), outsider = await account();
    const created = await call("/v2/rooms", "POST", host, { ...adapter.key, idempotency_key: key() }); const room = await created.json<RoomSnapshotV2>();
    let state = await (await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).json<RoomSnapshotV2>();
    for (const [owner, recording, checkpoint] of [[host, liftA, undefined], [guest, liftB, liftCheckpoint]] as const) {
      const result = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, { base_revision: state.revision, branch: 0, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) }); expect(result.status).toBe(200); state = (await result.json<MutationV2>()).room;
    }
    const path = `/v2/rooms/${room.room_id}/reactions/p0-0`, input = body();
    expect((await call(path)).status).toBe(401); expect((await call(path, "GET", outsider)).status).toBe(404);
    expect((await (await call("/v2/capabilities", "GET", host)).json<{ preset_reactions_enabled: boolean }>()).preset_reactions_enabled).toBe(true);
    expect((await call(path, "POST", host, input, false)).status).toBe(503);
    const unchanged = await exported(env.ROOMS_V2.getByName(room.room_id));
    const disabled = await call(path, "POST", host, { invalid: "x".repeat(4097) }, true, false);
    expect(disabled.status).toBe(503); expect(await disabled.json()).toMatchObject({ error: { code: "preset_reactions_disabled" } });
    expect((await exported(env.ROOMS_V2.getByName(room.room_id))).payload).toMatchObject({ database_schema_version: 3 });
    expect((await exported(env.ROOMS_V2.getByName(room.room_id))).payload.tables).toEqual(unchanged.payload.tables);
    for (const [gameplay, presets] of [[false, true], [true, false], [false, false]]) {
      expect((await (await call("/v2/capabilities", "GET", host, undefined, gameplay, presets)).json<{ preset_reactions_enabled: boolean }>()).preset_reactions_enabled).toBe(false);
    }
    const result = await call(path, "POST", host, input); expect(result.status).toBe(200); const accepted = await result.json<ReactionMutation>();
    expect((await (await call(path, "GET", guest, undefined, true, false)).json<PairReactions>()).reactions[0].reaction).toBe("love");
    const operation = `/v2/rooms/${room.room_id}/reaction-operations/${input.idempotency_key}`;
    expect((await (await call(operation, "GET", host, undefined, true, false)).json<ReactionMutation>()).receipt).toEqual(accepted.receipt);
    expect((await call(operation, "GET", guest)).status).toBe(404);
    expect(await (await call(`/v2/rooms/${room.room_id}`, "GET", guest)).json()).toEqual({ ...state, player_slot: "p1" });
    expect((await call(path, "POST", host, { ...input, padding: "x".repeat(4096) })).status).toBe(413);
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    expect((await call(path, "GET", guest)).status).toBe(404);
    const deleted = await exported(env.ROOMS_V2.getByName(room.room_id)); expect(deleted.payload.tables.slice(1).every(table => table.rows.length === 0)).toBe(true);
  });
});
