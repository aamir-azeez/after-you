import { ApiError } from "../protocol";
import { LEGACY_STAGE_COUNT } from "./chapter-types";
import type { RoomV2 } from "./room";

/** Turn ids name their stage with one digit, up to MAX_ROOM_STAGES - 1. */
export const STAGE_TURN_PATTERN = /^t(?:[0-9]|[12][0-9]|3[01])-[0-7]-[ab]$/;
/** The stage digit of a turn ("t3-4-a") or pair ("p3-4") id; 0 when there is none. */
export function stageDigit(id: string): number {
  const match = /-([0-9])(?:-[ab])?$/.exec(id);
  return match ? Number(match[1]) : 0;
}
/** Stage count of the room a turn or pair id belongs to. Digits of the published
 * two stages never contact the room; past them the room's own chapter decides
 * (2 for a missing, deleted or unknown room). */
export async function roomStages(room: () => DurableObjectStub<RoomV2>, id: string): Promise<number> {
  return stageDigit(id) < LEGACY_STAGE_COUNT ? LEGACY_STAGE_COUNT : await room().stageCount();
}
/** A stage digit past the room's chapter keeps the exact error it had before longer chapters. */
export async function stageWithin(room: DurableObjectStub<RoomV2>, id: string, code: string, status = 400): Promise<void> {
  if (stageDigit(id) >= await roomStages(() => room, id)) throw new ApiError(status, code);
}
