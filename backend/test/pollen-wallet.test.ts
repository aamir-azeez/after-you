import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { creditClear, creditTurn, fullJourneyUntil, historyView, noteFullJourney, walletView, MAX_CLAIMS } from "../src/pollen/wallet";
import { isoWeek } from "../src/pollen/week";
import { POLLEN_PLAYER_TABLES } from "../src/storage-schema";
import type { TurnFacts } from "../src/pollen/turn-facts";
import type { Outcome } from "../src/protocol";

// The wallet's bank, tail, slots, claims and first clears, on a real Player's storage with a fixed clock.
afterEach(async () => { await reset(); });
const SECRET = { POLLEN_SECRET: "synthetic-pollen-secret-for-tests-only-0001" };
const OWNER = "W".repeat(22), ROOM = "R".repeat(22), DAY = 86_400_000;
const MONDAY = Date.UTC(2026, 9, 26, 9);
let serial = 0;
const hash = () => (++serial).toString(16).padStart(64, "0");
function facts(extra: Partial<TurnFacts> = {}, at = MONDAY): TurnFacts {
  return { schema_version: 1, room_id: ROOM, recording_hash: hash(), turn_id: "t0-0-a", player_id: OWNER, accepted_at: at, week: isoWeek(at),
    level_id: "first-steps", stage_id: "first-path", role: "a", ticks: 900, tries: null, premium: false, hard: false, host: true, together: true,
    complete: false, subscriber: false, partner_subscriber: false, boost_percent: 0, ...extra };
}
const stub = () => env.PLAYERS.getByName("wallet-" + serial);
type Storage = DurableObjectStorage;
async function inPlayer<T>(work: (storage: Storage) => Promise<T> | T): Promise<T> {
  return runInDurableObject(stub(), async (_, state) => work(state.storage));
}
const value = <T>(outcome: Outcome<T>): T => { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; };
const credit = (storage: Storage, turn: TurnFacts, now = turn.accepted_at) => creditTurn(storage, SECRET, OWNER, turn, now, () => true);
const rows = (storage: Storage) => storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM pollen_claims").one().n;
/** Twelve different weekly slots of the same chapter family. */
const slots = Array.from({ length: 40 }, (_, index) => ({ stage_id: "stage-" + Math.floor(index / 2), role: (index % 2 ? "b" : "a") as "a" | "b" }));

describe("the Pollen wallet", () => {
  it("starts with 12 bank turns and pays full rate once per chapter, stage and role a week", async () => {
    serial += 100;
    await inPlayer(async storage => {
      expect(walletView(storage, MONDAY)).toEqual({ schema_version: 1, balance: 0, earned: 0, bank: 12 });
      expect(POLLEN_PLAYER_TABLES.some(table => storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name=?", table.name).toArray().length)).toBe(false);
      const first = value(await credit(storage, facts()));
      expect(first).toMatchObject({ earned: 89, balance: 89, turn: { kind: "bank", total: 89 } });
      const repeat = value(await credit(storage, facts()));
      expect(repeat).toMatchObject({ earned: 10, balance: 99, turn: { kind: "after_bank", reason: "repeat", total: 10 } });
      expect(walletView(storage, MONDAY).bank).toBe(11);
      for (const place of slots.slice(1, 12)) expect(value(await credit(storage, facts(place))).turn!.kind).toBe("bank");
      const empty = value(await credit(storage, facts(slots[12])));
      expect(empty.turn).toMatchObject({ kind: "after_bank", reason: "bank_empty", total: 10 });
      expect(walletView(storage, MONDAY)).toMatchObject({ bank: 0, balance: 89 * 12 + 20 });
    });
  });
  it("refills 12 every Monday up to 36, without writing while nothing is credited", async () => {
    serial += 100;
    await inPlayer(async storage => {
      for (const place of slots.slice(0, 12)) value(await credit(storage, facts(place)));
      expect(walletView(storage, MONDAY).bank).toBe(0);
      expect(walletView(storage, MONDAY + 7 * DAY).bank).toBe(12);
      expect(walletView(storage, MONDAY + 14 * DAY).bank).toBe(24);
      expect(walletView(storage, MONDAY + 70 * DAY).bank).toBe(36);
      // The Sunday before the next Monday is still this week.
      expect(walletView(storage, Date.UTC(2026, 10, 1, 23, 59)).bank).toBe(0);
      const next = MONDAY + 7 * DAY;
      expect(value(await credit(storage, facts(slots[0], next))).turn!.kind).toBe("bank");
      expect(walletView(storage, next).bank).toBe(11);
    });
  });
  it("pays 10 for 36 after-bank turns, then 1 for 64, then nothing and writes nothing", async () => {
    serial += 100;
    await inPlayer(async storage => {
      for (const place of slots.slice(0, 12)) value(await credit(storage, facts(place)));
      const pays: number[] = [];
      for (let index = 0; index < 101; index++) pays.push(value(await credit(storage, facts())).earned);
      expect(pays.slice(0, 36).every(pay => pay === 10) && pays.slice(36, 100).every(pay => pay === 1)).toBe(true);
      expect(pays[100]).toBe(0);
      const before = rows(storage), wallet = storage.sql.exec<{ data: string }>("SELECT data FROM pollen_wallet").one().data;
      const zero = value(await credit(storage, facts()));
      expect(zero).toMatchObject({ earned: 0, turn: { kind: "after_bank", total: 0 } });
      expect(rows(storage)).toBe(before);
      expect(storage.sql.exec<{ data: string }>("SELECT data FROM pollen_wallet").one().data).toBe(wallet);
      expect(walletView(storage, MONDAY).balance).toBe(89 * 12 + 424);
    });
  });
  it("credits a turn once: the same facts answer the first receipt and write nothing", async () => {
    serial += 100;
    await inPlayer(async storage => {
      const turn = facts({ tries: 1 });
      const first = value(await credit(storage, turn));
      const count = rows(storage);
      const again = value(await credit(storage, turn, turn.accepted_at + DAY));
      expect(again).toEqual(first);
      expect(rows(storage)).toBe(count);
      expect(walletView(storage, MONDAY).balance).toBe(111);
      // Two credits of one turn at once still pay once.
      const twin = facts(slots[5]);
      const both = await Promise.all([credit(storage, twin), credit(storage, twin)]);
      expect(both.map(outcome => value(outcome).earned)).toEqual([89, 89]);
      expect(walletView(storage, MONDAY).balance).toBe(200);
    });
  });
  it("pays nothing, and writes nothing, for a turn played before a friend joined", async () => {
    serial += 100;
    await inPlayer(async storage => {
      const alone = facts({ together: false });
      expect(value(await credit(storage, alone))).toEqual({ schema_version: 1, earned: 0, balance: 0, clears: [] });
      expect(storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='pollen_claims'").toArray()).toEqual([]);
      expect(value(await credit(storage, alone, MONDAY + DAY)).earned).toBe(0);
      // Its slot and the bank are untouched: the same slot with a friend pays full rate.
      expect(value(await credit(storage, facts())).turn).toMatchObject({ kind: "bank", total: 89 });
      expect(value(await credit(storage, facts({ together: false, complete: true, role: "b" }))).clears).toEqual([]);
    });
  });
  it("refuses another player's facts, broken facts, and facts older than 28 days", async () => {
    serial += 100;
    await inPlayer(async storage => {
      expect(await creditTurn(storage, SECRET, OWNER, { ...facts(), player_id: "X".repeat(22) }, MONDAY, () => true)).toEqual({ ok: false, status: 403, code: "pollen_claim_refused" });
      expect(await creditTurn(storage, SECRET, OWNER, { ...facts(), week: "2026-W01" }, MONDAY, () => true)).toEqual({ ok: false, status: 400, code: "invalid_pollen_facts" });
      expect(await creditTurn(storage, SECRET, OWNER, { ...facts(), boost_percent: 10 }, MONDAY, () => true)).toEqual({ ok: false, status: 400, code: "invalid_pollen_facts" });
      const old = facts({}, MONDAY - 28 * DAY - 1);
      expect(await credit(storage, old, MONDAY)).toEqual({ ok: false, status: 410, code: "pollen_claim_expired" });
      expect(await creditTurn(storage, {}, OWNER, facts(), MONDAY, () => true)).toEqual({ ok: false, status: 503, code: "pollen_unconfigured" });
      expect(await creditTurn(storage, SECRET, OWNER, facts(), MONDAY, () => false)).toEqual({ ok: false, status: 404, code: "identity_absent" });
      expect(walletView(storage, MONDAY).balance).toBe(0);
    });
  });
  it("prices a late claim by its own week's slots, and never on this week's bank", async () => {
    serial += 100;
    await inPlayer(async storage => {
      const lastWeek = MONDAY - 7 * DAY;
      value(await credit(storage, facts({}, lastWeek)));
      // The same slot this week is new; the same slot last week is a repeat.
      expect(value(await credit(storage, facts())).turn!.kind).toBe("bank");
      expect(value(await credit(storage, facts({}, lastWeek + DAY), MONDAY)).turn).toMatchObject({ kind: "after_bank", reason: "repeat" });
      // A new slot of last week claimed today pays the after-bank rate, so no week's turns move onto a later bank.
      expect(value(await credit(storage, facts(slots[3], lastWeek + DAY), MONDAY)).turn).toMatchObject({ kind: "after_bank", reason: "late", total: 10 });
      expect(walletView(storage, MONDAY).bank).toBe(22);
    });
  });
  it("keeps the bank turn of a turn accepted just before Monday and credited just after", async () => {
    serial += 100;
    await inPlayer(async storage => {
      const sunday = MONDAY - 9 * 3_600_000 - 1000;
      expect(value(await credit(storage, facts({}, sunday), sunday + 2000)).turn!.kind).toBe("bank");
    });
  });
  it("starts every bank at 12 with the first pay, however long ago a Full Journey end was noted", async () => {
    serial += 100;
    await inPlayer(async storage => {
      noteFullJourney(storage, MONDAY + 60 * DAY, MONDAY - 28 * DAY);
      expect(walletView(storage, MONDAY).bank).toBe(12);
      value(await credit(storage, facts()));
      expect(walletView(storage, MONDAY).bank).toBe(11);
      expect(walletView(storage, MONDAY + 7 * DAY).bank).toBe(23);
    });
  });
  it("pays bloom and boost lines from the facts", async () => {
    serial += 100;
    await runInDurableObject(stub(), async (_, state) => {
      // P...19 rolls x3 in 2026-W44 for first-steps/first-path/a (test/pollen-earn.test.ts vectors).
      const turn = { ...facts({ subscriber: true, partner_subscriber: true, boost_percent: 20 }), player_id: "P000000000000000000019" };
      const receipt = value(await creditTurn(state.storage, SECRET, turn.player_id, turn, MONDAY, () => true));
      expect(receipt.turn).toMatchObject({ amount: 89, bloom: 3, bloom_extra: 178, boost_percent: 20, boost: 18, total: 285 });
    });
  });
  it("pays a first clear once per chapter, and a first Hard clear together once more", async () => {
    serial += 100;
    await inPlayer(async storage => {
      const finish = value(await credit(storage, facts({ complete: true, hard: true, role: "b", boost_percent: 10, subscriber: true })));
      expect(finish.clears.map(line => [line.kind, line.total])).toEqual([["clear", 1320], ["hardclear", 1320]]);
      expect(finish.earned).toBe(finish.turn!.total + 2640);
      const again = value(await credit(storage, facts({ complete: true, hard: true, role: "b", stage_id: "other" })));
      expect(again.clears).toEqual([]);
      expect(value(creditClear(storage, { level_id: "first-steps", hard: true, boost_percent: 0 }, MONDAY, () => true))).toMatchObject({ earned: 0, clears: [] });
      expect(value(creditClear(storage, { level_id: "long-way-home", hard: false, boost_percent: 20 }, MONDAY, () => true))).toMatchObject({ earned: 3000, clears: [{ kind: "clear", total: 3000 }] });
      expect(value(creditClear(storage, { level_id: "long-way-home", hard: false, boost_percent: 20 }, MONDAY, () => true)).earned).toBe(0);
      expect(creditClear(storage, { level_id: "unknown", hard: false, boost_percent: 0 }, MONDAY, () => true)).toEqual({ ok: false, status: 422, code: "unsupported_chapter" });
      // A Hard finish pays the Hard clear only together; a finish with nobody in the room pays nothing.
      const alone = value(await credit(storage, facts({ level_id: "high-and-low", complete: true, hard: true, together: false })));
      expect([alone.earned, alone.clears]).toEqual([0, []]);
    });
  });
  it("prunes turn claims after 35 days, keeps clears, and stays under its row bound", async () => {
    serial += 100;
    await inPlayer(async storage => {
      const start = MONDAY - 34 * DAY;
      value(await credit(storage, facts({}, start), start));
      value(await credit(storage, facts({ complete: true, role: "b" }, start), start));
      expect(rows(storage)).toBe(3);
      value(await credit(storage, facts(slots[3]), MONDAY + 2 * DAY));
      expect(storage.sql.exec<{ kind: string }>("SELECT kind FROM pollen_claims ORDER BY kind").toArray().map(row => row.kind)).toEqual(["clear", "turn"]);
      expect(MAX_CLAIMS).toBeGreaterThanOrEqual(6 * (36 + 100) + 20);
    });
  });
  it("notes a Full Journey end only on a change, and never makes a wallet to store none", async () => {
    serial += 100;
    await inPlayer(async storage => {
      noteFullJourney(storage, 0, MONDAY);
      expect(storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='pollen_wallet'").toArray()).toEqual([]);
      noteFullJourney(storage, MONDAY + 30 * DAY, MONDAY);
      expect(fullJourneyUntil(storage)).toBe(MONDAY + 30 * DAY);
      expect(walletView(storage, MONDAY)).toEqual({ schema_version: 1, balance: 0, earned: 0, bank: 12 });
      noteFullJourney(storage, 0, MONDAY);
      expect(fullJourneyUntil(storage)).toBe(0);
    });
  });
  it("stops crediting a wallet that fails its check, without stopping play or replacing it", async () => {
    serial += 100;
    await inPlayer(async storage => {
      noteFullJourney(storage, MONDAY + DAY, MONDAY);
      storage.sql.exec("UPDATE pollen_wallet SET data=? WHERE id=1", JSON.stringify({ schema_version: 1, balance: -5 }));
      expect(fullJourneyUntil(storage)).toBe(0);
      expect(() => noteFullJourney(storage, MONDAY + 2 * DAY, MONDAY)).not.toThrow();
      await expect(credit(storage, facts())).rejects.toThrow("unsupported_pollen_wallet");
      expect(storage.sql.exec<{ data: string }>("SELECT data FROM pollen_wallet").one().data).toContain("-5");
    });
  });
  it("lists the newest paid claims as history", async () => {
    serial += 100;
    await inPlayer(async storage => {
      const unpaid = historyView(storage);
      expect(unpaid.entries).toEqual([]);
      expect(unpaid.first_clears).toContainEqual({ level_id: "first-steps", price: 1200 });
      expect(unpaid.first_clears).toContainEqual({ level_id: "turn-of-the-tide", price: 2000 });
      expect(unpaid.first_clears).toContainEqual({ level_id: "long-way-home", price: 2500 });
      expect(unpaid.bank).toEqual({ refill: 12, cap: 36, tail: [{ pay: 10, turns: 36 }, { pay: 1, turns: 64 }] });
      value(await credit(storage, facts(), MONDAY));
      value(await credit(storage, facts({ complete: true, role: "b", stage_id: "second-path" }), MONDAY + 1));
      const view = historyView(storage), entries = view.entries;
      expect(entries.map(entry => [entry.kind, entry.amount])).toEqual([["clear", 1200], ["turn", 89], ["turn", 89]]);
      expect(entries.find(entry => entry.kind === "turn")).toMatchObject({ level_id: "first-steps", role: expect.any(String) });
      // The page's first clears: paid (with its boost) once paid, the price until then.
      expect(view.first_clears).toContainEqual({ level_id: "first-steps", price: 1200, paid: 1200 });
      expect(view.first_clears).toContainEqual({ level_id: "high-and-low", price: 1200 });
    });
  });
  it("says in history what each turn's line said: its bonuses, a bloom and why it paid a little", async () => {
    serial += 100;
    await inPlayer(async storage => {
      const paid = value(await credit(storage, facts({ tries: 1 }), MONDAY));
      value(await credit(storage, facts({ tries: 1 }), MONDAY + 1));
      const [repeat, first] = historyView(storage).entries;
      expect(first).toMatchObject({ kind: "turn", bonuses: ["first_try"] });
      // A bloom shows only when there was one, as on the turn's own line.
      if (paid.turn!.bloom > 1) expect(first.bloom).toBe(paid.turn!.bloom);
      else expect(first).not.toHaveProperty("bloom");
      expect(repeat).toMatchObject({ kind: "turn", amount: 10, reason: "repeat" });
      expect(repeat).not.toHaveProperty("bonuses");
    });
  });
});

