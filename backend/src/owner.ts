import type { ServerVars } from "./flags";
import { serverConfig } from "./config";

/**
 * The owner's own player, named only by CONFIG's friend_aliases (config.ts): OWNER_ALIAS points at it, so no player
 * id is ever in code. An invalid alias map has no aliases (config.ts fails closed), so then there is no owner.
 * Read in the Worker and handed to a Durable Object when it needs it (its own env never gets a test's CONFIG).
 */
export const OWNER_ALIAS = "aamir";

/** The owner's player id, or null when CONFIG names none. */
export function ownerId(env: ServerVars): string | null {
  return serverConfig(env).friend_aliases.byAlias.get(OWNER_ALIAS) ?? null;
}
