import type { Outcome } from "./protocol";

/** Rooms still in play that one player may be linked to. */
export const MAX_ACTIVE_ROOM_LINKS = 20;
/**
 * Every room link one player may hold, finished ones included, until every v1
 * and v2 link has a room index row. Clients from 0.6.0 accept a room inbox of
 * up to 100 rooms and a room list of up to 128.
 */
export const MAX_ROOM_LINKS = 60;
/**
 * Every room link one player may hold once the room index covers all of them.
 * Lists, the inbox and identity deletion read the index in bounded pages and
 * batches, so their cost does not grow with this number. Readers of links
 * (snapshots, the campaign capture) always accept this many.
 */
export const MAX_INDEXED_ROOM_LINKS = 500;

/** The link bound for admission. Past MAX_ROOM_LINKS it rises only once every v1 and v2 link has an index row. */
export function roomLinkBound(fullyIndexed: boolean): number {
  return fullyIndexed ? MAX_INDEXED_ROOM_LINKS : MAX_ROOM_LINKS;
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
 * Runs a Player room reservation under the cap. The first attempt counts every
 * link, exactly as before, so below the cap no room is read. Only a
 * room_limit_reached refusal reads this player's rooms through `settle`, and
 * the reservation then runs once more with the ones no longer in play left out
 * of the count. The router passes `settle`: room-index-lists.ts settleFromRoomIndex, a
 * bounded read through the room index.
 */
export async function reserveWithinRoomLimit<T>(env: Env, playerId: string, reserve: (settled: string[]) => Promise<Outcome<T>>, settle: (env: Env, playerId: string) => Promise<string[]>): Promise<Outcome<T>> {
  const first = await reserve([]);
  if (first.ok || first.code !== "room_limit_reached") return first;
  const settled = await settle(env, playerId);
  return settled.length === 0 ? first : reserve(settled);
}
