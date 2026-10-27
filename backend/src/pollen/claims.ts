import { DurableObject } from "cloudflare:workers";
import { digest } from "../protocol";
import { SUB_ID_PATTERN, type ClaimAnswer } from "./grant";

/**
 * PollenClaims: one global object that knows which identity holds each store subscription (and the
 * old Lifetime purchase), so a subscription moved to another App User ID by a store restore never
 * pays the same month to both (POLLEN-RULES.md "Store check and counter").
 *
 * - Asked only by a Player, from inside a wallet read that already found an instalment due, and only
 *   for a subscription new to that identity (or one not looked at for RECLAIM_AFTER_MS): about one
 *   request per new subscription, never one per month.
 * - Keyed by RevenueCat's subscription id ("sub:<id>") or purchase id ("purchase:<id>"). The holder
 *   is kept only as a SHA-256 of the player id, so this object never names a player, and account
 *   erasure leaves the row as the record of a store purchase that was already granted for.
 * - claim answers { self: true, since } to the holder (since: when it became the holder), and to a
 *   new identity { self: false, since: now } after making it the holder: the move is recorded once,
 *   and the identity it moved from sees a later `since` the next time it asks.
 * - A repeat of the same claim changes nothing, so a retried wallet read is harmless.
 */
export const POLLEN_CLAIMS_OBJECT = "pollen-claims-v1";
export const MAX_CLAIM_KEYS = 16;
export const CLAIM_KEY_PATTERN = new RegExp(`^(sub|purchase):${SUB_ID_PATTERN.source.slice(1, -1)}$`);
const SCHEMA = "CREATE TABLE IF NOT EXISTS pollen_claims_held (claim_key TEXT PRIMARY KEY, holder TEXT NOT NULL, since INTEGER NOT NULL) WITHOUT ROWID";
const HASH = /^[a-f0-9]{64}$/;

export class PollenClaims extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => { this.ctx.storage.sql.exec(SCHEMA); });
  }
  /** Binding only: the holder of each key, made `holder` where it was someone else's or nobody's. */
  claim(keys: string[], holder: string, now: number): Record<string, ClaimAnswer> | null {
    if (!Array.isArray(keys) || keys.length < 1 || keys.length > MAX_CLAIM_KEYS || !keys.every(key => typeof key === "string" && CLAIM_KEY_PATTERN.test(key)) ||
      typeof holder !== "string" || !HASH.test(holder) || !Number.isSafeInteger(now) || now <= 0) return null;
    return this.ctx.storage.transactionSync(() => {
      const answers: Record<string, ClaimAnswer> = {};
      for (const key of new Set(keys)) {
        const row = this.ctx.storage.sql.exec<{ holder: string; since: number }>("SELECT holder, since FROM pollen_claims_held WHERE claim_key=?", key).toArray()[0];
        if (row?.holder === holder) { answers[key] = { self: true, since: row.since }; continue; }
        this.ctx.storage.sql.exec("INSERT OR REPLACE INTO pollen_claims_held VALUES (?,?,?)", key, holder, now);
        answers[key] = { self: !row, since: now };
      }
      return answers;
    });
  }
}

export const subscriptionClaimKey = (id: string) => `sub:${id}`;
export const purchaseClaimKey = (id: string) => `purchase:${id}`;

/** Claims `keys` for `playerId`; null when the object could not be asked (nothing is paid on that read). */
export async function claimFor(env: Env, playerId: string, keys: string[], now: number): Promise<Record<string, ClaimAnswer> | null> {
  try {
    return await env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT).claim(keys, await digest("pollen-claims|" + playerId), now);
  } catch { return null; }
}
