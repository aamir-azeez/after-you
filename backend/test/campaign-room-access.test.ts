// Retained Story protocol coverage; production withdrawal is tested without
// this test-only substitution in campaign-production.test.ts.
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => true, requireCampaignProduction: () => {}
}));

import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { initializeCampaignRoot, joinCampaignRoot } from "../src/v2/campaign-root";
import { initializeCampaignTarget, activateCampaignTarget, type TargetInitializeRequest } from "../src/v2/campaign-target";
import { prepareCampaignHttpAccess, campaignHttpAccessGuard, type CampaignRoomContext } from "../src/v2/campaign-room-access";
import { prepareCampaignAccess, campaignSource } from "../src/v2/campaign-source";
import { eraseCampaignChild } from "../src/v2/campaign-deletion";
import type { CampaignDefinition, CampaignKey } from "../src/v2/campaign-types";
import type { StoredCampaignAnchorV2, StoredCampaignMemberV2 } from "../src/v2/campaign-storage";
import type { RoomStateV2 } from "../src/v2/room";
import type { CampaignRedoBinding } from "../src/v2/campaign-redo";
import type { RedoState } from "../src/redo-control";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import final from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";
import rollingA from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";
import rollingB from "../../game/tests/fixtures/cooperative/weight-of-a-friend-b.json";
import rollingMiddle from "../../game/tests/fixtures/cooperative/weight-of-a-friend-checkpoint.json";
import homeA from "../../game/tests/fixtures/cooperative/bring-it-home-a.json";
import homeB from "../../game/tests/fixtures/cooperative/bring-it-home-b.json";
import homeFinal from "../../game/tests/fixtures/cooperative/rolling-home-final-checkpoint.json";

const definition = fixture.definition as CampaignDefinition, key = fixture.active_view.campaign_key as CampaignKey;
const R = fixture.active_view.campaign_room_id, I = fixture.active_view.invite_code!, T = "a".repeat(43), TOKEN = "c".repeat(64);
const resolver = (k: CampaignKey) => canonicalJson(k) === canonicalJson(key) ? definition : undefined;
let H = "", G = "", hash = "", address = 0;
const value = <T>(r: Outcome<T>): T => { if (!r.ok) throw new Error(r.code); return r.value; };
const context = (room = R): CampaignRoomContext => ({ schema_version: 2, room_id: room, device_hash: hash });
const root = () => env.ROOMS_V2.getByName(R);
const anchor = (ctx: DurableObjectState) => JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data) as StoredCampaignAnchorV2;
const gameplay = (ctx: DurableObjectState) => JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data) as RoomStateV2;
async function socialBoundaryInventory(stub: ReturnType<typeof root>) {
  return runInDurableObject(stub, async (_, ctx) => ({ alarm: await ctx.storage.getAlarm(), kv: [...ctx.storage.kv.list()],
    tables: ctx.storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray().map(table => ({
      ...table, rows: isAlarmMetadataTable(table) ? null : ctx.storage.sql.exec('SELECT * FROM "' + table.name + '" ORDER BY rowid').toArray()
    })) }));
}
async function call(path: string, method = "GET", body?: unknown, negotiation: string | null = "2", owner = H, token = T) {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", PRESENCE_ENABLED: "true", PRESET_REACTIONS_ENABLED: "true", PHOTO_DELIVERY_ENABLED: "true" });
  return worker.fetch(new Request("https://campaign.test" + path, { method, headers: {
    "Content-Type": "application/json", "CF-Connecting-IP": "198.19.0." + ++address, "X-Player-Id": owner, Authorization: "Bearer " + token,
    ...(negotiation === null ? {} : { "X-AfterYou-Campaign-Schema": negotiation })
  }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function setup(joined = true) {
  for (const owner of [H, G]) value(await env.PLAYERS.getByName(owner).create(owner, hash, "b".repeat(64)));
  value(await runInDurableObject(root(), (_, ctx) => initializeCampaignRoot(ctx.storage, { schema_version: 1, host_id: H,
    intent: { creation_schema: 2, link: { room_id: R, invite_code: I, host: true, api_version: 3 }, campaign_key: key } }, resolver)));
  if (joined) value(await runInDurableObject(root(), (_, ctx) => joinCampaignRoot(ctx.storage, G, { schema_version: 2, idempotency_key: "http-join-attempt-0001", invite_code: I, campaign_key: key, supported_simulation_versions: [6] }, resolver)));
}
async function complete() {
  let state = value(await root().snapshot(H, context()));
  const bodies = [];
  for (const [owner, recording, checkpoint] of [[H, highA, null], [G, highB, middle], [G, lowA, null], [H, lowB, final]] as const) {
    const body = { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) };
    state = value(await root().commit(owner, body, context())).room; bodies.push({ owner, body });
  }
  return { state, bodies };
}
async function published(debt = false, activate = true) {
  await setup(); const played = await complete();
  const invite = "EF".repeat(10), id = (await digest("v2:" + invite)).slice(0, 22);
  const origin = { expected_revision: 1, from_index: 0, source: { room_id: R, revision: played.state.revision, branch: 0, checkpoint_hash: final.checkpoint_hash } };
  const target = { room_id: id, invite_code: invite, index: 1, chapter: definition.chapters[1] };
  const request: TargetInitializeRequest = { schema_version: 1, binding: { campaign_room_id: R, campaign_key: key, room_id: id, chapter_index: 1, chapter: definition.chapters[1], host_id: H, guest_id: G, member_transition_id: TOKEN }, origin, target_intent: target };
  await runInDurableObject(root(), (_, ctx) => {
    const a = anchor(ctx), m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMemberV2;
    a.control.current_index = 1; a.control.revision = 5;
    a.control.chapters[0].completion = { source_revision: played.state.revision, source_branch: 0, checkpoint_hash: final.checkpoint_hash, transition_id: TOKEN, from_campaign_revision: 1, accepted_campaign_revision: 5 };
    a.control.chapters[1].room_id = id;
    if (debt) { a.control.activation = { transition_id: TOKEN }; a.activation = { transition_id: TOKEN, origin, target_intent: target, accepted_revision: 5 }; }
    m.status = "sealed"; m.seal = { transition_id: TOKEN, origin };
    ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m));
  });
  const child = env.ROOMS_V2.getByName(id);
  value(await runInDurableObject(child, (_, ctx) => initializeCampaignTarget(ctx.storage, request, resolver)));
  if (activate) value(await runInDurableObject(child, (_, ctx) => activateCampaignTarget(ctx.storage, { ...request, accepted_revision: 5 }, resolver)));
  return { ...played, child, id, request };
}
beforeEach(async () => { H = randomToken().slice(0, 22); G = randomToken().slice(0, 22); hash = await digest(T); });
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("fixed campaign room HTTP authority", () => {
  it("never projects a campaign root or child invite through ordinary friend sharing", async () => {
    const p = await published();
    const requested = await call("/v1/friends/request", "POST", { schema_version: 1, friend_code: G });
    expect(requested.status).toBe(200);
    const requestId = (await requested.json<{ request_id: string }>()).request_id;
    expect((await call("/v1/friends/accept", "POST", { schema_version: 1, player_id: H, request_id: requestId }, "2", G)).status).toBe(200);
    for (const [id, stub] of [[R, root()], [p.id, p.child]] as const) {
      const before = await socialBoundaryInventory(stub);
      expect(await stub.friendInvite(H, G)).toMatchObject({ ok: false, status: 409, code: "campaign_social_unavailable" });
      const share = await call("/v1/friends/share", "POST", { schema_version: 1, room: { api_version: 2, room_id: id } });
      expect(share.status).toBe(409); expect(await share.json()).toMatchObject({ error: { code: "campaign_social_unavailable" } });
      // A retained stale pointer cannot become an invitation either.
      await runInDurableObject(env.PLAYERS.getByName(H), (_, ctx) => {
        const identity = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data);
        identity.social.shared_room = { api_version: 2, room_id: id };
        ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
      });
      const descriptor = await call(`/v1/friends/${H}/join`, "POST", { schema_version: 1, request_id: requestId }, "2", G);
      expect(descriptor.status).toBe(409); expect(await descriptor.json()).toMatchObject({ error: { code: "friend_not_joinable" } });
      expect(await socialBoundaryInventory(stub)).toEqual(before);
    }
    const listed = await call("/v1/friends", "GET", undefined, "2", G);
    expect(listed.status).toBe(200);
    expect(await listed.json()).toMatchObject({ friends: [{ player_id: H, join_available: false }] });
  });
  it("holds ordinary redo on campaign roots and children without changing their history", async () => {
    const p = await published();
    value(await env.PLAYERS.getByName(H).redeemTesterAccess(H, hash, true));
    for (const [id, stub] of [[R, root()], [p.id, p.child]] as const) {
      const before = await socialBoundaryInventory(stub), s = value(await stub.snapshot(H, context(id)));
      const mutation = { action: "request", source: { room_id: id, revision: s.revision, branch: s.branch, stage_index: s.stage_index,
        a_hash: "a".repeat(64), first_player_id: H, second_player_id: G } };
      expect(await stub.redo(H, undefined, hash)).toMatchObject({ ok: false, status: 409, code: "campaign_redo_unavailable" });
      for (const [method, body] of [["GET", undefined], ["POST", mutation]] as const) {
        const response = await call(`/v2/rooms/${id}/redo`, method, body);
        expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ error: { code: "campaign_redo_unavailable" } });
      }
      const fork = { base_revision: s.revision, branch: s.branch, stage_index: 0, idempotency_key: "campaign-redo-fork-001", redo_request_id: "b".repeat(64) };
      expect(await stub.fork(H, fork, context(id), hash)).toMatchObject({ ok: false, status: 409, code: "campaign_redo_unavailable" });
      const response = await call(`/v2/rooms/${id}/fork`, "POST", fork);
      expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ error: { code: "campaign_redo_unavailable" } });
      expect(await socialBoundaryInventory(stub)).toEqual(before);
    }
  });
  const branches: [string, string, unknown?][] = [
    ["", "GET"], ["", "DELETE"], ["/operations/accepted-turn-key-01", "GET"], ["/collection", "GET"], ["/pairs/p0-0", "GET"],
    ["/photos/t0-0-a", "GET"], ["/photos/t0-0-a", "POST", {}], ["/photos/t0-0-a", "DELETE", {}],
    ["/photos/t0-0-a/delivery", "GET"], ["/photos/t0-0-a/ack", "POST", {}],
    ["/photo-operations/saved-photo-key-001", "GET"], ["/reactions/p0-0", "GET"], ["/reactions/p0-0", "POST", {}],
    ["/reaction-operations/saved-react-key-001", "GET"], ["/turns", "POST", {}], ["/fork", "POST", {}], ["/presence", "GET"]
  ];
  it.each(branches)("holds absent/wrong negotiation on %s %s before protected access", async (suffix, method, body) => {
    await setup();
    for (const header of [null, "1", "3"]) {
      const r = await call(`/v2/rooms/${R}${suffix}`, method, body, header);
      expect(r.status).toBe(409); expect(await r.json()).toMatchObject({ error: { code: "campaign_client_required" } });
    }
  });
  it("keeps ordinary reads unchanged with and without campaign negotiation", async () => {
    value(await env.PLAYERS.getByName(H).create(H, hash, "b".repeat(64)));
    value(await root().initialize(R, H, I, definition.chapters[0]));
    const a = await call(`/v2/rooms/${R}`, "GET", undefined, null), b = await call(`/v2/rooms/${R}`);
    expect(a.status).toBe(200); expect(b.status).toBe(200); expect(await a.json()).toEqual(await b.json());
  });
  it("admits a waiting host's real A, joined B and exact snapshot without extra public fields", async () => {
    await setup(false); let s = value(await root().snapshot(H, context()));
    const body = { base_revision: s.revision, branch: 0, idempotency_key: "host-a-before-join", recording: highA };
    const r = await call(`/v2/rooms/${R}/turns`, "POST", body); expect(r.status).toBe(200);
    expect(await r.json()).toMatchObject({ room: { guest_id: null, recording_a: highA } });
    value(await runInDurableObject(root(), (_, ctx) => joinCampaignRoot(ctx.storage, G, { schema_version: 2, idempotency_key: "join-after-source-01", invite_code: I, campaign_key: key, supported_simulation_versions: [6] }, resolver)));
    s = value(await root().snapshot(G, context()));
    expect((await call(`/v2/rooms/${R}/turns`, "POST", { base_revision: s.revision, branch: 0, idempotency_key: "guest-b-after-join", recording: highB, checkpoint: middle }, "2", G)).status).toBe(200);
    const snapshot = value(await root().snapshot(H, context()));
    expect(snapshot.stage_index).toBe(1); expect(Object.keys(snapshot)).not.toContain("campaign");
    expect(await env.PLAYERS.getByName(H).listRooms()).toEqual([]);
  });
  it("requires exact route, owner and original device even with the supported header", async () => {
    await setup();
    expect(await root().snapshot(H)).toMatchObject({ ok: false, code: "campaign_client_required" });
    expect(await root().snapshot(H, { ...context(), room_id: "Z".repeat(22) })).toMatchObject({ ok: false, code: "campaign_binding_mismatch" });
    expect(await root().snapshot(H, { ...context(), device_hash: "0".repeat(64) })).toMatchObject({ ok: false, status: 401 });
    expect(await root().snapshot("Z".repeat(22), context())).toMatchObject({ ok: false, status: 403 });
    expect(await root().snapshot(H, { ...context(), unexpected: true } as CampaignRoomContext)).toMatchObject({ ok: false, code: "campaign_client_required" });
  });
  it("blocks an already activated child until the anchor activation debt is discharged", async () => {
    const p = await published(true);
    expect(await p.child.snapshot(H, context(p.id))).toMatchObject({ ok: false, code: "campaign_activation_pending" });
    expect((await call(`/v2/rooms/${R}/pairs/p0-0`)).status).toBe(200);
    await runInDurableObject(root(), (_, ctx) => { const a = anchor(ctx); a.activation = null; a.control.activation = null; a.control.revision++; ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); });
    expect(value(await p.child.snapshot(H, context(p.id))).level_id).toBe("rolling-home");
  });
  it("never exposes a provisional target through a supported request", async () => {
    const p = await published(true, false);
    const r = await call(`/v2/rooms/${p.id}`); expect(r.status).toBe(409);
    await runInDurableObject(p.child, (_, ctx) => expect(gameplay(ctx)).toMatchObject({ revision: 1, stage_index: 0, a_turn_id: null }));
  });
  it("keeps sealed historical reaction metadata and presence behind the same published-room boundary", async () => {
    const p = await published();
    const body = { idempotency_key: "historical-reaction-http", a_hash: highA.recording_hash, b_hash: highB.recording_hash, expected_reaction_revision: 0, reaction: "love" };
    const written = await call(`/v2/rooms/${R}/reactions/p0-0`, "POST", body); expect(written.status).toBe(200); const receipt = await written.json();
    const operation = await call(`/v2/rooms/${R}/reaction-operations/${body.idempotency_key}`); expect(operation.status).toBe(200); expect(await operation.json()).toEqual(receipt);
    expect((await call(`/v2/rooms/${R}/photos/t0-0-a`)).status).toBe(200);
    const presence = await call(`/v2/rooms/${p.id}/presence`); expect(presence.status).toBe(200); expect(await presence.json()).toMatchObject({ partner_joined: true, partner_online: false });
  });
  it("uses named anchor publication for child gameplay and accepted premium retry without another purchase", async () => {
    const p = await published(), s = value(await p.child.snapshot(H, context(p.id)));
    const body = { base_revision: s.revision, branch: 0, idempotency_key: "premium-accepted-key-01", recording: rollingA };
    const accepted = value(await p.child.commit(H, body, context(p.id)));
    const r = await call(`/v2/rooms/${p.id}/turns`, "POST", body); expect(r.status).toBe(200); expect(await r.json()).toEqual(accepted);
    expect((await call(`/v2/rooms/${p.id}/turns`, "POST", body, null)).status).toBe(409);
    expect(await env.PLAYERS.getByName(G).listRooms()).toEqual([]);
  });
  it("checks the premium host only for new parent-bound redo acceptance, not accepted receipt recovery", async () => {
    const p = await published(), s = value(await p.child.snapshot(H, context(p.id))), path = `/v2/campaigns/${R}/chapters/1/redo`;
    value(await p.child.commit(H, { base_revision: s.revision, branch: s.branch, idempotency_key: "premium-redo-source-a", recording: rollingA }, context(p.id)));
    const overrides = { V2_ROOMS_ENABLED: "true", CAMPAIGN_MUTATIONS_ENABLED: "true", REVENUECAT_VERIFICATION_MODE: "demo",
      REVENUECAT_API_VERSION: "1", REVENUECAT_SECRET_KEY: "synthetic-only" };
    let local: Record<string, unknown> = {}, previous: Record<string, unknown> = {};
    await runInDurableObject(p.child, instance => {
      local = Reflect.get(instance, "env"); previous = Object.fromEntries(Object.keys(overrides).map(k => [k, local[k]])); Object.assign(local, overrides);
    });
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 404 }));
    try {
      const get = await call(path, "GET", undefined, "2", G); expect(get.status).toBe(200);
      const offered = await get.json<{ binding: CampaignRedoBinding; redo: RedoState }>();
      const requested = await call(path, "POST", { schema_version: 1, binding: offered.binding, source: offered.redo.source, action: "request" }, "2", G);
      expect(requested.status).toBe(200); const pending = await requested.json<{ redo: RedoState }>();
      const body = { schema_version: 1, binding: offered.binding, source: pending.redo.source, request_id: pending.redo.request!.request_id,
        idempotency_key: "premium-parent-redo-001" };
      const denied = await call(path + "/accept", "POST", body); expect(denied.status).toBe(402);
      expect(await denied.json()).toMatchObject({ error: { code: "host_unlock_required" } });
      value(await env.PLAYERS.getByName(H).redeemTesterAccess(H, hash, true));
      expect(await env.PLAYERS.getByName(G).storedTesterGrant(G)).toBeNull();
      const accepted = await call(path + "/accept", "POST", body); expect(accepted.status).toBe(200); const receipt = await accepted.json();
      await runInDurableObject(env.PLAYERS.getByName(H), instance => {
        vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "storedTesterGrant").mockImplementation(() => { throw new Error("unexpected_entitlement_retry"); });
      });
      for (const [endpoint, method, input] of [[path + "/accept", "POST", body], [path + "/operations/" + body.idempotency_key, "GET", undefined]] as const) {
        const recovered = await call(endpoint, method, input); expect(recovered.status).toBe(200); expect(await recovered.json()).toEqual(receipt);
      }
      expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    } finally { Object.assign(local, previous); }
  });
  it("keeps a sealed source receipt readable while refusing fresh forks", async () => {
    const p = await published(), old = p.bodies[0];
    expect(value(await root().commit(old.owner, old.body, context())).receipt.idempotency_key).toBe(old.body.idempotency_key);
    expect(await root().fork(H, { base_revision: p.state.revision, branch: 0, stage_index: 0, idempotency_key: "fresh-fork-after-seal" }, context())).toMatchObject({ ok: false, code: "campaign_source_sealed" });
  });
  it("rejects a separately valid child incoming origin that disagrees with published completion", async () => {
    const p = await published();
    await runInDurableObject(p.child, async (_, ctx) => {
      const m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMemberV2;
      m.incoming!.origin.source.checkpoint_hash = "0".repeat(64);
      ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m));
      expect(await prepareCampaignAccess(ctx.storage, resolver)).not.toBeNull();
    });
    expect(await p.child.snapshot(H, context(p.id))).toMatchObject({ ok: false, code: "campaign_binding_mismatch" });
  });
  it("binds a separately valid child's outgoing seal to the exact published completion", async () => {
    const p = await published(); let state = value(await p.child.snapshot(H, context(p.id)));
    for (const [owner, recording, checkpoint] of [[H, rollingA, null], [G, rollingB, rollingMiddle], [G, homeA, null], [H, homeB, homeFinal]] as const) {
      state = value(await p.child.commit(owner, { base_revision: state.revision, branch: 0, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) }, context(p.id))).room;
    }
    const token = "d".repeat(64), origin = { expected_revision: 5, from_index: 1, source: { room_id: p.id, revision: state.revision, branch: 0, checkpoint_hash: homeFinal.checkpoint_hash } };
    value(await runInDurableObject(p.child, (_, ctx) => campaignSource(ctx.storage, { schema_version: 1, binding: p.request.binding, attempt: { transition_id: token, origin } }, true, resolver)));
    await runInDurableObject(root(), (_, ctx) => {
      const a = anchor(ctx); a.control.state = "complete"; a.control.revision = 6;
      a.control.chapters[1].completion = { source_revision: state.revision, source_branch: 0, checkpoint_hash: homeFinal.checkpoint_hash, transition_id: token, from_campaign_revision: 5, accepted_campaign_revision: 6 };
      ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a));
    });
    expect(value(await p.child.snapshot(H, context(p.id))).active_role).toBe("complete");
    await runInDurableObject(p.child, async (_, ctx) => {
      const m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMemberV2;
      m.seal!.transition_id = "e".repeat(64); ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m));
      expect(await prepareCampaignAccess(ctx.storage, resolver)).not.toBeNull();
    });
    expect(await p.child.snapshot(H, context(p.id))).toMatchObject({ ok: false, code: "campaign_binding_mismatch" });
  });
  it("does not let a prepared Continue suppress the existing source fork race", async () => {
    await setup(); const p = await complete();
    const targetId = (await digest("v2:" + "EF".repeat(10))).slice(0, 22);
    await runInDurableObject(root(), (_, ctx) => {
      const a = anchor(ctx), origin = { expected_revision: 1, from_index: 0, source: { room_id: R, revision: p.state.revision, branch: 0, checkpoint_hash: final.checkpoint_hash } };
      const target = { room_id: targetId, invite_code: "EF".repeat(10), index: 1, chapter: definition.chapters[1] };
      a.control.state = "continuing"; a.control.revision = 2; a.control.transition = { transition_id: TOKEN, phase: "prepared", origin }; a.pending = { ...a.control.transition, target_intent: target };
      ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a));
    });
    expect(value(await root().fork(H, { base_revision: p.state.revision, branch: 0, stage_index: 0, idempotency_key: "fork-prepared-source" }, context())).room.branch).toBe(1);
  });
  it("rechecks raw local authority after a detached read and never treats a descriptor as a lease", async () => {
    await setup(); await runInDurableObject(root(), async (_, ctx) => {
      const access = await prepareCampaignHttpAccess(ctx.storage, env, H, context());
      const a = anchor(ctx); a.control.revision++; ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a));
      expect(campaignHttpAccessGuard(ctx.storage, access)).toMatchObject({ ok: false, code: "campaign_state_changed" });
    });
    value(await env.PLAYERS.getByName(H).beginDelete([1, 2, 3], hash));
    expect(await root().snapshot(H, context())).toMatchObject({ ok: false, status: 401 });
    await runInDurableObject(root(), (_, ctx) => expect(gameplay(ctx).host_id).toBe(H));
  });
  it.each(["identity", "child_fence"])("holds %s changing during the actual awaited child access path", async mode => {
    const p = await published();
    await runInDurableObject(p.child, async (_, ctx) => {
      let called = false;
      const scoped = { ...env, PLAYERS: { getByName: (owner: string) => ({ authorize: async (device: string) => {
        called = true;
        const actual = env.PLAYERS.getByName(owner);
        if (mode === "identity") value(await actual.beginDelete([1, 2, 3], device));
        const accepted = await actual.authorize(device);
        if (mode === "child_fence") value(await eraseCampaignChild(ctx.storage, { schema_version: 1, binding: p.request.binding, origin: p.request.origin }, resolver));
        return accepted;
      } }) } } as unknown as Env;
      await expect(prepareCampaignHttpAccess(ctx.storage, scoped, H, context(p.id))).rejects.toMatchObject({ code: mode === "identity" ? "identity_unavailable" : "campaign_state_changed" });
      expect(called).toBe(true);
      if (mode === "child_fence") expect(gameplay(ctx)).toEqual({ deleted: true });
      else expect(gameplay(ctx).host_id).toBe(H);
    });
  });
  it("allows room-based safety reporting while blocked and preserves exact receipt after root deletion", async () => {
    await setup(); const body = { schema_version: 1, idempotency_key: "retained-safety-report", room_family: "relay", room_id: R, reason: "other", photo: null };
    for (const header of [null, "1"]) {
      expect((await call("/v1/safety/report", "POST", body, header)).status).toBe(409);
      expect((await call("/v1/safety/block", "POST", { schema_version: 1, room_family: "relay", room_id: R }, header)).status).toBe(409);
    }
    expect((await call("/v1/safety/block", "POST", { schema_version: 1, room_family: "relay", room_id: R })).status).toBe(200);
    const sent = await call("/v1/safety/report", "POST", body); expect(sent.status).toBe(200); const receipt = await sent.json();
    value(await root().eraseCampaignRoot(H, R, null));
    const retried = await call("/v1/safety/report", "POST", body); expect(retried.status).toBe(200); expect(await retried.json()).toEqual(receipt);
    expect((await call("/v1/safety/report", "POST", body, null)).status).toBe(409);
    await runInDurableObject(root(), (_, ctx) => {
      ctx.storage.sql.exec("UPDATE metadata SET schema_version=999");
      ctx.storage.sql.exec("UPDATE campaign_member SET data='not-json'");
    });
    const damaged = await call("/v1/safety/report", "POST", body); expect(damaged.status).toBe(200); expect(await damaged.json()).toEqual(receipt);
    expect((await call("/v1/safety/report", "POST", { ...body, idempotency_key: "new-report-damaged-room" })).status).toBe(409);
    expect((await call("/v1/identity", "GET", undefined, null)).status).toBe(200);
  });
});
