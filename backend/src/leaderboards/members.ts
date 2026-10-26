import { pooled } from "../room-inbox";
import type { MemberState } from "./member";
import { storeView } from "./view-cache";

/**
 * A player's name on the boards that hold a run of theirs. Names show only
 * when both players of a run chose to show theirs (board.ts shownNames).
 * Each change reaches only the boards the player's LeaderboardMember lists.
 */
const BOARD_CONCURRENCY = 4;

/**
 * Applies the player's choice (or, with `show` undefined, their current one)
 * and current display name to their boards. Returns their settings.
 * Requests: 1 (Member) + 1 (Player, only while showing and on a board) + 1 per board listed.
 */
export async function syncMemberName(env: Env, playerId: string, show?: boolean): Promise<MemberState> {
  const member = env.LEADERBOARD_MEMBERS.getByName(playerId);
  const state = show === undefined ? await member.read() : await member.setShowName(show);
  if (!state.boards.length) return state;
  const name = state.show_name ? await env.PLAYERS.getByName(playerId).publicDisplayName(playerId) : null;
  await pooled(state.boards, BOARD_CONCURRENCY, async board => {
    const answer = await env.LEADERBOARD_BOARDS.getByName(board).setMember(board, playerId, state.show_name, name);
    if (answer.changed) await storeView(answer.view);
  });
  return state;
}

/**
 * Account erasure: each board the player is on forgets them, then their
 * settings go. Boards first, so a failure leaves the list for the retried
 * deletion. Runs whatever the flag says. Requests: 2 (Member) + 1 per board.
 */
export async function forgetLeaderboardPlayer(env: Env, playerId: string): Promise<void> {
  const member = env.LEADERBOARD_MEMBERS.getByName(playerId);
  await pooled((await member.read()).boards, BOARD_CONCURRENCY, async board => {
    const answer = await env.LEADERBOARD_BOARDS.getByName(board).forget(board, playerId);
    if (answer.changed) await storeView(answer.view);
  });
  await member.forget();
}
