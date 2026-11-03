import { DurableObject } from "cloudflare:workers";
import { answerWhileBlank, openLazyStorage } from "../lazy-storage";
import type { ListingChange } from "./store";
import type { Listing } from "./public";
import { MAX_DIRECTORY_ROWS } from "./rules";

/**
 * The public duel list across every chapter: one instance (DIRECTORY_NAME), one table with a row per listed duel.
 * The chapter boards stay the truth (duels/store.ts): each board sends a duel's new listing after a save that
 * changed it (a post, a seat taken or freed, steps, a label, off the list), and the list may lag a moment behind.
 * A tap always goes to the board, so a stale row answers spot_taken and is redrawn from the board's answer.
 *
 * Writes: one row per change sent, plus the timed out rows each put clears. Reads write nothing: `list` filters
 * by time, and the Worker caches its answer (public-list.ts) and filters it per reader, so ids stay on the server.
 * Changes may arrive late or twice (each save's own waitUntil, a route's repeat): each row keeps the duel's
 * `updated_ms`, an older change is ignored, and a duel taken off the list keeps a small closed row (open_until_ms 0)
 * for TOMBSTONE_MS, so a late listing can never put it back.
 * Optional: a Worker without the binding sends no changes and reads the list from nowhere (empty).
 */
export const DIRECTORY_NAME = "public-duels-v1";
const TOMBSTONE_MS = 3_600_000;
const TABLE = "CREATE TABLE IF NOT EXISTS listings (duel_id TEXT PRIMARY KEY, posted_ms INTEGER NOT NULL, open_until_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL, data TEXT NOT NULL) WITHOUT ROWID";

export class PublicDuelDirectory extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => openLazyStorage(this, ctx.storage, "listings", () => { ctx.storage.sql.exec(TABLE); }));
  }

  /** Applies the boards' changes, newest per duel winning; a repeat of the row held writes nothing. */
  put(changes: ListingChange[], now = Date.now()): void {
    this.ctx.storage.transactionSync(() => {
      for (const change of changes) {
        const held = this.ctx.storage.sql.exec<{ updated_ms: number; data: string }>("SELECT updated_ms,data FROM listings WHERE duel_id=?", change.duel_id).toArray()[0];
        const open = change.listing !== null && change.listing.open_until_ms > now, data = open ? JSON.stringify(change.listing) : "null";
        if (held && (held.updated_ms > change.updated_ms || held.updated_ms === change.updated_ms && held.data === data)) continue;
        this.ctx.storage.sql.exec("INSERT OR REPLACE INTO listings VALUES (?,?,?,?,?)", change.duel_id, open ? change.listing!.posted_ms : 0, open ? change.listing!.open_until_ms : 0, change.updated_ms, data);
      }
      this.ctx.storage.sql.exec("DELETE FROM listings WHERE open_until_ms <= ? AND updated_ms < ?", now, now - TOMBSTONE_MS);
    });
  }

  /** Every listing still open, newest first, at most MAX_DIRECTORY_ROWS. Reads only. */
  list(now = Date.now()): Listing[] {
    return this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM listings WHERE open_until_ms > ? ORDER BY posted_ms DESC LIMIT ?", now, MAX_DIRECTORY_ROWS).toArray()
      .map(row => JSON.parse(row.data) as Listing);
  }

  /** Account erasure: rows naming the player go (their boards send fresh ones as they forget them). */
  forget(player: string): void {
    this.ctx.storage.sql.exec("DELETE FROM listings WHERE instr(data, ?) > 0", player);
  }
}

// A directory nobody posted to lists nothing and stores nothing.
answerWhileBlank(PublicDuelDirectory, { list: () => [], forget: () => undefined });

/** Sends a board's listing changes to the directory, best effort; absent binding or flag off: nothing. */
export async function sendListings(env: Pick<Env, "PUBLIC_DUEL_DIRECTORY">, changes: readonly ListingChange[]): Promise<void> {
  if (!changes.length || !env.PUBLIC_DUEL_DIRECTORY) return;
  try { await env.PUBLIC_DUEL_DIRECTORY.getByName(DIRECTORY_NAME).put([...changes]); } catch { /* the next change of that duel heals it; a tap still asks the board */ }
}
