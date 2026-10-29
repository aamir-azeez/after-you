import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import * as FirstSteps from "../src/v2/protocol-first-steps";
import { highAndLow, rollingHome, houseForTwo, wishingWell } from "../src/v2/protocol-cooperative";
import { conservatory, longWayHome, longWayHomeV2, turnOfTheTide, turnOfTheTideV2 } from "../src/v2/protocol-journey";
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
    expect(CHAPTERS.map(row => row.adapter)).toEqual(LIVE_ORDER);
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
