import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { entitlement } from "../src/entitlement";
import { playEntitlement, revenuecatRequest } from "../src/play-entitlement";
import type { ServerVars } from "../src/flags";
import { configJson } from "./config";
import worker from "../src/index";
import { randomToken } from "../src/protocol";

const owner = "p".repeat(22);
const RC = { project_id: "projSynthetic", play_entitlement_lookup_id: "entlPlay", play_product_id: "prodPlay" };
/** RevenueCat as live configures it: the secret key beside CONFIG's ids. `raw` writes ids the runners would refuse. */
const rc = (ids: Record<string, unknown> = {}, raw = false): ServerVars => ({ REVENUECAT_SECRET_KEY: "synthetic-only", CONFIG: configJson({ revenuecat: { ...RC, ...ids } }, { raw }) });
const config = rc();
const active = () => ({ object: "list", items: [{ entitlement_id: "entlPlay", expires_at: null }], next_page: null });
const purchase = () => ({ object: "purchase", product_id: "prodPlay", store: "play_store", environment: "production", status: "owned", ownership: "purchased", purchased_at: Date.now() - 10000 });
function provider(grants: unknown = active(), purchases: unknown = { object: "list", items: [purchase()], next_page: null }) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (url, options) => {
    expect(url instanceof Request ? url.redirect : options?.redirect).toBe("manual"); expect(url instanceof Request ? url.signal : options?.signal).toBeInstanceOf(AbortSignal);
    return Response.json((url instanceof Request ? url.url : String(url)).includes("active_entitlements") ? grants : purchases);
  });
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });
const subscriptionConfig = rc({ play_subscription_product_ids: ["prodMonthly", "prodYearly"] });
const subscription = (change: Record<string, unknown> = {}) => ({ object: "subscription", product_id: "prodMonthly", store: "play_store", environment: "production", ownership: "purchased", gives_access: true, status: "active", ...change });
function subscriptionProvider(items: unknown[], purchases: unknown[] = [], nextPage: string | null = null) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (url, options) => {
    expect(url instanceof Request ? url.redirect : options?.redirect).toBe("manual");
    const target = url instanceof Request ? url.url : String(url);
    if (target.includes("active_entitlements")) return Response.json(active());
    if (target.includes("/subscriptions?")) return Response.json({ object: "list", items, next_page: nextPage });
    return Response.json({ object: "list", items: purchases, next_page: null });
  });
}
describe("server-selected Play subscription policy", () => {
  it.each([["monthly", {}], ["yearly", { product_id: "prodYearly" }], ["grace period", { status: "in_grace_period" }], ["cancelled but paid through the period", { status: "active", auto_renewal_status: "will_not_renew" }]])("admits an active %s subscription", async (_name, change) => {
    const requests = subscriptionProvider([subscription(change)]);
    expect(await playEntitlement(owner, subscriptionConfig)).toEqual({ full_journey: true, status: "verified", access_source: "play_subscription", entitlement: "full_journey_play", player_id: owner });
    expect(requests).toHaveBeenCalledTimes(3); expect(String(requests.mock.calls[2][0])).toContain(`/customers/${owner}/subscriptions?environment=production&limit=100`);
  });
  it.each([{ status: "expired", gives_access: false }, { status: "in_billing_retry", gives_access: false }, { status: "paused" }, { gives_access: false }, { store: "test_store" }, { store: "promotional" }, { environment: "sandbox" }, { product_id: "prodOther" }, { product_id: null }, { ownership: "family_shared" }, { object: "purchase" }])("rejects an expired, foreign or mismatched subscription %j", async change => {
    subscriptionProvider([subscription(change)]);
    expect(await playEntitlement(owner, subscriptionConfig)).toEqual({ full_journey: false, status: "verified" });
  });
  it("keeps the grandfathered one-time purchase without asking for subscriptions", async () => {
    const requests = subscriptionProvider([], [purchase()]);
    expect(await playEntitlement(owner, subscriptionConfig)).toMatchObject({ full_journey: true, access_source: "play_purchase" });
    expect(requests).toHaveBeenCalledTimes(2);
  });
  it("leaves one-time-only admission unchanged while no subscription product is configured", async () => {
    const requests = subscriptionProvider([subscription()]);
    expect(await playEntitlement(owner, config)).toEqual({ full_journey: false, status: "verified" });
    expect(requests).toHaveBeenCalledTimes(2);
    requests.mockClear(); expect(await playEntitlement(owner, rc({ play_subscription_product_ids: [] }))).toEqual({ full_journey: false, status: "verified" }); expect(requests).toHaveBeenCalledTimes(2);
  });
  it("holds instead of refusing subscribers when the subscription product list is malformed", async () => {
    const requests = subscriptionProvider([subscription()]);
    for (const bad of [["after_you_full_journey_monthly", "after_you_full_journey_yearly"], ["prodMonthly", "not-a-product"], Array.from({ length: 9 }, (_, i) => `prod${i}`), "prodMonthly", [7]]) {
      requests.mockClear(); expect(await playEntitlement(owner, rc({ play_subscription_product_ids: bad }, true))).toEqual({ full_journey: false, status: "unconfigured" }); expect(requests).not.toHaveBeenCalled();
    }
  });
  it("holds on incomplete or failed subscription reads", async () => {
    subscriptionProvider([], [], "/next");
    expect(await playEntitlement(owner, subscriptionConfig)).toMatchObject({ full_journey: false, status: "unavailable", reason: "provider_incomplete_list" });
    vi.restoreAllMocks();
    vi.spyOn(globalThis, "fetch").mockImplementation(async url => {
      const target = url instanceof Request ? url.url : String(url);
      if (target.includes("active_entitlements")) return Response.json(active());
      if (target.includes("/subscriptions?")) return new Response(null, { status: 503 });
      return Response.json({ object: "list", items: [], next_page: null });
    });
    expect(await playEntitlement(owner, subscriptionConfig)).toMatchObject({ full_journey: false, status: "unavailable", reason: "provider_http_503" });
  });
  it("needs the active entitlement before any subscription counts", async () => {
    const requests = vi.spyOn(globalThis, "fetch").mockImplementation(async url => Response.json((url instanceof Request ? url.url : String(url)).includes("active_entitlements") ? { object: "list", items: [], next_page: null } : { object: "list", items: [subscription()], next_page: null }));
    expect(await playEntitlement(owner, subscriptionConfig)).toEqual({ full_journey: false, status: "verified" }); expect(requests).toHaveBeenCalledTimes(1);
  });
});
describe("server-selected Play purchase policy", () => {
  it("requires the configured active entitlement and exact owned production Play product", async () => {
    const requests = provider(); expect(await playEntitlement(owner, config)).toMatchObject({ full_journey: true, status: "verified", access_source: "play_purchase", player_id: owner, entitlement: "full_journey_play" });
    expect(requests).toHaveBeenCalledTimes(2); expect(String(requests.mock.calls[1][0])).toContain("purchases?environment=production&limit=100");
  });
  it.each([{ store: "test_store" }, { environment: "sandbox" }, { product_id: "prodDemo" }, { status: "refunded" }, { ownership: "family_shared" }, { purchased_at: Date.now() + 86400000 }])("rejects mismatched or inactive purchase %j", async change => {
    provider(active(), { object: "list", items: [{ ...purchase(), ...change }], next_page: null });
    expect(await playEntitlement(owner, config)).toEqual({ full_journey: false, status: "verified" });
  });
  it.each([{ entitlement_id: "entlDemo", expires_at: null }, { entitlement_id: "entlPlay", expires_at: 1 }])("does not use purchases to bypass the active entitlement %j", async grant => {
    const requests = provider({ object: "list", items: [grant], next_page: null });
    expect((await playEntitlement(owner, config)).full_journey).toBe(false); expect(requests).toHaveBeenCalledTimes(1);
  });
  it("allows review only with both exact operator allowlist and fresh remote grant", async () => {
    const requests = provider();
    expect(await playEntitlement(owner, rc({ reviewer_ids: [owner] }))).toMatchObject({ full_journey: true, access_source: "review_grant", player_id: owner });
    expect(requests).toHaveBeenCalledTimes(1);
    requests.mockResolvedValue(Response.json({ object: "list", items: [], next_page: null }));
    expect(await playEntitlement(owner, rc({ reviewer_ids: [owner] }))).toEqual({ full_journey: false, status: "verified" });
  });
  it("does not permit a different reviewer or a promotional entitlement alone", async () => {
    provider(active(), { object: "list", items: [], next_page: null });
    expect((await playEntitlement(owner, rc({ reviewer_ids: ["q".repeat(22)] }))).full_journey).toBe(false);
  });
  it("holds on incomplete provider pages and malformed configuration", async () => {
    const request = provider(active(), { object: "list", items: [], next_page: "/next" });
    expect(await playEntitlement(owner, config)).toMatchObject({ status: "unavailable", reason: "provider_incomplete_list" });
    request.mockClear(); expect(await playEntitlement(owner, rc({ play_product_id: "" }, true))).toMatchObject({ status: "unconfigured" }); expect(request).not.toHaveBeenCalled();
  });
  it("always runs the Play check: no client or var can pick another policy", async () => {
    provider();
    expect(await entitlement(owner, { ...env, ...config })).toMatchObject({ full_journey: true, access_source: "play_purchase", environment: "test-store" });
  });
  it("cancels oversized streams, rejects invalid UTF8 and never follows redirects", async () => {
    let cancelled = false;
    const request = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(new ReadableStream({ start(c) { c.enqueue(new Uint8Array(262145)); }, cancel() { cancelled = true; } })));
    expect(await revenuecatRequest("https://api.revenuecat.com/test", "synthetic")).toEqual({ ok: false, reason: "provider_response_too_large" }); expect(cancelled).toBe(true);
    request.mockResolvedValue(new Response(new Uint8Array([255]))); expect((await revenuecatRequest("https://api.revenuecat.com/test", "synthetic")).ok).toBe(false);
    request.mockResolvedValue(new Response(null, { status: 302, headers: { Location: "https://untrusted.invalid" } })); expect(await revenuecatRequest("https://api.revenuecat.com/test", "synthetic")).toEqual({ ok: false, reason: "provider_http_302" });
  });
  it("rejects a positive result after credential rotation during provider I/O", async () => {
    const create = await worker.fetch(new Request("https://game.test/v1/identity", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" }), env);
    expect(create.status).toBe(201);
    const account = await create.json<{ player_id: string; device_token: string; recovery_code: string }>();
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => {
      const response = await worker.fetch(new Request("https://game.test/v1/identity/recover", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ player_id: account.player_id, recovery_code: account.recovery_code, idempotency_key: crypto.randomUUID(), next_device_token: randomToken(), next_recovery_code: randomToken() }) }), env);
      expect(response.status).toBe(200); return Response.json(active());
    });
    const response = await worker.fetch(new Request("https://game.test/v1/entitlement", { headers: { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } }), { ...env, ...rc({ reviewer_ids: [account.player_id] }) } as unknown as Env);
    expect(response.status).toBe(401); expect(await response.json()).toMatchObject({ error: { code: "invalid_auth" } });
  });
});
