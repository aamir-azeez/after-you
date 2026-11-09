import { POLLEN_PURSE_TABLES } from "../storage-schema";

/**
 * The currencies: Pollen and Fruits are two kinds of one wallet. They share the ledger (pollen_claims, wallet.ts
 * applyLedger) and are told apart by the ledger key: a Fruit line's key starts with FRUIT_PREFIX ("fruit:"), a Pollen
 * line's never does. Pollen's balance stays in the pollen_wallet row exactly as older code reads it; the Fruit balance,
 * and the few other numbers Fruits need, live in the purse (storage-schema.ts POLLEN_PURSE_TABLES), one row per kind:
 * - "fruits": the Fruit balance (below 0 only after a refund took back Fruits already spent) and lifetime earned;
 * - "sunshine": bank turns of Sunshine left (balance), and turns ever bought (earned);
 * - "converted": Fruits turned into Pollen that no refund has taken back yet (fruits.ts reclaim);
 * - "count:<track>": an achievement counter whose ledger lines are pruned (achievements.ts);
 * - "swept": the one-time achievement check on a player's first Fruits read (achievements.ts).
 * Every write runs inside the caller's transaction. The table is made by its first write only.
 */
export const CURRENCIES = Object.freeze(["pollen", "fruits"] as const);
export type Currency = typeof CURRENCIES[number];
export const FRUIT_PREFIX = "fruit:";
/** A ledger key in a currency: Fruit keys carry FRUIT_PREFIX. */
export const keyIn = (currency: Currency, key: string) => currency === "fruits" ? FRUIT_PREFIX + key : key;
export const currencyOfKey = (key: string): Currency => key.startsWith(FRUIT_PREFIX) ? "fruits" : "pollen";

export type PurseKind = "fruits" | "sunshine" | "converted" | "swept" | `count:${string}`;
export type PurseRow = { balance: number; earned: number };

const [PURSE] = POLLEN_PURSE_TABLES;
const known = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let found = known.get(storage);
  if (found === undefined) {
    found = storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", PURSE.name).toArray().length > 0;
    known.set(storage, found);
  }
  return found;
}

/** One kind's row, zeros when it was never written. */
export function purse(storage: DurableObjectStorage, kind: PurseKind): PurseRow {
  if (!present(storage)) return { balance: 0, earned: 0 };
  return storage.sql.exec<PurseRow>("SELECT balance,earned FROM currency_purse WHERE kind=?", kind).toArray()[0] ?? { balance: 0, earned: 0 };
}
/** Every row at once (at most PURSE.maxRows), for a read that needs several. */
export function purseRows(storage: DurableObjectStorage): Map<string, PurseRow> {
  if (!present(storage)) return new Map();
  return new Map(storage.sql.exec<{ kind: string; balance: number; earned: number }>("SELECT kind,balance,earned FROM currency_purse LIMIT ?", PURSE.maxRows).toArray()
    .map(row => [row.kind, { balance: row.balance, earned: row.earned }]));
}
/** Writes one kind's row, inside the caller's transaction. */
export function setPurse(storage: DurableObjectStorage, kind: PurseKind, row: PurseRow): void {
  if (!Number.isSafeInteger(row.balance) || !Number.isSafeInteger(row.earned)) throw new Error("invalid_purse_row");
  if (!present(storage)) { storage.sql.exec(PURSE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ")); known.delete(storage); }
  storage.sql.exec("INSERT OR REPLACE INTO currency_purse VALUES (?,?,?)", kind, row.balance, row.earned);
}
/** Adds `delta` to a kind's balance; a gain also adds to its lifetime earned. The new balance. */
export function addToPurse(storage: DurableObjectStorage, kind: PurseKind, delta: number, earns = true): number {
  if (delta === 0) return purse(storage, kind).balance;
  const row = purse(storage, kind);
  const next = { balance: row.balance + delta, earned: row.earned + (earns && delta > 0 ? delta : 0) };
  setPurse(storage, kind, next);
  return next.balance;
}

/** Account erasure: the purse goes with the wallet. */
export function dropPurse(storage: DurableObjectStorage): void {
  storage.sql.exec(`DROP TABLE IF EXISTS ${PURSE.name}`);
  known.delete(storage);
}
