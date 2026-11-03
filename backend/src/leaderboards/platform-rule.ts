import { flags, type ServerVars } from "../flags";
import { PLATFORM_LINKS_OBJECT } from "../platform-links";

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

/** The members with no platform link, in the order given ([] when every one is linked). One Durable Object request. */
export async function unlinkedMembers(env: Env, members: readonly string[]): Promise<string[]> {
  const linked = new Set(await env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT).linkedAmong([...members]));
  return members.filter(id => !linked.has(id));
}
