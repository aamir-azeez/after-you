import type { PairLooks } from "./run-looks";

/**
 * Our run on a board: the owner's own real run, and nothing else. Once the owner's pair (owner.ts) finishes a run
 * here that passes the same replay check as any board run, it is Our run; after that only a strictly faster owner run
 * replaces it. The board keeps one copy (board.ts lb_our_run, its replay in the shared blob format, apart from the
 * top 10 replays) and shows its time and replay hash on the view as `our_run`, so every read that already reads the
 * board learns it with no request of its own. Erasing either player's account, or striking the run, drops it, and the
 * board has no Our run until the owner's next run there. A board with none offers no race against Our run.
 *
 * An app that sends OUR_RUN_HEADER on the race list and race start races only this run. Older apps (0.8.1 and
 * before) still race the run they shipped, served from duels/legacy-shipped-our-run.ts alone.
 *
 * The run shows as the pair it is: both pips in the looks they finished in, and their names under the board's own
 * rule (both players show their names on boards, else "Our run"), from `names` and `looks` here, kept with the run and
 * changed with each player's name choice as a ranked row's are.
 *
 * A faster owner run replaces the one row whole, its replay copy with it, so at most one copy is ever kept. A ranked
 * row of the same run keeps its own top 10 replay as before, and a race already started plays from the copy its
 * phones took when it began (game/services/race_ghost.gd prefetch), as a board run that leaves the top 10 does.
 */
export type OurRunView = { entry_id: string; ticks: number; replay_hash: string; names: string[] | null; looks?: PairLooks };

/** Sent by an app that plays a kept Our run (game/services/rooms_api.gd) on GET /v1/duels/ghosts and POST /v1/duels/ghost. */
export const OUR_RUN_HEADER = "X-AfterYou-Our-Run";

/** Whether the request comes from an app that plays a kept Our run. */
export function playsOurRun(request: Request): boolean { return request.headers.get(OUR_RUN_HEADER) === "1"; }

/** Whether a run of `ticks` by `members` would become Our run over the kept one's time `current` (null for none): the owner's pair, strictly faster. */
export function beatsOurRun(owner: string | null, members: readonly (string | null)[], ticks: number, current: number | null): boolean {
  return owner !== null && members.includes(owner) && (current === null || ticks < current);
}
