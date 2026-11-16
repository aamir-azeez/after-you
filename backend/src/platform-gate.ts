import { clientReach } from "./app-status";
import { serverConfig } from "./config";
import { FLAG_VARS, gatedOn, type ServerVars } from "./flags";

/** A phone that asks about platform games sends this (platform-routes.ts capability). */
export const PLATFORM_HEADER = "X-AfterYou-Platform-Games";

/**
 * The platform account rule for online writes, behind REQUIRE_PLATFORM (config.ts GATED_KEYS, so CONFIG's
 * feature_min_version turns it on for apps at a version or newer): a write from a player with no Play Games or
 * Game Center link answers 403 platform_required, so throwaway identities cannot play online, post, trade or spend.
 *
 * Cost: none per request. Whether a player is linked rides on the identity row auth() already reads
 * (Player `platform_linked`), written only when a link is made, moved, removed or restored (platform-routes.ts).
 *
 * Never gated: reads; the identity itself (create, recover, delete, its deletion acknowledgement), so a player can
 * always leave (Apple 5.1.1(v), Google Play account deletion); linking and restoring, the way in; bundle claims, so a
 * paid Pollen or Fruit pack is always delivered; safety reports and blocks; push registration; photo transfer between
 * the player's own phones; and tester codes. Testers and the App Review identity (CONFIG revenuecat.tester_ids and
 * reviewer_ids) are never gated, and the capability tells their phones so (platform_exempt).
 */
export const PLATFORM_REQUIRED = "platform_required";
const READS = new Set(["GET", "HEAD", "OPTIONS"]);
const OPEN_PREFIXES = ["/v1/identity", "/v1/platform/", "/v1/safety/", "/v1/notifications/", "/v1/photo-transfer", "/v1/tester-access"];
const OPEN_PATHS = new Set(["/v1/pollen/bundle-claims"]);

/** Whether this request is an online write the rule covers. */
export function gatedWrite(request: Request, path: string): boolean {
  if (READS.has(request.method)) return false;
  return !OPEN_PATHS.has(path) && !OPEN_PREFIXES.some(prefix => path === prefix || path.startsWith(prefix.endsWith("/") ? prefix : prefix + "/"));
}

/** Whether the rule is on for this request's app. */
export function platformRequired(request: Request, env: ServerVars): boolean {
  return gatedOn(env, FLAG_VARS.requirePlatform, clientReach(request));
}

/**
 * Whether auth() needs the player's mark on a route whose identity check otherwise reads nothing more (Player.authorize):
 * only while the rule is on, for a gated write or the platform capability. Every other request makes the same call as before.
 */
export function wantsPlatform(request: Request, path: string, env: ServerVars): boolean {
  return platformRequired(request, env) && (gatedWrite(request, path) || request.headers.get(PLATFORM_HEADER) === "1");
}

/** Testers and the App Review identity play without a platform account. */
export function platformExempt(env: ServerVars, playerId: string): boolean {
  const settings = serverConfig(env).revenuecat;
  return settings.tester_ids.includes(playerId) || settings.reviewer_ids.includes(playerId);
}

/** The capability fields for a phone that asked about platform games (platform-routes.ts platformCapability). */
export function platformRuleCapability(request: Request, env: ServerVars, playerId: string, linked: boolean): Record<string, number | boolean> {
  if (!platformRequired(request, env)) return {};
  return { platform_required_version: 1, platform_linked: linked, ...(platformExempt(env, playerId) ? { platform_exempt: true } : {}) };
}
