/**
 * Leaderboard rewards, as hooks for the cosmetics phase. A board decides who
 * earns what and tells a RewardSink; the sink is the only place a reward is
 * written. The wallet and items tables come from the Pollen phases; until then
 * the board keeps its own ledger (BoardRewardLedger), which that phase reads
 * with `rewardsFor` or replaces with a sink that writes the player's items.
 *
 * - top10_ribbon: a verified entry placed in a board's top 10. One per board.
 * - gold_leaf: a verified entry held first place, strictly faster than every
 *   other ranked run then. One item per player however many sources it has.
 *
 * Both are kept forever. Only a struck entry (found fake) loses its own
 * grants; players it pushed down keep theirs. Every grant is keyed by
 * (reward, board, entry, player), so granting again is a no-op.
 */
export type LeaderboardReward = "top10_ribbon" | "gold_leaf";
export type RewardGrant = { player_id: string; reward: LeaderboardReward; board: string; entry_id: string; granted_at: number };

export interface RewardSink {
  grant(player: string, reward: LeaderboardReward, board: string, entryId: string): void;
  /** Takes back every grant whose source is this entry (a struck run). */
  revokeEntry(entryId: string): void;
  /** Drops a player's grants (account erasure). */
  forgetPlayer(player: string): void;
  /** A player's live grants from this board. */
  rewardsFor(player: string): RewardGrant[];
}

export const REWARD_LEDGER_SCHEMA = "CREATE TABLE IF NOT EXISTS lb_grants (grant_key TEXT PRIMARY KEY, player_id TEXT NOT NULL, reward TEXT NOT NULL, board TEXT NOT NULL, entry_id TEXT NOT NULL, granted_at INTEGER NOT NULL)";

/** The board's own ledger of grants, in its SQLite storage. */
export class BoardRewardLedger implements RewardSink {
  constructor(private readonly storage: DurableObjectStorage) {}
  grant(player: string, reward: LeaderboardReward, board: string, entryId: string): void {
    this.storage.sql.exec("INSERT OR IGNORE INTO lb_grants VALUES (?,?,?,?,?,?)", `${reward}:${board}:${entryId}:${player}`, player, reward, board, entryId, Date.now());
  }
  revokeEntry(entryId: string): void { this.storage.sql.exec("DELETE FROM lb_grants WHERE entry_id=?", entryId); }
  forgetPlayer(player: string): void { this.storage.sql.exec("DELETE FROM lb_grants WHERE player_id=?", player); }
  rewardsFor(player: string): RewardGrant[] {
    return this.storage.sql.exec<RewardGrant>("SELECT player_id,reward,board,entry_id,granted_at FROM lb_grants WHERE player_id=? ORDER BY granted_at", player).toArray();
  }
}
