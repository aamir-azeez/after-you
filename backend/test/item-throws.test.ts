import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { firstStepsV2, journeyAdapter, FIRST_STEPS_V2_HASH } from "../src/v2/protocol-journey";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import definition from "../../game/tests/fixtures/journey/first-steps-v2-definition.json";
import initial from "../../game/tests/fixtures/journey/first-steps-v2-initial-checkpoint.json";
import liftA from "../../game/tests/fixtures/journey/first-steps-v2-a-little-lift-a.json";
import liftB from "../../game/tests/fixtures/journey/first-steps-v2-a-little-lift-b.json";
import liftC from "../../game/tests/fixtures/journey/first-steps-v2-a-little-lift-c.json";
import liftEnd from "../../game/tests/fixtures/journey/first-steps-v2-a-little-lift-checkpoint.json";
import growA from "../../game/tests/fixtures/journey/first-steps-v2-a-place-to-grow-a.json";
import growB from "../../game/tests/fixtures/journey/first-steps-v2-a-place-to-grow-b.json";
import growC from "../../game/tests/fixtures/journey/first-steps-v2-a-place-to-grow-c.json";
import growEnd from "../../game/tests/fixtures/journey/first-steps-v2-a-place-to-grow-checkpoint.json";
import bundled from "../src/v2/first-steps-v2.json";
import bundledInitial from "../src/v2/first-steps-v2-initial.json";

/**
 * Throws and solid item spots (rules 20, src/v2/protocol-items.ts; the phone's rules are
 * game/core/physical/carried_items.gd) on first-steps@2 (game/tests/test_first_steps_v2.gd writes
 * the fixtures): the seed is thrown from the loft, caught on the shore and planted. The server takes
 * every turn and both closing checkpoints, never a checkpoint with the seed in the air, and refuses a
 * definition whose throw goes nowhere.
 */
type Json = Record<string, any>;
const flat = (checkpoint: Json): Json => { const { proof: _proof, ...rest } = checkpoint; void _proof; return rest; };
async function rehash(checkpoint: Json): Promise<ChapterCheckpoint> {
  const { checkpoint_hash: _hash, ...body } = checkpoint; void _hash;
  return { ...checkpoint, checkpoint_hash: await digest(canonicalJson(body)) } as ChapterCheckpoint;
}
const lift = [liftA, liftB, liftC] as unknown as ChapterRecording[];
const grow = [growA, growB, growC] as unknown as ChapterRecording[];

describe("item throws", () => {
  it("bundles the phone's definition, with a throw and a solid pedestal, on rules 20", async () => {
    expect(bundled).toEqual(definition);
    expect(bundledInitial).toEqual(initial);
    expect(await digest(canonicalJson(definition))).toBe(FIRST_STEPS_V2_HASH);
    expect(firstStepsV2.simulation_version).toBe(20);
    expect((definition as Json).stages[1].throws[0]).toMatchObject({ id: "seed-throw", to: "landing" });
    expect((definition as Json).item_spots[0]).toMatchObject({ id: "seed-pedestal", solid: { radius_cm: 28, reach_cm: 20 } });
  });

  it("accepts every turn and both closing checkpoints, the seed planted at the end", async () => {
    for (const turn of [...lift, ...grow]) expect(await firstStepsV2.recording(turn)).toBeTruthy();
    const afterLift = flat(liftEnd) as ChapterCheckpoint;
    // No seed in the lift stage: it is away until the garden stage puts it on the pedestal.
    const away = { holder: "", spot: "away", x: 0, z: 0, height: 0, surface_id: "" };
    expect((firstStepsV2.initial() as Json).mechanisms.items.seed).toEqual(away);
    expect((afterLift as Json).mechanisms.items.seed).toEqual(away);
    expect(await firstStepsV2.checkpoint(afterLift, firstStepsV2.initial(), lift[0], lift[2], [lift[1]])).toEqual(afterLift);
    const end = flat(growEnd) as ChapterCheckpoint;
    expect((end as Json).mechanisms.items.seed).toMatchObject({ holder: "", spot: "garden" });
    expect(await firstStepsV2.checkpoint(end, afterLift, grow[0], grow[2], [grow[1]])).toEqual(end);
  });

  it("never takes an away seed with a place", async () => {
    const value = structuredClone(flat(liftEnd));
    value.mechanisms.items.seed = { holder: "", spot: "away", x: 230, z: -90, height: 160, surface_id: "loft" };
    await expect(firstStepsV2.checkpoint(await rehash(value), firstStepsV2.initial(), lift[0], lift[2], [lift[1]])).rejects.toMatchObject({ code: "checkpoint_item_mismatch" });
  });

  it("never takes a checkpoint with the seed in the air", async () => {
    const value = structuredClone(flat(growEnd));
    value.mechanisms.items.seed = { holder: "", spot: "", x: -200, z: 0, height: 180, surface_id: "" };
    await expect(firstStepsV2.checkpoint(await rehash(value), flat(liftEnd) as ChapterCheckpoint, grow[0], grow[2], [grow[1]])).rejects.toMatchObject({ code: "checkpoint_item_mismatch" });
  });

  it("refuses a definition whose throw lands nowhere or flies too short to catch", async () => {
    const broken = (change: (value: Json) => void) => { const value: Json = structuredClone(definition); change(value); return value; };
    for (const value of [broken(value => { value.stages[1].throws[0].to = "nowhere"; }), broken(value => { value.stages[1].throws[0].flight_ticks = 5; }),
      broken(value => { value.stages[1].throws[0].mark.surface_id = "sky"; })])
      expect(() => journeyAdapter(value as any, initial as unknown as ChapterCheckpoint, "0".repeat(64))).toThrow(/Throw seed-throw/);
  });
});
