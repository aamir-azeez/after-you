import type { Outcome } from "./protocol";
import type { MemberRoomState } from "./room-leave";
import { roomLinkVersion } from "./room-links";

/** Rooms still in play that one player may be linked to. */
export const MAX_ACTIVE_ROOM_LINKS = 20;
/**
 * Every room link one player may hold, finished ones included, while the room
 * index is off. Clients from 0.6.0 accept a room inbox of up to 100 rooms and a
 * room list of up to 128.
 */
export const MAX_ROOM_LINKS = 60;
/**
 * Every room link one player may hold while the room index is on. Lists, the
 * inbox and identity deletion read the index in bounded pages and batches, so
 * their cost no longer grows with this number. Readers of links (snapshots,
 * the campaign capture) always accept this many, so a player who passed
 * MAX_ROOM_LINKS stays readable and deletable after the index is turned off.
 */
export const MAX_INDEXED_ROOM_LINKS = 500;

/**
 * The link bound for admission. Past MAX_ROOM_LINKS it rises only while the
 * index is on and every v1 and v2 link has an index row.
 */
export function roomLinkBound(indexOn: boolean, fullyIndexed: boolean): number {
  return indexOn && fullyIndexed ? MAX_INDEXED_ROOM_LINKS : MAX_ROOM_LINKS;
}

/**
 * The room cap. `settled` names linked rooms already confirmed as no longer in
 * play for this player (finished, replay-transferred or gone); they count only
 * toward `bound`. With nothing settled every link counts, as before.
 */
export function roomLimitReached(linkedRoomIds: readonly string[], settled: readonly string[] = [], bound = MAX_ROOM_LINKS): boolean {
  if (linkedRoomIds.length >= bound) return true;
  const done = new Set(settled);
  return linkedRoomIds.filter(id => !done.has(id)).length >= MAX_ACTIVE_ROOM_LINKS;
}

/**
 * Linked v1 and v2 rooms this player can no longer play in. Any other link
 * version, and any read that fails, counts as in play, so a failure can only
 * refuse a room, never allow an extra one.
 */
export async function settledRoomIds(env: Env, playerId: string): Promise<string[]> {
  const links = await env.PLAYERS.getByName(playerId).listRooms();
  const states = await Promise.all(links.map(async (link): Promise<MemberRoomState> => {
    try {
      const version = roomLinkVersion(link);
      if (version === 1) return await env.ROOMS.getByName(link.room_id).memberRoomState(playerId);
      if (version === 2) return await env.ROOMS_V2.getByName(link.room_id).memberRoomState(playerId);
    } catch { /* counted as in play */ }
    return "in_play";
  }));
  return links.filter((_, index) => states[index] !== "in_play").map(link => link.room_id);
}

/**
 * Runs a Player room reservation under the cap. The first attempt counts every
 * link, exactly as before, so below the cap no room is read. Only a
 * room_limit_reached refusal reads this player's rooms through `settle`, and
 * the reservation then runs once more with the ones no longer in play left out
 * of the count. The router picks `settle` (room-index-lists.ts roomSettler):
 * settledRoomIds, or a bounded read through the room index while it is on.
 */
export async function reserveWithinRoomLimit<T>(env: Env, playerId: string, reserve: (settled: string[]) => Promise<Outcome<T>>, settle: (env: Env, playerId: string) => Promise<string[]> = settledRoomIds): Promise<Outcome<T>> {
  const first = await reserve([]);
  if (first.ok || first.code !== "room_limit_reached") return first;
  const settled = await settle(env, playerId);
  return settled.length === 0 ? first : reserve(settled);
}
