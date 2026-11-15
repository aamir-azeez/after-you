import { CATALOG, isRetired, itemCurrency, itemPrice, type Catalog } from "./catalog";
import { keyIn } from "./currency";
import { applyLedger, type LedgerEntry } from "./wallet";
import { ownedAmong } from "./wardrobe";

/**
 * Retired items (catalog.json `retired`: the faces taken out of the game, 2026-11-14) are paid back once.
 *
 * A player who owns a retired item, bought alone or in a reaction pack that holds it, is paid its price
 * (catalog tier) back in its own currency, once (a payback, so not counted as earned): the ledger line's key (`retired:<id>`, a Fruit item's
 * under the Fruit prefix) makes a second read change nothing (wallet.ts applyLedger). The item stays owned,
 * so an older app that still has it in a reaction slot keeps sending it and no turn is refused; the app
 * from this build never lists, picks or draws it. Runs on the wallet read, inside one transaction: a player
 * who owns none pays one keyed read and writes nothing.
 */
export const RETIRED_KIND = "retired_refund";
export const RETIRED_PREFIX = "retired:";

/** The ledger lines a player owning `owned` (item and pack ids) is due: one per retired item they hold. */
export function retiredRefunds(owned: readonly string[], catalog: Catalog = CATALOG): LedgerEntry[] {
  const held = new Set(owned);
  return (catalog.retired ?? []).filter(id => isRetired(id, catalog) && (held.has(id) || Object.keys(catalog.packs).some(pack => held.has(pack) && catalog.packs[pack].faces.includes(id))))
    .map(id => ({ key: keyIn(itemCurrency(id, catalog), RETIRED_PREFIX + id), kind: RETIRED_KIND, amount: itemPrice(id, catalog), detail: { item: id }, earns: false as const }))
    .filter(entry => entry.amount > 0);
}

/** Pays each retired item the player owns back once, inside the caller's transaction; the lines it paid now. */
export function refundRetired(storage: DurableObjectStorage, now: number, catalog: Catalog = CATALOG): LedgerEntry[] {
  const retired = catalog.retired ?? [];
  if (!retired.length) return [];
  const packs = Object.keys(catalog.packs).filter(pack => catalog.packs[pack].faces.some(face => retired.includes(face)));
  const owned = ownedAmong(storage, [...retired, ...packs]);
  return owned.length ? applyLedger(storage, retiredRefunds(owned, catalog), now) : [];
}
