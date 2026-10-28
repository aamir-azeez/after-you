import { ApiError, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, boundedJson, canonicalJson, digest, isObject, unwrap, type Outcome } from "../protocol";
import type { ServerVars } from "../flags";
import { bearerDigest } from "../http";
import { earningOn, grantOn, itemBloomsOn, shopOn, wardrobeOn } from "./features";
import { ITEM_ID_PATTERN } from "./catalog";
import { CHAPTERS } from "../v2/chapters";
import type { CommittedV2, MutationV2 } from "../v2/room";
import type { Entitlement } from "../entitlement";
import type { PollenMember, TurnFacts } from "./turn-facts";
import type { HistoryView, PollenReceipt, WalletView } from "./wallet";

/**
 * The Worker's side of Pollen (POLLEN_EARN). Everything here is absent while the flag is off: no
 * capability, no member value into rooms, no credit after a turn, and the /v1/pollen routes answer
 * 503 before any body or object is read.
 *
 * Cost on the Free plan: one Player request (creditTurn) after each accepted standalone turn, one
 * more to the partner's Player on the turn that finishes a chapter together, and none on reads:
 * GET /v1/pollen and its history ride on auth()'s own Player call (authorizeWallet). While the grant
 * is on, that call itself reads RevenueCat when an instalment is due (a subrequest, about once a month
 * per subscriber) and asks PollenClaims once per subscription new to the player (grant-settle.ts).
 */
export const POLLEN_HEADER = "X-AfterYou-Pollen";
export const POLLEN_VERSION = 1;
export const POLLEN_PATH = "/v1/pollen";
export const POLLEN_HISTORY_PATH = "/v1/pollen/history";
export const TURN_CLAIMS_PATH = "/v1/pollen/turn-claims";
export const CLEAR_CLAIMS_PATH = "/v1/pollen/clear-claims";
export const SPEND_PATH = "/v1/pollen/spend";
export const EQUIP_PATH = "/v1/pollen/equip";
/** The capability version of the wardrobe (equip, owned items and the look on the wallet read, earned items). */
export const WARDROBE_VERSION = 1;
/** The capability version of the shop (spend, prices and the catalogue on the wallet read, and the name change price). Always sent with the wardrobe's. */
export const SHOP_VERSION = 1;
/** The capability version of item blooms (the receipt's `item_bloom`), so a phone publishes their odds only while they drop. */
export const ITEM_BLOOMS_VERSION = 1;
/** The capability version of the monthly grant (the wallet read's `grant`), so a phone shows it only while it pays. */
export const GRANT_VERSION = 1;
/** Claims one request may carry; each costs a Room read and a Player credit. */
export const MAX_CLAIMS_PER_REQUEST = 4;
/** A Full Journey with no end (a lifetime unlock): the latest time a Date holds. */
export const NO_END = 8_640_000_000_000_000;

/** The turn reply's `pollen` field: the credit's receipt, or `pending` when it did not land (the phone claims it later). */
export type PollenReply = PollenReceipt | { schema_version: 1; pending: true };

export function pollenWanted(request: Request): boolean { return request.headers.get(POLLEN_HEADER) === "1"; }
/** Earning works only with the flag on and a usable POLLEN_SECRET (no turn is paid without its bloom roll). */
export function pollenEarning(env: ServerVars): boolean { return earningOn(env); }
/** The capability field for GET /v2/capabilities: empty unless the client asked while earning works. */
export function pollenCapability(request: Request, env: ServerVars): { pollen_version?: number; pollen_wardrobe_version?: number; pollen_shop_version?: number; pollen_item_blooms_version?: number; pollen_grant_version?: number } {
  if (!pollenWanted(request) || !pollenEarning(env)) return {};
  return { pollen_version: POLLEN_VERSION, ...(wardrobeOn(env) ? { pollen_wardrobe_version: WARDROBE_VERSION } : {}), ...(shopOn(env) ? { pollen_shop_version: SHOP_VERSION } : {}),
    ...(itemBloomsOn(env) ? { pollen_item_blooms_version: ITEM_BLOOMS_VERSION } : {}), ...(grantOn(env) ? { pollen_grant_version: GRANT_VERSION } : {}) };
}

const TURN_ROUTE = /^\/v2\/rooms\/[A-Za-z0-9_-]{22}\/turns$/;
/** A standalone turn POST while the flag is on: auth() then reads the player's Full Journey end with the room check. */
export function pollenTurnRoute(request: Request, path: string, env: ServerVars): boolean {
  return request.method === "POST" && TURN_ROUTE.test(path) && pollenEarning(env);
}
/** Create and join while the flag is on: auth() reads the Full Journey end with the device check, to copy into the room. */
export function pollenMemberRoute(request: Request, path: string, env: ServerVars): boolean {
  return request.method === "POST" && (path === "/v2/rooms" || path === "/v2/rooms/join") && pollenEarning(env);
}
/** The wallet reads, whose answer auth() takes from its own Player call; null for any other route. While the wardrobe is on, the wallet read also carries it (features.ts wardrobeMode). */
export function pollenAuthView(request: Request, path: string, env: ServerVars): "wallet" | "history" | null {
  if (request.method !== "GET" || !pollenEarning(env)) return null;
  return path === POLLEN_PATH ? "wallet" : path === POLLEN_HISTORY_PATH ? "history" : null;
}
/** The member value a Player answer carries, when it carries one. */
export function pollenMember(answer: { fj_until?: number }): PollenMember | undefined {
  return typeof answer.fj_until === "number" ? { fj_until: answer.fj_until } : undefined;
}

/** Whether a path is a Pollen route: only while earning works; otherwise it falls through to 404 as before. */
export function pollenRoute(path: string, env: ServerVars): boolean {
  return (path === POLLEN_PATH || path.startsWith(POLLEN_PATH + "/")) && pollenEarning(env);
}

/**
 * Runs a provider check and answers it with the Full Journey end to note for the checked player
 * (paidUntil), or undefined when `wanted` is false (earning is off, or the check was another player's).
 */
export async function checkedWithEnd<T extends Entitlement | null>(check: (onGrant: (until: number) => void) => Promise<T>, wanted: boolean): Promise<{ access: T; until: number | undefined }> {
  let until: number | undefined;
  const access = await check(value => { until = value; });
  return { access, until: wanted && access !== null ? paidUntil(access, until) : undefined };
}

/**
 * The Full Journey end a provider check reported, to note on the player and copy into rooms:
 * the end of the paid period (NO_END for a lifetime unlock), 0 when RevenueCat verified no access,
 * undefined when it says nothing about paid access (unavailable, unconfigured, a tester or review grant).
 */
export function paidUntil(access: Entitlement, until: number | undefined): number | undefined {
  if (access.status !== "verified") return undefined;
  if (!access.full_journey) return 0;
  if (access.access_source === "tester_grant" || access.access_source === "review_grant") return undefined;
  return until;
}

/**
 * After an accepted standalone turn whose room froze Pollen facts: one credit to the player's own
 * Player (and, on the turn that finished the chapter together, the partner's first clear). A credit
 * that fails leaves the turn accepted: the reply says `pending` and the phone claims it later. The
 * facts never reach the phone; the `pollen` field goes only to a phone that asked.
 */
export async function creditCommitted(request: Request, env: Env, playerId: string, committed: CommittedV2): Promise<MutationV2 & { pollen?: PollenReply }> {
  const { pollen_facts: facts, ...reply } = committed;
  if (!facts) return reply;
  const partner = facts.complete && facts.together ? (facts.host ? reply.room.guest_id : reply.room.host_id) : null;
  const [own] = await Promise.all([
    settle(() => env.PLAYERS.getByName(playerId).creditTurn(playerId, facts)),
    partner ? settle(() => env.PLAYERS.getByName(partner).creditTogetherClear(partner, facts.level_id, facts.hard, facts.boost_percent)) : null
  ]);
  if (!pollenWanted(request)) return reply;
  return { ...reply, pollen: own?.ok ? own.value : { schema_version: 1, pending: true } };
}

/** A credit's outcome, or null when the call itself failed. */
async function settle<T>(call: () => Promise<Outcome<T>> | Outcome<T>): Promise<Outcome<T> | null> {
  try { return await call(); } catch { return null; }
}

type ClaimResult = { status: "credited"; receipt: PollenReceipt } | { status: "refused"; code: string } | { status: "retry" };
function claimResult(outcome: Outcome<PollenReceipt> | null): ClaimResult {
  if (outcome === null) return { status: "retry" };
  if (outcome.ok) return { status: "credited", receipt: outcome.value };
  // A server pause or missing key may pass; anything else is the claim's own answer and is final.
  return outcome.status >= 500 ? { status: "retry" } : { status: "refused", code: outcome.code };
}

function claimsOf(input: unknown, fields: (claim: Record<string, unknown>) => boolean): Record<string, unknown>[] {
  if (!isObject(input) || Object.keys(input).length !== 2 || input.schema_version !== 1 || !Array.isArray(input.claims) ||
    input.claims.length < 1 || input.claims.length > MAX_CLAIMS_PER_REQUEST || !input.claims.every(claim => isObject(claim) && fields(claim))) throw new ApiError(400, "invalid_pollen_claim");
  return input.claims as Record<string, unknown>[];
}
const only = (claim: Record<string, unknown>, keys: string[]) => Object.keys(claim).length === keys.length && keys.every(key => Object.hasOwn(claim, key));
/** Whether a level_id is a chapter, and whether any version of it is paid. */
function chapterLevel(levelId: string): { premium: boolean } | null {
  const rows = CHAPTERS.filter(row => row.adapter.key.level_id === levelId);
  return rows.length ? { premium: rows.some(row => row.adapter.premium) } : null;
}

/**
 * /v1/pollen routes, after auth(). `view` is what auth() read for GET /v1/pollen and its history.
 * - POST /v1/pollen/turn-claims {schema_version: 1, claims: [{room_id, recording_hash}]}: turns whose
 *   credit did not land; each reads the turn's frozen facts from its room and credits them once.
 * - POST /v1/pollen/clear-claims {schema_version: 1, claims: [{room_id} | {level_id}]}: a first clear
 *   made together in a room (read from the turn that finished it), or a solo first clear the app reports.
 * Each claim answers credited (with its receipt), refused (with a code; final) or retry.
 */
export async function routePollen(request: Request, path: string, playerId: string, env: Env, view?: WalletView | HistoryView): Promise<unknown> {
  if (!pollenEarning(env)) throw new ApiError(503, "pollen_disabled");
  if (path === POLLEN_PATH || path === POLLEN_HISTORY_PATH) {
    if (request.method !== "GET") throw new ApiError(405, "method_not_allowed");
    if (!view) throw new ApiError(503, "pollen_unavailable");
    return view;
  }
  if (path === SPEND_PATH || path === EQUIP_PATH) return routeWardrobe(request, path, playerId, env);
  if (path !== TURN_CLAIMS_PATH && path !== CLEAR_CLAIMS_PATH) throw new ApiError(404, "not_found");
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const player = env.PLAYERS.getByName(playerId), results: (ClaimResult & Record<string, unknown>)[] = [];
  if (path === TURN_CLAIMS_PATH) {
    const claims = claimsOf(await boundedJson(request, 4096), claim => only(claim, ["room_id", "recording_hash"]) &&
      typeof claim.room_id === "string" && ID_PATTERN.test(claim.room_id) && typeof claim.recording_hash === "string" && HASH_PATTERN.test(claim.recording_hash));
    for (const claim of claims) {
      const room_id = claim.room_id as string, recording_hash = claim.recording_hash as string;
      const facts = await settle(() => env.ROOMS_V2.getByName(room_id).pollenTurnFacts(playerId, recording_hash));
      const result = facts === null ? { status: "retry" as const } : !facts.ok ? { status: "refused" as const, code: facts.code }
        : claimResult(await settle(() => player.creditTurn(playerId, facts.value as TurnFacts)));
      results.push({ room_id, recording_hash, ...result });
    }
  } else {
    const claims = claimsOf(await boundedJson(request, 4096), claim => only(claim, ["room_id"]) && typeof claim.room_id === "string" && ID_PATTERN.test(claim.room_id) ||
      only(claim, ["level_id"]) && typeof claim.level_id === "string" && /^[a-z0-9-]{1,64}$/.test(claim.level_id));
    for (const claim of claims) {
      if (typeof claim.level_id === "string") {
        const level = chapterLevel(claim.level_id);
        results.push({ level_id: claim.level_id, ...(level === null ? { status: "refused" as const, code: "unsupported_chapter" } : claimResult(await settle(() => player.creditSoloClear(playerId, claim.level_id as string, level.premium)))) });
        continue;
      }
      const room_id = claim.room_id as string;
      const facts = await settle(() => env.ROOMS_V2.getByName(room_id).pollenClearFacts(playerId));
      const result = facts === null ? { status: "retry" as const } : !facts.ok ? { status: "refused" as const, code: facts.code }
        : claimResult(await settle(() => player.creditTogetherClear(playerId, facts.value.level_id, facts.value.hard && facts.value.together, facts.value.boost_percent)));
      results.push({ room_id, ...result });
    }
  }
  return { schema_version: 1, results };
}

const SPEND_KINDS = ["item", "set", "pack"] as const;
/**
 * POST /v1/pollen/equip (POLLEN_WARDROBE) and /spend (POLLEN_SHOP), after auth(). The body is hashed here, as room
 * operations are, so the Player's spend or equip runs in one synchronous transaction.
 * - spend {schema_version: 1, idempotency_key, kind: "item" | "set" | "pack", id, expected_cost}:
 *   `expected_cost` is what the confirm sheet showed (spend.ts charge).
 * - equip {schema_version: 1, idempotency_key, revision, look}: `look` is the whole look to wear.
 * Cost: one Player request beside auth()'s own.
 */
async function routeWardrobe(request: Request, path: string, playerId: string, env: Env): Promise<unknown> {
  const spend = path === SPEND_PATH;
  if (spend ? !shopOn(env) : !wardrobeOn(env)) throw new ApiError(503, spend ? "pollen_shop_disabled" : "pollen_wardrobe_disabled");
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = await boundedJson(request, 1024), code = spend ? "invalid_pollen_spend" : "invalid_pollen_equip";
  const fields = spend ? ["schema_version", "idempotency_key", "kind", "id", "expected_cost"] : ["schema_version", "idempotency_key", "revision", "look"];
  if (!isObject(input) || !only(input, fields) || input.schema_version !== 1 || typeof input.idempotency_key !== "string" || !IDEMPOTENCY_PATTERN.test(input.idempotency_key)) throw new ApiError(400, code);
  const op = { key: input.idempotency_key, hash: await digest(canonicalJson({ operation: spend ? "spend" : "equip", ...input })) };
  const player = env.PLAYERS.getByName(playerId), device = await bearerDigest(request);
  if (spend) {
    if (!SPEND_KINDS.includes(input.kind as typeof SPEND_KINDS[number]) || typeof input.id !== "string" || !ITEM_ID_PATTERN.test(input.id) ||
      typeof input.expected_cost !== "number" || !Number.isSafeInteger(input.expected_cost) || input.expected_cost < 0) throw new ApiError(400, code);
    return unwrap(await player.pollenSpend(playerId, device, op, { kind: input.kind as typeof SPEND_KINDS[number], id: input.id }, input.expected_cost));
  }
  if (typeof input.revision !== "number" || !Number.isSafeInteger(input.revision) || input.revision < 1 || !isObject(input.look)) throw new ApiError(400, code);
  return unwrap(await player.pollenEquip(playerId, device, op, input.look, input.revision));
}
