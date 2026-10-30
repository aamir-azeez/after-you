/**
 * The developers' ghost on each board: the time, in game ticks (30 a second,
 * summed over every turn), that a ghost race against "Our run" races. Each is
 * a whole run recorded with Forgiving catches off at the rules a new room
 * plays, as duel rooms always play, kept in the shared blob format in
 * game/tests/fixtures/dev_ghosts.json (made by game/tests/dev_ghost_recorder.gd;
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

/** The developers' ghost time on a board, in ticks, or null when it has none. */
export function developerGhost(board: string): number | null {
  const ticks = (DEVELOPER_GHOSTS as Record<string, number | undefined>)[board];
  return typeof ticks === "number" && Number.isSafeInteger(ticks) && ticks > 0 ? ticks : null;
}
