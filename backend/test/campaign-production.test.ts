import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { initializeCampaignStorageSchema } from "../src/v2/storage-schema";
import { campaignContinueKey } from "../src/v2/campaign-protocol";
import { campaignRedoBinding } from "../src/v2/campaign-redo";
import type { CampaignDefinition, CampaignKey, CampaignView } from "../src/v2/campaign-types";
import type { StoredCampaignAnchorV2, StoredCampaignMemberV2 } from "../src/v2/campaign-storage";
import type { RoomStateV2 } from "../src/v2/room";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import final from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";
import rollingA from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";

// No policy/registry substitution in this suite. Native recordings are first
// accepted by an ordinary room, then retained Story metadata is attached as an
// archived fixture. Nothing can switch the production policy on at runtime.
const H = fixture.active_view.host_id, G = fixture.active_view.guest_id!, R = fixture.active_view.campaign_room_id;
const I = fixture.active_view.invite_code!, T = "a".repeat(43), token = "c".repeat(64);
const definition = fixture.definition as CampaignDefinition, key = fixture.active_view.campaign_key as CampaignKey;
const flags = { V2_ROOMS_ENABLED: "true", CAMPAIGN_CREATION_ENABLED: "true", CAMPAIGN_MUTATIONS_ENABLED: "true",
  FIRST_STEPS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true", HOUSE_CHAPTER_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: "true" };
const changed = new Map<object, Record<string, unknown>>();
const root = () => env.ROOMS_V2.getByName(R);
const value = <T>(out: Outcome<T>): T => { if (!out.ok) throw new Error(out.code); return out.value; };
let hash = "", address = 0;
const context = () => ({ schema_version: 2 as const, room_id: R, device_hash: hash });
const create = () => ({ schema_version: 1, idempotency_key: "withdrawn-create-key-0001", campaign_key: key });
const join = () => ({ schema_version: 2 as const, idempotency_key: "withdrawn-join-key-0001", invite_code: I,
  campaign_key: key, supported_simulation_versions: [6] });
async function call(path: string, method = "GET", body?: unknown, owner = H) {
  const configured: Env = { ...env }; Object.assign(configured, flags);
  return worker.fetch(new Request("https://withdrawn.test" + path, { method, headers: {
    "Content-Type": "application/json", "X-Player-Id": owner, Authorization: "Bearer " + T,
    "X-AfterYou-Campaign-Schema": "2", "CF-Connecting-IP": "198.19.9." + ++address
  }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
const gameplay = (ctx: DurableObjectState) => JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data) as RoomStateV2;
async function bytes() {
  return runInDurableObject(root(), (_, ctx) => ["room", "turns", "pairs", "operations", "redo_control", "campaign_member", "campaign_anchor", "campaign_operations"]
    .map(name => [name, ctx.storage.sql.exec(`SELECT * FROM ${name}`).toArray()]));
}
async function allocation() {
  return value(await env.PLAYERS.getByName(H).reserveCampaignRoom(create().idempotency_key,
    { creation_schema: 2, link: { room_id: R, invite_code: I, host: true, api_version: 3 }, campaign_key: key }, hash));
}
async function archived(turns = 0, consent = false, joined = true) {
  const room = root(); value(await room.initialize(R, H, I, definition.chapters[0]));
  let state = joined ? value(await room.join(G, I, [6])) : value(await room.snapshot(H));
  const bodies: { owner: string; body: Record<string, unknown> }[] = [];
  for (const [owner, recording, checkpoint] of [[H, highA, null], [G, highB, middle], [G, lowA, null], [H, lowB, final]].slice(0, turns) as
    ([string, typeof highA | typeof highB | typeof lowA | typeof lowB, typeof middle | typeof final | null])[]) {
    const body = { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) };
    state = value(await room.commit(owner, body)).room; bodies.push({ owner, body });
  }
  const redoSource = { room_id: R, revision: state.revision, branch: state.branch, stage_index: state.stage_index,
    a_hash: highA.recording_hash, first_player_id: H, second_player_id: G };
  const requestId = await digest(canonicalJson(redoSource));
  let acceptedFork: Record<string, unknown> | null = null;
  if (consent) {
    value(await room.redo(G, { action: "request", source: redoSource }, hash));
    acceptedFork = { base_revision: state.revision, branch: state.branch, stage_index: state.stage_index,
      idempotency_key: "withdrawn-accepted-redo-01", redo_request_id: requestId };
    state = value(await room.fork(H, acceptedFork, undefined, hash)).room;
  }
  await allocation();
  if (joined) value(await env.PLAYERS.getByName(G).reserveCampaignJoin(join(), hash));
  await runInDurableObject(room, (_, ctx) => {
    const s = gameplay(ctx), control = structuredClone(fixture.active_view) as CampaignView;
    control.invite_expires_at = s.invite_expires_at;
    if (!joined) { control.state = "waiting"; control.revision = 0; control.guest_id = null; }
    const anchor: StoredCampaignAnchorV2 = { schema_version: 2, state: "live", definition, control,
      pending: null, closed_before_branches: [0, 0], deletion: null, activation: null };
    const member: StoredCampaignMemberV2 = { schema_version: 2, campaign_room_id: R, campaign_key: key, room_id: R,
      chapter_index: 0, chapter: definition.chapters[0], host_id: H, guest_id: joined ? G : null,
      transition_id: null, status: "active", seal: null, incoming: null };
    initializeCampaignStorageSchema(ctx.storage);
    ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify(anchor));
    ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(member));
  });
  return { state, bodies, redoSource, requestId, acceptedFork };
}
async function unavailable(response: Response) {
  expect(response.status).toBe(503); expect(await response.json()).toMatchObject({ error: { code: "campaign_unavailable" } });
}
beforeEach(async () => {
  hash = await digest(T); address = 0;
  for (const owner of [H, G]) value(await env.PLAYERS.getByName(owner).create(owner, hash, "b".repeat(64)));
  await runInDurableObject(root(), instance => {
    const local = Reflect.get(instance, "env") as Record<string, unknown>;
    changed.set(local, Object.fromEntries(Object.keys(flags).map(k => [k, local[k]]))); Object.assign(local, flags);
  });
});
afterEach(async () => { vi.restoreAllMocks(); for (const [local, prior] of changed) Object.assign(local, prior); changed.clear(); await reset(); });

it("does not initialize a formerly reserved Create or admit a fresh Join", async () => {
  await allocation();
  await unavailable(await call("/v2/campaigns", "POST", create()));
  expect(await root().snapshot(H, context())).toMatchObject({ ok: false, status: 404 });
  await archived(0, false, false);
  const before = await bytes();
  await unavailable(await call("/v2/campaigns/join", "POST", join(), G));
  expect(await env.PLAYERS.getByName(G).listRooms()).toEqual([]);
  expect(await bytes()).toEqual(before);
});

it("blocks fresh turns, fork and redo while retaining accepted turns and admission recovery", async () => {
  const saved = await archived(1), before = await bytes();
  for (const [path, body, owner] of [["/v2/campaigns", create(), H], ["/v2/campaigns/join", join(), G]] as const)
    expect((await call(path, "POST", body, owner)).status).toBe(200);
  const old = saved.bodies[0];
  expect((await call(`/v2/rooms/${R}/turns`, "POST", old.body)).status).toBe(200);
  await unavailable(await call(`/v2/rooms/${R}/turns`, "POST", { ...old.body, idempotency_key: "withdrawn-new-turn-0001" }));
  await unavailable(await call(`/v2/rooms/${R}/fork`, "POST", { base_revision: saved.state.revision, branch: 0, stage_index: 0, idempotency_key: "withdrawn-new-fork-0001" }));
  const campaign = value(await root().campaignControl(H)).campaign, binding = campaignRedoBinding(campaign, 0);
  expect((await call(`/v2/campaigns/${R}/chapters/0/redo`)).status).toBe(200);
  await unavailable(await call(`/v2/campaigns/${R}/chapters/0/redo`, "POST", { schema_version: 1, binding, action: "request", source: saved.redoSource }, G));
  await unavailable(await call(`/v2/campaigns/${R}/chapters/0/redo/accept`, "POST", { schema_version: 1, binding, source: saved.redoSource,
    request_id: saved.requestId, idempotency_key: "withdrawn-new-consent-01" }));
  expect(await bytes()).toEqual(before);
});

it("returns an exact accepted redo receipt without enabling another fork", async () => {
  const saved = await archived(1, true), before = await bytes();
  const binding = campaignRedoBinding(value(await root().campaignControl(H)).campaign, 0);
  const body = { schema_version: 1, binding, source: saved.redoSource, request_id: saved.requestId, idempotency_key: saved.acceptedFork!.idempotency_key };
  const accepted = await call(`/v2/campaigns/${R}/chapters/0/redo/accept`, "POST", body);
  expect(accepted.status).toBe(200);
  expect(await accepted.json()).toMatchObject({ receipt: { operation: "fork", branch: 1, request_hash: await digest(canonicalJson({ operation: "fork", ...saved.acceptedFork })) } });
  expect((await call(`/v2/campaigns/${R}/chapters/0/redo/operations/${body.idempotency_key}`)).status).toBe(200);
  await unavailable(await call(`/v2/campaigns/${R}/chapters/0/redo/accept`, "POST", { ...body, idempotency_key: "withdrawn-new-consent-02" }));
  expect(await bytes()).toEqual(before);
});

it("holds new paid child turns and forks without purchase I/O, preserving exact accepted retries", async () => {
  const saved = await archived(4), invite = "EF".repeat(10), id = (await digest("v2:" + invite)).slice(0, 22);
  const child = env.ROOMS_V2.getByName(id), pin = definition.chapters[1];
  value(await child.initialize(id, H, invite, pin)); value(await child.join(G, invite, [6]));
  const body = { base_revision: 1, branch: 0, idempotency_key: "retained-paid-child-turn", recording: rollingA };
  const accepted = value(await child.commit(H, body));
  const origin = { expected_revision: 1, from_index: 0, source: { room_id: R, revision: saved.state.revision, branch: 0, checkpoint_hash: final.checkpoint_hash } };
  await runInDurableObject(root(), (_, ctx) => {
    const a = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data) as StoredCampaignAnchorV2;
    const m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMemberV2;
    a.control.revision = 6; a.control.current_index = 1; a.control.chapters[1].room_id = id;
    a.control.chapters[0].completion = { source_revision: saved.state.revision, source_branch: 0, checkpoint_hash: final.checkpoint_hash,
      transition_id: token, from_campaign_revision: 1, accepted_campaign_revision: 5 };
    m.status = "sealed"; m.seal = { transition_id: token, origin };
    ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m));
  });
  await runInDurableObject(child, (instance, ctx) => {
    const local = Reflect.get(instance, "env") as Record<string, unknown>;
    changed.set(local, Object.fromEntries(Object.keys(flags).map(k => [k, local[k]]))); Object.assign(local, flags);
    const member: StoredCampaignMemberV2 = { schema_version: 2, campaign_room_id: R, campaign_key: key, room_id: id,
      chapter_index: 1, chapter: pin, host_id: H, guest_id: G, transition_id: token, status: "active", seal: null,
      incoming: { origin, accepted_revision: 5 } };
    initializeCampaignStorageSchema(ctx.storage); ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(member));
  });
  const inventory = () => runInDurableObject(child, (_, ctx) => ["room", "turns", "pairs", "operations", "campaign_member"]
    .map(name => [name, ctx.storage.sql.exec(`SELECT * FROM ${name}`).toArray()]));
  const before = await inventory(), rootBefore = await bytes();
  const provider = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("unexpected_provider_request"));
  const retry = await call(`/v2/rooms/${id}/turns`, "POST", body);
  expect(retry.status).toBe(200); expect(await retry.json()).toMatchObject({ receipt: accepted.receipt });
  await unavailable(await call(`/v2/rooms/${id}/turns`, "POST", { ...body, idempotency_key: "new-paid-child-turn-0001" }));
  await unavailable(await call(`/v2/rooms/${id}/fork`, "POST", { base_revision: 2, branch: 0, stage_index: 0, idempotency_key: "new-paid-child-fork-0001" }));
  expect(provider).not.toHaveBeenCalled(); expect(await inventory()).toEqual(before); expect(await bytes()).toEqual(rootBefore);
});

it("blocks Continue and Resume but preserves an accepted Continue and its activation debt read-only", async () => {
  const saved = await archived(4);
  const origin = { expected_revision: 1, from_index: 0, source: { room_id: R, revision: saved.state.revision, branch: 0, checkpoint_hash: final.checkpoint_hash } };
  const body = { schema_version: 1, campaign_key: key, idempotency_key: await campaignContinueKey(R, key, H, origin), ...origin };
  const before = await bytes();
  await unavailable(await call(`/v2/campaigns/${R}/continue`, "POST", body));
  await unavailable(await call(`/v2/campaigns/${R}/resume`, "POST", { schema_version: 1, campaign_key: key, transition_id: token }));
  expect(await bytes()).toEqual(before);
  const invite = "EF".repeat(10), target = { room_id: (await digest("v2:" + invite)).slice(0, 22), invite_code: invite, index: 1, chapter: definition.chapters[1] };
  await runInDurableObject(root(), (_, ctx) => {
    const a = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data) as StoredCampaignAnchorV2;
    const m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMemberV2;
    a.control.revision = 5; a.control.current_index = 1; a.control.chapters[1].room_id = target.room_id;
    a.control.chapters[0].completion = { source_revision: saved.state.revision, source_branch: 0, checkpoint_hash: final.checkpoint_hash,
      transition_id: token, from_campaign_revision: 1, accepted_campaign_revision: 5 };
    a.control.activation = { transition_id: token }; a.activation = { transition_id: token, origin, target_intent: target, accepted_revision: 5 };
    m.status = "sealed"; m.seal = { transition_id: token, origin };
    ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m));
  });
  const retained = await bytes();
  const accepted = await call(`/v2/campaigns/${R}/continue`, "POST", body);
  expect(accepted.status).toBe(200); expect(await accepted.json()).toMatchObject({ status: "accepted", campaign: { activation: { transition_id: token } } });
  expect((await call(`/v2/campaigns/${R}/operations/${body.idempotency_key}`)).status).toBe(200);
  await unavailable(await call(`/v2/campaigns/${R}/resume`, "POST", { schema_version: 1, campaign_key: key, transition_id: token }));
  expect(await bytes()).toEqual(retained);
});

it("keeps saved replays and account deletion available", async () => {
  await archived(2); const before = await bytes();
  for (const path of [`/v2/campaigns/${R}`, "/v2/campaigns", `/v2/rooms/${R}`, `/v2/rooms/${R}/collection`, `/v2/rooms/${R}/pairs/p0-0`])
    expect((await call(path)).status, path).toBe(200);
  expect(await bytes()).toEqual(before);
  expect((await call("/v1/identity", "DELETE")).status).toBe(200);
  expect((await call("/v1/identity")).status).toBe(401);
  expect((await call("/v1/identity/deletion-ack", "POST", { schema_version: 1 })).status).toBe(200);
});

it("leaves ordinary V2 room creation, joining and native turns enabled", async () => {
  const pin = definition.chapters[0];
  const response = await call("/v2/rooms", "POST", { idempotency_key: "ordinary-create-after-01", level_id: pin.level_id,
    level_version: pin.level_version, definition_hash: pin.definition_hash });
  expect(response.status).toBe(200);
  const room = await response.json<{ room_id: string; invite_code: string }>();
  expect((await call("/v2/rooms/join", "POST", { invite_code: room.invite_code, supported_simulation_versions: [6] }, G)).status).toBe(200);
  expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", { base_revision: 1, branch: 0, idempotency_key: "ordinary-turn-after-0001", recording: highA })).status).toBe(200);
});
