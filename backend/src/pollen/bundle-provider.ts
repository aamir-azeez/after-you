import { isObject } from "../protocol";
import type { ServerVars } from "../flags";
import { APP, PROJECT_PATTERN, serverConfig } from "../config";
import { revenuecatRequest, type ProviderResult } from "../play-entitlement";
import { BUNDLES, BUNDLE_KEYS, type BundleKey, type Bundles } from "./bundles";
import { SUB_ID_PATTERN } from "./grant";
import type { ProviderFetch } from "./grant-provider";

/**
 * The bundles' read of RevenueCat: the customer's one-time purchases (REST v2, the same list and key the
 * hosting check reads), filtered to real Pollen only. A purchase counts when it is:
 * - a Play Store purchase in production (APP.playEnvironment), owned by purchase (never family shared);
 * - of one of the four bundle products (bundles.json revenuecat_product);
 * - with a RevenueCat id, a quantity from 1 to MAX_QUANTITY and a purchase time.
 * Test Store, sandbox, promotional, App Store and any other product mint nothing. A purchase without a Play
 * order is never paid (bundle-settle.ts pays by order); it can only take back an older line paid under its id.
 * Status "owned" is paid once; "refunded" takes back what it paid.
 *
 * Any failed, unconfigured, malformed or partial read answers { ok: false }: nothing is credited or taken back on it.
 *
 * lookupBundles is the refund check's second read, for a paid bundle no longer in the buyer's own list (a restore
 * with RevenueCat's "Transfer to new App User ID" moved it to another identity): the purchase found by its Google
 * Play order, whoever holds it now, through the project-level search
 * (https://www.revenuecat.com/docs/api-v2/purchase#tag/Purchase/operation/search-purchases), or by its RevenueCat
 * id when no order was kept (https://www.revenuecat.com/docs/api-v2/purchase#tag/Purchase/operation/get-purchase).
 */
export type BundlePurchase = { id: string; bundle: BundleKey; refunded: boolean; quantity: number; order: string; usd_cents: number; purchased_at: number };
export type BundleRead = { ok: true; purchases: BundlePurchase[] } | { ok: false; reason: string };

/** Play lets a player buy a few of one consumable at once (multi-quantity); each pays its Pollen, never a second first gift. */
export const MAX_QUANTITY = 10;
/** A Google Play order number as RevenueCat reports it (store_purchase_identifier, "GPA.…"): what a bundle is paid once by. */
export const ORDER_PATTERN = /^[A-Za-z0-9_.:-]{1,128}$/;
/** The order as text ("" when none or malformed): the docs' sample shows it as a number though the schema says string. */
function orderOf(value: unknown): string {
  const text = typeof value === "string" ? value : typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? String(value) : "";
  return ORDER_PATTERN.test(text) ? text : "";
}

/** One listed purchase as the bundles see it, or null for one that never counts. */
export function bundlePurchase(item: unknown, products: Readonly<Record<string, BundleKey>>, environment: string = APP.playEnvironment, bundles: Bundles = BUNDLES): BundlePurchase | null {
  if (!isObject(item) || item.object !== "purchase" || typeof item.id !== "string" || !SUB_ID_PATTERN.test(item.id)) return null;
  if (item.store !== "play_store" || item.environment !== environment || item.ownership !== "purchased" || typeof item.product_id !== "string" || !Object.hasOwn(products, item.product_id)) return null;
  if (item.status !== "owned" && item.status !== "refunded") return null;
  const quantity = item.quantity === undefined || item.quantity === null ? 1 : item.quantity;
  if (typeof quantity !== "number" || !Number.isSafeInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY) return null;
  if (typeof item.purchased_at !== "number" || !Number.isSafeInteger(item.purchased_at) || item.purchased_at <= 0) return null;
  const bundle = products[item.product_id];
  const order = orderOf(item.store_purchase_identifier);
  const gross = isObject(item.revenue_in_usd) ? item.revenue_in_usd.gross : undefined;
  const usd = typeof gross === "number" && Number.isFinite(gross) && gross >= 0 && gross <= 10_000 ? Math.round(gross * 100) : bundles.bundles[bundle].usd_cents * quantity;
  return { id: item.id, bundle, refunded: item.status === "refunded", quantity, order, usd_cents: usd, purchased_at: item.purchased_at };
}

/** RevenueCat product id -> bundle, from the table. */
export function bundleProducts(bundles: Bundles = BUNDLES): Record<string, BundleKey> {
  return Object.fromEntries(BUNDLE_KEYS.map(key => [bundles.bundles[key].revenuecat_product, key]));
}

/** The project's REST v2 base and key, or null while unconfigured. */
function project(env: ServerVars): { base: string; key: string } | null {
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

/** The player's counted bundle purchases, oldest first. */
export async function readBundles(playerId: string, env: ServerVars, request: ProviderFetch = revenuecatRequest): Promise<BundleRead> {
  const products = bundleProducts(), at = project(env);
  if (at === null) return { ok: false, reason: "unconfigured" };
  const items = listItems(await request(`${at.base}/customers/${encodeURIComponent(playerId)}/purchases?environment=${APP.playEnvironment}&limit=100`, at.key));
  if (typeof items === "string") return { ok: false, reason: items };
  const purchases = items.flatMap(item => { const each = bundlePurchase(item, products); return each ? [each] : []; });
  purchases.sort((a, b) => a.purchased_at - b.purchased_at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return { ok: true, purchases };
}

/** A paid bundle the refund check asks about: the ledger's own purchase id, bundle and Play order ("" when none was kept). */
export type BundleAsk = { id: string; bundle: BundleKey; order: string };
/** The asked purchases RevenueCat reports refunded now, by the ledger's purchase id; { ok: false } when any lookup failed. */
export type BundleLookup = { ok: true; refunded: string[] } | { ok: false; reason: string };

/** Whether `item` is the asked purchase: the same order (or, without one, the same RevenueCat id), counted by bundlePurchase() as the same bundle. */
function samePurchase(item: unknown, ask: BundleAsk, products: Readonly<Record<string, BundleKey>>): boolean {
  if (!isObject(item)) return false;
  if (ask.order ? orderOf(item.store_purchase_identifier) !== ask.order : item.id !== ask.id) return false;
  return bundlePurchase(item, products)?.bundle === ask.bundle;
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
    if (ask.order) return listItems(await request(`${at.base}/purchases?store_purchase_identifier=${encodeURIComponent(ask.order)}`, at.key));
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
