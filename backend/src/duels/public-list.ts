import { DIRECTORY_NAME } from "./directory";
import { rowFor, type ListRow, type Listing } from "./public";
import { PUBLIC_PAGE_ROWS } from "./rules";

/**
 * The public list as a reader's page (GET /v1/duels/public/list/<scope>/<sort>/<page>). Every reader's list starts
 * from the same directory answer, so it is cached like a board view (leaderboards/view-cache.ts): this isolate's
 * memory and the data centre's Cache API for LIST_TTL_MS, the directory asked only when both miss. The Cache API
 * stores only on a Worker served from a custom domain; on workers.dev the memory copy alone saves the request.
 * The cached copy holds seat ids, which never leave the server: each page is filtered for its reader (their blocks
 * both ways) and stripped of ids (public.ts rowFor) before it goes out.
 */
export const LIST_TTL_MS = 30_000;
export type ListSort = "newest" | "almost_full";
const CACHE_URL = "https://public-duels.after-you.invalid/v1/list";
const STORED_AT = "X-Stored-At";
let memory: { at: number; listings: Listing[] } | null = null;

function cacheApi(): Cache | null {
  try { return (globalThis as { caches?: { default?: Cache } }).caches?.default ?? null; } catch { return null; }
}

/** Every open listing, from the caches when fresh, else from the directory (then cached). */
export async function listings(env: Pick<Env, "PUBLIC_DUEL_DIRECTORY">, now = Date.now()): Promise<Listing[]> {
  if (memory && now - memory.at < LIST_TTL_MS) return memory.listings;
  const cache = cacheApi();
  if (cache) {
    try {
      const hit = await cache.match(CACHE_URL);
      const at = Number(hit?.headers.get(STORED_AT));
      if (hit && Number.isFinite(at) && now - at < LIST_TTL_MS) { const held = await hit.json<Listing[]>(); if (Array.isArray(held)) { memory = { at, listings: held }; return held; } }
    } catch { /* ask the directory */ }
  }
  const fresh = env.PUBLIC_DUEL_DIRECTORY ? (await env.PUBLIC_DUEL_DIRECTORY.getByName(DIRECTORY_NAME).list(now)) as unknown as Listing[] : [];
  memory = { at: now, listings: fresh };
  if (cache) {
    try { await cache.put(CACHE_URL, new Response(JSON.stringify(fresh), { headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${LIST_TTL_MS / 1000}`, [STORED_AT]: String(now) } })); }
    catch { /* memory still serves */ }
  }
  return fresh;
}

/** After a post or join here, this isolate reads the directory again at its next list (other isolates within LIST_TTL_MS). */
export function forgetListings(): void { memory = null; }

/**
 * One reader's page: the scope's listings (every chapter, or one board), none holding a player the reader blocked
 * or who blocked them (`avoid`), none past its window, sorted, 20 a page.
 */
export function page(all: readonly Listing[], reader: string, avoid: ReadonlySet<string>, scope: string, sort: ListSort, index: number, now: number, looks: boolean): { rows: ListRow[]; next: number | null } {
  const shown = all.filter(item => (scope === "all" || item.board === scope) && item.open_until_ms > now &&
    !item.sides.some(side => side.seats.some(seat => seat.id !== null && seat.id !== reader && avoid.has(seat.id))));
  if (sort === "almost_full") shown.sort((a, b) => a.seats_open - b.seats_open || b.posted_ms - a.posted_ms);
  else shown.sort((a, b) => b.posted_ms - a.posted_ms);
  const start = index * PUBLIC_PAGE_ROWS;
  return { rows: shown.slice(start, start + PUBLIC_PAGE_ROWS).map(item => rowFor(item, reader, looks)), next: start + PUBLIC_PAGE_ROWS < shown.length ? index + 1 : null };
}

/** Tests start each case with empty caches. */
export async function forgetCachedListings(): Promise<void> {
  memory = null;
  const cache = cacheApi();
  if (cache) { try { await cache.delete(CACHE_URL); } catch { /* nothing cached */ } }
}
