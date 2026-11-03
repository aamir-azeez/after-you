import { ID_PATTERN } from "../protocol";
import { DUEL_ROOM_TABLES, isLazyTable } from "../storage-schema";
import type { DuelMasks } from "./public-mask";

/**
 * The duel a room plays for, kept in the room itself (storage-schema.ts
 * DUEL_ROOM_TABLES) so that every accepted turn knows it without asking
 * anyone: the turn's Pollen facts freeze whether it is a friend duel turn
 * (pollen/turn-facts.ts), and the Worker notes the turn on the duel
 * (duels/turn-hook.ts). Written once, in the transaction that creates the
 * room; a duel room is otherwise an ordinary room. Only the pair's two
 * members may ever be in it: a join by anyone else is refused.
 */
/**
 * `done`: the room has finished its run once; turns after that (a redo) are ordinary turns and pay no duel premium.
 * `others`: in a friend duel, the other pair's players still in it when the room was made, who may watch this room's run (duels/their-run.ts).
 * `public`: a public duel's room (duels/public.ts). Its side may hold one player when the room is made; the other joins
 * once the board says they hold the seat (admitToDuelLink). Its turns hold the duel extra until the duel ends
 * (pollen/turn-facts.ts duel_held).
 * `masks`: only in a public duel's room whose members may be strangers (all but a party that joined together): the
 * stand-ins a phone sees for the other member (the host's, then the guest's), random id-shaped values made with the
 * link, never a player's id (duels/public-mask.ts).
 */
export type DuelLink = { schema_version: 1; duel_id: string; board: string; kind: "friend" | "ghost"; side: 0 | 1; members: string[]; done?: true; others?: string[]; public?: true; masks?: string[] };
const [TABLE] = DUEL_ROOM_TABLES;
const DUEL_ID = /^[a-f0-9]{32}$/;
const BOARD = /^[a-z0-9-]{1,48}@[1-9][0-9]{0,3}$/;

export function validDuelLink(value: unknown): value is DuelLink {
  const link = value as DuelLink;
  const keys = typeof value === "object" && value !== null ? Object.keys(value).length : 0;
  const others = link?.others;
  if (others !== undefined && (!Array.isArray(others) || others.length > 2 || link.kind !== "friend" || !others.every(id => typeof id === "string" && ID_PATTERN.test(id) && !link.members?.includes(id)) || new Set(others).size !== others.length)) return false;
  const open = link?.public === true, masks = link?.masks;
  if (open && link.kind !== "friend" || masks !== undefined && !(open && Array.isArray(masks) && masks.length === 2 && masks.every(id => typeof id === "string" && ID_PATTERN.test(id) && !link.members?.includes(id)) && masks[0] !== masks[1])) return false;
  return keys === 6 + Number(link?.done === true) + Number(others !== undefined) + Number(open) + Number(masks !== undefined) && link.schema_version === 1 && typeof link.duel_id === "string" && DUEL_ID.test(link.duel_id) &&
    typeof link.board === "string" && BOARD.test(link.board) && (link.kind === "friend" || link.kind === "ghost") && (link.side === 0 || link.side === 1) &&
    Array.isArray(link.members) && (link.members.length === 2 || open && link.members.length === 1) && link.members.every(id => typeof id === "string" && ID_PATTERN.test(id)) && link.members[0] !== link.members[1];
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

/** Whether this room's duel premium is held until the duel ends (a public duel's room, pollen/duel-pay.ts creditDuelExtra). */
export function duelHeld(link: DuelLink | null): boolean {
  return duelPremium(link) && link?.public === true;
}

/**
 * Inside the join transaction: a public duel side's second player, whose seat its board just marked entered
 * (RoomV2.join). `known`: the first player knows them (a party that joined together), so the room drops its masks.
 */
export function admitToDuelLink(storage: DurableObjectStorage, player: string, known: boolean): void {
  const link = duelLink(storage);
  if (!link?.public || link.members.includes(player) || link.members.length >= 2) return;
  const { masks, ...rest } = link;
  storage.sql.exec("UPDATE duel_link SET data=? WHERE id=1", JSON.stringify({ ...rest, members: [...link.members, player], ...(known || !masks ? {} : { masks }) }));
  memo.delete(storage);
}

/** Whether a join must first ask the board: a public duel side's seat this player does not hold here yet. */
export function needsAdmission(link: DuelLink | null, player: string): boolean {
  return link?.public === true && link.members.length < 2 && !link.members.includes(player);
}

/** The masks a public duel room's replies carry for the Worker (duels/public-mask.ts), or none. */
export function duelMasks(link: DuelLink | null, state: { host_id: string; guest_id: string | null }): { duel_masks?: DuelMasks } {
  return link?.masks ? { duel_masks: { host: link.masks[0], guest: link.masks[1], host_id: state.host_id, guest_id: state.guest_id } } : {};
}

/** Whether a retried create names the same duel as the room holds (both null for an ordinary room). */
export function sameDuelLink(held: DuelLink | null, asked: DuelLink | undefined): boolean {
  if (!held || !asked) return !held && !asked;
  return held.duel_id === asked.duel_id && held.board === asked.board && held.kind === asked.kind && held.side === asked.side &&
    held.members[0] === asked.members[0] && held.members[1] === asked.members[1] && (held.others === undefined || held.others.join() === (asked.others ?? []).join());
}

/** Whether `player` may join: anyone in an ordinary room, only the pair in a duel's. */
export function duelJoinAllowed(link: DuelLink | null, player: string): boolean {
  return link === null || link.members.includes(player);
}

/** For the full room erase and a snapshot restore. */
export function clearDuelLink(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS duel_link");
  // The other pair's copy of the run (duels/their-run.ts) goes with it.
  storage.sql.exec("DROP TABLE IF EXISTS duel_their_run");
  memo.delete(storage);
}

/** The table as sqlite_master lists it, so snapshot schema checks let it pass. */
export function isDuelRoomTable(row: { name: string; sql: string }): boolean { return isLazyTable(DUEL_ROOM_TABLES, row); }
