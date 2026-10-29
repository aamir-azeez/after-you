import { ApiError, boundedJson, exactKeys, object, type Outcome } from "./protocol";
import type { RoomInboxProjection } from "./room-inbox";
import { bearerDigest } from "./http";
import { roomLinkVersion } from "./room-links";

/** A member's view of a room: still being played, finished, or no longer theirs (closed, erased or never joined). */
export type MemberRoomState = "in_play" | "finished" | "gone";
/**
 * The one rule for MemberRoomState, from the member's inbox projection
 * (room-inbox.ts), which both rooms and the room index use: a room waiting for
 * a friend or a turn is in play, a completed one is finished, and an erased
 * room (410) or one the caller is not in (404) is gone. Any other answer counts
 * as in play, so a failure can only keep a room counted, never free one.
 */
export function memberStateOf(outcome: Outcome<RoomInboxProjection>): MemberRoomState {
  if (!outcome.ok) return outcome.status === 404 || outcome.status === 410 ? "gone" : "in_play";
  return outcome.value.status === "completed" ? "finished" : "in_play";
}

/** Sent by clients from 0.5.2 with DELETE: close only a room still in play, never one that has just finished. */
export const CLOSE_IF_HEADER = "X-AfterYou-Close-If";
export function closeOnlyInPlay(request: Request): boolean { return request.headers.get(CLOSE_IF_HEADER) === "in-play"; }

/**
 * POST /v{1,2}/rooms/:id/leave removes the caller's own link to a room that is
 * gone for them, such as one the other member closed. While the caller is still
 * a member of a live or archived room it is refused with room_not_closed, so a
 * leave never strands a partner or hides data from identity deletion; the
 * caller closes a room in play with DELETE. Not gated by blocks or mutation
 * flags, and idempotent.
 *
 * `"leave_finished": true` also leaves a room that is
 * finished for the caller: the room erases the caller's own photos, photo
 * deliveries and reactions and stops treating them as a member (leaveFinished),
 * then the link goes. The partner keeps the room and its replay. A retry after
 * either step finds the room gone for the caller and only drops the link.
 */
export async function leaveRoom(request: Request, playerId: string, env: Env, version: 1 | 2, roomId: string): Promise<{ schema_version: 1; removed: true }> {
  const input = object(await boundedJson(request, 1024));
  const finished = input.leave_finished !== undefined;
  exactKeys(input, finished ? ["schema_version", "leave_finished"] : ["schema_version"]);
  if (input.schema_version !== 1 || (finished && input.leave_finished !== true)) throw new ApiError(400, "invalid_room_leave");
  const player = env.PLAYERS.getByName(playerId);
  const linked = (await player.listRooms()).some(link => link.room_id === roomId && roomLinkVersion(link) === version);
  if (linked) {
    const room = version === 1 ? env.ROOMS.getByName(roomId) : env.ROOMS_V2.getByName(roomId);
    const state: MemberRoomState = await room.memberRoomState(playerId);
    if (state === "in_play" || (state === "finished" && !finished)) throw new ApiError(409, "room_not_closed");
    if (!await player.authorize(await bearerDigest(request))) throw new ApiError(401, "identity_unavailable");
    if (state === "finished") {
      const left = await room.leaveFinished(playerId);
      if (!left.ok && left.status !== 404) throw new ApiError(left.status, left.code);
    }
    await player.removeRoom(roomId, version);
  }
  return { schema_version: 1, removed: true };
}

/** For DELETE with the close-if header: a finished room is kept, so the partner's replay is not erased by a stale tap. */
export async function requireInPlay(request: Request, state: () => Promise<MemberRoomState>): Promise<void> {
  if (closeOnlyInPlay(request) && await state() === "finished") throw new ApiError(409, "room_finished");
}
