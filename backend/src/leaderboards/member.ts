import { DurableObject } from "cloudflare:workers";
import { answerWhileBlank, openLazyStorage } from "../lazy-storage";
import { knownBoard } from "./boards";
import { fail, type Outcome } from "../protocol";
import { applyParty, blankParty, noteLook, parsedParty, prune, type DuelRef, type PartyAnswer, type PartyOp, type PartyState } from "../duels/party";
import type { Look } from "../pollen/catalog";
import { MemoryBudget } from "../limits";
import { MAX_BLOCKED_BY, PUBLIC_REPORTS_TO_PAUSE, PUBLIC_REPORT_WINDOW_MS } from "../duels/rules";

/**
 * One player's leaderboard settings, one Durable Object per player id: whether
 * they show their name on boards ("Show my name on leaderboards", off by
 * default) and the boards that hold a run of theirs, so a name change or an
 * operator clear reaches only those boards.
 *
 * `revision` goes up on every change and every name sync, and boards keep the
 * revision each member's choice came from, so an account check that read the
 * choice earlier can never write it back over a newer one (board.ts choose).
 * An erased player keeps only `erased`, so a check that was already under way
 * can never add them to a board again.
 *
 * Its own object, not the Player: the Player's portable snapshot accepts only
 * its known tables, and this needs none of the Player's reads.
 *
 * Duels keep the player's party and duel pointers here too (duels/party.ts),
 * in their own row, made by the first party or duel write. That write also
 * moves the revision on, so account erasure (members.ts) never skips a
 * player whose only trace is a duel.
 */
/**
 * Public duels (duels/public.ts) keep five optional keys here, absent until used, so a row nobody used for them reads
 * byte for byte as before: `public_off` (the player turned the switch off; absent is the default, on, and only
 * publicDuelsChosen reads it), `blocked_by` (players who blocked
 * this one, so their duels never list for them), `public_reports` (reports from public duels, newest last, inside
 * PUBLIC_REPORT_WINDOW_MS) and `public_paused` (set at PUBLIC_REPORTS_TO_PAUSE different reporters; only an operator
 * clears it). `duel_blocks`: players this one blocked from a public duel without knowing their id; the phone sees
 * each only by its handle and label (duels/public-routes.ts), the SafetyProfile holds the block itself.
 */
export type PublicReport = { from: string; at: number };
export type DuelBlock = { handle: string; id: string; label: string | null; at: number };
export type MemberState = { schema_version: 1; show_name: boolean; boards: string[]; revision: number; erased?: true;
  public_off?: true; blocked_by?: string[]; public_reports?: PublicReport[]; public_paused?: true; duel_blocks?: DuelBlock[] };

/**
 * Whether the player has public duels on: on unless they turned the switch off (owner, 2026-11-03: on by default, off in
 * Settings, for example on a child's phone). The one place that decides it; the phone shows the same default until the
 * server's first word (game/services/duels_client.gd public_on).
 */
export function publicDuelsChosen(state: Pick<MemberState, "public_off">): boolean { return !state.public_off; }
/** Whether strangers may meet the player in a public duel: switch on and not paused after reports. */
export function publicOpenTo(state: Pick<MemberState, "public_off" | "public_paused">): boolean { return publicDuelsChosen(state) && !state.public_paused; }

/** A repeated name choice tells the boards again at most this often (LeaderboardMember.touch). */
export const MEMBER_REPEAT_GAP_MS = 10 * 60_000;
/** Name choice changes a player makes an hour at most; each rewrites their rows on every board. */
export const MEMBER_CHANGES_PER_HOUR = 6;

function blank(): MemberState { return { schema_version: 1, show_name: false, boards: [], revision: 0 }; }

export class LeaderboardMember extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => openLazyStorage(this, ctx.storage, "lb_member", () => {
      ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS lb_member (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)");
    }));
  }
  read(): MemberState {
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM lb_member WHERE id=1").toArray()[0];
    return row ? { ...blank(), ...JSON.parse(row.data) as MemberState } : blank();
  }
  /** When a repeated choice last told the boards (memory only): at most once per MEMBER_REPEAT_GAP_MS. */
  private repeatedAt = 0;
  /** Name choice changes this hour (memory only): MEMBER_CHANGES_PER_HOUR. */
  private readonly changes = new MemoryBudget(MEMBER_CHANGES_PER_HOUR, 3_600_000);
  /**
   * Sets the name choice (or, with `show` undefined, keeps it) and moves the revision on; returns the state, whose boards the caller tells.
   * A choice the member already holds writes nothing and keeps the revision, so the boards save only where they missed one
   * (a reply lost after a partial update). `quiet`: nothing was done, a repeat within MEMBER_REPEAT_GAP_MS of the last or a change past
   * MEMBER_CHANGES_PER_HOUR; the route answers it retryable, so the phone keeps its choice and sends it again later.
   */
  touch(show?: boolean): MemberState & { quiet?: true } {
    return this.ctx.storage.transactionSync(() => {
      const state = this.read();
      if (state.erased) return state;
      const now = Date.now();
      if (show !== undefined && show === state.show_name) {
        if (now - this.repeatedAt < MEMBER_REPEAT_GAP_MS) return { ...state, quiet: true as const };
        this.repeatedAt = now;
        return state;
      }
      // A real change rewrites the player's rows on every board: a few an hour (memory only).
      if (show !== undefined && !this.changes.take(now)) return { ...state, quiet: true as const };
      if (show !== undefined) state.show_name = show;
      state.revision++;
      this.write(state);
      return state;
    });
  }
  /** Remembers a board that holds a run of this player's; an erased player is never added. */
  noteBoard(board: string): MemberState {
    return this.ctx.storage.transactionSync(() => {
      const state = this.read(), known = knownBoard(board);
      if (state.erased) return state;
      if (known && !state.boards.includes(known)) { state.boards.push(known); this.write(state); }
      return state;
    });
  }
  /**
   * The public duels switch: off is stored, on is the default and stores nothing. Turning it on is the caller's to allow
   * (the community rules, duels/public-routes.ts).
   */
  setPublicDuels(on: boolean): MemberState {
    return this.change(held => {
      if (publicDuelsChosen(held) === on) return false;
      if (on) delete held.public_off; else held.public_off = true;
      return true;
    });
  }
  /**
   * A public duel's pointer (as duels/routes.ts addRefs keeps it) and, in the same request, whether strangers may still
   * meet this player: a switch turned off, or a pause, while their post or join was on its way leaves that duel to be
   * hidden (duels/public-routes.ts addPublicRefs).
   */
  addPublicRef(owner: string, ref: DuelRef, now: number): { open: boolean } {
    const added = this.partyApply(owner, { kind: "add_duels", refs: [ref] }, now);
    return { open: added.ok && publicOpenTo(this.read()) };
  }
  /** `peer` blocked this player (or took it back): the public list hides their duels from this player. */
  noteBlockedBy(peer: string, blocked: boolean): MemberState {
    return this.change(state => {
      const list = state.blocked_by ?? [], has = list.includes(peer);
      if (has === blocked) return false;
      const next = blocked ? [...list, peer].slice(-MAX_BLOCKED_BY) : list.filter(id => id !== peer);
      if (next.length) state.blocked_by = next; else delete state.blocked_by;
      return true;
    });
  }
  /**
   * A report from a public duel (duels/public-routes.ts). Reports older than the window go; one reporter counts once.
   * Answers the state and whether this report paused the player.
   */
  publicReport(from: string, now: number): { state: MemberState; paused_now: boolean } {
    let pausedNow = false;
    const state = this.change(held => {
      const recent = (held.public_reports ?? []).filter(item => now - item.at < PUBLIC_REPORT_WINDOW_MS);
      const fresh = recent.some(item => item.from === from) ? recent : [...recent, { from, at: now }].slice(-PUBLIC_REPORTS_TO_PAUSE * 4);
      const changed = JSON.stringify(fresh) !== JSON.stringify(held.public_reports ?? []);
      if (fresh.length) held.public_reports = fresh; else delete held.public_reports;
      if (!held.public_paused && new Set(fresh.map(item => item.from)).size >= PUBLIC_REPORTS_TO_PAUSE) { held.public_paused = true; pausedNow = true; return true; }
      return changed;
    });
    return { state, paused_now: pausedNow };
  }
  /** Keeps a block made from a public duel by its handle (a repeat keeps one). */
  addDuelBlock(entry: DuelBlock): MemberState {
    return this.change(state => {
      if ((state.duel_blocks ?? []).some(item => item.id === entry.id)) return false;
      state.duel_blocks = [...(state.duel_blocks ?? []), entry].slice(-MAX_BLOCKED_BY);
      return true;
    });
  }
  /** Forgets a public duel block by its handle; answers the blocked id, or null when there was none. */
  removeDuelBlock(handle: string): string | null {
    let id: string | null = null;
    this.change(state => {
      const found = (state.duel_blocks ?? []).find(item => item.handle === handle);
      if (!found) return false;
      id = found.id;
      const rest = state.duel_blocks!.filter(item => item.handle !== handle);
      if (rest.length) state.duel_blocks = rest; else delete state.duel_blocks;
      return true;
    });
    return id;
  }
  /** The party row (as partyRead) and these settings, in one request: what the public duel routes need. */
  publicRead(now: number, look?: Look): { party: PartyState; member: MemberState } {
    return { party: this.partyRead(now, look), member: this.read() };
  }
  /** The operator's clear of a pause; the reports that led to it go too. */
  clearPublicPause(): MemberState {
    return this.change(state => {
      if (!state.public_paused && !state.public_reports) return false;
      delete state.public_paused;
      delete state.public_reports;
      return true;
    });
  }
  /** One change of the row in a transaction, written only when `apply` says it changed; an erased player changes nothing. */
  private change(apply: (state: MemberState) => boolean): MemberState {
    return this.ctx.storage.transactionSync(() => {
      const state = this.read();
      if (!state.erased && apply(state)) this.write(state);
      return state;
    });
  }
  /** Account erasure: keeps nothing but the mark that the player is gone. */
  forget(): void {
    this.ctx.storage.transactionSync(() => {
      this.write({ ...blank(), erased: true });
      this.ctx.storage.sql.exec("DROP TABLE IF EXISTS duel_party");
    });
  }
  /**
   * The duel party and pointers (duels/party.ts) as of `now`; blank for a player who never duelled. Reads only,
   * except that `look` (the owner's own look on their duel reads while looks are on) is kept in a row that
   * exists when it changed: one row write per change of look, never a new row.
   */
  partyRead(now: number, look?: Look): PartyState {
    const state = this.partyRow();
    prune(state, now);
    // The row as read, before pruning, is written back with only the look changed; an unchanged look reads nothing more.
    if (look !== undefined && noteLook(state, look) && this.hasPartyTable()) {
      const stored = this.partyRow();
      if (noteLook(stored, look)) this.ctx.storage.sql.exec("INSERT OR REPLACE INTO duel_party VALUES (1,?)", JSON.stringify(stored));
    }
    return state;
  }
  /** One party op for `owner`, in one transaction. An erased player changes nothing. */
  partyApply(owner: string, op: PartyOp, now: number): Outcome<PartyAnswer> {
    return this.ctx.storage.transactionSync((): Outcome<PartyAnswer> => {
      if (this.read().erased) return fail(404, "identity_absent");
      const state = this.partyRow(), before = JSON.stringify(state);
      const answer = applyParty(state, owner, op, now);
      if (!answer.ok || JSON.stringify(answer.value.state) === before) return answer;
      if (!this.hasPartyTable()) {
        this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS duel_party (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)");
        const member = this.read();
        member.revision++;
        this.write(member);
      }
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO duel_party VALUES (1,?)", JSON.stringify(answer.value.state));
      return answer;
    });
  }
  private hasPartyTable(): boolean {
    return this.ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name='duel_party'").toArray().length > 0;
  }
  private partyRow(): PartyState {
    if (!this.hasPartyTable()) return blankParty();
    return parsedParty(this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM duel_party WHERE id=1").toArray()[0]?.data);
  }
  private write(state: MemberState): void {
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO lb_member VALUES (1,?)", JSON.stringify(state));
  }
}

// A player who never touched leaderboards reads as the default and stores nothing.
answerWhileBlank(LeaderboardMember, { read: () => blank(), partyRead: () => blankParty(), publicRead: () => ({ party: blankParty(), member: blank() }), removeDuelBlock: () => null });
