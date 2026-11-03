import { flags, type ServerVars } from "../flags";
import { accountTokens, pairAccountKey, type PairKeys } from "./pair-accounts";
import { pairKey } from "./run";

/**
 * The platform rule for leaderboard posts, behind LEADERBOARD_REQUIRE_PLATFORM (needs LEADERBOARDS): a finished
 * together run enters its board only when both players have a Play Games or Game Center link (platform-links.ts),
 * so a run from throwaway identities never reaches a board. A link of either provider counts, whatever its own
 * flag says now: it was verified when it was made.
 *
 * Cost while on: one PlatformLinks request, a read only, per post that could place (submit.ts postRun, after the
 * free cached board check). Off: none. A refused run writes nothing anywhere, so a later post of the same run
 * (leaderboards/routes.ts, once both are linked) is not answered "known".
 *
 * Keep it off while Game Center is off (GAME_CENTER_ENABLED, and the iOS export's game_center entitlement):
 * iPhone players could never link, so no iPhone pair could post.
 */
export function platformRequiredOn(env: ServerVars): boolean { return flags.leaderboards(env) && flags.leaderboardRequirePlatform(env); }

/**
 * The members with no platform link, in the order given ([] when every one is linked), and, when both are linked,
 * the pair's account key (pair-accounts.ts). One Durable Object request.
 */
export async function pairAccounts(env: Env, members: readonly [string, string]): Promise<{ unlinked: string[]; account_key?: string }> {
  const tokens = await accountTokens(env, members);
  const unlinked = members.filter(id => !tokens.has(id));
  const account_key = await pairAccountKey(tokens, members);
  return account_key === undefined ? { unlinked } : { unlinked, account_key };
}

/**
 * Each pair's keys for a duel (duels/routes.ts): its pairKey, and while the rule is on its account key too when
 * both players are linked. One PlatformLinks read for every player while the rule is on, none while it is off.
 * A platform account links one player only (platform-links.ts), so two pairs never share a token.
 */
export async function duelPairKeys(env: Env, pairs: readonly (readonly [string, string])[]): Promise<PairKeys[]> {
  const ids = await Promise.all(pairs.map(pair => pairKey(pair[0], pair[1])));
  if (!platformRequiredOn(env)) return ids.map(pair_key => ({ pair_key }));
  const tokens = await accountTokens(env, pairs.flat());
  return Promise.all(pairs.map(async (pair, index): Promise<PairKeys> => {
    const account_key = await pairAccountKey(tokens, pair);
    return account_key === undefined ? { pair_key: ids[index] } : { pair_key: ids[index], account_key };
  }));
}
