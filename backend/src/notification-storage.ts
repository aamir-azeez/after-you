import { isObject } from "./protocol";
import { BINDING_PATTERN, MAX_REGISTRATIONS, makeHint, validHint, validNotificationToken, MAX_DELIVERY_ATTEMPTS, NOTIFICATION_TTL_MS, type NotificationEnvironment, type TurnHint } from "./notifications";

export const REGISTRATION_TABLE = { name: "notification_registrations", schema: "CREATE TABLE notification_registrations (binding_epoch TEXT PRIMARY KEY, data TEXT NOT NULL)" };
export const OUTBOX_TABLE = { name: "notification_outbox", schema: "CREATE TABLE notification_outbox (recipient_id TEXT PRIMARY KEY, data TEXT NOT NULL)" };
export const ALARM_TABLE = { name: "notification_alarm", schema: "CREATE TABLE notification_alarm (id INTEGER PRIMARY KEY CHECK(id=1), due_at INTEGER NOT NULL)" };
export function notificationTables(kind: string) { return kind === "Player" ? [REGISTRATION_TABLE] : [OUTBOX_TABLE, ALARM_TABLE]; }
/** Workerd v1.20260911.1 creates this protected internal table on setAlarm.
 * Only its exact known schema is accepted; alarm ownership is checked separately. */
export function isAlarmMetadataTable(row: { name: string; sql: string }): boolean {
  return row.name === "_cf_METADATA" && /^CREATE TABLE _cf_METADATA\s*\(\s*key INTEGER PRIMARY KEY,\s*value BLOB\s*\)$/.test(row.sql);
}
export function initializeNotifications(storage: DurableObjectStorage, kind: string): void {
  for (const table of notificationTables(kind)) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
}
type EventRow = { hint: TurnHint; created_at: number; attempts: number; next_at: number };
type RoomMembers = { room_id: string; revision: number; host_id: string; guest_id: string | null };
export type DeliveryResult = { delivered: boolean; retry_after_ms?: number };
function eventRow(value: string): EventRow | null {
  if (value.length > 2048) return null;
  try { const raw: unknown = JSON.parse(value);
    if (!isObject(raw) || Object.keys(raw).length !== 4 || !validHint(raw.hint) || !Number.isSafeInteger(raw.created_at) || Number(raw.created_at) <= 0 ||
      !Number.isSafeInteger(raw.attempts) || Number(raw.attempts) < 0 || Number(raw.attempts) >= MAX_DELIVERY_ATTEMPTS || !Number.isSafeInteger(raw.next_at) || Number(raw.next_at) < Number(raw.created_at)) return null;
    return raw as EventRow;
  } catch { return null; }
}
/** Exact, classified operational tables. Gameplay archive schemas stay unchanged. */
export function notificationAlarmOwned(storage: DurableObjectStorage, kind: string, actual: number | null): boolean {
  if (kind === "Player") {
    const registrations = storage.sql.exec<{ binding_epoch: string; data: string }>("SELECT binding_epoch,data FROM notification_registrations LIMIT 5").toArray();
    if (actual !== null || registrations.length > MAX_REGISTRATIONS) return false;
    const identityRow = storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").toArray()[0];
    const identity = identityRow ? JSON.parse(identityRow.data) : null;
    return registrations.every(row => {
      if (!BINDING_PATTERN.test(row.binding_epoch) || row.data.length > 8192) return false;
      let data: unknown; try { data = JSON.parse(row.data); } catch { return false; }
      return isObject(data) && Object.keys(data).length === 3 && validNotificationToken(data.token) && Number.isSafeInteger(data.updated_at) && Number(data.updated_at) > 0 &&
        isObject(identity) && identity.state === "active" && data.device_hash === identity.device_hash;
    });
  }
  const markers = storage.sql.exec<{ id: number; due_at: number }>("SELECT id,due_at FROM notification_alarm LIMIT 2").toArray();
  const pending = storage.sql.exec<{ recipient_id: string; data: string }>("SELECT recipient_id,data FROM notification_outbox LIMIT 3").toArray();
  if (pending.length > 2 || pending.some(row => !/^[A-Za-z0-9_-]{22}$/.test(row.recipient_id) || !eventRow(row.data))) return false;
  const roomRow = storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0];
  const room = roomRow ? JSON.parse(roomRow.data) : null;
  if (pending.some(item => {
    const hint = eventRow(item.data)!.hint;
    return !isObject(room) || room.room_id !== hint.room_id || Number(room.revision) < Number(hint.revision) ||
      hint.room_family !== (kind === "Room" ? "legacy" : "relay") || (room.host_id !== item.recipient_id && room.guest_id !== item.recipient_id);
  })) return false;
  if (actual === null) return markers.length === 0 && pending.length === 0;
  return markers.length === 1 && markers[0].id === 1 && Number.isSafeInteger(markers[0].due_at) && markers[0].due_at === actual && pending.length > 0 &&
    Math.min(...pending.map(row => eventRow(row.data)!.next_at)) === actual;
}
export function clearRegistrations(storage: DurableObjectStorage): void { storage.sql.exec("DELETE FROM notification_registrations"); }
/** Called in the SAME async SQLite transaction as gameplay or deletion writes. */
export async function scheduleNotifications(storage: DurableObjectStorage): Promise<void> {
  const actual = await storage.getAlarm();
  const marker = storage.sql.exec<{ due_at: number }>("SELECT due_at FROM notification_alarm WHERE id=1").toArray()[0];
  if (actual !== null && (!marker || marker.due_at !== actual)) throw new Error("unowned_notification_alarm");
  const rows = storage.sql.exec<{ data: string }>("SELECT data FROM notification_outbox LIMIT 3").toArray();
  if (!rows.length) { if (marker) { storage.sql.exec("DELETE FROM notification_alarm"); await storage.deleteAlarm(); } return; }
  const values = rows.map(row => eventRow(row.data));
  if (rows.length > 2 || values.some(value => !value)) throw new Error("notification_state_unavailable");
  const due = Math.min(...values.map(value => value!.next_at));
  storage.sql.exec("INSERT OR REPLACE INTO notification_alarm VALUES (1,?)", due); await storage.setAlarm(due);
}
export function queueTurnHint(storage: DurableObjectStorage, env: NotificationEnvironment, family: "legacy" | "relay", room: RoomMembers, actor: string, catchupRecipient?: string): void {
  if (String(env.NOTIFICATIONS_ENABLED) !== "true") return;
  const recipient = catchupRecipient ?? (actor === room.host_id ? room.guest_id : room.host_id);
  if (!recipient || recipient === actor || (recipient !== room.host_id && recipient !== room.guest_id)) return;
  const now = Date.now(), hint = makeHint(family, room.room_id, room.revision);
  const row: EventRow = { hint, created_at: now, attempts: 0, next_at: now + 1000 };
  // Only the newest hint per room/member is useful. This cannot fill gameplay history.
  storage.sql.exec("INSERT OR REPLACE INTO notification_outbox VALUES (?,?)", recipient, JSON.stringify(row));
}
export function clearTurnHints(storage: DurableObjectStorage): void { storage.sql.exec("DELETE FROM notification_outbox"); }
/** Binding-only read: an old send must not survive a deletion, fork or newer hint. */
export function turnHintEligible(storage: DurableObjectStorage, state: RoomMembers | null, recipient: string, hint: TurnHint): boolean {
  if (!state || !validHint(hint) || state.room_id !== hint.room_id || state.revision < Number(hint.revision) || (recipient !== state.host_id && recipient !== state.guest_id)) return false;
  const stored = storage.sql.exec<{ data: string }>("SELECT data FROM notification_outbox WHERE recipient_id=?", recipient).toArray()[0];
  const row = stored ? eventRow(stored.data) : null;
  return !!row && row.hint.event_id === hint.event_id && row.hint.revision === hint.revision && row.hint.room_family === hint.room_family && Date.now() - row.created_at < NOTIFICATION_TTL_MS;
}
/** No provider I/O inside a SQLite transaction. A crash after send may retry the same event ID. */
export async function deliverTurnHints(storage: DurableObjectStorage, env: Env & NotificationEnvironment, current: () => RoomMembers | null): Promise<void> {
  const due = storage.sql.exec<{ recipient_id: string; data: string }>("SELECT recipient_id,data FROM notification_outbox LIMIT 3").toArray();
  if (due.length > 2) throw new Error("notification_state_unavailable");
  for (const item of due) {
    const row = eventRow(item.data); if (!row) throw new Error("notification_state_unavailable");
    if (row.next_at > Date.now()) continue;
    const state = current();
    let result: DeliveryResult = { delivered: true };
    const eligible = String(env.NOTIFICATIONS_ENABLED) === "true" && state && state.room_id === row.hint.room_id && state.revision >= Number(row.hint.revision) &&
      (item.recipient_id === state.host_id || item.recipient_id === state.guest_id) && Date.now() - row.created_at < NOTIFICATION_TTL_MS;
    if (eligible) {
      try { result = await env.PLAYERS.getByName(item.recipient_id).deliverTurnNotification(row.hint); }
      catch { result = { delivered: false }; }
    }
    await storage.transaction(async () => {
      // New turn, deletion, or fork may have replaced this row during the send.
      const live = storage.sql.exec<{ data: string }>("SELECT data FROM notification_outbox WHERE recipient_id=?", item.recipient_id).toArray()[0];
      if (!live || live.data !== item.data) return;
      const attempts = row.attempts + 1;
      if (result.delivered || attempts >= MAX_DELIVERY_ATTEMPTS || Date.now() - row.created_at >= NOTIFICATION_TTL_MS) storage.sql.exec("DELETE FROM notification_outbox WHERE recipient_id=?", item.recipient_id);
      else {
        const delay = Math.min(86_400_000, Math.max(60_000 * 2 ** (attempts - 1), result.retry_after_ms ?? 0));
        storage.sql.exec("UPDATE notification_outbox SET data=? WHERE recipient_id=?", JSON.stringify({ ...row, attempts, next_at: Date.now() + delay }), item.recipient_id);
      }
      await scheduleNotifications(storage);
    });
  }
  // The system consumes the alarm before invoking us, including an early invocation.
  await storage.transaction(async () => { await scheduleNotifications(storage); });
}
/** Keep invalid/outdated snapshots from scheduling historical notifications on restore. */
export async function resetNotificationRuntime(storage: DurableObjectStorage, kind: string): Promise<void> {
  if (kind === "Player") clearRegistrations(storage);
  else { clearTurnHints(storage); storage.sql.exec("DELETE FROM notification_alarm"); await storage.deleteAlarm(); }
}
