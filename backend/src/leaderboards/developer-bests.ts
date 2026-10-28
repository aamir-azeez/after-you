/**
 * The developers' best together time on each board, in game ticks (30 a
 * second, summed over every turn of the run). A run faster than 0.8 times
 * this waits for a person even after its replay passes.
 *
 * Not set yet (null): every passed run on that board waits for a person
 * until the owner fills its number in. leaderboards.test.ts checks that each
 * key is a known board.
 *
 * Each number is runTicks (run.ts) on the final checkpoint of a whole run in
 * the game test fixtures. Most boards have only assisted whole runs recorded,
 * so they hold the fastest of those as a proxy until an unassisted run is
 * recorded. Forgiving catches only changes whether a catch counts, so a run
 * moves at about the same speed with it on or off. The floor only decides
 * which passed runs wait for a person: every ranked run has still passed its
 * replay.
 */
export const DEVELOPER_BESTS: Readonly<Record<string, number | null>> = Object.freeze({
  // Proxy from an assisted recording (game/tests/fixtures/v2/final-checkpoint.json), replace with an unassisted run.
  "relay-isles@2": 588,
  // Proxy from an assisted recording (game/tests/fixtures/first_steps/final-checkpoint.json), replace with an unassisted run.
  "first-steps@1": 406,
  // Proxy from an assisted recording (game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json), replace with an unassisted run.
  "high-and-low@1": 531,
  // Proxy from an assisted recording (game/tests/fixtures/comfort8/recordings.json, rolling-home entry), replace with an unassisted run.
  "rolling-home@1": 1173,
  // Proxy from an assisted recording (game/tests/fixtures/cooperative/a-house-for-two-final-checkpoint.json), replace with an unassisted run.
  "a-house-for-two@1": 1212,
  // Proxy from an assisted recording (game/tests/fixtures/journey/conservatory-final-checkpoint.json), replace with an unassisted run.
  "conservatory@1": 773,
  // Proxy from an assisted recording (game/tests/fixtures/journey/long-way-home-final-checkpoint.json), replace with an unassisted run.
  "long-way-home@1": 973,
  // Proxy from an assisted recording (game/tests/fixtures/cooperative/the-wishing-well-final-checkpoint.json), replace with an unassisted run.
  "the-wishing-well@1": 1698,
  // Proxy from an assisted recording (game/tests/fixtures/journey/long-way-home-v2-final-checkpoint.json), replace with an unassisted run.
  "long-way-home@2": 989,
  // Proxy from an assisted recording (game/tests/fixtures/journey/slack-water-high-punt-checkpoint.json), replace with an unassisted run.
  "turn-of-the-tide@1": 1756,
  // Unassisted whole run of six stages: game/tests/fixtures/lighthouse/v2-chain.json, checkpoints[6].
  "sleeping-lighthouse@2": 1470,
  // Proxy from an assisted recording (game/tests/fixtures/journey/turn-of-the-tide-v2-final-checkpoint.json), replace with an unassisted run.
  "turn-of-the-tide@2": 1906,
});
