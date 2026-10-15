import { ID_PATTERN, isObject } from "./protocol";
import type { ServerVars } from "./flags";

/**
 * Owner-reserved short friend names. FRIEND_ALIASES is a plain var holding a
 * small JSON object of alias -> 22-character player id, set only by deploys.
 * An alias is a public pointer to an existing player, never a credential: the
 * account stays protected by its device token and recovery code. Any invalid
 * value disables every alias (fail closed) and leaves the normal id path alone.
 */
export const ALIAS_PATTERN = /^[a-z][a-z0-9]{2,15}$/;
export const MAX_FRIEND_ALIASES = 32;
/** Opt-in request header for the optional friend_alias field on GET /v1/friends.
 * 0.6.0 and older clients reject a profile with an extra key, so they never get it. */
export const FRIEND_ALIAS_HEADER = "X-AfterYou-Friends";

type Aliases = { byAlias: ReadonlyMap<string, string>; byId: ReadonlyMap<string, string> };
const NONE: Aliases = { byAlias: new Map(), byId: new Map() };
let memo: { raw: unknown; value: Aliases } | null = null;

export function parseFriendAliases(raw: unknown): Aliases {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 4096) return NONE;
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { return NONE; }
  if (!isObject(parsed) || Object.getPrototypeOf(parsed) !== Object.prototype) return NONE;
  const entries = Object.entries(parsed);
  if (entries.length > MAX_FRIEND_ALIASES) return NONE;
  const byAlias = new Map<string, string>(), byId = new Map<string, string>();
  for (const [alias, id] of entries) {
    if (!ALIAS_PATTERN.test(alias) || typeof id !== "string" || !ID_PATTERN.test(id) || byId.has(id)) return NONE;
    byAlias.set(alias, id); byId.set(id, alias);
  }
  return { byAlias, byId };
}

function aliases(env: ServerVars): Aliases {
  const raw = env.FRIEND_ALIASES;
  if (memo === null || memo.raw !== raw) memo = { raw, value: parseFriendAliases(raw) };
  return memo.value;
}

/** A shaped alias -> its id, or null. Matching is case-insensitive. */
export function resolveFriendAlias(env: ServerVars, code: string): string | null {
  const alias = code.toLowerCase();
  if (!ALIAS_PATTERN.test(alias)) return null;
  return aliases(env).byAlias.get(alias) ?? null;
}

/** True when code has the alias shape (any case), known or not. */
export const aliasShaped = (code: string): boolean => ALIAS_PATTERN.test(code.toLowerCase());

export const friendAliasFor = (env: ServerVars, id: string): string | undefined => aliases(env).byId.get(id);
