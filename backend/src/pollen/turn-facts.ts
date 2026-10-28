import { HASH_PATTERN, ID_PATTERN, isObject } from "../protocol";
import { POLLEN_ROOM_TABLES, isLazyTable } from "../storage-schema";
import { boostPercent } from "./earn";
import { ISO_WEEK_PATTERN, isoWeek } from "./week";

/**
 * The facts of each accepted turn that Pollen pays from, frozen by the room in the transaction
 * that accepts the turn, so the inline credit, a retried commit and a later claim all price the
 * same turn from the same row (claim key `turn:<room_id>:<recording_hash>`).
 *
 * Room storage, created by the first turn committed while POLLEN_EARN is on (the Worker passes a
 * PollenMember into the commit only then):
 * - pollen_turn_facts: one row per accepted turn, keyed by recording hash; at most the turns bound.
 * - pollen_members: each member's Full Journey end (fj_until, ms) as their Player last reported it
 *   on create, join or a turn; a member without one has no row.
 * Operator snapshots leave both out (like turn_tries); the full room erase drops them; a member
 * erased from the room takes their rows with them.
 */
export type PollenMember = { fj_until: number };
export type TurnFacts = {
  schema_version: 1; room_id: string; recording_hash: string; turn_id: string; player_id: string;
  accepted_at: number; week: string; level_id: string; stage_id: string; role: "a" | "b";
  ticks: number; tries: number | null;
  /** A paid chapter; a hard room; the committing player hosts; the room had a guest; this turn finished the chapter. */
  premium: boolean; hard: boolean; host: boolean; together: boolean; complete: boolean;
  /** Whether the committing player, and the other member, had Full Journey at acceptance. */
  subscriber: boolean; partner_subscriber: boolean;
  /** The room boost frozen at acceptance: boost_percent_per_subscriber for each of the two. */
  boost_percent: number;
  /** Only on a friend duel's turn (duels/room-link.ts), which pays the duel premium; absent everywhere else, as on facts frozen before duels. */
  duel?: true;
};

const [FACTS, MEMBERS] = POLLEN_ROOM_TABLES;
export const MAX_FACTS = FACTS.maxRows;
const MAX_TIME = 8_640_000_000_000_000;

const bool = (value: unknown): value is boolean => typeof value === "boolean";
const count = (value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
const KEYS = ["schema_version", "room_id", "recording_hash", "turn_id", "player_id", "accepted_at", "week", "level_id", "stage_id", "role", "ticks", "tries",
  "premium", "hard", "host", "together", "complete", "subscriber", "partner_subscriber", "boost_percent"];

/** The exact shape, as the Player checks facts that reach it. */
export function validTurnFacts(value: unknown): value is TurnFacts {
  if (!isObject(value)) return false;
  const duel = Object.hasOwn(value, "duel");
  if (duel && value.duel !== true) return false;
  if (Object.keys(value).length !== KEYS.length + Number(duel) || !KEYS.every(key => Object.hasOwn(value, key))) return false;
  return value.schema_version === 1 && typeof value.room_id === "string" && ID_PATTERN.test(value.room_id) && typeof value.recording_hash === "string" && HASH_PATTERN.test(value.recording_hash) &&
    typeof value.turn_id === "string" && /^t[0-9]{1,2}-[0-9]{1,2}-[ab]$/.test(value.turn_id) && typeof value.player_id === "string" && ID_PATTERN.test(value.player_id) &&
    count(value.accepted_at, 1) && typeof value.week === "string" && ISO_WEEK_PATTERN.test(value.week) && value.week === isoWeek(value.accepted_at) &&
    typeof value.level_id === "string" && /^[a-z0-9-]{1,64}$/.test(value.level_id) && typeof value.stage_id === "string" && /^[a-z0-9-]{1,64}$/.test(value.stage_id) &&
    (value.role === "a" || value.role === "b") && count(value.ticks) && (value.tries === null || count(value.tries, 1, 999)) &&
    bool(value.premium) && bool(value.hard) && bool(value.host) && bool(value.together) && bool(value.complete) && bool(value.subscriber) && bool(value.partner_subscriber) &&
    // Frozen at acceptance: a later change of the per-subscriber rate never makes old facts invalid.
    count(value.boost_percent, 0, 100) && (value.boost_percent > 0) === (value.subscriber || value.partner_subscriber);
}

/** A member value from the Player: a Full Journey end in ms, 0 for none. */
export function validMember(value: unknown): value is PollenMember {
  return isObject(value) && Object.keys(value).length === 1 && count(value.fj_until, 0, MAX_TIME);
}

/** Which Pollen tables a room holds, read once per room instance; a write or drop forgets the answer. */
const known = new WeakMap<DurableObjectStorage, Set<string>>();
function present(storage: DurableObjectStorage, table: string): boolean {
  let names = known.get(storage);
  if (!names) {
    names = new Set(storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type='table' AND name IN (?,?)", FACTS.name, MEMBERS.name).toArray().map(row => row.name));
    known.set(storage, names);
  }
  return names.has(table);
}
function create(storage: DurableObjectStorage, table: typeof FACTS): void {
  if (present(storage, table.name)) return;
  storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  known.delete(storage);
}

/** A member's stored Full Journey end, or 0. */
export function memberUntil(storage: DurableObjectStorage, player: string | null): number {
  if (player === null || !present(storage, MEMBERS.name)) return 0;
  return storage.sql.exec<{ fj_until: number }>("SELECT fj_until FROM pollen_members WHERE player_id=?", player).toArray()[0]?.fj_until ?? 0;
}

/**
 * Keeps the member's copy as their Player reported it, inside a write the room already makes.
 * Undefined writes nothing (the flag is off); a value equal to the stored one writes nothing; 0
 * removes the row. The caller owns the transaction.
 */
export function recordMember(storage: DurableObjectStorage, player: string, member: PollenMember | undefined): void {
  if (member === undefined || !validMember(member) || !ID_PATTERN.test(player)) return;
  if (memberUntil(storage, player) === member.fj_until) return;
  if (member.fj_until === 0) { storage.sql.exec("DELETE FROM pollen_members WHERE player_id=?", player); return; }
  create(storage, MEMBERS);
  storage.sql.exec("INSERT OR REPLACE INTO pollen_members VALUES (?,?)", player, member.fj_until);
}

export type AcceptedTurn = {
  room_id: string; recording_hash: string; turn_id: string; player: string; partner: string | null; host: boolean;
  level_id: string; stage_id: string; role: "a" | "b"; ticks: number; tries: number | undefined;
  premium: boolean; hard: boolean; complete: boolean; accepted_at: number;
  /** A friend duel's room. */
  duel?: boolean;
};

/**
 * Freezes one accepted turn's facts, inside the commit transaction, after recordMember wrote the
 * committing player's copy. Past MAX_FACTS rows the oldest go, as the room's own history is bounded.
 */
export function recordTurnFacts(storage: DurableObjectStorage, turn: AcceptedTurn): TurnFacts {
  const subscriber = memberUntil(storage, turn.player) > turn.accepted_at;
  const partner_subscriber = memberUntil(storage, turn.partner) > turn.accepted_at;
  const facts: TurnFacts = { schema_version: 1, room_id: turn.room_id, recording_hash: turn.recording_hash, turn_id: turn.turn_id, player_id: turn.player,
    accepted_at: turn.accepted_at, week: isoWeek(turn.accepted_at), level_id: turn.level_id, stage_id: turn.stage_id, role: turn.role,
    ticks: turn.ticks, tries: turn.tries ?? null, premium: turn.premium, hard: turn.hard, host: turn.host, together: turn.partner !== null, complete: turn.complete,
    subscriber, partner_subscriber, boost_percent: boostPercent(Number(subscriber) + Number(partner_subscriber)), ...(turn.duel ? { duel: true as const } : {}) };
  create(storage, FACTS);
  storage.sql.exec("INSERT OR IGNORE INTO pollen_turn_facts VALUES (?,?,?,?)", facts.recording_hash, facts.player_id, facts.accepted_at, JSON.stringify(facts));
  storage.sql.exec("DELETE FROM pollen_turn_facts WHERE recording_hash IN (SELECT recording_hash FROM pollen_turn_facts ORDER BY accepted_at DESC, recording_hash LIMIT -1 OFFSET ?)", MAX_FACTS);
  return facts;
}

/** A stored row's facts, or null: reading facts never throws, so it can never fail an accepted turn's reply. */
function parsed(row: { data: string } | undefined): TurnFacts | null {
  if (!row) return null;
  try { const value: unknown = JSON.parse(row.data); return validTurnFacts(value) ? value : null; } catch { return null; }
}

/** The frozen facts of one turn, or null. A room without the table reads nothing. */
export function turnFacts(storage: DurableObjectStorage, recordingHash: string): TurnFacts | null {
  if (!present(storage, FACTS.name) || !HASH_PATTERN.test(recordingHash)) return null;
  return parsed(storage.sql.exec<{ data: string }>("SELECT data FROM pollen_turn_facts WHERE recording_hash=?", recordingHash).toArray()[0]);
}

/** The facts of the newest turn that finished the chapter, or null. */
export function completionFacts(storage: DurableObjectStorage): TurnFacts | null {
  if (!present(storage, FACTS.name)) return null;
  return parsed(storage.sql.exec<{ data: string }>("SELECT data FROM pollen_turn_facts WHERE json_extract(data,'$.complete')=1 ORDER BY accepted_at DESC LIMIT 1").toArray()[0]);
}

/**
 * For the full room erase (which every account erasure of a member runs) and a snapshot restore.
 * A member who leaves a finished room keeps their rows, as the room keeps their turns, so a turn
 * whose credit did not land can still be claimed.
 */
export function clearPollenRoom(storage: DurableObjectStorage): void {
  storage.sql.exec("DROP TABLE IF EXISTS pollen_turn_facts");
  storage.sql.exec("DROP TABLE IF EXISTS pollen_members");
  known.delete(storage);
}

/** The tables as sqlite_master lists them, so snapshot schema checks can let them pass. */
export function isPollenRoomTable(row: { name: string; sql: string }): boolean { return isLazyTable(POLLEN_ROOM_TABLES, row); }
