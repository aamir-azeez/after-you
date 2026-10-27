import { RATES, type Rates } from "./rates";
import { CATALOG, sold, type Catalog } from "./catalog";
import { KEY_LABELS, derivedKey, hmac } from "./keys";
import type { BloomSlot } from "./blooms";
import type { ServerVars } from "../flags";

/**
 * Item blooms (POLLEN-RULES.md "Item blooms"): a free-chapter bank turn may also drop a shop item.
 * A second roll, independent of the lucky bloom (own key, own label), and like it a roll of the
 * player's weekly slot, never of the recording, so sending a turn again rolls nothing new:
 *
 *   HMAC-SHA256(item key, "item-bloom-v1|" + player_id + "|" + ISO week + "|" + level_id + "|" + stage_id + "|" + role)
 *
 * - Bytes 0..3 as a big-endian unsigned number, mod rates.item_blooms.modulus, is the roll. The
 *   first tier whose cumulative `below` is above it drops (rarest first); otherwise nothing does.
 * - Bytes 4..7 the same way pick the item: index (pick mod pool size) into that tier's sold
 *   catalogue items the player does not own, sorted by id. A drop is free, so an unlock that guards
 *   buying a Special does not guard a drop.
 * - The explicit rule for a tier with nothing left to drop: when the tier has no sold item at all
 *   (empty), or the player owns every one, the drop pays the tier's Pollen price instead.
 * - Earned-only items and reaction packs never drop (`sold` leaves them out; packs are not items).
 *
 * Pure apart from the key: no storage, no clock. Nothing here knows whether a turn may roll; the
 * credit decides that (a bank turn in a free chapter: earn.ts bloomEligible), and money never
 * changes the odds or the pick.
 */
export type ItemBloomRoll = { roll: number; pick: number; tier: string | null };
/** What a drop gave: an item, or its tier's price when nothing in the tier is left to drop. */
export type ItemBloom = { tier: string; roll: number } & ({ item_id: string } | { pollen: number });

// Every tier a roll can drop pays its catalogue price when nothing is left to drop, so each needs one.
for (const step of RATES.item_blooms.tiers) if (!((CATALOG.tier_prices[step.tier] ?? 0) > 0)) throw new Error("invalid_item_bloom_tier: " + step.tier);

const u32 = (bytes: Uint8Array, at: number) => ((bytes[at] << 24) >>> 0) + (bytes[at + 1] << 16) + (bytes[at + 2] << 8) + bytes[at + 3];

export function itemBloomMessage(slot: BloomSlot): string {
  return `${KEY_LABELS.itemBloom}|${slot.player_id}|${slot.week}|${slot.level_id}|${slot.stage_id}|${slot.role}`;
}

/** The roll and pick from an HMAC's first eight bytes. */
export function itemBloomFromBytes(bytes: Uint8Array, rates: Rates = RATES): ItemBloomRoll {
  const roll = u32(bytes, 0) % rates.item_blooms.modulus;
  return { roll, pick: u32(bytes, 4), tier: rates.item_blooms.tiers.find(step => roll < step.below)?.tier ?? null };
}

/** The slot's item roll, or null while POLLEN_SECRET is unset. */
export async function itemBloomRoll(env: ServerVars, slot: BloomSlot, rates: Rates = RATES): Promise<ItemBloomRoll | null> {
  const key = derivedKey(env, KEY_LABELS.itemBloom);
  if (key === null) return null;
  return itemBloomFromBytes(await hmac(await key, itemBloomMessage(slot)), rates);
}

/** Every item a drop of `tier` may give, owned or not: the tier's sold items, sorted by id. */
export function droppable(tier: string, catalog: Catalog = CATALOG): string[] {
  return Object.keys(catalog.items).filter(id => catalog.items[id].tier === tier && sold(id, catalog)).sort();
}

/** What a roll gives a player who owns `owned`, or null when it drops nothing. */
export function resolveItemBloom(roll: ItemBloomRoll, owned: ReadonlySet<string>, catalog: Catalog = CATALOG): ItemBloom | null {
  if (roll.tier === null) return null;
  const pool = droppable(roll.tier, catalog).filter(id => !owned.has(id));
  if (pool.length > 0) return { tier: roll.tier, roll: roll.roll, item_id: pool[roll.pick % pool.length] };
  return { tier: roll.tier, roll: roll.roll, pollen: catalog.tier_prices[roll.tier] ?? 0 };
}

/**
 * Given to the credit while item blooms are on, so the wallet never reaches into the wardrobe
 * itself: the wardrobe's own read and write (wardrobe.ts ownedItemIds, addDroppedItem), both run
 * inside the credit's transaction. The credit rolls (itemBloomRoll) beside the lucky bloom, before it.
 */
export type ItemDrops = {
  owned: (storage: DurableObjectStorage) => ReadonlySet<string>;
  give: (storage: DurableObjectStorage, itemId: string, now: number) => void;
  catalog?: Catalog;
};
