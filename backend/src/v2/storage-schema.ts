import type { TableDefinition } from "../storage-schema";

export const METADATA_SCHEMA = "CREATE TABLE metadata (id INTEGER PRIMARY KEY CHECK(id=1), schema_version INTEGER NOT NULL)";
/** Fixed SQL; archive-provided SQL is never executed. */
export const ROOM_V2_TABLES: readonly TableDefinition[] = [
  { name: "room", schema: "CREATE TABLE room (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", columns: ["rowid", "id", "data"], maxRows: 1,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,id,data FROM room ORDER BY rowid LIMIT 2", insert: "INSERT INTO room (rowid,id,data) VALUES (CAST(? AS INTEGER),?,?)" },
  { name: "turns", schema: "CREATE TABLE turns (turn_id TEXT PRIMARY KEY, player_id TEXT NOT NULL, accepted_revision INTEGER NOT NULL, data TEXT NOT NULL)", columns: ["rowid", "turn_id", "player_id", "accepted_revision", "data"], maxRows: 128,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,turn_id,player_id,accepted_revision,data FROM turns ORDER BY rowid LIMIT 129", insert: "INSERT INTO turns (rowid,turn_id,player_id,accepted_revision,data) VALUES (CAST(? AS INTEGER),?,?,?,?)" },
  { name: "pairs", schema: "CREATE TABLE pairs (pair_id TEXT PRIMARY KEY, data TEXT NOT NULL)", columns: ["rowid", "pair_id", "data"], maxRows: 64,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,pair_id,data FROM pairs ORDER BY rowid LIMIT 65", insert: "INSERT INTO pairs (rowid,pair_id,data) VALUES (CAST(? AS INTEGER),?,?)" },
  { name: "operations", schema: "CREATE TABLE operations (request_key TEXT PRIMARY KEY, request_hash TEXT NOT NULL, receipt TEXT NOT NULL)", columns: ["rowid", "request_key", "request_hash", "receipt"], maxRows: 256,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,request_key,request_hash,receipt FROM operations ORDER BY rowid LIMIT 257", insert: "INSERT INTO operations (rowid,request_key,request_hash,receipt) VALUES (CAST(? AS INTEGER),?,?,?)" }
];

export function initializeRoomV2Schema(storage: DurableObjectStorage): void {
  storage.sql.exec(METADATA_SCHEMA.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT OR IGNORE INTO metadata VALUES (1,2)");
  if (storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata WHERE id=1").one().schema_version !== 2) throw new Error("unsupported_room_schema");
  for (const table of ROOM_V2_TABLES) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
}
