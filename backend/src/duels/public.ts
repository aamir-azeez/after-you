import { fail, ok, type Outcome } from "../protocol";
import { shownName } from "../display-names";
import { servedLook } from "../leaderboards/run-looks";
import type { Look } from "../pollen/catalog";
import type { ChapterKey } from "../v2/chapter-types";
import { conclude, decide, isFinal, knownKey, lastActivity, wearLooks, type Duel, type SeatView, type Side } from "./model";
import { MAX_PUBLIC_DUEL_MS, PUBLIC_OPEN_MS, PUBLIC_STALL_MS } from "./rules";

/**
 * Public duels: a friend duel whose seats fill from a list, with players who may not know each other. Pure: like
 * model.ts, every function changes the duel in place and answers; the board's store runs each in one transaction.
 *
 * Seats are numbered 0 to 3: side 0 holds seats 0 and 1, side 1 seats 2 and 3, in `members` order. A seat is open
 * while its member is null and it is not `gone` (a player who entered the room and then left, or was erased, never
 * hands the seat on, since a room's guest can't be replaced mid-run). A seat whose player never entered the room
 * goes back on the list when they leave. Labels are the player's shown name, kept only when they chose to show it
 * ("Show my name", leaderboards/member.ts), checked again whenever they are served; null draws as "A player".
 *
 * Time rules, read lazily like every duel's (publicSettle): open spots stay listed PUBLIC_OPEN_MS, and a duel that
 * still has one then ends as nobody_joined; a duel nobody played for PUBLIC_STALL_MS, or older than
 * MAX_PUBLIC_DUEL_MS, ends as stalled.
 *
 * The held duel extra (pollen/duel-pay.ts creditDuelExtra) is paid at the end to every seat not in the result's
 * `forfeit`, and only when both sides were fully seated at some point (`full_once`).
 *
 * Ids never leave the server: views carry ids only for the viewer and players they already know (their party, a
 * friend checked at posting or joining), and the list row (rowFor) carries none.
 */
/**
 * `hidden`: strangers may not meet this seat's player now (their switch is off, or they were paused after reports:
 * leaderboards/member.ts publicOpenTo), so the duel stays off the list while they hold it. Per seat, so one player's
 * change never lists a duel another player in it keeps off. A seat taken again starts clear.
 */
export type PublicSeat = { label: string | null; entered?: true; gone?: true; hidden?: true };
export type PublicState = {
  posted_ms: number; open_until_ms: number;
  /** Four seats in seat order. */
  seats: PublicSeat[];
  /** Both sides were fully seated at some point: the held extra may pay. */
  full_once?: true;
  /** Seats that forfeited their held extra while the duel ran (a leave); the result adds a stall's. */
  forfeit?: number[];
};
export type JoinAs = "alone" | "party";
export type SpotAnswer = { seat: number } | { reason: "seat_taken" | "full" | "one_left" | "split" };

/** The seat a join would take (game/tests/fixtures/public_duels/spots.json; the phone mirrors it in services/public_duel_spots.gd). */
export function spotFor(open: readonly boolean[], as: JoinAs, wanted: number | null): SpotAnswer {
  const pairOpen = (side: number) => open[side * 2] && open[side * 2 + 1];
  if (as === "alone") {
    if (wanted !== null) return open[wanted] ? { seat: wanted } : { reason: "seat_taken" };
    const beside = open.findIndex((free, seat) => free && !open[seat ^ 1]);
    if (beside >= 0) return { seat: beside };
    const first = open.findIndex(free => free);
    return first >= 0 ? { seat: first } : { reason: "full" };
  }
  if (wanted !== null) return pairOpen(wanted >> 1) ? { seat: wanted & ~1 } : open[wanted] ? { reason: "split" } : { reason: "seat_taken" };
  for (const side of [0, 1]) if (pairOpen(side)) return { seat: side * 2 };
  const count = open.filter(Boolean).length;
  return { reason: count === 0 ? "full" : count === 1 ? "one_left" : "split" };
}

const sideOfSeat = (duel: Duel, seat: number): Side => duel.sides[seat >> 1]!;
/** The player in `seat`, or null (also on a ghost race, which has no second side). */
export function holder(duel: Duel, seat: number): string | null { return duel.sides[seat >> 1]?.members[seat & 1] ?? null; }
/** The seat `player` holds, or -1. */
export function seatOf(duel: Duel, player: string): number {
  for (let seat = 0; seat < 4; seat++) if (holder(duel, seat) === player) return seat;
  return -1;
}
/** Seats anyone may still take: empty, never given up after entering, on a side still playing. */
export function openSeats(duel: Duel): boolean[] {
  return [0, 1, 2, 3].map(seat => holder(duel, seat) === null && !duel.public!.seats[seat].gone && !sideOfSeat(duel, seat).left && sideOfSeat(duel, seat).finished_ms === null);
}
export function seated(duel: Duel): string[] {
  return [0, 1, 2, 3].map(seat => holder(duel, seat)).filter((id): id is string => id !== null);
}
/** Whether the duel is on the list now: running, inside its window, with a spot open and nobody in it hidden (switched off or paused). */
export function listed(duel: Duel, now: number): boolean {
  return !!duel.public && duel.status === "running" && now < duel.public.open_until_ms && !hiddenSeat(duel) && openSeats(duel).some(Boolean);
}
const hiddenSeat = (duel: Duel) => duel.public!.seats.some((seat, index) => seat.hidden && holder(duel, index) !== null && !seat.gone);

export type PublicPost = { duel_id: string; board: string; chapter: ChapterKey; steps: number; players: string[]; labels: (string | null)[]; looks?: (Look | undefined)[]; known: string[] };
/** A posted duel: the poster (and partner) on side 0, every other seat open. Running at once: there is no challenge step. */
export function newPublicDuel(post: PublicPost, now: number): Duel {
  const blank = (): Side => ({ members: [null, null], pair_key: "", room: null, revision: 0, steps: 0, ticks: 0, turn: null, finished_ms: null, entry_id: null, check: "none", left: false, last_ms: null });
  const duel: Duel = { schema_version: 1, duel_id: post.duel_id, kind: "friend", board: post.board, chapter: post.chapter, steps: post.steps, status: "running",
    created_ms: now, accepted_ms: now, updated_ms: now, starter: post.players[0], sides: [blank(), blank()], ghost: null, known: [...new Set(post.known)].sort(),
    eligible: true, result: null, modifiers: [], public: { posted_ms: now, open_until_ms: now + PUBLIC_OPEN_MS, seats: [0, 1, 2, 3].map(() => ({ label: null })) } };
  seatPlayers(duel, 0, post.players, post.labels, post.looks);
  return duel;
}

function seatPlayers(duel: Duel, first: number, players: readonly string[], labels: readonly (string | null)[], looks?: readonly (Look | undefined)[]): void {
  players.forEach((player, index) => {
    const seat = first + index, side = sideOfSeat(duel, seat);
    side.members[seat & 1] = player;
    duel.public!.seats[seat] = { label: labels[index] ?? null };
    if (looks) wearLooks(side, id => id === player ? looks[index] : undefined);
  });
  if (!openSeats(duel).some(Boolean)) duel.public!.full_once = true;
}

export type PublicClaim = { players: string[]; as: JoinAs; seat: number | null; labels: (string | null)[]; looks?: (Look | undefined)[];
  /** Players the joiners blocked or who blocked them: a duel holding one is never joined. */
  avoid: string[];
  /** Known pairs to add: the party joining together. */
  known: string[] };
/**
 * Takes the spot a join asks for, in the board's transaction after settle. A repeat by players already seated answers
 * their seat; a join that lost the race, came after the duel left the list, or meets a blocked player is spot_taken.
 */
export function claimSeats(duel: Duel, claim: PublicClaim, now: number): Outcome<{ seat: number }> {
  if (!duel.public) return fail(404, "duel_not_found");
  const held = claim.players.map(player => seatOf(duel, player));
  if (held.every(seat => seat >= 0)) return ok({ seat: Math.min(...held) });
  if (held.some(seat => seat >= 0) || !listed(duel, now) || seated(duel).some(id => claim.avoid.includes(id))) return fail(409, "spot_taken");
  const spot = spotFor(openSeats(duel), claim.as, claim.seat);
  if (!("seat" in spot)) return fail(409, "spot_taken");
  seatPlayers(duel, spot.seat, claim.players, claim.labels, claim.looks);
  duel.known = [...new Set([...duel.known, ...claim.known])].sort();
  duel.updated_ms = now;
  return ok({ seat: spot.seat });
}

/** A side's room met a player: the room's claim (its host) or a guest the room asks the board about. Marks the seat entered. */
export function enterSeat(duel: Duel, side: 0 | 1, player: string, now: number): Outcome<true> {
  const seat = seatOf(duel, player);
  if (!duel.public || seat < 0 || seat >> 1 !== side) return fail(403, "duel_pair_only");
  if (duel.status !== "running") return fail(409, "duel_not_running");
  if (!duel.public.seats[seat].entered) { duel.public.seats[seat].entered = true; duel.updated_ms = now; }
  return ok(true);
}

/** Takes `player`'s id out of the duel: their seat, look, room claim, turn, known pairs and starter. */
function dropPlayer(duel: Duel, seat: number, now: number): void {
  const side = sideOfSeat(duel, seat), player = side.members[seat & 1]!;
  if (side.looks) wearLooks(side, id => id === player ? {} : undefined);
  side.members[seat & 1] = null;
  if (side.turn === player) side.turn = null;
  if (side.room?.host === player) side.room.host = null;
  duel.known = duel.known.filter(key => !key.split("|").includes(player));
  if (duel.starter === player) duel.starter = null;
  duel.updated_ms = now;
}

/** Frees a seat whose player never entered the room (never the last player's: they withdraw it instead). */
function freeSeat(duel: Duel, seat: number, now: number): void {
  dropPlayer(duel, seat, now);
  duel.public!.seats[seat] = { label: null };
}

/** Ends the side of a seat whose player entered and is gone: the side has left, and the seat forfeits unless `blocked`. */
function endSide(duel: Duel, seat: number, now: number, blocked: boolean): void {
  const side = sideOfSeat(duel, seat), state = duel.public!;
  if (!side.left) { side.left = true; side.left_by = seat; side.turn = null; }
  state.seats[seat].gone = true;
  if (!blocked) state.forfeit = [...new Set([...(state.forfeit ?? []), seat])].sort();
  duel.updated_ms = now;
}

/**
 * Leave, by seat (PLAN 5). The last player in it withdraws the duel. A seat whose player never entered the room
 * goes back on the list. After entering, the player's side ends as left and they forfeit their held extra, unless
 * the leave is a block of their own partner (`blocked`), which costs neither of them.
 */
export function publicLeave(duel: Duel, player: string, now: number, blocked: boolean): Outcome<Duel> {
  if (isFinal(duel)) return ok(duel);
  const seat = seatOf(duel, player), side = sideOfSeat(duel, seat), state = duel.public!;
  if (side.finished_ms !== null) return fail(409, "duel_finished_for_you");
  // The last player in it withdraws it and keeps their seat, so the duel still reads as theirs.
  if (seated(duel).length === 1) { duel.status = "withdrawn"; duel.updated_ms = now; return ok(duel); }
  if (!state.seats[seat].entered) { freeSeat(duel, seat, now); return ok(duel); }
  if (side.left) return ok(duel);
  endSide(duel, seat, now, blocked);
  decide(duel, now);
  return ok(duel);
}

/**
 * Account erasure in a public duel (PLAN 12): the player's id goes and the duel carries on for everyone else. Running,
 * the last player in it withdraws it; a seat never entered goes back on the list; otherwise their side ends as if they
 * left, and their held extra is forfeit. Final, their seat forfeits. Answers true: model.ts forgetPlayer has nothing to add.
 */
export function publicForget(duel: Duel, player: string, now: number): boolean {
  const seat = seatOf(duel, player), state = duel.public!;
  if (seat < 0) return false;
  if (duel.status === "running") {
    if (seated(duel).length === 1) { duel.status = "withdrawn"; dropPlayer(duel, seat, now); state.seats[seat] = { label: null, gone: true }; return true; }
    if (!state.seats[seat].entered) { freeSeat(duel, seat, now); return true; }
    endSide(duel, seat, now, false);
    dropPlayer(duel, seat, now);
    state.seats[seat] = { label: null, gone: true };
    decide(duel, now);
    return true;
  }
  dropPlayer(duel, seat, now);
  state.seats[seat] = { label: null, gone: true };
  state.forfeit = [...new Set([...(state.forfeit ?? []), seat])].sort();
  if (duel.result) duel.result.forfeit = [...new Set([...(duel.result.forfeit ?? []), seat])].sort();
  return true;
}

/** The time rules of a public duel (model.ts settle). Returns whether it changed. */
export function publicSettle(duel: Duel, now: number): boolean {
  if (duel.status !== "running") return false;
  if (decide(duel, now)) return true;
  const state = duel.public!;
  if (now >= state.open_until_ms && openSeats(duel).some(Boolean)) return conclude(duel, null, "nobody_joined", now, null);
  if (now - lastActivity(duel) >= PUBLIC_STALL_MS || now - state.posted_ms >= MAX_PUBLIC_DUEL_MS) return conclude(duel, null, "stalled", now, null);
  return false;
}

/** On a stall: the seat whose turn it was on each side still playing, who stopped (PLAN 10). */
export function stallForfeits(duel: Duel): number[] {
  return duel.sides.flatMap((side, index) => side && !side.left && side.finished_ms === null && side.turn !== null ? [index * 2 + side.members.indexOf(side.turn)] : []);
}

/** What this seat's held extra came to: paid, or why not. */
export type HeldState = { paid: boolean; reason?: "left" | "stopped" | "nobody_joined" | "erased" | "withdrawn" };
export function heldState(duel: Duel, seat: number): HeldState {
  if (duel.status === "withdrawn") return { paid: false, reason: "withdrawn" };
  const state = duel.public!, result = duel.result;
  if (result?.forfeit?.includes(seat) || state.forfeit?.includes(seat)) {
    if (duel.sides.some(side => side?.left_by === seat)) return { paid: false, reason: "left" };
    return { paid: false, reason: result?.reason === "stalled" ? "stopped" : "erased" };
  }
  return state.full_once ? { paid: true } : { paid: false, reason: "nobody_joined" };
}

/** Whether `viewer` may see `id`: their own, or one they already know (their party, a friend). */
export function publicKnown(duel: Duel, viewer: string, id: string): boolean {
  return id === viewer || duel.known.includes(knownKey(viewer, id));
}

/** A label as it may be served: the stored name if it still passes every name rule. */
const servedLabel = (label: string | null): string | null => label === null ? null : shownName(label);

export function publicSeatsView(duel: Duel, index: 0 | 1, viewer: string): SeatView[] {
  return [0, 1].map(slot => {
    const seat = index * 2 + slot, id = holder(duel, seat);
    return { open: id === null && !duel.public!.seats[seat].gone, you: id === viewer, label: id === null ? null : servedLabel(duel.public!.seats[seat].label) };
  });
}
export function publicView(duel: Duel): { posted_ms: number; open_until_ms: number; seats_open: number } {
  const state = duel.public!;
  return { posted_ms: state.posted_ms, open_until_ms: state.open_until_ms, seats_open: openSeats(duel).filter(Boolean).length };
}

/**
 * A listed duel as the list keeps it on the server (duels/directory.ts): seat ids stay here, for the reader's block
 * filter, and never reach a phone (rowFor). Null once the duel is off the list.
 */
export type ListingSeat = { id: string | null; open: boolean; label: string | null; look?: Look };
export type Listing = { duel_id: string; board: string; posted_ms: number; open_until_ms: number; steps: number; seats_open: number; sides: { steps: number; seats: ListingSeat[] }[] };
export function listingOf(duel: Duel, now: number): Listing | null {
  if (!listed(duel, now)) return null;
  const state = duel.public!, open = openSeats(duel);
  return { duel_id: duel.duel_id, board: duel.board, posted_ms: state.posted_ms, open_until_ms: state.open_until_ms, steps: duel.steps, seats_open: open.filter(Boolean).length,
    sides: duel.sides.map((side, index) => ({ steps: side!.steps, seats: [0, 1].map(slot => {
      const seat = index * 2 + slot, id = side!.members[slot], look = side!.looks?.[slot];
      return { id, open: open[seat], label: id === null ? null : state.seats[seat].label, ...(id !== null && look && Object.keys(look).length ? { look } : {}) };
    }) })) };
}

/** A list row as one reader's phone gets it: no ids, `mine` when they are in it, `you` on their seat. */
export type ListRow = { duel_id: string; board: string; posted_ms: number; open_until_ms: number; steps: number; mine: boolean;
  sides: { steps: number; seats: { open: boolean; label: string | null; you?: true; look?: Look }[] }[] };
export function rowFor(listing: Listing, reader: string, looks: boolean): ListRow {
  const ids = listing.sides.flatMap(side => side.seats.map(seat => seat.id));
  return { duel_id: listing.duel_id, board: listing.board, posted_ms: listing.posted_ms, open_until_ms: listing.open_until_ms, steps: listing.steps, mine: ids.includes(reader),
    sides: listing.sides.map(side => ({ steps: side.steps, seats: side.seats.map(seat => ({ open: seat.open, label: servedLabel(seat.label),
      ...(seat.id !== null && seat.id === reader ? { you: true as const } : {}), ...(looks && seat.look ? { look: servedLook(seat.look) } : {}) })) })) };
}

/** Sets `player`'s label on every seat they hold (a changed name or name choice). Returns whether it changed. */
export function relabel(duel: Duel, player: string, label: string | null, now: number): boolean {
  const seat = duel.public ? seatOf(duel, player) : -1;
  if (seat < 0 || duel.public!.seats[seat].label === label) return false;
  duel.public!.seats[seat].label = label;
  duel.updated_ms = now;
  return true;
}

/**
 * Marks `player`'s seat hidden or clear (their switch, or a pause after reports): a duel with a hidden seat leaves the
 * list, and the claim (claimSeats, through listed) refuses it in the same transaction. Returns whether it changed.
 */
export function hide(duel: Duel, player: string, hidden: boolean, now: number): boolean {
  // A duel that is over never lists again: its row is left as it is (no write for a switch or a pause).
  const seat = duel.public && duel.status === "running" ? seatOf(duel, player) : -1;
  if (seat < 0 || !!duel.public!.seats[seat].hidden === hidden) return false;
  if (hidden) duel.public!.seats[seat].hidden = true; else delete duel.public!.seats[seat].hidden;
  duel.updated_ms = now;
  return true;
}
