import { describe, expect, it } from "vitest";
import { RATES, chapterTier, checkedRates, tailLength, tailPay, type Rates } from "../src/pollen/rates";
import { bloomEligible, boostPercent, clearPrice, halfUp, pace, price, type PriceInput } from "../src/pollen/earn";
import { bloomFromBytes, bloomMessage, bloomRoll } from "../src/pollen/blooms";
import { isoWeek, weekIndex } from "../src/pollen/week";
import { CHAPTERS } from "../src/v2/chapters";
import raw from "../src/pollen/rates.json";

// Pure pricing (POLLEN-RULES.md), pinned to the reference model _tools/pollen_economy.py:
// BASE T1 89, T2f 148, T2 166, T3 207; FIRST 1200, 2000, 2000, 2500; first try +25%, gold +15%,
// silver +5%, Hard (paid) +50%; blooms 8% x2 and 2% x3 on free chapters; the bank 12, +12, cap 36;
// after the bank 10 x 36, then 1 x 64, then 0; the room boost +10% per subscriber; half up once per line.

type Facts = PriceInput["facts"];
const free = (extra: Partial<Facts> = {}): Facts => ({ level_id: "first-steps", stage_id: "first-path", role: "a", ticks: 900, tries: null,
  premium: false, hard: false, host: true, subscriber: false, boost_percent: 0, ...extra });
const paid = (extra: Partial<Facts> = {}): Facts => free({ level_id: "long-way-home", stage_id: "harbour", premium: true, ...extra });
const bank = (facts: Facts, bloom: 1 | 2 | 3 = 1) => price({ facts, bank: true, tail_index: 0, bloom });
/** The rates with an estimated best of 1000 ticks for the first-steps stage, so pace can be priced. */
const paced: Rates = { ...RATES, pace: { ...RATES.pace, best_ticks: { "first-steps|first-path|a": 1000 } } };

describe("Pollen rates", () => {
  it("hold the reference model's numbers", () => {
    expect(Object.fromEntries(Object.entries(RATES.tiers).map(([name, tier]) => [name, [tier.base, tier.first_clear, tier.blooms]]))).toEqual({
      short: [89, 1200, true], long: [148, 2000, true], paid: [166, 2000, false], finale: [207, 2500, false] });
    expect(RATES.bonus_percent).toEqual({ first_try: 25, gold_pace: 15, silver_pace: 5, hard: 50 });
    expect(RATES.boost_percent_per_subscriber).toBe(10);
    expect(RATES.bank).toEqual({ start: 12, refill: 12, cap: 36 });
    expect(RATES.tail).toEqual([{ pay: 10, turns: 36 }, { pay: 1, turns: 64 }]);
    // 8% pay x2 and 2% pay x3: rolls below 200 of 10,000 are x3, the next 800 are x2.
    expect(RATES.blooms).toEqual({ modulus: 10000, triple_below: 200, double_below: 1000 });
    expect(RATES.claims).toEqual({ turn_claim_days: 28, turn_prune_days: 35, weeks_kept: 6 });
  });
  it("give every chapter a tier, and only free chapters a tier that blooms", () => {
    for (const { adapter } of CHAPTERS) {
      const tier = chapterTier(adapter.key.level_id);
      expect(tier, adapter.key.level_id).not.toBeNull();
      expect(tier!.blooms, adapter.key.level_id).toBe(!adapter.premium);
      expect(bloomEligible({ level_id: adapter.key.level_id, premium: adapter.premium })).toBe(!adapter.premium);
    }
    expect(Object.keys(RATES.chapters).sort()).toEqual([...new Set(CHAPTERS.map(row => row.adapter.key.level_id))].sort());
    expect(chapterTier("not-a-chapter")).toBeNull();
    expect(chapterTier("constructor")).toBeNull();
  });
  it("refuse a broken rates file", () => {
    const broken = (change: (value: Record<string, unknown>) => void) => { const copy = structuredClone(raw) as Record<string, unknown>; change(copy); return () => checkedRates(copy); };
    expect(broken(() => undefined)).not.toThrow();
    expect(broken(value => { value.schema_version = 2; })).toThrow("invalid_pollen_rates");
    expect(broken(value => { (value.chapters as Record<string, string>)["first-steps"] = "missing"; })).toThrow("invalid_pollen_rates");
    expect(broken(value => { (value.tiers as Record<string, { base: number }>).short.base = 0.5; })).toThrow("invalid_pollen_rates");
    expect(broken(value => { (value.blooms as Record<string, number>).triple_below = 2000; })).toThrow("invalid_pollen_rates");
    expect(broken(value => { (value.bank as Record<string, number>).start = 40; })).toThrow("invalid_pollen_rates");
    expect(broken(value => { (value.claims as Record<string, number>).turn_prune_days = 28; })).toThrow("invalid_pollen_rates");
  });
});

describe("price", () => {
  it("rounds half up once", () => {
    expect([halfUp(1250, 100), halfUp(1249, 100), halfUp(12460, 100), halfUp(0, 100), halfUp(31050, 100)]).toEqual([13, 12, 125, 0, 311]);
  });
  it("pays each tier's base on a plain bank turn", () => {
    expect(bank(free()).total).toBe(89);
    expect(bank(free({ level_id: "turn-of-the-tide" })).total).toBe(148);
    expect(bank(paid({ level_id: "rolling-home" })).total).toBe(166);
    expect(bank(paid()).total).toBe(207);
  });
  it("adds skill bonuses, so a tier 1 turn pays 89 to 125 before blooms", () => {
    expect(bank(free({ tries: 1 }))).toMatchObject({ bonuses: ["first_try"], bonus_percent: 25, amount: 111, total: 111 });
    expect(bank(free({ tries: 2 })).total).toBe(89);
    expect(price({ facts: free({ tries: 1, ticks: 1200 }), bank: true, tail_index: 0, bloom: 1 }, paced)).toMatchObject({ bonuses: ["first_try", "gold_pace"], amount: 125 });
    expect(price({ facts: free({ ticks: 1201 }), bank: true, tail_index: 0, bloom: 1 }, paced)).toMatchObject({ bonuses: ["silver_pace"], amount: 93 });
    expect(price({ facts: free({ ticks: 1501 }), bank: true, tail_index: 0, bloom: 1 }, paced).bonuses).toEqual([]);
  });
  it("judges pace against the estimate, and leaves out times under its floor", () => {
    const at = (ticks: number) => pace({ level_id: "first-steps", stage_id: "first-path", role: "a", ticks }, paced);
    expect([at(799), at(800), at(1200), at(1201), at(1500), at(1501)]).toEqual([null, "gold", "gold", "silver", "silver", null]);
    // No estimate in the shipped rates yet: no stage pays a pace bonus.
    expect(pace({ level_id: "first-steps", stage_id: "first-path", role: "a", ticks: 1 })).toBeNull();
    expect(Object.keys(RATES.pace.best_ticks)).toEqual([]);
  });
  it("pays Hard only to a paid chapter's host while the host has Full Journey", () => {
    expect(bank(paid({ hard: true, subscriber: true }))).toMatchObject({ bonuses: ["hard"], amount: 311 });
    expect(bank(paid({ hard: true, subscriber: true, tries: 1 })).amount).toBe(362);
    expect(bank(paid({ hard: true, subscriber: false })).amount).toBe(207);
    expect(bank(free({ hard: true, subscriber: true })).amount).toBe(89);
  });
  it("pays a guest in a paid room the guest tier with no Hard bonus and no bloom", () => {
    expect(bank(paid({ host: false, hard: true, subscriber: true }), 3)).toMatchObject({ base: 166, amount: 166, bloom: 1, bloom_extra: 0, total: 166 });
    expect(bank(paid({ host: false, level_id: "conservatory" })).total).toBe(166);
  });
  it("blooms only in free chapters, on the unboosted amount, and boosts as its own line", () => {
    // POLLEN-RULES.md: a free-chapter turn worth 125 that blooms x2 in a room with one subscriber pays 125 + 125 + 13 = 263.
    const turn = price({ facts: free({ tries: 1, ticks: 1000, boost_percent: 10 }), bank: true, tail_index: 0, bloom: 2 }, paced);
    expect(turn).toMatchObject({ amount: 125, bloom: 2, bloom_extra: 125, boost_percent: 10, boost: 13, total: 263 });
    expect(bank(free(), 3)).toMatchObject({ bloom: 3, bloom_extra: 178, total: 267 });
    expect(bank(paid(), 3)).toMatchObject({ bloom: 1, bloom_extra: 0, total: 207 });
    expect(bank(paid({ boost_percent: 20 }), 2)).toMatchObject({ boost: 41, total: 248 });
  });
  it("pays the after-bank tail with no bonus, bloom or boost", () => {
    expect(price({ facts: free({ tries: 1, boost_percent: 20 }), bank: false, tail_index: 0, bloom: 3 })).toEqual({
      kind: "after_bank", base: 0, bonuses: [], bonus_percent: 0, amount: 10, bloom: 1, bloom_extra: 0, boost_percent: 0, boost: 0, total: 10 });
    expect([0, 35, 36, 99, 100, 1000].map(index => tailPay(index))).toEqual([10, 10, 1, 1, 0, 0]);
    expect(tailLength()).toBe(100);
    // At most 424 a week after the bank: 10 x 36 + 1 x 64.
    expect(Array.from({ length: 200 }, (_, index) => tailPay(index)).reduce((sum, pay) => sum + pay, 0)).toBe(424);
  });
  it("pays nothing for a chapter the rates do not know", () => {
    expect(bank(free({ level_id: "unknown-chapter" })).total).toBe(0);
  });
  it("prices first clears with the room boost, half up", () => {
    expect(clearPrice("first-steps", 0)).toEqual({ amount: 1200, boost_percent: 0, boost: 0, total: 1200 });
    expect(clearPrice("first-steps", 10)!.total).toBe(1320);
    expect(clearPrice("turn-of-the-tide", 20)!.total).toBe(2400);
    expect(clearPrice("long-way-home", 10)!.total).toBe(2750);
    expect(clearPrice("unknown-chapter", 10)).toBeNull();
    expect([boostPercent(0), boostPercent(1), boostPercent(2)]).toEqual([0, 10, 20]);
  });
  it("matches the model's expected pay per bank turn for a typical player", () => {
    // Typical profile: first try 60%, gold 25%, silver 35%; blooms 8% x2, 2% x3 (free chapters).
    const model: Record<string, number> = { "first-steps": 89 * 1.205 * 1.12, "turn-of-the-tide": 148 * 1.205 * 1.12, "rolling-home": 166 * 1.205, "long-way-home": 207 * 1.205 };
    for (const [level, expected] of Object.entries(model)) {
      const premium = level === "rolling-home" || level === "long-way-home";
      const rates: Rates = { ...RATES, pace: { ...RATES.pace, best_ticks: { [`${level}|s|a`]: 1000 } } };
      let mean = 0;
      for (const [tries, pFirst] of [[1, 0.6], [2, 0.4]] as const)
        for (const [ticks, pPace] of [[1000, 0.25], [1400, 0.35], [2000, 0.4]] as const)
          for (const [bloom, pBloom] of [[3, 0.02], [2, 0.08], [1, 0.9]] as const)
            mean += pFirst * pPace * pBloom * price({ facts: { ...free({ level_id: level, stage_id: "s", premium }), tries, ticks }, bank: true, tail_index: 0, bloom }, rates).total;
      expect(Math.abs(mean - expected), level).toBeLessThan(0.5);
    }
  });
});

describe("weeks", () => {
  it("names ISO weeks across a year boundary", () => {
    expect(isoWeek(Date.UTC(2026, 9, 26))).toBe("2026-W44");
    expect(isoWeek(Date.UTC(2025, 11, 29))).toBe("2026-W01");
    expect(isoWeek(Date.UTC(2026, 11, 31, 23, 59))).toBe("2026-W53");
    expect(isoWeek(Date.UTC(2027, 0, 1))).toBe("2026-W53");
    expect(isoWeek(Date.UTC(2027, 0, 4))).toBe("2027-W01");
    expect(isoWeek(Date.UTC(2024, 11, 30))).toBe("2025-W01");
  });
  it("starts each week Monday 00:00 UTC", () => {
    const monday = Date.UTC(2026, 9, 26), sunday = monday - 1;
    expect(weekIndex(monday)).toBe(weekIndex(sunday) + 1);
    expect(weekIndex(monday + 7 * 86_400_000 - 1)).toBe(weekIndex(monday));
    expect(weekIndex(Date.UTC(1970, 0, 5))).toBe(0);
  });
});

// Vectors made outside the worker with Node's crypto (hkdfSync, createHmac) from a synthetic secret.
const SECRET = { POLLEN_SECRET: "synthetic-pollen-secret-for-tests-only-0001" };
const slot = (player_id: string, week = "2026-W44") => ({ player_id, week, level_id: "first-steps", stage_id: "first-path", role: "a" as const });

describe("blooms", () => {
  it("roll from the HMAC's first four bytes, big-endian, mod 10,000", () => {
    expect(bloomFromBytes(new Uint8Array([0, 0, 0, 199]))).toEqual({ roll: 199, multiplier: 3 });
    expect(bloomFromBytes(new Uint8Array([0, 0, 0, 200]))).toEqual({ roll: 200, multiplier: 2 });
    expect(bloomFromBytes(new Uint8Array([0, 0, 3, 231]))).toEqual({ roll: 999, multiplier: 2 });
    expect(bloomFromBytes(new Uint8Array([0, 0, 3, 232]))).toEqual({ roll: 1000, multiplier: 1 });
    // 0xffffffff = 4294967295, mod 10,000 = 7295; the top bit must not read as negative.
    expect(bloomFromBytes(new Uint8Array([255, 255, 255, 255]))).toEqual({ roll: 7295, multiplier: 1 });
  });
  it("hash the player's weekly slot, never the recording", () => {
    expect(bloomMessage(slot("AAAAAAAAAAAAAAAAAAAAAA"))).toBe("pollen-bloom-v1|AAAAAAAAAAAAAAAAAAAAAA|2026-W44|first-steps|first-path|a");
  });
  it("match fixed vectors for each multiplier", async () => {
    expect(await bloomRoll(SECRET, slot("AAAAAAAAAAAAAAAAAAAAAA"))).toEqual({ roll: 4721, multiplier: 1 });
    expect(await bloomRoll(SECRET, slot("P000000000000000000013"))).toEqual({ roll: 943, multiplier: 2 });
    expect(await bloomRoll(SECRET, slot("P000000000000000000019"))).toEqual({ roll: 46, multiplier: 3 });
    expect(await bloomRoll(SECRET, { ...slot("AAAAAAAAAAAAAAAAAAAAAA", "2026-W53"), level_id: "relay-isles", stage_id: "second-path", role: "b" })).toEqual({ roll: 5250, multiplier: 1 });
  });
  it("roll nothing without a usable secret", async () => {
    expect(await bloomRoll({}, slot("AAAAAAAAAAAAAAAAAAAAAA"))).toBeNull();
    expect(await bloomRoll({ POLLEN_SECRET: "short" }, slot("AAAAAAAAAAAAAAAAAAAAAA"))).toBeNull();
  });
});
