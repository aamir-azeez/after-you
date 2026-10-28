import { walkRun } from "../leaderboards/run";
import type { CheckpointV2, RecordingV2 } from "../v2/protocol";

/**
 * A duel side's time so far, read from its room's live checkpoint the way the
 * Fastest pair board reads a finished run (leaderboards/run.ts walkRun): the
 * game ticks of every turn on the current branch, added up. Unlike the board,
 * assisted turns count (forgiving catches are on by default); the run only
 * says it had one. A pending first turn of the stage under way (the room's
 * `recording_a`) counts too, so the time moves with every turn.
 *
 * Steps are turns: two per stage, so "3 of 6 steps" on a three-stage chapter
 * means one and a half stages played. Retries on the phone never add.
 */
export type RunProgress = { steps: number; ticks: number; assisted: boolean; complete: boolean };

const whole = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 1;

/** Progress for a room at `checkpoint` with `stages` stages, or null when the chain is not whole. */
export function runProgress(checkpoint: CheckpointV2, stages: number, pending: RecordingV2 | null = null): RunProgress | null {
  if (checkpoint.stage_index > stages) return null;
  const walked = walkRun(checkpoint);
  if (!walked) return null;
  const complete = checkpoint.stage_index === stages;
  let { ticks, assisted } = walked, steps = checkpoint.stage_index * 2;
  if (pending && !complete) {
    if (!whole(pending.duration_ticks)) return null;
    if (pending.catch_assistance !== false) assisted = true;
    ticks += pending.duration_ticks;
    steps++;
  }
  return Number.isSafeInteger(ticks) ? { steps, ticks, assisted, complete } : null;
}
