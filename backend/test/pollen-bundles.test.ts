import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import gameBundles from "../../game/content/pollen_bundles.json";
import serverBundles from "../src/pollen/bundles.json";
import { BUNDLES, checkedBundles, firstGift, type Bundles } from "../src/pollen/bundles";
import { bundlePurchase, readBundles } from "../src/pollen/bundle-provider";
import { BUNDLE_CHECK_MS, bundlesView, lastBundleCheck, settleBundles } from "../src/pollen/bundle-settle";
import { bundlesOn, refundsOn } from "../src/pollen/features";
import { POLLEN_CLAIMS_OBJECT, type PollenClaims } from "../src/pollen/claims";
import { ledgerLines, walletView } from "../src/pollen/wallet";
import { RATES } from "../src/pollen/rates";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { POLLEN_BUNDLE_TABLES, POLLEN_PLAYER_TABLES } from "../src/storage-schema";
import { configJson, POLLEN_CLIENT } from "./config";
import { countingEnv } from "./meter";

// Pollen bundles on Google Play: the table and its product ids, what RevenueCat purchases count, and the
// claim route and daily refund check through the Worker. RevenueCat is always a mock; synthetic identities only.
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const ON = ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS", "POLLEN_BUNDLES"];
const REFUNDS_ONLY = ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS"];
const vars = (features: string[] = ON, revenuecat: Record<string, unknown> = { project_id: "proj1234" }): Record<string, string> =>
  ({ POLLEN_SECRET: SECRET, REVENUECAT_SECRET_KEY: "synthetic-revenuecat-key-for-tests", CONFIG: configJson({ features, revenuecat }) });

/** The table with the first gift the rules propose (+10%), as the owner may set it. */
const GIFT: Bundles = checkedBundles({ ...JSON.parse(JSON.stringify(serverBundles)), first_bonus_percent: 10 });

describe("the bundle table", () => {
  it("is the same file the game reads", () => {
    expect(gameBundles).toEqual(serverBundles);
  });
  it("pays the rules' amounts, with the first gift off until the owner decides, and 10% rounded down when set", () => {
    expect(Object.fromEntries(Object.entries(BUNDLES.bundles).map(([key, bundle]) => [key, [bundle.pollen, bundle.bonus, bundle.usd_cents]])))
      .toEqual({ pinch: [5000, 0, 99], pouch: [21000, 1000, 399], jar: [44000, 4000, 799], basket: [115000, 15000, 1999] });
    expect(BUNDLES.first_bonus_percent).toBe(0);
    expect(["pinch", "pouch", "jar", "basket"].map(key => firstGift(key as "pinch"))).toEqual([0, 0, 0, 0]);
    expect(["pinch", "pouch", "jar", "basket"].map(key => firstGift(key as "pinch", GIFT))).toEqual([500, 2100, 4400, 11500]);
  });
  it("names the real Play and RevenueCat products, each once", () => {
    expect(Object.fromEntries(Object.entries(BUNDLES.bundles).map(([key, bundle]) => [key, [bundle.play_product, bundle.revenuecat_product]])))
      .toEqual({ pinch: ["after_you_pollen_pinch", "prodd4e2b730e5"], pouch: ["after_you_pollen_pouch", "prod25def0f41d"], jar: ["after_you_pollen_jar", "proda8a9bcf221"], basket: ["after_you_pollen_basket", "prodde607106a6"] });
  });
  it("refuses a table outside its shape", () => {
    const copy = () => JSON.parse(JSON.stringify(serverBundles));
    for (const change of [(v: any) => { delete v.bundles.jar; }, (v: any) => { v.bundles.extra = v.bundles.jar; }, (v: any) => { v.bundles.pinch.bonus = 6000; },
      (v: any) => { v.first_bonus_percent = 101; }, (v: any) => { v.bundles.pouch.pollen = 1.5; }, (v: any) => { v.schema_version = 2; },
      (v: any) => { v.bundles.jar.revenuecat_product = v.bundles.pouch.revenuecat_product; }, (v: any) => { v.bundles.jar.play_product = "Jar Product"; }, (v: any) => { v.bundles.jar.revenuecat_product = "jar"; }]) {
      const value = copy(); change(value);
      expect(() => checkedBundles(value)).toThrow(/invalid_pollen_bundles/);
    }
  });
});

const owned = (id: string, product = "prodd4e2b730e5", extra: Record<string, unknown> = {}) => ({ object: "purchase", id, customer_id: "c", original_customer_id: "c", product_id: product,
  purchased_at: 1_700_000_000_000 + Number(id.replace(/\D/g, "") || 0), revenue_in_usd: { currency: "USD", gross: 0.99, commission: 0.15, tax: 0, proceeds: 0.84 }, quantity: 1, status: "owned",
  presented_offering_id: "pollen", environment: "production", store: "play_store", store_purchase_identifier: `GPA.0000-${id}`, ownership: "purchased", country: "US", ...extra });

describe("what RevenueCat purchases count", () => {
  const products = { prodd4e2b730e5: "pinch", prod25def0f41d: "pouch" } as const;
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
});

type Account = { player_id: string; device_token: string; recovery_code: string };
type Reply = { schema_version: 1; balance: number; credited: { bundle: string; pollen: number; first_gift: number; order: string; usd_cents: number }[]; refunded: { bundle: string; amount: number; order: string }[]; pending: boolean };
type Wallet = { balance: number; bundles?: { first_gift: boolean; first_gift_percent: number; spent_usd_cents: number } };
const shared = env as unknown as Record<string, unknown>;
const realNow = Date.now.bind(Date);
let address = 0, offset = 0, providerCalls = 0, current: Record<string, string> = vars();
let lists: Record<string, unknown[]> = {}, gate: Promise<void> | null = null, down = false;

async function call(path: string, method = "GET", account?: Account, body?: unknown, base: Env = env): Promise<Response> {
  const configured = Object.assign({ ...base }, current) as Env;
  return worker.fetch(new Request("https://bundles.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.94." + (++address % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), [POLLEN_HEADER]: "1", ...POLLEN_CLIENT },
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
    settleBundles(storage, Date.now(), () => true, { read: async () => ({ ok: true as const, purchases }), claim: async keys => Object.fromEntries(keys.map(key => [key, true])) }, RATES, table);
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
      expect(bundlesView(storage)).toEqual({ first_gift: false, first_gift_percent: 0, spent_usd_cents: 0 });
      expect(await settle(storage, [p("z1", "pinch")], BUNDLES)).toMatchObject({ reply: { balance: 5000, credited: [{ first_gift: 0 }] } });
      expect(ledgerLines(storage, "bundle:").map(line => line.detail.first_gift)).toEqual([0]);
      expect(bundlesView(storage, GIFT).first_gift).toBe(false);
      expect(await settle(storage, [p("z1", "pinch"), p("z2", "pouch", false, 2)], GIFT)).toMatchObject({ reply: { credited: [{ bundle: "pouch", first_gift: 0 }] } });
      expect(walletView(storage, Date.now()).balance).toBe(26000);
    });
  });
});

describe("bundles through the Worker", () => {
  beforeEach(() => {
    current = vars(); Object.assign(shared, current);
    offset = 0; providerCalls = 0; lists = {}; gate = null; down = false;
    vi.spyOn(Date, "now").mockImplementation(() => realNow() + offset);
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => {
      const url = String(input instanceof Request ? input.url : input);
      if (!url.startsWith("https://api.revenuecat.com/")) throw new Error("unexpected fetch");
      providerCalls++;
      if (gate) await gate;
      if (down) return new Response(null, { status: 500 });
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
    const meter = countingEnv({ ...env, ...current } as unknown as Env);
    const first = await claim(player, meter.env);
    expect(first.status).toBe(200);
    expect(meter.calls).toEqual(["PLAYERS.authorize", "PLAYERS.pollenBundleClaim"]);
    expect(await first.json<Reply>()).toEqual({ schema_version: 1, balance: 21000, pending: false, refunded: [],
      credited: [{ bundle: "pouch", pollen: 21000, first_gift: 0, order: "GPA.0000-rc_10", purchased_at: 1_700_000_000_010, usd_cents: 99 }] });
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: 21000, credited: [], refunded: [] });
    lists[player.player_id] = [owned("rc_10", "prod25def0f41d"), owned("rc_11", "prodd4e2b730e5")];
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: 26000, credited: [{ bundle: "pinch", pollen: 5000, first_gift: 0 }] });
    expect(await wallet(player)).toMatchObject({ balance: 26000, bundles: { first_gift: false, first_gift_percent: 0, spent_usd_cents: 198 } });
    const history = await (await call("/v1/pollen/history", "GET", player)).json<{ entries: Record<string, unknown>[] }>();
    expect(history.entries.filter(entry => entry.kind === "bundle").map(entry => [entry.amount, entry.bundle, entry.order, entry.usd_cents]).sort())
      .toEqual([[21000, "pouch", "GPA.0000-rc_10", 99], [5000, "pinch", "GPA.0000-rc_11", 99]].sort());
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
    expect(replies.flatMap(reply => reply.credited).map(each => each.pollen + each.first_gift)).toEqual([44000]);
    expect(replies.map(reply => reply.balance)).toEqual([44000, 44000]);
    expect((await wallet(player)).balance).toBe(44000);
  });

  it("takes back a refunded bundle, may go below zero and blocks spending until earning repays it", async () => {
    const player = await create();
    lists[player.player_id] = [owned("rc_30", "prodd4e2b730e5")];
    expect((await (await claim(player)).json<Reply>()).balance).toBe(5000);
    const daisy = await call("/v1/pollen/spend", "POST", player, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id: "daisy", expected_cost: 1000 });
    expect(daisy.status).toBe(200);
    lists[player.player_id] = [owned("rc_30", "prodd4e2b730e5", { status: "refunded" })];
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: -1000, credited: [], refunded: [{ bundle: "pinch", amount: 5000, order: "GPA.0000-rc_30" }] });
    expect(await (await claim(player)).json<Reply>()).toMatchObject({ balance: -1000, refunded: [] });
    const blocked = await call("/v1/pollen/spend", "POST", player, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id: "seashell", expected_cost: 1000 });
    expect(blocked.status).toBe(403);
    expect(await blocked.json()).toMatchObject({ error: { code: "pollen_blocked" } });
    expect(await wallet(player)).toMatchObject({ balance: -1000, bundles: { first_gift: false, first_gift_percent: 0, spent_usd_cents: 0 } });
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
    expect((await (await claim(first)).json<Reply>()).balance).toBe(115000);
    expect(await (await claim(second)).json<Reply>()).toMatchObject({ balance: 0, credited: [] });
    expect((await (await claim(first)).json<Reply>()).balance).toBe(115000);
    const rows = await runInDurableObject(env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT), async (_, state) =>
      state.storage.sql.exec<{ claim_key: string; holder: string }>("SELECT claim_key, holder FROM pollen_claims_held").toArray());
    expect(rows.map(row => row.claim_key)).toEqual(["bundle:rc_50"]);
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
    expect((await (await claim(player)).json<Reply>()).balance).toBe(5000);
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
    expect((await wallet(buyer)).balance).toBe(5000);
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

  it("keeps bundle keys out of the moving subscription claim, and subscription keys out of the bundle claim", async () => {
    const stub = env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT) as unknown as DurableObjectStub;
    await runInDurableObject(stub, async (instance: unknown) => {
      const claims = instance as PollenClaims;
      expect(claims.claim(["bundle:rc_90"], "a".repeat(64), 1)).toBeNull();
      expect(claims.claimBundles(["sub:rc_90"], "a".repeat(64), 1)).toBeNull();
      expect(claims.claimBundles(["bundle:rc_90"], "a".repeat(64), 1)).toEqual({ "bundle:rc_90": true });
      expect(claims.claimBundles(["bundle:rc_90"], "b".repeat(64), 2)).toEqual({ "bundle:rc_90": false });
      expect(claims.claimBundles(["bundle:rc_90"], "a".repeat(64), 3)).toEqual({ "bundle:rc_90": true });
    });
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
