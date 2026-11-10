import { isObject } from "../protocol";
import { RATES } from "./rates";
import raw from "./fruits.json";

/**
 * Fruits' numbers (claude PLAN v2 with the owner's answers of 2026-11-09 and its rebalance of 2026-11-10), as data: fruits.json, checked once at module
 * load, so a bad edit fails every test and every deploy check. Pack sizes and prices are in bundles.json, Orchard prices
 * in catalog.json; everything else Fruit is here. The phone reads these numbers from the wallet read, never its own copy.
 *
 * - grant: Full Journey month n pays min(first + step x floor((n - 1) / every), top) Fruits, on the same month count as
 *   the Pollen grant, plus `welcome` once per player with the first paid instalment while Fruits are on (grant-settle.ts).
 * - convert: Fruits turn into Pollen one way, `pollen_per_fruit` each, in multiples of `step`.
 * - sunshine: `price` Fruits double the base and skill pay of the next `turns` bank turns (wallet.ts creditTurn).
 * - achievements: one-time goals in display order (achievements.ts). `goal` 0 means every chapter the rates know.
 */
export type Ladder = { first: number; step: number; every: number; top: number };
export type Track = "together_clears" | "hard_clears" | "every_hard" | "duel_wins" | "ghost_wins" | "public_duels" | "top_ten_ribbon" | "gold_leaf" | "keepsakes" | "keepsakes_best";
export type Achievement = { id: string; fruits: number; track: Track; goal: number };
export type FruitRules = {
  schema_version: 1; grant: Ladder & { welcome: number }; convert: { pollen_per_fruit: number; step: number };
  sunshine: { price: number; turns: number }; achievements: readonly Achievement[];
};
export const TRACKS: readonly Track[] = Object.freeze(["together_clears", "hard_clears", "every_hard", "duel_wins", "ghost_wins", "public_duels", "top_ten_ribbon", "gold_leaf", "keepsakes", "keepsakes_best"]);
/** Tracks nothing can move yet: the keepsakes goals wait for keepsakes round 2. Listed, never paid. */
export const DORMANT_TRACKS: ReadonlySet<Track> = new Set(["keepsakes", "keepsakes_best"]);

const count = (value: unknown, min = 0, max = 1_000_000): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
const exact = (value: Record<string, unknown>, keys: readonly string[]) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

export function checkedFruitRules(value: unknown): FruitRules {
  const bad = (what: string): never => { throw new Error(`invalid_fruit_rules: ${what}`); };
  if (!isObject(value) || value.schema_version !== 1 || !exact(value, ["schema_version", "grant", "convert", "sunshine", "achievements"])) bad("fields");
  const v = value as Record<string, unknown>;
  const grant = v.grant as Record<string, unknown>;
  if (!isObject(grant) || !exact(grant, ["first", "step", "every", "top", "welcome"]) || !count(grant.first, 1) || !count(grant.step) || !count(grant.every, 1) || !count(grant.top, grant.first as number) || !count(grant.welcome)) bad("grant");
  const convert = v.convert as Record<string, unknown>;
  if (!isObject(convert) || !exact(convert, ["pollen_per_fruit", "step"]) || !count(convert.pollen_per_fruit, 1) || !count(convert.step, 1)) bad("convert");
  const sunshine = v.sunshine as Record<string, unknown>;
  if (!isObject(sunshine) || !exact(sunshine, ["price", "turns"]) || !count(sunshine.price, 1) || !count(sunshine.turns, 1, 1000)) bad("sunshine");
  if (!Array.isArray(v.achievements) || !v.achievements.length) bad("achievements");
  const ids = new Set<string>();
  for (const entry of v.achievements as unknown[]) {
    if (!isObject(entry)) bad("achievement");
    const item = entry as Record<string, unknown>;
    if ( !exact(item, ["id", "fruits", "track", "goal"]) || typeof item.id !== "string" || !/^[a-z0-9_]{1,32}$/.test(item.id) || ids.has(item.id) ||
      !count(item.fruits, 1) || !TRACKS.includes(item.track as Track) || !count(item.goal, 0, 1000) || (item.goal === 0 && item.track !== "together_clears")) bad(String(item.id));
    ids.add(item.id as string);
  }
  const frozen = (item: object) => Object.freeze(item);
  (v.achievements as object[]).forEach(frozen);
  for (const part of [grant, convert, sunshine, v.achievements as object, v]) frozen(part);
  return v as FruitRules;
}

export const FRUIT_RULES: FruitRules = checkedFruitRules(raw);

/** What month n (1-based) of a ladder pays. The Pollen grant's ladder has every 1. */
export function ladderAmount(n: number, ladder: Ladder): number {
  return Math.min(ladder.first + ladder.step * Math.floor((Math.max(1, n) - 1) / ladder.every), ladder.top);
}
/** The Fruits month n of Full Journey pays. */
export function fruitInstalment(n: number, rules: FruitRules = FRUIT_RULES): number { return ladderAmount(n, rules.grant); }
/** An achievement's goal, with 0 read as every chapter the rates know. */
export function goalOf(achievement: Achievement, chapters = Object.keys(RATES.chapters).length): number { return achievement.goal === 0 ? chapters : achievement.goal; }
