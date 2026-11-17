import { FRUIT_PREFIX, purse, setPurse } from "./currency";
import { DORMANT_TRACKS, FRUIT_RULES, goalOf, type Achievement, type FruitRules, type Track } from "./fruits";
import { applyLedger, inLedger, ledgerLine, ledgerLines, type FruitsReceipt, type LedgerEntry } from "./wallet";
import { pairGoalWins } from "./duel-pay";
import { earnedItems } from "./earned";
import { RATES, type Rates } from "./rates";

/**
 * Achievements (PLAN v2 section 8): one-time goals for playing together and playing well, each paying its Fruits once
 * for good under `fruit:ach:<id>`. Every check is the server's, against what the Player already keeps:
 * - together_clears: chapters with a `fruit:together:<level>` mark (a 0 Fruit line, one per chapter at most), written
 *   when a chapter is finished together while Fruits are on, and by the one-time sweep for every chapter whose first
 *   clear or Hard clear was already on record (a first clear made before Fruits counts whether it was solo or together:
 *   older rows can't tell them apart, and the owner's rule is to pay against existing records);
 * - hard_clears: `hardclear:` lines (always together, kept for good); every_hard, top_ten_ribbon, gold_leaf: earned items;
 * - ghost_wins: `ghostwin:` lines (kept for good);
 * - duel_wins, public_duels and public_wins: purse counters ("count:…"), since their own lines are pruned after 35 days. The
 *   sweep starts them from the lines still kept; after it, a friend duel win that paid adds one to duel_wins when its line
 *   is first written; a public duel finished with neither side giving up (duels/public.ts finishedPublic) sets public_duels
 *   to at least 1; a public duel won adds one to public_wins when its win line is first written, unless the farming guard
 *   held it back: past two wins over the same pair that week (duel-pay.ts creditDuelWin PAIR_GOAL_WINS; a tester's counts).
 * - keepsakes, keepsakes_best: dormant until keepsakes round 2 (listed, never paid).
 * settle() runs inside the caller's transaction at each of those moments, and at most once per player as the sweep on the
 * first Fruits read or moment (purse "swept" 1). Its second step (swept 2) starts public_wins from the public duel wins
 * still kept, once, also for a player swept before that goal existed. It writes only when something is newly marked or
 * due, so rows stay bounded by the goals and chapters.
 */
export type Moment = { level_id?: string; room_id?: string; together_level?: string; duel_win?: boolean; public_duel?: boolean; public_win?: boolean };
export type AchievementView = { id: string; fruits: number; goal: number; progress: number; live: boolean; paid_at?: number; level_id?: string; room_id?: string };
const MARK = `${FRUIT_PREFIX}together:`;
const achKey = (id: string) => `${FRUIT_PREFIX}ach:${id}`;
const COUNTERS = { duel_wins: "count:duel_wins", public_duels: "count:public_duels", public_wins: "count:public_wins" } as const;
type Counter = typeof COUNTERS[keyof typeof COUNTERS];
/** The sweep's steps done (purse "swept"): 1 the first sweep, 2 the public wins' start. */
const SWEPT = 2;

/** The chapters marked as finished together. */
function togetherLevels(storage: DurableObjectStorage): Set<string> {
  return new Set(ledgerLines(storage, MARK, 128).map(line => line.key.slice(MARK.length)));
}
function mark(level: string, rates: Rates): LedgerEntry | null {
  return Object.hasOwn(rates.chapters, level) ? { key: MARK + level, kind: "fruitmark", amount: 0, detail: { level_id: level } } : null;
}

/**
 * The sweep, once per player: marks and counters from the records kept before Fruits were on, then (step 2) public_wins
 * from the public duel wins still kept. Answers which counters it started, so a moment whose own line it just counted adds
 * nothing more.
 */
function sweep(storage: DurableObjectStorage, now: number, rates: Rates): { friend: boolean; public: boolean } {
  const done = purse(storage, "swept");
  if (done.balance >= SWEPT) return { friend: false, public: false };
  // A public duel's win shares the friend prefix: its line says public, or (older lines) its duel has a held extra line.
  const extras = ledgerLines(storage, "duelextra:", 512);
  const publicIds = new Set(extras.map(line => line.detail.duel_id));
  const wins = ledgerLines(storage, "duelwin:", 512), isPublic = (line: { detail: Record<string, unknown> }) => !!line.detail.public || publicIds.has(line.detail.duel_id);
  const found: [Counter, number][] = [[COUNTERS.public_wins, pairGoalWins(wins.filter(isPublic).map(line => line.detail))]];
  const first = done.balance < 1;
  if (first) {
    const levels = new Set([...ledgerLines(storage, "clear:", 256), ...ledgerLines(storage, "hardclear:", 256)].map(line => line.detail.level_id).filter((level): level is string => typeof level === "string"));
    applyLedger(storage, [...levels].flatMap(level => mark(level, rates) ?? []), now, rates);
    found.push([COUNTERS.duel_wins, wins.filter(line => line.amount > 0 && !isPublic(line)).length], [COUNTERS.public_duels, extras.filter(line => line.detail.reason === undefined).length]);
  }
  for (const [counter, count] of found) {
    const row = purse(storage, counter);
    if (count > row.balance) setPurse(storage, counter, { balance: count, earned: row.earned });
  }
  setPurse(storage, "swept", { balance: SWEPT, earned: first ? now : done.earned });
  return { friend: first, public: true };
}

/** Each track's progress now. */
function progress(storage: DurableObjectStorage, rates: Rates): Record<Track, number> {
  const earned = earnedItems(storage);
  const chapters = new Set(Object.keys(rates.chapters));
  return {
    together_clears: [...togetherLevels(storage)].filter(level => chapters.has(level)).length,
    hard_clears: ledgerLines(storage, "hardclear:", 256).length,
    every_hard: earned.has("every_hard") ? 1 : 0,
    duel_wins: purse(storage, COUNTERS.duel_wins).balance,
    ghost_wins: ledgerLines(storage, "ghostwin:", 256).length,
    public_duels: purse(storage, COUNTERS.public_duels).balance,
    public_wins: purse(storage, COUNTERS.public_wins).balance,
    top_ten_ribbon: earned.has("top_ten_ribbon") ? 1 : 0,
    gold_leaf: earned.has("gold_leaf") ? 1 : 0,
    keepsakes: 0, keepsakes_best: 0
  };
}

/**
 * A duel win's moment once its line is first written (duel-pay.ts CreditOptions.fresh): a friend duel win counts only when
 * it paid (never past the weekly limits or against the same pair again); a public duel win counts unless the farming guard
 * held it back (`counts` false: past two wins over the same pair that week, never a tester's).
 */
export function duelMoment(moment: Moment, paid: boolean, counts = true): Moment {
  return { ...moment, duel_win: !!moment.duel_win && paid, public_win: !!moment.public_win && counts };
}

/**
 * settleAchievements for bookkeeping no Fruits app asked for (a turn from an app Fruits are gated off for, a partner's clear,
 * a duel result, board rewards): only for a player whose sweep has run, so a player who has only used older apps writes
 * nothing, as with FRUITS off, and their first Fruits read sweeps it all from their records. One row read when unswept.
 */
export function settleStartedAchievements(storage: DurableObjectStorage, now: number, moment: Moment = {}): FruitsReceipt | null {
  return purse(storage, "swept").balance > 0 ? settleAchievements(storage, now, moment) : null;
}
/**
 * Notes `moment` and pays every live achievement now due, inside the caller's transaction. Only while Fruits are on (the
 * caller decides). Answers what it paid and the Fruit balance, or null when nothing was paid.
 */
export function settleAchievements(storage: DurableObjectStorage, now: number, moment: Moment = {}, rules: FruitRules = FRUIT_RULES, rates: Rates = RATES): FruitsReceipt | null {
  // A moment's own line is written before this runs, so a sweep made now has already counted it.
  const swept = sweep(storage, now, rates);
  const marked = moment.together_level ? mark(moment.together_level, rates) : null;
  if (marked) applyLedger(storage, [marked], now, rates);
  const add = (counter: Counter) => { const row = purse(storage, counter); setPurse(storage, counter, { balance: row.balance + 1, earned: row.earned }); };
  if (moment.duel_win && !swept.friend) add(COUNTERS.duel_wins);
  if (moment.public_win && !swept.public) add(COUNTERS.public_wins);
  if (moment.public_duel) { const row = purse(storage, COUNTERS.public_duels); if (row.balance < 1) setPurse(storage, COUNTERS.public_duels, { balance: 1, earned: row.earned }); }
  const now_progress = progress(storage, rates), chapters = Object.keys(rates.chapters).length;
  const due = rules.achievements.filter(item => !DORMANT_TRACKS.has(item.track) && now_progress[item.track] >= goalOf(item, chapters) && !inLedger(storage, achKey(item.id)));
  if (!due.length) return null;
  const detail = (item: Achievement) => ({ id: item.id, ...(moment.level_id && (item.track === "together_clears" || item.track === "hard_clears" || item.track === "every_hard") ? { level_id: moment.level_id } : {}),
    ...(moment.room_id && item.track === "together_clears" ? { room_id: moment.room_id } : {}) });
  const paid = applyLedger(storage, due.map(item => ({ key: achKey(item.id), kind: "fruitach", amount: item.fruits, detail: detail(item) })), now, rates);
  return { balance: purse(storage, "fruits").balance, paid: paid.map(entry => ({ id: String(entry.detail.id), amount: entry.amount })) };
}

/** The wallet read's list: every goal in order with its progress (capped at its goal) and when it was paid. Read only. */
export function achievementsView(storage: DurableObjectStorage, rules: FruitRules = FRUIT_RULES, rates: Rates = RATES): AchievementView[] {
  const now_progress = progress(storage, rates), chapters = Object.keys(rates.chapters).length;
  return rules.achievements.map(item => {
    const goal = goalOf(item, chapters), line = ledgerLine(storage, achKey(item.id)), live = !DORMANT_TRACKS.has(item.track);
    // A paid goal shows what it paid (public_duel_first paid 10 before it became 5).
    const view: AchievementView = { id: item.id, fruits: line ? line.amount : item.fruits, goal, progress: Math.min(goal, line ? goal : now_progress[item.track]), live };
    if (line) {
      view.paid_at = line.at;
      if (typeof line.detail.level_id === "string") view.level_id = line.detail.level_id;
      if (typeof line.detail.room_id === "string") view.room_id = line.detail.room_id;
    }
    return view;
  });
}
