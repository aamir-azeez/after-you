import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { MAX_ROOM_V2_ARCHIVE_BYTES, MAX_ROW_BYTES, type RoomV2Archive } from "../src/v2/snapshot";
import { MAX_REPLAY_ARCHIVE_BYTES, factsForArchive, type ReplayArchive } from "../src/v2/replay-transfer";
import { ROOM_V2_TRANSFER_TABLES } from "../src/v2/storage-schema";
import { MAX_PHOTOS } from "../src/v2/photos";
import { MAX_PHOTO_BYTES } from "../src/v2/photo-image";
import { turnOfTheTide } from "../src/v2/protocol-journey";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import initial from "../../game/tests/fixtures/journey/turn-of-the-tide-initial-checkpoint.json";
import setA from "../../game/tests/fixtures/journey/set-the-tide-a.json";
import setB from "../../game/tests/fixtures/journey/set-the-tide-b.json";
import middle from "../../game/tests/fixtures/journey/set-the-tide-checkpoint.json";
import seaLockA from "../../game/tests/fixtures/journey/slack-water-a.json";
import seaLockB from "../../game/tests/fixtures/journey/slack-water-b.json";
import seaLockFinal from "../../game/tests/fixtures/journey/slack-water-checkpoint.json";
import { TIDE_CHAINS } from "./turn-of-the-tide-chains";

// Turn of the Tide's owner-set turns: 2,700 ticks for A and 3,000 for B. The
// sizes below are structural, so they hold before and after the adapter
// reads those caps from its definition.
const TURNS = { a: 2700, b: 3000 };
const HOST = "A".repeat(22), GUEST = "B".repeat(22), ROOM = "c".repeat(22), INVITE = "E".repeat(20), WHEN = "2026-10-13T00:00:00.000Z";
const SQLITE_ROW_LIMIT = 2_000_000;
type Json = Record<string, any>;
type Chain = { a1: Json; b1: Json; cp1: Json; a2: Json; b2: Json; cp2: Json };
const bytes = (value: unknown) => new TextEncoder().encode(typeof value === "string" ? value : canonicalJson(value)).byteLength;
/** Every value in the tree, the root included, as replay-transfer.ts counts them. */
const values = (value: unknown): number => 1 + (Array.isArray(value) || (value !== null && typeof value === "object") ? Object.values(value as object).reduce((sum: number, child) => sum + values(child), 0) : 0);
/** replay-transfer.ts MAX_REPLAY_ARCHIVE_NODES, which the client's replay transfer also applies. */
const MAX_REPLAY_ARCHIVE_VALUES = 2_000_000;

/** `record` at `ticks` with one action entry a tick in its widest form and the
 * most replay checks, linked and rehashed. Only the structure is valid. */
async function widest(record: Json, ticks: number, checkpointHash: string, sourceHash: string): Promise<Json> {
  const body = structuredClone(record); delete body.recording_hash;
  const checks = Math.floor(ticks / 30) + 1;
  Object.assign(body, { duration_ticks: ticks, catch_assistance: false, checkpoint_hash: checkpointHash, source_recording_hash: sourceHash,
    actions: Array.from({ length: ticks }, (_, index) => ({ action: false, ticks: 1, x: -100, z: index % 2 ? -99 : -100 })),
    replay_checks: Array.from({ length: checks }, (_, index) => ({ tick: ticks - checks + 1 + index, state_hash: body.final_state_hash })) });
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}
async function proven(template: Json, previous: Json, a: Json, b: Json): Promise<Json> {
  const body = structuredClone(template); delete body.checkpoint_hash; delete body.proof;
  Object.assign(body, { previous_checkpoint_hash: previous.checkpoint_hash, a_recording_hash: a.recording_hash, b_recording_hash: b.recording_hash });
  return { ...body, checkpoint_hash: await digest(canonicalJson(body)), proof: { checkpoint: previous, a, b } };
}
let cached: Promise<Chain> | undefined;
/** The largest chain over every native way through both stages, widened. */
function widestChain(): Promise<Chain> {
  cached ??= (async () => {
    const ways: Json[][][] = [[[setA, setB, middle], [seaLockA, seaLockB, seaLockFinal]]];
    for (const chain of Object.values(TIDE_CHAINS)) for (const way of Object.values(chain.ways)) ways.push([chain.set as Json[], way as Json[]]);
    let result: Chain | undefined;
    for (const [one, two] of ways) {
      const a1 = await widest(one[0], TURNS.a, initial.checkpoint_hash, ""), b1 = await widest(one[1], TURNS.b, initial.checkpoint_hash, a1.recording_hash);
      const cp1 = await proven(one[2], initial, a1, b1);
      const a2 = await widest(two[0], TURNS.a, cp1.checkpoint_hash, ""), b2 = await widest(two[1], TURNS.b, cp1.checkpoint_hash, a2.recording_hash);
      const cp2 = await proven(two[2], cp1, a2, b2);
      if (!result || bytes(cp1) + bytes(cp2) > bytes(result.cp1) + bytes(result.cp2)) result = { a1, b1, cp1, a2, b2, cp2 };
    }
    return result!;
  })();
  return cached;
}
function roomState(chain: Chain, branches: number): Json {
  return { schema_version: 2, room_id: ROOM, revision: 999, branch: branches - 1, stage_index: 2, ...turnOfTheTide.key, host_id: HOST, guest_id: GUEST, checkpoint: chain.cp2,
    a_turn_id: null, completed_pair_ids: [`p${branches - 1}-0`, `p${branches - 1}-1`], invite_code: INVITE, invite_expires_at: WHEN, created_at: WHEN, updated_at: WHEN };
}
const pair = (chain: Chain, branch: number, stage: 0 | 1): Json => stage === 0
  ? { pair_id: `p${branch}-0`, branch, stage_index: 0, a: chain.a1, b: chain.b1, checkpoint: chain.cp1 }
  : { pair_id: `p${branch}-1`, branch, stage_index: 1, a: chain.a2, b: chain.b2, checkpoint: chain.cp2 };
/** Every branch forked back to the start and played through both stages. */
function replayArchive(chain: Chain, branches: number): ReplayArchive {
  const { invite_code: _invite, ...room } = roomState(chain, branches); void _invite;
  const turns: Json[] = [], pairs: Json[] = [];
  for (let branch = 0; branch < branches; branch++) {
    for (const [stage, role, recording] of [[0, "a", chain.a1], [0, "b", chain.b1], [1, "a", chain.a2], [1, "b", chain.b2]] as const)
      turns.push({ turn_id: `t${branch}-${stage}-${role}`, player_id: HOST, accepted_revision: 999, recording });
    pairs.push(pair(chain, branch, 0), pair(chain, branch, 1));
  }
  return { schema_version: 1, room, turns, pairs } as unknown as ReplayArchive;
}
/** Row bytes the RoomV2 snapshot counts: those branches, a full-size photo on
 * every turn, the replay manifest, and 1 KiB for every receipt, reaction and
 * delivery row each table may hold (the widest receipt is about 0.75 KB). */
async function snapshotRowBytes(chain: Chain, branches: number): Promise<number> {
  let rowid = 0;
  const row = (value: Json) => bytes({ rowid: String(++rowid), ...value });
  const archive = replayArchive(chain, branches);
  let total = row({ id: 1, data: JSON.stringify(roomState(chain, branches)) });
  for (const turn of archive.turns) total += row({ turn_id: turn.turn_id, player_id: turn.player_id, accepted_revision: turn.accepted_revision, data: JSON.stringify(turn.recording) });
  for (const value of archive.pairs) total += row({ pair_id: value.pair_id, data: JSON.stringify(value) });
  const photo = row({ turn_id: "t31-1-b", data: JSON.stringify({ schema_version: 1, turn_id: "t31-1-b", owner_player_id: HOST, recording_hash: "f".repeat(64), photo_revision: 256, sha256: "f".repeat(64),
    width: 960, height: 960, byte_length: MAX_PHOTO_BYTES, jpeg_base64: "A".repeat(Math.ceil(MAX_PHOTO_BYTES / 3) * 4), updated_at: WHEN }) });
  total += Math.min(MAX_PHOTOS, archive.turns.length) * photo;
  const manifest = factsForArchive(archive, 999, "f".repeat(64));
  total += row({ id: 1, data: JSON.stringify({ schema_version: 1, manifest, acked_player_ids: [HOST, GUEST], transferred: false }) });
  for (const table of ROOM_V2_TRANSFER_TABLES) if (SMALL_TABLES.includes(table.name)) total += table.maxRows * 1024;
  return total;
}
const SMALL_TABLES = ["operations", "photo_operations", "pair_reactions", "reaction_operations", "photo_delivery"];
/** The widest row of each small table, every field at its longest. */
function widestSmallRows(): number[] {
  const hash = "f".repeat(64), key = "k".repeat(80), rowid = "9223372036854775807", request = { request_key: `${HOST}:${key}`, request_hash: hash };
  const reaction = { schema_version: 1, pair_id: "p31-1", player_id: HOST, a_hash: hash, b_hash: hash, reaction_revision: 256, reaction: "sparkles" };
  return [
    { rowid, ...request, receipt: JSON.stringify({ schema_version: 2, room_id: ROOM, idempotency_key: key, request_hash: hash, operation: "turns", accepted_revision: 999, branch: 31, stage_index: 1,
      stage_id: "set-the-tide", turn_id: "t31-1-b", recording_hash: hash, pair_id: "p31-1", checkpoint_hash: hash }) },
    { rowid, ...request, receipt: JSON.stringify({ schema_version: 1, room_id: ROOM, idempotency_key: key, request_hash: hash, operation: "photo_upload", turn_id: "t31-1-b", recording_hash: hash, photo_revision: 256, photo_hash: hash }) },
    { rowid, reaction_key: `p31-1:${HOST}`, data: JSON.stringify(reaction) },
    { rowid, ...request, receipt: JSON.stringify({ ...reaction, room_id: ROOM, idempotency_key: key, request_hash: hash }) },
    { rowid, turn_id: "t31-1-b", data: JSON.stringify({ schema_version: 1, turn_id: "t31-1-b", recording_hash: hash, photo_revision: 256, sha256: hash, intended_player_ids: [HOST, GUEST], acked_player_ids: [HOST, GUEST], removed: false }) },
  ].map(bytes);
}

const room = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
type Stub = ReturnType<typeof room>;
function unwrap<T>(result: Outcome<T>): T { if (!result.ok) throw new Error(result.code); return result.value; }
async function commit(stub: Stub, state: RoomSnapshotV2, owner: string, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  return unwrap(await stub.commit(owner, { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) }));
}
async function seated(): Promise<{ stub: Stub; state: RoomSnapshotV2 }> {
  const stub = room(); unwrap(await stub.initialize(ROOM, HOST, INVITE, turnOfTheTide.key));
  return { stub, state: unwrap(await stub.join(GUEST, INVITE, [9])) };
}
/** Pads one stored row with trailing whitespace to exactly `size` bytes. */
async function pad(stub: Stub, table: "room" | "turns" | "pairs", key: string | number, size: number): Promise<void> {
  const column = table === "room" ? "id" : table === "turns" ? "turn_id" : "pair_id";
  await runInDurableObject(stub, async (_, ctx) => {
    const raw = ctx.storage.sql.exec<{ data: string }>(`SELECT data FROM ${table} WHERE ${column}=?`, key).one().data.trimEnd();
    expect(bytes(raw)).toBeLessThanOrEqual(size);
    ctx.storage.sql.exec(`UPDATE ${table} SET data=? WHERE ${column}=?`, raw + " ".repeat(size - bytes(raw)), key);
  });
}
const parsed = (value: string): RoomV2Archive => JSON.parse(value) as RoomV2Archive;
afterEach(async () => { await reset(); });

describe("Turn of the Tide room sizes", () => {
  it("bounds a stored row at 1.5 MiB: under the SQLite row limit, and 1.5x the widest tide room and pair rows", async () => {
    expect(MAX_ROW_BYTES).toBe(1_572_864);
    expect(MAX_ROW_BYTES).toBeLessThan(SQLITE_ROW_LIMIT);
    const chain = await widestChain();
    const roomRow = bytes(JSON.stringify(roomState(chain, 32))), pairRow = bytes(JSON.stringify(pair(chain, 31, 1)));
    const turnRow = Math.max(...[chain.a1, chain.b1, chain.a2, chain.b2].map(record => bytes(JSON.stringify(record))));
    expect(roomRow).toBeGreaterThan(512 * 1024); expect(pairRow).toBeGreaterThan(roomRow);
    for (const size of [roomRow, pairRow, turnRow]) expect(size * 1.5).toBeLessThanOrEqual(MAX_ROW_BYTES);
  });

  it("exports and restores a tide room whose rows reach the widest sizes and the bound, and refuses one byte more", async () => {
    const chain = await widestChain();
    let { stub, state } = await seated();
    state = (await commit(stub, state, HOST, setA)).room; state = (await commit(stub, state, GUEST, setB, middle)).room;
    state = (await commit(stub, state, GUEST, seaLockA)).room; state = (await commit(stub, state, HOST, seaLockB, seaLockFinal)).room;
    expect(state.stage_index).toBe(2);
    await pad(stub, "room", 1, bytes(JSON.stringify(roomState(chain, 32))));
    await pad(stub, "pairs", "p0-1", bytes(JSON.stringify(pair(chain, 31, 1))));
    await pad(stub, "turns", "t0-1-b", MAX_ROW_BYTES);
    const archive = unwrap(await stub.exportSnapshot("d".repeat(40))), target = room();
    expect(await target.restoreSnapshot(archive, ROOM)).toMatchObject({ ok: true });
    expect(parsed(unwrap(await target.exportSnapshot("d".repeat(40)))).payload.tables).toEqual(parsed(archive).payload.tables);
    expect(unwrap(await target.snapshot(HOST))).toEqual(state);
    expect(unwrap(await target.pairRecording(GUEST, "p0-1"))).toMatchObject({ a: seaLockA, b: seaLockB, checkpoint: seaLockFinal });
    // One byte over: export refuses it, and so does restore of a rehashed archive.
    const over = parsed(archive), turns = over.payload.tables.find(table => table.name === "turns")!;
    const row = turns.rows.find(value => value.turn_id === "t0-1-b")!; row.data = String(row.data) + " ";
    over.checksum.value = await digest(canonicalJson(over.payload));
    expect(await room().restoreSnapshot(canonicalJson(over), ROOM)).toMatchObject({ ok: false, code: "snapshot_too_large" });
    await pad(stub, "turns", "t0-1-b", MAX_ROW_BYTES + 1);
    expect(await stub.exportSnapshot("d".repeat(40))).toMatchObject({ ok: false, code: "snapshot_too_large" });
  });

  it("caps the tide at seven branches: the widest replay archive and room snapshot fit, and an eighth branch would not", async () => {
    expect(turnOfTheTide.max_branches).toBe(7);
    expect(Math.max(...widestSmallRows())).toBeLessThanOrEqual(1024);
    const chain = await widestChain(), branches = turnOfTheTide.max_branches!;
    const archive = bytes(replayArchive(chain, branches));
    expect(archive).toBeLessThanOrEqual(MAX_REPLAY_ARCHIVE_BYTES);
    expect(values(replayArchive(chain, branches))).toBeLessThanOrEqual(MAX_REPLAY_ARCHIVE_VALUES);
    // Some 16 KiB of envelope, table schemas and checksum ride on top of the rows.
    const limit = MAX_ROOM_V2_ARCHIVE_BYTES - 16 * 1024;
    expect(await snapshotRowBytes(chain, branches)).toBeLessThanOrEqual(limit);
    // Eight branches still fit the replay archive alone, but not the room snapshot.
    expect(bytes(replayArchive(chain, branches + 1))).toBeLessThanOrEqual(MAX_REPLAY_ARCHIVE_BYTES);
    expect(await snapshotRowBytes(chain, branches + 1)).toBeGreaterThan(limit);
    expect(bytes(replayArchive(chain, branches + 2))).toBeGreaterThan(MAX_REPLAY_ARCHIVE_BYTES);
  });

  it("lets a tide room fork six times, then reports its history full", async () => {
    let { stub, state } = await seated();
    for (let branch = 0; branch < 7; branch++) {
      state = (await commit(stub, state, HOST, setA)).room;
      const forked = await stub.fork(HOST, { base_revision: state.revision, branch: state.branch, stage_index: 0, idempotency_key: crypto.randomUUID() });
      if (branch < 6) state = unwrap(forked).room;
      else expect(forked).toMatchObject({ ok: false, code: "room_history_full" });
    }
    expect(state.branch).toBe(6);
  });
});
