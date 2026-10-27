import { MAX_INDEXED_ROOM_LINKS } from "./room-limit";

/** Fixed application schemas. Archive SQL is descriptive and is never executed. */
export type ObjectKind = "Player" | "Room";
export type TableDefinition = {
  name: string; schema: string; columns: string[]; maxRows: number;
  select: string; insert: string;
};
export const TABLES: Record<ObjectKind, readonly TableDefinition[]> = {
  Player: [
    { name: "identity", schema: "CREATE TABLE identity (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", columns: ["rowid", "id", "data"], maxRows: 1,
      select: "SELECT CAST(rowid AS TEXT) AS rowid, id, data FROM identity ORDER BY identity.rowid LIMIT 2", insert: "INSERT INTO identity (rowid,id,data) VALUES (CAST(? AS INTEGER),?,?)" },
    { name: "rooms", schema: "CREATE TABLE rooms (room_id TEXT PRIMARY KEY, data TEXT NOT NULL)", columns: ["rowid", "room_id", "data"], maxRows: MAX_INDEXED_ROOM_LINKS,
      select: `SELECT CAST(rowid AS TEXT) AS rowid, room_id, data FROM rooms ORDER BY rooms.rowid LIMIT ${MAX_INDEXED_ROOM_LINKS + 1}`, insert: "INSERT INTO rooms (rowid,room_id,data) VALUES (CAST(? AS INTEGER),?,?)" },
    { name: "creations", schema: "CREATE TABLE creations (request_key TEXT PRIMARY KEY, data TEXT NOT NULL)", columns: ["rowid", "request_key", "data"], maxRows: 128,
      select: "SELECT CAST(rowid AS TEXT) AS rowid, request_key, data FROM creations ORDER BY creations.rowid LIMIT 129", insert: "INSERT INTO creations (rowid,request_key,data) VALUES (CAST(? AS INTEGER),?,?)" }
  ],
  Room: [
    { name: "room", schema: "CREATE TABLE room (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", columns: ["rowid", "id", "data"], maxRows: 1,
      select: "SELECT CAST(rowid AS TEXT) AS rowid, id, data FROM room ORDER BY room.rowid LIMIT 2", insert: "INSERT INTO room (rowid,id,data) VALUES (CAST(? AS INTEGER),?,?)" },
    { name: "operations", schema: "CREATE TABLE operations (request_key TEXT PRIMARY KEY, request_hash TEXT NOT NULL, revision INTEGER NOT NULL)", columns: ["rowid", "request_key", "request_hash", "revision"], maxRows: 256,
      select: "SELECT CAST(rowid AS TEXT) AS rowid, request_key, request_hash, revision FROM operations ORDER BY operations.rowid LIMIT 257", insert: "INSERT INTO operations (rowid,request_key,request_hash,revision) VALUES (CAST(? AS INTEGER),?,?,?)" },
    { name: "archive", schema: "CREATE TABLE archive (attempt INTEGER PRIMARY KEY, data TEXT NOT NULL)", columns: ["rowid", "attempt", "data"], maxRows: 88,
      select: "SELECT CAST(rowid AS TEXT) AS rowid, attempt, data FROM archive ORDER BY archive.rowid LIMIT 89", insert: "INSERT INTO archive (rowid,attempt,data) VALUES (CAST(? AS INTEGER),?,?)" }
  ]
};

export function initializeSchema(storage: DurableObjectStorage, kind: ObjectKind): void {
  for (const table of TABLES[kind]) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
}

/**
 * Tables an object creates on first use, never in initializeSchema, so an object that never uses
 * them stores nothing more than before. Each has a fixed schema and a row bound its writer keeps.
 */
export type LazyTable = { name: string; schema: string; maxRows: number };
/** Player: the Pollen wallet (pollen/wallet.ts). Turn claims older than the prune window go before a new one lands. */
export const POLLEN_WALLET_TABLES: readonly LazyTable[] = Object.freeze([
  { name: "pollen_wallet", schema: "CREATE TABLE pollen_wallet (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", maxRows: 1 },
  // 6 kept weeks x (36 bank turns + 100 paying after-bank turns), plus first clears of every chapter twice.
  { name: "pollen_claims", schema: "CREATE TABLE pollen_claims (claim_key TEXT PRIMARY KEY, kind TEXT NOT NULL, amount INTEGER NOT NULL, created_at INTEGER NOT NULL, data TEXT NOT NULL) WITHOUT ROWID", maxRows: 1024 }
]);
/**
 * Player: the wardrobe (pollen/wardrobe.ts), made by the first purchase or look, never by a wallet.
 * - pollen_items: one row per owned item or reaction pack, never removed (bounded by the catalogue).
 * - pollen_ops: the newest spend and equip receipts by idempotency key; the oldest go past maxRows.
 * - pollen_look: the look the player wears and the revision it came from.
 */
export const POLLEN_SHOP_TABLES: readonly LazyTable[] = Object.freeze([
  { name: "pollen_items", schema: "CREATE TABLE pollen_items (item_id TEXT PRIMARY KEY, kind TEXT NOT NULL, source TEXT NOT NULL, acquired_at INTEGER NOT NULL) WITHOUT ROWID", maxRows: 512 },
  { name: "pollen_ops", schema: "CREATE TABLE pollen_ops (op_key TEXT PRIMARY KEY, request_hash TEXT NOT NULL, created_at INTEGER NOT NULL, data TEXT NOT NULL)", maxRows: 64 },
  { name: "pollen_look", schema: "CREATE TABLE pollen_look (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", maxRows: 1 }
]);
/** Every Pollen table a Player may hold: account erasure drops them all, and snapshots refuse a Player that has any. */
export const POLLEN_PLAYER_TABLES: readonly LazyTable[] = Object.freeze([...POLLEN_WALLET_TABLES, ...POLLEN_SHOP_TABLES]);
/** RoomV2: frozen Pollen facts per accepted turn and each member's Full Journey end (pollen/turn-facts.ts). */
export const POLLEN_ROOM_TABLES: readonly LazyTable[] = Object.freeze([
  // One row per accepted turn, as the turns table (MAX_TURNS); the oldest go first past it.
  { name: "pollen_turn_facts", schema: "CREATE TABLE pollen_turn_facts (recording_hash TEXT PRIMARY KEY, player_id TEXT NOT NULL, accepted_at INTEGER NOT NULL, data TEXT NOT NULL) WITHOUT ROWID", maxRows: 128 },
  { name: "pollen_members", schema: "CREATE TABLE pollen_members (player_id TEXT PRIMARY KEY, fj_until INTEGER NOT NULL) WITHOUT ROWID", maxRows: 2 }
]);
/**
 * RoomV2: looks (pollen/room-looks.ts), made by the first look that is not the default.
 * - member_looks: each member's look as their Player last reported it on create, join or a turn.
 * - turn_looks: the look a turn was played in, keyed by its recording hash; one row per accepted
 *   turn at most (the turns bound), and only for a look that is not the default.
 */
export const LOOKS_ROOM_TABLES: readonly LazyTable[] = Object.freeze([
  { name: "member_looks", schema: "CREATE TABLE member_looks (player_id TEXT PRIMARY KEY, look TEXT NOT NULL) WITHOUT ROWID", maxRows: 2 },
  { name: "turn_looks", schema: "CREATE TABLE turn_looks (recording_hash TEXT PRIMARY KEY, player_id TEXT NOT NULL, look TEXT NOT NULL)", maxRows: 128 }
]);
/** Whether a sqlite_master row is one of `tables` in its exact form. */
export function isLazyTable(tables: readonly LazyTable[], row: { name: string; sql: string }): boolean {
  return tables.some(table => table.name === row.name && table.schema === row.sql);
}
