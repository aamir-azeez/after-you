import { errorCode, logWarning } from "../log";
import { pooled } from "../room-inbox";
import type { RunCopyWork } from "./store";

/** Rooms told at once. */
const ROOM_CONCURRENCY = 4;

/**
 * Tells each room in `items` (a board's duel_run_copies rows, duels/store.ts) to drop its duel run
 * copy, or an erased player from it (their-run.ts dropTheirRun), then tells the board which rooms
 * answered, so their rows go. A room that failed keeps its row for the next sweep; telling a room
 * twice is a no-op. Called by the hourly replay job (leaderboards/operator.ts) and right after an
 * account erasure (leaderboards/members.ts).
 *
 * Requests: one per room, plus one to the board when any answered.
 */
export async function dropRunCopies(env: Env, board: string, items: readonly RunCopyWork[]): Promise<void> {
  if (!items.length) return;
  const answered: RunCopyWork[] = [];
  await pooled([...items], ROOM_CONCURRENCY, async item => {
    try {
      await env.ROOMS_V2.getByName(item.room_id).dropTheirRun(item.duel_id, item.player);
      answered.push(item);
    } catch (error) {
      logWarning("duel_run_copy_drop_failed", { code: errorCode(error) });
    }
  });
  if (answered.length) await env.LEADERBOARD_BOARDS.getByName(board).runCopiesDone(answered);
}
