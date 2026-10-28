import { ApiError, ID_PATTERN, boundedJson, isObject, unwrap, type Outcome } from "./protocol";
import { bearerDigest } from "./http";
import { flags, type ServerVars } from "./flags";
import { ROOM_INBOX_CONCURRENCY, pooled } from "./room-inbox";
import { syncMemberName, syncMemberNameIfKnown } from "./leaderboards/members";
import { resolveFriendAlias } from "./friend-aliases";
import { blockedName } from "./name-filter";
import { shopOn } from "./pollen/features";

export { blockedName };

/**
 * Display names: an optional name a player picks for friends and room partners.
 *
 * - The name lives in optional keys on the Player identity JSON (DisplayNameFields), never in `social`.
 * - PUT /v1/profile/name sets or clears it (auth plus one Player call). Nothing fans out on a change.
 * - GET /v1/friends carries names from calls the list already makes; accepted friends only.
 * - v2 rooms keep a copy per member in `member_names`, written inside the join, create and turn calls
 *   while the flag is on, and served as `partner_name` on full room reads, turn replies and the inbox.
 * - Every served name is checked again against the rules and the block list, so a list update hides
 *   an older name without a migration.
 * - Clients ask with DISPLAY_NAMES_HEADER; without it, or with the flag off, every reply is unchanged.
 */
export const DISPLAY_NAMES_HEADER = "X-AfterYou-Display-Names";
export const DISPLAY_NAMES_VERSION = 1;
export const DISPLAY_NAME_PATH = "/v1/profile/name";
export const MAX_DISPLAY_NAME_LENGTH = 18;
/** Non-null changes allowed in any rolling DISPLAY_NAME_WINDOW_MS. Clearing to anonymous is never counted. */
export const MAX_DISPLAY_NAME_CHANGES = 5;
export const DISPLAY_NAME_WINDOW_MS = 24 * 3_600_000;
/** How far ahead of the server's clock a revision may be (phones send milliseconds since 1970). */
export const MAX_REVISION_AHEAD_MS = 24 * 3_600_000;
/** How long an operator clear refuses new names. */
export const DISPLAY_NAME_LOCK_MS = 7 * 24 * 3_600_000;
/** Rooms one operator clear reaches: the admission bound for room links (room-limit.ts MAX_INDEXED_ROOM_LINKS). */
export const MAX_CLEARED_ROOMS = 500;

// ---- Rules ----

export type CleanedName = { ok: true; name: string } | { ok: false; code: "invalid_display_name" | "display_name_refused" };
/** Letters, non-enclosing marks, numbers, space separators and . ' - _ ! ? (ASCII apostrophe and U+2019). Everything else is refused. */
const ALLOWED = /^[\p{L}\p{Mn}\p{Mc}\p{N}\p{Zs}.'\-_!?\u2019]$/u;
/** Marks that draw nothing: variation selectors, the grapheme joiner, Khmer inherent vowels and Mongolian selectors. */
const INVISIBLE_MARKS = /[\u034F\u17B4\u17B5\u180B-\u180F\uFE00-\uFE0F\u{E0100}-\u{E01EF}]/u;
/** A mark at the start would sit on the text before the name on screen. */
const LEADING_MARK = /^\p{M}/u;
const MARK_RUN = /\p{M}{3,}/u;
/** Longest raw input looked at; anything longer could never clean to 18 code points of allowed text plus spacing. */
const MAX_RAW_UNITS = 256;

/**
 * The server's name rules. NFC first, then every code point must be allowed (so control, format,
 * separator, private-use, unassigned and surrogate code points are refused before any trimming),
 * then runs of spaces become one ASCII space, the ends are trimmed, the length is 1 to 18 code
 * points, no more than two combining marks stand in a row, and the block list has no match.
 */
export function cleanDisplayName(input: unknown): CleanedName {
  const name = formedName(input);
  if (name === null) return { ok: false, code: "invalid_display_name" };
  return blockedName(name) ? { ok: false, code: "display_name_refused" } : { ok: true, name };
}

/** Every rule except the block list: the cleaned name, or null. */
function formedName(input: unknown): string | null {
  if (typeof input !== "string" || input.length > MAX_RAW_UNITS) return null;
  const composed = input.normalize("NFC");
  for (const point of composed) if (!ALLOWED.test(point)) return null;
  const name = composed.replace(/\p{Zs}+/gu, " ").trim();
  const length = [...name].length;
  if (length < 1 || length > MAX_DISPLAY_NAME_LENGTH || MARK_RUN.test(name) || BLANK_LETTERS.test(name) || INVISIBLE_MARKS.test(name) || LEADING_MARK.test(name) || !VISIBLE.test(name)) return null;
  return name;
}

/** Letters that draw nothing (Hangul fillers, the blank Braille cell), so a name of them looks empty. */
const BLANK_LETTERS = /[\u115F\u1160\u3164\uFFA0\u2800]/u;
/** A name needs at least one letter or digit, so marks or punctuation alone never make one. */
const VISIBLE = /[\p{L}\p{N}]/u;

/** A stored name as it may be served: unchanged when it still passes every rule, otherwise null. */
export function shownName(value: unknown): string | null {
  return typeof value === "string" && formedName(value) === value && !blockedName(value) ? value : null;
}

// ---- Identity storage (Player) ----

/**
 * Optional keys on the Player identity JSON. `display_name_changes` holds the times of non-null sets inside the window.
 * `display_name_sets` counts names set while the shop was on, up to 2, for the name change price (pollen/name-price.ts).
 */
export type DisplayNameFields = { display_name?: string; display_name_changes?: number[]; display_name_rev?: number; display_name_locked_until?: number; display_name_sets?: number };
export const DISPLAY_NAME_KEYS = ["display_name", "display_name_changes", "display_name_rev", "display_name_locked_until", "display_name_sets"] as const;
export type DisplayNameState = { schema_version: 1; display_name: string | null; revision: number };
export type DisplayNameOutcome = Outcome<DisplayNameState> | { ok: true; value: DisplayNameState; cleared_rooms: string[] } | { ok: false; status: 429; code: "display_name_limited"; retry_after_seconds: number };

const safeTime = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
/** The snapshot check for the optional keys that are present. */
export function validDisplayNameFields(value: Record<string, unknown>): boolean {
  // Shape only, not the name rules: a later change to the rules must never stop an export or a
  // restore of a name stored under the old ones. Serving checks every rule again (shownName).
  if (Object.hasOwn(value, "display_name") && !storableName(value.display_name)) return false;
  if (Object.hasOwn(value, "display_name_changes")) {
    const changes = value.display_name_changes;
    if (!Array.isArray(changes) || changes.length > MAX_DISPLAY_NAME_CHANGES || !changes.every(safeTime)) return false;
  }
  if (Object.hasOwn(value, "display_name_rev") && !(safeTime(value.display_name_rev) && value.display_name_rev >= 1)) return false;
  if (Object.hasOwn(value, "display_name_sets") && !(value.display_name_sets === 1 || value.display_name_sets === 2)) return false;
  return !Object.hasOwn(value, "display_name_locked_until") || safeTime(value.display_name_locked_until);
}
/** A stored name's shape: 1 to 18 code points with no control, format, surrogate, private-use or unassigned ones. */
function storableName(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const length = [...value].length;
  return length >= 1 && length <= MAX_DISPLAY_NAME_LENGTH && !/[\p{Cc}\p{Cf}\p{Cs}\p{Co}\p{Cn}]/u.test(value);
}
export const hasDisplayNameFields = (value: Record<string, unknown>): boolean => DISPLAY_NAME_KEYS.some(key => Object.hasOwn(value, key));

function state(fields: DisplayNameFields): DisplayNameState {
  return { schema_version: 1, display_name: shownName(fields.display_name), revision: fields.display_name_rev ?? 0 };
}

/**
 * Applies one PUT to the identity's fields in place; `changed` says whether they need writing.
 * Order: an old revision answers the current state; the same name only moves the revision (so a
 * later retry of an older revision cannot win); a lock or the rolling limit refuses a non-null name
 * and changes nothing; null (anonymous) always clears.
 */
export function applyDisplayName(fields: DisplayNameFields, name: string | null, revision: number, now: number): { outcome: DisplayNameOutcome; changed: boolean } {
  if (name !== null && shownName(name) !== name) return { outcome: { ok: false, status: 400, code: "invalid_display_name" }, changed: false };
  // Phones send milliseconds since 1970; one far in the future would make every later change stale.
  if (!Number.isSafeInteger(revision) || revision < 1 || revision > now + MAX_REVISION_AHEAD_MS) return { outcome: { ok: false, status: 400, code: "invalid_display_name" }, changed: false };
  if (revision <= (fields.display_name_rev ?? 0)) return { outcome: { ok: true, value: state(fields) }, changed: false };
  if (name !== null && name !== (fields.display_name ?? null)) {
    if ((fields.display_name_locked_until ?? 0) > now) return { outcome: { ok: false, status: 403, code: "display_name_locked" }, changed: false };
    const recent = (fields.display_name_changes ?? []).filter(at => at > now - DISPLAY_NAME_WINDOW_MS);
    if (recent.length >= MAX_DISPLAY_NAME_CHANGES) {
      const retry = Math.max(1, Math.ceil((Math.min(...recent) + DISPLAY_NAME_WINDOW_MS - now) / 1000));
      return { outcome: { ok: false, status: 429, code: "display_name_limited", retry_after_seconds: retry }, changed: false };
    }
    fields.display_name = name;
    fields.display_name_changes = [...recent, now];
  } else if (name === null) delete fields.display_name;
  fields.display_name_rev = revision;
  if ((fields.display_name_locked_until ?? Infinity) <= now) delete fields.display_name_locked_until;
  return { outcome: { ok: true, value: state(fields) }, changed: true };
}

/** The operator clear: no name, and new names refused until at least now + DISPLAY_NAME_LOCK_MS. */
export function clearDisplayNameFields(fields: DisplayNameFields, now: number): void {
  delete fields.display_name;
  fields.display_name_locked_until = Math.max(fields.display_name_locked_until ?? 0, now + DISPLAY_NAME_LOCK_MS);
}

// ---- Room copy (RoomV2) ----

/**
 * One row per member who had a name when they last joined, created the room or took a turn
 * while the flag was on. Created by the first such write, dropped by the full room erase, left out
 * of operator snapshots and cleared by a restore.
 */
export const MEMBER_NAMES = {
  name: "member_names",
  schema: "CREATE TABLE member_names (player_id TEXT PRIMARY KEY, display_name TEXT NOT NULL)"
} as const;
/**
 * Whether the table exists, looked up once per room instance, so a room without names reads no
 * more rows than before. A write or drop forgets the answer instead of setting it, so a
 * transaction that rolls back can never leave it wrong.
 */
const memberTables = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let known = memberTables.get(storage);
  if (known === undefined) {
    known = storage.sql.exec("SELECT 1 AS found FROM sqlite_master WHERE type='table' AND name='member_names'").toArray().length > 0;
    memberTables.set(storage, known);
  }
  return known;
}

/**
 * The member's current name, passed into a write the room already makes: undefined writes nothing
 * (the flag is off), null deletes the row, a name upserts it only when it differs. The caller owns
 * the transaction.
 */
export function recordMemberName(storage: DurableObjectStorage, player: string, name: string | null | undefined): void {
  if (name === undefined || !ID_PATTERN.test(player)) return;
  const kept = shownName(name);
  if (kept === null) { eraseMemberName(storage, player); return; }
  if (present(storage) && storage.sql.exec<{ display_name: string }>("SELECT display_name FROM member_names WHERE player_id=?", player).toArray()[0]?.display_name === kept) return;
  storage.sql.exec(MEMBER_NAMES.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT OR REPLACE INTO member_names VALUES (?,?)", player, kept);
  memberTables.delete(storage);
}

/** The stored name of `player` as it may be served, or null. A room without the table reads nothing. */
export function memberName(storage: DurableObjectStorage, player: string | null): string | null {
  if (player === null || !present(storage)) return null;
  return shownName(storage.sql.exec<{ display_name: string }>("SELECT display_name FROM member_names WHERE player_id=?", player).toArray()[0]?.display_name);
}

/** Deletes one member's row (leaving a finished room, a null name, an operator clear); true when a row went. */
export function eraseMemberName(storage: DurableObjectStorage, player: string): boolean {
  if (!present(storage)) return false;
  return storage.sql.exec("DELETE FROM member_names WHERE player_id=?", player).rowsWritten > 0;
}

/** For the full room erase and a snapshot restore. */
export function clearMemberNames(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS member_names");
  memberTables.delete(storage);
}

/** The table as sqlite_master lists it, so snapshot schema checks can let it pass. */
export function isMemberNamesTable(row: { name: string; sql: string }): boolean {
  return row.name === MEMBER_NAMES.name && row.sql === MEMBER_NAMES.schema;
}

/** The inbox projection field: present only when the partner has a stored name. */
export function partnerNameField(storage: DurableObjectStorage, partner: string | null): { partner_name?: string } {
  const name = memberName(storage, partner);
  return name === null ? {} : { partner_name: name };
}

// ---- Routes ----

export function displayNamesWanted(request: Request): boolean { return request.headers.get(DISPLAY_NAMES_HEADER) === "1"; }
/** Names are served only to clients that ask while the flag is on. */
export function displayNamesShown(request: Request, env: ServerVars): boolean { return flags.displayNames(env) && displayNamesWanted(request); }
/** The capability field for GET /v2/capabilities: empty unless the flag is on and the client asked. */
export function displayNamesCapability(request: Request, env: ServerVars): { display_names_version?: number } {
  return displayNamesShown(request, env) ? { display_names_version: DISPLAY_NAMES_VERSION } : {};
}
/** Routes outside a room id that write the caller's name into a room (create and join), so auth() reads it with the device check. */
export function namesRoomRoute(request: Request, path: string, env: ServerVars): boolean {
  return request.method === "POST" && (path === "/v2/rooms" || path === "/v2/rooms/join") && flags.displayNames(env);
}

/**
 * The PUT body: exactly schema_version 1, display_name (string or null) and revision (safe integer >= 1),
 * and optionally pollen_price: the name change price the phone showed beside Save (a client that knows
 * the shop sends it). Any other shape is 400 invalid_display_name.
 */
function parseRequest(input: unknown): { name: string | null; revision: number; shown?: number } {
  const priced = isObject(input) && Object.hasOwn(input, "pollen_price");
  if (!isObject(input) || Object.keys(input).length !== 3 + Number(priced) || input.schema_version !== 1 || !Object.hasOwn(input, "display_name") ||
    (input.display_name !== null && typeof input.display_name !== "string") || typeof input.revision !== "number" || !Number.isSafeInteger(input.revision) || input.revision < 1 ||
    priced && !(typeof input.pollen_price === "number" && Number.isSafeInteger(input.pollen_price) && input.pollen_price >= 0)) {
    throw new ApiError(400, "invalid_display_name");
  }
  return { name: input.display_name as string | null, revision: input.revision, ...(priced ? { shown: input.pollen_price as number } : {}) };
}

/** PUT /v1/profile/name, after auth(). The flag is checked before the body or the Player is read. */
export async function routeDisplayName(request: Request, playerId: string, env: Env): Promise<DisplayNameState> {
  if (!flags.displayNames(env)) throw new ApiError(503, "display_names_disabled");
  if (request.method !== "PUT") throw new ApiError(405, "method_not_allowed");
  const { name, revision, shown } = parseRequest(await boundedJson(request, 1024));
  let cleaned: string | null = null;
  if (name !== null) {
    const result = cleanDisplayName(name);
    if (!result.ok) throw new ApiError(result.code === "display_name_refused" ? 422 : 400, result.code);
    cleaned = result.name;
  }
  // While the shop is on, a change may cost Pollen (pollen/name-price.ts); the Player charges it with the change.
  const pricing = shopOn(env) ? { shown } : undefined;
  const outcome = await env.PLAYERS.getByName(playerId).setDisplayName(playerId, await bearerDigest(request), cleaned, revision, pricing);
  if (!outcome.ok && "retry_after_seconds" in outcome) throw new ApiError(429, outcome.code, { retry_after_seconds: outcome.retry_after_seconds });
  // Going anonymous takes the name out of the player's rooms now, not at their next turn there.
  // It happens at most once per named set, so the 5-a-day limit bounds it. Best effort: a room
  // missed here drops the name at the player's next turn in it.
  if (outcome.ok && "cleared_rooms" in outcome && Array.isArray(outcome.cleared_rooms)) await clearRooms(env, playerId, outcome.cleared_rooms);
  const answer = unwrap(outcome);
  // Boards that show this player's name take the new one (leaderboards/members.ts); best effort, like the rooms.
  if (flags.leaderboards(env)) await syncMemberName(env, playerId).catch(() => undefined);
  return { schema_version: answer.schema_version, display_name: answer.display_name, revision: answer.revision };
}

/** Deletes the player's row in each room, four at a time; true for each room reached. */
async function clearRooms(env: Env, player: string, rooms: readonly string[]): Promise<boolean[]> {
  return pooled(rooms, ROOM_INBOX_CONCURRENCY, async roomId => {
    try { await env.ROOMS_V2.getByName(roomId).clearMemberName(player); return true; } catch { return false; }
  });
}

// ---- Friend link page (public, read-only) ----

/** The one page that may read a name: the friend link page on the owner's site. */
export const FRIEND_LINK_ORIGIN = "https://aamirazeez.com";
/** Seconds a browser, and this worker's edge cache, may keep an answer. */
export const FRIEND_LINK_MAX_AGE = 300;
const FRIEND_LINK_PATH = /^\/v1\/friend-link\/([A-Za-z0-9_-]{1,32})\/name$/;
const FRIEND_LINK_HEADERS = Object.freeze({
  "Cache-Control": `public, max-age=${FRIEND_LINK_MAX_AGE}`, "Access-Control-Allow-Origin": FRIEND_LINK_ORIGIN, "Vary": "Origin",
  "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8"
});

/** The friend id or short name in a GET /v1/friend-link/<code>/name path, or null for any other path. */
export function friendLinkCode(path: string): string | null {
  return FRIEND_LINK_PATH.exec(path)?.[1] ?? null;
}

function friendLinkAnswer(name: string | null): Response {
  return new Response(JSON.stringify({ schema_version: 1, display_name: name }), { status: 200, headers: FRIEND_LINK_HEADERS });
}

/**
 * GET /v1/friend-link/<friend id or short name>/name, for the friend link page's headline. It
 * answers only a chosen display name, or null. An unknown code, a deleted or never-made identity, an
 * anonymous player, a removed name and the flag off all answer the same null, so the page cannot tell
 * them apart. A short name resolves through FRIEND_ALIASES as an Add friend does. At most one Player
 * read, which stores nothing for an id nobody created; answers are kept for FRIEND_LINK_MAX_AGE.
 */
export async function routeFriendLinkName(request: Request, code: string, env: Env): Promise<Response> {
  if (!flags.displayNames(env)) return friendLinkAnswer(null);
  const id = ID_PATTERN.test(code) ? code : resolveFriendAlias(env, code);
  if (id === null) return friendLinkAnswer(null);
  // Keyed by the resolved id, so a short name and its long code share one entry.
  const key = new Request(`${new URL(request.url).origin}/__friend-link-name/${id}`);
  const cache = typeof caches === "undefined" ? null : caches.default;
  const kept = cache ? await cache.match(key).catch(() => undefined) : undefined;
  if (kept) return new Response(kept.body, { status: 200, headers: FRIEND_LINK_HEADERS });
  const answer = friendLinkAnswer(shownName(await env.PLAYERS.getByName(id).publicDisplayName(id)));
  if (cache) await cache.put(key, answer.clone()).catch(() => undefined);
  return answer;
}

const OPERATOR_PATH = /^\/operator\/safety\/players\/([A-Za-z0-9_-]{22})\/clear-name$/;
/**
 * POST /operator/safety/players/<id>/clear-name, after requireOperator: clears the name, locks new
 * names for DISPLAY_NAME_LOCK_MS and deletes the player's row in each of their v2 rooms (at most
 * MAX_CLEARED_ROOMS, four at a time). Every step can run again, so a failed or repeated call is safe
 * to resend; a repeat extends the lock from the time of the repeat. Null when the path is another one.
 */
export async function routeDisplayNameOperator(request: Request, path: string, env: Env): Promise<{ schema_version: 1; cleared: true; rooms: number } | null> {
  const match = OPERATOR_PATH.exec(path);
  if (!match) return null;
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = await boundedJson(request, 1024);
  if (!isObject(input) || Object.keys(input).length !== 1 || input.schema_version !== 1) throw new ApiError(400, "invalid_safety_request");
  const player = match[1];
  const rooms = unwrap(await env.PLAYERS.getByName(player).operatorClearDisplayName(player));
  const reached = await clearRooms(env, player, rooms);
  // Boards drop the name too, whatever the leaderboards flag says; a failure asks for the repeat this route allows.
  // A player who never touched leaderboards shows no name there, so only a read happens and nothing is stored.
  const boards = await syncMemberNameIfKnown(env, player).then(() => true, () => false);
  if (reached.some(done => !done) || !boards) throw new ApiError(503, "display_name_clear_incomplete");
  return { schema_version: 1, cleared: true, rooms: rooms.length };
}
