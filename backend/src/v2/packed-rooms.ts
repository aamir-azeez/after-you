import { flags, type ServerVars } from "../flags";

/**
 * Which rooms take packed recordings (v2/recording-codec.ts). A phone that reads them sends PACKED_HEADER; while
 * PACKED_RECORDINGS is on it is told `packed_recordings_version: 1`, and its create or join notes its seat as a
 * reader. A room whose host and guest both did is packed for good: it takes packed turns, and a read or turn reply
 * that asked says `packed_recordings: true` beside the room, which is when the phone records packed. Every other
 * room refuses a packed turn (422 packed_recording_not_allowed), so a member on an older app always reads its
 * partner's turns. Both forms of a turn are always taken in a packed room, and turning the flag off only stops new
 * rooms from becoming packed. The seats hold no player id.
 */
export const PACKED_HEADER = "X-AfterYou-Packed-Recordings";
export const PACKED_TABLE = { name: "packed_readers", schema: "CREATE TABLE packed_readers (seat TEXT PRIMARY KEY CHECK(seat IN ('host','guest')))", columns: ["rowid", "seat"], maxRows: 2 } as const;

export function packedAsked(request: Request): boolean { return request.headers.get(PACKED_HEADER) === "1"; }
/** Whether this create or join notes its seat as a reader. */
export function packedReader(request: Request, env: ServerVars): boolean { return packedAsked(request) && flags.packedRecordings(env); }
export function packedCapability(request: Request, env: ServerVars): { packed_recordings_version?: 1 } {
  return packedReader(request, env) ? { packed_recordings_version: 1 } : {};
}

/** Rooms already known to be packed: that never changes back. */
const known = new WeakSet<DurableObjectStorage>();
/** Inside the create or join transaction. */
export function noteReader(storage: DurableObjectStorage, seat: "host" | "guest"): void {
  storage.sql.exec(PACKED_TABLE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT OR IGNORE INTO packed_readers VALUES (?)", seat);
}
export function packedRoom(storage: DurableObjectStorage): boolean {
  if (known.has(storage)) return true;
  let readers = 0;
  try { readers = storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM packed_readers").one().n; } catch { return false; }
  if (readers === 2) known.add(storage);
  return readers === 2;
}
