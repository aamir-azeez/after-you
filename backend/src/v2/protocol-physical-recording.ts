import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object, text } from "../protocol";
import { boundedValue, exact, MAX_CHECKPOINT_BYTES, MAX_RECORDING_BYTES, MAX_V2_BODY_BYTES } from "./protocol-relay";
import { comfortRules, type ChapterKey, type ChapterLimits, type ChapterRecording } from "./chapter-types";
import { MAX_PHOTOS, MAX_REPLAY_ARCHIVE_BYTES, MAX_ROOM_V2_ARCHIVE_BYTES, MAX_ROW_BYTES } from "./row-bound";
import { MAX_PHOTO_BYTES } from "./photo-image";

const RECORD_KEYS = ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "stage_id", "stage_version", "checkpoint_hash", "role", "player_slot", "tick_rate", "duration_ticks", "catch_assistance", "actions", "replay_checks", "final_state_hash", "completed", "outcome", "source_recording_hash", "recording_hash"];
const OUTCOMES = ["source_ready", "objective_complete"];
const MAX_TICKS = 900, MAX_REPLAY_CHECKS = 31;
function need(value: unknown, code: string): asserts value { if (!value) throw new ApiError(422, code); }
function bool(value: unknown): void { if (typeof value !== "boolean") throw new ApiError(400, "invalid_boolean"); }
export function physicalAccepted(r: ChapterRecording): boolean { return r.completed === (r.role === "b") && r.outcome.source_ready === true && r.outcome.objective_complete === (r.role === "b"); }

/** Turn lengths a pinned definition declares for itself (rules 9 and later, as
 * the native runtime reads them). Absent: the published 900 and 1,200 ticks. */
export type TurnLimits = { a_ticks: number; b_ticks: number };
type Declaring = { simulation_version?: number; turn_limits?: unknown; input_rules?: unknown };
const declares = (definition: Declaring) => typeof definition.simulation_version === "number" && definition.simulation_version >= 9;
export function turnLimits(definition: Declaring): TurnLimits | undefined {
  if (definition.turn_limits === undefined || !declares(definition)) return undefined;
  const { a_ticks, b_ticks } = (definition.turn_limits ?? {}) as Record<string, unknown>;
  // The receiver waits out the recorded first turn, so it needs the longer cap.
  const cap = definition.input_rules === undefined ? 9_000 : LONG_TURN_TICKS;
  if (!Number.isSafeInteger(a_ticks) || !Number.isSafeInteger(b_ticks) || (a_ticks as number) < 1 || (b_ticks as number) <= (a_ticks as number) || (b_ticks as number) > cap) throw new Error("invalid turn_limits");
  return { a_ticks: a_ticks as number, b_ticks: b_ticks as number };
}

/** Capped input, as game/core/physical/runtime.gd INPUT_RULES plays it: a turn
 * records at most one input change every change_ticks ticks on average, after
 * a starting allowance of burst changes (reserve only orders the stick and the
 * button inside that allowance). A definition declaring input_rules may
 * declare turns up to LONG_TURN_TICKS (15 minutes); no published one does. */
export type InputRules = { change_ticks: number; burst: number; reserve: number };
export const INPUT_RULES: Readonly<Record<number, Readonly<InputRules>>> = Object.freeze({ 1: Object.freeze({ change_ticks: 10, burst: 800, reserve: 30 }) });
export const LONG_TURN_TICKS = 27_000;
export function inputRules(definition: Declaring): Readonly<InputRules> | undefined {
  if (definition.input_rules === undefined || !declares(definition)) return undefined;
  const rules = Number.isSafeInteger(definition.input_rules) ? INPUT_RULES[definition.input_rules as number] : undefined;
  if (!rules) throw new Error("invalid input_rules");
  return rules;
}
/** The most action entries a turn of `ticks` can record under `rules`: the first, the allowance and one per change_ticks. */
export function maxActionEntries(rules: Readonly<InputRules>, ticks: number): number {
  return Math.min(ticks, 1 + rules.burst + Math.floor(ticks / rules.change_ticks));
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

/** Everything in a stored recording but its action entries and replay checks
 * (four hashes, the ids, flags and keys), past its two ids: about 650 bytes measured. */
const RECORDING_FIXED_BYTES = 1_024;
/** The widest stored action entry, {"action":false,"ticks":N,"x":-100,"z":-100}, with its comma. */
const entryBytes = (ticks: number) => 44 + String(ticks).length;
/** The widest stored replay check, {"state_hash":"<64 hex>","tick":N}, with its comma. */
const checkBytes = (ticks: number) => 90 + String(ticks).length;
/** A room snapshot (snapshot.ts) measures each row with its data as a JSON string, every quote escaped:
 * eight more bytes an entry, six a check, and at most twice the rest. */
const ESCAPED_ENTRY_BYTES = 8, ESCAPED_CHECK_BYTES = 6, ESCAPED_REST = 2;
/** Past the records they nest, a checkpoint holds positions and mechanisms about as wide as the initial one, plus its hashes and keys. */
const CHECKPOINT_FIXED_BYTES = 1_024;
/** A pair row's own keys, and a turn row's, around the records they hold. */
const PAIR_KEYS_BYTES = 256;

/** The widest JSON a capped turn of `ticks` can store: every allowed change, every replay check, all at their widest. */
export function widestRecordingBytes(rules: Readonly<InputRules>, ticks: number, idBytes: number): number {
  return RECORDING_FIXED_BYTES + idBytes + maxActionEntries(rules, ticks) * entryBytes(ticks) + (Math.floor(ticks / 30) + 1) * checkBytes(ticks);
}
/** The same record inside a room snapshot row, its quotes escaped. */
function escapedRecordingBytes(rules: Readonly<InputRules>, ticks: number, idBytes: number): number {
  return widestRecordingBytes(rules, ticks, idBytes) + maxActionEntries(rules, ticks) * ESCAPED_ENTRY_BYTES + (Math.floor(ticks / 30) + 1) * ESCAPED_CHECK_BYTES +
    (ESCAPED_REST - 1) * (RECORDING_FIXED_BYTES + idBytes);
}
/** The same turn's values as boundedValue counts them: the record and its leaves, five per entry, three per check. */
export function widestRecordingValues(rules: Readonly<InputRules>, ticks: number): number {
  return 32 + 5 * maxActionEntries(rules, ticks) + 3 * (Math.floor(ticks / 30) + 1);
}
export type LongTurnShape = { turns: Readonly<TurnLimits>; rules: Readonly<InputRules>; stages: number; initial_bytes: number; id_bytes: number };
/** The widest row each stored thing of a capped chapter can be, honestly played: a stage-k checkpoint nests
 * every earlier stage's checkpoint and both records, and a pair row holds both records beside the checkpoint
 * that holds them again, so the last stage's pair row is the widest row. */
export function longTurnRows(shape: Readonly<LongTurnShape>, escaped = false): { recording: number; checkpoint: number; pair: number; branch: number } {
  const record = escaped ? escapedRecordingBytes : widestRecordingBytes, rest = escaped ? ESCAPED_REST : 1;
  const a = record(shape.rules, shape.turns.a_ticks, shape.id_bytes), b = record(shape.rules, shape.turns.b_ticks, shape.id_bytes);
  const initial = rest * shape.initial_bytes, fixed = rest * CHECKPOINT_FIXED_BYTES, keys = rest * PAIR_KEYS_BYTES;
  const checkpoint = (stage: number) => initial + stage * (initial + fixed + a + b);
  let branch = 0;
  for (let stage = 1; stage <= shape.stages; stage++) branch += keys + a + b + checkpoint(stage) + 2 * keys + a + b;
  return { recording: Math.max(a, b), checkpoint: checkpoint(shape.stages), pair: keys + a + b + checkpoint(shape.stages), branch };
}
/** Bounds for a capped chapter. Its records are bounded by what the cap lets them hold; a checkpoint
 * or a receiver's turn only by the room row, and the room checks each row's real size before it
 * writes it (room.ts commitTurn), so an oversized turn is refused there with turn_too_large. */
export function longTurnLimits(shape: Readonly<LongTurnShape>): ChapterLimits {
  const longest = Math.max(shape.turns.a_ticks, shape.turns.b_ticks), rows = longTurnRows(shape);
  // A row's values: a record's entries take about 7.2 bytes a value at their narrowest, so a row holds
  // fewer than one a 7 bytes; the byte bounds, not this, limit how many entries a record has.
  const values = Math.ceil(MAX_ROW_BYTES / 7);
  return { recording_bytes: rows.recording, recording_values: widestRecordingValues(shape.rules, longest),
    checkpoint_bytes: MAX_ROW_BYTES, checkpoint_values: values, turn_body_bytes: MAX_ROW_BYTES, turn_body_values: values };
}
/** The archive bounds a room's history must stay inside: the replay archive (replay-transfer.ts) and, beside photos, the room snapshot (snapshot.ts). */
export type ArchiveBounds = { replay_archive_bytes: number; room_archive_bytes: number; photo_row_bytes: number; max_photos: number };
export const ARCHIVE_BOUNDS: Readonly<ArchiveBounds> = Object.freeze({ replay_archive_bytes: MAX_REPLAY_ARCHIVE_BYTES, room_archive_bytes: MAX_ROOM_V2_ARCHIVE_BYTES - 4096,
  // A photo row: the base64 JPEG and its ids and hashes.
  photo_row_bytes: Math.ceil(MAX_PHOTO_BYTES / 3) * 4 + 1024, max_photos: MAX_PHOTOS });
/** Refuses, at module load, a capped chapter whose honestly played widest pair outgrows a room row,
 * or whose branches could outgrow the room's archives. turn_limits.py mirrors this. */
export function checkLongTurnBounds(shape: Readonly<LongTurnShape>, maxBranches: number | undefined, archives: Readonly<ArchiveBounds> = ARCHIVE_BOUNDS): void {
  const rows = longTurnRows(shape), escaped = longTurnRows(shape, true);
  if (rows.pair + ROW_ENVELOPE_BYTES > MAX_ROW_BYTES) throw new Error("turn_limits outgrow the room row bound");
  if (!Number.isSafeInteger(maxBranches) || (maxBranches as number) < 1) throw new Error("turn_limits need max_branches");
  // Every branch held, played to its end, beside the room row (the last checkpoint) and, in the snapshot, a photo on every turn.
  const history = (maxBranches as number) * rows.branch + rows.checkpoint + ROW_ENVELOPE_BYTES;
  const snapshot = (maxBranches as number) * escaped.branch + escaped.checkpoint + ROW_ENVELOPE_BYTES;
  const photos = Math.min(archives.max_photos, (maxBranches as number) * 2 * shape.stages) * archives.photo_row_bytes;
  if (history > archives.replay_archive_bytes || snapshot + photos + ARCHIVE_SMALL_TABLES_BYTES > archives.room_archive_bytes) throw new Error("max_branches outgrow the room archive bounds");
}
/** Receipts, reactions and deliveries a room snapshot may also hold (tide-room-limits.test.ts counts them at about 0.3 MB). */
const ARCHIVE_SMALL_TABLES_BYTES = 1024 * 1024;

/** Envelope selection comes only from an explicitly registered immutable adapter.
 * This preserves the published six parser and shares no checkpoint semantics. */
export function physicalRecording(definition: { stages: readonly { id: string; first_player_slot: string }[] }, key: Readonly<ChapterKey>, version: 6 | 7 | 8, supported: readonly number[] = [version], maxTicks = Number.MAX_SAFE_INTEGER,
  turns?: Readonly<TurnLimits>, limits?: Readonly<ChapterLimits>, input?: Readonly<InputRules>): (value: unknown) => Promise<ChapterRecording> {
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
    need(Array.isArray(r.actions) && r.actions.length > 0 && r.actions.length <= limit && (!input || r.actions.length <= maxActionEntries(input, duration)), "invalid_actions");
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
