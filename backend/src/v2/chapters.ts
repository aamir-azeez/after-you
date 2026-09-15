import { ApiError, object } from "../protocol";
import * as Relay from "./protocol-relay";
import * as FirstSteps from "./protocol-first-steps";
import type { ChapterAdapter, ChapterKey } from "./chapter-types";

export const RELAY_KEY: Readonly<ChapterKey> = Object.freeze({ level_id: Relay.RELAY.id, level_version: Relay.RELAY.version, definition_hash: Relay.DEFINITION_HASH });
const relay: ChapterAdapter = {
  key: RELAY_KEY, recording_version: 2, simulation_version: 2, premium: false, stages: Relay.RELAY.stages,
  initial: Relay.initialCheckpoint, recording: Relay.recordingV2,
  checkpoint: (value, previous, a, b) => Relay.checkpointV2(value, previous as Relay.CheckpointV2, a as Relay.RecordingV2, b as Relay.RecordingV2),
  accepted(recording) {
    if (recording.role === "a") return !recording.completed && recording.outcome.threw_seed === true;
    const stage = Relay.RELAY.stages.find(value => value.id === recording.stage_id);
    return !!stage && recording.completed && recording.outcome.caught_seed === true &&
      (stage.goal_action === "place_relay" ? recording.outcome.placed_relay === true : recording.outcome.planted_seed === true);
  }
};
const entries: readonly ChapterAdapter[] = [relay, FirstSteps.adapter];

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
export function creatable(entry: ChapterAdapter, env: Env): boolean { return entry === relay || String(env.FIRST_STEPS_ENABLED) === "true"; }
export function advertisedChapters(env: Env) {
  return entries.filter(entry => creatable(entry, env)).map(entry => ({ ...entry.key, premium: entry.premium, recording_version: entry.recording_version, simulation_version: entry.simulation_version }));
}
