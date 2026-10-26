import { isObject } from "./protocol";
import type { ServerVars } from "./flags";
import { PRODUCT_PATTERN, grantEnd, productList, revenuecatRequest, reviewer, type PlayEntitlementConfig, type ProviderResult } from "./play-entitlement";

/**
 * Play plus App Store hosting check. entitlement.ts selects it only when
 * REVENUECAT_VERIFICATION_MODE=play_store and APP_STORE_ENTITLEMENTS_ENABLED=true;
 * every other configuration runs playEntitlement unchanged.
 */
export type StoreEntitlementConfig = PlayEntitlementConfig &
  Pick<ServerVars, "REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS" | "REVENUECAT_APP_STORE_ENVIRONMENT" | "REVENUECAT_APP_STORE_ENTITLEMENT_LOOKUP_ID">;
export type StoreEntitlementResult = {
  full_journey: boolean; status: "verified" | "unconfigured" | "unavailable"; reason?: string;
  access_source?: "review_grant" | "play_purchase" | "play_subscription" | "app_store_subscription";
  entitlement?: "full_journey_play" | "full_journey"; player_id?: string;
};
type Admission = Required<Pick<StoreEntitlementResult, "access_source" | "entitlement">>;
/** One store's answer before the stores are combined. */
type StoreOutcome = { admitted: Admission } | { refused: true } | { held: "unconfigured" } | { held: "unavailable"; reason: string };

const ENVIRONMENTS = ["production", "sandbox"];
const LOOKUP_PATTERN = /^entl[A-Za-z0-9_-]+$/;
/** Subscription states RevenueCat reports as still paid for, including the billing grace period. */
const SUBSCRIPTION_ACCESS_STATUSES = ["active", "trialing", "in_grace_period"];

/** Unset means both environments, production first. Any other value but the three holds App Store hosts. */
function appStoreEnvironments(raw: string | undefined): string[] | null {
  if (raw === undefined || raw === "both") return ENVIRONMENTS;
  return ENVIRONMENTS.includes(raw) ? [raw] : null;
}
type ProviderList = { ok: true; items: unknown[]; incomplete: boolean } | { ok: false; reason: string };
/** A 404 is an absent customer, so an empty and complete list. */
function providerList(result: ProviderResult): ProviderList {
  if (!result.ok) return { ok: false, reason: result.reason };
  if (result.status === 404) return { ok: true, items: [], incomplete: false };
  const list = result.value;
  if (!isObject(list) || list.object !== "list" || !Array.isArray(list.items) || list.items.length > 100) return { ok: false, reason: "provider_invalid_list" };
  return { ok: true, items: list.items, incomplete: Boolean(list.next_page) };
}
function subscribed(items: unknown[], store: "play_store" | "app_store", products: string[], environment: string): boolean {
  return items.some(item => isObject(item) && item.object === "subscription" && typeof item.product_id === "string" && products.includes(item.product_id) &&
    item.store === store && item.environment === environment && item.ownership === "purchased" && item.gives_access === true &&
    typeof item.status === "string" && SUBSCRIPTION_ACCESS_STATUSES.includes(item.status));
}

/** This policy is selected by server configuration, never a caller header. */
/** `onGrant`: as in entitlement.ts, the end of the first active Full Journey entitlement (Play's lookup, then the App Store's). */
export async function storeEntitlement(playerId: string, config: StoreEntitlementConfig, onGrant?: (until: number) => void): Promise<StoreEntitlementResult> {
  if (!config.REVENUECAT_SECRET_KEY || !/^[A-Za-z0-9_-]{4,100}$/.test(config.REVENUECAT_PROJECT_ID ?? "")) return { full_journey: false, status: "unconfigured" };
  const key = config.REVENUECAT_SECRET_KEY;
  const playLookup = config.REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID ?? "";
  const playEnvironment = config.REVENUECAT_PLAY_ENVIRONMENT ?? "production";
  const playSubscriptions = productList(config.REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS);
  const playReady = PRODUCT_PATTERN.test(config.REVENUECAT_PLAY_PRODUCT_ID ?? "") && ENVIRONMENTS.includes(playEnvironment) && playSubscriptions !== null;
  const appLookup = (config.REVENUECAT_APP_STORE_ENTITLEMENT_LOOKUP_ID ?? "").trim() ? config.REVENUECAT_APP_STORE_ENTITLEMENT_LOOKUP_ID! : playLookup;
  const appEnvironments = appStoreEnvironments(config.REVENUECAT_APP_STORE_ENVIRONMENT);
  const appSubscriptions = productList(config.REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS);
  // The flag is on, so an unset App Store list is a missing setting, not "no App Store products".
  const appReady = appEnvironments !== null && appSubscriptions !== null && appSubscriptions.length > 0;
  const lookups = [playLookup, appLookup].filter(value => LOOKUP_PATTERN.test(value));
  if (lookups.length === 0) return { full_journey: false, status: "unconfigured" };

  const base = `https://api.revenuecat.com/v2/projects/${encodeURIComponent(config.REVENUECAT_PROJECT_ID!)}/customers/${encodeURIComponent(playerId)}`;
  const active = providerList(await revenuecatRequest(`${base}/active_entitlements?limit=100`, key));
  /** Per lookup ID: active, refused (absent or expired), or held. */
  const grant = (lookup: string): StoreOutcome | "active" => {
    if (!LOOKUP_PATTERN.test(lookup)) return { held: "unconfigured" };
    if (!active.ok) return { held: "unavailable", reason: active.reason };
    const entry = active.items.find(item => isObject(item) && item.entitlement_id === lookup);
    if (!isObject(entry)) return active.incomplete ? { held: "unavailable", reason: "provider_incomplete_list" } : { refused: true };
    return entry.expires_at === null || (typeof entry.expires_at === "number" && Number.isFinite(entry.expires_at) && entry.expires_at > Date.now()) ? "active" : { refused: true };
  };
  const playGrant = grant(playLookup);
  const appGrant = grant(appLookup);
  if (onGrant && active.ok) {
    const lookup = playGrant === "active" ? playLookup : appGrant === "active" ? appLookup : null;
    const entry = lookup === null ? undefined : active.items.find(item => isObject(item) && item.entitlement_id === lookup);
    if (isObject(entry)) onGrant(grantEnd(entry.expires_at));
  }
  // Without any Full Journey grant the host is plainly unpaid, whatever a store's product settings say.
  if (playGrant !== "active" && appGrant !== "active") return combine([playGrant, appGrant], playerId);

  // One subscriptions read per environment, shared by both stores.
  const subscriptionReads = new Map<string, Promise<ProviderList>>();
  const subscriptionsIn = (environment: string) => {
    let read = subscriptionReads.get(environment);
    if (!read) { read = revenuecatRequest(`${base}/subscriptions?environment=${environment}&limit=100`, key).then(providerList); subscriptionReads.set(environment, read); }
    return read;
  };

  const outcomes: StoreOutcome[] = [];
  // Play first, so a Play host makes the same provider reads as under playEntitlement.
  if (playGrant !== "active") outcomes.push(playGrant);
  else if (!playReady) outcomes.push({ held: "unconfigured" });
  else {
    if (reviewer(config, playerId))
      return admitted({ access_source: "review_grant", entitlement: "full_journey_play" }, playerId);
    const purchases = providerList(await revenuecatRequest(`${base}/purchases?environment=${playEnvironment}&limit=100`, key));
    if (!purchases.ok) outcomes.push({ held: "unavailable", reason: purchases.reason });
    else {
      const owned = purchases.items.some(item => isObject(item) && item.object === "purchase" && item.product_id === config.REVENUECAT_PLAY_PRODUCT_ID &&
        item.store === "play_store" && item.environment === playEnvironment && item.status === "owned" && item.ownership === "purchased" &&
        typeof item.purchased_at === "number" && Number.isSafeInteger(item.purchased_at) && item.purchased_at > 0 && item.purchased_at <= Date.now());
      if (owned) return admitted({ access_source: "play_purchase", entitlement: "full_journey_play" }, playerId);
      if (playSubscriptions!.length === 0) outcomes.push(purchases.incomplete ? { held: "unavailable", reason: "provider_incomplete_list" } : { refused: true });
      else {
        const plans = await subscriptionsIn(playEnvironment);
        if (!plans.ok) outcomes.push({ held: "unavailable", reason: plans.reason });
        else if (subscribed(plans.items, "play_store", playSubscriptions!, playEnvironment)) return admitted({ access_source: "play_subscription", entitlement: "full_journey_play" }, playerId);
        else outcomes.push(purchases.incomplete || plans.incomplete ? { held: "unavailable", reason: "provider_incomplete_list" } : { refused: true });
      }
    }
  }
  if (appGrant !== "active") outcomes.push(appGrant);
  else if (!appReady) outcomes.push({ held: "unconfigured" });
  else {
    // Production first (usually the read Play already made); sandbox is read only if production did not admit.
    // A failed read in one environment never blocks an admission from the other.
    let held: StoreOutcome | null = null;
    for (const environment of appEnvironments!) {
      const plans = await subscriptionsIn(environment);
      if (!plans.ok) { held ??= { held: "unavailable", reason: plans.reason }; continue; }
      if (subscribed(plans.items, "app_store", appSubscriptions!, environment))
        return admitted({ access_source: "app_store_subscription", entitlement: appLookup === playLookup ? "full_journey_play" : "full_journey" }, playerId);
      if (plans.incomplete) held ??= { held: "unavailable", reason: "provider_incomplete_list" };
    }
    outcomes.push(held ?? { refused: true });
  }
  return combine(outcomes, playerId);
}

function admitted(admission: Admission, playerId: string): StoreEntitlementResult {
  return { full_journey: true, status: "verified", ...admission, player_id: playerId };
}
/** A store setting problem holds as `unconfigured`, then a failed or partial read as `unavailable`; only clean refusals give `verified`. */
function combine(outcomes: StoreOutcome[], playerId: string): StoreEntitlementResult {
  for (const outcome of outcomes) if ("admitted" in outcome) return admitted(outcome.admitted, playerId);
  if (outcomes.some(outcome => "held" in outcome && outcome.held === "unconfigured")) return { full_journey: false, status: "unconfigured" };
  for (const outcome of outcomes) if ("held" in outcome && outcome.held === "unavailable") return { full_journey: false, status: "unavailable", reason: outcome.reason };
  return { full_journey: false, status: "verified" };
}
