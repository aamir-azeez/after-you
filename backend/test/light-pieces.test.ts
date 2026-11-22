import { describe, expect, it } from "vitest";
import { lightSignals, type LightStage } from "../src/v2/light-pieces";
import { gateHolds, type Predicate } from "../src/v2/protocol-journey";
import type { ItemState } from "../src/v2/protocol-items";
import light from "../../game/tests/fixtures/light_pieces/cases.json";

// The light pieces' cases (game/tests/fixtures/light_pieces/cases.json; game/tests/test_light_pieces.gd
// lights the same cases through the phone's light_pieces.gd): a light pad, a lens in its cradle, a mirror
// control and a selector that steers a mirror or puts a lamp out.
describe("light pieces", () => {
  const stage = light.stage as unknown as LightStage & { pressure_pads: [] };
  for (const sample of light.cases) {
    it(`lights what the phone lights: ${sample.name}`, () => {
      const items = sample.items as Record<string, ItemState>;
      const lit = lightSignals(stage, sample.controls, when => gateHolds(when as Predicate,
        { controls: sample.controls, levers: {}, light: {}, players: sample.players, stage, open: true, items }));
      expect(lit).toEqual(sample.signals);
    });
  }

  it("has no light without a field", () => {
    expect(lightSignals({ controls: [] }, {}, () => true)).toEqual({});
  });
});
