import type { Outcome } from "./protocol";
import type { MemberRoomState } from "./room-leave";
import { roomLinkVersion } from "./room-links";

/** Rooms still in play that one player may be linked to. */
export const MAX_ACTIVE_ROOM_LINKS = 20;
/**
 * Every room link one player may hold, finished ones included. It bounds each
 * per-link read (room lists, the room inbox, identity deletion); clients from
 * 0.6.0 accept a room inbox of up to 100 rooms and a room list of up to 128.
 */
export const MAX_ROOM_LINKS = 60;

/**
 * The room cap. `settled` names linked rooms already confirmed as no longer in
 * play for this player (finished, replay-transferred or gone); they count only
 * toward MAX_ROOM_LINKS. With nothing settled every link counts, as before.
 */
export function roomLimitReached(linkedRoomIds: readonly string[], settled: readonly string[] = []): boolean {
  if (linkedRoomIds.length >= MAX_ROOM_LINKS) return true;
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
 * room_limit_reached refusal reads this player's rooms, and the reservation
 * then runs once more with the ones no longer in play left out of the count.
 */
export async function reserveWithinRoomLimit<T>(env: Env, playerId: string, reserve: (settled: string[]) => Promise<Outcome<T>>): Promise<Outcome<T>> {
  const first = await reserve([]);
  if (first.ok || first.code !== "room_limit_reached") return first;
  const settled = await settledRoomIds(env, playerId);
  return settled.length === 0 ? first : reserve(settled);
}
