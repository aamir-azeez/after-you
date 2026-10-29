import { digest } from "../protocol";
import { chapter } from "../v2/chapters";
import { nestedProof } from "../v2/checkpoint-chain";
import type { ChapterKey } from "../v2/chapter-types";
import type { CheckpointV2 } from "../v2/protocol";
import type { MutationV2 } from "../v2/room";
import { boardKey } from "./boards";
import { boardLooksOf, type PairLooks } from "./run-looks";

/** A finished together run as a board receives it. Never sent to a phone: it names both players. */
export type LeaderboardRun = {
  schema_version: 1; board: string; entry_id: string; pair_key: string; members: [string, string];
  ticks: number; finished_at: string; finished_ms: number; chapter: ChapterKey; simulation_version: number;
  /** The room's final checkpoint. Its proof nests every pair of the finishing branch, so it alone replays the run. */
  checkpoint: CheckpointV2;
  /** What each member wore when it finished, in `members` order, when the room handed it over while looks are on (run-looks.ts). */
  looks?: PairLooks;
};

const ENTRY_DOMAIN = "after-you leaderboard entry v1\n";
const PAIR_DOMAIN = "after-you leaderboard pair v1\n";

/**
 * A run's public id: a hash of its room and finishing branch. Both members can
 * work it out from their own room; nobody else learns the room from it.
 */
export async function entryId(roomId: string, branch: number): Promise<string> {
  const hex = await digest(`${ENTRY_DOMAIN}${roomId}\n${branch}`);
  return hex.slice(0, 32);
}

/** The pair's private key on a board: the same for both orders of the two players. Never published. */
export async function pairKey(a: string, b: string): Promise<string> {
  return digest(PAIR_DOMAIN + [a, b].sort().join("\n"));
}

/** Ticks of every turn on the finishing branch, or null when the chain is not a whole, unassisted run. */
export function runTicks(checkpoint: CheckpointV2, stages: number): { ticks: number; simulation_version: number } | null {
  let current: CheckpointV2 = checkpoint, ticks = 0, simulation = -1;
  if (current.stage_index !== stages) return null;
  for (let index = stages; index > 0; index--) {
    const proof = nestedProof(current);
    if (!proof || current.stage_index !== index) return null;
    for (const turn of [proof.a, proof.b]) {
      if (turn.catch_assistance !== false || !Number.isSafeInteger(turn.duration_ticks) || turn.duration_ticks < 1) return null;
      if (simulation === -1) simulation = turn.simulation_version;
      if (turn.simulation_version !== simulation) return null;
      ticks += turn.duration_ticks;
    }
    current = proof.previous;
  }
  return current.stage_index === 0 && Number.isSafeInteger(ticks) ? { ticks, simulation_version: simulation } : null;
}

/**
 * The run a turn reply finished, or null. Only a standalone room's final turn
 * with two players and no assisted turn finishes a run that can rank. The
 * receipt must still be the room's latest change: a retry answered with a room
 * that has moved on since says nothing about when this run finished.
 */
export async function finishedRun(mutation: MutationV2 & { board_looks?: PairLooks }, context: unknown): Promise<LeaderboardRun | null> {
  const { receipt, room } = mutation;
  if (context !== undefined || receipt.operation !== "turns" || room.active_role !== "complete") return null;
  if (receipt.accepted_revision !== room.revision || receipt.branch !== room.branch) return null;
  const host = room.host_id, guest = room.guest_id;
  if (!guest || guest === host) return null;
  let stages: number;
  try { stages = chapter(room).stages.length; } catch { return null; }
  const timed = runTicks(room.checkpoint, stages);
  const finished_ms = Date.parse(room.updated_at);
  if (!timed || !Number.isFinite(finished_ms)) return null;
  const looks = boardLooksOf(mutation.board_looks);
  return {
    schema_version: 1, board: boardKey(room), entry_id: await entryId(room.room_id, room.branch), pair_key: await pairKey(host, guest),
    members: [host, guest], ticks: timed.ticks, finished_at: room.updated_at, finished_ms,
    chapter: { level_id: room.level_id, level_version: room.level_version, definition_hash: room.definition_hash },
    simulation_version: timed.simulation_version, checkpoint: room.checkpoint, ...(looks ? { looks } : {})
  };
}
