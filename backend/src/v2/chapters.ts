import { ApiError, object } from "../protocol";
import * as Relay from "./protocol-relay";
import * as FirstSteps from "./protocol-first-steps";
import { highAndLow, rollingHome, houseForTwo, wishingWell } from "./protocol-cooperative";
import { conservatory, longWayHome, longWayHomeV2, turnOfTheTide } from "./protocol-journey";
import { sleepingLighthouseV2 } from "./protocol-lighthouse";
import { LEGACY_STAGE_COUNT, type ChapterAdapter, type ChapterKey } from "./chapter-types";

export const RELAY_KEY: Readonly<ChapterKey> = Object.freeze({ level_id: Relay.RELAY.id, level_version: Relay.RELAY.version, definition_hash: Relay.DEFINITION_HASH });
const relay: ChapterAdapter = {
  key: RELAY_KEY, recording_version: 2, simulation_version: 2, supported_simulation_versions: [2, 8], premium: false, stages: Relay.RELAY.stages,
  initial: Relay.initialCheckpoint, recording: Relay.recordingV2,
  checkpoint: (value, previous, a, b) => Relay.checkpointV2(value, previous as Relay.CheckpointV2, a as Relay.RecordingV2, b as Relay.RecordingV2),
  accepted(recording) {
    if (recording.role === "a") return !recording.completed && recording.outcome.threw_seed === true;
    const stage = Relay.RELAY.stages.find(value => value.id === recording.stage_id);
    return !!stage && recording.completed && recording.outcome.caught_seed === true &&
      (stage.goal_action === "place_relay" ? recording.outcome.placed_relay === true : recording.outcome.planted_seed === true);
  }
};
/** Every chapter in advertised order, with the wrangler var that gates creating
 * it ("" = always creatable). One flag may gate several chapters. Chapters added
 * after 0.5.1 each pin their own rules, refuse older guests on join, and get
 * their own flag (default "false"). Adding a chapter is one row here plus its
 * adapter and its wrangler var. Never reorder rows: old clients see this order. */
const CHAPTERS: readonly { adapter: ChapterAdapter; flag: keyof Env | "" }[] = [
  { adapter: relay, flag: "" },
  { adapter: FirstSteps.adapter, flag: "FIRST_STEPS_ENABLED" },
  { adapter: highAndLow, flag: "COOP_CHAPTERS_ENABLED" },
  { adapter: rollingHome, flag: "COOP_CHAPTERS_ENABLED" },
  { adapter: houseForTwo, flag: "HOUSE_CHAPTER_ENABLED" },
  { adapter: conservatory, flag: "JOURNEY_CHAPTERS_ENABLED" },
  { adapter: longWayHome, flag: "JOURNEY_CHAPTERS_ENABLED" },
  { adapter: wishingWell, flag: "WISHING_WELL_CHAPTER_ENABLED" },
  { adapter: longWayHomeV2, flag: "LONG_WAY_HOME_V2_CHAPTER_ENABLED" },
  { adapter: turnOfTheTide, flag: "TURN_OF_THE_TIDE_CHAPTER_ENABLED" },
  { adapter: sleepingLighthouseV2, flag: "LIGHTHOUSE_V2_CHAPTER_ENABLED" },
];
const entries: readonly ChapterAdapter[] = CHAPTERS.map(row => row.adapter);

/** Exact immutable authored registry; unknown versions never fall back. */
export function chapter(value: unknown): ChapterAdapter {
  const key = object(value);
  const found = entries.find(entry => entry.key.level_id === key.level_id && entry.key.level_version === key.level_version && entry.key.definition_hash === key.definition_hash);
  if (!found) throw new ApiError(422, "unsupported_chapter");
  return found;
}
export function chapterKey(value: unknown): ChapterKey { return { ...chapter(value).key }; }
export function sameChapter(a: ChapterKey, b: ChapterKey): boolean {
  return a.level_id === b.level_id && a.level_version === b.level_version && a.definition_hash === b.definition_hash;
}
/** The wrangler var gating this chapter: "" if always creatable, undefined if unknown. */
export function chapterFlag(entry: ChapterAdapter): keyof Env | "" | undefined {
  return CHAPTERS.find(row => row.adapter === entry)?.flag;
}
export function creatable(entry: ChapterAdapter, env: Env): boolean {
  const flag = chapterFlag(entry);
  return flag === "" || (flag !== undefined && String(env[flag]) === "true");
}
/** Room level 1 (0.5.x and every client that does not ask): exactly the published
 * two-stage list, byte-identical to before. Room level 2 adds chapters with more
 * stages and names each chapter's stage count. */
export function advertisedChapters(env: Env, roomLevel = 1) {
  return entries.filter(entry => creatable(entry, env) && (roomLevel >= 2 || entry.stages.length === LEGACY_STAGE_COUNT)).map(entry => ({ ...entry.key, premium: entry.premium, recording_version: entry.recording_version, simulation_version: entry.simulation_version, ...(entry.supported_simulation_versions ? { supported_simulation_versions: entry.supported_simulation_versions } : {}), ...(roomLevel >= 2 ? { stage_count: entry.stages.length } : {}) }));
}
