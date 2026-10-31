import { isObject } from "../protocol";
import { PRODUCT_PATTERN } from "../config";
import raw from "./bundles.json";

/**
 * The four one-time Pollen bundles (POLLEN-RULES.md "Money"), as data: bundles.json, checked once at
 * module load. The game reads the same file (game/content/pollen_bundles.json; test/pollen-bundles.test.ts
 * pins the two equal), so the store page shows what the server pays.
 *
 * - `pollen` is what one bundle pays, its bonus included; `bonus` is the part of it that is bonus. Both are the
 *   same in every store.
 * - Per store (`play_store`, `app_store`, RevenueCat's own store names): `product` is the store's product id
 *   (Play Console, App Store Connect), `revenuecat_product` RevenueCat's own `prod…` id for it, which the
 *   purchases list reports, and `usd_cents` the US price there, kept for a receipt whose purchase carries no
 *   revenue figure. All are public ids that change only with the products, so they live here in code, not in CONFIG.
 *   A store whose four `revenuecat_product` ids are all "" is not set up in RevenueCat yet: none of its purchases
 *   counts (storeReady). A table with only some of them set is refused.
 * - The first bundle a player ever buys, in any store, also pays first_bonus_percent of its own Pollen, rounded
 *   down, once per player (at 20, the owner's choice of 2026-10-31, the Pouch: 4,200). A refund takes it back and
 *   never opens it again. At 0 it is off: nothing is paid and nothing closes.
 * Amounts live only here: the phone never sends one.
 */
export const BUNDLE_STORES = Object.freeze(["play_store", "app_store"] as const);
export type BundleStore = typeof BUNDLE_STORES[number];
export type StoreProduct = { product: string; revenuecat_product: string; usd_cents: number };
export type Bundle = { pollen: number; bonus: number } & Readonly<Record<BundleStore, StoreProduct>>;
export type Bundles = { schema_version: 2; first_bonus_percent: number; bundles: Readonly<Record<BundleKey, Bundle>> };
/** The four bundles, smallest first. */
export const BUNDLE_KEYS = Object.freeze(["pinch", "pouch", "jar", "basket"] as const);
export type BundleKey = typeof BUNDLE_KEYS[number];

/** A Google Play or App Store product id. */
const STORE_PRODUCT = /^[a-z][a-z0-9_.]{0,99}$/;
const count = (value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
const exact = (value: Record<string, unknown>, keys: readonly string[]) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

/** Throws on any entry outside the shapes above, so a bad edit fails every test and every deploy check. */
export function checkedBundles(value: unknown): Bundles {
  const bad = (what: string): never => { throw new Error(`invalid_pollen_bundles: ${what}`); };
  if (!isObject(value) || value.schema_version !== 2 || !exact(value, ["schema_version", "first_bonus_percent", "bundles"])) bad("fields");
  const v = value as Record<string, unknown>;
  if (!count(v.first_bonus_percent, 0, 100)) bad("first_bonus_percent");
  if (!isObject(v.bundles) || !exact(v.bundles, BUNDLE_KEYS)) bad("bundles");
  const table = v.bundles as Record<string, Record<string, unknown>>;
  for (const key of BUNDLE_KEYS) {
    const bundle = table[key];
    if (!isObject(bundle) || !exact(bundle, ["pollen", "bonus", ...BUNDLE_STORES]) || !count(bundle.pollen, 1, 10_000_000) || !count(bundle.bonus, 0, bundle.pollen as number)) bad(key);
    for (const store of BUNDLE_STORES) {
      const item = bundle[store];
      if (!isObject(item) || !exact(item, ["product", "revenuecat_product", "usd_cents"]) || typeof item.product !== "string" || !STORE_PRODUCT.test(item.product) ||
        typeof item.revenuecat_product !== "string" || (item.revenuecat_product !== "" && !PRODUCT_PATTERN.test(item.revenuecat_product)) || !count(item.usd_cents, 1, 1_000_000)) bad(`${key}.${store}`);
    }
  }
  const all = (store: BundleStore, field: string) => BUNDLE_KEYS.map(key => (table[key][store] as Record<string, unknown>)[field]);
  const products = BUNDLE_STORES.flatMap(store => all(store, "product"));
  if (new Set(products).size !== products.length) bad("store product ids repeat");
  for (const store of BUNDLE_STORES) {
    const ids = all(store, "revenuecat_product");
    if (ids.some(id => id === "") && ids.some(id => id !== "")) bad(`${store} is only partly set up`);
  }
  const ids = BUNDLE_STORES.flatMap(store => all(store, "revenuecat_product")).filter(id => id !== "");
  if (new Set(ids).size !== ids.length) bad("revenuecat product ids repeat");
  for (const part of [...Object.values(table).flatMap(bundle => BUNDLE_STORES.map(store => bundle[store])), ...Object.values(table), table, v]) Object.freeze(part);
  return v as Bundles;
}

export const BUNDLES: Bundles = checkedBundles(raw);

/** Whether a store's bundles are set up in RevenueCat (its four `prod…` ids are in the table). */
export function storeReady(store: BundleStore, bundles: Bundles = BUNDLES): boolean {
  return BUNDLE_KEYS.every(key => bundles.bundles[key][store].revenuecat_product !== "");
}
/** Whether the App Store's bundles are set up: the condition for selling them (features.ts appStoreBundlesOn). */
export const APP_STORE_BUNDLES_READY = storeReady("app_store");

/** The first-bundle gift for one bundle: first_bonus_percent of its Pollen, rounded down. */
export function firstGift(key: BundleKey, bundles: Bundles = BUNDLES): number {
  return Math.floor(bundles.bundles[key].pollen * bundles.first_bonus_percent / 100);
}
