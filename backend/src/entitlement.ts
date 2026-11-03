import { flags, type ServerVars } from "./flags";
import { APP } from "./config";
import { playEntitlement } from "./play-entitlement";
import { appStoreReady, storeEntitlement } from "./store-entitlement";
import { clientHeader } from "./app-status";
import { isTester, switchApplies } from "./test-codes";
import { HOST_ACCESS_FRESH_MS } from "./v2/host-access";

export type Entitlement = { full_journey: boolean; status: "verified" | "unconfigured" | "unavailable"; environment: string; checked_at: string; reason?: string; access_source?: "review_grant" | "play_purchase" | "play_subscription" | "app_store_subscription" | "tester_grant" | "tester_switched_off"; entitlement?: "full_journey_play" | "full_journey"; player_id?: string };
/**
 * The Full Journey check: a tester's switch (test-codes.ts) answers "verified, not entitled" with no provider call
 * while it is on, whatever they own; else a stored tester grant, else RevenueCat's record of a real store purchase (Play, plus the
 * App Store while APP_STORE_ENTITLEMENTS_ENABLED is on). Without REVENUECAT_SECRET_KEY and CONFIG's RevenueCat ids
 * the answer is "unconfigured", which holds hosting (503) rather than refusing it.
 *
 * `onGrant`, when given, hears the end of the Full Journey entitlement RevenueCat reported active
 * (ms; null ends, a lifetime unlock, as 8.64e15), before any later admission step. The answer itself
 * never carries it, so every reply stays as it was. Pollen's room boost reads it (pollen/routes.ts paidUntil).
 */
/** `beforeProvider`: runs only when the check is about to ask RevenueCat (GET /v1/entitlement spends its costly bucket there). */
export async function entitlement(playerId: string, env: ServerVars & { PLAYERS?: Env["PLAYERS"] }, onGrant?: (until: number) => void, beforeProvider?: () => Promise<void>): Promise<Entitlement> {
  const base = { full_journey: false, environment: APP.environment, checked_at: new Date().toISOString() };
  // A tester is checked every time, so their switch and Play sandbox subscription hold at once.
  const memoized = env.PLAYERS !== undefined && !isTester(env, playerId);
  if (env.PLAYERS) {
    const { grant, full_journey_off, memo } = await env.PLAYERS.getByName(playerId).storedAccess(playerId);
    if (full_journey_off && switchApplies(env, playerId)) return { ...base, status: "verified", access_source: "tester_switched_off", player_id: playerId };
    if (grant) return { ...base, full_journey: true, status: "verified", access_source: "tester_grant", entitlement: "full_journey", player_id: playerId };
    if (memo && memoized) {
      if (memo.until !== undefined) onGrant?.(memo.until);
      return { ...base, ...memo.answer, checked_at: new Date(memo.at).toISOString() };
    }
  }
  await beforeProvider?.();
  let until: number | undefined;
  const answer = flags.appStoreEntitlements(env) ? await storeEntitlement(playerId, env, value => { until = value; onGrant?.(value); }) : await playEntitlement(playerId, env, value => { until = value; onGrant?.(value); });
  // Only verified answers are remembered (entitlementFresh); a failure to remember costs nothing but the next check.
  if (memoized && answer.status === "verified") await env.PLAYERS!.getByName(playerId).noteEntitlement(playerId, { answer, at: Date.now(), ...(until !== undefined ? { until } : {}) }).catch(() => undefined);
  return { ...base, ...answer };
}

/**
 * A verified provider check, remembered in the player's Player memory (never stored) so the next checks make no
 * RevenueCat call. One that found Full Journey holds for HOST_ACCESS_FRESH_MS, the same window a room already trusts
 * its host's check for (v2/host-access.ts), and ends sooner at the entitlement's own end (`until`); a refund shows
 * within the same quarter of an hour as a room's memo. One that found none holds only NEGATIVE_FRESH_MS, so a purchase
 * shows within seconds while repeated premium turns or creates cannot call RevenueCat at the request rate. Either goes
 * with the tester switch or a deletion.
 */
export type EntitlementMemo = { answer: Omit<Entitlement, "environment" | "checked_at">; at: number; until?: number };
export const NEGATIVE_FRESH_MS = 10_000;
export function entitlementFresh(memo: EntitlementMemo, now: number): boolean {
  if (now < memo.at) return false;
  if (!memo.answer.full_journey) return now - memo.at < NEGATIVE_FRESH_MS;
  return now - memo.at < HOST_ACCESS_FRESH_MS && (memo.until === undefined || memo.until > now);
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
