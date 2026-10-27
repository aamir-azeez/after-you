import { flags } from "../flags";
import { errorCode, logWarning } from "../log";
import type { MutationV2 } from "../v2/room";
import { checkRun } from "./eligibility";
import { TOP_PLACES } from "./rules";
import { finishedRun } from "./run";
import { cachedView, storeView } from "./view-cache";
import { mightPlace } from "./view";

/**
 * After an accepted turn (v2/routes.ts): when it finished a together run that
 * might place, post it to its board. That is at most one Durable Object
 * request, and none when the cached board already holds ten faster runs.
 * Never throws and never changes the turn reply.
 *
 * A retried final turn posts again (a premium chapter's retry too, from its
 * receipt); the board answers "known" when the first post arrived.
 *
 * When the board's unchecked runs are full ("crowded"), this post runs the
 * account check itself (4 more requests: Player and Member for each player)
 * and posts again as checked, so a flood of posts from new accounts never
 * keeps out players who qualify.
 */
export async function postFinishedRun(env: Env, mutation: MutationV2, context: unknown): Promise<void> {
  if (!flags.leaderboards(env)) return;
  try {
    const run = await finishedRun(mutation, context);
    if (!run) return;
    const cached = await cachedView(run.board);
    if (cached && !mightPlace(cached, run.ticks, TOP_PLACES)) return;
    const stub = env.LEADERBOARD_BOARDS.getByName(run.board);
    let answer = await stub.submit(run.board, run);
    if (answer.status === "crowded") {
      const checked = await checkRun(env, run.board, run.entry_id, run.members, run.finished_ms);
      if (!checked.eligible) return;
      answer = await stub.submit(run.board, run, checked);
    }
    await storeView(answer.view);
  } catch (error) {
    logWarning("leaderboard_post_failed", { code: errorCode(error) });
  }
}
