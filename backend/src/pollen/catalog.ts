import { isObject } from "../protocol";
import raw from "./catalog.json";
import { PACK_FACES } from "../v2/end-reactions";
import { CURRENCIES, type Currency } from "./currency";
import { COSMETIC_CODE_MAX, serverConfig, type ServerConfig } from "../config";
import type { ServerVars } from "../flags";

/**
 * The wardrobe catalogue the server sells from (POLLEN-RULES.md "Prices"), as data: catalog.json
 * holds every item, this file checks it once at module load. A tier sets an item's price; no item
 * stores its own. The server, not the game's own copy, decides what is released and so what can be bought:
 * an item is released when this file says `released: true` (every item built before the release list) or when
 * CONFIG's `cosmetics_released` lists its code (catalogFor below), so the owner releases an item built into the
 * app with a one-line CONFIG edit. test/spend.test.ts pins every item's facts except `released` to the game's
 * game/tests/fixtures/golden/cosmetic_manifest.json, and every code to game/tests/fixtures/cosmetic_codes.json.
 *
 * - items: the pip cosmetics, keyed by id; each worn in one slot. An "earned" tier is never sold.
 * - code: the item's permanent number (1 to COSMETIC_CODE_MAX, one per item). It never changes and is never
 *   given to another item, even once an item is retired; CONFIG names items by it.
 * - tier_currency: the tiers priced in Fruits (the Orchard: sprig, fruit_small, fruit_hat, fruit_body); every other
 *   tier is Pollen. An Orchard item is sold, offered and drawn only while Fruits are on (the `fruits` argument below),
 *   and never drops from an item bloom (item-blooms.ts takes Pollen tiers only).
 * - sets: an item's `set` names the set it belongs to; buying a set's missing pieces together
 *   costs less (spend.ts), rounded down to its currency's `set_round_down`. A set's pieces share one currency.
 * - packs: reaction packs at `pack_price`, each listing its faces. Every pack face of the end reactions
 *   (v2/end-reactions.ts PACK_FACES) belongs to exactly one pack, and a pack holds nothing else, so the
 *   face a turn may carry and the pack that owns it can never drift apart.
 */
export type CatalogItem = { code: number; slot: string; tier: string; unlock: string; set: string; released: boolean };
export type CatalogPack = { released: boolean; faces: readonly string[] };
export type Catalog = {
  schema_version: 1; slots: readonly string[]; tier_prices: Readonly<Record<string, number>>; tier_currency: Readonly<Record<string, "fruits">>;
  set_discount_percent: number; set_round_down: Readonly<Record<Currency, number>>; set_min_missing: number; pack_price: number;
  items: Readonly<Record<string, CatalogItem>>; packs: Readonly<Record<string, CatalogPack>>;
};
/** What a pip wears: one item id per filled slot. {} is the default look. */
export type Look = Readonly<Record<string, string>>;

export const EARNED_TIER = "earned";
export const ITEM_ID_PATTERN = /^[a-z0-9_]{1,40}$/;
const LEVEL_PATTERN = /^[a-z0-9-]{1,64}$/;
const count = (value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
const exact = (value: Record<string, unknown>, keys: readonly string[]) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

/** Throws on any entry outside the shapes above, so a bad edit fails every test and every deploy check. */
export function checkedCatalog(value: unknown): Catalog {
  const bad = (what: string): never => { throw new Error(`invalid_pollen_catalog: ${what}`); };
  if (!isObject(value) || value.schema_version !== 1) bad("schema_version");
  const v = value as Record<string, unknown>;
  if (!exact(v, ["schema_version", "slots", "tier_prices", "tier_currency", "set_discount_percent", "set_round_down", "set_min_missing", "pack_price", "items", "packs"])) bad("fields");
  if (!Array.isArray(v.slots) || !v.slots.length || !v.slots.every(slot => typeof slot === "string" && ITEM_ID_PATTERN.test(slot)) || new Set(v.slots).size !== v.slots.length) bad("slots");
  if (!isObject(v.tier_prices) || !Object.values(v.tier_prices).every(price => count(price)) || v.tier_prices[EARNED_TIER] !== 0) bad("tier_prices");
  if (!isObject(v.tier_currency) || !Object.entries(v.tier_currency).every(([tier, currency]) => currency === "fruits" && tier !== EARNED_TIER && Object.hasOwn(v.tier_prices as object, tier))) bad("tier_currency");
  const rounding = v.set_round_down as Record<string, unknown>;
  if (!count(v.set_discount_percent, 0, 99) || !isObject(rounding) || !exact(rounding, CURRENCIES) || !CURRENCIES.every(currency => count(rounding[currency], 1)) || !count(v.set_min_missing, 2) || !count(v.pack_price, 1)) bad("set or pack rules");
  if (!isObject(v.items) || !isObject(v.packs)) bad("items");
  const slots = v.slots as string[], prices = v.tier_prices as Record<string, number>, currencies = v.tier_currency as Record<string, string>;
  const setCurrency = new Map<string, string>(), codes = new Set<number>();
  for (const [id, item] of Object.entries(v.items as Record<string, unknown>)) {
    if (!ITEM_ID_PATTERN.test(id) || !isObject(item) || !exact(item, ["code", "slot", "tier", "unlock", "set", "released"])) bad(id);
    const entry = item as Record<string, unknown>;
    if (!count(entry.code, 1, COSMETIC_CODE_MAX) || codes.has(entry.code)) bad(`${id} code`);
    codes.add(entry.code as number);
    if (!slots.includes(entry.slot as string) || typeof entry.tier !== "string" || !Object.hasOwn(prices, entry.tier) || typeof entry.released !== "boolean") bad(id);
    if (entry.unlock !== "" && !(typeof entry.unlock === "string" && LEVEL_PATTERN.test(entry.unlock))) bad(id);
    if (entry.set !== "" && !(typeof entry.set === "string" && ITEM_ID_PATTERN.test(entry.set))) bad(id);
    // An earned item is never sold, so it never sits in a set or behind an unlock.
    if (entry.tier === EARNED_TIER && (entry.set !== "" || entry.unlock !== "")) bad(id);
    // A set is bought in one currency.
    const currency = currencies[entry.tier as string] ?? "pollen";
    if (entry.set !== "") { if ((setCurrency.get(entry.set as string) ?? currency) !== currency) bad(`${entry.set} mixes currencies`); setCurrency.set(entry.set as string, currency); }
  }
  const packed = new Set<string>();
  for (const [id, pack] of Object.entries(v.packs as Record<string, unknown>)) {
    if (!ITEM_ID_PATTERN.test(id) || Object.hasOwn(v.items as object, id) || !isObject(pack) || !exact(pack, ["released", "faces"]) || typeof pack.released !== "boolean") bad(id);
    const faces = (pack as Record<string, unknown>).faces;
    if (!Array.isArray(faces) || !faces.length) bad(id);
    for (const face of faces as unknown[]) {
      if (typeof face !== "string" || !(PACK_FACES as readonly string[]).includes(face) || packed.has(face)) bad(id);
      packed.add(face as string);
    }
  }
  if (packed.size !== PACK_FACES.length) bad("pack faces");
  return deepFreeze(v) as Catalog;
}

function deepFreeze<T>(value: T): T {
  if (isObject(value) || Array.isArray(value)) { for (const child of Object.values(value as object)) deepFreeze(child); Object.freeze(value); }
  return value;
}

export const CATALOG: Catalog = checkedCatalog(raw);

/** The currency a tier is priced in. */
export function tierCurrency(tier: string, catalog: Catalog = CATALOG): Currency { return catalog.tier_currency[tier] ?? "pollen"; }
/** The currency an item is sold in (Pollen for an unknown one). */
export function itemCurrency(id: string, catalog: Catalog = CATALOG): Currency {
  const item = catalog.items[id];
  return item ? tierCurrency(item.tier, catalog) : "pollen";
}
/** An item's price in its currency, from its tier; 0 for an earned or unknown item. */
export function itemPrice(id: string, catalog: Catalog = CATALOG): number {
  const item = catalog.items[id];
  return item ? catalog.tier_prices[item.tier] ?? 0 : 0;
}
/** Whether an item may be shown and drawn now: released, and a Fruit item only while Fruits are on. */
function shown(id: string, catalog: Catalog, fruits: boolean): boolean {
  const item = catalog.items[id];
  return !!item && item.released && (fruits || itemCurrency(id, catalog) === "pollen");
}
/** Whether the item can be bought now: shown and not earned only. `fruits`: Fruits are on (features.ts fruitsOn). */
export function sold(id: string, catalog: Catalog = CATALOG, fruits = false): boolean {
  return shown(id, catalog, fruits) && catalog.items[id].tier !== EARNED_TIER && itemPrice(id, catalog) > 0;
}
/** The released, sold pieces of a set, in catalogue order. */
export function setPieces(setId: string, catalog: Catalog = CATALOG, fruits = false): string[] {
  return Object.keys(catalog.items).filter(id => catalog.items[id].set === setId && sold(id, catalog, fruits));
}
/** The currency a set is bought in (its pieces share one). */
export function setCurrency(setId: string, catalog: Catalog = CATALOG): Currency {
  const piece = Object.keys(catalog.items).find(id => catalog.items[id].set === setId);
  return piece ? itemCurrency(piece, catalog) : "pollen";
}
/** Every set with at least one sold piece, in catalogue order of first piece. */
export function offeredSets(catalog: Catalog = CATALOG, fruits = false): string[] {
  return [...new Set(Object.keys(catalog.items).filter(id => sold(id, catalog, fruits)).map(id => catalog.items[id].set).filter(Boolean))];
}
/** Released items (sold or earned) a phone may show and draw: an Orchard item only while Fruits are on. */
export function offeredItems(catalog: Catalog = CATALOG, fruits = false): string[] {
  return Object.keys(catalog.items).filter(id => shown(id, catalog, fruits));
}
/**
 * A short tag of offeredItems() (FNV-1a, 8 hex), sent beside the wardrobe's capability (routes.ts pollenCapability).
 * A phone keeps the `offered` of its last wallet read and draws nothing else on any pip, so it reads the wallet
 * again once this tag differs from the one its kept read came with: releasing an item reaches every phone on its
 * next launch, without a wallet read on each launch. Turning Fruits on or off changes it too.
 */
export function offeredTag(catalog: Catalog = CATALOG, fruits = false): string {
  let hash = 0x811c9dc5;
  for (const char of offeredItems(catalog, fruits).join(",")) hash = Math.imul(hash ^ char.charCodeAt(0), 0x01000193) >>> 0;
  return hash.toString(16).padStart(8, "0");
}
export const OFFERED_TAG = offeredTag();
/** The tag while Fruits are on. */
export const FRUITS_OFFERED_TAG = offeredTag(CATALOG, true);

/**
 * The catalogue as released now: `base` with every item whose code CONFIG's `cosmetics_released` lists marked released.
 * Codes `base` lacks are ignored (the deploy runners refuse them). With nothing new released the answer is `base`
 * itself, so prices, offers and the offered tag stay exactly as built. Pure; the Worker and the Player each work it out
 * from their own env (catalogFor), never passing it between them.
 */
export function releasedCatalog(released: ReadonlySet<number>, base: Catalog = CATALOG): Catalog {
  const ids = Object.keys(base.items).filter(id => !base.items[id].released && released.has(base.items[id].code));
  if (!ids.length) return base;
  const items = { ...base.items };
  for (const id of ids) items[id] = Object.freeze({ ...items[id], released: true });
  return Object.freeze({ ...base, items: Object.freeze(items) });
}
/** One answer per parsed CONFIG (config.ts parses CONFIG once per isolate and value), so a request does no work twice. */
type Released = { catalog: Catalog; tags: [string, string]; featured: number | undefined };
const released = new WeakMap<ServerConfig, Released>();
function releasedFor(env: ServerVars): Released {
  const config = serverConfig(env);
  let found = released.get(config);
  if (!found) {
    const catalog = releasedCatalog(config.cosmetics_released), featured = featuredItem(env, catalog);
    found = { catalog, tags: catalog === CATALOG ? [OFFERED_TAG, FRUITS_OFFERED_TAG] : [offeredTag(catalog), offeredTag(catalog, true)],
      featured: featured === undefined ? undefined : catalog.items[featured].code };
    released.set(config, found);
  }
  return found;
}
/** The catalogue this request sells, offers and drops from: catalog.json with CONFIG's released codes. */
export function catalogFor(env: ServerVars): Catalog { return releasedFor(env).catalog; }
/** offeredTag of catalogFor(env), worked out once per CONFIG. */
export function offeredTagFor(env: ServerVars, fruits: boolean): string { return releasedFor(env).tags[fruits ? 1 : 0]; }
/** The code of featuredItem(env), worked out once per CONFIG, or undefined. */
export function featuredCodeFor(env: ServerVars): number | undefined { return releasedFor(env).featured; }
/** The item with this code, or undefined. */
export function itemOfCode(code: number, catalog: Catalog = CATALOG): string | undefined {
  return Object.keys(catalog.items).find(id => catalog.items[id].code === code);
}
/**
 * The id of the item CONFIG's `cosmetics_featured` names, for the shop's featured place, or undefined when it names
 * none, an unknown code, or an item that is not released or not sold for Pollen now (the shelf of the week is Pollen
 * only). The phone then shows its built-in pick (game/services/featured_shelf.gd).
 */
export function featuredItem(env: ServerVars, catalog: Catalog = catalogFor(env)): string | undefined {
  const code = serverConfig(env).cosmetics_featured;
  const id = code === null ? undefined : itemOfCode(code, catalog);
  return id !== undefined && sold(id, catalog) && itemCurrency(id, catalog) === "pollen" ? id : undefined;
}
export function offeredPacks(catalog: Catalog = CATALOG): string[] {
  return Object.keys(catalog.packs).filter(id => catalog.packs[id].released);
}
/** The pack a face belongs to, or undefined for an everyday face (one of BASE_FACES). */
export function packOfFace(face: string, catalog: Catalog = CATALOG): string | undefined {
  return Object.keys(catalog.packs).find(id => catalog.packs[id].faces.includes(face));
}

/**
 * A look as stored and served: an object of slot -> item id, each a catalogue item worn in that
 * slot. Ownership is the Player's check (wardrobe.ts); this is shape only, so a room can check
 * what reaches it without a catalogue of anyone's items.
 */
export function validLook(value: unknown, catalog: Catalog = CATALOG): value is Look {
  if (!isObject(value) || Object.keys(value).length > catalog.slots.length) return false;
  return Object.entries(value).every(([slot, id]) => catalog.slots.includes(slot) && typeof id === "string" && catalog.items[id]?.slot === slot);
}
/** A look in slot order, so equal looks are equal strings. */
export function lookText(look: Look, catalog: Catalog = CATALOG): string {
  return JSON.stringify(Object.fromEntries(catalog.slots.filter(slot => Object.hasOwn(look, slot)).map(slot => [slot, look[slot]])));
}
export const isDefaultLook = (look: Look): boolean => Object.keys(look).length === 0;
