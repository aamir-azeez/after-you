// Retained Story protocol coverage; production withdrawal is tested without
// this test-only substitution in campaign-production.test.ts.
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => true, requireCampaignProduction: () => {}
}));

import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { encode } from "jpeg-js";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { campaignBoundaryGuard, campaignSource, type SourceRequest } from "../src/v2/campaign-source";
import { deliverTurnHints, isAlarmMetadataTable, queueTurnHint, scheduleNotifications, type DeliveryResult } from "../src/notification-storage";
import type { NotificationEnvironment } from "../src/notifications";
import { initializeCampaignStorageSchema } from "../src/v2/storage-schema";
import type { StoredCampaignAnchorV2 as StoredCampaignAnchor, StoredCampaignMemberV2 as StoredCampaignMember } from "../src/v2/campaign-storage";
import type { CampaignDefinition, CampaignKey, CampaignView } from "../src/v2/campaign-types";
import type { RoomSnapshotV2 } from "../src/v2/room";
import fixture from "./fixtures/campaign-control-v2.json";
import legacy from "./fixtures/campaign-contract.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import final from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";

const definition = fixture.definition as CampaignDefinition, view = fixture.active_view as CampaignView;
const H = view.host_id, G = view.guest_id!, R = view.campaign_room_id, I = view.invite_code!;
const room = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()), key = () => crypto.randomUUID();
type Stub = ReturnType<typeof room>;
function value<T>(out: Outcome<T>): T { if (!out.ok) throw new Error(out.code); return out.value; }
async function state(stub: Stub) { return runInDurableObject(stub, async (_, ctx) => JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data) as RoomSnapshotV2); }
async function proofs(stub: Stub) { return runInDurableObject(stub, async (_, ctx) => ["room", "turns", "pairs", "operations"].map(table => ({ table, rows: ctx.storage.sql.exec('SELECT * FROM "' + table + '" ORDER BY rowid').toArray() }))); }
function inventory(ctx: DurableObjectState) {
  const names = ctx.storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE type='table' AND name!='_cf_KV' ORDER BY name").toArray();
  return names.map(table => {
    // Workerd prohibits reading its alarm bytes. Compare the classified schema
    // here and the actual getAlarm value separately at the awaited boundary.
    if (table.name === "_cf_METADATA") { expect(isAlarmMetadataTable(table)).toBe(true); return { ...table, rows: null }; }
    return { ...table, rows: ctx.storage.sql.exec('SELECT * FROM "' + table.name + '" ORDER BY rowid').toArray() };
  });
}
async function play(stub: Stub) {
  let current = value(await stub.snapshot(H, REQUEST_CONTEXT)); const inputs: { owner: string; body: Record<string, unknown> }[] = [];
  for (const [owner, recording, checkpoint] of [[H, highA, null], [G, highB, middle], [G, lowA, null], [H, lowB, final]] as const) {
    const body = { base_revision: current.revision, branch: current.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
    inputs.push({ owner, body }); current = value(await stub.commit(owner, body, REQUEST_CONTEXT)).room;
  }
  return inputs;
}
async function ordinary(id = R) { const stub = room(); value(await stub.initialize(id, H, I, definition.chapters[0])); value(await stub.join(G, I, [6])); const inputs = await play(stub); return { stub, inputs }; }
async function prepared(uploadPhoto = false) {
  const { stub, inputs } = await ordinary(); let upload: Record<string, unknown> | undefined;
  if (uploadPhoto) {
    const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
    const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(b => b.toString(16).padStart(2, "0")).join("");
    upload = { idempotency_key: key(), recording_hash: highA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64: btoa(String.fromCharCode(...bytes)), sha256 };
    value(await stub.updatePhoto(H, "t0-0-a", upload, false, REQUEST_CONTEXT));
  }
  const current = await state(stub), targetInvite = "EF".repeat(10), targetId = (await digest("v2:" + targetInvite)).slice(0, 22);
  const control = structuredClone(fixture.pending_result.campaign) as CampaignView; control.invite_expires_at = current.invite_expires_at;
  const anchor: StoredCampaignAnchor = { schema_version: 2, activation: null, state: "live", definition: structuredClone(definition), control,
    pending: { ...control.transition!, target_intent: { room_id: targetId, invite_code: targetInvite, index: 1, chapter: structuredClone(definition.chapters[1]) } }, closed_before_branches: [0, 0], deletion: null };
  const member: StoredCampaignMember = { schema_version: 2, incoming: null, campaign_room_id: R, campaign_key: structuredClone(view.campaign_key), room_id: R, chapter_index: 0, chapter: structuredClone(definition.chapters[0]), host_id: H, guest_id: G, transition_id: null, status: "active", seal: null };
  await runInDurableObject(stub, async (_, ctx) => { initializeCampaignStorageSchema(ctx.storage); ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify(anchor)); ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(member)); });
  const request: SourceRequest = { schema_version: 1, binding: { campaign_room_id: R, campaign_key: member.campaign_key, room_id: R, chapter_index: 0, chapter: member.chapter, host_id: H, guest_id: G, member_transition_id: null }, attempt: { transition_id: control.transition!.transition_id, origin: control.transition!.origin } };
  return { stub, inputs, request, upload };
}
function deleting(ctx: DurableObjectState) {
  const a = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data) as StoredCampaignAnchor;
  a.control.state = "deleting"; a.deletion = { room_ids: [R, a.pending!.target_intent!.room_id], completed_room_ids: [] };
  const m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMember; m.status = "deleting";
  ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m));
}
const forkInput = (s: RoomSnapshotV2) => ({ base_revision: s.revision, branch: s.branch, stage_index: 0, idempotency_key: key() });
async function childPrepared(index = 1) {
  const childId = "B".repeat(22), { stub } = await ordinary(childId), current = await state(stub);
  const d = structuredClone(definition); d.chapters = Array.from({ length: index + 1 }, () => structuredClone(definition.chapters[0]));
  const { definition_hash: _previous, ...body } = d; d.definition_hash = await digest(canonicalJson(body));
  const campaignKey = { campaign_id: d.campaign_id, campaign_version: d.campaign_version, definition_hash: d.definition_hash };
  const incoming = { ...structuredClone(fixture.accepted_result.receipt.origin), expected_revision: 7, from_index: index - 1 };
  incoming.source.room_id = index === 1 ? R : "C".repeat(22);
  const member: StoredCampaignMember = { schema_version: 2, incoming: { origin: incoming, accepted_revision: 8 }, campaign_room_id: R, campaign_key: campaignKey, room_id: childId, chapter_index: index, chapter: d.chapters[index], host_id: H, guest_id: G, transition_id: "8".repeat(64), status: "active", seal: null };
  const request: SourceRequest = { schema_version: 1, binding: { campaign_room_id: R, campaign_key: campaignKey, room_id: childId, chapter_index: index, chapter: member.chapter, host_id: H, guest_id: G, member_transition_id: member.transition_id }, attempt: { transition_id: "7".repeat(64), origin: { expected_revision: 8, from_index: index, source: { room_id: childId, revision: current.revision, branch: current.branch, checkpoint_hash: current.checkpoint.checkpoint_hash } } } };
  await runInDurableObject(stub, async (_, ctx) => { initializeCampaignStorageSchema(ctx.storage); ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(member)); });
  const resolver = (k: CampaignKey) => canonicalJson(k) === canonicalJson(campaignKey) ? d : undefined;
  return { stub, member, request, resolver };
}
const REQUEST_CONTEXT = { schema_version: 2 as const, room_id: R, device_hash: "a".repeat(64) };
// Public Room calls now require original-device protocol context; the existing
// fixture helpers and all original lifecycle/proof assertions stay unchanged.
beforeEach(async () => {
  for (const owner of [H, G]) value(await env.PLAYERS.getByName(owner).create(owner, REQUEST_CONTEXT.device_hash, "b".repeat(64)));
});
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("campaign notification await boundaries", () => {
  for (const delivered of [true, false]) it("preserves outbox and owned alarm when campaign binding appears during delivery: " + delivered, async () => {
    const base = Date.now() + 3_600_000, clock = vi.spyOn(Date, "now").mockReturnValue(base);
    const { stub } = await ordinary(), current = await state(stub);
    await runInDurableObject(stub, async (instance, ctx) => {
      queueTurnHint(ctx.storage, { NOTIFICATIONS_ENABLED: "true" }, "relay", current, H);
      await ctx.storage.transaction(async () => scheduleNotifications(ctx.storage));
      clock.mockReturnValue(base + 2000);
      let started!: () => void, finish!: (result: DeliveryResult) => void, calls = 0;
      const waiting = new Promise<void>(resolve => { started = resolve; });
      const response = new Promise<DeliveryResult>(resolve => { finish = resolve; });
      const fakeEnv = { ...env, NOTIFICATIONS_ENABLED: "true", PLAYERS: { getByName: () => ({ deliverTurnNotification: async () => { calls++; started(); return await response; } }) } } as unknown as Env & NotificationEnvironment;
      const pending = deliverTurnHints(ctx.storage, fakeEnv, () => current, () => campaignBoundaryGuard(ctx.storage, "held") === null);
      await waiting;
      initializeCampaignStorageSchema(ctx.storage);
      const before = inventory(ctx), alarm = await ctx.storage.getAlarm();
      finish({ delivered }); await pending;
      expect(calls).toBe(1); expect(inventory(ctx)).toEqual(before); expect(await ctx.storage.getAlarm()).toBe(alarm);
      // The RoomV2 entry point also holds the retained outbox once bound.
      await instance.alarm(); expect(inventory(ctx)).toEqual(before); expect(await ctx.storage.getAlarm()).toBe(alarm);
    });
  });
  it("retains default standalone retry and successful delivery without a campaign predicate", async () => {
    const base = Date.now() + 3_600_000, clock = vi.spyOn(Date, "now").mockReturnValue(base);
    const { stub } = await ordinary(), current = await state(stub);
    await runInDurableObject(stub, async (_, ctx) => {
      queueTurnHint(ctx.storage, { NOTIFICATIONS_ENABLED: "true" }, "relay", current, H);
      await ctx.storage.transaction(async () => scheduleNotifications(ctx.storage));
      const proofBefore = ctx.storage.sql.exec("SELECT data FROM room").toArray();
      clock.mockReturnValue(base + 2000);
      let delivered = false, calls = 0;
      const fakeEnv = { ...env, NOTIFICATIONS_ENABLED: "true", PLAYERS: { getByName: () => ({ deliverTurnNotification: async () => { calls++; return { delivered }; } }) } } as unknown as Env & NotificationEnvironment;
      await deliverTurnHints(ctx.storage, fakeEnv, () => current);
      const row = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_outbox").one().data);
      expect(row.attempts).toBe(1); expect(row.next_at).toBe(base + 62_000); expect(await ctx.storage.getAlarm()).toBe(row.next_at);
      delivered = true; clock.mockReturnValue(row.next_at); await deliverTurnHints(ctx.storage, fakeEnv, () => current);
      expect(calls).toBe(2); expect(ctx.storage.sql.exec("SELECT * FROM notification_outbox").toArray()).toEqual([]);
      expect(ctx.storage.sql.exec("SELECT * FROM notification_alarm").toArray()).toEqual([]); expect(await ctx.storage.getAlarm()).toBeNull();
      expect(ctx.storage.sql.exec("SELECT data FROM room").toArray()).toEqual(proofBefore);
    });
  });
});

describe("disabled campaign source transactions", () => {
  it("holds archived legacy1 authority without rewriting any source, accepted retry or sidecar", async () => {
    const { stub, inputs, request } = await prepared();
    await runInDurableObject(stub, async (instance, ctx) => {
      const a = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data) as StoredCampaignAnchor;
      const m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMember;
      const { activation: _debt, control: _control, schema_version: _av, ...oldAnchor } = a;
      const { incoming: _incoming, schema_version: _mv, ...oldMember } = m;
      const oldControl = { ...structuredClone(legacy.pending_result.campaign), invite_expires_at: a.control.invite_expires_at };
      ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify({ ...oldAnchor, schema_version: 1, control: oldControl }, null, 2));
      ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify({ ...oldMember, schema_version: 1 }, null, 2));
      const before = inventory(ctx), alarm = await ctx.storage.getAlarm();
      expect(await instance.observeCampaignSource(request)).toMatchObject({ ok: false, code: "campaign_state_unavailable" });
      expect(await instance.sealCampaignSource(request)).toMatchObject({ ok: false, code: "campaign_state_unavailable" });
      expect(await instance.snapshot(H, REQUEST_CONTEXT)).toMatchObject({ ok: false, code: "campaign_state_unavailable" });
      expect(await instance.commit(inputs[0].owner, inputs[0].body, REQUEST_CONTEXT)).toMatchObject({ ok: false, code: "campaign_state_unavailable" });
      expect(await instance.operation(H, String(inputs[0].body.idempotency_key), REQUEST_CONTEXT)).toMatchObject({ ok: false, code: "campaign_state_unavailable" });
      expect(inventory(ctx)).toEqual(before); expect(await ctx.storage.getAlarm()).toBe(alarm);
    });
  });
  it("requires child outgoing chronology and a distinct token before observation or seal writes", async () => {
    const { stub, request, resolver } = await childPrepared();
    await runInDurableObject(stub, async (_, ctx) => {
      const before = inventory(ctx);
      for (const attempt of [{ ...request.attempt, origin: { ...request.attempt.origin, expected_revision: 0 } }, { ...request.attempt, origin: { ...request.attempt.origin, expected_revision: 7 } }, { ...request.attempt, transition_id: request.binding.member_transition_id! }]) {
        for (const seal of [false, true]) expect(await campaignSource(ctx.storage, { ...request, attempt }, seal, resolver)).toMatchObject({ ok: false, code: "campaign_transition_mismatch" });
        expect(inventory(ctx)).toEqual(before);
      }
      expect(value(await campaignSource(ctx.storage, request, false, resolver)).status).toBe("ready");
      expect(inventory(ctx)).toEqual(before);
      expect(value(await campaignSource(ctx.storage, request, true, resolver)).status).toBe("sealed");
      const sealed = inventory(ctx);
      expect(value(await campaignSource(ctx.storage, request, true, resolver)).status).toBe("sealed");
      expect(inventory(ctx)).toEqual(sealed);
    });
  });
  it("refuses an anchor as a later child's incoming source before acquiring any seal", async () => {
    const { stub, member, request, resolver } = await childPrepared(2);
    await runInDurableObject(stub, async (_, ctx) => {
      expect(value(await campaignSource(ctx.storage, request, false, resolver)).status).toBe("ready");
      member.incoming!.origin.source.room_id = R;
      ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(member));
      const before = inventory(ctx);
      for (const seal of [false, true]) expect(await campaignSource(ctx.storage, request, seal, resolver)).toMatchObject({ ok: false, code: "campaign_state_unavailable" });
      expect(inventory(ctx)).toEqual(before);
    });
  });
  it("seals once, preserves every accepted proof byte and reconciles the exact retry after eviction", async () => {
    const { stub, inputs, request } = await prepared(), before = await proofs(stub);
    expect(value(await stub.observeCampaignSource(request)).status).toBe("ready");
    expect(value(await stub.sealCampaignSource(request)).status).toBe("sealed");
    expect(await proofs(stub)).toEqual(before);
    const sealed = await runInDurableObject(stub, async (_, ctx) => inventory(ctx));
    await evictDurableObject(stub);
    expect(value(await stub.sealCampaignSource(request)).status).toBe("sealed");
    expect(await runInDurableObject(stub, async (_, ctx) => inventory(ctx))).toEqual(sealed);
    expect(value(await stub.commit(inputs[0].owner, inputs[0].body, REQUEST_CONTEXT)).receipt.idempotency_key).toBe(inputs[0].body.idempotency_key);
    expect(value(await stub.operation(H, String(inputs[0].body.idempotency_key), REQUEST_CONTEXT)).receipt.idempotency_key).toBe(inputs[0].body.idempotency_key);
    expect(value(await stub.collection(G, REQUEST_CONTEXT)).pairs).toHaveLength(2);
    expect(value(await stub.pairRecording(G, "p0-0", REQUEST_CONTEXT)).checkpoint).toEqual(middle);
    expect(await stub.sealCampaignSource({ ...request, attempt: { ...request.attempt, transition_id: "9".repeat(64) } })).toMatchObject({ ok: false, code: "campaign_seal_conflict" });
    expect(await proofs(stub)).toEqual(before);
  });
  it("lets a real fork win during seal validation and returns a bounded fork witness on exact retry", async () => {
    const { stub, request } = await prepared(), input = forkInput(await state(stub));
    await runInDurableObject(stub, async (instance, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle);
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { spy.mockRestore(); value(await instance.fork(H, input, REQUEST_CONTEXT)); return original(algorithm, data); });
      try { expect(await campaignSource(ctx.storage, request, true)).toMatchObject({ ok: false, code: "campaign_state_changed" }); } finally { spy.mockRestore(); }
    });
    expect(value(await stub.sealCampaignSource(request))).toMatchObject({ status: "source_forked", closed_before_branch: 1, observed_branch: 1 });
    expect((await state(stub)).stage_index).toBe(0);
    expect(await runInDurableObject(stub, async (_, ctx) => JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data).seal)).toBeNull();
    expect(await stub.sealCampaignSource({ ...request, attempt: { ...request.attempt, origin: { ...request.attempt.origin, source: { ...request.attempt.origin.source, revision: 1000 } } } })).toMatchObject({ ok: false, code: "campaign_source_mismatch" });
  });
  it("lets the seal win during fork hashing and prevents all new gameplay while retaining accepted retries", async () => {
    const { stub, request } = await prepared(), before = await proofs(stub), input = forkInput(await state(stub));
    await runInDurableObject(stub, async (instance, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle);
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { spy.mockRestore(); expect(value(await campaignSource(ctx.storage, request, true)).status).toBe("sealed"); return original(algorithm, data); });
      try { expect(await instance.fork(H, input, REQUEST_CONTEXT)).toMatchObject({ ok: false, code: "campaign_source_sealed" }); } finally { spy.mockRestore(); }
    });
    expect(await proofs(stub)).toEqual(before);
  });
  it("requires the exact prepared root transition and exact binding before acquiring a seal", async () => {
    const { stub, request } = await prepared(), before = await runInDurableObject(stub, async (_, ctx) => inventory(ctx));
    for (const patch of [{ host_id: G, guest_id: H }, { room_id: "Z".repeat(22) }, { member_transition_id: "8".repeat(64) }, { chapter_index: 1 }, { chapter: definition.chapters[1] }]) {
      expect(await stub.sealCampaignSource({ ...request, binding: { ...request.binding, ...patch } })).toMatchObject({ ok: false });
    }
    expect(await runInDurableObject(stub, async (_, ctx) => inventory(ctx))).toEqual(before);
    await runInDurableObject(stub, async (_, ctx) => { const a = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data) as StoredCampaignAnchor; a.control.state = "active"; a.control.transition = null; a.pending = null; ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); });
    expect(await stub.sealCampaignSource(request)).toMatchObject({ ok: false, code: "campaign_transition_mismatch" });
  });
  it("holds malformed local authority instead of sealing or inventing a fork witness", async () => {
    const { stub, request } = await prepared(), original = await state(stub);
    for (const patch of [{ branch: 99, revision: 99 }, { revision: -1 }, { stage_index: 99 }, { schema_version: 7 }, { a_turn_id: "t0-1-a" }, { completed_pair_ids: [] }, { checkpoint: { ...original.checkpoint, checkpoint_hash: "bad" } }, { checkpoint: { ...original.checkpoint, schema_version: 99 } }]) {
      await runInDurableObject(stub, async (_, ctx) => { ctx.storage.sql.exec("UPDATE room SET data=?", JSON.stringify({ ...original, ...patch })); const before = inventory(ctx); expect(await campaignSource(ctx.storage, request, true)).toMatchObject({ ok: false }); expect(inventory(ctx)).toEqual(before); });
    }
  });
  it("does not let an impossible future schema without sidecars fall through ordinary shortcuts", async () => {
    const stub = room(); await runInDurableObject(stub, async (instance, ctx) => {
      ctx.storage.sql.exec("UPDATE metadata SET schema_version=7"); const before = inventory(ctx);
      expect(instance.initialize(R, H, I)).toMatchObject({ ok: false }); expect(await instance.join(G, I)).toMatchObject({ ok: false });
      expect(await instance.eraseForPlayer(H, true)).toMatchObject({ ok: false }); expect(await instance.snapshot(H, REQUEST_CONTEXT)).toMatchObject({ ok: false });
      expect(inventory(ctx)).toEqual(before);
    });
  });
  it("refuses generic initialize/join/delete even for empty schema6 and pending-creation erasure", async () => {
    for (const seeded of [false, true]) {
      const stub = seeded ? (await prepared()).stub : room();
      await runInDurableObject(stub, async (instance, ctx) => { if (!seeded) initializeCampaignStorageSchema(ctx.storage); const before = inventory(ctx);
        expect(instance.initialize(R, H, I)).toMatchObject({ ok: false, code: "campaign_initialize_required" });
        expect(await instance.join(G, I, [6])).toMatchObject({ ok: false, code: "campaign_join_required" });
        expect(await instance.eraseForPlayer(H, true)).toMatchObject({ ok: false, code: "campaign_delete_required" }); expect(inventory(ctx)).toEqual(before);
      });
    }
  });
  it("rechecks the fast accepted retry after a lifecycle change during recording validation", async () => {
    const { stub, inputs } = await prepared(); await runInDurableObject(stub, async (instance, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle); let after: ReturnType<typeof inventory> | undefined;
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { deleting(ctx); after = inventory(ctx); return original(algorithm, data); });
      try { expect(await instance.commit(inputs[0].owner, inputs[0].body, REQUEST_CONTEXT)).toMatchObject({ ok: false, code: "campaign_not_active" }); } finally { spy.mockRestore(); }
      expect(inventory(ctx)).toEqual(after);
      expect(await instance.operation(H, String(inputs[0].body.idempotency_key), REQUEST_CONTEXT)).toMatchObject({ ok: false, code: "campaign_not_active" });
      expect(await instance.collection(G, REQUEST_CONTEXT)).toMatchObject({ ok: false, code: "campaign_not_active" });
    });
  });
  it("rechecks metadata lifecycle after its own asynchronous request hashing", async () => {
    const { stub } = await prepared(); await runInDurableObject(stub, async (instance, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle); let after: ReturnType<typeof inventory> | undefined;
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementation(async (algorithm, data) => { if (!after && new TextDecoder().decode(data).includes('"operation":"pair_reaction"')) { deleting(ctx); after = inventory(ctx); } return original(algorithm, data); });
      try { expect(await instance.react(H, "p0-0", { idempotency_key: key(), a_hash: highA.recording_hash, b_hash: highB.recording_hash, expected_reaction_revision: 0, reaction: "love" }, REQUEST_CONTEXT)).toMatchObject({ ok: false, code: "campaign_not_active" }); } finally { spy.mockRestore(); }
      expect(after).toBeDefined(); expect(inventory(ctx)).toEqual(after);
    });
  });
  it("allows sealed photo/reaction bookkeeping without changing source proofs or schema6", async () => {
    const { stub, request, upload } = await prepared(true); value(await stub.sealCampaignSource(request)); const before = await proofs(stub);
    const reaction = { idempotency_key: key(), a_hash: highA.recording_hash, b_hash: highB.recording_hash, expected_reaction_revision: 0, reaction: "love" };
    const accepted = value(await stub.react(G, "p0-0", reaction, REQUEST_CONTEXT));
    const reactionRows = await runInDurableObject(stub, async (_, ctx) => [ctx.storage.sql.exec("SELECT * FROM pair_reactions ORDER BY rowid").toArray(), ctx.storage.sql.exec("SELECT * FROM reaction_operations ORDER BY rowid").toArray()]);
    expect(value(await stub.react(G, "p0-0", reaction, REQUEST_CONTEXT))).toEqual(accepted);
    expect(value(await stub.reactionOperation(G, reaction.idempotency_key, REQUEST_CONTEXT))).toEqual(accepted);
    expect(await runInDurableObject(stub, async (_, ctx) => [ctx.storage.sql.exec("SELECT * FROM pair_reactions ORDER BY rowid").toArray(), ctx.storage.sql.exec("SELECT * FROM reaction_operations ORDER BY rowid").toArray()])).toEqual(reactionRows);
    expect(value(await stub.photoOperation(H, String(upload!.idempotency_key), REQUEST_CONTEXT)).receipt.photo_revision).toBe(1);
    value(await stub.acknowledgePhoto(G, "t0-0-a", { recording_hash: highA.recording_hash, photo_revision: 1, sha256: upload!.sha256 }, REQUEST_CONTEXT));
    value(await stub.updatePhoto(H, "t0-0-a", { idempotency_key: key(), recording_hash: highA.recording_hash, expected_photo_revision: 1, expected_photo_hash: upload!.sha256 }, true, REQUEST_CONTEXT));
    expect(await proofs(stub)).toEqual(before);
    expect(await runInDurableObject(stub, async (_, ctx) => ctx.storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata").one().schema_version)).toBe(6);
  });
  it("accepts a different seal only on the strictly later branch and requires a finite exact child resolver", async () => {
    const childId = "B".repeat(22), { stub } = await ordinary(childId), old = await state(stub); value(await stub.fork(H, forkInput(old), REQUEST_CONTEXT)); await play(stub); const current = await state(stub);
    const d = structuredClone(definition); d.chapters[1] = structuredClone(d.chapters[0]); const { definition_hash: _old, ...body } = d; d.definition_hash = await digest(canonicalJson(body));
    const campaignKey = { campaign_id: d.campaign_id, campaign_version: d.campaign_version, definition_hash: d.definition_hash };
    const member: StoredCampaignMember = { schema_version: 2, incoming: { origin: structuredClone(fixture.accepted_result.receipt.origin), accepted_revision: fixture.accepted_result.receipt.accepted_revision }, campaign_room_id: R, campaign_key: campaignKey, room_id: childId, chapter_index: 1, chapter: d.chapters[1], host_id: H, guest_id: G, transition_id: "8".repeat(64), status: "active", seal: null };
    const request: SourceRequest = { schema_version: 1, binding: { campaign_room_id: R, campaign_key: campaignKey, room_id: childId, chapter_index: 1, chapter: d.chapters[1], host_id: H, guest_id: G, member_transition_id: member.transition_id }, attempt: { transition_id: "7".repeat(64), origin: { expected_revision: 4, from_index: 1, source: { room_id: childId, revision: current.revision, branch: current.branch, checkpoint_hash: current.checkpoint.checkpoint_hash } } } };
    await runInDurableObject(stub, async (_, ctx) => {
      initializeCampaignStorageSchema(ctx.storage); ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(member));
      const resolver = (k: typeof campaignKey) => canonicalJson(k) === canonicalJson(campaignKey) ? d : undefined;
      expect(await campaignSource(ctx.storage, request, true)).toMatchObject({ ok: false });
      expect(value(await campaignSource(ctx.storage, request, true, resolver)).status).toBe("sealed");
      const earlier = structuredClone(request); earlier.attempt.transition_id = "6".repeat(64); earlier.attempt.origin.source = { room_id: childId, revision: old.revision, branch: old.branch, checkpoint_hash: old.checkpoint.checkpoint_hash };
      expect(value(await campaignSource(ctx.storage, earlier, true, resolver))).toMatchObject({ status: "source_forked", closed_before_branch: 1, observed_branch: 1 });
      earlier.attempt.origin.source.revision = current.revision;
      expect(await campaignSource(ctx.storage, earlier, true, resolver)).toMatchObject({ ok: false });
    });
  });
});
