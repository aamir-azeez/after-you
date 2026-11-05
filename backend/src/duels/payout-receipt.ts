import type { BonusReason, DuelRoomPay } from "../pollen/duel-pay";
import { isFinal, type Duel } from "./model";
import { seatOf, type HeldState } from "./public";

/**
 * A player's pay from an ended duel as their first paying read showed it, kept on the duel's own board row
 * (store.ts receipt), so every later read answers from the row it already reads, with no wallet request.
 *
 * The wallet's once-only ledger lines (pollen/duel-pay.ts) stay the only thing that pays; a receipt only spares asking
 * them again. So it is kept only once nothing it shows can change (duels/routes.ts duelDetail): the duel is final, every
 * wallet answer was a final one, and the player's side has no room or its run finished (a room whose run never finished
 * may still take duel turns that hold or pay). A lost or unknown receipt costs one more ask of the same lines, never a
 * second payment, which is also how older code that ignores it stays safe.
 *
 * Kept by seat (public.ts seatOf: side * 2 + member index), never by player id, so the row names
 * nobody new and an erasure's search for the id is unchanged; an erased player's receipt goes with them (store.ts).
 * Never in a view or a listing: views and listings pick their own fields.
 */
export const RECEIPT_VERSION = 1;
export type ShownBonus = { amount: number; counted: boolean; reason?: BonusReason };
/** A public duel's held extra as the duel page shows it (public-routes.ts publicDetail). */
export type ShownHeld = { amount: number; state: "running" | "paid" | "forfeit"; reason?: HeldState["reason"] };
/** The pay part of a duel read (duels/routes.ts duelDetail), as the phone gets it. */
export type PayoutShown = { pay?: DuelRoomPay; win_bonus?: ShownBonus; ghost_bonus?: ShownBonus; held?: ShownHeld };
export type PayoutReceipt = { v: typeof RECEIPT_VERSION; shown: PayoutShown };

/**
 * Whether a wallet answer is one it will give again: paid (its once-only line answers the same), or refused for good
 * (410, past the claim window). Absent (not asked) counts too. A 404 (no active identity) or a failure is not.
 */
export function lastingAnswer(outcome?: { ok: boolean; status?: number }): boolean {
  return !outcome || outcome.ok || outcome.status === 410;
}

/** What `player`'s kept receipt shows, or null when none is kept in a shape this code knows. */
export function receiptOf(duel: Duel, player: string): PayoutShown | null {
  const seat = seatOf(duel, player);
  const kept = seat < 0 ? undefined : duel.receipts?.[String(seat)];
  return kept?.v === RECEIPT_VERSION && kept.shown !== null && typeof kept.shown === "object" ? kept.shown : null;
}

/** Keeps `shown` for `player` on a final duel that seats them and holds no receipt for that seat yet. Returns whether it changed. */
export function keepReceipt(duel: Duel, player: string, shown: PayoutShown): boolean {
  const seat = seatOf(duel, player);
  if (!isFinal(duel) || seat < 0 || duel.receipts?.[String(seat)] !== undefined) return false;
  duel.receipts = { ...duel.receipts, [String(seat)]: { v: RECEIPT_VERSION, shown } };
  return true;
}

/** Account erasure: `player`'s receipt goes, before their id leaves the duel. Returns whether it changed. */
export function dropReceipt(duel: Duel, player: string): boolean {
  const seat = seatOf(duel, player);
  if (seat < 0 || duel.receipts?.[String(seat)] === undefined) return false;
  const { [String(seat)]: _gone, ...rest } = duel.receipts;
  if (Object.keys(rest).length) duel.receipts = rest; else delete duel.receipts;
  return true;
}
