import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { canonicalJson, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { initializeCampaignRoot, joinCampaignRoot, type CampaignRootInitialization } from "../src/v2/campaign-root";
import { reserveCampaignCreation, readCampaignCreation, reserveCampaignGuestLink } from "../src/v2/campaign-player";
import { initializeCampaignStorageSchema } from "../src/v2/storage-schema";
import { exportRoomV2, validateRoomV2 } from "../src/v2/snapshot";
import type { CampaignCreation } from "../src/v2/campaign-creation-intent";
import type { CampaignDefinition, CampaignKey, CampaignJoin } from "../src/v2/campaign-types";
import type { RoomStateV2 } from "../src/v2/room";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";

const H = fixture.active_view.host_id, G = fixture.active_view.guest_id!, R = fixture.active_view.campaign_room_id, I = fixture.active_view.invite_code!;
const D = "a".repeat(64), RECOVERY = "b".repeat(64), K = "saved-creation-key-0001";
const room = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()), player = () => env.PLAYERS.get(env.PLAYERS.newUniqueId());
function value<T>(out: Outcome<T>): T { if (!out.ok) throw new Error(out.code); return out.value; }
const definition = fixture.definition as CampaignDefinition, campaignKey = fixture.active_view.campaign_key as CampaignKey;
const resolver = (key: CampaignKey) => canonicalJson(key) === canonicalJson(campaignKey) ? definition : undefined;
const intent = (): CampaignCreation => ({ creation_schema: 2, link: { room_id: R, invite_code: I, host: true, api_version: 3 }, campaign_key: structuredClone(campaignKey) });
const request = (): CampaignRootInitialization => ({ schema_version: 1, host_id: H, intent: intent() });
const join = (): CampaignJoin => ({ schema_version: 1, invite_code: I, campaign_key: structuredClone(campaignKey), supported_simulation_versions: [6] });
const state = (ctx: DurableObjectState) => JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data) as RoomStateV2;
async function inventory(ctx: DurableObjectState) {
  const alarm = await ctx.storage.getAlarm(), kv = [...ctx.storage.kv.list()];
  const tables = ctx.storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray();
  return { alarm, kv, tables: tables.map(t => { if (t.name === "_cf_METADATA") { expect(isAlarmMetadataTable(t)).toBe(true); return { ...t, rows: null }; } return { ...t, rows: ctx.storage.sql.exec('SELECT * FROM "' + t.name + '" ORDER BY rowid').toArray() }; }) };
}
async function initialized(schema6 = false) { const stub = room(); const ack = await runInDurableObject(stub, (_, ctx) => { if (schema6) initializeCampaignStorageSchema(ctx.storage); return initializeCampaignRoot(ctx.storage, request(), resolver); }); value(ack); return { stub, ack: value(ack) }; }
async function account(owner = H) { const stub = player(); value(await stub.create(owner, D, RECOVERY)); return stub; }
function deleted(ctx: DurableObjectState) {
  initializeCampaignStorageSchema(ctx.storage); ctx.storage.sql.exec("DELETE FROM room"); ctx.storage.sql.exec("DELETE FROM campaign_member"); ctx.storage.sql.exec("DELETE FROM campaign_anchor");
  ctx.storage.sql.exec("INSERT INTO room VALUES(1,?)", JSON.stringify({ deleted: true }));
  ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify({ schema_version: 1, status: "deleted", campaign_room_id: R, room_id: R }));
  ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify({ schema_version: 1, state: "deleted", campaign_room_id: R }));
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("disabled root initialization and local Join", () => {
  it("atomically installs waiting root rows and preserves exact initial facts across eviction", async () => {
    for (const schema6 of [false, true]) {
      const c = await initialized(schema6); expect(c.ack).toMatchObject({ created: true, campaign: { revision: 0, state: "waiting", guest_id: null } });
      await runInDurableObject(c.stub, async (_, ctx) => { const before = await inventory(ctx); expect(value(await initializeCampaignRoot(ctx.storage, request(), resolver))).toEqual({ ...c.ack, created: false }); expect(await inventory(ctx)).toEqual(before);
        const raw = await exportRoomV2(ctx, "f".repeat(40), resolver); expect((await validateRoomV2(raw, R, resolver)).payload.format_version).toBe(8);
      });
      await evictDurableObject(c.stub); await runInDurableObject(c.stub, async (_, ctx) => { expect(value(await initializeCampaignRoot(ctx.storage, request(), resolver))).toEqual({ ...c.ack, created: false }); });
    }
  });
  it("rolls back all root rows and schema promotion when the final anchor insert fails", async () => {
    const stub = room(); await runInDurableObject(stub, async (_, ctx) => {
      const before = await inventory(ctx), original = ctx.storage.sql.exec.bind(ctx.storage.sql); let sawPairedRows = false;
      const spy = vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((sql: string, ...args: unknown[]) => {
        if (sql === "INSERT INTO campaign_anchor VALUES(1,?)") { sawPairedRows = original("SELECT 1 FROM room").toArray().length === 1 && original("SELECT 1 FROM campaign_member").toArray().length === 1; throw new Error("final_root_row_failed"); } return original(sql, ...args);
      }) as typeof ctx.storage.sql.exec);
      try { expect(await initializeCampaignRoot(ctx.storage, request(), resolver)).toMatchObject({ ok: false }); } finally { spy.mockRestore(); }
      expect(sawPairedRows).toBe(true); expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("preserves a real accepted host A through Join, retries after expiry, and subsequent receiver commit", async () => {
    const c = await initialized(); let current = value(await c.stub.snapshot(H));
    const body = { base_revision: current.revision, branch: 0, idempotency_key: "host-a-before-join", recording: highA };
    current = value(await c.stub.commit(H, body)).room; expect(current.revision).toBe(1);
    const joined = await runInDurableObject(c.stub, async (_, ctx) => {
      const proofs = ctx.storage.sql.exec("SELECT * FROM turns").toArray(), operations = ctx.storage.sql.exec("SELECT * FROM operations").toArray(), before = state(ctx);
      const out = value(await joinCampaignRoot(ctx.storage, G, join(), resolver)); expect(out.campaign).toMatchObject({ revision: 1, state: "active", guest_id: G, player_slot: "p1", invite_code: null });
      expect(state(ctx)).toMatchObject({ revision: 2, guest_id: G, a_turn_id: "t0-0-a", checkpoint: before.checkpoint, created_at: before.created_at, invite_expires_at: before.invite_expires_at });
      expect(ctx.storage.sql.exec("SELECT * FROM turns").toArray()).toEqual(proofs); expect(ctx.storage.sql.exec("SELECT * FROM operations").toArray()).toEqual(operations); return out;
    });
    current = value(await c.stub.snapshot(G)); current = value(await c.stub.commit(G, { base_revision: current.revision, branch: 0, idempotency_key: "guest-b-after-join", recording: highB, checkpoint: middle })).room;
    await evictDurableObject(c.stub);
    await runInDurableObject(c.stub, async (_, ctx) => { const before = await inventory(ctx), clock = vi.spyOn(Date, "now").mockReturnValue(Date.parse(state(ctx).invite_expires_at) + 1);
      try { expect(value(await joinCampaignRoot(ctx.storage, G, join(), resolver))).toEqual(joined); expect(value(await joinCampaignRoot(ctx.storage, H, join(), resolver)).campaign.player_slot).toBe("p0"); expect(value(await initializeCampaignRoot(ctx.storage, request(), resolver)).created).toBe(false); }
      finally { clock.mockRestore(); }
      expect(await inventory(ctx)).toEqual(before); expect(state(ctx).stage_index).toBe(1);
    });
  });
  it("rolls all three Join rows back if the final control write fails", async () => {
    const c = await initialized(); await runInDurableObject(c.stub, async (_, ctx) => {
      const before = await inventory(ctx), original = ctx.storage.sql.exec.bind(ctx.storage.sql); let sawGuest = false;
      const spy = vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((sql: string, ...args: unknown[]) => { if (sql === "UPDATE campaign_anchor SET data=? WHERE id=1") { sawGuest = JSON.parse(String(original("SELECT data FROM room").one().data)).guest_id === G; throw new Error("last_join_row_failed"); } return original(sql, ...args); }) as typeof ctx.storage.sql.exec);
      try { expect(await joinCampaignRoot(ctx.storage, G, join(), resolver)).toMatchObject({ ok: false }); } finally { spy.mockRestore(); }
      expect(sawGuest).toBe(true); expect(await inventory(ctx)).toEqual(before);
      expect(value(await joinCampaignRoot(ctx.storage, G, join(), resolver)).campaign.guest_id).toBe(G);
    });
  });
  it("holds unknown manifests, collisions, foreign owners and unsupported Join versions without writes", async () => {
    const c = await initialized(); await runInDurableObject(c.stub, async (_, ctx) => {
      const before = await inventory(ctx);
      expect(await initializeCampaignRoot(ctx.storage, request())).toMatchObject({ ok: false });
      expect(await initializeCampaignRoot(ctx.storage, { ...request(), host_id: G }, resolver)).toMatchObject({ ok: false });
      expect(await joinCampaignRoot(ctx.storage, G, { ...join(), supported_simulation_versions: [7] }, resolver)).toMatchObject({ ok: false });
      expect(await joinCampaignRoot(ctx.storage, G, { ...join(), invite_code: "EF".repeat(10) }, resolver)).toMatchObject({ ok: false });
      expect(await inventory(ctx)).toEqual(before);
    });
    const standalone = room(); value(await standalone.initialize(R, H, I, definition.chapters[0]));
    await runInDurableObject(standalone, async (_, ctx) => { const before = await inventory(ctx); expect(await initializeCampaignRoot(ctx.storage, request(), resolver)).toMatchObject({ ok: false }); expect(await inventory(ctx)).toEqual(before); });
  });
  it("holds a fresh expired guest and a third member without changing prior membership", async () => {
    const c = await initialized(); await runInDurableObject(c.stub, async (_, ctx) => {
      const before = await inventory(ctx), clock = vi.spyOn(Date, "now").mockReturnValue(Date.parse(state(ctx).invite_expires_at) + 1);
      try { expect(await joinCampaignRoot(ctx.storage, G, join(), resolver)).toMatchObject({ ok: false, code: "invite_expired" }); expect(value(await joinCampaignRoot(ctx.storage, H, join(), resolver)).campaign.player_slot).toBe("p0"); }
      finally { clock.mockRestore(); }
      expect(await inventory(ctx)).toEqual(before); value(await joinCampaignRoot(ctx.storage, G, join(), resolver));
      const paired = await inventory(ctx); expect(await joinCampaignRoot(ctx.storage, "X".repeat(22), join(), resolver)).toMatchObject({ ok: false, code: "campaign_full" }); expect(await inventory(ctx)).toEqual(paired);
    });
  });
  it("cannot overwrite a same-schema tombstone installed during hash validation", async () => {
    for (const schema6 of [false, true]) {
      const stub = room(); await runInDurableObject(stub, async (_, ctx) => {
        if (schema6) initializeCampaignStorageSchema(ctx.storage); const original = crypto.subtle.digest.bind(crypto.subtle); let tombstoned: Awaited<ReturnType<typeof inventory>>;
        const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { spy.mockRestore(); deleted(ctx); tombstoned = await inventory(ctx); return original(algorithm, data); });
        expect(await initializeCampaignRoot(ctx.storage, request(), resolver)).toMatchObject({ ok: false }); expect(await inventory(ctx)).toEqual(tombstoned!);
      });
    }
  });
  it("freezes definition and caller intent before hashing and rejects a Join after deleting wins validation", async () => {
    const stub = room(); await runInDurableObject(stub, async (_, ctx) => {
      const mutable = request(), manifest = structuredClone(definition), original = crypto.subtle.digest.bind(crypto.subtle);
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { spy.mockRestore(); mutable.host_id = G; manifest.chapters[0] = manifest.chapters[1]; return original(algorithm, data); });
      expect(value(await initializeCampaignRoot(ctx.storage, mutable, () => manifest)).campaign.host_id).toBe(H);
      let before: Awaited<ReturnType<typeof inventory>>;
      const deletingSpy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => {
        deletingSpy.mockRestore(); const a = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data), m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data);
        a.control.state = "deleting"; a.deletion = { room_ids: [R], completed_room_ids: [] }; m.status = "deleting";
        ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m)); before = await inventory(ctx); return original(algorithm, data);
      });
      expect(await joinCampaignRoot(ctx.storage, G, join(), resolver)).toMatchObject({ ok: false }); expect(await inventory(ctx)).toEqual(before!);
    });
  });
});

describe("durable api3 Player reservations and protected history", () => {
  it("atomically retains full host intent and one api3 slot across retry, capacity and eviction", async () => {
    const p = await account(); expect(value(await p.campaignCreation(K, campaignKey, D))).toBeNull();
    expect(value(await p.reserveCampaignRoom(K, intent(), D))).toEqual(intent());
    for (let i = 0; i < 19; i++) value(await p.addRoom({ room_id: String(i).padStart(22, "X"), invite_code: "", host: false }));
    expect(value(await p.reserveCampaignRoom(K, intent(), D))).toEqual(intent()); expect(await p.reserveCampaignGuest("Y".repeat(22), D)).toMatchObject({ ok: false, code: "room_limit_reached" });
    await evictDurableObject(p); expect(value(await p.campaignCreation(K, campaignKey, D))).toEqual(intent());
    expect((await p.listRooms()).filter(link => link.api_version === 3)).toHaveLength(1);
  });
  it("preserves guest prelinks and refuses version/host conflicts without extra slots", async () => {
    const p = await account(G); const expected = { room_id: R, invite_code: "", host: false, api_version: 3 };
    expect(value(await p.reserveCampaignGuest(R, D))).toEqual(expected); await evictDurableObject(p); expect(value(await p.reserveCampaignGuest(R, D))).toEqual(expected);
    expect(await p.reserveCampaignRoom(K, intent(), D)).toMatchObject({ ok: false, code: "room_version_conflict" }); expect(await p.listRooms()).toEqual([expected]);
    const other = await account(); value(await other.addRoom({ room_id: R, invite_code: "", host: false, api_version: 2 })); expect(await other.reserveCampaignGuest(R, D)).toMatchObject({ ok: false, code: "room_version_conflict" });
  });
  it("rolls the host creation row back when the link write fails", async () => {
    const p = await account(); await runInDurableObject(p, async (_, ctx) => {
      const before = await inventory(ctx), original = ctx.storage.sql.exec.bind(ctx.storage.sql); let sawIntent = false;
      const spy = vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((sql: string, ...args: unknown[]) => { if (sql === "INSERT INTO rooms VALUES(?,?)") { sawIntent = original("SELECT 1 FROM creations").toArray().length === 1; throw new Error("link_write_failed"); } return original(sql, ...args); }) as typeof ctx.storage.sql.exec);
      try { expect(await reserveCampaignCreation(ctx.storage, H, K, intent(), D)).toMatchObject({ ok: false }); } finally { spy.mockRestore(); }
      expect(sawIntent).toBe(true); expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("rejects old credentials when identity rotates during creation hashing", async () => {
    const p = await account(); await runInDurableObject(p, async (instance, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle); let rotated: Awaited<ReturnType<typeof inventory>>;
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { spy.mockRestore(); value(instance.recover(RECOVERY, "c".repeat(64), "d".repeat(64), "e".repeat(64))); rotated = await inventory(ctx); return original(algorithm, data); });
      expect(await reserveCampaignCreation(ctx.storage, H, K, intent(), D)).toMatchObject({ ok: false, code: "identity_unavailable" }); expect(await inventory(ctx)).toEqual(rotated!);
      expect(readCampaignCreation(ctx.storage, H, K, campaignKey, D)).toMatchObject({ ok: false }); expect(reserveCampaignGuestLink(ctx.storage, H, R, D)).toMatchObject({ ok: false });
    });
  });
  it("does not add a campaign link after identity deletion wins the validation await", async () => {
    const p = await account(); await runInDurableObject(p, async (instance, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle); let held: Awaited<ReturnType<typeof inventory>>;
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => { spy.mockRestore(); value(instance.beginDelete([1, 2, 3], D)); held = await inventory(ctx); return original(algorithm, data); });
      expect(await reserveCampaignCreation(ctx.storage, H, K, intent(), D)).toMatchObject({ ok: false, code: "identity_unavailable" }); expect(await inventory(ctx)).toEqual(held!);
    });
  });
  it("never recreates an old reservation with a missing or changed link", async () => {
    const p = await account(); value(await p.reserveCampaignRoom(K, intent(), D)); await p.removeRoom(R, 3);
    expect(await p.campaignCreation(K, campaignKey, D)).toMatchObject({ ok: false, code: "campaign_link_unavailable" }); expect(await p.reserveCampaignRoom(K, intent(), D)).toMatchObject({ ok: false, code: "campaign_link_unavailable" }); expect(await p.listRooms()).toEqual([]);
    const changed = { ...campaignKey, campaign_version: 2 }; expect(await p.campaignCreation(K, changed, D)).toMatchObject({ ok: false, code: "idempotency_campaign_mismatch" });
  });
  it("both ordinary creation paths protect old campaign and unknown intents while pruning ordinary history", async () => {
    for (const mode of ["legacy", "chapter"] as const) {
      const p = await account(); value(await p.reserveCampaignRoom(K, intent(), D)); await p.removeRoom(R, 3);
      await runInDurableObject(p, async (instance, ctx) => {
        ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)", "future-intent", JSON.stringify({ future_schema: 9, held: true }));
        for (let i = 0; i < 126; i++) ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)", "history-" + i, JSON.stringify({ room_id: String(i).padStart(22, "L"), invite_code: I, host: true }));
        const old = ctx.storage.sql.exec("SELECT * FROM creations WHERE request_key IN (?,?) ORDER BY rowid", K, "future-intent").toArray();
        const link = { room_id: "N".repeat(22), invite_code: I, host: true, ...(mode === "chapter" ? { api_version: 2 } : {}) };
        const out = mode === "legacy" ? instance.reserveRoom("new-ordinary", link) : instance.reserveChapterRoom("new-ordinary", link, { level_id: definition.chapters[0].level_id, level_version: definition.chapters[0].level_version, definition_hash: definition.chapters[0].definition_hash });
        expect(out.ok).toBe(true);
        expect(ctx.storage.sql.exec("SELECT * FROM creations WHERE request_key IN (?,?) ORDER BY rowid", K, "future-intent").toArray()).toEqual(old);
        expect(ctx.storage.sql.exec("SELECT data FROM creations WHERE request_key='new-ordinary'").toArray()).toHaveLength(1);
        expect(ctx.storage.sql.exec("SELECT data FROM rooms WHERE room_id=?", link.room_id).toArray()).toHaveLength(1);
        expect(ctx.storage.sql.exec("SELECT 1 FROM creations").toArray()).toHaveLength(128); expect(ctx.storage.sql.exec("SELECT 1 FROM creations WHERE request_key='history-0'").toArray()).toHaveLength(0);
      });
    }
  });
  it("holds a full protected set without losing the new ordinary or campaign room transaction", async () => {
    for (const mode of ["legacy", "chapter", "campaign"] as const) {
      const p = await account(); await runInDurableObject(p, async (instance, ctx) => {
        for (let i = 0; i < 128; i++) ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)", "protected-" + i, JSON.stringify({ future_schema: 9, held: i }));
        const before = await inventory(ctx), link = { room_id: "N".repeat(22), invite_code: I, host: true, ...(mode === "chapter" ? { api_version: 2 } : {}) };
        const out = mode === "legacy" ? instance.reserveRoom("new-ordinary", link) : mode === "chapter" ? instance.reserveChapterRoom("new-ordinary", link, { level_id: definition.chapters[0].level_id, level_version: definition.chapters[0].level_version, definition_hash: definition.chapters[0].definition_hash }) : await reserveCampaignCreation(ctx.storage, H, K, intent(), D);
        expect(out).toMatchObject({ ok: false, code: "creation_history_full" }); expect(await inventory(ctx)).toEqual(before);
      });
    }
  });
});
