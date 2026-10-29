import { POLLEN_BUNDLE_TABLES } from "../storage-schema";
import { DAY_MS, RATES, type Rates } from "./rates";
import { BUNDLES, firstGift, type BundleKey, type Bundles } from "./bundles";
import { applyLedger, ledgerLines, walletBalance, type LedgerEntry } from "./wallet";
import type { BundlePurchase, BundleRead } from "./bundle-provider";

/**
 * Pollen bundles in the player's own Player Durable Object (POLLEN_BUNDLES): bought Pollen is credited
 * from what RevenueCat lists, never from anything the phone sends.
 *
 * Run by the claim route (POST /v1/pollen/bundle-claims, after a purchase) and, at most once a day, by the
 * wallet read of a player who has bought a bundle before (the refund check):
 * 1. One RevenueCat read from inside this call (an outbound subrequest, not a DO request).
 * 2. For purchases new to this player, one PollenClaims request (claims.ts claimBundles): the first identity
 *    to claim a purchase keeps it, so a restore that moves it to another App User ID never pays twice.
 * 3. After those awaits, one synchronous transaction plans again from the ledger as stored now (an
 *    overlapping call may have paid in between): each owned purchase not paid yet pays once under
 *    `bundle:<purchase id>`, and each refunded purchase that was paid takes back exactly what it paid under
 *    `bundlerefund:<purchase id>`, which may take the balance below zero (spending stops until earning repays it).
 *
 * The first bundle a player ever buys also pays the first gift (bundles.ts firstGift), once. Whether it is
 * still open is read from the ledger: any `bundle:` row that carried a gift closes it, refunded or not.
 *
 * Storage: the ledger rows (pollen_claims, never pruned) and pollen_bundle_check (storage-schema.ts
 * POLLEN_BUNDLE_TABLES), one row with the last check's time. Nothing is added to the wallet row.
 */
export type BundleDeps = {
  /** The player's counted bundle purchases (bundle-provider.ts readBundles). */
  read: () => Promise<BundleRead>;
  /** PollenClaims answers by key ("bundle:<id>": held by this player), or null when it could not be asked. */
  claim: (keys: string[]) => Promise<Record<string, boolean> | null>;
};
export type BundleCredit = { bundle: BundleKey; pollen: number; first_gift: number; order: string; purchased_at: number; usd_cents: number };
export type BundleRefund = { bundle: BundleKey; amount: number; order: string };
export type BundleReply = { schema_version: 1; balance: number; credited: BundleCredit[]; refunded: BundleRefund[]; pending: boolean };
/** What GET /v1/pollen adds while bundles are on: whether the first gift is still open, and the money spent (refunds taken off). */
export type BundlesView = { first_gift: boolean; spent_usd_cents: number };
export type BundleOutcome = { status: "settled"; reply: BundleReply } | { status: "unavailable"; reason: string } | { status: "absent" };

/** After a failed provider or claims call, the daily check waits this long before trying again (memory only). */
export const BUNDLE_OUTAGE_PAUSE_MS = 5 * 60_000;
/** The refund check runs at most this often per player. */
export const BUNDLE_CHECK_MS = DAY_MS;

const [CHECK] = POLLEN_BUNDLE_TABLES;
export const bundleKey = (id: string) => `bundle:${id}`;
export const bundleRefundKey = (id: string) => `bundlerefund:${id}`;
const known = new WeakMap<DurableObjectStorage, boolean>();
const paused = new WeakMap<DurableObjectStorage, number>();
function present(storage: DurableObjectStorage): boolean {
  let found = known.get(storage);
  if (found === undefined) {
    found = storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", CHECK.name).toArray().length > 0;
    known.set(storage, found);
  }
  return found;
}
/** When the bundles were last checked, 0 for never. */
export function lastBundleCheck(storage: DurableObjectStorage): number {
  if (!present(storage)) return 0;
  return storage.sql.exec<{ checked_at: number }>("SELECT checked_at FROM pollen_bundle_check WHERE id=1").toArray()[0]?.checked_at ?? 0;
}
function noteCheck(storage: DurableObjectStorage, now: number): void {
  if (!present(storage)) { storage.sql.exec(CHECK.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ")); known.delete(storage); }
  storage.sql.exec("INSERT OR REPLACE INTO pollen_bundle_check VALUES (1,?)", now);
}

type Line = { key: string; amount: number; detail: Record<string, unknown> };
const bundleLines = (storage: DurableObjectStorage): Line[] => ledgerLines(storage, "bundle:", 1024);
const refundLines = (storage: DurableObjectStorage): Line[] => ledgerLines(storage, "bundlerefund:", 1024);

/** Whether the player has ever been paid for a bundle: only then does the wallet read check for refunds. */
export function hasBundles(storage: DurableObjectStorage): boolean { return ledgerLines(storage, "bundle:", 1).length > 0; }

/** Whether the daily refund check is due: a player with bundles, a day after the last check, and no outage pause. */
export function bundleCheckDue(storage: DurableObjectStorage, now: number): boolean {
  if ((paused.get(storage) ?? 0) > now || !hasBundles(storage)) return false;
  return now - lastBundleCheck(storage) >= BUNDLE_CHECK_MS;
}

/** The plan for one read, from the ledger as stored now: what to pay and what to take back. */
export function planBundles(purchases: readonly BundlePurchase[], held: (id: string) => boolean, paid: ReadonlyMap<string, Line>, refunded: ReadonlySet<string>, giftOpen: boolean, bundles: Bundles = BUNDLES): { entries: LedgerEntry[]; credited: BundleCredit[]; refunds: BundleRefund[] } {
  const entries: LedgerEntry[] = [], credited: BundleCredit[] = [], refunds: BundleRefund[] = [];
  let open = giftOpen;
  for (const purchase of purchases) {
    const prior = paid.get(bundleKey(purchase.id));
    if (purchase.refunded) {
      if (!prior || refunded.has(bundleRefundKey(purchase.id))) continue;
      entries.push({ key: bundleRefundKey(purchase.id), kind: "bundlerefund", amount: -prior.amount,
        detail: { bundle: purchase.bundle, purchase_id: purchase.id, order: purchase.order, usd_cents: Number(prior.detail.usd_cents ?? purchase.usd_cents), refunds: bundleKey(purchase.id) } });
      refunds.push({ bundle: purchase.bundle, amount: prior.amount, order: purchase.order });
      continue;
    }
    if (prior || !held(purchase.id)) continue;
    const pollen = bundles.bundles[purchase.bundle].pollen * purchase.quantity, gift = open ? firstGift(purchase.bundle, bundles) : 0;
    open = open && gift === 0;
    entries.push({ key: bundleKey(purchase.id), kind: "bundle", amount: pollen + gift,
      detail: { bundle: purchase.bundle, purchase_id: purchase.id, order: purchase.order, usd_cents: purchase.usd_cents, first_gift: gift, quantity: purchase.quantity, purchased_at: purchase.purchased_at } });
    credited.push({ bundle: purchase.bundle, pollen, first_gift: gift, order: purchase.order, purchased_at: purchase.purchased_at, usd_cents: purchase.usd_cents });
  }
  return { entries, credited, refunds };
}

/**
 * Reads RevenueCat and pays or takes back what is due. `active` re-checks the identity inside the
 * transaction. Never throws for a provider or claims failure ("unavailable": nothing is written).
 */
export async function settleBundles(storage: DurableObjectStorage, now: number, active: () => boolean, deps: BundleDeps, rates: Rates = RATES, bundles: Bundles = BUNDLES): Promise<BundleOutcome> {
  const read = await deps.read();
  if (!read.ok) { paused.set(storage, now + BUNDLE_OUTAGE_PAUSE_MS); return { status: "unavailable", reason: read.reason }; }
  const before = new Set(bundleLines(storage).map(line => line.key));
  const fresh = read.purchases.filter(purchase => !purchase.refunded && !before.has(bundleKey(purchase.id)));
  // Ask about at most MAX keys at a time; a longer list waits for the next call.
  const asked = fresh.slice(0, 16).map(purchase => bundleKey(purchase.id));
  const answers = asked.length ? await deps.claim(asked) : {};
  if (answers === null) { paused.set(storage, now + BUNDLE_OUTAGE_PAUSE_MS); return { status: "unavailable", reason: "claims_unavailable" }; }
  let outcome: BundleOutcome = { status: "absent" };
  storage.transactionSync(() => {
    if (!active()) return;
    // Planned again from the ledger as stored now: what an overlapping call paid is never paid twice.
    const paid = new Map(bundleLines(storage).map(line => [line.key, line]));
    const refunded = new Set(refundLines(storage).map(line => line.key));
    const giftOpen = ![...paid.values()].some(line => Number(line.detail.first_gift ?? 0) > 0);
    const plan = planBundles(read.purchases, id => answers[bundleKey(id)] === true, paid, refunded, giftOpen, bundles);
    applyLedger(storage, plan.entries, now, rates);
    noteCheck(storage, now);
    outcome = { status: "settled", reply: { schema_version: 1, balance: walletBalance(storage, now, rates), credited: plan.credited, refunded: plan.refunds, pending: false } };
  });
  paused.delete(storage);
  return outcome;
}

/** GET /v1/pollen's bundles part. Read only; never throws. */
export function bundlesView(storage: DurableObjectStorage): BundlesView {
  try {
    const paid = bundleLines(storage), refunds = refundLines(storage);
    const spent = paid.reduce((sum, line) => sum + Number(line.detail.usd_cents ?? 0), 0) - refunds.reduce((sum, line) => sum + Number(line.detail.usd_cents ?? 0), 0);
    return { first_gift: !paid.some(line => Number(line.detail.first_gift ?? 0) > 0), spent_usd_cents: Math.max(0, spent) };
  } catch { return { first_gift: true, spent_usd_cents: 0 }; }
}

/** Account erasure: the check time goes with the wallet (its ledger rows are the wallet's). */
export function dropBundles(storage: DurableObjectStorage): void {
  for (const table of POLLEN_BUNDLE_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
  known.delete(storage); paused.delete(storage);
}
