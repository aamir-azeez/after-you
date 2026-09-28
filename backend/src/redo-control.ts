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
export function resetRedo(storage: DurableObjectStorage): void { storage.sql.exec("DELETE FROM redo_control"); }
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
