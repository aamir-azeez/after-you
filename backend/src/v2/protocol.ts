import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object, text } from "../protocol";
import definition from "./relay-isles.json";
import initial from "./initial-checkpoint.json";

// This is a pinned authored catalog, not a client-supplied definition registry.
export const RELAY = definition;
export const DEFINITION_HASH = "705b79d266c8acb0b94e7c9955579466654d26492455cca4b6ff27f15684b07b";
export const MAX_RECORDING_BYTES = 49_152;
export const MAX_CHECKPOINT_BYTES = 229_376;
export const MAX_V2_BODY_BYTES = 327_680;
export type Slot = "p0" | "p1";
export type RecordingV2 = {
  schema_version: 2; simulation_version: 2; level_id: string; level_version: 2; definition_hash: string;
  stage_id: string; stage_version: 2; checkpoint_hash: string; role: "a" | "b"; player_slot: Slot;
  tick_rate: 30; duration_ticks: number; catch_assistance: boolean;
  actions: { ticks: number; x: number; z: number; action: boolean }[];
  replay_checks: { tick: number; state_hash: string }[];
  final_state_hash: string; completed: boolean;
  outcome: { threw_seed: boolean; caught_seed: boolean; placed_relay: boolean; planted_seed: boolean; took_seed: boolean };
  source_recording_hash: string; recording_hash: string;
};
export type CheckpointV2 = {
  schema_version: 2; level_id: string; level_version: 2; definition_hash: string; stage_index: number;
  completed_stage_id: string; next_stage_id: string;
  players: Record<Slot, { x: number; z: number; surface_id: string }>;
  latched_bridges: string[]; seed: { status: string; owner: string; socket_id: string };
  previous_checkpoint_hash: string; a_recording_hash: string; b_recording_hash: string; checkpoint_hash: string;
  proof: { previous_checkpoint?: CheckpointV2; a?: RecordingV2; b?: RecordingV2 };
};
export function initialCheckpoint(): CheckpointV2 { return structuredClone(initial) as CheckpointV2; }
export function exact(value: Record<string, unknown>, keys: readonly string[]): void {
  if (Object.keys(value).length !== keys.length || keys.some(key => !Object.hasOwn(value, key))) throw new ApiError(400, "unexpected_fields");
}
function bool(value: unknown): void { if (typeof value !== "boolean") throw new ApiError(400, "invalid_boolean"); }
export function boundedValue(value: unknown, bytes: number): void {
  // Iterative preflight bounds untrusted proof trees before recursive JSON
  // serialization or canonical hashing. A checkpoint has at most two ancestors.
  const pending: { value: unknown; depth: number }[] = [{ value, depth: 0 }];
  let nodes = 0;
  while (pending.length) {
    const item = pending.pop()!;
    if (++nodes > 24_000 || item.depth > 16) throw new ApiError(413, "structure_too_large");
    if (typeof item.value === "string") {
      if (item.value.length > 512) throw new ApiError(400, "invalid_text_length");
    } else if (typeof item.value === "number") {
      if (!Number.isSafeInteger(item.value)) throw new ApiError(400, "invalid_integer");
    } else if (typeof item.value === "object" && item.value !== null) {
      for (const [key, child] of Object.entries(item.value)) {
        if (key.length > 80) throw new ApiError(400, "invalid_field_name");
        pending.push({ value: child, depth: item.depth + 1 });
        if (pending.length > 24_000) throw new ApiError(413, "structure_too_large");
      }
    } else if (item.value !== null && typeof item.value !== "boolean") throw new ApiError(400, "invalid_json_value");
  }
  if (new TextEncoder().encode(JSON.stringify(value)).byteLength > bytes) throw new ApiError(413, "value_too_large");
}
export function stageIndex(id: unknown): number {
  const index = RELAY.stages.findIndex(stage => stage.id === id);
  if (index < 0) throw new ApiError(422, "unknown_stage");
  return index;
}
export function validateCatalog(levelId: unknown, levelVersion: unknown, hash: unknown): void {
  if (levelId !== RELAY.id || levelVersion !== RELAY.version || hash !== DEFINITION_HASH) throw new ApiError(422, "unsupported_chapter");
}
const RECORD_KEYS = ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "stage_id", "stage_version", "checkpoint_hash", "role", "player_slot", "tick_rate", "duration_ticks", "catch_assistance", "actions", "replay_checks", "final_state_hash", "completed", "outcome", "source_recording_hash", "recording_hash"];
export async function recordingV2(value: unknown): Promise<RecordingV2> {
  boundedValue(value, MAX_RECORDING_BYTES);
  const r = object(value); exact(r, RECORD_KEYS);
  if (r.schema_version !== 2 || r.simulation_version !== 2 || r.stage_version !== 2 || r.tick_rate !== 30) throw new ApiError(422, "unsupported_simulation_version");
  validateCatalog(r.level_id, r.level_version, r.definition_hash);
  const stage = RELAY.stages[stageIndex(r.stage_id)];
  if (r.role !== "a" && r.role !== "b") throw new ApiError(400, "invalid_role");
  const expected = r.role === "a" ? stage.first_player_slot : stage.first_player_slot === "p0" ? "p1" : "p0";
  if (r.player_slot !== expected) throw new ApiError(422, "wrong_player_slot");
  const duration = integer(r.duration_ticks, 1, 600);
  bool(r.catch_assistance); bool(r.completed);
  for (const name of ["checkpoint_hash", "final_state_hash", "recording_hash"]) text(r[name], HASH_PATTERN);
  if (r.role === "a" ? r.source_recording_hash !== "" : typeof r.source_recording_hash !== "string" || !HASH_PATTERN.test(r.source_recording_hash)) throw new ApiError(400, "invalid_source_hash");
  if (!Array.isArray(r.actions) || r.actions.length < 1 || r.actions.length > 600) throw new ApiError(400, "invalid_actions");
  let total = 0;
  for (const value of r.actions) {
    const a = object(value); exact(a, ["ticks", "x", "z", "action"]);
    total += integer(a.ticks, 1, 600); integer(a.x, -100, 100); integer(a.z, -100, 100); bool(a.action);
  }
  if (total !== duration) throw new ApiError(400, "action_duration_mismatch");
  if (!Array.isArray(r.replay_checks) || !r.replay_checks.length || r.replay_checks.length > 21) throw new ApiError(400, "invalid_replay_checks");
  let previous = 0;
  for (const value of r.replay_checks) {
    const c = object(value); exact(c, ["tick", "state_hash"]);
    const tick = integer(c.tick, 1, duration); text(c.state_hash, HASH_PATTERN);
    if (tick <= previous) throw new ApiError(400, "unordered_replay_checks");
    previous = tick;
  }
  if (previous !== duration || r.replay_checks.at(-1).state_hash !== r.final_state_hash) throw new ApiError(400, "final_replay_check_mismatch");
  const outcome = object(r.outcome); exact(outcome, ["threw_seed", "caught_seed", "placed_relay", "planted_seed", "took_seed"]);
  for (const value of Object.values(outcome)) bool(value);
  const { recording_hash, ...body } = r;
  if (await digest(canonicalJson(body)) !== recording_hash) throw new ApiError(422, "recording_hash_mismatch");
  // Preserve the submitted JSON value without normalization/default insertion.
  return r as RecordingV2;
}

/** Structural chain verification only: native simulation must still replay it. */
export async function checkpointV2(value: unknown, previous: CheckpointV2, a: RecordingV2, b: RecordingV2): Promise<CheckpointV2> {
  boundedValue(value, MAX_CHECKPOINT_BYTES);
  const c = object(value);
  exact(c, ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "latched_bridges", "seed", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"]);
  validateCatalog(c.level_id, c.level_version, c.definition_hash);
  const index = previous.stage_index + 1;
  if (c.schema_version !== 2 || c.stage_index !== index || index > RELAY.stages.length || c.completed_stage_id !== RELAY.stages[index - 1].id || c.next_stage_id !== (RELAY.stages[index]?.id ?? "")) throw new ApiError(422, "checkpoint_stage_mismatch");
  if (c.previous_checkpoint_hash !== previous.checkpoint_hash || c.a_recording_hash !== a.recording_hash || c.b_recording_hash !== b.recording_hash) throw new ApiError(422, "checkpoint_source_mismatch");
  const proof = object(c.proof); exact(proof, ["previous_checkpoint", "a", "b"]);
  if (canonicalJson(proof.previous_checkpoint) !== canonicalJson(previous) || canonicalJson(proof.a) !== canonicalJson(a) || canonicalJson(proof.b) !== canonicalJson(b)) throw new ApiError(422, "checkpoint_proof_mismatch");
  const players = object(c.players); exact(players, ["p0", "p1"]);
  const surfaces = [...RELAY.islands, ...RELAY.bridges];
  for (const value of Object.values(players)) {
    const p = object(value); exact(p, ["x", "z", "surface_id"]);
    const x = integer(p.x, -10_000, 10_000), z = integer(p.z, -10_000, 10_000);
    const surface = surfaces.find(item => item.id === p.surface_id);
    if (!surface || x < surface.rect_cm[0] || x > surface.rect_cm[2] || z < surface.rect_cm[1] || z > surface.rect_cm[3]) throw new ApiError(422, "checkpoint_surface_mismatch");
  }
  // Relay goals latch their bridge; a garden goal does not. Derive this from
  // the pinned versioned catalog rather than coordinates from test recordings.
  const expectedLatches = RELAY.stages.slice(0, index).filter(stage => stage.goal_action === "place_relay").map(stage => stage.bridge_id);
  if (canonicalJson(c.latched_bridges) !== canonicalJson(expectedLatches)) throw new ApiError(422, "checkpoint_latch_mismatch");
  const seed = object(c.seed); exact(seed, ["status", "owner", "socket_id"]);
  const completed = RELAY.stages[index - 1];
  if (seed.owner !== "" || seed.status !== (completed.goal_action === "place_relay" ? "socket" : "planted") || seed.socket_id !== completed.destination) throw new ApiError(422, "checkpoint_seed_mismatch");
  const { checkpoint_hash, proof: excludedProof, ...body } = c; void excludedProof;
  if (typeof checkpoint_hash !== "string" || !HASH_PATTERN.test(checkpoint_hash) || await digest(canonicalJson(body)) !== checkpoint_hash) throw new ApiError(422, "checkpoint_hash_mismatch");
  return c as CheckpointV2;
}
