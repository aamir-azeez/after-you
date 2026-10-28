import { pooled } from "../room-inbox";
import type { RewardDelivery } from "./rewards";

/**
 * Hands one board's marked players their earned items (rewards.ts deliveries) in their own Players
 * (Player.noteBoardRewards), then clears the marks that were answered. A Player that could not be
 * reached keeps its mark, so the next pending call tries again; one that answered anything but a
 * server failure (taken, already newer, no identity any more) is done.
 * Requests: 1 per player, plus 1 to the board when any answered.
 */
const DELIVERY_CONCURRENCY = 4;

type BoardStub = { rewardsDelivered(done: { player_id: string; seq: number }[]): unknown };

export async function deliverRewards(env: Env, board: string, stub: BoardStub, deliveries: readonly RewardDelivery[]): Promise<number> {
  const answered = await pooled(deliveries, DELIVERY_CONCURRENCY, async delivery => {
    try {
      const outcome = await env.PLAYERS.getByName(delivery.player_id).noteBoardRewards(delivery.player_id, board, delivery.items, delivery.seq);
      return outcome.ok || outcome.status < 500 ? { player_id: delivery.player_id, seq: delivery.seq } : null;
    } catch { return null; }
  });
  const done = answered.filter((item): item is { player_id: string; seq: number } => item !== null);
  if (done.length) await stub.rewardsDelivered(done);
  return done.length;
}
