// Retained Story protocol coverage; production withdrawal is tested without
// this test-only substitution in campaign-production.test.ts.
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => true, requireCampaignProduction: () => {}
}));

import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { canonicalJson, digest, fail, ok, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { continueCampaignControl, readCampaignControl, readCampaignOperation, resumeCampaignActivation, type CampaignControlDependencies } from "../src/v2/campaign-control";
import { campaignContinueKey, campaignContinueResult, continueOrigin } from "../src/v2/campaign-protocol";
import { campaignSource } from "../src/v2/campaign-source";
import { initializeCampaignTarget, activateCampaignTarget, type TargetInitializeRequest } from "../src/v2/campaign-target";
import { initializeCampaignStorageSchema, initializePhotoDelivery, ROOM_V2_DELIVERY_TABLES } from "../src/v2/storage-schema";
import { exportRoomV2, validateRoomV2 } from "../src/v2/snapshot";
import type { StoredCampaignAnchorV2, StoredCampaignMemberV2 } from "../src/v2/campaign-storage";
import type { CampaignContinue, CampaignDefinition, CampaignKey, CampaignView } from "../src/v2/campaign-types";
import type { RoomStateV2 } from "../src/v2/room";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import final from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";

const H = fixture.active_view.host_id, G = fixture.active_view.guest_id!, R = fixture.active_view.campaign_room_id, I = fixture.active_view.invite_code!;
const room = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
type Stub = ReturnType<typeof room>;
type Row = Record<string, string | number>;
function value<T>(out: Outcome<T>): T { if (!out.ok) throw new Error(out.code); return out.value; }
function anchor(ctx: DurableObjectState): StoredCampaignAnchorV2 { return JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data) as StoredCampaignAnchorV2; }
function state(ctx: DurableObjectState): RoomStateV2 { return JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data) as RoomStateV2; }
async function inventory(ctx: DurableObjectState) {
  const alarm = await ctx.storage.getAlarm(), kv = [...ctx.storage.kv.list()];
  const tables = ctx.storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray();
  return { alarm, kv, tables: tables.map(t => { if (t.name === "_cf_METADATA") { expect(isAlarmMetadataTable(t)).toBe(true); return { ...t, rows: null }; } return { ...t, rows: ctx.storage.sql.exec('SELECT * FROM "' + t.name + '" ORDER BY rowid').toArray() }; }) };
}
async function play(stub: Stub) {
  let s = value(await stub.snapshot(H, REQUEST_CONTEXT));
  for (const [owner, recording, checkpoint] of [[H, highA, null], [G, highB, middle], [G, lowA, null], [H, lowB, final]] as const)
    s = value(await stub.commit(owner, { base_revision: s.revision, branch: s.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) }, REQUEST_CONTEXT)).room;
}
async function setup(count = 2, complete = true) {
  const definition = structuredClone(fixture.definition) as CampaignDefinition;
  definition.campaign_id = "fixture-control-helper"; definition.chapters = Array.from({ length: count }, () => structuredClone(definition.chapters[0]));
  const { definition_hash: _old, ...unhashed } = definition; definition.definition_hash = await digest(canonicalJson(unhashed));
  const key: CampaignKey = { campaign_id: definition.campaign_id, campaign_version: 1, definition_hash: definition.definition_hash };
  const resolver = (k: CampaignKey) => canonicalJson(k) === canonicalJson(key) ? definition : undefined;
  const stub = room(); value(await stub.initialize(R, H, I, definition.chapters[0])); value(await stub.join(G, I, [6])); if (complete) await play(stub);
  await runInDurableObject(stub, async (_, ctx) => {
    const s = state(ctx), control = structuredClone(fixture.active_view) as CampaignView;
    control.campaign_key = key; control.invite_expires_at = s.invite_expires_at;
    control.chapters = definition.chapters.map((chapter, i) => ({ chapter, room_id: i ? null : R, completion: null }));
    const a: StoredCampaignAnchorV2 = { schema_version: 2, state: "live", definition, control, pending: null, closed_before_branches: Array(count).fill(0), deletion: null, activation: null };
    const m: StoredCampaignMemberV2 = { schema_version: 2, campaign_room_id: R, campaign_key: key, room_id: R, chapter_index: 0, chapter: definition.chapters[0], host_id: H, guest_id: G, transition_id: null, status: "active", seal: null, incoming: null };
    initializeCampaignStorageSchema(ctx.storage); ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify(a)); ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(m));
  });
  const targetScope = crypto.randomUUID(), requests: TargetInitializeRequest[] = [];
  const calls = { allocate: 0, admit: 0, source: 0, initialize: 0, activate: 0 };
  // Stubs are context-owned I/O objects. Retain only a deterministic test name;
  // construct each stub in the current caller's execution context.
  const target = (id: string) => env.ROOMS_V2.getByName(targetScope + ":" + id);
  const deps: CampaignControlDependencies = {
    mutationPolicy: () => ok(true), admitFresh: async () => { calls.admit++; return ok(true); },
    allocate: () => { calls.allocate++; return { transition_id: calls.allocate.toString(16).padStart(64, "0"), invite_code: (calls.allocate + 256).toString(16).padStart(20, "0").toUpperCase() }; },
    source: async (request, seal) => { calls.source++; return await runInDurableObject(target(request.binding.room_id), (_, ctx) => campaignSource(ctx.storage, request, seal, resolver)); },
    initialize: async request => { calls.initialize++; requests.push(structuredClone(request)); return await runInDurableObject(target(request.binding.room_id), (_, ctx) => initializeCampaignTarget(ctx.storage, request, resolver)); },
    activate: async request => { calls.activate++; return await runInDurableObject(target(request.binding.room_id), (_, ctx) => activateCampaignTarget(ctx.storage, request, resolver)); }
  };
  async function body(owner = H, patch: Partial<CampaignContinue> = {}): Promise<CampaignContinue> {
    const a = await runInDurableObject(stub, async (_, ctx) => anchor(ctx)), index = a.control.current_index;
    const s = await runInDurableObject(index ? target(a.control.chapters[index].room_id!) : stub, async (_, ctx) => state(ctx));
    const b = { schema_version: 1 as const, campaign_key: key, expected_revision: a.control.revision, from_index: index, source: { room_id: s.room_id, revision: s.revision, branch: s.branch, checkpoint_hash: s.checkpoint.checkpoint_hash }, ...patch };
    return { ...b, idempotency_key: await campaignContinueKey(R, key, owner, continueOrigin({ ...b, idempotency_key: "" })) };
  }
  async function advanceChild(id: string) {
    const request = requests.find(r => r.binding.room_id === id)!;
    // The local seam has no public campaign gameplay route yet. Copy rows that
    // the real ordinary coordinator accepted from native recordings; retain the
    // actual target's initialization clocks and immutable campaign sidecar.
    const played = room(); value(await played.initialize(id, H, request.target_intent.invite_code, definition.chapters[0])); value(await played.join(G, request.target_intent.invite_code, [6])); await play(played);
    const captured = await runInDurableObject(played, async (_, ctx) => { ctx.storage.transactionSync(() => initializePhotoDelivery(ctx.storage)); return ROOM_V2_DELIVERY_TABLES.map(t => ({ name: t.name, rows: ctx.storage.sql.exec<Row>(t.select).toArray() })); });
    await runInDurableObject(target(id), async (_, ctx) => {
      const before = state(ctx);
      ctx.storage.transactionSync(() => { for (const t of ROOM_V2_DELIVERY_TABLES) { ctx.storage.sql.exec('DELETE FROM "' + t.name + '"'); for (const row of captured.find(x => x.name === t.name)!.rows) {
        if (t.name === "room") { const s = JSON.parse(String(row.data)) as RoomStateV2; s.created_at = before.created_at; s.invite_expires_at = before.invite_expires_at; s.simulation_version = 6; row.data = JSON.stringify(s); }
        ctx.storage.sql.exec(t.insert, ...t.columns.map(k => row[k]));
      } } });
    });
  }
  return { stub, definition, key, resolver, deps, calls, target, requests, body, advanceChild };
}
type Setup = Awaited<ReturnType<typeof setup>>;
const post = (c: Setup, body: CampaignContinue, owner = H) => runInDurableObject(c.stub, (_, ctx) => continueCampaignControl(ctx.storage, owner, body, c.deps, c.resolver));
const get = (c: Setup, body: CampaignContinue, owner = H) => runInDurableObject(c.stub, (_, ctx) => readCampaignOperation(ctx.storage, owner, body.idempotency_key, c.resolver));
function deleting(ctx: DurableObjectState) {
  const a = anchor(ctx), m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMemberV2;
  a.control.state = "deleting"; a.deletion = { room_ids: [...a.control.chapters.flatMap(c => c.room_id ? [c.room_id] : []), ...(a.pending?.target_intent ? [a.pending.target_intent.room_id] : [])], completed_room_ids: [] }; m.status = "deleting";
  ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m));
}
const REQUEST_CONTEXT = { schema_version: 2 as const, room_id: R, device_hash: "a".repeat(64) };
// Public Room calls now require original-device protocol context; the existing
// fixture helpers and all original lifecycle/proof assertions stay unchanged.
beforeEach(async () => {
  for (const owner of [H, G]) value(await env.PLAYERS.getByName(owner).create(owner, REQUEST_CONTEXT.device_hash, "b".repeat(64)));
});
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("private campaign control prepare/publication/activation", () => {
  it("publishes and discharges once, reconstructs a missing owner alias with read-only GET, then finishes without target calls", async () => {
    const c = await setup(), host = await c.body(), guest = await c.body(G);
    const accepted = value(await post(c, host)); expect(accepted.status).toBe("accepted"); expect(accepted.campaign).toMatchObject({ revision: 6, current_index: 1, activation: null });
    expect(c.calls).toEqual({ allocate: 1, admit: 1, source: 0, initialize: 1, activate: 1 });
    await runInDurableObject(c.stub, async (_, ctx) => {
      const before = await inventory(ctx); const recovered = value(await readCampaignOperation(ctx.storage, G, guest.idempotency_key, c.resolver));
      expect(recovered.status).toBe("accepted"); expect(recovered.campaign.invite_code).toBeNull(); expect(await inventory(ctx)).toEqual(before);
      expect(ctx.storage.sql.exec("SELECT 1 FROM campaign_operations").toArray()).toHaveLength(1);
    });
    c.deps.admitFresh = async () => fail(403, "purchase_now_unavailable");
    expect(value(await post(c, guest, G)).status).toBe("accepted"); expect(c.calls.allocate).toBe(1);
    await evictDurableObject(c.stub); expect(value(await post(c, host))).toEqual(accepted);
    await c.advanceChild(accepted.campaign.chapters[1].room_id!); c.deps.admitFresh = async () => ok(true);
    const finish = await c.body(G), ended = value(await post(c, finish, G)); expect(ended).toMatchObject({ status: "accepted", receipt: { outcome: "finished", next_room_id: null }, campaign: { state: "complete", activation: null, revision: 9 } });
    expect(c.calls.initialize).toBe(1); expect(c.calls.activate).toBe(1);
    await runInDurableObject(c.stub, async (_, ctx) => { const raw = await exportRoomV2(ctx, "d".repeat(40), c.resolver); expect((await validateRoomV2(raw, R, c.resolver)).payload.format_version).toBe(8); });
  });
  it("attaches both owners to one durable target and converts every alias atomically", async () => {
    const c = await setup(), a = await c.body(), b = await c.body(G);
    await runInDurableObject(c.stub, async (_, ctx) => {
      const initialize = c.deps.initialize; let entered!: () => void, release!: () => void;
      const waiting = new Promise<void>(r => entered = r), gate = new Promise<void>(r => release = r);
      c.deps.initialize = async r => { entered(); await gate; return await initialize(r); };
      const first = continueCampaignControl(ctx.storage, H, a, c.deps, c.resolver); await waiting;
      const second = continueCampaignControl(ctx.storage, G, b, { ...c.deps, initialize: async () => fail(503, "second_alias_attached") }, c.resolver);
      expect(await second).toMatchObject({ ok: false, code: "second_alias_attached" });
      expect(ctx.storage.sql.exec("SELECT 1 FROM campaign_operations").toArray()).toHaveLength(2); expect(anchor(ctx).pending?.phase).toBe("source_sealed");
      release(); expect(value(await first).status).toBe("accepted");
      expect(anchor(ctx).pending).toBeNull(); expect(anchor(ctx).control.revision).toBe(6);
      expect(ctx.storage.sql.exec<{ receipt: string }>("SELECT receipt FROM campaign_operations").toArray().every(r => JSON.parse(r.receipt).status === "accepted")).toBe(true);
    });
    expect(c.requests.every(r => r.binding.room_id === c.requests[0].binding.room_id && r.binding.member_transition_id === c.requests[0].binding.member_transition_id)).toBe(true);
  });
  it("retains accepted debt after activation reply loss; GET stays inert and exact Resume preserves the original accepted revision", async () => {
    const c = await setup(), b = await c.body(), activate = c.deps.activate;
    c.deps.activate = async r => { value(await activate(r)); return fail(503, "lost_reply"); };
    const accepted = value(await post(c, b)); expect(accepted.status).toBe("accepted"); if (accepted.status !== "accepted") return;
    expect(accepted.campaign.revision).toBe(5); expect(accepted.campaign.activation?.transition_id).toBe(accepted.receipt.transition_id);
    await evictDurableObject(c.stub); const calls = structuredClone(c.calls);
    expect(value(await get(c, b))).toEqual(accepted); expect(c.calls).toEqual(calls);
    c.deps.activate = activate;
    const resume = { schema_version: 1, campaign_key: c.key, transition_id: accepted.receipt.transition_id };
    const ready = await runInDurableObject(c.stub, (_, ctx) => resumeCampaignActivation(ctx.storage, G, resume, c.deps, c.resolver));
    expect(value(ready).campaign).toMatchObject({ revision: 6, activation: null }); expect(value(await get(c, b))).toMatchObject({ receipt: { accepted_revision: 5 } });
    const n = c.calls.activate; await runInDurableObject(c.stub, (_, ctx) => resumeCampaignActivation(ctx.storage, H, resume, c.deps, c.resolver)); expect(c.calls.activate).toBe(n);
  });
  it("recovers source seal persistence and target init reply loss without replacing intent", async () => {
    const c = await setup(), b = await c.body();
    await runInDurableObject(c.stub, async (_, ctx) => {
      const original = ctx.storage.sql.exec.bind(ctx.storage.sql); let failed = false;
      const spy = vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((query: string, ...args: unknown[]) => {
        if (!failed && query === "UPDATE campaign_anchor SET data=? WHERE id=1" && JSON.parse(String(args[0])).pending?.phase === "source_sealed") { failed = true; throw new Error("lost_phase_write"); }
        return original(query, ...args);
      }) as typeof ctx.storage.sql.exec);
      try { expect(await continueCampaignControl(ctx.storage, H, b, c.deps, c.resolver)).toMatchObject({ ok: false }); } finally { spy.mockRestore(); }
      expect(anchor(ctx).pending?.phase).toBe("prepared"); expect(JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data).status).toBe("sealed");
    });
    await evictDurableObject(c.stub); const initialize = c.deps.initialize;
    c.deps.initialize = async r => { value(await initialize(r)); return fail(503, "lost_init_reply"); };
    expect(await post(c, b)).toMatchObject({ ok: false, code: "lost_init_reply" }); const pending = value(await get(c, b)); expect(pending.campaign.transition?.phase).toBe("source_sealed");
    await evictDurableObject(c.stub); c.deps.initialize = initialize;
    expect(value(await post(c, b)).status).toBe("accepted"); expect(c.calls.allocate).toBe(1); expect(c.requests[0]).toEqual(c.requests[1]);
  });
  it("rejects wrong source and control revisions before installing any intent or alias", async () => {
    for (const mode of ["incomplete", "checkpoint", "revision", "control"] as const) {
      const c = await setup(2, mode !== "incomplete"); let b = await c.body();
      if (mode === "checkpoint") b = await c.body(H, { source: { ...b.source, checkpoint_hash: "f".repeat(64) } });
      if (mode === "revision") b = await c.body(H, { source: { ...b.source, revision: b.source.revision + 100 } });
      if (mode === "control") b = await c.body(H, { expected_revision: 1000 });
      await runInDurableObject(c.stub, async (_, ctx) => { const before = await inventory(ctx); expect(await continueCampaignControl(ctx.storage, H, b, c.deps, c.resolver)).toMatchObject({ ok: false }); expect(await inventory(ctx)).toEqual(before); });
      expect(c.calls.initialize).toBe(0);
    }
  });
  it("keeps deleting state and all allocated targets fenced before or after each external callback", async () => {
    for (const point of ["admitFresh", "initialize", "activate"] as const) {
      const c = await setup(), b = await c.body(), call = c.deps[point];
      await runInDurableObject(c.stub, async (_, ctx) => {
        if (point === "admitFresh") c.deps.admitFresh = async (...args) => { const out = await (call as CampaignControlDependencies["admitFresh"])(...args); deleting(ctx); return out; };
        if (point === "initialize") c.deps.initialize = async r => { const out = await (call as CampaignControlDependencies["initialize"])(r); deleting(ctx); return out; };
        if (point === "activate") c.deps.activate = async r => { const out = await (call as CampaignControlDependencies["activate"])(r); deleting(ctx); return out; };
        expect(await continueCampaignControl(ctx.storage, H, b, c.deps, c.resolver)).toMatchObject({ ok: false, code: "campaign_deleting" });
        const a = anchor(ctx), before = await inventory(ctx); expect(a.control.state).toBe("deleting");
        if (a.pending?.target_intent) expect(a.deletion!.room_ids).toContain(a.pending.target_intent.room_id);
        expect(value(await readCampaignControl(ctx.storage, H, c.resolver)).campaign.state).toBe("deleting"); expect(await continueCampaignControl(ctx.storage, H, b, c.deps, c.resolver)).toMatchObject({ ok: false }); expect(await inventory(ctx)).toEqual(before);
      });
    }
  });
  it("holds malformed target ack with the exact saved target and allows a later deliberate retry", async () => {
    const c = await setup(), b = await c.body(), initialize = c.deps.initialize;
    c.deps.initialize = async r => { const out = value(await initialize(r)) as Record<string, unknown>; return ok({ ...out, ready: true }); };
    expect(await post(c, b)).toMatchObject({ ok: false }); expect(value(await get(c, b)).campaign.transition?.phase).toBe("source_sealed");
    c.deps.initialize = initialize; expect(value(await post(c, b)).status).toBe("accepted"); expect(c.calls.allocate).toBe(1);
  });
  it("holds deletion at both actual child source observation and seal replies", async () => {
    for (const sealBoundary of [false, true]) {
      const c = await setup(3), first = value(await post(c, await c.body()));
      await c.advanceChild(first.campaign.chapters[1].room_id!); const body = await c.body(), original = c.deps.source;
      await runInDurableObject(c.stub, async (_, ctx) => {
        c.deps.source = async (request, seal) => { const out = await original(request, seal); if (seal === sealBoundary) deleting(ctx); return out; };
        expect(await continueCampaignControl(ctx.storage, H, body, c.deps, c.resolver)).toMatchObject({ ok: false, code: "campaign_deleting" });
        const a = anchor(ctx), before = await inventory(ctx); expect(a.control.state).toBe("deleting");
        if (sealBoundary) { expect(a.pending?.phase).toBe("prepared"); expect(a.deletion!.room_ids).toContain(a.pending!.target_intent!.room_id); }
        else expect(a.pending).toBeNull();
        expect(await continueCampaignControl(ctx.storage, H, body, c.deps, c.resolver)).toMatchObject({ ok: false, code: "campaign_deleting" }); expect(await inventory(ctx)).toEqual(before);
      });
    }
  });
  it("can read a missing accepted owner alias during deleting without inserting it", async () => {
    const c = await setup(), a = await c.body(), b = await c.body(G); expect(value(await post(c, a)).status).toBe("accepted");
    await runInDurableObject(c.stub, async (_, ctx) => {
      deleting(ctx); const before = await inventory(ctx);
      expect(value(await readCampaignOperation(ctx.storage, G, b.idempotency_key, c.resolver))).toMatchObject({ status: "accepted", campaign: { state: "deleting" } });
      expect(await continueCampaignControl(ctx.storage, G, b, c.deps, c.resolver)).toEqual(fail(409, "campaign_deleting")); expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("returns concurrent durable acceptance before a late admission or source-observation failure", async () => {
    for (const boundary of ["admission", "observation"] as const) {
      const c = await setup(3);
      if (boundary === "observation") { const first = value(await post(c, await c.body())); await c.advanceChild(first.campaign.chapters[1].room_id!); }
      const a = await c.body(), b = await c.body(G); let entered!: () => void, release!: () => void;
      await runInDurableObject(c.stub, async (_, ctx) => {
      const waiting = new Promise<void>(r => entered = r), gate = new Promise<void>(r => release = r);
      if (boundary === "admission") {
        const original = c.deps.admitFresh; c.deps.admitFresh = async (owner, ...args) => { if (owner === H) { entered(); await gate; return fail(403, "late_admission_error"); } return await original(owner, ...args); };
      } else {
        const original = c.deps.source; let held = false;
        c.deps.source = async (request, seal) => { if (!seal && !held) { held = true; entered(); await gate; return fail(503, "late_observe_error"); } return await original(request, seal); };
      }
      const delayed = continueCampaignControl(ctx.storage, H, a, c.deps, c.resolver); await waiting;
      expect(value(await continueCampaignControl(ctx.storage, G, b, c.deps, c.resolver)).status).toBe("accepted"); release(); expect(value(await delayed).status).toBe("accepted");
      });
    }
  });
  it("rolls all owner aliases back together if publication fails during the second conversion", async () => {
    const c = await setup(), a = await c.body(), b = await c.body(G), initialize = c.deps.initialize;
    c.deps.initialize = async () => fail(503, "hold_before_publication");
    expect(await post(c, a)).toMatchObject({ ok: false }); expect(await post(c, b, G)).toMatchObject({ ok: false }); c.deps.initialize = initialize;
    await runInDurableObject(c.stub, async (_, ctx) => {
      const original = ctx.storage.sql.exec.bind(ctx.storage.sql); let conversions = 0;
      const spy = vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((query: string, ...args: unknown[]) => {
        if (query === "UPDATE campaign_operations SET receipt=? WHERE request_key=?" && ++conversions === 2) throw new Error("second_alias_write_failed");
        return original(query, ...args);
      }) as typeof ctx.storage.sql.exec);
      try { expect(await continueCampaignControl(ctx.storage, H, a, c.deps, c.resolver)).toMatchObject({ ok: false }); } finally { spy.mockRestore(); }
      expect(anchor(ctx)).toMatchObject({ pending: { phase: "target_initialized" }, control: { revision: 4, current_index: 0 } });
      expect(ctx.storage.sql.exec<{ receipt: string }>("SELECT receipt FROM campaign_operations").toArray().every(r => JSON.parse(r.receipt).status === "pending")).toBe(true);
    });
    expect(value(await post(c, a)).status).toBe("accepted"); expect(value(await get(c, b, G)).status).toBe("accepted");
  });
  it("does not clear a later activation debt when an earlier Resume reply arrives late", async () => {
    const c = await setup(3), first = await c.body(), activate = c.deps.activate;
    c.deps.activate = async () => fail(503, "save_first_debt"); const accepted = value(await post(c, first));
    expect(accepted.status).toBe("accepted"); if (accepted.status !== "accepted") return;
    const oldToken = accepted.receipt.transition_id, resume = { schema_version: 1, campaign_key: c.key, transition_id: oldToken };
    await runInDurableObject(c.stub, async (_, ctx) => {
    let entered!: () => void, release!: () => void, held = false;
    const waiting = new Promise<void>(r => entered = r), gate = new Promise<void>(r => release = r);
    c.deps.activate = async request => { if (request.binding.member_transition_id === oldToken && !held) { held = true; entered(); await gate; } return await activate(request); };
    const delayed = resumeCampaignActivation(ctx.storage, H, resume, c.deps, c.resolver); await waiting;
    value(await resumeCampaignActivation(ctx.storage, G, resume, c.deps, c.resolver));
    await c.advanceChild(accepted.campaign.chapters[1].room_id!); c.deps.activate = async () => fail(503, "save_later_debt");
    const current = anchor(ctx), s = await runInDurableObject(c.target(current.control.chapters[1].room_id!), async (_, childCtx) => state(childCtx));
    const origin = { expected_revision: current.control.revision, from_index: 1, source: { room_id: s.room_id, revision: s.revision, branch: s.branch, checkpoint_hash: s.checkpoint.checkpoint_hash } };
    const next: CampaignContinue = { schema_version: 1, campaign_key: c.key, idempotency_key: await campaignContinueKey(R, c.key, G, origin), ...origin };
    const later = value(await continueCampaignControl(ctx.storage, G, next, c.deps, c.resolver)); expect(later.campaign.activation).not.toBeNull(); expect(later.campaign.activation?.transition_id).not.toBe(oldToken);
    release(); const observed = value(await delayed); expect(observed.campaign).toMatchObject({ revision: later.campaign.revision, activation: later.campaign.activation });
    });
  });
  it("uses actual fork chronology, never a copied fence, to reject a prior source", async () => {
    const c = await setup(), old = await c.body();
    await runInDurableObject(c.stub, async (instance, ctx) => { const s = state(ctx); value(await instance.fork(H, { base_revision: s.revision, branch: s.branch, stage_index: 0, idempotency_key: crypto.randomUUID() }, REQUEST_CONTEXT)); });
    const rejected = value(await post(c, old)); expect(rejected.status).toBe("rejected"); expect(await campaignContinueResult(rejected, R, H, old, c.resolver)).toEqual(rejected);
    for (const changed of [{ ...old, expected_revision: 1000 }, { ...old, source: { ...old.source, revision: 1000 } }]) {
      changed.idempotency_key = await campaignContinueKey(R, c.key, H, continueOrigin(changed));
      expect(await post(c, changed)).toMatchObject({ ok: false });
    }
    expect(c.calls.initialize).toBe(0); await play(c.stub);
    const now = await c.body(); expect(value(await post(c, now)).status).toBe("accepted");
    const before = await runInDurableObject(c.stub, (_, ctx) => inventory(ctx));
    expect(value(await post(c, old)).status).toBe("rejected");
    const foreign = { ...old, source: { ...old.source, room_id: "X".repeat(22) } }; foreign.idempotency_key = await campaignContinueKey(R, c.key, H, continueOrigin(foreign));
    expect(await post(c, foreign)).toMatchObject({ ok: false });
    expect(await runInDurableObject(c.stub, (_, ctx) => inventory(ctx))).toEqual(before);
  });
  it("reconciles a prepared root whose genuine fork wins before sealing", async () => {
    const c = await setup(), b = await c.body();
    await runInDurableObject(c.stub, async (instance, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle); let forked = false;
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementation(async (algorithm, data) => {
        if (!forked && anchor(ctx).pending?.phase === "prepared") {
          forked = true; const s = state(ctx); value(await instance.fork(H, { base_revision: s.revision, branch: s.branch, stage_index: 0, idempotency_key: crypto.randomUUID() }, REQUEST_CONTEXT));
        }
        return original(algorithm, data);
      });
      let first: Awaited<ReturnType<typeof continueCampaignControl>>;
      try { first = await continueCampaignControl(ctx.storage, H, b, c.deps, c.resolver); }
      finally { spy.mockRestore(); }
      const out = value(first.ok ? first : await continueCampaignControl(ctx.storage, H, b, c.deps, c.resolver)); expect(out.status).toBe("rejected");
      expect(forked).toBe(true); expect(anchor(ctx)).toMatchObject({ pending: null, control: { state: "active", transition: null }, closed_before_branches: [1, 0] });
      expect(ctx.storage.sql.exec("SELECT 1 FROM campaign_operations").toArray()).toHaveLength(0);
    });
  });
  it("preserves empty lookup and caller identity without mutation, and clones mutable input before the initial hash await", async () => {
    const c = await setup(), b = await c.body();
    await runInDurableObject(c.stub, async (_, ctx) => {
      const before = await inventory(ctx); expect(await readCampaignOperation(ctx.storage, H, "f".repeat(64), c.resolver)).toEqual(fail(404, "operation_not_found"));
      expect(await readCampaignControl(ctx.storage, "X".repeat(22), c.resolver)).toMatchObject({ ok: false, code: "campaign_owner_mismatch" }); expect(await inventory(ctx)).toEqual(before);
      const mutable = structuredClone(b), running = continueCampaignControl(ctx.storage, H, mutable, c.deps, c.resolver); mutable.source.revision += 900; mutable.expected_revision += 900;
      const accepted = value(await running); expect(accepted.status).toBe("accepted"); expect(await campaignContinueResult(accepted, R, H, b, c.resolver)).toEqual(accepted);
    });
  });
  it("keeps explicit legacy sidecar1 exportable while every live helper holds it without writes", async () => {
    const c = await setup(), b = await c.body();
    await runInDurableObject(c.stub, async (_, ctx) => {
      const a = anchor(ctx), m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data) as StoredCampaignMemberV2;
      const { activation: _debt, ...rest } = a, { activation: _marker, ...control } = a.control, { incoming: _incoming, ...member } = m;
      ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify({ ...rest, schema_version: 1, control: { ...control, schema_version: 1 } }));
      ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify({ ...member, schema_version: 1 }));
      const before = await inventory(ctx);
      expect(await readCampaignControl(ctx.storage, H, c.resolver)).toMatchObject({ ok: false });
      expect(await readCampaignOperation(ctx.storage, H, b.idempotency_key, c.resolver)).toMatchObject({ ok: false });
      expect(await continueCampaignControl(ctx.storage, H, b, c.deps, c.resolver)).toMatchObject({ ok: false });
      expect((await validateRoomV2(await exportRoomV2(ctx, "d".repeat(40), c.resolver), R, c.resolver)).payload.format_version).toBe(8);
      expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("bounds a full eight-entry journey at sixteen aliases and preserves old receipts after later progress", async () => {
    const c = await setup(8); const first: CampaignContinue[] = [];
    for (let i = 0; i < 8; i++) {
      const a = await c.body(), b = await c.body(G); if (i === 0) first.push(a, b);
      const accepted = value(await post(c, a)); expect(value(await post(c, b, G)).status).toBe("accepted");
      if (i < 7) await c.advanceChild(accepted.campaign.chapters[i + 1].room_id!);
    }
    await runInDurableObject(c.stub, async (_, ctx) => { expect(ctx.storage.sql.exec("SELECT 1 FROM campaign_operations").toArray()).toHaveLength(16); expect(anchor(ctx).control.state).toBe("complete");
      const before = await inventory(ctx); expect(value(await readCampaignOperation(ctx.storage, H, first[0].idempotency_key, c.resolver))).toMatchObject({ status: "accepted", receipt: { accepted_revision: 5 } }); expect(await inventory(ctx)).toEqual(before);
      expect((await validateRoomV2(await exportRoomV2(ctx, "e".repeat(40), c.resolver), R, c.resolver)).payload.format_version).toBe(8);
    });
    expect(c.calls.initialize).toBe(7); expect(c.calls.activate).toBe(7);
  });
});
