import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { creditTurn, type PollenReceipt } from "../src/pollen/wallet";
import { droppable, itemBloomFromBytes, itemBloomMessage, itemBloomRoll, resolveItemBloom, type ItemBloomRoll, type ItemDrops } from "../src/pollen/item-blooms";
import { bloomMessage, bloomRoll } from "../src/pollen/blooms";
import { KEY_LABELS, derivedKey, hmac } from "../src/pollen/keys";
import { RATES, checkedRates, type Rates } from "../src/pollen/rates";
import { CATALOG, checkedCatalog, type Catalog } from "../src/pollen/catalog";
import { addDroppedItem, ownedItemIds } from "../src/pollen/wardrobe";
import { itemBloomsOn } from "../src/pollen/features";
import { isoWeek } from "../src/pollen/week";
import type { TurnFacts } from "../src/pollen/turn-facts";
import type { Outcome } from "../src/protocol";
import { meterRows } from "./meter";
import rawRates from "../src/pollen/rates.json";

// Item blooms: the odds table at every boundary, what a drop gives, the explicit empty and fully
// owned tier rule, independence from the lucky bloom, and a drop inside the turn credit. Synthetic ids only.
afterEach(async () => { await reset(); });
const SECRET = { POLLEN_SECRET: "synthetic-pollen-secret-for-tests-only-0001" };
const OWNER = "I".repeat(22), ROOM = "R".repeat(22);
const MONDAY = Date.UTC(2026, 9, 26, 9);
let serial = 0;
const hash = () => (++serial).toString(16).padStart(64, "0");
function facts(extra: Partial<TurnFacts> = {}): TurnFacts {
  return { schema_version: 1, room_id: ROOM, recording_hash: hash(), turn_id: "t0-0-a", player_id: OWNER, accepted_at: MONDAY, week: isoWeek(MONDAY),
    level_id: "first-steps", stage_id: "first-path", role: "a", ticks: 900, tries: null, premium: false, hard: false, host: true, together: true,
    complete: false, subscriber: false, partner_subscriber: false, boost_percent: 0, ...extra };
}
const value = <T>(outcome: Outcome<T>): T => { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; };
/** Eight bytes whose first word is `roll` and second `pick`, big-endian. */
function bytes(roll: number, pick = 0): Uint8Array {
  const out = new Uint8Array(32), view = new DataView(out.buffer);
  view.setUint32(0, roll); view.setUint32(4, pick); return out;
}
/** Rates where every free-chapter bank roll drops `tier`. */
const always = (tier: string): Rates => checkedRates({ ...rawRates, item_blooms: { modulus: 1_000_000, tiers: [{ tier, below: 1_000_000 }] } });
const DROPS: ItemDrops = { owned: ownedItemIds, give: addDroppedItem };
const stub = () => env.PLAYERS.getByName("item-blooms-" + serial);
const items = (storage: DurableObjectStorage) => storage.sql.exec<{ item_id: string; source: string }>("SELECT item_id, source FROM pollen_items ORDER BY item_id").toArray();

describe("item bloom odds", () => {
  it("drops by the cumulative thresholds out of 1,000,000, rarest first, at every boundary", () => {
    const vectors: [number, string | null][] = [
      [0, "special"], [1, "special"], [2, "epic"], [161, "epic"], [162, "rare"], [1761, "rare"], [1762, "uncommon"],
      [4261, "uncommon"], [4262, "common"], [9261, "common"], [9262, null], [999_999, null]
    ];
    for (const [roll, tier] of vectors) expect([roll, itemBloomFromBytes(bytes(roll)).tier]).toEqual([roll, tier]);
    // The roll is the first word mod 1,000,000; the pick is the second word, whole.
    expect(itemBloomFromBytes(bytes(3_000_001, 0xfffffffe))).toEqual({ roll: 1, pick: 0xfffffffe, tier: "special" });
    expect(itemBloomFromBytes(bytes(0xffffffff))).toMatchObject({ roll: 0xffffffff % 1_000_000 });
    // The rules' widths: 2, 160, 1,600, 2,500 and 5,000 per million.
    const widths = RATES.item_blooms.tiers.map((step, index, all) => [step.tier, step.below - (index ? all[index - 1].below : 0)]);
    expect(widths).toEqual([["special", 2], ["epic", 160], ["rare", 1600], ["uncommon", 2500], ["common", 5000]]);
    expect(RATES.item_blooms.modulus).toBe(1_000_000);
  });
  it("names only catalogue tiers that sell, and refuses thresholds out of order", () => {
    for (const step of RATES.item_blooms.tiers) expect(Object.hasOwn(CATALOG.tier_prices, step.tier) && step.tier !== "earned").toBe(true);
    const bad = (tiers: unknown) => () => checkedRates({ ...rawRates, item_blooms: { modulus: 1_000_000, tiers } });
    expect(bad([{ tier: "epic", below: 10 }, { tier: "rare", below: 10 }])).toThrow("item_blooms");
    expect(bad([{ tier: "epic", below: 10 }, { tier: "epic", below: 20 }])).toThrow("item_blooms");
    expect(bad([{ tier: "epic", below: 2_000_000 }])).toThrow("item_blooms");
  });
  it("rolls on its own key and label, never the lucky bloom's, so a turn may have both, one or neither", async () => {
    const slot = { player_id: OWNER, week: "2026-W44", level_id: "first-steps", stage_id: "first-path", role: "a" as const };
    expect(itemBloomMessage(slot)).toBe(`item-bloom-v1|${OWNER}|2026-W44|first-steps|first-path|a`);
    expect(bloomMessage(slot)).toBe(`pollen-bloom-v1|${OWNER}|2026-W44|first-steps|first-path|a`);
    const own = await hmac(await derivedKey(SECRET, KEY_LABELS.itemBloom)!, itemBloomMessage(slot));
    expect(await itemBloomRoll(SECRET, slot)).toEqual(itemBloomFromBytes(own));
    expect(await itemBloomRoll({}, slot)).toBeNull();
    // The same message under the lucky bloom's key gives other bytes.
    const other = await hmac(await derivedKey(SECRET, KEY_LABELS.bloom)!, itemBloomMessage(slot));
    expect(Array.from(other.slice(0, 8))).not.toEqual(Array.from(own.slice(0, 8)));
    // Over many synthetic slots the two rolls show no tie: drops land as often with a lucky bloom as without.
    let blooms = 0, drops = 0, both = 0;
    for (let index = 0; index < 20_000; index++) {
      const each = { ...slot, player_id: "S" + String(index).padStart(21, "0") };
      const [lucky, item] = await Promise.all([bloomRoll(SECRET, each), itemBloomRoll(SECRET, each, always20())]);
      const bloomed = lucky!.multiplier > 1, dropped = item!.tier !== null;
      blooms += Number(bloomed); drops += Number(dropped); both += Number(bloomed && dropped);
    }
    const expected = blooms * drops / 20_000;
    expect(blooms).toBeGreaterThan(1600); expect(blooms).toBeLessThan(2400);
    expect(drops).toBeGreaterThan(3600); expect(drops).toBeLessThan(4400);
    expect(Math.abs(both - expected)).toBeLessThan(4 * Math.sqrt(expected));
  });
});
/** A wider table for the independence check only (20% drop), so the sample has enough drops. */
function always20(): Rates { return checkedRates({ ...rawRates, item_blooms: { modulus: 1_000_000, tiers: [{ tier: "common", below: 200_000 }] } }); }

describe("what an item bloom gives", () => {
  const roll = (tier: string | null, pick = 0): ItemBloomRoll => ({ roll: 7, pick, tier });
  it("picks by index from the tier's sold items the player does not own, sorted by id", () => {
    expect(droppable("common")).toEqual(["daisy", "seashell"]);
    expect(resolveItemBloom(roll("common", 0), new Set())).toEqual({ tier: "common", roll: 7, item_id: "daisy" });
    expect(resolveItemBloom(roll("common", 1), new Set())).toEqual({ tier: "common", roll: 7, item_id: "seashell" });
    expect(resolveItemBloom(roll("common", 5), new Set(["daisy"]))).toEqual({ tier: "common", roll: 7, item_id: "seashell" });
    expect(resolveItemBloom(roll(null), new Set())).toBeNull();
  });
  it("can drop a Special that is not unlocked yet, since a drop costs nothing", () => {
    expect(droppable("special")).toEqual(["lighthouse_lamp"]);
    expect(resolveItemBloom(roll("special"), new Set())).toMatchObject({ item_id: "lighthouse_lamp" });
  });
  it("pays a fully owned tier's price instead, for every tier", () => {
    for (const [tier, price] of [["common", 1000], ["uncommon", 5000], ["rare", 20000], ["epic", 50000], ["special", 100000]] as const)
      expect(resolveItemBloom(roll(tier), new Set(droppable(tier)))).toEqual({ tier, roll: 7, pollen: price });
  });
  it("pays an empty tier's price: a tier with no released shop item has nothing to drop", () => {
    const empty = catalogWith(items => { items.lantern.released = false; });
    expect(droppable("epic", empty)).toEqual([]);
    expect(resolveItemBloom(roll("epic"), new Set(), empty)).toEqual({ tier: "epic", roll: 7, pollen: 50000 });
  });
  it("never drops an earned-only item, an item not released or a reaction pack", () => {
    const wide = catalogWith((items, catalog) => {
      items.unreleased_daisy = { slot: "hat", tier: "common", unlock: "", set: "", released: false };
      catalog.packs = { happy_faces: { released: true } };
    });
    expect(droppable("common", wide)).toEqual(["daisy", "seashell"]);
    expect(droppable("earned", wide)).toEqual([]);
    const all = RATES.item_blooms.tiers.flatMap(step => droppable(step.tier));
    expect(all.some(id => CATALOG.items[id].tier === "earned")).toBe(false);
    expect(all).not.toContain("happy_faces");
  });
});
function catalogWith(change: (items: Record<string, { slot: string; tier: string; unlock: string; set: string; released: boolean }>, catalog: Record<string, unknown>) => void): Catalog {
  const copy = JSON.parse(JSON.stringify(CATALOG));
  change(copy.items, copy);
  return checkedCatalog(copy);
}

describe("an item bloom in the turn credit", () => {
  const credit = (storage: DurableObjectStorage, turn: TurnFacts, rates: Rates, drops: ItemDrops | null = DROPS) =>
    creditTurn(storage, SECRET, OWNER, turn, MONDAY, () => true, rates, drops ?? undefined);
  it("owns the item in the same credit, records the roll and item in the claim, and gives it once on a retry", async () => {
    serial += 100;
    await runInDurableObject(stub(), async (_, state) => {
      const storage = state.storage, rates = always("common"), turn = facts();
      const first = value(await credit(storage, turn, rates));
      expect(first.item_bloom).toMatchObject({ tier: "common" });
      const dropped = (first.item_bloom as { item_id: string }).item_id;
      expect(["daisy", "seashell"]).toContain(dropped);
      expect(items(storage)).toEqual([{ item_id: dropped, source: "bloom" }]);
      // Its Pollen is the turn's alone: the drop adds nothing to the turn's total.
      expect(first.earned).toBe(first.turn!.total);
      const detail = JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM pollen_claims").one().data).detail;
      expect(detail).toMatchObject({ item_tier: "common", item_id: dropped });
      expect(typeof detail.item_roll).toBe("number");
      const again = value(await credit(storage, turn, rates));
      expect(again).toEqual(first);
      expect(items(storage)).toHaveLength(1);
    });
  });
  it("drops the other Common next, then pays 1,000 once both are owned, never boosted and never in the turn's total", async () => {
    serial += 100;
    await runInDurableObject(stub(), async (_, state) => {
      const storage = state.storage, rates = always("common");
      value(await credit(storage, facts({ stage_id: "one" }), rates));
      const second = value(await credit(storage, facts({ stage_id: "two" }), rates));
      expect(items(storage).map(row => row.item_id)).toEqual(["daisy", "seashell"]);
      expect(second.item_bloom).toHaveProperty("item_id");
      const third = value(await credit(storage, facts({ stage_id: "three", subscriber: true, boost_percent: 10 }), rates));
      expect(third.item_bloom).toEqual({ tier: "common", roll: expect.any(Number), pollen: 1000 });
      expect(third.earned).toBe(third.turn!.total + 1000);
      expect(third.turn!.boost).toBe(Math.floor((third.turn!.amount * 10 + 50) / 100));
    });
  });
  it("never rolls on a paid chapter, a guest's paid room, an after-bank turn, or while item blooms are off", async () => {
    serial += 100;
    await runInDurableObject(stub(), async (_, state) => {
      const storage = state.storage, rates = always("common");
      const paid = value(await credit(storage, facts({ level_id: "rolling-home", premium: true }), rates));
      const guest = value(await credit(storage, facts({ level_id: "rolling-home", premium: true, host: false, stage_id: "g" }), rates));
      const off = value(await credit(storage, facts({ stage_id: "off" }), rates, null));
      value(await credit(storage, facts({ stage_id: "repeat" }), rates));
      const repeat = value(await credit(storage, facts({ stage_id: "repeat" }), rates));
      expect(repeat.turn!.kind).toBe("after_bank");
      for (const receipt of [paid, guest, off, repeat] as PollenReceipt[]) expect(receipt).not.toHaveProperty("item_bloom");
      expect(items(storage)).toHaveLength(1);
    });
  });
  it("adds one wardrobe row for a dropped item and none for a turn that drops nothing", async () => {
    serial += 100;
    const player = stub();
    // Make the tables first, then measure two more turns: one that drops an item and one that cannot.
    await runInDurableObject(player, async (_, state) => { value(await credit(state.storage, facts({ stage_id: "warm" }), always("common"))); });
    const plain = await meterRows({ player }, () => runInDurableObject(player, async (_, state) => value(await credit(state.storage, facts({ stage_id: "plain" }), RATES, null))));
    const drop = await meterRows({ player }, () => runInDurableObject(player, async (_, state) => value(await credit(state.storage, facts({ stage_id: "drop" }), always("common")))));
    console.log("item bloom rows", JSON.stringify({ plain: plain.rows, drop: drop.rows }));
    expect(drop.value.item_bloom).toHaveProperty("item_id");
    expect(drop.rows.player.written - plain.rows.player.written).toBe(1);
  });
});

describe("the item bloom flag", () => {
  it("is on only with POLLEN_ITEM_BLOOMS, the shop and earning", () => {
    expect(itemBloomsOn({ FEATURES: "POLLEN_EARN,POLLEN_SHOP,POLLEN_ITEM_BLOOMS", ...SECRET })).toBe(true);
    expect(itemBloomsOn({ FEATURES: "POLLEN_EARN,POLLEN_ITEM_BLOOMS", ...SECRET })).toBe(false);
    expect(itemBloomsOn({ FEATURES: "POLLEN_EARN,POLLEN_SHOP", ...SECRET })).toBe(false);
    expect(itemBloomsOn({ FEATURES: "POLLEN_EARN,POLLEN_SHOP,POLLEN_ITEM_BLOOMS" })).toBe(false);
  });
});
