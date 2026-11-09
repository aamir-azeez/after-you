import { fail, ok, type Outcome } from "../protocol";
import { FRUIT_PREFIX, addToPurse, currencyOfKey, purse, setPurse } from "./currency";
import { FRUIT_RULES, type FruitRules } from "./fruits";
import { applyLedger, inLedger, newestLines, receiptFields, walletBalance, type LedgerEntry } from "./wallet";

/**
 * What Fruits do besides being paid (PLAN v2 sections 5, 6 and 11), in the player's own Player Durable Object. Every
 * function runs inside the caller's transaction (the spend's, a credit's, a refund's); none awaits.
 *
 * - Turning Fruits into Pollen: one way, FRUIT_RULES.convert.pollen_per_fruit each, in multiples of its step, refused while
 *   either balance is below 0. Two ledger lines in one transaction, `fruit:convert:<request key>` and `convert:<request key>`,
 *   kept as history only and pruned with turns (wallet.ts prune), since the spend's own receipt (wardrobe.ts pollen_ops)
 *   makes a retry answer the same. The purse's "converted" row counts Fruits turned into Pollen that no refund took back.
 * - Taking back after converting (withReclaim): a refund that takes back Fruits the player no longer has, because they
 *   were turned into Pollen, takes that part back as Pollen at the same rate, so buying, converting and refunding never
 *   keeps anything: Pollen taken = rate x min(shortfall, converted not reclaimed yet). Fruits spent on Orchard items stay
 *   below zero as Fruits, which blocks Fruit spending until play or the grant repays it. The account is never locked.
 * - Sunshine: bought for FRUIT_RULES.sunshine.price Fruits when none is left; each bank turn after that pays its plain amount
 *   again (wallet.ts creditTurn) until FRUIT_RULES.sunshine.turns are used. It never touches blooms, item drops, first clears,
 *   the grant, bundles or duel bonuses, and it has no clock.
 */
export type ConvertOutcome = { fruits: number; pollen: number; fruit_balance: number; balance: number };

/**
 * Fruit take-backs in `entries` with the converted shortfall moved onto Pollen: each negative Fruit line the balance can't
 * cover is shortened by the Fruits that were converted, and a Pollen line `reclaim:<its key>` takes those back as Pollen.
 * `pollen`: the Pollen each Fruit take-back took, by its key. Entries already in the ledger are left out (they change nothing).
 */
export function withReclaim(storage: DurableObjectStorage, entries: readonly LedgerEntry[], rules: FruitRules = FRUIT_RULES): { entries: LedgerEntry[]; pollen: Map<string, number> } {
  const fresh = entries.filter(entry => !inLedger(storage, entry.key)), pollen = new Map<string, number>();
  if (!fresh.some(entry => currencyOfKey(entry.key) === "fruits" && entry.amount < 0)) return { entries: fresh, pollen };
  let balance = purse(storage, "fruits").balance;
  const converted = purse(storage, "converted");
  let left = converted.balance;
  const out: LedgerEntry[] = [];
  for (const entry of fresh) {
    if (currencyOfKey(entry.key) !== "fruits") { out.push(entry); continue; }
    balance += entry.amount;
    const back = entry.amount < 0 && balance < 0 ? Math.min(-balance, left, -entry.amount) : 0;
    if (back <= 0) { out.push(entry); continue; }
    balance += back; left -= back;
    const taken = back * rules.convert.pollen_per_fruit;
    out.push({ ...entry, amount: entry.amount + back, detail: { ...entry.detail, reclaimed: back } });
    out.push({ key: `reclaim:${entry.key.slice(FRUIT_PREFIX.length)}`, kind: "reclaim", amount: -taken, earns: false, detail: { fruits: back, refunds: entry.key } });
    pollen.set(entry.key, taken);
  }
  if (left !== converted.balance) setPurse(storage, "converted", { balance: left, earned: converted.earned });
  return { entries: out, pollen };
}

/** Turns `count` Fruits into Pollen under the spend's request key. `expected`: the Fruits the phone's card showed. */
export function convertFruits(storage: DurableObjectStorage, opKey: string, count: number, expected: number, now: number, rules: FruitRules = FRUIT_RULES): Outcome<ConvertOutcome> {
  const step = rules.convert.step;
  if (!Number.isSafeInteger(count) || count < step || count % step !== 0 || count > 1_000_000) return fail(400, "invalid_pollen_spend");
  if (expected !== count) return fail(409, "pollen_price_changed");
  const fruits = purse(storage, "fruits").balance;
  if (fruits < 0 || walletBalance(storage, now) < 0) return fail(403, "fruits_blocked");
  if (fruits < count) return fail(402, "fruits_short");
  const pollen = count * rules.convert.pollen_per_fruit;
  applyLedger(storage, [
    { key: `${FRUIT_PREFIX}convert:${opKey}`, kind: "fruitconvert", amount: -count, detail: { pollen } },
    { key: `convert:${opKey}`, kind: "convert", amount: pollen, earns: false, detail: { fruits: count } }
  ], now);
  const converted = purse(storage, "converted");
  setPurse(storage, "converted", { balance: converted.balance + count, earned: converted.earned + count });
  return ok({ fruits: count, pollen, fruit_balance: purse(storage, "fruits").balance, balance: walletBalance(storage, now) });
}

/** Buys Sunshine: `expected` is the price the phone showed. The Fruit balance and the turns left after it. */
export function buySunshine(storage: DurableObjectStorage, expected: number, rules: FruitRules = FRUIT_RULES): Outcome<{ fruit_balance: number; sunshine_left: number }> {
  const fruits = purse(storage, "fruits").balance, sunshine = purse(storage, "sunshine");
  if (fruits < 0) return fail(403, "fruits_blocked");
  if (sunshine.balance > 0) return fail(409, "sunshine_active");
  if (expected !== rules.sunshine.price) return fail(409, "pollen_price_changed");
  if (fruits < rules.sunshine.price) return fail(402, "fruits_short");
  const balance = addToPurse(storage, "fruits", -rules.sunshine.price);
  setPurse(storage, "sunshine", { balance: rules.sunshine.turns, earned: sunshine.earned + rules.sunshine.turns });
  return ok({ fruit_balance: balance, sunshine_left: rules.sunshine.turns });
}

/** Spends one Sunshine turn (wallet.ts FruitHooks.sunshine): the turns left after it, or null when none was left. */
export function spendSunshineTurn(storage: DurableObjectStorage): number | null {
  const sunshine = purse(storage, "sunshine");
  if (sunshine.balance <= 0) return null;
  setPurse(storage, "sunshine", { balance: sunshine.balance - 1, earned: sunshine.earned });
  return sunshine.balance - 1;
}

/** Pays `price` Fruits for Orchard items (wardrobe.ts spend), after the caller checked the balance. The balance left. */
export function payFruits(storage: DurableObjectStorage, price: number): number { return addToPurse(storage, "fruits", -price); }

/** One Fruit line as the Fruits history lists it (GET /v1/pollen/history `fruit_entries`). */
export type FruitEntry = { kind: string; amount: number; at: number; id?: string; level_id?: string; step?: number; bundle?: string; order?: string; store?: "app_store"; usd_cents?: number };
export const FRUIT_HISTORY_LIMIT = 50;
const KINDS: Readonly<Record<string, string>> = Object.freeze({ fruitgrant: "grant", fruitgrantrefund: "grantrefund", fruitwelcome: "welcome", fruitwelcomerefund: "welcomerefund",
  fruitbundle: "bundle", fruitbundlerefund: "bundlerefund", fruitach: "ach", fruitconvert: "convert" });

/** The newest Fruit lines, newest first: one read of the Fruit key range. */
export function fruitHistory(storage: DurableObjectStorage): FruitEntry[] {
  // The achievement marks (0 Fruit lines, at most one per chapter) are read and left out.
  return newestLines(storage, FRUIT_PREFIX, FRUIT_HISTORY_LIMIT + 16).flatMap(line => {
    const kind = KINDS[line.kind];
    if (!kind) return [];
    const detail = line.detail, entry: FruitEntry = { kind, amount: line.amount, at: line.at };
    if (typeof detail.id === "string") entry.id = detail.id;
    if (typeof detail.level_id === "string") entry.level_id = detail.level_id;
    if (typeof detail.step === "number") entry.step = detail.step;
    if (kind === "bundle" || kind === "bundlerefund") Object.assign(entry, receiptFields(detail));
    return [entry];
  }).slice(0, FRUIT_HISTORY_LIMIT);
}
