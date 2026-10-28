import { flags, type ServerVars } from "../flags";
import { errorCode, logWarning } from "../log";
import { entryId } from "../leaderboards/run";
import { chapter } from "../v2/chapters";
import type { RoomSnapshotV2 } from "../v2/room";
import type { ProgressNote } from "./model";
import type { DuelLink } from "./room-link";
import type { FinishProof } from "./store";
import { runProgress } from "./ticks";

/** Duels run while DUELS and LEADERBOARDS are both on: duels live in the boards, and friend results need its replay check. */
export function duelsOn(env: ServerVars): boolean { return flags.duels(env) && flags.leaderboards(env); }

/**
 * The note a duel room's state gives its duel: absolute values at the room's
 * revision (model.ts progress keeps only newer ones), and on a finished run
 * its board entry id and, for a friend duel, its final checkpoint for the
 * replay job. Null when the room's chain cannot be read.
 */
export async function roomNote(room: RoomSnapshotV2, link: DuelLink): Promise<{ note: ProgressNote; proof?: FinishProof } | null> {
  let adapter;
  try { adapter = chapter(room); } catch { return null; }
  const progress = runProgress(room.checkpoint, adapter.stages.length, room.active_role === "b" ? room.recording_a : null);
  const at = Date.parse(room.updated_at);
  if (!progress || !Number.isFinite(at)) return null;
  const complete = progress.complete && room.active_role === "complete";
  const note: ProgressNote = { room_id: room.room_id, revision: room.revision, steps: progress.steps, ticks: progress.ticks, assisted: progress.assisted,
    turn: complete ? null : room.active_player_id, complete, at_ms: at, entry_id: complete ? await entryId(room.room_id, room.branch) : null };
  const proof = complete && link.kind === "friend" ? { checkpoint: room.checkpoint, simulation_version: room.simulation_version ?? adapter.simulation_version } : undefined;
  return { note, ...(proof ? { proof } : {}) };
}

/**
 * After an accepted turn in a duel room (v2/routes.ts, beside the board post):
 * one request to the duel's board. Never throws and never changes the turn
 * reply; a lost note is healed by the next turn or the phone's sync.
 */
export async function noteDuelTurn(env: Env, room: RoomSnapshotV2, link: DuelLink | null | undefined): Promise<void> {
  if (!link || !duelsOn(env)) return;
  try {
    const made = await roomNote(room, link);
    if (made) await env.LEADERBOARD_BOARDS.getByName(link.board).duelProgress(link.duel_id, made.note, made.proof);
  } catch (error) {
    logWarning("duel_note_failed", { code: errorCode(error) });
  }
}
