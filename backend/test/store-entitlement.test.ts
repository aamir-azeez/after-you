import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { entitlement } from "../src/entitlement";
import { playEntitlement } from "../src/play-entitlement";
import { storeEntitlement, type StoreEntitlementConfig } from "../src/store-entitlement";
import { rollingHome } from "../src/v2/protocol-cooperative";
import worker from "../src/index";

// Synthetic provider data only: nothing here has met a real App Store purchase.
const owner = "p".repeat(22);
const play: StoreEntitlementConfig = { REVENUECAT_SECRET_KEY: "synthetic-only", REVENUECAT_PROJECT_ID: "projSynthetic", REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID: "entlPlay", REVENUECAT_PLAY_PRODUCT_ID: "prodPlay", REVENUECAT_PLAY_ENVIRONMENT: "production", REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS: "prodMonthly,prodYearly" };
const stores: StoreEntitlementConfig = { ...play, REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS: "prodIosMonthly, prodIosYearly" };
const grant = (entitlement_id = "entlPlay", expires_at: number | null = null) => ({ entitlement_id, expires_at });
const purchase = (change: Record<string, unknown> = {}) => ({ object: "purchase", product_id: "prodPlay", store: "play_store", environment: "production", status: "owned", ownership: "purchased", purchased_at: Date.now() - 10000, ...change });
const playPlan = (change: Record<string, unknown> = {}) => ({ object: "subscription", product_id: "prodMonthly", store: "play_store", environment: "production", ownership: "purchased", gives_access: true, status: "active", ...change });
const iosPlan = (change: Record<string, unknown> = {}) => ({ object: "subscription", product_id: "prodIosMonthly", store: "app_store", environment: "production", ownership: "purchased", gives_access: true, status: "active", ...change });
const list = (items: unknown[], next_page: string | null = null) => ({ object: "list", items, next_page });

type Reply = unknown | (() => Response);
type Customer = { active?: Reply; purchases?: Reply; subscriptions?: Reply | Record<string, Reply> };
/** Routes each RevenueCat read; `subscriptions` may be keyed by environment. */
function provider(customer: Customer = {}) {
  const reply = (value: Reply) => typeof value === "function" ? (value as () => Response)() : Response.json(value);
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (url, options) => {
    expect(url instanceof Request ? url.redirect : options?.redirect).toBe("manual");
    const target = new URL(url instanceof Request ? url.url : String(url));
    if (target.pathname.endsWith("/active_entitlements")) return reply(customer.active ?? list([grant()]));
    if (target.pathname.endsWith("/purchases")) return reply(customer.purchases ?? list([]));
    if (target.pathname.endsWith("/subscriptions")) {
      const plans = customer.subscriptions ?? list([]);
      const keyed = typeof plans === "object" && plans !== null && !("object" in plans);
      return reply(keyed ? (plans as Record<string, Reply>)[target.searchParams.get("environment")!] ?? list([]) : plans);
    }
    throw new Error("unexpected provider read " + target.pathname);
  });
}
const reads = (requests: ReturnType<typeof provider>) => requests.mock.calls.map(([url]) => { const target = new URL(url instanceof Request ? url.url : String(url)); return target.pathname.split("/").pop() + target.search; });
const admittedBy = (access_source: string, entitlement = "full_journey_play") => ({ full_journey: true, status: "verified", access_source, entitlement, player_id: owner });
const refused = { full_journey: false, status: "verified" };
const unconfigured = { full_journey: false, status: "unconfigured" };
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("APP_STORE_ENTITLEMENTS_ENABLED gate", () => {
  const customers: [string, Customer][] = [
    ["App Store subscriber", { subscriptions: list([iosPlan()]) }],
    ["Play purchaser", { purchases: list([purchase()]) }],
    ["Play subscriber", { subscriptions: list([playPlan()]) }],
    ["no grant", { active: list([]) }],
    ["provider failure", { active: () => new Response(null, { status: 503 }) }]
  ];
  it.each([undefined, "", "false", "TRUE", "1", " true", "yes"])("flag %j keeps the Play-only check, reads included", async flag => {
    for (const [, customer] of customers) {
      const expected = provider(customer); const before = await playEntitlement(owner, stores); const expectedReads = reads(expected); vi.restoreAllMocks();
      const requests = provider(customer);
      const { checked_at, environment, ...result } = await entitlement(owner, { ...env, ...stores, REVENUECAT_VERIFICATION_MODE: "play_store", APP_STORE_ENTITLEMENTS_ENABLED: flag });
      expect(typeof checked_at).toBe("string"); expect(environment).toBe(env.ENVIRONMENT);
      expect(result).toEqual(before); expect(reads(requests)).toEqual(expectedReads); vi.restoreAllMocks();
    }
  });
  it("admits an App Store subscriber only once the flag is exactly \"true\"", async () => {
    provider({ subscriptions: list([iosPlan()]) });
    const off = await entitlement(owner, { ...env, ...stores, REVENUECAT_VERIFICATION_MODE: "play_store" });
    expect(off).toMatchObject(refused); expect(off.access_source).toBeUndefined();
    const on = await entitlement(owner, { ...env, ...stores, REVENUECAT_VERIFICATION_MODE: "play_store", APP_STORE_ENTITLEMENTS_ENABLED: "true" });
    expect(on).toEqual({ ...admittedBy("app_store_subscription"), environment: env.ENVIRONMENT, checked_at: expect.any(String) });
  });
  it("does nothing outside play_store mode", async () => {
    provider({ active: list([grant("entlDemo")]) });
    const demo = { ...env, ...stores, APP_STORE_ENTITLEMENTS_ENABLED: "true", REVENUECAT_API_VERSION: "2", REVENUECAT_ENTITLEMENT_LOOKUP_ID: "entlDemo" };
    expect(await entitlement(owner, demo)).toMatchObject({ full_journey: true, status: "verified" });
    expect((await entitlement(owner, { ...demo, REVENUECAT_VERIFICATION_MODE: "app_store" })).status).toBe("unconfigured");
  });
});

describe("Play hosts with the flag on", () => {
  it.each<[string, Customer, number]>([
    ["grandfathered one-time purchase", { purchases: list([purchase()]) }, 2],
    ["monthly subscription", { subscriptions: list([playPlan()]) }, 3],
    ["yearly subscription in the grace period", { subscriptions: list([playPlan({ product_id: "prodYearly", status: "in_grace_period" })]) }, 3],
    ["cancelled subscription still paid through", { subscriptions: list([playPlan({ auto_renewal_status: "will_not_renew" })]) }, 3],
    ["expired subscription", { subscriptions: list([playPlan({ status: "expired", gives_access: false })]) }, 3],
    ["account hold", { subscriptions: list([playPlan({ status: "in_billing_retry", gives_access: false })]) }, 3],
    ["refunded purchase", { purchases: list([purchase({ status: "refunded" })]) }, 3],
    ["no grant", { active: list([]) }, 1],
    ["expired grant", { active: list([grant("entlPlay", 1)]), purchases: list([purchase()]) }, 1]
  ])("gives the same answer and reads for a %s", async (_name, customer, count) => {
    const expected = provider(customer); const before = await playEntitlement(owner, play); const expectedReads = reads(expected); vi.restoreAllMocks();
    const requests = provider(customer);
    expect(await storeEntitlement(owner, stores)).toEqual(before);
    expect(reads(requests)).toEqual(expectedReads); expect(requests).toHaveBeenCalledTimes(count);
  });
  it("keeps one-time-only Play admission when no Play subscription list is set", async () => {
    const requests = provider({ purchases: list([purchase()]) });
    expect(await storeEntitlement(owner, { ...stores, REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS: undefined })).toEqual(admittedBy("play_purchase"));
    expect(requests).toHaveBeenCalledTimes(2);
  });
  it("keeps review access to the allowlist plus a live grant", async () => {
    const requests = provider();
    expect(await storeEntitlement(owner, { ...stores, REVENUECAT_REVIEWER_IDS: owner })).toEqual(admittedBy("review_grant")); expect(requests).toHaveBeenCalledTimes(1);
    vi.restoreAllMocks(); provider({ active: list([]) });
    expect(await storeEntitlement(owner, { ...stores, REVENUECAT_REVIEWER_IDS: owner })).toEqual(refused);
  });
});

describe("App Store subscriptions", () => {
  it.each([["monthly", {}], ["yearly", { product_id: "prodIosYearly" }], ["introductory trial", { status: "trialing" }], ["billing grace period", { status: "in_grace_period" }], ["cancelled but paid through the period", { auto_renewal_status: "will_not_renew" }]])("admits an active %s subscription", async (_name, change) => {
    const requests = provider({ subscriptions: list([iosPlan(change)]) });
    expect(await storeEntitlement(owner, stores)).toEqual(admittedBy("app_store_subscription"));
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "purchases?environment=production&limit=100", "subscriptions?environment=production&limit=100"]);
  });
  it.each([
    ["expired", { status: "expired", gives_access: false }], ["in billing retry", { status: "in_billing_retry", gives_access: false }],
    ["in billing retry even if access is claimed", { status: "in_billing_retry" }], ["paused", { status: "paused" }], ["unknown", { status: "unknown" }],
    ["without access", { gives_access: false }], ["from the Mac App Store", { store: "mac_app_store" }], ["promotional", { store: "promotional" }],
    ["from the Test Store", { store: "test_store" }], ["sandbox in production", { environment: "sandbox" }], ["a Play product on the App Store", { product_id: "prodMonthly" }],
    ["an unknown product", { product_id: "prodOther" }], ["without a product", { product_id: null }], ["family shared", { ownership: "family_shared" }],
    ["shaped as a purchase", { object: "purchase" }]
  ])("refuses a subscription that is %s", async (_name, change) => {
    provider({ subscriptions: list([iosPlan(change)]) });
    expect(await storeEntitlement(owner, stores)).toEqual(refused);
  });
  it("refuses an App Store product reported under Play", async () => {
    provider({ subscriptions: list([iosPlan({ store: "play_store" })]) });
    expect(await storeEntitlement(owner, stores)).toEqual(refused);
  });
  it("needs the active entitlement before an App Store subscription counts", async () => {
    for (const active of [list([]), list([grant("entlPlay", Date.now() - 1000)]), list([grant("entlOther")])]) {
      const requests = provider({ active, subscriptions: list([iosPlan()]) });
      expect(await storeEntitlement(owner, stores)).toEqual(refused); expect(requests).toHaveBeenCalledTimes(1); vi.restoreAllMocks();
    }
  });
  it("reads App Store sandbox separately from Play production", async () => {
    const sandbox = { ...stores, REVENUECAT_APP_STORE_ENVIRONMENT: "sandbox" };
    let requests = provider({ subscriptions: { sandbox: list([iosPlan({ environment: "sandbox" })]) } });
    expect(await storeEntitlement(owner, sandbox)).toEqual(admittedBy("app_store_subscription"));
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "purchases?environment=production&limit=100", "subscriptions?environment=production&limit=100", "subscriptions?environment=sandbox&limit=100"]);
    vi.restoreAllMocks(); provider({ subscriptions: { sandbox: list([iosPlan()]) } });
    expect(await storeEntitlement(owner, sandbox)).toEqual(refused);
    vi.restoreAllMocks(); requests = provider({ subscriptions: { production: list([playPlan()]) } });
    expect(await storeEntitlement(owner, sandbox)).toEqual(admittedBy("play_subscription")); expect(requests).toHaveBeenCalledTimes(3);
  });
  it("supports a separate App Store entitlement", async () => {
    const parallel = { ...stores, REVENUECAT_APP_STORE_ENTITLEMENT_LOOKUP_ID: "entlApp" };
    provider({ active: list([grant("entlApp")]), subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, parallel)).toEqual(admittedBy("app_store_subscription", "full_journey"));
    vi.restoreAllMocks(); const requests = provider({ active: list([grant("entlApp")]), purchases: list([purchase()]), subscriptions: list([playPlan()]) });
    expect(await storeEntitlement(owner, parallel)).toEqual(refused);
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "subscriptions?environment=production&limit=100"]);
    vi.restoreAllMocks(); provider({ active: list([grant()]), subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, parallel)).toEqual(refused);
    vi.restoreAllMocks(); provider({ active: list([grant()]), purchases: list([purchase()]) });
    expect(await storeEntitlement(owner, parallel)).toEqual(admittedBy("play_purchase"));
  });
});

describe("hosts with both stores", () => {
  it("prefers the Play purchase and stops reading", async () => {
    const requests = provider({ purchases: list([purchase()]), subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, stores)).toEqual(admittedBy("play_purchase")); expect(requests).toHaveBeenCalledTimes(2);
  });
  it("reports the Play subscription when both stores have one", async () => {
    provider({ subscriptions: list([iosPlan(), playPlan()]) });
    expect(await storeEntitlement(owner, stores)).toEqual(admittedBy("play_subscription"));
  });
  it("admits through the App Store once the Play subscription has lapsed", async () => {
    const requests = provider({ purchases: list([purchase({ status: "refunded" })]), subscriptions: list([playPlan({ status: "expired", gives_access: false }), iosPlan()]) });
    expect(await storeEntitlement(owner, stores)).toEqual(admittedBy("app_store_subscription")); expect(requests).toHaveBeenCalledTimes(3);
  });
  it("refuses when both stores have lapsed", async () => {
    provider({ subscriptions: list([playPlan({ status: "in_billing_retry", gives_access: false }), iosPlan({ status: "expired", gives_access: false })]) });
    expect(await storeEntitlement(owner, stores)).toEqual(refused);
  });
});

describe("store settings fail closed for their own store", () => {
  const badLists = ["after_you_full_journey_monthly_ios", "prodIosMonthly,not-a-product", Array.from({ length: 9 }, (_, i) => `prod${i}`).join(",")];
  it.each(badLists)("a malformed App Store list %j holds App Store hosts and leaves Play hosts alone", async bad => {
    const config = { ...stores, REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS: bad };
    provider({ subscriptions: list([iosPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(unconfigured);
    vi.restoreAllMocks(); provider({ purchases: list([purchase()]) }); expect(await storeEntitlement(owner, config)).toEqual(admittedBy("play_purchase"));
    vi.restoreAllMocks(); provider({ subscriptions: list([playPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(admittedBy("play_subscription"));
    vi.restoreAllMocks(); provider({ active: list([]) }); expect(await storeEntitlement(owner, config)).toEqual(refused);
  });
  it.each([[{ REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS: undefined }], [{ REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS: " , " }], [{ REVENUECAT_APP_STORE_ENVIRONMENT: "Production" }], [{ REVENUECAT_APP_STORE_ENVIRONMENT: "staging" }]])("an unset list or bad environment %j holds rather than refusing", async change => {
    const requests = provider({ subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, { ...stores, ...change })).toEqual(unconfigured);
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "purchases?environment=production&limit=100", "subscriptions?environment=production&limit=100"]);
  });
  it("a malformed Play subscription list holds Play subscribers and still admits App Store hosts", async () => {
    const config = { ...stores, REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS: "after_you_full_journey_monthly" };
    let requests = provider({ subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, config)).toEqual(admittedBy("app_store_subscription"));
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "subscriptions?environment=production&limit=100"]);
    vi.restoreAllMocks(); provider({ subscriptions: list([playPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(unconfigured);
    vi.restoreAllMocks(); requests = provider({ subscriptions: list([iosPlan()]) });
    expect(await entitlement(owner, { ...env, ...config, REVENUECAT_VERIFICATION_MODE: "play_store" })).toMatchObject(unconfigured); expect(requests).not.toHaveBeenCalled();
  });
  it("a missing Play product or environment holds Play and review but not the App Store", async () => {
    for (const change of [{ REVENUECAT_PLAY_PRODUCT_ID: "" }, { REVENUECAT_PLAY_ENVIRONMENT: "staging" }]) {
      provider({ subscriptions: list([iosPlan()]) }); expect(await storeEntitlement(owner, { ...stores, ...change })).toEqual(admittedBy("app_store_subscription"));
      vi.restoreAllMocks(); provider({ purchases: list([purchase()]) }); expect(await storeEntitlement(owner, { ...stores, ...change, REVENUECAT_REVIEWER_IDS: owner })).toEqual(unconfigured);
      vi.restoreAllMocks();
    }
  });
  it("a malformed App Store entitlement ID holds only the App Store", async () => {
    const config = { ...stores, REVENUECAT_APP_STORE_ENTITLEMENT_LOOKUP_ID: "full_journey_ios" };
    provider({ subscriptions: list([iosPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(unconfigured);
    vi.restoreAllMocks(); provider({ purchases: list([purchase()]) }); expect(await storeEntitlement(owner, config)).toEqual(admittedBy("play_purchase"));
  });
  it.each([{ REVENUECAT_SECRET_KEY: "" }, { REVENUECAT_PROJECT_ID: "x" }, { REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID: "full_journey_play" }])("shared settings %j hold before any read", async change => {
    const requests = provider({ subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, { ...stores, ...change })).toEqual(unconfigured); expect(requests).not.toHaveBeenCalled();
  });
});

describe("RevenueCat failures", () => {
  const failed = (status: number) => () => new Response(null, { status });
  it("holds when the entitlement read fails, is malformed or is cut short", async () => {
    provider({ active: failed(503) }); expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_http_503" });
    vi.restoreAllMocks(); provider({ active: { object: "list", items: "nope" } }); expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_invalid_list" });
    vi.restoreAllMocks(); provider({ active: list([grant("entlOther")], "/next") }); expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_incomplete_list" });
    vi.restoreAllMocks(); vi.spyOn(globalThis, "fetch").mockRejectedValue(new TypeError("network")); expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_request_or_decode_failed" });
  });
  it("treats an unknown customer as unpaid", async () => {
    const requests = provider({ active: failed(404) }); expect(await storeEntitlement(owner, stores)).toEqual(refused); expect(requests).toHaveBeenCalledTimes(1);
  });
  it("still admits an App Store subscriber when the Play purchase read fails", async () => {
    provider({ purchases: failed(500), subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, stores)).toEqual(admittedBy("app_store_subscription"));
    vi.restoreAllMocks(); provider({ purchases: failed(500) });
    expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_http_500" });
  });
  it("holds when the subscription read fails or is cut short", async () => {
    provider({ subscriptions: failed(503) }); expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_http_503" });
    vi.restoreAllMocks(); provider({ subscriptions: list([], "/next") }); expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_incomplete_list" });
    vi.restoreAllMocks(); provider({ subscriptions: { object: "list", items: Array.from({ length: 101 }, () => iosPlan()) } }); expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_invalid_list" });
  });
  it("still admits a Play subscriber when the separate App Store sandbox read fails", async () => {
    provider({ subscriptions: { production: list([playPlan()]), sandbox: failed(503) } });
    expect(await storeEntitlement(owner, { ...stores, REVENUECAT_APP_STORE_ENVIRONMENT: "sandbox" })).toEqual(admittedBy("play_subscription"));
    vi.restoreAllMocks(); provider({ subscriptions: { production: list([]), sandbox: failed(503) } });
    expect(await storeEntitlement(owner, { ...stores, REVENUECAT_APP_STORE_ENVIRONMENT: "sandbox" })).toEqual({ full_journey: false, status: "unavailable", reason: "provider_http_503" });
  });
  it("treats a missing subscription record as no subscription", async () => {
    provider({ subscriptions: failed(404) }); expect(await storeEntitlement(owner, stores)).toEqual(refused);
  });
});

describe("paid room creation through the Worker", () => {
  let requestNo = 0;
  async function call(path: string, account: { player_id: string; device_token: string } | undefined, body: unknown, overrides: Record<string, unknown> = {}) {
    const configured: Env = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true", ...overrides });
    return worker.fetch(new Request("https://after-you.test" + path, { method: account && body === undefined ? "GET" : "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.2." + ++requestNo,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
  }
  it("keeps the shipped error codes and adds the App Store source", async () => {
    const created = await call("/v1/identity", undefined, {}); expect(created.status).toBe(201);
    const host = await created.json<{ player_id: string; device_token: string }>();
    const live = { ...stores, REVENUECAT_VERIFICATION_MODE: "play_store" };
    provider({ subscriptions: list([iosPlan()]) });
    const off = await call("/v2/rooms", host, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, live);
    expect(off.status).toBe(402); expect(await off.json()).toMatchObject({ error: { code: "host_unlock_required" } });
    const held = await call("/v2/rooms", host, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, { ...live, APP_STORE_ENTITLEMENTS_ENABLED: "true", REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS: "after_you_full_journey_monthly_ios" });
    expect(held.status).toBe(503); expect(await held.json()).toMatchObject({ error: { code: "entitlement_unavailable" } });
    const on = await call("/v2/rooms", host, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, { ...live, APP_STORE_ENTITLEMENTS_ENABLED: "true" });
    expect(on.status).toBe(200);
    const checked = await call("/v1/entitlement", host, undefined, { ...live, APP_STORE_ENTITLEMENTS_ENABLED: "true" });
    expect(checked.status).toBe(200); expect(await checked.json()).toMatchObject({ full_journey: true, status: "verified", access_source: "app_store_subscription", entitlement: "full_journey_play", player_id: host.player_id });
  });
});
