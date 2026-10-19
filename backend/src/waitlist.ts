import { JSON_HEADERS, errorResponse, json } from "./http";
import { flags, type ServerVars } from "./flags";
import { ApiError, boundedJson, digest, exactKeys, object } from "./protocol";
import { logWarning } from "./log";
import { MIN_CONFIRM_SECRET_LENGTH, TOKEN_PATTERN, signConfirmToken, verifyConfirmToken } from "./waitlist-token";
import { confirmEmail, sender } from "./waitlist-email";

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
/** Siteverify codes that mean our setup is wrong, not that the visitor failed. */
const TURNSTILE_SETUP_ERRORS = ["missing-input-secret", "invalid-input-secret", "bad-request", "internal-error"];

export type WaitlistEnv = Pick<ServerVars, "IOS_WAITLIST_ENABLED" | "RESEND_API_KEY" | "RESEND_SEGMENT_ID" | "TURNSTILE_SECRET_KEY" | "TURNSTILE_SITE_KEY" | "WAITLIST_CONFIRM_SECRET" | "WAITLIST_REPLY_TO" | "WAITLIST_FROM">
  & { PUBLIC_LIMITER: RateLimit; WAITLIST_ADDRESS_LIMITER: RateLimit };

const CORS = Object.freeze({ "Access-Control-Allow-Origin": WAITLIST_ORIGIN, Vary: "Origin" });
/** Resend's daily or monthly quota is spent: say so plainly, and tell the page to come back much later. */
const FULL = "waitlist_full";

/** The page's request, or null when this is not a waitlist path or the flag is off. */
export async function routeWaitlist(request: Request, path: string, env: WaitlistEnv): Promise<Response | null> {
  if ((path !== WAITLIST_PATH && path !== CONFIRM_PATH) || !flags.iosWaitlist(env)) return null;
  try {
    if (request.headers.get("Origin") !== WAITLIST_ORIGIN) throw new ApiError(403, "origin_not_allowed");
    if (request.method === "OPTIONS") {
      if (request.headers.get("Access-Control-Request-Method") !== "POST") throw new ApiError(405, "method_not_allowed");
      return new Response(null, { status: 204, headers: { ...JSON_HEADERS, ...CORS, "Access-Control-Allow-Methods": "GET, POST", "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Max-Age": "86400" } });
    }
    const config = configured(env);
    if (path === WAITLIST_PATH && request.method === "GET") return json({ schema_version: 1, site_key: config.siteKey }, 200, CORS);
    if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
    const ip = request.headers.get("CF-Connecting-IP");
    if (!(await env.PUBLIC_LIMITER.limit({ key: await digest("waitlist:" + ipKey(ip)) })).success) throw new ApiError(429, "rate_limited");
    return path === WAITLIST_PATH ? await signUp(request, ip, env, config) : await confirm(request, env, config);
  } catch (error) {
    return errorResponse(error, error instanceof ApiError && error.code === FULL ? { ...CORS, "Retry-After": "3600" } : CORS, "waitlist_unavailable");
  }
}

type WaitlistConfig = { siteKey: string; turnstileSecret: string; resendKey: string; segment: string; confirmSecret: string; replyTo: string; from: string };
function configured(env: WaitlistEnv): WaitlistConfig {
  const siteKey = env.TURNSTILE_SITE_KEY ?? "", segment = env.RESEND_SEGMENT_ID ?? "", confirmSecret = env.WAITLIST_CONFIRM_SECRET ?? "", replyTo = env.WAITLIST_REPLY_TO ?? "", from = env.WAITLIST_FROM ?? "";
  if (!SITE_KEY_PATTERN.test(siteKey) || !SEGMENT_PATTERN.test(segment) || confirmSecret.length < MIN_CONFIRM_SECRET_LENGTH || !EMAIL_PATTERN.test(replyTo) || !EMAIL_PATTERN.test(from) || !env.TURNSTILE_SECRET_KEY || !env.RESEND_API_KEY) {
    logWarning("waitlist_unconfigured");
    throw new ApiError(503, "waitlist_unavailable");
  }
  return { siteKey, segment, confirmSecret, replyTo, from, turnstileSecret: env.TURNSTILE_SECRET_KEY, resendKey: env.RESEND_API_KEY };
}

async function signUp(request: Request, ip: string | null, env: WaitlistEnv, config: WaitlistConfig): Promise<Response> {
  const input = object(await boundedJson(request, 4096)); exactKeys(input, ["schema_version", "email", "turnstile_token"]);
  if (input.schema_version !== 1 || typeof input.turnstile_token !== "string" || !TURNSTILE_TOKEN_PATTERN.test(input.turnstile_token)) throw new ApiError(400, "invalid_waitlist_request");
  const email = normalEmail(input.email);
  await verifyTurnstile(input.turnstile_token, ip, config.turnstileSecret);
  // One confirm email per inbox a minute, counted only after a passing human check, so nobody can lock an address out
  // without solving one. The key is a hash; the limiter never sees the address.
  await limitAddress(env, "waitlist-address:", email);
  const token = await signConfirmToken(email, config.confirmSecret, Math.floor(Date.now() / 1000));
  await sendConfirmEmail(email, CONFIRM_PAGE + "#t=" + token, config);
  return json({ schema_version: 1, sent: true }, 200, CORS);
}

async function confirm(request: Request, env: WaitlistEnv, config: WaitlistConfig): Promise<Response> {
  const input = object(await boundedJson(request, 2048)); exactKeys(input, ["schema_version", "token"]);
  if (input.schema_version !== 1 || typeof input.token !== "string" || !TOKEN_PATTERN.test(input.token)) throw new ApiError(400, "invalid_confirm_link");
  const checked = await verifyConfirmToken(input.token, config.confirmSecret, Math.floor(Date.now() / 1000));
  if (!checked.ok) throw checked.reason === "expired" ? new ApiError(410, "confirm_link_expired") : new ApiError(400, "invalid_confirm_link");
  // A signed address passed our own check when it was signed; check it again in case that rule ever changes.
  const email = normalEmail(checked.email);
  // One confirm per inbox a minute, so a replayed link cannot burn Resend's API rate.
  await limitAddress(env, "waitlist-confirm:", email);
  await addContact(email, config);
  return json({ schema_version: 1, confirmed: true }, 200, CORS);
}

/** The trimmed, lower-cased address, or 400 invalid_email. */
export function normalEmail(value: unknown): string {
  if (typeof value !== "string") throw new ApiError(400, "invalid_email");
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !EMAIL_PATTERN.test(email)) throw new ApiError(400, "invalid_email");
  return email;
}

/**
 * The inbox an address delivers to, for rate limits only (mail always goes to the address as typed): no "+tag", and
 * for Gmail no dots, so the variants of one inbox share one allowance.
 */
export function inboxKey(email: string): string {
  const at = email.lastIndexOf("@");
  let local = email.slice(0, at).split("+")[0], domain = email.slice(at + 1);
  if (domain === "gmail.com" || domain === "googlemail.com") { local = local.replace(/\./g, ""); domain = "gmail.com"; }
  return local + "@" + domain;
}
async function limitAddress(env: WaitlistEnv, scope: string, email: string): Promise<void> {
  if (!(await env.WAITLIST_ADDRESS_LIMITER.limit({ key: await digest(scope + inboxKey(email)) })).success) throw new ApiError(429, "rate_limited");
}

/** The limiter's IP key: an IPv4 address as is (also when mapped into IPv6), an IPv6 address as its /64. */
export function ipKey(ip: string | null): string {
  if (!ip) return "local";
  const v4 = /(\d{1,3}(?:\.\d{1,3}){3})$/.exec(ip);
  if (v4) return v4[1];
  if (!ip.includes(":")) return ip;
  const [head, tail] = ip.toLowerCase().split("::");
  const front = head ? head.split(":") : [], back = tail === undefined ? [] : tail ? tail.split(":") : [];
  const groups = tail === undefined ? front : [...front, ...Array(Math.max(0, 8 - front.length - back.length)).fill("0"), ...back];
  return groups.slice(0, 4).map(group => group.replace(/^0+(?=.)/, "")).join(":") + "::/64";
}

async function upstream(service: string, step: string, url: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) });
  } catch (error) {
    logWarning("waitlist_upstream", { service, step, status: error instanceof Error && error.name === "TimeoutError" ? "timeout" : "network" });
    throw new ApiError(503, "waitlist_unavailable");
  }
}
function unavailable(service: string, step: string, status: number | string): never {
  logWarning("waitlist_upstream", { service, step, status });
  throw new ApiError(503, "waitlist_unavailable");
}
/** A small upstream JSON body, or {} when it is missing, large or not JSON. Never logged. */
async function smallJson(response: Response): Promise<Record<string, unknown>> {
  try {
    const text = await response.text();
    const value: unknown = text.length <= 4096 ? JSON.parse(text) : null;
    return value && typeof value === "object" ? value as Record<string, unknown> : {};
  } catch { return {}; }
}

async function verifyTurnstile(token: string, ip: string | null, secret: string): Promise<void> {
  const body: Record<string, string> = { secret, response: token, ...(ip ? { remoteip: ip } : {}) };
  const response = await upstream("turnstile", "siteverify", SITEVERIFY_URL, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const value = await smallJson(response);
  if (!response.ok || typeof value.success !== "boolean") return unavailable("turnstile", "siteverify", response.status);
  const codes = Array.isArray(value["error-codes"]) ? value["error-codes"] : [];
  const setup = codes.find(code => TURNSTILE_SETUP_ERRORS.includes(String(code)));
  if (value.success !== true && setup) return unavailable("turnstile", "siteverify", String(setup));
  if (value.success !== true || value.hostname !== TURNSTILE_HOSTNAME || value.action !== TURNSTILE_ACTION) throw new ApiError(403, "human_check_failed");
}

async function sendConfirmEmail(email: string, link: string, config: WaitlistConfig): Promise<void> {
  const message = confirmEmail(link);
  const sent = await upstream("resend", "send", RESEND_URL + "/emails", {
    method: "POST",
    headers: { Authorization: "Bearer " + config.resendKey, "Content-Type": "application/json" },
    body: JSON.stringify({ from: sender(config.from), to: [email], reply_to: config.replyTo, subject: message.subject, html: message.html, text: message.text })
  });
  if (sent.ok) { await sent.body?.cancel(); return; }
  const name = String((await smallJson(sent)).name ?? "");
  if (sent.status === 429 && (name === "daily_quota_exceeded" || name === "monthly_quota_exceeded")) {
    logWarning("waitlist_upstream", { service: "resend", step: "send", status: name });
    throw new ApiError(503, FULL);
  }
  // A validation error with no sender problem named is most likely the visitor's address; it is still logged (status
  // only), so a broken sender setup shows up as a run of 422s.
  if (sent.status === 422 && !/from|domain|required/.test(name)) {
    logWarning("waitlist_upstream", { service: "resend", step: "send", status: 422 });
    throw new ApiError(400, "invalid_email");
  }
  return unavailable("resend", "send", sent.status);
}

/**
 * Puts the contact in the segment. Adding an existing contact to the segment is tried first, so a contact that already
 * exists (perhaps unsubscribed, or in another segment) is never recreated and its subscription is left as Resend has
 * it. Only a refusal that may mean "no such contact" creates one, with the segment; a create that loses a race to
 * another confirm falls back to adding once more. Resend does not document these answers exactly, so any 4xx other
 * than auth, permission and rate errors counts as "try the other call".
 */
async function addContact(email: string, config: WaitlistConfig): Promise<void> {
  const auth = "Bearer " + config.resendKey;
  const segment = () => upstream("resend", "segment", `${RESEND_URL}/contacts/${encodeURIComponent(email)}/segments/${encodeURIComponent(config.segment)}`, { method: "POST", headers: { Authorization: auth } });
  const first = await segment();
  await first.body?.cancel();
  if (first.ok) return;
  if (!maybeMissing(first.status)) return unavailable("resend", "segment", first.status);
  const created = await upstream("resend", "create", RESEND_URL + "/contacts", { method: "POST", headers: { Authorization: auth, "Content-Type": "application/json" }, body: JSON.stringify({ email, segments: [{ id: config.segment }] }) });
  await created.body?.cancel();
  if (created.ok) return;
  if (!maybeMissing(created.status)) return unavailable("resend", "create", created.status);
  const again = await segment();
  await again.body?.cancel();
  if (again.ok) return;
  logWarning("waitlist_upstream", { service: "resend", step: "create", status: created.status });
  return unavailable("resend", "segment", again.status);
}
/** A 4xx that may only mean the other call is the right one; auth, permission and rate errors are not. */
function maybeMissing(status: number): boolean {
  return status >= 400 && status < 500 && ![401, 403, 429].includes(status);
}
