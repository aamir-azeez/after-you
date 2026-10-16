/**
 * Members who left a finished room (POST .../leave with leave_finished). Shared
 * by the v1 Room and RoomV2. The table is created by the first leave only, so
 * every other room's storage is unchanged, and the full room erase drops it.
 * A departed member is no longer a member of the room, and nobody can fork the
 * room back into play.
 */
export const ROOM_DEPARTURES = {
  name: "room_departures",
  schema: "CREATE TABLE room_departures (player_id TEXT PRIMARY KEY, left_at TEXT NOT NULL)"
} as const;

/**
 * Whether the table exists, looked up once per room instance: every membership
 * check runs on every room request, so a room nobody has left must read no
 * more rows than before. Only this module creates or drops the table.
 */
const tables = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let known = tables.get(storage);
  if (known === undefined) {
    known = storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name=?", ROOM_DEPARTURES.name).toArray().length > 0;
    tables.set(storage, known);
  }
  return known;
}

/**
 * The one membership rule for a room object and every projection read from its
 * storage: the host or the guest, and not someone who left.
 */
export function isMember(storage: DurableObjectStorage, room: { host_id: string | null; guest_id: string | null }, player: string): boolean {
  return (player === room.host_id || player === room.guest_id) && !departed(storage, player);
}

export function departed(storage: DurableObjectStorage, player: string): boolean {
  return present(storage) && storage.sql.exec("SELECT 1 AS found FROM room_departures WHERE player_id=?", player).toArray().length > 0;
}

/** True once any member has left; such a room never returns to play. */
export function anyDeparture(storage: DurableObjectStorage): boolean {
  return present(storage) && storage.sql.exec("SELECT 1 AS found FROM room_departures LIMIT 1").toArray().length > 0;
}

/** The caller owns the room transaction and writes nothing after this. */
export function recordDeparture(storage: DurableObjectStorage, player: string): void {
  storage.sql.exec(ROOM_DEPARTURES.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT OR IGNORE INTO room_departures VALUES (?,?)", player, new Date().toISOString());
  tables.set(storage, true);
}

/** For the full room erase, as its last write: the room's storage goes back to its usual tables. */
export function clearDepartures(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS room_departures");
  tables.set(storage, false);
}
