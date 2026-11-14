import { ApiError } from "../protocol";
import { energyOn } from "../pollen/features";
import { FLAG_VARS, gated, type Reach } from "../flags";
import type { EnergyView } from "../pollen/energy";

/**
 * Duel energy on a start or a join (pollen/energy.ts; ENERGY-PLAN.md, the owner's answers of 2026-11-09): every player who
 * starts or joins pays 1 of their own, keyed by the duel id so a retried request never pays twice. Each payer's Player is
 * asked once (one Player request each: the starter's and the partner's), only after every check of the route has passed,
 * just before the board call that makes or joins the duel. When that board call refuses or fails, each spend this request
 * made is given back before the reply, once; nothing later (a decline, expiry, stall or no answer) ever gives it back.
 * While ENERGY is off nothing is asked and nothing is charged.
 *
 * Refusals: 409 energy_empty (the player has none), 409 partner_energy_empty (the partner has none), 503 energy_unavailable
 * (a Player could not be asked); in each case nothing stays spent.
 */
type Spent = { id: string; fresh: boolean; view: EnergyView };

async function charge(env: Env, player: string, payers: readonly string[], duelId: string): Promise<Spent[]> {
  // While ENERGY is gated to newer apps, a partner pays only once their own meter has been used (energy.ts spendEnergy
  // `started`): an app that never showed the meter never spent from it, so a partner still on an older app is never charged.
  const partnersStarted = gated(env, FLAG_VARS.energy);
  const answers = await Promise.all(payers.map(async id => {
    try { return { id, outcome: await env.PLAYERS.getByName(id).spendEnergy(id, duelId, partnersStarted && id !== player) }; } catch { return { id, outcome: null }; }
  }));
  const spent = answers.flatMap(each => each.outcome?.ok ? [{ id: each.id, ...each.outcome.value }] : []);
  const refused = answers.find(each => !each.outcome?.ok);
  if (!refused) return spent;
  // Only this request's own spends go back. A Player that could not be answered is left alone: it may hold an earlier
  // request's spend for the same duel, and at worst it keeps one energy that comes back by itself in ENERGY_RULES.step_ms.
  await giveBack(env, spent.filter(each => each.fresh).map(each => each.id), duelId);
  const failed = refused.outcome;
  if (failed === null) throw new ApiError(503, "energy_unavailable");
  if (!failed.ok && failed.code !== "energy_empty") throw new ApiError(failed.status, failed.code);
  throw new ApiError(409, refused.id === player ? "energy_empty" : "partner_energy_empty");
}

async function giveBack(env: Env, ids: readonly string[], duelId: string): Promise<void> {
  await Promise.all(ids.map(async id => { try { await env.PLAYERS.getByName(id).refundEnergy(id, duelId); } catch { /* the spend line stays; a support check finds it */ } }));
}

/**
 * Runs `start` (the board call that makes or joins the duel) after charging every payer, and gives each fresh spend back
 * when it throws. Answers its value and the requesting player's meter after the spend (null while ENERGY is off for the
 * requesting app, `reach`: then nobody is charged, as with the flag off).
 */
export async function withEnergy<T>(env: Env, reach: Reach, player: string, payers: readonly string[], duelId: string, start: () => Promise<T>): Promise<{ value: T; energy: EnergyView | null }> {
  if (!energyOn(env, reach)) return { value: await start(), energy: null };
  const spent = await charge(env, player, payers, duelId);
  try { return { value: await start(), energy: spent.find(each => each.id === player)?.view ?? null }; }
  catch (error) { await giveBack(env, spent.filter(each => each.fresh).map(each => each.id), duelId); throw error; }
}
