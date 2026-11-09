import { decodeBlob } from "../blob-codec";
import { walkRun } from "../leaderboards/run";
import type { CheckpointV2, RecordingV2 } from "../v2/protocol";

/**
 * A duel side's time so far, read from its room's live checkpoint the way the
 * Fastest pair board reads a finished run (leaderboards/run.ts walkRun): the
 * game ticks of every turn on the current branch, added up. Every turn is
 * unassisted: a duel's room refuses Forgiving catches (v2/room.ts), so a chain
 * with an assisted turn is not a duel run and reads null. A pending first turn of the stage under way (the room's
 * `recording_a`) counts too, so the time moves with every turn.
 *
 * Steps are turns: two per stage, so "3 of 6 steps" on a three-stage chapter
 * means one and a half stages played. Retries on the phone never add.
 *
 * `splits`: the time after each turn, one per step (the last is `ticks`), so a phone can set two sides side by
 * side after the same number of turns while one is ahead (model.ts Side.splits, Ghost.splits).
 */
export type RunProgress = { steps: number; ticks: number; complete: boolean; splits: number[] };

const whole = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 1;

/** Progress for a room at `checkpoint` with `stages` stages, or null when the chain is not whole or has an assisted turn. */
export function runProgress(checkpoint: CheckpointV2, stages: number, pending: RecordingV2 | null = null): RunProgress | null {
  if (checkpoint.stage_index > stages) return null;
  const walked = walkRun(checkpoint);
  if (!walked || walked.assisted) return null;
  const complete = checkpoint.stage_index === stages, turns = [...walked.turns];
  if (pending && !complete) {
    if (!whole(pending.duration_ticks) || pending.catch_assistance !== false) return null;
    turns.push(pending.duration_ticks);
  }
  const splits = runningTotals(turns);
  const ticks = splits.at(-1) ?? 0;
  return Number.isSafeInteger(ticks) ? { steps: turns.length, ticks, complete, splits } : null;
}

/** Each turn's ticks, added up turn by turn. */
export function runningTotals(turns: readonly number[]): number[] {
  let sum = 0;
  return turns.map(ticks => sum += ticks);
}

/** Whether `splits` can stand for a run of `steps` turns timed at `ticks`: one whole, rising total per turn ending at `ticks`. */
export function validSplits(splits: unknown, steps: number, ticks: number): splits is number[] {
  return Array.isArray(splits) && splits.length === steps && (steps === 0 ? ticks === 0 : splits[steps - 1] === ticks) &&
    splits.every((value, index) => whole(value) && (index === 0 || value > splits[index - 1]));
}

/**
 * A board run's time after each turn, read from its kept replay (the tagged blob body of its final checkpoint,
 * leaderboards/proofs.ts) in the board that made the race, so no request of its own. Null unless it is a whole
 * unassisted run of `steps` turns timed at `ticks`, the ghost's own time.
 */
export async function replaySplits(body: Uint8Array, byteLength: number, steps: number, ticks: number): Promise<number[] | null> {
  try {
    const bytes = await decodeBlob(body, byteLength);
    if (!bytes || steps % 2 !== 0) return null;
    const progress = runProgress(JSON.parse(new TextDecoder().decode(bytes)) as CheckpointV2, steps / 2);
    return progress?.complete && validSplits(progress.splits, steps, ticks) ? progress.splits : null;
  } catch { return null; }
}
