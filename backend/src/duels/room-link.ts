import { ID_PATTERN } from "../protocol";
import { DUEL_ROOM_TABLES, isLazyTable } from "../storage-schema";

/**
 * The duel a room plays for, kept in the room itself (storage-schema.ts
 * DUEL_ROOM_TABLES) so that every accepted turn knows it without asking
 * anyone: the turn's Pollen facts freeze whether it is a friend duel turn
 * (pollen/turn-facts.ts), and the Worker notes the turn on the duel
 * (duels/turn-hook.ts). Written once, in the transaction that creates the
 * room; a duel room is otherwise an ordinary room. Only the pair's two
 * members may ever be in it: a join by anyone else is refused.
 */
/** `done`: the room has finished its run once; turns after that (a redo) are ordinary turns and pay no duel premium. */
export type DuelLink = { schema_version: 1; duel_id: string; board: string; kind: "friend" | "ghost"; side: 0 | 1; members: string[]; done?: true };
const [TABLE] = DUEL_ROOM_TABLES;
const DUEL_ID = /^[a-f0-9]{32}$/;
const BOARD = /^[a-z0-9-]{1,48}@[1-9][0-9]{0,3}$/;

export function validDuelLink(value: unknown): value is DuelLink {
  const link = value as DuelLink;
  const keys = typeof value === "object" && value !== null ? Object.keys(value).length : 0;
  return keys === 6 + Number(link?.done === true) && link.schema_version === 1 && typeof link.duel_id === "string" && DUEL_ID.test(link.duel_id) &&
    typeof link.board === "string" && BOARD.test(link.board) && (link.kind === "friend" || link.kind === "ghost") && (link.side === 0 || link.side === 1) &&
    Array.isArray(link.members) && link.members.length === 2 && link.members.every(id => typeof id === "string" && ID_PATTERN.test(id)) && link.members[0] !== link.members[1];
}

/** The answer per room instance; a write or clear forgets it. */
const memo = new WeakMap<DurableObjectStorage, DuelLink | null>();

/** The room's duel, or null for an ordinary room. Never throws. */
export function duelLink(storage: DurableObjectStorage): DuelLink | null {
  if (memo.has(storage)) return memo.get(storage)!;
  let link: DuelLink | null = null;
  try {
    if (storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", TABLE.name).toArray().length) {
      const row = storage.sql.exec<{ data: string }>("SELECT data FROM duel_link WHERE id=1").toArray()[0];
      const value: unknown = row ? JSON.parse(row.data) : null;
      link = validDuelLink(value) ? value : null;
    }
  } catch { link = null; }
  memo.set(storage, link);
  return link;
}

/** Inside the creating transaction. */
export function recordDuelLink(storage: DurableObjectStorage, link: DuelLink): void {
  storage.sql.exec(TABLE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT OR REPLACE INTO duel_link VALUES (1,?)", JSON.stringify(link));
  memo.delete(storage);
}

/** Inside the commit that finished the room's run: later turns are no longer duel turns. */
export function markDuelDone(storage: DurableObjectStorage): void {
  const link = duelLink(storage);
  if (!link || link.done) return;
  storage.sql.exec("UPDATE duel_link SET data=? WHERE id=1", JSON.stringify({ ...link, done: true }));
  memo.delete(storage);
}

/** Whether a turn in this room pays the friend duel premium: a friend duel's room until its run first finished. */
export function duelPremium(link: DuelLink | null): boolean {
  return link?.kind === "friend" && !link.done;
}

/** Whether a retried create names the same duel as the room holds (both null for an ordinary room). */
export function sameDuelLink(held: DuelLink | null, asked: DuelLink | undefined): boolean {
  if (!held || !asked) return !held && !asked;
  return held.duel_id === asked.duel_id && held.board === asked.board && held.kind === asked.kind && held.side === asked.side &&
    held.members[0] === asked.members[0] && held.members[1] === asked.members[1];
}

/** Whether `player` may join: anyone in an ordinary room, only the pair in a duel's. */
export function duelJoinAllowed(link: DuelLink | null, player: string): boolean {
  return link === null || link.members.includes(player);
}

/** For the full room erase and a snapshot restore. */
export function clearDuelLink(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS duel_link");
  memo.delete(storage);
}

/** The table as sqlite_master lists it, so snapshot schema checks let it pass. */
export function isDuelRoomTable(row: { name: string; sql: string }): boolean { return isLazyTable(DUEL_ROOM_TABLES, row); }
