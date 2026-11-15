import { isObject } from "../protocol";
import type { ServerVars } from "../flags";
import { APP, PROJECT_PATTERN, serverConfig } from "../config";
import { revenuecatRequest, type ProviderResult } from "../play-entitlement";
import { BUNDLES, BUNDLE_KEYS, BUNDLE_STORES, type BundleKey, type BundleStore, type Bundles } from "./bundles";
import { APP_STORE_REF, APP_STORE_TRANSACTION, bundleRef, refId } from "./claims";
import { SUB_ID_PATTERN } from "./grant";
import type { ProviderFetch } from "./grant-provider";

/**
 * The bundles' read of RevenueCat: the customer's one-time purchases (REST v2, the same list and key the
 * hosting check reads), filtered to real Pollen only. A purchase counts when it is:
 * - a Play Store or App Store purchase, in production or in sandbox, owned by purchase (never family shared);
 * - of one of the four bundle products of that same store (bundles.json, the store's revenuecat_product), so the
 *   App Store counts only once its four products are in the table;
 * - with a RevenueCat id, a quantity from 1 to MAX_QUANTITY and a purchase time.
 * Sandbox counts for every player, every time (owner, 2026-11-14: testers are trusted): only the developer can make a
 * sandbox buyer (a Play Console license tester, App Store sandbox, TestFlight and App Review). Test Store (the GitHub
 * APK), promotional and any other product mint nothing: their store never matches a bundle product's store.
 * Each read is two list requests made at once, production and sandbox (one list each, so neither fills the other's
 * page of 100); one list holds both stores, so the App Store adds no request. A sandbox purchase carries `sandbox`,
 * so its paid line keeps the mark and the refund check looks it up in sandbox.
 * Each counted purchase carries its reference (`order`, claims.ts bundleRef): the Play order, or "appstore:" and the
 * App Store transaction id. A purchase without one is never paid (bundle-settle.ts pays by reference); it can only
 * take back an older Play line paid under its id. Status "owned" is paid once; "refunded" takes back what it paid.
 *
 * Any failed, unconfigured, malformed or partial read answers { ok: false }: nothing is credited or taken back on it.
 *
 * lookupBundles is the refund check's second read, for a paid bundle no longer in the buyer's own list (a restore
 * with RevenueCat's "Transfer to new App User ID" moved it to another identity): the purchase found by its Google
 * Play order or App Store transaction id, whoever holds it now, through the project-level search
 * (https://www.revenuecat.com/docs/api-v2/purchase#tag/Purchase/operation/search-purchases), or by its RevenueCat
 * id when no order was kept (https://www.revenuecat.com/docs/api-v2/purchase#tag/Purchase/operation/get-purchase).
 */
/** `order`: the purchase's reference (claims.ts bundleRef), "" when the store gave none. `sandbox`: a sandbox purchase, either store. */
export type BundlePurchase = { id: string; bundle: BundleKey; refunded: boolean; quantity: number; order: string; usd_cents: number; purchased_at: number; sandbox?: true };
/** The environment App Review, TestFlight and Play license testers buy in. */
export const SANDBOX = "sandbox";
/** The environments every bundle read lists, production first. */
const ENVIRONMENTS: readonly string[] = Object.freeze([APP.playEnvironment, SANDBOX]);
/** RevenueCat product id -> the bundle it sells and the store it sells in. */
export type BundleProducts = Readonly<Record<string, { bundle: BundleKey; store: BundleStore }>>;
export type BundleRead = { ok: true; purchases: BundlePurchase[] } | { ok: false; reason: string };

/** Play lets a player buy a few of one consumable at once (multi-quantity); each pays its Pollen, never a second first gift. */
export const MAX_QUANTITY = 10;
/** A Google Play order number as RevenueCat reports it (store_purchase_identifier, "GPA.…"). */
const ORDER_PATTERN = /^[A-Za-z0-9_.:-]{1,128}$/;
/**
 * The purchase's reference ("" when none or malformed), from its store_purchase_identifier: the docs' sample shows it
 * as a number though the schema says string. A Play order that looks like an App Store reference is refused.
 */
function refOf(store: BundleStore, value: unknown): string {
  const text = typeof value === "string" ? value : typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? String(value) : "";
  if (store === "app_store") return APP_STORE_TRANSACTION.test(text) ? bundleRef(store, text) : "";
  return ORDER_PATTERN.test(text) && !text.startsWith(APP_STORE_REF) ? text : "";
}

/** One listed purchase as the bundles see it, in `environment` (production or SANDBOX), or null for one that never counts. */
export function bundlePurchase(item: unknown, products: BundleProducts, environment: string = APP.playEnvironment, bundles: Bundles = BUNDLES): BundlePurchase | null {
  if (!isObject(item) || item.object !== "purchase" || typeof item.id !== "string" || !SUB_ID_PATTERN.test(item.id)) return null;
  if (!ENVIRONMENTS.includes(environment) || item.environment !== environment || item.ownership !== "purchased" || typeof item.product_id !== "string" || !Object.hasOwn(products, item.product_id)) return null;
  const { bundle, store } = products[item.product_id];
  if (item.store !== store) return null;
  if (item.status !== "owned" && item.status !== "refunded") return null;
  const quantity = item.quantity === undefined || item.quantity === null ? 1 : item.quantity;
  if (typeof quantity !== "number" || !Number.isSafeInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY) return null;
  if (typeof item.purchased_at !== "number" || !Number.isSafeInteger(item.purchased_at) || item.purchased_at <= 0) return null;
  const order = refOf(store, item.store_purchase_identifier);
  const gross = isObject(item.revenue_in_usd) ? item.revenue_in_usd.gross : undefined;
  const usd = typeof gross === "number" && Number.isFinite(gross) && gross >= 0 && gross <= 10_000 ? Math.round(gross * 100) : bundles.bundles[bundle][store].usd_cents * quantity;
  return { id: item.id, bundle, refunded: item.status === "refunded", quantity, order, usd_cents: usd, purchased_at: item.purchased_at, ...(environment === SANDBOX ? { sandbox: true as const } : {}) };
}

/** RevenueCat product id -> bundle and store, from the table: a store not set up yet ("" ids) has none. */
export function bundleProducts(bundles: Bundles = BUNDLES): BundleProducts {
  return Object.fromEntries(BUNDLE_STORES.flatMap(store => BUNDLE_KEYS.flatMap(bundle => {
    const id = bundles.bundles[bundle][store].revenuecat_product;
    return id ? [[id, { bundle, store }]] : [];
  })));
}

/** The project's REST v2 base and key, or null while unconfigured. Also the grant's lookups (grant-provider.ts lookupGrantSubs). */
export function project(env: ServerVars): { base: string; key: string } | null {
  const id = serverConfig(env).revenuecat.project_id ?? "", key = env.REVENUECAT_SECRET_KEY;
  return key && PROJECT_PATTERN.test(id) ? { base: `https://api.revenuecat.com/v2/projects/${encodeURIComponent(id)}`, key } : null;
}
/** A whole list's items, [] for 404, or the reason it cannot be trusted. */
function listItems(result: ProviderResult): unknown[] | string {
  if (!result.ok) return result.reason;
  if (result.status === 404) return [];
  const value = result.value;
  if (!isObject(value) || value.object !== "list" || !Array.isArray(value.items) || value.items.length > 100) return "provider_invalid_list";
  return value.next_page ? "provider_incomplete_list" : value.items;
}

/** Oldest first, ties by RevenueCat id. */
export function byPurchaseTime(a: BundlePurchase, b: BundlePurchase): number { return a.purchased_at - b.purchased_at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0); }

/** The player's counted bundle purchases in both environments, oldest first. */
export async function readBundles(playerId: string, env: ServerVars, request: ProviderFetch = revenuecatRequest): Promise<BundleRead> {
  const products = bundleProducts(), at = project(env);
  if (at === null) return { ok: false, reason: "unconfigured" };
  const lists = await Promise.all(ENVIRONMENTS.map(async environment =>
    ({ environment, items: listItems(await request(`${at.base}/customers/${encodeURIComponent(playerId)}/purchases?environment=${environment}&limit=100`, at.key)) })));
  const purchases: BundlePurchase[] = [];
  for (const { environment, items } of lists) {
    if (typeof items === "string") return { ok: false, reason: items };
    for (const item of items) { const each = bundlePurchase(item, products, environment); if (each) purchases.push(each); }
  }
  purchases.sort(byPurchaseTime);
  return { ok: true, purchases };
}

/** A paid bundle the refund check asks about: the ledger's own purchase id, bundle and reference ("" when none was kept). */
export type BundleAsk = { id: string; bundle: BundleKey; order: string; sandbox?: boolean };
/** The asked purchases RevenueCat reports refunded now, by the ledger's purchase id; { ok: false } when any lookup failed. */
export type BundleLookup = { ok: true; refunded: string[] } | { ok: false; reason: string };

/**
 * Whether `item` is the asked purchase: the same reference (or, without one, the same RevenueCat id), counted by
 * bundlePurchase() as the same bundle, in the line's own environment (a sandbox line matches a sandbox purchase).
 */
function samePurchase(item: unknown, ask: BundleAsk, products: BundleProducts): boolean {
  const counted = bundlePurchase(item, products, ask.sandbox ? SANDBOX : APP.playEnvironment);
  if (counted === null || counted.bundle !== ask.bundle) return false;
  return ask.order ? counted.order === ask.order : counted.id === ask.id;
}

/**
 * Whether each asked purchase is refunded now, whichever App User ID holds it: one request per purchase, all at
 * once, so a slow provider costs the wallet read one request timeout, not one per purchase.
 * Not found (404, or nothing that matches) is no news; only "refunded" is acted on.
 */
export async function lookupBundles(asks: readonly BundleAsk[], env: ServerVars, request: ProviderFetch = revenuecatRequest): Promise<BundleLookup> {
  const products = bundleProducts(), at = project(env);
  if (at === null) return { ok: false, reason: "unconfigured" };
  const found = await Promise.all(asks.map(async (ask): Promise<unknown[] | string> => {
    if (ask.order) return listItems(await request(`${at.base}/purchases?store_purchase_identifier=${encodeURIComponent(refId(ask.order))}`, at.key));
    const result = await request(`${at.base}/purchases/${encodeURIComponent(ask.id)}`, at.key);
    return !result.ok ? result.reason : result.status === 404 ? [] : [result.value];
  }));
  const refunded: string[] = [];
  for (const [index, items] of found.entries()) {
    if (typeof items === "string") return { ok: false, reason: items };
    const ask = asks[index];
    if (items.some(item => samePurchase(item, ask, products) && isObject(item) && item.status === "refunded")) refunded.push(ask.id);
  }
  return { ok: true, refunded };
}
