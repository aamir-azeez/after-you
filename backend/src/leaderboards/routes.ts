import { ApiError, boundedJson, digest, isObject, text } from "../protocol";
import { flags } from "../flags";
import { json } from "../http";
import { knownBoard } from "./boards";
import { syncMemberName } from "./members";
import { cachedView, storeView } from "./view-cache";
import { serveReplay } from "./replays";

/**
 * The phone's leaderboard routes, all absent (falling through to 404) while
 * LEADERBOARDS is off (not in CONFIG):
 * - GET /v1/leaderboards/<board>: the board anyone sees, before auth() so a
 *   cached answer costs no Durable Object request at all;
 * - GET /v1/leaderboards/<board>/replay/<entry>: a top 10 run's replay
 *   (replays.ts), before auth() for the same reason;
 * - GET and PUT /v1/leaderboards/me: the "Show my name on leaderboards" choice;
 * - POST /v1/leaderboards/<board>/entries/<entry>/report.
 */
export const LEADERBOARDS_PREFIX = "/v1/leaderboards/";
export const LEADERBOARDS_HEADER = "X-AfterYou-Leaderboards";
const BOARD_PATH = /^\/v1\/leaderboards\/([a-z0-9-]{1,48}@[1-9][0-9]{0,3})$/;
const REPLAY_PATH = /^\/v1\/leaderboards\/([a-z0-9-]{1,48}@[1-9][0-9]{0,3})\/replay\/([a-f0-9]{32})$/;
const REPORT_PATH = /^\/v1\/leaderboards\/([a-z0-9-]{1,48}@[1-9][0-9]{0,3})\/entries\/([a-f0-9]{32})\/report$/;
const ME_PATH = "/v1/leaderboards/me";

/** `leaderboards_version: 1` on /v2/capabilities for a phone that asks while the flag is on. */
export function leaderboardsCapability(request: Request, env: Env): { leaderboards_version?: number } {
  return flags.leaderboards(env) && request.headers.get(LEADERBOARDS_HEADER) === "1" ? { leaderboards_version: 1 } : {};
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
  if (cached) return json(cached);
  const view = await env.LEADERBOARD_BOARDS.getByName(board).view(board);
  await storeView(view);
  return json(view);
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
