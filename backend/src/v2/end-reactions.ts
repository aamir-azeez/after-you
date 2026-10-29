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
 *
 * Faces come in two kinds. The everyday faces (BASE_FACES) are everyone's. The pack faces
 * (PACK_FACES) belong to reaction packs (pollen/catalog.json packs): only a player who owns the
 * pack may send one (v2/face-packs.ts checks a turn against the owned packs its Player call
 * brings), and only a phone that says it draws them (FACE_PACKS_HEADER) is sent one. Any other
 * phone gets the everyday face that stands in for it (PACK_FALLBACK), so an older build still
 * shows a face where it would otherwise drop a whole run reaction track.
 */
export const BASE_FACES = ["happy", "squeeze", "surprised", "sad", "annoyed", "angry", "sleepy", "knocked_out", "heart"] as const;
export const PACK_FACES = ["heart_eyes", "proud", "wink", "wow", "crying", "dizzy"] as const;
export const FACES = [...BASE_FACES, ...PACK_FACES] as const;
export type BaseFace = typeof BASE_FACES[number];
export type PackFace = typeof PACK_FACES[number];
export type Face = typeof FACES[number];
/** The everyday face a phone without FACE_PACKS_HEADER is shown for each pack face. */
export const PACK_FALLBACK: Readonly<Record<PackFace, BaseFace>> = { heart_eyes: "heart", proud: "happy", wink: "happy", wow: "surprised", crying: "sad", dizzy: "knocked_out" };
/** Sent by phones that draw pack faces, beside END_REACTIONS_HEADER and RUN_REACTIONS_HEADER; GET /v2/capabilities then answers face_packs_version. */
export const FACE_PACKS_HEADER = "X-AfterYou-Face-Packs";
export const FACE_PACKS_VERSION = 1;
export function facePacksWanted(request: Request): boolean { return request.headers.get(FACE_PACKS_HEADER) === String(FACE_PACKS_VERSION); }
export function isPackFace(face: string): face is PackFace { return (PACK_FACES as readonly string[]).includes(face); }
/** The face as a phone that does (`packs`) or does not draw pack faces should see it. */
export function shownFace(face: Face, packs: boolean): Face {
  return packs || !isPackFace(face) ? face : PACK_FALLBACK[face];
}

const schemaFor = (faces: readonly string[]) =>
  `CREATE TABLE end_reactions (turn_id TEXT PRIMARY KEY, recording_hash TEXT NOT NULL, player_id TEXT NOT NULL, face TEXT NOT NULL CHECK(face IN (${faces.map(face => `'${face}'`).join(",")})))`;
export const END_REACTIONS = { name: "end_reactions", schema: schemaFor(FACES) } as const;
/**
 * The table as rooms made it before the pack faces: its CHECK lists only the everyday faces. It
 * keeps working for everyday faces; the first pack face sent to such a room rebuilds it with
 * today's schema inside that turn's transaction (recordEndReaction), copying at most MAX_ROWS rows
 * once. Snapshot checks accept both (isEndReactionsTable).
 */
export const LEGACY_SCHEMAS: readonly string[] = [schemaFor(BASE_FACES)];
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
  if (isPackFace(face)) upgradeLegacyTable(storage);
  storage.sql.exec("INSERT INTO end_reactions VALUES (?,?,?,?)", turnId, text(recordingHash, HASH_PATTERN), player, face);
  tables.delete(storage);
}

/** Rebuilds a table made before the pack faces with today's schema, every row kept in order. The caller owns the transaction. */
function upgradeLegacyTable(storage: DurableObjectStorage): void {
  const row = storage.sql.exec<{ sql: string }>("SELECT sql FROM sqlite_master WHERE type='table' AND name='end_reactions'").toArray()[0];
  if (!row || row.sql === END_REACTIONS.schema) return;
  if (!LEGACY_SCHEMAS.includes(row.sql)) throw new Error("end_reactions_schema_unknown");
  // Copied aside and back rather than renamed: a rename would rewrite the stored CREATE text, which
  // the exact schema checks above and in snapshot.ts compare.
  storage.sql.exec("CREATE TABLE end_reactions_copy AS SELECT turn_id,recording_hash,player_id,face FROM end_reactions ORDER BY rowid");
  storage.sql.exec("DROP TABLE end_reactions");
  storage.sql.exec(END_REACTIONS.schema);
  storage.sql.exec("INSERT INTO end_reactions SELECT turn_id,recording_hash,player_id,face FROM end_reactions_copy ORDER BY rowid");
  storage.sql.exec("DROP TABLE end_reactions_copy");
}

/** Every face the room holds, by recording hash, as a phone that does (`packs`) or does not draw pack faces sees them. A room without the table reads none. */
export function endReactionsList(storage: DurableObjectStorage, packs = true): EndReactionsList {
  const faces: Record<string, Face> = {};
  if (present(storage)) {
    for (const row of storage.sql.exec<{ recording_hash: string; face: Face }>("SELECT recording_hash,face FROM end_reactions ORDER BY rowid LIMIT ?", MAX_ROWS)) faces[row.recording_hash] = shownFace(row.face, packs);
  }
  return { schema_version: 1, faces };
}

/** The face on `partner`'s latest accepted turn, when that turn carried one. */
export function partnerFace(storage: DurableObjectStorage, partner: string | null): Face | undefined {
  if (partner === null || !present(storage)) return undefined;
  const row = storage.sql.exec<{ face: Face }>("SELECT e.face AS face FROM end_reactions e WHERE e.player_id=? AND e.turn_id=(SELECT turn_id FROM turns WHERE player_id=? ORDER BY accepted_revision DESC LIMIT 1)", partner, partner).toArray()[0];
  return row?.face;
}

/** A room read's or turn reply's view for `player`, whose partner is the other member (pack faces as endReactionsList shows them). */
export function endReactionsView(storage: DurableObjectStorage, partner: string | null, packs = true): EndReactionsView {
  const face = partnerFace(storage, partner);
  return { ...endReactionsList(storage, packs), ...(face === undefined ? {} : { partner: shownFace(face, packs) }) };
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
  return row.name === END_REACTIONS.name && (row.sql === END_REACTIONS.schema || LEGACY_SCHEMAS.includes(row.sql));
}
