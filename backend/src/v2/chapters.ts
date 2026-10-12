import { ApiError, object } from "../protocol";
import * as Relay from "./protocol-relay";
import * as FirstSteps from "./protocol-first-steps";
import { highAndLow, rollingHome, houseForTwo, wishingWell } from "./protocol-cooperative";
import { conservatory, longWayHome, longWayHomeV2, turnOfTheTide } from "./protocol-journey";
import type { ChapterAdapter, ChapterKey } from "./chapter-types";

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
/** Chapters added after 0.5.1. Each pins its own rules, refuses older guests on
 * join, and is creatable only behind its own flag (default "false"). Adding a
 * chapter is one row here plus its adapter and its wrangler var. */
const FLAGGED: readonly { adapter: ChapterAdapter; flag: keyof Env }[] = [
  { adapter: wishingWell, flag: "WISHING_WELL_CHAPTER_ENABLED" },
  { adapter: longWayHomeV2, flag: "LONG_WAY_HOME_V2_CHAPTER_ENABLED" },
  { adapter: turnOfTheTide, flag: "TURN_OF_THE_TIDE_CHAPTER_ENABLED" },
];
const entries: readonly ChapterAdapter[] = [relay, FirstSteps.adapter, highAndLow, rollingHome, houseForTwo, conservatory, longWayHome, ...FLAGGED.map(row => row.adapter)];

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
export function creatable(entry: ChapterAdapter, env: Env): boolean {
  if (entry === relay) return true;
  const flagged = FLAGGED.find(row => row.adapter === entry);
  if (flagged) return String(env[flagged.flag]) === "true";
  if (entry === FirstSteps.adapter) return String(env.FIRST_STEPS_ENABLED) === "true";
  if (entry === houseForTwo) return String(env.HOUSE_CHAPTER_ENABLED) === "true";
  if (entry === conservatory || entry === longWayHome) return String(env.JOURNEY_CHAPTERS_ENABLED) === "true";
  return (entry === highAndLow || entry === rollingHome) && String(env.COOP_CHAPTERS_ENABLED) === "true";
}
export function advertisedChapters(env: Env) {
  return entries.filter(entry => creatable(entry, env)).map(entry => ({ ...entry.key, premium: entry.premium, recording_version: entry.recording_version, simulation_version: entry.simulation_version, ...(entry.supported_simulation_versions ? { supported_simulation_versions: entry.supported_simulation_versions } : {}) }));
}
