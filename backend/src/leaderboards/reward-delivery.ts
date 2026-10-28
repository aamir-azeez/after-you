import { pooled } from "../room-inbox";
import type { RewardDelivery } from "./rewards";

/**
 * Hands marked players their earned items (rewards.ts deliveries) in their own Players
 * (Player.noteBoardRewards), in one pass after the operator call's own board work, then tells each
 * board how its players went. One that answered anything but a server failure (taken, already newer,
 * no identity any more) is done. One that failed or took longer than DELIVERY_TIMEOUT_MS keeps its
 * mark behind the others, so the next call tries again without holding up the rest; a late answer is
 * still safe, since the Player keeps only the newest seq.
 * Never throws: a delivery is a side task of the call, and its marks stay for the next one.
 * Requests: 1 per player, plus 1 per board that had any.
 */
const DELIVERY_CONCURRENCY = 4;
/** The longest one Player delivery may hold up the operator call it rides on. */
export const DELIVERY_TIMEOUT_MS = 5_000;
/** Players handed their board rewards per operator call, across every board; each is one Player request. */
export const MAX_REWARD_DELIVERIES = 16;

type Mark = { player_id: string; seq: number };
type BoardStub = { rewardsDelivered(done: Mark[], failed: Mark[]): unknown };
/** One board's marked players, as its answer carried them. */
export type RewardBatch = { board: string; stub: BoardStub; rewards: readonly RewardDelivery[] };

export async function deliverRewards(env: Env, batches: readonly RewardBatch[], timeoutMs = DELIVERY_TIMEOUT_MS): Promise<number> {
  const work = batches.flatMap(batch => batch.rewards.map(delivery => ({ batch, delivery })));
  if (!work.length) return 0;
  const answered = await pooled(work, DELIVERY_CONCURRENCY, async ({ batch, delivery }) => {
    const mark = { player_id: delivery.player_id, seq: delivery.seq };
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const call = env.PLAYERS.getByName(delivery.player_id).noteBoardRewards(delivery.player_id, batch.board, delivery.items, delivery.seq).then(outcome => outcome.ok || outcome.status < 500, () => false);
      const late = new Promise<boolean>(resolve => { timer = setTimeout(() => resolve(false), timeoutMs); });
      return { batch, mark, done: await Promise.race([call, late]) };
    } catch { return { batch, mark, done: false }; } finally { if (timer !== undefined) clearTimeout(timer); }
  });
  let done = 0;
  for (const batch of batches) {
    const mine = answered.filter(item => item.batch === batch);
    if (!mine.length) continue;
    const ok = mine.filter(item => item.done).map(item => item.mark), failed = mine.filter(item => !item.done).map(item => item.mark);
    try { await batch.stub.rewardsDelivered(ok, failed); done += ok.length; } catch { /* the marks stay */ }
  }
  return done;
}
