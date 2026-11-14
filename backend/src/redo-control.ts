import type { InboxRedo } from "./room-inbox";
import { ApiError, HASH_PATTERN, ID_PATTERN, canonicalJson, digest, fail, isObject, object, ok, type Outcome } from "./protocol";

// Advisory state only. Accepted re-recording remains an ordinary archived fork.
export const REDO_TABLE = { name: "redo_control", schema: "CREATE TABLE redo_control (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)" };
export type RedoSource = { room_id: string; revision: number; branch: number; stage_index: number; a_hash: string; first_player_id: string; second_player_id: string };
export type RedoRequest = { request_id: string; source: RedoSource; status: "pending" | "declined" | "cancelled" | "accepted" };
export type RedoState = { schema_version: 1; source: RedoSource | null; request: RedoRequest | null };
type Action = "request" | "decline" | "cancel";
export type RedoMutation = { action: Action; source: RedoSource; request_id: string };

function exact(value: Record<string, unknown>, keys: string[]): boolean { return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)); }
export function validRedoSource(value: unknown): value is RedoSource {
  return isObject(value) && exact(value, ["room_id", "revision", "branch", "stage_index", "a_hash", "first_player_id", "second_player_id"]) &&
    [value.room_id, value.first_player_id, value.second_player_id].every(id => typeof id === "string" && ID_PATTERN.test(id)) && value.first_player_id !== value.second_player_id &&
    typeof value.a_hash === "string" && HASH_PATTERN.test(value.a_hash) && [value.revision, value.branch, value.stage_index].every(n => Number.isSafeInteger(n) && Number(n) >= 0);
}
function validRequest(value: unknown): value is RedoRequest {
  return isObject(value) && exact(value, ["request_id", "source", "status"]) && typeof value.request_id === "string" && HASH_PATTERN.test(value.request_id) &&
    validRedoSource(value.source) && ["pending", "declined", "cancelled", "accepted"].includes(String(value.status));
}
export function initializeRedo(storage: DurableObjectStorage): void { storage.sql.exec(REDO_TABLE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ")); }
/** For the full room erase and a snapshot restore: the request and the seen first turn. */
/**
 * Start over (v2/room.ts wipeRun): the request and the seen note go, and the row records the branch the run begins
 * again on (run_from), which phones compare with the last one they saw to drop their copies of the old run.
 */
export function clearRedoRequests(storage: DurableObjectStorage, runFrom: number): void {
  storage.sql.exec("DELETE FROM redo_control");
  ensureSeen(storage);
  storage.sql.exec("INSERT INTO redo_seen VALUES (1,'','',?) ON CONFLICT(id) DO UPDATE SET turn_id='',a_hash='',run_from=excluded.run_from", runFrom);
}
/** The branch the room's run last began again on (start over), 0 for a room never started over. */
export function runFrom(storage: DurableObjectStorage): number {
  return seenPresent(storage) ? storage.sql.exec<{ run_from: number }>("SELECT run_from FROM redo_seen WHERE id=1").toArray()[0]?.run_from ?? 0 : 0;
}
export function resetRedo(storage: DurableObjectStorage): void { storage.sql.exec("DELETE FROM redo_control"); storage.sql.exec("DROP TABLE IF EXISTS redo_seen"); seenTables.delete(storage); }
function stored(storage: DurableObjectStorage): RedoRequest | null {
  const rows = storage.sql.exec<{ id: number; data: string }>("SELECT id,data FROM redo_control LIMIT 2").toArray();
  if (!rows.length) return null;
  if (rows.length !== 1 || rows[0].id !== 1 || rows[0].data.length > 2048) throw new ApiError(503, "redo_state_unavailable");
  let value: unknown; try { value = JSON.parse(rows[0].data); } catch { throw new ApiError(503, "redo_state_unavailable"); }
  if (!validRequest(value)) throw new ApiError(503, "redo_state_unavailable");
  return value;
}
export function redoRuntimeValid(storage: DurableObjectStorage): boolean { try { stored(storage); return true; } catch { return false; } }
export function redoState(storage: DurableObjectStorage, source: RedoSource | null): RedoState {
  const current = stored(storage);
  return { schema_version: 1, source, request: source && current && canonicalJson(current.source) === canonicalJson(source) ? current : null };
}
export async function parseRedoMutation(value: unknown): Promise<RedoMutation> {
  const input = object(value);
  if (!exact(input, ["action", "source"]) || !["request", "decline", "cancel"].includes(String(input.action)) || !validRedoSource(input.source)) throw new ApiError(400, "invalid_redo_request");
  return { action: input.action as Action, source: input.source, request_id: await digest(canonicalJson(input.source)) };
}
// Called inside the room's transaction, after re-reading its authoritative turn.
export function mutateRedo(storage: DurableObjectStorage, source: RedoSource | null, player: string, input: RedoMutation): Outcome<RedoState> {
  if (!source || canonicalJson(source) !== canonicalJson(input.source)) return fail(409, "redo_source_changed");
  if (player !== (input.action === "decline" ? source.first_player_id : source.second_player_id)) return fail(403, "wrong_redo_player");
  const previous = redoState(storage, source).request;
  if (input.action !== "request" && !previous) return fail(409, "redo_request_missing");
  // One open request per room position: a redo and a start over never replace each other's row. The refusal is a code
  // 0.8.1 settles (it drops its pending request), as for a moved room.
  const other = previous ? null : stored(storage);
  if (input.action === "request" && other?.status === "pending" && samePosition(other.source, source)) return fail(409, "redo_source_changed");
  // One request per accepted A turn. Retries and cancelled/declined requests do
  // not create more work or repeatedly interrupt the partner.
  if (previous && (input.action === "request" || previous.status !== "pending")) return ok(redoState(storage, source));
  const request: RedoRequest = { request_id: input.request_id, source, status: input.action === "request" ? "pending" : input.action === "decline" ? "declined" : "cancelled" };
  storage.sql.exec("INSERT OR REPLACE INTO redo_control VALUES (1,?)", JSON.stringify(request));
  return ok({ schema_version: 1, source, request });
}
export function consentToRedo(storage: DurableObjectStorage, source: RedoSource | null, player: string, requestId: string): Outcome<null> {
  if (!source || player !== source.first_player_id) return fail(409, "redo_source_changed");
  const request = redoState(storage, source).request;
  return request && request.request_id === requestId && request.status === "pending" ? ok(null) : fail(409, "redo_request_missing");
}
export function acceptedRedo(storage: DurableObjectStorage): void {
  const request = stored(storage);
  if (request) storage.sql.exec("UPDATE redo_control SET data=? WHERE id=1", JSON.stringify({ ...request, status: "accepted" }));
}
/**
 * The inbox's view of the stored request (room-inbox.ts), from the scalars its projection already selected: a request
 * is current only on the same revision, branch and stage, since the revision moves with every turn. Reads one small
 * row and never the turn; a damaged row only drops the field.
 */
export function inboxRedo(storage: DurableObjectStorage, player: string, room: { revision: number; branch: number; stage_index: number; a_turn_id: string | null; checkpoint_hash: string | null }): { redo?: InboxRedo } {
  let request: RedoRequest | null;
  try { request = stored(storage); } catch { return {}; }
  if (!request || request.source.revision !== room.revision || request.source.branch !== room.branch || request.source.stage_index !== room.stage_index) return {};
  // A redo only while the second turn is unplayed; a start over (isStartOver) at any stage, shown as start_over_*.
  const over = room.checkpoint_hash !== null && request.source.a_hash === room.checkpoint_hash;
  if (!over && !room.a_turn_id) return {};
  const shown = (state: "asked_you" | "you_asked" | "kept"): { redo: InboxRedo } => ({ redo: { state: over ? `start_over_${state}` as const : state, stage_index: room.stage_index } });
  if (request.status === "pending") return player === request.source.first_player_id ? shown("asked_you") : player === request.source.second_player_id ? shown("you_asked") : {};
  return request.status === "declined" && player === request.source.second_player_id ? shown("kept") : {};
}

const samePosition = (a: RedoSource, b: Pick<RedoSource, "room_id" | "revision" | "branch" | "stage_index">): boolean =>
  a.room_id === b.room_id && a.revision === b.revision && a.branch === b.branch && a.stage_index === b.stage_index;

/**
 * Start over: either member asks to take the room back to its first stage, the other agrees (a fork to stage 0
 * carrying the request's id) or declines. It is the same one-row request as a redo, told apart by its source:
 * a start over names the room's live checkpoint where a redo names the first turn's recording, so the asker is the
 * source's second player and the friend who answers is its first. Older Workers read the row as an ordinary request
 * for a source that is never their redo source, so it shows nowhere there and nothing accepts it.
 */
export type RoomPosition = { room_id: string; revision: number; branch: number; stage_index: number; checkpoint_hash: string; host_id: string; guest_id: string | null };
export function startOverSource(room: RoomPosition, asker: string): RedoSource | null {
  if (!room.guest_id || ![room.host_id, room.guest_id].includes(asker)) return null;
  return { room_id: room.room_id, revision: room.revision, branch: room.branch, stage_index: room.stage_index, a_hash: room.checkpoint_hash,
    first_player_id: asker === room.host_id ? room.guest_id : room.host_id, second_player_id: asker };
}
/** Whether a request's source is a start over of this room position. */
export function isStartOver(source: RedoSource, room: Pick<RoomPosition, "checkpoint_hash">): boolean { return source.a_hash === room.checkpoint_hash; }
/** The start over request on this room position, whatever its status, or null. */
export function startOverRequest(storage: DurableObjectStorage, room: RoomPosition): RedoRequest | null {
  const current = stored(storage);
  return current && samePosition(current.source, room) && isStartOver(current.source, room) ? current : null;
}
/** A fork carrying `requestId` answers this pending start over: only its first player (the friend asked) may. */
export function startOverConsent(storage: DurableObjectStorage, room: RoomPosition, player: string, requestId: string): boolean {
  const request = startOverRequest(storage, room);
  return request !== null && request.status === "pending" && request.request_id === requestId && request.source.first_player_id === player;
}

/**
 * Play my turn again (self redo): the first player may record their saved turn again until the friend's phone has
 * fetched it. The room notes the first time a room read hands the first turn to the second player (v2/room.ts
 * view), one row a turn, in a table made by the first such read so other rooms' storage is unchanged; a
 * replacement is refused once the row names the live first turn. Operator snapshots leave the table out, and the
 * full erase and a snapshot restore drop it (resetRedo).
 */
export const REDO_SEEN_TABLE = { name: "redo_seen", schema: "CREATE TABLE redo_seen (id INTEGER PRIMARY KEY CHECK(id=1), turn_id TEXT NOT NULL, a_hash TEXT NOT NULL, run_from INTEGER NOT NULL DEFAULT 0)" } as const;
function ensureSeen(storage: DurableObjectStorage): void {
  if (seenPresent(storage)) return;
  storage.sql.exec(REDO_SEEN_TABLE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  seenTables.delete(storage);
}
/** Whether the table exists, looked up once per room instance (every waiting poll asks); only this module makes or drops it. */
const seenTables = new WeakMap<DurableObjectStorage, boolean>();
function seenPresent(storage: DurableObjectStorage): boolean {
  let known = seenTables.get(storage);
  if (known === undefined) {
    known = storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name=?", REDO_SEEN_TABLE.name).toArray().length > 0;
    seenTables.set(storage, known);
  }
  return known;
}
/** Whether the second player's phone has fetched this first turn. */
export function turnSeen(storage: DurableObjectStorage, turnId: string, aHash: string): boolean {
  return seenPresent(storage) && storage.sql.exec("SELECT 1 AS seen FROM redo_seen WHERE id=1 AND turn_id=? AND a_hash=?", turnId, aHash).toArray().length > 0;
}
/** Notes that the second player was handed this first turn; writes only the first time. */
export function noteTurnSeen(storage: DurableObjectStorage, turnId: string, aHash: string): void {
  if (turnSeen(storage, turnId, aHash)) return;
  ensureSeen(storage);
  storage.sql.exec("INSERT INTO redo_seen VALUES (1,?,?,0) ON CONFLICT(id) DO UPDATE SET turn_id=excluded.turn_id,a_hash=excluded.a_hash", turnId, aHash);
}
/** The table as sqlite_master lists it, so snapshot schema checks can let it pass. */
export function isRedoSeenTable(row: { name: string; sql: string }): boolean {
  return row.name === REDO_SEEN_TABLE.name && row.sql === REDO_SEEN_TABLE.schema;
}

/**
 * The redo state for a phone that sent poll redo version 2 (v2/routes.ts POLL_REDO_HEADER): the redo state as
 * before, the room's start over request, and whether this member may play their saved turn again now. Version 1
 * phones get RedoState exactly as before, which never shows a start over.
 */
export type RedoStateV2 = { schema_version: 2; source: RedoSource | null; request: RedoRequest | null; start_over: RedoRequest | null; replace_open: boolean; run_from: number };
export function redoStateV2(storage: DurableObjectStorage, source: RedoSource | null, room: RoomPosition | null, replaceOpen: boolean): RedoStateV2 {
  const state = redoState(storage, source);
  return { schema_version: 2, source: state.source, request: state.request, start_over: room ? startOverRequest(storage, room) : null, replace_open: replaceOpen, run_from: runFrom(storage) };
}
