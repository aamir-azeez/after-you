import { POLLEN_GRANT_TABLES } from "../storage-schema";
import { DAY_MS, RATES, type Rates } from "./rates";
import { LIFETIME_KEY, anniversary, claimsNeeded, grantDue, ladder, movedSubs, planGrant, purchaseClaimKey, refundKey, subscriptionClaimKey, validGrant, type ClaimAnswer, type GrantHint, type GrantState, type MovedSub, type PaidInstalment } from "./grant";
import { applyLedger, fullJourneyUntil, inLedger, ledgerLine, ledgerLines, noteFullJourney, type LedgerEntry } from "./wallet";
import type { GrantRefund, Instalment } from "./grant";
import { currencyOfKey, keyIn } from "./currency";
import { FRUIT_RULES, fruitInstalment, type FruitRules } from "./fruits";
import { withReclaim } from "./fruit-ops";
import type { GrantLookup, GrantRead } from "./grant-provider";
import { MAX_BUNDLE_LOOKUPS } from "./bundle-settle";

/**
 * The monthly grant in the player's own Player Durable Object (POLLEN_GRANT), run inside the wallet
 * read (GET /v1/pollen), which is already a Player request:
 *
 * 1. A date check on the stored state and the phone's hint (grant.ts grantDue). Nothing is due: nothing
 *    else happens, no provider call and no write. A hint is how a subscriber whose Full Journey end was
 *    never noted (no hosting check since they bought) starts: at most one read a day while the phone says
 *    it has Full Journey, one per BOUGHT_GAP_MS right after a purchase, and one ever on a legacy app.
 * 2. Due: one RevenueCat read from inside this call (an outbound subrequest, not a DO request), and
 *    one PollenClaims request (claims.ts) for the listed subscriptions that can give cover.
 * 3. After those awaits, one synchronous transaction plans again from the state as stored now (another
 *    read may have paid in between), pays each instalment by its `grant:<anchor>:<n>` key through the
 *    wallet's ledger, takes back refunded ones, and saves the state. Two overlapping reads pay once.
 *
 * A failed provider or claims call pays nothing and writes nothing; a later read tries again after a
 * short in-memory pause. Reads that overlap while one is out share its outcome, so a burst of wallet
 * reads costs one provider read. Storage: pollen_grant (storage-schema.ts POLLEN_GRANT_TABLES), one row.
 */
export type GrantDeps = {
  /** The player's counted subscriptions (grant-provider.ts readGrant); `lifetime`: also look for the old Lifetime unlock. */
  read: (lifetime: boolean) => Promise<GrantRead>;
  /** PollenClaims answers by claim key, or null when it could not be asked. */
  claim: (keys: string[]) => Promise<Record<string, ClaimAnswer> | null>;
  /**
   * Told what this settle newly paid (the ledger's fresh positive grant lines, never a line another read
   * already paid), after its transaction committed. Only the caller that started the settle is told: a read
   * that joins one already out takes its outcome only.
   */
  paid?: (lines: readonly { key: string; amount: number }[]) => void;
  /** Subscriptions paid here that moved away, looked up by id (grant-provider.ts lookupGrantSubs). Absent: none are looked up. */
  lookup?: (ids: string[]) => Promise<GrantLookup>;
  /** Fruits are on (features.ts fruitsOn): each instalment paid also pays its Fruits, and the first the welcome basket. A refund takes back Fruit lines either way. */
  fruits?: boolean;
};

/**
 * The Fruit lines of one settle (PLAN v2 section 7): beside each Pollen instalment paid while Fruits are on,
 * `fruit:grant:<anchor>:<n>` at the Fruit ladder's step for the same month count (fruits.ts fruitInstalment), and once per
 * player `fruit:welcome` with the first of them (a subscriber already on Full Journey gets it with their next instalment;
 * months paid before Fruits pay no Fruits, by the owner's call: no back pay). A refunded instalment takes back the Fruit
 * line paid with it, if any, under `fruit:grantrefund:<anchor>:<n>`, and the welcome basket if it came with that month.
 */
export function fruitGrantEntries(storage: DurableObjectStorage, pay: readonly Instalment[], refunds: readonly GrantRefund[], fruits: boolean, now: number, rules: FruitRules = FRUIT_RULES): LedgerEntry[] {
  const entries: LedgerEntry[] = [];
  const welcome = ledgerLine(storage, keyIn("fruits", WELCOME));
  for (const refund of refunds) {
    const line = ledgerLine(storage, keyIn("fruits", refund.refunds));
    if (line) entries.push({ key: keyIn("fruits", refund.key), kind: "fruitgrantrefund", amount: -line.amount, detail: { refunds: line.key, sub: refund.sub } });
    if (welcome && welcome.detail.with === refund.refunds) entries.push({ key: keyIn("fruits", WELCOME_REFUND), kind: "fruitwelcomerefund", amount: -welcome.amount, detail: { refunds: welcome.key } });
  }
  // A catch-up after a long absence pays Fruits only for months due within FRUIT_CATCH_UP_MS: months that fell due
  // before Fruits went on never pay them (no back pay).
  const recent = pay.filter(paid => paid.due >= now - FRUIT_CATCH_UP_MS);
  if (!fruits || recent.length === 0) return entries;
  for (const paid of recent) entries.push({ key: keyIn("fruits", paid.key), kind: "fruitgrant", amount: fruitInstalment(paid.step, rules), detail: { anchor: paid.anchor, n: paid.n, due: paid.due, step: paid.step, sub: paid.sub } });
  if (!welcome && rules.grant.welcome > 0) entries.push({ key: keyIn("fruits", WELCOME), kind: "fruitwelcome", amount: rules.grant.welcome, detail: { with: recent[0].key } });
  return entries;
}
const WELCOME = "welcome", WELCOME_REFUND = "welcomerefund";
/** How far back a catch-up pays Fruits: about one month. */
export const FRUIT_CATCH_UP_MS = 31 * DAY_MS;

/** The wallet read's Fruit part of the grant (fruit-ops.ts fruitsView): the next instalment's Fruits, the top, and what came with the newest instalment. */
export type FruitGrantView = { next: number; top: number; welcome: number; welcome_paid: boolean; latest?: { amount: number; welcome: number; at: number } };
export function fruitGrantView(storage: DurableObjectStorage, rules: FruitRules = FRUIT_RULES): FruitGrantView | undefined {
  try {
    const state = storedGrant(storage);
    if (state === null) return undefined;
    const welcome = ledgerLine(storage, keyIn("fruits", WELCOME));
    const view: FruitGrantView = { next: fruitInstalment(state.months + 1, rules), top: rules.grant.top, welcome: rules.grant.welcome, welcome_paid: welcome !== null };
    const latest = state.latest ? ledgerLine(storage, keyIn("fruits", state.latest.key)) : null;
    if (latest) view.latest = { amount: latest.amount, welcome: welcome && welcome.detail.with === state.latest!.key ? welcome.amount : 0, at: latest.at };
    return view;
  } catch { return undefined; }
}
/** What GET /v1/pollen adds for a player with a grant: the loyalty count, the next step, the top step and the newest instalment. */
export type GrantView = { months: number; next: number; top: number; latest?: { key: string; amount: number; at: number } };
export type GrantOutcome = "not_due" | "paused" | "unavailable" | "settled";

/** A Full Journey with no end: the old Lifetime unlock (routes.ts NO_END). */
const LIFETIME_END = 8_640_000_000_000_000;
/** After a failed provider or claims call, the next read waits this long (memory only, so a new instance may try at once). */
export const OUTAGE_PAUSE_MS = 5 * 60_000;
/** While an instalment waits on grace, a hold or a renewal not seen yet, a read looks again after this. */
export const WAIT_PAUSE_MS = 60 * 60_000;

const [GRANT] = POLLEN_GRANT_TABLES;
const known = new WeakMap<DurableObjectStorage, boolean>();
const paused = new WeakMap<DurableObjectStorage, number>();
const running = new WeakMap<DurableObjectStorage, Promise<GrantOutcome>>();
function present(storage: DurableObjectStorage): boolean {
  let found = known.get(storage);
  if (found === undefined) {
    found = storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", GRANT.name).toArray().length > 0;
    known.set(storage, found);
  }
  return found;
}

/** The stored state, or null. A state that fails its check stops the grant rather than being replaced. */
export function storedGrant(storage: DurableObjectStorage): GrantState | null {
  if (!present(storage)) return null;
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM pollen_grant WHERE id=1").toArray()[0];
  if (!row) return null;
  const value: unknown = JSON.parse(row.data);
  if (!validGrant(value)) throw new Error("unsupported_pollen_grant");
  return value;
}
function saveGrant(storage: DurableObjectStorage, state: GrantState): void {
  if (!present(storage)) { storage.sql.exec(GRANT.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ")); known.delete(storage); }
  storage.sql.exec("INSERT OR REPLACE INTO pollen_grant VALUES (1,?)", JSON.stringify(state));
}

/** The instalments a subscription paid with due dates in [from, to) that no refund took back yet. */
function paidBy(storage: DurableObjectStorage) {
  return (sub: string, from: number, to: number): PaidInstalment[] => ledgerLines(storage, "grant:", 512).flatMap(line => {
    const { anchor, n, due } = line.detail as { anchor?: unknown; n?: unknown; due?: unknown };
    if (line.detail.sub !== sub || typeof anchor !== "number" || typeof n !== "number" || typeof due !== "number" || due < from || due >= to || inLedger(storage, refundKey(anchor, n))) return [];
    return [{ key: line.key, amount: line.amount, anchor, n, due, sub }];
  });
}

/**
 * Pays what is due, if anything. `active` re-checks the identity inside the transaction; `hint` is what
 * the phone said (grant.ts GrantHint). Never throws for a provider or claims failure; a stored state
 * that fails its check throws, as the wallet does.
 */
export async function settleGrant(storage: DurableObjectStorage, now: number, active: () => boolean, deps: GrantDeps, hint: GrantHint = "none", rates: Rates = RATES): Promise<GrantOutcome> {
  if ((paused.get(storage) ?? 0) > now) return "paused";
  // One provider read at a time per Player: a read that comes in while one is out takes its outcome.
  const busy = running.get(storage);
  if (busy) return busy;
  const before = storedGrant(storage), fjUntil = fullJourneyUntil(storage);
  if (!grantDue(before, fjUntil, now, hint)) return "not_due";
  const run: Promise<GrantOutcome> = settleDue(storage, now, active, deps, before, fjUntil, rates).finally(() => { if (running.get(storage) === run) running.delete(storage); });
  running.set(storage, run);
  return run;
}

async function settleDue(storage: DurableObjectStorage, now: number, active: () => boolean, deps: GrantDeps, before: GrantState | null, fjUntil: number, rates: Rates): Promise<GrantOutcome> {
  const read = await deps.read(fjUntil >= LIFETIME_END && !before?.lifetime);
  if (!read.ok) { paused.set(storage, now + OUTAGE_PAUSE_MS); return "unavailable"; }
  const keys = [...claimsNeeded(before, read.subs).map(subscriptionClaimKey), ...(read.lifetime && !before?.lifetime ? [purchaseClaimKey(read.lifetime.id)] : [])];
  const answers = keys.length ? await deps.claim(keys) : {};
  if (answers === null) { paused.set(storage, now + OUTAGE_PAUSE_MS); return "unavailable"; }
  const subClaims = Object.fromEntries(read.subs.filter(sub => answers[subscriptionClaimKey(sub.id)]).map(sub => [sub.id, answers[subscriptionClaimKey(sub.id)]]));
  const lifetimeClaim = read.lifetime ? answers[purchaseClaimKey(read.lifetime.id)] : undefined;
  // Moved subscriptions, as bundle-settle.ts missingBundles bounds its lookups: at most MAX_BUNDLE_LOOKUPS, a different
  // window each day when there are more. A failed lookup takes nothing back; the daily look again (grant.ts) retries it.
  const missing = deps.lookup ? movedSubs(before, read.subs, paidBy(storage), now) : [];
  const start = (Math.floor(now / DAY_MS) * MAX_BUNDLE_LOOKUPS) % Math.max(1, missing.length);
  const asks = missing.length <= MAX_BUNDLE_LOOKUPS ? missing : Array.from({ length: MAX_BUNDLE_LOOKUPS }, (_, index) => missing[(start + index) % missing.length]);
  const looked = asks.length ? await deps.lookup!(asks) : null;
  const moved: MovedSub[] = looked?.ok ? looked.found : [];
  let waiting = false, alive = false, newly: LedgerEntry[] = [];
  storage.transactionSync(() => {
    if (!active()) return;
    alive = true;
    // Planned again from the state as stored now: what an overlapping read paid is never paid twice.
    const fresh = storedGrant(storage);
    const plan = planGrant(fresh, read.subs, subClaims, now, paidBy(storage), lifetimeClaim ? { claim: lifetimeClaim } : null, rates, moved);
    const entries: LedgerEntry[] = [
      ...plan.refunds.map(refund => ({ key: refund.key, kind: "grantrefund", amount: -refund.amount, detail: { refunds: refund.refunds, sub: refund.sub } })),
      ...plan.pay.map(paid => ({ key: paid.key, kind: "grant", amount: paid.amount, detail: { anchor: paid.anchor, n: paid.n, due: paid.due, step: paid.step, sub: paid.sub } })),
      ...(plan.lifetime > 0 ? [{ key: LIFETIME_KEY, kind: "grant", amount: plan.lifetime, detail: { lifetime: true } }] : []),
      ...fruitGrantEntries(storage, plan.pay, plan.refunds, deps.fruits === true, now)
    ];
    // A Fruit take-back the balance can't cover, because those Fruits were turned into Pollen, takes them back as Pollen (fruit-ops.ts).
    const applied = applyLedger(storage, withReclaim(storage, entries).entries, now, rates);
    // The Pollen lines alone set `latest` and the push, as before Fruits: older apps read them as Pollen.
    const paid = applied.filter(entry => entry.amount > 0 && currencyOfKey(entry.key) === "pollen");
    if (paid.length) plan.state.latest = { key: paid[paid.length - 1].key, amount: paid[paid.length - 1].amount, at: now };
    saveGrant(storage, plan.state);
    waiting = plan.state.live && anniversary(plan.state.anchor, plan.state.next) <= now;
    newly = paid;
  });
  // An erasure that finished during the awaits leaves nothing to note on.
  if (!alive) return "settled";
  if (newly.length && deps.paid) {
    try { deps.paid(newly.map(line => ({ key: line.key, amount: line.amount }))); } catch { /* A listener never undoes or fails a payment. */ }
  }
  if (waiting) paused.set(storage, now + WAIT_PAUSE_MS);
  // The read also refreshes the Full Journey end the room boost uses, but only ever later: a gift or
  // another entitlement this read does not count must not end a boost (refunds move it back in Phase 6).
  const access = Math.max(0, ...read.subs.map(sub => sub.access_until));
  if (access > fjUntil && fjUntil < LIFETIME_END) noteFullJourney(storage, access, now);
  return "settled";
}

/** GET /v1/pollen's grant part, or undefined for a player with no grant state. Read only; never throws. */
export function grantView(storage: DurableObjectStorage, rates: Rates = RATES): GrantView | undefined {
  try {
    const state = storedGrant(storage);
    if (state === null || state.latest === null) return undefined;
    return { ...ladder(state, rates), latest: state.latest };
  } catch { return undefined; }
}

/** Account erasure: the grant state goes with the wallet (its ledger rows are the wallet's). */
export function dropGrant(storage: DurableObjectStorage): void {
  for (const table of POLLEN_GRANT_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
  known.delete(storage); paused.delete(storage); running.delete(storage);
}
