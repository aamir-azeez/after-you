import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, expect, it } from "vitest";
import worker from "../src/index";
import { digest, randomToken } from "../src/protocol";
import { advertisedCampaigns, retainedCampaign } from "../src/v2/campaign-registry";
import fixture from "./fixtures/campaign-control-v2.json";

afterEach(async () => { await reset(); });
it("keeps the actual production registry empty even if flags or a client body request the test campaign", async () => {
  const owner = randomToken(16), token = randomToken(), configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", CAMPAIGN_CREATION_ENABLED: "true", CAMPAIGN_MUTATIONS_ENABLED: "true" });
  expect((await env.PLAYERS.getByName(owner).create(owner, await digest(token), "b".repeat(64))).ok).toBe(true);
  const headers = { "X-Player-Id": owner, Authorization: "Bearer " + token, "X-AfterYou-Campaign-Schema": "2", "Content-Type": "application/json" };
  expect(advertisedCampaigns(configured)).toEqual([]); expect(retainedCampaign(fixture.active_view.campaign_key)).toBeUndefined();
  const cap = await worker.fetch(new Request("https://campaign.test/v2/capabilities", { headers }), configured);
  expect(cap.status).toBe(200); expect(await cap.json()).toMatchObject({ campaign_control_version: 2, campaign_creation_enabled: false, campaign_definitions: [] });
  const attempt = await worker.fetch(new Request("https://campaign.test/v2/campaigns", { method: "POST", headers,
    body: JSON.stringify({ schema_version: 1, idempotency_key: "unregistered-campaign-create", campaign_key: fixture.active_view.campaign_key }) }), configured);
  expect(attempt.status).toBe(503); expect(await attempt.json()).toMatchObject({ error: { code: "campaign_creation_disabled" } });
  expect(await env.PLAYERS.getByName(owner).listRooms()).toEqual([]);
});
