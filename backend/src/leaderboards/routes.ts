import { ApiError, ID_PATTERN, boundedJson, digest, isObject, text, unwrap } from "../protocol";
import { flags } from "../flags";
import { json } from "../http";
import { knownBoard } from "./boards";
import { syncMemberName } from "./members";
import { cachedView, storeView } from "./view-cache";
import { serveReplay } from "./replays";
import { publicView } from "./view";
import { looksOn } from "../pollen/features";
import { platformRequiredOn } from "./platform-rule";
import { roomRun } from "./run";
import { postRun } from "./submit";

/**
 * The phone's leaderboard routes, all absent (falling through to 404) while
 * LEADERBOARDS is off (not in CONFIG):
 * - GET /v1/leaderboards/<board>: the board anyone sees, before auth() so a
 *   cached answer costs no Durable Object request at all. Rows carry the
 *   pair's looks only while POLLEN_LOOKS is on (run-looks.ts);
 * - GET /v1/leaderboards/<board>/replay/<entry>: a top 10 run's replay
 *   (replays.ts), before auth() for the same reason;
 * - GET and PUT /v1/leaderboards/me: the "Show my name on leaderboards" choice;
 * - POST /v1/leaderboards/<board>/entries/<entry>/report;
 * - POST /v1/leaderboards/post, only while the platform rule is on
 *   (platform-rule.ts): a member of a finished together room posts its run,
 *   or learns who still needs a platform account (postRoomRun).
 */
export const LEADERBOARDS_PREFIX = "/v1/leaderboards/";
export const LEADERBOARDS_HEADER = "X-AfterYou-Leaderboards";
const BOARD_PATH = /^\/v1\/leaderboards\/([a-z0-9-]{1,48}@[1-9][0-9]{0,3})$/;
const REPLAY_PATH = /^\/v1\/leaderboards\/([a-z0-9-]{1,48}@[1-9][0-9]{0,3})\/replay\/([a-f0-9]{32})$/;
const REPORT_PATH = /^\/v1\/leaderboards\/([a-z0-9-]{1,48}@[1-9][0-9]{0,3})\/entries\/([a-f0-9]{32})\/report$/;
const ME_PATH = "/v1/leaderboards/me";
export const POST_PATH = "/v1/leaderboards/post";

/**
 * `leaderboards_version: 1` on /v2/capabilities for a phone that asks while the flag is on, with
 * `leaderboards_platform_required: 1` while posts need platform accounts (platform-rule.ts).
 */
export function leaderboardsCapability(request: Request, env: Env): { leaderboards_version?: number; leaderboards_platform_required?: number } {
  if (!flags.leaderboards(env) || request.headers.get(LEADERBOARDS_HEADER) !== "1") return {};
  return { leaderboards_version: 1, ...(platformRequiredOn(env) ? { leaderboards_platform_required: 1 } : {}) };
}

/** The public board and replay reads, or null for any other request. Limited per address like the other public reads. */
export async function routeLeaderboardRead(request: Request, path: string, env: Env): Promise<Response | null> {
  if (!flags.leaderboards(env) || request.method !== "GET") return null;
  const replay = REPLAY_PATH.exec(path);
  const board = knownBoard((replay ?? BOARD_PATH.exec(path))?.[1]);
  if (!board) return null;
  const address = request.headers.get("CF-Connecting-IP") || "local";
  if (!(await env.PLAYER_LIMITER.limit({ key: "leaderboard:" + await digest(address) })).success) throw new ApiError(429, "rate_limited");
  if (replay) return serveReplay(env, board, replay[2]);
  const cached = await cachedView(board);
  if (cached) return json(publicView(cached, looksOn(env)));
  const view = await env.LEADERBOARD_BOARDS.getByName(board).view(board);
  await storeView(view);
  return json(publicView(view, looksOn(env)));
}

/** The signed-in routes under /v1/leaderboards/, after auth(); null for any other path. */
export async function routeLeaderboards(request: Request, path: string, playerId: string, env: Env): Promise<unknown | null> {
  if (!path.startsWith(LEADERBOARDS_PREFIX) || !flags.leaderboards(env)) return null;
  if (path === ME_PATH) {
    if (request.method === "GET") return { schema_version: 1, show_name: (await env.LEADERBOARD_MEMBERS.getByName(playerId).read()).show_name };
    if (request.method !== "PUT") throw new ApiError(405, "method_not_allowed");
    const input = await boundedJson(request, 1024);
    if (!isObject(input) || Object.keys(input).length !== 2 || input.schema_version !== 1 || typeof input.show_name !== "boolean") throw new ApiError(400, "invalid_leaderboard_request");
    return { schema_version: 1, show_name: (await syncMemberName(env, playerId, input.show_name)).show_name };
  }
  if (path === POST_PATH) {
    if (!platformRequiredOn(env)) return null;
    if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
    const input = await boundedJson(request, 1024);
    if (!isObject(input) || Object.keys(input).length !== 2 || input.schema_version !== 1) throw new ApiError(400, "invalid_leaderboard_request");
    return postRoomRun(env, playerId, text(input.room_id, ID_PATTERN));
  }
  const report = REPORT_PATH.exec(path);
  if (report) {
    if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
    const board = knownBoard(report[1]);
    if (!board) throw new ApiError(404, "not_found");
    const input = await boundedJson(request, 1024);
    if (!isObject(input) || Object.keys(input).length !== 1 || input.schema_version !== 1) throw new ApiError(400, "invalid_leaderboard_request");
    const entry = text(report[2], /^[a-f0-9]{32}$/);
    // The board keeps a hash per reporter, never the player id.
    const reporters = await env.LEADERBOARD_BOARDS.getByName(board).report(entry, await digest(`after-you leaderboard reporter v1\n${board}\n${playerId}`));
    if (reporters === null) throw new ApiError(404, "entry_not_found");
    return { schema_version: 1, reported: true };
  }
  return null;
}

/**
 * POST_PATH: the run of a finished together room this player is in, posted
 * again now (after a member linked a platform account), or why not:
 * - "posted": on its board or just sent there (checking, known or listed);
 * - "platform_required", with `you` and `partner` saying who has a link;
 * - "not_placed": ten faster runs, the pair's own faster run, or the board's checks;
 * - "not_postable": not a finished, whole, unassisted run with two players.
 * The pair's looks come from the room as the finishing commit hands them over
 * (run-looks.ts), so a run posted late shows what each wore.
 * Requests (beside auth): 1 room read, 1 PlatformLinks read, and the board
 * only when both are linked, the run might place and the cached board does
 * not list it yet (submit.ts postRun). Nothing is written while one is missing.
 */
async function postRoomRun(env: Env, playerId: string, roomId: string): Promise<unknown> {
  const { board_looks, ...room } = unwrap(await env.ROOMS_V2.getByName(roomId).boardSnapshot(playerId, looksOn(env)));
  const run = await roomRun(room, board_looks);
  if (!run) return { schema_version: 1, status: "not_postable" };
  const outcome = await postRun(env, run);
  if (outcome.status === "platform_required") {
    const partner = run.members[0] === playerId ? run.members[1] : run.members[0];
    return { schema_version: 1, status: "platform_required", you: !outcome.unlinked.includes(playerId), partner: !outcome.unlinked.includes(partner) };
  }
  return { schema_version: 1, status: ["checking", "known", "listed"].includes(outcome.status) ? "posted" : "not_placed" };
}
