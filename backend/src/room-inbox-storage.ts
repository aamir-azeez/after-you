/** Operational inbox activity is deliberately kept outside portable gameplay snapshots. */
export const ROOM_INBOX_ACTIVITY = {
  name: "room_inbox_activity",
  schema: "CREATE TABLE room_inbox_activity (player_id TEXT PRIMARY KEY, remote_activity_sequence INTEGER NOT NULL CHECK(remote_activity_sequence >= 1), last_activity_at TEXT NOT NULL)"
} as const;

export function initializeRoomInboxActivity(storage: DurableObjectStorage): void {
  storage.sql.exec(ROOM_INBOX_ACTIVITY.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
}

export function recordRemoteRoomActivity(storage: DurableObjectStorage, actor: string, host: string, guest: string | null): void {
  const recipient = actor === host ? guest : host;
  if (!recipient || recipient === actor) return;
  const current = storage.sql.exec<{ remote_activity_sequence: number }>(
    "SELECT remote_activity_sequence FROM room_inbox_activity WHERE player_id=?", recipient
  ).toArray()[0]?.remote_activity_sequence ?? 0;
  if (current >= Number.MAX_SAFE_INTEGER) throw new Error("room_activity_sequence_exhausted");
  storage.sql.exec("INSERT OR REPLACE INTO room_inbox_activity VALUES (?,?,?)", recipient, current + 1, new Date().toISOString());
}

export function remoteRoomActivity(storage: DurableObjectStorage, player: string): { sequence: number; at: string | null } {
  const row = storage.sql.exec<{ remote_activity_sequence: number; last_activity_at: string }>(
    "SELECT remote_activity_sequence,last_activity_at FROM room_inbox_activity WHERE player_id=?", player
  ).toArray()[0];
  return row ? { sequence: row.remote_activity_sequence, at: row.last_activity_at } : { sequence: 0, at: null };
}

export function clearRoomInboxActivity(storage: DurableObjectStorage): void {
  storage.sql.exec("DELETE FROM room_inbox_activity");
}
