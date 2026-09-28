// Retained Story protocol coverage; production withdrawal is tested without
// this test-only substitution in campaign-production.test.ts.
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => true, requireCampaignProduction: () => {}
}));

import c0_0 from "../../game/tests/fixtures/first_steps/cumulative-lift-a.json";
import c0_1 from "../../game/tests/fixtures/first_steps/cumulative-lift-b.json";
import c0_2 from "../../game/tests/fixtures/first_steps/cumulative-lift-checkpoint.json";
import c0_3 from "../../game/tests/fixtures/first_steps/cumulative-garden-a.json";
import c0_4 from "../../game/tests/fixtures/first_steps/cumulative-garden-b.json";
import c0_5 from "../../game/tests/fixtures/first_steps/cumulative-garden-checkpoint.json";
import c1_0 from "../../game/tests/fixtures/v2/relay-a.json";
import c1_1 from "../../game/tests/fixtures/v2/relay-b.json";
import c1_2 from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import c1_3 from "../../game/tests/fixtures/v2/garden-a.json";
import c1_4 from "../../game/tests/fixtures/v2/garden-b.json";
import c1_5 from "../../game/tests/fixtures/v2/final-checkpoint.json";
import c2_0 from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import c2_1 from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import c2_2 from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import c2_3 from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import c2_4 from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import c2_5 from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";
import c3_0 from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";
import c3_1 from "../../game/tests/fixtures/cooperative/weight-of-a-friend-b.json";
import c3_2 from "../../game/tests/fixtures/cooperative/weight-of-a-friend-checkpoint.json";
import c3_3 from "../../game/tests/fixtures/cooperative/bring-it-home-a.json";
import c3_4 from "../../game/tests/fixtures/cooperative/bring-it-home-b.json";
import c3_5 from "../../game/tests/fixtures/cooperative/rolling-home-final-checkpoint.json";
import c4_0 from "../../game/tests/fixtures/cooperative/open-the-house-a.json";
import c4_1 from "../../game/tests/fixtures/cooperative/open-the-house-b.json";
import c4_2 from "../../game/tests/fixtures/cooperative/open-the-house-checkpoint.json";
import c4_3 from "../../game/tests/fixtures/cooperative/the-room-below-a.json";
import c4_4 from "../../game/tests/fixtures/cooperative/the-room-below-b.json";
import c4_5 from "../../game/tests/fixtures/cooperative/a-house-for-two-final-checkpoint.json";
import c5_0 from "../../game/tests/fixtures/journey/a-light-above-a.json";
import c5_1 from "../../game/tests/fixtures/journey/a-light-above-b.json";
import c5_2 from "../../game/tests/fixtures/journey/a-light-above-checkpoint.json";
import c5_3 from "../../game/tests/fixtures/journey/the-way-light-returns-a.json";
import c5_4 from "../../game/tests/fixtures/journey/the-way-light-returns-b.json";
import c5_5 from "../../game/tests/fixtures/journey/conservatory-final-checkpoint.json";
import c6_0 from "../../game/tests/fixtures/journey/the-path-you-leave-a.json";
import c6_1 from "../../game/tests/fixtures/journey/the-path-you-leave-b.json";
import c6_2 from "../../game/tests/fixtures/journey/the-path-you-leave-checkpoint.json";
import c6_3 from "../../game/tests/fixtures/journey/a-place-beside-you-a.json";
import c6_4 from "../../game/tests/fixtures/journey/a-place-beside-you-b.json";
import c6_5 from "../../game/tests/fixtures/journey/long-way-home-final-checkpoint.json";
import nativeFirstSteps from "../../game/tests/fixtures/comfort8/first-steps.json";
import shippedStory from "../../game/content/campaigns/a-place-for-two-v1.json";

const proofs = [
  [c0_0, c0_1, c0_2, c0_3, c0_4, c0_5],
  [c1_0, c1_1, c1_2, c1_3, c1_4, c1_5],
  [c2_0, c2_1, c2_2, c2_3, c2_4, c2_5],
  [c3_0, c3_1, c3_2, c3_3, c3_4, c3_5],
  [c4_0, c4_1, c4_2, c4_3, c4_4, c4_5],
  [c5_0, c5_1, c5_2, c5_3, c5_4, c5_5],
  [c6_0, c6_1, c6_2, c6_3, c6_4, c6_5]
] as const;

import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject, runDurableObjectAlarm } from "cloudflare:test";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, type Outcome } from "../src/protocol";
import { chapter } from "../src/v2/chapters";
import { queueTurnHint, scheduleNotifications } from "../src/notification-storage";
import { campaignContinueKey, campaignDefinition } from "../src/v2/campaign-protocol";
import type { CampaignDefinition, CampaignKey, CampaignView, CampaignContinueResult } from "../src/v2/campaign-types";
import type { MutationV2, PairV2, RoomSnapshotV2 } from "../src/v2/room";
import type { CampaignRedoAccept, CampaignRedoBinding } from "../src/v2/campaign-redo";
import type { RedoState } from "../src/redo-control";

// Synthetic story registry with actual current chapter pins and native-verified
// golden recordings. All turns below pass through the real public router.
const catalog = vi.hoisted(() => ({ definition: null as CampaignDefinition | null }));
vi.mock("../src/v2/campaign-registry", async original => {
  const actual = await original<typeof import("../src/v2/campaign-registry")>();
  const { canonicalJson } = await import("../src/protocol");
  const resolve = (key: CampaignKey) => {
    const d = catalog.definition;
    return d && canonicalJson(key) === canonicalJson({ campaign_id: d.campaign_id,
      campaign_version: d.campaign_version, definition_hash: d.definition_hash }) ? structuredClone(d) : undefined;
  };
  return { ...actual, retainedCampaign: resolve,
    advertisedCampaigns: () => catalog.definition ? [structuredClone(catalog.definition)] : [],
    campaignCreatable: (key: CampaignKey, e: { CAMPAIGN_CREATION_ENABLED?: string }) => e.CAMPAIGN_CREATION_ENABLED === "true" && !!resolve(key) };
});
const flags = { V2_ROOMS_ENABLED: "true", FIRST_STEPS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true",
  HOUSE_CHAPTER_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: "true", CAMPAIGN_CREATION_ENABLED: "true",
  CAMPAIGN_MUTATIONS_ENABLED: "true", REVENUECAT_VERIFICATION_MODE: "demo", REVENUECAT_API_VERSION: "1",
  REVENUECAT_SECRET_KEY: "synthetic-only", NOTIFICATIONS_ENABLED: "false" };
const T = "a".repeat(43), I = "AB".repeat(10);
const unwrap = <V>(r: Outcome<V>): V => { if (!r.ok) throw new Error(r.code); return r.value; };
let H = "", G = "", R = "", device = "", invite = I, address = 0, entitlementReads = 0, key: CampaignKey;
const targetInitializations = new Set<string>();
const changed = new Map<object, Record<string, unknown>>();
async function configure() {
  await runInDurableObject(env.ROOMS_V2.getByName(R), instance => {
    const local = Reflect.get(instance, "env") as Record<string, unknown>;
    if (!changed.has(local)) changed.set(local, Object.fromEntries(Object.keys(flags).map(k => [k, local[k]])));
    Object.assign(local, flags);
  });
}
async function call(path: string, method = "GET", body?: unknown, owner = H) {
  const configured: Env = { ...env }; Object.assign(configured, flags);
  return worker.fetch(new Request("https://seven-chapter.test" + path, { method, headers: {
    "Content-Type": "application/json", "CF-Connecting-IP": "198.22.1." + ++address,
    "X-Player-Id": owner, Authorization: "Bearer " + T, "X-AfterYou-Campaign-Schema": "2"
  }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function response<V>(r: Response, status = 200): Promise<V> {
  const value = await r.json<V>(); expect(r.status, JSON.stringify(value)).toBe(status); return value;
}
async function control(owner = H) {
  return (await response<{ campaign: CampaignView }>(await call(`/v2/campaigns/${R}`, "GET", undefined, owner))).campaign;
}
async function anchorRows() {
  return runInDurableObject(env.ROOMS_V2.getByName(R), (_, ctx) =>
    ["campaign_anchor", "campaign_operations", "campaign_member"].map(t => [t, ctx.storage.sql.exec(`SELECT * FROM ${t}`).toArray()]));
}
beforeEach(async () => {
  await reset(); H = randomToken(16); G = randomToken(16); R = (await digest("v2:" + I)).slice(0, 22);
  device = await digest(T); address = 0; invite = I; entitlementReads = 0; targetInitializations.clear();
  const chapters = proofs.map(([a]) => ({ level_id: a.level_id, level_version: a.level_version,
    definition_hash: a.definition_hash, simulation_version: a.simulation_version, premium: chapter(a).premium }));
  const body = { schema_version: 1 as const, campaign_id: "fixture-seven-adapters", campaign_version: 1, chapters,
    story: { story_id: "fixture-seven-story", story_version: 1, content_hash: "7".repeat(64) } };
  catalog.definition = await campaignDefinition({ ...body, definition_hash: await digest(canonicalJson(body)) }, pin => {
    const adapter = chapter(pin); return adapter.premium === pin.premium &&
      (adapter.supported_simulation_versions ?? [adapter.simulation_version]).includes(pin.simulation_version);
  });
  key = { campaign_id: body.campaign_id, campaign_version: 1, definition_hash: catalog.definition.definition_hash };
  for (const owner of [H, G]) unwrap(await env.PLAYERS.getByName(owner).create(owner, device, "b".repeat(64)));
  await runInDurableObject(env.PLAYERS.getByName(H), instance => {
    const original = instance.storedTesterGrant;
    vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "storedTesterGrant").mockImplementation(function(this: typeof instance, owner: string) {
      if (owner === H) entitlementReads++;
      return original.call(this, owner);
    });
  });
  await configure();
  await runInDurableObject(env.ROOMS_V2.getByName(R), instance => {
    const original = instance.campaignBoundTarget;
    vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignBoundTarget").mockImplementation(function(this: typeof instance, ...args: Parameters<typeof instance.campaignBoundTarget>) {
      if (!args[1]) targetInitializations.add((args[0] as { binding: { room_id: string } }).binding.room_id);
      return original.apply(this, args);
    });
  });
  const random = crypto.getRandomValues.bind(crypto);
  vi.spyOn(crypto, "getRandomValues").mockImplementation(((array: Uint8Array) => {
    if (array instanceof Uint8Array && array.length === 10) { array.set(invite.match(/../g)!.map(v => parseInt(v, 16))); return array; }
    return random(array);
  }) as typeof crypto.getRandomValues);
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 404 }));
});
afterEach(async () => {
  vi.restoreAllMocks(); for (const [target, prior] of changed) Object.assign(target, prior);
  changed.clear(); flags.NOTIFICATIONS_ENABLED = "false"; flags.V2_ROOMS_ENABLED = "true"; flags.CAMPAIGN_MUTATIONS_ENABLED = "true";
  catalog.definition = null; await reset();
});

async function firstStoryPair(simulation: 5 | 8 = 8, onlyA = false) {
  if (simulation === 8) {
    catalog.definition = structuredClone(shippedStory.definition) as CampaignDefinition;
    key = { campaign_id: catalog.definition.campaign_id, campaign_version: catalog.definition.campaign_version,
      definition_hash: catalog.definition.definition_hash };
  }
  await response(await call("/v2/campaigns", "POST", { schema_version: 1, idempotency_key: "alarm-create-0001", campaign_key: key }), 201);
  await response(await call("/v2/campaigns/join", "POST", { schema_version: 2, idempotency_key: "alarm-join-000001",
    campaign_key: key, invite_code: I, supported_simulation_versions: [2, 5, 6, 7, 8] }, G));
  let room = await response<RoomSnapshotV2>(await call(`/v2/rooms/${R}`));
  expect(room.simulation_version).toBe(simulation);
  const first = simulation === 8 ? nativeFirstSteps.pairs[0] : { a: c0_0, b: c0_1, checkpoint: c0_2 };
  for (const [recording, checkpoint] of [[first.a, null], [first.b, first.checkpoint]] as const) {
    room = (await response<MutationV2>(await call(`/v2/rooms/${R}/turns`, "POST", {
      base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording,
      ...(checkpoint ? { checkpoint } : {}) }, recording.player_slot === "p0" ? H : G))).room;
    if (onlyA) return room;
  }
  expect(room.stage_index).toBe(1); expect(room.revision).toBe(3);
  return room;
}

type RedoView = { schema_version: 1; binding: CampaignRedoBinding; redo: RedoState };
const redoPath = (index = 0) => `/v2/campaigns/${R}/chapters/${index}/redo`;
async function offer(index = 0, owner = G) {
  return response<RedoView>(await call(redoPath(index), "GET", undefined, owner));
}
async function requestRedo(index = 0) {
  const view = await offer(index), source = view.redo.source!;
  expect(source).not.toBeNull();
  return response<RedoView>(await call(redoPath(index), "POST", { schema_version: 1, binding: view.binding, action: "request", source }, source.second_player_id));
}
function acceptBody(view: RedoView): CampaignRedoAccept {
  return { schema_version: 1, binding: view.binding, source: view.redo.source!, request_id: view.redo.request!.request_id, idempotency_key: crypto.randomUUID() };
}
async function play(room: RoomSnapshotV2, recording: { player_slot: string }, checkpoint?: unknown) {
  return (await response<MutationV2>(await call(`/v2/rooms/${room.room_id}/turns`, "POST", {
    base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording,
    ...(checkpoint ? { checkpoint } : {}) }, recording.player_slot === "p0" ? H : G))).room;
}
async function advance(room: RoomSnapshotV2, index: number) {
  const current = await control(), origin = { expected_revision: current.revision, from_index: index,
    source: { room_id: room.room_id, revision: room.revision, branch: room.branch, checkpoint_hash: room.checkpoint.checkpoint_hash } };
  invite = (index + 32).toString(16).toUpperCase().repeat(10);
  await response(await call(`/v2/campaigns/${R}/continue`, "POST", { schema_version: 1, campaign_key: key, ...origin,
    idempotency_key: await campaignContinueKey(R, key, H, origin) }));
  return control();
}
async function redoInventory(id = R) {
  return runInDurableObject(env.ROOMS_V2.getByName(id), async (_, ctx) => ({
    history: ["turns", "pairs"].map(t => ctx.storage.sql.exec(`SELECT * FROM ${t} ORDER BY rowid`).toArray()),
    notifications: ["notification_outbox", "notification_alarm"].map(t => ctx.storage.sql.exec(`SELECT * FROM ${t}`).toArray()),
    alarm: await ctx.storage.getAlarm()
  }));
}

it("redo keeps rules8 history, uses the reversed stage author, and recovers while writes are paused", async () => {
  flags.NOTIFICATIONS_ENABLED = "true"; await configure();
  const middle = await firstStoryPair(), room = await play(middle, nativeFirstSteps.pairs[1].a);
  const requested = await requestRedo(), body = acceptBody(requested), before = await redoInventory(), parent = await anchorRows();
  expect(body.source).toMatchObject({ first_player_id: G, second_player_id: H, stage_index: 1 });
  expect(await response(await call(redoPath(), "POST", { schema_version: 1, binding: requested.binding, action: "request", source: body.source }, H))).toEqual(requested);
  await response(await call(redoPath() + "/accept", "POST", body, H), 409);
  const accepted = await response(await call(redoPath() + "/accept", "POST", body, G));
  expect(accepted).toMatchObject({ schema_version: 1, binding: requested.binding, receipt: { operation: "fork", accepted_revision: room.revision + 1,
    branch: room.branch + 1, stage_index: 1, checkpoint_hash: room.checkpoint.checkpoint_hash, turn_id: null, pair_id: null } });
  expect(Object.keys(accepted as object).sort()).toEqual(["binding", "receipt", "schema_version"]);
  expect(await redoInventory()).toEqual(before); expect(before.notifications).toEqual([[], []]); expect(before.alarm).toBeNull();
  expect(await anchorRows()).toEqual(parent);
  const current = await response<RoomSnapshotV2>(await call(`/v2/rooms/${R}`));
  expect(current).toMatchObject({ active_role: "a", a_turn_id: null, branch: 1, stage_index: 1 });
  expect(current.completed_pair_ids).toEqual(middle.completed_pair_ids); expect(current.checkpoint).toEqual(middle.checkpoint);
  await evictDurableObject(env.ROOMS_V2.getByName(R));
  flags.V2_ROOMS_ENABLED = "false"; flags.CAMPAIGN_MUTATIONS_ENABLED = "false"; await configure();
  expect(await response(await call("/v2/capabilities"))).toMatchObject({ campaign_control_version: 2, campaign_redo_version: 1, campaign_mutations_enabled: false });
  expect(await response(await call(redoPath() + "/operations/" + body.idempotency_key, "GET", undefined, G))).toEqual(accepted);
  expect(await response(await call(redoPath() + "/accept", "POST", body, G))).toEqual(accepted);
  await response(await call(redoPath() + "/accept", "POST", { ...body, idempotency_key: crypto.randomUUID() }, G), 503);
  expect(globalThis.fetch).not.toHaveBeenCalled();
});

it.each(["decline", "cancel"] as const)("keeps %s terminal for the same A source without changing gameplay", async action => {
  const room = await firstStoryPair(8, true), requested = await requestRedo(), body = acceptBody(requested);
  const actor = action === "decline" ? H : G, mutation = { schema_version: 1, binding: requested.binding, action, source: body.source };
  const stopped = await response<RedoView>(await call(redoPath(), "POST", mutation, actor));
  expect(stopped.redo.request?.status).toBe(action === "decline" ? "declined" : "cancelled");
  expect(await requestRedo()).toEqual(stopped);
  await response(await call(redoPath() + "/accept", "POST", body), 409);
  expect(await response(await call(`/v2/rooms/${R}`))).toEqual(room);
});

it.each(["b", "redo"] as const)("keeps only the %s winner and never rewinds the next completed pair", async winner => {
  const room = await firstStoryPair(8, true), requested = await requestRedo(), body = acceptBody(requested), first = nativeFirstSteps.pairs[0];
  const b = { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording: first.b, checkpoint: first.checkpoint };
  if (winner === "b") {
    await response(await call(`/v2/rooms/${R}/turns`, "POST", b, G));
    await response(await call(redoPath() + "/accept", "POST", body), 409);
    expect(await response(await call(`/v2/rooms/${R}`))).toMatchObject({ stage_index: 1, branch: 0 });
  } else {
    await response(await call(redoPath() + "/accept", "POST", body));
    await response(await call(`/v2/rooms/${R}/turns`, "POST", b, G), 409);
    expect(await response(await call(`/v2/rooms/${R}`))).toMatchObject({ stage_index: 0, branch: 1 });
  }
});

it("arbitrates concurrent B submission and consent in the child transaction", async () => {
  const room = await firstStoryPair(8, true), requested = await requestRedo(), body = acceptBody(requested), first = nativeFirstSteps.pairs[0];
  const outcomes = await Promise.all([
    call(`/v2/rooms/${R}/turns`, "POST", { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(),
      recording: first.b, checkpoint: first.checkpoint }, G),
    call(redoPath() + "/accept", "POST", body)
  ]);
  expect(outcomes.map(r => r.status).sort()).toEqual([200, 409]);
  await Promise.all(outcomes.map(r => r.arrayBuffer()));
  const current = await response<RoomSnapshotV2>(await call(`/v2/rooms/${R}`));
  expect(current.revision).toBe(room.revision + 1);
  expect([[0, 1], [1, 0]]).toContainEqual([current.stage_index, current.branch]);
});

it("dispatches later-child redo and recovers its immutable receipt after Continue", async () => {
  let room = await firstStoryPair(5);
  room = await play(room, c0_3); room = await play(room, c0_4, c0_5);
  let view = await advance(room, 0), id = view.chapters[1].room_id!;
  room = await response<RoomSnapshotV2>(await call(`/v2/rooms/${id}`)); room = await play(room, c1_0);
  const requested = await requestRedo(1), body = acceptBody(requested), parent = await anchorRows(), history = await redoInventory(id);
  const accepted = await response(await call(redoPath(1) + "/accept", "POST", body));
  expect(await anchorRows()).toEqual(parent); expect(await redoInventory(id)).toEqual(history);
  room = await response<RoomSnapshotV2>(await call(`/v2/rooms/${id}`));
  for (const [recording, checkpoint] of [[c1_0, null], [c1_1, c1_2], [c1_3, null], [c1_4, c1_5]] as const)
    room = await play(room, recording, checkpoint ?? undefined);
  view = await advance(room, 1); expect(view.current_index).toBe(2);
  await evictDurableObject(env.ROOMS_V2.getByName(id)); await configure();
  expect(await response(await call(redoPath(1) + "/operations/" + body.idempotency_key))).toEqual(accepted);
  expect(await response(await call(redoPath(1) + "/accept", "POST", body))).toEqual(accepted);
  await response(await call(redoPath(2) + "/operations/" + body.idempotency_key), 404);
  await response(await call(redoPath(1) + "/accept", "POST", { ...body, idempotency_key: crypto.randomUUID() }), 409);
  expect((await control()).current_index).toBe(2);
});

it("rejects mismatched binding/source, exhausted history, direct-child bypass and a revoked device", async () => {
  const room = await firstStoryPair(8, true), requested = await requestRedo(), body = acceptBody(requested);
  await response(await call(redoPath() + "/accept", "POST", { ...body, binding: { ...body.binding, chapter_index: 1 } }), 422);
  await response(await call(redoPath() + "/accept", "POST", { ...body, source: { ...body.source, revision: 0 } }), 400);
  await response(await call(`/v2/rooms/${R}/redo`), 409);
  await response(await call(`/v2/rooms/${R}/fork`, "POST", { base_revision: room.revision, branch: room.branch,
    stage_index: room.stage_index, idempotency_key: body.idempotency_key, redo_request_id: body.request_id }), 409);
  await runInDurableObject(env.ROOMS_V2.getByName(R), instance => vi.spyOn(instance as unknown as { capacity(): boolean }, "capacity").mockReturnValue(false));
  expect(await response(await call(redoPath() + "/accept", "POST", body), 409)).toMatchObject({ error: { code: "room_history_full" } });
  expect(await response(await call(`/v2/rooms/${R}`))).toEqual(room);
  unwrap(await env.PLAYERS.getByName(H).beginDelete([1, 2, 3], device));
  await response(await call(redoPath() + "/accept", "POST", body), 401);
});

it("does not schedule disabled Story notifications after accepted turns", async () => {
  vi.spyOn(Date, "now").mockReturnValue(Date.now() + 3_600_000);
  flags.NOTIFICATIONS_ENABLED = "true"; await configure(); await firstStoryPair();
  await runInDurableObject(env.ROOMS_V2.getByName(R), async (_, ctx) => {
    expect(ctx.storage.sql.exec("SELECT * FROM notification_outbox").toArray()).toEqual([]);
    expect(ctx.storage.sql.exec("SELECT * FROM notification_alarm").toArray()).toEqual([]);
    expect(await ctx.storage.getAlarm()).toBeNull();
  });
  expect(globalThis.fetch).not.toHaveBeenCalled();
});

it.each([5, 8] as const)("deletes a rules%i Story identity after a previously scheduled notification alarm was consumed", async simulation => {
  const clock = vi.spyOn(Date, "now").mockReturnValue(Date.now() + 3_600_000);
  const room = await firstStoryPair(simulation), stub = env.ROOMS_V2.getByName(R);
  // Reproduce the notification rows written by the earlier Story commit path.
  await runInDurableObject(stub, async (_, ctx) => {
    queueTurnHint(ctx.storage, { NOTIFICATIONS_ENABLED: "true" }, "relay", room, H);
    await scheduleNotifications(ctx.storage);
    expect(await ctx.storage.getAlarm()).toBe(Date.now() + 1000);
  });
  clock.mockReturnValue(Date.now() + 1001);
  expect(await runDurableObjectAlarm(stub)).toBe(true);
  await runInDurableObject(stub, async (_, ctx) => {
    expect(await ctx.storage.getAlarm()).toBeNull();
    expect(ctx.storage.sql.exec("SELECT * FROM notification_outbox").toArray()).toHaveLength(1);
    expect(ctx.storage.sql.exec("SELECT * FROM notification_alarm").toArray()).toHaveLength(1);
    expect(ctx.storage.sql.exec("SELECT * FROM pairs").toArray()).toHaveLength(1);
  });
  // A failed deletion must leave the same identity available for a DELETE retry.
  unwrap(await env.PLAYERS.getByName(H).beginDelete([1, 2, 3], device));
  expect((await call("/v1/identity")).status).toBe(401);
  expect(await env.PLAYERS.getByName(H).listRooms()).toHaveLength(1);
  expect(await response(await call("/v1/identity", "DELETE"))).toEqual({ deleted: true });
  expect(await response(await call("/v1/identity", "DELETE"))).toEqual({ deleted: true });
  expect(await env.PLAYERS.getByName(H).listRooms()).toEqual([]);
  await runInDurableObject(stub, async (_, ctx) => {
    expect(await ctx.storage.getAlarm()).toBeNull();
    for (const table of ["notification_outbox", "notification_alarm", "turns", "pairs"])
      expect(ctx.storage.sql.exec(`SELECT * FROM ${table}`).toArray()).toEqual([]);
    expect(JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data)).toEqual({ deleted: true });
  });
  expect(await response(await call("/v1/identity", "DELETE", undefined, G))).toEqual({ deleted: true });
  expect(await env.PLAYERS.getByName(G).listRooms()).toEqual([]);
  expect(globalThis.fetch).not.toHaveBeenCalled();
});

it("carries two players through seven actual chapter adapters, survives returning, and ends once", async () => {
  const creation = { schema_version: 1, idempotency_key: "seven-create-0001", campaign_key: key };
  await response(await call("/v2/campaigns", "POST", creation), 201);
  let view = (await response<{ campaign: CampaignView }>(await call("/v2/campaigns/join", "POST", {
    schema_version: 2, idempotency_key: "seven-join-000001", campaign_key: key, invite_code: I,
    supported_simulation_versions: [2, 5, 6, 7]
  }, G))).campaign;
  expect(globalThis.fetch).not.toHaveBeenCalled();
  const rooms: string[] = [], endpoints: RoomSnapshotV2[] = [];
  for (let index = 0; index < proofs.length; index++) {
    const entry = view.chapters[index], id = entry.room_id!;
    expect(view.current_index).toBe(index); expect(entry.chapter).toEqual(catalog.definition!.chapters[index]);
    expect(rooms).not.toContain(id); rooms.push(id);
    const [a0, b0, checkpoint0, a1, b1, checkpoint1] = proofs[index];
    let room = await response<RoomSnapshotV2>(await call(`/v2/rooms/${id}`));
    expect(room.host_id).toBe(H); expect(room.guest_id).toBe(G);
    expect(room.simulation_version ?? chapter(room).simulation_version).toBe(entry.chapter.simulation_version);
    for (const [recording, checkpoint] of [[a0, null], [b0, checkpoint0], [a1, null], [b1, checkpoint1]] as const) {
      const owner = recording.player_slot === "p0" ? H : G;
      expect(room.active_player_id).toBe(owner);
      const input = { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording,
        ...(checkpoint ? { checkpoint } : {}) };
      const accepted = await response<MutationV2>(await call(`/v2/rooms/${id}/turns`, "POST", input, owner));
      room = accepted.room;
      expect(accepted.receipt.recording_hash).toBe(recording.recording_hash);
      if (checkpoint) expect(room.checkpoint).toEqual(checkpoint);
    }
    expect(room.active_role).toBe("complete"); endpoints.push(room);
    const owner = index % 2 === 0 ? G : H, other = owner === H ? G : H;
    const current = await control(owner);
    const origin = { expected_revision: current.revision, from_index: index,
      source: { room_id: id, revision: room.revision, branch: room.branch, checkpoint_hash: room.checkpoint.checkpoint_hash } };
    const input = { schema_version: 1, campaign_key: key, ...origin,
      idempotency_key: await campaignContinueKey(R, key, owner, origin) };
    invite = (index + 32).toString(16).toUpperCase().padStart(2, "0").repeat(10);
    if (index === 2) {
      const before = await anchorRows();
      expect((await call(`/v2/campaigns/${R}/continue`, "POST", input, owner)).status).toBe(402);
      expect(await anchorRows()).toEqual(before);
      unwrap(await env.PLAYERS.getByName(H).redeemTesterAccess(H, device, true));
      expect(await env.PLAYERS.getByName(G).storedTesterGrant(G)).toBeNull();
    }
    // Discard the accepted response as a lost reply, then return on a cold root.
    const readsBeforeAdvance = entitlementReads;
    const sent = await call(`/v2/campaigns/${R}/continue`, "POST", input, owner);
    expect(sent.status).toBe(200); await sent.arrayBuffer();
    if (index >= 2 && index < 6) expect(entitlementReads).toBeGreaterThan(readsBeforeAdvance);
    await evictDurableObject(env.ROOMS_V2.getByName(R)); await configure();
    const before = await anchorRows(), paidRequests = vi.mocked(globalThis.fetch).mock.calls.length, readsBeforeRetry = entitlementReads;
    const operation = await response<CampaignContinueResult>(await call(`/v2/campaigns/${R}/operations/${input.idempotency_key}`, "GET", undefined, owner));
    expect(operation.status).toBe("accepted"); expect(await anchorRows()).toEqual(before);
    const retry = await response<CampaignContinueResult>(await call(`/v2/campaigns/${R}/continue`, "POST", input, owner));
    expect(retry).toEqual(operation); expect(await anchorRows()).toEqual(before);
    expect(vi.mocked(globalThis.fetch).mock.calls).toHaveLength(paidRequests);
    const alias = { ...input, idempotency_key: await campaignContinueKey(R, key, other, origin) };
    const partner = await response<CampaignContinueResult>(await call(`/v2/campaigns/${R}/continue`, "POST", alias, other));
    expect(partner.status).toBe("accepted");
    expect(entitlementReads).toBe(readsBeforeRetry);
    if (retry.status !== "accepted") throw new Error("expected_accepted_continue");
    expect(retry.receipt.outcome).toBe(index === 6 ? "finished" : "advanced");
    expect(retry.receipt.next_index).toBe(index === 6 ? null : index + 1);
    if (index === 6) expect(retry.receipt.next_room_id).toBeNull();
    view = await control(); expect(view.activation).toBeNull(); expect(view.transition).toBeNull();
    expect(view.chapters[index].completion).toMatchObject({ source_revision: room.revision,
      source_branch: room.branch, checkpoint_hash: room.checkpoint.checkpoint_hash,
      from_campaign_revision: current.revision });
    expect(view.current_index).toBe(Math.min(index + 1, 6));
    if (index < 6) expect(retry.receipt.next_room_id).toBe(view.chapters[index + 1].room_id);
    for (const member of [H, G]) expect(await env.PLAYERS.getByName(member).listRooms())
      .toEqual([{ room_id: R, api_version: 3, host: member === H, invite_code: member === H ? I : "" }]);
  }
  expect(view.state).toBe("complete"); expect(view.chapters).toHaveLength(7);
  expect(view.chapters.map(row => row.room_id)).toEqual(rooms);
  expect([...targetInitializations].sort()).toEqual(rooms.slice(1).sort());
  for (let index = 0; index < rooms.length; index++) {
    const pair = await response<PairV2>(await call(`/v2/rooms/${rooms[index]}/pairs/p0-1`, "GET", undefined, G));
    expect(pair.a).toEqual(proofs[index][3]); expect(pair.b).toEqual(proofs[index][4]);
    expect(pair.checkpoint).toEqual(endpoints[index].checkpoint);
  }
  expect(await env.PLAYERS.getByName(G).storedTesterGrant(G)).toBeNull();
  // Identity deletion is the existing public whole-story deletion route.
  expect(await response(await call("/v1/identity", "DELETE", undefined, H))).toEqual({ deleted: true });
  expect(await env.PLAYERS.getByName(H).listRooms()).toEqual([]);
  for (const id of rooms) await runInDurableObject(env.ROOMS_V2.getByName(id), (_, ctx) => {
    expect(JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data)).toEqual({ deleted: true });
    expect(ctx.storage.sql.exec("SELECT * FROM turns").toArray()).toEqual([]);
    expect(ctx.storage.sql.exec("SELECT * FROM pairs").toArray()).toEqual([]);
    expect(JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member WHERE id=1").one().data))
      .toEqual({ schema_version: 1, status: "deleted", campaign_room_id: R, room_id: id });
  });
  expect(unwrap(await env.ROOMS_V2.getByName(R).campaignTerminalFact(R))).toEqual({ schema_version: 1,
    status: "deleted", campaign_room_id: R, room_id: R });
  expect(await env.PLAYERS.getByName(G).listRooms()).toHaveLength(1);
  expect(await response(await call(`/v2/campaigns/${R}/reconcile-deletion`, "POST", { schema_version: 1 }, G)))
    .toMatchObject({ status: "released", player_id: G, campaign_room_id: R });
  expect(await env.PLAYERS.getByName(G).listRooms()).toEqual([]);
}, 30_000);
