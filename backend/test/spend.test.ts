import { describe, expect, it } from "vitest";
import { CATALOG, checkedCatalog, offeredItems, offeredSets, validLook, type Catalog } from "../src/pollen/catalog";
import { charge, quote, setCost, type Holdings } from "../src/pollen/spend";
import manifest from "../../game/tests/fixtures/golden/cosmetic_manifest.json";

// The wardrobe's prices (POLLEN-RULES.md "Prices"): tiers, sets, owned pieces, the Special unlock and
// a negative balance. A fixture catalogue stands in for items nobody has released yet.
const item = (slot: string, tier: string, extra: Partial<{ unlock: string; set: string; released: boolean }> = {}) => ({ slot, tier, unlock: "", set: "", released: true, ...extra });
const FIXTURE: Catalog = checkedCatalog({
  ...JSON.parse(JSON.stringify(CATALOG)),
  items: {
    acorn_cap: item("hat", "common", { set: "meadow" }),
    daisy_pin: item("hat", "uncommon", { set: "meadow" }),
    petal_trail: item("body", "rare", { set: "meadow" }),
    meadow_draft: item("leaf", "epic", { set: "meadow", released: false }),
    lamp: item("hat", "special", { unlock: "sleeping-lighthouse", set: "shore" }),
    shell: item("hat", "common", { set: "shore" }),
    ribbon: item("hat", "earned"),
    hidden: item("hat", "common", { released: false })
  },
  packs: { garden_faces: { released: true, faces: ["heart_eyes", "proud", "wink"] }, big_feelings: { released: false, faces: ["wow", "crying", "dizzy"] } }
});
const holding = (owned: string[] = [], cleared: string[] = []): Holdings => ({ owned: new Set(owned), cleared: level => cleared.includes(level) });

describe("the shop catalogue", () => {
  it("matches the game's cosmetic manifest in everything but release", () => {
    const items = manifest.items as Record<string, { id: string; slot: string; tier: string; price: number; sold: boolean; unlock: string; set: string }>;
    expect(Object.keys(CATALOG.items).sort()).toEqual([...manifest.ids].sort());
    expect([...CATALOG.slots]).toEqual(manifest.slots);
    expect(CATALOG.tier_prices).toEqual(manifest.tier_prices);
    for (const [id, row] of Object.entries(items)) {
      const server = CATALOG.items[id];
      expect({ slot: server.slot, tier: server.tier, unlock: server.unlock, set: server.set }, id).toEqual({ slot: row.slot, tier: row.tier, unlock: row.unlock, set: row.set });
      expect(CATALOG.tier_prices[server.tier], id).toBe(row.price);
      expect(server.tier !== "earned" && row.price > 0, id).toBe(row.sold);
    }
  });
  it("keeps the 1:5:20:50:100 ramp and sells no earned item", () => {
    expect(CATALOG.tier_prices).toEqual({ common: 1000, uncommon: 5000, rare: 20000, epic: 50000, special: 100000, earned: 0 });
    for (const id of ["gold_leaf", "every_hard", "top_ten_ribbon"]) expect(quote({ kind: "item", id }, holding()), id).toMatchObject({ ok: false, code: "not_for_sale" });
  });
  it("refuses a catalogue that breaks its own rules", () => {
    const base = JSON.parse(JSON.stringify(CATALOG));
    expect(() => checkedCatalog({ ...base, items: { ...base.items, daisy: { ...base.items.daisy, slot: "shoe" } } })).toThrow();
    expect(() => checkedCatalog({ ...base, items: { ...base.items, gold_leaf: { ...base.items.gold_leaf, set: "meadow" } } })).toThrow();
    expect(() => checkedCatalog({ ...base, tier_prices: { ...base.tier_prices, earned: 5 } })).toThrow();
    expect(() => checkedCatalog({ ...base, packs: { daisy: { released: true } } })).toThrow();
    // Every pack face sits in exactly one pack, and a pack holds pack faces only.
    expect(() => checkedCatalog({ ...base, packs: { ...base.packs, garden_faces: { released: true, faces: ["heart_eyes", "proud", "wink", "happy"] } } })).toThrow();
    expect(() => checkedCatalog({ ...base, packs: { ...base.packs, garden_faces: { released: true, faces: ["heart_eyes", "proud", "wow"] } } })).toThrow();
    expect(() => checkedCatalog({ ...base, packs: { ...base.packs, garden_faces: { released: true, faces: ["heart_eyes", "proud"] } } })).toThrow();
    expect(() => checkedCatalog({ ...base, packs: { ...base.packs, garden_faces: { released: true, faces: [] } } })).toThrow();
    expect(() => checkedCatalog({ ...base, extra: 1 })).toThrow();
  });
  it("lists what is offered, and checks a look's shape against the slots", () => {
    expect(offeredItems(FIXTURE)).not.toContain("hidden");
    expect(offeredSets(FIXTURE)).toEqual(["meadow", "shore"]);
    expect(validLook({}, FIXTURE)).toBe(true);
    expect(validLook({ hat: "acorn_cap", body: "petal_trail" }, FIXTURE)).toBe(true);
    expect(validLook({ body: "acorn_cap" }, FIXTURE)).toBe(false);
    expect(validLook({ hat: "nothing" }, FIXTURE)).toBe(false);
    expect(validLook({ shoe: "acorn_cap" }, FIXTURE)).toBe(false);
    expect(validLook([], FIXTURE)).toBe(false);
  });
});

describe("spend maths", () => {
  it("prices one item by its tier", () => {
    expect(quote({ kind: "item", id: "daisy_pin" }, holding(), FIXTURE)).toEqual({ ok: true, value: { kind: "item", id: "daisy_pin", pieces: ["daisy_pin"], full: 5000, cost: 5000 } });
    expect(quote({ kind: "item", id: "nope" }, holding(), FIXTURE)).toMatchObject({ ok: false, status: 404, code: "unknown_item" });
    expect(quote({ kind: "item", id: "hidden" }, holding(), FIXTURE)).toMatchObject({ ok: false, code: "not_for_sale" });
    expect(quote({ kind: "item", id: "ribbon" }, holding(), FIXTURE)).toMatchObject({ ok: false, code: "not_for_sale" });
  });
  it("takes 15% off a set with two or more missing pieces, rounded down to 100", () => {
    // The rules' own example: a Common, an Uncommon and a Rare, 26,000 apart or 22,100 together.
    expect(quote({ kind: "set", id: "meadow" }, holding(), FIXTURE)).toEqual({ ok: true, value: { kind: "set", id: "meadow", pieces: ["acorn_cap", "daisy_pin", "petal_trail"], full: 26000, cost: 22100 } });
    expect(setCost(6000, 2, FIXTURE)).toBe(5100);
    expect(setCost(1100, 2, FIXTURE)).toBe(900);
    expect(setCost(5000, 1, FIXTURE)).toBe(5000);
  });
  it("never charges a piece the player owns, and charges one missing piece at its own price", () => {
    expect(quote({ kind: "set", id: "meadow" }, holding(["acorn_cap"]), FIXTURE)).toMatchObject({ ok: true, value: { pieces: ["daisy_pin", "petal_trail"], full: 25000, cost: 21200 } });
    expect(quote({ kind: "set", id: "meadow" }, holding(["acorn_cap", "daisy_pin"]), FIXTURE)).toMatchObject({ ok: true, value: { pieces: ["petal_trail"], full: 20000, cost: 20000 } });
    expect(quote({ kind: "set", id: "meadow" }, holding(["acorn_cap", "daisy_pin", "petal_trail"]), FIXTURE)).toMatchObject({ ok: false, code: "already_owned" });
    expect(quote({ kind: "item", id: "acorn_cap" }, holding(["acorn_cap"]), FIXTURE)).toMatchObject({ ok: false, status: 409, code: "already_owned" });
    expect(quote({ kind: "set", id: "nothing" }, holding(), FIXTURE)).toMatchObject({ ok: false, code: "unknown_item" });
  });
  it("sells a Special only after its chapter is cleared, alone or in its set", () => {
    expect(quote({ kind: "item", id: "lamp" }, holding(), FIXTURE)).toMatchObject({ ok: false, status: 403, code: "pollen_locked" });
    expect(quote({ kind: "set", id: "shore" }, holding(), FIXTURE)).toMatchObject({ ok: false, code: "pollen_locked" });
    expect(quote({ kind: "item", id: "lamp" }, holding([], ["sleeping-lighthouse"]), FIXTURE)).toMatchObject({ ok: true, value: { cost: 100000 } });
    expect(quote({ kind: "set", id: "shore" }, holding([], ["sleeping-lighthouse"]), FIXTURE)).toMatchObject({ ok: true, value: { full: 101000, cost: 85800 } });
    // Owning the locked piece already leaves only the open one to buy.
    expect(quote({ kind: "set", id: "shore" }, holding(["lamp"]), FIXTURE)).toMatchObject({ ok: true, value: { pieces: ["shell"], cost: 1000 } });
    expect(quote({ kind: "item", id: "lighthouse_lamp" }, holding())).toMatchObject({ ok: false, code: "pollen_locked" });
  });
  it("prices reaction packs flat", () => {
    expect(quote({ kind: "pack", id: "garden_faces" }, holding(), FIXTURE)).toMatchObject({ ok: true, value: { pieces: ["garden_faces"], cost: 5000 } });
    expect(quote({ kind: "pack", id: "big_feelings" }, holding(), FIXTURE)).toMatchObject({ ok: false, code: "not_for_sale" });
    expect(quote({ kind: "pack", id: "garden_faces" }, holding(["garden_faces"]), FIXTURE)).toMatchObject({ ok: false, code: "already_owned" });
    expect(quote({ kind: "pack", id: "acorn_cap" }, holding(), FIXTURE)).toMatchObject({ ok: false, code: "unknown_item" });
  });
  it("refuses a negative balance, a cost the phone did not show and a short balance", () => {
    const quoted = { kind: "item" as const, id: "daisy_pin", pieces: ["daisy_pin"], full: 5000, cost: 5000 };
    expect(charge(quoted, 5000, 5000)).toEqual({ ok: true, value: 0 });
    expect(charge(quoted, 24000, 5000)).toEqual({ ok: true, value: 19000 });
    expect(charge(quoted, -1, 5000)).toMatchObject({ ok: false, status: 403, code: "pollen_blocked" });
    expect(charge(quoted, -1, 4000)).toMatchObject({ code: "pollen_blocked" });
    expect(charge(quoted, 24000, 4000)).toMatchObject({ ok: false, status: 409, code: "pollen_price_changed" });
    expect(charge(quoted, 4999, 5000)).toMatchObject({ ok: false, status: 402, code: "pollen_short" });
  });
});
