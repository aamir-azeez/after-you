import { ApiError, boundedJson, exactKeys, object } from "./protocol";
import { bearerDigest } from "./http";
import { roomLinkVersion } from "./room-links";

/** A member's view of a room: still being played, finished, or no longer theirs (closed, erased or never joined). */
export type MemberRoomState = "in_play" | "finished" | "gone";

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
 */
export async function leaveRoom(request: Request, playerId: string, env: Env, version: 1 | 2, roomId: string): Promise<{ schema_version: 1; removed: true }> {
  const input = object(await boundedJson(request, 1024)); exactKeys(input, ["schema_version"]);
  if (input.schema_version !== 1) throw new ApiError(400, "invalid_room_leave");
  const player = env.PLAYERS.getByName(playerId);
  const linked = (await player.listRooms()).some(link => link.room_id === roomId && roomLinkVersion(link) === version);
  if (linked) {
    const state: MemberRoomState = version === 1 ? await env.ROOMS.getByName(roomId).memberRoomState(playerId) : await env.ROOMS_V2.getByName(roomId).memberRoomState(playerId);
    if (state !== "gone") throw new ApiError(409, "room_not_closed");
    if (!await player.authorize(await bearerDigest(request))) throw new ApiError(401, "identity_unavailable");
    await player.removeRoom(roomId, version);
  }
  return { schema_version: 1, removed: true };
}

/** For DELETE with the close-if header: a finished room is kept, so the partner's replay is not erased by a stale tap. */
export async function requireInPlay(request: Request, state: () => Promise<MemberRoomState>): Promise<void> {
  if (closeOnlyInPlay(request) && await state() === "finished") throw new ApiError(409, "room_finished");
}
