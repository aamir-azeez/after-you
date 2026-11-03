import { ApiError, digest } from "./protocol";

/**
 * Every rate limiter the Worker uses, in one place: which binding, which key and which refusal. Each
 * limiter is a Workers rate limit binding (wrangler.jsonc "ratelimits"), so a refused request costs no
 * Durable Object request and no row. A refusal is ApiError 429, which errorResponse answers retryable with
 * Retry-After 60. Address keys are a SHA-256 of the address's limiter key (ipKey), never the address.
 *
 * - PUBLIC_LIMITER, 20 a minute per address: routes with no identity (identity creation, recovery, app status,
 *   the friend link name page, operator routes, deletion acknowledgement), and the waitlist under its own scope.
 * - AUTH_LIMITER, 600 a minute per address: every signed-in request, before auth() asks the Player whether
 *   its credentials are good, so requests with bad credentials cost no Player request past it. Keyed by
 *   address, never by the claimed player id, so nobody can lock another player out. A phone's busiest minute is about
 *   130 requests (a room's first minute, a history sync and its photos) and photo transfer runs at 54 a minute, so
 *   this leaves room for about four busy phones behind one address (two players in a room on home Wi-Fi, carrier NAT).
 * - PLAYER_LIMITER, 120 a minute per player after auth(); public board reads share it under their own scope.
 * - TESTER_CODE_LIMITER, 5 a minute: tester codes and platform links (their own scopes), and the costly class:
 *   the routes in COSTLY_ROUTES, each a scope of its own per player, which fan out to many objects, write rows
 *   or call RevenueCat. None of them is a timer on the phone; each is a tap, a purchase or a hosted room.
 * - PHOTO_ACK_LIMITER and PHOTO_TRANSFER_LIMITER, 60 a minute: photo and transfer routes, per player and room.
 * - WAITLIST_ADDRESS_LIMITER, 1 a minute per inbox.
 */

/**
 * A count kept in a Durable Object's memory: at most `limit` takes in any `windowMs`. For guards on one object's
 * own work (presence lease changes, "just bought" wallet hints), where a binding would cost a call per request.
 * Memory only: an evicted object starts again from zero, which costs at most one more window.
 */
export class MemoryBudget {
  private times: number[] = [];
  constructor(private readonly limit: number, private readonly windowMs: number) {}
  /** Whether one more fits in the window; one that fits is counted. */
  take(now: number): boolean {
    this.times = this.times.filter(time => now - time < this.windowMs);
    if (this.times.length >= this.limit) return false;
    this.times.push(now);
    return true;
  }
}

/** The limiter's address key: an IPv4 address as is (also when mapped into IPv6), an IPv6 address as its /64. */
export function ipKey(ip: string | null): string {
  if (!ip) return "local";
  const v4 = /(\d{1,3}(?:\.\d{1,3}){3})$/.exec(ip);
  if (v4) return v4[1];
  if (!ip.includes(":")) return ip;
  const [head, tail] = ip.toLowerCase().split("::");
  const front = head ? head.split(":") : [], back = tail === undefined ? [] : tail ? tail.split(":") : [];
  const groups = tail === undefined ? front : [...front, ...Array(Math.max(0, 8 - front.length - back.length)).fill("0"), ...back];
  return groups.slice(0, 4).map(group => group.replace(/^0+(?=.)/, "")).join(":") + "::/64";
}
/** The hashed address key of a request, with an optional scope inside the hash. */
export function addressKey(request: Request, scope = ""): Promise<string> {
  return digest(scope + ipKey(request.headers.get("CF-Connecting-IP")));
}
async function check(limiter: RateLimit, key: string, code = "rate_limited"): Promise<void> {
  if (!(await limiter.limit({ key })).success) throw new ApiError(429, code);
}

export async function limitPublic(request: Request, env: Env): Promise<void> { await check(env.PUBLIC_LIMITER, await addressKey(request)); }
export async function limitAuth(request: Request, env: Env): Promise<void> { await check(env.AUTH_LIMITER, await addressKey(request)); }
export function limitPlayer(env: Env, player: string): Promise<void> { return check(env.PLAYER_LIMITER, player); }
export async function limitBoardRead(request: Request, env: Env): Promise<void> { await check(env.PLAYER_LIMITER, "leaderboard:" + await addressKey(request)); }
export async function limitWaitlist(request: Request, env: { PUBLIC_LIMITER: RateLimit }): Promise<void> { await check(env.PUBLIC_LIMITER, await addressKey(request, "waitlist:")); }
/** `material`: the scope and the inbox key, hashed here. */
export async function limitWaitlistAddress(env: { WAITLIST_ADDRESS_LIMITER: RateLimit }, material: string): Promise<void> { await check(env.WAITLIST_ADDRESS_LIMITER, await digest(material)); }
/** Tester codes: one bucket per player and one per address, so fresh identities do not get fresh guesses. */
export async function limitTesterCode(request: Request, env: Env, owner: string): Promise<void> {
  await check(env.TESTER_CODE_LIMITER, "owner:" + owner, "tester_rate_limited");
  await check(env.TESTER_CODE_LIMITER, "ip:" + await addressKey(request), "tester_rate_limited");
}
export async function limitPlatformRestore(request: Request, env: Env): Promise<void> { await check(env.TESTER_CODE_LIMITER, "platform-ip:" + await addressKey(request)); }
export function limitPlatformLink(env: Env, player: string): Promise<void> { return check(env.TESTER_CODE_LIMITER, "platform-player:" + player); }
export function limitPhotoTransfer(env: Env, owner: string, acknowledgement: boolean): Promise<void> {
  return check(acknowledgement ? env.PHOTO_ACK_LIMITER : env.PHOTO_TRANSFER_LIMITER, owner + ":transfer", "photo_transfer_rate_limited");
}
const ROOM_SCOPES = { photo: ["", "photo_ack_rate_limited"], replay: ["replay:", "replay_transfer_rate_limited"], history: ["history:", "history_rate_limited"] } as const;
/** A room's photo acknowledgements, replay transfer and history uploads, per player and room. */
export function limitRoomTransfer(env: Env, kind: keyof typeof ROOM_SCOPES, player: string, room: string): Promise<void> {
  const [scope, code] = ROOM_SCOPES[kind];
  return check(env.PHOTO_ACK_LIMITER, scope + player + ":" + room, code);
}

/**
 * The costly class: signed-in routes whose one request fans out to many objects, writes rows on several of
 * them or calls RevenueCat. Each kind is its own 5-a-minute bucket per player. The phone sends every one of
 * them on a tap or a hosted room, never on a timer, so normal play stays far below it; a refusal is 429
 * rate_limited, which every caller already keeps and retries (see DEPLOY-A-NOTES.md for each route).
 * Deliberately absent, each with its own guard: GET /v1/friends and GET /v1/social/inbox (read on the phone's
 * timers and live hints; the list's refresh floor, the inbox's re-check memo), POST /v1/pollen/bundle-claims (sent
 * three times in five seconds after a purchase; its own pace, pollen/bundle-settle.ts pacedClaim), POST
 * /v1/friends/accept (up to ten held requests accepted in a row; a repeat costs a few reads and writes nothing).
 */
export const COSTLY_ROUTES = Object.freeze([
  { kind: "publication", method: "POST", path: /^\/v1\/social\/publication$/ },
  { kind: "friend-request", method: "POST", path: /^\/v1\/friends\/request$/ },
  { kind: "leaderboard-name", method: "PUT", path: /^\/v1\/leaderboards\/me$/ },
  { kind: "duel-challenge", method: "POST", path: /^\/v1\/duels\/challenge$/ },
  { kind: "duel-ghost", method: "POST", path: /^\/v1\/duels\/ghost$/ },
  { kind: "duel-party-invite", method: "POST", path: /^\/v1\/duels\/party\/invite$/ },
  { kind: "report", method: "POST", path: /^\/v1\/safety\/report$/ },
  { kind: "block", method: "POST", path: /^\/v1\/safety\/(?:block|blocks\/[A-Za-z0-9_-]{22})$/ }
] as const);
/**
 * Costly work a route does only sometimes, limited where it happens: a change of the shared friend room (its hints
 * and revokes reach every friend), turning hosting alerts on or off (not their acknowledgements, sent per shown
 * event), and a Full Journey check that will ask RevenueCat (GET /v1/entitlement; a remembered answer is free).
 */
export const COSTLY_IN_ROUTE = Object.freeze(["friend-share", "friend-alerts", "entitlement"] as const);
export type CostlyKind = typeof COSTLY_ROUTES[number]["kind"] | typeof COSTLY_IN_ROUTE[number];

export function costlyKind(method: string, path: string): CostlyKind | null {
  return COSTLY_ROUTES.find(route => route.method === method && route.path.test(path))?.kind ?? null;
}
export function limitCostly(env: Env, kind: CostlyKind, player: string): Promise<void> {
  return check(env.TESTER_CODE_LIMITER, `costly:${kind}:${player}`);
}
/** After auth(): the costly bucket of the request's route, if it has one. */
export async function limitCostlyRoute(request: Request, path: string, player: string, env: Env): Promise<void> {
  const kind = costlyKind(request.method, path);
  if (kind !== null) await limitCostly(env, kind, player);
}
