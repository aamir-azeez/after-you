import { canonicalJson, digest, isObject } from "../protocol";
import { roomLinkVersion, validRoomLink, type RoomLink } from "../room-links";
import { boundedCampaign } from "./campaign-protocol";
import type { CampaignKey } from "./campaign-types";

/** A separate intent version; old raw links and chapter intents are never rewritten. */
export type CampaignCreation = { creation_schema: 2; link: RoomLink; campaign_key: CampaignKey };
export function validCampaignCreation(value: unknown): value is CampaignCreation {
  try {
    boundedCampaign(value, 4096);
    if (!isObject(value) || Object.keys(value).length !== 3 || value.creation_schema !== 2 ||
        !validRoomLink(value.link) || roomLinkVersion(value.link) !== 3 || !value.link.host || !isObject(value.campaign_key)) return false;
    const key = value.campaign_key;
    return Object.keys(key).length === 3 && typeof key.campaign_id === "string" && /^[a-z][a-z0-9-]{0,47}$/.test(key.campaign_id) &&
      typeof key.campaign_version === "number" && Number.isSafeInteger(key.campaign_version) && key.campaign_version > 0 &&
      typeof key.definition_hash === "string" && /^[a-f0-9]{64}$/.test(key.definition_hash);
  } catch { return false; }
}
export async function campaignCreation(value: unknown): Promise<CampaignCreation | null> {
  if (!validCampaignCreation(value)) return null;
  if ((await digest("v2:" + value.link.invite_code)).slice(0, 22) !== value.link.room_id) return null;
  return JSON.parse(canonicalJson(value)) as CampaignCreation;
}
/** Content classification is independent of the outer archive format. */
export function campaignBearingLink(value: unknown): boolean {
  return validRoomLink(value) && roomLinkVersion(value) === 3 || validCampaignCreation(value);
}
