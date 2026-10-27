import { DurableObject } from "cloudflare:workers";
import { canonicalJson, digest } from "../protocol";
import { answerWhileBlank, openLazyStorage } from "../lazy-storage";
import type { ChapterKey } from "../v2/chapter-types";
import { BoardRewardLedger, REWARD_LEDGER_SCHEMA, type RewardGrant, type RewardSink } from "./rewards";
import { KEPT_RANKED, MAX_CHECKED, MAX_REPORTERS, MAX_REVIEW, MAX_UNCHECKED, REVIEW_REASONS, TOP_PLACES, compareRuns, holdsFor, strictlyFirst } from "./rules";
import type { LeaderboardRun } from "./run";
import { emptyView, type BoardRow, type BoardView } from "./view";

/**
 * One chapter version's board, one Durable Object named by its board key.
 *
 * An entry is a finished together run, at most one live entry per pair, in one state:
 * - "checking": waits for the account check (eligible null), then the replay check;
 * - "review": passed the replay and waits for a person (`holds` says why);
 * - "ranked": counts. Only ranked runs push anyone down or earn anything.
 * The room's final checkpoint is kept beside a waiting entry (lb_proofs) and
 * dropped once its verdict is in. Settled runs leave a short tombstone
 * (lb_outcomes) so a retried submission of the same run never comes back.
 *
 * Every write is one synchronous transaction, so out-of-order and repeated
 * calls are safe: a verdict names the proof hash it checked and is ignored
 * when the entry has moved on.
 */
export type SubmitStatus = "checking" | "known" | "not_placed" | "busy" | "crowded" | "ineligible";
/** `rev`: the member's settings revision (member.ts) the name choice came from; an older one never overwrites it. */
export type Member = { id: string | null; show: boolean; name: string | null; rev?: number };
export type MemberChoice = { show: boolean; name: string | null; rev: number };
type EntryData = {
  finished_at: string; chapter: ChapterKey; simulation_version: number; members: [Member, Member];
  eligible: boolean | null; holds: string[]; reports: string[]; gold: boolean; submitted_at: number;
};
type EntryRow = { entry_id: string; pair_key: string; state: "checking" | "review" | "ranked"; ticks: number; finished_ms: number; data: string };
type Entry = Omit<EntryRow, "data"> & { data: EntryData };
export type StandingWork = { entry_id: string; members: (string | null)[]; finished_ms: number };
/** `checkpoint` is the stored JSON text, passed on unparsed so the Worker spends no CPU on it. */
export type ReplayWork = { entry_id: string; chapter: ChapterKey; simulation_version: number; ticks: number; proof_hash: string; checkpoint: string };
export type PendingWork = { standing: StandingWork[]; replay: ReplayWork[] };
export type StandingResult = { entry_id: string; eligible: boolean; reason: string; members: MemberChoice[] };
export type Verdict = { entry_id: string; proof_hash: string; valid: boolean; measured_ticks: number; reason: string };
export type RankedNote = { entry_id: string; members: string[] };
export type ReviewItem = { entry_id: string; state: string; rank: number | null; ticks: number; finished_at: string; holds: string[]; reports: number };

/** A stored final checkpoint is at most this long (SQLite keeps a value under 2 MB). */
export const MAX_PROOF_CHARS = 1_900_000;
/** Replay work handed out per call, by checkpoint length. */
export const MAX_REPLAY_CHARS = 4_000_000;
/** Tombstones kept, newest first. */
const MAX_OUTCOMES = 512;

const SCHEMA = [
  "CREATE TABLE IF NOT EXISTS lb_entries (entry_id TEXT PRIMARY KEY, pair_key TEXT NOT NULL, state TEXT NOT NULL, ticks INTEGER NOT NULL, finished_ms INTEGER NOT NULL, data TEXT NOT NULL)",
  "CREATE TABLE IF NOT EXISTS lb_proofs (entry_id TEXT PRIMARY KEY, proof_hash TEXT NOT NULL, checkpoint TEXT NOT NULL)",
  "CREATE TABLE IF NOT EXISTS lb_outcomes (entry_id TEXT PRIMARY KEY, outcome TEXT NOT NULL, at INTEGER NOT NULL)",
  REWARD_LEDGER_SCHEMA
];

export class LeaderboardBoard extends DurableObject<Env> {
  private readonly rewards: RewardSink & BoardRewardLedger;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.rewards = new BoardRewardLedger(ctx.storage);
    ctx.blockConcurrencyWhile(async () => openLazyStorage(this, ctx.storage, "lb_entries", () => { for (const sql of SCHEMA) ctx.storage.sql.exec(sql); }));
  }

  /**
   * Takes a finished run that might place. Returns what became of it and the
   * board as anyone sees it now. `checked`: the account check, run by the
   * poster only after this board answered "crowded" (submit.ts).
   */
  async submit(board: string, run: LeaderboardRun, checked?: StandingResult): Promise<{ status: SubmitStatus; view: BoardView }> {
    const serialized = canonicalJson(run.checkpoint);
    const proofHash = await digest(serialized);
    const status = this.ctx.storage.transactionSync((): SubmitStatus => {
      if (this.outcome(run.entry_id) || this.entry(run.entry_id)) return "known";
      if (serialized.length > MAX_PROOF_CHARS) return "not_placed";
      const timed = { ticks: run.ticks, finished_ms: run.finished_ms, entry_id: run.entry_id };
      const all = this.entries();
      const ranked = all.filter(entry => entry.state === "ranked").sort(compareRuns);
      const mine = all.filter(entry => entry.pair_key === run.pair_key);
      // One entry per pair: a run no better than the pair's own ranked or waiting run never enters.
      if (mine.some(entry => compareRuns(entry, timed) <= 0)) return "not_placed";
      const others = ranked.filter(entry => entry.pair_key !== run.pair_key);
      if (others.length >= TOP_PLACES && compareRuns(timed, others[TOP_PLACES - 1]) > 0) return "not_placed";
      if (checked && (!checked.eligible || checked.entry_id !== run.entry_id)) return "ineligible";
      const waiting = all.filter(entry => entry.state === "checking" && entry.pair_key !== run.pair_key);
      if (!checked) {
        // Unchecked runs never push anyone out; the poster checks the accounts and posts again.
        if (waiting.filter(entry => entry.data.eligible === null).length >= MAX_UNCHECKED) return "crowded";
      } else {
        const pool = waiting.filter(entry => entry.data.eligible === true).sort(compareRuns);
        if (pool.length >= MAX_CHECKED) {
          if (compareRuns(timed, pool[pool.length - 1]) > 0) return "busy";
          this.drop(pool[pool.length - 1].entry_id, "crowded");
        }
      }
      for (const older of mine) if (older.state !== "ranked") this.drop(older.entry_id, "superseded");
      const members: [Member, Member] = [{ id: run.members[0], show: false, name: null }, { id: run.members[1], show: false, name: null }];
      if (checked) members.forEach((member, index) => choose(member, checked.members[index]));
      const data: EntryData = { finished_at: run.finished_at, chapter: run.chapter, simulation_version: run.simulation_version, members,
        eligible: checked ? true : null, holds: [], reports: [], gold: false, submitted_at: Date.now() };
      this.ctx.storage.sql.exec("INSERT INTO lb_entries VALUES (?,?,?,?,?,?)", run.entry_id, run.pair_key, "checking", run.ticks, run.finished_ms, JSON.stringify(data));
      this.ctx.storage.sql.exec("INSERT INTO lb_proofs VALUES (?,?,?)", run.entry_id, proofHash, serialized);
      return "checking";
    });
    return { status, view: this.view(board) };
  }

  /** The board as anyone sees it. */
  view(board: string): BoardView {
    const ranked = this.ranked();
    const top: BoardRow[] = ranked.slice(0, TOP_PLACES).map((entry, index) => ({
      rank: index + 1, entry_id: entry.entry_id, ticks: entry.ticks, finished_on: entry.data.finished_at.slice(0, 10),
      names: shownNames(entry.data.members), gold_leaf: index === 0 && entry.data.gold }));
    const checking = this.entries().filter(entry => entry.state !== "ranked").map(entry => entry.entry_id).sort();
    return { schema_version: 1, board, top, checking };
  }

  /** What the replay job still has to do here: account checks first, then replays of eligible runs. */
  pendingWork(maxChars = MAX_REPLAY_CHARS): PendingWork {
    const standing: StandingWork[] = [], replay: ReplayWork[] = [];
    let chars = 0;
    for (const entry of this.entries().filter(item => item.state === "checking").sort(compareRuns)) {
      if (entry.data.eligible === null) { standing.push({ entry_id: entry.entry_id, members: [entry.data.members[0].id, entry.data.members[1].id], finished_ms: entry.finished_ms }); continue; }
      const proof = this.ctx.storage.sql.exec<{ proof_hash: string; checkpoint: string }>("SELECT proof_hash,checkpoint FROM lb_proofs WHERE entry_id=?", entry.entry_id).toArray()[0];
      if (!proof || chars + proof.checkpoint.length > maxChars) continue;
      chars += proof.checkpoint.length;
      replay.push({ entry_id: entry.entry_id, chapter: entry.data.chapter, simulation_version: entry.data.simulation_version, ticks: entry.ticks, proof_hash: proof.proof_hash, checkpoint: proof.checkpoint });
    }
    return { standing, replay };
  }

  /** Account check results. An ineligible run is dropped; an eligible one keeps each member's name choice. Returns the work left and the board now. */
  standings(board: string, results: StandingResult[], maxChars = MAX_REPLAY_CHARS): { work: PendingWork; view: BoardView } {
    this.ctx.storage.transactionSync(() => {
      for (const result of results) {
        const entry = this.entry(result.entry_id);
        if (!entry || entry.state !== "checking" || entry.data.eligible !== null) continue;
        if (!result.eligible) { this.drop(entry.entry_id, "ineligible"); continue; }
        entry.data.eligible = true;
        entry.data.members.forEach((member, index) => choose(member, result.members[index]));
        this.save(entry);
      }
    });
    return { work: this.pendingWork(maxChars), view: this.view(board) };
  }

  /**
   * Replay verdicts. A verdict counts only for a checking, eligible entry whose
   * stored proof it checked. A failed replay or a measured time other than the
   * claimed one drops the run. A passed run waits for a person when it holds
   * (rules.ts holdsFor, against `developerBest`, null when unknown), else ranks
   * at once. Returns the runs that ranked.
   */
  verdicts(board: string, verdicts: Verdict[], developerBest: number | null): { ranked: RankedNote[]; view: BoardView } {
    const ranked: RankedNote[] = [];
    this.ctx.storage.transactionSync(() => {
      for (const verdict of verdicts) {
        const entry = this.entry(verdict.entry_id);
        const proof = this.ctx.storage.sql.exec<{ proof_hash: string }>("SELECT proof_hash FROM lb_proofs WHERE entry_id=?", verdict.entry_id).toArray()[0];
        if (!entry || entry.state !== "checking" || entry.data.eligible !== true || !proof || proof.proof_hash !== verdict.proof_hash) continue;
        // The job could not judge it (its build lacks the chapter, or the check broke): a person looks.
        if (!verdict.valid && REVIEW_REASONS.includes(verdict.reason)) { this.toReview(entry, [verdict.reason]); continue; }
        if (!verdict.valid || verdict.measured_ticks !== entry.ticks) { this.drop(entry.entry_id, "failed"); continue; }
        const first = this.ranked().find(item => item.pair_key !== entry.pair_key);
        const holds = holdsFor(entry.ticks, developerBest, first ? first.ticks : null);
        if (holds.length) { this.toReview(entry, holds); continue; }
        const note = this.rank(board, entry);
        if (note) ranked.push(note);
      }
    });
    return { ranked, view: this.view(board) };
  }

  /** A person's answer on a run waiting for review: approve ranks it, reject drops it. */
  review(board: string, entryId: string, approve: boolean): { done: boolean; ranked: RankedNote | null; view: BoardView } {
    let done = false, ranked: RankedNote | null = null;
    this.ctx.storage.transactionSync(() => {
      const entry = this.entry(entryId);
      if (!entry || entry.state !== "review") return;
      done = true;
      if (approve) { entry.data.holds = []; ranked = this.rank(board, entry); }
      else this.drop(entryId, "rejected");
    });
    return { done, ranked, view: this.view(board) };
  }

  /**
   * A run found fake, in any state: it goes, with every reward it earned. Players
   * it pushed down keep theirs; runs that move up into the top 10, or to a
   * strict first place, earn what that place earns.
   */
  strike(board: string, entryId: string): { done: boolean; promoted: RankedNote[]; view: BoardView } {
    let done = false;
    const promoted: RankedNote[] = [];
    this.ctx.storage.transactionSync(() => {
      // A run already gone (superseded, pushed out) still loses what it earned.
      const revoked = this.rewards.revokeEntry(entryId) > 0, present = this.entry(entryId) !== null;
      done = revoked || present || this.outcome(entryId);
      if (!done) return;
      this.drop(entryId, "struck");
      const ranked = this.ranked();
      ranked.slice(0, TOP_PLACES).forEach((entry, index) => { if (this.award(board, entry, index, ranked)) promoted.push(noteOf(entry)); });
    });
    return { done, promoted, view: this.view(board) };
  }

  /** A player's report of a ranked or reviewed run; each player counts once. Returns the number of reporters. */
  report(entryId: string, reporter: string): number | null {
    return this.ctx.storage.transactionSync(() => {
      const entry = this.entry(entryId);
      if (!entry || entry.state === "checking") return null;
      if (!entry.data.reports.includes(reporter) && entry.data.reports.length < MAX_REPORTERS) { entry.data.reports.push(reporter); this.save(entry); }
      return entry.data.reports.length;
    });
  }

  /** The runs a person should look at: waiting for review, or reported. */
  reviewList(): ReviewItem[] {
    const ranked = this.ranked();
    return this.entries().filter(entry => entry.state === "review" || entry.data.reports.length > 0).map(entry => ({
      entry_id: entry.entry_id, state: entry.state, rank: entry.state === "ranked" ? ranked.findIndex(item => item.entry_id === entry.entry_id) + 1 : null,
      ticks: entry.ticks, finished_at: entry.data.finished_at, holds: entry.data.holds, reports: entry.data.reports.length }));
  }

  /** A player's name choice and current display name, on every run of theirs here. Returns how many runs changed and the board now. */
  setMember(board: string, player: string, show: boolean, name: string | null, rev: number): { changed: number; view: BoardView } {
    const changed = this.ctx.storage.transactionSync(() => {
      let count = 0;
      for (const entry of this.entries()) {
        let touched = false;
        for (const member of entry.data.members) {
          if (member.id === player && choose(member, { show, name, rev })) touched = true;
        }
        if (touched) { this.save(entry); count++; }
      }
      return count;
    });
    return { changed, view: this.view(board) };
  }

  /** Account erasure: the player's waiting runs go, their ranked runs keep only the pair's time ("A pair"), and their rewards here go. */
  forget(board: string, player: string): { changed: number; view: BoardView } {
    const changed = this.ctx.storage.transactionSync(() => {
      let count = 0;
      for (const entry of this.entries()) {
        if (!entry.data.members.some(member => member.id === player)) continue;
        count++;
        if (entry.state !== "ranked") { this.drop(entry.entry_id, "forgotten"); continue; }
        for (const member of entry.data.members) if (member.id === player) { member.id = null; member.show = false; member.name = null; }
        this.save(entry);
        // The pair key was a hash of both ids; a random one keeps the row without them.
        this.ctx.storage.sql.exec("UPDATE lb_entries SET pair_key=? WHERE entry_id=?", crypto.randomUUID(), entry.entry_id);
      }
      this.rewards.forgetPlayer(player);
      return count;
    });
    return { changed, view: this.view(board) };
  }

  /** The cosmetics phase's read of what a player earned here (rewards.ts). */
  rewardsFor(player: string): RewardGrant[] { return this.rewards.rewardsFor(player); }

  /** Ranks a run that passed every check, inside the caller's transaction. Null when it no longer reaches the top 10. */
  private rank(board: string, entry: Entry): RankedNote | null {
    this.ctx.storage.sql.exec("DELETE FROM lb_proofs WHERE entry_id=?", entry.entry_id);
    const older = this.ranked().filter(item => item.pair_key === entry.pair_key);
    const place = [...this.ranked().filter(item => item.pair_key !== entry.pair_key), entry].sort(compareRuns).findIndex(item => item.entry_id === entry.entry_id);
    // Out of the top 10 now: it goes, and the pair keeps any run it already had.
    if (place >= TOP_PLACES) { this.drop(entry.entry_id, "not_placed"); return null; }
    entry.state = "ranked";
    this.save(entry);
    // The pair's older ranked run gives way; it keeps what it earned.
    for (const item of older) this.drop(item.entry_id, "superseded");
    const ranked = this.ranked();
    const index = ranked.findIndex(item => item.entry_id === entry.entry_id);
    this.award(board, entry, index, ranked);
    for (const below of ranked.slice(KEPT_RANKED)) this.drop(below.entry_id, "pushed_out");
    return noteOf(entry);
  }

  /** Grants what place `index` earns, once. Returns whether the entry is in the top 10. */
  private award(board: string, entry: Entry, index: number, ranked: Entry[]): boolean {
    if (index >= TOP_PLACES) return false;
    const members = entry.data.members.filter(member => member.id !== null).map(member => member.id!);
    for (const member of members) this.rewards.grant(member, "top10_ribbon", board, entry.entry_id);
    if (index === 0 && !entry.data.gold && strictlyFirst(entry.ticks, ranked.slice(1))) {
      entry.data.gold = true;
      this.save(entry);
      for (const member of members) this.rewards.grant(member, "gold_leaf", board, entry.entry_id);
    }
    return true;
  }

  /** Sends a run to a person, its proof dropped. A full review list gives up its slowest run for a faster one. */
  private toReview(entry: Entry, holds: string[]): void {
    this.ctx.storage.sql.exec("DELETE FROM lb_proofs WHERE entry_id=?", entry.entry_id);
    const pool = this.entries().filter(item => item.state === "review").sort(compareRuns);
    if (pool.length >= MAX_REVIEW) {
      if (compareRuns(entry, pool[pool.length - 1]) > 0) { this.drop(entry.entry_id, "review_full"); return; }
      this.drop(pool[pool.length - 1].entry_id, "review_full");
    }
    entry.state = "review";
    entry.data.holds = holds;
    this.save(entry);
  }

  private entries(): Entry[] {
    return this.ctx.storage.sql.exec<EntryRow>("SELECT entry_id,pair_key,state,ticks,finished_ms,data FROM lb_entries").toArray().map(row => ({ ...row, data: JSON.parse(row.data) as EntryData }));
  }
  private ranked(): Entry[] { return this.entries().filter(entry => entry.state === "ranked").sort(compareRuns); }
  private entry(id: string): Entry | null {
    const row = this.ctx.storage.sql.exec<EntryRow>("SELECT entry_id,pair_key,state,ticks,finished_ms,data FROM lb_entries WHERE entry_id=?", id).toArray()[0];
    return row ? { ...row, data: JSON.parse(row.data) as EntryData } : null;
  }
  private outcome(id: string): boolean { return this.ctx.storage.sql.exec("SELECT 1 FROM lb_outcomes WHERE entry_id=?", id).toArray().length > 0; }
  private save(entry: Entry): void {
    this.ctx.storage.sql.exec("UPDATE lb_entries SET state=?,data=? WHERE entry_id=?", entry.state, JSON.stringify(entry.data), entry.entry_id);
  }
  /** Removes a run and its proof, and leaves its tombstone. */
  private drop(id: string, outcome: string): void {
    this.ctx.storage.sql.exec("DELETE FROM lb_entries WHERE entry_id=?", id);
    this.ctx.storage.sql.exec("DELETE FROM lb_proofs WHERE entry_id=?", id);
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO lb_outcomes VALUES (?,?,?)", id, outcome, Date.now());
    this.ctx.storage.sql.exec("DELETE FROM lb_outcomes WHERE entry_id IN (SELECT entry_id FROM lb_outcomes ORDER BY at DESC, entry_id LIMIT -1 OFFSET ?)", MAX_OUTCOMES);
  }
}

/** Applies a name choice unless the member already holds a newer one. Returns whether anything changed. */
function choose(member: Member, choice: MemberChoice): boolean {
  if (member.rev !== undefined && choice.rev < member.rev) return false;
  const next = { show: choice.show, name: choice.show ? choice.name : null, rev: choice.rev };
  const changed = member.show !== next.show || member.name !== next.name || member.rev !== next.rev;
  Object.assign(member, next);
  return changed;
}

/** Both names, only when both players chose to show theirs. */
function shownNames(members: [Member, Member]): string[] | null {
  const [a, b] = members;
  return a.show && b.show && a.name && b.name ? [a.name, b.name] : null;
}
function noteOf(entry: Entry): RankedNote {
  return { entry_id: entry.entry_id, members: entry.data.members.filter(member => member.id !== null).map(member => member.id!) };
}

// A board nobody posted to answers reads as an empty board and stores nothing.
answerWhileBlank(LeaderboardBoard, {
  view: (board: string) => emptyView(board), pendingWork: () => ({ standing: [], replay: [] }), standings: (board: string) => ({ work: { standing: [], replay: [] }, view: emptyView(board) }),
  verdicts: (board: string) => ({ ranked: [], view: emptyView(board) }), review: (board: string) => ({ done: false, ranked: null, view: emptyView(board) }),
  strike: (board: string) => ({ done: false, promoted: [], view: emptyView(board) }), report: () => null, reviewList: () => [],
  setMember: (board: string) => ({ changed: 0, view: emptyView(board) }), forget: (board: string) => ({ changed: 0, view: emptyView(board) }), rewardsFor: () => []
});
