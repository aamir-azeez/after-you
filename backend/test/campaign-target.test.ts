import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { encode } from "jpeg-js";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { initializeCampaignTarget, activateCampaignTarget, campaignTargetInitialization, campaignTargetActivation, campaignTargetInitialized, campaignTargetActivated, type TargetInitializeRequest, type TargetActivateRequest } from "../src/v2/campaign-target";
import { campaignSource, type SourceRequest } from "../src/v2/campaign-source";
import type { CampaignDefinition, CampaignKey } from "../src/v2/campaign-types";
import type { StoredCampaignMemberV2 } from "../src/v2/campaign-storage";
import type { RoomStateV2 } from "../src/v2/room";
import { initializeCampaignStorageSchema, ROOM_V2_DELIVERY_TABLES } from "../src/v2/storage-schema";
import { exportRoomV2, validateRoomV2 } from "../src/v2/snapshot";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import final from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";

const H = fixture.active_view.host_id, G = fixture.active_view.guest_id!, R = fixture.active_view.campaign_room_id;
const room = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()), operation = () => crypto.randomUUID();
type Row = Record<string, string | number>;
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
async function contract(index = 1) {
  const definition = structuredClone(fixture.definition) as CampaignDefinition;
  definition.campaign_id = "fixture-local-target";
  definition.chapters = Array.from({ length: index + 1 }, () => structuredClone(definition.chapters[0]));
  const { definition_hash: _previous, ...body } = definition; definition.definition_hash = await digest(canonicalJson(body));
  const campaignKey = { campaign_id: definition.campaign_id, campaign_version: definition.campaign_version, definition_hash: definition.definition_hash };
  const invite = "EF".repeat(10), id = (await digest("v2:" + invite)).slice(0, 22);
  const origin = structuredClone(fixture.accepted_result.receipt.origin); origin.from_index = index - 1;
  if (index > 1) origin.source.room_id = "C".repeat(22);
  const request: TargetInitializeRequest = { schema_version: 1, binding: { campaign_room_id: R, campaign_key: campaignKey, room_id: id, chapter_index: index, chapter: definition.chapters[index], host_id: H, guest_id: G, member_transition_id: "8".repeat(64) }, origin,
    target_intent: { room_id: id, invite_code: invite, index, chapter: definition.chapters[index] } };
  const activation: TargetActivateRequest = { ...structuredClone(request), accepted_revision: origin.expected_revision + 2 };
  const resolver = (key: CampaignKey) => canonicalJson(key) === canonicalJson(campaignKey) ? definition : undefined;
  return { definition, request, activation, resolver };
}
async function inventory(ctx: DurableObjectState) {
  const alarm = await ctx.storage.getAlarm();
  const tables = ctx.storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray();
  return { alarm, kv: [...ctx.storage.kv.list()], tables: tables.map(table => {
    if (table.name === "_cf_METADATA") { expect(isAlarmMetadataTable(table)).toBe(true); return { ...table, rows: null }; }
    return { ...table, rows: ctx.storage.sql.exec('SELECT * FROM "' + table.name + '" ORDER BY rowid').toArray() };
  }) };
}
function stored(ctx: DurableObjectState) {
  return { member: JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member WHERE id=1").one().data) as StoredCampaignMemberV2,
    state: JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data) as RoomStateV2 };
}
async function initialized(emptySchema6 = false) {
  const c = await contract(), stub = room();
  const ack = await runInDurableObject(stub, async (_, ctx) => {
    if (emptySchema6) initializeCampaignStorageSchema(ctx.storage);
    return value(await initializeCampaignTarget(ctx.storage, c.request, c.resolver));
  });
  return { ...c, stub, ack };
}
function tombstone(ctx: DurableObjectState, request: TargetInitializeRequest) {
  ctx.storage.transactionSync(() => {
    initializeCampaignStorageSchema(ctx.storage);
    ctx.storage.sql.exec("DELETE FROM room"); ctx.storage.sql.exec("DELETE FROM campaign_member");
    ctx.storage.sql.exec("INSERT INTO room VALUES(1,?)", JSON.stringify({ deleted: true }));
    ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify({ schema_version: 1, status: "deleted", campaign_room_id: request.binding.campaign_room_id, room_id: request.binding.room_id }));
  });
}
async function advancedFixture(request: TargetInitializeRequest) {
  // Actual standalone coordinator accepts the native recordings and metadata.
  // The resulting rows represent later campaign gameplay; no campaign route is enabled.
  const stub = room(), b = request.binding;
  value(await stub.initialize(b.room_id, H, request.target_intent.invite_code, b.chapter));
  let current = value(await stub.join(G, request.target_intent.invite_code, [6]));
  for (const [owner, recording, checkpoint] of [[H, highA, null], [G, highB, middle], [G, lowA, null], [H, lowB, final]] as const)
    current = value(await stub.commit(owner, { base_revision: current.revision, branch: current.branch, idempotency_key: operation(), recording, ...(checkpoint ? { checkpoint } : {}) })).room;
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(n => n.toString(16).padStart(2, "0")).join("");
  value(await stub.updatePhoto(H, "t0-0-a", { idempotency_key: operation(), recording_hash: highA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64: btoa(String.fromCharCode(...bytes)), sha256 }));
  value(await stub.react(G, "p0-0", { idempotency_key: operation(), a_hash: highA.recording_hash, b_hash: highB.recording_hash, expected_reaction_revision: 0, reaction: "love" }));
  value(await stub.acknowledgePhoto(G, "t0-0-a", { recording_hash: highA.recording_hash, photo_revision: 1, sha256 }));
  return await runInDurableObject(stub, async (_, ctx) => ROOM_V2_DELIVERY_TABLES.map(table => ({ name: table.name, rows: ctx.storage.sql.exec<Row>(table.select).toArray() })));
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("disabled local campaign target helpers", () => {
  it("rolls back schema promotion and paired gameplay if the member insert fails", async () => {
    const c = await contract(), stub = room();
    await runInDurableObject(stub, async (_, ctx) => {
      const before = await inventory(ctx), original = ctx.storage.sql.exec.bind(ctx.storage.sql);
      let pairedGuest: string | null = null;
      const spy = vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((query: string, ...bindings: unknown[]) => {
        if (query === "INSERT INTO campaign_member VALUES(1,?)") {
          pairedGuest = JSON.parse(String(original("SELECT data FROM room WHERE id=1").one().data)).guest_id;
          throw new Error("synthetic_member_write_failure");
        }
        return original(query, ...bindings);
      }) as typeof ctx.storage.sql.exec);
      try { expect(await initializeCampaignTarget(ctx.storage, c.request, c.resolver)).toMatchObject({ ok: false }); } finally { spy.mockRestore(); }
      expect(pairedGuest).toBe(G); expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("atomically initializes paired provisional gameplay and preserves exact retry facts across eviction", async () => {
    for (const schema6 of [false, true]) {
      const c = await initialized(schema6);
      await runInDurableObject(c.stub, async (instance, ctx) => {
        const { member, state } = stored(ctx);
        expect(member).toMatchObject({ schema_version: 2, status: "provisional", seal: null, incoming: { origin: c.request.origin, accepted_revision: null } });
        expect(state).toMatchObject({ schema_version: 2, revision: 1, stage_index: 0, branch: 0, host_id: H, guest_id: G, a_turn_id: null, completed_pair_ids: [], simulation_version: 6 });
        expect(ctx.storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata").one().schema_version).toBe(6);
        expect(state.created_at).toBe(state.updated_at); expect(state.created_at).toBe(c.ack.created_at);
        expect(await campaignTargetInitialized(c.ack, c.request, c.resolver)).toEqual(c.ack);
        const before = await inventory(ctx);
        expect(await instance.snapshot(H)).toMatchObject({ ok: false });
        expect(await instance.join(G, c.request.target_intent.invite_code, [6])).toMatchObject({ ok: false });
        expect(instance.initialize(c.request.binding.room_id, H, c.request.target_intent.invite_code)).toMatchObject({ ok: false });
        expect(value(await initializeCampaignTarget(ctx.storage, c.request, c.resolver))).toEqual(c.ack);
        expect(await inventory(ctx)).toEqual(before);
        const raw = await exportRoomV2(ctx, "d".repeat(40), c.resolver);
        expect((await validateRoomV2(raw, c.request.binding.room_id, c.resolver)).payload.format_version).toBe(8);
      });
      await evictDurableObject(c.stub);
      await runInDurableObject(c.stub, async (_, ctx) => { const before = await inventory(ctx); expect(value(await initializeCampaignTarget(ctx.storage, c.request, c.resolver))).toEqual(c.ack); expect(await inventory(ctx)).toEqual(before); });
    }
  });
  it("activates exactly once and refuses a different publication revision without changing gameplay clocks", async () => {
    const c = await initialized();
    const ack = await runInDurableObject(c.stub, async (_, ctx) => {
      const stateBefore = ctx.storage.sql.exec("SELECT data FROM room").toArray();
      const result = value(await activateCampaignTarget(ctx.storage, c.activation, c.resolver));
      expect(stored(ctx).member).toMatchObject({ status: "active", incoming: { accepted_revision: c.activation.accepted_revision } });
      expect(ctx.storage.sql.exec("SELECT data FROM room").toArray()).toEqual(stateBefore);
      expect(await campaignTargetActivated(result, c.activation, c.resolver)).toEqual(result);
      const before = await inventory(ctx);
      expect(value(await activateCampaignTarget(ctx.storage, c.activation, c.resolver))).toEqual(result);
      for (const revision of [c.request.origin.expected_revision, c.activation.accepted_revision + 1]) expect(await activateCampaignTarget(ctx.storage, { ...c.activation, accepted_revision: revision }, c.resolver)).toMatchObject({ ok: false });
      expect(await inventory(ctx)).toEqual(before); return result;
    });
    await evictDurableObject(c.stub);
    await runInDurableObject(c.stub, async (_, ctx) => { const before = await inventory(ctx); expect(value(await activateCampaignTarget(ctx.storage, c.activation, c.resolver))).toEqual(ack); expect(await inventory(ctx)).toEqual(before); });
  });
  it("preserves every accepted proof/photo/reaction row on active and outgoing-sealed retries", async () => {
    const c = await initialized(), advanced = await advancedFixture(c.request);
    await runInDurableObject(c.stub, async (_, ctx) => {
      value(await activateCampaignTarget(ctx.storage, c.activation, c.resolver));
      const initial = stored(ctx).state;
      ctx.storage.transactionSync(() => {
        for (const table of ROOM_V2_DELIVERY_TABLES) {
          ctx.storage.sql.exec('DELETE FROM "' + table.name + '"');
          for (const raw of advanced.find(t => t.name === table.name)!.rows) {
            const row = { ...raw };
            if (table.name === "room") row.data = JSON.stringify({ ...JSON.parse(String(row.data)), simulation_version: 6, created_at: initial.created_at, invite_expires_at: initial.invite_expires_at });
            ctx.storage.sql.exec(table.insert, ...table.columns.map(column => row[column]));
          }
        }
      });
      const active = await inventory(ctx);
      expect(value(await initializeCampaignTarget(ctx.storage, c.request, c.resolver))).toEqual(c.ack);
      expect(value(await activateCampaignTarget(ctx.storage, c.activation, c.resolver))).toMatchObject({ accepted_revision: c.activation.accepted_revision });
      expect(await inventory(ctx)).toEqual(active);
      const state = stored(ctx).state, outgoing: SourceRequest = { schema_version: 1, binding: c.request.binding, attempt: { transition_id: "7".repeat(64), origin: { expected_revision: c.activation.accepted_revision, from_index: c.request.binding.chapter_index, source: { room_id: state.room_id, revision: state.revision, branch: state.branch, checkpoint_hash: state.checkpoint.checkpoint_hash } } } };
      expect(value(await campaignSource(ctx.storage, outgoing, true, c.resolver)).status).toBe("sealed");
      const sealed = await inventory(ctx);
      expect(value(await initializeCampaignTarget(ctx.storage, c.request, c.resolver))).toEqual(c.ack);
      expect(value(await activateCampaignTarget(ctx.storage, c.activation, c.resolver))).toMatchObject({ accepted_revision: c.activation.accepted_revision });
      expect(stored(ctx).member.seal).toEqual(outgoing.attempt); expect(await inventory(ctx)).toEqual(sealed);
      const raw = await exportRoomV2(ctx, "d".repeat(40), c.resolver);
      expect((await validateRoomV2(raw, state.room_id, c.resolver)).payload.summary.state).toBe("active");
    });
  });
  it("validates exact duplicated fields, both owners, finite pins, predecessor and invite-derived identity", async () => {
    const c = await contract(), target = room();
    const changed: unknown[] = [{ ...c.request, extra: true }, { ...c.request, schema_version: 2 }];
    for (const mutate of [
      (r: TargetInitializeRequest) => { r.binding.host_id = r.binding.guest_id; },
      (r: TargetInitializeRequest) => { r.binding.guest_id = "bad"; },
      (r: TargetInitializeRequest) => { r.binding.member_transition_id = "bad"; },
      (r: TargetInitializeRequest) => { r.binding.chapter_index = 0; r.target_intent.index = 0; },
      (r: TargetInitializeRequest) => { r.origin.source.room_id = "C".repeat(22); },
      (r: TargetInitializeRequest) => { r.origin.from_index = 1; },
      (r: TargetInitializeRequest) => { r.target_intent.index = 2; },
      (r: TargetInitializeRequest) => { r.target_intent.room_id = "Z".repeat(22); },
      (r: TargetInitializeRequest) => { r.target_intent.chapter = { ...r.target_intent.chapter, premium: !r.target_intent.chapter.premium }; },
      (r: TargetInitializeRequest) => { r.target_intent.invite_code = "AB".repeat(10); },
      (r: TargetInitializeRequest) => { r.binding.room_id = "Z".repeat(22); r.target_intent.room_id = r.binding.room_id; },
      (r: TargetInitializeRequest) => { r.binding.campaign_key.definition_hash = "f".repeat(64); },
      (r: TargetInitializeRequest) => { r.binding.chapter.simulation_version = 99; r.target_intent.chapter.simulation_version = 99; }
    ]) { const bad = structuredClone(c.request); mutate(bad); changed.push(bad); }
    await runInDurableObject(target, async (_, ctx) => {
      const before = await inventory(ctx);
      for (const bad of changed) { expect(await initializeCampaignTarget(ctx.storage, bad, c.resolver)).toMatchObject({ ok: false }); expect(await inventory(ctx)).toEqual(before); }
      expect(await activateCampaignTarget(ctx.storage, c.activation, c.resolver)).toMatchObject({ ok: false });
      expect(await inventory(ctx)).toEqual(before);
    });
    const later = await contract(2);
    expect(await campaignTargetInitialization(later.request, later.resolver)).toEqual(later.request);
    later.request.origin.source.room_id = R;
    await expect(campaignTargetInitialization(later.request, later.resolver)).rejects.toThrow();
  });
  it("holds contradictory requests against an existing target without rewriting its first binding", async () => {
    const c = await initialized();
    await runInDurableObject(c.stub, async (_, ctx) => {
      const before = await inventory(ctx);
      for (const mutate of [
        (r: TargetInitializeRequest) => { r.binding.host_id = "J".repeat(22); },
        (r: TargetInitializeRequest) => { r.binding.guest_id = "K".repeat(22); },
        (r: TargetInitializeRequest) => { r.binding.member_transition_id = "9".repeat(64); },
        (r: TargetInitializeRequest) => { r.origin.expected_revision += 1; },
        (r: TargetInitializeRequest) => { r.origin.source.checkpoint_hash = "e".repeat(64); }
      ]) { const bad = structuredClone(c.request); mutate(bad); expect(await initializeCampaignTarget(ctx.storage, bad, c.resolver)).toMatchObject({ ok: false }); expect(await activateCampaignTarget(ctx.storage, { ...bad, accepted_revision: 8 }, c.resolver)).toMatchObject({ ok: false }); expect(await inventory(ctx)).toEqual(before); }
    });
  });
  it("keeps unsupported schemas, unknown state, orphan rows and standalone rooms unchanged", async () => {
    const c = await contract();
    for (const variant of ["schema", "table", "kv", "alarm", "orphan", "standalone", "standalone_deleted"]) {
      const stub = room();
      await runInDurableObject(stub, async (instance, ctx) => {
        if (variant === "schema") ctx.storage.sql.exec("UPDATE metadata SET schema_version=7");
        if (variant === "table") ctx.storage.sql.exec("CREATE TABLE foreign_state(value TEXT)");
        if (variant === "kv") ctx.storage.kv.put("foreign", "preserved");
        if (variant === "alarm") await ctx.storage.setAlarm(Date.now() + 3_600_000);
        if (variant === "orphan") ctx.storage.sql.exec("INSERT INTO operations VALUES(?,?,?)", "orphan", "e".repeat(64), "{}");
        if (variant === "standalone") value(instance.initialize(c.request.binding.room_id, H, c.request.target_intent.invite_code, c.request.binding.chapter));
        if (variant === "standalone_deleted") ctx.storage.sql.exec("INSERT INTO room VALUES(1,?)", JSON.stringify({ deleted: true }));
        const before = await inventory(ctx);
        expect(await initializeCampaignTarget(ctx.storage, c.request, c.resolver)).toMatchObject({ ok: false });
        expect(await activateCampaignTarget(ctx.storage, c.activation, c.resolver)).toMatchObject({ ok: false });
        expect(await inventory(ctx)).toEqual(before);
      });
    }
  });
  it("holds deleting, missing-gameplay, legacy and minimal tombstone targets", async () => {
    for (const variant of ["deleting", "missing", "legacy", "tombstone"]) {
      const c = await initialized();
      await runInDurableObject(c.stub, async (_, ctx) => {
        const member = stored(ctx).member;
        if (variant === "deleting") { member.status = "deleting"; ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(member)); }
        if (variant === "missing") ctx.storage.sql.exec("DELETE FROM room");
        if (variant === "legacy") { const { schema_version: _version, incoming: _incoming, ...old } = member; ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify({ ...old, schema_version: 1 })); }
        if (variant === "tombstone") tombstone(ctx, c.request);
        const before = await inventory(ctx);
        expect(await initializeCampaignTarget(ctx.storage, c.request, c.resolver)).toMatchObject({ ok: false });
        expect(await activateCampaignTarget(ctx.storage, c.activation, c.resolver)).toMatchObject({ ok: false });
        expect(await inventory(ctx)).toEqual(before);
      });
    }
  });
  it("lets a tombstone win while a fresh initializer is validating its immutable definition", async () => {
    for (const schema6 of [false, true]) {
      const c = await contract(), stub = room();
      await runInDurableObject(stub, async (_, ctx) => {
        if (schema6) initializeCampaignStorageSchema(ctx.storage);
        const original = crypto.subtle.digest.bind(crypto.subtle); let after: Awaited<ReturnType<typeof inventory>> | undefined;
        const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { spy.mockRestore(); tombstone(ctx, c.request); after = await inventory(ctx); return original(algorithm, data); });
        try { expect(await initializeCampaignTarget(ctx.storage, c.request, c.resolver)).toMatchObject({ ok: false }); } finally { spy.mockRestore(); }
        expect(after).toBeDefined(); expect(await inventory(ctx)).toEqual(after);
      });
    }
  });
  it("rechecks deleting and tombstone state after activation validation awaits", async () => {
    for (const deleted of [false, true]) {
      const c = await initialized();
      await runInDurableObject(c.stub, async (_, ctx) => {
        const original = crypto.subtle.digest.bind(crypto.subtle); let after: Awaited<ReturnType<typeof inventory>> | undefined;
        const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => {
          spy.mockRestore();
          if (deleted) tombstone(ctx, c.request);
          else { const member = stored(ctx).member; member.status = "deleting"; ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(member)); }
          after = await inventory(ctx); return original(algorithm, data);
        });
        try { expect(await activateCampaignTarget(ctx.storage, c.activation, c.resolver)).toMatchObject({ ok: false }); } finally { spy.mockRestore(); }
        expect(after).toBeDefined(); expect(await inventory(ctx)).toEqual(after);
      });
    }
  });
  it("freezes caller request and trusted definition across hashing without accepting later mutations", async () => {
    const c = await contract(), originalRequest = structuredClone(c.request), stub = room();
    await runInDurableObject(stub, async (_, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle);
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { spy.mockRestore(); c.request.binding.guest_id = "K".repeat(22); c.definition.chapters[1].premium = true; return original(algorithm, data); });
      try { const ack = value(await initializeCampaignTarget(ctx.storage, c.request, c.resolver)); expect(ack.binding).toEqual(originalRequest.binding); expect(stored(ctx).member.guest_id).toBe(G); } finally { spy.mockRestore(); }
    });
  });
  it("rejects forged or contradictory acknowledgements and leaves default wrappers unenabled", async () => {
    const c = await initialized();
    for (const patch of [{ status: "ready" }, { ready: true }, { created_at: "not-a-time" }, { invite_expires_at: c.ack.created_at }, { origin: { ...c.ack.origin, expected_revision: 9 } }]) await expect(campaignTargetInitialized({ ...c.ack, ...patch }, c.request, c.resolver)).rejects.toThrow();
    await expect(campaignTargetActivation({ ...c.activation, accepted_revision: c.request.origin.expected_revision }, c.resolver)).rejects.toThrow();
    await runInDurableObject(c.stub, async (instance, ctx) => {
      const before = await inventory(ctx);
      expect(await instance.initializeCampaignTarget(c.request)).toMatchObject({ ok: false });
      expect(await instance.activateCampaignTarget(c.activation)).toMatchObject({ ok: false });
      expect(await inventory(ctx)).toEqual(before);
    });
  });
});
