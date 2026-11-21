import { DurableObject } from "cloudflare:workers";
import { ID_PATTERN } from "./protocol";
import { CLAIM_GRACE_MS, usernameShaped } from "./usernames";

/**
 * One shard of the username index (usernames.ts usernameShard picks it): a row per lowercase name with the player
 * that claimed it. The row is only the lock that makes a claim atomic; the holder's Player says whether it still holds
 * the name. Every method is one statement or one read and one write, so the object's own ordering makes each atomic.
 *
 * - `rev` rises on every write, so a take over based on an older read changes nothing.
 * - `retired`: a name a moderator cleared; nobody may claim it again.
 */
export const USERNAME_INDEX_TABLE = "CREATE TABLE IF NOT EXISTS usernames (key TEXT PRIMARY KEY, owner TEXT NOT NULL, rev INTEGER NOT NULL, claimed_at INTEGER NOT NULL, retired INTEGER NOT NULL) WITHOUT ROWID";
type IndexRow = { owner: string; rev: number; claimed_at: number; retired: number };
export type IndexClaim = { ok: true } | { ok: false; code: "username_taken" } | { ok: false; code: "username_check"; owner: string; rev: number };

const lowerKey = (key: string): boolean => usernameShaped(key) && key === key.toLowerCase();

export class UsernameIndex extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => { ctx.storage.sql.exec(USERNAME_INDEX_TABLE); });
  }
  private row(key: string): IndexRow | null {
    return this.ctx.storage.sql.exec<IndexRow>("SELECT owner, rev, claimed_at, retired FROM usernames WHERE key=?", key).toArray()[0] ?? null;
  }
  private write(key: string, owner: string, rev: number, now: number, retired = 0): void {
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO usernames VALUES (?,?,?,?,?)", key, owner, rev, now, retired);
  }
  /**
   * Binding only. Free or already `player`'s: claimed (the row's time moves, so a check in flight cannot take it).
   * A retired name, or another player's claim younger than CLAIM_GRACE_MS: taken. An older claim: the caller asks that
   * player's Player and may take it over with takeOver.
   */
  claim(key: string, player: string, now: number): IndexClaim {
    if (!lowerKey(key) || !ID_PATTERN.test(player)) return { ok: false, code: "username_taken" };
    const row = this.row(key);
    if (row?.retired) return { ok: false, code: "username_taken" };
    if (row && row.owner !== player) return row.claimed_at > now - CLAIM_GRACE_MS ? { ok: false, code: "username_taken" } : { ok: false, code: "username_check", owner: row.owner, rev: row.rev };
    this.write(key, player, (row?.rev ?? 0) + 1, now);
    return { ok: true };
  }
  /** Binding only: `player` takes the name, if the row is still `owner`'s at `rev` (its Player said it no longer holds it). */
  takeOver(key: string, player: string, owner: string, rev: number, now: number): boolean {
    const row = this.row(key);
    if (!row || row.retired || row.owner !== owner || row.rev !== rev || !ID_PATTERN.test(player)) return false;
    this.write(key, player, rev + 1, now);
    return true;
  }
  /** Binding only: the player a name points to, or null (none, or retired). */
  lookup(key: string): string | null {
    const row = this.row(key);
    return row && !row.retired ? row.owner : null;
  }
  /** Binding only: forgets `player`'s claim (an erased account, a claim whose Player change failed). A retired row stays. */
  release(key: string, player: string): void {
    this.ctx.storage.sql.exec("DELETE FROM usernames WHERE key=? AND owner=? AND retired=0", key, player);
  }
  /** Binding only (the moderator clear): nobody may claim the name again. */
  retire(key: string, player: string, now: number): void {
    if (!lowerKey(key)) return;
    this.write(key, player, (this.row(key)?.rev ?? 0) + 1, now, 1);
  }
}
