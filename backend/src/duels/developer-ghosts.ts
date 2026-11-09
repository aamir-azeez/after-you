import { runningTotals, validSplits } from "./ticks";

/**
 * The developers' ghost on each board: the time, in game ticks (30 a second,
 * summed over every turn), that a ghost race against "Our run" races. Each is
 * a whole run recorded with Forgiving catches off at the rules a new room
 * plays, as duel rooms always play, kept in the shared blob format in
 * game/content/dev_ghosts.json (made by game/tests/dev_ghost_recorder.gd;
 * game/tests/test_dev_ghosts.gd replays each through the leaderboard replay
 * check). developer-ghosts.test.ts keeps these numbers equal to that file's and
 * the keys equal to the boards.
 *
 * Kept apart from the developers' best times (leaderboards/developer-bests.ts),
 * the floor below which a passed board run waits for a person.
 */
export const DEVELOPER_GHOSTS: Readonly<Record<string, number>> = Object.freeze({
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

/**
 * Each developers' ghost's turns, in ticks and play order, from the same recorded runs (developer-ghosts.test.ts
 * walks each one): what a ghost race's view gives as the ghost's time after each turn (developerGhostSplits).
 */
export const DEVELOPER_GHOST_TURNS: Readonly<Record<string, readonly number[]>> = Object.freeze({
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

/** The developers' ghost's time after each turn on a board, or null when it has none or its turns do not add up to its time. */
export function developerGhostSplits(board: string): number[] | null {
  const turns = (DEVELOPER_GHOST_TURNS as Record<string, readonly number[] | undefined>)[board], ticks = developerGhost(board);
  if (!turns || ticks === null) return null;
  const splits = runningTotals(turns);
  return validSplits(splits, turns.length, ticks) ? splits : null;
}

/** The developers' ghost time on a board, in ticks, or null when it has none. */
export function developerGhost(board: string): number | null {
  const ticks = (DEVELOPER_GHOSTS as Record<string, number | undefined>)[board];
  return typeof ticks === "number" && Number.isSafeInteger(ticks) && ticks > 0 ? ticks : null;
}
