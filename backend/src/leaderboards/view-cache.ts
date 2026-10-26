import type { BoardView } from "./view";

/**
 * Board views are the same for every reader, so a read is answered from a
 * cache and a board object is asked only when both caches miss:
 * 1. this isolate's memory, for VIEW_TTL_MS;
 * 2. the Cache API (caches.default) of the data centre, for the same time.
 *
 * The Cache API only stores on a Worker served from a custom domain; on a
 * workers.dev address its put and match do nothing, so there the memory cache
 * alone saves the request. Every answer a board gives (a read, a submission or
 * a verdict) refreshes both, so a change shows at once where it was made and
 * within VIEW_TTL_MS everywhere else.
 */
export const VIEW_TTL_MS = 120_000;
const MAX_MEMORY = 64;
const memory = new Map<string, { at: number; view: BoardView }>();

function cacheUrl(board: string): string { return `https://leaderboards.after-you.invalid/v1/${encodeURIComponent(board)}`; }
function cacheApi(): Cache | null {
  try { return (globalThis as { caches?: { default?: Cache } }).caches?.default ?? null; } catch { return null; }
}

export async function cachedView(board: string, now = Date.now()): Promise<BoardView | null> {
  const held = memory.get(board);
  if (held && now - held.at < VIEW_TTL_MS) return held.view;
  const cache = cacheApi();
  if (!cache) return null;
  try {
    const hit = await cache.match(cacheUrl(board));
    if (!hit) return null;
    const view = await hit.json<BoardView>();
    if (view?.schema_version !== 1 || view.board !== board) return null;
    remember(board, view, now);
    return view;
  } catch { return null; }
}

export async function storeView(view: BoardView, now = Date.now()): Promise<void> {
  remember(view.board, view, now);
  const cache = cacheApi();
  if (!cache) return;
  try {
    await cache.put(cacheUrl(view.board), new Response(JSON.stringify(view), { headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${VIEW_TTL_MS / 1000}` } }));
  } catch { /* the memory copy still serves */ }
}

function remember(board: string, view: BoardView, now: number): void {
  memory.delete(board);
  memory.set(board, { at: now, view });
  while (memory.size > MAX_MEMORY) memory.delete(memory.keys().next().value!);
}

/** Tests start each case with empty caches. */
export async function forgetViews(boards: readonly string[]): Promise<void> {
  memory.clear();
  const cache = cacheApi();
  if (cache) for (const board of boards) { try { await cache.delete(cacheUrl(board)); } catch { /* nothing cached */ } }
}
