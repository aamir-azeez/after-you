import { shownName } from "../display-names";
import { pooled } from "../room-inbox";
import { boardKeys } from "./boards";
import type { MemberState } from "./member";
import { storeView } from "./view-cache";

/**
 * A player's name on the boards that hold a run of theirs. Names show only
 * when both players of a run chose to show theirs (board.ts shownNames).
 */
const BOARD_CONCURRENCY = 4;

/**
 * Applies the player's choice (or, with `show` undefined, their current one)
 * and their current shown name to the boards their LeaderboardMember lists,
 * under a new revision. Returns their settings.
 * Requests: 1 (Member) + 1 (Player, only while showing and on a board) + 1 per board listed.
 */
export async function syncMemberName(env: Env, playerId: string, show?: boolean): Promise<MemberState> {
  const state = await env.LEADERBOARD_MEMBERS.getByName(playerId).touch(show);
  if (!state.boards.length || state.erased) return state;
  const name = state.show_name ? shownName(await env.PLAYERS.getByName(playerId).publicDisplayName(playerId)) : null;
  await pooled(state.boards, BOARD_CONCURRENCY, async board => {
    const answer = await env.LEADERBOARD_BOARDS.getByName(board).setMember(board, playerId, state.show_name, name, state.revision);
    if (answer.changed) await storeView(answer.view);
  });
  return state;
}

/**
 * Account erasure: the player's settings keep only an erased mark (so an
 * account check already under way cannot add them back), then every board
 * forgets them: their waiting runs go, their ranked runs keep only the pair's
 * time, their rewards there go. Every board, not only the listed ones, since
 * a run still waiting for its account check is on no list yet.
 * Requests: 1 (Member) + 1 per board (12 today).
 */
/** forgetLeaderboardPlayer only for a player whose member record ever changed; anyone else costs one read and stores nothing. */
export async function forgetLeaderboardPlayerIfKnown(env: Env, playerId: string): Promise<void> {
  const state = await env.LEADERBOARD_MEMBERS.getByName(playerId).read();
  if (state.erased || (state.revision === 0 && state.boards.length === 0)) return;
  await forgetLeaderboardPlayer(env, playerId);
}

export async function forgetLeaderboardPlayer(env: Env, playerId: string): Promise<void> {
  await env.LEADERBOARD_MEMBERS.getByName(playerId).forget();
  await pooled([...boardKeys()], BOARD_CONCURRENCY, async board => {
    const answer = await env.LEADERBOARD_BOARDS.getByName(board).forget(board, playerId);
    if (answer.changed) await storeView(answer.view);
  });
}
