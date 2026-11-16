import { fail, ok, type Outcome } from "../protocol";
import { FRUIT_PREFIX, purse } from "./currency";
import { applyLedger, inLedger, ledgerLines } from "./wallet";

/**
 * Levels a free player opens once with Fruits (the owner, 2026-11-16: Fog Marsh costs 3 Fruits because it opens Space;
 * Full Journey players get it free), in the player's own Player Durable Object.
 *
 * - LEVEL_PRICES is the server's price per level id. The game's descriptor names the same price (`unlock: {fruits}`,
 *   game/content/chapters/index.gd) and the chapter manifest carries it (`unlock_fruits`); backend/test/level-unlocks.test.ts
 *   pins every manifest row to this table, so the price a card shows is the price charged.
 * - Paying writes one kept Fruit ledger line, `fruit:level:<level id>` (kind "fruitlevel", never pruned: wallet.ts prune
 *   leaves every kind but turns and their kin), through the shared ledger, so the Fruit balance, history and refund
 *   rules are the ones every Fruit spend has. That line is the unlock: it never goes, so a level once paid stays open.
 * - The spend route's kind "level" (wardrobe.ts fruitSpend) runs it with the spend's receipt, so the same idempotency key
 *   answers the same receipt, and a level already paid is refused `already_owned` under any key (never a second charge).
 * - Full Journey opens every priced level while it lasts, without a line: its spend is refused `level_free`.
 * Every function runs inside the caller's transaction; none awaits.
 */
export const LEVEL_PRICES: Readonly<Record<string, number>> = Object.freeze({ "fog-marsh": 3 });
export const LEVEL_UNLOCK_PREFIX = `${FRUIT_PREFIX}level:`;
export const LEVEL_ID_PATTERN = /^[a-z0-9-]{1,64}$/;
export const levelUnlockKey = (levelId: string) => LEVEL_UNLOCK_PREFIX + levelId;

/** The wallet read's `levels` (inside `fruits`): every priced level and the ones this player has paid for, in id order. */
export type LevelsView = { prices: Record<string, number>; open: string[] };

/** The level ids this player has paid for: one read of the unlock key range. */
export function paidLevels(storage: DurableObjectStorage): string[] {
  return ledgerLines(storage, LEVEL_UNLOCK_PREFIX, 64).map(line => line.key.slice(LEVEL_UNLOCK_PREFIX.length)).sort();
}

export function levelsView(storage: DurableObjectStorage, prices: Readonly<Record<string, number>> = LEVEL_PRICES): LevelsView {
  return { prices: { ...prices }, open: paidLevels(storage) };
}

/**
 * Opens `levelId` for its price in Fruits. `expected`: the price the phone's card showed. `fullJourney`: the player has
 * Full Journey now (Player.roomFullJourneyUntil, so a tester's switch counts), and every priced level is already open.
 */
export function unlockLevel(storage: DurableObjectStorage, levelId: string, expected: number, now: number, fullJourney: boolean,
  prices: Readonly<Record<string, number>> = LEVEL_PRICES): Outcome<{ fruit_balance: number; cost: number }> {
  if (!LEVEL_ID_PATTERN.test(levelId) || !Object.hasOwn(prices, levelId)) return fail(404, "unknown_item");
  if (inLedger(storage, levelUnlockKey(levelId))) return fail(409, "already_owned");
  if (fullJourney) return fail(409, "level_free");
  const price = prices[levelId], fruits = purse(storage, "fruits").balance;
  if (fruits < 0) return fail(403, "fruits_blocked");
  if (expected !== price) return fail(409, "pollen_price_changed");
  if (fruits < price) return fail(402, "fruits_short");
  const applied = applyLedger(storage, [{ key: levelUnlockKey(levelId), kind: "fruitlevel", amount: -price, detail: { level_id: levelId } }], now);
  if (applied.length !== 1) throw new Error("level_unlock_partial");
  return ok({ fruit_balance: purse(storage, "fruits").balance, cost: price });
}
