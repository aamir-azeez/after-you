import { fail, ok, type Outcome } from "../protocol";
import type { ChapterKey } from "../v2/chapter-types";
import { CHALLENGE_TTL_MS, ROOM_CLAIM_TAKEOVER_MS, STALL_MS } from "./rules";

/**
 * The duel state machine. Pure: every function takes the duel and the clock,
 * changes the duel in place and answers; nothing here reads storage or env.
 * The store (store.ts) runs each call inside one synchronous transaction and
 * saves the duel when it changed, so repeats and calls in any order are safe:
 * accepting twice answers the running duel, a turn older than the one held is
 * ignored, a second finish never moves a time, and a verdict counts only for
 * the run it names.
 *
 * Two kinds, one shape:
 * - friend: pair 0 challenged pair 1. Each pair plays the chapter in its own
 *   fresh room (`room`, claimed by whichever member opens it first). A run
 *   counts once the replay check passed it (`check`), so a win arrives with
 *   the result.
 * - ghost: pair 0 races a recorded time (`ghost`); side 1 is null. Decided the
 *   moment the pair finishes, with no check: a ghost race earns nothing extra.
 *
 * Time rules are read lazily (settle): a challenge fades after
 * CHALLENGE_TTL_MS, and a running duel nobody has played for STALL_MS ends
 * unfinished, with no win and no loss, even when one pair finished.
 *
 * Extension points, unused today: `modifiers` is where a card layer's
 * effects would sit, read only by score(); `result` names the winner and the
 * reason, which is all a rating needs. Boards always take the raw time.
 */
export type DuelKind = "friend" | "ghost";
export type DuelStatus = "challenged" | "running" | "decided" | "declined" | "withdrawn" | "expired" | "pair_gone" | "unfinished";
export const FINAL_STATUSES: readonly DuelStatus[] = Object.freeze(["decided", "declined", "withdrawn", "expired", "pair_gone", "unfinished"]);
/** A finished friend run's replay check: waiting, passed, failed, or error (the job could not judge it). */
export type RunCheck = "none" | "waiting" | "passed" | "failed" | "error";
export type SideRoom = { room_id: string; invite_code: string; host: string | null; claimed_ms: number };
export type Side = {
  /** Null once that player's account is erased. */
  members: [string | null, string | null];
  /** leaderboards/run.ts pairKey of the two members: the same pair on the boards. */
  pair_key: string;
  room: SideRoom | null;
  /** The room revision the progress below came from; older notes are ignored. */
  revision: number; steps: number; ticks: number; assisted: boolean;
  /** Whose turn it is in the side's room, or null. */
  turn: string | null;
  finished_ms: number | null;
  /** leaderboards/run.ts entryId of the finished run: the replay job's id for it. */
  entry_id: string | null;
  check: RunCheck; left: boolean;
  last_ms: number | null;
};
export type Ghost = { source: "board" | "developer"; entry_id: string | null; rank: number | null; ticks: number; names: string[] | null };
export type ResultReason = "faster" | "draw" | "left" | "failed_check" | "unchecked" | "stalled" | "erased";
/** `winner`: the side index that won (1 is the ghost in a ghost race), or null for a draw or no result. */
export type DuelResult = { winner: 0 | 1 | null; reason: ResultReason; decided_ms: number; margin_ticks: number | null };
/** A card layer's effect on the score, later. Always empty today. */
export type Modifier = { kind: string };
export type Duel = {
  schema_version: 1; duel_id: string; kind: DuelKind; board: string; chapter: ChapterKey;
  /** Turns in a whole run: two per stage. */
  steps: number;
  status: DuelStatus; created_ms: number; accepted_ms: number | null; updated_ms: number;
  /** The player who sent the challenge or started the race. */
  starter: string | null;
  sides: [Side, Side | null];
  ghost: Ghost | null;
  /** Friendships checked across the two pairs ("a|b", ids sorted): only those players see each other's ids. */
  known: string[];
  /** Whether all four accounts met the board's rule when the challenge was accepted: a win pays its bonus only then. */
  eligible: boolean | null;
  result: DuelResult | null;
  modifiers: Modifier[];
};
export type ProgressNote = { room_id: string; revision: number; steps: number; ticks: number; assisted: boolean; turn: string | null; complete: boolean; at_ms: number; entry_id: string | null };

export function blankSide(members: [string, string], pairKey: string): Side {
  return { members, pair_key: pairKey, room: null, revision: 0, steps: 0, ticks: 0, assisted: false, turn: null, finished_ms: null, entry_id: null, check: "none", left: false, last_ms: null };
}

export type FriendDuelInput = { duel_id: string; board: string; chapter: ChapterKey; steps: number; starter: string; a: Side; b: Side; known: string[] };
export function newFriendDuel(input: FriendDuelInput, now: number): Duel {
  return { schema_version: 1, duel_id: input.duel_id, kind: "friend", board: input.board, chapter: input.chapter, steps: input.steps, status: "challenged",
    created_ms: now, accepted_ms: null, updated_ms: now, starter: input.starter, sides: [input.a, input.b], ghost: null, known: [...new Set(input.known)].sort(),
    eligible: null, result: null, modifiers: [] };
}

export type GhostRaceInput = { duel_id: string; board: string; chapter: ChapterKey; steps: number; starter: string; a: Side; ghost: Ghost };
export function newGhostRace(input: GhostRaceInput, now: number): Duel {
  return { schema_version: 1, duel_id: input.duel_id, kind: "ghost", board: input.board, chapter: input.chapter, steps: input.steps, status: "running",
    created_ms: now, accepted_ms: now, updated_ms: now, starter: input.starter, sides: [input.a, null], ghost: input.ghost, known: [], eligible: false, result: null, modifiers: [] };
}

export const knownKey = (a: string, b: string): string => [a, b].sort().join("|");
export const isFinal = (duel: Duel): boolean => FINAL_STATUSES.includes(duel.status);
/** Waiting or running: what counts against a pair's limits and shows on its lobby. */
export const isOpen = (duel: Duel): boolean => duel.status === "challenged" || duel.status === "running";

/** The side `player` is on, or -1. */
export function sideOf(duel: Duel, player: string): 0 | 1 | -1 {
  if (duel.sides[0].members.includes(player)) return 0;
  return duel.sides[1]?.members.includes(player) ? 1 : -1;
}

/** Every player still named in the duel. */
export function players(duel: Duel): string[] {
  return [...duel.sides[0].members, ...(duel.sides[1]?.members ?? [])].filter((id): id is string => id !== null);
}

/** A side's score: its raw ticks. The one place a card layer's modifiers would apply; boards never read it. */
export function score(duel: Duel, index: 0 | 1): number {
  if (index === 1 && duel.kind === "ghost") return duel.ghost!.ticks;
  return duel.sides[index]!.ticks;
}

/** Applies the time rules. Returns whether the duel changed. */
export function settle(duel: Duel, now: number): boolean {
  if (duel.status === "challenged") {
    if (now - duel.created_ms < CHALLENGE_TTL_MS) return false;
    duel.status = "expired";
    duel.updated_ms = now;
    return true;
  }
  if (duel.status !== "running") return false;
  if (decide(duel, now)) return true;
  if (now - lastActivity(duel) < STALL_MS) return false;
  return conclude(duel, null, "stalled", now, null);
}

function lastActivity(duel: Duel): number {
  const sides = duel.sides.filter((side): side is Side => side !== null);
  return Math.max(duel.accepted_ms ?? duel.created_ms, ...sides.map(side => side.last_ms ?? 0));
}

function conclude(duel: Duel, winner: 0 | 1 | null, reason: ResultReason, now: number, margin: number | null): boolean {
  duel.status = winner !== null || reason === "draw" ? "decided" : "unfinished";
  duel.result = { winner, reason, decided_ms: now, margin_ticks: margin };
  for (const side of duel.sides) if (side) side.turn = null;
  duel.updated_ms = now;
  return true;
}

type Settled = "passed" | "failed" | "error" | "left" | "open";
function sideSettled(side: Side): Settled {
  if (side.finished_ms === null) return side.left ? "left" : "open";
  return side.check === "passed" || side.check === "failed" || side.check === "error" ? side.check : "open";
}

/** Decides a running duel whose outcome is known. Returns whether it changed. */
export function decide(duel: Duel, now: number): boolean {
  if (duel.status !== "running") return false;
  if (duel.kind === "ghost") {
    const side = duel.sides[0];
    if (side.left) return conclude(duel, null, "left", now, null);
    if (side.finished_ms === null) return false;
    return compare(duel, now);
  }
  const states = [sideSettled(duel.sides[0]), sideSettled(duel.sides[1]!)];
  if (states.includes("open")) return false;
  if (states[0] === "passed" && states[1] === "passed") return compare(duel, now);
  if (states.includes("error")) return conclude(duel, null, "unchecked", now, null);
  const passed = states.indexOf("passed");
  if (passed >= 0) return conclude(duel, passed as 0 | 1, states[1 - passed] === "left" ? "left" : "failed_check", now, null);
  return conclude(duel, null, states.includes("failed") ? "failed_check" : "left", now, null);
}

function compare(duel: Duel, now: number): boolean {
  const a = score(duel, 0), b = score(duel, 1);
  if (a === b) return conclude(duel, null, "draw", now, 0);
  return conclude(duel, a < b ? 0 : 1, "faster", now, Math.abs(a - b));
}

/**
 * Pair 1 accepts. `intact`: both its members still have each other as their
 * party; a pair that dissolved closes the challenge. `eligible`: the four
 * accounts' board rule, for the win bonus.
 */
export function accept(duel: Duel, player: string, now: number, intact: boolean, eligible: boolean): Outcome<Duel> {
  if (duel.kind !== "friend") return fail(409, "not_a_challenge");
  if (sideOf(duel, player) !== 1) return fail(403, "duel_not_yours");
  settle(duel, now);
  if (duel.status === "running" || duel.status === "decided" || duel.status === "unfinished") return ok(duel);
  if (duel.status !== "challenged") return fail(409, "challenge_" + duel.status);
  if (!intact) {
    duel.status = "pair_gone";
    duel.updated_ms = now;
    return fail(409, "challenge_pair_gone");
  }
  duel.status = "running";
  duel.accepted_ms = now;
  duel.eligible = eligible;
  duel.updated_ms = now;
  return ok(duel);
}

/** "Not now" from pair 1 declines; pair 0 takes its challenge back. Repeats answer the same. */
export function decline(duel: Duel, player: string, now: number): Outcome<Duel> {
  const side = sideOf(duel, player);
  if (side < 0) return fail(403, "duel_not_yours");
  settle(duel, now);
  const closed: DuelStatus = side === 1 ? "declined" : "withdrawn";
  if (duel.status === closed || duel.status === "expired") return ok(duel);
  if (duel.status !== "challenged") return fail(409, "challenge_" + duel.status);
  duel.status = closed;
  duel.updated_ms = now;
  return ok(duel);
}

/**
 * The first member of a side to open the duel claims its room with the room
 * they are about to create; everyone after gets that room, to join. A claim
 * whose room never appeared (`roomAbsent`, checked by the caller) passes to
 * the partner after ROOM_CLAIM_TAKEOVER_MS. Answers the side's room.
 */
export function claimRoom(duel: Duel, player: string, proposal: { room_id: string; invite_code: string }, now: number, roomAbsent = false): Outcome<SideRoom> {
  const index = sideOf(duel, player);
  if (index < 0) return fail(403, "duel_not_yours");
  settle(duel, now);
  if (duel.status !== "running") return fail(409, "duel_not_running");
  const side = duel.sides[index]!;
  if (side.left) return fail(409, "duel_left");
  const stale = side.room !== null && side.room.host !== player && side.revision === 0 && roomAbsent && now - side.room.claimed_ms >= ROOM_CLAIM_TAKEOVER_MS;
  if (side.room === null || stale) {
    side.room = { room_id: proposal.room_id, invite_code: proposal.invite_code, host: player, claimed_ms: now };
    duel.updated_ms = now;
  }
  return ok(side.room);
}

/**
 * A turn accepted in a side's room. Notes carry the room's whole state at
 * that revision, so a lost or repeated note is healed by the next one. A
 * side's first finish is final: a later redo in its room changes nothing here.
 */
export function progress(duel: Duel, note: ProgressNote, now: number): Outcome<{ finished: boolean }> {
  settle(duel, now);
  const index = duel.sides.findIndex(side => side?.room?.room_id === note.room_id);
  if (index < 0) return fail(404, "duel_room_unknown");
  const side = duel.sides[index]!;
  if (duel.status !== "running" || side.finished_ms !== null || note.revision <= side.revision) return ok({ finished: false });
  Object.assign(side, { revision: note.revision, steps: Math.min(note.steps, duel.steps), ticks: note.ticks, assisted: note.assisted, turn: note.complete ? null : note.turn, last_ms: note.at_ms });
  if (note.complete) {
    side.finished_ms = note.at_ms;
    side.entry_id = note.entry_id;
    side.check = duel.kind === "friend" ? "waiting" : "none";
  }
  duel.updated_ms = now;
  decide(duel, now);
  return ok({ finished: note.complete });
}

/** The replay check's answer on a waiting friend run. Returns whether it counted. */
export function verdict(duel: Duel, entryId: string, check: "passed" | "failed" | "error", now: number): boolean {
  if (duel.kind !== "friend" || duel.status !== "running") return false;
  const side = duel.sides.find(item => item?.entry_id === entryId && item.check === "waiting");
  if (!side) return false;
  side.check = check;
  duel.updated_ms = now;
  decide(duel, now);
  return true;
}

/**
 * A member's pair leaves: before an answer it is a decline (or taking a
 * challenge back); while running it hands the other pair the win once its run
 * passes. Turned off once the pair has finished.
 */
export function leave(duel: Duel, player: string, now: number): Outcome<Duel> {
  const index = sideOf(duel, player);
  if (index < 0) return fail(403, "duel_not_yours");
  settle(duel, now);
  if (duel.status === "challenged") return decline(duel, player, now);
  if (isFinal(duel)) return ok(duel);
  const side = duel.sides[index]!;
  if (side.finished_ms !== null) return fail(409, "duel_finished_for_you");
  if (!side.left) {
    side.left = true;
    side.turn = null;
    duel.updated_ms = now;
    decide(duel, now);
  }
  return ok(duel);
}

/** Account erasure: the player's id goes everywhere; an open duel ends unfinished. Returns whether it changed. */
export function forgetPlayer(duel: Duel, player: string, now: number): boolean {
  if (sideOf(duel, player) < 0 && duel.starter !== player) return false;
  for (const side of duel.sides) {
    if (!side) continue;
    side.members = side.members.map(id => id === player ? null : id) as [string | null, string | null];
    if (side.room?.host === player) side.room.host = null;
    if (side.turn === player) side.turn = null;
  }
  if (duel.starter === player) duel.starter = null;
  duel.known = duel.known.filter(key => !key.split("|").includes(player));
  if (duel.status === "challenged") { duel.status = "withdrawn"; duel.updated_ms = now; }
  else if (duel.status === "running") conclude(duel, null, "erased", now, null);
  duel.updated_ms = now;
  return true;
}

/** What one player's phone sees of a duel. Ids on the other pair show only where a friendship was checked. */
export type SideView = {
  members: (string | null)[]; you: boolean; steps: number; ticks: number; assisted: boolean;
  /** Index into `members` of whose turn it is, or null. */
  turn: number | null;
  finished: boolean; left: boolean; check: RunCheck;
  /** Own side only: the room to open or join, and whether this player claimed it. */
  room_id?: string | null; invite_code?: string | null; hosting?: boolean;
};
export type DuelView = {
  schema_version: 1; duel_id: string; kind: DuelKind; board: string; status: DuelStatus; steps: number;
  created_ms: number; accepted_ms: number | null; updated_ms: number;
  mine: 0 | 1; sides: [SideView, SideView | null]; ghost: Ghost | null;
  result: { outcome: "won" | "lost" | "draw" | "none"; reason: ResultReason; margin_ticks: number | null; decided_ms: number } | null;
  eligible: boolean | null;
};

export function viewFor(duel: Duel, viewer: string): DuelView | null {
  const mine = sideOf(duel, viewer);
  if (mine < 0) return null;
  const known = new Set(duel.known);
  const sideView = (side: Side, index: 0 | 1): SideView => {
    const own = index === mine;
    const members = side.members.map(id => id !== null && (own || known.has(knownKey(viewer, id))) ? id : null);
    const turn = side.turn === null ? -1 : side.members.indexOf(side.turn);
    return { members, you: own, steps: side.steps, ticks: side.ticks, assisted: side.assisted, turn: turn < 0 ? null : turn, finished: side.finished_ms !== null, left: side.left, check: side.check,
      ...(own ? { room_id: side.room?.room_id ?? null, invite_code: side.room?.invite_code ?? null, hosting: side.room?.host === viewer } : {}) };
  };
  const result = duel.result;
  const outcome = !result ? null : result.winner === null ? (result.reason === "draw" ? "draw" : "none") : result.winner === mine ? "won" : "lost";
  return {
    schema_version: 1, duel_id: duel.duel_id, kind: duel.kind, board: duel.board, status: duel.status, steps: duel.steps,
    created_ms: duel.created_ms, accepted_ms: duel.accepted_ms, updated_ms: duel.updated_ms, mine,
    sides: [sideView(duel.sides[0], 0), duel.sides[1] ? sideView(duel.sides[1], 1) : null], ghost: duel.ghost,
    result: result && outcome ? { outcome, reason: result.reason, margin_ticks: result.margin_ticks, decided_ms: result.decided_ms } : null,
    eligible: duel.eligible
  };
}
