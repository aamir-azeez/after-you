import { RATES, chapterTier, tailPay, type Rates } from "./rates";
import type { TurnFacts } from "./turn-facts";
import type { BloomMultiplier } from "./blooms";

/**
 * What a turn or a first clear pays (POLLEN-RULES.md "Earning"). Pure: integers only, and every
 * rounding is half up. Nothing here reads storage, the clock or a key.
 *
 * A bank turn: a = base x (100 + bonus percent) / 100, rounded once. A bloom pays a x (multiplier - 1)
 * more, and the room boost is boost percent of a, rounded once; both are worked out on the unboosted a,
 * so paying for Full Journey never makes a bloom bigger. An after-bank turn pays its tail step only.
 */
export type Bonus = "first_try" | "gold_pace" | "silver_pace" | "hard";
export type TurnPrice = {
  kind: "bank" | "after_bank";
  /** The tier base before bonuses; 0 after the bank. */
  base: number;
  bonuses: Bonus[];
  /** The bonuses' percents added together. */
  bonus_percent: number;
  /** Base plus bonuses (bank) or the tail step (after the bank). */
  amount: number;
  bloom: BloomMultiplier;
  bloom_extra: number;
  boost_percent: number;
  boost: number;
  total: number;
};
export type ClearPrice = { amount: number; boost_percent: number; boost: number; total: number };

/** n / d rounded half up, for n >= 0 and d > 0. */
export function halfUp(n: number, d: number): number { return Math.floor((2 * n + d) / (2 * d)); }

/** Gold or silver pace for a turn's ticks, or null (no estimate for the stage, or a time below the floor). */
export function pace(facts: Pick<TurnFacts, "level_id" | "stage_id" | "role" | "ticks">, rates: Rates = RATES): "gold" | "silver" | null {
  const best = rates.pace.best_ticks[`${facts.level_id}|${facts.stage_id}|${facts.role}`];
  if (!best || facts.ticks * 100 < best * rates.pace.floor_percent) return null;
  if (facts.ticks * 100 <= best * rates.pace.gold_percent) return "gold";
  return facts.ticks * 100 <= best * rates.pace.silver_percent ? "silver" : null;
}

/** Whether a turn may bloom: a free chapter whose tier blooms. Paid chapters and guests in paid rooms never do. */
export function bloomEligible(facts: Pick<TurnFacts, "level_id" | "premium">, rates: Rates = RATES): boolean {
  return !facts.premium && chapterTier(facts.level_id, rates)?.blooms === true;
}

export type PriceInput = {
  facts: Pick<TurnFacts, "level_id" | "stage_id" | "role" | "ticks" | "tries" | "premium" | "hard" | "host" | "subscriber" | "boost_percent">;
  /** A bank turn (full rate) or an after-bank one. */
  bank: boolean;
  /** For an after-bank turn: how many after-bank turns came before it in its week. */
  tail_index: number;
  /** The turn's bloom roll; used only when the turn may bloom. */
  bloom: BloomMultiplier;
};

export function price(input: PriceInput, rates: Rates = RATES): TurnPrice {
  const { facts } = input;
  const own = chapterTier(facts.level_id, rates);
  if (!input.bank || own === null) {
    const amount = own === null ? 0 : tailPay(input.tail_index, rates);
    return { kind: "after_bank", base: 0, bonuses: [], bonus_percent: 0, amount, bloom: 1, bloom_extra: 0, boost_percent: 0, boost: 0, total: amount };
  }
  // A guest in a paid room earns the guest tier, whatever the chapter's own tier.
  const tier = facts.premium && !facts.host ? rates.tiers[rates.guest_paid_tier] : own;
  const bonuses: Bonus[] = [];
  if (facts.tries === 1) bonuses.push("first_try");
  const speed = pace(facts, rates);
  if (speed) bonuses.push(speed === "gold" ? "gold_pace" : "silver_pace");
  // Hard pays only in a paid chapter, to its host, while the host has Full Journey.
  if (facts.premium && facts.hard && facts.host && facts.subscriber) bonuses.push("hard");
  const bonus_percent = bonuses.reduce((sum, bonus) => sum + rates.bonus_percent[bonus], 0);
  const amount = halfUp(tier.base * (100 + bonus_percent), 100);
  const bloom: BloomMultiplier = bloomEligible(facts, rates) ? input.bloom : 1;
  const bloom_extra = amount * (bloom - 1);
  const boost = halfUp(amount * facts.boost_percent, 100);
  return { kind: "bank", base: tier.base, bonuses, bonus_percent, amount, bloom, bloom_extra, boost_percent: facts.boost_percent, boost, total: amount + bloom_extra + boost };
}

/** A chapter's first clear (and a first Hard clear, which pays it again), with the room's boost. Null for a chapter the rates do not know. */
export function clearPrice(levelId: string, boostPercent: number, rates: Rates = RATES): ClearPrice | null {
  const tier = chapterTier(levelId, rates);
  if (tier === null) return null;
  const boost = halfUp(tier.first_clear * boostPercent, 100);
  return { amount: tier.first_clear, boost_percent: boostPercent, boost, total: tier.first_clear + boost };
}

/** The room boost: boost_percent_per_subscriber for each Full Journey member. */
export function boostPercent(subscribers: number, rates: Rates = RATES): number { return subscribers * rates.boost_percent_per_subscriber; }
