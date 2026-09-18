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
export type ChapterAdapter = {
  key: Readonly<ChapterKey>; recording_version: number; simulation_version: number; supported_simulation_versions?: readonly number[]; premium: false;
  stages: readonly { id: string; first_player_slot: string }[];
  initial(): ChapterCheckpoint;
  recording(value: unknown): Promise<ChapterRecording>;
  checkpoint(value: unknown, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording): Promise<ChapterCheckpoint>;
  accepted(recording: ChapterRecording): boolean;
};
