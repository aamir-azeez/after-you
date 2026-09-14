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
    { name: "rooms", schema: "CREATE TABLE rooms (room_id TEXT PRIMARY KEY, data TEXT NOT NULL)", columns: ["rowid", "room_id", "data"], maxRows: 20,
      select: "SELECT CAST(rowid AS TEXT) AS rowid, room_id, data FROM rooms ORDER BY rooms.rowid LIMIT 21", insert: "INSERT INTO rooms (rowid,room_id,data) VALUES (CAST(? AS INTEGER),?,?)" },
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
