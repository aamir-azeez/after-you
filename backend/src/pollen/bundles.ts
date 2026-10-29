import { isObject } from "../protocol";
import { BUNDLE_KEYS, type BundleKey } from "../config";
import raw from "./bundles.json";

/**
 * The four one-time Pollen bundles (POLLEN-RULES.md "Money"), as data: bundles.json, checked once at
 * module load. The game reads the same file (game/content/pollen_bundles.json; test/pollen-bundles.test.ts
 * pins the two equal), so the store page shows what the server pays.
 *
 * - `pollen` is what one bundle pays, its bonus included; `bonus` is the part of it that is bonus.
 * - `usd_cents` is the US price, kept for a receipt whose purchase carries no revenue figure.
 * - The first bundle a player ever buys also pays first_bonus_percent of its own Pollen, rounded down,
 *   once per player (at 10, the Pouch: 2,100). A refund takes it back and never opens it again. It is 0, off,
 *   until the owner decides on it (POLLEN-RULES.md owner decision 5); at 0 nothing is paid and nothing closes.
 * Amounts live only here: the phone never sends one.
 */
export type Bundle = { pollen: number; bonus: number; usd_cents: number };
export type Bundles = { schema_version: 1; first_bonus_percent: number; bundles: Readonly<Record<BundleKey, Bundle>> };
export { BUNDLE_KEYS, type BundleKey };

const count = (value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
const exact = (value: Record<string, unknown>, keys: readonly string[]) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

/** Throws on any entry outside the shapes above, so a bad edit fails every test and every deploy check. */
export function checkedBundles(value: unknown): Bundles {
  const bad = (what: string): never => { throw new Error(`invalid_pollen_bundles: ${what}`); };
  if (!isObject(value) || value.schema_version !== 1 || !exact(value, ["schema_version", "first_bonus_percent", "bundles"])) bad("fields");
  const v = value as Record<string, unknown>;
  if (!count(v.first_bonus_percent, 0, 100)) bad("first_bonus_percent");
  if (!isObject(v.bundles) || !exact(v.bundles, BUNDLE_KEYS)) bad("bundles");
  for (const key of BUNDLE_KEYS) {
    const bundle = (v.bundles as Record<string, unknown>)[key];
    if (!isObject(bundle) || !exact(bundle, ["pollen", "bonus", "usd_cents"]) || !count(bundle.pollen, 1, 10_000_000) || !count(bundle.bonus, 0, bundle.pollen as number) || !count(bundle.usd_cents, 1, 1_000_000)) bad(key);
  }
  for (const part of [v.bundles, ...Object.values(v.bundles as object), v]) Object.freeze(part);
  return v as Bundles;
}

export const BUNDLES: Bundles = checkedBundles(raw);

/** The first-bundle gift for one bundle: first_bonus_percent of its Pollen, rounded down. */
export function firstGift(key: BundleKey, bundles: Bundles = BUNDLES): number {
  return Math.floor(bundles.bundles[key].pollen * bundles.first_bonus_percent / 100);
}
