import { ApiError } from "../protocol";

/** Story is withdrawn from production. Environment flags cannot re-enable it.
 * Retained readers and exact accepted receipts remain available for old saves. */
export function campaignProductionEnabled(): boolean { return false; }
export function requireCampaignProduction(): void {
  if (!campaignProductionEnabled()) throw new ApiError(503, "campaign_unavailable");
}
