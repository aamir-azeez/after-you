import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { withConfig } from "./config";
import { countingEnv } from "./meter";
import { COSTLY_ROUTES, COSTLY_IN_ROUTE, MemoryBudget, costlyKind, ipKey } from "../src/limits";
import { digest } from "../src/protocol";

type Account = { player_id: string; device_token: string; recovery_code: string };
const sources = import.meta.glob<string>("../src/**/*.ts", { query: "?raw", import: "default", eager: true });
let address = 0;
const recorder = (allow: (key: string) => boolean = () => true) => {
  const keys: string[] = [];
  return { keys, limiter: { limit: async ({ key }: { key: string }) => { keys.push(key); return { success: allow(key) }; } } };
};
async function call(path: string, method = "GET", a?: Account, body?: unknown, overrides: Partial<Env> = {}, ip = "198.18.9." + ++address) {
  return worker.fetch(new Request("https://limits.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip, ...(a ? { "X-Player-Id": a.player_id, Authorization: "Bearer " + a.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), withConfig({ ...env, ...overrides }));
}
async function create(): Promise<Account> { const r = await call("/v1/identity", "POST", undefined, {}); expect(r.status).toBe(201); return r.json<Account>(); }
afterEach(async () => { await reset(); });

describe("one limits module", () => {
  it("is the only place that calls a rate limit binding", () => {
    const callers = Object.entries(sources).filter(([path, text]) => !path.endsWith("/src/limits.ts") && /\.limit\(\{/.test(text)).map(([path]) => path);
    expect(callers).toEqual([]);
  });

  it("keys an IPv6 address by its /64 and an IPv4 address as it is, hashed", async () => {
    expect(ipKey("2001:db8:85a3:12:8a2e:370:7334:1")).toBe("2001:db8:85a3:12::/64");
    expect(ipKey("::ffff:203.0.113.9")).toBe("203.0.113.9");
    const { keys, limiter } = recorder();
    for (const ip of ["2001:db8:85a3:12::1", "2001:db8:85a3:12:ffff::2"]) expect((await call("/v1/identity", "POST", undefined, {}, { PUBLIC_LIMITER: limiter }, ip)).status).toBe(201);
    expect(keys[0]).toBe(keys[1]);
    expect(keys[0]).toBe(await digest("2001:db8:85a3:12::/64"));
  });

  it("refuses a signed-in request over the address limit before any Player request, and never keys it by the claimed id", async () => {
    const a = await create(), { keys, limiter } = recorder(() => false), counted = countingEnv(withConfig({ ...env, AUTH_LIMITER: limiter }));
    const refused = await worker.fetch(new Request("https://limits.test/v1/identity", { headers: { "X-Player-Id": a.player_id, Authorization: "Bearer " + a.device_token, "CF-Connecting-IP": "203.0.113.40" } }), counted.env);
    expect(refused.status).toBe(429); expect(refused.headers.get("Retry-After")).toBe("60");
    expect((await refused.json<{ error: { code: string; retryable: boolean } }>()).error).toEqual({ code: "rate_limited", retryable: true });
    expect(counted.calls).toEqual([]);
    expect(keys).toEqual([await digest("203.0.113.40")]);
    // Malformed credentials are refused for free, before the limiter is spent.
    const free = recorder();
    expect((await call("/v1/identity", "GET", { ...a, device_token: "short" }, undefined, { AUTH_LIMITER: free.limiter })).status).toBe(401);
    expect(free.keys).toEqual([]);
  });

  it("lets four busy phones through one address: each at the per-player limit", async () => {
    const phones = [await create(), await create(), await create(), await create()];
    for (let i = 0; i < 110; i++) for (const p of phones) expect((await call("/v1/identity", "GET", p, undefined, {}, "203.0.113.41")).status).toBe(200);
  }, 120_000);
});

describe("the costly class", () => {
  it("names routes the phone sends on taps, purchases and hosted rooms, never its timers", () => {
    expect(costlyKind("POST", "/v1/social/publication")).toBe("publication");
    expect(costlyKind("POST", "/v1/friends/request")).toBe("friend-request");
    expect(costlyKind("PUT", "/v1/leaderboards/me")).toBe("leaderboard-name");
    expect(costlyKind("POST", "/v1/friends/accept")).toBe("friend-accept");
    expect(costlyKind("POST", "/v1/safety/blocks/" + "a".repeat(22))).toBe("block");
    // Read on timers and live hints, or sent in quick tries, each with its own guard; or costly only in part (COSTLY_IN_ROUTE).
    for (const [method, path] of [["GET", "/v1/friends"], ["GET", "/v1/social/inbox"], ["POST", "/v1/presence"], ["GET", "/v1/leaderboards/me"], ["DELETE", "/v1/safety/blocks/" + "a".repeat(22)],
      ["DELETE", "/v1/friends/" + "a".repeat(22)], ["POST", "/v1/pollen/bundle-claims"], ["GET", "/v1/entitlement"], ["POST", "/v1/friends/share"], ["POST", `/v1/friends/${"a".repeat(22)}/notifications`]])
      expect(costlyKind(method, path)).toBeNull();
    expect(new Set([...COSTLY_ROUTES.map(route => route.kind), ...COSTLY_IN_ROUTE]).size).toBe(COSTLY_ROUTES.length + COSTLY_IN_ROUTE.length);
  });

  it("spends one bucket per kind and player, and answers a retryable 429 with no work done", async () => {
    const [a, b] = [await create(), await create()], { keys, limiter } = recorder(key => !key.startsWith("costly:friend-request:"));
    const counted = countingEnv(withConfig({ ...env, TESTER_CODE_LIMITER: limiter }));
    const refused = await worker.fetch(new Request("https://limits.test/v1/friends/request", { method: "POST", headers: { "Content-Type": "application/json", "X-Player-Id": a.player_id, Authorization: "Bearer " + a.device_token, "CF-Connecting-IP": "203.0.113.42" },
      body: JSON.stringify({ schema_version: 1, friend_code: b.player_id }) }), counted.env);
    expect(refused.status).toBe(429);
    expect((await refused.json<{ error: { code: string } }>()).error.code).toBe("rate_limited");
    expect(keys).toEqual(["costly:friend-request:" + a.player_id]);
    // Only auth()'s own Player call was made.
    expect(counted.calls).toEqual(["PLAYERS.authorize"]);
  });

  it("limits a share only when it changes the shared room", async () => {
    const a = await create();
    const room = await (await call("/v1/rooms", "POST", a, { idempotency_key: crypto.randomUUID() })).json<{ room_id: string }>();
    const { keys, limiter } = recorder(), share = (value: unknown) => call("/v1/friends/share", "POST", a, { schema_version: 1, room: value }, { TESTER_CODE_LIMITER: limiter });
    expect((await share({ api_version: 1, room_id: room.room_id })).status).toBe(200);
    expect((await share({ api_version: 1, room_id: room.room_id })).status).toBe(200);
    expect(keys).toEqual(["costly:friend-share:" + a.player_id]);
    expect((await share(null)).status).toBe(200);
    expect(keys.length).toBe(2);
  });
});

describe("memory budgets", () => {
  it("counts at most `limit` in any window", () => {
    const budget = new MemoryBudget(3, 60_000);
    expect([0, 1, 2, 3].map(t => budget.take(t * 1000))).toEqual([true, true, true, false]);
    expect(budget.take(60_000)).toBe(true);
    expect(budget.take(60_500)).toBe(false);
  });
});
