import { ApiError, HASH_PATTERN, canonicalJson, object, text } from "../protocol";
import { exact } from "./protocol-relay";
import { isFingerprint } from "./open-turns";
import { parseRow, storedTurn, type RowData } from "./row-codec";
import type { RecordingV2 } from "./protocol";

/**
 * Turn send-back on open turns (claude-20261011/open-turns-fingerprints/WIRE.md section 9). The server keeps earlier
 * turns only as fingerprints, so a phone that lost its copies (a new install) asks for them by hash; the server answers
 * with any it still holds in full and remembers the rest as wanted; the partner's next poll names them (`wanted`), and
 * the partner's phone sends its copies back, which the server takes only when they hash to a wanted turn of this room.
 * The asking phone's next ask gets them, and its acknowledgement drops them; a copy delivered and never acknowledged goes
 * when the room's next turn is accepted.
 *
 * Two small tables, made by the first ask, so every other room's storage is unchanged: one row of wanted hashes per
 * member, and one row per copy sent back (in the turn row's stored form, row-codec.ts storedTurn). No revision moves.
 * Operator snapshots leave both out and a restore drops them, as for turn tries: they only carry turns between phones.
 */
export const TURN_WANTS = { name: "turn_wants", schema: "CREATE TABLE turn_wants (player_id TEXT PRIMARY KEY, hashes TEXT NOT NULL) WITHOUT ROWID" } as const;
export const TURN_COPIES = { name: "turn_copies", schema: "CREATE TABLE turn_copies (recording_hash TEXT PRIMARY KEY, data BLOB NOT NULL) WITHOUT ROWID" } as const;
/** Most hashes one ask names: every turn a room holds. */
export const MAX_ASKED = 128;
/** Most copies one send-back carries, and the most bytes of copies one answer carries (a phone asks again for the rest). */
export const MAX_SENT = 16, MAX_ANSWER_BYTES = 1_000_000;

function present(storage: DurableObjectStorage): boolean {
  return storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name=?", TURN_WANTS.name).toArray().length > 0;
}
function ensure(storage: DurableObjectStorage): void {
  for (const table of [TURN_WANTS, TURN_COPIES]) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
}
/** `{ schema_version: 1, recording_hashes }`: 1 to MAX_ASKED distinct hashes. */
export function parseAsked(input: unknown): string[] {
  const value = object(input); exact(value, ["schema_version", "recording_hashes"]);
  const hashes = value.recording_hashes;
  if (value.schema_version !== 1 || !Array.isArray(hashes) || hashes.length < 1 || hashes.length > MAX_ASKED || new Set(hashes).size !== hashes.length) throw new ApiError(422, "invalid_turn_copies");
  return hashes.map(hash => text(hash, HASH_PATTERN));
}
/** `{ schema_version: 1, turns }`: 1 to MAX_SENT records, each checked by the caller as a turn of the room. */
export function parseSent(input: unknown): unknown[] {
  const value = object(input); exact(value, ["schema_version", "turns"]);
  if (value.schema_version !== 1 || !Array.isArray(value.turns) || value.turns.length < 1 || value.turns.length > MAX_SENT) throw new ApiError(422, "invalid_turn_copies");
  return value.turns;
}

/** Every turn row's hash, and the record of each held in full (a compressed row is always a full one). */
function roomTurns(storage: DurableObjectStorage): Map<string, RecordingV2 | null> {
  const turns = new Map<string, RecordingV2 | null>();
  for (const row of storage.sql.exec<{ data: RowData }>("SELECT data FROM turns")) {
    const recording = parseRow<RecordingV2 & { recording_hash: string }>(row.data);
    if (typeof recording.recording_hash === "string") turns.set(recording.recording_hash, isFingerprint(recording) || Object.keys(recording).length === 1 ? null : recording);
  }
  return turns;
}
function wants(storage: DurableObjectStorage, player: string): string[] {
  const row = storage.sql.exec<{ hashes: string }>("SELECT hashes FROM turn_wants WHERE player_id=?", player).toArray()[0];
  return row ? JSON.parse(row.hashes) as string[] : [];
}
function writeWants(storage: DurableObjectStorage, player: string, hashes: string[], before: string[]): void {
  if (canonicalJson(hashes) === canonicalJson(before)) return;
  if (hashes.length) storage.sql.exec("INSERT INTO turn_wants VALUES (?,?) ON CONFLICT(player_id) DO UPDATE SET hashes=excluded.hashes", player, JSON.stringify(hashes));
  else storage.sql.exec("DELETE FROM turn_wants WHERE player_id=?", player);
}
function copy(storage: DurableObjectStorage, hash: string): RecordingV2 | null {
  const row = storage.sql.exec<{ data: RowData }>("SELECT data FROM turn_copies WHERE recording_hash=?", hash).toArray()[0];
  return row ? parseRow<RecordingV2>(row.data) : null;
}

/**
 * `player` asks for turns of the room by hash (every one must be a turn of this room). The answer carries each the
 * server holds in full (a row still full, or a copy sent back), up to MAX_ANSWER_BYTES with `more` when some wait for
 * the next ask; every other one is remembered as wanted. Writes at most the member's one wants row, and only on a change.
 */
export function askCopies(storage: DurableObjectStorage, player: string, asked: string[]): { schema_version: 1; copies: RecordingV2[]; more: boolean } {
  const turns = roomTurns(storage);
  if (asked.some(hash => !turns.has(hash))) throw new ApiError(422, "turn_not_in_room");
  ensure(storage);
  const copies: RecordingV2[] = [], missing: string[] = [];
  let bytes = 0, more = false;
  for (const hash of asked) {
    const held = turns.get(hash) ?? copy(storage, hash);
    if (!held) { missing.push(hash); continue; }
    const size = canonicalJson(held).length;
    if (copies.length && bytes + size > MAX_ANSWER_BYTES) { more = true; continue; }
    copies.push(held); bytes += size;
  }
  const before = wants(storage, player);
  writeWants(storage, player, [...new Set([...before.filter(hash => !asked.includes(hash)), ...missing])].sort(), before);
  return { schema_version: 1, copies, more };
}
/** What the other member of the room wants and the server holds no copy of: the poll's `wanted`; null when nobody ever asked in this room (no tables). */
export function wantedBy(storage: DurableObjectStorage, other: string | null): string[] | null {
  if (!present(storage)) return null;
  if (other === null) return [];
  const asked = wants(storage, other);
  return asked.filter(hash => !copy(storage, hash));
}
/**
 * `player` sends copies back: each record already checked as a full turn whose hash it carries (recordingV2). Kept only
 * when the other member wants it and it is a fingerprint here; a copy already kept counts as kept again. One row a copy.
 */
export function keepCopies(storage: DurableObjectStorage, other: string | null, sent: RecordingV2[], compress: boolean): { schema_version: 1; kept: string[] } {
  if (other === null || !present(storage)) return { schema_version: 1, kept: [] };
  const wanted = new Set(wants(storage, other)), turns = roomTurns(storage), kept: string[] = [];
  for (const recording of sent) {
    const hash = recording.recording_hash;
    if (!wanted.has(hash) || !turns.has(hash)) continue;
    if (!copy(storage, hash) && turns.get(hash) === null) storage.sql.exec("INSERT INTO turn_copies VALUES (?,?)", hash, storedTurn(recording, compress));
    kept.push(hash);
  }
  return { schema_version: 1, kept: [...new Set(kept)] };
}
/** `player` holds these turns again: their copies go (unless the other member still wants one) and they leave the member's wants. */
export function acknowledgeCopies(storage: DurableObjectStorage, player: string, other: string | null, hashes: string[]): { schema_version: 1; acknowledged: string[] } {
  if (!present(storage)) return { schema_version: 1, acknowledged: hashes };
  const theirs = new Set(other === null ? [] : wants(storage, other));
  for (const hash of hashes) if (!theirs.has(hash)) storage.sql.exec("DELETE FROM turn_copies WHERE recording_hash=?", hash);
  const before = wants(storage, player);
  writeWants(storage, player, before.filter(hash => !hashes.includes(hash)), before);
  return { schema_version: 1, acknowledged: hashes };
}
/** Inside a turn's transaction: copies already handed over (no member still wants them) go back to fingerprints only. */
export function dropDeliveredCopies(storage: DurableObjectStorage): void {
  if (!present(storage)) return;
  const wanted = storage.sql.exec<{ hashes: string }>("SELECT hashes FROM turn_wants").toArray().flatMap(row => JSON.parse(row.hashes) as string[]);
  storage.sql.exec("DELETE FROM turn_copies WHERE recording_hash NOT IN (SELECT value FROM json_each(?))", JSON.stringify(wanted));
}
/** For the full room erase, a start over and a snapshot restore. */
export function clearTurnCopies(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS turn_wants"); storage.sql.exec("DROP TABLE IF EXISTS turn_copies");
}
/** The tables as sqlite_master lists them, so snapshot schema checks let them pass. */
export function isTurnCopiesTable(row: { name: string; sql: string }): boolean {
  return (row.name === TURN_WANTS.name && row.sql === TURN_WANTS.schema) || (row.name === TURN_COPIES.name && row.sql === TURN_COPIES.schema);
}
