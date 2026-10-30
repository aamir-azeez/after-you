import type { ServerVars } from "../flags";
import { validLook, type Look } from "./catalog";
import { looksOn } from "./features";

/**
 * The Worker's side of looks in rooms (POLLEN_LOOKS; room storage is room-looks.ts). While the flag
 * is off nothing here writes or serves a look, and every reply is byte for byte as before.
 *
 * - Writing: on create, join and a turn, auth() asks the Player's identity answer for the look too
 *   (Player.lookField), on the call it already makes, and the route passes it into the room call.
 * - Serving: only to a phone that sends LOOKS_HEADER, and only beside a room read or turn reply a
 *   member already gets: `partner_look` (the other member's look now) and `turn_looks` (the look of
 *   each of the other member's turns, by recording hash), and `turn_looks` for every turn beside a
 *   replay transfer. Leaderboard rows also carry each pair's looks while the flag is on, on the public
 *   cached board read with no header asked, also for a pair that hides its names (leaderboards/run-looks.ts).
 */
export const LOOKS_HEADER = "X-AfterYou-Looks";
export const LOOKS_VERSION = 1;

export function looksWanted(request: Request): boolean { return request.headers.get(LOOKS_HEADER) === "1"; }
/** Looks are served only to phones that ask while the flag is on. */
export function looksShown(request: Request, env: ServerVars): boolean { return looksOn(env) && looksWanted(request); }
export function looksCapability(request: Request, env: ServerVars): { looks_version?: number } {
  return looksShown(request, env) ? { looks_version: LOOKS_VERSION } : {};
}

const TURN_ROUTE = /^\/v2\/rooms\/[A-Za-z0-9_-]{22}\/turns$/;
/** The routes that write the caller's look into a room while looks are on: create, join and a turn. */
export function looksMemberRoute(request: Request, path: string, env: ServerVars): boolean {
  return request.method === "POST" && (path === "/v2/rooms" || path === "/v2/rooms/join" || TURN_ROUTE.test(path)) && looksOn(env);
}
/** The look a Player answer carries, when it carries a valid one. */
export function memberLookOf(answer: { look?: unknown }): Look | undefined {
  return validLook(answer.look) ? answer.look : undefined;
}
