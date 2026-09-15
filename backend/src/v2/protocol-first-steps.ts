import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object, text } from "../protocol";
import { boundedValue, exact, MAX_RECORDING_BYTES, MAX_CHECKPOINT_BYTES } from "./protocol-relay";
import type { ChapterAdapter, ChapterCheckpoint, ChapterRecording } from "./chapter-types";
import definition from "./first-steps.json";
import initial from "./first-steps-initial.json";

export const FIRST_STEPS = definition;
export const FIRST_STEPS_HASH = "72ddc480e0f493c983fb012ce7bfa20a9cb1984ef7263d236c11509a527df85b";
const key = Object.freeze({ level_id: definition.id, level_version: 1, definition_hash: FIRST_STEPS_HASH });
const RECORD_KEYS = ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "stage_id", "stage_version", "checkpoint_hash", "role", "player_slot", "tick_rate", "duration_ticks", "catch_assistance", "actions", "replay_checks", "final_state_hash", "completed", "outcome", "source_recording_hash", "recording_hash"];
const OUTCOMES = ["supplied_power", "boarded_lift", "reached_loft", "took_seed", "threw_seed", "activated_garden", "caught_seed", "planted_seed"];
const CHECKPOINT_KEYS = ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "seed", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"];
function need(value: unknown, code: string): asserts value { if (!value) throw new ApiError(422, code); }
function bool(value: unknown): void { if (typeof value !== "boolean") throw new ApiError(400, "invalid_boolean"); }
function catalog(value: Record<string, unknown>): void { need(value.level_id === key.level_id && value.level_version === key.level_version && value.definition_hash === key.definition_hash, "unsupported_chapter"); }

async function recording(value: unknown): Promise<ChapterRecording> {
  boundedValue(value, MAX_RECORDING_BYTES);
  const r = object(value); exact(r, RECORD_KEYS); catalog(r);
  need(r.schema_version === 4 && r.simulation_version === 4 && r.stage_version === 1 && r.tick_rate === 30, "unsupported_simulation_version");
  const stage = definition.stages.find(stage => stage.id === r.stage_id);
  need(stage, "unknown_stage");
  need(r.role === "a" || r.role === "b", "invalid_role");
  need(r.player_slot === (r.role === "a" ? stage.first_player_slot : stage.first_player_slot === "p0" ? "p1" : "p0"), "wrong_player_slot");
  const duration = integer(r.duration_ticks, 1, 600);
  bool(r.catch_assistance); bool(r.completed);
  for (const name of ["checkpoint_hash", "final_state_hash", "recording_hash"]) text(r[name], HASH_PATTERN);
  need(r.role === "a" ? r.source_recording_hash === "" : typeof r.source_recording_hash === "string" && HASH_PATTERN.test(r.source_recording_hash), "invalid_source_hash");
  need(Array.isArray(r.actions) && r.actions.length > 0 && r.actions.length <= 600, "invalid_actions");
  let ticks = 0;
  for (const value of r.actions) {
    const action = object(value); exact(action, ["ticks", "x", "z", "action"]);
    ticks += integer(action.ticks, 1, 600); integer(action.x, -100, 100); integer(action.z, -100, 100); bool(action.action);
  }
  need(ticks === duration, "action_duration_mismatch");
  need(Array.isArray(r.replay_checks) && r.replay_checks.length > 0 && r.replay_checks.length <= 21, "invalid_replay_checks");
  let previous = 0;
  for (const value of r.replay_checks) {
    const check = object(value); exact(check, ["tick", "state_hash"]);
    const tick = integer(check.tick, 1, duration); text(check.state_hash, HASH_PATTERN);
    need(tick > previous, "unordered_replay_checks"); previous = tick;
  }
  need(previous === duration && r.replay_checks.at(-1).state_hash === r.final_state_hash, "final_replay_check_mismatch");
  const outcome = object(r.outcome); exact(outcome, OUTCOMES); Object.values(outcome).forEach(bool);
  const { recording_hash, ...body } = r;
  need(await digest(canonicalJson(body)) === recording_hash, "recording_hash_mismatch");
  return r as ChapterRecording;
}

function accepted(r: ChapterRecording): boolean {
  if (r.completed !== (r.role === "b")) return false;
  const first = r.stage_id === definition.stages[0].id;
  const enabled = first ? (r.role === "a" ? ["supplied_power"] : ["supplied_power", "boarded_lift", "reached_loft"]) :
    (r.role === "a" ? ["took_seed", "threw_seed", "activated_garden"] : ["took_seed", "threw_seed", "activated_garden", "caught_seed", "planted_seed"]);
  return OUTCOMES.every(name => r.outcome[name] === enabled.includes(name));
}

async function checkpoint(value: unknown, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording): Promise<ChapterCheckpoint> {
  boundedValue(value, MAX_CHECKPOINT_BYTES);
  const c = object(value); exact(c, CHECKPOINT_KEYS); catalog(c);
  const index = previous.stage_index + 1;
  need(c.schema_version === 4 && c.stage_index === index && index <= definition.stages.length && c.completed_stage_id === definition.stages[index - 1].id && c.next_stage_id === (definition.stages[index]?.id ?? ""), "checkpoint_stage_mismatch");
  need(c.previous_checkpoint_hash === previous.checkpoint_hash && c.a_recording_hash === a.recording_hash && c.b_recording_hash === b.recording_hash, "checkpoint_source_mismatch");
  const proof = object(c.proof); exact(proof, ["checkpoint", "a", "b"]);
  need(canonicalJson(proof.checkpoint) === canonicalJson(previous) && canonicalJson(proof.a) === canonicalJson(a) && canonicalJson(proof.b) === canonicalJson(b), "checkpoint_proof_mismatch");
  const players = object(c.players); exact(players, ["p0", "p1"]);
  const surfaces = [...definition.islands, { id: definition.lift.id, rect_cm: definition.lift.rect_cm, height_cm: definition.lift.top_height_cm }];
  for (const value of Object.values(players)) {
    const p = object(value); exact(p, ["x", "z", "height", "surface_id"]);
    const x = integer(p.x, -10_000, 10_000), z = integer(p.z, -10_000, 10_000), height = integer(p.height, 0, definition.lift.top_height_cm);
    const surface = surfaces.find(surface => surface.id === p.surface_id);
    need(surface && height === surface.height_cm && x >= surface.rect_cm[0] && x <= surface.rect_cm[2] && z >= surface.rect_cm[1] && z <= surface.rect_cm[3], "checkpoint_surface_mismatch");
  }
  const mechanisms = object(c.mechanisms); exact(mechanisms, ["lift", "garden_open", "loft_open"]);
  const lift = object(mechanisms.lift); exact(lift, ["height_cm", "phase", "progress_ticks", "boarded_slot"]);
  need(lift.height_cm === definition.lift.top_height_cm && lift.phase === "upper" && lift.progress_ticks === definition.lift.rise_ticks && lift.boarded_slot === "p1" && mechanisms.loft_open === true && mechanisms.garden_open === (index === 2), "checkpoint_mechanism_mismatch");
  const socket = definition.sockets.find(socket => socket.id === (index === 1 ? "seed-pedestal" : "garden"))!;
  const seed = object(c.seed); exact(seed, ["status", "owner", "socket_id", "x", "z", "height"]);
  need(seed.status === (index === 1 ? "pedestal" : "planted") && seed.owner === "" && seed.socket_id === socket.id && seed.x === socket.position_cm[0] && seed.z === socket.position_cm[1] && seed.height === socket.seed_height_cm, "checkpoint_seed_mismatch");
  const { checkpoint_hash, proof: ignoredProof, ...body } = c; void ignoredProof;
  need(typeof checkpoint_hash === "string" && HASH_PATTERN.test(checkpoint_hash) && await digest(canonicalJson(body)) === checkpoint_hash, "checkpoint_hash_mismatch");
  return c as ChapterCheckpoint;
}

/** New simulation mechanics, explicitly distinct from Relay's seed-only rules. */
export const adapter: ChapterAdapter = { key, recording_version: 4, simulation_version: 4, premium: false, stages: definition.stages,
  initial: () => structuredClone(initial), recording, checkpoint, accepted };
