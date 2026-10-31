import { flags, type ServerVars } from "./flags";
import { APP } from "./config";
import { playEntitlement } from "./play-entitlement";
import { appStoreReady, storeEntitlement } from "./store-entitlement";
import { clientHeader } from "./app-status";

export type Entitlement = { full_journey: boolean; status: "verified" | "unconfigured" | "unavailable"; environment: string; checked_at: string; reason?: string; access_source?: "review_grant" | "play_purchase" | "play_subscription" | "app_store_subscription" | "tester_grant"; entitlement?: "full_journey_play" | "full_journey"; player_id?: string };
/**
 * The Full Journey check: a stored tester grant, else RevenueCat's record of a real store purchase (Play, plus the
 * App Store while APP_STORE_ENTITLEMENTS_ENABLED is on). Without REVENUECAT_SECRET_KEY and CONFIG's RevenueCat ids
 * the answer is "unconfigured", which holds hosting (503) rather than refusing it.
 *
 * `onGrant`, when given, hears the end of the Full Journey entitlement RevenueCat reported active
 * (ms; null ends, a lifetime unlock, as 8.64e15), before any later admission step. The answer itself
 * never carries it, so every reply stays as it was. Pollen's room boost reads it (pollen/routes.ts paidUntil).
 */
export async function entitlement(playerId: string, env: ServerVars & { PLAYERS?: Env["PLAYERS"] }, onGrant?: (until: number) => void): Promise<Entitlement> {
  const base = { full_journey: false, environment: APP.environment, checked_at: new Date().toISOString() };
  if (env.PLAYERS) {
    const grant = await env.PLAYERS.getByName(playerId).storedTesterGrant(playerId);
    if (grant) return { ...base, full_journey: true, status: "verified", access_source: "tester_grant", entitlement: "full_journey", player_id: playerId };
  }
  return { ...base, ...(flags.appStoreEntitlements(env) ? await storeEntitlement(playerId, env, onGrant) : await playEntitlement(playerId, env, onGrant)) };
}

/** The capability version of Full Journey through the App Store (store-entitlement.ts appStoreReady). */
export const APP_STORE_FULL_JOURNEY_VERSION = 1;
/**
 * GET /v2/capabilities' App Store part: sent only to an App Store build (X-AfterYou-Client names the app_store channel),
 * and only while App Store subscribers are admitted. An iPhone sells Full Journey and shows paid chapters only after a
 * read that carries it; a read without it hides them again, as on a build that sells nothing.
 */
export function storeCapability(request: Request, env: ServerVars): { app_store_full_journey_version?: number } {
  return clientHeader(request)?.channel === "app_store" && appStoreReady(env) ? { app_store_full_journey_version: APP_STORE_FULL_JOURNEY_VERSION } : {};
}
