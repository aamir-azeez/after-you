import { fail, ok, type Outcome } from "../protocol";
import { addToPurse, purse, setPurse } from "./currency";
import { applyLedger, dropLedgerLine, fullJourneyUntil, inLedger } from "./wallet";

/**
 * Duel energy (ENERGY-PLAN.md, the owner's answers of 2026-11-09), in the player's own Player Durable Object.
 *
 * - Up to ENERGY_RULES.max (ENERGY_RULES.full_journey_max while the player has Full Journey), one back every ENERGY_RULES.step_ms.
 * - Stored as one time in the purse (currency.ts kind "energy", its balance column): `full_at`, when the meter is full.
 *   Energy now = max - ceil((full_at - now) / step), never below 0 or above max. Nothing ticks: no alarm, only arithmetic.
 * - Starting or joining a duel spends 1, once per duel: the ledger line `energy:<duel id>` (0 Pollen, kind "energy",
 *   pruned with turns after 35 days). Spending moves full_at to max(now, full_at) + step. A start or join the server
 *   refuses at that moment gives it back once: full_at moves back one step. Nothing later
 *   (a decline, expiry, stall or no answer) ever gives it back. Giving back removes the spend line, so a retry of the
 *   same refused start pays again only if it goes through.
 * - A refill (the spend route's kind "energy", fruit-ops.ts pricing in Fruits) sets full_at to now, only below the max,
 *   so the meter never goes above it.
 * Every function runs inside the caller's transaction (a Player method's own).
 */
export const ENERGY_RULES = Object.freeze({ max: 5, full_journey_max: 7, step_ms: 10 * 60_000, refill_fruits: 10 });
/** `base_max` and `full_journey_max`: both tops, so the Full Journey card can show the perk to a player without it. */
export type EnergyView = { schema_version: 1; energy: number; max: number; full_at: number; step_ms: number; now: number; refill_fruits: number; base_max: number; full_journey_max: number };
export const energyKey = (duelId: string) => `energy:${duelId}`;
const DUEL_ID = /^[A-Za-z0-9_-]{1,64}$/;

/** The meter's top for this player now. */
export function energyMax(storage: DurableObjectStorage, now: number): number { return fullJourneyUntil(storage) > now ? ENERGY_RULES.full_journey_max : ENERGY_RULES.max; }
/** Energy now, from `full_at`. */
export function energyAt(fullAt: number, max: number, now: number): number {
  return Math.max(0, Math.min(max, max - Math.ceil(Math.max(0, fullAt - now) / ENERGY_RULES.step_ms)));
}
export function energyView(storage: DurableObjectStorage, now: number): EnergyView {
  const max = energyMax(storage, now), fullAt = Math.max(now, purse(storage, "energy").balance);
  return { schema_version: 1, energy: energyAt(fullAt, max, now), max, full_at: fullAt, step_ms: ENERGY_RULES.step_ms, now, refill_fruits: ENERGY_RULES.refill_fruits,
    base_max: ENERGY_RULES.max, full_journey_max: ENERGY_RULES.full_journey_max };
}

/** `fresh`: this call spent (a repeat for the same duel spends nothing and answers false). */
export type EnergySpend = { fresh: boolean; view: EnergyView };
/** Spends 1 for `duelId`, once: a repeat answers the meter as it is. 409 energy_empty when none is left. */
export function spendEnergy(storage: DurableObjectStorage, duelId: string, now: number): Outcome<EnergySpend> {
  if (!DUEL_ID.test(duelId)) return fail(400, "invalid_duel_request");
  if (inLedger(storage, energyKey(duelId))) return ok({ fresh: false, view: energyView(storage, now) });
  const view = energyView(storage, now);
  if (view.energy < 1) return fail(409, "energy_empty");
  // full_at is never before now (energyView), so a full meter starts counting from the spend.
  setPurse(storage, "energy", { balance: view.full_at + ENERGY_RULES.step_ms, earned: purse(storage, "energy").earned });
  applyLedger(storage, [{ key: energyKey(duelId), kind: "energy", amount: 0, detail: { duel_id: duelId } }], now);
  return ok({ fresh: true, view: energyView(storage, now) });
}

/** Gives back what `duelId` spent, once, when its start or join was refused at once: its spend line goes. Nothing to give back changes nothing. */
export function refundEnergy(storage: DurableObjectStorage, duelId: string, now: number): EnergyView {
  if (!DUEL_ID.test(duelId) || !dropLedgerLine(storage, energyKey(duelId))) return energyView(storage, now);
  const row = purse(storage, "energy");
  setPurse(storage, "energy", { balance: Math.max(now, row.balance - ENERGY_RULES.step_ms), earned: row.earned });
  return energyView(storage, now);
}

/** Fills the meter for ENERGY_RULES.refill_fruits Fruits (the spend route's kind "energy"), only below the max. `expected`: the price the phone showed. */
export function refillEnergy(storage: DurableObjectStorage, expected: number, now: number): Outcome<{ fruit_balance: number; energy: EnergyView }> {
  const fruits = purse(storage, "fruits").balance, view = energyView(storage, now);
  if (view.energy >= view.max) return fail(409, "energy_full");
  if (fruits < 0) return fail(403, "fruits_blocked");
  if (expected !== ENERGY_RULES.refill_fruits) return fail(409, "pollen_price_changed");
  if (fruits < ENERGY_RULES.refill_fruits) return fail(402, "fruits_short");
  const balance = addToPurse(storage, "fruits", -ENERGY_RULES.refill_fruits);
  setPurse(storage, "energy", { balance: now, earned: purse(storage, "energy").earned + 1 });
  return ok({ fruit_balance: balance, energy: energyView(storage, now) });
}
