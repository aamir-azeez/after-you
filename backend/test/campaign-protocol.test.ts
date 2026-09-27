import { describe, expect, it } from "vitest";
import fixture from "./fixtures/campaign-contract.json";
import { canonicalJson, digest } from "../src/protocol";
import { boundedCampaign, campaignContinue, campaignContinueKey, campaignContinueResult, campaignCreate, campaignDefinition, campaignEnvelope, campaignJoin, campaignList, campaignRequestHash, campaignView, continueOrigin } from "../src/v2/campaign-protocol";
import type { CampaignContinue, CampaignDefinition, CampaignKey, CampaignView } from "../src/v2/campaign-types";

const copy = <T>(value: T): T => structuredClone(value);
const definition = fixture.definition as CampaignDefinition;
const active = fixture.active_view as CampaignView;
const body = fixture.continue_body as CampaignContinue;
const owner = active.host_id, anchor = active.campaign_room_id;
const registry = (key: CampaignKey) => canonicalJson(key) === canonicalJson(active.campaign_key) ? definition : undefined;
const verifyPin = (pin: unknown) => definition.chapters.some(known => canonicalJson(known) === canonicalJson(pin));
async function rehash(value: CampaignDefinition): Promise<CampaignDefinition> {
  const { definition_hash: _, ...content } = value;
  value.definition_hash = await digest(canonicalJson(content));
  return value;
}
function completed(): CampaignView {
  const value = copy(fixture.accepted_result.campaign) as CampaignView;
  value.revision = 5; value.state = "complete";
  value.chapters[1].completion = { source_revision: 5, source_branch: 0, checkpoint_hash: "e".repeat(64), transition_id: "d".repeat(64), from_campaign_revision: 3, accepted_campaign_revision: 5 };
  return value;
}

describe("bounded campaign wire contract (no registered production manifest or routes)", () => {
  it("accepts only a bound terminal fork receipt, including after a newer branch completed", async () => {
    for (const result of [fixture.rejected_result,fixture.rejected_newer_result,fixture.rejected_equal_result]) {
      expect(await campaignContinueResult(result,anchor,owner,body,registry)).toEqual(result);
    }
    for (const invalid of fixture.invalid_rejections) {
      await expect(campaignContinueResult(invalid.result,anchor,owner,body,registry),invalid.id).rejects.toThrow();
    }
  });
  it("pins story and adapter metadata in the canonical definition, returning a detached value", async () => {
    const result = await campaignDefinition(definition, verifyPin);
    expect(result).toEqual(definition); result.story.story_id = "changed";
    expect(definition.story.story_id).toBe("fixture-story");
    const changed = copy(definition); changed.story.content_hash = "f".repeat(64);
    await expect(campaignDefinition(changed, verifyPin)).rejects.toMatchObject({ code: "campaign_definition_hash_mismatch" });
    changed.chapters[1].premium = false;
    await expect(campaignDefinition(await rehash(changed), verifyPin)).rejects.toMatchObject({ code: "unsupported_campaign_chapter" });
  });
  it("requires the narrative pin and two through eight entries before hashing", async () => {
    const missing = copy(definition) as unknown as Record<string, unknown>; delete missing.story;
    await expect(campaignDefinition(missing, verifyPin)).rejects.toThrow();
    for (const count of [1,9]) {
      const changed = copy(definition); changed.chapters = Array.from({length:count},()=>copy(definition.chapters[0]));
      await expect(campaignDefinition(await rehash(changed), verifyPin)).rejects.toThrow();
    }
    const eight = copy(definition); eight.chapters = Array.from({length:8},()=>copy(definition.chapters[0]));
    expect((await campaignDefinition(await rehash(eight),verifyPin)).chapters).toHaveLength(8);
  });
  it("matches native canonical key/request-hash preimages exactly", async () => {
    expect(canonicalJson(fixture.idempotency_key_preimage)).toBe(fixture.idempotency_key_canonical_json);
    expect(canonicalJson(fixture.request_hash_preimage)).toBe(fixture.request_hash_canonical_json);
    expect(await campaignContinueKey(anchor,body.campaign_key,owner,continueOrigin(body))).toBe(body.idempotency_key);
    expect(await campaignRequestHash(anchor,owner,body)).toBe(fixture.expected_request_hash);
    expect(await campaignContinue(body,anchor,owner,registry)).toEqual(body);
  });
  it("binds Continue to owner, source branch/checkpoint and exact saved request", async () => {
    await expect(campaignContinue(body,anchor,active.guest_id!,registry)).rejects.toMatchObject({code:"campaign_idempotency_mismatch"});
    const changed = copy(body); changed.source.branch++;
    await expect(campaignContinue(changed,anchor,owner,registry)).rejects.toMatchObject({code:"campaign_idempotency_mismatch"});
    changed.idempotency_key = await campaignContinueKey(anchor,changed.campaign_key,owner,continueOrigin(changed));
    expect(await campaignContinue(changed,anchor,owner,registry)).toEqual(changed);
    await expect(campaignContinueResult(fixture.accepted_result,anchor,owner,changed,registry)).rejects.toThrow();
  });
  it("validates exact host invitation-to-anchor and hides it from the guest projection", async () => {
    expect(await campaignView(active,owner,registry)).toEqual(active);
    const wrong = copy(active); wrong.invite_code = "CD".repeat(10);
    await expect(campaignView(wrong,owner,registry)).rejects.toMatchObject({code:"campaign_invite_mismatch"});
    const guest = copy(active); guest.player_slot = "p1"; guest.invite_code = null; guest.invite_expires_at = null;
    expect(await campaignView(guest,guest.guest_id!,registry)).toEqual(guest);
    await expect(campaignView(active,active.guest_id!,registry)).rejects.toThrow();
    await expect(campaignView(active,"X".repeat(22),registry)).rejects.toMatchObject({code:"campaign_owner_mismatch"});
  });
  it.each(fixture.invalid_views)("rejects shared native/server counterexample $id", async ({view}) => {
    await expect(campaignView(view,owner,registry)).rejects.toThrow();
  });
  it("validates calendar UTC with exact milliseconds, including year zero", async () => {
    const value = copy(active); value.invite_expires_at = "0000-02-29T00:00:00.000Z";
    expect((await campaignView(value,owner,registry)).invite_expires_at).toBe(value.invite_expires_at);
    for (const date of ["2026-02-29T00:00:00.000Z","2026-09-27T13:00:00.000+00:00","2026-09-27T24:00:00.000Z"]) {
      value.invite_expires_at = date; await expect(campaignView(value,owner,registry)).rejects.toThrow();
    }
  });
  it("requires completed prefix, distinct room identities and pinned catalog entries", async () => {
    const value = copy(fixture.accepted_result.campaign);
    value.chapters[0].completion = null as never;
    await expect(campaignView(value,owner,registry)).rejects.toThrow();
    const duplicate = copy(fixture.accepted_result.campaign); duplicate.chapters[1].room_id = anchor;
    await expect(campaignView(duplicate,owner,registry)).rejects.toThrow();
    const future = copy(active); future.chapters[1].room_id = "B".repeat(22);
    await expect(campaignView(future,owner,registry)).rejects.toThrow();
    const pin = copy(active); pin.chapters[0].chapter.premium = true;
    await expect(campaignView(pin,owner,registry)).rejects.toMatchObject({code:"campaign_chapter_mismatch"});
  });
  it("retains terminal completion when deletion starts from a completed campaign", async () => {
    const value = completed(); expect(await campaignView(value,owner,registry)).toEqual(value);
    value.state = "deleting"; expect(await campaignView(value,owner,registry)).toEqual(value);
    value.state = "active"; await expect(campaignView(value,owner,registry)).rejects.toThrow();
  });
  it("allows waiting and deletion before a partner joins, but not active play", async () => {
    const value = copy(active); value.guest_id = null; value.state = "waiting";
    expect(await campaignView(value,owner,registry)).toEqual(value);
    value.state = "deleting"; expect(await campaignView(value,owner,registry)).toEqual(value);
    value.state = "active"; await expect(campaignView(value,owner,registry)).rejects.toThrow();
  });
  it("validates pending and accepted responses and permits an old accepted receipt with a newer completed view", async () => {
    expect(await campaignContinueResult(fixture.pending_result,anchor,owner,body,registry)).toEqual(fixture.pending_result);
    expect(await campaignContinueResult(fixture.accepted_result,anchor,owner,body,registry)).toEqual(fixture.accepted_result);
    const result = {...copy(fixture.accepted_result),campaign:completed()};
    expect(await campaignContinueResult(result,anchor,owner,body,registry)).toEqual(result);
    result.campaign.chapters[0].completion!.checkpoint_hash = "f".repeat(64);
    await expect(campaignContinueResult(result,anchor,owner,body,registry)).rejects.toThrow();
  });
  it("rejects mixed pending/accepted unions and receipts with invented targets", async () => {
    await expect(campaignContinueResult({...fixture.pending_result,receipt:fixture.accepted_result.receipt},anchor,owner,body,registry)).rejects.toThrow();
    const result = copy(fixture.accepted_result); result.receipt.next_room_id = "X".repeat(22);
    await expect(campaignContinueResult(result,anchor,owner,body,registry)).rejects.toThrow();
  });
  it("accepts terminal Finish with no new room, including deletion after completion", async () => {
    const view=completed(), completion=view.chapters[1].completion!;
    const last:CampaignContinue={schema_version:1,idempotency_key:"",campaign_key:view.campaign_key,expected_revision:3,from_index:1,source:{room_id:view.chapters[1].room_id!,revision:5,branch:0,checkpoint_hash:completion.checkpoint_hash}};
    last.idempotency_key=await campaignContinueKey(anchor,last.campaign_key,owner,continueOrigin(last));
    const result={schema_version:1,operation:"campaign_continue",status:"accepted",campaign:view,receipt:{schema_version:1,operation:"campaign_continue",campaign_room_id:anchor,campaign_key:view.campaign_key,player_id:owner,idempotency_key:last.idempotency_key,request_hash:await campaignRequestHash(anchor,owner,last),transition_id:completion.transition_id,origin:continueOrigin(last),accepted_revision:5,outcome:"finished",next_index:null,next_room_id:null}};
    expect(await campaignContinueResult(result,anchor,owner,last,registry)).toEqual(result);
    result.campaign.state="deleting";
    expect(await campaignContinueResult(result,anchor,owner,last,registry)).toEqual(result);
    await expect(campaignContinueResult({...result,receipt:{...result.receipt,next_room_id:"X".repeat(22)}},anchor,owner,last,registry)).rejects.toThrow();
  });
  it("rejects unsupported campaigns and joins missing any bundled simulation version", () => {
    expect(campaignCreate({schema_version:1,idempotency_key:"C".repeat(22),campaign_key:active.campaign_key},registry).campaign_key).toEqual(active.campaign_key);
    expect(()=>campaignCreate({schema_version:1,idempotency_key:"C".repeat(22),campaign_key:{...active.campaign_key,definition_hash:"f".repeat(64)}},registry)).toThrow();
    const join={schema_version:1,invite_code:active.invite_code,campaign_key:active.campaign_key,supported_simulation_versions:[2,4,5,6]};
    expect(campaignJoin(join,registry)).toEqual(join);
    expect(()=>campaignJoin({...join,supported_simulation_versions:[2,4,5]},registry)).toThrow();
    expect(()=>campaignJoin({...join,supported_simulation_versions:[6,6]},registry)).toThrow();
  });
  it("bounds list count and unique anchors, and returns detached validated envelopes", async () => {
    const result=await campaignEnvelope({campaign:active},owner,registry); result.campaign.revision++;
    expect(active.revision).toBe(1);
    expect(await campaignList({campaigns:[]},owner,registry)).toEqual({campaigns:[]});
    await expect(campaignList({campaigns:[active,active]},owner,registry)).rejects.toThrow();
    await expect(campaignList({campaigns:Array(21).fill(active)},owner,registry)).rejects.toThrow();
    const twenty:CampaignView[]=[];
    for(let index=0;index<20;index++) {
      const value=copy(active);value.invite_code=index.toString(16).toUpperCase().padStart(20,"0");
      value.campaign_room_id=(await digest("v2:"+value.invite_code)).slice(0,22);value.chapters[0].room_id=value.campaign_room_id;twenty.push(value);
    }
    expect((await campaignList({campaigns:twenty},owner,registry)).campaigns).toHaveLength(20);
  });
  it("rejects excess bytes, nodes, depth, cycles, non-JSON and nonfinite numbers before hashing", () => {
    expect(()=>boundedCampaign({proof:"x".repeat(16384)})).toThrow();
    expect(()=>boundedCampaign(Array(2048).fill(0))).toThrow();
    let deep:unknown=0; for(let i=0;i<13;i++)deep={child:deep};
    expect(()=>boundedCampaign(deep)).toThrow();
    const cycle:Record<string,unknown>={};cycle.self=cycle;
    for(const value of [cycle,undefined,NaN,Infinity,new Date()])expect(()=>boundedCampaign(value)).toThrow();
    expect(()=>boundedCampaign({x:1},7)).not.toThrow();expect(()=>boundedCampaign({x:1},6)).toThrow();
  });
  it("rejects missing, extra, fractional and unsafe fields without mutating input", async () => {
    const before=canonicalJson(active);
    await expect(campaignView({...active,proof:{}},owner,registry)).rejects.toThrow();
    const missing=copy(active) as unknown as Record<string,unknown>;delete missing.transition;
    await expect(campaignView(missing,owner,registry)).rejects.toThrow();
    for(const revision of [1.5,Number.MAX_SAFE_INTEGER+1,-1])await expect(campaignView({...active,revision},owner,registry)).rejects.toThrow();
    expect(canonicalJson(active)).toBe(before);
  });
});
