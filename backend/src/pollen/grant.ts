import { isObject } from "../protocol";
import { DAY_MS, RATES, type Rates } from "./rates";

/**
 * The Full Journey monthly grant (POLLEN-RULES.md "The Full Journey grant"), as pure rules over a
 * player's grant state and one read of their subscriptions. No storage, no clock, no provider:
 * grant-settle.ts reads and writes, grant-provider.ts reads RevenueCat, claims.ts is the global check.
 *
 * - The ladder: month n pays min(first + step x (n - 1), top). n counts every instalment ever paid
 *   to this identity (`months`), on either plan; cancelling never resets it, and a refunded month
 *   moves it back by one. A recovered identity is the same Player, so it keeps the count.
 * - The anchor: the start of the first paid period of a run of paid cover. Instalment k of an anchor
 *   falls due on its k-th monthly anniversary (k = 0 at the anchor itself): the anchor's day of the
 *   month at the anchor's time of day, or the month's last day when that day does not exist there.
 *   Each is computed from the anchor, never from the previous due date (31 Jan, 28 or 29 Feb, 31 Mar).
 * - An instalment is paid once the paid cover of a subscription RevenueCat still lists for this App
 *   User ID holds its due date. Its key is
 *   `grant:<anchor ms>:<k + 1>`, so a switch of plan inside one anchor never pays a month twice.
 * - Cover comes only from periods RevenueCat lists as paid for this App User ID: never a trial, a
 *   grace period, an account hold or a tester or review grant (grant-provider.ts has its own status
 *   filter for that; the hosting check admits trials and testers). A due date with no cover while a
 *   subscription is in grace, on hold or about to renew waits; with none of those the anchor lapses,
 *   and the next paid cover starts a new anchor with the same count. A paid period that starts after
 *   a gap in cover (a resume from a pause or an account hold) restarts that subscription's cover, so
 *   the months in between are never paid (when a read saw the hold); the month that ends in recovery
 *   is paid at the recovery.
 * - Every read that may pay asks the global PollenClaims check (claims.ts) about each listed
 *   subscription. One that came to this identity from another (a store restore transfer), or came
 *   back after it moved away, gives cover only from a month after that move, so a month is never
 *   paid to both identities, however often it moves.
 * - A refund: a subscription that ended before the end of the period it was paid through, with no
 *   other subscription already running from that end (a plan switch), takes back each instalment it
 *   paid in that period and moves the count back by one for each.
 */
export const SWITCH_GAP_MS = DAY_MS;
/** A plan switch: the new subscription started this close to (or before) the old one's early end. A rebuy after a refund starts later. */
export const CARRY_GAP_MS = 5 * 60_000;
/** An end this much before the period's recorded end reads as a refund, not a store's rounding. */
export const REFUND_MARGIN_MS = DAY_MS;
/** With nothing to watch while a Full Journey end is noted (a lifetime unlock, another store), look again at most daily. */
export const RETRY_MS = DAY_MS;
/** Instalments one read may pay (catch-up after a long absence); the rest come on the next read. */
export const MAX_CATCH_UP = 48;
/** Subscriptions kept per identity, newest cover first. */
export const MAX_SUBS = 8;
const MAX_TIME = 8_640_000_000_000_000;

export type GrantStatus = "paid" | "trial" | "grace" | "hold" | "ended";
/**
 * One subscription as grant-provider.ts reads it. `started_at`: when it first started (RevenueCat
 * starts_at); `access_until`: the end of its access while it gives any, else 0.
 */
export type GrantSub = { id: string; status: GrantStatus; started_at: number; period_start: number; period_end: number; ends_at: number; renews: boolean; access_until: number };
/**
 * What this identity knows of a subscription: its cover runs [from, through); `claimed_at` is the
 * PollenClaims answer's `since`; `held`: a read saw it paused or on hold since its last paid period.
 */
export type SubRecord = { from: number; through: number; claimed_at: number; held: boolean };
export type GrantState = {
  schema_version: 1;
  /** Instalments ever paid to this identity, net of refunds. */
  months: number;
  /** The current anchor (ms), 0 before the first; `next`: the index of its next instalment; `live`: false once it lapsed at `lapsed_at`. */
  anchor: number; next: number; live: boolean; lapsed_at: number;
  /** Whether a paid subscription will renew: then a due date is worth a read even before a later Full Journey end is noted. */
  renews: boolean;
  subs: Record<string, SubRecord>;
  /** Read again at this time whatever else holds (a trial's end, a moved subscription's cover start); 0 for none. */
  recheck_at: number;
  /** No read before this (after a read that found nothing to watch). */
  retry_at: number;
  /** The last complete read. */
  checked_at: number;
  /** The Lifetime thank-you was settled (paid, or refused as moved). */
  lifetime: boolean;
  /** The newest instalment paid (or the Lifetime thank-you), for the wallet read: no ledger scan. */
  latest: { key: string; amount: number; at: number } | null;
};
/**
 * PollenClaims' answer for one subscription: `self` while it never moved to this identity from another
 * (this identity was its first holder); `since`: when this identity became its holder. Both stay the
 * same on every repeat, so a retried read plans the same.
 */
export type ClaimAnswer = { self: boolean; since: number };
/** A paid instalment, as the ledger keeps it. */
export type Instalment = { key: string; anchor: number; n: number; due: number; amount: number; step: number; sub: string };
/** A paid instalment found again for a refund: the ledger's key and amount. */
export type PaidInstalment = { key: string; amount: number; anchor: number; n: number; due: number; sub: string };
export type GrantRefund = { key: string; refunds: string; amount: number; sub: string };
export type GrantPlan = { state: GrantState; pay: Instalment[]; refunds: GrantRefund[]; lifetime: number };

const count = (value: unknown, min = 0, max = MAX_TIME): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
export const SUB_ID_PATTERN = /^[A-Za-z0-9_.:-]{1,128}$/;

/** What month n (1-based) of a subscription pays. */
export function instalmentAmount(n: number, rates: Rates = RATES): number {
  return Math.min(rates.grant.first + rates.grant.step * (Math.max(1, n) - 1), rates.grant.top);
}

/** The k-th monthly anniversary of `anchor` (UTC): its day of the month, or the month's last day, at its time of day. */
export function anniversary(anchor: number, k: number): number {
  const at = new Date(anchor), months = at.getUTCMonth() + k;
  const year = at.getUTCFullYear() + Math.floor(months / 12), month = ((months % 12) + 12) % 12;
  const last = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  return Date.UTC(year, month, Math.min(at.getUTCDate(), last), at.getUTCHours(), at.getUTCMinutes(), at.getUTCSeconds(), at.getUTCMilliseconds());
}

export const grantKey = (anchor: number, n: number) => `grant:${anchor}:${n}`;
export const refundKey = (anchor: number, n: number) => `grantrefund:${anchor}:${n}`;
export const LIFETIME_KEY = "grant:lifetime";
/** PollenClaims keys: RevenueCat's subscription id, kept through renewals, and the Lifetime purchase id. */
export const subscriptionClaimKey = (id: string) => `sub:${id}`;
export const purchaseClaimKey = (id: string) => `purchase:${id}`;

export function emptyGrant(): GrantState {
  return { schema_version: 1, months: 0, anchor: 0, next: 0, live: false, lapsed_at: 0, renews: false, subs: {}, recheck_at: 0, retry_at: 0, checked_at: 0, lifetime: false, latest: null };
}

export function validGrant(value: unknown): value is GrantState {
  if (!isObject(value) || Object.keys(value).length !== 13 || value.schema_version !== 1) return false;
  const latest = value.latest;
  if (latest !== null && !(isObject(latest) && Object.keys(latest).length === 3 && typeof latest.key === "string" && /^grant:/.test(latest.key) && count(latest.amount, 1) && count(latest.at))) return false;
  if (!count(value.months, 0, 100_000) || !count(value.anchor) || !count(value.next, 0, 100_000) || typeof value.live !== "boolean" || !count(value.lapsed_at)) return false;
  if (typeof value.renews !== "boolean" || !count(value.recheck_at) || !count(value.retry_at) || !count(value.checked_at) || typeof value.lifetime !== "boolean") return false;
  if (!isObject(value.subs) || Object.keys(value.subs).length > MAX_SUBS) return false;
  return Object.entries(value.subs).every(([id, sub]) => SUB_ID_PATTERN.test(id) && isObject(sub) && Object.keys(sub).length === 4 && count(sub.from) && count(sub.through) && count(sub.claimed_at) && typeof sub.held === "boolean");
}

/**
 * Whether a wallet read should ask RevenueCat now: only when an instalment is due, a trial or a
 * moved subscription's cover is ready to look at, or a Full Journey end is noted with no live anchor.
 * A player who never subscribed (no state, no Full Journey end) never costs a read.
 */
export function grantDue(state: GrantState | null, fjUntil: number, now: number): boolean {
  if (state === null) return fjUntil > now;
  if (now < state.retry_at) return false;
  if (state.recheck_at > 0 && now >= state.recheck_at) return true;
  if (state.live) {
    const due = anniversary(state.anchor, state.next);
    return due <= now && (state.renews || due < Math.max(fjUntil, coverEnd(state)));
  }
  return fjUntil > now;
}
const coverEnd = (state: GrantState) => Object.values(state.subs).reduce((end, sub) => Math.max(end, sub.through), 0);

/**
 * The subscriptions a read needs the PollenClaims answer for: each listed one that can give cover
 * (paid, or a known one that ended and may still owe catch-up). Reads happen only when something is
 * due, so this is about one PollenClaims request per subscriber per month (one request holds them all).
 */
export function claimsNeeded(state: GrantState | null, subs: readonly GrantSub[]): string[] {
  return subs.filter(sub => sub.status === "paid" || (sub.status === "ended" && state?.subs[sub.id])).map(sub => sub.id);
}

/**
 * One read's outcome: the new state, the instalments to pay, the refunds to take back, and the
 * Lifetime thank-you (0 for none). `paidBy(sub, from, to)` lists the instalments a subscription
 * paid with due dates in [from, to) that were not refunded yet (from the ledger). The plan never
 * pays a key twice by itself; the ledger also skips any key it already holds.
 */
export function planGrant(prev: GrantState | null, subs: readonly GrantSub[], claims: Readonly<Record<string, ClaimAnswer>>, now: number,
  paidBy: (sub: string, from: number, to: number) => PaidInstalment[], lifetime: { claim: ClaimAnswer } | null = null, rates: Rates = RATES): GrantPlan {
  const state: GrantState = structuredClone(prev ?? emptyGrant());
  // 1. What each subscription covers for this identity. Cover from a subscription that moved here
  // starts a month after the move (the claim's `since`), so the same answer on a retry plans the same.
  for (const sub of subs) {
    const known = state.subs[sub.id], claim = claims[sub.id];
    if (!known) {
      if (sub.status !== "paid" || !claim) continue;
      state.subs[sub.id] = { from: claim.self ? sub.period_start : Math.max(sub.period_start, anniversary(claim.since, 1)), through: paidTo(sub), claimed_at: claim.since, held: false };
      continue;
    }
    // It moved away and came back since this identity last held it: cover only from a month after it came back.
    if (claim && claim.since !== known.claimed_at) { known.from = Math.max(known.from, anniversary(claim.since, 1)); known.claimed_at = claim.since; }
    if (sub.status === "hold") known.held = true;
    if (sub.status !== "paid") continue;
    // A resume from a pause or a hold that a read saw: the months in the gap are never covered. (A gap
    // with no hold seen is a plan renewed while nobody read: those months are caught up.)
    if (known.held && sub.period_start > known.through + SWITCH_GAP_MS) known.from = Math.max(known.from, sub.period_start);
    known.held = false;
    known.through = Math.max(known.through, paidTo(sub));
  }
  // Cover counts only from a subscription this read still lists for this App User ID: one moved away pays here no more.
  const listed = new Set(subs.map(sub => sub.id));
  const covers = () => Object.entries(state.subs).filter(([id]) => listed.has(id));
  // 2. Refunds: an end before the recorded period end, with nothing carrying on from it.
  const refunds: GrantRefund[] = [];
  for (const sub of subs) {
    const known = state.subs[sub.id];
    if (!known || sub.status !== "ended") continue;
    const early = sub.ends_at + REFUND_MARGIN_MS < known.through;
    // A switch starts its new subscription at (or before) the old one's end; a rebuy after a refund starts later.
    const carried = subs.some(other => other.id !== sub.id && state.subs[other.id] && other.started_at <= sub.ends_at + CARRY_GAP_MS && state.subs[other.id].through > sub.ends_at);
    if (early && !carried) {
      for (const paid of paidBy(sub.id, sub.period_start, known.through)) {
        refunds.push({ key: refundKey(paid.anchor, paid.n), refunds: paid.key, amount: paid.amount, sub: sub.id });
        state.months = Math.max(0, state.months - 1);
      }
    }
    known.through = Math.min(known.through, Math.max(known.from, sub.ends_at));
  }
  // 3. Instalments, oldest first: catch-up pays each missed month at its own step.
  const pay: Instalment[] = [];
  for (let guard = 0; guard < MAX_CATCH_UP + 2 && pay.length < MAX_CATCH_UP; guard++) {
    if (!state.live) {
      const after = state.anchor === 0 ? -1 : state.lapsed_at;
      const starts = covers().map(([, sub]) => sub).filter(sub => sub.from > after && sub.through > sub.from && sub.from <= now).map(sub => sub.from);
      if (starts.length === 0) break;
      state.anchor = Math.min(...starts); state.next = 0; state.live = true; state.lapsed_at = 0;
    }
    const due = anniversary(state.anchor, state.next);
    if (due > now) break;
    const cover = covers().filter(([, sub]) => sub.from <= due + SWITCH_GAP_MS && sub.through > due).sort(([, a], [, b]) => a.from - b.from)[0];
    if (cover) {
      const n = state.next + 1, step = state.months + 1;
      pay.push({ key: grantKey(state.anchor, n), anchor: state.anchor, n, due, amount: instalmentAmount(step, rates), step, sub: cover[0] });
      state.months++; state.next++;
      continue;
    }
    // No cover yet: wait while a known subscription may still pay for this date (grace, hold, a renewal not seen yet).
    const waiting = subs.some(sub => {
      const known = state.subs[sub.id];
      return known && known.from <= due + SWITCH_GAP_MS && (sub.status === "grace" || sub.status === "hold" || (sub.status === "paid" && sub.renews));
    });
    if (waiting) break;
    state.live = false; state.lapsed_at = due;
  }
  // 4. The Lifetime thank-you, once: paid only to the identity that first claimed the purchase.
  let thanks = 0;
  if (lifetime && !state.lifetime) { state.lifetime = true; thanks = lifetime.claim.self ? rates.grant.lifetime_thanks : 0; }
  // 5. What to watch next.
  state.renews = subs.some(sub => state.subs[sub.id] && sub.status === "paid" && sub.renews);
  const watch = [...subs.filter(sub => sub.status === "trial").map(sub => sub.period_end), ...Object.values(state.subs).filter(sub => sub.from > now).map(sub => sub.from)];
  state.recheck_at = watch.length ? Math.min(...watch) : 0;
  // With no live anchor, nothing new is looked for before what is being watched (or a day): a noted end alone is not news.
  state.retry_at = state.live ? 0 : state.recheck_at || now + RETRY_MS;
  state.checked_at = now;
  // Keep the subscriptions with the newest cover.
  state.subs = Object.fromEntries(Object.entries(state.subs).sort(([, a], [, b]) => b.through - a.through).slice(0, MAX_SUBS));
  return { state, pay, refunds, lifetime: thanks };
}

/** The end of a paid subscription's paid cover: its current period, or the next one already renewed. */
function paidTo(sub: GrantSub): number { return Math.max(sub.period_end, sub.ends_at); }

/** The step the next instalment pays, and the top step, for the wallet read. */
export function ladder(state: GrantState, rates: Rates = RATES): { months: number; next: number; top: number } {
  return { months: state.months, next: instalmentAmount(state.months + 1, rates), top: rates.grant.top };
}
