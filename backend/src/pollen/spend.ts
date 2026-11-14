import { fail, ok, type Outcome } from "../protocol";
import { CATALOG, itemCurrency, itemPrice, offeredPacks, setCurrency, setPieces, sold, type Catalog } from "./catalog";
import type { Currency } from "./currency";

/**
 * What a purchase costs (POLLEN-RULES.md "Prices"). Pure: integers only, no storage, no clock.
 *
 * - An item costs its tier's price, in its tier's currency (Pollen, or Fruits for the Orchard). Earned items, items
 *   not released and Orchard items while Fruits are off are never sold.
 * - A Special (an item with `unlock`) is sold only once its chapter is cleared.
 * - A set: its released pieces the player does not own yet. When at least `set_min_missing` are
 *   missing they cost `set_discount_percent` less, rounded down to its currency's `set_round_down`
 *   (Pollen 100, Fruits 5); one missing piece costs its own price. Owned pieces are never charged.
 * - A reaction pack costs `pack_price` Pollen, while it sells (catalog.ts offeredPacks: none of its faces sells alone).
 * - Nothing owned is sold again, so a purchase can never charge twice for one thing.
 * The spend kinds "convert", "sunshine" and "energy" are Fruit operations (fruit-ops.ts, energy.ts), not priced here.
 *
 * charge() then refuses a negative balance in the purchase's currency (it blocks every spend in it), a cost the
 * phone did not show (`expected`), and a balance that is short.
 */
export type SpendKind = "item" | "set" | "pack" | "convert" | "sunshine" | "energy";
export type SpendRequest = { kind: SpendKind; id: string };
/** `pieces`: what the purchase adds; `full`: their prices added up; `cost`: what is charged, in `currency`. */
export type Quote = { kind: SpendKind; id: string; pieces: string[]; full: number; cost: number; currency: Currency };
/** What the player holds, as the quote needs it: owned item and pack ids, and whether a chapter (level_id) is cleared. */
export type Holdings = { owned: ReadonlySet<string>; cleared: (levelId: string) => boolean };

export function setCost(full: number, missing: number, catalog: Catalog = CATALOG, currency: Currency = "pollen"): number {
  if (missing < catalog.set_min_missing) return full;
  const round = catalog.set_round_down[currency];
  return Math.floor(full * (100 - catalog.set_discount_percent) / (100 * round)) * round;
}

/** `fruits`: Fruits are on, so Orchard items are sold. */
export function quote(request: SpendRequest, holdings: Holdings, catalog: Catalog = CATALOG, fruits = false): Outcome<Quote> {
  const locked = (id: string) => { const unlock = catalog.items[id]?.unlock ?? ""; return unlock !== "" && !holdings.cleared(unlock); };
  if (request.kind === "item") {
    if (!Object.hasOwn(catalog.items, request.id)) return fail(404, "unknown_item");
    if (!sold(request.id, catalog, fruits)) return fail(409, "not_for_sale");
    if (holdings.owned.has(request.id)) return fail(409, "already_owned");
    if (locked(request.id)) return fail(403, "pollen_locked");
    const price = itemPrice(request.id, catalog);
    return ok({ kind: "item", id: request.id, pieces: [request.id], full: price, cost: price, currency: itemCurrency(request.id, catalog) });
  }
  if (request.kind === "set") {
    const pieces = setPieces(request.id, catalog, fruits);
    if (!pieces.length) return fail(404, "unknown_item");
    const missing = pieces.filter(id => !holdings.owned.has(id));
    if (!missing.length) return fail(409, "already_owned");
    if (missing.some(locked)) return fail(403, "pollen_locked");
    const full = missing.reduce((sum, id) => sum + itemPrice(id, catalog), 0), currency = setCurrency(request.id, catalog);
    return ok({ kind: "set", id: request.id, pieces: missing, full, cost: setCost(full, missing.length, catalog, currency), currency });
  }
  if (request.kind !== "pack") return fail(400, "invalid_pollen_spend");
  const pack = catalog.packs[request.id];
  if (!pack || !Object.hasOwn(catalog.packs, request.id)) return fail(404, "unknown_item");
  if (!offeredPacks(catalog).includes(request.id)) return fail(409, "not_for_sale");
  // A pack whose every face is owned (bought alone) is owned too: it is never sold for nothing.
  if (holdings.owned.has(request.id) || pack.faces.every(face => holdings.owned.has(face))) return fail(409, "already_owned");
  return ok({ kind: "pack", id: request.id, pieces: [request.id], full: catalog.pack_price, cost: catalog.pack_price, currency: "pollen" });
}

/** The balance after paying `quote`, or the refusal. `balance` is in the quote's currency; `expected`: the cost the phone showed on its confirm sheet. */
export function charge(quoted: Quote, balance: number, expected: number): Outcome<number> {
  const fruits = quoted.currency === "fruits";
  if (balance < 0) return fail(403, fruits ? "fruits_blocked" : "pollen_blocked");
  if (expected !== quoted.cost) return fail(409, "pollen_price_changed");
  if (balance < quoted.cost) return fail(402, fruits ? "fruits_short" : "pollen_short");
  return ok(balance - quoted.cost);
}
