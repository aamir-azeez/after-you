import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { MAX_ROOM_V2_ARCHIVE_BYTES, MAX_ROW_BYTES } from "../src/v2/snapshot";
import { MAX_REPLAY_ARCHIVE_BYTES, factsForArchive, type ReplayArchive } from "../src/v2/replay-transfer";
import { ROOM_V2_TRANSFER_TABLES } from "../src/v2/storage-schema";
import { MAX_PHOTOS } from "../src/v2/photos";
import { MAX_PHOTO_BYTES } from "../src/v2/photo-image";
import { boundedTurnValue } from "../src/v2/protocol";
import { sleepingLighthouseV2, LIGHTHOUSE_LIMITS } from "../src/v2/protocol-lighthouse";
import chain from "../../game/tests/fixtures/lighthouse/v2-chain.json";

// sleeping-lighthouse@2 at its structural widest: all twelve records at the
// 600-tick turn, one action entry a tick in its widest form and the most replay
// checks. The worst room for a branch cap of B is B branches that each fork back
// to the start and play all six stages: any other fork adds a subset of that.
const TICKS = 600, HOST = "A".repeat(22), GUEST = "B".repeat(22), ROOM = "c".repeat(22), INVITE = "E".repeat(20), WHEN = "2026-10-13T00:00:00.000Z";
const SQLITE_ROW_LIMIT = 2_000_000, MAX_REPLAY_ARCHIVE_VALUES = 2_000_000, MAX_TURNS = 128, MAX_PAIRS = 64;
type Json = Record<string, any>;
const bytes = (value: unknown) => new TextEncoder().encode(typeof value === "string" ? value : canonicalJson(value)).byteLength;
const values = (value: unknown): number => 1 + (Array.isArray(value) || (value !== null && typeof value === "object") ? Object.values(value as object).reduce((sum: number, child) => sum + values(child), 0) : 0);
const depth = (value: unknown): number => Array.isArray(value) || (value !== null && typeof value === "object") ? 1 + Math.max(0, ...Object.values(value as object).map(depth)) : 0;

async function widest(record: Json, checkpointHash: string, sourceHash: string): Promise<Json> {
  const body = structuredClone(record); delete body.recording_hash;
  const checks = Math.floor(TICKS / 30) + 1;
  Object.assign(body, { duration_ticks: TICKS, checkpoint_hash: checkpointHash, source_recording_hash: sourceHash,
    actions: Array.from({ length: TICKS }, (_, index) => ({ action: false, ticks: 1, x: -100, z: index % 2 ? -100 : 100 })),
    replay_checks: Array.from({ length: checks }, (_, index) => ({ tick: TICKS - checks + 1 + index, state_hash: body.final_state_hash })) });
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}
async function proven(template: Json, previous: Json, a: Json, b: Json): Promise<Json> {
  const body = structuredClone(template); delete body.checkpoint_hash; delete body.proof;
  Object.assign(body, { previous_checkpoint_hash: previous.checkpoint_hash, a_recording_hash: a.recording_hash, b_recording_hash: b.recording_hash });
  return { ...body, checkpoint_hash: await digest(canonicalJson(body)), proof: { checkpoint: previous, a, b } };
}
type Stage = { a: Json; b: Json; checkpoint: Json };
let cached: Promise<Stage[]> | undefined;
function widestChain(): Promise<Stage[]> {
  cached ??= (async () => {
    const source = chain as Json, stages: Stage[] = [];
    let previous = source.checkpoints[0] as Json;
    for (const [index, pair] of (source.pairs as Json[]).entries()) {
      const a = await widest(pair.a, previous.checkpoint_hash, ""), b = await widest(pair.b, previous.checkpoint_hash, a.recording_hash);
      previous = await proven(source.checkpoints[index + 1], previous, a, b);
      stages.push({ a, b, checkpoint: previous });
    }
    return stages;
  })();
  return cached;
}
function roomState(stages: Stage[], branches: number): Json {
  return { schema_version: 2, room_id: ROOM, revision: 999, branch: branches - 1, stage_index: 6, ...sleepingLighthouseV2.key, host_id: HOST, guest_id: GUEST, checkpoint: stages[5].checkpoint,
    a_turn_id: null, completed_pair_ids: stages.map((_, stage) => `p${branches - 1}-${stage}`), invite_code: INVITE, invite_expires_at: WHEN, created_at: WHEN, updated_at: WHEN };
}
const pair = (stages: Stage[], branch: number, stage: number): Json => ({ pair_id: `p${branch}-${stage}`, branch, stage_index: stage, a: stages[stage].a, b: stages[stage].b, checkpoint: stages[stage].checkpoint });
function replayArchive(stages: Stage[], branches: number): ReplayArchive {
  const { invite_code: _invite, ...room } = roomState(stages, branches); void _invite;
  const turns: Json[] = [], pairs: Json[] = [];
  for (let branch = 0; branch < branches; branch++) {
    for (const [stage, value] of stages.entries()) {
      turns.push({ turn_id: `t${branch}-${stage}-a`, player_id: HOST, accepted_revision: 999, recording: value.a }, { turn_id: `t${branch}-${stage}-b`, player_id: GUEST, accepted_revision: 999, recording: value.b });
      pairs.push(pair(stages, branch, stage));
    }
  }
  return { schema_version: 1, room, turns, pairs } as unknown as ReplayArchive;
}
/** Row bytes the RoomV2 snapshot counts (as in tide-room-limits): the rows, a
 * full-size photo on every turn up to the photo cap, the replay manifest, and
 * 1 KiB for every row each small table may hold. */
function snapshotRowBytes(stages: Stage[], branches: number): number {
  let rowid = 0;
  const row = (value: Json) => bytes({ rowid: String(++rowid), ...value });
  const archive = replayArchive(stages, branches);
  let total = row({ id: 1, data: JSON.stringify(roomState(stages, branches)) });
  for (const turn of archive.turns) total += row({ turn_id: turn.turn_id, player_id: turn.player_id, accepted_revision: turn.accepted_revision, data: JSON.stringify(turn.recording) });
  for (const value of archive.pairs) total += row({ pair_id: value.pair_id, data: JSON.stringify(value) });
  const photo = row({ turn_id: "t31-5-b", data: JSON.stringify({ schema_version: 1, turn_id: "t31-5-b", owner_player_id: HOST, recording_hash: "f".repeat(64), photo_revision: 256, sha256: "f".repeat(64),
    width: 960, height: 960, byte_length: MAX_PHOTO_BYTES, jpeg_base64: "A".repeat(Math.ceil(MAX_PHOTO_BYTES / 3) * 4), updated_at: WHEN }) });
  total += Math.min(MAX_PHOTOS, archive.turns.length) * photo;
  total += row({ id: 1, data: JSON.stringify({ schema_version: 1, manifest: factsForArchive(archive, 999, "f".repeat(64)), acked_player_ids: [HOST, GUEST], transferred: false }) });
  for (const table of ROOM_V2_TRANSFER_TABLES) if (["operations", "photo_operations", "pair_reactions", "reaction_operations", "photo_delivery"].includes(table.name)) total += table.maxRows * 1024;
  return total;
}

describe("sleeping-lighthouse@2 room sizes", () => {
  it("keeps the widest checkpoint, receiver body and stored rows inside the chapter's bounds", async () => {
    const stages = await widestChain(), final = stages[5].checkpoint;
    expect(bytes(final)).toBeLessThanOrEqual(LIGHTHOUSE_LIMITS.checkpoint_bytes); expect(values(final)).toBeLessThanOrEqual(LIGHTHOUSE_LIMITS.checkpoint_values);
    const body = { base_revision: 999, idempotency_key: "k".repeat(80), branch: 31, recording: stages[5].b, checkpoint: final };
    expect(() => boundedTurnValue(body, LIGHTHOUSE_LIMITS)).not.toThrow();
    expect(depth(body)).toBeLessThanOrEqual(16);
    const rows = [JSON.stringify(roomState(stages, 32)), JSON.stringify(pair(stages, 31, 5)), JSON.stringify(stages[5].b)].map(bytes);
    for (const size of rows) expect(size * 1.5).toBeLessThanOrEqual(MAX_ROW_BYTES);
    expect(MAX_ROW_BYTES).toBeLessThan(SQLITE_ROW_LIMIT);
  });

  it("caps the room's branches so the widest replay archive and room snapshot fit, and one more branch would not", async () => {
    const stages = await widestChain(), branches = sleepingLighthouseV2.max_branches!;
    expect(branches * 2 * stages.length + branches).toBeLessThanOrEqual(MAX_TURNS); expect(branches * stages.length).toBeLessThanOrEqual(MAX_PAIRS);
    const archive = replayArchive(stages, branches), limit = MAX_ROOM_V2_ARCHIVE_BYTES - 16 * 1024;
    console.log("LIGHTHOUSE widest archive", branches, "branches:", bytes(archive), "bytes,", values(archive), "values; snapshot rows", snapshotRowBytes(stages, branches),
      "; one more:", bytes(replayArchive(stages, branches + 1)), snapshotRowBytes(stages, branches + 1));
    expect(bytes(archive)).toBeLessThanOrEqual(MAX_REPLAY_ARCHIVE_BYTES);
    expect(values(archive)).toBeLessThanOrEqual(MAX_REPLAY_ARCHIVE_VALUES);
    expect(snapshotRowBytes(stages, branches)).toBeLessThanOrEqual(limit);
    const more = replayArchive(stages, branches + 1);
    expect(bytes(more) > MAX_REPLAY_ARCHIVE_BYTES || snapshotRowBytes(stages, branches + 1) > limit).toBe(true);
  });
});
