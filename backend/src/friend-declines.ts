/**
 * Friend requests a player declined, kept in that player's own FriendRoomEvents object (friend-room-events.ts),
 * whose storage no older code checks or exports, so this sets no rollback floor. The same player's request is
 * refused as unavailable for FRIEND_DECLINE_MS after a decline (Friends, Decline on an incoming request), so a
 * decline is not answered by the same request again at once. Choosing Add for that player clears it.
 *
 * The table is made by the first decline, never for a player who never declined, holds at most
 * MAX_FRIEND_DECLINES rows (the oldest go first), and goes with the player's other friend events at erasure.
 */
export const FRIEND_DECLINE_MS = 7 * 24 * 60 * 60 * 1000;
export const MAX_FRIEND_DECLINES = 64;
const SCHEMA = "CREATE TABLE friend_declines (player_id TEXT PRIMARY KEY, until INTEGER NOT NULL) WITHOUT ROWID";
const known = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let found = known.get(storage);
  if (found === undefined) {
    found = storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name='friend_declines'").toArray().length > 0;
    known.set(storage, found);
  }
  return found;
}
/** Whether `peer`'s requests are still refused after a decline. Reads one row at most. */
export function declined(storage: DurableObjectStorage, peer: string, now: number): boolean {
  if (!present(storage)) return false;
  return (storage.sql.exec<{ until: number }>("SELECT until FROM friend_declines WHERE player_id=?", peer).toArray()[0]?.until ?? 0) > now;
}
export function noteDecline(storage: DurableObjectStorage, peer: string, now: number): void {
  if (!present(storage)) { storage.sql.exec(SCHEMA.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ")); known.set(storage, true); }
  storage.sql.exec("DELETE FROM friend_declines WHERE until<=?", now);
  storage.sql.exec("INSERT OR REPLACE INTO friend_declines VALUES (?,?)", peer, now + FRIEND_DECLINE_MS);
  storage.sql.exec("DELETE FROM friend_declines WHERE player_id IN (SELECT player_id FROM friend_declines ORDER BY until DESC LIMIT -1 OFFSET ?)", MAX_FRIEND_DECLINES);
}
/** The player chose Add for `peer`: their earlier decline no longer holds. Writes only when there was one. */
export function clearDecline(storage: DurableObjectStorage, peer: string): void {
  if (present(storage) && storage.sql.exec("SELECT 1 FROM friend_declines WHERE player_id=?", peer).toArray().length) storage.sql.exec("DELETE FROM friend_declines WHERE player_id=?", peer);
}
export function dropDeclines(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS friend_declines"); known.delete(storage);
}
