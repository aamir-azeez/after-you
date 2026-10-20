import { ApiError, digest, unwrap, type Outcome } from "./protocol";

/** Headers on every API answer with a JSON body. */
export const JSON_HEADERS = Object.freeze({ "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" });
const BYTES_HEADERS = Object.freeze({ "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/octet-stream" });

export function json(value: unknown, status = 200, headers: Record<string, string> = {}): Response { return new Response(JSON.stringify(value), { status, headers: { ...JSON_HEADERS, ...headers } }); }
/**
 * The API's error answer, {error: {code, retryable}}. An ApiError keeps its status; 429 and 503 are retryable and carry
 * Retry-After (60 and 15 seconds, or the error's retry_after_seconds), plus any numeric details. Anything else is 503 with the fallback code and no Retry-After. Extra headers win.
 * Never put request bodies, credentials, invite codes or upstream payloads in it.
 */
export function errorResponse(error: unknown, headers: Record<string, string> = {}, fallback = "service_unavailable"): Response {
  if (!(error instanceof ApiError)) return json({ error: { code: fallback, retryable: true } }, 503, headers);
  const retryable = error.status === 429 || error.status === 503;
  const retryAfter = String(error.details?.retry_after_seconds ?? (error.status === 429 ? 60 : 15));
  return json({ error: { code: error.code, retryable, ...error.details } }, error.status, { ...(retryable ? { "Retry-After": retryAfter } : {}), ...headers });
}
export function bytes(value: Uint8Array): Response { return new Response(value, { headers: BYTES_HEADERS }); }
/** json() of an ok outcome; a failed one throws its ApiError. */
export function result<T>(outcome: Outcome<T>): Response { return json(unwrap(outcome)); }
/** The digest of the bearer token on a request auth() already accepted. */
export function bearerDigest(request: Request): Promise<string> { return digest(request.headers.get("Authorization")!.slice(7)); }
