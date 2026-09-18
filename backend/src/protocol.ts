export const LEVEL_IDS = ["first-light", "long-way-home", "patient-garden", "rising-together", "across-the-blue", "lantern-crossing", "two-beats", "after-you"] as const;
export const MAX_BODY_BYTES = 98_304;
export type Role = "a" | "b";
export type LegacySimulationVersion = 1 | 6;
export function legacySimulationVersion(value: unknown): LegacySimulationVersion {
  if (value !== 1 && value !== 6) throw new ApiError(422, "unsupported_simulation_version");
  return value;
}
export type Outcome<T> = { ok: true; value: T } | { ok: false; status: number; code: string };
export const ok = <T>(value: T): Outcome<T> => ({ ok: true, value });
export const fail = (status: number, code: string): Outcome<never> => ({ ok: false, status, code });
export type Recording = {
  schema_version: 1; simulation_version: LegacySimulationVersion; level_id: string; level_version: 1;
  role: Role; duration_ticks: number; tick_rate: 30; catch_assistance: boolean;
  actions: { ticks: number; x: number; z: number; action: boolean }[];
  checkpoints: { tick: number; state_hash: string }[];
  final_state_hash: string; completed: boolean;
  outcome: { threw_seed: boolean; caught_seed: boolean; planted_seed: boolean };
  source_recording_hash?: string;
};
export type RoomState = {
  schema_version: 1; room_id: string; revision: number; attempt: number;
  simulation_version?: LegacySimulationVersion;
  host_id: string; guest_id: string | null; level_index: number; level_id: string;
  first_player_id: string; active_role: Role | "complete";
  recordings: { a: Recording | null; b: Recording | null };
  completed_islands: string[]; created_at: string; updated_at: string;
  invite_code: string; invite_expires_at: string;
  reactions: Record<string, "love" | "sparkles" | "again">;
};
export type RoomSnapshot = Omit<RoomState, "invite_code"> & { invite_code?: string };
export class ApiError extends Error {
  constructor(public status: number, public code: string) { super(code); }
}
export const isObject = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
export function object(value: unknown): Record<string, unknown> {
  if (!isObject(value)) throw new ApiError(400, "invalid_object");
  return value;
}
export function exactKeys(value: Record<string, unknown>, allowed: string[]): void {
  if (Object.keys(value).some(key => !allowed.includes(key))) throw new ApiError(400, "unexpected_field");
}
export function text(value: unknown, pattern: RegExp, code = "invalid_field"): string {
  if (typeof value !== "string" || !pattern.test(value)) throw new ApiError(400, code);
  return value;
}
export function integer(value: unknown, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) throw new ApiError(400, "invalid_integer");
  return value;
}
function boolean(value: unknown): boolean {
  if (typeof value !== "boolean") throw new ApiError(400, "invalid_boolean");
  return value;
}
export const ID_PATTERN = /^[a-zA-Z0-9_-]{22}$/;
export const SECRET_PATTERN = /^[a-zA-Z0-9_-]{43}$/;
export const IDEMPOTENCY_PATTERN = /^[a-zA-Z0-9_-]{16,80}$/;
export const HASH_PATTERN = /^[a-f0-9]{64}$/;
export function recording(input: unknown): Recording {
  const r = object(input);
  exactKeys(r, ["schema_version", "simulation_version", "level_id", "level_version", "role", "duration_ticks", "tick_rate", "catch_assistance", "actions", "checkpoints", "final_state_hash", "completed", "outcome", "source_recording_hash"]);
  if (r.schema_version !== 1 || r.level_version !== 1 || r.tick_rate !== 30) throw new ApiError(422, "unsupported_simulation_version");
  const simulation_version = legacySimulationVersion(r.simulation_version);
  if (r.role !== "a" && r.role !== "b") throw new ApiError(400, "invalid_role");
  const level_id = text(r.level_id, /^[a-z-]{1,40}$/);
  if (!(LEVEL_IDS as readonly string[]).includes(level_id)) throw new ApiError(422, "unknown_level");
  const duration_ticks = integer(r.duration_ticks, 1, 600);
  if (!Array.isArray(r.actions) || r.actions.length < 1 || r.actions.length > 600) throw new ApiError(400, "invalid_actions");
  const actions = r.actions.map(inputAction => {
    const a = object(inputAction); exactKeys(a, ["ticks", "x", "z", "action"]);
    return { ticks: integer(a.ticks, 1, 600), x: integer(a.x, -100, 100), z: integer(a.z, -100, 100), action: boolean(a.action) };
  });
  if (actions.reduce((sum, a) => sum + a.ticks, 0) !== duration_ticks) throw new ApiError(400, "action_duration_mismatch");
  if (!Array.isArray(r.checkpoints) || r.checkpoints.length > 601) throw new ApiError(400, "invalid_checkpoints");
  let previous = -1;
  const checkpoints = r.checkpoints.map(inputCheckpoint => {
    const c = object(inputCheckpoint); exactKeys(c, ["tick", "state_hash"]);
    const tick = integer(c.tick, 0, duration_ticks);
    if (tick <= previous) throw new ApiError(400, "unordered_checkpoints");
    previous = tick;
    return { tick, state_hash: text(c.state_hash, HASH_PATTERN) };
  });
  const o = object(r.outcome); exactKeys(o, ["threw_seed", "caught_seed", "planted_seed"]);
  const result: Recording = {
    schema_version: 1, simulation_version, level_version: 1, tick_rate: 30,
    level_id, role: r.role, duration_ticks, actions, checkpoints, catch_assistance: r.catch_assistance === undefined ? true : boolean(r.catch_assistance),
    final_state_hash: text(r.final_state_hash, HASH_PATTERN), completed: boolean(r.completed),
    outcome: { threw_seed: boolean(o.threw_seed), caught_seed: boolean(o.caught_seed), planted_seed: boolean(o.planted_seed) }
  };
  if (r.source_recording_hash !== undefined) result.source_recording_hash = text(r.source_recording_hash, HASH_PATTERN);
  return result;
}
export async function boundedJson(request: Request, max = MAX_BODY_BYTES): Promise<unknown> {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) throw new ApiError(415, "json_required");
  if (Number(request.headers.get("content-length")) > max) throw new ApiError(413, "body_too_large");
  if (!request.body) throw new ApiError(400, "body_required");
  const reader = request.body.getReader(); const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const part = await reader.read(); if (part.done) break;
      size += part.value.byteLength;
      if (size > max) { await reader.cancel(); throw new ApiError(413, "body_too_large"); }
      chunks.push(part.value);
    }
    const data = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.byteLength; }
    try { return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(data)); }
    catch { throw new ApiError(400, "invalid_json"); }
  } finally { reader.releaseLock(); }
}
export function randomToken(bytes = 32): string {
  return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(bytes)))).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
export async function digest(value: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return [...bytes].map(b => b.toString(16).padStart(2, "0")).join("");
}
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
  if (isObject(value)) return "{" + Object.keys(value).sort().map(key => JSON.stringify(key) + ":" + canonicalJson(value[key])).join(",") + "}";
  return JSON.stringify(value);
}
export function equalHash(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return crypto.subtle.timingSafeEqual(new TextEncoder().encode(a), new TextEncoder().encode(b));
}
