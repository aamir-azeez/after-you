import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { boundedTurnValue, MAX_V2_BODY_BYTES } from "../src/v2/protocol";
import { physicalRecording, scaledLimits } from "../src/v2/protocol-physical-recording";
import { advertisedChapters, chapter } from "../src/v2/chapters";
import { wishingWell } from "../src/v2/protocol-cooperative";
import definition from "../../game/tests/fixtures/cooperative/the-wishing-well-definition.json";
import aheadA from "../../game/tests/fixtures/cooperative/go-on-ahead-a.json";
import longB from "../../game/tests/fixtures/cooperative/back-for-you-b-long.json";
import final from "../../game/tests/fixtures/cooperative/the-wishing-well-final-checkpoint.json";
import { sleepingLighthouseV2 } from "../src/v2/protocol-lighthouse";

// Per-chapter size bounds, turn length and branch caps are optional. A chapter
// that sets none keeps every published bound, including the comfort receiver's
// 1,200 ticks.
describe("per-chapter limits", () => {
  it("leaves the published turn bounds alone when a chapter sets none", () => {
    expect(() => boundedTurnValue({ schema_version: 2, recording: longB, checkpoint: final })).not.toThrow();
    expect(() => boundedTurnValue({ schema_version: 2, recording: longB, checkpoint: final }, undefined)).not.toThrow();
    const wide = { pad: Array.from({ length: Math.ceil(MAX_V2_BODY_BYTES / 500) + 1 }, () => "x".repeat(500)) };
    expect(() => boundedTurnValue(wide)).toThrow("value_too_large");
    expect(() => boundedTurnValue(wide, { turn_body_bytes: MAX_V2_BODY_BYTES * 2, turn_body_values: 44_000 })).not.toThrow();
    expect(() => boundedTurnValue({ schema_version: 2, recording: longB, checkpoint: final }, { turn_body_bytes: 1024, turn_body_values: 44_000 })).toThrow("value_too_large");
  });

  it("caps turn length only when a chapter asks", async () => {
    const supported = wishingWell.supported_simulation_versions ?? [wishingWell.simulation_version];
    const published = physicalRecording(definition, wishingWell.key, 6, supported);
    const unbounded = physicalRecording(definition, wishingWell.key, 6, supported, Number.MAX_SAFE_INTEGER);
    expect(longB.duration_ticks).toBeGreaterThan(900);
    expect(await published(longB)).toEqual(longB);
    expect(await unbounded(longB)).toEqual(longB);
    expect(await physicalRecording(definition, wishingWell.key, 6, supported, aheadA.duration_ticks)(aheadA)).toEqual(aheadA);
    await expect(physicalRecording(definition, wishingWell.key, 6, supported, aheadA.duration_ticks - 1)(aheadA)).rejects.toThrow();
    await expect(physicalRecording(definition, wishingWell.key, 6, supported, 900)(longB)).rejects.toThrow();
  });

  it("registers no published chapter with its own limits or branch cap, beyond the turn caps and branch cap Turn of the Tide declares", () => {
    // Sleeping Lighthouse @2 has six stages and its own bounds, pinned in its own suite.
    const rows = advertisedChapters(env, 2).filter(row => chapter(row) !== sleepingLighthouseV2);
    expect(rows.length).toBeGreaterThan(7);
    expect(rows.some(row => row.level_id === "turn-of-the-tide")).toBe(true);
    for (const row of rows) {
      const adapter = chapter(row);
      expect(adapter.stages.length).toBe(2);
      // Turn of the Tide declares longer turns, and its bounds grow with them.
      if (row.level_id === "turn-of-the-tide") expect(adapter.limits).toEqual(scaledLimits({ a_ticks: 2700, b_ticks: 3000 }));
      else expect(adapter.limits).toBeUndefined();
      expect(adapter.max_branches).toBe(row.level_id === "turn-of-the-tide" ? 7 : undefined);
    }
  });
});
