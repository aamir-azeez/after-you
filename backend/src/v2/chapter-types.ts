import type { OpenTurns } from "./open-turns";

export type ChapterKey = { level_id: string; level_version: number; definition_hash: string };
export type Slot = "p0" | "p1";
export type ChapterRecording = ChapterKey & {
  schema_version: number; simulation_version: number; stage_id: string; stage_version: number;
  checkpoint_hash: string; role: "a" | "b"; player_slot: Slot; tick_rate: 30; duration_ticks: number;
  catch_assistance: boolean; actions?: { ticks: number; x: number; z: number; action: boolean }[];
  replay_checks?: { tick: number; state_hash: string }[]; final_state_hash: string;
  /** A packed record's runs and checks in place of `actions` and `replay_checks` (v2/recording-codec.ts). */
  packed?: string;
  completed: boolean; outcome: Record<string, boolean>; source_recording_hash: string; recording_hash: string;
  /** Carry-over turns (rules 18 to 21, open-turns.ts carryFits): the tick of the turn before at which this one took over, the
   * world hash at this turn's start, and its world hash at the tick the next turn takes over. All three are under recording_hash. */
  handoff_tick?: number; start_hash?: string; handoff_hash?: string;
};
/** A recording in its JSON form, its runs and checks listed (every record before packed recordings, and every JSON turn since). */
export type JsonChapterRecording = ChapterRecording & { actions: NonNullable<ChapterRecording["actions"]>; replay_checks: NonNullable<ChapterRecording["replay_checks"]>; packed?: never };
export type ChapterCheckpoint = ChapterKey & {
  schema_version: number; stage_index: number; completed_stage_id: string; next_stage_id: string;
  previous_checkpoint_hash: string; a_recording_hash: string; b_recording_hash: string; checkpoint_hash: string;
  /** Open turns (open-turns.ts, schema 9) name every turn of the stage here in place of the a and b hashes, and nest no proof. */
  turn_hashes?: string[];
  /** Open turns: the pip that plays the next stage's first turn, the one that did not close this stage. */
  next_first_slot?: Slot;
};
export type ChapterLimits = { checkpoint_bytes: number; checkpoint_values: number; turn_body_bytes: number; turn_body_values: number; recording_bytes?: number; recording_values?: number };
/** Stage digits in turn, pair and photo ids are one character. */
export const MAX_ROOM_STAGES = 8;
/** 0.5.x clients, and every client that does not ask for more, see only two-stage chapters. */
export const LEGACY_STAGE_COUNT = 2;
export type ChapterAdapter = {
  key: Readonly<ChapterKey>; recording_version: number; simulation_version: number; supported_simulation_versions?: readonly number[]; premium: boolean;
  require_supported_simulation_on_join?: boolean;
  stages: readonly { id: string; first_player_slot: string }[];
  /** Size bounds for a chapter whose proofs nest more than two stages. Absent = the published bounds. */
  limits?: Readonly<ChapterLimits>;
  /** Fewer forks than the published 32, for chapters whose replay archive would outgrow its cap. */
  max_branches?: number;
  /** Open turns (open-turns.ts): the stages' turn caps and the widest turn. Absent: two turns a stage, as published. */
  open_turns?: OpenTurns;
  initial(): ChapterCheckpoint;
  /** `stored`: a stored row, which on open turns may be a turn's fingerprint (open-turns.ts). */
  recording(value: unknown, stored?: boolean): Promise<ChapterRecording>;
  /** `passes`: an open turns stage's turns between its first and its closing turn, in order. */
  checkpoint(value: unknown, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording, passes?: readonly ChapterRecording[]): Promise<ChapterCheckpoint>;
  accepted(recording: ChapterRecording): boolean;
};
/** Comfort rules (8) and their later aliases. 9 plays exactly as 8 and exists so a
 * chapter pinned to it can refuse 0.5.x guests, which never advertised 9. 10 (tide
 * rules), 12 and 13 (open controls) and the open turns 18 to 21 build on them: same
 * records and bounds, only the checkpoint envelope differs. 11 is the Lighthouse room's own. */
export const COMFORT_RULES: readonly number[] = [8, 9, 10, 12, 13, 18, 19, 20, 21];
export function comfortRules(version: unknown): boolean { return typeof version === "number" && COMFORT_RULES.includes(version); }
/** Tide rules: 10, 13 (tide rules with open controls), 19 (with open turns too) and 20 (19 with the new pieces). No route latches. */
export const TIDE_RULES: readonly number[] = [10, 13, 19, 20];
export function tideRules(version: unknown): boolean { return typeof version === "number" && TIDE_RULES.includes(version); }
/** Open controls: 12 (comfort rules) and 13 (tide rules) with every pad held by
 * either player and every lever, switch or selector worked by either. Older
 * clients never advertised 12 or 13, so a chapter pinned to one refuses them on join. */
export const OPEN_CONTROLS_RULES: readonly number[] = [12, 13, 18, 19, 20, 21];
/** Open turns (claude-20261011/carry-over-turns/design.md): 18 (12 with open turns) and 19 (13 with open turns). A stage
 * is one timeline: each turn takes over from the one before at its hand-off (open-turns.ts carryFits) and passes back
 * and forth until both pips reach the goal, up to its turn_cap. The phone's core/physical/open_controls.gd mirrors the numbers. */
export const OPEN_TURNS_RULES: readonly number[] = [18, 19, 20, 21];
/** The new pieces of The Falls and Fog Marsh: 20 is 19 plus "not" in gates, moving
 * platforms, sinking stones and pull-up ladders (game/core/physical/pieces_rules.gd).
 * None adds a mechanism: the checkpoint keeps its four. */
export const PIECES_RULES: readonly number[] = [20];
export function piecesRules(version: unknown): boolean { return typeof version === "number" && PIECES_RULES.includes(version); }
/** The shared ball: 21 is 18 with one ball both players push in every turn, the friend's replay pushing it too, and a
 * ball home stage that ends with the ball in its cradle (game/core/physical/runtime.gd _shared_ball). A cooperative
 * level with a ball pins it on open turns; the checkpoint keeps its four mechanisms (open-turns.ts openBallProblem). */
export const SHARED_BALL_RULES: readonly number[] = [21];
export function sharedBall(version: unknown): boolean { return typeof version === "number" && SHARED_BALL_RULES.includes(version); }
export function openTurns(version: unknown): boolean { return typeof version === "number" && OPEN_TURNS_RULES.includes(version); }
export function openControls(version: unknown): boolean { return typeof version === "number" && OPEN_CONTROLS_RULES.includes(version); }
