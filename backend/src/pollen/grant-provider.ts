import { isObject } from "../protocol";
import { flags, type ServerVars } from "../flags";
import { PRODUCT_PATTERN, productList, revenuecatRequest, type ProviderResult } from "../play-entitlement";
import { SUB_ID_PATTERN, type GrantStatus, type GrantSub } from "./grant";

/**
 * The grant's own read of RevenueCat (REST v2, the same customer subscriptions list the hosting check
 * reads, with the existing key), and its own status filter. Only these count:
 * - a Full Journey subscription product the server is configured with (Play, and the App Store while
 *   that check is on), in its store and the environment below, owned by purchase (never family shared);
 * - status "active" with gives_access as paid; "trialing" as a trial; "in_grace_period" as grace;
 *   "in_billing_retry", "paused", "unknown" and "incomplete" (and "active" without access) as a hold;
 *   "expired" as ended. The hosting check admits trials, grace and testers; this never pays for them.
 * Tester and review grants are not subscriptions, so they never appear here.
 *
 * Environments: Play reads REVENUECAT_PLAY_ENVIRONMENT (production when unset), as the hosting check.
 * The App Store reads production, or sandbox only when REVENUECAT_APP_STORE_ENVIRONMENT is exactly
 * "sandbox": its "both" lets App Review host, but the grant never pays a sandbox purchase there.
 *
 * Any failed, unconfigured or partial read answers { ok: false }: nothing is paid or taken back on it.
 * The subscription `id` is RevenueCat's own, kept through renewals (a renewal is not a new subscription),
 * which is what PollenClaims keys on.
 */
export type GrantRead = { ok: true; subs: GrantSub[]; lifetime: { id: string } | null } | { ok: false; reason: string };
export type ProviderFetch = (url: string, key: string) => Promise<ProviderResult>;

type Store = { store: "play_store" | "app_store"; products: string[]; environment: string };
const ENVIRONMENTS = ["production", "sandbox"];

function stores(env: ServerVars): Store[] | null {
  const play = productList(env.REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS), playEnvironment = env.REVENUECAT_PLAY_ENVIRONMENT ?? "production";
  if (play === null || !ENVIRONMENTS.includes(playEnvironment)) return null;
  const out: Store[] = play.length ? [{ store: "play_store", products: play, environment: playEnvironment }] : [];
  if (flags.appStoreEntitlements(env)) {
    const app = productList(env.REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS);
    if (app === null) return null;
    if (app.length) out.push({ store: "app_store", products: app, environment: env.REVENUECAT_APP_STORE_ENVIRONMENT === "sandbox" ? "sandbox" : "production" });
  }
  return out;
}

const time = (value: unknown): number | null => typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : null;
const STATUS: Readonly<Record<string, GrantStatus>> = { trialing: "trial", in_grace_period: "grace", in_billing_retry: "hold", paused: "hold", unknown: "hold", incomplete: "hold", expired: "ended" };

/** One listed subscription as the grant sees it, or null for one it never counts. */
export function grantSub(item: unknown, store: Store): GrantSub | null {
  if (!isObject(item) || item.object !== "subscription" || typeof item.id !== "string" || !SUB_ID_PATTERN.test(item.id)) return null;
  if (item.store !== store.store || item.environment !== store.environment || item.ownership !== "purchased" || typeof item.product_id !== "string" || !store.products.includes(item.product_id)) return null;
  const start = time(item.current_period_starts_at);
  if (start === null || typeof item.status !== "string") return null;
  const periodEnd = time(item.current_period_ends_at), endsAt = time(item.ends_at), end = Math.max(start, periodEnd ?? endsAt ?? start);
  const status: GrantStatus = item.status === "active" ? (item.gives_access === true ? "paid" : "hold") : STATUS[item.status] ?? "hold";
  return { id: item.id, status, started_at: Math.min(start, time(item.starts_at) ?? start), period_start: start, period_end: end, ends_at: Math.max(start, endsAt ?? end),
    renews: item.auto_renewal_status !== "will_not_renew" && item.auto_renewal_status !== "will_pause",
    access_until: item.gives_access === true ? Math.max(end, endsAt ?? 0) : 0 };
}

function list(result: ProviderResult): unknown[] | string {
  if (!result.ok) return result.reason;
  if (result.status === 404) return [];
  const value = result.value;
  if (!isObject(value) || value.object !== "list" || !Array.isArray(value.items) || value.items.length > 100) return "provider_invalid_list";
  return value.next_page ? "provider_incomplete_list" : value.items;
}

/**
 * The player's counted subscriptions, and with `lifetime` the old Lifetime unlock if they own it
 * (one more read, made only for a player whose noted Full Journey has no end).
 */
export async function readGrant(playerId: string, env: ServerVars, lifetime: boolean, request: ProviderFetch = revenuecatRequest): Promise<GrantRead> {
  const configured = stores(env);
  if (env.REVENUECAT_VERIFICATION_MODE !== "play_store" || !env.REVENUECAT_SECRET_KEY || !/^[A-Za-z0-9_-]{4,100}$/.test(env.REVENUECAT_PROJECT_ID ?? "") || configured === null)
    return { ok: false, reason: "unconfigured" };
  const key = env.REVENUECAT_SECRET_KEY;
  const base = `https://api.revenuecat.com/v2/projects/${encodeURIComponent(env.REVENUECAT_PROJECT_ID!)}/customers/${encodeURIComponent(playerId)}`;
  const subs: GrantSub[] = [];
  for (const environment of [...new Set(configured.map(store => store.environment))]) {
    const items = list(await request(`${base}/subscriptions?environment=${environment}&limit=100`, key));
    if (typeof items === "string") return { ok: false, reason: items };
    for (const store of configured.filter(each => each.environment === environment))
      for (const item of items) { const sub = grantSub(item, store); if (sub) subs.push(sub); }
  }
  let owned: { id: string } | null = null;
  const product = env.REVENUECAT_PLAY_PRODUCT_ID ?? "", environment = env.REVENUECAT_PLAY_ENVIRONMENT ?? "production";
  if (lifetime && PRODUCT_PATTERN.test(product)) {
    const items = list(await request(`${base}/purchases?environment=${environment}&limit=100`, key));
    if (typeof items === "string") return { ok: false, reason: items };
    const purchase = items.find(item => isObject(item) && item.object === "purchase" && item.product_id === product && item.store === "play_store" && item.environment === environment &&
      item.status === "owned" && item.ownership === "purchased" && typeof item.id === "string" && SUB_ID_PATTERN.test(item.id));
    owned = isObject(purchase) ? { id: purchase.id as string } : null;
  }
  return { ok: true, subs, lifetime: owned };
}
