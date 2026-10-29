import type { ServerVars } from "./flags";
import { ALIAS_PATTERN, serverConfig } from "./config";

/**
 * Owner-reserved short friend names: CONFIG's friend_aliases, a small object of alias -> 22-character player id
 * (config.ts checks it). An alias is a public pointer to an existing player, never a credential: the account stays
 * protected by its device token and recovery code. Any invalid entry disables every alias (fail closed) and leaves
 * the normal id path alone.
 */
/** Opt-in request header for the optional friend_alias field on GET /v1/friends.
 * 0.6.0 and older clients reject a profile with an extra key, so they never get it. */
export const FRIEND_ALIAS_HEADER = "X-AfterYou-Friends";

/** A shaped alias -> its id, or null. Matching is case-insensitive. */
export function resolveFriendAlias(env: ServerVars, code: string): string | null {
  const alias = code.toLowerCase();
  if (!ALIAS_PATTERN.test(alias)) return null;
  return serverConfig(env).friend_aliases.byAlias.get(alias) ?? null;
}

/** True when code has the alias shape (any case), known or not. */
export const aliasShaped = (code: string): boolean => ALIAS_PATTERN.test(code.toLowerCase());

export const friendAliasFor = (env: ServerVars, id: string): string | undefined => serverConfig(env).friend_aliases.byId.get(id);
