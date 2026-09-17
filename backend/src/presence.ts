import { ApiError, HASH_PATTERN, isObject } from "./protocol";
import { safetyMembers } from "./safety-routes";
import { interactionBlocked } from "./safety";

export const PRESENCE_SESSION = /^[a-f0-9]{36}$/;
export const PRESENCE_HEARTBEAT_SECONDS = 30;
export const PRESENCE_TTL_MS = 90_000;
export const MAX_PRESENCE_SESSIONS = 8;
export const PRESENCE_TABLES = [
  { name: "presence_leases", schema: "CREATE TABLE presence_leases (session_id TEXT PRIMARY KEY, device_hash TEXT NOT NULL, expires_at INTEGER NOT NULL)" },
  { name: "presence_alarm", schema: "CREATE TABLE presence_alarm (id INTEGER PRIMARY KEY CHECK(id=1), due_at INTEGER NOT NULL)" }
] as const;
type Lease = { session_id: string; device_hash: string; expires_at: number };
export type PresencePolicy = { schema_version: 1; heartbeat_seconds: 30; expires_after_seconds: 90 };
export type RoomPresence = { schema_version: 1; partner_joined: boolean; partner_online: boolean; expires_after_seconds: number };
export const presenceEnabled = (env: Env) => String(env.PRESENCE_ENABLED) === "true";
export const presencePolicy = (): PresencePolicy => ({ schema_version: 1, heartbeat_seconds: PRESENCE_HEARTBEAT_SECONDS, expires_after_seconds: 90 });
export function initializePresence(storage: DurableObjectStorage): void {
  for (const table of PRESENCE_TABLES) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
}
/** Revocation is synchronous with identity rotation/deletion. The owned alarm
 * may remain until its imminent cleanup, but no session remains visible. */
export function clearPresence(storage: DurableObjectStorage): void { storage.sql.exec("DELETE FROM presence_leases"); }
export function prunePresence(storage: DurableObjectStorage, now = Date.now()): void {
  storage.sql.exec("DELETE FROM presence_leases WHERE expires_at<=?", now);
}
/** Only this exact operational state may be omitted from portable snapshots.
 * An earlier alarm is valid after a read prunes expired leases or identity
 * rotation removes them. Unowned alarms and malformed rows remain a hold. */
export function presenceAlarmOwned(storage: DurableObjectStorage, actual: number | null, consumed = false): boolean {
  const leases = storage.sql.exec<Lease>("SELECT session_id,device_hash,expires_at FROM presence_leases LIMIT 9").toArray();
  const markers = storage.sql.exec<{ id: number; due_at: number }>("SELECT id,due_at FROM presence_alarm LIMIT 2").toArray();
  const raw = storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").toArray()[0];
  let identity: unknown = null; try { if (raw) identity = JSON.parse(raw.data); } catch { return false; }
  if (leases.length > MAX_PRESENCE_SESSIONS || leases.some(row => !PRESENCE_SESSION.test(row.session_id) || !HASH_PATTERN.test(row.device_hash) ||
    !Number.isSafeInteger(row.expires_at) || row.expires_at <= 0 || !isObject(identity) || identity.state !== "active" || row.device_hash !== identity.device_hash)) return false;
  if (!markers.length) return actual === null && leases.length === 0;
  if (markers.length !== 1 || markers[0].id !== 1 || !Number.isSafeInteger(markers[0].due_at) || markers[0].due_at <= 0) return false;
  return (actual === markers[0].due_at || (consumed && actual === null)) && leases.every(row => markers[0].due_at <= row.expires_at);
}
/** Caller owns one SQLite transaction and has already verified alarm ownership. */
export async function schedulePresence(storage: DurableObjectStorage): Promise<void> {
  const next = storage.sql.exec<{ due_at: number | null }>("SELECT MIN(expires_at) AS due_at FROM presence_leases").one().due_at;
  if (next === null) { storage.sql.exec("DELETE FROM presence_alarm"); await storage.deleteAlarm(); return; }
  storage.sql.exec("INSERT OR REPLACE INTO presence_alarm VALUES (1,?)", next);
  await storage.setAlarm(next);
}
export async function resetPresence(storage: DurableObjectStorage): Promise<void> {
  clearPresence(storage); storage.sql.exec("DELETE FROM presence_alarm"); await storage.deleteAlarm();
}
/** The only public read is through a room both identities actually share. */
export async function roomPresence(env: Env, owner: string, deviceHash: string, family: "legacy" | "relay", roomId: string): Promise<RoomPresence> {
  const members = await safetyMembers(env, owner, family, roomId);
  if (await interactionBlocked(env, members.host_id, members.guest_id)) throw new ApiError(403, "player_blocked");
  if (!presenceEnabled(env)) throw new ApiError(503, "presence_unavailable");
  const partner = owner === members.host_id ? members.guest_id : members.host_id;
  const expires = partner ? await env.PLAYERS.getByName(partner).presenceExpiry(partner) : 0;
  // A peer deletion or block may complete while the presence RPC is suspended.
  const current = await safetyMembers(env, owner, family, roomId);
  if (current.host_id !== members.host_id || current.guest_id !== members.guest_id) throw new ApiError(409, "room_membership_changed");
  if (await interactionBlocked(env, current.host_id, current.guest_id)) throw new ApiError(403, "player_blocked");
  if (!await env.PLAYERS.getByName(owner).authorize(deviceHash)) throw new ApiError(401, "invalid_auth");
  const seconds = Math.max(0, Math.min(90, Math.ceil((expires - Date.now()) / 1000)));
  return { schema_version: 1, partner_joined: partner !== null, partner_online: seconds > 0, expires_after_seconds: seconds };
}
