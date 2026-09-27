// Campaign control wire format. No production campaign manifest is registered here.
// All object shapes are exact; all fields below are required, including nullable ones.
// Public gameplay continues to use existing RoomSnapshotV2 without added fields.

export const CAMPAIGN_SCHEMA = 1;
export const CAMPAIGN_LINK_VERSION = 3;
export const MAX_CAMPAIGN_CHAPTERS = 8;
export const MAX_CAMPAIGN_CONTROL_BYTES = 16_384;
export const MAX_CAMPAIGN_REQUEST_BYTES = 4_096;
export const MAX_CAMPAIGN_LIST_BYTES = 327_680;
export const MAX_CAMPAIGN_OPERATIONS = 16; // at most one alias per member per entry
export const MAX_CAMPAIGN_DEPTH = 12;
export const MAX_CAMPAIGN_NODES = 2_048;
export const MAX_CAMPAIGN_LIST_NODES = 41_000; // separately bounded aggregate of <=20 views
export const MAX_CAMPAIGN_LIST_DEPTH = 14;

// IDs use existing ID_PATTERN (22 ASCII URL-safe characters); hashes use HASH_PATTERN.
// Integer fields are finite safe integers. Registry versions are positive integers.
export type CampaignKey = {
  campaign_id: string; // /^[a-z][a-z0-9-]{0,47}$/
  campaign_version: number;
  definition_hash: string;
};
export type CampaignChapterPin = {
  level_id: string; // existing immutable chapter ID
  level_version: number;
  definition_hash: string;
  simulation_version: number;
  premium: boolean; // must agree with the authoritative bundled adapter
};
export type CampaignStoryPin = {
  story_id: string; // /^[a-z][a-z0-9-]{0,47}$/
  story_version: number;
  content_hash: string; // hash of locally bundled immutable story content; no backend prose
};
export type CampaignDefinition = {
  schema_version: 1;
  campaign_id: string;
  campaign_version: number;
  story: CampaignStoryPin;
  chapters: CampaignChapterPin[]; // ordered, 2..8; production first campaign requires all 7
  definition_hash: string; // hash of this exact object excluding definition_hash
};
export type CampaignSource = {
  room_id: string;
  revision: number; // gameplay revision, >= 0
  branch: number; // existing 0..31 branch limit
  checkpoint_hash: string;
};
export type CampaignOrigin = {
  expected_revision: number; // anchor CONTROL revision, >= 0
  from_index: number; // 0..chapter_count-1
  source: CampaignSource;
};
export type CampaignCompletionRef = {
  source_revision: number;
  source_branch: number;
  checkpoint_hash: string;
  transition_id: string; // 64 lower-case hexadecimal, internal random operation ID
  from_campaign_revision: number;
  accepted_campaign_revision: number;
};
export type CampaignChapterView = {
  chapter: CampaignChapterPin;
  room_id: string | null;
  completion: CampaignCompletionRef | null;
};
export type CampaignTransitionView = {
  transition_id: string;
  phase: "prepared" | "source_sealed" | "target_initialized";
  origin: CampaignOrigin;
  // Provisional target ID and nonce remain private until publication.
};
export type CampaignView = {
  schema_version: 1;
  api_version: 2;
  campaign_room_id: string;
  campaign_key: CampaignKey;
  revision: number; // independent of the first room's gameplay revision
  host_id: string;
  guest_id: string | null;
  player_slot: "p0" | "p1";
  state: "waiting" | "active" | "continuing" | "complete" | "deleting";
  current_index: number;
  chapters: CampaignChapterView[];
  transition: CampaignTransitionView | null;
  invite_code: string | null; // host sees original 20 uppercase hex; guest always null
  invite_expires_at: string | null; // canonical YYYY-MM-DDTHH:mm:ss.sssZ, host only
};
export type CampaignEnvelope = { campaign: CampaignView };
export type CampaignList = { campaigns: CampaignView[] }; // <= 20; total body bounded
export type CampaignCreate = {
  schema_version: 1;
  idempotency_key: string; // existing 16..80 ASCII URL-safe key; caller stores before POST
  campaign_key: CampaignKey;
};
export type CampaignJoin = {
  schema_version: 1;
  invite_code: string;
  campaign_key: CampaignKey; // one-time invitation must identify the bounded story
  supported_simulation_versions: number[]; // distinct, nonempty, max 8, positive integers
};
export type CampaignContinue = {
  schema_version: 1;
  idempotency_key: string; // exact canonical 64-hex key defined in companion document
  campaign_key: CampaignKey;
  expected_revision: number;
  from_index: number;
  source: CampaignSource;
};
export type CampaignContinueReceipt = {
  schema_version: 1;
  operation: "campaign_continue";
  campaign_room_id: string;
  campaign_key: CampaignKey;
  player_id: string;
  idempotency_key: string;
  request_hash: string;
  transition_id: string;
  origin: CampaignOrigin;
  accepted_revision: number;
  outcome: "advanced" | "finished";
  next_index: number | null;
  next_room_id: string | null;
};
export type CampaignContinueResult =
  | {
      schema_version: 1;
      operation: "campaign_continue";
      status: "pending";
      player_id: string;
      idempotency_key: string;
      request_hash: string;
      transition_id: string;
      campaign: CampaignView;
    }
  | {
      schema_version: 1;
      operation: "campaign_continue";
      status: "accepted";
      receipt: CampaignContinueReceipt;
      campaign: CampaignView;
    };

// Suggested private sidecar shape. Never return target_intent or delete progress publicly.
export type CampaignTargetIntent = {
  room_id: string;
  invite_code: string;
  index: number;
  chapter: CampaignChapterPin;
};
export type CampaignPending = CampaignTransitionView & {
  target_intent: CampaignTargetIntent | null; // null only for terminal Finish
};
export type CampaignMemberSidecar = {
  schema_version: 1;
  campaign_room_id: string;
  chapter_index: number;
  transition_id: string | null; // null only for first chapter
  status: "provisional" | "active" | "sealed" | "deleting";
  sealed_source: CampaignSource | null;
};
