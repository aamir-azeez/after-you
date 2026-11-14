import { POLLEN_BUNDLE_TABLES } from "../storage-schema";
import { DAY_MS, RATES, type Rates } from "./rates";
import { BUNDLES, BUNDLE_KEYS, firstGift, type BundleKey, type Bundles } from "./bundles";
import { applyLedger, ledgerLines, purchaseLines, walletBalance, type LedgerEntry } from "./wallet";
import { type BundleAsk, type BundleLookup, type BundlePurchase, type BundleRead } from "./bundle-provider";
import { refId, refStore } from "./claims";
import { CURRENCIES, currencyOfKey, keyIn, purse, type Currency } from "./currency";
import { withReclaim } from "./fruit-ops";

/**
 * Pollen bundles in the player's own Player Durable Object (POLLEN_BUNDLES): bought Pollen is credited
 * from what RevenueCat lists, never from anything the phone sends.
 *
 * Run by the claim route (POST /v1/pollen/bundle-claims, after a purchase) and, at most once a day, by the
 * wallet read of a player who has bought a bundle before (the refund check):
 * 1. One RevenueCat read from inside this call (bundle-provider.ts readBundles: the production and sandbox lists at
 *    once, two outbound subrequests, no DO request). Sandbox purchases pay like real ones, for every player, every time.
 * 2. For purchases new to this player, one PollenClaims request (claims.ts claimBundles): the first identity
 *    to claim a purchase's reference (its Google Play order, or "appstore:" and its App Store transaction id,
 *    claims.ts bundleRef) keeps it, so a restore that moves it to another App User ID, or gives it a new
 *    RevenueCat id, never pays twice. Both stores' purchases settle the same way below; "order" there means
 *    the reference.
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
 * The first bundle a player ever buys, in either store, also pays the first gift (bundles.ts firstGift), once, while
 * the gift is set above 0. Whether it is still open is read from the ledger: any `bundle:` row closes it, refunded or
 * not, from either store, with or without a gift, so a gift the owner turns on later never goes to a player who
 * already bought, and a Play buyer never gets a second one on iPhone.
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
  /** Fruits are on (features.ts fruitsOn): Fruit packs are paid. Off, they wait. */
  fruits?: boolean;
};
/**
 * What a reply says about one purchase: `order` is the store's own id as its receipt shows it (the Play order, or the
 * App Store transaction id), and `store` is "app_store" for an App Store purchase (absent for Play, as before).
 */
type Receipt = { order: string; store?: "app_store" };
export type BundleCredit = { bundle: BundleKey; pollen: number; first_gift: number; purchased_at: number; usd_cents: number } & Receipt;
export type BundleRefund = { bundle: BundleKey; amount: number } & Receipt;
/** A reference (claims.ts bundleRef) as a reply shows it. */
export function receiptOf(ref: string): Receipt {
  return refStore(ref) === "app_store" ? { order: refId(ref), store: "app_store" } : { order: ref };
}
/**
 * `credited` and `refunded` are Pollen bundles only, as older apps read them; Fruit packs answer in `fruit_credited` and
 * `fruit_refunded` (`fruits` and `amount` in Fruits; `pollen_taken`: Pollen taken back for Fruits already turned into Pollen),
 * with `fruit_balance`, only once the player has bought a Fruit pack.
 */
export type FruitCredit = Omit<BundleCredit, "pollen"> & { fruits: number };
export type FruitRefund = BundleRefund & { pollen_taken: number };
export type BundleReply = { schema_version: 1; balance: number; credited: BundleCredit[]; refunded: BundleRefund[]; pending: boolean; fruit_credited?: FruitCredit[]; fruit_refunded?: FruitRefund[]; fruit_balance?: number };
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
/**
 * The claim route's pace per player (memory only). After a claim that credited and took back nothing, the next one
 * reads RevenueCat only after CLAIM_GAP_MS, doubling each time up to CLAIM_GAP_MAX_MS; a claim that settled something,
 * or one a full CLAIM_GAP_MAX_MS after the last, starts it again. The phone's own tries right after a purchase (at 0, 1.5 and 4.5 seconds) fit the first gaps.
 * A claim inside the gap, or while another is running, is refused with a retryable 429 and costs no provider call
 * and no row; the phone keeps its claim waiting and sends it on its next flush.
 */
export const CLAIM_GAP_MS = 1_000;
export const CLAIM_GAP_MAX_MS = 60_000;

const [CHECK] = POLLEN_BUNDLE_TABLES;
/** A pack's ledger keys: `bundle:<order>` and `bundlerefund:<order>`, under FRUIT_PREFIX for a Fruit pack (currency.ts). */
export const bundleKey = (id: string, currency: Currency = "pollen") => keyIn(currency, `bundle:${id}`);
export const bundleRefundKey = (id: string, currency: Currency = "pollen") => keyIn(currency, `bundlerefund:${id}`);
/** The order (or older RevenueCat id) a pack line's key names, whichever currency. */
const idOfKey = (key: string) => key.slice(key.indexOf("bundle:") + "bundle:".length);
const known = new WeakMap<DurableObjectStorage, boolean>();
const paused = new WeakMap<DurableObjectStorage, number>();
type Pace = { next_at: number; gap: number; running: boolean; last_at: number };
const paces = new WeakMap<DurableObjectStorage, Pace>();
/** Forgets the claim pace (memory only), as an evicted object does: account erasure, and tests that claim back to back. */
export function forgetClaimPace(storage: DurableObjectStorage): void { paces.delete(storage); }
/** The claim route's settle under its pace (CLAIM_GAP_MS), or "busy" without a provider call. */
export async function pacedClaim(storage: DurableObjectStorage, now: number, settle: () => Promise<BundleOutcome>): Promise<BundleOutcome | "busy"> {
  const pace = paces.get(storage) ?? { next_at: 0, gap: 0, running: false, last_at: 0 };
  if (pace.running || now < pace.next_at) return "busy";
  // A quiet minute is a new purchase's first claim: its quick tries get the short gaps again.
  if (now - pace.last_at >= CLAIM_GAP_MAX_MS) pace.gap = 0;
  pace.running = true; pace.last_at = now; paces.set(storage, pace);
  let outcome: BundleOutcome = { status: "unavailable", reason: "claim_failed" };
  try { outcome = await settle(); return outcome; }
  finally {
    const moved = outcome.status === "settled" && (outcome.reply.credited.length > 0 || outcome.reply.refunded.length > 0);
    pace.gap = moved ? 0 : Math.min(CLAIM_GAP_MAX_MS, pace.gap === 0 ? CLAIM_GAP_MS : pace.gap * 2);
    pace.next_at = Date.now() + pace.gap; pace.running = false;
  }
}
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
/** Every pack line of both currencies (two primary key ranges). */
const bundleLines = (storage: DurableObjectStorage): Line[] => CURRENCIES.flatMap(currency => ledgerLines(storage, bundleKey("", currency), 1024));
const refundLines = (storage: DurableObjectStorage): Line[] => CURRENCIES.flatMap(currency => ledgerLines(storage, bundleRefundKey("", currency), 1024));
const currencyOfLine = (line: Line): Currency => currencyOfKey(line.key);

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
/** A paid line's refund key: `bundlerefund:` with the same suffix and currency, whichever form the line has. */
const refundKeyOf = (line: Line) => bundleRefundKey(idOfKey(line.key), currencyOfLine(line));

/** Whether the player has ever been paid for a pack of `currency` (either, when absent): only then does the wallet read check for refunds. */
export function hasBundles(storage: DurableObjectStorage, currency?: Currency): boolean {
  return (currency ? [currency] : CURRENCIES).some(each => ledgerLines(storage, bundleKey("", each), 1).length > 0);
}

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
    const { bundle, order, purchase_id: id, environment } = line.detail;
    if (shown.has(line.key) || back.has(refundKeyOf(line)) || !(BUNDLE_KEYS as readonly unknown[]).includes(bundle)) return [];
    return [{ id: typeof id === "string" ? id : idOfKey(line.key), bundle: bundle as BundleKey, order: typeof order === "string" ? order : "", ...(environment === "sandbox" ? { sandbox: true } : {}) }];
  });
  if (asks.length <= MAX_BUNDLE_LOOKUPS) return asks;
  const start = (Math.floor(now / DAY_MS) * MAX_BUNDLE_LOOKUPS) % asks.length;
  return Array.from({ length: MAX_BUNDLE_LOOKUPS }, (_, index) => asks[(start + index) % asks.length]);
}

/** A looked-up refund as the plan reads it: the ledger's own purchase, refunded. */
const takenBack = (ask: BundleAsk): BundlePurchase => ({ id: ask.id, bundle: ask.bundle, refunded: true, quantity: 1, order: ask.order, usd_cents: 0, purchased_at: 0, ...(ask.sandbox ? { sandbox: true as const } : {}) });

/** The orders a read shows refunded: none of them is paid on that read, whatever order its records come in. */
const refundedOrders = (purchases: readonly BundlePurchase[]) => new Set(purchases.flatMap(purchase => purchase.refunded && purchase.order ? [purchase.order] : []));

/**
 * The plan for one read, from the ledger as stored now: what to pay and what to take back. `held` is whether
 * this player holds an order (PollenClaims). Two records of one order in one read pay or take back once, and an
 * order any record shows refunded is never paid.
 */
export function planBundles(purchases: readonly BundlePurchase[], held: (order: string) => boolean, lines: readonly Line[], refunded: ReadonlySet<string>, giftOpen: Readonly<Record<Currency, boolean>>, bundles: Bundles = BUNDLES): BundlePlan {
  const plan: BundlePlan = { entries: [], credited: [], refunds: [], fruitCredited: [], fruitRefunds: [] };
  const paid = paidIndex(lines), back = new Set(refunded), gone = refundedOrders(purchases);
  const open = { ...giftOpen };
  for (const purchase of purchases) {
    const prior = paidLine(purchase, paid), currency = bundles.bundles[purchase.bundle].currency;
    if (purchase.refunded) {
      if (!prior || back.has(refundKeyOf(prior))) continue;
      back.add(refundKeyOf(prior));
      const order = typeof prior.detail.order === "string" && prior.detail.order ? prior.detail.order : purchase.order;
      const fruit = currencyOfLine(prior) === "fruits";
      plan.entries.push({ key: refundKeyOf(prior), kind: fruit ? "fruitbundlerefund" : "bundlerefund", amount: -prior.amount,
        detail: { bundle: purchase.bundle, purchase_id: purchase.id, order, usd_cents: Number(prior.detail.usd_cents ?? purchase.usd_cents), refunds: prior.key } });
      (fruit ? plan.fruitRefunds : plan.refunds).push({ bundle: purchase.bundle, amount: prior.amount, ...receiptOf(order), key: refundKeyOf(prior) });
      continue;
    }
    if (prior || !purchase.order || gone.has(purchase.order) || !held(purchase.order)) continue;
    const amount = bundles.bundles[purchase.bundle].amount * purchase.quantity, gift = open[currency] ? firstGift(purchase.bundle, bundles) : 0;
    // Only the first pack a player ever buys in a currency can carry its gift, whatever the percent was then.
    open[currency] = false;
    const line: Line = { key: bundleKey(purchase.order, currency), amount: amount + gift,
      detail: { bundle: purchase.bundle, purchase_id: purchase.id, order: purchase.order, usd_cents: purchase.usd_cents, first_gift: gift, quantity: purchase.quantity, purchased_at: purchase.purchased_at, ...(purchase.sandbox ? { environment: "sandbox" } : {}) } };
    paid.byOrder.set(purchase.order, line); paid.byKey.set(line.key, line);
    plan.entries.push({ ...line, kind: currency === "fruits" ? "fruitbundle" : "bundle" });
    const receipt = { bundle: purchase.bundle, first_gift: gift, ...receiptOf(purchase.order), purchased_at: purchase.purchased_at, usd_cents: purchase.usd_cents };
    if (currency === "fruits") plan.fruitCredited.push({ ...receipt, fruits: amount }); else plan.credited.push({ ...receipt, pollen: amount });
  }
  return plan;
}
/** One read's plan; each refund names its ledger key (`key`), dropped from the reply. */
export type BundlePlan = { entries: LedgerEntry[]; credited: BundleCredit[]; refunds: (BundleRefund & { key: string })[]; fruitCredited: FruitCredit[]; fruitRefunds: (BundleRefund & { key: string })[] };

/**
 * Reads RevenueCat and pays or takes back what is due. `active` re-checks the identity inside the
 * transaction. Never throws for a provider or claims failure ("unavailable": nothing is written).
 */
export async function settleBundles(storage: DurableObjectStorage, now: number, active: () => boolean, deps: BundleDeps, rates: Rates = RATES, bundles: Bundles = BUNDLES): Promise<BundleOutcome> {
  const read = await deps.read();
  if (!read.ok) { paused.set(storage, now + BUNDLE_OUTAGE_PAUSE_MS); return { status: "unavailable", reason: read.reason }; }
  // While Fruits are off a Fruit pack waits unpaid (as a Pollen bundle waits for a store that sells), so nothing Fruit is
  // written; a refund of one already paid is still taken back.
  const listed = deps.fruits ? read.purchases : read.purchases.filter(purchase => purchase.refunded || bundles.bundles[purchase.bundle].currency !== "fruits");
  const asks = missingBundles(storage, listed, now);
  let moved: BundlePurchase[] = [], lookupFailed: string | null = null;
  if (asks.length && deps.lookup) {
    const found = await deps.lookup(asks);
    if (found.ok) moved = asks.filter(ask => found.refunded.includes(ask.id)).map(takenBack);
    else lookupFailed = found.reason;
  }
  // Without lookups made (the claim route, or a failed lookup) a missing bundle leaves the check due, so the wallet read looks it up again.
  const checked = asks.length === 0 || (deps.lookup !== undefined && lookupFailed === null);
  // Orders new to this player, each once; at most MAX_CLAIM_KEYS at a time, a longer list waits for the next call.
  const before = paidIndex(bundleLines(storage)), gone = refundedOrders(listed), fresh = new Map<string, BundlePurchase>();
  for (const purchase of listed)
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
    const giftOpen = { pollen: !lines.some(line => currencyOfLine(line) === "pollen"), fruits: !lines.some(line => currencyOfLine(line) === "fruits") };
    const plan = planBundles([...listed, ...moved], order => answers[order] === true, lines, refunded, giftOpen, bundles);
    // A Fruit refund that finds those Fruits already turned into Pollen takes the shortfall back as Pollen (fruit-ops.ts).
    const taken = withReclaim(storage, plan.entries);
    applyLedger(storage, taken.entries, now, rates);
    // Only the daily check notes its time: a claim that finds nothing new writes no row.
    if (checked && deps.lookup) noteCheck(storage, now);
    const strip = <T extends { key: string }>({ key: _, ...rest }: T) => rest;
    const fruity = plan.fruitCredited.length > 0 || plan.fruitRefunds.length > 0 || hasBundles(storage, "fruits");
    outcome = { status: "settled", reply: { schema_version: 1, balance: walletBalance(storage, now, rates), credited: plan.credited, refunded: plan.refunds.map(strip), pending: false,
      ...(fruity ? { fruit_credited: plan.fruitCredited, fruit_refunded: plan.fruitRefunds.map(refund => ({ ...strip(refund), pollen_taken: taken.pollen.get(refund.key) ?? 0 })), fruit_balance: purse(storage, "fruits").balance } : {}) },
      ...(lookupFailed ? { lookup_failed: lookupFailed } : {}) };
  });
  if (lookupFailed) paused.set(storage, now + BUNDLE_OUTAGE_PAUSE_MS); else paused.delete(storage);
  return outcome;
}

/** GET /v1/pollen's bundles part. Read only; never throws. */
export function bundlesView(storage: DurableObjectStorage, bundles: Bundles = BUNDLES): BundlesView {
  const percent = bundles.first_bonus_percent.pollen;
  try {
    // The same total the history shows (wallet.ts purchaseLines).
    return { first_gift: percent > 0 && !hasBundles(storage, "pollen"), first_gift_percent: percent, spent_usd_cents: purchaseLines(storage).spent_usd_cents ?? 0 };
  } catch { return { first_gift: false, first_gift_percent: percent, spent_usd_cents: 0 }; }
}

/** Account erasure: the check time goes with the wallet (its ledger rows are the wallet's). */
export function dropBundles(storage: DurableObjectStorage): void {
  for (const table of POLLEN_BUNDLE_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
  known.delete(storage); paused.delete(storage); forgetClaimPace(storage);
}
