import { ApiError, boundedJson, isObject, text } from "../protocol";
import { JSON_HEADERS, json } from "../http";
import { flags } from "../flags";
import { boardKeys, developerBest, knownBoard } from "./boards";
import { MAX_REPLAY_CHARS, type PendingWork, type StandingResult, type StandingWork, type Verdict } from "./board";
import { leaderboardCaller } from "./job-token";
import { eligible } from "./standing";
import { storeView } from "./view-cache";

/**
 * The replay job's and the owner's routes under /operator/leaderboards/, all POST:
 * - pending (job or operator): runs the account check on new runs, then hands
 *   out runs to replay with their stored final checkpoints;
 * - verdicts (job or operator): the replay results;
 * - review-list and review (operator only): runs waiting for a person or
 *   reported, and a person's approve, reject or strike.
 * While LEADERBOARDS_ENABLED is off every route answers 503 leaderboards_disabled,
 * which the job reads as nothing to do.
 */
export const OPERATOR_PREFIX = "/operator/leaderboards/";
/** Replay work handed out per pending call, by checkpoint length, across all boards. */
export const MAX_PENDING_CHARS = 4_000_000;
const MAX_VERDICTS = 64;
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
 * One request per board, plus for each new run one Player and one Member
 * request per member, then one more board request. Each entry is written as
 * JSON text around its stored checkpoint text, which is never parsed here:
 * a Worker on the Free plan has 10 ms of CPU per request.
 */
async function pending(env: Env): Promise<string[]> {
  const entries: string[] = [];
  let budget = MAX_PENDING_CHARS;
  for (const board of boardKeys()) {
    if (budget <= 0) break;
    const stub = env.LEADERBOARD_BOARDS.getByName(board);
    let work: PendingWork = await stub.pendingWork(Math.min(budget, MAX_REPLAY_CHARS));
    if (work.standing.length) {
      const checked = await stub.standings(board, await Promise.all(work.standing.map(item => standing(env, board, item))), Math.min(budget, MAX_REPLAY_CHARS));
      await storeView(checked.view);
      work = checked.work;
    }
    for (const item of work.replay) {
      const { checkpoint, ...facts } = item;
      entries.push(JSON.stringify({ board, ...facts }).slice(0, -1) + `,"checkpoint":${checkpoint}}`);
      budget -= checkpoint.length;
    }
  }
  return entries;
}

/** Both members' account check and name choice. Noting the board first means a later name change reaches it. */
async function standing(env: Env, board: string, item: StandingWork): Promise<StandingResult> {
  const members = await Promise.all(item.members.map(async id => {
    if (id === null) return { ok: false, show: false, name: null };
    // A player with no identity (erased) is never written to again.
    const player = await env.PLAYERS.getByName(id).leaderboardStanding();
    if (!player) return { ok: false, show: false, name: null };
    const settings = await env.LEADERBOARD_MEMBERS.getByName(id).noteBoard(board);
    return { ok: eligible(player, item.finished_ms), show: settings.show_name, name: player.display_name };
  }));
  const ok = members.length === 2 && members.every(member => member.ok);
  return { entry_id: item.entry_id, eligible: ok, reason: ok ? "" : "ineligible", members: [{ show: members[0].show, name: members[0].name }, { show: members[1].show, name: members[1].name }] };
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

/** One request per board named. Each run that ranked is reported back by id only. */
async function verdicts(env: Env, value: unknown): Promise<{ ranked: string[] }> {
  const ranked: string[] = [];
  for (const [board, list] of parseVerdicts(value)) {
    const answer = await env.LEADERBOARD_BOARDS.getByName(board).verdicts(board, list, developerBest(board));
    await storeView(answer.view);
    ranked.push(...answer.ranked.map(note => note.entry_id));
  }
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
  const answer = input.action === "strike" ? await stub.strike(board, entry) : await stub.review(board, entry, input.action === "approve");
  await storeView(answer.view);
  return { done: answer.done };
}
