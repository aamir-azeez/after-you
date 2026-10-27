import { fail, ok, type Outcome } from "../protocol";
import { CATALOG, itemPrice, setPieces, sold, type Catalog } from "./catalog";

/**
 * What a purchase costs (POLLEN-RULES.md "Prices"). Pure: integers only, no storage, no clock.
 *
 * - An item costs its tier's price. Earned items and items not released are never sold.
 * - A Special (an item with `unlock`) is sold only once its chapter is cleared.
 * - A set: its released pieces the player does not own yet. When at least `set_min_missing` are
 *   missing they cost `set_discount_percent` less, rounded down to `set_round_down`; one missing
 *   piece costs its own price. Owned pieces are never charged.
 * - A reaction pack costs `pack_price`.
 * - Nothing owned is sold again, so a purchase can never charge twice for one thing.
 *
 * charge() then refuses a negative balance (it blocks every spend), a cost the phone did not
 * show (`expected`), and a balance that is short.
 */
export type SpendKind = "item" | "set" | "pack";
export type SpendRequest = { kind: SpendKind; id: string };
/** `pieces`: what the purchase adds; `full`: their prices added up; `cost`: what is charged. */
export type Quote = { kind: SpendKind; id: string; pieces: string[]; full: number; cost: number };
/** What the player holds, as the quote needs it: owned item and pack ids, and whether a chapter (level_id) is cleared. */
export type Holdings = { owned: ReadonlySet<string>; cleared: (levelId: string) => boolean };

export function setCost(full: number, missing: number, catalog: Catalog = CATALOG): number {
  if (missing < catalog.set_min_missing) return full;
  return Math.floor(full * (100 - catalog.set_discount_percent) / (100 * catalog.set_round_down)) * catalog.set_round_down;
}

export function quote(request: SpendRequest, holdings: Holdings, catalog: Catalog = CATALOG): Outcome<Quote> {
  const locked = (id: string) => { const unlock = catalog.items[id]?.unlock ?? ""; return unlock !== "" && !holdings.cleared(unlock); };
  if (request.kind === "item") {
    if (!Object.hasOwn(catalog.items, request.id)) return fail(404, "unknown_item");
    if (!sold(request.id, catalog)) return fail(409, "not_for_sale");
    if (holdings.owned.has(request.id)) return fail(409, "already_owned");
    if (locked(request.id)) return fail(403, "pollen_locked");
    const price = itemPrice(request.id, catalog);
    return ok({ kind: "item", id: request.id, pieces: [request.id], full: price, cost: price });
  }
  if (request.kind === "set") {
    const pieces = setPieces(request.id, catalog);
    if (!pieces.length) return fail(404, "unknown_item");
    const missing = pieces.filter(id => !holdings.owned.has(id));
    if (!missing.length) return fail(409, "already_owned");
    if (missing.some(locked)) return fail(403, "pollen_locked");
    const full = missing.reduce((sum, id) => sum + itemPrice(id, catalog), 0);
    return ok({ kind: "set", id: request.id, pieces: missing, full, cost: setCost(full, missing.length, catalog) });
  }
  const pack = catalog.packs[request.id];
  if (!pack || !Object.hasOwn(catalog.packs, request.id)) return fail(404, "unknown_item");
  if (!pack.released) return fail(409, "not_for_sale");
  if (holdings.owned.has(request.id)) return fail(409, "already_owned");
  return ok({ kind: "pack", id: request.id, pieces: [request.id], full: catalog.pack_price, cost: catalog.pack_price });
}

/** The balance after paying `quote`, or the refusal. `expected`: the cost the phone showed on its confirm sheet. */
export function charge(quoted: Quote, balance: number, expected: number): Outcome<number> {
  if (balance < 0) return fail(403, "pollen_blocked");
  if (expected !== quoted.cost) return fail(409, "pollen_price_changed");
  if (balance < quoted.cost) return fail(402, "pollen_short");
  return ok(balance - quoted.cost);
}
