import { DurableObject } from "cloudflare:workers";
import { answerWhileBlank, openLazyStorage } from "../lazy-storage";
import { knownBoard } from "./boards";

/**
 * One player's leaderboard settings, one Durable Object per player id: whether
 * they show their name on boards ("Show my name on leaderboards", off by
 * default) and the boards that hold a ranked run of theirs, so a name change,
 * an operator clear or an account erasure reaches only those boards.
 *
 * Its own object, not the Player: the Player's portable snapshot accepts only
 * its known tables, and this needs none of the Player's reads.
 */
export type MemberState = { schema_version: 1; show_name: boolean; boards: string[] };

const DEFAULT: MemberState = Object.freeze({ schema_version: 1, show_name: false, boards: [] }) as MemberState;

export class LeaderboardMember extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => openLazyStorage(this, ctx.storage, "lb_member", () => {
      ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS lb_member (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)");
    }));
  }
  read(): MemberState {
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM lb_member WHERE id=1").toArray()[0];
    return row ? JSON.parse(row.data) as MemberState : { ...DEFAULT, boards: [] };
  }
  /** Sets the name choice; returns the state, whose boards the caller tells. */
  setShowName(show: boolean): MemberState {
    return this.ctx.storage.transactionSync(() => {
      const state = this.read();
      if (state.show_name !== show) { state.show_name = show; this.write(state); }
      return state;
    });
  }
  /** Remembers a board that now ranks a run of this player's. */
  noteBoard(board: string): MemberState {
    return this.ctx.storage.transactionSync(() => {
      const state = this.read(), known = knownBoard(board);
      if (known && !state.boards.includes(known)) { state.boards.push(known); this.write(state); }
      return state;
    });
  }
  /** Account erasure: returns the boards to tell and keeps nothing. */
  forget(): string[] {
    return this.ctx.storage.transactionSync(() => {
      const boards = this.read().boards;
      this.ctx.storage.sql.exec("DELETE FROM lb_member");
      return boards;
    });
  }
  private write(state: MemberState): void {
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO lb_member VALUES (1,?)", JSON.stringify(state));
  }
}

// A player who never touched leaderboards reads as the default and stores nothing.
answerWhileBlank(LeaderboardMember, { read: () => ({ ...DEFAULT, boards: [] }), forget: () => [] });
