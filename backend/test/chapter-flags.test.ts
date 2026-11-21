import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import * as FirstSteps from "../src/v2/protocol-first-steps";
import { highAndLow, highAndLowV2, rollingHome, rollingHomeV2, houseForTwo, houseForTwoV2, wishingWell, wishingWellV2 } from "../src/v2/protocol-cooperative";
import { conservatory, conservatoryV2, firstStepsV2, fogMarsh, longWayHome, longWayHomeV2, longWayHomeV3, relayIslesV3, sleepingLighthouseV3, theFalls, turnOfTheTide, turnOfTheTideV2, turnOfTheTideV3 } from "../src/v2/protocol-journey";
import { sleepingLighthouseV2 } from "../src/v2/protocol-lighthouse";
import { LEGACY_STAGE_COUNT, type ChapterAdapter } from "../src/v2/chapter-types";
import { CHAPTERS, RELAY_KEY, advertisedChapters, chapter, chapterFlag, creatable } from "../src/v2/chapters";
import { withConfig } from "./config";

// The advertised order and fields as live served them with every chapter flag on, before those flags retired.
const relay = chapter(RELAY_KEY);
const LIVE_ORDER: readonly ChapterAdapter[] = [relay, FirstSteps.adapter, highAndLow, rollingHome, houseForTwo, conservatory, longWayHome, wishingWell,
  longWayHomeV2, turnOfTheTide, sleepingLighthouseV2, turnOfTheTideV2];
function liveAdvertised(roomLevel: number) {
  return LIVE_ORDER.filter(entry => roomLevel >= 2 || entry.stages.length === LEGACY_STAGE_COUNT).map(entry => ({ ...entry.key, premium: entry.premium, recording_version: entry.recording_version,
    simulation_version: entry.simulation_version, ...(entry.supported_simulation_versions ? { supported_simulation_versions: entry.supported_simulation_versions } : {}),
    ...(roomLevel >= 2 ? { stage_count: entry.stages.length } : {}) }));
}

describe("chapter table", () => {
  it("creates and advertises every published chapter, in live's order, whatever CONFIG says", () => {
    // Unreleased chapters follow the published ones, each behind its own flag (off unless CONFIG lists it).
    const UNRELEASED: readonly [ChapterAdapter, string][] = [[longWayHomeV3, "LONG_WAY_HOME_V3_CHAPTER_ENABLED"], [turnOfTheTideV3, "TURN_OF_THE_TIDE_V3_CHAPTER_ENABLED"],
      [conservatoryV2, "CONSERVATORY_V2_CHAPTER_ENABLED"], [highAndLowV2, "HIGH_AND_LOW_V2_CHAPTER_ENABLED"], [wishingWellV2, "THE_WISHING_WELL_V2_CHAPTER_ENABLED"], [firstStepsV2, "FIRST_STEPS_V2_CHAPTER_ENABLED"],
      [rollingHomeV2, "ROLLING_HOME_V2_CHAPTER_ENABLED"], [houseForTwoV2, "A_HOUSE_FOR_TWO_V2_CHAPTER_ENABLED"], [theFalls, "THE_FALLS_CHAPTER_ENABLED"], [fogMarsh, "FOG_MARSH_CHAPTER_ENABLED"],
      [relayIslesV3, "RELAY_ISLES_V3_CHAPTER_ENABLED"],
      [sleepingLighthouseV3, "SLEEPING_LIGHTHOUSE_V3_CHAPTER_ENABLED"]];
    expect(CHAPTERS.map(row => row.adapter)).toEqual([...LIVE_ORDER, ...UNRELEASED.map(([entry]) => entry)]);
    for (const [entry, flag] of UNRELEASED) {
      expect(chapterFlag(entry)).toBe(flag);
      expect(creatable(entry, withConfig({ ...env }) as Env)).toBe(false);
      expect(creatable(entry, withConfig({ ...env, [flag]: "true" }) as Env)).toBe(true);
    }
    for (const vars of [withConfig({ ...env }), { ...env, CONFIG: "not json" }] as Env[]) {
      for (const entry of LIVE_ORDER) {
        expect(chapterFlag(entry), entry.key.level_id).toBe("");
        expect(creatable(entry, vars), entry.key.level_id).toBe(true);
      }
      for (const level of [1, 2]) expect(JSON.stringify(advertisedChapters(vars, level)), `level ${level}`).toBe(JSON.stringify(liveAdvertised(level)));
    }
  });
  it("knows no chapter outside the table", () => {
    const stranger = { ...highAndLow };
    expect(chapterFlag(stranger)).toBeUndefined();
    expect(creatable(stranger, withConfig({ ...env }) as Env)).toBe(false);
  });
});
