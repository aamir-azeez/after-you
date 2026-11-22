import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { wishingWellV2, WISHING_WELL_V2_HASH } from "../src/v2/protocol-journey";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import definition from "../../game/tests/fixtures/journey/the-wishing-well-v2-definition.json";
import initial from "../../game/tests/fixtures/journey/the-wishing-well-v2-initial-checkpoint.json";
import aheadA from "../../game/tests/fixtures/journey/the-wishing-well-v2-go-on-ahead-a.json";
import aheadB from "../../game/tests/fixtures/journey/the-wishing-well-v2-go-on-ahead-b.json";
import aheadC from "../../game/tests/fixtures/journey/the-wishing-well-v2-go-on-ahead-c.json";
import aheadD from "../../game/tests/fixtures/journey/the-wishing-well-v2-go-on-ahead-d.json";
import aheadEnd from "../../game/tests/fixtures/journey/the-wishing-well-v2-go-on-ahead-checkpoint.json";
import backA from "../../game/tests/fixtures/journey/the-wishing-well-v2-back-for-you-a.json";
import backB from "../../game/tests/fixtures/journey/the-wishing-well-v2-back-for-you-b.json";
import backC from "../../game/tests/fixtures/journey/the-wishing-well-v2-back-for-you-c.json";
import backEnd from "../../game/tests/fixtures/journey/the-wishing-well-v2-back-for-you-checkpoint.json";
import bundled from "../src/v2/the-wishing-well-v2.json";
import bundledInitial from "../src/v2/the-wishing-well-v2-initial.json";

/**
 * The Wishing Well@2 on the journey rules with the new pieces (20; game/tests/test_the_wishing_well_v2.gd writes the
 * fixtures): the old crane's swinging bucket over the garden plank (a beat kept in the phone's world, never in a
 * checkpoint, game/core/physical/swings.gd) and the winch handle thrown up from the well. The server takes every
 * carry-over turn and both closing checkpoints, the handle fitted in the winch at the end.
 */
type Json = Record<string, any>;
const flat = (checkpoint: Json): Json => { const { proof: _proof, ...rest } = checkpoint; void _proof; return rest; };
async function rehash(checkpoint: Json): Promise<ChapterCheckpoint> {
  const { checkpoint_hash: _hash, ...body } = checkpoint; void _hash;
  return { ...checkpoint, checkpoint_hash: await digest(canonicalJson(body)) } as ChapterCheckpoint;
}
const ahead = [aheadA, aheadB, aheadC, aheadD] as unknown as ChapterRecording[];
const back = [backA, backB, backC] as unknown as ChapterRecording[];

describe("the Wishing Well@2", () => {
  it("bundles the phone's definition on rules 20, with the crane's swing and the handle's throw", async () => {
    expect(bundled).toEqual(definition);
    expect(bundledInitial).toEqual(initial);
    expect(await digest(canonicalJson(definition))).toBe(WISHING_WELL_V2_HASH);
    expect(wishingWellV2.simulation_version).toBe(20);
    expect(wishingWellV2.open_turns?.caps).toEqual([10, 10]);
    expect((definition as Json).stages[0].swings[0]).toMatchObject({ id: "well-crane", brake: { pad_id: "brake-board" }, outcome: "drowned" });
    expect((definition as Json).stages[1].throws[0]).toMatchObject({ id: "handle-throw", to: "winch-landing" });
  });

  it("accepts every turn and both closing checkpoints, the handle in the winch at the end", async () => {
    for (const turn of [...ahead, ...back]) expect(await wishingWellV2.recording(turn)).toBeTruthy();
    const afterAhead = flat(aheadEnd) as ChapterCheckpoint;
    expect(await wishingWellV2.checkpoint(afterAhead, wishingWellV2.initial(), ahead[0], ahead[3], ahead.slice(1, 3))).toEqual(afterAhead);
    const end = flat(backEnd) as ChapterCheckpoint;
    expect((end as Json).mechanisms.items.handle).toMatchObject({ holder: "", spot: "winch" });
    expect(await wishingWellV2.checkpoint(end, afterAhead, back[0], back[2], [back[1]])).toEqual(end);
  });

  it("refuses a closing checkpoint with a pip away from the bell", async () => {
    const value = structuredClone(flat(aheadEnd));
    value.players.p0.x = 0;
    await expect(wishingWellV2.checkpoint(await rehash(value), wishingWellV2.initial(), ahead[0], ahead[3], ahead.slice(1, 3))).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
  });
});
