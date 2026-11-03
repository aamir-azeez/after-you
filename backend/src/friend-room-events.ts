import { DurableObject } from "cloudflare:workers";
import { flags } from "./flags";
import { ID_PATTERN, isObject, fail, ok, type Outcome } from "./protocol";
import { validSharedFriendRoom, type SharedFriendRoom } from "./friends";
import { clearDecline, declined, dropDeclines, noteDecline } from "./friend-declines";

/** Sent by clients (0.6.1+) that read hosting events correctly. Clients up to 0.6.0
 * parse an event's numbers as floats and reject the whole inbox, so a tapped
 * hosting push there can never be acknowledged and keeps reopening Friends. */
export const FRIEND_EVENTS_HEADER = "X-AfterYou-Friend-Events";
export const friendEventsCapable = (request: Request): boolean => request.headers.get(FRIEND_EVENTS_HEADER) === "2";
/** On unless the var is exactly "false": hosting events then reach only capable clients. */
export const FRIEND_EVENTS_CLIENT_GATE = (env: object): boolean => String(Reflect.get(env, "FRIEND_EVENTS_CLIENT_GATE")) !== "false";
export const FRIEND_ROOM_EVENT_TTL_MS = 24 * 60 * 60 * 1000;
export const FRIEND_ROOM_EVENT_MAX_ATTEMPTS = 6;
export const FRIEND_ROOM_EVENT_MAX_ROWS = 20;
export const FRIEND_ROOM_EVENT_MAX_ACKS = 40;
/**
 * One hosting push per host, room and recipient in this window. A host's newer event for the same room inside it still
 * replaces the in-app row, with no push of its own; the host's route also answers a republish of the same room inside it
 * with the current event (player.ts publishFriendRoom), so nothing new is sent at all. Another room pushes as before.
 */
export const FRIEND_ROOM_PUSH_WINDOW_MS = 15 * 60_000;
/** The inbox shows an event it checked this recently without checking it again (memory only); revokes still remove it at once. */
export const FRIEND_ROOM_EVENT_CHECKED_MS = 60_000;
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
  /** Event ids the inbox read checked, and when (memory only). */
  private readonly checked = new Map<string, number>();
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
      if (await this.ctx.storage.getAlarm() !== null) await this.ctx.storage.deleteAlarm();
      return;
    }
    if (rows.length > FRIEND_ROOM_EVENT_MAX_ROWS) throw new Error("friend_room_events_unavailable");
    const parsed = rows.map(row => checkedRow(row.data));
    if (parsed.some(row => !row)) throw new Error("friend_room_events_unavailable");
    const due = Math.min(...parsed.map(row => Math.min(row!.created_at + FRIEND_ROOM_EVENT_TTL_MS, row!.push_state === "pending" ? row!.next_at : Number.MAX_SAFE_INTEGER)));
    // Writes only on a change: enqueue, revoke and acknowledge all end here.
    const marker = this.ctx.storage.sql.exec<{ due_at: number }>("SELECT due_at FROM friend_room_event_alarm WHERE id=1").toArray()[0]?.due_at ?? null;
    if (marker !== due) this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_event_alarm VALUES (1,?)", due);
    if (await this.ctx.storage.getAlarm() !== due) await this.ctx.storage.setAlarm(due);
  }
  private pruneAcks(now: number): void { this.ctx.storage.sql.exec("DELETE FROM friend_room_event_acks WHERE expires_at<=?", now); }
  /**
   * When the alarm last pushed this host's room to the recipient, 0 for never: a push marker, an ack row named
   * `<host>_0<room>` (an event id has an epoch from 1, so no acknowledgement, enqueue or older code ever matches it),
   * with its time kept as expires_at minus the TTL, so the acks' own pruning removes it.
   */
  private lastPushed(host: string, room: string): number {
    const at = this.ctx.storage.sql.exec<{ expires_at: number }>("SELECT expires_at FROM friend_room_event_acks WHERE event_id=?", `${host}_0${room}`).toArray()[0]?.expires_at;
    return at === undefined ? 0 : at - FRIEND_ROOM_EVENT_TTL_MS;
  }
  /** Notes a push of `row` (lastPushed); the host's markers for its other rooms whose window has passed go. */
  private markPushed(row: QueueRow, now: number): void {
    this.ctx.storage.sql.exec("DELETE FROM friend_room_event_acks WHERE substr(event_id,1,24)=? AND expires_at<=?", `${row.host_id}_0`, now - FRIEND_ROOM_PUSH_WINDOW_MS + FRIEND_ROOM_EVENT_TTL_MS);
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_event_acks VALUES (?,?,?)", `${row.host_id}_0${row.room.room_id}`, row.request_id, now + FRIEND_ROOM_EVENT_TTL_MS);
  }
  /** Binding only (friend-declines.ts): whether this player declined `peer`'s request lately. Reads only. */
  declined(peer: string): boolean { return ID_PATTERN.test(peer) && declined(this.ctx.storage, peer, Date.now()); }
  /** Binding only: this player declined `peer`'s request (DELETE /v1/friends/<id> of a pending incoming one). */
  noteDecline(peer: string): void { if (ID_PATTERN.test(peer)) noteDecline(this.ctx.storage, peer, Date.now()); }
  /** Binding only: this player chose Add for `peer`. Writes only when a decline was held. */
  clearDecline(peer: string): void { if (ID_PATTERN.test(peer)) clearDecline(this.ctx.storage, peer); }
  /** Binding-only. Enqueue is idempotent by host and exact server epoch. */
  async enqueue(event: FriendRoomEvent): Promise<Outcome<{ queued: boolean }>> {
    if (!validEvent(event)) return fail(400, "invalid_friend_notification");
    if (!flags.friendRoomEvents(this.env) || Date.now() - event.published_at >= FRIEND_ROOM_EVENT_TTL_MS) return ok({ queued: false });
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
      // Inside the push window of this host's last push for the same room, the row replaces the old one in the app with no push of its own.
      const quiet = now - this.lastPushed(event.host_id, event.room.room_id) < FRIEND_ROOM_PUSH_WINDOW_MS;
      const row: QueueRow = { ...event, created_at: event.published_at, attempts: 0, next_at: now + 1000, push_state: quiet ? "sent" : "pending" };
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_event_queue VALUES (?,?)", event.host_id, JSON.stringify(row));
      await this.schedule();
      return ok({ queued: true });
    });
  }
  /**
   * Binding-only inbox read; HTTP callers must recheck current relationship and publication, except for an event
   * marked `checked`: one they checked within FRIEND_ROOM_EVENT_CHECKED_MS (noteChecked).
   */
  inbox(): Array<FriendRoomEvent & { checked: boolean }> {
    const rows = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue ORDER BY json_extract(data,'$.published_at') DESC LIMIT 21").toArray();
    if (rows.length > FRIEND_ROOM_EVENT_MAX_ROWS) throw new Error("friend_room_events_unavailable");
    const parsed = rows.map(row => checkedRow(row.data));
    if (parsed.some(row => !row)) throw new Error("friend_room_events_unavailable");
    const now = Date.now();
    for (const [id, at] of this.checked) if (now - at >= FRIEND_ROOM_EVENT_CHECKED_MS || !parsed.some(row => row!.event_id === id)) this.checked.delete(id);
    return parsed.map(row => ({ schema_version: 1, category: "room_available", event_id: row!.event_id, host_id: row!.host_id, recipient_id: row!.recipient_id,
      request_id: row!.request_id, publication_epoch: row!.publication_epoch, room: row!.room, published_at: row!.published_at, checked: this.checked.has(row!.event_id) }));
  }
  /** Binding only: the inbox read checked these events just now. Memory only, at most one entry per queued row. */
  noteChecked(eventIds: string[]): void {
    const now = Date.now();
    for (const id of eventIds.slice(0, FRIEND_ROOM_EVENT_MAX_ROWS)) if (typeof id === "string") this.checked.set(id, now);
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
    for (const id of this.checked.keys()) if (id.startsWith(host + "_")) this.checked.delete(id);
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
      dropDeclines(this.ctx.storage);
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
      if (Date.now() - row.created_at < FRIEND_ROOM_EVENT_TTL_MS && flags.friendRoomEvents(this.env)) {
        try { result = await this.env.PLAYERS.getByName(row.recipient_id).deliverFriendRoomNotification(row); }
        catch { result = { status: "retry" }; }
      }
      await this.ctx.storage.transaction(async () => {
        const live = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue WHERE host_id=?", row.host_id).toArray()[0];
        if (!live || live.data !== item.data) return;
        const attempts = row.attempts + 1;
        if (result.status === "cancelled" || attempts >= FRIEND_ROOM_EVENT_MAX_ATTEMPTS || Date.now() - row.created_at >= FRIEND_ROOM_EVENT_TTL_MS) this.ctx.storage.sql.exec("DELETE FROM friend_room_event_queue WHERE host_id=?", row.host_id);
        else if (result.status === "done") {
          this.ctx.storage.sql.exec("UPDATE friend_room_event_queue SET data=? WHERE host_id=?", JSON.stringify({ ...row, push_state: "sent" }), row.host_id);
          // The push marker (lastPushed), so this host's next event for the room inside the window adds no push.
          this.markPushed(row, Date.now());
        }
        else this.ctx.storage.sql.exec("UPDATE friend_room_event_queue SET data=? WHERE host_id=?", JSON.stringify({ ...row, attempts, next_at: Date.now() + Math.max(backoff(attempts), Math.min(60 * 60_000, result.retry_after_ms ?? 0)) }), row.host_id);
        await this.schedule();
      });
    }
    await this.ctx.storage.transaction(() => this.schedule());
  }
}
