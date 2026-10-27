import { DurableObject } from "cloudflare:workers";
import { answerWhileBlank, openLazyStorage } from "../lazy-storage";
import { knownBoard } from "./boards";

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
    this.ctx.storage.transactionSync(() => this.write({ ...blank(), erased: true }));
  }
  private write(state: MemberState): void {
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO lb_member VALUES (1,?)", JSON.stringify(state));
  }
}

// A player who never touched leaderboards reads as the default and stores nothing.
answerWhileBlank(LeaderboardMember, { read: () => blank() });
