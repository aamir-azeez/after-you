import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import gameBundles from "../../game/content/pollen_bundles.json";
import serverBundles from "../src/pollen/bundles.json";
import { APP_STORE_BUNDLES_READY, BUNDLES, checkedBundles, firstGift, storeReady, type BundleKey, type Bundles } from "../src/pollen/bundles";
import { bundleProducts, bundlePurchase, lookupBundles, readBundles, type BundleAsk, type BundlePurchase } from "../src/pollen/bundle-provider";
import { BUNDLE_CHECK_MS, MAX_BUNDLE_LOOKUPS, bundleCheckDue, bundlesView, lastBundleCheck, settleBundles } from "../src/pollen/bundle-settle";
import { anyBundlesOn, appStoreBundlesOn, bundlesOn, refundsOn } from "../src/pollen/features";
import { POLLEN_CLAIMS_OBJECT, type PollenClaims } from "../src/pollen/claims";
import { applyLedger, ledgerLines, walletView } from "../src/pollen/wallet";
import { RATES } from "../src/pollen/rates";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { POLLEN_BUNDLE_TABLES, POLLEN_PLAYER_TABLES } from "../src/storage-schema";
import { configJson, POLLEN_CLIENT, PRE_SHOP_CLIENT } from "./config";
import { countingEnv, meterRows } from "./meter";

// Pollen bundles on Google Play: the table and its product ids, what RevenueCat purchases count, and the
// claim route and daily refund check through the Worker. RevenueCat is always a mock; synthetic identities only.
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const ON = ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS", "POLLEN_BUNDLES"];
/** Both stores selling. */
const BOTH = [...ON, "POLLEN_BUNDLES_APP_STORE"];
/** The App Store alone: iPhone sells, Play does not. */
const APP_STORE_ONLY = ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS", "POLLEN_BUNDLES_APP_STORE"];
const REFUNDS_ONLY = ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS"];
const vars = (features: string[] = ON, revenuecat: Record<string, unknown> = { project_id: "proj1234" }): Record<string, string> =>
  ({ POLLEN_SECRET: SECRET, REVENUECAT_SECRET_KEY: "synthetic-revenuecat-key-for-tests", CONFIG: configJson({ features, revenuecat }) });

/** The table with another first gift (+10%), and with none, as the owner may set them. */
const GIFT: Bundles = checkedBundles({ ...JSON.parse(JSON.stringify(serverBundles)), first_bonus_percent: 10 });
const OFF: Bundles = checkedBundles({ ...JSON.parse(JSON.stringify(serverBundles)), first_bonus_percent: 0 });
/** What a player's first bundle pays at the shipped table: its Pollen and the first gift. */
const firstPay = (key: BundleKey) => BUNDLES.bundles[key].pollen + firstGift(key);

describe("the bundle table", () => {
  it("is the same file the game reads", () => {
    expect(gameBundles).toEqual(serverBundles);
  });
  it("pays the rules' amounts in both stores, with the owner's 20% first gift rounded down, and 10% when set", () => {
    expect(Object.fromEntries(Object.entries(BUNDLES.bundles).map(([key, bundle]) => [key, [bundle.pollen, bundle.bonus, bundle.play_store.usd_cents, bundle.app_store.usd_cents]])))
      .toEqual({ pinch: [5000, 0, 99, 149], pouch: [21000, 1000, 399, 499], jar: [44000, 4000, 799, 899], basket: [115000, 15000, 1999, 2199] });
    expect(BUNDLES.first_bonus_percent).toBe(20);
    expect(["pinch", "pouch", "jar", "basket"].map(key => firstGift(key as "pinch"))).toEqual([1000, 4200, 8800, 23000]);
    expect(["pinch", "pouch", "jar", "basket"].map(key => firstGift(key as "pinch", GIFT))).toEqual([500, 2100, 4400, 11500]);
  });
  it("names the real Play, App Store and RevenueCat products, each once", () => {
    expect(Object.fromEntries(Object.entries(BUNDLES.bundles).map(([key, bundle]) => [key, [bundle.play_store.product, bundle.play_store.revenuecat_product]])))
      .toEqual({ pinch: ["after_you_pollen_pinch", "prodd4e2b730e5"], pouch: ["after_you_pollen_pouch", "prod25def0f41d"], jar: ["after_you_pollen_jar", "proda8a9bcf221"], basket: ["after_you_pollen_basket", "prodde607106a6"] });
    expect(Object.fromEntries(Object.entries(BUNDLES.bundles).map(([key, bundle]) => [key, [bundle.app_store.product, bundle.app_store.revenuecat_product]])))
      .toEqual({ pinch: ["after_you_pollen_pinch_ios", "prod235f72a2e0"], pouch: ["after_you_pollen_pouch_ios", "prodc18dc7e8e6"], jar: ["after_you_pollen_jar_ios", "prod5920f90735"], basket: ["after_you_pollen_basket_ios", "prod9dfc202990"] });
  });
  it("keeps the App Store's ids apart from Play's, and a store set up only when all four of its products are", () => {
    expect(storeReady("play_store")).toBe(true);
    expect(storeReady("app_store")).toBe(true);
    expect(APP_STORE_BUNDLES_READY).toBe(true);
    const unset = JSON.parse(JSON.stringify(serverBundles));
    for (const key of ["pinch", "pouch", "jar", "basket"]) unset.bundles[key].app_store.revenuecat_product = "";
    const table = checkedBundles(unset);
    expect(storeReady("app_store", table)).toBe(false);
    expect(Object.values(bundleProducts(table)).map(each => each.store)).toEqual(["play_store", "play_store", "play_store", "play_store"]);
    expect(Object.values(bundleProducts()).filter(each => each.store === "app_store").map(each => each.bundle)).toEqual(["pinch", "pouch", "jar", "basket"]);
  });
  it("refuses a table outside its shape", () => {
    const copy = () => JSON.parse(JSON.stringify(serverBundles));
    for (const change of [(v: any) => { delete v.bundles.jar; }, (v: any) => { v.bundles.extra = v.bundles.jar; }, (v: any) => { v.bundles.pinch.bonus = 6000; },
      (v: any) => { v.first_bonus_percent = 101; }, (v: any) => { v.bundles.pouch.pollen = 1.5; }, (v: any) => { v.schema_version = 1; },
      (v: any) => { v.bundles.jar.play_store.revenuecat_product = v.bundles.pouch.play_store.revenuecat_product; }, (v: any) => { v.bundles.jar.play_store.product = "Jar Product"; },
      (v: any) => { v.bundles.jar.play_store.revenuecat_product = "jar"; }, (v: any) => { v.bundles.jar.app_store.revenuecat_product = v.bundles.jar.play_store.revenuecat_product; },
      (v: any) => { v.bundles.jar.app_store.product = v.bundles.jar.play_store.product; }, (v: any) => { v.bundles.jar.app_store.revenuecat_product = ""; },
      (v: any) => { delete v.bundles.jar.app_store; }, (v: any) => { v.bundles.jar.app_store.usd_cents = 0; }, (v: any) => { v.bundles.jar.extra_store = v.bundles.jar.app_store; }]) {
      const value = copy(); change(value);
      expect(() => checkedBundles(value)).toThrow(/invalid_pollen_bundles/);
    }
  });
});

const owned = (id: string, product = "prodd4e2b730e5", extra: Record<string, unknown> = {}) => ({ object: "purchase", id, customer_id: "c", original_customer_id: "c", product_id: product,
  purchased_at: 1_700_000_000_000 + Number(id.replace(/\D/g, "") || 0), revenue_in_usd: { currency: "USD", gross: 0.99, commission: 0.15, tax: 0, proceeds: 0.84 }, quantity: 1, status: "owned",
  presented_offering_id: "pollen", environment: "production", store: "play_store", store_purchase_identifier: `GPA.0000-${id}`, ownership: "purchased", country: "US", ...extra });

describe("what RevenueCat purchases count", () => {
  const products = { prodd4e2b730e5: { bundle: "pinch", store: "play_store" }, prod25def0f41d: { bundle: "pouch", store: "play_store" } } as const;
  it("counts a Play production purchase of a configured bundle, owned by purchase", () => {
    expect(bundlePurchase(owned("rc_1"), products)).toEqual({ id: "rc_1", bundle: "pinch", refunded: false, quantity: 1, order: "GPA.0000-rc_1", usd_cents: 99, purchased_at: 1_700_000_000_001 });
    expect(bundlePurchase(owned("rc_2", "prod25def0f41d", { status: "refunded", revenue_in_usd: null }), products)).toMatchObject({ bundle: "pouch", refunded: true, usd_cents: 399 });
  });
  it("mints nothing from Test Store, sandbox, promotional, the App Store, family sharing or another product", () => {
    for (const change of [{ store: "test_store" }, { environment: "sandbox" }, { store: "promotional" }, { store: "app_store" }, { ownership: "family_shared" },
      { product_id: "prodOther" }, { product_id: "prodd4e2b730e5y" }, { status: "pending" }, { quantity: 0 }, { quantity: 11 }, { id: "bad id" }, { object: "subscription" }, { purchased_at: null }])
      expect(bundlePurchase(owned("rc_3", "prodd4e2b730e5", change), products), JSON.stringify(change)).toBeNull();
  });
  it("reads nothing while unconfigured and answers a failed or partial list as unavailable", async () => {
    const request = vi.fn(async () => ({ ok: true as const, status: 200, value: { object: "list", items: [owned("rc_4")], next_page: null } }));
    expect(await readBundles("P".repeat(22), vars(ON, {}), request)).toEqual({ ok: false, reason: "unconfigured" });
    expect(request).not.toHaveBeenCalled();
    expect(await readBundles("P".repeat(22), vars(), request)).toMatchObject({ ok: true, purchases: [{ id: "rc_4", bundle: "pinch" }] });
    expect(String((request.mock.calls[0] as unknown[])[0])).toContain("/customers/PPPPPPPPPPPPPPPPPPPPPP/purchases?environment=production&limit=100");
    expect(await readBundles("P".repeat(22), vars(), async () => ({ ok: true, status: 200, value: { object: "list", items: [], next_page: "more" } }))).toEqual({ ok: false, reason: "provider_incomplete_list" });
    expect(await readBundles("P".repeat(22), vars(), async () => ({ ok: false, reason: "provider_http_500" }))).toEqual({ ok: false, reason: "provider_http_500" });
    expect(await readBundles("P".repeat(22), vars(), async () => ({ ok: true, status: 404, value: null }))).toEqual({ ok: true, purchases: [] });
  });
  it("looks a moved purchase up by its Play order, whoever holds it, and acts only on the same purchase refunded", async () => {
    const ask: BundleAsk = { id: "rc_5", bundle: "pinch", order: "GPA.0000-rc_5" };
    const list = (...items: unknown[]) => async () => ({ ok: true as const, status: 200, value: { object: "list", items, next_page: null } });
    const request = vi.fn(list(owned("rc_5", "prodd4e2b730e5", { status: "refunded", customer_id: "someone-else" })));
    expect(await lookupBundles([ask], vars(ON, {}), request)).toEqual({ ok: false, reason: "unconfigured" });
    expect(request).not.toHaveBeenCalled();
    expect(await lookupBundles([ask], vars(), request)).toEqual({ ok: true, refunded: ["rc_5"] });
    expect(String((request.mock.calls[0] as unknown[])[0])).toBe("https://api.revenuecat.com/v2/projects/proj1234/purchases?store_purchase_identifier=GPA.0000-rc_5");
    // A new RevenueCat id after the move still matches by order; the order may come back as a number.
    expect(await lookupBundles([ask], vars(), list(owned("rc_99", "prodd4e2b730e5", { status: "refunded", store_purchase_identifier: "GPA.0000-rc_5" })))).toEqual({ ok: true, refunded: ["rc_5"] });
    expect(await lookupBundles([{ ...ask, order: "12345678" }], vars(), list(owned("rc_5", "prodd4e2b730e5", { status: "refunded", store_purchase_identifier: 12345678 })))).toEqual({ ok: true, refunded: ["rc_5"] });
    for (const change of [{ status: "owned" }, { store_purchase_identifier: "GPA.other" }, { product_id: "prod25def0f41d" }, { environment: "sandbox" }, { store: "test_store" }, { ownership: "family_shared" }])
      expect(await lookupBundles([ask], vars(), list(owned("rc_5", "prodd4e2b730e5", { status: "refunded", ...change }))), JSON.stringify(change)).toEqual({ ok: true, refunded: [] });
    expect(await lookupBundles([ask], vars(), async () => ({ ok: true, status: 404, value: null }))).toEqual({ ok: true, refunded: [] });
    expect(await lookupBundles([ask], vars(), async () => ({ ok: false, reason: "provider_http_429" }))).toEqual({ ok: false, reason: "provider_http_429" });
    expect(await lookupBundles([ask], vars(), async () => ({ ok: true, status: 200, value: { object: "list", items: [], next_page: "more" } }))).toEqual({ ok: false, reason: "provider_incomplete_list" });
    // No order kept: the purchase by its RevenueCat id.
    const byId = vi.fn(async () => ({ ok: true as const, status: 200, value: owned("rc_5", "prodd4e2b730e5", { status: "refunded", store_purchase_identifier: null }) }));
    expect(await lookupBundles([{ ...ask, order: "" }], vars(), byId)).toEqual({ ok: true, refunded: ["rc_5"] });
    expect(String((byId.mock.calls[0] as unknown[])[0])).toBe("https://api.revenuecat.com/v2/projects/proj1234/purchases/rc_5");
    expect(await lookupBundles([{ ...ask, order: "" }], vars(), async () => ({ ok: true, status: 200, value: owned("rc_6", "prodd4e2b730e5", { status: "refunded", store_purchase_identifier: null }) }))).toEqual({ ok: true, refunded: [] });
    // One failed lookup fails the set; the rest are asked at the same time, not one after another.
    let open = 0, most = 0;
    const slow = async (url: string) => { open++; most = Math.max(most, open); await new Promise(resolve => setTimeout(resolve, 5)); open--;
      return url.endsWith("rc_7") ? { ok: false as const, reason: "provider_request_or_decode_failed" } : { ok: true as const, status: 404, value: null }; };
    expect(await lookupBundles(["rc_5", "rc_6", "rc_7"].map(id => ({ id, bundle: "pinch" as const, order: "GPA.0000-" + id })), vars(), slow)).toEqual({ ok: false, reason: "provider_request_or_decode_failed" });
    expect(most).toBe(3);
  });
});

/** An App Store purchase as RevenueCat lists it: its transaction id is the store_purchase_identifier. */
const apple = (id: string, product = "prod235f72a2e0", extra: Record<string, unknown> = {}) => owned(id, product,
  { store: "app_store", store_purchase_identifier: "20000000000" + id.replace(/\D/g, "").padStart(5, "0"), revenue_in_usd: { currency: "USD", gross: 1.49, commission: 0.22, tax: 0, proceeds: 1.27 }, ...extra });

describe("what App Store purchases count", () => {
  it("counts an App Store production purchase of an App Store bundle, by its transaction id kept apart from Play orders", () => {
    expect(bundlePurchase(apple("rc_1"), bundleProducts())).toEqual({ id: "rc_1", bundle: "pinch", refunded: false, quantity: 1, order: "appstore:2000000000000001", usd_cents: 149, purchased_at: 1_700_000_000_001 });
    // No revenue figure: the App Store's own US price, not Play's.
    expect(bundlePurchase(apple("rc_2", "prodc18dc7e8e6", { revenue_in_usd: null }), bundleProducts())).toMatchObject({ bundle: "pouch", usd_cents: 499 });
    // The id may come back as a number.
    expect(bundlePurchase(apple("rc_3", "prod235f72a2e0", { store_purchase_identifier: 2000000000000003 }), bundleProducts())?.order).toBe("appstore:2000000000000003");
  });
  it("mints nothing from sandbox (App Review, TestFlight), a product of the other store, family sharing or a malformed id", () => {
    for (const change of [{ environment: "sandbox" }, { product_id: "prodd4e2b730e5" }, { store: "play_store" }, { ownership: "family_shared" }, { store: "test_store" }])
      expect(bundlePurchase(apple("rc_4", "prod235f72a2e0", change), bundleProducts()), JSON.stringify(change)).toBeNull();
    // A Play product listed as an App Store purchase, and the other way round, never count.
    expect(bundlePurchase(owned("rc_5", "prod235f72a2e0"), bundleProducts())).toBeNull();
    // An id that is not an App Store transaction id, or a Play order that looks like an App Store reference, is no reference.
    expect(bundlePurchase(apple("rc_6", "prod235f72a2e0", { store_purchase_identifier: "GPA.1" }), bundleProducts())?.order).toBe("");
    expect(bundlePurchase(owned("rc_7", "prodd4e2b730e5", { store_purchase_identifier: "appstore:1" }), bundleProducts())?.order).toBe("");
  });
  it("looks a moved App Store purchase up by its own transaction id", async () => {
    const request = vi.fn(async () => ({ ok: true as const, status: 200, value: { object: "list", items: [apple("rc_8", "prod235f72a2e0", { status: "refunded", customer_id: "moved" })], next_page: null } }));
    expect(await lookupBundles([{ id: "rc_8", bundle: "pinch", order: "appstore:2000000000000008" }], vars(), request)).toEqual({ ok: true, refunded: ["rc_8"] });
    expect(String((request.mock.calls[0] as unknown[])[0])).toBe("https://api.revenuecat.com/v2/projects/proj1234/purchases?store_purchase_identifier=2000000000000008");
    // A Play purchase with the same digits is another purchase.
    expect(await lookupBundles([{ id: "rc_8", bundle: "pinch", order: "2000000000000008" }], vars(), request)).toEqual({ ok: true, refunded: [] });
  });
});

describe("the first gift across stores", () => {
  afterEach(async () => { await reset(); });
  const p = (id: string, bundle: "pinch" | "pouch", order: string, at: number) => ({ id, bundle, refunded: false, quantity: 1, order, usd_cents: 149, purchased_at: at });
  const settle = (storage: DurableObjectStorage, purchases: ReturnType<typeof p>[]) =>
    settleBundles(storage, Date.now(), () => true, { read: async () => ({ ok: true as const, purchases }), claim: async asked => Object.fromEntries(asked.map(each => [each.order, true])) }, RATES, GIFT);
  it("pays once per player whichever store the first bundle came from", async () => {
    await runInDurableObject(env.PLAYERS.getByName("gift-stores"), async (_, state) => {
      const storage = state.storage;
      expect(await settle(storage, [p("a1", "pouch", "appstore:2000000000000101", 1)])).toMatchObject({ reply: { credited: [{ first_gift: 2100, order: "2000000000000101", store: "app_store" }] } });
      expect(await settle(storage, [p("a1", "pouch", "appstore:2000000000000101", 1), p("g1", "pouch", "GPA.g1", 2)])).toMatchObject({ reply: { credited: [{ first_gift: 0, order: "GPA.g1" }] } });
      expect(bundlesView(storage, GIFT).first_gift).toBe(false);
    });
    await runInDurableObject(env.PLAYERS.getByName("gift-stores-2"), async (_, state) => {
      const storage = state.storage;
      expect(await settle(storage, [p("g2", "pinch", "GPA.g2", 1)])).toMatchObject({ reply: { credited: [{ first_gift: 500 }] } });
      expect(await settle(storage, [p("g2", "pinch", "GPA.g2", 1), p("a2", "pinch", "appstore:2000000000000102", 2)])).toMatchObject({ reply: { credited: [{ first_gift: 0, store: "app_store" }] } });
    });
  });
});

type Account = { player_id: string; device_token: string; recovery_code: string };
type Reply = { schema_version: 1; balance: number; credited: { bundle: string; pollen: number; first_gift: number; order: string; usd_cents: number }[]; refunded: { bundle: string; amount: number; order: string }[]; pending: boolean };
type Wallet = { balance: number; bundles?: { first_gift: boolean; first_gift_percent: number; spent_usd_cents: number } };
const shared = env as unknown as Record<string, unknown>;
/** Player rows a moved refund's take-back writes: the refund line, the wallet row and the check time. */
const PLAYER_ROWS_ON_TAKE_BACK = 3;
const realNow = Date.now.bind(Date);
let address = 0, offset = 0, providerCalls = 0, current: Record<string, string> = vars();
let lists: Record<string, unknown[]> = {}, orders: Record<string, unknown[]> = {}, gate: Promise<void> | null = null, down = false;

async function call(path: string, method = "GET", account?: Account, body?: unknown, base: Env = env, client: Record<string, string> = POLLEN_CLIENT): Promise<Response> {
  const configured = Object.assign({ ...base }, current) as Env;
  return worker.fetch(new Request("https://bundles.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.94." + (++address % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), [POLLEN_HEADER]: "1", ...client },
  body: body === undefined ? (method === "POST" ? "{}" : undefined) : JSON.stringify(body) }), configured);
}
const claim = (account: Account, base: Env = env) => call("/v1/pollen/bundle-claims", "POST", account, { schema_version: 1 }, base);
const wallet = async (account: Account) => (await call("/v1/pollen", "GET", account)).json<Wallet>();
const tables = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) =>
  state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE name LIKE 'pollen_%' ORDER BY name").toArray().map(row => row.name));

describe("the first gift, when the owner sets it", () => {
  afterEach(async () => { await reset(); });
  const p = (id: string, bundle: "pinch" | "pouch", refunded = false, at = 1) => ({ id, bundle, refunded, quantity: 1, order: "GPA." + id, usd_cents: 99, purchased_at: at });
  const settle = (storage: DurableObjectStorage, purchases: ReturnType<typeof p>[], table: Bundles) =>
    settleBundles(storage, Date.now(), () => true, { read: async () => ({ ok: true as const, purchases }), claim: async asked => Object.fromEntries(asked.map(each => [each.order, true])) }, RATES, table);
  it("pays 10% once on the first bundle, never on a later one, and a refund never opens it again", async () => {
    await runInDurableObject(env.PLAYERS.getByName("gift-ten"), async (_, state) => {
      const storage = state.storage;
      expect(bundlesView(storage, GIFT)).toEqual({ first_gift: true, first_gift_percent: 10, spent_usd_cents: 0 });
      expect(await settle(storage, [p("g1", "pouch", false, 1)], GIFT)).toMatchObject({ status: "settled", reply: { balance: 23100, credited: [{ bundle: "pouch", pollen: 21000, first_gift: 2100 }] } });
      expect(await settle(storage, [p("g1", "pouch", false, 1), p("g2", "pinch", false, 2)], GIFT)).toMatchObject({ reply: { balance: 28100, credited: [{ bundle: "pinch", first_gift: 0 }] } });
      expect(await settle(storage, [p("g1", "pouch", true, 1), p("g2", "pinch", false, 2)], GIFT)).toMatchObject({ reply: { balance: 5000, refunded: [{ bundle: "pouch", amount: 23100 }] } });
      expect(bundlesView(storage, GIFT).first_gift).toBe(false);
      expect(await settle(storage, [p("g1", "pouch", true, 1), p("g2", "pinch", false, 2), p("g3", "pinch", false, 3)], GIFT)).toMatchObject({ reply: { balance: 10000, credited: [{ first_gift: 0 }] } });
    });
  });
  it("pays none at 0, and a gift set later never goes to a player who already bought", async () => {
    await runInDurableObject(env.PLAYERS.getByName("gift-zero"), async (_, state) => {
      const storage = state.storage;
      expect(bundlesView(storage, OFF)).toEqual({ first_gift: false, first_gift_percent: 0, spent_usd_cents: 0 });
      expect(await settle(storage, [p("z1", "pinch")], OFF)).toMatchObject({ reply: { balance: 5000, credited: [{ first_gift: 0 }] } });
      expect(ledgerLines(storage, "bundle:").map(line => line.detail.first_gift)).toEqual([0]);
      expect(bundlesView(storage, GIFT).first_gift).toBe(false);
      expect(await settle(storage, [p("z1", "pinch"), p("z2", "pouch", false, 2)], GIFT)).toMatchObject({ reply: { credited: [{ bundle: "pouch", first_gift: 0 }] } });
      expect(walletView(storage, Date.now()).balance).toBe(26000);
    });
  });
});

describe("the refund check's lookups", () => {
  afterEach(async () => { await reset(); });
  const p = (id: string, refunded = false) => ({ id, bundle: "pinch" as const, refunded, quantity: 1, order: "GPA." + id, usd_cents: 99, purchased_at: Number(id.slice(1)) });
  const yes = async (asked: BundlePurchase[]) => Object.fromEntries(asked.map(each => [each.order, true]));
  it("asks only about paid bundles missing from the list, at most the cap a check, a new window each day", async () => {
    await runInDurableObject(env.PLAYERS.getByName("lookup-cap"), async (_, state) => {
      const storage = state.storage, all = Array.from({ length: 11 }, (_, index) => p("m" + (index + 1)));
      const day = BUNDLE_CHECK_MS, start = 20_000 * day;
      expect(await settleBundles(storage, start, () => true, { read: async () => ({ ok: true, purchases: all }), claim: yes })).toMatchObject({ reply: { balance: firstPay("pinch") + 50000 } });
      const seen: string[][] = [];
      const lookup = async (asks: BundleAsk[]) => { seen.push(asks.map(ask => ask.id)); return { ok: true as const, refunded: [] }; };
      // Still listed: nothing to look up.
      await settleBundles(storage, start + day, () => true, { read: async () => ({ ok: true, purchases: all }), claim: yes, lookup });
      expect(seen).toEqual([]);
      for (let next = 2; next <= 3; next++) await settleBundles(storage, start + next * day, () => true, { read: async () => ({ ok: true, purchases: [all[0]] }), claim: yes, lookup });
      expect(seen.map(ids => ids.length)).toEqual([MAX_BUNDLE_LOOKUPS, MAX_BUNDLE_LOOKUPS]);
      expect(new Set(seen.flat())).toEqual(new Set(all.slice(1).map(each => each.id)));
      expect(walletView(storage, start + 3 * day).balance).toBe(firstPay("pinch") + 50000);
    });
  });
  it("takes a looked-up refund back once, under retries and a reply that comes back twice", async () => {
    await runInDurableObject(env.PLAYERS.getByName("lookup-once"), async (_, state) => {
      const storage = state.storage, now = 20_000 * BUNDLE_CHECK_MS;
      await settleBundles(storage, now, () => true, { read: async () => ({ ok: true, purchases: [p("r1"), p("r2"), p("r3")] }), claim: yes });
      const asked: string[][] = [];
      const deps = { read: async () => ({ ok: true as const, purchases: [p("r2", true), p("r3")] }), claim: yes, lookup: async (asks: BundleAsk[]) => { asked.push(asks.map(ask => ask.id)); return { ok: true as const, refunded: ["r1", "r1"] }; } };
      // A failed lookup still takes back the refund the list shows, takes nothing moved back, and leaves the check due.
      const checked = lastBundleCheck(storage);
      expect(await settleBundles(storage, now + 1, () => true, { ...deps, lookup: async () => ({ ok: false as const, reason: "provider_http_500" }) }))
        .toMatchObject({ status: "settled", lookup_failed: "provider_http_500", reply: { balance: firstPay("pinch") + 5000, refunded: [{ order: "GPA.r2" }] } });
      expect(lastBundleCheck(storage)).toBe(checked);
      expect(bundleCheckDue(storage, now + BUNDLE_CHECK_MS)).toBe(true);
      const both = await Promise.all([settleBundles(storage, now + 2, () => true, deps), settleBundles(storage, now + 2, () => true, deps)]);
      expect(both.flatMap(outcome => outcome.status === "settled" ? outcome.reply.refunded : [])).toEqual([{ bundle: "pinch", amount: firstPay("pinch"), order: "GPA.r1" }]);
      expect(lastBundleCheck(storage)).toBe(now + 2);
      expect(await settleBundles(storage, now + 3, () => true, deps)).toMatchObject({ reply: { balance: 5000, refunded: [] } });
      expect(ledgerLines(storage, "bundlerefund:").map(line => [line.key, line.amount]).sort()).toEqual([["bundlerefund:GPA.r1", -firstPay("pinch")], ["bundlerefund:GPA.r2", -5000]]);
      // Once taken back it is never looked up again.
      expect(asked).toEqual([["r1"], ["r1"]]);
    });
  });
});

describe("bundles through the Worker", () => {
  beforeEach(() => {
    current = vars(); Object.assign(shared, current);
    offset = 0; providerCalls = 0; lists = {}; orders = {}; gate = null; down = false;
    vi.spyOn(Date, "now").mockImplementation(() => realNow() + offset);
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => {
      const url = String(input instanceof Request ? input.url : input);
      if (!url.startsWith("https://api.revenuecat.com/")) throw new Error("unexpected fetch");
      providerCalls++;
      if (gate) await gate;
      if (down) return new Response(null, { status: 500 });
      // The project-level search by Play order, whoever holds the purchase now.
      const order = new URL(url).searchParams.get("store_purchase_identifier");
      if (order !== null) return Response.json({ object: "list", items: orders[order] ?? [], next_page: null });
      const player = /customers\/([^/]+)\//.exec(url)?.[1] ?? "";
      return url.includes("/purchases?") ? Response.json({ object: "list", items: lists[player] ?? [], next_page: null }) : new Response(null, { status: 404 });
    });
  });
  afterEach(async () => { for (const key of Object.keys(current)) delete shared[key]; vi.restoreAllMocks(); await reset(); });
  const create = async (): Promise<Account> => { const made = await call("/v1/identity", "POST"); expect(made.status).toBe(201); return made.json<Account>(); };

  it("is off without POLLEN_BUNDLES, refunds or the shop: 503, no capability and no wallet part", async () => {
    const on = (names: string[]) => ({ CONFIG: configJson({ features: names }), POLLEN_SECRET: SECRET });
    expect(bundlesOn(on(ON))).toBe(true);
    expect(bundlesOn(on(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_BUNDLES"]))).toBe(false);
    expect(bundlesOn(on(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_BUNDLES"]))).toBe(false);
    expect(refundsOn(on(REFUNDS_ONLY))).toBe(true);
    expect(refundsOn(on(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_REFUNDS"]))).toBe(false);
    const player = await create();
    expect(await (await call("/v2/capabilities", "GET", player)).json()).toMatchObject({ pollen_bundles_version: 1, pollen_shop_version: 1 });
    current = vars(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"]);
    Object.assign(shared, current);
    const off = await claim(player);
    expect(off.status).toBe(503);
    expect(await off.json()).toMatchObject({ error: { code: "pollen_bundles_disabled" } });
    expect(await (await call("/v2/capabilities", "GET", player)).json()).not.toHaveProperty("pollen_bundles_version");
    expect(await wallet(player)).not.toHaveProperty("bundles");
    expect(providerCalls).toBe(0);
  });

  it("keeps taking refunds back on the wallet read after bundles stop selling", async () => {
    const player = await create();
    lists[player.player_id] = [owned("rc_15", "prodd4e2b730e5")];
    await claim(player);
    current = vars(REFUNDS_ONLY); Object.assign(shared, current);
    expect((await claim(player)).status).toBe(503);
    expect(await (await call("/v2/capabilities", "GET", player)).json()).not.toHaveProperty("pollen_bundles_version");
    lists[player.player_id] = [owned("rc_15", "prodd4e2b730e5", { status: "refunded" })];
    offset = BUNDLE_CHECK_MS + 1000;
    const read = await wallet(player);
    expect(read.balance).toBe(0);
    expect(read).not.toHaveProperty("bundles");
  });

  it("refuses any body but {schema_version: 1}", async () => {
    const player = await create();
    for (const body of [{}, { schema_version: 2 }, { schema_version: 1, bundle: "pinch" }, { schema_version: 1, amount: 115000 }])
      expect((await call("/v1/pollen/bundle-claims", "POST", player, body)).status).toBe(400);
    expect((await call("/v1/pollen/bundle-claims", "GET", player)).status).toBe(405);
  });

  it("credits a purchase once with the first gift, a later bundle without it, and a repeat nothing", async () => {
    const player = await create();
    lists[player.player_id] = [owned("rc_10", "prod25def0f41d")];
    expect(await wallet(player)).toMatchObject({ balance: 0, bundles: { first_gift: true, first_gift_percent: 20, spent_usd_cents: 0 } });
    const meter = countingEnv({ ...env, ...current } as unknown as Env);
    const bought = await claim(player, meter.env);
    expect(bought.status).toBe(200);
    expect(meter.calls).toEqual(["PLAYERS.authorize", "PLAYERS.pollenBundleClaim"]);
    expect(await bought.json<Reply>()).toEqual({ schema_version: 1, balance: 25200, pending: false, refunded: [],
      credited: [{ bundle: "pouch", pollen: 21000, first_gift: 4200, order: "GPA.0000-rc_10", purchased_at: 1_700_000_000_010, usd_cents: 99 }] });
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: 25200, credited: [], refunded: [] });
    lists[player.player_id] = [owned("rc_10", "prod25def0f41d"), owned("rc_11", "prodd4e2b730e5")];
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: 30200, credited: [{ bundle: "pinch", pollen: 5000, first_gift: 0 }] });
    expect(await wallet(player)).toMatchObject({ balance: 30200, bundles: { first_gift: false, first_gift_percent: 20, spent_usd_cents: 198 } });
    const history = await (await call("/v1/pollen/history", "GET", player)).json<{ entries: Record<string, unknown>[]; purchases: Record<string, unknown>[]; spent_usd_cents: number }>();
    expect(history.entries.filter(entry => entry.kind === "bundle").map(entry => [entry.amount, entry.bundle, entry.order, entry.usd_cents]).sort())
      .toEqual([[25200, "pouch", "GPA.0000-rc_10", 99], [5000, "pinch", "GPA.0000-rc_11", 99]].sort());
    // The purchases part lists every bundle with its receipt line, and the money spent.
    expect(history.purchases.map(line => [line.kind, line.amount, line.bundle, line.order, line.usd_cents]).sort())
      .toEqual([["bundle", 25200, "pouch", "GPA.0000-rc_10", 99], ["bundle", 5000, "pinch", "GPA.0000-rc_11", 99]].sort());
    expect(history.spent_usd_cents).toBe(198);
  });

  it("lists purchases in the history apart from turns, newest first with refunds, and nothing for a player who never bought", async () => {
    const never = await create();
    const empty = await (await call("/v1/pollen/history", "GET", never)).json<Record<string, unknown>>();
    expect(empty).not.toHaveProperty("purchases"); expect(empty).not.toHaveProperty("spent_usd_cents");
    const player = await create();
    lists[player.player_id] = [owned("rc_60", "prod25def0f41d", { revenue_in_usd: { gross: 3.99 } })];
    await claim(player);
    lists[player.player_id] = [owned("rc_60", "prod25def0f41d", { status: "refunded", revenue_in_usd: { gross: 3.99 } }), owned("rc_61", "prodd4e2b730e5")];
    await claim(player);
    // 60 turn rows newer than every purchase: the 50 newest entries hold no bundle, the purchases part still has all three.
    await runInDurableObject(env.PLAYERS.getByName(player.player_id), async (_, state) => {
      for (let index = 0; index < 60; index++)
        state.storage.sql.exec("INSERT INTO pollen_claims VALUES (?,?,?,?,?)", `turn:room${index}:hash`, "turn", 10, Date.now() + 60_000 + index, JSON.stringify({ schema_version: 1, receipt: { schema_version: 1, earned: 10, clears: [] }, detail: {} }));
    });
    const history = await (await call("/v1/pollen/history", "GET", player)).json<{ entries: Record<string, unknown>[]; purchases: Record<string, unknown>[]; spent_usd_cents: number }>();
    expect(history.entries.some(entry => String(entry.kind).startsWith("bundle"))).toBe(false);
    expect(history.purchases.map(line => [line.kind, line.amount, line.bundle, line.usd_cents]).sort()).toEqual([
      ["bundle", firstPay("pouch"), "pouch", 399], ["bundlerefund", -firstPay("pouch"), "pouch", 399], ["bundle", 5000, "pinch", 99]].sort());
    const times = history.purchases.map(line => Number(line.at));
    expect(times).toEqual([...times].sort((a, b) => b - a));
    // A bundle is dated when it was bought on Play, not when its claim landed; a refund when it was taken back.
    expect(history.purchases.filter(line => line.kind === "bundle").map(line => line.at).sort()).toEqual([1_700_000_000_060, 1_700_000_000_061]);
    expect(Number(history.purchases.find(line => line.kind === "bundlerefund")?.at)).toBeGreaterThan(1_700_000_000_061);
    expect(history.spent_usd_cents).toBe(99);
  });

  it("pays two overlapping claims once", async () => {
    const player = await create();
    lists[player.player_id] = [owned("rc_20", "proda8a9bcf221")];
    let open!: () => void;
    gate = new Promise(resolve => { open = resolve; });
    const both = Promise.all([claim(player), claim(player)]);
    await new Promise(resolve => setTimeout(resolve, 20));
    open();
    const replies = await Promise.all((await both).map(response => response.json<Reply>()));
    expect(replies.flatMap(reply => reply.credited).map(each => each.pollen + each.first_gift)).toEqual([firstPay("jar")]);
    expect(replies.map(reply => reply.balance)).toEqual([firstPay("jar"), firstPay("jar")]);
    expect((await wallet(player)).balance).toBe(firstPay("jar"));
  });

  it("takes back a refunded bundle, may go below zero and blocks spending until earning repays it", async () => {
    const player = await create();
    lists[player.player_id] = [owned("rc_30", "prodd4e2b730e5")];
    expect((await (await claim(player)).json<Reply>()).balance).toBe(firstPay("pinch"));
    const daisy = await call("/v1/pollen/spend", "POST", player, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id: "daisy", expected_cost: 1000 });
    expect(daisy.status).toBe(200);
    lists[player.player_id] = [owned("rc_30", "prodd4e2b730e5", { status: "refunded" })];
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: -1000, credited: [], refunded: [{ bundle: "pinch", amount: firstPay("pinch"), order: "GPA.0000-rc_30" }] });
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: -1000, refunded: [] });
    const blocked = await call("/v1/pollen/spend", "POST", player, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id: "seashell", expected_cost: 1000 });
    expect(blocked.status).toBe(403);
    expect(await blocked.json()).toMatchObject({ error: { code: "pollen_blocked" } });
    expect(await wallet(player)).toMatchObject({ balance: -1000, bundles: { first_gift: false, first_gift_percent: 20, spent_usd_cents: 0 } });
    lists[player.player_id].push(owned("rc_31", "prodd4e2b730e5"));
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: 4000, credited: [{ first_gift: 0 }] });
  });

  it("mints nothing from a sandbox, Test Store, promotional or shared purchase", async () => {
    const player = await create();
    lists[player.player_id] = [owned("rc_40", "prodd4e2b730e5", { environment: "sandbox" }), owned("rc_41", "prodd4e2b730e5", { store: "test_store" }),
      owned("rc_42", "prodd4e2b730e5", { store: "promotional" }), owned("rc_43", "prodd4e2b730e5", { ownership: "family_shared" }), owned("rc_44", "prodUnknown")];
    const meter = countingEnv({ ...env, ...current } as unknown as Env);
    expect(await (await claim(player, meter.env)).json<Reply>()).toMatchObject({ balance: 0, credited: [] });
    expect(meter.calls).toEqual(["PLAYERS.authorize", "PLAYERS.pollenBundleClaim"]);
  });

  it("pays a purchase to the first identity that claims it, never a second after a restore", async () => {
    const first = await create(), second = await create();
    lists[first.player_id] = [owned("rc_50", "prodde607106a6")];
    lists[second.player_id] = [owned("rc_50", "prodde607106a6")];
    expect((await (await claim(first)).json<Reply>()).balance).toBe(firstPay("basket"));
    expect(await (await claim(second)).json<Reply>()).toMatchObject({ balance: 0, credited: [] });
    expect((await (await claim(first)).json<Reply>()).balance).toBe(firstPay("basket"));
    const rows = await runInDurableObject(env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT), async (_, state) =>
      state.storage.sql.exec<{ claim_key: string; holder: string }>("SELECT claim_key, holder FROM pollen_claims_held").toArray());
    expect(rows.map(row => row.claim_key)).toEqual(["order:GPA.0000-rc_50"]);
    expect(rows[0].holder).toMatch(/^[a-f0-9]{64}$/);
  });

  it("answers 503 and writes nothing when RevenueCat cannot be read", async () => {
    const player = await create();
    lists[player.player_id] = [owned("rc_60", "prodd4e2b730e5")];
    down = true;
    const failed = await claim(player);
    expect(failed.status).toBe(503);
    expect(await failed.json()).toMatchObject({ error: { code: "pollen_bundles_unavailable" } });
    expect(await tables(player)).toEqual([]);
    down = false;
    expect((await (await claim(player)).json<Reply>()).balance).toBe(firstPay("pinch"));
  });

  it("checks for refunds on the wallet read at most once a day, and never for a player who bought nothing", async () => {
    const buyer = await create(), other = await create();
    await wallet(other);
    expect(providerCalls).toBe(0);
    lists[buyer.player_id] = [owned("rc_70", "prodd4e2b730e5")];
    await claim(buyer);
    const checked = await runInDurableObject(env.PLAYERS.getByName(buyer.player_id), async (_, state) => lastBundleCheck(state.storage));
    expect(checked).toBeGreaterThan(0);
    providerCalls = 0;
    lists[buyer.player_id] = [owned("rc_70", "prodd4e2b730e5", { status: "refunded" })];
    expect((await wallet(buyer)).balance).toBe(firstPay("pinch"));
    expect(providerCalls).toBe(0);
    offset = BUNDLE_CHECK_MS + 1000;
    const meter = countingEnv({ ...env, ...current } as unknown as Env);
    expect((await (await call("/v1/pollen", "GET", buyer, undefined, meter.env)).json<Wallet>()).balance).toBe(0);
    expect(meter.calls).toEqual(["PLAYERS.authorizeWallet"]);
    expect(providerCalls).toBe(1);
    await wallet(buyer);
    expect(providerCalls).toBe(1);
    // An outage never stops the read, and pauses the next try.
    offset += BUNDLE_CHECK_MS + 1000;
    down = true;
    expect((await call("/v1/pollen", "GET", buyer)).status).toBe(200);
    await wallet(buyer);
    expect(providerCalls).toBe(2);
  });

  it("takes a refund back from the identity it paid after a restore moved the purchase to another account", async () => {
    const buyer = await create(), other = await create();
    lists[buyer.player_id] = [owned("rc_100", "prodd4e2b730e5")];
    lists[other.player_id] = [owned("rc_100", "prodd4e2b730e5")];
    expect((await (await claim(buyer)).json<Reply>()).balance).toBe(firstPay("pinch"));
    expect((await (await claim(other)).json<Reply>()).balance).toBe(0);
    // "Transfer to new App User ID": the purchase now lists only under the other account, and is refunded there.
    const refunded = owned("rc_100", "prodd4e2b730e5", { status: "refunded", customer_id: other.player_id });
    lists[buyer.player_id] = []; lists[other.player_id] = [refunded]; orders["GPA.0000-rc_100"] = [refunded];
    offset = BUNDLE_CHECK_MS + 1000; providerCalls = 0;
    const meter = countingEnv({ ...env, ...current } as unknown as Env);
    const stubs = { player: env.PLAYERS.getByName(buyer.player_id) as unknown as DurableObjectStub, claims: env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT) as unknown as DurableObjectStub };
    const metered = await meterRows(stubs, async () => (await call("/v1/pollen", "GET", buyer, undefined, meter.env)).json<Wallet>());
    expect(metered.value.balance).toBe(0);
    // One DO request (the wallet read itself), one list and one lookup; the refund row, the wallet and the check time written.
    expect(meter.calls).toEqual(["PLAYERS.authorizeWallet"]);
    expect(providerCalls).toBe(2);
    expect(metered.rows.claims).toEqual({ read: 0, written: 0 });
    expect(metered.rows.player.written).toBe(PLAYER_ROWS_ON_TAKE_BACK);
    const lines = await runInDurableObject(env.PLAYERS.getByName(buyer.player_id), async (_, state) => ledgerLines(state.storage, "bundlerefund:"));
    expect(lines.map(line => [line.key, line.amount, line.detail.order])).toEqual([["bundlerefund:GPA.0000-rc_100", -firstPay("pinch"), "GPA.0000-rc_100"]]);
    // The other account was never paid, so nothing comes off it, and it makes no check.
    expect((await wallet(other)).balance).toBe(0);
    expect(providerCalls).toBe(2);
    // The next day: the list only, no lookup, nothing taken twice.
    offset += BUNDLE_CHECK_MS + 1000;
    expect((await wallet(buyer)).balance).toBe(0);
    expect(providerCalls).toBe(3);
  });

  it("takes a moved refund back once from two overlapping wallet reads", async () => {
    const buyer = await create();
    lists[buyer.player_id] = [owned("rc_110", "prodd4e2b730e5")];
    await claim(buyer);
    const refunded = owned("rc_110", "prodd4e2b730e5", { status: "refunded", customer_id: "moved" });
    lists[buyer.player_id] = []; orders["GPA.0000-rc_110"] = [refunded];
    offset = BUNDLE_CHECK_MS + 1000;
    let open!: () => void;
    gate = new Promise(resolve => { open = resolve; });
    const both = Promise.all([wallet(buyer), wallet(buyer)]);
    await new Promise(resolve => setTimeout(resolve, 20));
    open();
    expect((await both).map(read => read.balance)).toEqual([0, 0]);
    const lines = await runInDurableObject(env.PLAYERS.getByName(buyer.player_id), async (_, state) => ledgerLines(state.storage, "bundlerefund:"));
    expect(lines.map(line => line.key)).toEqual(["bundlerefund:GPA.0000-rc_110"]);
  });

  it("makes no lookup from the claim route, and leaves the check due for the wallet read", async () => {
    const buyer = await create();
    lists[buyer.player_id] = [owned("rc_120", "prodd4e2b730e5")];
    await claim(buyer);
    const refunded = owned("rc_120", "prodd4e2b730e5", { status: "refunded", customer_id: "moved" });
    lists[buyer.player_id] = [owned("rc_121", "prod25def0f41d")]; orders["GPA.0000-rc_120"] = [refunded];
    offset = BUNDLE_CHECK_MS + 1000; providerCalls = 0;
    expect(await (await claim(buyer)).json<Reply>()).toMatchObject({ balance: firstPay("pinch") + 21000, credited: [{ bundle: "pouch", first_gift: 0 }], refunded: [] });
    expect(providerCalls).toBe(1);
    expect((await wallet(buyer)).balance).toBe(21000);
    expect(providerCalls).toBe(3);
  });

  it("makes no lookup and takes nothing back without POLLEN_REFUNDS", async () => {
    const buyer = await create();
    lists[buyer.player_id] = [owned("rc_130", "prodd4e2b730e5")];
    await claim(buyer);
    lists[buyer.player_id] = []; orders["GPA.0000-rc_130"] = [owned("rc_130", "prodd4e2b730e5", { status: "refunded", customer_id: "moved" })];
    current = vars(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"]); Object.assign(shared, current);
    offset = BUNDLE_CHECK_MS + 1000; providerCalls = 0;
    expect((await wallet(buyer)).balance).toBe(firstPay("pinch"));
    expect(providerCalls).toBe(0);
  });

  it("keeps bundle keys out of the moving subscription claim, and subscription keys out of the bundle claim", async () => {
    const stub = env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT) as unknown as DurableObjectStub;
    await runInDurableObject(stub, async (instance: unknown, state) => {
      const claims = instance as PollenClaims, a = "a".repeat(64), b = "b".repeat(64);
      expect(claims.claim(["order:GPA.90"], a, 1)).toBeNull();
      expect(claims.claim(["bundle:rc_90"], a, 1)).toBeNull();
      expect(claims.claimBundles(["sub:rc_90"], a, 1)).toBeNull();
      // The older purchase id key is only read now, never claimed.
      expect(claims.claimBundles(["bundle:rc_90"], a, 1)).toBeNull();
      expect(claims.claimBundles(["order:GPA.90"], a, 1, ["order:GPA.91"])).toBeNull();
      expect(claims.claimBundles(["order:GPA.90"], a, 1)).toEqual({ "order:GPA.90": true });
      expect(claims.claimBundles(["order:GPA.90"], b, 2)).toEqual({ "order:GPA.90": false });
      expect(claims.claimBundles(["order:GPA.90"], a, 3)).toEqual({ "order:GPA.90": true });
      // An older row for the purchase decides who holds its order, once, and the order row keeps it.
      state.storage.sql.exec("INSERT INTO pollen_claims_held VALUES (?,?,?,0)", "bundle:rc_91", b, 4);
      expect(claims.claimBundles(["order:GPA.91"], a, 5, ["bundle:rc_91"])).toEqual({ "order:GPA.91": false });
      expect(claims.claimBundles(["order:GPA.91"], b, 6)).toEqual({ "order:GPA.91": true });
      expect(claims.claimBundles(["order:GPA.92"], a, 7, ["bundle:rc_92"])).toEqual({ "order:GPA.92": true });
    });
  });

  it("pays one Play order once when a restore gives it a new RevenueCat id on another account", async () => {
    const first = await create(), second = await create();
    lists[first.player_id] = [owned("rc_200", "prodd4e2b730e5")];
    lists[second.player_id] = [owned("rc_201", "prodd4e2b730e5", { store_purchase_identifier: "GPA.0000-rc_200" })];
    const claimsStub = { claims: env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT) as unknown as DurableObjectStub };
    const paid = await meterRows(claimsStub, async () => (await claim(first)).json<Reply>());
    expect(paid.value.balance).toBe(firstPay("pinch"));
    expect(paid.rows.claims.written).toBe(1);
    const refused = await meterRows(claimsStub, async () => (await claim(second)).json<Reply>());
    expect(refused.value).toMatchObject({ balance: 0, credited: [] });
    expect(refused.rows.claims.written).toBe(0);
    const rows = await runInDurableObject(env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT), async (_, state) =>
      state.storage.sql.exec<{ claim_key: string }>("SELECT claim_key FROM pollen_claims_held").toArray().map(row => row.claim_key));
    expect(rows).toEqual(["order:GPA.0000-rc_200"]);
  });

  it("never pays again when the purchase comes back to the buyer under a new RevenueCat id, and never pays one without an order", async () => {
    const buyer = await create();
    lists[buyer.player_id] = [owned("rc_210", "prodd4e2b730e5")];
    expect((await (await claim(buyer)).json<Reply>()).balance).toBe(firstPay("pinch"));
    const back = owned("rc_211", "prodd4e2b730e5", { store_purchase_identifier: "GPA.0000-rc_210" });
    lists[buyer.player_id] = [back];
    expect(await (await claim(buyer)).json<Reply>()).toMatchObject({ balance: firstPay("pinch"), credited: [] });
    // Both records listed at once, and two records of one new order: each order pays once.
    const twice = owned("rc_213", "prodd4e2b730e5", { store_purchase_identifier: "GPA.0000-rc_212" });
    lists[buyer.player_id] = [owned("rc_210", "prodd4e2b730e5"), back, owned("rc_212", "prodd4e2b730e5"), twice, owned("rc_214", "prodd4e2b730e5", { store_purchase_identifier: null })];
    expect(await (await claim(buyer)).json<Reply>()).toMatchObject({ balance: firstPay("pinch") + 5000, credited: [{ order: "GPA.0000-rc_212", first_gift: 0 }] });
    const keys = await runInDurableObject(env.PLAYERS.getByName(buyer.player_id), async (_, state) => ledgerLines(state.storage, "bundle:").map(line => line.key).sort());
    expect(keys).toEqual(["bundle:GPA.0000-rc_210", "bundle:GPA.0000-rc_212"]);
    // A new order listed refunded under one id and owned under another, in either order, never pays.
    for (const [index, first] of [true, false].entries()) {
      const id = `rc_${215 + 2 * index}`, other = `rc_${216 + 2 * index}`;
      const records = [owned(id, "prodd4e2b730e5", { status: "refunded" }), owned(other, "prodd4e2b730e5", { store_purchase_identifier: `GPA.0000-${id}` })];
      lists[buyer.player_id] = first ? records : records.reverse();
      expect(await (await claim(buyer)).json<Reply>()).toMatchObject({ balance: firstPay("pinch") + 5000, credited: [], refunded: [] });
    }
  });

  it("takes a refund back by its order when the refunded record has a new RevenueCat id, on either account", async () => {
    const buyer = await create();
    lists[buyer.player_id] = [owned("rc_220", "prodd4e2b730e5"), owned("rc_221", "prodd4e2b730e5")];
    expect((await (await claim(buyer)).json<Reply>()).balance).toBe(firstPay("pinch") + 5000);
    // Restored back under a new id and refunded there: the buyer's own list shows it, no lookup.
    const home = owned("rc_222", "prodd4e2b730e5", { status: "refunded", store_purchase_identifier: "GPA.0000-rc_220" });
    // Moved away under a new id and refunded there: found by its order.
    const away = owned("rc_223", "prodd4e2b730e5", { status: "refunded", store_purchase_identifier: "GPA.0000-rc_221", customer_id: "moved" });
    lists[buyer.player_id] = [home]; orders["GPA.0000-rc_221"] = [away];
    offset = BUNDLE_CHECK_MS + 1000; providerCalls = 0;
    expect((await wallet(buyer)).balance).toBe(0);
    expect(providerCalls).toBe(2);
    const lines = await runInDurableObject(env.PLAYERS.getByName(buyer.player_id), async (_, state) => ledgerLines(state.storage, "bundlerefund:").map(line => [line.key, line.amount]).sort());
    expect(lines).toEqual([["bundlerefund:GPA.0000-rc_220", -firstPay("pinch")], ["bundlerefund:GPA.0000-rc_221", -5000]]);
    offset += BUNDLE_CHECK_MS + 1000;
    expect((await wallet(buyer)).balance).toBe(0);
    expect(providerCalls).toBe(3);
  });

  it("still matches and takes back a line kept under the older purchase id key", async () => {
    const buyer = await create();
    await runInDurableObject(env.PLAYERS.getByName(buyer.player_id), async (_, state) => {
      applyLedger(state.storage, [
        { key: "bundle:rc_240", kind: "bundle", amount: 5000, detail: { bundle: "pinch", purchase_id: "rc_240", order: "GPA.0000-rc_240", usd_cents: 99, first_gift: 0, quantity: 1, purchased_at: 1 } },
        { key: "bundle:rc_241", kind: "bundle", amount: 5000, detail: { bundle: "pinch", purchase_id: "rc_241", order: "", usd_cents: 99, first_gift: 0, quantity: 1, purchased_at: 2 } }], Date.now(), RATES);
    });
    // Listed again under its order (a new id) and by its id without one: neither pays again.
    lists[buyer.player_id] = [owned("rc_242", "prodd4e2b730e5", { store_purchase_identifier: "GPA.0000-rc_240" }), owned("rc_241", "prodd4e2b730e5", { store_purchase_identifier: null })];
    expect(await (await claim(buyer)).json<Reply>()).toMatchObject({ balance: 10000, credited: [] });
    lists[buyer.player_id] = [owned("rc_242", "prodd4e2b730e5", { status: "refunded", store_purchase_identifier: "GPA.0000-rc_240" }), owned("rc_241", "prodd4e2b730e5", { status: "refunded", store_purchase_identifier: null })];
    expect(await (await claim(buyer)).json<Reply>()).toMatchObject({ balance: 0, refunded: [{ amount: 5000 }, { amount: 5000 }] });
    const lines = await runInDurableObject(env.PLAYERS.getByName(buyer.player_id), async (_, state) => ledgerLines(state.storage, "bundlerefund:").map(line => line.key).sort());
    expect(lines).toEqual(["bundlerefund:rc_240", "bundlerefund:rc_241"]);
  });

  const use = (features: string[]) => { current = vars(features); Object.assign(shared, current); };
  const caps = async (player: Account, client: Record<string, string> = POLLEN_CLIENT) => (await call("/v2/capabilities", "GET", player, undefined, env, client)).json<Record<string, unknown>>();

  it("sells on the App Store by its own switch, apart from Google Play", async () => {
    const on = (names: string[]) => ({ CONFIG: configJson({ features: names }), POLLEN_SECRET: SECRET });
    expect([bundlesOn(on(APP_STORE_ONLY)), appStoreBundlesOn(on(APP_STORE_ONLY)), anyBundlesOn(on(APP_STORE_ONLY))]).toEqual([false, true, true]);
    expect([bundlesOn(on(ON)), appStoreBundlesOn(on(ON)), anyBundlesOn(on(ON))]).toEqual([true, false, true]);
    // The App Store needs refund checks like Play.
    expect(appStoreBundlesOn(on(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_BUNDLES_APP_STORE"]))).toBe(false);
    const player = await create();
    expect(await caps(player)).toMatchObject({ pollen_bundles_version: 1 });
    expect(await caps(player)).not.toHaveProperty("pollen_app_store_bundles_version");
    use(APP_STORE_ONLY);
    expect(await caps(player)).toMatchObject({ pollen_app_store_bundles_version: 1 });
    expect(await caps(player)).not.toHaveProperty("pollen_bundles_version");
    lists[player.player_id] = [apple("rc_300")];
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: 5000, credited: [{ bundle: "pinch", order: "2000000000000300", store: "app_store", usd_cents: 149 }] });
    expect(await wallet(player)).toMatchObject({ bundles: { first_gift: false, spent_usd_cents: 149 } });
    use(BOTH);
    expect(await caps(player)).toMatchObject({ pollen_bundles_version: 1, pollen_app_store_bundles_version: 1 });
  });

  it("pays an App Store purchase once by its transaction id, with the requests and rows a Play purchase costs", async () => {
    use(BOTH);
    const first = await create(), second = await create();
    lists[first.player_id] = [apple("rc_310", "prodc18dc7e8e6", { revenue_in_usd: { gross: 4.99 } })];
    lists[second.player_id] = [apple("rc_311", "prodc18dc7e8e6", { store_purchase_identifier: "2000000000000310" })];
    const meter = countingEnv({ ...env, ...current } as unknown as Env);
    const stubs = { player: env.PLAYERS.getByName(first.player_id) as unknown as DurableObjectStub, claims: env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT) as unknown as DurableObjectStub };
    providerCalls = 0;
    const paid = await meterRows(stubs, async () => (await claim(first, meter.env)).json<Reply>());
    expect(paid.value).toEqual({ schema_version: 1, balance: 21000, pending: false, refunded: [],
      credited: [{ bundle: "pouch", pollen: 21000, first_gift: 0, order: "2000000000000310", store: "app_store", purchased_at: 1_700_000_000_310, usd_cents: 499 }] });
    // Auth and the claim; one RevenueCat list for both stores; one claims row; the ledger line and the wallet row.
    expect(meter.calls).toEqual(["PLAYERS.authorize", "PLAYERS.pollenBundleClaim"]);
    expect(providerCalls).toBe(1);
    expect(paid.rows.claims.written).toBe(1);
    // A restore onto another account (a new RevenueCat id, the same transaction) never pays twice.
    expect(await (await claim(second)).json<Reply>()).toMatchObject({ balance: 0, credited: [] });
    expect(await (await claim(first)).json<Reply>()).toMatchObject({ balance: 21000, credited: [] });
    const rows = await runInDurableObject(env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT), async (_, state) =>
      state.storage.sql.exec<{ claim_key: string }>("SELECT claim_key FROM pollen_claims_held").toArray().map(row => row.claim_key));
    expect(rows).toEqual(["appstore:2000000000000310"]);
    const keys = await runInDurableObject(env.PLAYERS.getByName(first.player_id), async (_, state) => ledgerLines(state.storage, "bundle:").map(line => line.key));
    expect(keys).toEqual(["bundle:appstore:2000000000000310"]);
    const history = await (await call("/v1/pollen/history", "GET", first)).json<{ purchases: Record<string, unknown>[]; spent_usd_cents: number }>();
    expect(history.purchases.map(line => [line.kind, line.order, line.store, line.usd_cents])).toEqual([["bundle", "2000000000000310", "app_store", 499]]);
    expect(history.spent_usd_cents).toBe(499);
  });

  it("keeps a Play order and an App Store id with the same digits apart: each pays once, in its own rows", async () => {
    use(BOTH);
    const player = await create();
    lists[player.player_id] = [owned("rc_320", "prodd4e2b730e5", { store_purchase_identifier: "2000000000000320" }), apple("rc_321", "prod235f72a2e0", { store_purchase_identifier: "2000000000000320" })];
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: 10000, credited: [{ order: "2000000000000320" }, { order: "2000000000000320", store: "app_store" }] });
    expect((await (await claim(player)).json<Reply>()).credited).toEqual([]);
    const keys = await runInDurableObject(env.PLAYERS.getByName(player.player_id), async (_, state) => ledgerLines(state.storage, "bundle:").map(line => line.key).sort());
    expect(keys).toEqual(["bundle:2000000000000320", "bundle:appstore:2000000000000320"]);
    const rows = await runInDurableObject(env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT), async (_, state) =>
      state.storage.sql.exec<{ claim_key: string }>("SELECT claim_key FROM pollen_claims_held ORDER BY claim_key").toArray().map(row => row.claim_key));
    expect(rows).toEqual(["appstore:2000000000000320", "order:2000000000000320"]);
  });

  it("takes an App Store refund back, from the list and after a restore moved it, and keeps doing so once the App Store stops selling", async () => {
    use(APP_STORE_ONLY);
    const buyer = await create();
    lists[buyer.player_id] = [apple("rc_330"), apple("rc_331", "prod5920f90735")];
    expect((await (await claim(buyer)).json<Reply>()).balance).toBe(49000);
    // The App Store stops selling; refunds are still taken back on the wallet read.
    use(REFUNDS_ONLY);
    const away = apple("rc_331", "prod5920f90735", { status: "refunded", customer_id: "moved" });
    lists[buyer.player_id] = [apple("rc_330", "prod235f72a2e0", { status: "refunded" })]; orders["2000000000000331"] = [away];
    offset = BUNDLE_CHECK_MS + 1000; providerCalls = 0;
    expect((await wallet(buyer)).balance).toBe(0);
    expect(providerCalls).toBe(2);
    const lines = await runInDurableObject(env.PLAYERS.getByName(buyer.player_id), async (_, state) => ledgerLines(state.storage, "bundlerefund:").map(line => [line.key, line.amount]).sort());
    expect(lines).toEqual([["bundlerefund:appstore:2000000000000330", -5000], ["bundlerefund:appstore:2000000000000331", -44000]]);
    const history = await (await call("/v1/pollen/history", "GET", buyer)).json<{ purchases: Record<string, unknown>[] }>();
    expect(history.purchases.filter(line => line.kind === "bundlerefund").map(line => [line.order, line.store]).sort()).toEqual([["2000000000000330", "app_store"], ["2000000000000331", "app_store"]]);
  });

  it("offers no shop, item drops or bundles to an app older than 0.7.5", async () => {
    use([...BOTH, "POLLEN_ITEM_BLOOMS"]);
    const player = await create();
    const old = await caps(player, PRE_SHOP_CLIENT);
    expect(old).toMatchObject({ pollen_version: 1, pollen_wardrobe_version: 1 });
    for (const field of ["pollen_shop_version", "pollen_item_blooms_version", "pollen_bundles_version", "pollen_app_store_bundles_version"]) expect(old, field).not.toHaveProperty(field);
    expect(await caps(player)).toMatchObject({ pollen_shop_version: 1, pollen_item_blooms_version: 1, pollen_bundles_version: 1, pollen_app_store_bundles_version: 1 });
    // The wallet read carries the wardrobe without what is sold.
    const read = await (await call("/v1/pollen", "GET", player, undefined, env, PRE_SHOP_CLIENT)).json<Record<string, unknown>>();
    expect(read).toHaveProperty("wardrobe");
    for (const field of ["bundles", "name_price", "name_price_next"]) expect(read, field).not.toHaveProperty(field);
    expect(await wallet(player)).toHaveProperty("name_price");
    lists[player.player_id] = [apple("rc_340")];
    const refused = await call("/v1/pollen/bundle-claims", "POST", player, { schema_version: 1 }, env, PRE_SHOP_CLIENT);
    expect(refused.status).toBe(503);
    const spend = await call("/v1/pollen/spend", "POST", player, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id: "daisy", expected_cost: 1000 }, env, PRE_SHOP_CLIENT);
    expect(spend.status).toBe(503);
    expect(await spend.json()).toMatchObject({ error: { code: "pollen_shop_disabled" } });
    // No version at all counts as older.
    expect(await caps(player, {})).not.toHaveProperty("pollen_shop_version");
    expect(providerCalls).toBe(0);
  });

  it("erases the bundle check with the account", async () => {
    const player = await create();
    lists[player.player_id] = [owned("rc_80", "prodd4e2b730e5")];
    await claim(player);
    expect(await tables(player)).toEqual(expect.arrayContaining([POLLEN_BUNDLE_TABLES[0].name, "pollen_claims", "pollen_wallet"]));
    expect(POLLEN_PLAYER_TABLES.map(table => table.name)).toContain(POLLEN_BUNDLE_TABLES[0].name);
    expect((await call("/v1/identity", "DELETE", player)).status).toBe(200);
    expect(await tables(player)).toEqual([]);
  });
});
