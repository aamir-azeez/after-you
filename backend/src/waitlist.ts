import { JSON_HEADERS } from "./http";
import { flags, type ServerVars } from "./flags";
import { ApiError, boundedJson, digest, exactKeys, object } from "./protocol";
import { logWarning } from "./log";
import { MIN_CONFIRM_SECRET_LENGTH, TOKEN_PATTERN, signConfirmToken, verifyConfirmToken } from "./waitlist-token";
import { WAITLIST_SENDER, confirmEmail } from "./waitlist-email";

/**
 * The iOS launch waitlist behind the friend link page on aamirazeez.com, with double opt-in.
 *
 * - GET /v1/waitlist/ios answers the page's public Turnstile site key.
 * - POST /v1/waitlist/ios {schema_version 1, email, turnstile_token} checks Turnstile and emails a signed confirm link.
 *   No contact exists yet.
 * - The link opens a page on aamirazeez.com that holds the token in its fragment and confirms only when the person
 *   taps its button: POST /v1/waitlist/ios/confirm {schema_version 1, token}. Link scanners that fetch the URL never
 *   confirm, and the token never reaches a server log. Confirming adds the Resend contact to the waitlist segment and
 *   is idempotent.
 *
 * The worker keeps no list and opens no Durable Object. Every answer is the same whether or not the address is already
 * listed. Emails, tokens and upstream bodies are never logged.
 *
 * Absent unless IOS_WAITLIST_ENABLED is "true": both paths then fall through as before (OPTIONS 405, others to auth()).
 */
export const WAITLIST_PATH = "/v1/waitlist/ios";
export const CONFIRM_PATH = "/v1/waitlist/ios/confirm";
export const WAITLIST_ORIGIN = "https://aamirazeez.com";
export const CONFIRM_PAGE = "https://aamirazeez.com/after-you/waitlist/confirm/";
/** The page's hostname and widget action, both checked on the siteverify answer. */
export const TURNSTILE_HOSTNAME = "aamirazeez.com";
export const TURNSTILE_ACTION = "ios_waitlist";
const SITEVERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
const RESEND_URL = "https://api.resend.com";
const UPSTREAM_TIMEOUT_MS = 8000;
const SEGMENT_PATTERN = /^[A-Za-z0-9-]{8,64}$/;
const SITE_KEY_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
/** A plain address check: one @, no spaces or angle brackets, a dotted domain. Resend does the rest. */
const EMAIL_PATTERN = /^[^\s@<>()[\]\\,;:"]{1,64}@(?=.{4,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;
const TURNSTILE_TOKEN_PATTERN = /^[\x21-\x7e]{1,2048}$/;

export type WaitlistEnv = Pick<ServerVars, "IOS_WAITLIST_ENABLED" | "RESEND_API_KEY" | "RESEND_SEGMENT_ID" | "TURNSTILE_SECRET_KEY" | "TURNSTILE_SITE_KEY" | "WAITLIST_CONFIRM_SECRET" | "WAITLIST_REPLY_TO">
  & { PUBLIC_LIMITER: RateLimit; WAITLIST_ADDRESS_LIMITER: RateLimit };

const CORS = Object.freeze({ "Access-Control-Allow-Origin": WAITLIST_ORIGIN, Vary: "Origin" });
function answer(value: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(value === null ? null : JSON.stringify(value), { status, headers: { ...JSON_HEADERS, ...CORS, ...extra } });
}
function failure(error: unknown): Response {
  const status = error instanceof ApiError ? error.status : 503, code = error instanceof ApiError ? error.code : "waitlist_unavailable";
  const retryable = status === 429 || status === 503;
  return answer({ error: { code, retryable } }, status, retryable ? { "Retry-After": status === 429 ? "60" : "15" } : {});
}

/** The page's request, or null when this is not a waitlist path or the flag is off. */
export async function routeWaitlist(request: Request, path: string, env: WaitlistEnv): Promise<Response | null> {
  if ((path !== WAITLIST_PATH && path !== CONFIRM_PATH) || !flags.iosWaitlist(env)) return null;
  try {
    if (request.headers.get("Origin") !== WAITLIST_ORIGIN) throw new ApiError(403, "origin_not_allowed");
    if (request.method === "OPTIONS") {
      if (request.headers.get("Access-Control-Request-Method") !== "POST") throw new ApiError(405, "method_not_allowed");
      return answer(null, 204, { "Access-Control-Allow-Methods": "GET, POST", "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Max-Age": "86400" });
    }
    const config = configured(env);
    if (path === WAITLIST_PATH && request.method === "GET") return answer({ schema_version: 1, site_key: config.siteKey });
    if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
    const ip = request.headers.get("CF-Connecting-IP");
    if (!(await env.PUBLIC_LIMITER.limit({ key: await digest("waitlist:" + (ip || "local")) })).success) throw new ApiError(429, "rate_limited");
    return path === WAITLIST_PATH ? await signUp(request, ip, env, config) : await confirm(request, config);
  } catch (error) {
    return failure(error);
  }
}

type WaitlistConfig = { siteKey: string; turnstileSecret: string; resendKey: string; segment: string; confirmSecret: string; replyTo: string };
function configured(env: WaitlistEnv): WaitlistConfig {
  const siteKey = env.TURNSTILE_SITE_KEY ?? "", segment = env.RESEND_SEGMENT_ID ?? "", confirmSecret = env.WAITLIST_CONFIRM_SECRET ?? "", replyTo = env.WAITLIST_REPLY_TO ?? "";
  if (!SITE_KEY_PATTERN.test(siteKey) || !SEGMENT_PATTERN.test(segment) || confirmSecret.length < MIN_CONFIRM_SECRET_LENGTH || !EMAIL_PATTERN.test(replyTo) || !env.TURNSTILE_SECRET_KEY || !env.RESEND_API_KEY) {
    logWarning("waitlist_unconfigured");
    throw new ApiError(503, "waitlist_unavailable");
  }
  return { siteKey, segment, confirmSecret, replyTo, turnstileSecret: env.TURNSTILE_SECRET_KEY, resendKey: env.RESEND_API_KEY };
}

async function signUp(request: Request, ip: string | null, env: WaitlistEnv, config: WaitlistConfig): Promise<Response> {
  const input = object(await boundedJson(request, 4096)); exactKeys(input, ["schema_version", "email", "turnstile_token"]);
  if (input.schema_version !== 1 || typeof input.turnstile_token !== "string" || !TURNSTILE_TOKEN_PATTERN.test(input.turnstile_token)) throw new ApiError(400, "invalid_waitlist_request");
  const email = normalEmail(input.email);
  await verifyTurnstile(input.turnstile_token, ip, config.turnstileSecret);
  // One confirm email per address a minute, counted only after a passing human check, so nobody can lock an address out
  // without solving one. The key is a hash; the limiter never sees the address.
  if (!(await env.WAITLIST_ADDRESS_LIMITER.limit({ key: await digest("waitlist-address:" + email) })).success) throw new ApiError(429, "rate_limited");
  const token = await signConfirmToken(email, config.confirmSecret, Math.floor(Date.now() / 1000));
  await sendConfirmEmail(email, CONFIRM_PAGE + "#t=" + token, config);
  return answer({ schema_version: 1, sent: true });
}

async function confirm(request: Request, config: WaitlistConfig): Promise<Response> {
  const input = object(await boundedJson(request, 2048)); exactKeys(input, ["schema_version", "token"]);
  if (input.schema_version !== 1 || typeof input.token !== "string" || !TOKEN_PATTERN.test(input.token)) throw new ApiError(400, "invalid_confirm_link");
  const checked = await verifyConfirmToken(input.token, config.confirmSecret, Math.floor(Date.now() / 1000));
  if (!checked.ok) throw checked.reason === "expired" ? new ApiError(410, "confirm_link_expired") : new ApiError(400, "invalid_confirm_link");
  // A signed address passed our own check when it was signed; check it again in case that rule ever changes.
  await addContact(normalEmail(checked.email), config);
  return answer({ schema_version: 1, confirmed: true });
}

/** The trimmed, lower-cased address, or 400 invalid_email. */
export function normalEmail(value: unknown): string {
  if (typeof value !== "string") throw new ApiError(400, "invalid_email");
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !EMAIL_PATTERN.test(email)) throw new ApiError(400, "invalid_email");
  return email;
}

async function upstream(service: string, step: string, url: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) });
  } catch (error) {
    logWarning("waitlist_upstream", { service, step, status: error instanceof Error && error.name === "TimeoutError" ? "timeout" : "network" });
    throw new ApiError(503, "waitlist_unavailable");
  }
}
function unavailable(service: string, step: string, status: number): never {
  logWarning("waitlist_upstream", { service, step, status });
  throw new ApiError(503, "waitlist_unavailable");
}

async function verifyTurnstile(token: string, ip: string | null, secret: string): Promise<void> {
  const body: Record<string, string> = { secret, response: token, ...(ip ? { remoteip: ip } : {}) };
  const response = await upstream("turnstile", "siteverify", SITEVERIFY_URL, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  let outcome: unknown = null;
  try { outcome = await response.json(); } catch { outcome = null; }
  const value = outcome && typeof outcome === "object" ? outcome as Record<string, unknown> : {};
  if (!response.ok || typeof value.success !== "boolean") return unavailable("turnstile", "siteverify", response.status);
  if (value.success !== true || value.hostname !== TURNSTILE_HOSTNAME || value.action !== TURNSTILE_ACTION) throw new ApiError(403, "human_check_failed");
}

async function sendConfirmEmail(email: string, link: string, config: WaitlistConfig): Promise<void> {
  const message = confirmEmail(link);
  const sent = await upstream("resend", "send", RESEND_URL + "/emails", {
    method: "POST",
    headers: { Authorization: "Bearer " + config.resendKey, "Content-Type": "application/json" },
    body: JSON.stringify({ from: WAITLIST_SENDER, to: [email], reply_to: config.replyTo, subject: message.subject, html: message.html, text: message.text })
  });
  await sent.body?.cancel();
  if (sent.ok) return;
  // Resend refusing the address itself (a validation error) is the person's typo; quota, auth and server errors are ours.
  if (sent.status === 422) throw new ApiError(400, "invalid_email");
  return unavailable("resend", "send", sent.status);
}

/**
 * Creates the contact in the segment. Resend does not document what creating an existing contact answers, so any
 * other 4xx tries adding the existing contact to the segment instead; both paths end in the same success. Create sends
 * unsubscribed false because the person has just proved the address is theirs and asked to join; the fallback leaves
 * an existing contact's subscription as Resend has it.
 */
async function addContact(email: string, config: WaitlistConfig): Promise<void> {
  const headers = { Authorization: "Bearer " + config.resendKey, "Content-Type": "application/json" };
  const created = await upstream("resend", "create", RESEND_URL + "/contacts", { method: "POST", headers, body: JSON.stringify({ email, unsubscribed: false, segments: [{ id: config.segment }] }) });
  await created.body?.cancel();
  if (created.ok) return;
  if (!resendFallback(created.status)) return unavailable("resend", "create", created.status);
  const added = await upstream("resend", "segment", `${RESEND_URL}/contacts/${encodeURIComponent(email)}/segments/${encodeURIComponent(config.segment)}`, { method: "POST", headers: { Authorization: headers.Authorization } });
  await added.body?.cancel();
  if (added.ok) return;
  logWarning("waitlist_upstream", { service: "resend", step: "create", status: created.status });
  return unavailable("resend", "segment", added.status);
}
/** A refusal that may mean "already a contact"; auth, quota, rate and server errors do not. */
function resendFallback(status: number): boolean {
  return status >= 400 && status < 500 && ![401, 403, 429].includes(status);
}
