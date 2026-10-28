import { ApiError, canonicalJson, digest } from "../protocol";
import type { ChapterKey } from "./chapter-types";
import { checkpointAt, nestedProof } from "./checkpoint-chain";
import type { CheckpointV2, RecordingV2 } from "./protocol";
import type { PairFacts, TurnFacts } from "./replay-transfer";
import type { PairV2 } from "./room";

/**
 * One finished attempt (branch) of a room as a single canonical blob. Its last
 * checkpoint nests every record of the attempt once; `rows` carries what lives
 * outside the checkpoint so the server can rebuild each row and prove it equal.
 */
export type AttemptBlob = ChapterKey & {
  format: "after-you.attempt"; format_version: 1; room_id: string; position: number; branch: number;
  checkpoint: CheckpointV2 | null; open_turn: RecordingV2 | null; rows: { turns: TurnFacts[]; pairs: PairFacts[] };
};
export type AttemptRoom = ChapterKey & { room_id: string };
export const ZERO_LINK = "0".repeat(64);
export const LINK_SCHEMA = "after-you.history.v1";
/** Largest blob accepted back; the widest real attempt is about 2.1 MB uncompressed (a Lighthouse branch). */
export const MAX_ATTEMPT_BYTES = 4 * 1024 * 1024;

const utf8 = (value: string) => new TextEncoder().encode(value);
export function isStub(data: string): boolean {
  const value = JSON.parse(data) as Record<string, unknown>;
  return Object.keys(value).length === 1 && "recording_hash" in value || "checkpoint" in value && Object.keys(value.checkpoint as object).length === 1;
}
const stageOf = (id: string) => Number(id.split("-")[1]);

/** Built from the attempt's rows, or null when any of them is already a stub (offloaded). */
export function attemptBlob(storage: DurableObjectStorage, room: AttemptRoom, branch: number): AttemptBlob | null {
  return blobFromRows(room, branch,
    storage.sql.exec<TurnRow>("SELECT turn_id,player_id,accepted_revision,data FROM turns WHERE turn_id LIKE ? ORDER BY rowid", `t${branch}-%`).toArray(),
    storage.sql.exec<PairRow>("SELECT pair_id,data FROM pairs WHERE pair_id LIKE ? ORDER BY rowid", `p${branch}-%`).toArray());
}
type TurnRow = { turn_id: string; player_id: string; accepted_revision: number; data: string };
type PairRow = { pair_id: string; data: string };
/** The same blob from rows in rowid order (an operator snapshot holds them as plain rows). */
export function blobFromRows(room: AttemptRoom, branch: number, allTurns: TurnRow[], allPairs: PairRow[]): AttemptBlob | null {
  const turnRows = allTurns.filter(row => row.turn_id.startsWith(`t${branch}-`)), pairRows = allPairs.filter(row => row.pair_id.startsWith(`p${branch}-`));
  if (turnRows.some(row => isStub(row.data)) || pairRows.some(row => isStub(row.data))) return null;
  const pairs = pairRows.map(row => JSON.parse(row.data) as PairV2).sort((a, b) => a.stage_index - b.stage_index);
  const recordings = new Map(turnRows.map(row => [row.turn_id, JSON.parse(row.data) as RecordingV2]));
  const checkpoint = pairs.at(-1)?.checkpoint ?? null;
  pairs.forEach((pair, index) => {
    const a = recordings.get(`t${branch}-${pair.stage_index}-a`), b = recordings.get(`t${branch}-${pair.stage_index}-b`);
    need(pair.branch === branch && (index === 0 || pair.stage_index === pairs[index - 1].stage_index + 1) && a && b);
    need(canonicalJson(checkpointAt(checkpoint!, pair.stage_index + 1)) === canonicalJson(pair.checkpoint));
    need(canonicalJson(pair.a) === canonicalJson(a) && canonicalJson(pair.b) === canonicalJson(b));
  });
  const paired = new Set(pairs.flatMap(pair => [`t${branch}-${pair.stage_index}-a`, `t${branch}-${pair.stage_index}-b`]));
  const open = turnRows.filter(row => !paired.has(row.turn_id));
  need(open.length <= 1 && open.every(row => row.turn_id.endsWith("-a") && (!pairs.length || stageOf(row.turn_id) === pairs.at(-1)!.stage_index + 1)));
  return { format: "after-you.attempt", format_version: 1, room_id: room.room_id, level_id: room.level_id, level_version: room.level_version, definition_hash: room.definition_hash,
    position: branch, branch, checkpoint, open_turn: open.length ? recordings.get(open[0].turn_id)! : null,
    rows: { turns: turnRows.map(row => ({ turn_id: row.turn_id, player_id: row.player_id, accepted_revision: row.accepted_revision, recording_hash: recordings.get(row.turn_id)!.recording_hash })),
      pairs: pairs.map(pair => ({ pair_id: pair.pair_id, branch: pair.branch, stage_index: pair.stage_index, a_hash: pair.a.recording_hash, b_hash: pair.b.recording_hash, checkpoint_hash: pair.checkpoint.checkpoint_hash })) } };
}
function need(value: unknown): asserts value { if (!value) throw new ApiError(500, "history_rows_inconsistent"); }

/** How far the attempt got: stages completed on its lineage, or the stage of its open first turn. */
export function lastStage(blob: AttemptBlob): number {
  if (blob.checkpoint) return blob.checkpoint.stage_index;
  return blob.open_turn ? stageOf(blob.rows.turns[0].turn_id) : 0;
}
export const blobBytes = (blob: AttemptBlob): Uint8Array => utf8(canonicalJson(blob));
/** Commits to the room, the chapter version, the attempt's place and every attempt before it. */
export function attemptLink(room: AttemptRoom, position: number, previous: string, attemptDigest: string, byteLength: number): Promise<string> {
  return digest(canonicalJson({ schema: LINK_SCHEMA, room_id: room.room_id, level_id: room.level_id, level_version: room.level_version, definition_hash: room.definition_hash,
    position, branch: position, previous, digest: attemptDigest, byte_length: byteLength }));
}

/** The pairs and turn rows an attempt's blob rebuilds, each checked against the blob's own hashes. */
export function attemptRows(blob: AttemptBlob): { pairs: Map<string, PairV2>; turns: Map<string, RecordingV2> } {
  const pairs = new Map<string, PairV2>(), turns = new Map<string, RecordingV2>();
  for (const facts of blob.rows.pairs) {
    const checkpoint = checkpointAt(blob.checkpoint!, facts.stage_index + 1), proof = nestedProof(checkpoint);
    need(proof && checkpoint.checkpoint_hash === facts.checkpoint_hash && proof.a.recording_hash === facts.a_hash && proof.b.recording_hash === facts.b_hash);
    pairs.set(facts.pair_id, { pair_id: facts.pair_id, branch: facts.branch, stage_index: facts.stage_index, a: proof.a, b: proof.b, checkpoint });
    turns.set(`t${facts.branch}-${facts.stage_index}-a`, proof.a); turns.set(`t${facts.branch}-${facts.stage_index}-b`, proof.b);
  }
  if (blob.open_turn) turns.set(blob.rows.turns.find(turn => !turns.has(turn.turn_id))!.turn_id, blob.open_turn);
  for (const facts of blob.rows.turns) need(turns.get(facts.turn_id)?.recording_hash === facts.recording_hash);
  need(turns.size === blob.rows.turns.length);
  return { pairs, turns };
}
