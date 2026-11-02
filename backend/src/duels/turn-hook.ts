import { flags, type ServerVars } from "../flags";
import { errorCode, logWarning } from "../log";
import { entryId } from "../leaderboards/run";
import { chapter } from "../v2/chapters";
import type { RoomSnapshotV2 } from "../v2/room";
import type { ProgressNote } from "./model";
import type { DuelLink } from "./room-link";
import type { FinishProof } from "./store";
import { runProgress } from "./ticks";
import { developerGhost } from "./developer-ghosts";
import type { PairLooks } from "../leaderboards/run-looks";

/** Duels run while DUELS and LEADERBOARDS are both on: duels live in the boards, which also run their replay check while DUEL_RUN_CHECKS is on. */
export function duelsOn(env: ServerVars): boolean { return flags.duels(env) && flags.leaderboards(env); }
/** Duel runs wait for the board's replay check (model.ts awaitsCheck) only while DUEL_RUN_CHECKS is on beside duels; off by default. */
export function duelRunChecksOn(env: ServerVars): boolean { return duelsOn(env) && flags.duelRunChecks(env); }

/**
 * The note a duel room's state gives its duel: absolute values at the room's
 * revision (model.ts progress keeps only newer ones), and on a finished run
 * its board entry id and, for a run that may need the replay check, its final
 * checkpoint for the replay job. Null when the room's chain cannot be read.
 */
export async function roomNote(room: RoomSnapshotV2, link: DuelLink, looks?: PairLooks): Promise<{ note: ProgressNote; proof?: FinishProof } | null> {
  let adapter;
  try { adapter = chapter(room); } catch { return null; }
  const progress = runProgress(room.checkpoint, adapter.stages.length, room.active_role === "b" ? room.recording_a : null);
  const at = Date.parse(room.updated_at);
  if (!progress || !Number.isFinite(at)) return null;
  const complete = progress.complete && room.active_role === "complete";
  const note: ProgressNote = { room_id: room.room_id, revision: room.revision, steps: progress.steps, ticks: progress.ticks,
    turn: complete ? null : room.active_player_id, complete, at_ms: at, entry_id: complete ? await entryId(room.room_id, room.branch) : null,
    ...(looks ? { looks: memberLooks(room, looks) } : {}) };
  // A finish that may wait for the check brings its checkpoint: every friend run, and a ghost race run faster than the
  // developers' ghost. The board decides (model.ts awaitsCheck, which reads DUEL_RUN_CHECKS in the board's own CONFIG),
  // and with checks off it neither encodes nor keeps it; this only spares the rest the payload.
  const checked = link.kind === "friend" || progress.ticks < (developerGhost(link.board) ?? 0);
  const proof = complete && checked ? { checkpoint: room.checkpoint, simulation_version: room.simulation_version ?? adapter.simulation_version } : undefined;
  return { note, ...(proof ? { proof } : {}) };
}

/**
 * After an accepted turn in a duel room (v2/routes.ts, beside the board post):
 * one request to the duel's board. Never throws and never changes the turn
 * reply; a lost note is healed by the next turn or the phone's sync. `actor`:
 * who took the turn, whom the duel's news leaves out (duels/news.ts). `looks`:
 * the room's two members' looks, host first, while looks are on (v2/room.ts
 * commit `duel_looks`); they ride in the same note.
 */
export async function noteDuelTurn(env: Env, room: RoomSnapshotV2, link: DuelLink | null | undefined, actor?: string, looks?: PairLooks): Promise<void> {
  if (!link || !duelsOn(env)) return;
  try {
    const made = await roomNote(room, link, looks);
    if (made) await env.LEADERBOARD_BOARDS.getByName(link.board).duelProgress(link.duel_id, made.note, made.proof, actor);
  } catch (error) {
    logWarning("duel_note_failed", { code: errorCode(error) });
  }
}

/** The room's looks by member id: the host's, and the guest's once someone joined. */
function memberLooks(room: RoomSnapshotV2, looks: PairLooks): Record<string, PairLooks[number]> {
  return { [room.host_id]: looks[0], ...(room.guest_id ? { [room.guest_id]: looks[1] } : {}) };
}
