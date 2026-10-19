import { HASH_PATTERN, integer, text } from "../protocol";

/**
 * How many tries a player's phone says an accepted turn took. Presentation only:
 * never part of a recording, its hash, a checkpoint, a receipt or replay bytes.
 *
 * The table is created by the first turn that sends a count, so every other
 * room's storage is unchanged. It is keyed by turn id and keeps the turn's
 * recording hash, so offload stubs, replay transfer and forks leave it alone and
 * the count stays readable for every attempt. Operator snapshots leave it out,
 * as they do inbox activity; the full room erase drops it.
 */
export const TURN_TRIES = {
  name: "turn_tries",
  schema: "CREATE TABLE turn_tries (turn_id TEXT PRIMARY KEY, recording_hash TEXT NOT NULL, tries INTEGER NOT NULL CHECK(tries BETWEEN 1 AND 999))"
} as const;
export const MAX_TRIES = 999;
/** Sent on GET /v2/capabilities by clients that send and read counts. */
export const TURN_TRIES_HEADER = "X-AfterYou-Turn-Tries";
export type TurnTriesView = { schema_version: 1; tries: Record<string, number> };

export function triesWanted(request: Request): boolean { return request.headers.get(TURN_TRIES_HEADER) === "1"; }

/** The optional field a turn body may carry, for the exact-key check. */
export function triesField(body: Record<string, unknown>): string[] { return body.tries === undefined ? [] : ["tries"]; }

/** A sent count, 1 to 999, or undefined when the body has none. */
export function parseTries(body: Record<string, unknown>): number | undefined {
  return body.tries === undefined ? undefined : integer(body.tries, 1, MAX_TRIES);
}

function present(storage: DurableObjectStorage): boolean {
  return storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name=?", TURN_TRIES.name).toArray().length > 0;
}

/** The caller owns the transaction that inserted the turn row. */
export function recordTries(storage: DurableObjectStorage, turnId: string, recordingHash: string, tries: number | undefined): void {
  if (tries === undefined) return;
  storage.sql.exec(TURN_TRIES.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT INTO turn_tries VALUES (?,?,?)", turnId, text(recordingHash, HASH_PATTERN), tries);
}

/** Every count the room holds, by recording hash. A room without the table reads no rows. */
export function turnTriesView(storage: DurableObjectStorage): TurnTriesView {
  const tries: Record<string, number> = {};
  if (present(storage)) {
    for (const row of storage.sql.exec<{ recording_hash: string; tries: number }>("SELECT recording_hash,tries FROM turn_tries ORDER BY rowid LIMIT 129")) tries[row.recording_hash] = row.tries;
  }
  return { schema_version: 1, tries };
}

/** For the full room erase and a snapshot restore. */
export function clearTurnTries(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS turn_tries");
}

/** The table as sqlite_master lists it, so snapshot schema checks can let it pass. */
export function isTurnTriesTable(row: { name: string; sql: string }): boolean {
  return row.name === TURN_TRIES.name && row.sql === TURN_TRIES.schema;
}
