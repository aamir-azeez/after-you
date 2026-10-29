/**
 * The leaderboard rules as numbers and one ordering. Pure: no storage, no env.
 *
 * One board per chapter version ("Fastest pair"). A run's time is the sum of
 * the game ticks of every turn on its finishing branch. Faster first; equal
 * ticks go to the run whose last turn the server accepted earlier.
 */

/** Places that rank and earn the Top 10 ribbon. */
export const TOP_PLACES = 10;
/** Ranked entries kept below the top 10, so a struck run lets the next one move up. */
export const KEPT_RANKED = TOP_PLACES + 3;
/**
 * Replays (board.ts lb_replays): each top 10 run keeps its final checkpoint
 * so players can watch it, in the shared blob format (blob-codec.ts, deflate
 * plus the SHA-256 of the canonical bytes). A run pushed below place 10,
 * struck, dropped or played by an erased account loses it; a run waiting for
 * a person keeps it until their answer. So the server holds about 120 replays
 * (10 on each of 12 boards), plus one for each run waiting for a person: at
 * most MAX_REVIEW (48) a board, usually none. A final checkpoint is typically
 * 12 to 35 KB of JSON and deflates to about a quarter of that; an encoded
 * replay above this many bytes is not kept (its run still ranks, with no
 * Watch). Worst case 12 x (10 + 48) x 360 KB, about 250 MB; typical well
 * under 1 MB in all.
 */
export const MAX_REPLAY_BYTES = 360 * 1024;
/**
 * Runs waiting, per board, in three pools so one kind can never crowd out another:
 * - unchecked: posted, account check not run yet. A full pool never evicts; the
 *   post runs the account check itself first (submit.ts), so new accounts posting
 *   fakes cannot push out players who qualify;
 * - checked: qualified and waiting for the replay; a faster run evicts the slowest;
 * - review: passed and waiting for a person; a faster run evicts the slowest.
 */
export const MAX_UNCHECKED = 16;
export const MAX_CHECKED = 24;
export const MAX_REVIEW = 48;
/** Verdicts that send a run to a person instead of dropping it: the job could not judge it. */
export const REVIEW_REASONS: readonly string[] = ["replay_error", "no_verdict", "unknown_chapter"];
/** A time below this share of the developers' best waits for a person. */
export const FLOOR_RATIO = 0.8;
/** A new first this much faster than the old first, or more, waits for a person. */
export const WIDE_MARGIN_RATIO = 0.85;
/**
 * The account check's two conditions, relaxed to 0 on 2026-10-29 so a new pair ranks once its replay
 * passes. The checks stay in place (standing.ts eligible); raise them again if cheating appears
 * (they were 7 days and 2 partners). An account with no identity, or erased, still never ranks.
 */
/** Both accounts at least this old when the run finished. */
export const MIN_ACCOUNT_AGE_MS = 0;
/** Each player has turns alongside at least this many different partners. At 0 ranking reads no partners (standing.ts). */
export const MIN_PARTNERS = 0;
/** Distinct reporters kept per entry. */
export const MAX_REPORTERS = 32;

export type Timed = { ticks: number; finished_ms: number; entry_id: string };

/** Negative when `a` ranks above `b`. The entry id only breaks a same-millisecond tie, so the order is total. */
export function compareRuns(a: Timed, b: Timed): number {
  return a.ticks - b.ticks || a.finished_ms - b.finished_ms || (a.entry_id < b.entry_id ? -1 : a.entry_id > b.entry_id ? 1 : 0);
}

/** Whether `ticks` beats every other time strictly; a run that only ties for first earns no Gold leaf. */
export function strictlyFirst(ticks: number, others: readonly { ticks: number }[]): boolean {
  return others.every(other => ticks < other.ticks);
}

/** Why a passed run still waits for a person, given the developers' best (null when unknown) and the current first's ticks. */
export function holdsFor(ticks: number, developerBest: number | null, firstTicks: number | null): string[] {
  const holds: string[] = [];
  if (developerBest === null) holds.push("no_developer_best");
  else if (ticks < FLOOR_RATIO * developerBest) holds.push("below_floor");
  if (firstTicks !== null && ticks < WIDE_MARGIN_RATIO * firstTicks) holds.push("wide_margin");
  return holds;
}
