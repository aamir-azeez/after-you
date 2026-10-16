import { isObject, readBounded } from "./protocol";
import { commaList, type ServerVars } from "./flags";

export type PlayEntitlementConfig = Pick<ServerVars, "REVENUECAT_SECRET_KEY" | "REVENUECAT_PROJECT_ID" | "REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID" |
  "REVENUECAT_PLAY_PRODUCT_ID" | "REVENUECAT_PLAY_ENVIRONMENT" | "REVENUECAT_REVIEWER_IDS" | "REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS">;
export const PRODUCT_PATTERN = /^prod[A-Za-z0-9_-]+$/;
/** Unset or blank gives []; a set but malformed list gives null, so the check holds (unconfigured) rather than refusing every subscriber. */
export function productList(raw: string | undefined): string[] | null {
  const values = commaList(raw);
  if ((raw ?? "").trim() && (values.length > 8 || !values.every(value => PRODUCT_PATTERN.test(value)))) return null;
  return values;
}
/** True when playerId is on a well-formed reviewer list of at most 16 IDs. */
export function reviewer(config: Pick<ServerVars, "REVENUECAT_REVIEWER_IDS">, playerId: string): boolean {
  const reviewers = commaList(config.REVENUECAT_REVIEWER_IDS);
  return reviewers.length <= 16 && reviewers.every(value => /^[A-Za-z0-9_-]{22}$/.test(value)) && reviewers.includes(playerId);
}
/** Subscription states RevenueCat reports as still paid for, including the billing grace period. */
const SUBSCRIPTION_ACCESS_STATUSES = ["active", "trialing", "in_grace_period"];
export type ProviderResult = { ok: true; status: number; value: unknown } | { ok: false; reason: string };

/** Provider bodies and redirects are bounded; caller data never enters logs. */
export async function revenuecatRequest(url: string, key: string, method = "GET"): Promise<ProviderResult> {
  try {
    const response = await fetch(url, { method, redirect: "manual", signal: AbortSignal.timeout(8000), headers: { Authorization: `Bearer ${key}`, Accept: "application/json" } });
    if (method === "DELETE" && (response.status === 200 || response.status === 404)) {
      await response.body?.cancel(); return { ok: true, status: response.status, value: null };
    }
    if (response.status === 404) { await response.body?.cancel(); return { ok: true, status: 404, value: null }; }
    if (!response.ok) { await response.body?.cancel(); return { ok: false, reason: `provider_http_${response.status}` }; }
    if (!response.body) return { ok: false, reason: "provider_empty_response" };
    const bytes = await readBounded(response.body, 262144);
    if (!bytes) return { ok: false, reason: "provider_response_too_large" };
    return { ok: true, status: response.status, value: JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes)) };
  } catch { return { ok: false, reason: "provider_request_or_decode_failed" }; }
}

/** This policy is selected by server configuration, never a caller header. */
export async function playEntitlement(playerId: string, config: PlayEntitlementConfig): Promise<{ full_journey: boolean; status: "verified" | "unconfigured" | "unavailable"; reason?: string; access_source?: "review_grant" | "play_purchase" | "play_subscription"; entitlement?: "full_journey_play"; player_id?: string }> {
  const environment = config.REVENUECAT_PLAY_ENVIRONMENT ?? "production";
  if (!config.REVENUECAT_SECRET_KEY || !/^[A-Za-z0-9_-]{4,100}$/.test(config.REVENUECAT_PROJECT_ID ?? "") ||
      !/^entl[A-Za-z0-9_-]+$/.test(config.REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID ?? "") ||
      !PRODUCT_PATTERN.test(config.REVENUECAT_PLAY_PRODUCT_ID ?? "") ||
      !["production", "sandbox"].includes(environment)) return { full_journey: false, status: "unconfigured" };
  // Unset keeps one-time-only admission. A set but malformed list holds (503)
  // rather than quietly refusing every subscriber as unpaid.
  const subscriptionProducts = productList(config.REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS);
  if (subscriptionProducts === null) return { full_journey: false, status: "unconfigured" };
  const base = `https://api.revenuecat.com/v2/projects/${encodeURIComponent(config.REVENUECAT_PROJECT_ID!)}/customers/${encodeURIComponent(playerId)}`;
  const active = await revenuecatRequest(`${base}/active_entitlements?limit=100`, config.REVENUECAT_SECRET_KEY);
  if (!active.ok) return { full_journey: false, status: "unavailable", reason: active.reason };
  if (active.status === 404) return { full_journey: false, status: "verified" };
  const list = active.value;
  if (!isObject(list) || list.object !== "list" || !Array.isArray(list.items) || list.items.length > 100) return { full_journey: false, status: "unavailable", reason: "provider_invalid_list" };
  const grant = list.items.find(entry => isObject(entry) && entry.entitlement_id === config.REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID);
  if (!isObject(grant)) return { full_journey: false, status: list.next_page ? "unavailable" : "verified", ...(list.next_page ? { reason: "provider_incomplete_list" } : {}) };
  if (!(grant.expires_at === null || (typeof grant.expires_at === "number" && Number.isFinite(grant.expires_at) && grant.expires_at > Date.now()))) return { full_journey: false, status: "verified" };
  // Review access is an actual provider entitlement plus an operator-managed
  // exact identity allowlist. The allowlist alone never grants access.
  if (reviewer(config, playerId)) return { full_journey: true, status: "verified", access_source: "review_grant", entitlement: "full_journey_play", player_id: playerId };
  const purchases = await revenuecatRequest(`${base}/purchases?environment=${environment}&limit=100`, config.REVENUECAT_SECRET_KEY);
  if (!purchases.ok) return { full_journey: false, status: "unavailable", reason: purchases.reason };
  if (purchases.status === 404) return { full_journey: false, status: "verified" };
  const records = purchases.value;
  if (!isObject(records) || records.object !== "list" || !Array.isArray(records.items) || records.items.length > 100) return { full_journey: false, status: "unavailable", reason: "provider_invalid_list" };
  const owned = records.items.some(item => isObject(item) && item.object === "purchase" && item.product_id === config.REVENUECAT_PLAY_PRODUCT_ID &&
    item.store === "play_store" && item.environment === environment && item.status === "owned" && item.ownership === "purchased" &&
    typeof item.purchased_at === "number" && Number.isSafeInteger(item.purchased_at) && item.purchased_at > 0 && item.purchased_at <= Date.now());
  if (owned) return { full_journey: true, status: "verified", access_source: "play_purchase", entitlement: "full_journey_play", player_id: playerId };
  if (subscriptionProducts.length === 0)
    return { full_journey: false, status: records.next_page ? "unavailable" : "verified", ...(records.next_page ? { reason: "provider_incomplete_list" } : {}) };
  const subscriptions = await revenuecatRequest(`${base}/subscriptions?environment=${environment}&limit=100`, config.REVENUECAT_SECRET_KEY);
  if (!subscriptions.ok) return { full_journey: false, status: "unavailable", reason: subscriptions.reason };
  if (subscriptions.status === 404) return { full_journey: false, status: records.next_page ? "unavailable" : "verified", ...(records.next_page ? { reason: "provider_incomplete_list" } : {}) };
  const plans = subscriptions.value;
  if (!isObject(plans) || plans.object !== "list" || !Array.isArray(plans.items) || plans.items.length > 100) return { full_journey: false, status: "unavailable", reason: "provider_invalid_list" };
  const subscribed = plans.items.some(item => isObject(item) && item.object === "subscription" && typeof item.product_id === "string" && subscriptionProducts.includes(item.product_id) &&
    item.store === "play_store" && item.environment === environment && item.ownership === "purchased" && item.gives_access === true &&
    typeof item.status === "string" && SUBSCRIPTION_ACCESS_STATUSES.includes(item.status));
  if (subscribed) return { full_journey: true, status: "verified", access_source: "play_subscription", entitlement: "full_journey_play", player_id: playerId };
  const incomplete = Boolean(records.next_page || plans.next_page);
  return { full_journey: false, status: incomplete ? "unavailable" : "verified", ...(incomplete ? { reason: "provider_incomplete_list" } : {}) };
}
