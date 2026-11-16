import { runningTotals, validSplits } from "./ticks";
import type { Ghost } from "./model";

/**
 * LEGACY, for apps without OUR_RUN_HEADER only (0.8.1 and older). Delete this file, its test and every
 * `plays === false` branch that calls it (duels/routes.ts ghosts and ghostRace) once the minimum app version
 * passes the build that dropped the shipped runs.
 *
 * Those apps shipped the developers' recorded runs as Our run and play the pip from their own copy, so they must
 * keep racing exactly these times and turns. Apps that send the header race only the owner's kept run
 * (leaderboards/our-run.ts) and never read anything here. The runs themselves stay as a test corpus in
 * game/tests/fixtures/whole_runs.json; legacy-shipped-our-run.test.ts keeps these numbers equal to it.
 */
export const LEGACY_SHIPPED_TICKS: Readonly<Record<string, number>> = Object.freeze({
  "relay-isles@2": 588,
  "first-steps@1": 406,
  "high-and-low@1": 531,
  "rolling-home@1": 1173,
  "a-house-for-two@1": 1212,
  "conservatory@1": 773,
  "long-way-home@1": 973,
  "the-wishing-well@1": 1698,
  "long-way-home@2": 989,
  "turn-of-the-tide@1": 1756,
  "sleeping-lighthouse@2": 1470,
  "turn-of-the-tide@2": 1906,
});

/** Each shipped run's turns, in ticks and play order: the race's time after each turn (legacyShippedSplits). */
export const LEGACY_SHIPPED_TURNS: Readonly<Record<string, readonly number[]>> = Object.freeze({
  "relay-isles@2": [140, 140, 150, 158],
  "first-steps@1": [21, 179, 80, 126],
  "high-and-low@1": [91, 141, 75, 224],
  "rolling-home@1": [63, 268, 294, 548],
  "a-house-for-two@1": [195, 231, 342, 444],
  "conservatory@1": [80, 263, 66, 364],
  "long-way-home@1": [332, 332, 106, 203],
  "the-wishing-well@1": [428, 470, 400, 400],
  "long-way-home@2": [332, 332, 106, 219],
  "turn-of-the-tide@1": [418, 498, 392, 448],
  "sleeping-lighthouse@2": [200, 200, 39, 283, 36, 62, 124, 124, 118, 176, 16, 92],
  "turn-of-the-tide@2": [458, 580, 399, 469],
});

/** The shipped run's time after each turn on a board, or null when it has none or its turns do not add up to its time. */
export function legacyShippedSplits(board: string): number[] | null {
  const turns = (LEGACY_SHIPPED_TURNS as Record<string, readonly number[] | undefined>)[board], ticks = legacyShippedTicks(board);
  if (!turns || ticks === null) return null;
  const splits = runningTotals(turns);
  return validSplits(splits, turns.length, ticks) ? splits : null;
}

/** The shipped run's time on a board, in ticks, or null when it has none. */
export function legacyShippedTicks(board: string): number | null {
  const ticks = (LEGACY_SHIPPED_TICKS as Record<string, number | undefined>)[board];
  return typeof ticks === "number" && Number.isSafeInteger(ticks) && ticks > 0 ? ticks : null;
}

/** The race an older app starts against Our run on a board of `steps` turns: the shipped run, or null when it has none. */
export function legacyShippedGhost(board: string, steps: number): Ghost | null {
  const ticks = legacyShippedTicks(board), splits = legacyShippedSplits(board);
  return ticks === null ? null : { source: "developer", entry_id: null, rank: null, ticks, names: null, ...(splits && splits.length === steps ? { splits } : {}) };
}
