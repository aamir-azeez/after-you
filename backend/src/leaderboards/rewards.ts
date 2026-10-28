/**
 * Leaderboard rewards. A board decides who earns what and tells a RewardSink;
 * the sink is the only place a reward is written. The board keeps its own
 * ledger (BoardRewardLedger), and each player's items follow it: every change
 * to a player's grants marks them for delivery (lb_reward_sync), and the replay
 * job (operator.ts, reward-delivery.ts) hands each marked player the whole set
 * this board gives them now, as earned items (pollen/earned.ts), while
 * POLLEN_WARDROBE is on.
 *
 * - top10_ribbon: a verified entry placed in a board's top 10. One per board.
 * - gold_leaf: a verified entry held first place, strictly faster than every
 *   other ranked run then. One item per player however many sources it has.
 *
 * Both are kept forever. Only a struck entry (found fake) loses its own
 * grants; players it pushed down keep theirs, and a player whose last grant of
 * an item went loses that item at the next delivery. Every grant is keyed by
 * (reward, board, entry, player), so granting again is a no-op.
 *
 * Deliveries are safe to repeat and to arrive out of order: each mark carries a
 * `seq` that only grows on this board (the sentinel row '' keeps the highest
 * given), the Player keeps the newest seq it took per board, and a mark is
 * cleared only when the delivery that answered carried its current seq.
 */
export type LeaderboardReward = "top10_ribbon" | "gold_leaf";
export type RewardGrant = { player_id: string; reward: LeaderboardReward; board: string; entry_id: string; granted_at: number };
/** One marked player and every item this board gives them now. */
export type RewardDelivery = { player_id: string; seq: number; items: string[] };

/** The catalogue item each reward gives (backend/src/pollen/catalog.json, tier "earned"). */
export const REWARD_ITEMS: Readonly<Record<LeaderboardReward, string>> = Object.freeze({ top10_ribbon: "top_ten_ribbon", gold_leaf: "gold_leaf" });

export interface RewardSink {
  grant(player: string, reward: LeaderboardReward, board: string, entryId: string): void;
  /** Takes back every grant whose source is this entry (a struck run); returns how many went. */
  revokeEntry(entryId: string): number;
  /** Drops a player's grants (account erasure). */
  forgetPlayer(player: string): void;
  /** A player's live grants from this board. */
  rewardsFor(player: string): RewardGrant[];
}

export const REWARD_LEDGER_SCHEMA = "CREATE TABLE IF NOT EXISTS lb_grants (grant_key TEXT PRIMARY KEY, player_id TEXT NOT NULL, reward TEXT NOT NULL, board TEXT NOT NULL, entry_id TEXT NOT NULL, granted_at INTEGER NOT NULL)";
const SYNC_TABLE = "lb_reward_sync";
const SYNC_SCHEMA = `CREATE TABLE ${SYNC_TABLE} (player_id TEXT PRIMARY KEY, seq INTEGER NOT NULL) WITHOUT ROWID`;
/** The row that keeps the highest seq given, so a seq is never given twice even once every mark is cleared. */
const HIGH = "";

/**
 * Creates the delivery marks beside an existing ledger. A board that had grants
 * before marks were kept (or before the wardrobe existed) marks every player
 * it granted, so what was earned earlier is delivered too.
 */
export function openRewardSync(storage: DurableObjectStorage): void {
  if (storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", SYNC_TABLE).toArray().length > 0) return;
  storage.sql.exec(SYNC_SCHEMA);
  const seq = Date.now();
  storage.sql.exec(`INSERT INTO ${SYNC_TABLE} SELECT DISTINCT player_id, ? FROM lb_grants`, seq);
  storage.sql.exec(`INSERT OR REPLACE INTO ${SYNC_TABLE} VALUES (?,?)`, HIGH, seq);
}

/** The board's own ledger of grants and delivery marks, in its SQLite storage. Every call runs in the caller's transaction. */
export class BoardRewardLedger implements RewardSink {
  constructor(private readonly storage: DurableObjectStorage) {}
  grant(player: string, reward: LeaderboardReward, board: string, entryId: string): void {
    // Only a reward new to the player here changes their items; another run's grant of it does not.
    const had = this.storage.sql.exec("SELECT 1 FROM lb_grants WHERE player_id=? AND reward=? LIMIT 1", player, reward).toArray().length > 0;
    const written = this.storage.sql.exec("INSERT OR IGNORE INTO lb_grants VALUES (?,?,?,?,?,?)", `${reward}:${board}:${entryId}:${player}`, player, reward, board, entryId, Date.now()).rowsWritten;
    if (written > 0 && !had) this.mark(player);
  }
  revokeEntry(entryId: string): number {
    const players = this.storage.sql.exec<{ player_id: string }>("SELECT DISTINCT player_id FROM lb_grants WHERE entry_id=?", entryId).toArray().map(row => row.player_id);
    const before = new Map(players.map(player => [player, this.itemsFor(player).join(",")]));
    const gone = this.storage.sql.exec("DELETE FROM lb_grants WHERE entry_id=?", entryId).rowsWritten;
    for (const player of players) if (this.itemsFor(player).join(",") !== before.get(player)) this.mark(player);
    return gone;
  }
  forgetPlayer(player: string): void {
    this.storage.sql.exec("DELETE FROM lb_grants WHERE player_id=?", player);
    // An erased player's own Player drops their items; nothing is left to deliver.
    this.storage.sql.exec(`DELETE FROM ${SYNC_TABLE} WHERE player_id=?`, player);
  }
  rewardsFor(player: string): RewardGrant[] {
    return this.storage.sql.exec<RewardGrant>("SELECT player_id,reward,board,entry_id,granted_at FROM lb_grants WHERE player_id=? ORDER BY granted_at", player).toArray();
  }

  /** Up to `limit` marked players, oldest mark first, each with every item this board gives them now. */
  deliveries(limit: number): RewardDelivery[] {
    if (limit <= 0) return [];
    return this.storage.sql.exec<{ player_id: string; seq: number }>(`SELECT player_id,seq FROM ${SYNC_TABLE} WHERE player_id!=? ORDER BY seq, player_id LIMIT ?`, HIGH, limit).toArray()
      .map(row => ({ player_id: row.player_id, seq: row.seq, items: this.itemsFor(row.player_id) }));
  }
  /**
   * Clears each mark the delivery answered for, and moves each one that failed behind every other mark
   * (a fresh seq), so a Player that keeps failing never holds up the rest. Either only while the mark
   * still carries the seq that was delivered: a newer change keeps its own.
   */
  delivered(done: readonly { player_id: string; seq: number }[], failed: readonly { player_id: string; seq: number }[] = []): void {
    for (const item of done) if (item.player_id !== HIGH) this.storage.sql.exec(`DELETE FROM ${SYNC_TABLE} WHERE player_id=? AND seq=?`, item.player_id, item.seq);
    for (const item of failed) {
      const still = item.player_id !== HIGH && this.storage.sql.exec(`SELECT 1 FROM ${SYNC_TABLE} WHERE player_id=? AND seq=?`, item.player_id, item.seq).toArray().length > 0;
      if (still) this.mark(item.player_id);
    }
  }

  private itemsFor(player: string): string[] {
    const rewards = this.storage.sql.exec<{ reward: string }>("SELECT DISTINCT reward FROM lb_grants WHERE player_id=?", player).toArray();
    return [...new Set(rewards.map(row => REWARD_ITEMS[row.reward as LeaderboardReward]).filter(Boolean))].sort();
  }
  /** Marks the player for delivery under a seq above any this board gave. */
  private mark(player: string): void {
    const high = this.storage.sql.exec<{ seq: number }>(`SELECT seq FROM ${SYNC_TABLE} WHERE player_id=?`, HIGH).toArray()[0]?.seq ?? 0;
    const seq = Math.max(Date.now(), high + 1);
    this.storage.sql.exec(`INSERT OR REPLACE INTO ${SYNC_TABLE} VALUES (?,?)`, player, seq);
    this.storage.sql.exec(`INSERT OR REPLACE INTO ${SYNC_TABLE} VALUES (?,?)`, HIGH, seq);
  }
}
