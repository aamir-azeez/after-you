import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import * as FirstSteps from "../src/v2/protocol-first-steps";
import { highAndLow, rollingHome, houseForTwo, wishingWell } from "../src/v2/protocol-cooperative";
import { conservatory, longWayHome, longWayHomeV2, turnOfTheTide } from "../src/v2/protocol-journey";
import { sleepingLighthouseV2 } from "../src/v2/protocol-lighthouse";
import { LEGACY_STAGE_COUNT, type ChapterAdapter } from "../src/v2/chapter-types";
import { RELAY_KEY, advertisedChapters, chapter, chapterFlag, creatable } from "../src/v2/chapters";

// A frozen copy of creatable() and the advertised order before the flag table,
// so the table provably gates and lists every chapter exactly as before.
const relay = chapter(RELAY_KEY);
const OLD_FLAGGED: readonly { adapter: ChapterAdapter; flag: keyof Env }[] = [
  { adapter: wishingWell, flag: "WISHING_WELL_CHAPTER_ENABLED" },
  { adapter: longWayHomeV2, flag: "LONG_WAY_HOME_V2_CHAPTER_ENABLED" },
  { adapter: turnOfTheTide, flag: "TURN_OF_THE_TIDE_CHAPTER_ENABLED" },
  { adapter: sleepingLighthouseV2, flag: "LIGHTHOUSE_V2_CHAPTER_ENABLED" },
];
const OLD_ENTRIES: readonly ChapterAdapter[] = [relay, FirstSteps.adapter, highAndLow, rollingHome, houseForTwo, conservatory, longWayHome, ...OLD_FLAGGED.map(row => row.adapter)];
function oldCreatable(entry: ChapterAdapter, env: Env): boolean {
  if (entry === relay) return true;
  const flagged = OLD_FLAGGED.find(row => row.adapter === entry);
  if (flagged) return String(env[flagged.flag]) === "true";
  if (entry === FirstSteps.adapter) return String(env.FIRST_STEPS_ENABLED) === "true";
  if (entry === houseForTwo) return String(env.HOUSE_CHAPTER_ENABLED) === "true";
  if (entry === conservatory || entry === longWayHome) return String(env.JOURNEY_CHAPTERS_ENABLED) === "true";
  return (entry === highAndLow || entry === rollingHome) && String(env.COOP_CHAPTERS_ENABLED) === "true";
}
function oldAdvertised(env: Env, roomLevel = 1) {
  return OLD_ENTRIES.filter(entry => oldCreatable(entry, env) && (roomLevel >= 2 || entry.stages.length === LEGACY_STAGE_COUNT)).map(entry => ({ ...entry.key, premium: entry.premium, recording_version: entry.recording_version, simulation_version: entry.simulation_version, ...(entry.supported_simulation_versions ? { supported_simulation_versions: entry.supported_simulation_versions } : {}), ...(roomLevel >= 2 ? { stage_count: entry.stages.length } : {}) }));
}
const FLAGS: readonly (keyof Env)[] = ["FIRST_STEPS_ENABLED", "COOP_CHAPTERS_ENABLED", "HOUSE_CHAPTER_ENABLED", "JOURNEY_CHAPTERS_ENABLED",
  "WISHING_WELL_CHAPTER_ENABLED", "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "TURN_OF_THE_TIDE_CHAPTER_ENABLED", "LIGHTHOUSE_V2_CHAPTER_ENABLED"];
/** Env with exactly the flags in `mask` set to `on`, the rest to `off`. */
function configured(mask: number, on: unknown, off: unknown): Env {
  const result: Env = { ...env };
  FLAGS.forEach((flag, bit) => Object.assign(result, { [flag]: mask & (1 << bit) ? on : off }));
  return result;
}

describe("chapter flag table", () => {
  it("gates and advertises every chapter exactly as the old hard-coded checks, for every flag combination", () => {
    // "true"/"false" as wrangler sets them, plus a boolean and an absent var, which String() also read.
    for (const [on, off] of [["true", "false"], [true, undefined]] as const) {
      for (let mask = 0; mask < 1 << FLAGS.length; mask++) {
        const vars = configured(mask, on, off);
        for (const entry of OLD_ENTRIES) expect(creatable(entry, vars), `${entry.key.level_id}@${entry.key.level_version} mask ${mask}`).toBe(oldCreatable(entry, vars));
        for (const level of [1, 2]) expect(JSON.stringify(advertisedChapters(vars, level)), `level ${level} mask ${mask}`).toBe(JSON.stringify(oldAdvertised(vars, level)));
      }
    }
    expect(JSON.stringify(advertisedChapters(env))).toBe(JSON.stringify(oldAdvertised(env)));
  });
  it("names each chapter's creation flag, shared where two chapters share one", () => {
    expect(chapterFlag(relay)).toBe("");
    const named = OLD_ENTRIES.filter(entry => entry !== relay).map(entry => chapterFlag(entry));
    expect(named).toEqual(["FIRST_STEPS_ENABLED", "COOP_CHAPTERS_ENABLED", "COOP_CHAPTERS_ENABLED", "HOUSE_CHAPTER_ENABLED", "JOURNEY_CHAPTERS_ENABLED", "JOURNEY_CHAPTERS_ENABLED",
      "WISHING_WELL_CHAPTER_ENABLED", "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "TURN_OF_THE_TIDE_CHAPTER_ENABLED", "LIGHTHOUSE_V2_CHAPTER_ENABLED"]);
    expect(new Set(named)).toEqual(new Set(FLAGS));
    const stranger = { ...highAndLow };
    expect(chapterFlag(stranger)).toBeUndefined();
    expect(creatable(stranger, configured((1 << FLAGS.length) - 1, "true", "false"))).toBe(false);
  });
});
