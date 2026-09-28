import archivedDefinition from "../../../game/content/compatibility/a-place-for-two-definition-v1.json";
import { ApiError, canonicalJson } from "../protocol";
import { chapter, creatable } from "./chapters";
import { campaignDefinition, type CampaignDefinitionResolver } from "./campaign-protocol";
import type { CampaignDefinition, CampaignKey } from "./campaign-types";
import { campaignProductionEnabled } from "./campaign-production";

// Immutable shipped definition; advertisement may later be removed independently.
// Existing saves must continue to resolve this exact retained key.
const key = (d: CampaignDefinition): CampaignKey => ({ campaign_id: d.campaign_id,
  campaign_version: d.campaign_version, definition_hash: d.definition_hash });
const firstRelease = structuredClone(archivedDefinition) as CampaignDefinition;
const retained: readonly CampaignDefinition[] = [firstRelease];
const fresh: readonly CampaignKey[] = [key(firstRelease)];
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
export const retainedCampaign: CampaignDefinitionResolver = wanted => {
  const found = retained.find(d => same(key(d), wanted));
  return found ? structuredClone(found) : undefined;
};
export function advertisedCampaigns(env: Env): CampaignDefinition[] {
  if (!campaignProductionEnabled()) return [];
  return fresh.map(retainedCampaign).filter((d): d is CampaignDefinition => !!d)
    .filter(d => d.chapters.every(pin => creatable(chapter(pin), env)));
}
export function campaignCreatable(wanted: CampaignKey, env: Env): boolean {
  return String(env.CAMPAIGN_CREATION_ENABLED) === "true" && advertisedCampaigns(env).some(d => same(key(d), wanted));
}
/** Only trusted binding callers supply a stored definition. Never resolve a
 * public body/environment blob, and never substitute another campaign version. */
export async function exactCampaignDefinition(value: unknown, wanted: CampaignKey): Promise<CampaignDefinition> {
  const frozen = structuredClone(value);
  const definition = await campaignDefinition(frozen, pin => {
    try { const a = chapter(pin); return a.premium === pin.premium &&
      (a.supported_simulation_versions ?? [a.simulation_version]).includes(pin.simulation_version); }
    catch { return false; }
  });
  if (!same(key(definition), wanted)) throw new ApiError(409, "campaign_definition_mismatch");
  return definition;
}
export function definitionResolver(definition: CampaignDefinition): CampaignDefinitionResolver {
  const frozen = structuredClone(definition), expected = key(frozen);
  return wanted => same(wanted, expected) ? structuredClone(frozen) : undefined;
}
