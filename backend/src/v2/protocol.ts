import { ApiError } from "../protocol";
import { chapter, RELAY_KEY, sameChapter } from "./chapters";
import type { ChapterKey, ChapterCheckpoint, ChapterRecording } from "./chapter-types";

// The frozen Relay adapter retains its exact schema, canonical bytes and bounds.
export { RELAY, DEFINITION_HASH, MAX_RECORDING_BYTES, MAX_CHECKPOINT_BYTES, MAX_V2_BODY_BYTES, boundedValue, boundedTurnValue, exact } from "./protocol-relay";
export type { Slot } from "./chapter-types";
export type RecordingV2 = ChapterRecording;
export type CheckpointV2 = ChapterCheckpoint;
export { chapter, chapterKey, RELAY_KEY } from "./chapters";

export function validateCatalog(level_id: unknown, level_version: unknown, definition_hash: unknown): void {
  chapter({ level_id, level_version, definition_hash });
}
export function initialCheckpoint(key: ChapterKey = RELAY_KEY): CheckpointV2 { return chapter(key).initial(); }
export async function recordingV2(value: unknown, expected?: ChapterKey): Promise<RecordingV2> {
  const adapter = chapter(value);
  if (expected && !sameChapter(adapter.key, chapter(expected).key)) throw new ApiError(422, "recording_chapter_mismatch");
  return adapter.recording(value);
}
/** `passes`: an open turns stage's turns between the first and the closing one (open-turns.ts). */
export async function checkpointV2(value: unknown, previous: CheckpointV2, a: RecordingV2, b: RecordingV2, passes: readonly RecordingV2[] = []): Promise<CheckpointV2> {
  const adapter = chapter(previous);
  if (![value, a, b, ...passes].every(item => sameChapter(adapter.key, chapter(item).key))) throw new ApiError(422, "checkpoint_chapter_mismatch");
  if (passes.length && !adapter.open_turns) throw new ApiError(422, "checkpoint_recording_mismatch");
  return passes.length ? adapter.checkpoint(value, previous, a, b, passes) : adapter.checkpoint(value, previous, a, b);
}
export function acceptedRecording(recording: RecordingV2): boolean { return chapter(recording).accepted(recording); }
