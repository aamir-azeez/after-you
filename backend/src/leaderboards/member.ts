import { DurableObject } from "cloudflare:workers";
import { answerWhileBlank, openLazyStorage } from "../lazy-storage";
import { knownBoard } from "./boards";
import { fail, type Outcome } from "../protocol";
import { applyParty, blankParty, parsedParty, prune, type PartyAnswer, type PartyOp, type PartyState } from "../duels/party";

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
export type MemberState = { schema_version: 1; show_name: boolean; boards: string[]; revision: number; erased?: true };

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
  /** Sets the name choice (or, with `show` undefined, keeps it) and moves the revision on; returns the state, whose boards the caller tells. */
  touch(show?: boolean): MemberState {
    return this.ctx.storage.transactionSync(() => {
      const state = this.read();
      if (state.erased) return state;
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
  /** Account erasure: keeps nothing but the mark that the player is gone. */
  forget(): void {
    this.ctx.storage.transactionSync(() => {
      this.write({ ...blank(), erased: true });
      this.ctx.storage.sql.exec("DROP TABLE IF EXISTS duel_party");
    });
  }
  /** The duel party and pointers (duels/party.ts) as of `now`; blank for a player who never duelled. Reads only. */
  partyRead(now: number): PartyState {
    const state = this.partyRow();
    prune(state, now);
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
answerWhileBlank(LeaderboardMember, { read: () => blank(), partyRead: () => blankParty() });
