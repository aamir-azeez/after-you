import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import fruitsJson from "../src/pollen/fruits.json";
import { FRUIT_RULES, checkedFruitRules, fruitInstalment, goalOf, ladderAmount } from "../src/pollen/fruits";
import { BUNDLES, firstGift, keysOf, storeReady } from "../src/pollen/bundles";
import { CATALOG, FRUITS_OFFERED_TAG, OFFERED_TAG, itemCurrency, offeredItems, sold } from "../src/pollen/catalog";
import { quote, setCost } from "../src/pollen/spend";
import { RATES } from "../src/pollen/rates";
import { droppable } from "../src/pollen/item-blooms";
import { FRUIT_PREFIX, purse, setPurse } from "../src/pollen/currency";
import { applyLedger, creditClear, creditTurn, dropWallet, historyView, ledgerLines, noteFullJourney, validWallet, walletView, type FruitHooks } from "../src/pollen/wallet";
import { forgetClaimPace, planBundles, settleBundles } from "../src/pollen/bundle-settle";
import type { BundlePurchase } from "../src/pollen/bundle-provider";
import { buySunshine, convertFruits, spendSunshineTurn, withReclaim } from "../src/pollen/fruit-ops";
import { achievementsView, settleAchievements } from "../src/pollen/achievements";
import { creditDuelWin } from "../src/pollen/duel-pay";
import { anniversary, type GrantSub } from "../src/pollen/grant";
import { settleGrant, type GrantDeps } from "../src/pollen/grant-settle";
import { fruitsView } from "../src/pollen/fruits-view";
import { fruitPacksOn, fruitsOn } from "../src/pollen/features";
import { isoWeek } from "../src/pollen/week";
import type { TurnFacts } from "../src/pollen/turn-facts";
import type { Outcome } from "../src/protocol";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { POLLEN_CLIENT, withConfig } from "./config";
import { meterRows } from "./meter";

// Fruits, the second currency (PLAN v2 with the owner's answers of 2026-11-09): the rules as data, Fruit lines on the shared
// ledger, packs and their first-pack gift, converting and taking it back on a refund, Sunshine, achievements, the grant's
// Fruits, the routes with FRUITS on and off, what older code still reads, and the rows each action writes. Synthetic ids only.
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const DAY = 86_400_000, HOUR = 3_600_000;
const MONDAY = Date.UTC(2026, 9, 26, 9);
const OWNER = "F".repeat(22), ROOM = "R".repeat(22);
let serial = 0;
const hash = () => (++serial).toString(16).padStart(64, "0");
const value = <T>(outcome: Outcome<T>): T => { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; };
async function inPlayer<T>(work: (storage: DurableObjectStorage) => Promise<T> | T): Promise<T> {
  return runInDurableObject(env.PLAYERS.getByName("fruits-" + ++serial), async (_, state) => work(state.storage));
}
const fruitBalance = (storage: DurableObjectStorage) => purse(storage, "fruits").balance;
const fund = (storage: DurableObjectStorage, fruits: number) => applyLedger(storage, [{ key: `${FRUIT_PREFIX}bundle:GPA.fund-${++serial}`, kind: "fruitbundle", amount: fruits, detail: { bundle: "crate" } }], MONDAY);
const HOOKS: FruitHooks = { sunshine: spendSunshineTurn, achievements: (storage, now, moment) => settleAchievements(storage, now, moment) };
function facts(extra: Partial<TurnFacts> = {}, at = MONDAY): TurnFacts {
  return { schema_version: 1, room_id: ROOM, recording_hash: hash(), turn_id: "t0-0-a", player_id: OWNER, accepted_at: at, week: isoWeek(at),
    level_id: "first-steps", stage_id: "first-path", role: "a", ticks: 900, tries: null, premium: false, hard: false, host: true, together: true,
    complete: false, subscriber: false, partner_subscriber: false, boost_percent: 0, ...extra };
}
afterEach(async () => { await reset(); });

describe("the Fruit rules", () => {
  it("pays the ladder: 10 a month, 1 more each month, 24 from month 15, and a 10 welcome basket", () => {
    expect([1, 2, 3, 4, 5, 6, 11, 12, 14, 15, 60].map(n => fruitInstalment(n))).toEqual([10, 11, 12, 13, 14, 15, 20, 21, 23, 24, 24]);
    expect(FRUIT_RULES.grant.welcome).toBe(10);
    // One ladder function prices both currencies: the Pollen grant's own ladder has every 1.
    expect([1, 2, 31].map(n => ladderAmount(n, { ...RATES.grant, every: 1 }))).toEqual([4500, 4750, 12000]);
  });
  it("lists 15 achievements worth 340 Fruits, the keepsake two dormant, and every chapter as the together goal", () => {
    expect(FRUIT_RULES.achievements.length).toBe(15);
    expect(FRUIT_RULES.achievements.reduce((sum, item) => sum + item.fruits, 0)).toBe(340);
    expect(goalOf(FRUIT_RULES.achievements.find(item => item.id === "together_all")!)).toBe(Object.keys(RATES.chapters).length);
    expect(FRUIT_RULES.achievements.every(item => item.fruits >= 10)).toBe(true);
  });
  it("refuses a rules file outside its shape", () => {
    const copy = () => JSON.parse(JSON.stringify(fruitsJson));
    for (const change of [(v: any) => { v.grant.every = 0; }, (v: any) => { v.convert.step = 0; }, (v: any) => { v.sunshine.turns = 1.5; },
      (v: any) => { v.achievements[1].id = v.achievements[0].id; }, (v: any) => { v.achievements[0].track = "nope"; }, (v: any) => { v.achievements[3].goal = 0; }, (v: any) => { v.extra = 1; }]) {
      const value = copy(); change(value);
      expect(() => checkedFruitRules(value)).toThrow(/invalid_fruit_rules/);
    }
  });
  it("sells Handful 25, Bowl 55, Crate 120 and Barrel 260 at the plan's prices, set up in RevenueCat on both stores, the first paying double", () => {
    expect(keysOf("fruits").map(key => [key, BUNDLES.bundles[key].amount, BUNDLES.bundles[key].bonus, BUNDLES.bundles[key].play_store.usd_cents, BUNDLES.bundles[key].app_store.usd_cents]))
      .toEqual([["handful", 25, 0, 249, 299], ["bowl", 55, 5, 499, 599], ["crate", 120, 20, 999, 1099], ["barrel", 260, 60, 1999, 2199]]);
    expect(keysOf("fruits").map(key => firstGift(key))).toEqual([25, 55, 120, 260]);
    expect(keysOf("fruits").map(key => BUNDLES.bundles[key].play_store.product)).toEqual(["after_you_fruits_handful", "after_you_fruits_bowl", "after_you_fruits_crate", "after_you_fruits_barrel"]);
    expect(keysOf("fruits").map(key => BUNDLES.bundles[key].app_store.product)).toEqual(["after_you_fruits_handful_ios", "after_you_fruits_bowl_ios", "after_you_fruits_crate_ios", "after_you_fruits_barrel_ios"]);
    expect([storeReady("play_store", "fruits"), storeReady("app_store", "fruits"), storeReady("play_store", "pollen"), storeReady("app_store", "pollen")]).toEqual([true, true, true, true]);
    // Pollen keeps its own 20% gift.
    expect(firstGift("pouch")).toBe(4200);
  });
  it("prices the Orchard in Fruits (Sprig 20, small 50, hat 100, body 200, the set 295), sold only while Fruits are on, never from a bloom", () => {
    expect(Object.fromEntries(Object.keys(CATALOG.items).filter(id => itemCurrency(id) === "fruits").map(id => [id, CATALOG.tier_prices[CATALOG.items[id].tier]])))
      .toEqual({ apple_hood: 100, blueberry_hood: 100, blossom_crown: 100, orchard_skin: 200, apple_leaf: 50, sprig_coral: 20, sprig_plum: 20, sprig_sun: 20, sprig_sky: 20 });
    expect(sold("apple_hood")).toBe(false);
    expect(sold("apple_hood", CATALOG, true)).toBe(true);
    const owned = { owned: new Set<string>(), cleared: () => false };
    expect(quote({ kind: "set", id: "orchard" }, owned, CATALOG, true)).toEqual({ ok: true, value: { kind: "set", id: "orchard", pieces: ["apple_hood", "orchard_skin", "apple_leaf"], full: 350, cost: 295, currency: "fruits" } });
    expect(quote({ kind: "set", id: "orchard" }, { ...owned, owned: new Set(["apple_hood"]) }, CATALOG, true)).toMatchObject({ value: { full: 250, cost: 210 } });
    expect(quote({ kind: "set", id: "orchard" }, { ...owned, owned: new Set(["apple_leaf"]) }, CATALOG, true)).toMatchObject({ value: { full: 300, cost: 255 } });
    expect(quote({ kind: "set", id: "orchard" }, { ...owned, owned: new Set(["orchard_skin"]) }, CATALOG, true)).toMatchObject({ value: { full: 150, cost: 125 } });
    // One piece missing costs its own price.
    expect(quote({ kind: "set", id: "orchard" }, { ...owned, owned: new Set(["apple_hood", "orchard_skin"]) }, CATALOG, true)).toMatchObject({ value: { pieces: ["apple_leaf"], full: 50, cost: 50 } });
    expect(quote({ kind: "item", id: "sprig_sun" }, owned)).toMatchObject({ ok: false, code: "not_for_sale" });
    expect(setCost(26000, 3, CATALOG, "pollen")).toBe(22100);
    for (const step of RATES.item_blooms.tiers) expect(droppable(step.tier).some(id => itemCurrency(id) === "fruits"), step.tier).toBe(false);
    expect(offeredItems()).not.toContain("apple_hood");
    expect(offeredItems(CATALOG, true)).toContain("apple_hood");
    expect(FRUITS_OFFERED_TAG).not.toBe(OFFERED_TAG);
  });
  it("turns on only with the shop, and sells packs only where that store's bundles sell and its Fruit products are set up", () => {
    const vars = (features: string[]) => withConfig({ POLLEN_SECRET: SECRET, features });
    expect(fruitsOn(vars(["FRUITS"]))).toBe(false);
    expect(fruitsOn(vars(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"]))).toBe(false);
    expect(fruitsOn(vars(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "FRUITS"]))).toBe(true);
    // Set up in RevenueCat: Play sells Fruit packs once Fruits and Play's bundles are both on.
    expect(fruitPacksOn(vars(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS", "POLLEN_BUNDLES", "FRUITS"]))).toBe(true);
    expect(fruitPacksOn(vars(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS", "POLLEN_BUNDLES"]))).toBe(false);
    expect(fruitPacksOn(vars(["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS", "FRUITS"]))).toBe(false);
  });
});

describe("Fruit lines on the shared ledger", () => {
  it("credit the purse, never the Pollen wallet row, which keeps exactly the shape older code checks", async () => {
    await inPlayer(storage => {
      applyLedger(storage, [{ key: "grant:1:1", kind: "grant", amount: 4500, detail: {} }], MONDAY);
      fund(storage, 120);
      expect(walletView(storage, MONDAY).balance).toBe(4500);
      expect(fruitBalance(storage)).toBe(120);
      const row = JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM pollen_wallet").one().data);
      expect(validWallet(row)).toBe(true);
      // A Pollen prefix never reaches a Fruit line, and the Pollen history never lists one.
      expect(ledgerLines(storage, "bundle:", 64)).toEqual([]);
      expect(historyView(storage, MONDAY).entries.map(entry => entry.kind)).toEqual(["grant"]);
    });
  });
  it("go with the wallet on account erasure", async () => {
    await inPlayer(storage => {
      fund(storage, 10);
      dropWallet(storage);
      expect(storage.sql.exec("SELECT name FROM sqlite_master WHERE name IN ('currency_purse','pollen_claims','pollen_wallet')").toArray()).toEqual([]);
    });
  });
  it("write nothing at all for a player Fruits never touched", async () => {
    await inPlayer(async storage => {
      value(await creditTurn(storage, { POLLEN_SECRET: SECRET }, OWNER, facts(), MONDAY, () => true));
      expect(storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='currency_purse'").toArray()).toEqual([]);
    });
  });
});

describe("Fruit packs", () => {
  const p = (id: string, bundle: BundlePurchase["bundle"], extra: Partial<BundlePurchase> = {}): BundlePurchase => ({ id, bundle, refunded: false, quantity: 1, order: "GPA." + id, usd_cents: 249, purchased_at: ++serial, ...extra });
  const settle = (storage: DurableObjectStorage, purchases: BundlePurchase[]) => { forgetClaimPace(storage);
    return settleBundles(storage, MONDAY, () => true, { read: async () => ({ ok: true as const, purchases }), claim: async asked => Object.fromEntries(asked.map(each => [each.order, true])), fruits: true }); };
  it("pay the first Fruit pack double once, apart from the Pollen gift, and a refund takes the pack and its gift back", async () => {
    await inPlayer(async storage => {
      const one = p("f1", "handful"), two = p("f2", "bowl"), pollen = p("p1", "pouch");
      expect(await settle(storage, [one])).toMatchObject({ status: "settled", reply: { credited: [], fruit_credited: [{ bundle: "handful", fruits: 25, first_gift: 25 }], fruit_balance: 50 } });
      // The Pollen gift is still open, and the second Fruit pack pays no gift.
      expect(await settle(storage, [one, two, pollen])).toMatchObject({ reply: { credited: [{ bundle: "pouch", pollen: 21000, first_gift: 4200 }], fruit_credited: [{ bundle: "bowl", fruits: 55, first_gift: 0 }], fruit_balance: 105 } });
      expect(await settle(storage, [{ ...one, refunded: true }, two, pollen])).toMatchObject({ reply: { refunded: [], fruit_refunded: [{ bundle: "handful", amount: 50, pollen_taken: 0 }], fruit_balance: 55 } });
      // Paid once: the same list again changes nothing.
      expect(await settle(storage, [{ ...one, refunded: true }, two, pollen])).toMatchObject({ reply: { fruit_credited: [], fruit_refunded: [], fruit_balance: 55 } });
      expect(walletView(storage, MONDAY).balance).toBe(25200);
    });
  });
  it("wait unpaid while Fruits are off, and pay once they are on", async () => {
    await inPlayer(async storage => {
      const pack = p("w1", "crate"), read = async () => ({ ok: true as const, purchases: [pack] }), claim = async (asked: BundlePurchase[]) => Object.fromEntries(asked.map(each => [each.order, true]));
      forgetClaimPace(storage);
      expect(await settleBundles(storage, MONDAY, () => true, { read, claim, fruits: false })).toMatchObject({ reply: { credited: [] } });
      expect(storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='currency_purse'").toArray()).toEqual([]);
      expect(await settleBundles(storage, MONDAY, () => true, { read, claim, fruits: true })).toMatchObject({ reply: { fruit_credited: [{ bundle: "crate", fruits: 120, first_gift: 120 }] } });
    });
  });
  it("pay one App Store sandbox Fruit pack per identity", () => {
    const sandbox = (id: string) => p(id, "crate", { sandbox: true, order: "appstore:" + id });
    const plan = planBundles([sandbox("s1"), sandbox("s2")], () => true, [], new Set(), { pollen: true, fruits: true });
    expect(plan.fruitCredited.map(each => each.order)).toEqual(["s1"]);
    const later = planBundles([sandbox("s3")], () => true, [{ key: "fruit:bundle:appstore:s1", amount: 240, detail: { environment: "sandbox" } }], new Set(), { pollen: true, fruits: false });
    expect(later.fruitCredited).toEqual([]);
  });
});

describe("turning Fruits into Pollen", () => {
  it("pays 300 Pollen a Fruit, 10 at a time, and refuses while either balance is below zero", async () => {
    await inPlayer(storage => {
      fund(storage, 35);
      expect(convertFruits(storage, "key-a", 15, 15, MONDAY)).toMatchObject({ ok: false, code: "invalid_pollen_spend" });
      expect(convertFruits(storage, "key-a", 20, 10, MONDAY)).toMatchObject({ ok: false, code: "pollen_price_changed" });
      expect(convertFruits(storage, "key-a", 40, 40, MONDAY)).toMatchObject({ ok: false, status: 402, code: "fruits_short" });
      expect(value(convertFruits(storage, "key-a", 20, 20, MONDAY))).toEqual({ fruits: 20, pollen: 6000, fruit_balance: 15, balance: 6000 });
      expect(purse(storage, "converted").balance).toBe(20);
      applyLedger(storage, [{ key: "bundlerefund:x", kind: "bundlerefund", amount: -9000, detail: {} }], MONDAY);
      expect(convertFruits(storage, "key-b", 10, 10, MONDAY)).toMatchObject({ ok: false, status: 403, code: "fruits_blocked" });
    });
  });
  it("never converts twice for one request key, even after its receipt is gone", async () => {
    await inPlayer(storage => {
      fund(storage, 40);
      value(convertFruits(storage, "same-key", 10, 10, MONDAY));
      expect(convertFruits(storage, "same-key", 10, 10, MONDAY)).toMatchObject({ ok: false, status: 409, code: "idempotency_key_reused" });
      expect([fruitBalance(storage), walletView(storage, MONDAY).balance, purse(storage, "converted").balance]).toEqual([30, 3000, 10]);
    });
  });
  it("takes back several Fruit refunds in one settle in order, Pollen only for what was converted", async () => {
    await inPlayer(storage => {
      applyLedger(storage, [{ key: "fruit:bundle:GPA.m1", kind: "fruitbundle", amount: 30, detail: {} }, { key: "fruit:bundle:GPA.m2", kind: "fruitbundle", amount: 30, detail: {} }], MONDAY);
      value(convertFruits(storage, "convert-m", 50, 50, MONDAY));
      const back = withReclaim(storage, [{ key: "fruit:bundlerefund:GPA.m1", kind: "fruitbundlerefund", amount: -30, detail: {} }, { key: "fruit:bundlerefund:GPA.m2", kind: "fruitbundlerefund", amount: -30, detail: {} }]);
      applyLedger(storage, back.entries, MONDAY);
      expect([back.pollen.get("fruit:bundlerefund:GPA.m1"), back.pollen.get("fruit:bundlerefund:GPA.m2")]).toEqual([6000, 9000]);
      expect([fruitBalance(storage), walletView(storage, MONDAY).balance, purse(storage, "converted").balance]).toEqual([0, 0, 0]);
    });
  });
  it("never keeps anything when bought, converted and refunded: the converted shortfall comes back as Pollen", async () => {
    await inPlayer(storage => {
      applyLedger(storage, [{ key: "fruit:bundle:GPA.r1", kind: "fruitbundle", amount: 50, detail: {} }], MONDAY);
      value(convertFruits(storage, "convert-1", 40, 40, MONDAY));
      expect([fruitBalance(storage), walletView(storage, MONDAY).balance]).toEqual([10, 12000]);
      const back = withReclaim(storage, [{ key: "fruit:bundlerefund:GPA.r1", kind: "fruitbundlerefund", amount: -50, detail: {} }]);
      applyLedger(storage, back.entries, MONDAY);
      expect([fruitBalance(storage), walletView(storage, MONDAY).balance, purse(storage, "converted").balance]).toEqual([0, 0, 0]);
      expect(back.pollen.get("fruit:bundlerefund:GPA.r1")).toBe(12000);
      expect(historyView(storage, MONDAY).entries.map(entry => [entry.kind, entry.amount]).sort()).toEqual([["convert", 12000], ["reclaim", -12000]]);
    });
  });
  it("takes back only the converted part as Pollen: Fruits spent on items stay below zero as Fruits", async () => {
    await inPlayer(storage => {
      applyLedger(storage, [{ key: "fruit:bundle:GPA.r2", kind: "fruitbundle", amount: 50, detail: {} }], MONDAY);
      setPurse(storage, "fruits", { balance: 30, earned: 50 }); // a Sprig bought for 20
      value(convertFruits(storage, "convert-2", 30, 30, MONDAY));
      applyLedger(storage, withReclaim(storage, [{ key: "fruit:bundlerefund:GPA.r2", kind: "fruitbundlerefund", amount: -50, detail: {} }]).entries, MONDAY);
      expect([fruitBalance(storage), walletView(storage, MONDAY).balance]).toEqual([-20, 0]);
    });
  });
});

describe("Sunshine", () => {
  const credit = (storage: DurableObjectStorage, turn: TurnFacts, hooks: FruitHooks | null = HOOKS) => creditTurn(storage, { POLLEN_SECRET: SECRET }, OWNER, turn, turn.accepted_at, () => true, RATES, undefined, hooks ?? undefined);
  const slots = Array.from({ length: 40 }, (_, index) => ({ stage_id: "stage-" + Math.floor(index / 2), role: (index % 2 ? "b" : "a") as "a" | "b" }));
  it("is bought for 20 Fruits only when none is left", async () => {
    await inPlayer(storage => {
      expect(buySunshine(storage, 20)).toMatchObject({ ok: false, code: "fruits_short" });
      fund(storage, 35);
      expect(buySunshine(storage, 25)).toMatchObject({ ok: false, code: "pollen_price_changed" });
      expect(value(buySunshine(storage, 20))).toEqual({ fruit_balance: 15, sunshine_left: 48 });
      expect(buySunshine(storage, 20)).toMatchObject({ ok: false, status: 409, code: "sunshine_active" });
    });
  });
  it("pays a bank turn's plain amount again for 48 bank turns, never after the bank, on a retry or on the boost", async () => {
    await inPlayer(async storage => {
      fund(storage, 20); value(buySunshine(storage, 20));
      const turn = facts({ ...slots[0], tries: 1, subscriber: true, boost_percent: 10 });
      const paid = value(await credit(storage, turn));
      expect(paid.turn).toMatchObject({ kind: "bank", amount: 111, sunshine: 111, boost: 11 });
      expect(paid.turn!.total).toBe(paid.turn!.amount + paid.turn!.bloom_extra + paid.turn!.boost + 111);
      expect(paid.sunshine_left).toBe(47);
      // A retry answers its receipt and spends nothing.
      expect(value(await credit(storage, turn))).toMatchObject({ turn: { sunshine: 111 }, sunshine_left: 47 });
      expect(purse(storage, "sunshine").balance).toBe(47);
      // A repeat of the slot is after the bank: no Sunshine.
      expect(value(await credit(storage, facts({ ...slots[0] })))).not.toHaveProperty("sunshine_left");
      for (const place of slots.slice(1, 12)) value(await credit(storage, facts(place)));
      expect(purse(storage, "sunshine").balance).toBe(36);
      // Bank empty: nothing more spent this week.
      const emptyBank = value(await credit(storage, facts(slots[12])));
      expect(emptyBank.turn!.sunshine).toBeUndefined();
      expect(purse(storage, "sunshine").balance).toBe(36);
      // Without the Fruit hooks (FRUITS off) nothing is spent or paid.
      const later = facts({ ...slots[13] }, MONDAY + 7 * DAY);
      expect(value(await credit(storage, later, null)).turn!.sunshine).toBeUndefined();
      expect(purse(storage, "sunshine").balance).toBe(36);
      expect(historyView(storage, MONDAY).entries.filter(entry => entry.sunshine).length).toBe(12);
    });
  });
  it("runs out after 48 bank turns", async () => {
    await inPlayer(async storage => {
      fund(storage, 20); value(buySunshine(storage, 20));
      for (let week = 0; week < 5; week++) for (const place of slots.slice(0, 12)) value(await credit(storage, facts(place, MONDAY + week * 7 * DAY)));
      expect(purse(storage, "sunshine")).toEqual({ balance: 0, earned: 48 });
    });
  });
});

describe("achievements", () => {
  it("pay each once, at the moment and on the sweep, and never the dormant keepsake goals", async () => {
    await inPlayer(async storage => {
      // A clear before Fruits: the sweep counts it.
      value(creditClear(storage, { level_id: "relay-isles", hard: false, boost_percent: 0 }, MONDAY, () => true));
      const swept = settleAchievements(storage, MONDAY);
      expect(swept).toEqual({ balance: 10, paid: [{ id: "together_first", amount: 10 }] });
      expect(settleAchievements(storage, MONDAY)).toBeNull();
      // A Hard clear together: hard_first, once.
      const hard = value(creditClear(storage, { level_id: "first-steps", hard: true, boost_percent: 0, room_id: ROOM, together: true }, MONDAY, () => true, RATES, HOOKS));
      expect(hard.fruits).toEqual({ balance: 20, paid: [{ id: "hard_first", amount: 10 }] });
      expect(value(creditClear(storage, { level_id: "first-steps", hard: true, boost_percent: 0, room_id: ROOM, together: true }, MONDAY, () => true, RATES, HOOKS)).fruits).toBeUndefined();
      const view = achievementsView(storage);
      expect(view.find(item => item.id === "together_five")).toMatchObject({ goal: 5, progress: 2, live: true });
      expect(view.find(item => item.id === "hard_first")).toMatchObject({ progress: 1, paid_at: MONDAY, level_id: "first-steps" });
      expect(view.filter(item => !item.live).map(item => item.id)).toEqual(["keepsake_first", "keepsake_all"]);
      expect(ledgerLines(storage, "fruit:ach:", 64).length).toBe(2);
    });
  });
  it("count paid friend duel wins only, never a public duel's or one past the weekly limits, and pay the first and the tenth", async () => {
    await inPlayer(storage => {
      settleAchievements(storage, MONDAY);
      const fresh = (at: number) => ({ fresh: (s: DurableObjectStorage, paid: boolean) => { settleAchievements(s, at, paid ? { duel_win: true } : {}); } });
      creditDuelWin(storage, { duel_id: "public-1", opponent: "pair-x", decided_ms: MONDAY }, MONDAY, () => true, RATES, { fresh: s => { settleAchievements(s, MONDAY); }, public: true });
      expect(purse(storage, "count:duel_wins").balance).toBe(0);
      // Four friend wins in the public win's week: the week pays three wins in all, so two of them count and two pay 0 and count toward nothing.
      for (let n = 0; n < 4; n++) creditDuelWin(storage, { duel_id: "week-" + n, opponent: "pair-" + n, decided_ms: MONDAY }, MONDAY, () => true, RATES, fresh(MONDAY));
      expect(purse(storage, "count:duel_wins").balance).toBe(2);
      // One more a week for eight weeks: ten paid friend wins.
      for (let week = 1; week <= 8; week++) {
        const at = MONDAY + week * 7 * DAY;
        creditDuelWin(storage, { duel_id: "later-" + week, opponent: "pair-later-" + week, decided_ms: at }, at, () => true, RATES, fresh(at));
      }
      // A repeat of a win is not a new one.
      creditDuelWin(storage, { duel_id: "week-0", opponent: "pair-0", decided_ms: MONDAY }, MONDAY, () => true, RATES, fresh(MONDAY));
      expect(purse(storage, "count:duel_wins").balance).toBe(10);
      expect(ledgerLines(storage, "fruit:ach:duel_win", 8).map(line => [line.key, line.amount])).toEqual([["fruit:ach:duel_win_first", 10], ["fruit:ach:duel_win_ten", 10]]);
    });
  });
  it("mark a chapter finished together on a turn, so a clear made solo before still counts once it is played together", async () => {
    await inPlayer(async storage => {
      settleAchievements(storage, MONDAY);
      const turn = facts({ complete: true, level_id: "high-and-low", stage_id: "s", role: "a" });
      const paid = value(await creditTurn(storage, { POLLEN_SECRET: SECRET }, OWNER, turn, MONDAY, () => true, RATES, undefined, HOOKS));
      expect(paid.fruits).toEqual({ balance: 10, paid: [{ id: "together_first", amount: 10 }] });
      expect(ledgerLines(storage, "fruit:together:", 16).map(line => line.key)).toEqual(["fruit:together:high-and-low"]);
    });
  });
});

describe("the grant's Fruits", () => {
  const DUE = Date.UTC(2026, 7, 3, 10);
  const paid = (id: string, from: number, to: number): GrantSub => ({ id, status: "paid", started_at: from, period_start: from, period_end: to, ends_at: to, renews: true, access_until: to });
  const ended = (id: string, from: number, to: number, endsAt: number): GrantSub => ({ id, status: "ended", started_at: from, period_start: from, period_end: to, ends_at: endsAt, renews: false, access_until: 0 });
  const self = async (keys: string[]) => Object.fromEntries(keys.map(key => [key, { self: true, since: DUE }]));
  it("pays 10 Fruits and the welcome basket with the first month, 11 the next, and nothing while Fruits are off", async () => {
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      const start = DUE - HOUR, next = anniversary(start, 1);
      const told: { key: string; amount: number }[][] = [];
      const deps = (subs: GrantSub[], fruits = true): GrantDeps => ({ read: async () => ({ ok: true, subs, lifetime: null }), claim: self, fruits, paid: lines => told.push([...lines]) });
      expect(await settleGrant(storage, DUE, () => true, deps([paid("sub_f", start, next)]))).toBe("settled");
      expect([walletView(storage, DUE).balance, fruitBalance(storage)]).toEqual([4500, 20]);
      expect(fruitsView(storage, DUE).grant).toMatchObject({ next: 11, welcome_paid: true, latest: { amount: 10, welcome: 10 } });
      // The push and `latest` stay Pollen only.
      expect(told).toEqual([[{ key: `grant:${start}:1`, amount: 4500 }]]);
      noteFullJourney(storage, next + 20 * DAY, next);
      expect(await settleGrant(storage, next + HOUR, () => true, deps([paid("sub_f", next, anniversary(start, 2))]))).toBe("settled");
      expect(fruitBalance(storage)).toBe(31);
      noteFullJourney(storage, anniversary(start, 2) + 20 * DAY, anniversary(start, 2));
      expect(await settleGrant(storage, anniversary(start, 2) + HOUR, () => true, deps([paid("sub_f", anniversary(start, 2), anniversary(start, 3))], false))).toBe("settled");
      expect([walletView(storage, anniversary(start, 2) + HOUR).balance, fruitBalance(storage)]).toEqual([4500 + 4750 + 5000, 31]);
    });
  });
  it("pays no Fruits in a trial, the basket with an existing subscriber's next month, and no Fruits for months due before the catch-up window", async () => {
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      const start = DUE - HOUR, next = anniversary(start, 1);
      const trial: GrantSub = { ...paid("sub_t", start, next), status: "trial" };
      await settleGrant(storage, DUE, () => true, { read: async () => ({ ok: true, subs: [trial], lifetime: null }), claim: self, fruits: true });
      expect(fruitBalance(storage)).toBe(0);
    });
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      const start = DUE - HOUR, next = anniversary(start, 1);
      // A month paid before Fruits went on: no Fruits for it, ever.
      expect(await settleGrant(storage, DUE, () => true, { read: async () => ({ ok: true, subs: [paid("sub_e", start, next)], lifetime: null }), claim: self, fruits: false })).toBe("settled");
      noteFullJourney(storage, next + 20 * DAY, next);
      expect(await settleGrant(storage, next + HOUR, () => true, { read: async () => ({ ok: true, subs: [paid("sub_e", next, anniversary(start, 2))], lifetime: null }), claim: self, fruits: true })).toBe("settled");
      // Month 2 at its step (11) and the welcome basket with it.
      expect(fruitBalance(storage)).toBe(21);
    });
    await inPlayer(async storage => {
      // Three months caught up at once, long after: only the month due within the window pays Fruits.
      const start = DUE - 70 * DAY, now = anniversary(start, 2) + HOUR;
      noteFullJourney(storage, anniversary(start, 3), now);
      expect(await settleGrant(storage, now, () => true, { read: async () => ({ ok: true, subs: [paid("sub_c", anniversary(start, 2), anniversary(start, 3))].map(sub => ({ ...sub, started_at: start })), lifetime: null }), claim: async keys => Object.fromEntries(keys.map(key => [key, { self: true, since: start }])), fruits: true })).toBe("settled");
      const fruitLines = ledgerLines(storage, "fruit:grant:", 8);
      expect(fruitLines.every(line => (line.detail.due as number) >= now - 31 * DAY)).toBe(true);
    });
  });
  it("takes a refunded first month's Fruits and welcome basket back with its Pollen", async () => {
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      const start = DUE - HOUR, next = anniversary(start, 1);
      expect(await settleGrant(storage, DUE, () => true, { read: async () => ({ ok: true, subs: [paid("sub_r", start, next)], lifetime: null }), claim: self, fruits: true })).toBe("settled");
      expect(fruitBalance(storage)).toBe(20);
      // Refunded the day it was bought: the read at the next due date takes the month back.
      expect(await settleGrant(storage, next + HOUR, () => true, { read: async () => ({ ok: true, subs: [ended("sub_r", start, next, DUE + HOUR)], lifetime: null }), claim: self, fruits: true })).toBe("settled");
      expect([walletView(storage, next + HOUR).balance, fruitBalance(storage)]).toEqual([0, 0]);
      expect(ledgerLines(storage, "fruit:", 16).map(line => [line.key.replace(/:\d+:/, ":A:"), line.amount]).sort())
        .toEqual([["fruit:grant:A:1", 10], ["fruit:grantrefund:A:1", -10], ["fruit:welcome", 10], ["fruit:welcomerefund", -10]]);
    });
  });
});

// The routes through the Worker, with FRUITS on and off.
type Account = { player_id: string; device_token: string; recovery_code: string };
const BASE = { POLLEN_SECRET: SECRET };
const SHOP = { ...BASE, features: ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"] };
const FRUITS = { ...BASE, features: [...SHOP.features, "FRUITS"] };
let address = 0;
const shared = env as unknown as Record<string, unknown>;
beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, unknown> = FRUITS): Promise<Response> {
  return worker.fetch(new Request("https://fruits.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.95." + (++address % 250), [POLLEN_HEADER]: "1", ...POLLEN_CLIENT,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), withConfig(Object.assign({ ...env }, vars)) as Env);
}
async function create(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201);
  return made.json<Account>();
}
const player = (account: Account) => env.PLAYERS.getByName(account.player_id);
const inAccount = <T>(account: Account, work: (storage: DurableObjectStorage) => T) => runInDurableObject(player(account), async (_, state) => work(state.storage));
const spendBody = (kind: string, id: string, expected_cost: number, key: string = crypto.randomUUID()) => ({ schema_version: 1, idempotency_key: key, kind, id, expected_cost });
type Read = { balance: number; fruits?: Record<string, unknown> & { balance: number; achievements: unknown[] }; wardrobe?: Record<string, unknown> };

describe("the Fruit routes", () => {
  it("say nothing of Fruits while FRUITS is off: no capability, no wallet part, no Orchard price, Fruit spends refused", async () => {
    const account = await create();
    const caps = await (await call("/v2/capabilities", "GET", account, undefined, SHOP)).json<Record<string, unknown>>();
    expect(caps).not.toHaveProperty("pollen_fruits_version");
    const read = await (await call("/v1/pollen", "GET", account, undefined, SHOP)).json<Read>();
    expect(read).not.toHaveProperty("fruits");
    expect(read.wardrobe).not.toHaveProperty("fruit_prices");
    expect(read.wardrobe!.offered).not.toContain("apple_hood");
    for (const body of [spendBody("convert", "10", 10), spendBody("sunshine", "sunshine", 20)]) {
      const refused = await call("/v1/pollen/spend", "POST", account, body, SHOP);
      expect(refused.status).toBe(503);
    }
    expect((await call("/v1/pollen/spend", "POST", account, spendBody("item", "apple_hood", 100), SHOP)).status).toBe(409);
    expect(await inAccount(account, storage => storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='currency_purse'").toArray().length)).toBe(0);
  });
  it("read, sell the Orchard, convert and buy Sunshine while FRUITS is on, each once per key", async () => {
    const account = await create();
    const caps = await (await call("/v2/capabilities", "GET", account)).json<Record<string, unknown>>();
    expect(caps).toMatchObject({ pollen_fruits_version: 1, pollen_offered_tag: FRUITS_OFFERED_TAG });
    expect(caps).not.toHaveProperty("pollen_fruit_packs_version");
    const first = await (await call("/v1/pollen", "GET", account)).json<Read>();
    expect(first.fruits).toMatchObject({ balance: 0, sunshine: { left: 0, turns: 48, price: 20 }, convert: { pollen_per_fruit: 300, step: 10 }, first_pack_gift: true, first_pack_percent: 100 });
    expect(first.fruits!.achievements.length).toBe(15);
    expect(first.wardrobe).toMatchObject({ fruit_prices: { apple_hood: 100, sprig_sun: 20, orchard_skin: 200 }, fruit_sets: { orchard: ["apple_hood", "orchard_skin", "apple_leaf"] }, fruit_set_costs: { orchard: 295 } });
    expect((first.fruits as Record<string, unknown>).ladder).toEqual({ first: 10, step: 1, every: 1, top: 24, welcome: 10 });
    expect(Object.keys(first.wardrobe!.prices as object)).not.toContain("apple_hood");
    await inAccount(account, storage => { fund(storage, 200); });
    const cap = spendBody("item", "apple_hood", 100);
    const bought = await (await call("/v1/pollen/spend", "POST", account, cap)).json<Record<string, unknown>>();
    expect(bought).toMatchObject({ kind: "item", cost: 100, currency: "fruits", fruit_balance: 100, balance: 0 });
    expect(await (await call("/v1/pollen/spend", "POST", account, cap)).json()).toEqual(bought);
    expect((await call("/v1/pollen/spend", "POST", account, { ...cap, id: "sprig_sun", expected_cost: 10 })).status).toBe(409);
    const convert = await (await call("/v1/pollen/spend", "POST", account, spendBody("convert", "20", 20))).json<Record<string, unknown>>();
    expect(convert).toMatchObject({ kind: "convert", currency: "fruits", cost: 20, pollen: 6000, balance: 6000, fruit_balance: 80 });
    const sunshine = await (await call("/v1/pollen/spend", "POST", account, spendBody("sunshine", "sunshine", 20))).json<Record<string, unknown>>();
    expect(sunshine).toMatchObject({ kind: "sunshine", cost: 20, fruit_balance: 60, sunshine_left: 48 });
    const short = await call("/v1/pollen/spend", "POST", account, spendBody("item", "orchard_skin", 200));
    expect([short.status, (await short.json<{ error: { code: string } }>()).error.code]).toEqual([402, "fruits_short"]);
    const history = await (await call("/v1/pollen/history", "GET", account)).json<{ entries: { kind: string }[]; fruit_entries: { kind: string; amount: number }[] }>();
    expect(history.entries.map(entry => entry.kind)).toEqual(["convert"]);
    expect(history.fruit_entries.map(entry => [entry.kind, entry.amount])).toEqual(expect.arrayContaining([["convert", -20], ["bundle", 200]]));
  });
  it("measure the rows each Fruit action writes", async () => {
    const account = await create();
    await call("/v1/pollen", "GET", account);
    await inAccount(account, storage => { fund(storage, 100); });
    // A first purchase makes the wardrobe tables, as any first Pollen purchase does; measured after it.
    await call("/v1/pollen/spend", "POST", account, spendBody("item", "sprig_coral", 20));
    const stubs = { player: player(account) };
    const read = await meterRows(stubs, () => call("/v1/pollen", "GET", account));
    const item = await meterRows(stubs, () => call("/v1/pollen/spend", "POST", account, spendBody("item", "sprig_sky", 20)));
    const convert = await meterRows(stubs, () => call("/v1/pollen/spend", "POST", account, spendBody("convert", "10", 10)));
    const sunshine = await meterRows(stubs, () => call("/v1/pollen/spend", "POST", account, spendBody("sunshine", "sunshine", 20)));
    const measured = { read: read.rows.player.written, item: item.rows.player.written, convert: convert.rows.player.written, sunshine: sunshine.rows.player.written };
    console.log("fruit rows written", JSON.stringify(measured));
    expect(measured.read).toBe(0);
    // The purse, the item and the receipt; the two ledger lines, the purse, the converted count, the wallet and the receipt; the purse twice and the receipt.
    expect(measured).toEqual({ read: 0, item: 3, convert: 6, sunshine: 3 });
  });
  it("measure a Sunshine turn: one row more than the same turn without it", async () => {
    const rowsOf = async (hooks: boolean) => {
      const stub = env.PLAYERS.getByName("fruits-meter-" + ++serial);
      await runInDurableObject(stub, async (_, state) => { fund(state.storage, 20); value(buySunshine(state.storage, 20)); value(await creditTurn(state.storage, { POLLEN_SECRET: SECRET }, OWNER, facts(), MONDAY, () => true)); });
      const metered = await meterRows({ stub }, () => runInDurableObject(stub, async (_, state) =>
        value(await creditTurn(state.storage, { POLLEN_SECRET: SECRET }, OWNER, facts({ stage_id: "second" }), MONDAY, () => true, RATES, undefined, hooks ? HOOKS : undefined))));
      return metered.rows.stub.written;
    };
    const plain = await rowsOf(false), sunny = await rowsOf(true);
    console.log("sunshine turn rows", plain, sunny);
    expect(sunny - plain).toBe(1);
  });
});
