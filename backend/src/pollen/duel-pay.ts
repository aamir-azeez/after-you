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
 */
export type DuelWin = { duel_id: string; opponent: string; decided_ms: number };
export type GhostWin = { duel_id: string; board: string };
export type BonusReason = "weekly_cap" | "same_pair" | "board_paid";
export type DuelWinAnswer = { amount: number; counted: boolean; reason?: BonusReason; balance: number };
export type DuelRoomPay = { turns: number; plain: number; blooms: number; duel: number; boost: number; boost_percent: number; total: number };

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
  price: () => Outcome<LedgerEntry>, held: (detail: Record<string, unknown>, amount: number) => Held): Outcome<DuelWinAnswer> {
  return storage.transactionSync((): Outcome<DuelWinAnswer> => {
    if (!active()) return fail(404, "identity_absent");
    const prior = ledgerLines(storage, key, 1).find(line => line.key === key);
    if (prior) { const seen = held(prior.detail, prior.amount); return ok(answer(seen.amount, seen.reason, walletBalance(storage, now, rates))); }
    const entry = price();
    if (!entry.ok) return entry;
    applyLedger(storage, [entry.value], now, rates);
    return ok(answer(entry.value.amount, entry.value.detail.reason, walletBalance(storage, now, rates)));
  });
}

export function creditDuelWin(storage: DurableObjectStorage, win: DuelWin, now: number, active: () => boolean, rates: Rates = RATES): Outcome<DuelWinAnswer> {
  const key = WIN_PREFIX + win.duel_id;
  return creditOnce(storage, key, now, active, rates, () => {
    if (now - win.decided_ms > rates.claims.turn_claim_days * DAY_MS) return fail(410, "duel_win_expired");
    const week = weekIndex(win.decided_ms);
    const lines = ledgerLines(storage, WIN_PREFIX, MAX_WEEK_LINES).filter(line => line.detail.week === week && line.amount > 0);
    const reason = lines.length >= rates.duels.wins_per_week ? "weekly_cap" : lines.some(line => line.detail.opponent === win.opponent) ? "same_pair" : undefined;
    return ok({ key, kind: "duelwin", amount: reason ? 0 : rates.duels.win_bonus, detail: { duel_id: win.duel_id, week, opponent: win.opponent, ...(reason ? { reason } : {}) } });
  }, (detail, amount) => ({ amount, reason: detail.reason }));
}

/** The first win over the developers' ghost on a board. Never pruned (wallet.ts prunes only turns and duel wins), so it pays once for good. */
export function creditGhostWin(storage: DurableObjectStorage, win: GhostWin, now: number, active: () => boolean, rates: Rates = RATES): Outcome<DuelWinAnswer> {
  const key = GHOST_PREFIX + win.board;
  return creditOnce(storage, key, now, active, rates,
    () => ok({ key, kind: "ghostwin", amount: rates.duels.ghost_win_bonus, detail: { duel_id: win.duel_id } }),
    (detail, amount) => detail.duel_id === win.duel_id ? { amount } : { amount: 0, reason: "board_paid" });
}

function answer(amount: number, reason: unknown, balance: number): DuelWinAnswer {
  return { amount, counted: amount > 0, ...(REASONS.includes(reason) ? { reason: reason as BonusReason } : {}), balance };
}

/** What the player's turns in `roomId` paid, read from their turn claims. Reads only. */
export function duelRoomPay(storage: DurableObjectStorage, roomId: string): DuelRoomPay {
  const pay: DuelRoomPay = { turns: 0, plain: 0, blooms: 0, duel: 0, boost: 0, boost_percent: 0, total: 0 };
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
    pay.boost += turn.boost ?? 0;
    pay.boost_percent = Math.max(pay.boost_percent, turn.boost_percent ?? 0);
    pay.total += turn.total ?? 0;
  }
  return pay;
}
