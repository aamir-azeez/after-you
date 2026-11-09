import { fail, ok, type Outcome } from "../protocol";
import { DAY_MS, RATES, type Rates } from "./rates";
import { weekIndex } from "./week";
import { applyLedger, ledgerLines, walletBalance, type LedgerEntry } from "./wallet";

/**
 * A duel's Pollen on the player's own wallet (POLLEN-RULES.md "Duels and ghost races").
 *
 * The win bonus: each player of the winning pair gets rates.duels.win_bonus once per duel, as the
 * ledger line `duelwin:<duel_id>`, with no room boost, no premium and no bloom. At most
 * wins_per_week counted wins in the week the duel was decided, and only one against the same
 * opposing pair that week. A win past either limit still writes its line, at 0 with the reason, so
 * a repeat answers the same and the order of a week's wins never changes. Pruned with turn claims;
 * a win older than the turn claim window is refused, so a pruned line can never pay twice.
 *
 * The ghost bonus: each player of a pair that beats the developers' ghost on a board gets
 * rates.duels.ghost_win_bonus the first time, as the ledger line `ghostwin:<board>`, kept for good,
 * with no room boost, no premium and no bloom. The line names the race that paid it: that race
 * answers the same again, and any later win on the board answers 0 with "board_paid", writing nothing.
 *
 * The duel's pay: what the player's turns in the duel's room paid, from their turn claims, split
 * the way the result card shows it.
 *
 * The held extra (public duels, duels/public.ts): a public duel room's bank turns price the duel premium as
 * `duel_held`, left out of the turn's total and the balance (pollen/earn.ts price). When the duel is final, each
 * player's read pays the sum of their held turns in their room once, as the ledger line `duelextra:<duel_id>`, or 0
 * with the reason when they forfeit it (a leave, the stop that stalled their side, nobody joined). Like a win, it is
 * refused once the duel ended more than the turn claim window ago, and pruned with duel wins; held turn claims are
 * kept until MAX_PUBLIC_DUEL_MS has passed, so they are always there to be summed (wallet.ts prune).
 */
/** `opponent`: the opposing pair's key; `opponent_pair`: its id key too when `opponent` is its account key (leaderboards/pair-accounts.ts). */
export type DuelWin = { duel_id: string; opponent: string; decided_ms: number; opponent_pair?: string };
export type GhostWin = { duel_id: string; board: string };
export type BonusReason = "weekly_cap" | "same_pair" | "board_paid";
export type DuelWinAnswer = { amount: number; counted: boolean; reason?: BonusReason; balance: number };
/** `held`: the duel premium the turns hold for the end of a public duel (absent from `total`). */
export type DuelRoomPay = { turns: number; plain: number; blooms: number; duel: number; duel_percent: number; boost: number; boost_percent: number; total: number; held: number };
/** A public duel's held extra for one player: `paid` false with the reason when forfeited (duels/public.ts heldState). */
export type DuelExtra = { duel_id: string; room_id: string | null; decided_ms: number; paid: boolean; reason?: string };
export type DuelExtraAnswer = { amount: number; held: number; paid: boolean; reason?: string; balance: number };
const EXTRA_PREFIX = "duelextra:";

const WIN_PREFIX = "duelwin:";
const GHOST_PREFIX = "ghostwin:";
const MAX_WEEK_LINES = 256;
const REASONS: readonly unknown[] = ["weekly_cap", "same_pair", "board_paid"];
type Held = { amount: number; reason?: unknown };

/**
 * One bonus line, at most once, in one transaction: a held line answers through `held`, and only a
 * missing one asks `price` for the line to write, or a refusal.
 */
function creditOnce(storage: DurableObjectStorage, key: string, now: number, active: () => boolean, rates: Rates,
  price: () => Outcome<LedgerEntry>, held: (detail: Record<string, unknown>, amount: number) => Held, fresh?: (storage: DurableObjectStorage) => void): Outcome<DuelWinAnswer> {
  return storage.transactionSync((): Outcome<DuelWinAnswer> => {
    if (!active()) return fail(404, "identity_absent");
    const prior = ledgerLines(storage, key, 1).find(line => line.key === key);
    if (prior) { const seen = held(prior.detail, prior.amount); return ok(answer(seen.amount, seen.reason, walletBalance(storage, now, rates))); }
    const entry = price();
    if (!entry.ok) return entry;
    applyLedger(storage, [entry.value], now, rates);
    fresh?.(storage);
    return ok(answer(entry.value.amount, entry.value.detail.reason, walletBalance(storage, now, rates)));
  });
}

/**
 * `fresh`: run inside the transaction once the line is first written (achievements.ts, while Fruits are on);
 * `public`: a public duel's win, kept on the line so it never counts as a friend duel win.
 */
export type CreditOptions = { fresh?: (storage: DurableObjectStorage) => void; public?: boolean };
export function creditDuelWin(storage: DurableObjectStorage, win: DuelWin, now: number, active: () => boolean, rates: Rates = RATES, options: CreditOptions = {}): Outcome<DuelWinAnswer> {
  const key = WIN_PREFIX + win.duel_id;
  return creditOnce(storage, key, now, active, rates, () => {
    if (now - win.decided_ms > rates.claims.turn_claim_days * DAY_MS) return fail(410, "duel_win_expired");
    const week = weekIndex(win.decided_ms);
    const weekLines = ledgerLines(storage, WIN_PREFIX, MAX_WEEK_LINES).filter(line => line.detail.week === week);
    const lines = weekLines.filter(line => line.amount > 0);
    const theirs = samePairKeys(weekLines.map(line => line.detail), win.opponent_pair ? [win.opponent, win.opponent_pair] : [win.opponent]);
    const met = lines.some(line => keysOf(line.detail).some(id => theirs.has(id)));
    const reason = lines.length >= rates.duels.wins_per_week ? "weekly_cap" : met ? "same_pair" : undefined;
    return ok({ key, kind: "duelwin", amount: reason ? 0 : rates.duels.win_bonus, detail: { duel_id: win.duel_id, week, opponent: win.opponent, ...(win.opponent_pair ? { opponent_pair: win.opponent_pair } : {}), ...(reason ? { reason } : {}), ...(options.public ? { public: true } : {}) } });
  }, (detail, amount) => ({ amount, reason: detail.reason }), options.fresh);
}

/** The first win over the developers' ghost on a board. Never pruned (wallet.ts prunes only turns and duel wins), so it pays once for good. */
export function creditGhostWin(storage: DurableObjectStorage, win: GhostWin, now: number, active: () => boolean, rates: Rates = RATES, options: CreditOptions = {}): Outcome<DuelWinAnswer> {
  const key = GHOST_PREFIX + win.board;
  return creditOnce(storage, key, now, active, rates,
    () => ok({ key, kind: "ghostwin", amount: rates.duels.ghost_win_bonus, detail: { duel_id: win.duel_id } }),
    (detail, amount) => detail.duel_id === win.duel_id ? { amount } : { amount: 0, reason: "board_paid" }, options.fresh);
}

/** A win line's opponent keys: its pair key, or its account key and the id key beside it (leaderboards/pair-accounts.ts). */
function keysOf(detail: Record<string, unknown>): unknown[] {
  return detail.opponent_pair === undefined ? [detail.opponent] : [detail.opponent, detail.opponent_pair];
}

/**
 * Every key the week's lines tie to `start`: a line naming an account key and an id key says both are the same
 * pair, so a win before the platform rule (id key only) and one after it by other identities (account key only)
 * meet through the line that named both, whatever order they were paid in. At most MAX_WEEK_LINES lines.
 */
function samePairKeys(details: readonly Record<string, unknown>[], start: readonly unknown[]): Set<unknown> {
  const keys = new Set<unknown>(start);
  for (let grew = true; grew;) {
    grew = false;
    for (const detail of details) {
      const own = keysOf(detail);
      if (own.some(id => keys.has(id)) && own.some(id => !keys.has(id))) { for (const id of own) keys.add(id); grew = true; }
    }
  }
  return keys;
}

/** A public duel's held extra, once per player per duel (EXTRA_PREFIX). A repeat answers the line as written. */
export function creditDuelExtra(storage: DurableObjectStorage, extra: DuelExtra, now: number, active: () => boolean, rates: Rates = RATES, options: CreditOptions = {}): Outcome<DuelExtraAnswer> {
  const key = EXTRA_PREFIX + extra.duel_id;
  return storage.transactionSync((): Outcome<DuelExtraAnswer> => {
    if (!active()) return fail(404, "identity_absent");
    const prior = ledgerLines(storage, key, 1).find(line => line.key === key);
    if (prior) return ok(extraAnswer(prior.amount, prior.detail, walletBalance(storage, now, rates)));
    if (now - extra.decided_ms > rates.claims.turn_claim_days * DAY_MS) return fail(410, "duel_extra_expired");
    // A public duel finished and not forfeited (achievements.ts public_duels: at least 1, so a repeat changes nothing).
    if (extra.paid) options.fresh?.(storage);
    const held = extra.room_id ? duelRoomPay(storage, extra.room_id).held : 0;
    const amount = extra.paid ? held : 0;
    // Nothing held writes nothing: a player who never took a duel turn here has no line to keep.
    if (held === 0) return ok(extraAnswer(0, { held: 0, ...(extra.paid ? {} : { reason: extra.reason }) }, walletBalance(storage, now, rates)));
    applyLedger(storage, [{ key, kind: "duelextra", amount, detail: { duel_id: extra.duel_id, room_id: extra.room_id, held, ...(extra.paid ? {} : { reason: extra.reason ?? "forfeit" }) } }], now, rates);
    return ok(extraAnswer(amount, { held, ...(extra.paid ? {} : { reason: extra.reason ?? "forfeit" }) }, walletBalance(storage, now, rates)));
  });
}

function extraAnswer(amount: number, detail: Record<string, unknown>, balance: number): DuelExtraAnswer {
  const held = typeof detail.held === "number" ? detail.held : amount;
  return { amount, held, paid: detail.reason === undefined, ...(typeof detail.reason === "string" ? { reason: detail.reason } : {}), balance };
}

function answer(amount: number, reason: unknown, balance: number): DuelWinAnswer {
  return { amount, counted: amount > 0, ...(REASONS.includes(reason) ? { reason: reason as BonusReason } : {}), balance };
}

/** What the player's turns in `roomId` paid, read from their turn claims. Reads only. */
export function duelRoomPay(storage: DurableObjectStorage, roomId: string): DuelRoomPay {
  const pay: DuelRoomPay = { turns: 0, plain: 0, blooms: 0, duel: 0, duel_percent: 0, boost: 0, boost_percent: 0, total: 0, held: 0 };
  let rows: { data: string }[] = [];
  try {
    const prefix = `turn:${roomId}:`, end = `turn:${roomId};`;
    rows = storage.sql.exec<{ data: string }>("SELECT data FROM pollen_claims WHERE claim_key>=? AND claim_key<? LIMIT 128", prefix, end).toArray();
  } catch { return pay; }
  for (const row of rows) {
    const turn = (JSON.parse(row.data) as { receipt?: { turn?: Record<string, number> } }).receipt?.turn;
    if (!turn) continue;
    pay.turns++;
    pay.plain += turn.amount ?? 0;
    pay.blooms += turn.bloom_extra ?? 0;
    pay.duel += turn.duel ?? 0;
    pay.held += turn.duel_held ?? 0;
    // The premium's percent as the turns were priced (pollen/earn.ts price, rates.duels.turn_percent).
    pay.duel_percent = Math.max(pay.duel_percent, turn.duel_percent ?? 0);
    pay.boost += turn.boost ?? 0;
    pay.boost_percent = Math.max(pay.boost_percent, turn.boost_percent ?? 0);
    pay.total += turn.total ?? 0;
  }
  return pay;
}
