import { canonicalJson } from "../protocol";
import type { ChapterRecording, Slot } from "./chapter-types";
import { MAX_REPLAY_ARCHIVE_BYTES, MAX_ROW_BYTES } from "./row-bound";
import { checkBytes, checkTicks } from "./recording-codec";

/**
 * Open turns: the open turns rules (14 and 15, chapter-types.ts OPEN_TURNS_RULES, open controls with open turns) play a stage in as many
 * turns as it takes. Turn 1 is a first turn as before (role "a"); every later turn (role "b") plays from the stage's
 * checkpoint with the other pip's latest turn as its memory, which nests the turns before it by
 * `source_recording_hash`. Odd turns are the stage's first player's, even turns the other's. A turn that ends with both players at the goal (its light holding)
 * closes the stage (completed, with the checkpoint that proves every turn); any other later turn is a
 * pass (not completed, no checkpoint) and play goes to the other pip. A turn lasts at least as long as its memory.
 *
 * The caps: each stage's `turn_cap` from its definition (DEFAULT_TURN_CAP when absent), the room's 128 turns, and a
 * per stage byte budget kept only as a backstop under the row bound. The last turn a cap or the budget allows must
 * finish the stage (`must_finish`), so the phone retries it like a second turn.
 *
 * Every turn has the same time limit: the level's second turn limit (turn_limits.b_ticks, or the published 1,200).
 * Every turn is packed (recording-codec.ts) whatever PACKED_RECORDINGS says: only apps that read packed turns play
 * these rules, so a JSON turn is refused and the bounds below are sized by the widest packed turn.
 * Turn ids keep a letter for the turn's number, so the first two keep today's ids: t<branch>-<stage>-a, -b, -c ...
 * This file is the one place these rules live on the server; core/physical/open_turns.gd mirrors them on the phone.
 */
export const DEFAULT_TURN_CAP = 10;
export const MIN_TURN_CAP = 2;
export const MAX_TURN_CAP = 20;
export const TURN_LETTERS = "abcdefghijklmnopqrst";
/** Every turn id a room can hold: published rooms only ever use a and b. */
export const OPEN_TURN_ID_PATTERN = /^t(?:[0-9]|[12][0-9]|3[01])-[0-7]-[a-t]$/;
/** Checkpoints of open turns nest every turn of their stage (proof.turns); published checkpoints stay schema 7. */
export const OPEN_CHECKPOINT_SCHEMA = 8;
/** Room keys, ids and counters beside the records; the same allowance the pair row bound keeps (protocol-physical-recording.ts). */
const ENVELOPE_BYTES = 16_384;
/** A stage's own checkpoint fields (players, mechanisms, hashes) beside the turns it nests. */
const STAGE_OVERHEAD_BYTES = 16_384;

export type OpenTurns = {
  /** Each stage's turn cap, in stage order. */
  readonly caps: readonly number[];
  /** The widest recording a turn may send (the chapter's recording bound). */
  readonly recording_bytes: number;
  /** Most bytes a stage's turns may take together; a backstop that keeps the closing pair row under MAX_ROW_BYTES. */
  readonly stage_bytes: number;
  /** The branches (attempts) the chapter keeps, so its widest replay archive fits (openTurnLimits). */
  readonly branches: number;
};

/** A stage's turn cap, as its definition declares it: a whole number from 2 to 20 (open_turns.gd cap_valid). Throws at module load on a bad value. */
export function stageTurnCap(stage: { turn_cap?: unknown }): number {
  if (stage.turn_cap === undefined) return DEFAULT_TURN_CAP;
  if (!Number.isSafeInteger(stage.turn_cap) || (stage.turn_cap as number) < MIN_TURN_CAP || (stage.turn_cap as number) > MAX_TURN_CAP) throw new Error("invalid turn_cap");
  return stage.turn_cap as number;
}

/** A packed turn's header fields (ids, hashes, outcome) beside its `packed` string: the widest real header is under 900 bytes. */
const PACKED_HEADER_BYTES = 2_048;
/** The values a packed turn holds: its header fields and outcome, with room to spare. */
export const PACKED_RECORDING_VALUES = 64;
/** A stage's own checkpoint fields (players, mechanisms, hashes) as values, beside the turns it nests. */
const STAGE_OVERHEAD_VALUES = 4_096;
/**
 * The widest packed turn `ticks` ticks long, as canonical JSON: a new stick every tick (three bytes a run), the run
 * count, every replay check (recording-codec.ts), base64, and the header. About 4.6 bytes a tick against about 47
 * for a JSON turn.
 */
export function packedRecordingBytes(ticks: number): number {
  let raw = 1 + Math.max(1, Math.ceil(Math.log2(ticks + 1) / 7)) + 3 * ticks;
  for (const tick of checkTicks(ticks)) raw += checkBytes(tick, ticks);
  return PACKED_HEADER_BYTES + 4 * Math.ceil(raw / 3);
}

/** Room a stage keeps for passes beyond its widest first and closing turns, or the chapter gives up branches for it. */
const PASS_FLOOR_BYTES = 98_304;
/** The widest turn body the Worker copies within its 10 ms (twice, at 4 ns a byte: test/compressed-rooms.test.ts). */
const MAX_WORKER_BODY_BYTES = 1_250_000;
/**
 * The caps, the budget and the branches for a chapter. Three bounds set the budget, the smallest wins:
 * - the closing pair row holds the last checkpoint (every stage's turns) and two recordings, under MAX_ROW_BYTES;
 * - the closing turn's body (that checkpoint and the closing recording) stays inside the Worker's CPU (MAX_WORKER_BODY_BYTES);
 * - the replay archive holds every branch's turn rows and pair rows (each pair nests the stages before it), under
 *   MAX_REPLAY_ARCHIVE_BYTES.
 * The chapter keeps as many of `maxBranches` as still leave each stage its widest first and closing turns and
 * PASS_FLOOR_BYTES of passes; long turns (the tide's) trade branches for that. Throws at module load when even one
 * branch cannot.
 */
export function openTurnLimits(stages: readonly { turn_cap?: unknown }[], recordingBytes: number, maxBranches: number): OpenTurns {
  const caps = stages.map(stageTurnCap), n = stages.length, pairs = n * (n + 1) / 2;
  const row = Math.min(Math.floor((MAX_ROW_BYTES - ENVELOPE_BYTES - 2 * recordingBytes) / n), Math.floor((MAX_WORKER_BODY_BYTES - ENVELOPE_BYTES - recordingBytes) / n)) - STAGE_OVERHEAD_BYTES;
  const archive = (branches: number) => Math.floor((MAX_REPLAY_ARCHIVE_BYTES / branches - n * (2 * recordingBytes + ENVELOPE_BYTES) - pairs * STAGE_OVERHEAD_BYTES) / (n + pairs));
  for (let branches = maxBranches; branches >= 1; branches--) {
    const stageBytes = Math.min(row, archive(branches));
    if (stageBytes >= 2 * recordingBytes + PASS_FLOOR_BYTES) return Object.freeze({ caps: Object.freeze(caps), recording_bytes: recordingBytes, stage_bytes: stageBytes, branches });
  }
  throw new Error("open turns outgrow the room row bound");
}
/** The recording, checkpoint and turn body bounds an open turns chapter needs: packed turns, every stage at its budget, then the closing turn. */
export function openBodyLimits(open: OpenTurns, stages: number): { recording_bytes: number; recording_values: number; checkpoint_bytes: number; checkpoint_values: number; turn_body_bytes: number; turn_body_values: number } {
  const checkpointBytes = stages * (open.stage_bytes + STAGE_OVERHEAD_BYTES);
  // Every stage's turns, up to the widest cap, and its own fields.
  const checkpointValues = stages * (Math.max(...open.caps) * PACKED_RECORDING_VALUES + STAGE_OVERHEAD_VALUES);
  return { recording_bytes: open.recording_bytes, recording_values: PACKED_RECORDING_VALUES, checkpoint_bytes: checkpointBytes, checkpoint_values: checkpointValues,
    turn_body_bytes: checkpointBytes + open.recording_bytes + ENVELOPE_BYTES, turn_body_values: checkpointValues + PACKED_RECORDING_VALUES + 1_000 };
}

/** The slot that plays turn `turn` (1 based) of a stage whose first player is `first`. */
export function turnSlot(first: string, turn: number): Slot {
  return (turn % 2 === 1) === (first === "p0") ? "p0" : "p1";
}
/** Turn `turn`'s id on `branch` and stage `stage`. */
export function turnId(branch: number, stage: number, turn: number): string {
  return `t${branch}-${stage}-${TURN_LETTERS[turn - 1]}`;
}
/** The turn number an id names (a = 1), or 0. */
export function turnNumber(id: string): number {
  return TURN_LETTERS.indexOf(id.slice(-1)) + 1;
}
/** Every possible turn id of one stage, a to the cap's letter (rows that do not exist are harmless to name). */
export function stageTurnIds(branch: number, stage: number): string[] {
  return [...TURN_LETTERS].map((_, index) => turnId(branch, stage, index + 1));
}
/** A turn's size against the stage budget: its canonical bytes. */
export function recordingBytes(recording: ChapterRecording): number {
  return new TextEncoder().encode(canonicalJson(recording)).byteLength;
}
/** The bytes a pass may take now: the budget less the turns so far and one widest closing turn kept back for after it. */
export function passRoom(open: OpenTurns, used: number): number {
  return open.stage_bytes - open.recording_bytes - used;
}
/**
 * Whether the next turn (`turn`, 1 based) must close the stage: it is the cap's turn, or the budget has no room left
 * for a pass. A pass bigger than passRoom is refused too; the phone checks its own size before it offers Pass.
 */
export function mustFinish(open: OpenTurns, stage: number, turn: number, used: number): boolean {
  return turn >= 2 && (turn >= open.caps[stage] || passRoom(open, used) <= 0);
}
/**
 * When an open turns stage ends (owner, 2026-11-14): both pips end a turn in the goal area (the live pip and the
 * memory's final place) and the stage's objective holds. The first turn's own part is not asked again. The one place
 * this rule lives on the server; core/physical/open_turns.gd holds the phone's.
 */
export function openStageEnds(atGoal: (slot: Slot) => boolean, objective: boolean): boolean {
  return objective && atGoal("p0") && atGoal("p1");
}
/** Open turns acceptance: a first turn as before; a later turn either closes the stage or passes without its goal. */
export function openAccepted(r: ChapterRecording, physical: (r: ChapterRecording) => boolean): boolean {
  if (r.role === "a" || r.completed) return physical(r);
  return r.outcome.objective_complete === false;
}
