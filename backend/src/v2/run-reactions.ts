import { ApiError, HASH_PATTERN, isObject, text } from "../protocol";
import { FACES, shownFace, type Face } from "./end-reactions";

/**
 * Reactions made during a run: the faces a player tapped while playing, each at
 * a tick of the turn's own step count, sent with that turn as `run_reactions`.
 * Presentation only, like the end-of-run face: never part of a recording, its
 * hash, a checkpoint, a receipt's proof or replay bytes. The faces are the end
 * reactions' own (end-reactions.ts FACES).
 *
 * Storage follows end_reactions: one row per turn that carried a track, in a
 * table created by the first such turn inside that turn's transaction, so every
 * other room's storage is unchanged. It adds no request and no Durable Object
 * call: the track rides on the turn and comes back beside a room read and a
 * turn reply (the partner's latest turn's) and the end reactions list (every turn's). Leaving a finished room erases the leaver's
 * rows, the full room erase drops the table, and operator snapshots leave it out
 * while a restore clears it.
 */
export const RUN_REACTIONS = {
  name: "run_reactions",
  schema: "CREATE TABLE run_reactions (turn_id TEXT PRIMARY KEY, recording_hash TEXT NOT NULL, player_id TEXT NOT NULL, track TEXT NOT NULL)"
} as const;
/** The most reactions one turn may carry (the client's own cap per turn). */
export const MAX_RUN_REACTIONS = 20;
/** A room holds at most 128 turns (room.ts MAX_TURNS); one more row proves the bound. */
const MAX_ROWS = 129;
/** Sent on GET /v2/capabilities, a room read, a turn and the end reactions list by clients that send and play run reactions. */
export const RUN_REACTIONS_HEADER = "X-AfterYou-Run-Reactions";
export type RunReaction = { tick: number; id: Face };
/** Tracks by recording hash, only for recordings that carried one. */
export type RunReactionsView = { schema_version: 1; tracks: Record<string, RunReaction[]> };

export function runReactionsWanted(request: Request): boolean { return request.headers.get(RUN_REACTIONS_HEADER) === "1"; }

/** The optional field a turn body may carry, for the exact-key check. */
export function runReactionField(body: Record<string, unknown>): string[] { return body.run_reactions === undefined ? [] : ["run_reactions"]; }

/**
 * A sent track, or undefined when the body has none: 1 to MAX_RUN_REACTIONS
 * entries of exactly {tick, id}, ticks whole and strictly rising, ids from the
 * catalog. Whether every tick lies within the turn is withinTurn's check, once
 * the recording is read.
 */
export function parseRunReactions(body: Record<string, unknown>): RunReaction[] | undefined {
  const value = body.run_reactions;
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_RUN_REACTIONS) throw new ApiError(400, "invalid_run_reactions");
  let previous = -1;
  return value.map(entry => {
    if (!isObject(entry) || Object.keys(entry).length !== 2) throw new ApiError(400, "invalid_run_reactions");
    const { tick, id } = entry;
    if (typeof tick !== "number" || !Number.isInteger(tick) || tick <= previous || typeof id !== "string" || !(FACES as readonly string[]).includes(id)) throw new ApiError(400, "invalid_run_reactions");
    previous = tick;
    return { tick, id: id as Face };
  });
}

/** Every reaction falls inside the turn: its last tick is at most the recording's length. */
export function withinTurn(track: RunReaction[] | undefined, durationTicks: number): void {
  if (track !== undefined && track[track.length - 1].tick > durationTicks) throw new ApiError(400, "invalid_run_reactions");
}

/** Whether the table exists, looked up once per room instance (as end-reactions.ts does). */
const tables = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let known = tables.get(storage);
  if (known === undefined) {
    known = storage.sql.exec("SELECT 1 AS found FROM sqlite_master WHERE type='table' AND name=?", RUN_REACTIONS.name).toArray().length > 0;
    tables.set(storage, known);
  }
  return known;
}

/** The caller owns the transaction that inserted the turn row. */
export function recordRunReactions(storage: DurableObjectStorage, turnId: string, recordingHash: string, player: string, track: RunReaction[] | undefined): void {
  if (track === undefined) return;
  storage.sql.exec(RUN_REACTIONS.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT INTO run_reactions VALUES (?,?,?,?)", turnId, text(recordingHash, HASH_PATTERN), player, JSON.stringify(track));
  tables.delete(storage);
}

/** Every turn's track (the end reactions list), pack faces as end-reactions.ts shownFace gives them for `packs`. A room without the table reads no rows. */
export function runReactionsView(storage: DurableObjectStorage, packs = true): RunReactionsView {
  const tracks: Record<string, RunReaction[]> = {};
  if (present(storage)) {
    for (const row of storage.sql.exec<{ recording_hash: string; track: string }>("SELECT recording_hash,track FROM run_reactions ORDER BY rowid LIMIT ?", MAX_ROWS)) tracks[row.recording_hash] = shownTrack(row.track, packs);
  }
  return { schema_version: 1, tracks };
}

/**
 * The track on `partner`'s latest accepted turn, for a room read or turn reply:
 * the memory a second turn plays alongside, or the friend's turn that just
 * finished a pair. One row by key; a room without the table reads none.
 */
export function partnerTrack(storage: DurableObjectStorage, partner: string | null, packs = true): RunReactionsView {
  const tracks: Record<string, RunReaction[]> = {};
  if (partner !== null && present(storage)) {
    const row = storage.sql.exec<{ recording_hash: string; track: string }>("SELECT r.recording_hash AS recording_hash,r.track AS track FROM run_reactions r WHERE r.turn_id=(SELECT turn_id FROM turns WHERE player_id=? ORDER BY accepted_revision DESC LIMIT 1)", partner).toArray()[0];
    if (row) tracks[row.recording_hash] = shownTrack(row.track, packs);
  }
  return { schema_version: 1, tracks };
}

/** A stored track as a phone that does (`packs`) or does not draw pack faces sees it. */
function shownTrack(stored: string, packs: boolean): RunReaction[] {
  const track = JSON.parse(stored) as RunReaction[];
  return packs ? track : track.map(entry => ({ tick: entry.tick, id: shownFace(entry.id, false) }));
}

/** Leaving a finished room: the leaver's tracks go with their faces. The caller owns the transaction. */
export function eraseRunReactionsOf(storage: DurableObjectStorage, player: string): void {
  if (present(storage)) storage.sql.exec("DELETE FROM run_reactions WHERE player_id=?", player);
}

/** For the full room erase and a snapshot restore. */
export function clearRunReactions(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS run_reactions");
  tables.delete(storage);
}

/** The table as sqlite_master lists it, so snapshot schema checks can let it pass. */
export function isRunReactionsTable(row: { name: string; sql: string }): boolean {
  return row.name === RUN_REACTIONS.name && row.sql === RUN_REACTIONS.schema;
}
