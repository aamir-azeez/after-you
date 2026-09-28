import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { validateSnapshot, type PortableSnapshot } from "../src/snapshot";
import { reserveCampaignJoin } from "../src/v2/campaign-player";
import type { CampaignJoin } from "../src/v2/campaign-types";
import fixture from "./fixtures/campaign-control-v2.json";

const OWNER = fixture.active_view.host_id, PEER = fixture.active_view.guest_id!;
const DEVICE = "a".repeat(64), RECOVERY = "b".repeat(64), COMMIT = "f".repeat(40);
const FRIEND_REQUEST = "F".repeat(22), ROOM = "S".repeat(22);
const player = () => env.PLAYERS.get(env.PLAYERS.newUniqueId());
type PlayerStub = ReturnType<typeof player>;
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
const parse = (raw: string): PortableSnapshot => JSON.parse(raw) as PortableSnapshot;
const join = (): CampaignJoin => ({ schema_version: 2, idempotency_key: "story-join-merge-0001", invite_code: fixture.active_view.invite_code!, campaign_key: structuredClone(fixture.active_view.campaign_key), supported_simulation_versions: [6] });
async function source() { const stub = player(); value(await stub.create(OWNER, DEVICE, RECOVERY)); return stub; }
async function exported(stub: PlayerStub) { return value(await stub.exportSnapshot(COMMIT)); }
async function social(stub: PlayerStub) {
  value(await stub.friendPropose(OWNER, DEVICE, PEER, FRIEND_REQUEST));
  value(await stub.friendConfirm(OWNER, PEER, FRIEND_REQUEST));
}
async function admission(stub: PlayerStub) { return value(await stub.reserveCampaignJoin(join(), DEVICE)); }
async function encode(archive: PortableSnapshot) {
  archive.checksum.value = await digest(canonicalJson(archive.payload)); return canonicalJson(archive);
}
function identityRow(archive: PortableSnapshot) { return archive.payload.tables.find(table => table.name === "identity")!.rows[0]; }
function admissionRow(archive: PortableSnapshot) { return archive.payload.tables.find(table => table.name === "creations")!.rows[0]; }
async function inventory(stub: PlayerStub) {
  return runInDurableObject(stub, async (_, ctx) => {
    const alarm = await ctx.storage.getAlarm(), kv = [...ctx.storage.kv.list()];
    const schema = ctx.storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray();
    return { alarm, kv, tables: schema.filter(row => !isAlarmMetadataTable(row)).map(row => ({ ...row, rows: ctx.storage.sql.exec('SELECT * FROM "' + row.name + '" ORDER BY rowid').toArray() })) };
  });
}
async function rejectedWithoutWrites(raw: string, code: string) {
  const target = player(), before = await inventory(target);
  expect(await target.restoreSnapshot(raw, OWNER)).toMatchObject({ ok: false, code });
  expect(await inventory(target)).toEqual(before);
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("Player Story and social archive compatibility", () => {
  it("keeps historical social6 and tester data restorable byte-for-byte", async () => {
    const stub = await source(); expect(parse(await exported(stub)).payload.format_version).toBe(1);
    value(await stub.redeemTesterAccess(OWNER, DEVICE, true)); expect(parse(await exported(stub)).payload.format_version).toBe(4);
    await social(stub);
    await runInDurableObject(stub, (_, ctx) => {
      const row = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one();
      ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(JSON.parse(row.data), null, 2));
    });
    const raw = await exported(stub), archive = parse(raw), target = player();
    expect(archive.payload.format_version).toBe(6);
    expect(JSON.parse(String(identityRow(archive).data)).tester_grant).toMatchObject({ schema_version: 1 });
    value(await target.restoreSnapshot(raw, OWNER)); await evictDurableObject(target);
    expect(parse(await exported(target)).payload.tables).toEqual(archive.payload.tables);
    expect(await target.friendEdge(OWNER, PEER)).toMatchObject({ link: { accepted: true, request_id: FRIEND_REQUEST } });
  });

  it("keeps historical admission6 exact and refuses its ordinary restore", async () => {
    const stub = await source(); await admission(stub);
    const raw = await exported(stub), archive = parse(raw);
    expect(archive.payload.format_version).toBe(6);
    expect(JSON.parse(String(identityRow(archive).data))).not.toHaveProperty("social");
    expect((await validateSnapshot(raw, "Player", OWNER)).payload.tables).toEqual(archive.payload.tables);
    await rejectedWithoutWrites(raw, "campaign_restore_unsupported");
  });

  it("exports combined7 in either write order without changing social, tester or admission bytes", async () => {
    for (const socialFirst of [true, false]) {
      const stub = await source(); value(await stub.redeemTesterAccess(OWNER, DEVICE, true));
      if (socialFirst) { await social(stub); await admission(stub); }
      else { await admission(stub); await social(stub); }
      await runInDurableObject(stub, (_, ctx) => {
        for (const table of ["identity", "creations"]) {
          const rows = ctx.storage.sql.exec<{ rowid: string; data: string }>(`SELECT CAST(rowid AS TEXT) AS rowid,data FROM ${table}`).toArray();
          for (const row of rows) {
            const formatted = JSON.stringify(JSON.parse(row.data), null, 2);
            ctx.storage.sql.exec(`UPDATE ${table} SET data=? WHERE rowid=?`, formatted, row.rowid);
            expect(ctx.storage.sql.exec<{ data: string }>(`SELECT data FROM ${table} WHERE rowid=?`, row.rowid).one().data).toBe(formatted);
          }
        }
      });
      const before = await inventory(stub), raw = await exported(stub), archive = parse(raw);
      expect(archive.payload).toMatchObject({ format_version: 7, database_schema_version: 1 });
      expect(String(identityRow(archive).data)).toContain("\n"); expect(String(admissionRow(archive).data)).toContain("\n");
      expect(JSON.parse(String(identityRow(archive).data))).toMatchObject({ tester_grant: { schema_version: 1 }, social: { links: [{ accepted: true, request_id: FRIEND_REQUEST }] } });
      expect((await validateSnapshot(raw, "Player", OWNER)).payload.tables).toEqual(archive.payload.tables);
      expect(await inventory(stub)).toEqual(before);
      value(await stub.campaignJoinAttempt(join(), DEVICE));
      await rejectedWithoutWrites(raw, "campaign_restore_unsupported");
    }
  });

  it("rejects ambiguous6, incomplete7 and envelopes with neither extension before writes", async () => {
    for (const shape of ["neither", "social", "admission", "both"] as const) {
      const stub = await source();
      if (shape === "social" || shape === "both") await social(stub);
      if (shape === "admission" || shape === "both") await admission(stub);
      const archive = parse(await exported(stub));
      for (const version of shape === "neither" ? [6, 7] as const : shape === "both" ? [6] as const : [7] as const) {
        const altered = structuredClone(archive); altered.payload.format_version = version;
        const raw = await encode(altered);
        await expect(validateSnapshot(raw, "Player", OWNER)).rejects.toThrow("unsupported_snapshot_format");
        await rejectedWithoutWrites(raw, "unsupported_snapshot_format");
      }
    }
  });

  it("retains exact social, tester, owner, row-key and admission-hash validation in combined7", async () => {
    const stub = await source(); await social(stub); await admission(stub); value(await stub.redeemTesterAccess(OWNER, DEVICE, true));
    const archive = parse(await exported(stub));
    for (const corruption of ["social", "tester", "owner", "key", "hash"] as const) {
      const changed = structuredClone(archive), row = identityRow(changed), identity = JSON.parse(String(row.data));
      const intentRow = admissionRow(changed), intent = JSON.parse(String(intentRow.data));
      if (corruption === "social") identity.social.links.push(identity.social.links[0]);
      if (corruption === "tester") identity.tester_grant.extra = true;
      if (corruption === "owner") intent.player_id = PEER;
      if (corruption === "key") intentRow.request_key = "wrong-story-key-0001";
      if (corruption === "hash") intent.request_hash = "0".repeat(64);
      row.data = JSON.stringify(identity); intentRow.data = JSON.stringify(intent);
      const code = corruption === "social" ? "unsupported_friend_state" : corruption === "tester" ? "unsupported_tester_grant" : "invalid_campaign_admission";
      await rejectedWithoutWrites(await encode(changed), code);
    }
  });

  it("keeps campaign restore refusal content-based inside social6 and lower envelopes", async () => {
    for (const table of ["rooms", "creations"] as const) {
      const stub = await source(); await social(stub);
      const link = JSON.stringify({ room_id: ROOM, invite_code: "A".repeat(20), host: true, api_version: 3 }, null, 2);
      await runInDurableObject(stub, (_, ctx) => ctx.storage.sql.exec(`INSERT INTO ${table} VALUES(?,?)`, table === "rooms" ? ROOM : "retained-story-key-01", link).toArray());
      const archive = parse(await exported(stub)); expect(archive.payload.format_version).toBe(6);
      await rejectedWithoutWrites(await encode(archive), "campaign_restore_unsupported");
      const identity = JSON.parse(String(identityRow(archive).data)); delete identity.social;
      identityRow(archive).data = JSON.stringify(identity);
      for (const version of [2, 3, 4] as const) {
        archive.payload.format_version = version; const raw = await encode(archive);
        expect((await validateSnapshot(raw, "Player", OWNER)).payload.tables).toEqual(archive.payload.tables);
        await rejectedWithoutWrites(raw, "campaign_restore_unsupported");
      }
    }
  });

  it("refuses lower envelopes for admission or social instead of silently dropping either", async () => {
    for (const shape of ["social", "admission"] as const) {
      const stub = await source(); if (shape === "social") await social(stub); else await admission(stub);
      const archive = parse(await exported(stub));
      for (const version of [1, 2, 3, 4, 5] as const) {
        archive.payload.format_version = version;
        await rejectedWithoutWrites(await encode(archive), shape === "social" ? "unsupported_friend_state" : "unsupported_snapshot_format");
      }
    }
  });

  it("preserves a friends update that wins while Story admission awaits its hash", async () => {
    const stub = await source();
    await runInDurableObject(stub, async (instance, ctx) => {
      const original = crypto.subtle.digest.bind(crypto.subtle);
      const spy = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => {
        spy.mockRestore(); value(instance.friendPropose(OWNER, DEVICE, PEER, FRIEND_REQUEST)); return original(algorithm, data);
      });
      expect(await reserveCampaignJoin(ctx.storage, OWNER, join(), DEVICE)).toMatchObject({ ok: false, code: "campaign_player_changed" });
    });
    expect(await stub.listRooms()).toEqual([]);
    expect(await stub.friendEdge(OWNER, PEER)).toMatchObject({ link: { accepted: false, request_id: FRIEND_REQUEST } });
    const archive = parse(await exported(stub)); expect(archive.payload.format_version).toBe(6); expect(archive.payload.tables[2].rows).toEqual([]);
    await admission(stub); expect(parse(await exported(stub)).payload.format_version).toBe(7);
  });

  it("keeps campaign deletion preflight intact before clearing the shared social room", async () => {
    const stub = await source(); await social(stub); await admission(stub);
    value(await stub.addRoom({ room_id: ROOM, invite_code: "A".repeat(20), host: true }));
    value(await stub.friendShare(OWNER, DEVICE, { api_version: 1, room_id: ROOM }));
    const before = await inventory(stub);
    expect(await stub.beginDelete([1, 2], DEVICE)).toMatchObject({ ok: false, code: "unsupported_room_version" });
    expect(await inventory(stub)).toEqual(before);
    value(await stub.beginDelete([1, 2, 3], DEVICE));
    expect(await stub.friendEdge(OWNER, PEER)).toBeNull();
    const identity = JSON.parse(String(identityRow(parse(await exported(stub))).data));
    expect(identity).toMatchObject({ state: "deleting", social: { shared_room: null } });
    expect(await stub.friendShare(OWNER, DEVICE, null)).toMatchObject({ ok: false, code: "invalid_auth" });
    expect(await stub.campaignJoinAttempt(join(), DEVICE)).toMatchObject({ ok: false, code: "identity_unavailable" });
  });
});
