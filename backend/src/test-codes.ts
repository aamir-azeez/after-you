import { digest, equalHash, unwrap } from "./protocol";
import { serverConfig, TEST_CODE_ACTIONS, type TestCodeAction } from "./config";
import type { ServerVars } from "./flags";

/**
 * Testers' own codes, typed in the tester code field (POST /v1/tester-access, tester-access.ts). Each code's salted
 * hash and what it does live in CONFIG's test_codes; a code works only for a player in CONFIG's
 * revenuecat.tester_ids, so for anyone else it is one more wrong tester code.
 *
 * - grant_keepsakes and reset_keepsakes change nothing here: the server only says yes, and the phone shows its
 *   keepsakes all earned or fresh (game/services/tester_switches.gd). Real progress is never written.
 * - toggle_full_journey flips a switch on the tester's Player: while it is on, every Full Journey check answers
 *   "verified, not entitled" (entitlement.ts) and rooms copy no Full Journey boost for them (player.ts). Nothing
 *   in RevenueCat or the store changes, and the monthly grant keeps following the real purchase. The switch
 *   counts only while switchApplies().
 */
export const TEST_CODE_SALT = "afteryou.test-code.v1:";
/** What the phone is told to do. The toggle answers where it now stands. */
export type TestAction = "grant_keepsakes" | "reset_keepsakes" | "full_journey_off" | "full_journey_on";
export type TestActionReply = { schema_version: 1; player_id: string; test_action: TestAction };

/** The hash CONFIG holds for `code` under `action`. The action is part of the salt, so a hash means one action only. */
export function testCodeHash(action: TestCodeAction, code: string): Promise<string> {
  return digest(TEST_CODE_SALT + action + ":" + code);
}

/** Whether `playerId` may use test codes at all: a listed tester. Reads CONFIG only. */
export function isTester(env: ServerVars, playerId: string): boolean {
  return serverConfig(env).revenuecat.tester_ids.includes(playerId);
}

/**
 * Whether a stored Full Journey switch counts: only for a listed tester while the toggle code is configured, so
 * taking either away (a new tester id, `--set test_codes=null`) gives the real Full Journey back at once, with no
 * code needed to clear it. Reads CONFIG only.
 */
export function switchApplies(env: ServerVars, playerId: string): boolean {
  return isTester(env, playerId) && serverConfig(env).test_codes.has("toggle_full_journey");
}

/** The configured action whose hash `code` matches, or null. Every configured action is checked, matched or not. */
export async function matchTestCode(env: ServerVars, code: string): Promise<TestCodeAction | null> {
  const codes = serverConfig(env).test_codes;
  let found: TestCodeAction | null = null;
  for (const action of TEST_CODE_ACTIONS) {
    const expected = codes.get(action);
    if (expected === undefined) continue;
    if (equalHash(await testCodeHash(action, code), expected)) found = action;
  }
  return found;
}

/** Carries out a matched action for an authenticated tester (the caller has checked isTester and the limiter). */
export async function runTestAction(action: TestCodeAction, owner: string, deviceHash: string, env: Env): Promise<TestActionReply> {
  if (action === "toggle_full_journey") {
    const { full_journey_off } = unwrap(await env.PLAYERS.getByName(owner).toggleFullJourneyOff(owner, deviceHash));
    return { schema_version: 1, player_id: owner, test_action: full_journey_off ? "full_journey_off" : "full_journey_on" };
  }
  // A keepsake code writes nothing here. The Player checks the credential again after the limiter's wait, as a
  // redemption does, so a device revoked meanwhile learns nothing.
  unwrap(await env.PLAYERS.getByName(owner).testerAccess(owner, deviceHash));
  return { schema_version: 1, player_id: owner, test_action: action };
}

/**
 * GET /v2/capabilities' part for a tester whose Full Journey switch is on: `full_journey_off: true`, which the phone
 * reads as "treat me as without Full Journey". Only a listed tester costs the one Player read; everyone else, and a
 * tester with the switch off, gets the same bytes as before.
 */
export async function testerSwitchCapability(playerId: string, env: Env): Promise<{ full_journey_off?: true }> {
  if (!switchApplies(env, playerId)) return {};
  return (await env.PLAYERS.getByName(playerId).storedAccess(playerId)).full_journey_off ? { full_journey_off: true } : {};
}
