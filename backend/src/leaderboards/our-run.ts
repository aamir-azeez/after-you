import { developerGhost } from "../duels/developer-ghosts";
import type { BoardView } from "./view";

/**
 * Our run on a board: the time a ghost race against "Our run" races. By default the developers' run the game ships
 * (duels/developer-ghosts.ts). Once the owner's pair (owner.ts) finishes a run here that passes the same replay check
 * as any board run and beats it, that run takes its place: the board keeps one copy (board.ts lb_our_run, its replay
 * in the shared blob format, apart from the top 10 replays), each faster one replacing it, and shows its time and
 * replay hash on the view as `our_run`, so every read that already reads the board learns it with no request of its
 * own. Erasing either player's account, or striking the run, drops it, and the shipped run is Our run again.
 *
 * Only an app that can fetch and play the kept run (it sends OUR_RUN_HEADER on the race list and race start) races
 * it. Every other app (0.8.1 and older) keeps the shipped run's time, splits and ghost exactly as before, so the pip
 * it plays from its own copy of the shipped run always matches the race.
 */
export type OurRunView = { entry_id: string; ticks: number; replay_hash: string };

/** Sent by an app that plays a kept Our run (game/services/rooms_api.gd) on GET /v1/duels/ghosts and POST /v1/duels/ghost. */
export const OUR_RUN_HEADER = "X-AfterYou-Our-Run";

/** Whether the request comes from an app that plays a kept Our run. */
export function playsOurRun(request: Request): boolean { return request.headers.get(OUR_RUN_HEADER) === "1"; }

/**
 * Our run's time on `board`: the kept owner run's from `view` when `plays` (an app that plays it, or the board's own
 * rule for what replaces it), else the shipped run's; null when there is neither.
 */
export function ourRunTicks(board: string, view: Pick<BoardView, "our_run"> | null | undefined, plays: boolean): number | null {
  return (plays ? view?.our_run?.ticks : undefined) ?? developerGhost(board);
}

/** Whether a run of `ticks` by `members` would become Our run over `current` (ourRunTicks): the owner's pair, strictly faster. */
export function beatsOurRun(owner: string | null, members: readonly (string | null)[], ticks: number, current: number | null): boolean {
  return owner !== null && members.includes(owner) && (current === null || ticks < current);
}
