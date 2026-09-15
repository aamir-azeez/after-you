import type { TableDefinition } from "../storage-schema";

export const METADATA_SCHEMA = "CREATE TABLE metadata (id INTEGER PRIMARY KEY CHECK(id=1), schema_version INTEGER NOT NULL)";
/** Fixed SQL; archive-provided SQL is never executed. */
export const LEGACY_ROOM_V2_TABLES: readonly TableDefinition[] = [
  { name: "room", schema: "CREATE TABLE room (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", columns: ["rowid", "id", "data"], maxRows: 1,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,id,data FROM room ORDER BY room.rowid LIMIT 2", insert: "INSERT INTO room (rowid,id,data) VALUES (CAST(? AS INTEGER),?,?)" },
  { name: "turns", schema: "CREATE TABLE turns (turn_id TEXT PRIMARY KEY, player_id TEXT NOT NULL, accepted_revision INTEGER NOT NULL, data TEXT NOT NULL)", columns: ["rowid", "turn_id", "player_id", "accepted_revision", "data"], maxRows: 128,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,turn_id,player_id,accepted_revision,data FROM turns ORDER BY turns.rowid LIMIT 129", insert: "INSERT INTO turns (rowid,turn_id,player_id,accepted_revision,data) VALUES (CAST(? AS INTEGER),?,?,?,?)" },
  { name: "pairs", schema: "CREATE TABLE pairs (pair_id TEXT PRIMARY KEY, data TEXT NOT NULL)", columns: ["rowid", "pair_id", "data"], maxRows: 64,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,pair_id,data FROM pairs ORDER BY pairs.rowid LIMIT 65", insert: "INSERT INTO pairs (rowid,pair_id,data) VALUES (CAST(? AS INTEGER),?,?)" },
  { name: "operations", schema: "CREATE TABLE operations (request_key TEXT PRIMARY KEY, request_hash TEXT NOT NULL, receipt TEXT NOT NULL)", columns: ["rowid", "request_key", "request_hash", "receipt"], maxRows: 256,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,request_key,request_hash,receipt FROM operations ORDER BY operations.rowid LIMIT 257", insert: "INSERT INTO operations (rowid,request_key,request_hash,receipt) VALUES (CAST(? AS INTEGER),?,?,?)" }
];
export const ROOM_V2_TABLES: readonly TableDefinition[] = [...LEGACY_ROOM_V2_TABLES,
  { name: "photos", schema: "CREATE TABLE photos (turn_id TEXT PRIMARY KEY, data TEXT NOT NULL)", columns: ["rowid", "turn_id", "data"], maxRows: 128,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,turn_id,data FROM photos ORDER BY photos.rowid LIMIT 129", insert: "INSERT INTO photos (rowid,turn_id,data) VALUES (CAST(? AS INTEGER),?,?)" },
  { name: "photo_operations", schema: "CREATE TABLE photo_operations (request_key TEXT PRIMARY KEY, request_hash TEXT NOT NULL, receipt TEXT NOT NULL)", columns: ["rowid", "request_key", "request_hash", "receipt"], maxRows: 256,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,request_key,request_hash,receipt FROM photo_operations ORDER BY photo_operations.rowid LIMIT 257", insert: "INSERT INTO photo_operations (rowid,request_key,request_hash,receipt) VALUES (CAST(? AS INTEGER),?,?,?)" }
];

export const REACTION_TABLES: readonly TableDefinition[] = [
  { name: "pair_reactions", schema: "CREATE TABLE pair_reactions (reaction_key TEXT PRIMARY KEY, data TEXT NOT NULL)", columns: ["rowid", "reaction_key", "data"], maxRows: 128,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,reaction_key,data FROM pair_reactions ORDER BY pair_reactions.rowid LIMIT 129", insert: "INSERT INTO pair_reactions (rowid,reaction_key,data) VALUES (CAST(? AS INTEGER),?,?)" },
  { name: "reaction_operations", schema: "CREATE TABLE reaction_operations (request_key TEXT PRIMARY KEY, request_hash TEXT NOT NULL, receipt TEXT NOT NULL)", columns: ["rowid", "request_key", "request_hash", "receipt"], maxRows: 256,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,request_key,request_hash,receipt FROM reaction_operations ORDER BY reaction_operations.rowid LIMIT 257", insert: "INSERT INTO reaction_operations (rowid,request_key,request_hash,receipt) VALUES (CAST(? AS INTEGER),?,?,?)" }
];
export const ROOM_V2_REACTION_TABLES: readonly TableDefinition[] = [...ROOM_V2_TABLES, ...REACTION_TABLES];

/** The caller already owns the mutation/restore transaction. No gameplay row changes. */
export function initializePairReactions(storage: DurableObjectStorage): void {
  const version = storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata WHERE id=1").one().schema_version;
  if (version !== 3 && version !== 4) throw new Error("unsupported_room_schema");
  for (const table of REACTION_TABLES) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  if (version === 3) storage.sql.exec("UPDATE metadata SET schema_version=4 WHERE id=1");
}

export function initializeRoomV2Schema(storage: DurableObjectStorage): void {
  storage.transactionSync(() => {
    storage.sql.exec(METADATA_SCHEMA.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
    storage.sql.exec("INSERT OR IGNORE INTO metadata VALUES (1,3)");
    const version = storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata WHERE id=1").one().schema_version;
    if (version !== 2 && version !== 3 && version !== 4) throw new Error("unsupported_room_schema");
    for (const table of version === 4 ? ROOM_V2_REACTION_TABLES : ROOM_V2_TABLES) storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
    if (version === 2) storage.sql.exec("UPDATE metadata SET schema_version=3 WHERE id=1");
  });
}
