import { fail, ok, type Outcome } from "./protocol";
import { errorCode, logWarning } from "./log";
import { roomLinkVersion, type RoomLink } from "./room-links";
import { partnerBlocks } from "./safety";
import { remoteRoomActivity } from "./room-inbox-storage";
import { departed, isMember } from "./room-departure";
import { chapter } from "./v2/chapters";
import { partnerFace, type Face } from "./v2/end-reactions";

export type RoomInboxStatus = "waiting_for_friend" | "your_turn" | "waiting_for_their_turn" | "completed" | "unavailable" | "closed";
/** Clients from 0.5.2 send this header and understand the "closed" status; older clients validate the status list exactly. */
export const ROOM_INBOX_CLOSED_HEADER = "X-AfterYou-Room-Inbox";
/** Clients that offer Leave room send this ("1"); while finishedRoomLeave is on, a room the other member left then carries partner_left. */
export const ROOM_INBOX_LEAVE_HEADER = "X-AfterYou-Room-Leave";
export type RoomInboxEntry = {
  room_id: string; family: "legacy" | "relay" | "story" | "unknown"; api_version: number;
  chapter: { id: string | null; version: number | null };
  membership: { host_id: string | null; guest_id: string | null; you_are_host: boolean };
  status: RoomInboxStatus; revision: number | null; remote_activity_sequence: number; activity_at: string | null;
  /** Only for clients that send ROOM_INBOX_LEAVE_HEADER: the other member left this finished room. */
  partner_left?: true;
  /** Only for clients that send END_REACTIONS_HEADER while end reactions are on: the face on the other member's latest turn. */
  partner_reaction?: Face;
};
export type RoomInboxProjection = Omit<RoomInboxEntry, "family" | "api_version">;

/** A room erased by a member (closed, or their identity deleted) keeps only a tombstone row. */
function closedRoom(storage: DurableObjectStorage): boolean {
  return storage.sql.exec("SELECT 1 AS closed FROM room WHERE id=1 AND json_extract(data,'$.deleted') IS 1").toArray().length > 0;
}

function partnerLeft(storage: DurableObjectStorage, row: { host_id: string; guest_id: string | null }, player: string): { partner_left?: true } {
  const partner = player === row.host_id ? row.guest_id : row.host_id;
  return partner !== null && departed(storage, partner) ? { partner_left: true } : {};
}

function turnStatus(player: string, guest: string | null, active: string | null): RoomInboxStatus {
  if (!guest) return "waiting_for_friend";
  if (!active) return "completed";
  return active === player ? "your_turn" : "waiting_for_their_turn";
}

/** Legacy room summary reads only scalar JSON fields and the separate activity row. */
export function legacyInboxProjection(storage: DurableObjectStorage, player: string): Outcome<RoomInboxProjection> {
  const row = storage.sql.exec<{
    room_id: string; revision: number; level_id: string; host_id: string; guest_id: string | null;
    first_player_id: string; active_role: string; updated_at: string;
  }>("SELECT json_extract(data,'$.room_id') AS room_id,json_extract(data,'$.revision') AS revision,json_extract(data,'$.level_id') AS level_id,json_extract(data,'$.host_id') AS host_id,json_extract(data,'$.guest_id') AS guest_id,json_extract(data,'$.first_player_id') AS first_player_id,json_extract(data,'$.active_role') AS active_role,json_extract(data,'$.updated_at') AS updated_at FROM room WHERE id=1 AND json_extract(data,'$.deleted') IS NOT 1").toArray()[0];
  if (!row && closedRoom(storage)) return fail(410, "room_closed");
  if (!row || !isMember(storage, row, player)) return fail(404, "room_not_found");
  const active = row.active_role === "complete" ? null : row.active_role === "a" ? row.first_player_id : row.first_player_id === row.host_id ? row.guest_id : row.host_id;
  const activity = remoteRoomActivity(storage, player);
  return ok({
    room_id: row.room_id, chapter: { id: row.level_id, version: 1 },
    membership: { host_id: row.host_id, guest_id: row.guest_id, you_are_host: row.host_id === player },
    status: turnStatus(player, row.guest_id, active), revision: row.revision,
    remote_activity_sequence: activity.sequence, activity_at: row.updated_at ?? activity.at, ...partnerLeft(storage, row, player)
  });
}

/**
 * Relay-family projection also selects only small room metadata, never turn or pair data,
 * except that a room which holds end reactions also looks up the other member's latest
 * turn id for their face (v2/end-reactions.ts partnerFace); other rooms read nothing more.
 * A room whose replay both members saved keeps these fields in its compacted row, so it
 * still reads as the finished chapter rather than an unknown room.
 */
export function relayInboxProjection(storage: DurableObjectStorage, player: string): Outcome<RoomInboxProjection> {
  const row = storage.sql.exec<{
    room_id: string; revision: number; stage_index: number; level_id: string; level_version: number;
    definition_hash: string; host_id: string; guest_id: string | null; a_turn_id: string | null; updated_at: string;
  }>("SELECT json_extract(data,'$.room_id') AS room_id,json_extract(data,'$.revision') AS revision,json_extract(data,'$.stage_index') AS stage_index,json_extract(data,'$.level_id') AS level_id,json_extract(data,'$.level_version') AS level_version,json_extract(data,'$.definition_hash') AS definition_hash,json_extract(data,'$.host_id') AS host_id,json_extract(data,'$.guest_id') AS guest_id,json_extract(data,'$.a_turn_id') AS a_turn_id,json_extract(data,'$.updated_at') AS updated_at FROM room WHERE id=1 AND json_extract(data,'$.deleted') IS NOT 1").toArray()[0];
  if (!row && closedRoom(storage)) return fail(410, "room_closed");
  if (!row || !isMember(storage, row, player)) return fail(404, "room_not_found");
  let active: string | null = null;
  try {
    const selected = chapter({ level_id: row.level_id, level_version: row.level_version, definition_hash: row.definition_hash });
    const stage = selected.stages[row.stage_index];
    if (stage) {
      const first = stage.first_player_slot === "p0" ? row.host_id : row.guest_id;
      const second = stage.first_player_slot === "p0" ? row.guest_id : row.host_id;
      active = row.a_turn_id ? second : first;
    }
  } catch { return fail(409, "unsupported_chapter"); }
  const activity = remoteRoomActivity(storage, player);
  return ok({
    room_id: row.room_id, chapter: { id: row.level_id, version: row.level_version },
    membership: { host_id: row.host_id, guest_id: row.guest_id, you_are_host: row.host_id === player },
    status: turnStatus(player, row.guest_id, active), revision: row.revision,
    remote_activity_sequence: activity.sequence, activity_at: row.updated_at ?? activity.at, ...partnerLeft(storage, row, player), ...partnerReaction(storage, row, player)
  });
}

/** The face the other member sent with their latest turn, if any (v2/end-reactions.ts). */
function partnerReaction(storage: DurableObjectStorage, row: { host_id: string; guest_id: string | null }, player: string): { partner_reaction?: Face } {
  const face = partnerFace(storage, player === row.host_id ? row.guest_id : row.host_id);
  return face === undefined ? {} : { partner_reaction: face };
}

/** The entry for a link with no readable projection: a Story or unknown link, or a failed or refused read. */
export function fallback(link: RoomLink, status: RoomInboxStatus = "unavailable"): RoomInboxEntry {
  const version = roomLinkVersion(link);
  return { room_id: link.room_id, family: version === 1 ? "legacy" : version === 2 ? "relay" : version === 3 ? "story" : "unknown",
    api_version: version, chapter: { id: null, version: null },
    membership: { host_id: null, guest_id: null, you_are_host: link.host }, status,
    revision: null, remote_activity_sequence: 0, activity_at: null };
}

/** Rooms read at once for one inbox request or room list page. */
export const ROOM_INBOX_CONCURRENCY = 4;

/** Runs `work` over `items`, `size` at a time; the results keep the items' order. */
export async function pooled<T, R>(items: readonly T[], size: number, work: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const worker = async () => { while (next < items.length) { const index = next++; results[index] = await work(items[index]); } };
  await Promise.all(Array.from({ length: Math.min(size, items.length) }, worker));
  return results;
}

/** A link's projection, read live or taken from the room index; null stands for a read that failed. */
export type InboxSource = () => Promise<Outcome<RoomInboxProjection> | null> | Outcome<RoomInboxProjection> | null;

/**
 * The one way an inbox entry is built, for the original and the indexed inbox.
 * Story and unknown links, failed reads and refused reads give the fallback
 * entry (with showClosed, a room another member erased reads "closed"); a room
 * whose pair is blocked in either direction is left out (null). partner_left
 * is kept only with showLeft, and partner_reaction only with showReactions.
 */
export async function inboxEntry(link: RoomLink, source: InboxSource, showClosed: boolean, showLeft: boolean, blocked: (host: string, guest: string | null) => Promise<boolean>, showReactions = false): Promise<RoomInboxEntry | null> {
  const version = roomLinkVersion(link);
  if (version !== 1 && version !== 2) return fallback(link);
  try {
    const result = await source();
    if (!result) return fallback(link);
    if (!result.ok) return fallback(link, showClosed && result.status === 410 ? "closed" : "unavailable");
    const { partner_left, partner_reaction, ...value } = result.value;
    if (await blocked(value.membership.host_id!, value.membership.guest_id)) return null;
    return { ...value, family: version === 1 ? "legacy" : "relay", api_version: version, ...(showLeft && partner_left ? { partner_left } : {}),
      ...(showReactions && partner_reaction !== undefined ? { partner_reaction } : {}) };
  } catch (error) { logWarning("room_inbox_entry_failed", { api_version: version, reason: errorCode(error) }); return fallback(link); }
}

/** The inbox body: entries in link order, then a stable sort by activity time, so equal times list as before. */
export function inboxBody(entries: readonly (RoomInboxEntry | null)[]): { schema_version: 1; rooms: RoomInboxEntry[] } {
  const rooms = entries.filter((room): room is RoomInboxEntry => room !== null);
  rooms.sort((a, b) => (Date.parse(b.activity_at ?? "") || 0) - (Date.parse(a.activity_at ?? "") || 0));
  return { schema_version: 1, rooms };
}

/**
 * Authenticated, bounded summary list. Unavailable links remain visible for recovery.
 * With showClosed, a room another member erased reads "closed" so its remaining
 * member can tell it apart and remove it; otherwise it stays "unavailable".
 * Rooms are read a few at a time, each partner's block check runs once, and a
 * room that throws reads "unavailable" without failing the others. The router
 * passes the links it already read; it sends at most MAX_ROOM_LINKS (room-limit.ts)
 * here, and longer lists or the room index go to room-index-lists.ts.
 */
export async function roomInbox(playerId: string, env: Env, showClosed = false, showLeft = false, known?: RoomLink[], showReactions = false): Promise<{ schema_version: 1; rooms: RoomInboxEntry[] }> {
  const links = known ?? await env.PLAYERS.getByName(playerId).listRooms();
  const blocked = partnerBlocks(env, playerId);
  return inboxBody(await pooled(links, ROOM_INBOX_CONCURRENCY, link => inboxEntry(link, () => roomLinkVersion(link) === 1
    ? env.ROOMS.getByName(link.room_id).inboxProjection(playerId)
    : env.ROOMS_V2.getByName(link.room_id).inboxProjection(playerId), showClosed, showLeft, blocked, showReactions)));
}
