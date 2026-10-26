/**
 * The developers' best together time on each board, in game ticks (30 a
 * second, summed over every turn of the run). A run faster than 0.8 times
 * this waits for a person even after its replay passes.
 *
 * Not set yet (null): every passed run on that board waits for a person
 * until the owner fills its number in. leaderboards.test.ts checks that each
 * key is a known board.
 */
export const DEVELOPER_BESTS: Readonly<Record<string, number | null>> = Object.freeze({
  "relay-isles@2": null,
  "first-steps@1": null,
  "high-and-low@1": null,
  "rolling-home@1": null,
  "a-house-for-two@1": null,
  "conservatory@1": null,
  "long-way-home@1": null,
  "the-wishing-well@1": null,
  "long-way-home@2": null,
  "turn-of-the-tide@1": null,
  "sleeping-lighthouse@2": null,
  "turn-of-the-tide@2": null,
});
