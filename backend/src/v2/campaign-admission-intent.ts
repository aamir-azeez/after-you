import { ApiError, canonicalJson, digest, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, isObject } from "../protocol";
import { boundedCampaign } from "./campaign-protocol";
import type { CampaignCreate, CampaignJoin } from "./campaign-types";

export type CampaignJoinAttempt = CampaignJoin;
export type CampaignAdmission = "create" | "join";
export type CampaignAdmissionRequest = CampaignCreate | CampaignJoinAttempt;
/** Open Join records are retained even after membership succeeds. They make no
 * claim about current membership; only the anchor owns that authority. */
export type CampaignAdmissionIntent = {
  creation_schema: 3; admission: CampaignAdmission; player_id: string;
  request: CampaignAdmissionRequest; request_hash: string;
  state: "open" | "closed"; room_id: string | null;
};
export type CampaignCancellationReceipt = {
  schema_version: 1; operation: "campaign_admission_cancel"; admission: CampaignAdmission;
  status: "cancelled"; player_id: string; idempotency_key: string; request_hash: string;
};
function need(value: unknown): asserts value { if (!value) throw new ApiError(422, "invalid_campaign_admission"); }
function exact(value: unknown, keys: string[]): Record<string, unknown> {
  need(isObject(value) && Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k))); return value;
}
function key(value: unknown): void {
  const k = exact(value, ["campaign_id", "campaign_version", "definition_hash"]);
  need(typeof k.campaign_id === "string" && /^[a-z][a-z0-9-]{0,47}$/.test(k.campaign_id));
  need(typeof k.campaign_version === "number" && Number.isSafeInteger(k.campaign_version) && k.campaign_version > 0);
  need(typeof k.definition_hash === "string" && HASH_PATTERN.test(k.definition_hash));
}
/** Structural admission identity, independent of current fresh-admission flags.
 * The actual Join still resolves its immutable finite definition separately. */
export function campaignAdmissionRequest(value: unknown, admission: CampaignAdmission): CampaignAdmissionRequest {
  boundedCampaign(value, 4096);
  const x = exact(value, admission === "create" ? ["schema_version", "idempotency_key", "campaign_key"] :
    ["schema_version", "idempotency_key", "invite_code", "campaign_key", "supported_simulation_versions"]);
  need(x.schema_version === (admission === "create" ? 1 : 2));
  need(typeof x.idempotency_key === "string" && IDEMPOTENCY_PATTERN.test(x.idempotency_key)); key(x.campaign_key);
  if (admission === "join") {
    need(typeof x.invite_code === "string" && /^[A-F0-9]{20}$/.test(x.invite_code));
    need(Array.isArray(x.supported_simulation_versions) && x.supported_simulation_versions.length > 0 && x.supported_simulation_versions.length <= 8);
    need(x.supported_simulation_versions.every(v => typeof v === "number" && Number.isSafeInteger(v) && v > 0));
    need(new Set(x.supported_simulation_versions).size === x.supported_simulation_versions.length);
  }
  return structuredClone(x) as CampaignAdmissionRequest;
}
export async function campaignAdmissionHash(owner: string, admission: CampaignAdmission, body: CampaignAdmissionRequest): Promise<string> {
  need(typeof owner === "string" && ID_PATTERN.test(owner));
  // Exact spelling and paths match the existing native LobbyProtocol helper.
  return digest(canonicalJson({ owner_player_id: owner, path: admission === "create" ? "/v2/campaigns" : "/v2/campaigns/join", body }));
}
export function validCampaignAdmissionIntent(value: unknown): value is CampaignAdmissionIntent {
  try {
    boundedCampaign(value, 8192);
    const x = exact(value, ["creation_schema", "admission", "player_id", "request", "request_hash", "state", "room_id"]);
    need(x.creation_schema === 3 && (x.admission === "create" || x.admission === "join"));
    need(typeof x.player_id === "string" && ID_PATTERN.test(x.player_id));
    campaignAdmissionRequest(x.request, x.admission);
    need(typeof x.request_hash === "string" && HASH_PATTERN.test(x.request_hash));
    need(x.state === "open" || x.state === "closed");
    if (x.admission === "create") need(x.state === "closed" && x.room_id === null);
    else need(typeof x.room_id === "string" && ID_PATTERN.test(x.room_id));
    return true;
  } catch { return false; }
}
export async function campaignAdmissionIntent(value: unknown, owner: string): Promise<CampaignAdmissionIntent | null> {
  if (!validCampaignAdmissionIntent(value) || value.player_id !== owner) return null;
  const detached = structuredClone(value);
  if (detached.request_hash !== await campaignAdmissionHash(owner, detached.admission, detached.request)) return null;
  if (detached.admission === "join" && detached.room_id !== (await digest("v2:" + (detached.request as CampaignJoinAttempt).invite_code)).slice(0, 22)) return null;
  return detached;
}
export function cancellationReceipt(intent: CampaignAdmissionIntent): CampaignCancellationReceipt {
  need(intent.state === "closed");
  return { schema_version: 1, operation: "campaign_admission_cancel", admission: intent.admission, status: "cancelled",
    player_id: intent.player_id, idempotency_key: intent.request.idempotency_key, request_hash: intent.request_hash };
}
