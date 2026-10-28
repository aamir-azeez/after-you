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
 * the game test fixtures. Only an unassisted run counts. A null board has only
 * assisted whole runs recorded, so its comment names the fastest of those for
 * reference; that time is not a best because an assisted run cannot rank.
 */
export const DEVELOPER_BESTS: Readonly<Record<string, number | null>> = Object.freeze({
  // Assisted only: fastest is 588 in game/tests/fixtures/v2/final-checkpoint.json.
  "relay-isles@2": null,
  // Assisted only: fastest is 406 in game/tests/fixtures/first_steps/final-checkpoint.json.
  "first-steps@1": null,
  // Assisted only: fastest is 531 in game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json.
  "high-and-low@1": null,
  // Assisted only: fastest is 1173 in game/tests/fixtures/comfort8/recordings.json (rolling-home).
  "rolling-home@1": null,
  // Assisted only: fastest is 1212 in game/tests/fixtures/cooperative/a-house-for-two-final-checkpoint.json.
  "a-house-for-two@1": null,
  // Assisted only: fastest is 773 in game/tests/fixtures/journey/conservatory-final-checkpoint.json.
  "conservatory@1": null,
  // Assisted only: fastest is 973 in game/tests/fixtures/journey/long-way-home-final-checkpoint.json.
  "long-way-home@1": null,
  // Assisted only: fastest is 1698 in game/tests/fixtures/cooperative/the-wishing-well-final-checkpoint.json.
  "the-wishing-well@1": null,
  // Assisted only: fastest is 989 in game/tests/fixtures/journey/long-way-home-v2-final-checkpoint.json.
  "long-way-home@2": null,
  // Assisted only: fastest is 1756 in game/tests/fixtures/journey/slack-water-high-punt-checkpoint.json.
  "turn-of-the-tide@1": null,
  // Unassisted whole run of six stages: game/tests/fixtures/lighthouse/v2-chain.json, checkpoints[6].
  "sleeping-lighthouse@2": 1470,
  // Assisted only: fastest is 1906 in game/tests/fixtures/journey/turn-of-the-tide-v2-final-checkpoint.json.
  "turn-of-the-tide@2": null,
});
