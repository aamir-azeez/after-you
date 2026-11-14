import { flags } from "../flags";
import { errorCode, logWarning } from "../log";
import type { MutationV2 } from "../v2/room";
import { checkRun } from "./eligibility";
import { TOP_PLACES } from "./rules";
import { finishedRun, type LeaderboardRun } from "./run";
import type { SubmitStatus } from "./board";
import { pairAccounts, platformRequiredOn } from "./platform-rule";
import type { PairLooks } from "./run-looks";
import { cachedView, storeView } from "./view-cache";
import { mightPlace } from "./view";

/**
 * After an accepted turn (v2/routes.ts): when it finished a together run that
 * might place, post it to its board (postRun). Never throws and never changes
 * the turn reply.
 *
 * A retried final turn posts again (a premium chapter's retry too, from its
 * receipt); the board answers "known" when the first post arrived.
 *
 * `looks`: the pair's looks the room handed over with the finishing commit
 * (run-looks.ts), stored with the run in the same request. A retried premium
 * final turn posts from its receipt, which has none, so a run that only
 * reaches its board that way shows the default looks.
 */
export async function postFinishedRun(env: Env, mutation: MutationV2, context: unknown, looks?: PairLooks): Promise<void> {
  if (!flags.leaderboards(env)) return;
  let run: LeaderboardRun | null;
  try { run = await finishedRun(mutation, context, looks); } catch (error) { logWarning("leaderboard_post_failed", { code: errorCode(error) }); return; }
  await postPreparedRun(env, run);
}
/** postFinishedRun's post, for a run the room already worked out (v2/room.ts turnRequest), so the Worker never holds the room. */
export async function postPreparedRun(env: Env, run: LeaderboardRun | null | undefined): Promise<void> {
  if (!run || !flags.leaderboards(env)) return;
  try { await postRun(env, run); } catch (error) { logWarning("leaderboard_post_failed", { code: errorCode(error) }); }
}

/**
 * What became of a post: the board's answer, "listed" when the cached board
 * already lists the run, "skipped" when it holds ten faster runs, or
 * "platform_required" with the members who have no platform link.
 */
export type PostOutcome = { status: SubmitStatus | "listed" | "skipped" } | { status: "platform_required"; unlinked: string[] };

/**
 * Posts a finished run that might place. That is at most one board request,
 * and none when the cached board already holds ten faster runs or lists the
 * run. While the platform rule is on (platform-rule.ts) one PlatformLinks read
 * comes first, and a pair with an unlinked member writes nothing anywhere; the
 * same read gives a linked pair its account key (pair-accounts.ts), so the
 * board counts every identity pair behind the same two accounts as one.
 *
 * When the board's unchecked runs are full ("crowded"), this post runs the
 * account check itself (4 more requests: Player and Member for each player)
 * and posts again as checked, so a flood of posts from new accounts never
 * keeps out players who qualify. Throws when a request fails.
 */
export async function postRun(env: Env, run: LeaderboardRun): Promise<PostOutcome> {
  const cached = await cachedView(run.board);
  if (cached && (cached.checking.includes(run.entry_id) || cached.top.some(row => row.entry_id === run.entry_id))) return { status: "listed" };
  if (cached && !mightPlace(cached, run.ticks, TOP_PLACES)) return { status: "skipped" };
  if (platformRequiredOn(env)) {
    const accounts = await pairAccounts(env, run.members);
    if (accounts.account_key === undefined) return { status: "platform_required", unlinked: accounts.unlinked };
    run = { ...run, account_key: accounts.account_key };
  }
  const stub = env.LEADERBOARD_BOARDS.getByName(run.board);
  let answer = await stub.submit(run.board, run);
  if (answer.status === "crowded") {
    const checked = await checkRun(env, run.board, run.entry_id, run.members, run.finished_ms);
    if (!checked.eligible) return { status: "ineligible" };
    answer = await stub.submit(run.board, run, checked);
  }
  await storeView(answer.view);
  return { status: answer.status };
}
