import { ApiError, SECRET_PATTERN, digest, equalHash } from "../protocol";
import type { ServerVars } from "../flags";

/**
 * The replay job's credential, derived from SAFETY_OPERATOR_TOKEN so it needs
 * no var or secret slot of its own: HMAC-SHA256 keyed by the operator token
 * over JOB_TOKEN_LABEL, as 43 base64url characters. It opens only the job's
 * two routes (pending and verdicts); the operator token itself opens those
 * and the review routes. Rotating the operator token rotates this one too.
 * scripts/leaderboard-job-token.mjs prints it for `gh secret set`.
 */
export const JOB_TOKEN_LABEL = "after-you leaderboard replay job v1";

export async function deriveJobToken(operatorToken: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(operatorToken), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(JOB_TOKEN_LABEL)));
  return btoa(String.fromCharCode(...mac)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Which credential a request carries: "operator", "job" or neither (401). */
export async function leaderboardCaller(request: Request, env: ServerVars): Promise<"operator" | "job"> {
  const secret = env.SAFETY_OPERATOR_TOKEN, authorization = request.headers.get("Authorization");
  if (!secret || !SECRET_PATTERN.test(secret) || !authorization?.startsWith("Bearer ") || !SECRET_PATTERN.test(authorization.slice(7))) throw new ApiError(401, "invalid_operator_auth");
  const given = await digest(authorization.slice(7));
  if (equalHash(await digest(secret), given)) return "operator";
  if (equalHash(await digest(await deriveJobToken(secret)), given)) return "job";
  throw new ApiError(401, "invalid_operator_auth");
}
