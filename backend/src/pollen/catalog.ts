import { isObject } from "../protocol";
import raw from "./catalog.json";
import { PACK_FACES } from "../v2/end-reactions";

/**
 * The wardrobe catalogue the server sells from (POLLEN-RULES.md "Prices"), as data: catalog.json
 * holds every item, this file checks it once at module load. A tier sets an item's price; no item
 * stores its own. `released` here, not the game's own copy, decides what can be bought, so the
 * owner offers an item by changing this file and turning POLLEN_SHOP on.
 * test/spend.test.ts pins every item's facts except `released` to the game's
 * game/tests/fixtures/golden/cosmetic_manifest.json.
 *
 * - items: the pip cosmetics, keyed by id; each worn in one slot. An "earned" tier is never sold.
 * - sets: an item's `set` names the set it belongs to; buying a set's missing pieces together
 *   costs less (spend.ts). No item has a set yet.
 * - packs: reaction packs at `pack_price`, each listing its faces. Every pack face of the end reactions
 *   (v2/end-reactions.ts PACK_FACES) belongs to exactly one pack, and a pack holds nothing else, so the
 *   face a turn may carry and the pack that owns it can never drift apart.
 */
export type CatalogItem = { slot: string; tier: string; unlock: string; set: string; released: boolean };
export type CatalogPack = { released: boolean; faces: readonly string[] };
export type Catalog = {
  schema_version: 1; slots: readonly string[]; tier_prices: Readonly<Record<string, number>>;
  set_discount_percent: number; set_round_down: number; set_min_missing: number; pack_price: number;
  items: Readonly<Record<string, CatalogItem>>; packs: Readonly<Record<string, CatalogPack>>;
};
/** What a pip wears: one item id per filled slot. {} is the default look. */
export type Look = Readonly<Record<string, string>>;

export const EARNED_TIER = "earned";
export const ITEM_ID_PATTERN = /^[a-z0-9_]{1,40}$/;
const LEVEL_PATTERN = /^[a-z0-9-]{1,64}$/;
const count = (value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
const exact = (value: Record<string, unknown>, keys: string[]) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));

/** Throws on any entry outside the shapes above, so a bad edit fails every test and every deploy check. */
export function checkedCatalog(value: unknown): Catalog {
  const bad = (what: string): never => { throw new Error(`invalid_pollen_catalog: ${what}`); };
  if (!isObject(value) || value.schema_version !== 1) bad("schema_version");
  const v = value as Record<string, unknown>;
  if (!exact(v, ["schema_version", "slots", "tier_prices", "set_discount_percent", "set_round_down", "set_min_missing", "pack_price", "items", "packs"])) bad("fields");
  if (!Array.isArray(v.slots) || !v.slots.length || !v.slots.every(slot => typeof slot === "string" && ITEM_ID_PATTERN.test(slot)) || new Set(v.slots).size !== v.slots.length) bad("slots");
  if (!isObject(v.tier_prices) || !Object.values(v.tier_prices).every(price => count(price)) || v.tier_prices[EARNED_TIER] !== 0) bad("tier_prices");
  if (!count(v.set_discount_percent, 0, 99) || !count(v.set_round_down, 1) || !count(v.set_min_missing, 2) || !count(v.pack_price, 1)) bad("set or pack rules");
  if (!isObject(v.items) || !isObject(v.packs)) bad("items");
  const slots = v.slots as string[], prices = v.tier_prices as Record<string, number>;
  for (const [id, item] of Object.entries(v.items as Record<string, unknown>)) {
    if (!ITEM_ID_PATTERN.test(id) || !isObject(item) || !exact(item, ["slot", "tier", "unlock", "set", "released"])) bad(id);
    const entry = item as Record<string, unknown>;
    if (!slots.includes(entry.slot as string) || typeof entry.tier !== "string" || !Object.hasOwn(prices, entry.tier) || typeof entry.released !== "boolean") bad(id);
    if (entry.unlock !== "" && !(typeof entry.unlock === "string" && LEVEL_PATTERN.test(entry.unlock))) bad(id);
    if (entry.set !== "" && !(typeof entry.set === "string" && ITEM_ID_PATTERN.test(entry.set))) bad(id);
    // An earned item is never sold, so it never sits in a set or behind an unlock.
    if (entry.tier === EARNED_TIER && (entry.set !== "" || entry.unlock !== "")) bad(id);
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

/** An item's price in Pollen, from its tier; 0 for an earned or unknown item. */
export function itemPrice(id: string, catalog: Catalog = CATALOG): number {
  const item = catalog.items[id];
  return item ? catalog.tier_prices[item.tier] ?? 0 : 0;
}
/** Whether the item can be bought now: known, released and not earned only. */
export function sold(id: string, catalog: Catalog = CATALOG): boolean {
  const item = catalog.items[id];
  return !!item && item.released && item.tier !== EARNED_TIER && itemPrice(id, catalog) > 0;
}
/** The released, sold pieces of a set, in catalogue order. */
export function setPieces(setId: string, catalog: Catalog = CATALOG): string[] {
  return Object.keys(catalog.items).filter(id => catalog.items[id].set === setId && sold(id, catalog));
}
/** Every set with at least one released piece, in catalogue order of first piece. */
export function offeredSets(catalog: Catalog = CATALOG): string[] {
  return [...new Set(Object.keys(catalog.items).filter(id => sold(id, catalog)).map(id => catalog.items[id].set).filter(Boolean))];
}
/** Released items (sold or earned) and released packs: what a phone may show and draw. */
export function offeredItems(catalog: Catalog = CATALOG): string[] {
  return Object.keys(catalog.items).filter(id => catalog.items[id].released);
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
