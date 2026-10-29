import { fail, type Outcome, type RoomSnapshot } from "./protocol";
import { errorCode, logWarning } from "./log";
import { roomLinkVersion, type RoomLink } from "./room-links";
import { ROOM_INBOX_CONCURRENCY, inboxBody, inboxEntry, pooled, type RoomInboxEntry, type RoomInboxProjection } from "./room-inbox";
import { partnerBlocks } from "./safety";
import { memberStateOf } from "./room-leave";
import { ROOM_INDEX_READS, ROOM_NEXT_HEADER, ROOM_PAGE_HEADER, type RoomIndexRow, type RoomObservation } from "./room-index";
import type { RoomLobbyV2 } from "./v2/room";

/**
 * The indexed inbox, room list and legacy room list: a bounded page chosen by
 * the Player's room index (room-index.ts), so a request costs the same whatever
 * the link count. The router serves every room list and the inbox from these.
 */

/** The page a request asked for: ROOM_PAGE_HEADER as a decimal offset, else the first page. */
export function pageOffset(request: Request): number {
  const match = /^(0|[1-9][0-9]{0,5})$/.exec(request.headers.get(ROOM_PAGE_HEADER) ?? "");
  return match ? Number(match[1]) : 0;
}
/** Adds ROOM_NEXT_HEADER when more rooms follow the page; the body keeps its shape. */
export function withNext(response: Response, next: number | null): Response {
  if (next !== null) response.headers.set(ROOM_NEXT_HEADER, String(next));
  return response;
}

/** A live read of one linked room for the index; null when the read itself failed. */
async function observe(env: Env, playerId: string, link: RoomLink): Promise<RoomObservation | null> {
  const version = roomLinkVersion(link);
  try {
    return version === 1 ? await env.ROOMS.getByName(link.room_id).indexEntry(playerId) : await env.ROOMS_V2.getByName(link.room_id).indexEntry(playerId);
  } catch (error) { logWarning("room_inbox_entry_failed", { api_version: version, reason: errorCode(error) }); return null; }
}

/** Reads `links` live, four at a time, and stores what they said in one Player call (none when nothing was read). */
async function readAndRecord(env: Env, playerId: string, links: readonly RoomLink[]): Promise<Map<string, RoomObservation | null>> {
  const observations = await pooled(links, ROOM_INBOX_CONCURRENCY, link => observe(env, playerId, link));
  if (links.length) await env.PLAYERS.getByName(playerId).recordRoomIndex(playerId, links.map((link, index) => ({ room_id: link.room_id, api_version: roomLinkVersion(link), observation: observations[index] })));
  return new Map(links.map((link, index) => [link.room_id, observations[index]]));
}

/** What a stored row shows: its stored answer, or a 404 for a link whose reads have not answered yet. */
function stored(row: RoomIndexRow | null): Outcome<RoomInboxProjection> | null {
  return row ? row.outcome ?? fail(404, "room_not_found") : null;
}

/**
 * GET /v1/room-inbox from the index: up to ROOM_INBOX_PAGE rooms. Rooms the page
 * marks `read` are read live and stored, the rest come from their rows, and
 * every entry is built by inboxEntry, as in roomInbox.
 */
export async function indexedRoomInbox(playerId: string, env: Env, showClosed: boolean, showLeft: boolean, offset: number, showReactions = false, showNames = false, facePacks = false): Promise<{ body: { schema_version: 1; rooms: RoomInboxEntry[] }; next: number | null }> {
  const page = await env.PLAYERS.getByName(playerId).roomIndexPage("inbox", offset);
  const live = await readAndRecord(env, playerId, [...page.rooms.filter(room => room.read).map(room => room.link), ...page.recheck]);
  const blocked = partnerBlocks(env, playerId);
  const entries = await pooled(page.rooms, ROOM_INBOX_CONCURRENCY, room => inboxEntry(room.link,
    () => room.read ? live.get(room.link.room_id)?.outcome ?? null : stored(room.row), showClosed, showLeft, blocked, showReactions, showNames, facePacks));
  return { body: inboxBody(entries), next: page.next };
}

/**
 * One page of full room views, read four at a time in link order. A room that
 * answers 404 loses its link, as before. Unlike the original lists, any other
 * failed or thrown read leaves only that room out, so one bad room never fails
 * the whole list.
 */
async function roomViews<T extends { host_id: string; guest_id: string | null }>(playerId: string, env: Env, family: "legacy" | "relay", offset: number, read: (roomId: string) => Promise<Outcome<T>>): Promise<{ body: { rooms: T[] }; next: number | null }> {
  const player = env.PLAYERS.getByName(playerId), page = await player.roomIndexPage(family, offset), blocked = partnerBlocks(env, playerId);
  const version = family === "legacy" ? 1 : 2;
  const views = await pooled(page.rooms, ROOM_INBOX_CONCURRENCY, async ({ link }): Promise<T | null> => {
    try {
      const view = await read(link.room_id);
      if (view.ok) return await blocked(view.value.host_id, view.value.guest_id) ? null : view.value;
      if (view.status === 404) await player.removeRoom(link.room_id, version);
      else logWarning("room_list_entry_failed", { api_version: version, status: view.status });
    } catch (error) { logWarning("room_list_entry_failed", { api_version: version, reason: errorCode(error) }); }
    return null;
  });
  return { body: { rooms: views.filter((view): view is Awaited<T> => view !== null) }, next: page.next };
}

/** GET /v2/rooms from the index: one page of v2 links, each room's lobby view as before. */
export function indexedRelayRooms(playerId: string, env: Env, offset: number): Promise<{ body: { rooms: RoomLobbyV2[] }; next: number | null }> {
  return roomViews(playerId, env, "relay", offset, roomId => env.ROOMS_V2.getByName(roomId).lobbySnapshot(playerId));
}

/** GET /v1/rooms from the index: one page of v1 links, each room's snapshot as before. */
export function indexedLegacyRooms(playerId: string, env: Env, offset: number): Promise<{ body: { rooms: RoomSnapshot[] }; next: number | null }> {
  return roomViews(playerId, env, "legacy", offset, async roomId => env.ROOMS.getByName(roomId).snapshot(playerId));
}

/**
 * The room cap's refusal path (the router passes it to reserveWithinRoomLimit): reads up to ROOM_INDEX_READS links the index cannot
 * vouch for as settled (unindexed first), stores the results, and returns every
 * room the index now holds as settled, so a reservation refused only because a
 * link had no row can pass once it has one. A failed read stays in play, so a
 * failure can only refuse a room.
 */
export async function settleFromRoomIndex(env: Env, playerId: string): Promise<string[]> {
  const player = env.PLAYERS.getByName(playerId);
  const links = await player.roomIndexUnsettled(ROOM_INDEX_READS);
  if (!links.length) return [];
  const live = await readAndRecord(env, playerId, links);
  // A 404 read now settles the room for this reservation, though the index keeps it unchecked.
  const gone = links.filter(link => { const seen = live.get(link.room_id); return !!seen && memberStateOf(seen.outcome) !== "in_play"; }).map(link => link.room_id);
  return [...new Set([...await player.roomIndexSettled(), ...gone])];
}
