import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { entitlement as fullCheck, storeCapability } from "../src/entitlement";
import { CLIENT_HEADER } from "../src/app-status";
import { playEntitlement as playCheck } from "../src/play-entitlement";
import { storeEntitlement as storeCheck } from "../src/store-entitlement";
import type { ServerVars } from "../src/flags";
import { configJson } from "./config";
import { rollingHome } from "../src/v2/protocol-cooperative";
import worker from "../src/index";

// Synthetic provider data only: nothing here has met a real App Store purchase.
const owner = "p".repeat(22);
/** CONFIG's RevenueCat ids, plus the secret key (`secret`, default synthetic) and the flags (`features`) a check runs with. */
type Ids = Record<string, unknown> & { secret?: string; features?: string[] };
const play: Ids = { project_id: "projSynthetic", play_entitlement_lookup_id: "entlPlay", play_product_id: "prodPlay", play_subscription_product_ids: ["prodMonthly", "prodYearly"] };
const stores: Ids = { ...play, app_store_subscription_product_ids: ["prodIosMonthly", "prodIosYearly"] };
const APP_STORE_ON = ["APP_STORE_ENTITLEMENTS_ENABLED"];
/** The env a check reads: the secret beside CONFIG, written raw so a malformed id reaches the code as a hand-edited CONFIG would. */
const rc = ({ secret = "synthetic-only", features, ...ids }: Ids): ServerVars => ({ ...(secret ? { REVENUECAT_SECRET_KEY: secret } : {}),
  CONFIG: configJson({ revenuecat: ids, ...(features ? { features } : {}) }, { raw: true }) });
const storeEntitlement = (player: string, ids: Ids) => storeCheck(player, rc(ids));
const playEntitlement = (player: string, ids: Ids) => playCheck(player, rc(ids));
const entitlement = (player: string, ids: Ids) => fullCheck(player, { ...env, ...rc(ids) });
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
  it.each([[[]], [["POLLEN_EARN"]], [["APP_STORE_ENTITLEMENTS_ENABLED_LATER"]]])("features %j keep the Play-only check, reads included", async features => {
    for (const [, customer] of customers) {
      const expected = provider(customer); const before = await playEntitlement(owner, stores); const expectedReads = reads(expected); vi.restoreAllMocks();
      const requests = provider(customer);
      const { checked_at, environment, ...result } = await entitlement(owner, { ...stores, features });
      expect(typeof checked_at).toBe("string"); expect(environment).toBe("test-store");
      expect(result).toEqual(before); expect(reads(requests)).toEqual(expectedReads); vi.restoreAllMocks();
    }
  });
  it("admits an App Store subscriber only once CONFIG lists the flag", async () => {
    provider({ subscriptions: list([iosPlan()]) });
    const off = await entitlement(owner, stores);
    expect(off).toMatchObject(refused); expect(off.access_source).toBeUndefined();
    const on = await entitlement(owner, { ...stores, features: APP_STORE_ON });
    expect(on).toEqual({ ...admittedBy("app_store_subscription"), environment: "test-store", checked_at: expect.any(String) });
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
    let requests = provider(customer);
    expect(await storeEntitlement(owner, { ...stores, app_store_environment: "production" })).toEqual(before);
    expect(reads(requests)).toEqual(expectedReads); expect(requests).toHaveBeenCalledTimes(count); vi.restoreAllMocks();
    // Both App Store environments (the default): the same answer; a refused host with a live grant also costs the sandbox read.
    requests = provider(customer);
    expect(await storeEntitlement(owner, stores)).toEqual(before);
    expect(reads(requests)).toEqual([...expectedReads, ...(!before.full_journey && count === 3 ? ["subscriptions?environment=sandbox&limit=100"] : [])]);
  });
  it("keeps one-time-only Play admission when no Play subscription list is set", async () => {
    const requests = provider({ purchases: list([purchase()]) });
    expect(await storeEntitlement(owner, { ...stores, play_subscription_product_ids: undefined })).toEqual(admittedBy("play_purchase"));
    expect(requests).toHaveBeenCalledTimes(2);
  });
  it("keeps review access to the allowlist plus a live grant", async () => {
    const requests = provider();
    expect(await storeEntitlement(owner, { ...stores, reviewer_ids: [owner] })).toEqual(admittedBy("review_grant")); expect(requests).toHaveBeenCalledTimes(1);
    vi.restoreAllMocks(); provider({ active: list([]) });
    expect(await storeEntitlement(owner, { ...stores, reviewer_ids: [owner] })).toEqual(refused);
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
    ["from the Test Store", { store: "test_store" }], ["a Play product on the App Store", { product_id: "prodMonthly" }],
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
    const sandbox = { ...stores, app_store_environment: "sandbox" };
    let requests = provider({ subscriptions: { sandbox: list([iosPlan({ environment: "sandbox" })]) } });
    expect(await storeEntitlement(owner, sandbox)).toEqual(admittedBy("app_store_subscription"));
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "purchases?environment=production&limit=100", "subscriptions?environment=production&limit=100", "subscriptions?environment=sandbox&limit=100"]);
    vi.restoreAllMocks(); provider({ subscriptions: { sandbox: list([iosPlan()]) } });
    expect(await storeEntitlement(owner, sandbox)).toEqual(refused);
    vi.restoreAllMocks(); requests = provider({ subscriptions: { production: list([playPlan()]) } });
    expect(await storeEntitlement(owner, sandbox)).toEqual(admittedBy("play_subscription")); expect(requests).toHaveBeenCalledTimes(3);
  });
  it("supports a separate App Store entitlement", async () => {
    const parallel = { ...stores, app_store_entitlement_lookup_id: "entlApp" };
    provider({ active: list([grant("entlApp")]), subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, parallel)).toEqual(admittedBy("app_store_subscription", "full_journey"));
    vi.restoreAllMocks(); const requests = provider({ active: list([grant("entlApp")]), purchases: list([purchase()]), subscriptions: list([playPlan()]) });
    expect(await storeEntitlement(owner, parallel)).toEqual(refused);
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "subscriptions?environment=production&limit=100", "subscriptions?environment=sandbox&limit=100"]);
    vi.restoreAllMocks(); provider({ active: list([grant()]), subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, parallel)).toEqual(refused);
    vi.restoreAllMocks(); provider({ active: list([grant()]), purchases: list([purchase()]) });
    expect(await storeEntitlement(owner, parallel)).toEqual(admittedBy("play_purchase"));
  });
});

describe("App Store environments", () => {
  const productionRead = ["active_entitlements?limit=100", "purchases?environment=production&limit=100", "subscriptions?environment=production&limit=100"];
  const bothReads = [...productionRead, "subscriptions?environment=sandbox&limit=100"];
  const sandboxPlan = iosPlan({ environment: "sandbox" });
  it.each([["unset", undefined], ["both", "both"]])("%s accepts production or sandbox and reads sandbox only when production did not admit", async (_name, environment) => {
    const config = { ...stores, app_store_environment: environment };
    let requests = provider({ subscriptions: { production: list([iosPlan()]), sandbox: list([sandboxPlan]) } });
    expect(await storeEntitlement(owner, config)).toEqual(admittedBy("app_store_subscription")); expect(reads(requests)).toEqual(productionRead);
    vi.restoreAllMocks(); requests = provider({ subscriptions: { production: list([]), sandbox: list([sandboxPlan]) } });
    expect(await storeEntitlement(owner, config)).toEqual(admittedBy("app_store_subscription")); expect(reads(requests)).toEqual(bothReads);
    vi.restoreAllMocks(); requests = provider({ subscriptions: { production: list([]), sandbox: list([]) } });
    expect(await storeEntitlement(owner, config)).toEqual(refused); expect(reads(requests)).toEqual(bothReads);
    // Each list must say its own environment: a record labelled with the other one never counts.
    vi.restoreAllMocks(); provider({ subscriptions: { production: list([sandboxPlan]), sandbox: list([iosPlan()]) } });
    expect(await storeEntitlement(owner, config)).toEqual(refused);
    // Play keeps its own environment; a Play subscription in the sandbox list never counts.
    vi.restoreAllMocks(); provider({ subscriptions: { production: list([]), sandbox: list([playPlan({ environment: "sandbox" })]) } });
    expect(await storeEntitlement(owner, config)).toEqual(refused);
  });
  it("production alone refuses a sandbox subscription and never reads sandbox", async () => {
    const config = { ...stores, app_store_environment: "production" };
    let requests = provider({ subscriptions: { production: list([]), sandbox: list([sandboxPlan]) } });
    expect(await storeEntitlement(owner, config)).toEqual(refused); expect(reads(requests)).toEqual(productionRead);
    vi.restoreAllMocks(); requests = provider({ subscriptions: { production: list([iosPlan()]) } });
    expect(await storeEntitlement(owner, config)).toEqual(admittedBy("app_store_subscription")); expect(reads(requests)).toEqual(productionRead);
  });
  it("sandbox alone refuses a production subscription", async () => {
    const config = { ...stores, app_store_environment: "sandbox" };
    let requests = provider({ subscriptions: { production: list([iosPlan()]), sandbox: list([]) } });
    expect(await storeEntitlement(owner, config)).toEqual(refused); expect(reads(requests)).toEqual(bothReads);
    vi.restoreAllMocks(); requests = provider({ subscriptions: { sandbox: list([sandboxPlan]) } });
    expect(await storeEntitlement(owner, config)).toEqual(admittedBy("app_store_subscription")); expect(reads(requests)).toEqual(bothReads);
  });
  it("a failed or cut-short read in one environment does not block an admission from the other", async () => {
    const failed = (status: number) => () => new Response(null, { status });
    provider({ subscriptions: { production: failed(503), sandbox: list([sandboxPlan]) } });
    expect(await storeEntitlement(owner, stores)).toEqual(admittedBy("app_store_subscription"));
    vi.restoreAllMocks(); let requests = provider({ subscriptions: { production: list([iosPlan()]), sandbox: failed(503) } });
    expect(await storeEntitlement(owner, stores)).toEqual(admittedBy("app_store_subscription")); expect(reads(requests)).toEqual(productionRead);
    vi.restoreAllMocks(); provider({ subscriptions: { production: list([], "/next"), sandbox: list([sandboxPlan]) } });
    expect(await storeEntitlement(owner, stores)).toEqual(admittedBy("app_store_subscription"));
    // Nobody admitted: the failure or the cut-short list holds the host instead of refusing it.
    vi.restoreAllMocks(); provider({ subscriptions: { production: list([]), sandbox: failed(503) } });
    expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_http_503" });
    vi.restoreAllMocks(); provider({ subscriptions: { production: failed(500), sandbox: list([]) } });
    expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_http_500" });
    vi.restoreAllMocks(); provider({ subscriptions: { production: list([]), sandbox: list([], "/next") } });
    expect(await storeEntitlement(owner, stores)).toEqual({ full_journey: false, status: "unavailable", reason: "provider_incomplete_list" });
    // A missing sandbox customer is an empty list, so a clean refusal.
    vi.restoreAllMocks(); requests = provider({ subscriptions: { production: list([]), sandbox: failed(404) } });
    expect(await storeEntitlement(owner, stores)).toEqual(refused); expect(reads(requests)).toEqual(bothReads);
  });
  it.each(["", "Both", "production,sandbox", "all", " both"])("the value %j holds App Store hosts and leaves Play hosts alone", async value => {
    const config = { ...stores, app_store_environment: value };
    provider({ subscriptions: list([iosPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(unconfigured);
    vi.restoreAllMocks(); provider({ subscriptions: list([playPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(admittedBy("play_subscription"));
  });
  it("leaves the Play-only check unchanged when the flag is off, whatever the App Store environment says", async () => {
    for (const value of [undefined, "both", "sandbox", "nonsense"]) {
      for (const customer of [{ subscriptions: { production: list([playPlan()]), sandbox: list([sandboxPlan]) } }, { subscriptions: { production: list([]), sandbox: list([sandboxPlan]) } }]) {
        const expected = provider(customer); const before = await playEntitlement(owner, play); const expectedReads = reads(expected); vi.restoreAllMocks();
        const requests = provider(customer);
        const { checked_at, environment, ...result } = await entitlement(owner, { ...stores, app_store_environment: value });
        expect(result).toEqual(before); expect(reads(requests)).toEqual(expectedReads); vi.restoreAllMocks();
      }
    }
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
  const badLists = [["after_you_full_journey_monthly_ios"], ["prodIosMonthly", "not-a-product"], Array.from({ length: 9 }, (_, i) => `prod${i}`), "prodIosMonthly"];
  it.each(badLists)("a malformed App Store list %j holds App Store hosts and leaves Play hosts alone", async bad => {
    const config = { ...stores, app_store_subscription_product_ids: bad };
    provider({ subscriptions: list([iosPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(unconfigured);
    vi.restoreAllMocks(); provider({ purchases: list([purchase()]) }); expect(await storeEntitlement(owner, config)).toEqual(admittedBy("play_purchase"));
    vi.restoreAllMocks(); provider({ subscriptions: list([playPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(admittedBy("play_subscription"));
    vi.restoreAllMocks(); provider({ active: list([]) }); expect(await storeEntitlement(owner, config)).toEqual(refused);
  });
  it.each([[{ app_store_subscription_product_ids: undefined }], [{ app_store_subscription_product_ids: [] }], [{ app_store_environment: "Production" }], [{ app_store_environment: "staging" }]])("an unset list or bad environment %j holds rather than refusing", async change => {
    const requests = provider({ subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, { ...stores, ...change })).toEqual(unconfigured);
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "purchases?environment=production&limit=100", "subscriptions?environment=production&limit=100"]);
  });
  it("a malformed Play subscription list holds Play subscribers and still admits App Store hosts", async () => {
    const config = { ...stores, play_subscription_product_ids: ["after_you_full_journey_monthly"] };
    let requests = provider({ subscriptions: list([iosPlan()]) });
    expect(await storeEntitlement(owner, config)).toEqual(admittedBy("app_store_subscription"));
    expect(reads(requests)).toEqual(["active_entitlements?limit=100", "subscriptions?environment=production&limit=100"]);
    vi.restoreAllMocks(); provider({ subscriptions: list([playPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(unconfigured);
    vi.restoreAllMocks(); requests = provider({ subscriptions: list([iosPlan()]) });
    expect(await entitlement(owner, config)).toMatchObject(unconfigured); expect(requests).not.toHaveBeenCalled();
  });
  it("a missing Play product holds Play and review but not the App Store", async () => {
    for (const change of [{ play_product_id: "" }, { play_product_id: undefined }]) {
      provider({ subscriptions: list([iosPlan()]) }); expect(await storeEntitlement(owner, { ...stores, ...change })).toEqual(admittedBy("app_store_subscription"));
      vi.restoreAllMocks(); provider({ purchases: list([purchase()]) }); expect(await storeEntitlement(owner, { ...stores, ...change, reviewer_ids: [owner] })).toEqual(unconfigured);
      vi.restoreAllMocks();
    }
  });
  it("a malformed App Store entitlement ID holds only the App Store", async () => {
    const config = { ...stores, app_store_entitlement_lookup_id: "full_journey_ios" };
    provider({ subscriptions: list([iosPlan()]) }); expect(await storeEntitlement(owner, config)).toEqual(unconfigured);
    vi.restoreAllMocks(); provider({ purchases: list([purchase()]) }); expect(await storeEntitlement(owner, config)).toEqual(admittedBy("play_purchase"));
  });
  it.each([{ secret: "" }, { project_id: "x" }, { play_entitlement_lookup_id: "full_journey_play" }])("shared settings %j hold before any read", async change => {
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
    expect(await storeEntitlement(owner, { ...stores, app_store_environment: "sandbox" })).toEqual(admittedBy("play_subscription"));
    vi.restoreAllMocks(); provider({ subscriptions: { production: list([]), sandbox: failed(503) } });
    expect(await storeEntitlement(owner, { ...stores, app_store_environment: "sandbox" })).toEqual({ full_journey: false, status: "unavailable", reason: "provider_http_503" });
  });
  it("treats a missing subscription record as no subscription", async () => {
    provider({ subscriptions: failed(404) }); expect(await storeEntitlement(owner, stores)).toEqual(refused);
  });
});

describe("paid room creation through the Worker", () => {
  let requestNo = 0;
  async function call(path: string, account: { player_id: string; device_token: string } | undefined, body: unknown, ids?: Ids) {
    const configured = { ...env, ...(ids ? rc(ids) : {}) } as Env;
    return worker.fetch(new Request("https://after-you.test" + path, { method: account && body === undefined ? "GET" : "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.2." + ++requestNo,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
  }
  it("keeps the shipped error codes and adds the App Store source", async () => {
    const created = await call("/v1/identity", undefined, {}); expect(created.status).toBe(201);
    const host = await created.json<{ player_id: string; device_token: string }>();
    const live = stores;
    provider({ subscriptions: list([iosPlan()]) });
    const off = await call("/v2/rooms", host, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, live);
    expect(off.status).toBe(402); expect(await off.json()).toMatchObject({ error: { code: "host_unlock_required" } });
    const held = await call("/v2/rooms", host, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, { ...live, features: APP_STORE_ON, app_store_subscription_product_ids: ["after_you_full_journey_monthly_ios"] });
    expect(held.status).toBe(503); expect(await held.json()).toMatchObject({ error: { code: "entitlement_unavailable" } });
    const on = await call("/v2/rooms", host, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, { ...live, features: APP_STORE_ON });
    expect(on.status).toBe(200);
    const checked = await call("/v1/entitlement", host, undefined, { ...live, features: APP_STORE_ON });
    expect(checked.status).toBe(200); expect(await checked.json()).toMatchObject({ full_journey: true, status: "verified", access_source: "app_store_subscription", entitlement: "full_journey_play", player_id: host.player_id });
  });
});

describe("the App Store Full Journey capability", () => {
  const ask = (client: string | null) => new Request("https://store.test/v2/capabilities", { headers: client ? { [CLIENT_HEADER]: client } : {} });
  const live: Ids = { ...stores, features: APP_STORE_ON };
  it("goes to an App Store build only while App Store subscribers are admitted", () => {
    expect(storeCapability(ask("0.7.5 app_store"), rc(live))).toEqual({ app_store_full_journey_version: 1 });
    // The default environment ("both") and the Play lookup reused; a sandbox only setting still admits App Review.
    expect(storeCapability(ask("0.7.5 app_store"), rc({ ...live, app_store_environment: "sandbox", app_store_entitlement_lookup_id: "entlIos" }))).toEqual({ app_store_full_journey_version: 1 });
    for (const client of ["0.7.5 play", "0.7.5 github", "0.7.5", null]) expect(storeCapability(ask(client), rc(live)), String(client)).toEqual({});
  });
  it("is absent while the flag is off or any App Store setting the check needs is missing", () => {
    for (const ids of [{ ...stores }, { ...live, app_store_subscription_product_ids: [] }, { ...live, app_store_subscription_product_ids: undefined },
      { ...live, app_store_subscription_product_ids: "prodIosMonthly" }, { ...live, app_store_environment: "staging" }, { ...live, project_id: undefined },
      { ...live, secret: "" }, { ...live, play_entitlement_lookup_id: undefined }])
      expect(storeCapability(ask("0.7.5 app_store"), rc(ids as Ids)), JSON.stringify(ids)).toEqual({});
  });
});
