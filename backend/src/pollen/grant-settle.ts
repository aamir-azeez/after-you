import { POLLEN_GRANT_TABLES } from "../storage-schema";
import { RATES, type Rates } from "./rates";
import { LIFETIME_KEY, anniversary, claimsNeeded, grantDue, ladder, planGrant, refundKey, validGrant, type ClaimAnswer, type GrantState, type PaidInstalment } from "./grant";
import { applyLedger, fullJourneyUntil, inLedger, ledgerLines, noteFullJourney, type LedgerEntry } from "./wallet";
import { purchaseClaimKey, subscriptionClaimKey } from "./claims";
import type { GrantRead } from "./grant-provider";

/**
 * The monthly grant in the player's own Player Durable Object (POLLEN_GRANT), run inside the wallet
 * read (GET /v1/pollen), which is already a Player request:
 *
 * 1. A date check on the stored state (grant.ts grantDue). Nothing is due: nothing else happens, no
 *    provider call and no write. A player who never subscribed has no state and no Full Journey end.
 * 2. Due: one RevenueCat read from inside this call (an outbound subrequest, not a DO request), and,
 *    for a subscription new to this identity, one PollenClaims request (claims.ts).
 * 3. After those awaits, one synchronous transaction plans again from the state as stored now (another
 *    read may have paid in between), pays each instalment by its `grant:<anchor>:<n>` key through the
 *    wallet's ledger, takes back refunded ones, and saves the state. Two overlapping reads pay once.
 *
 * A failed provider or claims call pays nothing and writes nothing; a later read tries again after a
 * short in-memory pause. Storage: pollen_grant (storage-schema.ts POLLEN_GRANT_TABLES), one row.
 */
export type GrantDeps = {
  /** The player's counted subscriptions (grant-provider.ts readGrant); `lifetime`: also look for the old Lifetime unlock. */
  read: (lifetime: boolean) => Promise<GrantRead>;
  /** PollenClaims answers by claim key, or null when it could not be asked. */
  claim: (keys: string[]) => Promise<Record<string, ClaimAnswer> | null>;
};
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
  return (sub: string, from: number, to: number): PaidInstalment[] => ledgerLines(storage, "grant", 512).flatMap(line => {
    const { anchor, n, due } = line.detail as { anchor?: unknown; n?: unknown; due?: unknown };
    if (line.detail.sub !== sub || typeof anchor !== "number" || typeof n !== "number" || typeof due !== "number" || due < from || due >= to || inLedger(storage, refundKey(anchor, n))) return [];
    return [{ key: line.key, amount: line.amount, anchor, n, due, sub }];
  });
}

/**
 * Pays what is due, if anything. `active` re-checks the identity inside the transaction. Never throws
 * for a provider or claims failure; a stored state that fails its check throws, as the wallet does.
 */
export async function settleGrant(storage: DurableObjectStorage, now: number, active: () => boolean, deps: GrantDeps, rates: Rates = RATES): Promise<GrantOutcome> {
  if ((paused.get(storage) ?? 0) > now) return "paused";
  const before = storedGrant(storage), fjUntil = fullJourneyUntil(storage);
  if (!grantDue(before, fjUntil, now)) return "not_due";
  const read = await deps.read(fjUntil >= LIFETIME_END && !before?.lifetime);
  if (!read.ok) { paused.set(storage, now + OUTAGE_PAUSE_MS); return "unavailable"; }
  const keys = [...claimsNeeded(before, read.subs, now).map(subscriptionClaimKey), ...(read.lifetime && !before?.lifetime ? [purchaseClaimKey(read.lifetime.id)] : [])];
  const answers = keys.length ? await deps.claim(keys) : {};
  if (answers === null) { paused.set(storage, now + OUTAGE_PAUSE_MS); return "unavailable"; }
  const subClaims = Object.fromEntries(read.subs.filter(sub => answers[subscriptionClaimKey(sub.id)]).map(sub => [sub.id, answers[subscriptionClaimKey(sub.id)]]));
  const lifetimeClaim = read.lifetime ? answers[purchaseClaimKey(read.lifetime.id)] : undefined;
  let waiting = false;
  storage.transactionSync(() => {
    if (!active()) return;
    // Planned again from the state as stored now: what an overlapping read paid is never paid twice.
    const fresh = storedGrant(storage);
    const plan = planGrant(fresh, read.subs, subClaims, now, paidBy(storage), lifetimeClaim ? { claim: lifetimeClaim } : null, rates);
    const entries: LedgerEntry[] = [
      ...plan.refunds.map(refund => ({ key: refund.key, kind: "grantrefund", amount: -refund.amount, detail: { refunds: refund.refunds, sub: refund.sub } })),
      ...plan.pay.map(paid => ({ key: paid.key, kind: "grant", amount: paid.amount, detail: { anchor: paid.anchor, n: paid.n, due: paid.due, step: paid.step, sub: paid.sub } })),
      ...(plan.lifetime > 0 ? [{ key: LIFETIME_KEY, kind: "grant", amount: plan.lifetime, detail: { lifetime: true } }] : [])
    ];
    applyLedger(storage, entries, now, rates);
    saveGrant(storage, plan.state);
    waiting = plan.state.live && anniversary(plan.state.anchor, plan.state.next) <= now;
  });
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
    if (state === null || (state.months === 0 && !state.lifetime)) return undefined;
    const latest = ledgerLines(storage, "grant", 1)[0];
    return { ...ladder(state, rates), ...(latest ? { latest: { key: latest.key, amount: latest.amount, at: latest.at } } : {}) };
  } catch { return undefined; }
}

/** Account erasure: the grant state goes with the wallet (its ledger rows are the wallet's). */
export function dropGrant(storage: DurableObjectStorage): void {
  for (const table of POLLEN_GRANT_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
  known.delete(storage); paused.delete(storage);
}
