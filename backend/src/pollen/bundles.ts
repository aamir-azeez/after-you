import { isObject } from "../protocol";
import { PRODUCT_PATTERN } from "../config";
import { CURRENCIES, type Currency } from "./currency";
import raw from "./bundles.json";

/**
 * The one-time packs of both currencies (POLLEN-RULES.md "Money"; Fruits PLAN v2 section 3), as data: bundles.json,
 * checked once at module load. The game reads the same file (game/content/pollen_bundles.json; test/pollen-bundles.test.ts
 * pins the two equal), so the store page shows what the server pays.
 *
 * - `currency`: "pollen" (Pinch, Pouch, Jar, Basket) or "fruits" (Handful, Bowl, Crate, Barrel). The keys never change; the
 *   game shows the jar as "Basket" and the basket as "Wheelbarrow".
 * - `amount` is what one pack pays, its bonus included; `bonus` is the part of it that is bonus. Both are the same in every store.
 * - Per store (`play_store`, `app_store`, RevenueCat's own store names): `product` is the store's product id
 *   (Play Console, App Store Connect), `revenuecat_product` RevenueCat's own `prod…` id for it, which the
 *   purchases list reports, and `usd_cents` the US price there, kept for a receipt whose purchase carries no
 *   revenue figure. All are public ids that change only with the products, so they live here in code, not in CONFIG.
 *   A currency's packs in a store whose `revenuecat_product` ids are all "" are not set up in RevenueCat yet: none of their
 *   purchases counts (storeReady). A currency with only some of them set in a store is refused.
 * - The first pack a player ever buys in a currency, in any store, also pays first_bonus_percent[currency] of its own amount,
 *   rounded down, once per player and currency (Pollen 20, the owner's choice of 2026-10-31; Fruits 100, paying double, the
 *   owner's of 2026-11-09). A refund takes it back and never opens it again. At 0 it is off: nothing is paid and nothing closes.
 * Amounts live only here: the phone never sends one.
 */
export const BUNDLE_STORES = Object.freeze(["play_store", "app_store"] as const);
export type BundleStore = typeof BUNDLE_STORES[number];
export type StoreProduct = { product: string; revenuecat_product: string; usd_cents: number };
export type Bundle = { currency: Currency; amount: number; bonus: number } & Readonly<Record<BundleStore, StoreProduct>>;
export type Bundles = { schema_version: 3; first_bonus_percent: Readonly<Record<Currency, number>>; bundles: Readonly<Record<BundleKey, Bundle>> };
/** Every pack, smallest first per currency, Pollen first. */
export const BUNDLE_KEYS = Object.freeze(["pinch", "pouch", "jar", "basket", "handful", "bowl", "crate", "barrel"] as const);
export type BundleKey = typeof BUNDLE_KEYS[number];
const CURRENCY_OF: Readonly<Record<BundleKey, Currency>> = Object.freeze({ pinch: "pollen", pouch: "pollen", jar: "pollen", basket: "pollen", handful: "fruits", bowl: "fruits", crate: "fruits", barrel: "fruits" });

/** A Google Play or App Store product id. */
const STORE_PRODUCT = /^[a-z][a-z0-9_.]{0,99}$/;
const count = (value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
const exact = (value: Record<string, unknown>, keys: readonly string[]) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

/** The keys of one currency's packs, smallest first. */
export function keysOf(currency: Currency): BundleKey[] { return BUNDLE_KEYS.filter(key => CURRENCY_OF[key] === currency); }

/** Throws on any entry outside the shapes above, so a bad edit fails every test and every deploy check. */
export function checkedBundles(value: unknown): Bundles {
  const bad = (what: string): never => { throw new Error(`invalid_pollen_bundles: ${what}`); };
  if (!isObject(value) || value.schema_version !== 3 || !exact(value, ["schema_version", "first_bonus_percent", "bundles"])) bad("fields");
  const v = value as Record<string, unknown>;
  const percents = v.first_bonus_percent;
  if (!isObject(percents) || !exact(percents, CURRENCIES) || !CURRENCIES.every(currency => count(percents[currency], 0, 100))) bad("first_bonus_percent");
  if (!isObject(v.bundles) || !exact(v.bundles, BUNDLE_KEYS) || Object.keys(v.bundles).join() !== BUNDLE_KEYS.join()) bad("bundles");
  const table = v.bundles as Record<string, Record<string, unknown>>;
  for (const key of BUNDLE_KEYS) {
    const bundle = table[key];
    if (!isObject(bundle) || !exact(bundle, ["currency", "amount", "bonus", ...BUNDLE_STORES]) || bundle.currency !== CURRENCY_OF[key] ||
      !count(bundle.amount, 1, 10_000_000) || !count(bundle.bonus, 0, bundle.amount as number)) bad(key);
    for (const store of BUNDLE_STORES) {
      const item = bundle[store];
      if (!isObject(item) || !exact(item, ["product", "revenuecat_product", "usd_cents"]) || typeof item.product !== "string" || !STORE_PRODUCT.test(item.product) ||
        typeof item.revenuecat_product !== "string" || (item.revenuecat_product !== "" && !PRODUCT_PATTERN.test(item.revenuecat_product)) || !count(item.usd_cents, 1, 1_000_000)) bad(`${key}.${store}`);
    }
  }
  const all = (store: BundleStore, field: string, keys: readonly BundleKey[] = BUNDLE_KEYS) => keys.map(key => (table[key][store] as Record<string, unknown>)[field]);
  const products = BUNDLE_STORES.flatMap(store => all(store, "product"));
  if (new Set(products).size !== products.length) bad("store product ids repeat");
  // Each currency is set up in a store all at once or not at all: Fruits can wait while Pollen sells.
  for (const store of BUNDLE_STORES) for (const currency of CURRENCIES) {
    const ids = all(store, "revenuecat_product", keysOf(currency));
    if (ids.some(id => id === "") && ids.some(id => id !== "")) bad(`${currency} in ${store} is only partly set up`);
  }
  const ids = BUNDLE_STORES.flatMap(store => all(store, "revenuecat_product")).filter(id => id !== "");
  if (new Set(ids).size !== ids.length) bad("revenuecat product ids repeat");
  for (const part of [...Object.values(table).flatMap(bundle => BUNDLE_STORES.map(store => bundle[store])), ...Object.values(table), table, percents as object, v]) Object.freeze(part);
  return v as Bundles;
}

export const BUNDLES: Bundles = checkedBundles(raw);

/** Whether a currency's packs are set up in RevenueCat in a store (their four `prod…` ids are in the table). */
export function storeReady(store: BundleStore, currency: Currency = "pollen", bundles: Bundles = BUNDLES): boolean {
  return keysOf(currency).every(key => bundles.bundles[key][store].revenuecat_product !== "");
}
/** Whether the App Store's Pollen bundles are set up: the condition for selling them (features.ts appStoreBundlesOn). */
export const APP_STORE_BUNDLES_READY = storeReady("app_store", "pollen");
/** The same for Fruit packs, per store (features.ts fruitPacksOn, appStoreFruitPacksOn). */
export const PLAY_FRUIT_PACKS_READY = storeReady("play_store", "fruits");
export const APP_STORE_FRUIT_PACKS_READY = storeReady("app_store", "fruits");

/** The first-pack gift for one pack: its currency's first_bonus_percent of its amount, rounded down. */
export function firstGift(key: BundleKey, bundles: Bundles = BUNDLES): number {
  const bundle = bundles.bundles[key];
  return Math.floor(bundle.amount * bundles.first_bonus_percent[bundle.currency] / 100);
}
