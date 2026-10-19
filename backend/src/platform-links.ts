import { DurableObject } from "cloudflare:workers";

/**
 * Links a verified platform games account (Play Games or Game Center) to one After You player.
 *
 * One named object holds every link, so a link is one request and one row, a restore is one
 * request and one indexed read, and erasure by player id needs no pointer stored on the Player
 * (whose identity record and snapshot schema stay unchanged). The external id is kept only as a
 * SHA-256 of "provider:id"; nothing here can name the platform account.
 *
 * Rules:
 * - one link per provider account, and one per player and provider;
 * - an account already linked to another player answers "conflict" and changes nothing unless the
 *   caller asked to replace it (the player chose this device's identity on purpose);
 * - a player already linked to another account of the same provider answers "other_account";
 * - unlink and erase delete only rows that point at that player, so repeats are harmless.
 */
export const PLATFORM_LINKS_OBJECT = "platform-links-v1";
export const PLATFORM_PROVIDERS = ["play_games", "game_center"] as const;
export type PlatformProvider = typeof PLATFORM_PROVIDERS[number];
export type LinkStatus = "linked" | "conflict" | "other_account";
export type LinkAnswer = { status: LinkStatus; changed: boolean } | { status: "replayed"; changed: false };

const SCHEMA = [
  "CREATE TABLE IF NOT EXISTS platform_links (provider TEXT NOT NULL, external_hash TEXT NOT NULL, player_id TEXT NOT NULL, linked_at INTEGER NOT NULL, PRIMARY KEY (provider, external_hash)) WITHOUT ROWID",
  "CREATE UNIQUE INDEX IF NOT EXISTS platform_links_player ON platform_links (player_id, provider)",
  "CREATE TABLE IF NOT EXISTS platform_nonces (nonce TEXT PRIMARY KEY, expires_at INTEGER NOT NULL) WITHOUT ROWID",
];
const HASH = /^[a-f0-9]{64}$/, PLAYER = /^[a-zA-Z0-9_-]{22}$/;
const validProvider = (value: string): value is PlatformProvider => (PLATFORM_PROVIDERS as readonly string[]).includes(value);

export class PlatformLinks extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => { for (const statement of SCHEMA) this.ctx.storage.sql.exec(statement); });
  }
  private owner(provider: string, externalHash: string): string | null {
    return this.ctx.storage.sql.exec<{ player_id: string }>("SELECT player_id FROM platform_links WHERE provider=? AND external_hash=?", provider, externalHash).toArray()[0]?.player_id ?? null;
  }
  /**
   * A signature that may only be used once (Game Center). False when it was seen before its expiry.
   * Expired entries are swept a few at a time so the table stays small.
   */
  private claim(nonce: string | undefined, expiresAt: number): boolean {
    if (nonce === undefined) return true;
    if (!HASH.test(nonce)) return false;
    const now = Date.now();
    this.ctx.storage.sql.exec("DELETE FROM platform_nonces WHERE nonce IN (SELECT nonce FROM platform_nonces WHERE expires_at<? LIMIT 16)", now);
    return this.ctx.storage.sql.exec("INSERT OR IGNORE INTO platform_nonces (nonce, expires_at) VALUES (?, ?)", nonce, Math.max(expiresAt, now)).rowsWritten > 0;
  }

  link(provider: string, externalHash: string, playerId: string, replace: boolean, nonce?: string, nonceExpiresAt = 0): LinkAnswer {
    if (!validProvider(provider) || !HASH.test(externalHash) || !PLAYER.test(playerId)) throw new Error("invalid_platform_link");
    return this.ctx.storage.transactionSync((): LinkAnswer => {
      if (!this.claim(nonce, nonceExpiresAt)) return { status: "replayed", changed: false };
      const current = this.owner(provider, externalHash);
      if (current === playerId) return { status: "linked", changed: false };
      const mine = this.ctx.storage.sql.exec<{ external_hash: string }>("SELECT external_hash FROM platform_links WHERE player_id=? AND provider=?", playerId, provider).toArray()[0];
      if (current !== null && !replace) return { status: "conflict", changed: false };
      if (current === null && mine && !replace) return { status: "other_account", changed: false };
      if (current !== null) this.ctx.storage.sql.exec("DELETE FROM platform_links WHERE provider=? AND external_hash=?", provider, externalHash);
      if (mine) this.ctx.storage.sql.exec("DELETE FROM platform_links WHERE player_id=? AND provider=?", playerId, provider);
      this.ctx.storage.sql.exec("INSERT INTO platform_links (provider, external_hash, player_id, linked_at) VALUES (?, ?, ?, ?)", provider, externalHash, playerId, Date.now());
      return { status: "linked", changed: true };
    });
  }
  /** The linked player, null when none, or "replayed" for a reused one-time signature. */
  lookup(provider: string, externalHash: string, nonce?: string, nonceExpiresAt = 0): { player_id: string | null } | { replayed: true } {
    if (!validProvider(provider) || !HASH.test(externalHash)) throw new Error("invalid_platform_link");
    return this.ctx.storage.transactionSync(() => {
      if (!this.claim(nonce, nonceExpiresAt)) return { replayed: true as const };
      return { player_id: this.owner(provider, externalHash) };
    });
  }
  /** Drops a link that points at a player who no longer exists (found during a restore). */
  forget(provider: string, externalHash: string, playerId: string): boolean {
    return this.ctx.storage.sql.exec("DELETE FROM platform_links WHERE provider=? AND external_hash=? AND player_id=?", provider, externalHash, playerId).rowsWritten > 0;
  }
  unlink(provider: string, playerId: string): boolean {
    if (!validProvider(provider) || !PLAYER.test(playerId)) throw new Error("invalid_platform_link");
    return this.ctx.storage.sql.exec("DELETE FROM platform_links WHERE player_id=? AND provider=?", playerId, provider).rowsWritten > 0;
  }
  /** Account erasure: every provider's link for this player. Safe to repeat. */
  eraseOwner(playerId: string): number {
    if (!PLAYER.test(playerId)) return 0;
    return this.ctx.storage.sql.exec("DELETE FROM platform_links WHERE player_id=?", playerId).rowsWritten;
  }
  /** Tests and operator checks only: is this player linked for this provider. */
  linkedProviders(playerId: string): string[] {
    return this.ctx.storage.sql.exec<{ provider: string }>("SELECT provider FROM platform_links WHERE player_id=? ORDER BY provider", playerId).toArray().map(row => row.provider);
  }
}
