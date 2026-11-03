import { digest } from "../protocol";
import { PLATFORM_LINKS_OBJECT } from "../platform-links";

/**
 * Pairs keyed by their platform accounts (claude-20261011 PAIR-KEYS.md), while the platform rule is on
 * (platform-rule.ts): a pair whose two players both have a platform link also carries `account_key`, a hash of
 * their two account tokens (platform-links.ts accountsAmong), so every identity pair behind the same two
 * accounts counts as one pair on the boards and in duels. `pair_key` (run.ts pairKey, the two player ids) stays
 * beside it, so entries and duels made before the rule still match their own pair.
 *
 * Neither key ever goes to a phone: board, duel and lobby views are built field by field without them.
 */
export type PairKeys = { pair_key: string; account_key?: string };

const ACCOUNT_PAIR_DOMAIN = "after-you leaderboard pair accounts v1\n";

/** The pair key of two account tokens: the same for both orders. A domain of its own, so it never equals a pairKey. */
export async function accountPairKey(a: string, b: string): Promise<string> {
  return digest(ACCOUNT_PAIR_DOMAIN + [a, b].sort().join("\n"));
}

/** Whether two holders are the same pair: the same player ids, or both keyed by the same two accounts. */
export function samePair(a: PairKeys, b: PairKeys): boolean {
  return a.pair_key === b.pair_key || (a.account_key !== undefined && a.account_key === b.account_key);
}

/** Each listed player's account token (absent when unlinked). One PlatformLinks read, nothing written; at most four ids. */
export async function accountTokens(env: Env, players: readonly string[]): Promise<Map<string, string>> {
  const found = await env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT).accountsAmong([...players]);
  return new Map(found.map(row => [row.player_id, row.account]));
}

/** The pair's account key from tokens already read, or undefined when either player has none. */
export async function pairAccountKey(tokens: ReadonlyMap<string, string>, members: readonly [string, string]): Promise<string | undefined> {
  const [a, b] = [tokens.get(members[0]), tokens.get(members[1])];
  return a !== undefined && b !== undefined ? accountPairKey(a, b) : undefined;
}
