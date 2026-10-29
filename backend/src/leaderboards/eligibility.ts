import type { StandingResult } from "./board";
import { eligible } from "./standing";

/**
 * The account check for one run: both players at least MIN_ACCOUNT_AGE_MS old
 * when it finished, each with turns alongside at least MIN_PARTNERS different
 * partners (rules.ts, both 0 since 2026-10-29; standing.ts), and each player's
 * name choice under its revision. A player
 * with no identity, or erased, never qualifies and is never written to.
 * Noting the board first means a later name change reaches it.
 * Requests: per player, 1 Player and (when they have an identity) 1 Member.
 */
export async function checkRun(env: Env, board: string, entryId: string, members: readonly (string | null)[], finishedMs: number): Promise<StandingResult> {
  const checked = await Promise.all(members.map(async id => {
    if (id === null) return { ok: false, show: false, name: null, rev: 0 };
    const player = await env.PLAYERS.getByName(id).leaderboardStanding();
    if (!player) return { ok: false, show: false, name: null, rev: 0 };
    const settings = await env.LEADERBOARD_MEMBERS.getByName(id).noteBoard(board);
    return { ok: !settings.erased && eligible(player, finishedMs), show: settings.show_name, name: player.display_name, rev: settings.revision };
  }));
  const ok = checked.length === 2 && checked.every(member => member.ok);
  return { entry_id: entryId, eligible: ok, reason: ok ? "" : "ineligible", members: checked.map(({ show, name, rev }) => ({ show, name, rev })) };
}
