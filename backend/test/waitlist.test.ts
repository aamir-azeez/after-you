import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { inboxKey, ipKey, normalEmail } from "../src/waitlist";
import { CONFIRM_TTL_SECONDS, signConfirmToken, verifyConfirmToken } from "../src/waitlist-token";
import { confirmEmail } from "../src/waitlist-email";
import { APP } from "../src/config";
import { withConfig } from "./config";

const ORIGIN = "https://aamirazeez.com";
const SEGMENT = APP.resendSegmentId;
const SECRET = "test-confirm-secret-0123456789abcdef-never-real";
/** The flag and the three secrets. The site key, both addresses and the segment are APP's (config.ts). */
const VARS = {
  IOS_WAITLIST_ENABLED: "true", RESEND_API_KEY: "re_test_key_never_real", TURNSTILE_SECRET_KEY: "1x0000000000000000000000000000000AA",
  WAITLIST_CONFIRM_SECRET: SECRET
};
const TOKEN = "XXXX.DUMMY.TOKEN.XXXX";
const EMAIL = "Someone.Waiting@Example.com", NORMAL = "someone.waiting@example.com";
const SIGNUP = "/v1/waitlist/ios", CONFIRM = "/v1/waitlist/ios/confirm";
const now = () => Math.floor(Date.now() / 1000);
let ip = 0;
function limiter(success = true) { return { limit: vi.fn(async (_: { key: string }) => ({ success })) }; }
/** Durable Object namespaces that fail the test if the waitlist touches any of them. */
function noObjects(): Record<string, unknown> {
  const trap = new Proxy({}, { get(_, name) { throw new Error("durable object touched: " + String(name)); } });
  return Object.fromEntries(["PLAYERS", "ROOMS", "ROOMS_V2", "SAFETY_PROFILES", "SAFETY_INBOX", "FRIEND_ROOM_EVENTS", "PHOTO_TRANSFERS", "PHOTO_TRANSFER_BUDGET"].map(name => [name, trap]));
}
type Call = { path?: string; method?: string; origin?: string | null; body?: unknown; raw?: string; contentType?: string; vars?: Record<string, unknown>; headers?: Record<string, string> };
function call(options: Call = {}): Promise<Response> {
  const path = options.path ?? SIGNUP, method = options.method ?? "POST";
  const headers: Record<string, string> = { "CF-Connecting-IP": "198.51.100." + (++ip % 250), ...(options.headers ?? {}) };
  if (options.origin !== null) headers.Origin = options.origin ?? ORIGIN;
  if (method === "POST") headers["Content-Type"] = options.contentType ?? "application/json";
  const fallback = path === SIGNUP ? { schema_version: 1, email: EMAIL, turnstile_token: TOKEN } : {};
  const body = options.raw ?? (method === "POST" ? JSON.stringify(options.body ?? fallback) : undefined);
  return worker.fetch(new Request("https://game.test" + path, { method, headers, body }),
    withConfig({ ...env, PUBLIC_LIMITER: limiter(), WAITLIST_ADDRESS_LIMITER: limiter(), ...noObjects(), ...VARS, ...(options.vars ?? {}) }) as unknown as Env);
}
const confirmCall = async (token: string, options: Call = {}) => call({ path: CONFIRM, body: { schema_version: 1, token }, ...options });
type Answer = () => Response | Promise<Response>;
type Upstream = { siteverify?: Answer; send?: Answer; create?: Answer; segment?: Answer };
function upstream(answers: Upstream = {}) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (input: RequestInfo | URL) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url === "https://challenges.cloudflare.com/turnstile/v0/siteverify") return answers.siteverify ? answers.siteverify() : Response.json({ success: true, hostname: "aamirazeez.com", action: "ios_waitlist", "error-codes": [] });
    if (url === "https://api.resend.com/emails") return answers.send ? answers.send() : Response.json({ id: "49a3999c-0ce1-4ea6-ab68-afcd6dc2e794" });
    if (url === "https://api.resend.com/contacts") return answers.create ? answers.create() : Response.json({ object: "contact", id: "479e3145-dd38-476b-932c-529ceb705947" }, { status: 201 });
    if (url.startsWith("https://api.resend.com/contacts/")) return answers.segment ? answers.segment() : Response.json({ id: SEGMENT });
    throw new Error("unexpected fetch " + url);
  });
}
const resendError = (status: number, name: string) => () => Response.json({ statusCode: status, name, message: "x" }, { status });
async function errorCode(response: Response) { return ((await response.json()) as { error: { code: string } }).error.code; }
function expectCors(response: Response) {
  expect(response.headers.get("Access-Control-Allow-Origin")).toBe(ORIGIN);
  expect(response.headers.get("Vary")).toBe("Origin");
  expect(response.headers.get("Cache-Control")).toBe("no-store");
}
const urls = (spy: ReturnType<typeof upstream>) => spy.mock.calls.map(([input]) => String(input));
function sentEmail(spy: ReturnType<typeof upstream>): Record<string, unknown> {
  const index = urls(spy).indexOf("https://api.resend.com/emails");
  expect(index).toBeGreaterThanOrEqual(0);
  return JSON.parse(String((spy.mock.calls[index][1] as RequestInit).body));
}
function linkToken(message: Record<string, unknown>): string {
  const match = /https:\/\/aamirazeez\.com\/after-you\/waitlist\/confirm\/#t=([A-Za-z0-9_.-]+)/.exec(String(message.text));
  expect(match).not.toBeNull();
  return match![1];
}

afterEach(() => { vi.restoreAllMocks(); });

describe("iOS waitlist with the flag off", () => {
  it("answers every method on both paths exactly as before and calls nothing", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    for (const flag of [undefined, "false", "TRUE", "1", ""]) {
      const vars: Record<string, unknown> = { ...VARS, IOS_WAITLIST_ENABLED: flag };
      for (const path of [SIGNUP, CONFIRM]) {
        const post = await call({ path, vars });
        expect(post.status).toBe(401);
        expect(await post.json()).toEqual({ error: { code: "invalid_auth", retryable: false } });
        expect(post.headers.get("Access-Control-Allow-Origin")).toBeNull();
        const options = await call({ path, method: "OPTIONS", vars, headers: { "Access-Control-Request-Method": "POST" } });
        expect(options.status).toBe(405);
        expect(options.headers.get("Access-Control-Allow-Origin")).toBeNull();
        expect((await call({ path, method: "GET", vars })).status).toBe(401);
      }
    }
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});

describe("the page's config and CORS", () => {
  it("hands the page its public site key and nothing secret", async () => {
    const response = await call({ method: "GET" });
    expect(response.status).toBe(200);
    expectCors(response);
    const text = await response.text();
    expect(JSON.parse(text)).toEqual({ schema_version: 1, site_key: APP.turnstileSiteKey });
    for (const secret of [VARS.TURNSTILE_SECRET_KEY, VARS.RESEND_API_KEY, SECRET]) expect(text).not.toContain(secret);
  });

  it("answers the browser's preflight on both paths for the page's origin only", async () => {
    for (const path of [SIGNUP, CONFIRM]) {
      const preflight = await call({ path, method: "OPTIONS", headers: { "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type" } });
      expect(preflight.status).toBe(204);
      expect(preflight.headers.get("Access-Control-Allow-Origin")).toBe(ORIGIN);
      expect(preflight.headers.get("Access-Control-Allow-Methods")).toBe("GET, POST");
      expect(preflight.headers.get("Access-Control-Allow-Headers")).toBe("Content-Type");
      expect((await call({ path, method: "OPTIONS" })).status).toBe(405);
      for (const origin of [null, "https://evil.example", "http://aamirazeez.com", "https://www.aamirazeez.com", "https://aamirazeez.com.evil.example"]) {
        for (const method of ["OPTIONS", "GET", "POST"]) {
          const response = await call({ path, method, origin, headers: method === "OPTIONS" ? { "Access-Control-Request-Method": "POST" } : {} });
          expect(response.status, `${path} ${origin} ${method}`).toBe(403);
          expect(await errorCode(response)).toBe("origin_not_allowed");
          expectCors(response);
        }
      }
    }
  });

  it("refuses other methods, and GET on the confirm path", async () => {
    for (const [path, method] of [[SIGNUP, "PUT"], [SIGNUP, "DELETE"], [CONFIRM, "GET"], [CONFIRM, "PATCH"]]) {
      const response = await call({ path, method });
      expect(response.status, `${path} ${method}`).toBe(405);
      expectCors(response);
    }
  });

  it("stays closed with 503 until every secret is set", async () => {
    for (const missing of ["RESEND_API_KEY", "TURNSTILE_SECRET_KEY", "WAITLIST_CONFIRM_SECRET"]) {
      const fetchSpy = upstream();
      for (const [path, method] of [[SIGNUP, "GET"], [SIGNUP, "POST"], [CONFIRM, "POST"]]) {
        const response = await call({ path, method, vars: { [missing]: undefined } });
        expect(response.status, `${missing} ${path} ${method}`).toBe(503);
        expectCors(response);
      }
      expect(fetchSpy).not.toHaveBeenCalled();
      vi.restoreAllMocks();
    }
    expect((await call({ method: "GET", vars: { WAITLIST_CONFIRM_SECRET: "x".repeat(31) } })).status).toBe(503);
  });
});

describe("signing up", () => {
  it("checks the human, then emails a signed confirm link and creates no contact", async () => {
    const fetchSpy = upstream();
    const address = limiter();
    const response = await call({ vars: { WAITLIST_ADDRESS_LIMITER: address } });
    expect(response.status).toBe(200);
    expectCors(response);
    expect(await response.json()).toEqual({ schema_version: 1, sent: true });
    expect(urls(fetchSpy)).toEqual(["https://challenges.cloudflare.com/turnstile/v0/siteverify", "https://api.resend.com/emails"]);
    const verify = fetchSpy.mock.calls[0][1] as RequestInit;
    expect(JSON.parse(String(verify.body))).toEqual({ secret: VARS.TURNSTILE_SECRET_KEY, response: TOKEN, remoteip: expect.stringMatching(/^198\.51\.100\./) });
    expect(verify.signal).toBeInstanceOf(AbortSignal);
    const sendInit = fetchSpy.mock.calls[1][1] as RequestInit;
    expect((sendInit.headers as Record<string, string>).Authorization).toBe("Bearer " + VARS.RESEND_API_KEY);
    expect(sendInit.signal).toBeInstanceOf(AbortSignal);
    const message = sentEmail(fetchSpy);
    expect(Object.keys(message).sort()).toEqual(["from", "html", "reply_to", "subject", "text", "to"]);
    expect(message.from).toBe("After You <waitlist@afteryou.aamirazeez.com>");
    expect(message.to).toEqual([NORMAL]);
    expect(message.reply_to).toBe(APP.waitlistReplyTo);
    expect(message.subject).toBe("Confirm your email for After You on iPhone");
    const token = linkToken(message);
    expect(String(message.html)).toContain(`href="https://aamirazeez.com/after-you/waitlist/confirm/#t=${token}"`);
    const checked = await verifyConfirmToken(token, SECRET, now());
    expect(checked).toEqual({ ok: true, email: NORMAL });
    // The address limiter counts a hash of the address, never the address.
    const key = address.limit.mock.calls[0][0].key;
    expect(key).toMatch(/^[0-9a-f]{64}$/);
    expect(key).not.toContain("someone");
  });

  it("answers any two addresses byte for byte alike", async () => {
    upstream();
    const first = await call();
    const second = await call({ body: { schema_version: 1, email: "other.person@example.org", turnstile_token: TOKEN } });
    expect(second.status).toBe(first.status);
    expect([...second.headers].sort()).toEqual([...first.headers].sort());
    expect(await second.text()).toBe(await first.text());
  });

  it("checks the address before calling anyone", async () => {
    const fetchSpy = upstream();
    for (const email of ["", "plain", "a@b", "a@localhost", "two@@example.com", "a b@example.com", "<a@example.com>", "a@-example.com", "a@example..com", "a@" + "x".repeat(250) + ".com", "x".repeat(65) + "@example.com", 42, null]) {
      const response = await call({ body: { schema_version: 1, email, turnstile_token: TOKEN } });
      expect(response.status, String(email)).toBe(400);
      expect(await errorCode(response)).toBe("invalid_email");
      expectCors(response);
    }
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(normalEmail("  First.Last+ios@Mail.Example.co.uk ")).toBe("first.last+ios@mail.example.co.uk");
  });

  it("refuses malformed requests with readable errors", async () => {
    const fetchSpy = upstream();
    const cases: [Call, number, string][] = [
      [{ body: { schema_version: 1, email: EMAIL, turnstile_token: TOKEN, name: "x" } }, 400, "unexpected_field"],
      [{ body: { schema_version: 2, email: EMAIL, turnstile_token: TOKEN } }, 400, "invalid_waitlist_request"],
      [{ body: { schema_version: 1, email: EMAIL } }, 400, "invalid_waitlist_request"],
      [{ body: { schema_version: 1, email: EMAIL, turnstile_token: "x".repeat(2049) } }, 400, "invalid_waitlist_request"],
      [{ body: [] }, 400, "invalid_object"],
      [{ raw: "{" }, 400, "invalid_json"],
      [{ contentType: "text/plain" }, 415, "json_required"],
      [{ raw: JSON.stringify({ schema_version: 1, email: EMAIL, turnstile_token: "x".repeat(4100) }) }, 413, "body_too_large"]
    ];
    for (const [options, status, code] of cases) {
      const response = await call(options);
      expect(response.status, code).toBe(status);
      expect(await errorCode(response)).toBe(code);
      expectCors(response);
    }
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("refuses a failed, foreign or reused human check without emailing", async () => {
    for (const verdict of [
      { success: false, "error-codes": ["invalid-input-response"] },
      { success: false, "error-codes": ["timeout-or-duplicate"] },
      { success: true, hostname: "evil.example", action: "ios_waitlist" },
      { success: true, hostname: "aamirazeez.com", action: "other" },
      { success: true, hostname: "aamirazeez.com" }
    ]) {
      const fetchSpy = upstream({ siteverify: () => Response.json(verdict) });
      const address = limiter();
      const response = await call({ vars: { WAITLIST_ADDRESS_LIMITER: address } });
      expect(response.status).toBe(403);
      expect(await response.json()).toEqual({ error: { code: "human_check_failed", retryable: false } });
      expectCors(response);
      expect(urls(fetchSpy)).toEqual(["https://challenges.cloudflare.com/turnstile/v0/siteverify"]);
      // A failed check never spends the address's allowance.
      expect(address.limit).not.toHaveBeenCalled();
      vi.restoreAllMocks();
    }
  });

  it("limits each IP before any outside call, and each address after the human check", async () => {
    let fetchSpy = upstream();
    const blocked = await call({ vars: { PUBLIC_LIMITER: limiter(false) } });
    expect(blocked.status).toBe(429);
    expect(await blocked.json()).toEqual({ error: { code: "rate_limited", retryable: true } });
    expect(blocked.headers.get("Retry-After")).toBe("60");
    expectCors(blocked);
    expect(fetchSpy).not.toHaveBeenCalled();
    vi.restoreAllMocks();

    fetchSpy = upstream();
    const busy = await call({ vars: { WAITLIST_ADDRESS_LIMITER: limiter(false) } });
    expect(busy.status).toBe(429);
    expectCors(busy);
    expect(urls(fetchSpy)).toEqual(["https://challenges.cloudflare.com/turnstile/v0/siteverify"]);

    // The IP key is a hash in its own bucket, not the raw address or the key identity creation uses.
    const perIp = limiter();
    await call({ vars: { PUBLIC_LIMITER: perIp }, headers: { "CF-Connecting-IP": "203.0.113.9" } });
    const key = perIp.limit.mock.calls[0][0].key;
    const plain = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode("203.0.113.9")))].map(b => b.toString(16).padStart(2, "0")).join("");
    expect(key).toMatch(/^[0-9a-f]{64}$/);
    expect(key).not.toBe(plain);
    // GET and the preflight never spend either limiter.
    const untouched = limiter(), addressUntouched = limiter();
    await call({ method: "GET", vars: { PUBLIC_LIMITER: untouched, WAITLIST_ADDRESS_LIMITER: addressUntouched } });
    await call({ method: "OPTIONS", vars: { PUBLIC_LIMITER: untouched, WAITLIST_ADDRESS_LIMITER: addressUntouched }, headers: { "Access-Control-Request-Method": "POST" } });
    expect(untouched.limit).not.toHaveBeenCalled();
    expect(addressUntouched.limit).not.toHaveBeenCalled();
  });

  it("maps outside failures to 503 retryable, and Resend refusing the address to invalid_email", async () => {
    const failures: Upstream[] = [
      { siteverify: () => new Response("oops", { status: 500 }) },
      { siteverify: () => new Response("not json") },
      { siteverify: () => { throw new TypeError("network"); } },
      { send: resendError(401, "validation_error") },
      { send: resendError(403, "validation_error") },
      { send: resendError(429, "rate_limit_exceeded") },
      { send: resendError(500, "application_error") },
      { send: () => { throw new TypeError("network"); } }
    ];
    for (const answers of failures) {
      upstream(answers);
      const response = await call();
      expect(response.status).toBe(503);
      expect(await response.json()).toEqual({ error: { code: "waitlist_unavailable", retryable: true } });
      expect(response.headers.get("Retry-After")).toBe("15");
      expectCors(response);
      vi.restoreAllMocks();
    }
    for (const name of ["invalid_from_address", "missing_required_field"]) {
      upstream({ send: resendError(422, name) });
      const sender = await call();
      expect(sender.status, name).toBe(503);
      vi.restoreAllMocks();
    }
    upstream({ send: resendError(422, "validation_error") });
    const refused = await call();
    expect(refused.status).toBe(400);
    expect(await errorCode(refused)).toBe("invalid_email");
  });

  it("says plainly when Resend's sending quota is spent", async () => {
    for (const name of ["daily_quota_exceeded", "monthly_quota_exceeded"]) {
      upstream({ send: resendError(429, name) });
      const response = await call();
      expect(response.status).toBe(503);
      expect(await response.json()).toEqual({ error: { code: "waitlist_full", retryable: true } });
      expect(response.headers.get("Retry-After")).toBe("3600");
      expectCors(response);
      vi.restoreAllMocks();
    }
  });

  it("treats a broken Turnstile setup as our failure, not the visitor's", async () => {
    for (const code of ["invalid-input-secret", "missing-input-secret", "internal-error", "bad-request"]) {
      upstream({ siteverify: () => Response.json({ success: false, "error-codes": [code] }) });
      const response = await call();
      expect(response.status, code).toBe(503);
      expect(await errorCode(response)).toBe("waitlist_unavailable");
      vi.restoreAllMocks();
    }
  });

  it("folds the variants of one inbox into one allowance, and never changes where mail goes", async () => {
    expect(inboxKey("v.ictim+1@gmail.com")).toBe("victim@gmail.com");
    expect(inboxKey("victim@googlemail.com")).toBe("victim@gmail.com");
    expect(inboxKey("first.last+ios@example.com")).toBe("first.last@example.com");
    const fetchSpy = upstream();
    await call({ body: { schema_version: 1, email: "V.ictim+waitlist@Gmail.com", turnstile_token: TOKEN } });
    expect(sentEmail(fetchSpy).to).toEqual(["v.ictim+waitlist@gmail.com"]);
  });

  it("keys IPv6 on its /64 and mapped IPv4 on the IPv4 address", () => {
    expect(ipKey("2001:db8:85a3:12:8a2e:370:7334:1")).toBe("2001:db8:85a3:12::/64");
    expect(ipKey("2001:db8:85a3:12::99")).toBe("2001:db8:85a3:12::/64");
    expect(ipKey("2001:0db8::1")).toBe("2001:db8:0:0::/64");
    expect(ipKey("::ffff:203.0.113.9")).toBe("203.0.113.9");
    expect(ipKey("203.0.113.9")).toBe("203.0.113.9");
    expect(ipKey(null)).toBe("local");
  });
});

describe("confirming", () => {
  const missing = () => resendError(404, "not_found")();
  const SEGMENT_URL = `https://api.resend.com/contacts/${encodeURIComponent(NORMAL)}/segments/${SEGMENT}`;
  it("adds the contact to the segment only after the tap, from the link the email carried", async () => {
    const fetchSpy = upstream();
    await call();
    const token = linkToken(sentEmail(fetchSpy));
    expect(urls(fetchSpy).some(url => url.includes("/contacts"))).toBe(false);
    vi.restoreAllMocks();
    // A new address: adding it to the segment finds no contact, so it is created with the segment.
    const confirmSpy = upstream({ segment: missing });
    const response = await confirmCall(token);
    expect(response.status).toBe(200);
    expectCors(response);
    expect(await response.json()).toEqual({ schema_version: 1, confirmed: true });
    expect(urls(confirmSpy)).toEqual([SEGMENT_URL, "https://api.resend.com/contacts"]);
    const add = confirmSpy.mock.calls[0][1] as RequestInit;
    expect(add.method).toBe("POST");
    expect(add.body).toBeUndefined();
    expect((add.headers as Record<string, string>).Authorization).toBe("Bearer " + VARS.RESEND_API_KEY);
    // The subscription is never set: a new contact starts subscribed, and nothing here can undo an unsubscribe.
    expect(JSON.parse(String((confirmSpy.mock.calls[1][1] as RequestInit).body))).toEqual({ email: NORMAL, segments: [{ id: SEGMENT }] });
  });

  it("is idempotent, and an existing contact gets the same bytes and is never recreated", async () => {
    const token = await signConfirmToken(NORMAL, SECRET, now());
    upstream({ segment: missing });
    const fresh = await confirmCall(token);
    vi.restoreAllMocks();
    const cases: [Upstream, string[]][] = [
      [{}, ["segment"]],
      [{ segment: missing, create: resendError(409, "x") }, ["segment", "create", "segment"]],
      [{ segment: missing, create: resendError(422, "validation_error") }, ["segment", "create", "segment"]]
    ];
    for (const [answers, steps] of cases) {
      let segmentCalls = 0;
      const first = answers.segment;
      const fetchSpy = upstream({ ...answers, segment: () => (++segmentCalls === 1 && first ? first() : Response.json({ id: SEGMENT })) });
      const again = await confirmCall(token);
      expect(again.status).toBe(fresh.status);
      expect([...again.headers].sort()).toEqual([...fresh.headers].sort());
      expect(await again.text()).toBe(await fresh.clone().text());
      expect(urls(fetchSpy).map(url => url.endsWith("/contacts") ? "create" : "segment")).toEqual(steps);
      vi.restoreAllMocks();
    }
  });

  it("refuses an expired link with 410 and calls nobody", async () => {
    const fetchSpy = upstream();
    const old = await signConfirmToken(NORMAL, SECRET, now() - CONFIRM_TTL_SECONDS - 5);
    const response = await confirmCall(old);
    expect(response.status).toBe(410);
    expect(await response.json()).toEqual({ error: { code: "confirm_link_expired", retryable: false } });
    expectCors(response);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("refuses forged, altered and malformed links with 400 and calls nobody", async () => {
    const fetchSpy = upstream();
    const good = await signConfirmToken(NORMAL, SECRET, now());
    const [payload, mac] = good.split(".");
    const otherPayload = btoa(JSON.stringify({ e: "attacker@example.com", x: now() + 1000 })).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const flipped = mac.slice(0, -2) + (mac.at(-2) === "A" ? "B" : "A") + mac.at(-1);
    const forged = [
      await signConfirmToken(NORMAL, "a-different-secret-0123456789abcdef", now()),
      otherPayload + "." + mac,
      payload + "." + flipped,
      payload, "", "x.y", payload + "." + mac + ".extra", "!".repeat(60) + "." + mac
    ];
    for (const token of forged) {
      const response = await confirmCall(token);
      expect(response.status, token.slice(0, 20)).toBe(400);
      expect(await errorCode(response)).toBe("invalid_confirm_link");
      expectCors(response);
    }
    // An expired forgery reads as forged, not expired.
    const expiredForgery = await signConfirmToken(NORMAL, "a-different-secret-0123456789abcdef", now() - CONFIRM_TTL_SECONDS - 5);
    expect(await errorCode(await confirmCall(expiredForgery))).toBe("invalid_confirm_link");
    for (const body of [{ schema_version: 1 }, { schema_version: 2, token: good }, { schema_version: 1, token: good, email: NORMAL }, { schema_version: 1, token: 7 }]) {
      const response = await call({ path: CONFIRM, body });
      expect(response.status).toBe(400);
      expectCors(response);
    }
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("limits each IP, and each inbox once its link checks out", async () => {
    const token = await signConfirmToken(NORMAL, SECRET, now());
    let fetchSpy = upstream();
    const perIp = await confirmCall(token, { vars: { PUBLIC_LIMITER: limiter(false) } });
    expect(perIp.status).toBe(429);
    expectCors(perIp);
    expect(fetchSpy).not.toHaveBeenCalled();
    vi.restoreAllMocks();
    fetchSpy = upstream();
    const address = limiter(false);
    const perInbox = await confirmCall(token, { vars: { WAITLIST_ADDRESS_LIMITER: address } });
    expect(perInbox.status).toBe(429);
    expect(fetchSpy).not.toHaveBeenCalled();
    // Its own bucket, apart from the sign-up one, keyed on a hash.
    const key = address.limit.mock.calls[0][0].key;
    expect(key).toMatch(/^[0-9a-f]{64}$/);
    const signupKey = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode("waitlist-address:" + NORMAL)))].map(b => b.toString(16).padStart(2, "0")).join("");
    expect(key).not.toBe(signupKey);
    // A forged link never spends the inbox's allowance.
    const untouched = limiter();
    await confirmCall("x".repeat(20) + "." + "A".repeat(43), { vars: { WAITLIST_ADDRESS_LIMITER: untouched } });
    expect(untouched.limit).not.toHaveBeenCalled();
  });

  it("answers 503 retryable when Resend fails, and never tries the other call on auth, permission or rate errors", async () => {
    const token = await signConfirmToken(NORMAL, SECRET, now());
    const failures: [Upstream, number][] = [
      [{ segment: resendError(401, "x") }, 1], [{ segment: resendError(403, "restricted_api_key") }, 1], [{ segment: resendError(429, "rate_limit_exceeded") }, 1],
      [{ segment: resendError(500, "application_error") }, 1], [{ segment: () => { throw new TypeError("network"); } }, 1],
      [{ segment: missing, create: resendError(401, "x") }, 2], [{ segment: missing, create: resendError(500, "x") }, 2],
      [{ segment: missing, create: resendError(422, "x") }, 3]
    ];
    for (const [answers, calls] of failures) {
      const fetchSpy = upstream(answers);
      const response = await confirmCall(token);
      expect(response.status).toBe(503);
      expect(await response.json()).toEqual({ error: { code: "waitlist_unavailable", retryable: true } });
      expectCors(response);
      expect(fetchSpy).toHaveBeenCalledTimes(calls);
      vi.restoreAllMocks();
    }
  });
});

describe("the confirm link and email", () => {
  it("round-trips, expires after seven days and is bound to its secret", async () => {
    const issued = 1_800_000_000;
    const token = await signConfirmToken(NORMAL, SECRET, issued);
    expect(await verifyConfirmToken(token, SECRET, issued + CONFIRM_TTL_SECONDS)).toEqual({ ok: true, email: NORMAL });
    expect(await verifyConfirmToken(token, SECRET, issued + CONFIRM_TTL_SECONDS + 1)).toEqual({ ok: false, reason: "expired" });
    expect(await verifyConfirmToken(token, SECRET + "x", issued)).toEqual({ ok: false, reason: "invalid" });
    expect(await verifyConfirmToken(undefined, SECRET, issued)).toEqual({ ok: false, reason: "invalid" });
    expect(token.length).toBeLessThan(200);
    expect(token).toMatch(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}$/);
  });

  it("escapes the link in the HTML part and keeps both parts", () => {
    const message = confirmEmail('https://aamirazeez.com/after-you/waitlist/confirm/#t=a"><script>');
    expect(message.html).not.toContain('"><script>');
    expect(message.html).toContain("&quot;&gt;&lt;script&gt;");
    expect(message.text).toContain("Open this link so I know this email is yours");
    expect(message.html).toContain("Yes, add me");
    expect(message.html).not.toMatch(/[–—]/);
  });

  it("stays light all the way through, so dark mode flips it as one", () => {
    const { html } = confirmEmail("https://aamirazeez.com/after-you/waitlist/confirm/#t=x");
    const brightness = (hex: string) => {
      const n = parseInt(hex.slice(1), 16);
      return 0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255);
    };
    const inline = html.split("</head>")[1];
    const backgrounds = [...inline.matchAll(/(?:background-color:|bgcolor=")(#[0-9a-f]{6})/g)].map(m => m[1]);
    const texts = [...inline.matchAll(/[^-]color:(#[0-9a-f]{6})/g)].map(m => m[1]);
    expect(backgrounds.length).toBeGreaterThan(4);
    expect(texts.length).toBeGreaterThan(4);
    // Gmail on Android darkens a background above 205 and lightens text below 150; anything between is left as is.
    for (const color of backgrounds) expect(brightness(color)).toBeGreaterThan(210);
    for (const color of texts) expect(brightness(color)).toBeLessThan(140);
    expect(html).not.toMatch(/mix-blend-mode|background-image|u \+ \.body/);
    expect(html).toContain('<meta name="color-scheme" content="light dark">');
    expect(html).toContain("@media (prefers-color-scheme:dark)");
    expect(html).toContain("[data-ogsb] .bg-card");
    expect(html).toContain('email-spirits-v2.png" width="240" height="132" alt="');
    expect(html).not.toContain(">After You</td>");
  });
});

describe("privacy", () => {
  it("describes the waitlist on /privacy, whatever the flag, with its own removal contact", async () => {
    for (const flag of ["true", "false"]) {
      const response = await worker.fetch(new Request("https://game.test/privacy"), withConfig({ ...env, IOS_WAITLIST_ENABLED: flag }) as unknown as Env);
      expect(response.status).toBe(200);
      const page = await response.text();
      expect(page).toContain("<h2>The iPhone waitlist</h2>");
      expect(page).toContain("Resend stores the list");
      expect(page).toContain("Cloudflare Turnstile");
      expect(page).toContain('<a href="mailto:afteryou-reply@aamirazeez.com">afteryou-reply@aamirazeez.com</a>');
      expect(page).not.toContain("three months");
      expect(page).toContain("In the game, we do not ask for your email address or phone number. A display name is optional, and so is signing in to Google Play Games or Game Center.");
      expect(page).toContain("After You keeps a one-way code made from your Play Games or Game Center player ID next to your online identity.");
      expect(page).toContain("the After You server never receives it. Unlinking in Settings, or deleting your online identity, removes the code.");
      expect(page).not.toMatch(/\bI('ll| will| delete| keep)\b/);
    }
  });

  it("logs no email, token, link or key on any path", async () => {
    const lines: string[] = [];
    for (const level of ["log", "info", "warn", "error", "debug"] as const) vi.spyOn(console, level).mockImplementation((...args: unknown[]) => { lines.push(args.map(String).join(" ")); });
    const token = await signConfirmToken(NORMAL, SECRET, now());
    const signups: Upstream[] = [{}, { send: resendError(500, "x") }, { send: resendError(422, "x") }, { siteverify: () => new Response("x", { status: 500 }) }, { send: () => { throw new TypeError("network " + EMAIL); } }];
    for (const answers of signups) { upstream(answers); await call(); vi.mocked(globalThis.fetch).mockRestore(); }
    const confirms: Upstream[] = [{}, { segment: resendError(404, "x") }, { segment: resendError(404, "x"), create: resendError(422, "x") }, { segment: resendError(401, "x") }];
    for (const answers of confirms) { upstream(answers); await confirmCall(token); vi.mocked(globalThis.fetch).mockRestore(); }
    for (const [status, name] of [[429, "daily_quota_exceeded"], [422, "invalid_from_address"], [422, "validation_error"]] as const) { upstream({ send: resendError(status, name) }); await call(); vi.mocked(globalThis.fetch).mockRestore(); }
    await call({ vars: { RESEND_API_KEY: undefined } });
    expect(lines.length).toBeGreaterThan(0);
    const all = lines.join("\n").toLowerCase();
    for (const secret of [EMAIL, "someone.waiting", "example.com", TOKEN, token, token.split(".")[1], VARS.RESEND_API_KEY, VARS.TURNSTILE_SECRET_KEY, SECRET, SEGMENT]) expect(all).not.toContain(secret.toLowerCase());
  });
});
