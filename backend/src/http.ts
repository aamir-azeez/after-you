import { digest, unwrap, type Outcome } from "./protocol";

/** Headers on every API answer with a JSON body. */
export const JSON_HEADERS = Object.freeze({ "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" });
const BYTES_HEADERS = Object.freeze({ "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/octet-stream" });

export function json(value: unknown, status = 200): Response { return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS }); }
export function bytes(value: Uint8Array): Response { return new Response(value, { headers: BYTES_HEADERS }); }
/** json() of an ok outcome; a failed one throws its ApiError. */
export function result<T>(outcome: Outcome<T>): Response { return json(unwrap(outcome)); }
/** The digest of the bearer token on a request auth() already accepted. */
export function bearerDigest(request: Request): Promise<string> { return digest(request.headers.get("Authorization")!.slice(7)); }
