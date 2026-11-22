import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object, text } from "../protocol";
import { boundedValue, exact, MAX_CHECKPOINT_BYTES, MAX_RECORDING_BYTES, MAX_V2_BODY_BYTES } from "./protocol-relay";
import { carryOver, comfortRules, openTurns, type ChapterKey, type ChapterLimits, type ChapterRecording } from "./chapter-types";
import { MAX_ROW_BYTES } from "./row-bound";
import { isPacked, packedKeys, unpackRecording } from "./recording-codec";
import { CARRY_RECORD_KEYS, MAX_OPEN_TURN_TICKS, OPEN_TURNS_BRANCHES, carryFits, isFingerprint, openBodyLimits, openTurnLimits, packedRecordingBytes, type OpenTurns } from "./open-turns";

const RECORD_KEYS = ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "stage_id", "stage_version", "checkpoint_hash", "role", "player_slot", "tick_rate", "duration_ticks", "catch_assistance", "actions", "replay_checks", "final_state_hash", "completed", "outcome", "source_recording_hash", "recording_hash"];
const PACKED_KEYS = packedKeys(RECORD_KEYS);
/** An open turns fingerprint (open-turns.ts): a packed record without `packed`. */
const FINGERPRINT_KEYS = PACKED_KEYS.filter(key => key !== "packed");
/** Carry-over turns (rules 18 to 21) add their hand-off header fields to each form (open-turns.ts CARRY_RECORD_KEYS). */
const CARRY_KEYS = { record: [...RECORD_KEYS, ...CARRY_RECORD_KEYS], packed: [...PACKED_KEYS, ...CARRY_RECORD_KEYS], print: [...FINGERPRINT_KEYS, ...CARRY_RECORD_KEYS] };
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
  // The receiver waits out the recorded first turn, so it needs the longer cap. Open turns (open-turns.ts) play every
  // turn alongside its memory with the same limit, so there the two may be equal, and turns may be longer.
  const open = openTurns(definition.simulation_version), shortestB = open ? (a_ticks as number) : (a_ticks as number) + 1;
  if (!Number.isSafeInteger(a_ticks) || !Number.isSafeInteger(b_ticks) || (a_ticks as number) < 1 || (b_ticks as number) < shortestB || (b_ticks as number) > (open ? MAX_OPEN_TURN_TICKS : 9_000)) throw new Error("invalid turn_limits");
  return { a_ticks: a_ticks as number, b_ticks: b_ticks as number };
}
/** The published comfort bounds grown by how much longer the turns are. */
export function scaledLimits(turns: Readonly<TurnLimits>): ChapterLimits {
  const factor = Math.max(1, turns.a_ticks / MAX_TICKS, turns.b_ticks / 1200);
  const scale = (published: number) => Math.ceil(published * factor);
  return { recording_bytes: scale(65_536), recording_values: scale(24_000), checkpoint_bytes: scale(MAX_CHECKPOINT_BYTES), checkpoint_values: scale(24_000),
    turn_body_bytes: scale(MAX_V2_BODY_BYTES), turn_body_values: scale(32_000) };
}

/** Open turns on a definition with no turn_limits: the published comfort recording bounds. */
export const COMFORT_RECORDING: Readonly<ChapterLimits> = { recording_bytes: 65_536, recording_values: 24_000, checkpoint_bytes: MAX_CHECKPOINT_BYTES, checkpoint_values: 24_000, turn_body_bytes: 0, turn_body_values: 0 };
/**
 * An open turns chapter (open-turns.ts) on the physical record format, the one setup every family's adapter uses: every
 * turn packed and as long as the second turn limit, a flat checkpoint, so no bound grows with the stages; the branches
 * that fit (at most `maxBranches`); and a recording parser that takes packed turns only, before any other check (a
 * stored row may be a turn's fingerprint). Throws at module load when the turns outgrow a room.
 */
export function openPhysicalRecording(definition: { simulation_version?: number; turn_limits?: unknown; stages: readonly { id: string; first_player_slot: string; turn_cap?: unknown }[] },
  key: Readonly<ChapterKey>, version: 6 | 7, supported: readonly number[], maxBranches = OPEN_TURNS_BRANCHES):
  { open: OpenTurns; limits: ChapterLimits; recording: (value: unknown, stored?: boolean) => Promise<ChapterRecording> } {
  const turns = turnLimits(definition);
  const carry = carryOver(definition.simulation_version);
  const open = openTurnLimits(definition.stages, packedRecordingBytes(turns?.b_ticks ?? 1200), maxBranches, carry);
  const limits = { ...(turns ? scaledLimits(turns) : COMFORT_RECORDING), ...openBodyLimits(open) };
  checkTurnBounds(limits, open.branches);
  const parsed = physicalRecording(definition, key, version, supported, undefined, turns, limits, true, carry);
  return { open, limits, recording: (value: unknown, stored = false) => {
    if (!stored) need(value !== null && typeof value === "object" && isPacked(value), "packed_recording_required");
    return parsed(value, stored);
  } };
}

/**
 * A completed stage's latched routes and levers against the checkpoint before it, the one check both physical families
 * use (the journey on every rules, the cooperative family on open turns): routes are sorted, unique strings, keep every
 * earlier one and add only this stage's gates' routes; levers name only levers of the stages so far, keep every earlier
 * one, and change only this stage's. Returns the routes, then and now, and the levers.
 */
export function checkRoutesAndLevers(mechanisms: Record<string, unknown>, prior: Record<string, unknown>,
  stages: readonly { gates: readonly { route_id: string }[]; levers: readonly { id: string }[] }[], index: number): { routes: string[]; previousRoutes: string[]; levers: Record<string, unknown> } {
  const stage = stages[index - 1];
  const levers = object(mechanisms.levers), priorLevers = object(prior.levers), leverIds = stages.slice(0, index).flatMap(s => s.levers.map(lever => lever.id));
  need(Object.keys(levers).every(id => leverIds.includes(id)) && Object.keys(priorLevers).every(id => id in levers), "checkpoint_mechanism_mismatch");
  for (const id of Object.keys(levers)) need(typeof levers[id] === "boolean" && (stage.levers.some(lever => lever.id === id) || levers[id] === priorLevers[id]), "checkpoint_mechanism_mismatch");
  const routes = mechanisms.latched_bridges, previousRoutes = prior.latched_bridges as string[];
  need(Array.isArray(routes) && routes.every(route => typeof route === "string") && canonicalJson(routes) === canonicalJson([...new Set(routes)].sort()), "checkpoint_mechanism_mismatch");
  const allowed = new Set([...previousRoutes, ...stage.gates.map(gate => gate.route_id)]);
  need(routes.every(route => allowed.has(route)) && previousRoutes.every(route => routes.includes(route)), "checkpoint_mechanism_mismatch");
  return { routes: routes as string[], previousRoutes, levers };
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
 * This preserves the published six parser and shares no checkpoint semantics.
 * `stored` (open turns only): the record is a stored row, which may be a turn's fingerprint (open-turns.ts); its header
 * is checked as a turn's is, and its hash, which covers the runs it no longer holds, is taken as stored.
 * `carry` (carry-over turns): every turn names its hand-off (open-turns.ts carryFits) and a stage's first turn may be either pip's. */
export function physicalRecording(definition: { stages: readonly { id: string; first_player_slot: string }[] }, key: Readonly<ChapterKey>, version: 6 | 7 | 8, supported: readonly number[] = [version], maxTicks = Number.MAX_SAFE_INTEGER,
  turns?: Readonly<TurnLimits>, limits?: Readonly<ChapterLimits>, open = false, carry = false): (value: unknown, stored?: boolean) => Promise<ChapterRecording> {
  return async (value: unknown, stored = false): Promise<ChapterRecording> => {
    const comfort = value !== null && typeof value === "object" && "simulation_version" in value && comfortRules(value.simulation_version) && supported.includes(value.simulation_version as number);
    boundedValue(value, comfort ? limits?.recording_bytes ?? 65_536 : MAX_RECORDING_BYTES, comfort ? limits?.recording_values : undefined);
    // A packed record (v2/recording-codec.ts) carries its runs and checks as one string; whether the room may take it is the room's call.
    const r = object(value), packed = isPacked(r), print = open && stored && isFingerprint(r); exact(r, print ? (carry ? CARRY_KEYS.print : FINGERPRINT_KEYS) : packed ? (carry ? CARRY_KEYS.packed : PACKED_KEYS) : carry ? CARRY_KEYS.record : RECORD_KEYS); need(r.level_id === key.level_id && r.level_version === key.level_version && r.definition_hash === key.definition_hash, "unsupported_chapter");
    need(r.schema_version === version && supported.includes(r.simulation_version as number) && r.stage_version === 1 && r.tick_rate === 30, "unsupported_simulation_version");
    const stage = definition.stages.find(stage => stage.id === r.stage_id); need(stage, "unknown_stage");
    need(r.role === "a" || r.role === "b", "invalid_role");
    // Open turns (open-turns.ts): a later turn is either pip's, as its place in the stage says (the room and the checkpoint check it);
    // on carry-over turns the first turn too, as the checkpoint before the stage says.
    need(r.player_slot === (r.role === "a" ? stage.first_player_slot : stage.first_player_slot === "p0" ? "p1" : "p0") || open && (r.role === "b" || carry) && (r.player_slot === "p0" || r.player_slot === "p1"), "wrong_player_slot");
    // Open turns: every turn has the second turn's limit.
    const role = open ? "b" : r.role;
    const published = comfortRules(r.simulation_version) && role === "b" ? 1200 : MAX_TICKS;
    const limit = Math.min(turns ? (role === "b" ? turns.b_ticks : turns.a_ticks) : published, maxTicks);
    const duration = integer(r.duration_ticks, 1, limit); bool(r.catch_assistance); bool(r.completed);
    for (const name of ["checkpoint_hash", "final_state_hash", "recording_hash", ...(carry ? ["start_hash", "handoff_hash"] : [])]) text(r[name], HASH_PATTERN);
    // Carry-over turns: a hand-off inside the turn before (never longer than this limit); a first turn hands off at 0 from its own start.
    if (carry) { integer(r.handoff_tick, 0, limit); need(r.role !== "a" || carryFits(r as ChapterRecording, null, null), "invalid_handoff"); }
    need(r.role === "a" ? r.source_recording_hash === "" : typeof r.source_recording_hash === "string" && HASH_PATTERN.test(r.source_recording_hash), "invalid_source_hash");
    // Packed runs and checks come back canonical, on the implied check ticks and ending on final_state_hash.
    if (print) { exact(object(r.outcome), OUTCOMES); Object.values(object(r.outcome)).forEach(bool); return r as ChapterRecording; }
    if (packed) { unpackRecording(r.packed, duration, r.final_state_hash as string, limit); return hashed(r); }
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
    return hashed(r);
  };
}
async function hashed(r: Record<string, unknown>): Promise<ChapterRecording> {
  const outcome = object(r.outcome); exact(outcome, OUTCOMES); Object.values(outcome).forEach(bool);
  const { recording_hash, ...body } = r; need(await digest(canonicalJson(body)) === recording_hash, "recording_hash_mismatch");
  return r as ChapterRecording;
}
