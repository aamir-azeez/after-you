import { ApiError, SECRET_PATTERN, digest, equalHash } from "./protocol";
import type { ServerVars } from "./flags";

/** The operator credential check every /operator/ route runs first. A player credential never passes it. */
export async function requireOperator(request: Request, env: ServerVars): Promise<void> {
  const secret = env.SAFETY_OPERATOR_TOKEN;
  const authorization = request.headers.get("Authorization");
  if (!secret || !SECRET_PATTERN.test(secret) || !authorization?.startsWith("Bearer ") || !SECRET_PATTERN.test(authorization.slice(7)) || !equalHash(await digest(secret), await digest(authorization.slice(7)))) throw new ApiError(401, "invalid_operator_auth");
}
