import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { boundedTurnValue, MAX_V2_BODY_BYTES } from "../src/v2/protocol";
import { physicalRecording } from "../src/v2/protocol-physical-recording";
import { advertisedChapters, chapter } from "../src/v2/chapters";
import { wishingWell } from "../src/v2/protocol-cooperative";
import definition from "../../game/tests/fixtures/cooperative/the-wishing-well-definition.json";
import aheadA from "../../game/tests/fixtures/cooperative/go-on-ahead-a.json";
import longB from "../../game/tests/fixtures/cooperative/back-for-you-b-long.json";
import final from "../../game/tests/fixtures/cooperative/the-wishing-well-final-checkpoint.json";

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

  it("registers no published chapter with its own limits or branch cap", () => {
    const allOn: Env = { ...env }; Object.assign(allOn, { COOP_CHAPTERS_ENABLED: "true", HOUSE_CHAPTER_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: "true", FIRST_STEPS_ENABLED: "true",
      WISHING_WELL_CHAPTER_ENABLED: "true", LONG_WAY_HOME_V2_CHAPTER_ENABLED: "true", TURN_OF_THE_TIDE_CHAPTER_ENABLED: "true" });
    const rows = advertisedChapters(allOn, 2);
    expect(rows.length).toBeGreaterThan(7);
    for (const row of rows) {
      const adapter = chapter(row);
      expect(adapter.stages.length).toBe(2);
      expect(adapter.limits).toBeUndefined();
      expect(adapter.max_branches).toBeUndefined();
    }
  });
});
