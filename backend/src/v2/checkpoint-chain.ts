import { ApiError, isObject } from "../protocol";
import type { CheckpointV2, RecordingV2 } from "./protocol";

type Proof = { checkpoint?: unknown; previous_checkpoint?: unknown; a?: unknown; b?: unknown; turns?: unknown };

/**
 * Every adapter accepts a checkpoint only when its proof nests the previous one
 * canonically equal (relay under `previous_checkpoint`, the others under
 * `checkpoint`), so the live checkpoint carries every earlier stage of its lineage.
 */
/**
 * `turns`: every turn of the stage in play order; a and b are its first and its closing turn. A room's open turns
 * checkpoint nests nothing (open-turns.ts fingerprints), so this is null for it; a run a phone posts from its own copy
 * nests every turn (leaderboards/run.ts openRoomRun).
 */
export function nestedProof(checkpoint: CheckpointV2): { previous: CheckpointV2; a: RecordingV2; b: RecordingV2; turns: RecordingV2[] } | null {
  const proof = (checkpoint as CheckpointV2 & { proof?: Proof }).proof;
  if (!isObject(proof)) return null;
  const previous = proof.checkpoint ?? proof.previous_checkpoint;
  if (!isObject(previous)) return null;
  if (Array.isArray(proof.turns)) {
    const turns = proof.turns as unknown[];
    if (turns.length < 2 || !turns.every(isObject)) return null;
    return { previous: previous as CheckpointV2, a: turns[0] as RecordingV2, b: turns.at(-1) as RecordingV2, turns: turns as RecordingV2[] };
  }
  if (!isObject(proof.a) || !isObject(proof.b)) return null;
  return { previous: previous as CheckpointV2, a: proof.a as RecordingV2, b: proof.b as RecordingV2, turns: [proof.a as RecordingV2, proof.b as RecordingV2] };
}

/** The checkpoint reached after `stageIndex` stages, read out of a later checkpoint of the same lineage. */
export function checkpointAt(checkpoint: CheckpointV2, stageIndex: number): CheckpointV2 {
  let current = checkpoint;
  while (current.stage_index > stageIndex) {
    const proof = nestedProof(current);
    if (!proof) throw new ApiError(500, "checkpoint_chain_broken");
    current = proof.previous;
  }
  if (current.stage_index !== stageIndex) throw new ApiError(500, "checkpoint_chain_broken");
  return current;
}
