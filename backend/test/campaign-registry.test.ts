import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, randomToken } from "../src/protocol";
import { chapter } from "../src/v2/chapters";
import { advertisedCampaigns, campaignCreatable, exactCampaignDefinition, retainedCampaign } from "../src/v2/campaign-registry";
import bundle from "../../game/content/campaigns/a-place-for-two-v1.json";
import fixture from "./fixtures/campaign-control-v2.json";

afterEach(async () => { await reset(); });
const wanted = { campaign_id: bundle.definition.campaign_id, campaign_version: bundle.definition.campaign_version,
  definition_hash: bundle.definition.definition_hash };
function enabled(): Env {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", CAMPAIGN_CREATION_ENABLED: "true", CAMPAIGN_MUTATIONS_ENABLED: "true",
    FIRST_STEPS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true", HOUSE_CHAPTER_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: "true" });
  return configured;
}

it("validates the shared content hashes and seven current rules against the existing chapter adapters", async () => {
  const { content_hash, ...body } = bundle.story;
  expect(await digest(canonicalJson(body))).toBe(content_hash);
  expect(content_hash).toBe("015ace9140afb2d67c9acd47506a8108dd838e98278a9ac479166290e45fef16");
  const definition = await exactCampaignDefinition(bundle.definition,wanted);
  expect(definition.definition_hash).toBe("41ae5d6498f3691774075508fe900bfc1fcc14e82be9035494097fed132fe1c1");
  expect(definition.story).toEqual({ story_id:bundle.story.story_id, story_version:bundle.story.story_version, content_hash });
  expect(definition.chapters.map(pin => pin.level_id)).toEqual(["first-steps","relay-isles","high-and-low","rolling-home","a-house-for-two","conservatory","long-way-home"]);
  expect(definition.chapters.map(pin => pin.premium)).toEqual([false,false,false,true,true,true,true]);
  for (const pin of definition.chapters) {
    const adapter = chapter(pin);
    expect(pin.simulation_version).toBe(8);
    expect(adapter.supported_simulation_versions).toContain(8);
    expect(pin.premium).toBe(adapter.premium);
  }
  expect(retainedCampaign(wanted)).toEqual(definition);
  expect(advertisedCampaigns(enabled())).toEqual([definition]);
  const changed = retainedCampaign(wanted)!;
  changed.chapters[0].simulation_version = 99;
  expect(retainedCampaign(wanted)).toEqual(definition);
});

it("keeps retention independent of the existing admission and chapter flag gates", () => {
  const configured = enabled();
  expect(campaignCreatable(wanted,configured)).toBe(true);
  Object.assign(configured,{ CAMPAIGN_CREATION_ENABLED:"false", CAMPAIGN_MUTATIONS_ENABLED:"false" });
  expect(campaignCreatable(wanted,configured)).toBe(false);
  expect(retainedCampaign(wanted)).toEqual(bundle.definition);
  for (const flag of ["FIRST_STEPS_ENABLED","COOP_CHAPTERS_ENABLED","HOUSE_CHAPTER_ENABLED","JOURNEY_CHAPTERS_ENABLED"]) {
    const paused = enabled(); Object.assign(paused,{ [flag]:"false" });
    expect(advertisedCampaigns(paused)).toEqual([]);
    expect(campaignCreatable(wanted,paused)).toBe(false);
    expect(retainedCampaign(wanted)).toEqual(bundle.definition);
  }
});

it("advertises only the reviewed bundle and refuses a client-supplied unregistered campaign", async () => {
  const owner = randomToken(16), token = randomToken(), configured = enabled();
  expect((await env.PLAYERS.getByName(owner).create(owner,await digest(token),"b".repeat(64))).ok).toBe(true);
  const headers = { "X-Player-Id":owner, Authorization:"Bearer "+token, "X-AfterYou-Campaign-Schema":"2", "Content-Type":"application/json" };
  expect(retainedCampaign(fixture.active_view.campaign_key)).toBeUndefined();
  const cap = await worker.fetch(new Request("https://campaign.test/v2/capabilities",{ headers }),configured);
  expect(cap.status).toBe(200);
  expect(await cap.json()).toMatchObject({ campaign_control_version:2, campaign_creation_enabled:true, campaign_definitions:[bundle.definition] });
  const attempt = await worker.fetch(new Request("https://campaign.test/v2/campaigns",{ method:"POST", headers,
    body:JSON.stringify({ schema_version:1, idempotency_key:"unregistered-campaign-create", campaign_key:fixture.active_view.campaign_key }) }),configured);
  expect(attempt.status).toBe(503);
  expect(await attempt.json()).toMatchObject({ error:{ code:"campaign_creation_disabled" } });
  expect(await env.PLAYERS.getByName(owner).listRooms()).toEqual([]);
  Object.assign(configured,{ CAMPAIGN_CREATION_ENABLED:"false" });
  const paused = await worker.fetch(new Request("https://campaign.test/v2/capabilities",{ headers }),configured);
  expect(await paused.json()).toMatchObject({ campaign_creation_enabled:false, campaign_definitions:[bundle.definition] });
});
