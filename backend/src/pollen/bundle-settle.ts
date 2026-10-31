import { POLLEN_BUNDLE_TABLES } from "../storage-schema";
import { DAY_MS, RATES, type Rates } from "./rates";
import { BUNDLES, BUNDLE_KEYS, firstGift, type BundleKey, type Bundles } from "./bundles";
import { applyLedger, ledgerLines, purchaseLines, walletBalance, type LedgerEntry } from "./wallet";
import type { BundleAsk, BundleLookup, BundlePurchase, BundleRead } from "./bundle-provider";

/**
 * Pollen bundles in the player's own Player Durable Object (POLLEN_BUNDLES): bought Pollen is credited
 * from what RevenueCat lists, never from anything the phone sends.
 *
 * Run by the claim route (POST /v1/pollen/bundle-claims, after a purchase) and, at most once a day, by the
 * wallet read of a player who has bought a bundle before (the refund check):
 * 1. One RevenueCat read from inside this call (an outbound subrequest, not a DO request).
 * 2. For orders new to this player, one PollenClaims request (claims.ts claimBundles): the first identity
 *    to claim a Google Play order keeps it, so a restore that moves it to another App User ID, or gives it a
 *    new RevenueCat id, never pays twice.
 * 3. After those awaits, one synchronous transaction plans again from the ledger as stored now (an
 *    overlapping call may have paid in between): each owned order not paid yet pays once under
 *    `bundle:<order>`, and each refunded purchase whose order was paid takes back exactly what it paid under
 *    `bundlerefund:<order>`, which may take the balance below zero (spending stops until earning repays it).
 *    Each purchase is matched to the ledger by its order, so a new RevenueCat id for one already paid (a restore
 *    back to this player) is the same line. Lines keyed by RevenueCat purchase id are the older form: still
 *    matched, by their kept order or by that id, and taken back under their own key. A purchase without an
 *    order is never paid.
 *
 * A restore with RevenueCat's "Transfer to new App User ID" moves a purchase off the buyer's list, so the
 * identity that was paid for it would never see its refund there. The daily check (deps.lookup) therefore also
 * looks up each paid bundle missing from the list and not taken back yet by its Google Play order, whoever holds
 * it now (bundle-provider.ts lookupBundles): outbound requests only, at most MAX_BUNDLE_LOOKUPS a check, rotated
 * by day when there are more, and none at all for a buyer whose bundles are all still listed. A refunded one is
 * matched to its line by the same order, so it is taken back under the same `bundlerefund:` key, once.
 * PollenClaims already pays each purchase to one identity only, so only that identity's take-back matters.
 * A failed lookup still lets the list's own credits and refunds land, but leaves the check due (after the outage
 * pause) so the lookups are made again. The claim route makes no lookups; while a paid bundle is missing it
 * leaves the check time alone too, so the next wallet read still makes them.
 *
 * The first bundle a player ever buys also pays the first gift (bundles.ts firstGift), once, while the gift
 * is set above 0. Whether it is still open is read from the ledger: any `bundle:` row closes it, refunded or
 * not, with or without a gift, so a gift the owner turns on later never goes to a player who already bought.
 *
 * Storage: the ledger rows (pollen_claims, never pruned) and pollen_bundle_check (storage-schema.ts
 * POLLEN_BUNDLE_TABLES), one row with the last check's time. Nothing is added to the wallet row.
 */
export type BundleDeps = {
  /** The player's counted bundle purchases (bundle-provider.ts readBundles). */
  read: () => Promise<BundleRead>;
  /** PollenClaims (claims.ts claimBundlesFor): whether this player holds each purchase's order, by order; null when it could not be asked. */
  claim: (purchases: BundlePurchase[]) => Promise<Record<string, boolean> | null>;
  /** The daily check only: which paid bundles missing from the list are refunded now (bundle-provider.ts lookupBundles). */
  lookup?: (asks: BundleAsk[]) => Promise<BundleLookup>;
};
export type BundleCredit = { bundle: BundleKey; pollen: number; first_gift: number; order: string; purchased_at: number; usd_cents: number };
export type BundleRefund = { bundle: BundleKey; amount: number; order: string };
export type BundleReply = { schema_version: 1; balance: number; credited: BundleCredit[]; refunded: BundleRefund[]; pending: boolean };
/** What GET /v1/pollen adds while bundles are on: whether a first gift is still open (and set above 0), its percent, and the money spent (refunds taken off). */
export type BundlesView = { first_gift: boolean; first_gift_percent: number; spent_usd_cents: number };
/** `lookup_failed`: the daily check's lookups could not be made (the rest settled; the check stays due). */
export type BundleOutcome = { status: "settled"; reply: BundleReply; lookup_failed?: string } | { status: "unavailable"; reason: string } | { status: "absent" };

/** After a failed provider or claims call, the daily check waits this long before trying again (memory only). */
export const BUNDLE_OUTAGE_PAUSE_MS = 5 * 60_000;
/** The refund check runs at most this often per player. */
export const BUNDLE_CHECK_MS = DAY_MS;
/** At most this many paid bundles missing from the list are looked up in one check: within the Workers cap on subrequests, and on simultaneous connections, so they go in one round. */
export const MAX_BUNDLE_LOOKUPS = 6;

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

/** The paid lines, by kept order and by key, to match a listed purchase to the line that paid it. */
type Paid = { byOrder: Map<string, Line>; byKey: Map<string, Line> };
function paidIndex(lines: readonly Line[]): Paid {
  const byOrder = new Map<string, Line>(), byKey = new Map<string, Line>();
  for (const line of lines) {
    byKey.set(line.key, line);
    const order = line.detail.order;
    if (typeof order === "string" && order && !byOrder.has(order)) byOrder.set(order, line);
  }
  return { byOrder, byKey };
}
/** The line that paid `purchase`: by its order, or (an older line) by its RevenueCat id. */
const paidLine = (purchase: { id: string; order: string }, paid: Paid): Line | undefined =>
  (purchase.order ? paid.byOrder.get(purchase.order) : undefined) ?? paid.byKey.get(bundleKey(purchase.id));
/** A paid line's refund key: `bundlerefund:` with the same suffix, whichever form the line has. */
const refundKeyOf = (line: Line) => bundleRefundKey(line.key.slice(bundleKey("").length));

/** Whether the player has ever been paid for a bundle: only then does the wallet read check for refunds. */
export function hasBundles(storage: DurableObjectStorage): boolean { return ledgerLines(storage, "bundle:", 1).length > 0; }

/** Whether the daily refund check is due: a player with bundles, a day after the last check, and no outage pause. */
export function bundleCheckDue(storage: DurableObjectStorage, now: number): boolean {
  if ((paused.get(storage) ?? 0) > now || !hasBundles(storage)) return false;
  return now - lastBundleCheck(storage) >= BUNDLE_CHECK_MS;
}

/**
 * The paid bundles not taken back that the list no longer shows, as lookups: up to MAX_BUNDLE_LOOKUPS, a
 * different window each day when there are more, so none waits for good.
 */
export function missingBundles(storage: DurableObjectStorage, listed: readonly BundlePurchase[], now: number): BundleAsk[] {
  const lines = bundleLines(storage), paid = paidIndex(lines);
  const shown = new Set(listed.flatMap(purchase => { const line = paidLine(purchase, paid); return line ? [line.key] : []; }));
  const back = new Set(refundLines(storage).map(line => line.key));
  const asks = lines.flatMap(line => {
    const { bundle, order, purchase_id: id } = line.detail;
    if (shown.has(line.key) || back.has(refundKeyOf(line)) || !(BUNDLE_KEYS as readonly unknown[]).includes(bundle)) return [];
    return [{ id: typeof id === "string" ? id : line.key.slice(bundleKey("").length), bundle: bundle as BundleKey, order: typeof order === "string" ? order : "" }];
  });
  if (asks.length <= MAX_BUNDLE_LOOKUPS) return asks;
  const start = (Math.floor(now / DAY_MS) * MAX_BUNDLE_LOOKUPS) % asks.length;
  return Array.from({ length: MAX_BUNDLE_LOOKUPS }, (_, index) => asks[(start + index) % asks.length]);
}

/** A looked-up refund as the plan reads it: the ledger's own purchase, refunded. */
const takenBack = (ask: BundleAsk): BundlePurchase => ({ id: ask.id, bundle: ask.bundle, refunded: true, quantity: 1, order: ask.order, usd_cents: 0, purchased_at: 0 });

/** The orders a read shows refunded: none of them is paid on that read, whatever order its records come in. */
const refundedOrders = (purchases: readonly BundlePurchase[]) => new Set(purchases.flatMap(purchase => purchase.refunded && purchase.order ? [purchase.order] : []));

/**
 * The plan for one read, from the ledger as stored now: what to pay and what to take back. `held` is whether
 * this player holds an order (PollenClaims). Two records of one order in one read pay or take back once, and an
 * order any record shows refunded is never paid.
 */
export function planBundles(purchases: readonly BundlePurchase[], held: (order: string) => boolean, lines: readonly Line[], refunded: ReadonlySet<string>, giftOpen: boolean, bundles: Bundles = BUNDLES): { entries: LedgerEntry[]; credited: BundleCredit[]; refunds: BundleRefund[] } {
  const entries: LedgerEntry[] = [], credited: BundleCredit[] = [], refunds: BundleRefund[] = [];
  const paid = paidIndex(lines), back = new Set(refunded), gone = refundedOrders(purchases);
  let open = giftOpen;
  for (const purchase of purchases) {
    const prior = paidLine(purchase, paid);
    if (purchase.refunded) {
      if (!prior || back.has(refundKeyOf(prior))) continue;
      back.add(refundKeyOf(prior));
      const order = typeof prior.detail.order === "string" && prior.detail.order ? prior.detail.order : purchase.order;
      entries.push({ key: refundKeyOf(prior), kind: "bundlerefund", amount: -prior.amount,
        detail: { bundle: purchase.bundle, purchase_id: purchase.id, order, usd_cents: Number(prior.detail.usd_cents ?? purchase.usd_cents), refunds: prior.key } });
      refunds.push({ bundle: purchase.bundle, amount: prior.amount, order });
      continue;
    }
    if (prior || !purchase.order || gone.has(purchase.order) || !held(purchase.order)) continue;
    const pollen = bundles.bundles[purchase.bundle].pollen * purchase.quantity, gift = open ? firstGift(purchase.bundle, bundles) : 0;
    // Only the first bundle a player ever buys can carry the gift, whatever the percent was then.
    open = false;
    const line: Line = { key: bundleKey(purchase.order), amount: pollen + gift,
      detail: { bundle: purchase.bundle, purchase_id: purchase.id, order: purchase.order, usd_cents: purchase.usd_cents, first_gift: gift, quantity: purchase.quantity, purchased_at: purchase.purchased_at } };
    paid.byOrder.set(purchase.order, line); paid.byKey.set(line.key, line);
    entries.push({ ...line, kind: "bundle" });
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
  const asks = missingBundles(storage, read.purchases, now);
  let moved: BundlePurchase[] = [], lookupFailed: string | null = null;
  if (asks.length && deps.lookup) {
    const found = await deps.lookup(asks);
    if (found.ok) moved = asks.filter(ask => found.refunded.includes(ask.id)).map(takenBack);
    else lookupFailed = found.reason;
  }
  // Without lookups made (the claim route, or a failed lookup) a missing bundle leaves the check due, so the wallet read looks it up again.
  const checked = asks.length === 0 || (deps.lookup !== undefined && lookupFailed === null);
  // Orders new to this player, each once; at most MAX_CLAIM_KEYS at a time, a longer list waits for the next call.
  const before = paidIndex(bundleLines(storage)), gone = refundedOrders(read.purchases), fresh = new Map<string, BundlePurchase>();
  for (const purchase of read.purchases)
    if (!purchase.refunded && purchase.order && !gone.has(purchase.order) && !paidLine(purchase, before) && !fresh.has(purchase.order)) fresh.set(purchase.order, purchase);
  const asked = [...fresh.values()].slice(0, 16);
  const answers = asked.length ? await deps.claim(asked) : {};
  if (answers === null) { paused.set(storage, now + BUNDLE_OUTAGE_PAUSE_MS); return { status: "unavailable", reason: "claims_unavailable" }; }
  let outcome: BundleOutcome = { status: "absent" };
  storage.transactionSync(() => {
    if (!active()) return;
    // Planned again from the ledger as stored now: what an overlapping call paid is never paid twice.
    const lines = bundleLines(storage);
    const refunded = new Set(refundLines(storage).map(line => line.key));
    const plan = planBundles([...read.purchases, ...moved], order => answers[order] === true, lines, refunded, lines.length === 0, bundles);
    applyLedger(storage, plan.entries, now, rates);
    if (checked) noteCheck(storage, now);
    outcome = { status: "settled", reply: { schema_version: 1, balance: walletBalance(storage, now, rates), credited: plan.credited, refunded: plan.refunds, pending: false }, ...(lookupFailed ? { lookup_failed: lookupFailed } : {}) };
  });
  if (lookupFailed) paused.set(storage, now + BUNDLE_OUTAGE_PAUSE_MS); else paused.delete(storage);
  return outcome;
}

/** GET /v1/pollen's bundles part. Read only; never throws. */
export function bundlesView(storage: DurableObjectStorage, bundles: Bundles = BUNDLES): BundlesView {
  const percent = bundles.first_bonus_percent;
  try {
    // The same total the history shows (wallet.ts purchaseLines).
    return { first_gift: percent > 0 && !hasBundles(storage), first_gift_percent: percent, spent_usd_cents: purchaseLines(storage).spent_usd_cents ?? 0 };
  } catch { return { first_gift: false, first_gift_percent: percent, spent_usd_cents: 0 }; }
}

/** Account erasure: the check time goes with the wallet (its ledger rows are the wallet's). */
export function dropBundles(storage: DurableObjectStorage): void {
  for (const table of POLLEN_BUNDLE_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
  known.delete(storage); paused.delete(storage);
}
