import { fail, type Outcome } from "./protocol";
import { errorCode, logWarning } from "./log";
import type { RoomInboxProjection } from "./room-inbox";
import type { RoomObservation } from "./room-index";

/** One member's inbox projection, stamped with this room's clock. A throw reads as a failure with no lasting answer. */
export function observeRoom(project: () => Outcome<RoomInboxProjection>): RoomObservation {
  let outcome: Outcome<RoomInboxProjection>;
  try { outcome = project(); } catch { outcome = fail(503, "room_unreadable"); }
  return { observed_at: Date.now(), outcome };
}

/**
 * Sends each member's current projection to that member's room index (Player)
 * after a change has committed. Fire and forget: the room's answer never waits
 * on it or changes because of it, and the index re-checks rows, so a lost push
 * only delays a correction. The rooms call it only while the room index is on,
 * except after an erase, which always tells the other member so that no index
 * row keeps the erased member's id.
 */
export function pushRoomIndex(ctx: DurableObjectState, env: Env, roomId: string, version: 1 | 2, members: readonly (string | null | undefined)[], project: (player: string) => Outcome<RoomInboxProjection>): void {
  for (const member of new Set(members)) {
    if (!member) continue;
    const observation = observeRoom(() => project(member));
    ctx.waitUntil(env.PLAYERS.getByName(member).noteRoomIndex(member, roomId, version, observation)
      .catch(error => logWarning("room_index_push_failed", { api_version: version, reason: errorCode(error) })));
  }
}
