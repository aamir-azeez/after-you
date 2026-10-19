import { ApiError, HASH_PATTERN, text } from "../protocol";

/**
 * The face a player picked at the end of a run, sent with that turn. Presentation
 * only: never part of a recording, its hash, a checkpoint, a receipt or replay
 * bytes. (The preset pair reactions in reactions.ts are a different feature.)
 *
 * The table is created by the first turn that carries a face, inside that turn's
 * transaction, so every other room's storage is unchanged. It is keyed by turn id
 * and keeps the recording hash and the player, so offload stubs, replay transfer
 * and forks leave it alone, leaving a finished room erases the leaver's rows, and
 * the full room erase drops it. Operator snapshots leave it out and a restore
 * clears it, as with turn_tries.
 */
export const FACES = ["happy", "squeeze", "surprised", "sad", "annoyed", "angry", "sleepy", "knocked_out", "heart"] as const;
export type Face = typeof FACES[number];
export const END_REACTIONS = {
  name: "end_reactions",
  schema: `CREATE TABLE end_reactions (turn_id TEXT PRIMARY KEY, recording_hash TEXT NOT NULL, player_id TEXT NOT NULL, face TEXT NOT NULL CHECK(face IN (${FACES.map(face => `'${face}'`).join(",")})))`
} as const;
/** A room holds at most 128 turns (room.ts MAX_TURNS); one more row proves the bound. */
const MAX_ROWS = 129;
/** Sent on GET /v2/capabilities, a room read and a turn by clients that send and read faces. */
export const END_REACTIONS_HEADER = "X-AfterYou-End-Reactions";
/** What a room read or a turn reply carries for such a client: every face by recording hash, and the friend's latest. */
export type EndReactionsView = { schema_version: 1; faces: Record<string, Face>; partner?: Face };
/** The list Replays reads (GET .../end-reactions). */
export type EndReactionsList = { schema_version: 1; faces: Record<string, Face> };

export function endReactionsWanted(request: Request): boolean { return request.headers.get(END_REACTIONS_HEADER) === "1"; }

/** The optional field a turn body may carry, for the exact-key check. */
export function endReactionField(body: Record<string, unknown>): string[] { return body.end_reaction === undefined ? [] : ["end_reaction"]; }

/** A sent face, or undefined when the body has none. */
export function parseEndReaction(body: Record<string, unknown>): Face | undefined {
  if (body.end_reaction === undefined) return undefined;
  if (typeof body.end_reaction !== "string" || !(FACES as readonly string[]).includes(body.end_reaction)) throw new ApiError(400, "invalid_end_reaction");
  return body.end_reaction as Face;
}

/**
 * Whether the table exists, looked up once per room instance: every inbox
 * projection asks for the friend's face, so a room without faces must read no
 * more rows than before. A write or drop forgets the answer instead of setting
 * it, so a transaction that rolls back can never leave it wrong.
 */
const tables = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let known = tables.get(storage);
  if (known === undefined) {
    known = storage.sql.exec("SELECT 1 AS found FROM sqlite_master WHERE type='table' AND name='end_reactions'").toArray().length > 0;
    tables.set(storage, known);
  }
  return known;
}

/** The caller owns the transaction that inserted the turn row. */
export function recordEndReaction(storage: DurableObjectStorage, turnId: string, recordingHash: string, player: string, face: Face | undefined): void {
  if (face === undefined) return;
  storage.sql.exec(END_REACTIONS.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT INTO end_reactions VALUES (?,?,?,?)", turnId, text(recordingHash, HASH_PATTERN), player, face);
  tables.delete(storage);
}

/** Every face the room holds, by recording hash. A room without the table reads none. */
export function endReactionsList(storage: DurableObjectStorage): EndReactionsList {
  const faces: Record<string, Face> = {};
  if (present(storage)) {
    for (const row of storage.sql.exec<{ recording_hash: string; face: Face }>("SELECT recording_hash,face FROM end_reactions ORDER BY rowid LIMIT ?", MAX_ROWS)) faces[row.recording_hash] = row.face;
  }
  return { schema_version: 1, faces };
}

/** The face on `partner`'s latest accepted turn, when that turn carried one. */
export function partnerFace(storage: DurableObjectStorage, partner: string | null): Face | undefined {
  if (partner === null || !present(storage)) return undefined;
  const row = storage.sql.exec<{ face: Face }>("SELECT e.face AS face FROM end_reactions e WHERE e.player_id=? AND e.turn_id=(SELECT turn_id FROM turns WHERE player_id=? ORDER BY accepted_revision DESC LIMIT 1)", partner, partner).toArray()[0];
  return row?.face;
}

/** A room read's or turn reply's view for `player`, whose partner is the other member. */
export function endReactionsView(storage: DurableObjectStorage, partner: string | null): EndReactionsView {
  const face = partnerFace(storage, partner);
  return { ...endReactionsList(storage), ...(face === undefined ? {} : { partner: face }) };
}

/** Leaving a finished room: the leaver's faces go with their photos. The caller owns the transaction. */
export function eraseEndReactionsOf(storage: DurableObjectStorage, player: string): void {
  if (present(storage)) storage.sql.exec("DELETE FROM end_reactions WHERE player_id=?", player);
}

/** For the full room erase and a snapshot restore. */
export function clearEndReactions(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS end_reactions");
  tables.delete(storage);
}

/** The table as sqlite_master lists it, so snapshot schema checks can let it pass. */
export function isEndReactionsTable(row: { name: string; sql: string }): boolean {
  return row.name === END_REACTIONS.name && row.sql === END_REACTIONS.schema;
}
