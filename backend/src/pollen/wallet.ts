import { fail, isObject, ok, type Outcome } from "../protocol";
import type { ServerVars } from "../flags";
import { POLLEN_PLAYER_TABLES, POLLEN_WALLET_TABLES, isLazyTable } from "../storage-schema";
import { DAY_MS, RATES, chapterTier, tailLength, type Rates } from "./rates";
import { weekIndex } from "./week";
import { boostPercent, clearPrice, price, type ClearPrice, type TurnPrice } from "./earn";
import { bloomRoll } from "./blooms";
import { validTurnFacts } from "./turn-facts";

/**
 * The Pollen wallet, in the player's own Player Durable Object: the only real balance. Phones keep
 * a copy of the last confirmed answer and the claims they have not sent yet.
 *
 * Storage (created by the first credit or Full Journey note, never by setup):
 * - pollen_wallet, one row: balance, lifetime earned, the turn bank, per-week slots and after-bank
 *   counts for the kept weeks, the player's Full Journey end (fj_until) and the last prune day.
 * - pollen_claims: one row per paid claim, keyed by its idempotency key. A key that is present
 *   answers its first receipt and changes nothing.
 *     turn:<room_id>:<recording_hash>   an accepted turn (pruned after turn_prune_days)
 *     clear:<level_id>                  a chapter's first clear, together or solo (kept)
 *     hardclear:<level_id>              a chapter's first Hard clear together (kept)
 *   A turn that pays nothing writes no row: a turn played before the guest joined (never paid, by its
 *   frozen facts), or one whose week's after-bank turns are used up (that count only grows, and only
 *   a turn of the current week spends the bank).
 *
 * Every check and write of one credit happens in one synchronous transaction, after the only
 * await (the bloom roll), so two credits of the same key can never both pay.
 */
export type WeekState = { slots: string[]; tail: number };
export type WalletState = {
  schema_version: 1; balance: number; earned: number; bank: number; week: number;
  weeks: Record<string, WeekState>; fj_until: number; pruned_day: number;
};
/** `reason`: why a turn paid the after-bank rate. `boost_from`: whose Full Journey boosted it, from the turn player's side. */
/**
 * `reason`: why a turn paid the after-bank rate: its slot was paid this week already (repeat), the
 * bank was empty, or the turn is from an earlier week (late: only a turn of the current week spends
 * the current bank, so no week's turns move onto a later bank). `boost_from`: whose Full Journey
 * boosted it, from the turn player's side.
 */
export type TurnLine = TurnPrice & { reason?: "repeat" | "bank_empty" | "late"; boost_from?: ("you" | "partner")[] };
export type ClearLine = { kind: "clear" | "hardclear"; level_id: string } & ClearPrice;
/** What a credit answers, and what the turn reply's `pollen` field carries. */
export type PollenReceipt = { schema_version: 1; earned: number; balance: number; turn?: TurnLine; clears: ClearLine[] };
export type WalletView = { schema_version: 1; balance: number; earned: number; bank: number };
export type HistoryEntry = { kind: string; amount: number; at: number; level_id?: string; stage_id?: string; role?: string };
export type HistoryView = { schema_version: 1; entries: HistoryEntry[] };
/** A first clear to pay: from the turn that finished a chapter together, or claimed by the app for a solo clear. */
export type ClearClaim = { level_id: string; hard: boolean; boost_percent: number };

const [WALLET, CLAIMS] = POLLEN_WALLET_TABLES;
export const MAX_CLAIMS = CLAIMS.maxRows;
export const HISTORY_LIMIT = 50;
/** A turn credited this soon after acceptance is never late, so a turn accepted just before Monday 00:00 UTC keeps its bank turn. */
export const LATE_GRACE_MS = 3_600_000;
const MAX_SLOTS = 128;
const MAX_TIME = 8_640_000_000_000_000;

const count = (value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
export const turnClaimKey = (roomId: string, recordingHash: string) => `turn:${roomId}:${recordingHash}`;
export const clearClaimKey = (kind: "clear" | "hardclear", levelId: string) => `${kind}:${levelId}`;

/** Whether the tables exist, read once per Player instance; a create or drop forgets the answer. */
const known = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let found = known.get(storage);
  if (found === undefined) {
    found = storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", WALLET.name).toArray().length > 0;
    known.set(storage, found);
  }
  return found;
}
function ensureTables(storage: DurableObjectStorage): void {
  if (present(storage)) return;
  for (const table of POLLEN_WALLET_TABLES) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  known.delete(storage);
}

export function validWallet(value: unknown, rates: Rates = RATES): value is WalletState {
  if (!isObject(value) || Object.keys(value).length !== 8 || value.schema_version !== 1) return false;
  if (!count(value.balance) || !count(value.earned) || !count(value.bank, 0, rates.bank.cap) || !count(value.week) || !count(value.fj_until, 0, MAX_TIME) || !count(value.pruned_day)) return false;
  if (!isObject(value.weeks) || Object.keys(value.weeks).length > rates.claims.weeks_kept + 1) return false;
  return Object.entries(value.weeks).every(([week, state]) => /^[0-9]{1,7}$/.test(week) && isObject(state) && Object.keys(state).length === 2 &&
    Array.isArray(state.slots) && state.slots.length <= MAX_SLOTS && state.slots.every(slot => typeof slot === "string" && slot.length <= 160) && count(state.tail, 0, tailLength(rates)));
}

/** The stored wallet, or null. A wallet that fails its check stops every credit rather than being replaced. */
function stored(storage: DurableObjectStorage): WalletState | null {
  if (!present(storage)) return null;
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM pollen_wallet WHERE id=1").toArray()[0];
  if (!row) return null;
  const value: unknown = JSON.parse(row.data);
  if (!validWallet(value)) throw new Error("unsupported_pollen_wallet");
  return value;
}

/**
 * The wallet as of `now`. Until it has been paid anything (a wallet made only to note a Full Journey
 * end), it holds the starting bank this week, so every player starts with the same 12; after that,
 * each Monday since the last touch refills it.
 */
function current(storage: DurableObjectStorage, now: number, rates: Rates = RATES): WalletState {
  const week = weekIndex(now);
  const wallet = stored(storage) ?? { schema_version: 1, balance: 0, earned: 0, bank: rates.bank.start, week, weeks: {}, fj_until: 0, pruned_day: 0 };
  if (wallet.earned === 0) { wallet.bank = rates.bank.start; wallet.week = week; }
  if (week > wallet.week) { wallet.bank = Math.min(rates.bank.cap, wallet.bank + rates.bank.refill * (week - wallet.week)); wallet.week = week; }
  return wallet;
}

function save(storage: DurableObjectStorage, wallet: WalletState, now: number, rates: Rates = RATES): void {
  const oldest = weekIndex(now) - rates.claims.weeks_kept + 1;
  for (const week of Object.keys(wallet.weeks)) if (Number(week) < oldest) delete wallet.weeks[week];
  storage.sql.exec("INSERT OR REPLACE INTO pollen_wallet VALUES (1,?)", JSON.stringify(wallet));
}

/** Turn claims older than the prune window go, at most once a day, before a new claim lands. */
function prune(storage: DurableObjectStorage, wallet: WalletState, now: number, rates: Rates = RATES): void {
  const day = Math.floor(now / DAY_MS);
  if (wallet.pruned_day === day) return;
  storage.sql.exec("DELETE FROM pollen_claims WHERE kind='turn' AND created_at<?", now - rates.claims.turn_prune_days * DAY_MS);
  wallet.pruned_day = day;
}

type StoredClaim = { schema_version: 1; receipt: Omit<PollenReceipt, "balance">; detail: Record<string, unknown> };
function claimed(storage: DurableObjectStorage, key: string): StoredClaim | null {
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM pollen_claims WHERE claim_key=?", key).toArray()[0];
  return row ? JSON.parse(row.data) as StoredClaim : null;
}
function insertClaim(storage: DurableObjectStorage, key: string, kind: string, amount: number, now: number, receipt: Omit<PollenReceipt, "balance">, detail: Record<string, unknown>): void {
  storage.sql.exec("INSERT INTO pollen_claims VALUES (?,?,?,?,?)", key, kind, amount, now, JSON.stringify({ schema_version: 1, receipt, detail } satisfies StoredClaim));
}

/** Each first clear of `claim` not paid before, as claim rows; the lines it paid. */
function payClears(storage: DurableObjectStorage, claim: ClearClaim, now: number, rates: Rates = RATES): ClearLine[] {
  const lines: ClearLine[] = [];
  for (const kind of claim.hard ? ["clear", "hardclear"] as const : ["clear"] as const) {
    const key = clearClaimKey(kind, claim.level_id), cost = clearPrice(claim.level_id, claim.boost_percent, rates);
    if (cost === null || claimed(storage, key)) continue;
    const line: ClearLine = { kind, level_id: claim.level_id, ...cost };
    insertClaim(storage, key, kind, cost.total, now, { schema_version: 1, earned: cost.total, clears: [line] }, { level_id: claim.level_id });
    lines.push(line);
  }
  return lines;
}

const total = (lines: readonly { total: number }[]) => lines.reduce((sum, line) => sum + line.total, 0);

/**
 * Credits one accepted turn from its frozen facts, once per claim key. `active` re-checks the
 * identity inside the transaction (a deletion may start during the bloom roll).
 */
export async function creditTurn(storage: DurableObjectStorage, env: ServerVars, owner: string, facts: unknown, now: number, active: () => boolean, rates: Rates = RATES): Promise<Outcome<PollenReceipt>> {
  if (!validTurnFacts(facts)) return fail(400, "invalid_pollen_facts");
  if (facts.player_id !== owner) return fail(403, "pollen_claim_refused");
  const roll = await bloomRoll(env, { player_id: owner, week: facts.week, level_id: facts.level_id, stage_id: facts.stage_id, role: facts.role }, rates);
  if (roll === null) return fail(503, "pollen_unconfigured");
  return storage.transactionSync((): Outcome<PollenReceipt> => {
    if (!active()) return fail(404, "identity_absent");
    const key = turnClaimKey(facts.room_id, facts.recording_hash);
    const prior = present(storage) ? claimed(storage, key) : null;
    if (prior) return ok({ ...prior.receipt, balance: stored(storage)?.balance ?? 0 });
    if (now - facts.accepted_at > rates.claims.turn_claim_days * DAY_MS) return fail(410, "pollen_claim_expired");
    // Only a turn with a friend earns: a host's turn committed before the guest joined pays nothing,
    // now or on any later claim (the room froze `together` with the turn), and writes nothing.
    if (!facts.together) return ok({ schema_version: 1, earned: 0, balance: stored(storage)?.balance ?? 0, clears: [] });
    const wallet = current(storage, now, rates);
    const zero = (turn: TurnLine): Outcome<PollenReceipt> => ok({ schema_version: 1, earned: 0, balance: wallet.balance, turn, clears: [] });
    if (chapterTier(facts.level_id, rates) === null) return zero(price({ facts, bank: false, tail_index: 0, bloom: 1 }, rates));
    const week = String(weekIndex(facts.accepted_at)), slot = `${facts.level_id}|${facts.stage_id}|${facts.role}`;
    const state: WeekState = wallet.weeks[week] ?? { slots: [], tail: 0 };
    const repeat = state.slots.includes(slot), late = Number(week) < weekIndex(now) && now - facts.accepted_at > LATE_GRACE_MS, bank = !repeat && !late && wallet.bank > 0, tailIndex = state.tail;
    if (bank) { wallet.bank--; state.slots.push(slot); }
    else if (state.tail < tailLength(rates)) state.tail++;
    const priced = price({ facts, bank, tail_index: tailIndex, bloom: roll.multiplier }, rates);
    const boostFrom = [...(facts.subscriber ? ["you" as const] : []), ...(facts.partner_subscriber ? ["partner" as const] : [])];
    const turn: TurnLine = { ...priced, ...(bank ? {} : { reason: repeat ? "repeat" as const : late ? "late" as const : "bank_empty" as const }), ...(priced.boost_percent > 0 ? { boost_from: boostFrom } : {}) };
    ensureTables(storage);
    const clears = facts.complete ? payClears(storage, { level_id: facts.level_id, hard: facts.hard && facts.together, boost_percent: facts.boost_percent }, now, rates) : [];
    if (!bank && turn.total === 0 && clears.length === 0) return zero(turn);
    prune(storage, wallet, now, rates);
    const earned = turn.total + total(clears);
    if (turn.total > 0 || bank) insertClaim(storage, key, "turn", turn.total, now, { schema_version: 1, earned, turn, clears },
      { room_id: facts.room_id, week: facts.week, level_id: facts.level_id, stage_id: facts.stage_id, role: facts.role, roll: roll.roll });
    wallet.weeks[week] = state;
    wallet.balance += earned; wallet.earned += earned;
    save(storage, wallet, now, rates);
    return ok({ schema_version: 1, earned, balance: wallet.balance, turn, clears });
  });
}

/** Credits a first clear (and a first Hard clear) once per chapter. Nothing new to pay writes nothing. */
export function creditClear(storage: DurableObjectStorage, claim: ClearClaim, now: number, active: () => boolean, rates: Rates = RATES): Outcome<PollenReceipt> {
  return storage.transactionSync((): Outcome<PollenReceipt> => {
    if (!active()) return fail(404, "identity_absent");
    if (chapterTier(claim.level_id, rates) === null) return fail(422, "unsupported_chapter");
    if (!count(claim.boost_percent, 0, boostPercent(2, rates))) return fail(400, "invalid_pollen_clear");
    const wallet = current(storage, now, rates);
    if (present(storage) && (claim.hard ? ["clear", "hardclear"] as const : ["clear"] as const).every(kind => claimed(storage, clearClaimKey(kind, claim.level_id))))
      return ok({ schema_version: 1, earned: 0, balance: wallet.balance, clears: [] });
    ensureTables(storage);
    const clears = payClears(storage, claim, now, rates);
    const earned = total(clears);
    wallet.balance += earned; wallet.earned += earned;
    save(storage, wallet, now, rates);
    return ok({ schema_version: 1, earned, balance: wallet.balance, clears });
  });
}

/**
 * A solo first clear the app claims. A paid chapter needs Full Journey (the stored end; no provider
 * call), and a subscriber's room of one gets one subscriber's boost. Hard is never paid solo.
 */
export function creditSoloClear(storage: DurableObjectStorage, levelId: string, premium: boolean, now: number, active: () => boolean, rates: Rates = RATES): Outcome<PollenReceipt> {
  if (!active()) return fail(404, "identity_absent");
  const subscriber = fullJourneyUntil(storage) > now;
  if (premium && !subscriber) return fail(403, "full_journey_required");
  return creditClear(storage, { level_id: levelId, hard: false, boost_percent: boostPercent(Number(subscriber), rates) }, now, active, rates);
}

/**
 * The player's Full Journey end as last noted (0 for none). It rides on the identity checks of
 * turns, creates and joins, so a wallet that fails its check reads as none here rather than
 * stopping play; its credits still stop until it is looked at.
 */
export function fullJourneyUntil(storage: DurableObjectStorage): number {
  try { return stored(storage)?.fj_until ?? 0; } catch { return 0; }
}

/**
 * Notes the Full Journey end RevenueCat reported. Writes only on a change, never makes a wallet just
 * to store 0, and never stops the identity check it rides on.
 */
export function noteFullJourney(storage: DurableObjectStorage, until: number, now: number, rates: Rates = RATES): void {
  if (!count(until, 0, MAX_TIME) || fullJourneyUntil(storage) === until || (until === 0 && !present(storage))) return;
  try {
    storage.transactionSync(() => {
      ensureTables(storage);
      const wallet = current(storage, now, rates);
      wallet.fj_until = until;
      save(storage, wallet, now, rates);
    });
  } catch { /* an unreadable wallet keeps its old value */ }
}

/** GET /v1/pollen. Read only: a refill that is due shows without being written. */
export function walletView(storage: DurableObjectStorage, now: number, rates: Rates = RATES): WalletView {
  const wallet = current(storage, now, rates);
  return { schema_version: 1, balance: wallet.balance, earned: wallet.earned, bank: wallet.bank };
}

/** GET /v1/pollen/history: the newest paid claims, newest first. */
export function historyView(storage: DurableObjectStorage): HistoryView {
  if (!present(storage)) return { schema_version: 1, entries: [] };
  const entries = storage.sql.exec<{ kind: string; amount: number; created_at: number; data: string }>("SELECT kind,amount,created_at,data FROM pollen_claims ORDER BY created_at DESC, claim_key LIMIT ?", HISTORY_LIMIT).toArray().map(row => {
    const detail = (JSON.parse(row.data) as StoredClaim).detail ?? {};
    const entry: HistoryEntry = { kind: row.kind, amount: row.amount, at: row.created_at };
    for (const field of ["level_id", "stage_id", "role"] as const) if (typeof detail[field] === "string") entry[field] = detail[field] as string;
    return entry;
  });
  return { schema_version: 1, entries };
}

/** The balance as of `now` (0 for a player who never earned). The caller owns the transaction. */
export function walletBalance(storage: DurableObjectStorage, now: number, rates: Rates = RATES): number {
  return current(storage, now, rates).balance;
}

/**
 * Takes `amount` from the balance, inside the caller's transaction, after the caller priced and
 * checked the spend (spend.ts charge). Lifetime earned is unchanged. Never takes the balance
 * below zero; the balance it leaves, or null when it would.
 */
export function payFromWallet(storage: DurableObjectStorage, amount: number, now: number, rates: Rates = RATES): number | null {
  const wallet = current(storage, now, rates);
  if (!count(amount, 1) || wallet.balance < amount) return null;
  wallet.balance -= amount;
  ensureTables(storage);
  save(storage, wallet, now, rates);
  return wallet.balance;
}

/** Whether the player's first clear of a chapter (any version) is on record: what unlocks a Special. */
export function chapterCleared(storage: DurableObjectStorage, levelId: string): boolean {
  return present(storage) && claimed(storage, clearClaimKey("clear", levelId)) !== null;
}

/** Account erasure: the wallet and every claim go (wardrobe.ts drops the rest). A Player that never earned has nothing to drop. */
export function dropWallet(storage: DurableObjectStorage): void {
  for (const table of POLLEN_WALLET_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
  known.delete(storage);
}

/** The tables as sqlite_master lists them (snapshot.ts refuses a Player that has them). */
export function isPollenPlayerTable(row: { name: string; sql: string }): boolean { return isLazyTable(POLLEN_PLAYER_TABLES, row); }
