import { ApiError, HASH_PATTERN, boundedJson, digest, equalHash, isObject, type Outcome } from "./protocol";

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
function unwrap<T>(result: Outcome<T>): T { if (!result.ok) throw new ApiError(result.status, result.code); return result.value; }
/** Normal authenticated caller only. The submitted code is never persisted or logged. */
export async function routeTesterAccess(request: Request, owner: string, env: Env): Promise<TesterAccess> {
  if (!["GET", "POST"].includes(request.method)) throw new ApiError(405, "method_not_allowed");
  const player = env.PLAYERS.getByName(owner), deviceHash = await digest(request.headers.get("Authorization")!.slice(7));
  const existing = unwrap(await player.testerAccess(owner, deviceHash));
  if (request.method === "GET" || existing.granted) return existing;
  // Separate actor and edge-IP buckets bound guessing across credential rotation
  // and fresh identities. Neither code nor credentials appear in limiter keys.
  const ip = await digest(request.headers.get("CF-Connecting-IP") || "local");
  if (!(await env.TESTER_CODE_LIMITER.limit({ key: "owner:" + owner })).success ||
      !(await env.TESTER_CODE_LIMITER.limit({ key: "ip:" + ip })).success) throw new ApiError(429, "tester_rate_limited");
  const body = await boundedJson(request, 1024);
  if (!isObject(body) || Object.keys(body).sort().join() !== "code,schema_version" || body.schema_version !== 1 || typeof body.code !== "string" || !/^[!-~]{8,128}$/.test(body.code)) throw new ApiError(400, "invalid_tester_request");
  const config = env as Env & { TESTER_CODE_SHA256?: string };
  const proposedHash = await digest(TESTER_CODE_DOMAIN + body.code);
  const accepted = String(env.TESTER_ACCESS_ENABLED) === "true" && typeof config.TESTER_CODE_SHA256 === "string" && HASH_PATTERN.test(config.TESTER_CODE_SHA256) && equalHash(proposedHash, config.TESTER_CODE_SHA256);
  // This binding-only Boolean comes solely from the server policy above. The
  // Player performs the original-credential check and write without an await.
  return unwrap(await player.redeemTesterAccess(owner, deviceHash, accepted));
}
