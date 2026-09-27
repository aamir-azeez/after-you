import { ApiError, canonicalJson, digest, ID_PATTERN, isObject } from "../protocol";
import { boundedCampaign, campaignView, type CampaignDefinitionResolver } from "./campaign-protocol";
import { campaignAdmissionHash, campaignAdmissionRequest } from "./campaign-admission-intent";
import type { CampaignJoin, CampaignKey, CampaignView } from "./campaign-types";

/** Internal binding fact, reconstructed from authoritative root state. */
export type CampaignJoinCancellation = {
  schema_version: 1; admission: "join"; operation: "campaign_admission_cancel";
  status: "cancelled" | "accepted"; player_id: string; idempotency_key: string;
  request_hash: string; campaign_room_id: string; campaign_key: CampaignKey;
  campaign: CampaignView | null;
};
function need(value: unknown): asserts value { if (!value) throw new ApiError(422, "invalid_campaign_cancellation_ack"); }
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
export async function campaignJoinCancellationAck(value: unknown, owner: string, expected: unknown, resolver: CampaignDefinitionResolver = () => undefined): Promise<CampaignJoinCancellation> {
  boundedCampaign(value, 16384); const detached = structuredClone(value);
  const input = campaignAdmissionRequest(expected, "join") as CampaignJoin;
  need(ID_PATTERN.test(owner) && isObject(detached) && Object.keys(detached).length === 10 &&
    ["schema_version", "admission", "operation", "status", "player_id", "idempotency_key", "request_hash", "campaign_room_id", "campaign_key", "campaign"].every(k => Object.hasOwn(detached, k)));
  need(detached.schema_version === 1 && detached.admission === "join" && detached.operation === "campaign_admission_cancel" && (detached.status === "accepted" || detached.status === "cancelled"));
  need(detached.player_id === owner && detached.idempotency_key === input.idempotency_key && same(detached.campaign_key, input.campaign_key));
  need(detached.request_hash === await campaignAdmissionHash(owner, "join", input));
  need(detached.campaign_room_id === (await digest("v2:" + input.invite_code)).slice(0, 22));
  if (detached.status === "cancelled") need(detached.campaign === null);
  else {
    const view = await campaignView(detached.campaign, owner, resolver);
    need(view.campaign_room_id === detached.campaign_room_id && same(view.campaign_key, input.campaign_key));
    if (owner === view.host_id) need(view.invite_code === input.invite_code);
  }
  return detached as CampaignJoinCancellation;
}
