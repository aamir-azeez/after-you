import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object, text } from "../protocol";
import { boundedValue, exact, MAX_CHECKPOINT_BYTES, MAX_RECORDING_BYTES, MAX_V2_BODY_BYTES } from "./protocol-relay";
import { comfortRules, type ChapterKey, type ChapterLimits, type ChapterRecording } from "./chapter-types";
import { MAX_ROW_BYTES } from "./row-bound";

const RECORD_KEYS = ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "stage_id", "stage_version", "checkpoint_hash", "role", "player_slot", "tick_rate", "duration_ticks", "catch_assistance", "actions", "replay_checks", "final_state_hash", "completed", "outcome", "source_recording_hash", "recording_hash"];
const OUTCOMES = ["source_ready", "objective_complete"];
const MAX_TICKS = 900, MAX_REPLAY_CHECKS = 31;
function need(value: unknown, code: string): asserts value { if (!value) throw new ApiError(422, code); }
function bool(value: unknown): void { if (typeof value !== "boolean") throw new ApiError(400, "invalid_boolean"); }
export function physicalAccepted(r: ChapterRecording): boolean { return r.completed === (r.role === "b") && r.outcome.source_ready === true && r.outcome.objective_complete === (r.role === "b"); }

/** Turn lengths a pinned definition declares for itself (rules 9 and later, as
 * the native runtime reads them). Absent: the published 900 and 1,200 ticks. */
export type TurnLimits = { a_ticks: number; b_ticks: number };
export function turnLimits(definition: { simulation_version?: number; turn_limits?: unknown }): TurnLimits | undefined {
  if (definition.turn_limits === undefined || !(typeof definition.simulation_version === "number" && definition.simulation_version >= 9)) return undefined;
  const { a_ticks, b_ticks } = (definition.turn_limits ?? {}) as Record<string, unknown>;
  // The receiver waits out the recorded first turn, so it needs the longer cap.
  if (!Number.isSafeInteger(a_ticks) || !Number.isSafeInteger(b_ticks) || (a_ticks as number) < 1 || (b_ticks as number) <= (a_ticks as number) || (b_ticks as number) > 9_000) throw new Error("invalid turn_limits");
  return { a_ticks: a_ticks as number, b_ticks: b_ticks as number };
}
/** The published comfort bounds grown by how much longer the turns are. */
export function scaledLimits(turns: Readonly<TurnLimits>): ChapterLimits {
  const factor = Math.max(1, turns.a_ticks / MAX_TICKS, turns.b_ticks / 1200);
  const scale = (published: number) => Math.ceil(published * factor);
  return { recording_bytes: scale(65_536), recording_values: scale(24_000), checkpoint_bytes: scale(MAX_CHECKPOINT_BYTES), checkpoint_values: scale(24_000),
    turn_body_bytes: scale(MAX_V2_BODY_BYTES), turn_body_values: scale(32_000) };
}

/** Room keys, ids and counters stored beside a pair's records and checkpoint. */
export const ROW_ENVELOPE_BYTES = 16_384;
/** A pair row holds both records and the checkpoint that proves them, and
 * MAX_ROW_BYTES bounds every row. Bounds grown for longer turns must keep the
 * widest accepted pair inside it, and the chapter must cap its branches so its
 * replay archive and room snapshot stay inside theirs. Throws at module load. */
export function checkTurnBounds(limits: Readonly<ChapterLimits>, maxBranches: number | undefined): void {
  const pair = limits.checkpoint_bytes + 2 * (limits.recording_bytes ?? 65_536) + ROW_ENVELOPE_BYTES;
  if (pair > MAX_ROW_BYTES) throw new Error("turn_limits outgrow the room row bound");
  if (!Number.isSafeInteger(maxBranches) || (maxBranches as number) < 1) throw new Error("turn_limits need max_branches");
}

/** Envelope selection comes only from an explicitly registered immutable adapter.
 * This preserves the published six parser and shares no checkpoint semantics. */
export function physicalRecording(definition: { stages: readonly { id: string; first_player_slot: string }[] }, key: Readonly<ChapterKey>, version: 6 | 7 | 8, supported: readonly number[] = [version], maxTicks = Number.MAX_SAFE_INTEGER,
  turns?: Readonly<TurnLimits>, limits?: Readonly<ChapterLimits>): (value: unknown) => Promise<ChapterRecording> {
  return async (value: unknown): Promise<ChapterRecording> => {
    const comfort = value !== null && typeof value === "object" && "simulation_version" in value && comfortRules(value.simulation_version) && supported.includes(value.simulation_version as number);
    boundedValue(value, comfort ? limits?.recording_bytes ?? 65_536 : MAX_RECORDING_BYTES, comfort ? limits?.recording_values : undefined);
    const r = object(value); exact(r, RECORD_KEYS); need(r.level_id === key.level_id && r.level_version === key.level_version && r.definition_hash === key.definition_hash, "unsupported_chapter");
    need(r.schema_version === version && supported.includes(r.simulation_version as number) && r.stage_version === 1 && r.tick_rate === 30, "unsupported_simulation_version");
    const stage = definition.stages.find(stage => stage.id === r.stage_id); need(stage, "unknown_stage");
    need(r.role === "a" || r.role === "b", "invalid_role");
    need(r.player_slot === (r.role === "a" ? stage.first_player_slot : stage.first_player_slot === "p0" ? "p1" : "p0"), "wrong_player_slot");
    const published = comfortRules(r.simulation_version) && r.role === "b" ? 1200 : MAX_TICKS;
    const limit = Math.min(turns ? (r.role === "b" ? turns.b_ticks : turns.a_ticks) : published, maxTicks);
    const duration = integer(r.duration_ticks, 1, limit); bool(r.catch_assistance); bool(r.completed);
    for (const name of ["checkpoint_hash", "final_state_hash", "recording_hash"]) text(r[name], HASH_PATTERN);
    need(r.role === "a" ? r.source_recording_hash === "" : typeof r.source_recording_hash === "string" && HASH_PATTERN.test(r.source_recording_hash), "invalid_source_hash");
    need(Array.isArray(r.actions) && r.actions.length > 0 && r.actions.length <= limit, "invalid_actions");
    let ticks = 0;
    for (const value of r.actions) {
      const action = object(value); exact(action, ["ticks", "x", "z", "action"]);
      ticks += integer(action.ticks, 1, limit); integer(action.x, -100, 100); integer(action.z, -100, 100); bool(action.action);
    }
    need(ticks === duration, "action_duration_mismatch");
    // One check a second and one at the end, as two_pair_proof.gd counts them.
    const checks = turns ? Math.floor(limit / 30) + 1 : limit === 1200 ? 41 : MAX_REPLAY_CHECKS;
    need(Array.isArray(r.replay_checks) && r.replay_checks.length > 0 && r.replay_checks.length <= checks, "invalid_replay_checks");
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
