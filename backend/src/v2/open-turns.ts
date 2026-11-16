import { canonicalJson } from "../protocol";
import type { ChapterRecording, Slot } from "./chapter-types";
import { MAX_REPLAY_ARCHIVE_BYTES, MAX_ROOM_PAIRS, MAX_ROOM_TURNS, MAX_ROW_BYTES } from "./row-bound";
import { checkBytes, checkTicks, isPacked } from "./recording-codec";

/**
 * Open turns: the open turns rules (14 and 15, chapter-types.ts OPEN_TURNS_RULES, open controls with open turns) play a stage in as many
 * turns as it takes. Turn 1 is a first turn as before (role "a"); every later turn (role "b") plays from the stage's
 * checkpoint with the other pip's latest turn as its memory, chained by `source_recording_hash`. Odd turns are the
 * stage's first player's, even turns the other's. A turn that ends with both players at the goal (its light holding)
 * closes the stage (completed, with its checkpoint); any other later turn is a pass (not completed, no checkpoint) and
 * play goes to the other pip. A turn lasts at least as long as its memory.
 *
 * Fingerprints (owner, 2026-11-16; claude-20261011/open-turns-fingerprints/WIRE.md): the server keeps only the newest
 * turn in full. A checkpoint names its stage's turns by hash (`turn_hashes`) and nests nothing. Turn k becomes its
 * fingerprint (the record without `packed`) in the transaction that accepts turn k+1, which its partner played over
 * it; a stage's closing turn stays full until the member who did not play it acknowledges it (room.ts). The phones
 * keep every turn and replay from their own copies, so a turn is bounded only by MAX_PACKED_CHARS and its rules
 * ceiling, never by how many stages or turns came before it.
 *
 * The caps: each stage's `turn_cap` from its definition (DEFAULT_TURN_CAP when absent) and the room's 128 turns. The
 * cap's turn must finish the stage (`must_finish`), so the phone retries it like a second turn.
 *
 * Every turn has the same time limit: the level's second turn limit (turn_limits.b_ticks, or the published 1,200).
 * Every turn is packed (recording-codec.ts) whatever PACKED_RECORDINGS says: only apps that read packed turns play
 * these rules, so a JSON turn is refused and the bounds below are sized by the widest packed turn.
 * Turn ids keep a letter for the turn's number, so the first two keep today's ids: t<branch>-<stage>-a, -b, -c ...
 * This file is the one place these rules live on the server; core/physical/open_turns.gd mirrors them on the phone.
 */
export const DEFAULT_TURN_CAP = 10;
/**
 * The longest turn these rules take: ten minutes, where older rules stop at 9,000 ticks. Every turn is packed, and
 * the widest one this long is about 82,000 characters, under MAX_PACKED_CHARS (131,072) with room to spare
 * (game/core/physical/runtime.gd MAX_OPEN_TURN_TICKS mirrors it).
 */
export const MAX_OPEN_TURN_TICKS = 18_000;
export const MIN_TURN_CAP = 2;
export const MAX_TURN_CAP = 20;
export const TURN_LETTERS = "abcdefghijklmnopqrst";
/** Every turn id a room can hold: published rooms only ever use a and b. */
export const OPEN_TURN_ID_PATTERN = /^t(?:[0-9]|[12][0-9]|3[01])-[0-7]-[a-t]$/;
/** Checkpoints of open turns name every turn of their stage (turn_hashes) and nest nothing; published checkpoints stay schema 7. */
export const OPEN_CHECKPOINT_SCHEMA = 8;
/** Room keys, ids and counters beside the records; the same allowance the pair row bound keeps (protocol-physical-recording.ts). */
const ENVELOPE_BYTES = 16_384;
/** A flat open turns checkpoint (players, mechanisms, hashes and up to 20 turn hashes: about 1 KB), with room to spare. */
const CHECKPOINT_BYTES = 16_384;
const CHECKPOINT_VALUES = 4_096;

export type OpenTurns = {
  /** Each stage's turn cap, in stage order. */
  readonly caps: readonly number[];
  /** The widest recording a turn may send (the chapter's recording bound). */
  readonly recording_bytes: number;
  /** The branches (attempts) the chapter keeps, so every row a room holds fits its archive (openTurnLimits). */
  readonly branches: number;
};

/** A stage's turn cap, as its definition declares it: a whole number from 2 to 20 (open_turns.gd cap_valid). Throws at module load on a bad value. */
export function stageTurnCap(stage: { turn_cap?: unknown }): number {
  if (stage.turn_cap === undefined) return DEFAULT_TURN_CAP;
  if (!Number.isSafeInteger(stage.turn_cap) || (stage.turn_cap as number) < MIN_TURN_CAP || (stage.turn_cap as number) > MAX_TURN_CAP) throw new Error("invalid turn_cap");
  return stage.turn_cap as number;
}

/** A packed turn's header fields (ids, hashes, outcome) beside its `packed` string: the widest real header is under 900 bytes. A fingerprint is this header alone. */
const PACKED_HEADER_BYTES = 2_048;
/** The values a packed turn holds: its header fields and outcome, with room to spare. */
export const PACKED_RECORDING_VALUES = 64;
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

/** The widest turn body the Worker copies within its 10 ms (twice, at 4 ns a byte: test/compressed-rooms.test.ts). */
const MAX_WORKER_BODY_BYTES = 1_250_000;
/**
 * The caps and the branches for a chapter. Nothing nests, so no bound grows with the stages or the turns:
 * - a turn row holds one recording, and the closing turn's body one recording and a flat checkpoint, under
 *   MAX_ROW_BYTES and the Worker's CPU (MAX_WORKER_BODY_BYTES);
 * - every row a room may hold (MAX_ROOM_TURNS turn rows and MAX_ROOM_PAIRS pair rows as fingerprints, and per branch
 *   at most two full turns: its newest and a closing turn the partner has not acknowledged) stays under
 *   MAX_REPLAY_ARCHIVE_BYTES, so the room snapshot and the replay archive fit.
 * The chapter keeps as many of `maxBranches` as fit. Throws at module load when even one branch cannot.
 */
export function openTurnLimits(stages: readonly { turn_cap?: unknown }[], recordingBytes: number, maxBranches: number): OpenTurns {
  const caps = stages.map(stageTurnCap);
  if (recordingBytes + ENVELOPE_BYTES > MAX_ROW_BYTES || recordingBytes + CHECKPOINT_BYTES + ENVELOPE_BYTES > MAX_WORKER_BODY_BYTES) throw new Error("open turns outgrow the room row bound");
  const held = MAX_ROOM_TURNS * (PACKED_HEADER_BYTES + ENVELOPE_BYTES) + MAX_ROOM_PAIRS * (2 * PACKED_HEADER_BYTES + CHECKPOINT_BYTES + ENVELOPE_BYTES);
  for (let branches = maxBranches; branches >= 1; branches--) {
    if (held + branches * 2 * recordingBytes <= MAX_REPLAY_ARCHIVE_BYTES) return Object.freeze({ caps: Object.freeze(caps), recording_bytes: recordingBytes, branches });
  }
  throw new Error("open turns outgrow the room row bound");
}
/** The recording, checkpoint and turn body bounds an open turns chapter needs: packed turns, a flat checkpoint, and the closing turn's body. */
export function openBodyLimits(open: OpenTurns): { recording_bytes: number; recording_values: number; checkpoint_bytes: number; checkpoint_values: number; turn_body_bytes: number; turn_body_values: number } {
  return { recording_bytes: open.recording_bytes, recording_values: PACKED_RECORDING_VALUES, checkpoint_bytes: CHECKPOINT_BYTES, checkpoint_values: CHECKPOINT_VALUES,
    turn_body_bytes: open.recording_bytes + CHECKPOINT_BYTES + ENVELOPE_BYTES, turn_body_values: CHECKPOINT_VALUES + PACKED_RECORDING_VALUES + 1_000 };
}

/** A turn's fingerprint: its record without `packed` (the header the next checks need, and its hash). */
export function fingerprint(recording: ChapterRecording): ChapterRecording {
  const { packed: _packed, ...header } = recording; void _packed;
  return header as ChapterRecording;
}
/** Whether a stored turn is only its fingerprint: no runs, packed or listed. */
export function isFingerprint(recording: object): boolean { return !isPacked(recording) && !Object.hasOwn(recording, "actions"); }

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
/** A turn's canonical bytes. */
export function recordingBytes(recording: ChapterRecording): number {
  return new TextEncoder().encode(canonicalJson(recording)).byteLength;
}
/** Whether the next turn (`turn`, 1 based) must close the stage: it is the cap's turn. */
export function mustFinish(open: OpenTurns, stage: number, turn: number): boolean {
  return turn >= 2 && turn >= open.caps[stage];
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
