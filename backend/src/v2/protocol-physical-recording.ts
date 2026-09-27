import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object, text } from "../protocol";
import { boundedValue, exact, MAX_RECORDING_BYTES } from "./protocol-relay";
import type { ChapterKey, ChapterRecording } from "./chapter-types";

const RECORD_KEYS = ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "stage_id", "stage_version", "checkpoint_hash", "role", "player_slot", "tick_rate", "duration_ticks", "catch_assistance", "actions", "replay_checks", "final_state_hash", "completed", "outcome", "source_recording_hash", "recording_hash"];
const OUTCOMES = ["source_ready", "objective_complete"];
const MAX_TICKS = 900, MAX_REPLAY_CHECKS = 31;
function need(value: unknown, code: string): asserts value { if (!value) throw new ApiError(422, code); }
function bool(value: unknown): void { if (typeof value !== "boolean") throw new ApiError(400, "invalid_boolean"); }
export function physicalAccepted(r: ChapterRecording): boolean { return r.completed === (r.role === "b") && r.outcome.source_ready === true && r.outcome.objective_complete === (r.role === "b"); }

/** Envelope selection comes only from an explicitly registered immutable adapter.
 * This preserves the published six parser and shares no checkpoint semantics. */
export function physicalRecording(definition: { stages: readonly { id: string; first_player_slot: string }[] }, key: Readonly<ChapterKey>, version: 6 | 7): (value: unknown) => Promise<ChapterRecording> {
  return async (value: unknown): Promise<ChapterRecording> => {
    boundedValue(value, MAX_RECORDING_BYTES);
    const r = object(value); exact(r, RECORD_KEYS); need(r.level_id === key.level_id && r.level_version === key.level_version && r.definition_hash === key.definition_hash, "unsupported_chapter");
    need(r.schema_version === version && r.simulation_version === version && r.stage_version === 1 && r.tick_rate === 30, "unsupported_simulation_version");
    const stage = definition.stages.find(stage => stage.id === r.stage_id); need(stage, "unknown_stage");
    need(r.role === "a" || r.role === "b", "invalid_role");
    need(r.player_slot === (r.role === "a" ? stage.first_player_slot : stage.first_player_slot === "p0" ? "p1" : "p0"), "wrong_player_slot");
    const duration = integer(r.duration_ticks, 1, MAX_TICKS); bool(r.catch_assistance); bool(r.completed);
    for (const name of ["checkpoint_hash", "final_state_hash", "recording_hash"]) text(r[name], HASH_PATTERN);
    need(r.role === "a" ? r.source_recording_hash === "" : typeof r.source_recording_hash === "string" && HASH_PATTERN.test(r.source_recording_hash), "invalid_source_hash");
    need(Array.isArray(r.actions) && r.actions.length > 0 && r.actions.length <= MAX_TICKS, "invalid_actions");
    let ticks = 0;
    for (const value of r.actions) {
      const action = object(value); exact(action, ["ticks", "x", "z", "action"]);
      ticks += integer(action.ticks, 1, MAX_TICKS); integer(action.x, -100, 100); integer(action.z, -100, 100); bool(action.action);
    }
    need(ticks === duration, "action_duration_mismatch");
    need(Array.isArray(r.replay_checks) && r.replay_checks.length > 0 && r.replay_checks.length <= MAX_REPLAY_CHECKS, "invalid_replay_checks");
    let previous = 0;
    for (const value of r.replay_checks) {
      const check = object(value); exact(check, ["tick", "state_hash"]);
      const tick = integer(check.tick, 1, duration); text(check.state_hash, HASH_PATTERN);
      need(tick > previous, "unordered_replay_checks"); previous = tick;
    }
    need(previous === duration && r.replay_checks.at(-1).state_hash === r.final_state_hash, "final_replay_check_mismatch");
    const outcome = object(r.outcome); exact(outcome, OUTCOMES); Object.values(outcome).forEach(bool);
    const { recording_hash, ...body } = r; need(await digest(canonicalJson(body)) === recording_hash, "recording_hash_mismatch");
    return r as ChapterRecording;
  };
}
