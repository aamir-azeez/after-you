import { ApiError, boundedJson, isObject, text } from "../protocol";
import { JSON_HEADERS, json } from "../http";
import { flags } from "../flags";
import { boardKeys, developerBest, knownBoard } from "./boards";
import { MAX_REPLAY_CHARS, type PendingWork, type Verdict } from "./board";
import { leaderboardCaller } from "./job-token";
import { checkRun } from "./eligibility";
import { pooled } from "../room-inbox";
import { storeView } from "./view-cache";
import { MAX_REWARD_DELIVERIES, deliverRewards, type RewardBatch } from "./reward-delivery";
import { wardrobeOn } from "../pollen/features";

/**
 * The replay job's and the owner's routes under /operator/leaderboards/, all POST:
 * - pending (job or operator): runs the account check on new runs, then hands
 *   out runs to replay with their stored final checkpoints. While POLLEN_WARDROBE
 *   is on it also delivers earned items to players whose board rewards changed
 *   (reward-delivery.ts);
 * - verdicts (job or operator): the replay results;
 * - review-list and review (operator only): runs waiting for a person or
 *   reported, and a person's approve, reject or strike.
 * While LEADERBOARDS is off (not in FEATURES) every route answers 503 leaderboards_disabled,
 * which the job reads as nothing to do.
 */
export const OPERATOR_PREFIX = "/operator/leaderboards/";
/** Replay work handed out per pending call, by checkpoint length, across all boards. */
export const MAX_PENDING_CHARS = 4_000_000;
const MAX_VERDICTS = 64;
/** Account checks per pending call, across boards, four at a time (each is up to 4 requests). */
const MAX_STANDINGS = 16;
const STANDING_CONCURRENCY = 4;
const ENTRY = /^[a-f0-9]{32}$/, HASH = /^[a-f0-9]{64}$/;

export async function routeLeaderboardOperator(request: Request, path: string, env: Env): Promise<Response> {
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const caller = await leaderboardCaller(request, env);
  if (!flags.leaderboards(env)) throw new ApiError(503, "leaderboards_disabled");
  const input = await boundedJson(request, 256 * 1024);
  if (!isObject(input) || input.schema_version !== 1) throw new ApiError(400, "invalid_leaderboard_request");
  const action = path.slice(OPERATOR_PREFIX.length);
  if (action === "pending") return new Response(`{"schema_version":1,"entries":[${(await pending(env)).join(",")}]}`, { headers: JSON_HEADERS });
  if (action === "verdicts") return json({ schema_version: 1, ...(await verdicts(env, input.verdicts)) });
  if (caller !== "operator") throw new ApiError(403, "operator_required");
  if (action === "review-list") return json({ schema_version: 1, boards: await reviewList(env) });
  if (action === "review") return json({ schema_version: 1, ...(await review(env, input)) });
  throw new ApiError(404, "not_found");
}

/**
 * One request per board, plus up to MAX_STANDINGS account checks (eligibility.ts)
 * and one more request for each board that had any. While the wardrobe is on, up to
 * MAX_REWARD_DELIVERIES Player requests more, and one board request for each board that delivered any. The boards are visited
 * from a starting point that moves each hour, so a board with large proofs
 * never starves the rest. Each entry is written as JSON text around its stored
 * checkpoint text, which is never parsed here: a Worker on the Free plan has
 * 10 ms of CPU per request.
 */
async function pending(env: Env): Promise<string[]> {
  const entries: string[] = [];
  const keys = boardKeys(), start = Math.floor(Date.now() / 3_600_000) % keys.length;
  let budget = MAX_PENDING_CHARS, checks = MAX_STANDINGS, deliveries = wardrobeOn(env) ? MAX_REWARD_DELIVERIES : 0;
  const batches: RewardBatch[] = [];
  for (let step = 0; step < keys.length; step++) {
    const board = keys[(start + step) % keys.length];
    const stub = env.LEADERBOARD_BOARDS.getByName(board);
    let work: PendingWork = await stub.pendingWork(Math.max(0, Math.min(budget, MAX_REPLAY_CHARS)), deliveries);
    if (work.rewards?.length) { deliveries -= work.rewards.length; batches.push({ board, stub, rewards: work.rewards }); }
    const due = work.standing.slice(0, checks);
    if (due.length) {
      checks -= due.length;
      const results = await pooled(due, STANDING_CONCURRENCY, item => checkRun(env, board, item.entry_id, item.members, item.finished_ms));
      const checked = await stub.standings(board, results, Math.max(0, Math.min(budget, MAX_REPLAY_CHARS)));
      await storeView(checked.view);
      work = checked.work;
    }
    for (const item of work.replay) {
      const { checkpoint, ...facts } = item;
      entries.push(JSON.stringify({ board, ...facts }).slice(0, -1) + `,"checkpoint":${checkpoint}}`);
      budget -= checkpoint.length;
    }
  }
  // One pass once every board's replay work is in hand: a delivery never costs the job its work.
  await deliverRewards(env, batches);
  return entries;
}

function parseVerdicts(value: unknown): Map<string, Verdict[]> {
  if (!Array.isArray(value) || value.length > MAX_VERDICTS) throw new ApiError(400, "invalid_leaderboard_request");
  const byBoard = new Map<string, Verdict[]>();
  for (const item of value) {
    if (!isObject(item) || Object.keys(item).length !== 6 || typeof item.valid !== "boolean" || !Number.isSafeInteger(item.measured_ticks) || typeof item.reason !== "string" || item.reason.length > 120) throw new ApiError(400, "invalid_leaderboard_request");
    const board = knownBoard(item.board);
    if (!board) throw new ApiError(400, "invalid_leaderboard_request");
    const verdict: Verdict = { entry_id: text(item.entry_id, ENTRY), proof_hash: text(item.proof_hash, HASH), valid: item.valid, measured_ticks: item.measured_ticks as number, reason: item.reason };
    byBoard.set(board, [...(byBoard.get(board) ?? []), verdict]);
  }
  return byBoard;
}

/**
 * One request per board named; each run that ranked is reported back by id only. While the wardrobe is
 * on, each board's answer also carries its changed rewards, handed out in one pass once every board's
 * verdicts are applied (reward-delivery.ts), so a pair the celebration promised a Gold leaf can wear it
 * at once rather than after the next hourly pull.
 */
async function verdicts(env: Env, value: unknown): Promise<{ ranked: string[] }> {
  const ranked: string[] = [], batches: RewardBatch[] = [];
  let deliveries = wardrobeOn(env) ? MAX_REWARD_DELIVERIES : 0;
  for (const [board, list] of parseVerdicts(value)) {
    const stub = env.LEADERBOARD_BOARDS.getByName(board);
    const answer = await stub.verdicts(board, list, developerBest(board), deliveries);
    await storeView(answer.view);
    ranked.push(...answer.ranked.map(note => note.entry_id));
    if (answer.rewards?.length) { deliveries -= answer.rewards.length; batches.push({ board, stub, rewards: answer.rewards }); }
  }
  await deliverRewards(env, batches);
  return { ranked };
}

async function reviewList(env: Env): Promise<{ board: string; entries: unknown[] }[]> {
  const result: { board: string; entries: unknown[] }[] = [];
  for (const board of boardKeys()) {
    const entries = await env.LEADERBOARD_BOARDS.getByName(board).reviewList();
    if (entries.length) result.push({ board, entries });
  }
  return result;
}

async function review(env: Env, input: Record<string, unknown>): Promise<{ done: boolean }> {
  if (Object.keys(input).length !== 4 || !["approve", "reject", "strike"].includes(String(input.action))) throw new ApiError(400, "invalid_leaderboard_request");
  const board = knownBoard(input.board), entry = text(input.entry_id, ENTRY);
  if (!board) throw new ApiError(400, "invalid_leaderboard_request");
  const stub = env.LEADERBOARD_BOARDS.getByName(board);
  const deliveries = wardrobeOn(env) ? MAX_REWARD_DELIVERIES : 0;
  const answer = input.action === "strike" ? await stub.strike(board, entry, deliveries) : await stub.review(board, entry, input.action === "approve", deliveries);
  await storeView(answer.view);
  if (answer.rewards?.length) await deliverRewards(env, [{ board, stub, rewards: answer.rewards }]);
  return { done: answer.done };
}
