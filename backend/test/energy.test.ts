import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { ENERGY_RULES, energyAt, energyView, refillEnergy, refundEnergy, spendEnergy } from "../src/pollen/energy";
import { withEnergy } from "../src/duels/energy-charge";
import { applyLedger, historyView, ledgerLines, noteFullJourney } from "../src/pollen/wallet";
import { purse } from "../src/pollen/currency";
import { energyOn } from "../src/pollen/features";
import { ApiError, type Outcome } from "../src/protocol";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { POLLEN_CLIENT, withConfig } from "./config";
import { meterRows } from "./meter";

// Duel energy (ENERGY-PLAN.md, the owner's answers of 2026-11-09): the meter's arithmetic, a spend once per duel, giving
// back a refused start, the Fruit refill, Full Journey's 7, the charge around a start for both of a pair, and the reads.
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const T0 = Date.UTC(2026, 10, 9, 9), STEP = ENERGY_RULES.step_ms;
const value = <T>(outcome: Outcome<T>): T => { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; };
let serial = 0;
async function inPlayer<T>(work: (storage: DurableObjectStorage) => T): Promise<T> {
  return runInDurableObject(env.PLAYERS.getByName("energy-" + ++serial), async (_, state) => work(state.storage));
}
afterEach(async () => { await reset(); });

describe("the energy meter", () => {
  it("is full at 5, comes back one every 10 minutes from the time it is full, and never goes below 0 or above the top", () => {
    expect(energyAt(0, 5, T0)).toBe(5);
    expect(energyAt(T0 + STEP, 5, T0)).toBe(4);
    expect(energyAt(T0 + STEP - 1, 5, T0)).toBe(4);
    expect(energyAt(T0 + 5 * STEP, 5, T0)).toBe(0);
    expect(energyAt(T0 + 9 * STEP, 5, T0)).toBe(0);
    expect(energyAt(T0 + 3 * STEP, 5, T0 + 2 * STEP)).toBe(4);
  });
  it("spends 1 per duel once, refuses when empty, and gives a refused start back once", async () => {
    await inPlayer(storage => {
      for (let n = 0; n < 5; n++) expect(value(spendEnergy(storage, "duel-" + n, T0)).fresh).toBe(true);
      expect(value(spendEnergy(storage, "duel-0", T0))).toMatchObject({ fresh: false, view: { energy: 0 } });
      expect(spendEnergy(storage, "duel-5", T0)).toMatchObject({ ok: false, status: 409, code: "energy_empty" });
      expect(energyView(storage, T0 + STEP)).toMatchObject({ energy: 1, max: 5, full_at: T0 + 5 * STEP });
      expect(refundEnergy(storage, "duel-4", T0).energy).toBe(1);
      expect(refundEnergy(storage, "duel-4", T0).energy).toBe(1);
      // Given back: the same duel's retry pays again, once.
      expect(value(spendEnergy(storage, "duel-4", T0))).toMatchObject({ fresh: true, view: { energy: 0 } });
      // Never a Pollen line in the history.
      expect(historyView(storage, T0).entries).toEqual([]);
    });
  });
  it("holds 7 with Full Journey", async () => {
    await inPlayer(storage => {
      noteFullJourney(storage, T0 + 30 * 86_400_000, T0);
      expect(energyView(storage, T0)).toMatchObject({ energy: 7, max: 7 });
      for (let n = 0; n < 7; n++) value(spendEnergy(storage, "fj-" + n, T0));
      expect(spendEnergy(storage, "fj-7", T0)).toMatchObject({ code: "energy_empty" });
    });
  });
  it("refills to the top for 20 Fruits, only below it", async () => {
    await inPlayer(storage => {
      applyLedger(storage, [{ key: "fruit:bundle:GPA.e1", kind: "fruitbundle", amount: 25, detail: {} }], T0);
      expect(refillEnergy(storage, 20, T0)).toMatchObject({ ok: false, status: 409, code: "energy_full" });
      value(spendEnergy(storage, "r-1", T0)); value(spendEnergy(storage, "r-2", T0));
      expect(refillEnergy(storage, 10, T0)).toMatchObject({ code: "pollen_price_changed" });
      expect(value(refillEnergy(storage, 20, T0))).toMatchObject({ fruit_balance: 5, energy: { energy: 5 } });
      expect(purse(storage, "fruits").balance).toBe(5);
    });
  });
});

// A start through withEnergy, for a pair of real identities.
type Account = { player_id: string; device_token: string };
let address = 0;
const ON = withConfig({ ...env, POLLEN_SECRET: SECRET, features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "ENERGY"] }) as Env;
const OFF = withConfig({ ...env, POLLEN_SECRET: SECRET, features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN"] }) as Env;
async function create(): Promise<Account> {
  const made = await worker.fetch(new Request("https://energy.test/v1/identity", { method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.96." + (++address % 250) }, body: "{}" }), ON);
  expect(made.status).toBe(201);
  return made.json<Account>();
}
const spends = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => ledgerLines(state.storage, "energy:", 16).length);
const empty = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => { for (let n = 0; n < 5; n++) value(spendEnergy(state.storage, "drain-" + n, Date.now())); });

describe("a duel start or join", () => {
  it("charges each of the pair once, answers the starter's meter, and charges nothing while ENERGY is off", async () => {
    const [a, b] = [await create(), await create()];
    expect(energyOn(ON, null)).toBe(true);
    const done = await withEnergy(ON, null, a.player_id, [a.player_id, b.player_id], "duel-ok", async () => "made");
    expect(done).toMatchObject({ value: "made", energy: { energy: 4, max: 5 } });
    await withEnergy(ON, null, a.player_id, [a.player_id, b.player_id], "duel-ok", async () => "made");
    expect([await spends(a), await spends(b)]).toEqual([1, 1]);
    expect(await withEnergy(OFF, null, a.player_id, [a.player_id, b.player_id], "duel-off", async () => "made")).toEqual({ value: "made", energy: null });
    expect([await spends(a), await spends(b)]).toEqual([1, 1]);
  });
  it("gives every spend back when the board refuses, and names a partner who has none", async () => {
    const [a, b] = [await create(), await create()];
    await expect(withEnergy(ON, null, a.player_id, [a.player_id, b.player_id], "duel-refused", async () => { throw new ApiError(409, "duel_limit_reached"); })).rejects.toThrow("duel_limit_reached");
    expect([await spends(a), await spends(b)]).toEqual([0, 0]);
    await empty(b);
    await expect(withEnergy(ON, null, a.player_id, [a.player_id, b.player_id], "duel-partner", async () => "made")).rejects.toMatchObject({ code: "partner_energy_empty" });
    // The starter's own spend went back; the board was never asked.
    expect(await spends(a)).toBe(0);
    await expect(withEnergy(ON, null, b.player_id, [b.player_id], "duel-self", async () => "made")).rejects.toMatchObject({ code: "energy_empty" });
  });
});

describe("the reads", () => {
  const call = (path: string, account: Account, vars: Env) => worker.fetch(new Request("https://energy.test" + path, { headers: { "CF-Connecting-IP": "198.18.97." + (++address % 250), [POLLEN_HEADER]: "1", ...POLLEN_CLIENT,
    "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } }), vars);
  it("carry the meter on the wallet read only while ENERGY is on, writing no row", async () => {
    const account = await create();
    const on = await (await call("/v1/pollen", account, ON)).json<Record<string, unknown>>();
    expect(on.energy).toMatchObject({ energy: 5, max: 5, step_ms: STEP, refill_fruits: 20 });
    expect(await (await call("/v1/pollen", account, OFF)).json()).not.toHaveProperty("energy");
    const metered = await meterRows({ player: env.PLAYERS.getByName(account.player_id) }, () => call("/v1/pollen", account, ON));
    expect(metered.rows.player.written).toBe(0);
  });
});
