import { ApiError, isObject } from "../protocol";
import type { CheckpointV2, RecordingV2 } from "./protocol";

type Proof = { checkpoint?: unknown; previous_checkpoint?: unknown; a?: unknown; b?: unknown };

/**
 * Every adapter accepts a checkpoint only when its proof nests the previous one
 * canonically equal (relay under `previous_checkpoint`, the others under
 * `checkpoint`), so the live checkpoint carries every earlier stage of its lineage.
 */
export function nestedProof(checkpoint: CheckpointV2): { previous: CheckpointV2; a: RecordingV2; b: RecordingV2 } | null {
  const proof = (checkpoint as CheckpointV2 & { proof?: Proof }).proof;
  if (!isObject(proof)) return null;
  const previous = proof.checkpoint ?? proof.previous_checkpoint;
  if (!isObject(previous) || !isObject(proof.a) || !isObject(proof.b)) return null;
  return { previous: previous as CheckpointV2, a: proof.a as RecordingV2, b: proof.b as RecordingV2 };
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
