import rules from "../../game/content/username_rules.json";
import { ApiError, ID_PATTERN, boundedJson, isObject, unwrap, type Outcome } from "./protocol";
import { bearerDigest } from "./http";
import { flags, type ServerVars } from "./flags";
import { blockedName } from "./name-filter";
import { resolveFriendAlias } from "./friend-aliases";
import { syncMemberName } from "./leaderboards/members";
import { shopOn } from "./pollen/features";

/**
 * Usernames: a unique name each player picks ("thebluebeanie"), shown with its capitals and matched without them.
 * The friend code is friend-<the name in lowercase>; the 22-character friend-<id> codes keep working.
 *
 * - The Player is the truth for what it holds (UsernameFields on its identity JSON): its username, and old names
 *   held for it for USERNAME_HOLD_MS after a change. Claiming one also makes it the display name, so rooms,
 *   leaderboards, the friend link page and older apps show it with no further work (display-names.ts).
 * - The index (username-index.ts) only makes a claim atomic: USERNAME_SHARDS UsernameIndex objects, each name's row
 *   in the shard its hash picks. A claim is one index request on top of the Player write the change already makes.
 *   A rename writes nothing to the old name's row; a later claim of it asks the holder's Player whether it still
 *   holds it, once the row is older than CLAIM_GRACE_MS, and takes it over only if not (claimIndex).
 * - Friend codes resolve an id first, then a CONFIG friend alias, then the index, and the holder's Player confirms
 *   in the identity check the Add already makes (friends-routes.ts).
 * - Clients ask with USERNAMES_HEADER; without it, or with the flag off, every reply is unchanged.
 */
export const USERNAMES_HEADER = "X-AfterYou-Usernames";
export const USERNAMES_VERSION = 1;
export const USERNAME_PATH = "/v1/profile/username";
export const MIN_USERNAME_LENGTH: number = rules.min_length;
export const MAX_USERNAME_LENGTH: number = rules.max_length;
/** How long an old name stays the player's own after a change, before anyone else may take it. */
export const USERNAME_HOLD_MS = 30 * 24 * 3_600_000;
/** Changes to a new name allowed in any rolling USERNAME_WINDOW_MS (the display names' limit); capitals alone never count. */
export const MAX_USERNAME_CHANGES = 5;
export const USERNAME_WINDOW_MS = 24 * 3_600_000;
/** Old names held at once; a sixth change in the window lets the oldest hold go early. */
export const MAX_HELD_USERNAMES = MAX_USERNAME_CHANGES;
/**
 * A claim younger than this is never checked against its holder's Player: it may be between the index write and
 * the Player's commit. Far longer than any request.
 */
export const CLAIM_GRACE_MS = 5 * 60_000;

// ---- Rules ----

const SHAPE = /^[A-Za-z0-9](?:[._-]?[A-Za-z0-9])*$/;
const ALLOWED = /^[A-Za-z0-9._-]*$/;
const RESERVED: ReadonlySet<string> = new Set(rules.reserved);
const RESERVED_INSIDE: readonly string[] = rules.reserved_inside;
const TYPE_PREFIX = new RegExp(`^(?:${rules.type_prefixes.join("|")})[._-]`);

export type UsernameProblem = "length" | "characters" | "symbols" | "username_refused" | "username_reserved";

/** The lowercase form names are matched by, and the friend code shows. */
export const usernameKey = (name: string): string => name.toLowerCase();

/** The shape alone: 3 to 18 allowed characters, a letter or digit at each end, no two symbols in a row. */
export function usernameShaped(value: unknown): value is string {
  return typeof value === "string" && value.length >= MIN_USERNAME_LENGTH && value.length <= MAX_USERNAME_LENGTH && SHAPE.test(value);
}

/** Reserved for the game (username_rules.json): the fold, the brand names inside, and the share code prefixes. */
export function reservedUsername(name: string): boolean {
  const lower = name.toLowerCase(), bare = lower.replace(/[._-]/g, "");
  return RESERVED.has(bare.replace(/[0-9]+$/, "")) || RESERVED_INSIDE.some(word => bare.includes(word)) || TYPE_PREFIX.test(lower);
}

/** What is wrong with a name, or null. Pinned with the game by game/tests/fixtures/display_names/username_vectors.json. */
export function usernameProblem(name: string): UsernameProblem | null {
  if (name.length < MIN_USERNAME_LENGTH || name.length > MAX_USERNAME_LENGTH) return "length";
  if (!ALLOWED.test(name)) return "characters";
  if (!SHAPE.test(name)) return "symbols";
  if (blockedName(name)) return "username_refused";
  return reservedUsername(name) ? "username_reserved" : null;
}

/**
 * The server's check of a name `player` asks for: the rules, then whether it is reserved. A CONFIG friend alias is
 * a reserved name only its own player may take ("aamir" stays the owner's), whatever the reserved list says.
 */
export function checkUsername(env: ServerVars, player: string, input: unknown): { ok: true; name: string; key: string } | { ok: false; status: 400 | 409 | 422; code: string } {
  if (typeof input !== "string" || input.length > 64) return { ok: false, status: 400, code: "invalid_username" };
  const problem = usernameProblem(input), key = usernameKey(input);
  if (problem === "length" || problem === "characters" || problem === "symbols") return { ok: false, status: 400, code: "invalid_username" };
  if (problem === "username_refused") return { ok: false, status: 422, code: "username_refused" };
  const alias = resolveFriendAlias(env, key);
  if (alias !== null) return alias === player ? { ok: true, name: input, key } : { ok: false, status: 409, code: "username_taken" };
  if (problem === "username_reserved") return { ok: false, status: 422, code: "username_reserved" };
  return { ok: true, name: input, key };
}

/** A stored username as it may be served: unchanged when it still has the shape and passes the block list, otherwise null. */
export function shownUsername(value: unknown): string | null {
  return usernameShaped(value) && !blockedName(value) ? value : null;
}

// ---- Identity storage (Player) ----

/**
 * Optional keys on the Player identity JSON. `username_held`: old names still the player's own until `until`.
 * `username_sets` counts names taken, up to 2, for the price (pollen/name-price.ts); `username_changes` the times of
 * changes inside USERNAME_WINDOW_MS. `username_cleared`: the key a moderator last cleared, for the index to retire. A moderator's lock is the display names' one (display_name_locked_until).
 */
export type HeldUsername = { key: string; until: number };
export type UsernameFields = { username?: string; username_held?: HeldUsername[]; username_sets?: number; username_changes?: number[]; username_cleared?: string };
export const USERNAME_KEYS = ["username", "username_held", "username_sets", "username_changes", "username_cleared"] as const;
export const hasUsernameFields = (value: Record<string, unknown>): boolean => USERNAME_KEYS.some(key => Object.hasOwn(value, key));

const safeTime = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
/** The snapshot check for the optional keys that are present. Shape only: serving checks the rules again. */
export function validUsernameFields(value: Record<string, unknown>): boolean {
  if (Object.hasOwn(value, "username") && !usernameShaped(value.username)) return false;
  if (Object.hasOwn(value, "username_cleared") && !(usernameShaped(value.username_cleared) && value.username_cleared === usernameKey(value.username_cleared))) return false;
  if (Object.hasOwn(value, "username_held")) {
    const held = value.username_held;
    if (!Array.isArray(held) || held.length > MAX_HELD_USERNAMES || !held.every(entry => isObject(entry) && Object.keys(entry).length === 2 && usernameShaped(entry.key) && entry.key === usernameKey(entry.key) && safeTime(entry.until))) return false;
  }
  if (Object.hasOwn(value, "username_changes")) {
    const changes = value.username_changes;
    if (!Array.isArray(changes) || changes.length > MAX_USERNAME_CHANGES || !changes.every(safeTime)) return false;
  }
  return !Object.hasOwn(value, "username_sets") || value.username_sets === 1 || value.username_sets === 2;
}

/** Whether the fields hold `key` now: the username, or an old name whose hold has not run out. */
export function holdsUsername(fields: UsernameFields, key: string, now: number): boolean {
  return (fields.username !== undefined && usernameKey(fields.username) === key) || (fields.username_held ?? []).some(entry => entry.key === key && entry.until > now);
}

/** Every name the fields keep a claim on (the username and every hold, run out or not), for erasure. */
export function claimedKeys(fields: UsernameFields): string[] {
  return [...new Set([...(fields.username !== undefined ? [usernameKey(fields.username)] : []), ...(fields.username_held ?? []).map(entry => entry.key)])];
}

export type UsernameState = { schema_version: 1; username: string | null };
export type UsernameOutcome = Outcome<UsernameState> | { ok: false; status: 429; code: "username_limited"; retry_after_seconds: number };

/**
 * What a change to `name` needs, before any write: `same` (nothing to do), a capitals-only change (`index` false,
 * free, not counted) or a new name (`index` true). Refusals: the moderator's lock, then the rolling limit.
 */
export function planUsername(fields: UsernameFields & { display_name_locked_until?: number }, name: string, now: number): { ok: true; same: boolean; index: boolean } | { ok: false; status: 403; code: "username_locked" } | { ok: false; status: 429; code: "username_limited"; retry_after_seconds: number } {
  if (fields.username === name) return { ok: true, same: true, index: false };
  if (fields.username !== undefined && usernameKey(fields.username) === usernameKey(name)) return { ok: true, same: false, index: false };
  if ((fields.display_name_locked_until ?? 0) > now) return { ok: false, status: 403, code: "username_locked" };
  const recent = (fields.username_changes ?? []).filter(at => at > now - USERNAME_WINDOW_MS);
  if (recent.length >= MAX_USERNAME_CHANGES) {
    return { ok: false, status: 429, code: "username_limited", retry_after_seconds: Math.max(1, Math.ceil((Math.min(...recent) + USERNAME_WINDOW_MS - now) / 1000)) };
  }
  return { ok: true, same: false, index: true };
}

/** Applies a planned change in place. A new name is counted and the old one held; capitals alone change nothing else. */
export function applyUsername(fields: UsernameFields, name: string, counted: boolean, now: number): void {
  const before = fields.username, key = usernameKey(name);
  let held = (fields.username_held ?? []).filter(entry => entry.until > now && entry.key !== key);
  if (before !== undefined && usernameKey(before) !== key) held = [...held, { key: usernameKey(before), until: now + USERNAME_HOLD_MS }].slice(-MAX_HELD_USERNAMES);
  if (held.length > 0) fields.username_held = held; else delete fields.username_held;
  fields.username = name;
  if (counted) {
    fields.username_changes = [...(fields.username_changes ?? []).filter(at => at > now - USERNAME_WINDOW_MS), now];
    fields.username_sets = Math.min(2, (fields.username_sets ?? 0) + 1);
  }
}

/** The operator clear: no username, its key noted in `username_cleared` for the index to retire; old holds stay. */
export function clearUsernameFields(fields: UsernameFields): void {
  if (fields.username === undefined) return;
  fields.username_cleared = usernameKey(fields.username);
  delete fields.username;
}

// ---- The index ----

/** Shards of the index. Changing this or usernameShard remaps every name: never change either once live. */
export const USERNAME_SHARDS = 32;
/** The shard object's name for a lowercase key (FNV-1a over its characters). */
export function usernameShard(key: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < key.length; i++) { hash ^= key.charCodeAt(i); hash = Math.imul(hash, 0x01000193) >>> 0; }
  return `shard-${hash % USERNAME_SHARDS}`;
}
export const usernameIndex = (env: Env, key: string) => env.USERNAMES.getByName(usernameShard(key));

/**
 * Takes `key` in the index for `player`: free, already theirs, or held by someone whose Player no longer holds it
 * (asked only once the row is past CLAIM_GRACE_MS, and taken over only if the row is still the one read).
 * One index request when free or already theirs.
 */
export async function claimIndex(env: Env, key: string, player: string, now: number): Promise<boolean> {
  const shard = usernameIndex(env, key);
  const answer = await shard.claim(key, player, now);
  if (answer.ok) return true;
  if (answer.code !== "username_check") return false;
  if (await env.PLAYERS.getByName(answer.owner).usernameHolds(answer.owner, key)) return false;
  return shard.takeOver(key, player, answer.owner, answer.rev, Date.now());
}

/** The player id a username names in the index, or null. The caller confirms it with that Player. */
export async function lookupUsername(env: Env, name: string): Promise<{ id: string; key: string } | null> {
  const key = usernameKey(name);
  const id = await usernameIndex(env, key).lookup(key);
  return id !== null && ID_PATTERN.test(id) ? { id, key } : null;
}

// ---- Routes ----

/** Usernames need display names on: the name is also the display name. */
export const usernamesOn = (env: ServerVars): boolean => flags.usernames(env) && flags.displayNames(env);
export const usernamesWanted = (request: Request): boolean => request.headers.get(USERNAMES_HEADER) === "1";
/** Usernames are served only to clients that ask while the flags are on. */
export function usernamesShown(request: Request, env: ServerVars): boolean { return usernamesOn(env) && usernamesWanted(request); }
/** The capability field for GET /v2/capabilities. */
export function usernamesCapability(request: Request, env: ServerVars): { usernames_version?: number } {
  return usernamesShown(request, env) ? { usernames_version: USERNAMES_VERSION } : {};
}

export type UsernameView = { schema_version: 1; username: string | null; suggestion?: string; pollen_price?: number; pollen_price_next?: number };

/**
 * GET and PUT /v1/profile/username, after auth().
 *
 * GET answers the username (or null), the change price while the shop is on, and for a player with none their
 * display name as a suggestion when it passes every rule and nobody holds it (one index read, only then).
 *
 * PUT {schema_version: 1, username, pollen_price?}: pollen_price is the price the phone showed beside Save, sent
 * while the shop is on. Refusals: 400 invalid_username, 422 username_refused or username_reserved, 409
 * username_taken or name_change_price, 403 username_locked, 402 pollen_short, 429 username_limited.
 */
export async function routeUsername(request: Request, playerId: string, env: Env): Promise<UsernameView | UsernameState> {
  if (!usernamesOn(env)) throw new ApiError(503, "usernames_disabled");
  const hash = await bearerDigest(request), player = env.PLAYERS.getByName(playerId), shop = shopOn(env);
  if (request.method === "GET") {
    const view = unwrap(await player.usernameView(playerId, hash, shop));
    const answer: UsernameView = { schema_version: 1, username: shownUsername(view.username), ...(view.price !== undefined ? { pollen_price: view.price, pollen_price_next: view.price_next } : {}) };
    const suggestion = view.username === null && view.display_name !== null ? checkUsername(env, playerId, view.display_name) : null;
    if (suggestion?.ok && (await usernameIndex(env, suggestion.key).lookup(suggestion.key)) === null) answer.suggestion = suggestion.name;
    return answer;
  }
  if (request.method !== "PUT") throw new ApiError(405, "method_not_allowed");
  const input = await boundedJson(request, 1024);
  const priced = isObject(input) && Object.hasOwn(input, "pollen_price");
  if (!isObject(input) || Object.keys(input).length !== 2 + Number(priced) || input.schema_version !== 1 || typeof input.username !== "string" ||
    priced && !(typeof input.pollen_price === "number" && Number.isSafeInteger(input.pollen_price) && input.pollen_price >= 0)) throw new ApiError(400, "invalid_username");
  const checked = checkUsername(env, playerId, input.username);
  if (!checked.ok) throw new ApiError(checked.status, checked.code);
  const outcome = await player.claimUsername(playerId, hash, checked.name, priced ? input.pollen_price as number : undefined, shop);
  if (!outcome.ok && "retry_after_seconds" in outcome) throw new ApiError(429, outcome.code, { retry_after_seconds: outcome.retry_after_seconds });
  const answer = unwrap(outcome);
  // Boards that show this player's name take the new one (leaderboards/members.ts); best effort, as for display names.
  if (flags.leaderboards(env)) await syncMemberName(env, playerId).catch(() => undefined);
  return { schema_version: 1, username: answer.username };
}
