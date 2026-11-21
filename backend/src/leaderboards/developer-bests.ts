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
  // The boards these chapters opened again on once every hand control went solid (boards.ts boardKey), each a proxy
  // from the same assisted recording as above, walked again on the chapter's current definition (rolling home: the
  // final checkpoint of game/tests/fixtures/comfort8/recordings.json's rolling-home entry).
  "high-and-low-3b6576ba@1": 520,
  "rolling-home-3362e8af@1": 1197,
  "a-house-for-two-f14fb0ab@1": 1199,
  "conservatory-5e474141@1": 816,
  "long-way-home-79ea6a35@1": 969,
  "the-wishing-well-14cfffbd@1": 1670,
  "long-way-home-9d91b918@2": 977,
  "turn-of-the-tide-bddd9290@1": 1794,
  "turn-of-the-tide-8e29d35f@2": 1999,
  // Unassisted whole run of six stages on the solid mirrors: game/tests/fixtures/lighthouse/v2-chain.json, checkpoints[6].
  "sleeping-lighthouse-925adf59@2": 1473,
});
