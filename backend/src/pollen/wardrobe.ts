import { HASH_PATTERN, IDEMPOTENCY_PATTERN, equalHash, fail, isObject, ok, type Outcome } from "../protocol";
import { POLLEN_SHOP_TABLES, isLazyTable } from "../storage-schema";
import { CATALOG, isDefaultLook, itemPrice, offeredItems, offeredPacks, offeredSets, setPieces, sold, validLook, type Catalog, type Look } from "./catalog";
import { charge, quote, type SpendRequest } from "./spend";
import { chapterCleared, payFromWallet, walletBalance } from "./wallet";
import { boardSource, earnedItems, setEarned } from "./earned";

/**
 * The wardrobe, in the player's own Player Durable Object: what they own, what they wear, and the
 * receipts that make spending and wearing safe to send again. Wearing and the owned items need
 * POLLEN_WARDROBE; spending and the catalogue's prices need POLLEN_SHOP (features.ts).
 * Earned items (earned.ts) are owned too, beside what was bought or dropped.
 *
 * Storage (storage-schema.ts POLLEN_SHOP_TABLES), made by the first purchase or look:
 * - pollen_items: owned items and reaction packs, bought or dropped by an item bloom (source "bloom").
 *   Nothing owned is sold again (spend.ts), so a purchase can never charge twice for one thing,
 *   whatever arrives late or twice.
 * - pollen_ops: the newest MAX_OPS receipts, keyed by the phone's idempotency key, with the hash of
 *   the request that made each (the Worker's digest of its canonical body, as room operations).
 *   The same key and body answers the stored receipt and changes nothing; the same key with
 *   another body is 409 idempotency_key_reused.
 * - pollen_look: the look worn and the revision it came from (the phone's clock, as display names),
 *   so an older equip that arrives after a newer one answers the current look.
 *
 * Every check and write of one spend or equip happens in one synchronous transaction: the caller
 * hashes the body first, and nothing here awaits.
 */
export type OpKey = { key: string; hash: string };
export type SpendReceipt = { schema_version: 1; op: "spend"; kind: SpendRequest["kind"]; id: string; pieces: string[]; cost: number; balance: number };
export type LookState = { schema_version: 1; look: Look; revision: number };
export type EquipReceipt = LookState & { op: "equip" };
/**
 * What GET /v1/pollen adds while the wardrobe is on: what is owned (bought, dropped or earned) and worn,
 * and `offered`, the items a phone may draw: with the shop on, every item the server releases (sold or
 * earned); with it off, only the player's own, so nothing of the catalogue shows without the shop.
 */
export type OwnedView = { items: string[]; packs: string[]; look: Look; look_revision: number; offered: string[] };
/**
 * What it adds beside that while the shop is on. `prices`, `sets` and `pack_price` come from the server's
 * catalogue, which decides what is sold and for how much, so a phone shows the price the spend checks.
 */
export type ShopView = { prices: Record<string, number>; offered_packs: string[]; pack_price: number; sets: Record<string, string[]>; unlocked: string[] };
export type WardrobeView = OwnedView & ShopView;

const [ITEMS, OPS] = POLLEN_SHOP_TABLES;
export const MAX_OPS = OPS.maxRows;
/** How far ahead of the server's clock an equip revision may be (phones send milliseconds since 1970). */
export const MAX_LOOK_REVISION_AHEAD_MS = 24 * 3_600_000;

/** Whether the tables exist, read once per Player instance; a create or drop forgets the answer. */
const known = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let found = known.get(storage);
  if (found === undefined) {
    found = storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", ITEMS.name).toArray().length > 0;
    known.set(storage, found);
  }
  return found;
}
function ensureTables(storage: DurableObjectStorage): void {
  if (present(storage)) return;
  for (const table of POLLEN_SHOP_TABLES) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  known.delete(storage);
}

/** Owned item and pack ids by kind: what was bought or dropped, and every earned item. */
function owned(storage: DurableObjectStorage): Map<string, string> {
  const result = present(storage) ? new Map(storage.sql.exec<{ item_id: string; kind: string }>("SELECT item_id,kind FROM pollen_items LIMIT ?", ITEMS.maxRows).toArray().map(row => [row.item_id, row.kind])) : new Map<string, string>();
  for (const id of earnedItems(storage)) result.set(id, "item");
  return result;
}

/** The item ids the player owns (not packs): what an item bloom may no longer drop. Read inside the credit's transaction. */
export function ownedItemIds(storage: DurableObjectStorage): ReadonlySet<string> {
  return new Set([...owned(storage)].filter(([, kind]) => kind === "item").map(([id]) => id));
}
/**
 * The reaction packs the player owns, for the turn answers that check pack faces (v2/face-packs.ts).
 * Never throws, so it can never stop the turn it rides on; anything unreadable reads as none.
 */
export function ownedPackIds(storage: DurableObjectStorage): string[] {
  try { return [...owned(storage)].filter(([, kind]) => kind === "pack").map(([id]) => id); } catch { return []; }
}
/** Owns an item an item bloom dropped, inside the credit's transaction (pollen/item-blooms.ts). Never one already owned. */
export function addDroppedItem(storage: DurableObjectStorage, itemId: string, now: number): void {
  ensureTables(storage);
  storage.sql.exec("INSERT INTO pollen_items VALUES (?,?,?,?)", itemId, "item", "bloom", now);
}

function storedLook(storage: DurableObjectStorage, catalog: Catalog = CATALOG): LookState {
  const row = present(storage) ? storage.sql.exec<{ data: string }>("SELECT data FROM pollen_look WHERE id=1").toArray()[0] : undefined;
  if (row) {
    try {
      const value: unknown = JSON.parse(row.data);
      if (isObject(value) && value.schema_version === 1 && validLook(value.look, catalog) && Number.isSafeInteger(value.revision)) return value as LookState;
    } catch { /* an unreadable row reads as the default look */ }
  }
  return { schema_version: 1, look: {}, revision: 0 };
}

/**
 * The look the player wears, for the identity answers that carry it into rooms. Never throws, so
 * it can never stop the turn or join it rides on; anything unreadable is the default look.
 */
export function wornLook(storage: DurableObjectStorage, catalog: Catalog = CATALOG): Look {
  try { return storedLook(storage, catalog).look; } catch { return {}; }
}

/** The stored receipt for `op`, 409 for the same key with another body, or null for a new key. */
function priorOp<T>(storage: DurableObjectStorage, op: OpKey): Outcome<T> | null {
  if (!present(storage)) return null;
  const row = storage.sql.exec<{ request_hash: string; data: string }>("SELECT request_hash,data FROM pollen_ops WHERE op_key=?", op.key).toArray()[0];
  if (!row) return null;
  return equalHash(row.request_hash, op.hash) ? ok(JSON.parse(row.data) as T) : fail(409, "idempotency_key_reused");
}
function saveOp(storage: DurableObjectStorage, op: OpKey, now: number, receipt: unknown): void {
  storage.sql.exec("INSERT INTO pollen_ops (op_key,request_hash,created_at,data) VALUES (?,?,?,?)", op.key, op.hash, now, JSON.stringify(receipt));
  // Only the newest MAX_OPS stay: a key older than that is a new request, which can never charge twice (nothing owned is sold again).
  storage.sql.exec("DELETE FROM pollen_ops WHERE op_key IN (SELECT op_key FROM pollen_ops ORDER BY created_at DESC, op_key DESC LIMIT -1 OFFSET ?)", MAX_OPS);
}
export function validOpKey(op: OpKey): boolean { return IDEMPOTENCY_PATTERN.test(op.key) && HASH_PATTERN.test(op.hash); }

/**
 * One purchase: priced from what the player owns now and what they cleared, checked against the
 * balance and the cost the phone showed (`expected`), then paid, owned and receipted together.
 * `active` re-checks the identity inside the transaction.
 */
export function spend(storage: DurableObjectStorage, op: OpKey, request: SpendRequest, expected: number, now: number, active: () => boolean, catalog: Catalog = CATALOG): Outcome<SpendReceipt> {
  if (!validOpKey(op)) return fail(400, "invalid_pollen_spend");
  return storage.transactionSync((): Outcome<SpendReceipt> => {
    if (!active()) return fail(404, "identity_absent");
    const prior = priorOp<SpendReceipt>(storage, op); if (prior) return prior;
    const items = owned(storage);
    const quoted = quote(request, { owned: new Set(items.keys()), cleared: level => chapterCleared(storage, level) }, catalog);
    if (!quoted.ok) return quoted;
    const left = charge(quoted.value, walletBalance(storage, now), expected);
    if (!left.ok) return left;
    const balance = payFromWallet(storage, quoted.value.cost, now);
    if (balance === null || balance !== left.value) return fail(409, "pollen_price_changed");
    ensureTables(storage);
    for (const id of quoted.value.pieces) storage.sql.exec("INSERT INTO pollen_items VALUES (?,?,?,?)", id, request.kind === "pack" ? "pack" : "item", "bought", now);
    const receipt: SpendReceipt = { schema_version: 1, op: "spend", kind: request.kind, id: request.id, pieces: quoted.value.pieces, cost: quoted.value.cost, balance };
    saveOp(storage, op, now, receipt);
    return ok(receipt);
  });
}

/**
 * Wears `look`: every item in it must be owned. A revision at or under the stored one answers the
 * current look and writes nothing, so a late or repeated equip never undoes a newer one.
 */
export function equip(storage: DurableObjectStorage, op: OpKey, look: unknown, revision: number, now: number, active: () => boolean, catalog: Catalog = CATALOG): Outcome<EquipReceipt> {
  if (!validOpKey(op)) return fail(400, "invalid_pollen_equip");
  if (!validLook(look, catalog) || !Number.isSafeInteger(revision) || revision < 1 || revision > now + MAX_LOOK_REVISION_AHEAD_MS) return fail(400, "invalid_pollen_equip");
  return storage.transactionSync((): Outcome<EquipReceipt> => {
    if (!active()) return fail(404, "identity_absent");
    const prior = priorOp<EquipReceipt>(storage, op); if (prior) return prior;
    const current = storedLook(storage, catalog);
    if (revision <= current.revision) return ok({ ...current, op: "equip" });
    const items = owned(storage);
    if (Object.values(look).some(id => items.get(id) !== "item")) return fail(403, "not_owned");
    // The default look on a player who never bought anything stores nothing.
    if (!present(storage) && isDefaultLook(look)) return ok({ schema_version: 1, look: {}, revision, op: "equip" });
    ensureTables(storage);
    const state: LookState = { schema_version: 1, look, revision };
    storage.sql.exec("INSERT OR REPLACE INTO pollen_look VALUES (1,?)", JSON.stringify(state));
    const receipt: EquipReceipt = { ...state, op: "equip" };
    saveOp(storage, op, now, receipt);
    return ok(receipt);
  });
}

/**
 * What a leaderboard gives the player now (earned.ts board source), delivered whole by the replay job.
 * An item no source gives any more comes off the look in the same transaction, at the same revision.
 * `active` re-checks the identity inside the transaction. Answers whether anything changed.
 */
export function noteBoardRewards(storage: DurableObjectStorage, board: string, items: readonly string[], seq: number, now: number, active: () => boolean, catalog: Catalog = CATALOG): Outcome<{ changed: boolean }> {
  return storage.transactionSync((): Outcome<{ changed: boolean }> => {
    if (!active()) return fail(404, "identity_absent");
    if (!setEarned(storage, boardSource(board), items, seq, now)) return ok({ changed: false });
    const current = storedLook(storage, catalog), mine = owned(storage);
    const kept = Object.fromEntries(Object.entries(current.look).filter(([, id]) => mine.get(id) === "item"));
    if (Object.keys(kept).length !== Object.keys(current.look).length) storage.sql.exec("INSERT OR REPLACE INTO pollen_look VALUES (1,?)", JSON.stringify({ ...current, look: kept } satisfies LookState));
    return ok({ changed: true });
  });
}

/** GET /v1/pollen's wardrobe part: what is owned and worn, and with `shop` what is sold and for how much. Read only. */
export function wardrobeView(storage: DurableObjectStorage, shop: boolean, catalog: Catalog = CATALOG): OwnedView | WardrobeView {
  const items = owned(storage), look = storedLook(storage, catalog);
  const base: OwnedView = { items: [...items].filter(([, kind]) => kind === "item").map(([id]) => id).sort(), packs: [...items].filter(([, kind]) => kind === "pack").map(([id]) => id).sort(),
    look: look.look, look_revision: look.revision, offered: offeredItems(catalog) };
  if (!shop) return { ...base, offered: offeredItems(catalog).filter(id => items.get(id) === "item") };
  const sets = Object.fromEntries(offeredSets(catalog).map(set => [set, setPieces(set, catalog)]));
  const unlocked = offeredItems(catalog).filter(id => catalog.items[id].unlock !== "" && chapterCleared(storage, catalog.items[id].unlock));
  return { ...base, prices: Object.fromEntries(offeredItems(catalog).filter(id => sold(id, catalog)).map(id => [id, itemPrice(id, catalog)])),
    offered_packs: offeredPacks(catalog), pack_price: catalog.pack_price, sets, unlocked };
}

/** Account erasure: owned items, receipts and the look go. */
export function dropWardrobe(storage: DurableObjectStorage): void {
  for (const table of POLLEN_SHOP_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
  known.delete(storage);
}
export function isWardrobeTable(row: { name: string; sql: string }): boolean { return isLazyTable(POLLEN_SHOP_TABLES, row); }
