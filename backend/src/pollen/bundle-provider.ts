import { isObject } from "../protocol";
import type { ServerVars } from "../flags";
import { APP, BUNDLE_KEYS, PROJECT_PATTERN, serverConfig, type BundleKey } from "../config";
import { revenuecatRequest } from "../play-entitlement";
import { BUNDLES, type Bundles } from "./bundles";
import { SUB_ID_PATTERN } from "./grant";
import type { ProviderFetch } from "./grant-provider";

/**
 * The bundles' read of RevenueCat: the customer's one-time purchases (REST v2, the same list and key the
 * hosting check reads), filtered to real Pollen only. A purchase counts when it is:
 * - a Play Store purchase in production (APP.playEnvironment), owned by purchase (never family shared);
 * - of one of the four configured bundle products (CONFIG revenuecat.play_bundle_product_ids);
 * - with a RevenueCat id, a quantity from 1 to MAX_QUANTITY and a purchase time.
 * Test Store, sandbox, promotional, App Store and any other product mint nothing.
 * Status "owned" is paid once; "refunded" takes back what it paid.
 *
 * Any failed, unconfigured, malformed or partial read answers { ok: false }: nothing is credited or taken back on it.
 */
export type BundlePurchase = { id: string; bundle: BundleKey; refunded: boolean; quantity: number; order: string; usd_cents: number; purchased_at: number };
export type BundleRead = { ok: true; purchases: BundlePurchase[] } | { ok: false; reason: string };

/** Play lets a player buy a few of one consumable at once (multi-quantity); each pays its Pollen, never a second first gift. */
export const MAX_QUANTITY = 10;
const ORDER_PATTERN = /^[A-Za-z0-9_.:-]{1,128}$/;

/** One listed purchase as the bundles see it, or null for one that never counts. */
export function bundlePurchase(item: unknown, products: Readonly<Record<string, BundleKey>>, environment: string = APP.playEnvironment, bundles: Bundles = BUNDLES): BundlePurchase | null {
  if (!isObject(item) || item.object !== "purchase" || typeof item.id !== "string" || !SUB_ID_PATTERN.test(item.id)) return null;
  if (item.store !== "play_store" || item.environment !== environment || item.ownership !== "purchased" || typeof item.product_id !== "string" || !Object.hasOwn(products, item.product_id)) return null;
  if (item.status !== "owned" && item.status !== "refunded") return null;
  const quantity = item.quantity === undefined || item.quantity === null ? 1 : item.quantity;
  if (typeof quantity !== "number" || !Number.isSafeInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY) return null;
  if (typeof item.purchased_at !== "number" || !Number.isSafeInteger(item.purchased_at) || item.purchased_at <= 0) return null;
  const bundle = products[item.product_id];
  const order = typeof item.store_purchase_identifier === "string" && ORDER_PATTERN.test(item.store_purchase_identifier) ? item.store_purchase_identifier : "";
  const gross = isObject(item.revenue_in_usd) ? item.revenue_in_usd.gross : undefined;
  const usd = typeof gross === "number" && Number.isFinite(gross) && gross >= 0 && gross <= 10_000 ? Math.round(gross * 100) : bundles.bundles[bundle].usd_cents * quantity;
  return { id: item.id, bundle, refunded: item.status === "refunded", quantity, order, usd_cents: usd, purchased_at: item.purchased_at };
}

/** RevenueCat product id -> bundle, or null while the map is unset or malformed. */
export function bundleProducts(env: ServerVars): Record<string, BundleKey> | null {
  const map = serverConfig(env).revenuecat.play_bundle_product_ids;
  if (!map) return null;
  return Object.fromEntries(BUNDLE_KEYS.map(key => [map[key], key]));
}

/** The player's counted bundle purchases, oldest first. */
export async function readBundles(playerId: string, env: ServerVars, request: ProviderFetch = revenuecatRequest): Promise<BundleRead> {
  const products = bundleProducts(env), project = serverConfig(env).revenuecat.project_id ?? "";
  if (!env.REVENUECAT_SECRET_KEY || !PROJECT_PATTERN.test(project) || products === null) return { ok: false, reason: "unconfigured" };
  const url = `https://api.revenuecat.com/v2/projects/${encodeURIComponent(project)}/customers/${encodeURIComponent(playerId)}/purchases?environment=${APP.playEnvironment}&limit=100`;
  const result = await request(url, env.REVENUECAT_SECRET_KEY);
  if (!result.ok) return { ok: false, reason: result.reason };
  if (result.status === 404) return { ok: true, purchases: [] };
  const value = result.value;
  if (!isObject(value) || value.object !== "list" || !Array.isArray(value.items) || value.items.length > 100) return { ok: false, reason: "provider_invalid_list" };
  if (value.next_page) return { ok: false, reason: "provider_incomplete_list" };
  const purchases = value.items.flatMap(item => { const each = bundlePurchase(item, products); return each ? [each] : []; });
  purchases.sort((a, b) => a.purchased_at - b.purchased_at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return { ok: true, purchases };
}
