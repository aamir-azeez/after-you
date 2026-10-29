import { chapter } from "./protocol";
import { archived, expireAttempt, finishedOf, roomKey, type HistoryRoom } from "./history-room";
import { historyChain, persistChain, storedAttempts } from "./history";
import { initializeHistory } from "./storage-schema";

/**
 * The replay time limit on finished rooms (REPLAY_EXPIRY, off by default; the owner turns it on).
 *
 * A finished standalone room keeps every attempt's replay bytes until both
 * phones have saved them (attempt history, history-room.ts, or the older replay
 * transfer, replay-transfer.ts). With the switch on, the room also arms a clock
 * REPLAY_KEEP_MS long when its run finishes (and, for rooms finished before,
 * the first time a member reads it). When the clock runs out, the room keeps
 * only what attempt history keeps after both phones saved an attempt: every
 * finished attempt's digest and chain link, its rows as hashes, and the room's
 * own listing, times and final checkpoint hash, exactly as if both had saved
 * it. A phone that saved an attempt can still send it back; one that never
 * did cannot watch it any more. Nothing is deleted when a room is read.
 *
 * The clock is one row here and shares the room's single Durable Object alarm
 * with turn hints (notification-storage.ts): the alarm is due at the earlier
 * of the two, and its marker and ownership check count both. A room that is no
 * longer finished when the clock runs out (a redo started) is left as it is and
 * re-armed when it finishes again; a room whose replays already left (replay
 * transfer) or that was erased just drops the clock. With the switch off when
 * the clock runs out, nothing is deleted and the clock goes.
 *
 * Cost per finished room: one row written when armed, one alarm invocation
 * (one Durable Object request) when it runs out, which reads the room's
 * attempt rows once and rewrites each still held turn and pair row as its
 * hash (test/replay-expiry.test.ts measures it).
 */
export const REPLAY_KEEP_MS = 90 * 86_400_000;
export const REPLAY_EXPIRY_TABLE = { name: "replay_expiry", schema: "CREATE TABLE replay_expiry (id INTEGER PRIMARY KEY CHECK(id=1), due_at INTEGER NOT NULL)" } as const;

function present(storage: DurableObjectStorage): boolean {
  return storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", REPLAY_EXPIRY_TABLE.name).toArray().length > 0;
}
/** When the clock runs out, or null when the room has none. */
export function replayExpiryDue(storage: DurableObjectStorage): number | null {
  if (!present(storage)) return null;
  const row = storage.sql.exec<{ due_at: number }>("SELECT due_at FROM replay_expiry WHERE id=1").toArray()[0];
  return row && Number.isSafeInteger(row.due_at) ? row.due_at : null;
}
/** Arms the clock at `due` unless one is armed; true when this armed it. The caller schedules the alarm. */
export function armReplayExpiry(storage: DurableObjectStorage, due: number, replace = false): boolean {
  if (!replace && replayExpiryDue(storage) !== null) return false;
  storage.sql.exec(REPLAY_EXPIRY_TABLE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT OR REPLACE INTO replay_expiry VALUES (1,?)", due);
  return true;
}
/** Drops the clock (a restore, an erase, or the clock done). The caller schedules the alarm. */
export function clearReplayExpiry(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS replay_expiry");
}
/** The table as sqlite_master lists it, so snapshot schema checks let it pass; it is never exported. */
export function isReplayExpiryTable(row: { name: string; sql: string }): boolean {
  return row.name === REPLAY_EXPIRY_TABLE.name && row.sql === REPLAY_EXPIRY_TABLE.schema;
}
/** Whether a standalone room's run is finished, so the clock applies. */
export function finishedRoom(room: HistoryRoom | null): boolean {
  if (!room || archived(room)) return false;
  try { return room.stage_index === chapter(room).stages.length && room.guest_id !== null; } catch { return false; }
}

/**
 * The alarm's part for the clock, before turn hints run (their final schedule sets the next alarm).
 * `room` reads the stored room (live, archived or erased). `on` is the switch.
 * Returns what it did, for tests and logs.
 */
export async function runReplayExpiry(storage: DurableObjectStorage, room: () => HistoryRoom | null, on: boolean, now: number): Promise<"none" | "waiting" | "dropped" | "expired" | "retry"> {
  const due = replayExpiryDue(storage);
  if (due === null) return "none";
  if (due > now) return "waiting";
  const stored = room();
  // Switched off, erased, already left by replay transfer v1, or not finished any more: nothing to delete.
  if (!on || !stored || (archived(stored) && stored.replay_transfer_version === 1) || (!archived(stored) && !finishedRoom(stored))) {
    clearReplayExpiry(storage);
    return "dropped";
  }
  let chain;
  try { chain = await historyChain(storage, roomKey(stored), finishedOf(stored)); }
  catch {
    // A row the chain needs is not held (a half offloaded room): only attempt history can move it; drop the clock.
    clearReplayExpiry(storage);
    return "dropped";
  }
  return storage.transactionSync(() => {
    const current = room();
    // Anything moved while the chain was hashed: try again in an hour.
    if (!current || current.revision !== stored.revision || current.branch !== stored.branch || archived(current) !== archived(stored)) { armReplayExpiry(storage, now + 3_600_000, true); return "retry"; }
    if (!initializeHistory(storage)) { clearReplayExpiry(storage); return "dropped"; }
    if (!persistChain(storage, chain.fresh.map(item => item.record))) { armReplayExpiry(storage, now + 3_600_000, true); return "retry"; }
    const finished = finishedOf(current);
    for (const record of storedAttempts(storage)) if (record.state === "held" && record.position < finished) expireAttempt(storage, current, record);
    clearReplayExpiry(storage);
    return "expired";
  });
}
