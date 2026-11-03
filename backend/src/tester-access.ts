import { ApiError, HASH_PATTERN, boundedJson, digest, equalHash, isObject, unwrap } from "./protocol";
import { bearerDigest } from "./http";
import { flags, type ServerVars } from "./flags";
import { isTester, matchTestCode, runTestAction, type TestActionReply } from "./test-codes";
import { limitTesterCode } from "./limits";

export const TESTER_CODE_DOMAIN = "afteryou.tester-code.v1:";
export type TesterGrant = { schema_version: 1; granted_at: string };
export type TesterAccess = { schema_version: 1; granted: false; player_id: string } | {
  schema_version: 1; granted: true; access_source: "tester_grant"; entitlement: "full_journey"; player_id: string; granted_at: string;
};
export function validTesterGrant(value: unknown): value is TesterGrant {
  if (!isObject(value) || Object.keys(value).sort().join() !== "granted_at,schema_version" || value.schema_version !== 1 || typeof value.granted_at !== "string" ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value.granted_at)) return false;
  const time = Date.parse(value.granted_at);
  return Number.isFinite(time) && new Date(time).toISOString() === value.granted_at;
}
export function testerReceipt(owner: string, grant: TesterGrant | null): TesterAccess {
  return grant ? { schema_version: 1, granted: true, access_source: "tester_grant", entitlement: "full_journey", player_id: owner, granted_at: grant.granted_at } :
    { schema_version: 1, granted: false, player_id: owner };
}
/**
 * Normal authenticated caller only. The submitted code is never persisted or logged. A player in CONFIG's
 * tester list may also type a test code here (test-codes.ts); for everyone else the route is unchanged.
 */
export async function routeTesterAccess(request: Request, owner: string, env: Env & ServerVars): Promise<TesterAccess | TestActionReply> {
  if (!["GET", "POST"].includes(request.method)) throw new ApiError(405, "method_not_allowed");
  const player = env.PLAYERS.getByName(owner), deviceHash = await bearerDigest(request);
  const existing = unwrap(await player.testerAccess(owner, deviceHash));
  // A tester's every attempt spends the limiter, granted or not, since a test code works either way.
  const tester = request.method === "POST" && isTester(env, owner);
  if (request.method === "GET" || existing.granted && !tester) return existing;
  // Separate actor and edge-IP buckets bound guessing across credential rotation
  // and fresh identities. Neither code nor credentials appear in limiter keys.
  await limitTesterCode(request, env, owner);
  const body = await boundedJson(request, 1024);
  if (!isObject(body) || Object.keys(body).sort().join() !== "code,schema_version" || body.schema_version !== 1 || typeof body.code !== "string" || !/^[!-~]{8,128}$/.test(body.code)) throw new ApiError(400, "invalid_tester_request");
  if (tester) {
    const action = await matchTestCode(env, body.code);
    if (action) return runTestAction(action, owner, deviceHash, env);
    if (existing.granted) return existing;
  }
  const proposedHash = await digest(TESTER_CODE_DOMAIN + body.code);
  const accepted = flags.testerAccess(env) && typeof env.TESTER_CODE_SHA256 === "string" && HASH_PATTERN.test(env.TESTER_CODE_SHA256) && equalHash(proposedHash, env.TESTER_CODE_SHA256);
  // This binding-only Boolean comes solely from the server policy above. The
  // Player performs the original-credential check and write without an await.
  return unwrap(await player.redeemTesterAccess(owner, deviceHash, accepted));
}
