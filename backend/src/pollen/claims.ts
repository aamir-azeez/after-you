import { DurableObject } from "cloudflare:workers";
import type { ServerVars } from "../flags";
import { KEY_LABELS, derivedKey, hmac } from "./keys";
import { SUB_ID_PATTERN, type ClaimAnswer } from "./grant";

/**
 * PollenClaims: one global object that knows which identity holds each store subscription (and the
 * old Lifetime purchase), so a subscription moved to another App User ID by a store restore never
 * pays the same month to two identities (POLLEN-RULES.md "Store check and counter").
 *
 * - Asked only by a Player, from inside a wallet read that already found something due: about one
 *   request per subscriber per month, with every listed subscription in it (grant.ts claimsNeeded).
 * - Keyed by RevenueCat's subscription id ("sub:<id>", kept through renewals) or purchase id
 *   ("purchase:<id>"). The holder is kept only as an HMAC of the player id under a key derived from
 *   POLLEN_SECRET, so no row here can be tied to a player; account erasure leaves the row as the
 *   record of a store purchase already granted for.
 * - Each row: the holder, `since` (when it became the holder) and `moved` (it came from another
 *   holder). The holder's answer is { self: !moved, since }, the same on every repeat, so a retried
 *   or reordered read plans the same. A new holder takes the row with since = now and moved = true;
 *   the identity it moved from sees a later `since` when it holds it again.
 * - Pollen bundles (claimBundles) are the other way round: the first identity to claim a Google Play order
 *   ("order:<order>") keeps it for good, so a restore that moves a consumable to a new App User ID, or gives it
 *   a new RevenueCat id, never mints its Pollen twice. Rows keyed "bundle:<RevenueCat purchase id>" came first;
 *   none were written before the shop opened, but one is still read when its order has no row yet.
 */
export const POLLEN_CLAIMS_OBJECT = "pollen-claims-v1";
export const MAX_CLAIM_KEYS = 16;
export const CLAIM_KEY_PATTERN = new RegExp(`^(sub|purchase):${SUB_ID_PATTERN.source.slice(1, -1)}$`);
/** A Pollen bundle's Google Play order ("order:<order>", the order in the same characters as an id): only claimBundles takes these, and claim() never moves one. */
export const ORDER_CLAIM_KEY_PATTERN = new RegExp(`^order:${SUB_ID_PATTERN.source.slice(1, -1)}$`);
/** The older bundle key ("bundle:<RevenueCat purchase id>"), only ever read now. */
export const BUNDLE_CLAIM_KEY_PATTERN = new RegExp(`^bundle:${SUB_ID_PATTERN.source.slice(1, -1)}$`);
const orderClaimKey = (order: string) => `order:${order}`;
const olderClaimKey = (id: string) => `bundle:${id}`;
const SCHEMA = "CREATE TABLE IF NOT EXISTS pollen_claims_held (claim_key TEXT PRIMARY KEY, holder TEXT NOT NULL, since INTEGER NOT NULL, moved INTEGER NOT NULL) WITHOUT ROWID";
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
        const row = this.ctx.storage.sql.exec<{ holder: string; since: number; moved: number }>("SELECT holder, since, moved FROM pollen_claims_held WHERE claim_key=?", key).toArray()[0];
        if (row?.holder === holder) { answers[key] = { self: row.moved === 0, since: row.since }; continue; }
        this.ctx.storage.sql.exec("INSERT OR REPLACE INTO pollen_claims_held VALUES (?,?,?,?)", key, holder, now, row ? 1 : 0);
        answers[key] = { self: !row, since: now };
      }
      return answers;
    });
  }
  /**
   * Binding only: whether `holder` holds each bundle order (`keys`, "order:<order>"), the first holder for good.
   * An order nobody holds becomes the holder's (true); one another holder took first answers false and never
   * moves. `older` may name, at the same index, the purchase's older "bundle:<id>" key: while the order has no
   * row, whoever holds that one holds the order.
   */
  claimBundles(keys: string[], holder: string, now: number, older: (string | null)[] = []): Record<string, boolean> | null {
    if (!Array.isArray(keys) || keys.length < 1 || keys.length > MAX_CLAIM_KEYS || !keys.every(key => typeof key === "string" && ORDER_CLAIM_KEY_PATTERN.test(key)) ||
      !Array.isArray(older) || older.length > keys.length || !older.every(key => key === null || (typeof key === "string" && BUNDLE_CLAIM_KEY_PATTERN.test(key))) ||
      typeof holder !== "string" || !HASH.test(holder) || !Number.isSafeInteger(now) || now <= 0) return null;
    const holderOf = (key: string) => this.ctx.storage.sql.exec<{ holder: string }>("SELECT holder FROM pollen_claims_held WHERE claim_key=?", key).toArray()[0]?.holder;
    return this.ctx.storage.transactionSync(() => {
      const answers: Record<string, boolean> = {};
      keys.forEach((key, index) => {
        let owner = holderOf(key);
        if (owner === undefined) {
          const before = older[index];
          owner = (before ? holderOf(before) : undefined) ?? holder;
          this.ctx.storage.sql.exec("INSERT INTO pollen_claims_held VALUES (?,?,?,0)", key, owner, now);
        }
        answers[key] = owner === holder;
      });
      return answers;
    });
  }
}

const hex = (bytes: Uint8Array) => [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("");

/** Claims `keys` for `playerId`; null when the object could not be asked (nothing is paid on that read). */
export async function claimFor(env: Env & ServerVars, playerId: string, keys: string[], now: number): Promise<Record<string, ClaimAnswer> | null> {
  try {
    const key = derivedKey(env, KEY_LABELS.claims);
    if (key === null) return null;
    return await env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT).claim(keys, hex(await hmac(await key, playerId)), now);
  } catch { return null; }
}

/**
 * Claims each bundle purchase's Play order for `playerId` (claimBundles, with its RevenueCat id for the older key):
 * whether this player holds it, by order. Null when the object could not be asked (nothing is credited then).
 */
export async function claimBundlesFor(env: Env & ServerVars, playerId: string, purchases: readonly { order: string; id: string }[], now: number): Promise<Record<string, boolean> | null> {
  try {
    const key = derivedKey(env, KEY_LABELS.claims);
    if (key === null) return null;
    const answers = await env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT).claimBundles(purchases.map(each => orderClaimKey(each.order)), hex(await hmac(await key, playerId)), now, purchases.map(each => olderClaimKey(each.id)));
    return answers === null ? null : Object.fromEntries(purchases.map(each => [each.order, answers[orderClaimKey(each.order)] === true]));
  } catch { return null; }
}
