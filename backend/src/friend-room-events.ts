import { DurableObject } from "cloudflare:workers";
import { ID_PATTERN, isObject, fail, ok, type Outcome } from "./protocol";
import { validSharedFriendRoom, type SharedFriendRoom } from "./friends";

export const FRIEND_ROOM_EVENTS_ENABLED = (env: { FRIEND_ROOM_EVENTS_ENABLED?: string }): boolean => String(env.FRIEND_ROOM_EVENTS_ENABLED) === "true";
export const FRIEND_ROOM_EVENT_TTL_MS = 24 * 60 * 60 * 1000;
export const FRIEND_ROOM_EVENT_MAX_ATTEMPTS = 6;
export const FRIEND_ROOM_EVENT_MAX_ROWS = 20;
export const FRIEND_ROOM_EVENT_MAX_ACKS = 40;
const EVENT_SCHEMA = "CREATE TABLE friend_room_event_queue (host_id TEXT PRIMARY KEY, data TEXT NOT NULL)";
const ACK_SCHEMA = "CREATE TABLE friend_room_event_acks (event_id TEXT PRIMARY KEY, request_id TEXT NOT NULL, expires_at INTEGER NOT NULL)";
const ALARM_SCHEMA = "CREATE TABLE friend_room_event_alarm (id INTEGER PRIMARY KEY CHECK(id=1), due_at INTEGER NOT NULL)";
const exact = (v: Record<string, unknown>, keys: string[]) => Object.keys(v).length === keys.length && keys.every(key => Object.hasOwn(v, key));

export type FriendRoomEvent = {
  schema_version: 1; category: "room_available"; event_id: string; host_id: string; recipient_id: string;
  request_id: string; publication_epoch: number; room: SharedFriendRoom; published_at: number;
};
type QueueRow = FriendRoomEvent & { created_at: number; attempts: number; next_at: number; push_state: "pending" | "sent" };
export type FriendRoomDelivery = { status: "done" | "cancelled" | "retry"; retry_after_ms?: number };
function validEvent(value: unknown): value is FriendRoomEvent {
  if (!isObject(value) || !exact(value, ["schema_version", "category", "event_id", "host_id", "recipient_id", "request_id", "publication_epoch", "room", "published_at"])) return false;
  return value.schema_version === 1 && value.category === "room_available" && typeof value.event_id === "string" && /^[A-Za-z0-9_-]{22}_[1-9][0-9]{0,15}$/.test(value.event_id) &&
    typeof value.host_id === "string" && ID_PATTERN.test(value.host_id) && typeof value.recipient_id === "string" && ID_PATTERN.test(value.recipient_id) && value.host_id !== value.recipient_id &&
    typeof value.request_id === "string" && ID_PATTERN.test(value.request_id) && Number.isSafeInteger(value.publication_epoch) && Number(value.publication_epoch) > 0 &&
    validSharedFriendRoom(value.room) && Number.isSafeInteger(value.published_at) && Number(value.published_at) > 0;
}
function checkedRow(raw: string): QueueRow | null {
  if (raw.length > 4096) return null;
  try {
    const value: unknown = JSON.parse(raw);
    if (!isObject(value) || !exact(value, ["schema_version", "category", "event_id", "host_id", "recipient_id", "request_id", "publication_epoch", "room", "published_at", "created_at", "attempts", "next_at", "push_state"])) return null;
    const { created_at, attempts, next_at, push_state, ...event } = value;
    if (!validEvent(event) || !Number.isSafeInteger(created_at) || Number(created_at) <= 0 || !Number.isSafeInteger(attempts) || Number(attempts) < 0 || Number(attempts) >= FRIEND_ROOM_EVENT_MAX_ATTEMPTS || !Number.isSafeInteger(next_at) || Number(next_at) < Number(created_at) || (push_state !== "pending" && push_state !== "sent")) return null;
    return value as QueueRow;
  } catch { return null; }
}
function backoff(attempt: number): number { return Math.min(60 * 60_000, 30_000 * 2 ** Math.max(0, attempt - 1)); }

/** Recipient-owned, bounded in-app queue. Each row is durable before alarm delivery can send push. */
export class FriendRoomEvents extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      for (const schema of [EVENT_SCHEMA, ACK_SCHEMA, ALARM_SCHEMA]) this.ctx.storage.sql.exec(schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
    });
  }
  private async schedule(): Promise<void> {
    const now = Date.now();
    this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue WHERE json_extract(data,'$.created_at')<=?", now - FRIEND_ROOM_EVENT_TTL_MS);
    const rows = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue LIMIT 21").toArray();
    if (!rows.length) {
      this.ctx.storage.sql.exec("DELETE FROM friend_room_event_alarm");
      await this.ctx.storage.deleteAlarm();
      return;
    }
    if (rows.length > FRIEND_ROOM_EVENT_MAX_ROWS) throw new Error("friend_room_events_unavailable");
    const parsed = rows.map(row => checkedRow(row.data));
    if (parsed.some(row => !row)) throw new Error("friend_room_events_unavailable");
    const due = Math.min(...parsed.map(row => Math.min(row!.created_at + FRIEND_ROOM_EVENT_TTL_MS, row!.push_state === "pending" ? row!.next_at : Number.MAX_SAFE_INTEGER)));
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_event_alarm VALUES (1,?)", due);
    await this.ctx.storage.setAlarm(due);
  }
  private pruneAcks(now: number): void { this.ctx.storage.sql.exec("DELETE FROM friend_room_event_acks WHERE expires_at<=?", now); }
  /** Binding-only. Enqueue is idempotent by host and exact server epoch. */
  async enqueue(event: FriendRoomEvent): Promise<Outcome<{ queued: boolean }>> {
    if (!validEvent(event)) return fail(400, "invalid_friend_notification");
    if (!FRIEND_ROOM_EVENTS_ENABLED(this.env) || Date.now() - event.published_at >= FRIEND_ROOM_EVENT_TTL_MS) return ok({ queued: false });
    return this.ctx.storage.transaction(async () => {
      const now = Date.now(); this.pruneAcks(now);
      this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue WHERE json_extract(data,'$.created_at')<=?", now - FRIEND_ROOM_EVENT_TTL_MS);
      const acked = this.ctx.storage.sql.exec("SELECT event_id FROM friend_room_event_acks WHERE event_id=?", event.event_id).toArray().length > 0;
      const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue WHERE host_id=?", event.host_id).toArray()[0];
      if (acked) { await this.schedule(); return ok({ queued: false }); }
      if (old) {
        const existing = checkedRow(old.data);
        if (existing?.event_id === event.event_id) { await this.schedule(); return ok({ queued: true }); }
      } else if (this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM friend_room_event_queue").one().n >= FRIEND_ROOM_EVENT_MAX_ROWS) return fail(409, "friend_event_queue_full");
      const row: QueueRow = { ...event, created_at: event.published_at, attempts: 0, next_at: now + 1000, push_state: "pending" };
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_event_queue VALUES (?,?)", event.host_id, JSON.stringify(row));
      await this.schedule();
      return ok({ queued: true });
    });
  }
  /** Binding-only inbox read; HTTP callers must recheck current relationship and publication. */
  inbox(): FriendRoomEvent[] {
    const rows = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue ORDER BY json_extract(data,'$.published_at') DESC LIMIT 21").toArray();
    if (rows.length > FRIEND_ROOM_EVENT_MAX_ROWS) throw new Error("friend_room_events_unavailable");
    const parsed = rows.map(row => checkedRow(row.data));
    if (parsed.some(row => !row)) throw new Error("friend_room_events_unavailable");
    return parsed.map(row => ({ schema_version: 1, category: "room_available", event_id: row!.event_id, host_id: row!.host_id, recipient_id: row!.recipient_id,
      request_id: row!.request_id, publication_epoch: row!.publication_epoch, room: row!.room, published_at: row!.published_at }));
  }
  /**
   * Idempotent, including after the queued row has already been removed. An event that was
   * cancelled, revoked or expired before the recipient acked is already gone, so acking it is a
   * benign success rather than an error. Clients therefore treat a 404 ack as success too.
   */
  async acknowledge(eventId: string, recipient: string, requestId: string): Promise<Outcome<{ acknowledged: true }>> {
    if (!ID_PATTERN.test(recipient) || !ID_PATTERN.test(requestId) || !/^[A-Za-z0-9_-]{22}_[1-9][0-9]{0,15}$/.test(eventId)) return fail(400, "invalid_friend_notification");
    return this.ctx.storage.transaction(async () => {
      const now = Date.now(); this.pruneAcks(now);
      const queued = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue WHERE json_extract(data,'$.event_id')=?", eventId).toArray()[0];
      if (queued) {
        const row = checkedRow(queued.data);
        if (!row || row.recipient_id !== recipient || row.request_id !== requestId) return fail(409, "friend_event_changed");
      } else {
        const ack = this.ctx.storage.sql.exec<{ request_id: string }>("SELECT request_id FROM friend_room_event_acks WHERE event_id=?", eventId).toArray()[0];
        if (ack && ack.request_id !== requestId) return fail(409, "friend_event_changed");
        return ok({ acknowledged: true });
      }
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_event_acks VALUES (?,?,?)", eventId, requestId, now + FRIEND_ROOM_EVENT_TTL_MS);
      this.ctx.storage.sql.exec("DELETE FROM friend_room_event_acks WHERE event_id IN (SELECT event_id FROM friend_room_event_acks ORDER BY expires_at DESC LIMIT -1 OFFSET ?)", FRIEND_ROOM_EVENT_MAX_ACKS);
      this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue WHERE json_extract(data,'$.event_id')=?", eventId);
      await this.schedule();
      return ok({ acknowledged: true });
    });
  }
  /** Binding-only delivery guard; acked or replaced events cannot reach FCM. */
  isPending(recipient: string, eventId: string): boolean {
    if (!ID_PATTERN.test(recipient)) return false;
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue WHERE json_extract(data,'$.event_id')=?", eventId).toArray()[0];
    const value = row ? checkedRow(row.data) : null;
    return !!value && value.recipient_id === recipient && Date.now() - value.created_at < FRIEND_ROOM_EVENT_TTL_MS;
  }
  /** Binding-only cancellation. A newer epoch replaces the same publisher row. */
  async revoke(host: string, eventId?: string): Promise<void> {
    if (!ID_PATTERN.test(host)) return;
    await this.ctx.storage.transaction(async () => {
      if (eventId) this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue WHERE host_id=? AND json_extract(data,'$.event_id')=?", host, eventId);
      else this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue WHERE host_id=?", host);
      await this.schedule();
    });
  }
  async clearRecipient(recipient: string): Promise<void> {
    if (!ID_PATTERN.test(recipient)) return;
    await this.ctx.storage.transaction(async () => {
      this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue");
      this.ctx.storage.sql.exec("DELETE FROM friend_room_event_acks");
      await this.schedule();
    });
  }
  async alarm(): Promise<void> {
    const all = this.ctx.storage.sql.exec<{ host_id: string; data: string }>("SELECT host_id,data FROM friend_room_event_queue LIMIT 21").toArray();
    for (const item of all) { const row = checkedRow(item.data); if (!row) throw new Error("friend_room_events_unavailable"); if (Date.now() - row.created_at >= FRIEND_ROOM_EVENT_TTL_MS) this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue WHERE host_id=?", row.host_id); }
    const due = this.ctx.storage.sql.exec<{ host_id: string; data: string }>("SELECT host_id,data FROM friend_room_event_queue WHERE json_extract(data,'$.push_state')='pending' ORDER BY json_extract(data,'$.next_at') LIMIT 21").toArray();
    if (due.length > FRIEND_ROOM_EVENT_MAX_ROWS) throw new Error("friend_room_events_unavailable");
    for (const item of due) {
      const row = checkedRow(item.data); if (!row) throw new Error("friend_room_events_unavailable");
      if (row.next_at > Date.now()) break;
      let result: FriendRoomDelivery = { status: "cancelled" };
      if (Date.now() - row.created_at < FRIEND_ROOM_EVENT_TTL_MS && FRIEND_ROOM_EVENTS_ENABLED(this.env)) {
        try { result = await this.env.PLAYERS.getByName(row.recipient_id).deliverFriendRoomNotification(row); }
        catch { result = { status: "retry" }; }
      }
      await this.ctx.storage.transaction(async () => {
        const live = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue WHERE host_id=?", row.host_id).toArray()[0];
        if (!live || live.data !== item.data) return;
        const attempts = row.attempts + 1;
        if (result.status === "cancelled" || attempts >= FRIEND_ROOM_EVENT_MAX_ATTEMPTS || Date.now() - row.created_at >= FRIEND_ROOM_EVENT_TTL_MS) this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue WHERE host_id=?", row.host_id);
        else if (result.status === "done") this.ctx.storage.sql.exec("UPDATE friend_room_event_queue SET data=? WHERE host_id=?", JSON.stringify({ ...row, push_state: "sent" }), row.host_id);
        else this.ctx.storage.sql.exec("UPDATE friend_room_event_queue SET data=? WHERE host_id=?", JSON.stringify({ ...row, attempts, next_at: Date.now() + Math.max(backoff(attempts), Math.min(60 * 60_000, result.retry_after_ms ?? 0)) }), row.host_id);
        await this.schedule();
      });
    }
    await this.ctx.storage.transaction(() => this.schedule());
  }
}
