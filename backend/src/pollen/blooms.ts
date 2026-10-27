import { RATES, type Rates } from "./rates";
import { KEY_LABELS, derivedKey, hmac } from "./keys";
import type { ServerVars } from "../flags";

/**
 * Lucky blooms (POLLEN-RULES.md): a free-chapter bank turn may pay x2 or x3. The roll belongs to the
 * player's weekly slot, not to the recording, so sending an old recording again rolls nothing new:
 *
 *   HMAC-SHA256(bloom key, "pollen-bloom-v1|" + player_id + "|" + ISO week + "|" + level_id + "|" + stage_id + "|" + role)
 *
 * Bytes 0..3 as a big-endian unsigned number, mod rates.blooms.modulus, is the roll: below
 * triple_below is x3, below double_below x2. The key is HKDF("pollen-bloom-v1") of POLLEN_SECRET
 * (keys.ts). The roll is stored with the credit, so it can be checked later.
 *
 * Item blooms (item-blooms.ts) are a second, independent roll with their own label (KEY_LABELS.itemBloom)
 * and their own message prefix "item-bloom-v1|"; they belong beside this one, inside the same credit.
 */
export type BloomMultiplier = 1 | 2 | 3;
export type BloomRoll = { roll: number; multiplier: BloomMultiplier };
export type BloomSlot = { player_id: string; week: string; level_id: string; stage_id: string; role: "a" | "b" };

export function bloomMessage(slot: BloomSlot): string {
  return `${KEY_LABELS.bloom}|${slot.player_id}|${slot.week}|${slot.level_id}|${slot.stage_id}|${slot.role}`;
}

/** The roll from an HMAC's first four bytes. */
export function bloomFromBytes(bytes: Uint8Array, rates: Rates = RATES): BloomRoll {
  const roll = (((bytes[0] << 24) >>> 0) + (bytes[1] << 16) + (bytes[2] << 8) + bytes[3]) % rates.blooms.modulus;
  return { roll, multiplier: roll < rates.blooms.triple_below ? 3 : roll < rates.blooms.double_below ? 2 : 1 };
}

/** The slot's roll, or null while POLLEN_SECRET is unset: a turn is never credited without its roll. */
export async function bloomRoll(env: ServerVars, slot: BloomSlot, rates: Rates = RATES): Promise<BloomRoll | null> {
  const key = derivedKey(env, KEY_LABELS.bloom);
  if (key === null) return null;
  return bloomFromBytes(await hmac(await key, bloomMessage(slot)), rates);
}
