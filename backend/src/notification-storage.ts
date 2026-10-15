import { isObject } from "./protocol";
import { BINDING_PATTERN, validIosRegistration, MAX_REGISTRATIONS, makeHint, makeRedoHint, validRoomHint, validNotificationToken, MAX_DELIVERY_ATTEMPTS, NOTIFICATION_TTL_MS, type NotificationEnvironment, type RoomHint } from "./notifications";
import { redoState, type RedoSource } from "./redo-control";
import { checkedFriendPublication, checkedFriendSubscription, FRIEND_PUBLICATION_OPS_TABLE, FRIEND_PUBLICATION_TABLE, FRIEND_SUBSCRIPTIONS_TABLE, MAX_FRIEND_SUBSCRIPTIONS, MAX_PUBLICATION_RECEIPTS } from "./friend-room-event-storage";

export const REGISTRATION_TABLE = { name: "notification_registrations", schema: "CREATE TABLE notification_registrations (binding_epoch TEXT PRIMARY KEY, data TEXT NOT NULL)" };
/** One row per registration that opted into redo-request pushes. Absent row = off. */
export const CATEGORY_TABLE = { name: "notification_categories", schema: "CREATE TABLE notification_categories (binding_epoch TEXT PRIMARY KEY, data TEXT NOT NULL)" };
export const OUTBOX_TABLE = { name: "notification_outbox", schema: "CREATE TABLE notification_outbox (recipient_id TEXT PRIMARY KEY, data TEXT NOT NULL)" };
export const ALARM_TABLE = { name: "notification_alarm", schema: "CREATE TABLE notification_alarm (id INTEGER PRIMARY KEY CHECK(id=1), due_at INTEGER NOT NULL)" };
export function notificationTables(kind: string) { return kind === "Player" ? [REGISTRATION_TABLE, CATEGORY_TABLE, FRIEND_PUBLICATION_TABLE, FRIEND_PUBLICATION_OPS_TABLE, FRIEND_SUBSCRIPTIONS_TABLE] : [OUTBOX_TABLE, ALARM_TABLE]; }
/** Workerd v1.20260911.1 creates this protected internal table on setAlarm.
 * Only its exact known schema is accepted; alarm ownership is checked separately. */
export function isAlarmMetadataTable(row: { name: string; sql: string }): boolean {
  return row.name === "_cf_METADATA" && /^CREATE TABLE _cf_METADATA\s*\(\s*key INTEGER PRIMARY KEY,\s*value BLOB\s*\)$/.test(row.sql);
}
export function initializeNotifications(storage: DurableObjectStorage, kind: string): void {
  for (const table of notificationTables(kind)) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
}
type EventRow = { hint: RoomHint; created_at: number; attempts: number; next_at: number };
type RoomMembers = { room_id: string; revision: number; host_id: string; guest_id: string | null };
export type DeliveryResult = { delivered: boolean; retry_after_ms?: number };
function eventRow(value: string): EventRow | null {
  if (value.length > 2048) return null;
  try { const raw: unknown = JSON.parse(value);
    if (!isObject(raw) || Object.keys(raw).length !== 4 || !validRoomHint(raw.hint) || !Number.isSafeInteger(raw.created_at) || Number(raw.created_at) <= 0 ||
      !Number.isSafeInteger(raw.attempts) || Number(raw.attempts) < 0 || Number(raw.attempts) >= MAX_DELIVERY_ATTEMPTS || !Number.isSafeInteger(raw.next_at) || Number(raw.next_at) < Number(raw.created_at)) return null;
    return raw as EventRow;
  } catch { return null; }
}
export function validCategoryRow(row: { binding_epoch: string; data: string }): boolean {
  if (!BINDING_PATTERN.test(row.binding_epoch) || row.data.length > 256) return false;
  try { const data: unknown = JSON.parse(row.data);
    return isObject(data) && Object.keys(data).length === 3 && data.schema_version === 1 && data.redo_requests === true && Number.isSafeInteger(data.updated_at) && Number(data.updated_at) > 0;
  } catch { return false; }
}
/** A registration row has token, device_hash and updated_at, plus friend_events:2 when a
 * client that reads hosting events registered it (0.6.1+), plus platform and categories
 * together when the iOS app registered it. No other key is accepted. */
function validRegistrationKeys(data: Record<string, unknown>): boolean {
  const extra = Object.keys(data).filter(key => !["token", "device_hash", "updated_at"].includes(key));
  if ((extra.includes("platform") || extra.includes("categories")) && !validIosRegistration(data)) return false;
  return Object.keys(data).length - extra.length === 3 && extra.every(key => key === "friend_events" ? data.friend_events === 2 : key === "platform" || key === "categories");
}
/** Registrations are deleted in several places; a category row without one is inert and removed here. */
export function pruneNotificationCategories(storage: DurableObjectStorage): void {
  storage.sql.exec("DELETE FROM notification_categories WHERE binding_epoch NOT IN (SELECT binding_epoch FROM notification_registrations)");
}
/** Exact, classified operational tables. Gameplay archive schemas stay unchanged. */
export function notificationAlarmOwned(storage: DurableObjectStorage, kind: string, actual: number | null, consumedForDeletion = false): boolean {
  if (kind === "Player") {
    const registrations = storage.sql.exec<{ binding_epoch: string; data: string }>("SELECT binding_epoch,data FROM notification_registrations LIMIT 5").toArray();
    if (actual !== null || registrations.length > MAX_REGISTRATIONS) return false;
    const categories = storage.sql.exec<{ binding_epoch: string; data: string }>("SELECT binding_epoch,data FROM notification_categories LIMIT 5").toArray();
    if (categories.length > MAX_REGISTRATIONS || !categories.every(validCategoryRow)) return false;
    const identityRow = storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").toArray()[0];
    const identity = identityRow ? JSON.parse(identityRow.data) : null;
    const publication = storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_publication WHERE id=1").toArray();
    const operations = storage.sql.exec<{ publication_id: string; data: string }>("SELECT publication_id,data FROM friend_room_publication_ops LIMIT 21").toArray();
    const subscriptions = storage.sql.exec<{ host_id: string; data: string }>("SELECT host_id,data FROM friend_room_subscriptions LIMIT 21").toArray();
    if (publication.length > 1 || operations.length > MAX_PUBLICATION_RECEIPTS || subscriptions.length > MAX_FRIEND_SUBSCRIPTIONS) return false;
    if (publication.some(row => {
      try { const state: unknown = JSON.parse(row.data); return !isObject(state) || Object.keys(state).length !== 3 || state.schema_version !== 1 || !Number.isSafeInteger(state.epoch_counter) || Number(state.epoch_counter) < 0 ||
        !(state.current === null || checkedFriendPublication(JSON.stringify(state.current)) !== null && (state.current as { publication_epoch: number }).publication_epoch <= Number(state.epoch_counter)); }
      catch { return true; }
    })) return false;
    if (operations.some(row => !/^[A-Za-z0-9_-]{22}$/.test(row.publication_id) || checkedFriendPublication(row.data)?.publication_id !== row.publication_id) ||
      subscriptions.some(row => !/^[A-Za-z0-9_-]{22}$/.test(row.host_id) || !checkedFriendSubscription(row.data))) return false;
    return registrations.every(row => {
      if (!BINDING_PATTERN.test(row.binding_epoch) || row.data.length > 8192) return false;
      let data: unknown; try { data = JSON.parse(row.data); } catch { return false; }
      return isObject(data) && validRegistrationKeys(data) && validNotificationToken(data.token) && Number.isSafeInteger(data.updated_at) && Number(data.updated_at) > 0 &&
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
  if (actual === null) {
    if (markers.length === 0 && pending.length === 0) return true;
    // Older Story commits scheduled hints although their alarm handler could not
    // deliver them. Authorized campaign deletion may consume only that exact,
    // overdue operational state; ordinary ownership checks remain strict.
    if (!consumedForDeletion || markers.length !== 1 || !Number.isSafeInteger(markers[0].due_at) ||
      markers[0].due_at <= 0 || markers[0].due_at > Date.now()) return false;
    actual = markers[0].due_at;
  }
  return markers.length === 1 && markers[0].id === 1 && Number.isSafeInteger(markers[0].due_at) && markers[0].due_at === actual && pending.length > 0 &&
    Math.min(...pending.map(row => eventRow(row.data)!.next_at)) === actual;
}
export function clearRegistrations(storage: DurableObjectStorage): void { storage.sql.exec("DELETE FROM notification_registrations"); storage.sql.exec("DELETE FROM notification_categories"); }
/** Called in the SAME async SQLite transaction as gameplay or deletion writes.
 * allowMutation must be a pure read of this DO's persisted state. Callers retain
 * the default storage input gates (no allowConcurrency); this is not an external
 * or mutable in-memory authorization callback. */
export async function scheduleNotifications(storage: DurableObjectStorage, allowMutation: () => boolean = () => true): Promise<void> {
  const actual = await storage.getAlarm();
  if (!allowMutation()) return;
  const marker = storage.sql.exec<{ due_at: number }>("SELECT due_at FROM notification_alarm WHERE id=1").toArray()[0];
  if (actual !== null && (!marker || marker.due_at !== actual)) throw new Error("unowned_notification_alarm");
  const rows = storage.sql.exec<{ data: string }>("SELECT data FROM notification_outbox LIMIT 3").toArray();
  if (!rows.length) { if (marker) { storage.sql.exec("DELETE FROM notification_alarm"); await storage.deleteAlarm(); } return; }
  const values = rows.map(row => eventRow(row.data));
  if (rows.length > 2 || values.some(value => !value)) throw new Error("notification_state_unavailable");
  const due = Math.min(...values.map(value => value!.next_at));
  storage.sql.exec("INSERT OR REPLACE INTO notification_alarm VALUES (1,?)", due); await storage.setAlarm(due);
}
/** How soon a repair alarm runs after a gameplay write could not schedule its hint. */
export const NOTIFICATION_REPAIR_DELAY_MS = 1000;
/**
 * For gameplay writes (turns, forks, joins, redo requests). The queued hint stays in the
 * same transaction even when the alarm bookkeeping fails, so a turn never fails over a
 * notification. If no alarm is set, a repair alarm is armed; once it fires the system has
 * consumed it, and the handler's own schedule rewrites a consistent marker and alarm.
 */
export async function scheduleGameplayNotifications(storage: DurableObjectStorage): Promise<void> {
  try { await scheduleNotifications(storage); }
  catch {
    try { if (await storage.getAlarm() === null) await storage.setAlarm(Date.now() + NOTIFICATION_REPAIR_DELAY_MS); }
    catch { /* The next gameplay write or alarm tries again. */ }
  }
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
/** Same outbox slot as turn hints: a later turn by the requester replaces it, and a fork clears it. */
export function queueRedoHint(storage: DurableObjectStorage, env: NotificationEnvironment, family: "legacy" | "relay", room: RoomMembers, recipient: string, requestId: string): boolean {
  if (String(env.NOTIFICATIONS_ENABLED) !== "true" || (recipient !== room.host_id && recipient !== room.guest_id)) return false;
  const now = Date.now(), hint = makeRedoHint(family, room.room_id, room.revision, requestId);
  const row: EventRow = { hint, created_at: now, attempts: 0, next_at: now + 1000 };
  storage.sql.exec("INSERT OR REPLACE INTO notification_outbox VALUES (?,?)", recipient, JSON.stringify(row));
  return true;
}
export function clearTurnHints(storage: DurableObjectStorage): void { storage.sql.exec("DELETE FROM notification_outbox"); }
/** Binding-only read: an old send must not survive a deletion, fork or newer hint. */
export function turnHintEligible(storage: DurableObjectStorage, state: RoomMembers | null, recipient: string, hint: RoomHint): boolean {
  if (!state || !validRoomHint(hint) || state.room_id !== hint.room_id || state.revision < Number(hint.revision) || (recipient !== state.host_id && recipient !== state.guest_id)) return false;
  const stored = storage.sql.exec<{ data: string }>("SELECT data FROM notification_outbox WHERE recipient_id=?", recipient).toArray()[0];
  const row = stored ? eventRow(stored.data) : null;
  return !!row && row.hint.event_id === hint.event_id && row.hint.revision === hint.revision && row.hint.room_family === hint.room_family && Date.now() - row.created_at < NOTIFICATION_TTL_MS;
}
/** A redo hint is sent only while its exact request is still pending and addressed to the first player. */
export function redoHintCurrent(storage: DurableObjectStorage, source: RedoSource | null, recipient: string, hint: RoomHint): boolean {
  if (hint.kind !== "redo_requested") return true;
  if (!source || source.first_player_id !== recipient) return false;
  try { const request = redoState(storage, source).request; return request?.status === "pending" && `redo_${request.request_id}` === hint.event_id; }
  catch { return false; }
}
/** No provider I/O inside a SQLite transaction. A crash after send may retry the same event ID.
 * The same persisted-state callback contract as scheduleNotifications applies;
 * recheck it inside the write transaction after every awaited provider delivery. */
export async function deliverTurnHints(storage: DurableObjectStorage, env: Env & NotificationEnvironment, current: () => RoomMembers | null, allowMutation: () => boolean = () => true): Promise<void> {
  if (!allowMutation()) return;
  const due = storage.sql.exec<{ recipient_id: string; data: string }>("SELECT recipient_id,data FROM notification_outbox LIMIT 3").toArray();
  if (due.length > 2) throw new Error("notification_state_unavailable");
  for (const item of due) {
    if (!allowMutation()) return;
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
      if (!allowMutation()) return;
      // New turn, deletion, or fork may have replaced this row during the send.
      const live = storage.sql.exec<{ data: string }>("SELECT data FROM notification_outbox WHERE recipient_id=?", item.recipient_id).toArray()[0];
      if (!live || live.data !== item.data) return;
      const attempts = row.attempts + 1;
      if (result.delivered || attempts >= MAX_DELIVERY_ATTEMPTS || Date.now() - row.created_at >= NOTIFICATION_TTL_MS) storage.sql.exec("DELETE FROM notification_outbox WHERE recipient_id=?", item.recipient_id);
      else {
        const delay = Math.min(86_400_000, Math.max(60_000 * 2 ** (attempts - 1), result.retry_after_ms ?? 0));
        storage.sql.exec("UPDATE notification_outbox SET data=? WHERE recipient_id=?", JSON.stringify({ ...row, attempts, next_at: Date.now() + delay }), item.recipient_id);
      }
      await scheduleNotifications(storage, allowMutation);
    });
  }
  // The system consumes the alarm before invoking us, including an early invocation.
  await storage.transaction(async () => { if (allowMutation()) await scheduleNotifications(storage, allowMutation); });
}
/** Keep invalid/outdated snapshots from scheduling historical notifications on restore. */
export async function resetNotificationRuntime(storage: DurableObjectStorage, kind: string): Promise<void> {
  if (kind === "Player") {
    clearRegistrations(storage);
    storage.sql.exec("DELETE FROM friend_room_publication");
    storage.sql.exec("DELETE FROM friend_room_publication_ops");
    storage.sql.exec("DELETE FROM friend_room_subscriptions");
  }
  else { clearTurnHints(storage); storage.sql.exec("DELETE FROM notification_alarm"); await storage.deleteAlarm(); }
}
