import raw from "./rates.json";

/**
 * Pollen pay rates (POLLEN-RULES.md), as data: rates.json holds every number, this file
 * checks them once at module load and gives them names. A chapter's tier sets its base pay
 * and first clear; whether a turn is paid comes from the chapter adapter (`premium`), never
 * from here. `_tools/pollen_economy.py` is the reference model; test/pollen-earn.test.ts pins
 * its numbers.
 */
export type Tier = { base: number; first_clear: number; blooms: boolean };
export type TailStep = { pay: number; turns: number };
export type Rates = {
  tiers: Readonly<Record<string, Tier>>;
  /** level_id -> tier name, for every chapter (any version). */
  chapters: Readonly<Record<string, string>>;
  /** The tier a guest's turn in a paid room pays, whatever the chapter's own tier. */
  guest_paid_tier: string;
  bonus_percent: { first_try: number; gold_pace: number; silver_pace: number; hard: number };
  /** Each Full Journey member of a room adds this much for both players. */
  boost_percent_per_subscriber: number;
  /**
   * Friend duels (POLLEN-RULES.md "Duels and ghost races"): a duel bank turn adds turn_percent of its
   * base plus bonuses, worked out together with the room boost and rounded once; each player of the
   * winning pair gets win_bonus, at most wins_per_week counted wins a week, once a week per opposing pair.
   */
  duels: { turn_percent: number; win_bonus: number; wins_per_week: number };
  /** Full-rate turns: a new wallet starts with `start`, gains `refill` each Monday (UTC) and holds at most `cap`. */
  bank: { start: number; refill: number; cap: number };
  /** After the bank: `pay` for each of the next `turns` turns in a week, step by step, then 0. */
  tail: readonly TailStep[];
  /** A bloom roll is HMAC bytes 0..3 (big-endian) mod `modulus`: below `triple_below` pays x3, below `double_below` x2. */
  blooms: { modulus: number; triple_below: number; double_below: number };
  /**
   * Item blooms (pollen/item-blooms.ts): a roll is HMAC bytes 0..3 (big-endian) mod `modulus`; the first
   * tier whose cumulative `below` is above the roll drops, rarest first. A roll at or above the last `below` drops nothing.
   */
  item_blooms: { modulus: number; tiers: readonly { tier: string; below: number }[] };
  /**
   * The Full Journey monthly grant (pollen/grant.ts): month n of a subscription pays
   * min(first + step x (n - 1), top). `lifetime_thanks`: the one-off thank-you for the old Lifetime unlock.
   */
  grant: { first: number; step: number; top: number; lifetime_thanks: number };
  /**
   * Estimated pace: Gold at or under best x gold_percent%, Silver at or under best x silver_percent%,
   * nothing under best x floor_percent%. `best_ticks` is keyed "level_id|stage_id|role"; a stage
   * with no entry has no pace bonus.
   */
  pace: { gold_percent: number; silver_percent: number; floor_percent: number; best_ticks: Readonly<Record<string, number>> };
  /** A turn claim is refused once its facts are older than turn_claim_days; turn claims are pruned after turn_prune_days. */
  claims: { turn_claim_days: number; turn_prune_days: number; weeks_kept: number };
};

const count = (value: unknown, min = 0): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min;

/** Throws on any rate outside the shapes above, so a bad edit fails every test and every deploy check. */
export function checkedRates(value: unknown): Rates {
  const rates = value as Rates & { schema_version: number };
  const fail = (what: string): never => { throw new Error("invalid_pollen_rates:" + what); };
  if (rates?.schema_version !== 1) fail("schema_version");
  for (const [name, tier] of Object.entries(rates.tiers ?? {})) if (!count(tier.base, 1) || !count(tier.first_clear, 1) || typeof tier.blooms !== "boolean") fail("tier " + name);
  for (const [level, tier] of Object.entries(rates.chapters ?? {})) if (!/^[a-z0-9-]{1,64}$/.test(level) || !rates.tiers[tier]) fail("chapter " + level);
  if (!rates.tiers[rates.guest_paid_tier]) fail("guest_paid_tier");
  if (!Object.values(rates.bonus_percent ?? {}).every(percent => count(percent))) fail("bonus_percent");
  if (!count(rates.boost_percent_per_subscriber)) fail("boost");
  if (!count(rates.duels?.turn_percent) || !count(rates.duels.win_bonus) || !count(rates.duels.wins_per_week, 1)) fail("duels");
  if (!count(rates.bank?.start) || !count(rates.bank?.refill) || !count(rates.bank?.cap, 1) || rates.bank.start > rates.bank.cap) fail("bank");
  if (!Array.isArray(rates.tail) || !rates.tail.every(step => count(step.pay) && count(step.turns, 1))) fail("tail");
  const blooms = rates.blooms;
  if (!count(blooms?.modulus, 1) || !count(blooms.triple_below) || !count(blooms.double_below) || blooms.triple_below > blooms.double_below || blooms.double_below > blooms.modulus) fail("blooms");
  const items = rates.item_blooms;
  if (!count(items?.modulus, 1) || !Array.isArray(items.tiers) || !items.tiers.every((step, index) => typeof step?.tier === "string" && /^[a-z]{1,16}$/.test(step.tier) &&
    count(step.below, 1) && step.below <= items.modulus && (index === 0 || step.below > items.tiers[index - 1].below)) || new Set(items.tiers.map(step => step.tier)).size !== items.tiers.length) fail("item_blooms");
  const grant = rates.grant;
  if (!count(grant?.first, 1) || !count(grant.step) || !count(grant.top, 1) || grant.top < grant.first || !count(grant.lifetime_thanks)) fail("grant");
  const pace = rates.pace;
  if (!count(pace?.gold_percent, 1) || !count(pace.silver_percent, 1) || !count(pace.floor_percent) || pace.gold_percent > pace.silver_percent || pace.floor_percent > pace.gold_percent) fail("pace");
  for (const [stage, ticks] of Object.entries(pace.best_ticks ?? {})) if (!/^[a-z0-9-]+\|[a-z0-9-]+\|[ab]$/.test(stage) || !count(ticks, 1)) fail("pace " + stage);
  const claims = rates.claims;
  if (!count(claims?.turn_claim_days, 1) || !count(claims.turn_prune_days, 1) || claims.turn_prune_days <= claims.turn_claim_days || !count(claims.weeks_kept, 1) || claims.weeks_kept * 7 < claims.turn_claim_days + 7) fail("claims");
  return rates;
}

export const RATES: Rates = checkedRates(raw);
export const DAY_MS = 86_400_000;

/** The tier of a chapter by level_id, or null for a chapter the rates do not know (it earns nothing). */
export function chapterTier(levelId: string, rates: Rates = RATES): Tier | null {
  const name = Object.hasOwn(rates.chapters, levelId) ? rates.chapters[levelId] : undefined;
  return name === undefined ? null : rates.tiers[name];
}

/** The most after-bank turns in a week that still pay something. */
export function tailLength(rates: Rates = RATES): number { return rates.tail.reduce((sum, step) => sum + step.turns, 0); }

/** What the `index`th after-bank turn of a week pays (0-based): each tail step in order, then 0. */
export function tailPay(index: number, rates: Rates = RATES): number {
  let start = 0;
  for (const step of rates.tail) { if (index < start + step.turns) return step.pay; start += step.turns; }
  return 0;
}
