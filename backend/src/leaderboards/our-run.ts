import { developerGhost } from "../duels/developer-ghosts";
import type { BoardView } from "./view";

/**
 * Our run on a board: the time a ghost race against "Our run" races. By default the developers' run the game ships
 * (duels/developer-ghosts.ts). Once the owner's pair (owner.ts) finishes a run here that passes the same replay check
 * as any board run and beats it, that run takes its place: the board keeps one copy (board.ts lb_our_run, its replay
 * in the shared blob format, apart from the top 10 replays), each faster one replacing it, and shows its time and
 * replay hash on the view as `our_run`, so every read that already reads the board learns it with no request of its
 * own. Erasing either player's account, or striking the run, drops it, and the shipped run is Our run again.
 */
export type OurRunView = { entry_id: string; ticks: number; replay_hash: string };

/** Our run's time on `board`: the kept owner run's from `view`, else the shipped run's; null when there is neither. */
export function ourRunTicks(board: string, view: Pick<BoardView, "our_run"> | null | undefined): number | null {
  return view?.our_run?.ticks ?? developerGhost(board);
}

/** Whether a run of `ticks` by `members` would become Our run over `current` (ourRunTicks): the owner's pair, strictly faster. */
export function beatsOurRun(owner: string | null, members: readonly (string | null)[], ticks: number, current: number | null): boolean {
  return owner !== null && members.includes(owner) && (current === null || ticks < current);
}
