export type ChapterKey = { level_id: string; level_version: number; definition_hash: string };
export type Slot = "p0" | "p1";
export type ChapterRecording = ChapterKey & {
  schema_version: number; simulation_version: number; stage_id: string; stage_version: number;
  checkpoint_hash: string; role: "a" | "b"; player_slot: Slot; tick_rate: 30; duration_ticks: number;
  catch_assistance: boolean; actions: { ticks: number; x: number; z: number; action: boolean }[];
  replay_checks: { tick: number; state_hash: string }[]; final_state_hash: string;
  completed: boolean; outcome: Record<string, boolean>; source_recording_hash: string; recording_hash: string;
};
export type ChapterCheckpoint = ChapterKey & {
  schema_version: number; stage_index: number; completed_stage_id: string; next_stage_id: string;
  previous_checkpoint_hash: string; a_recording_hash: string; b_recording_hash: string; checkpoint_hash: string;
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
  initial(): ChapterCheckpoint;
  recording(value: unknown): Promise<ChapterRecording>;
  checkpoint(value: unknown, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording): Promise<ChapterCheckpoint>;
  accepted(recording: ChapterRecording): boolean;
};
/** Comfort rules (8) and their later aliases. 9 plays exactly as 8 and exists so a
 * chapter pinned to it can refuse 0.5.x guests, which never advertised 9. 10 (tide
 * rules), 12 and 13 (open controls) build on them: same records and bounds, only
 * the checkpoint envelope differs. 11 is the Lighthouse room's own. */
export const COMFORT_RULES: readonly number[] = [8, 9, 10, 12, 13, 14, 15];
export function comfortRules(version: unknown): boolean { return typeof version === "number" && COMFORT_RULES.includes(version); }
/** Tide rules: 10, 13 (tide rules with open controls) and 15 (with open turns too). No route latches. */
export const TIDE_RULES: readonly number[] = [10, 13, 15];
export function tideRules(version: unknown): boolean { return typeof version === "number" && TIDE_RULES.includes(version); }
/** Open controls: 12 (comfort rules) and 13 (tide rules) with every pad held by
 * either player and every lever, switch or selector worked by either. Older
 * clients never advertised 12 or 13, so a chapter pinned to one refuses them on join. */
export const OPEN_CONTROLS_RULES: readonly number[] = [12, 13, 14, 15];
/** Open turns: 14 (12 with open turns) and 15 (13 with open turns). A stage passes
 * back and forth until its goal holds at the end of a turn, up to its turn_cap. */
export const OPEN_TURNS_RULES: readonly number[] = [14, 15];
export function openTurns(version: unknown): boolean { return typeof version === "number" && OPEN_TURNS_RULES.includes(version); }
export function openControls(version: unknown): boolean { return typeof version === "number" && OPEN_CONTROLS_RULES.includes(version); }
