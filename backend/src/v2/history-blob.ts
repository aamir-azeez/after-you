import { ApiError, canonicalJson, digest } from "../protocol";
import type { ChapterKey } from "./chapter-types";
import { checkpointAt, nestedProof } from "./checkpoint-chain";
import { fingerprint, turnId, turnNumber } from "./open-turns";
import { chapter, type CheckpointV2, type RecordingV2 } from "./protocol";
import type { PairFacts, TurnFacts } from "./replay-transfer";
import type { PairV2 } from "./room";
import { parseRow, type RowData } from "./row-codec";

/**
 * One finished attempt (branch) of a room as a single canonical blob. Its last
 * checkpoint nests every record of the attempt once; `rows` carries what lives
 * outside the checkpoint so the server can rebuild each row and prove it equal.
 */
export type AttemptBlob = ChapterKey & {
  format: "after-you.attempt"; format_version: 1; room_id: string; position: number; branch: number;
  checkpoint: CheckpointV2 | null; open_turn: RecordingV2 | null; rows: { turns: TurnFacts[]; pairs: PairFacts[] };
} | OpenAttemptBlob;
/**
 * Open turns (open-turns.ts; claude-20261011/open-turns-fingerprints/WIRE.md): the checkpoints nest nothing, so the blob
 * lists each pair's checkpoint and every turn, each as its fingerprint whatever its row holds, so an attempt's bytes never
 * change once it is finished. The phones replay from their own copies.
 */
export type OpenAttemptBlob = ChapterKey & {
  format: "after-you.attempt"; format_version: 2; room_id: string; position: number; branch: number;
  checkpoint: CheckpointV2 | null; checkpoints: CheckpointV2[]; turns: RecordingV2[]; rows: { turns: TurnFacts[]; pairs: PairFacts[] };
};
const isOpenBlob = (blob: AttemptBlob): blob is OpenAttemptBlob => blob.format_version === 2;
export type AttemptRoom = ChapterKey & { room_id: string };
export const ZERO_LINK = "0".repeat(64);
export const LINK_SCHEMA = "after-you.history.v1";
/** Largest blob accepted back; the widest real attempt is about 2.1 MB uncompressed (a Lighthouse branch). */
export const MAX_ATTEMPT_BYTES = 4 * 1024 * 1024;

const utf8 = (value: string) => new TextEncoder().encode(value);
/** Stubs are always text (row-codec.ts); a deflated row is a full one. */
export function isStub(data: RowData): boolean {
  if (typeof data !== "string") return false;
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
type TurnRow = { turn_id: string; player_id: string; accepted_revision: number; data: RowData };
type PairRow = { pair_id: string; data: RowData };
/** The same blob from rows in rowid order (an operator snapshot holds them as plain rows). */
export function blobFromRows(room: AttemptRoom, branch: number, allTurns: TurnRow[], allPairs: PairRow[]): AttemptBlob | null {
  const turnRows = allTurns.filter(row => row.turn_id.startsWith(`t${branch}-`)), pairRows = allPairs.filter(row => row.pair_id.startsWith(`p${branch}-`));
  if (turnRows.some(row => isStub(row.data)) || pairRows.some(row => isStub(row.data))) return null;
  if (chapter(room).open_turns) return openBlobFromRows(room, branch, turnRows, pairRows);
  const pairs = pairRows.map(row => parseRow<PairV2>(row.data)).sort((a, b) => a.stage_index - b.stage_index);
  const recordings = new Map(turnRows.map(row => [row.turn_id, parseRow<RecordingV2>(row.data)]));
  const checkpoint = pairs.at(-1)?.checkpoint ?? null;
  // Each pair's turns, a and b.
  const paired = new Set<string>();
  pairs.forEach((pair, index) => {
    need(pair.branch === branch && (index === 0 || pair.stage_index === pairs[index - 1].stage_index + 1));
    need(canonicalJson(checkpointAt(checkpoint!, pair.stage_index + 1)) === canonicalJson(pair.checkpoint));
    const proof = nestedProof(pair.checkpoint); need(proof);
    proof.turns.forEach((turn, at) => {
      const id = turnId(branch, pair.stage_index, at + 1); need(canonicalJson(recordings.get(id)) === canonicalJson(turn)); paired.add(id);
    });
    need(canonicalJson(pair.a) === canonicalJson(proof.a) && canonicalJson(pair.b) === canonicalJson(proof.b));
  });
  // The open stage's first turn, one stage after the last pair.
  const open = turnRows.filter(row => !paired.has(row.turn_id)).sort((x, y) => turnNumber(x.turn_id) - turnNumber(y.turn_id));
  need(open.every((row, at) => turnNumber(row.turn_id) === at + 1 && stageOf(row.turn_id) === stageOf(open[0].turn_id) && (!pairs.length || stageOf(row.turn_id) === pairs.at(-1)!.stage_index + 1)));
  return { format: "after-you.attempt", format_version: 1, room_id: room.room_id, level_id: room.level_id, level_version: room.level_version, definition_hash: room.definition_hash,
    position: branch, branch, checkpoint, open_turn: open.length ? recordings.get(open[0].turn_id)! : null,
    rows: { turns: turnRows.map(row => ({ turn_id: row.turn_id, player_id: row.player_id, accepted_revision: row.accepted_revision, recording_hash: recordings.get(row.turn_id)!.recording_hash })),
      pairs: pairs.map(pair => ({ pair_id: pair.pair_id, branch: pair.branch, stage_index: pair.stage_index, a_hash: pair.a.recording_hash, b_hash: pair.b.recording_hash, checkpoint_hash: pair.checkpoint.checkpoint_hash })) } };
}
/** Open turns: each pair chains on the one before it and names its turns by hash; the turns after the last pair are one stage's, a on. */
function openBlobFromRows(room: AttemptRoom, branch: number, turnRows: TurnRow[], pairRows: PairRow[]): OpenAttemptBlob {
  const pairs = pairRows.map(row => parseRow<PairV2>(row.data)).sort((a, b) => a.stage_index - b.stage_index);
  const recordings = new Map(turnRows.map(row => [row.turn_id, fingerprint(parseRow<RecordingV2>(row.data))]));
  const paired = new Set<string>();
  pairs.forEach((pair, index) => {
    const hashes = pair.checkpoint.turn_hashes ?? [];
    need(pair.branch === branch && hashes.length >= 2 && (index === 0 || (pair.stage_index === pairs[index - 1].stage_index + 1 && pair.checkpoint.previous_checkpoint_hash === pairs[index - 1].checkpoint.checkpoint_hash)));
    hashes.forEach((hash, at) => { const id = turnId(branch, pair.stage_index, at + 1); need(recordings.get(id)?.recording_hash === hash); paired.add(id); });
    need(pair.a.recording_hash === hashes[0] && pair.b.recording_hash === hashes.at(-1));
  });
  const open = turnRows.filter(row => !paired.has(row.turn_id)).sort((x, y) => turnNumber(x.turn_id) - turnNumber(y.turn_id));
  need(open.every((row, at) => turnNumber(row.turn_id) === at + 1 && stageOf(row.turn_id) === stageOf(open[0].turn_id) && (!pairs.length || stageOf(row.turn_id) === pairs.at(-1)!.stage_index + 1)));
  return { format: "after-you.attempt", format_version: 2, room_id: room.room_id, level_id: room.level_id, level_version: room.level_version, definition_hash: room.definition_hash,
    position: branch, branch, checkpoint: pairs.at(-1)?.checkpoint ?? null, checkpoints: pairs.map(pair => pair.checkpoint), turns: turnRows.map(row => recordings.get(row.turn_id)!),
    rows: { turns: turnRows.map(row => ({ turn_id: row.turn_id, player_id: row.player_id, accepted_revision: row.accepted_revision, recording_hash: recordings.get(row.turn_id)!.recording_hash })),
      pairs: pairs.map(pair => ({ pair_id: pair.pair_id, branch: pair.branch, stage_index: pair.stage_index, a_hash: pair.a.recording_hash, b_hash: pair.b.recording_hash, checkpoint_hash: pair.checkpoint.checkpoint_hash })) } };
}
function need(value: unknown): asserts value { if (!value) throw new ApiError(500, "history_rows_inconsistent"); }

/** How far the attempt got: stages completed on its lineage, or the stage of its open first turn. */
export function lastStage(blob: AttemptBlob): number {
  if (blob.checkpoint) return blob.checkpoint.stage_index;
  return (isOpenBlob(blob) ? blob.turns.length : blob.open_turn) ? stageOf(blob.rows.turns[0].turn_id) : 0;
}
export const blobBytes = (blob: AttemptBlob): Uint8Array => utf8(canonicalJson(blob));
/** Commits to the room, the chapter version, the attempt's place and every attempt before it. */
export function attemptLink(room: AttemptRoom, position: number, previous: string, attemptDigest: string, byteLength: number): Promise<string> {
  return digest(canonicalJson({ schema: LINK_SCHEMA, room_id: room.room_id, level_id: room.level_id, level_version: room.level_version, definition_hash: room.definition_hash,
    position, branch: position, previous, digest: attemptDigest, byte_length: byteLength }));
}

/** The pairs and turn rows an attempt's blob rebuilds, each checked against the blob's own hashes. */
export function attemptRows(blob: AttemptBlob): { pairs: Map<string, PairV2>; turns: Map<string, RecordingV2> } {
  if (isOpenBlob(blob)) return openAttemptRows(blob);
  const pairs = new Map<string, PairV2>(), turns = new Map<string, RecordingV2>();
  for (const facts of blob.rows.pairs) {
    const checkpoint = checkpointAt(blob.checkpoint!, facts.stage_index + 1), proof = nestedProof(checkpoint);
    need(proof && checkpoint.checkpoint_hash === facts.checkpoint_hash && proof.a.recording_hash === facts.a_hash && proof.b.recording_hash === facts.b_hash);
    pairs.set(facts.pair_id, { pair_id: facts.pair_id, branch: facts.branch, stage_index: facts.stage_index, a: proof.a, b: proof.b, checkpoint });
    proof.turns.forEach((turn, at) => turns.set(turnId(facts.branch, facts.stage_index, at + 1), turn));
  }
  // The open stage's first turn.
  if (blob.open_turn) turns.set(blob.rows.turns.find(turn => !turns.has(turn.turn_id) && turn.turn_id.endsWith("-a"))!.turn_id, blob.open_turn);
  for (const facts of blob.rows.turns) need(turns.get(facts.turn_id)?.recording_hash === facts.recording_hash);
  need(turns.size === blob.rows.turns.length);
  return { pairs, turns };
}
/** Open turns: every turn's fingerprint under its id, and each pair from its listed checkpoint with its first and closing turns. */
function openAttemptRows(blob: OpenAttemptBlob): { pairs: Map<string, PairV2>; turns: Map<string, RecordingV2> } {
  need(Array.isArray(blob.turns) && Array.isArray(blob.checkpoints) && blob.turns.length === blob.rows.turns.length && blob.checkpoints.length === blob.rows.pairs.length);
  const turns = new Map<string, RecordingV2>(), pairs = new Map<string, PairV2>();
  blob.rows.turns.forEach((facts, at) => { need(blob.turns[at].recording_hash === facts.recording_hash && !turns.has(facts.turn_id)); turns.set(facts.turn_id, blob.turns[at]); });
  blob.rows.pairs.forEach((facts, at) => {
    const checkpoint = blob.checkpoints[at], hashes = checkpoint.turn_hashes ?? [];
    const a = turns.get(turnId(facts.branch, facts.stage_index, 1)), b = turns.get(turnId(facts.branch, facts.stage_index, hashes.length));
    need(checkpoint.checkpoint_hash === facts.checkpoint_hash && checkpoint.stage_index === facts.stage_index + 1 && a?.recording_hash === facts.a_hash && b?.recording_hash === facts.b_hash);
    pairs.set(facts.pair_id, { pair_id: facts.pair_id, branch: facts.branch, stage_index: facts.stage_index, a: fingerprint(a), b: fingerprint(b), checkpoint });
  });
  return { pairs, turns };
}
