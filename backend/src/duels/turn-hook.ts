import { flags, type ServerVars } from "../flags";
import { errorCode, logWarning } from "../log";
import { entryId } from "../leaderboards/run";
import { chapter } from "../v2/chapters";
import type { RoomSnapshotV2 } from "../v2/room";
import type { Duel, ProgressNote } from "./model";
import type { DuelLink } from "./room-link";
import type { FinishProof } from "./store";
import type { EncodedProof } from "../leaderboards/proofs";
import type { CheckpointV2 } from "../v2/protocol";
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
export type DuelNote = { note: ProgressNote; proof?: FinishProof };
/** `encode`: the room's own encoder (v2/room.ts turnHooks), so the proof goes encoded; without it, raw. */
export async function roomNote(room: RoomSnapshotV2, link: DuelLink, looks?: PairLooks, encode?: (checkpoint: CheckpointV2) => Promise<EncodedProof>): Promise<DuelNote | null> {
  let adapter;
  try { adapter = chapter(room); } catch { return null; }
  const progress = runProgress(room.checkpoint, adapter.stages.length, room.active_role === "b" ? room.recording_a : null);
  const at = Date.parse(room.updated_at);
  if (!progress || !Number.isFinite(at)) return null;
  const complete = progress.complete && room.active_role === "complete";
  const note: ProgressNote = { room_id: room.room_id, revision: room.revision, steps: progress.steps, ticks: progress.ticks, splits: progress.splits,
    turn: complete ? null : nextPlayer(room, link), complete, at_ms: at, entry_id: complete ? await entryId(room.room_id, room.branch) : null,
    ...(looks ? { looks: memberLooks(room, looks) } : {}) };
  // A finish that may wait for the check brings its checkpoint: every friend run, and a ghost race run faster than the
  // developers' ghost. The board decides (model.ts awaitsCheck, which reads DUEL_RUN_CHECKS in the board's own CONFIG),
  // and with checks off it neither encodes nor keeps it; this only spares the rest the payload.
  const checked = link.kind === "friend" || progress.ticks < (developerGhost(link.board) ?? 0);
  const proof = complete && checked ? { ...(encode ? { proof: await encode(room.checkpoint) } : { checkpoint: room.checkpoint }), simulation_version: room.simulation_version ?? adapter.simulation_version } : undefined;
  return { note, ...(proof ? { proof } : {}) };
}

/**
 * Whose move the room waits for. The room names the guest's slot by its guest, and a host may play the
 * first turn before the partner joins, so a friend duel's or ghost race's room with no guest yet waits
 * for the pair's other member, whom the link names. A public room's other seat may still be open or
 * not yet entered (public.ts enterSeat), so it stays as the room says, and views point at that seat
 * (public.ts publicWaitingSlot).
 */
function nextPlayer(room: RoomSnapshotV2, link: DuelLink): string | null {
  if (room.active_player_id !== null || room.guest_id !== null || link.public || link.members.length !== 2 || !link.members.includes(room.host_id)) return room.active_player_id;
  return link.members.find(id => id !== room.host_id) ?? null;
}

/**
 * After an accepted turn in a duel room (v2/routes.ts, beside the board post):
 * one request to the duel's board. Never throws and never changes the turn
 * reply; a lost note is healed by the next turn or the phone's sync. `actor`:
 * who took the turn, whom the duel's news leaves out (duels/news.ts). `looks`:
 * the room's two members' looks, host first, while looks are on (v2/room.ts
 * commit `duel_looks`); they ride in the same note. `covered`: the actor's partner, whom the route tells itself
 * (news.ts sendTurnHints), so the board leaves them out. Answers the duel as the board noted it, or null.
 */
export async function noteDuelTurn(env: Env, room: RoomSnapshotV2, link: DuelLink | null | undefined, actor?: string, looks?: PairLooks, covered?: string): Promise<{ duel_id: string; updated_ms: number } | null> {
  if (!link || !duelsOn(env)) return null;
  let made: DuelNote | null;
  try { made = await roomNote(room, link, looks); } catch (error) { logWarning("duel_note_failed", { code: errorCode(error) }); return null; }
  return sendDuelNote(env, room.room_id, link, made, actor, covered);
}
/** noteDuelTurn's request, for a note the room already made (v2/room.ts turnRequest), so the Worker never holds the room. */
export async function sendDuelNote(env: Env, roomId: string, link: DuelLink, made: DuelNote | null, actor?: string, covered?: string): Promise<{ duel_id: string; updated_ms: number } | null> {
  if (!duelsOn(env)) return null;
  try {
    const noted = made ? await env.LEADERBOARD_BOARDS.getByName(link.board).duelProgress(link.duel_id, made.note, made.proof, actor, covered) : null;
    // A public duel's finished run: the room learns who on the other pair may watch it, which it could not know when made.
    if (made?.note.complete && link.public && noted?.ok) {
      const duel = noted.value as unknown as Duel, others = duel.sides[1 - link.side]?.members.filter((id): id is string => id !== null) ?? [];
      if (others.length) await env.ROOMS_V2.getByName(roomId).duelTheirRunViewers(others);
    }
    return noted?.ok ? { duel_id: noted.value.duel_id, updated_ms: noted.value.updated_ms } : null;
  } catch (error) {
    logWarning("duel_note_failed", { code: errorCode(error) });
    return null;
  }
}

/** The room's looks by member id: the host's, and the guest's once someone joined. */
function memberLooks(room: RoomSnapshotV2, looks: PairLooks): Record<string, PairLooks[number]> {
  return { [room.host_id]: looks[0], ...(room.guest_id ? { [room.guest_id]: looks[1] } : {}) };
}
