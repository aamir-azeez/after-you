import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { COSMETIC_CODE_MAX, EMPTY_CONFIG, MAX_RELEASED_COSMETICS, parseConfig } from "../src/config";
import { FLAG_NAMES } from "../src/flags";
import { CATALOG, FRUITS_OFFERED_TAG, OFFERED_TAG, catalogFor, checkedCatalog, featuredItem, itemOfCode, offeredItems, offeredTagFor, releasedCatalog, setPieces, sold, type Catalog } from "../src/pollen/catalog";
import { quote, type Holdings } from "../src/pollen/spend";
import { droppable } from "../src/pollen/item-blooms";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { POLLEN_CLIENT, PRE_SHOP_CLIENT, withConfig } from "./config";
import pinned from "../../game/tests/fixtures/cosmetic_codes.json";
import manifest from "../../game/tests/fixtures/golden/cosmetic_manifest.json";

// The cosmetics release list and featured item (CONFIG cosmetics_released and cosmetics_featured, by item code):
// permanent codes, refusing to sell an item not released, the CONFIG shape and the featured capability. The routes with
// an item built unreleased, and the Durable Object count, are in cosmetic-release-routes.test.ts. Synthetic identities only.
const PINS = pinned.codes as Record<string, number>;
const holding = (owned: string[] = []): Holdings => ({ owned: new Set(owned), cleared: () => false });
/** The real catalogue plus made-up items built unreleased. Made-up codes stay in the 900s, clear of every real block (hats 200s, skins 300s). */
const BUILT: Catalog = checkedCatalog({
  ...structuredClone(CATALOG),
  items: { ...structuredClone(CATALOG.items),
    reed_cap: { code: 901, slot: "hat", tier: "common", unlock: "", set: "", released: false },
    dune_skin: { code: 902, slot: "body", tier: "rare", unlock: "", set: "dunes", released: false },
    dune_leaf: { code: 903, slot: "leaf", tier: "uncommon", unlock: "", set: "dunes", released: false },
    pear_hood: { code: 904, slot: "hat", tier: "fruit_hat", unlock: "", set: "", released: false } }
});
const config = (value: Record<string, unknown>) => parseConfig(JSON.stringify(value), FLAG_NAMES);

describe("item codes", () => {
  it("gives every item the code pinned for it, and pins each code once", () => {
    expect(Object.keys(CATALOG.items).sort()).toEqual(Object.keys(PINS).filter(id => Object.hasOwn(CATALOG.items, id)).sort());
    for (const [id, item] of Object.entries(CATALOG.items)) expect(item.code, id).toBe(PINS[id]);
    expect(new Set(Object.values(PINS)).size).toBe(Object.keys(PINS).length);
    for (const code of Object.values(PINS)) expect(Number.isSafeInteger(code) && code >= 1 && code <= COSMETIC_CODE_MAX, String(code)).toBe(true);
    // The first catalogue keeps 1 to 18 in shop order (later blocks start at their hundreds).
    const first = manifest.ids.filter(id => CATALOG.items[id].code < 100);
    expect(first.map(id => CATALOG.items[id].code)).toEqual(first.map((_, index) => index + 1));
  });
  it("agrees with the game's manifest", () => {
    const rows = manifest.items as Record<string, { code: number }>;
    for (const [id, item] of Object.entries(CATALOG.items)) expect(item.code, id).toBe(rows[id].code);
  });
  it("refuses an item without a whole code in range, or two items sharing one", () => {
    const base = structuredClone(CATALOG) as unknown as { items: Record<string, Record<string, unknown>> };
    const withDaisy = (code: unknown) => ({ ...base, items: { ...base.items, daisy: { ...base.items.daisy, code } } });
    for (const code of [0, -1, COSMETIC_CODE_MAX + 1, 1.5, "1", null]) expect(() => checkedCatalog(withDaisy(code)), String(code)).toThrow();
    const { code: _dropped, ...noCode } = base.items.daisy;
    expect(() => checkedCatalog({ ...base, items: { ...base.items, daisy: noCode } })).toThrow();
    expect(() => checkedCatalog(withDaisy(2))).toThrow();
    // The batches' blocks are accepted.
    expect(BUILT.items.reed_cap.code).toBe(901);
    expect(itemOfCode(902, BUILT)).toBe("dune_skin");
    expect(itemOfCode(4)).toBe("tide");
    expect(itemOfCode(998)).toBeUndefined();
  });
});

describe("the CONFIG keys", () => {
  it("reads a release list and a featured code, and nothing when they are absent", () => {
    expect(EMPTY_CONFIG.cosmetics_released.size).toBe(0);
    expect(EMPTY_CONFIG.cosmetics_featured).toBeNull();
    const none = config({});
    expect(none.problems).toEqual([]);
    expect(none.config.cosmetics_released.size).toBe(0);
    expect(none.config.cosmetics_featured).toBeNull();
    const set = config({ cosmetics_released: [901, 902, 1], cosmetics_featured: 4 });
    expect(set.problems).toEqual([]);
    expect(set.unknown).toEqual([]);
    expect([...set.config.cosmetics_released]).toEqual([901, 902, 1]);
    expect(set.config.cosmetics_featured).toBe(4);
  });
  it("refuses a malformed list whole and a malformed featured code, failing safe to the built-in catalogue", () => {
    const tooMany = Array.from({ length: MAX_RELEASED_COSMETICS + 1 }, (_, index) => index + 1);
    for (const list of [901, "901", [901, 901], [0], [COSMETIC_CODE_MAX + 1], [2.5], ["901"], [null], tooMany, {}]) {
      const check = config({ cosmetics_released: list });
      expect(check.problems.length, JSON.stringify(list).slice(0, 40)).toBe(1);
      expect(check.config.cosmetics_released.size).toBe(0);
    }
    for (const code of [0, -4, COSMETIC_CODE_MAX + 1, 4.5, "4", [4], null, true]) {
      const check = config({ cosmetics_featured: code });
      expect(check.problems.length, JSON.stringify(code)).toBe(1);
      expect(check.config.cosmetics_featured).toBeNull();
    }
    // One bad key leaves the others standing.
    const mixed = config({ features: ["POLLEN_EARN"], cosmetics_released: "all", cosmetics_featured: 4 });
    expect(mixed.config.features.has("POLLEN_EARN")).toBe(true);
    expect(mixed.config.cosmetics_featured).toBe(4);
  });
});

describe("releasing by code", () => {
  it("changes nothing while no list releases anything new", () => {
    expect(releasedCatalog(new Set())).toBe(CATALOG);
    // Listing every code already released changes nothing (items built unreleased, as the skins' 300s, are left out).
    expect(releasedCatalog(new Set(Object.entries(PINS).filter(([id]) => CATALOG.items[id]?.released).map(([, code]) => code)))).toBe(CATALOG);
    // With FACE_SINGLES off, listing the face items too changes nothing.
    expect(releasedCatalog(new Set(Object.values(CATALOG.items).filter(item => item.released || item.code >= 400 && item.code <= 499).map(item => item.code)), CATALOG, false)).toBe(CATALOG);
    expect(releasedCatalog(new Set([998, 999]))).toBe(CATALOG);
    expect(catalogFor(withConfig({}))).toBe(CATALOG);
    expect(catalogFor({})).toBe(CATALOG);
    expect(catalogFor(withConfig({ cosmetics_released: [1, 2, 3], cosmetics_featured: 4 }))).toBe(CATALOG);
    // The tags phones hold stay exactly as they are, so a deploy with no list reads no wallet again.
    expect(offeredTagFor(withConfig({}), false)).toBe(OFFERED_TAG);
    expect(offeredTagFor(withConfig({}), true)).toBe(FRUITS_OFFERED_TAG);
    expect([OFFERED_TAG, FRUITS_OFFERED_TAG]).toEqual(["779e8348", "82a1733d"]);
  });
  it("refuses to sell, offer, set or drop an item built unreleased until its code is listed", () => {
    for (const id of ["reed_cap", "dune_skin", "dune_leaf"]) {
      expect(quote({ kind: "item", id }, holding(), BUILT), id).toMatchObject({ ok: false, status: 409, code: "not_for_sale" });
      expect(sold(id, BUILT), id).toBe(false);
      expect(offeredItems(BUILT), id).not.toContain(id);
    }
    expect(quote({ kind: "set", id: "dunes" }, holding(), BUILT)).toMatchObject({ ok: false, status: 404, code: "unknown_item" });
    expect(droppable("common", BUILT)).not.toContain("reed_cap");
    const released = releasedCatalog(new Set([901, 902, 998]), BUILT);
    expect(released).not.toBe(BUILT);
    expect(quote({ kind: "item", id: "reed_cap" }, holding(), released)).toEqual({ ok: true, value: { kind: "item", id: "reed_cap", pieces: ["reed_cap"], full: 1000, cost: 1000, currency: "pollen" } });
    expect(offeredItems(released)).toContain("dune_skin");
    expect(droppable("common", released)).toContain("reed_cap");
    // A set sells only its released pieces; the Dune leaf (398) stays hidden.
    expect(setPieces("dunes", released)).toEqual(["dune_skin"]);
    expect(quote({ kind: "item", id: "dune_leaf" }, holding(), released)).toMatchObject({ ok: false, code: "not_for_sale" });
    // A released Fruit item still sells only while Fruits are on.
    const pear = releasedCatalog(new Set([904]), BUILT);
    expect(sold("pear_hood", pear)).toBe(false);
    expect(sold("pear_hood", pear, true)).toBe(true);
    // Every item built as released stays released.
    expect(offeredItems(released, true)).toEqual(expect.arrayContaining(Object.keys(CATALOG.items).filter(id => CATALOG.items[id].released)));
    expect(Object.isFrozen(released.items.reed_cap) && Object.isFrozen(released.items)).toBe(true);
  });
});

describe("the featured item", () => {
  const featured = (code: unknown) => featuredItem(withConfig({ cosmetics_featured: code }));
  it("names a released item sold for Pollen, and nothing else", () => {
    expect(featured(4)).toBe("tide");
    expect(featured(1)).toBe("daisy");
    expect(featured(7)).toBeUndefined(); // Gold leaf: earned, never sold
    expect(featured(10)).toBeUndefined(); // Apple hood: Fruits, not on the Pollen shelf
    expect(featured(998)).toBeUndefined(); // no such item
    expect(featuredItem(withConfig({}))).toBeUndefined();
    const env901 = withConfig({ cosmetics_featured: 901 });
    expect(featuredItem(env901, BUILT)).toBeUndefined(); // built unreleased
    expect(featuredItem(env901, releasedCatalog(new Set([901]), BUILT))).toBe("reed_cap");
  });
});

describe("the routes", () => {
  type Account = { player_id: string; device_token: string };
  const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
  const SHOP = { POLLEN_SECRET: SECRET, features: ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"] };
  const WARDROBE = { POLLEN_SECRET: SECRET, features: ["POLLEN_EARN", "POLLEN_WARDROBE"] };
  const LISTS = { cosmetics_released: [1, 2, 3, 901, 902], cosmetics_featured: 4 };
  let address = 0;
  const shared = env as unknown as Record<string, unknown>;
  beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
  afterEach(async () => { delete shared.POLLEN_SECRET; await reset(); });
  const call = (path: string, method: string, account: Account | undefined, vars: Record<string, unknown>, client: Record<string, string> = POLLEN_CLIENT, base: Env = env) =>
    worker.fetch(new Request("https://cosmetics.test" + path, { method, body: method === "POST" ? "{}" : undefined,
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.94." + (++address % 250), [POLLEN_HEADER]: "1", ...client,
        ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) } }), withConfig(Object.assign({ ...base }, vars)) as Env);
  const create = async (): Promise<Account> => (await call("/v1/identity", "POST", undefined, SHOP)).json<Account>();

  it("sends the featured code beside the shop's capability only, and keeps the tag while nothing new is released", async () => {
    const player = await create();
    const caps = async (vars: Record<string, unknown>, client = POLLEN_CLIENT) => (await call("/v2/capabilities", "GET", player, vars, client)).json<Record<string, unknown>>();
    const shop = await caps({ ...SHOP, ...LISTS });
    expect(shop.pollen_featured_code).toBe(4);
    expect(shop.pollen_offered_tag).toBe(OFFERED_TAG);
    expect(await caps(SHOP)).not.toHaveProperty("pollen_featured_code");
    expect(await caps({ ...WARDROBE, ...LISTS })).not.toHaveProperty("pollen_featured_code");
    expect(await caps({ ...SHOP, ...LISTS }, PRE_SHOP_CLIENT)).not.toHaveProperty("pollen_featured_code");
    expect(await caps({ ...SHOP, cosmetics_featured: 7 })).not.toHaveProperty("pollen_featured_code");
    expect(await caps({ ...SHOP, cosmetics_featured: 998 })).not.toHaveProperty("pollen_featured_code");
  });
});
