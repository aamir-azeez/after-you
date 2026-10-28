import { POLLEN_EARNED_TABLES } from "../storage-schema";
import { CATALOG, EARNED_TIER, type Catalog } from "./catalog";

/**
 * Earned items, in the player's own Player Durable Object: the looks a player gets by playing and
 * never by paying (catalogue tier "earned"). They are owned like bought ones (wardrobe.ts owned), so
 * they are worn through the same equip. Each source keeps its own row, so an item two sources gave
 * stays until the last of them takes it back:
 * - board:<board key>: what that leaderboard's grants give the player now (leaderboards/rewards.ts),
 *   delivered whole by the replay job (leaderboards/operator.ts); a delivery with an older `seq`
 *   than the stored one changes nothing, so a late or repeated one never undoes a newer one.
 * - every_hard: a together Hard first clear of every chapter in EVERY_HARD_LEVELS, read from the
 *   hardclear claims the wallet keeps (wallet.ts) when one lands; kept once earned.
 *
 * Storage (storage-schema.ts POLLEN_EARNED_TABLES), made by the first earned item: one row per
 * source, at most one per board plus Every Hard. Every write runs inside the caller's transaction.
 */
const [EARNED] = POLLEN_EARNED_TABLES;
export const EVERY_HARD = "every_hard";
/**
 * The chapters Every Hard asks for, by level id (any version): every chapter the game offers Hard
 * on (game services/hard_mode.gd eligible). test/pollen-earned.test.ts pins it to the game's chapter
 * manifest, so a chapter the game adds Hard to fails the test until it is listed here.
 */
export const EVERY_HARD_LEVELS: readonly string[] = Object.freeze([
  "first-steps", "relay-isles", "high-and-low", "rolling-home", "a-house-for-two",
  "conservatory", "long-way-home", "the-wishing-well", "turn-of-the-tide", "sleeping-lighthouse"
]);
export const boardSource = (board: string) => `board:${board}`;

/** Whether the table exists, read once per Player instance; a create or drop forgets the answer. */
const known = new WeakMap<DurableObjectStorage, boolean>();
function present(storage: DurableObjectStorage): boolean {
  let found = known.get(storage);
  if (found === undefined) {
    found = storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", EARNED.name).toArray().length > 0;
    known.set(storage, found);
  }
  return found;
}
function ensureTable(storage: DurableObjectStorage): void {
  if (present(storage)) return;
  storage.sql.exec(EARNED.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  known.delete(storage);
}

/** Whether every id is a released earned-only item of the catalogue, each once. */
export function validEarnedItems(items: unknown, catalog: Catalog = CATALOG): items is string[] {
  return Array.isArray(items) && items.length <= Object.keys(catalog.items).length && new Set(items).size === items.length &&
    items.every(id => typeof id === "string" && Object.hasOwn(catalog.items, id) && catalog.items[id].tier === EARNED_TIER && catalog.items[id].released);
}

/** Every item some source gives the player now. A row that cannot be read gives nothing. */
export function earnedItems(storage: DurableObjectStorage): Set<string> {
  const result = new Set<string>();
  if (!present(storage)) return result;
  for (const row of storage.sql.exec<{ items: string }>("SELECT items FROM pollen_earned LIMIT ?", EARNED.maxRows).toArray()) {
    try {
      const items: unknown = JSON.parse(row.items);
      if (Array.isArray(items)) for (const id of items) if (typeof id === "string") result.add(id);
    } catch { /* an unreadable row gives nothing */ }
  }
  return result;
}

/**
 * Sets what `source` gives the player, unless the stored row is as new or newer (`seq`). A source
 * that gives nothing and was never stored writes nothing. Returns whether the row changed.
 */
export function setEarned(storage: DurableObjectStorage, source: string, items: readonly string[], seq: number, now: number): boolean {
  const row = present(storage) ? storage.sql.exec<{ items: string; seq: number }>("SELECT items,seq FROM pollen_earned WHERE source=?", source).toArray()[0] : undefined;
  if (row ? row.seq >= seq : items.length === 0) return false;
  const text = JSON.stringify([...items].sort());
  if (row?.items === text) { storage.sql.exec("UPDATE pollen_earned SET seq=? WHERE source=?", seq, source); return false; }
  ensureTable(storage);
  storage.sql.exec("INSERT OR REPLACE INTO pollen_earned VALUES (?,?,?,?)", source, text, seq, now);
  return true;
}

/** Every Hard, once each chapter in EVERY_HARD_LEVELS has a together Hard first clear (`hardCleared`). Kept once earned. */
export function noteEveryHard(storage: DurableObjectStorage, hardCleared: (levelId: string) => boolean, now: number): boolean {
  if (present(storage) && storage.sql.exec("SELECT 1 FROM pollen_earned WHERE source=?", EVERY_HARD).toArray().length > 0) return false;
  if (!EVERY_HARD_LEVELS.every(hardCleared)) return false;
  return setEarned(storage, EVERY_HARD, [EVERY_HARD], 1, now);
}

/** Account erasure: every earned item goes. */
export function dropEarned(storage: DurableObjectStorage): void {
  storage.sql.exec(`DROP TABLE IF EXISTS ${EARNED.name}`);
  known.delete(storage);
}
