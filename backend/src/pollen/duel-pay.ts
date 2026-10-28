import { fail, ok, type Outcome } from "../protocol";
import { DAY_MS, RATES, type Rates } from "./rates";
import { weekIndex } from "./week";
import { applyLedger, ledgerLines, walletBalance } from "./wallet";

/**
 * A friend duel's Pollen on the player's own wallet (POLLEN-RULES.md "Duels and ghost races").
 *
 * The win bonus: each player of the winning pair gets rates.duels.win_bonus once per duel, as the
 * ledger line `duelwin:<duel_id>`, with no room boost, no premium and no bloom. At most
 * wins_per_week counted wins in the week the duel was decided, and only one against the same
 * opposing pair that week. A win past either limit still writes its line, at 0 with the reason, so
 * a repeat answers the same and the order of a week's wins never changes. Pruned with turn claims;
 * a win older than the turn claim window is refused, so a pruned line can never pay twice.
 *
 * The duel's pay: what the player's turns in the duel's room paid, from their turn claims, split
 * the way the result card shows it.
 */
export type DuelWin = { duel_id: string; opponent: string; decided_ms: number };
export type DuelWinAnswer = { amount: number; counted: boolean; reason?: "weekly_cap" | "same_pair"; balance: number };
export type DuelRoomPay = { turns: number; plain: number; blooms: number; duel: number; boost: number; boost_percent: number; total: number };

const WIN_PREFIX = "duelwin:";
const MAX_WEEK_LINES = 256;

export function creditDuelWin(storage: DurableObjectStorage, win: DuelWin, now: number, active: () => boolean, rates: Rates = RATES): Outcome<DuelWinAnswer> {
  return storage.transactionSync((): Outcome<DuelWinAnswer> => {
    if (!active()) return fail(404, "identity_absent");
    const key = WIN_PREFIX + win.duel_id;
    const prior = ledgerLines(storage, key, 1).find(line => line.key === key);
    if (prior) return ok(answer(prior.amount, prior.detail.reason, walletBalance(storage, now, rates)));
    if (now - win.decided_ms > rates.claims.turn_claim_days * DAY_MS) return fail(410, "duel_win_expired");
    const week = weekIndex(win.decided_ms);
    const lines = ledgerLines(storage, WIN_PREFIX, MAX_WEEK_LINES).filter(line => line.detail.week === week && line.amount > 0);
    const reason = lines.length >= rates.duels.wins_per_week ? "weekly_cap" : lines.some(line => line.detail.opponent === win.opponent) ? "same_pair" : undefined;
    const amount = reason ? 0 : rates.duels.win_bonus;
    applyLedger(storage, [{ key, kind: "duelwin", amount, detail: { duel_id: win.duel_id, week, opponent: win.opponent, ...(reason ? { reason } : {}) } }], now, rates);
    return ok(answer(amount, reason, walletBalance(storage, now, rates)));
  });
}

function answer(amount: number, reason: unknown, balance: number): DuelWinAnswer {
  return { amount, counted: amount > 0, ...(reason === "weekly_cap" || reason === "same_pair" ? { reason } : {}), balance };
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
