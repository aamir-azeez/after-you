import { HASH_PATTERN, ID_PATTERN } from "../protocol";
import { LOOKS_ROOM_TABLES, isLazyTable } from "../storage-schema";
import { CATALOG, isDefaultLook, lookText, validLook, type Catalog, type Look } from "./catalog";

/**
 * Looks in a v2 room (POLLEN_LOOKS). Cosmetics are strictly per player: each member's own look rides
 * into the room from their own Player, on the identity answer auth() already reads for create, join
 * and turns (no extra Durable Object request), and only room members ever read them back.
 *
 * Room storage (storage-schema.ts LOOKS_ROOM_TABLES), made by the first look that is not the default,
 * so a room where everyone wears the default look stores nothing:
 * - member_looks: each member's current look; the default look removes the row.
 * - turn_looks: the look each turn was played in, keyed by its recording hash, written in the commit
 *   that accepts the turn. A replay draws each turn in its own look, whatever either player wears now.
 *   Replay transfer and attempt history never touch it, so a replay that comes back keeps its looks.
 * Operator snapshots leave both out (like member names); the full room erase drops them; a member
 * who leaves a finished room takes their member_looks row (their turns' looks stay with the turns).
 */
const [MEMBERS, TURNS] = LOOKS_ROOM_TABLES;
export const MAX_TURN_LOOKS = TURNS.maxRows;

const known = new WeakMap<DurableObjectStorage, Set<string>>();
function present(storage: DurableObjectStorage, table: string): boolean {
  let names = known.get(storage);
  if (!names) {
    names = new Set(storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type='table' AND name IN (?,?)", MEMBERS.name, TURNS.name).toArray().map(row => row.name));
    known.set(storage, names);
  }
  return names.has(table);
}
function create(storage: DurableObjectStorage, table: typeof MEMBERS): void {
  if (present(storage, table.name)) return;
  storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  known.delete(storage);
}
/** A stored look as it may be served: checked again on the way out, so a catalogue change never serves a slot that no longer exists. */
function parsed(text: string | undefined, catalog: Catalog): Look {
  if (text === undefined) return {};
  try { const value: unknown = JSON.parse(text); return validLook(value, catalog) ? value : {}; } catch { return {}; }
}

/** A member's stored look, or the default. */
export function memberLook(storage: DurableObjectStorage, player: string | null, catalog: Catalog = CATALOG): Look {
  if (player === null || !present(storage, MEMBERS.name)) return {};
  return parsed(storage.sql.exec<{ look: string }>("SELECT look FROM member_looks WHERE player_id=?", player).toArray()[0]?.look, catalog);
}

/**
 * Keeps the member's look as their Player reported it, inside a write the room already makes.
 * Undefined writes nothing (looks are off); an unchanged look writes nothing; the default look
 * removes the row. The caller owns the transaction.
 */
export function recordMemberLook(storage: DurableObjectStorage, player: string, look: Look | undefined, catalog: Catalog = CATALOG): void {
  if (look === undefined || !validLook(look, catalog) || !ID_PATTERN.test(player)) return;
  const text = lookText(look, catalog);
  if (!present(storage, MEMBERS.name)) { if (isDefaultLook(look)) return; }
  else {
    const stored = storage.sql.exec<{ look: string }>("SELECT look FROM member_looks WHERE player_id=?", player).toArray()[0]?.look;
    if (isDefaultLook(look)) { if (stored !== undefined) storage.sql.exec("DELETE FROM member_looks WHERE player_id=?", player); return; }
    if (stored === text) return;
  }
  create(storage, MEMBERS);
  storage.sql.exec("INSERT OR REPLACE INTO member_looks VALUES (?,?)", player, text);
}

/** The look of one accepted turn, inside its commit; only a look that is not the default is written. Past the bound the oldest go. */
export function recordTurnLook(storage: DurableObjectStorage, recordingHash: string, player: string, look: Look | undefined, catalog: Catalog = CATALOG): void {
  if (look === undefined || isDefaultLook(look) || !validLook(look, catalog) || !HASH_PATTERN.test(recordingHash) || !ID_PATTERN.test(player)) return;
  create(storage, TURNS);
  storage.sql.exec("INSERT OR IGNORE INTO turn_looks VALUES (?,?,?)", recordingHash, player, lookText(look, catalog));
  storage.sql.exec("DELETE FROM turn_looks WHERE rowid <= (SELECT rowid FROM turn_looks ORDER BY rowid DESC LIMIT 1 OFFSET ?)", MAX_TURN_LOOKS);
}

/**
 * Turn looks keyed by recording hash: every turn's look, or with `player` only that member's turns.
 * Turns in the default look are absent. A room without the table reads nothing.
 */
export function turnLooks(storage: DurableObjectStorage, player?: string | null, catalog: Catalog = CATALOG): Record<string, Look> {
  if (player === null || !present(storage, TURNS.name)) return {};
  const rows = player === undefined
    ? storage.sql.exec<{ recording_hash: string; look: string }>("SELECT recording_hash,look FROM turn_looks ORDER BY rowid LIMIT ?", MAX_TURN_LOOKS).toArray()
    : storage.sql.exec<{ recording_hash: string; look: string }>("SELECT recording_hash,look FROM turn_looks WHERE player_id=? ORDER BY rowid LIMIT ?", player, MAX_TURN_LOOKS).toArray();
  const result: Record<string, Look> = {};
  for (const row of rows) { const look = parsed(row.look, catalog); if (!isDefaultLook(look)) result[row.recording_hash] = look; }
  return result;
}

/** A member leaving a finished room: their current look goes; true when a row went. */
export function eraseMemberLook(storage: DurableObjectStorage, player: string): boolean {
  if (!present(storage, MEMBERS.name)) return false;
  return storage.sql.exec("DELETE FROM member_looks WHERE player_id=?", player).rowsWritten > 0;
}

/** For the full room erase and a snapshot restore. */
export function clearLooks(storage: DurableObjectStorage): void {
  for (const table of LOOKS_ROOM_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
  known.delete(storage);
}

/** The tables as sqlite_master lists them, so snapshot schema checks can let them pass. */
export function isLooksRoomTable(row: { name: string; sql: string }): boolean { return isLazyTable(LOOKS_ROOM_TABLES, row); }
