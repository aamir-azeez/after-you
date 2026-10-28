import { pooled } from "../room-inbox";
import type { PartyOp } from "./party";

/**
 * Account erasure's duel part, run before the player's LeaderboardMember
 * forgets everything (leaderboards/members.ts): the partner who names them,
 * and every friend holding an invite from them or one they sent, stop naming
 * them. Their duels are taken care of by each board's forget (duels/store.ts).
 * Requests: 1 (the player's Member) + 1 per other player named, at most 10.
 */
export async function forgetDuelParty(env: Env, playerId: string): Promise<void> {
  const state = await env.LEADERBOARD_MEMBERS.getByName(playerId).partyRead(Date.now());
  const now = Date.now(), tasks: { id: string; op: PartyOp }[] = [];
  if (state.partner) tasks.push({ id: state.partner, op: { kind: "unpartner", partner: playerId } });
  for (const invite of state.invites_in) tasks.push({ id: invite.from, op: { kind: "cancel" } });
  if (state.invite_out) tasks.push({ id: state.invite_out.to, op: { kind: "dismiss", from: playerId } });
  await pooled(tasks, 4, async task => {
    // A friend's own invite to someone else is theirs to keep: only one aimed at this player is cancelled.
    if (task.op.kind === "cancel") {
      const theirs = await env.LEADERBOARD_MEMBERS.getByName(task.id).partyRead(now);
      if (theirs.invite_out?.to !== playerId) return;
    }
    await env.LEADERBOARD_MEMBERS.getByName(task.id).partyApply(task.id, task.op, now);
  });
}
