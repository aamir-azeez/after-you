import { pooled } from "../room-inbox";
import type { RewardDelivery } from "./rewards";

/**
 * Hands one board's marked players their earned items (rewards.ts deliveries) in their own Players
 * (Player.noteBoardRewards), then tells the board how each went. One that answered anything but a
 * server failure (taken, already newer, no identity any more) is done; one that could not be reached
 * keeps its mark behind the others, so the next pending call tries again without holding up the rest.
 * Never throws: a delivery is a side task of the pending call, and its marks stay for the next one.
 * Requests: 1 per player, plus 1 to the board.
 */
const DELIVERY_CONCURRENCY = 4;

type Mark = { player_id: string; seq: number };
type BoardStub = { rewardsDelivered(done: Mark[], failed: Mark[]): unknown };

export async function deliverRewards(env: Env, board: string, stub: BoardStub, deliveries: readonly RewardDelivery[]): Promise<number> {
  const answered = await pooled(deliveries, DELIVERY_CONCURRENCY, async delivery => {
    const mark = { player_id: delivery.player_id, seq: delivery.seq };
    try {
      const outcome = await env.PLAYERS.getByName(delivery.player_id).noteBoardRewards(delivery.player_id, board, delivery.items, delivery.seq);
      return { mark, done: outcome.ok || outcome.status < 500 };
    } catch { return { mark, done: false }; }
  });
  const done = answered.filter(item => item.done).map(item => item.mark), failed = answered.filter(item => !item.done).map(item => item.mark);
  try { await stub.rewardsDelivered(done, failed); } catch { return 0; }
  return done.length;
}
