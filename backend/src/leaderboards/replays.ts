import { ApiError } from "../protocol";
import { JSON_HEADERS } from "../http";
import { blobBase64 } from "../blob-codec";
import { cachedView, storeView } from "./view-cache";

/**
 * GET /v1/leaderboards/<board>/replay/<entry_id>: a top 10 run's kept replay
 * (board.ts lb_replays), the same bytes for every reader. It answers only for
 * a row of the board view that names a replay, and carries what that row
 * shows (place, time, the names both players chose to show) and the replay
 * in the shared blob format: `body` is the tagged body in base64, decoded on
 * the phone to `byte_length` canonical bytes whose SHA-256 is `digest`. It
 * never carries a player id, a pair key or a room id; the checkpoint holds
 * none.
 *
 * Requests: none while this isolate holds the board view (view-cache.ts) and
 * the replay body; else one (the board's `replay`, which also refreshes the
 * view). A fresh view that does not show a replay for the entry refuses
 * without asking the board, so an erased account's replay stops within
 * VIEW_TTL_MS everywhere, as its names do. Bodies are kept by their hash in
 * this isolate's memory (the Cache API does nothing on workers.dev), up to
 * MAX_CACHED_CHARS of base64.
 */
export const MAX_CACHED_CHARS = 8 * 1024 * 1024;
type Body = { byte_length: number; base64: string };
const bodies = new Map<string, Body>();
let cachedChars = 0;

export async function serveReplay(env: Env, board: string, entryId: string): Promise<Response> {
  const cached = await cachedView(board);
  let row = cached?.top.find(item => item.entry_id === entryId);
  if (cached && !row?.replay_hash) throw new ApiError(404, "replay_not_found");
  let body = row?.replay_hash ? held(row.replay_hash) : undefined;
  if (!row || !body) {
    const answer = await env.LEADERBOARD_BOARDS.getByName(board).replay(board, entryId);
    await storeView(answer.view);
    row = answer.view.top.find(item => item.entry_id === entryId);
    if (!row || !answer.replay || row.replay_hash !== answer.replay.proof_hash) throw new ApiError(404, "replay_not_found");
    body = remember(answer.replay.proof_hash, { byte_length: answer.replay.byte_length, base64: blobBase64(answer.replay.body) });
  }
  const head = { schema_version: 1, board, entry_id: row.entry_id, rank: row.rank, ticks: row.ticks, finished_on: row.finished_on, names: row.names, gold_leaf: row.gold_leaf, digest: row.replay_hash, byte_length: body.byte_length };
  // The body is spliced in, never run through JSON.stringify: base64 needs no escaping.
  return new Response(JSON.stringify(head).slice(0, -1) + `,"body":"${body.base64}"}`, { headers: JSON_HEADERS });
}

function held(hash: string): Body | undefined {
  const body = bodies.get(hash);
  if (body) { bodies.delete(hash); bodies.set(hash, body); }
  return body;
}

function remember(hash: string, body: Body): Body {
  if (body.base64.length > MAX_CACHED_CHARS) return body;
  const old = bodies.get(hash);
  if (old) { cachedChars -= old.base64.length; bodies.delete(hash); }
  bodies.set(hash, body);
  cachedChars += body.base64.length;
  while (cachedChars > MAX_CACHED_CHARS) {
    const [oldest, value] = bodies.entries().next().value!;
    bodies.delete(oldest);
    cachedChars -= value.base64.length;
  }
  return body;
}

/** Tests start each case with an empty cache. */
export function forgetReplays(): void { bodies.clear(); cachedChars = 0; }
