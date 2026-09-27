import { ApiError, canonicalJson, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, isObject } from "../protocol";
import type { TableDefinition } from "../storage-schema";
import { boundedCampaign, campaignJoin } from "./campaign-protocol";
import { campaignAdmissionHash, campaignAdmissionRequest } from "./campaign-admission-intent";
import type { CampaignDefinition, CampaignJoin, CampaignView } from "./campaign-types";

export const MAX_CAMPAIGN_JOIN_ATTEMPTS = 128;
export const CAMPAIGN_JOIN_TABLE: TableDefinition = {
  name: "campaign_join_attempts",
  schema: "CREATE TABLE campaign_join_attempts (request_key TEXT PRIMARY KEY, request_hash TEXT NOT NULL, data TEXT NOT NULL)",
  columns: ["rowid", "request_key", "request_hash", "data"], maxRows: MAX_CAMPAIGN_JOIN_ATTEMPTS,
  select: "SELECT CAST(rowid AS TEXT) AS rowid,request_key,request_hash,data FROM campaign_join_attempts ORDER BY campaign_join_attempts.rowid LIMIT 129",
  insert: "INSERT INTO campaign_join_attempts (rowid,request_key,request_hash,data) VALUES (CAST(? AS INTEGER),?,?,?)"
};
export type CampaignJoinFact = { schema_version: 1; player_id: string; request: CampaignJoin; status: "accepted" | "cancelled" };
type Row = Record<string, string | number>;
function need(value: unknown): asserts value { if (!value) throw new ApiError(422, "invalid_campaign_join_storage"); }
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
export function joinFact(value: unknown): CampaignJoinFact {
  boundedCampaign(value, 8192);
  need(isObject(value) && Object.keys(value).length === 4 && ["schema_version", "player_id", "request", "status"].every(k => Object.hasOwn(value, k)));
  need(value.schema_version === 1 && typeof value.player_id === "string" && ID_PATTERN.test(value.player_id));
  need(value.status === "accepted" || value.status === "cancelled"); campaignAdmissionRequest(value.request, "join");
  return structuredClone(value) as CampaignJoinFact;
}
/** Called only after the ordinary root sidecar has been fully validated. */
export async function validateCampaignJoinRows(rows: Row[], view: CampaignView, definition: CampaignDefinition): Promise<void> {
  need(rows.length <= MAX_CAMPAIGN_JOIN_ATTEMPTS); let accepted = 0;
  const keys = new Set<string>();
  for (const row of rows) {
    need(typeof row.data === "string"); const fact = joinFact(JSON.parse(row.data));
    need(typeof row.request_hash === "string" && HASH_PATTERN.test(row.request_hash));
    need(row.request_key === fact.player_id + ":" + fact.request.idempotency_key && IDEMPOTENCY_PATTERN.test(fact.request.idempotency_key));
    need(!keys.has(row.request_key)); keys.add(row.request_key);
    need(fact.player_id !== view.host_id && same(fact.request.campaign_key, view.campaign_key) && fact.request.invite_code === view.invite_code);
    need(row.request_hash === await campaignAdmissionHash(fact.player_id, "join", fact.request));
    if (fact.status === "accepted") {
      need(fact.player_id === view.guest_id && ++accepted <= 1);
      campaignJoin(fact.request, key => same(key, view.campaign_key) ? definition : undefined);
    }
  }
}
