import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, randomToken, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { campaignAdmissionHash, type CampaignAdmissionIntent } from "../src/v2/campaign-admission-intent";
import { finalizeCampaignTerminalLink } from "../src/v2/campaign-player";
import { initializeCampaignStorageSchema } from "../src/v2/storage-schema";
import type { CampaignJoin, CampaignKey, CampaignView } from "../src/v2/campaign-types";
import fixture from "./fixtures/campaign-control-v2.json";

// Only the immutable test definition is substituted. Requests use the real
// worker and named Player/Room bindings; no HTTP definition/ack is trusted.
vi.mock("../src/v2/campaign-registry", async original => {
  const actual = await original<typeof import("../src/v2/campaign-registry")>();
  const f = (await import("./fixtures/campaign-control-v2.json")).default;
  const { canonicalJson } = await import("../src/protocol");
  const retainedCampaign = (k: CampaignKey) => canonicalJson(k) === canonicalJson(f.active_view.campaign_key) ? structuredClone(f.definition) : undefined;
  return { ...actual, retainedCampaign, advertisedCampaigns: () => [structuredClone(f.definition)],
    campaignCreatable: (k: CampaignKey, e: { CAMPAIGN_CREATION_ENABLED?: string }) => e.CAMPAIGN_CREATION_ENABLED === "true" && !!retainedCampaign(k) };
});

const R = fixture.active_view.campaign_room_id, I = fixture.active_view.invite_code!, key = fixture.active_view.campaign_key as CampaignKey;
const T = "a".repeat(43), OTHER = "Q".repeat(22), BODY = { schema_version: 1 };
const root = () => env.ROOMS_V2.getByName(R), player = (owner = G) => env.PLAYERS.getByName(owner);
const unwrap = <T>(out: Outcome<T>): T => { if (!out.ok) throw new Error(out.code); return out.value; };
const create = () => ({ schema_version: 1, idempotency_key: "terminal-create-key-0001", campaign_key: key });
const join = (id = "terminal-join-key-0001", invite = I): CampaignJoin => ({ schema_version: 2, idempotency_key: id, invite_code: invite,
  campaign_key: key, supported_simulation_versions: [6] });
const path = (id = R) => "/v2/campaigns/" + id + "/reconcile-deletion";
const released = (owner = G) => ({ schema_version: 1, operation: "campaign_terminal_cleanup", status: "released", player_id: owner, campaign_room_id: R });
let H = "", G = "", hash = "", address = 0;
const changed = new Map<object, Record<string, unknown>>();
const flags = { V2_ROOMS_ENABLED: "true", CAMPAIGN_CREATION_ENABLED: "true", CAMPAIGN_MUTATIONS_ENABLED: "true" };
async function call(route: string, method = "GET", body?: unknown, owner = G, overrides: Record<string, unknown> = {}, marked = true, token = T) {
  const configured: Env = { ...env }; Object.assign(configured, flags, overrides);
  return worker.fetch(new Request("https://terminal.test" + route, { method, headers: { "Content-Type": "application/json",
    "CF-Connecting-IP": "198.21.1." + ++address, "X-Player-Id": owner, Authorization: "Bearer " + token,
    ...(marked ? { "X-AfterYou-Campaign-Schema": "2" } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function inventory(ctx: DurableObjectState) {
  const alarm = await ctx.storage.getAlarm(), kv = [...ctx.storage.kv.list()];
  return { alarm, kv, tables: ctx.storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray().map(t => {
    if (t.name === "_cf_METADATA") { expect(isAlarmMetadataTable(t)).toBe(true); return { ...t, rows: null }; }
    return { ...t, rows: ctx.storage.sql.exec('SELECT * FROM "' + t.name + '" ORDER BY rowid').toArray() };
  }) };
}
const playerBytes = (owner = G) => runInDurableObject(player(owner), (_, ctx) => inventory(ctx));
const rootBytes = () => runInDurableObject(root(), (_, ctx) => inventory(ctx));
async function paired() {
  const made = await call("/v2/campaigns", "POST", create(), H); expect(made.status).toBe(201);
  const joined = await call("/v2/campaigns/join", "POST", join()); expect(joined.status).toBe(200);
}
async function erased(owner = H) {
  const result = await call("/v1/identity", "DELETE", undefined, owner, {}, false);
  expect(result.status).toBe(200); expect(await result.json()).toEqual({ deleted: true });
  expect(unwrap(await root().campaignTerminalFact(R))).toEqual({ schema_version: 1, status: "deleted", campaign_room_id: R, room_id: R });
}
async function changeIdentity(owner: string, field: "state" | "device_hash", value: string) {
  await runInDurableObject(player(owner), (_, ctx) => {
    const row = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data);
    row[field] = value; ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(row));
  });
}

beforeEach(async () => {
  await reset(); H = randomToken(16); G = randomToken(16); hash = await digest(T); address = 0;
  for (const owner of [H, G]) unwrap(await player(owner).create(owner, hash, "b".repeat(64)));
  await runInDurableObject(root(), instance => {
    const local = Reflect.get(instance, "env") as Record<string, unknown>;
    if (!changed.has(local)) changed.set(local, Object.fromEntries(Object.keys(flags).map(k => [k, local[k]])));
    Object.assign(local, flags);
  });
  const original = crypto.getRandomValues.bind(crypto);
  vi.spyOn(crypto, "getRandomValues").mockImplementation(((array: Uint8Array) => {
    if (array instanceof Uint8Array && array.length === 10) { array.set(I.match(/../g)!.map(x => parseInt(x, 16))); return array; }
    return original(array);
  }) as typeof crypto.getRandomValues);
});
afterEach(async () => { vi.restoreAllMocks(); for (const [target, prior] of changed) Object.assign(target, prior); changed.clear(); await reset(); });

describe("explicit requester-only terminal campaign reconciliation", () => {
  it("discovers the cold survivor's terminal link read-only and releases only it after partner identity deletion", async () => {
    await paired(); unwrap(await player().addRoom({ room_id: OTHER, invite_code: "", host: false, api_version: 2 }));
    await erased(); const beforeRoot = await rootBytes(), before = await playerBytes();
    const list = await call("/v2/campaigns"); expect(list.status).toBe(409);
    expect(await list.json()).toEqual({ error: { code: "campaign_terminal_reconciliation_required", campaign_room_id: R } });
    expect(await playerBytes()).toEqual(before); expect(await rootBytes()).toEqual(beforeRoot);
    const result = await call(path(), "POST", BODY); expect(result.status).toBe(200); expect(await result.json()).toEqual(released());
    expect(await player().listRooms()).toEqual([{ room_id: OTHER, invite_code: "", host: false, api_version: 2 }]);
    const after = await playerBytes(); expect(after.tables.find(t => t.name === "identity")).toEqual(before.tables.find(t => t.name === "identity"));
    const rows = after.tables.find(t => t.name === "creations")!.rows!;
    expect(rows).toHaveLength(1); expect(JSON.parse(String(rows[0].data))).toMatchObject({ state: "closed", request: join() });
    expect(await rootBytes()).toEqual(beforeRoot); expect(await (await call("/v2/campaigns")).json()).toEqual({ campaigns: [] });
  });
  it("replays the same receipt after a lost reply and eviction without reopening delayed Join", async () => {
    await paired(); await erased(); const first = await call(path(), "POST", BODY); expect(first.status).toBe(200);
    const expected = await first.json(), before = await playerBytes(), room = await rootBytes();
    await evictDurableObject(player()); await evictDurableObject(root());
    expect(await (await call(path(), "POST", BODY)).json()).toEqual(expected);
    expect(await playerBytes()).toEqual(before); expect(await rootBytes()).toEqual(room);
    expect(await player().reserveCampaignJoin(join(), hash)).toMatchObject({ ok: false, code: "campaign_admission_cancelled" });
    expect((await call("/v2/campaigns/join", "POST", join())).status).not.toBe(200);
  });
  it("retains host allocation bytes and keeps delayed Create held after host cleanup", async () => {
    await paired(); await erased(G); const before = await playerBytes(H);
    const result = await call(path(), "POST", BODY, H); expect(result.status).toBe(200); expect(await result.json()).toEqual(released(H));
    const after = await playerBytes(H); expect(after.tables.find(t => t.name === "creations")).toEqual(before.tables.find(t => t.name === "creations"));
    await evictDurableObject(player(H)); expect(await (await call(path(), "POST", BODY, H)).json()).toEqual(released(H));
    expect((await call("/v2/campaigns", "POST", create(), H)).status).toBe(409); expect(await player(H).listRooms()).toEqual([]);
  });
  it("closes every same-anchor open key but preserves another anchor and prior closed fences", async () => {
    await paired(); unwrap(await player().reserveCampaignJoin(join("terminal-second-key-0001"), hash));
    const other = join("terminal-other-key-0001", "EF".repeat(10)); unwrap(await player().reserveCampaignJoin(other, hash));
    const closed = join("terminal-closed-key-0001");
    await runInDurableObject(player(), async (_, ctx) => {
      const fact: CampaignAdmissionIntent = { creation_schema: 3, admission: "join", player_id: G, request: closed,
        request_hash: await campaignAdmissionHash(G, "join", closed), state: "closed", room_id: R };
      ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)", closed.idempotency_key, JSON.stringify(fact));
    });
    await erased(); const before = await playerBytes(); expect((await call(path(), "POST", BODY)).status).toBe(200);
    const rows = (await playerBytes()).tables.find(t => t.name === "creations")!.rows!;
    for (const id of [join().idempotency_key, "terminal-second-key-0001"]) expect(JSON.parse(String(rows.find(r => r.request_key === id)!.data)).state).toBe("closed");
    for (const id of [other.idempotency_key, closed.idempotency_key]) expect(rows.find(r => r.request_key === id)).toEqual(before.tables.find(t => t.name === "creations")!.rows!.find(r => r.request_key === id));
    expect(await player().listRooms()).toEqual([{ room_id: (await digest("v2:" + other.invite_code)).slice(0, 22), invite_code: "", host: false, api_version: 3 }]);
  });
  it("cleans at the full128 retained-key bound without adding a receipt row or pruning a fence", async () => {
    await paired();
    await runInDurableObject(player(), async (_, ctx) => {
      for (let i = 1; i < 128; i++) {
        const request = join("terminal-capacity-key-" + i.toString().padStart(4, "0"));
        const intent: CampaignAdmissionIntent = { creation_schema: 3, admission: "join", player_id: G, request,
          request_hash: await campaignAdmissionHash(G, "join", request), state: "open", room_id: R };
        ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)", request.idempotency_key, JSON.stringify(intent));
      }
    });
    await erased(); const before = (await playerBytes()).tables.find(t => t.name === "creations")!.rows!;
    expect((await call(path(), "POST", BODY)).status).toBe(200);
    const after = (await playerBytes()).tables.find(t => t.name === "creations")!.rows!;
    expect(after).toHaveLength(128); expect(after.map(row => row.request_key)).toEqual(before.map(row => row.request_key));
    for (let i = 0; i < before.length; i++) expect(JSON.parse(String(after[i].data))).toEqual({ ...JSON.parse(String(before[i].data)), state: "closed" });
    const settled = await playerBytes(); await evictDurableObject(player());
    expect(await (await call(path(), "POST", BODY)).json()).toEqual(released()); expect(await playerBytes()).toEqual(settled);
  });
  it("holds an active root and never starts deletion while trying terminal cleanup", async () => {
    await paired(); const room = await rootBytes(), person = await playerBytes();
    expect((await call(path(), "POST", BODY)).status).toBe(409);
    expect(await rootBytes()).toEqual(room); expect(await playerBytes()).toEqual(person);
    expect(unwrap(await root().campaignControl(G)).campaign.state).toBe("active");
  });
  it("preserves an uninitialized allocation instead of inferring deletion from absence", async () => {
    unwrap(await player(H).reserveCampaignRoom(create().idempotency_key, { creation_schema: 2,
      link: { room_id: R, invite_code: I, host: true, api_version: 3 }, campaign_key: key }, hash));
    const room = await rootBytes(), person = await playerBytes(H);
    expect((await call(path(), "POST", BODY, H)).status).toBe(409);
    expect(await rootBytes()).toEqual(room); expect(await playerBytes(H)).toEqual(person);
  });
  it("holds incomplete deletion with unchanged proof/control and Player state", async () => {
    await paired(); await runInDurableObject(root(), (_, ctx) => {
      const a = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor").one().data);
      const m = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member").one().data);
      a.control.state = "deleting"; a.control.revision++; a.deletion = { room_ids: [R], completed_room_ids: [] }; m.status = "deleting";
      ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?", JSON.stringify(a)); ctx.storage.sql.exec("UPDATE campaign_member SET data=?", JSON.stringify(m));
    });
    const room = await rootBytes(), person = await playerBytes();
    expect((await call(path(), "POST", BODY)).status).toBe(409);
    expect(await rootBytes()).toEqual(room); expect(await playerBytes()).toEqual(person);
  });
  it("rejects child tombstones, unknown tables/KV, future schema, malformed rows and stray alarms without writes", async () => {
    await paired(); await erased();
    for (const mode of ["child", "table", "kv", "future", "json", "alarm"]) {
      const id = randomToken(16), r = env.ROOMS_V2.getByName(id);
      await runInDurableObject(r, async (instance, ctx) => {
        initializeCampaignStorageSchema(ctx.storage);
        ctx.storage.sql.exec("INSERT INTO room VALUES(1,?)", JSON.stringify({ deleted: true }));
        ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify({ schema_version: 1, status: "deleted", campaign_room_id: mode === "child" ? R : id, room_id: id }));
        if (mode !== "child") ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify({ schema_version: 1, state: "deleted", campaign_room_id: id }));
        if (mode === "table") ctx.storage.sql.exec("CREATE TABLE future_data (data TEXT)");
        if (mode === "kv") ctx.storage.kv.put("foreign", "retained");
        if (mode === "future") ctx.storage.sql.exec("UPDATE metadata SET schema_version=999");
        if (mode === "json") ctx.storage.sql.exec("UPDATE campaign_member SET data='not-json'");
        if (mode === "alarm") await ctx.storage.setAlarm(Date.now() + 3600000);
        const before = await inventory(ctx); expect(await instance.campaignTerminalFact(id)).toMatchObject({ ok: false }); expect(await inventory(ctx)).toEqual(before);
      });
    }
  });
  it("requires retained provenance before touching a legacy keyless guest link", async () => {
    await paired(); await erased(); await runInDurableObject(player(), (_, ctx) => ctx.storage.sql.exec("DELETE FROM creations"));
    const before = await playerBytes(), room = await rootBytes();
    const response = await call(path(), "POST", BODY); expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: { code: "campaign_terminal_provenance_required", retryable: false } });
    expect(await playerBytes()).toEqual(before); expect(await rootBytes()).toEqual(room);
    expect(await player().reserveCampaignGuest(R, hash)).toMatchObject({ ok: false, code: "campaign_join_attempt_required" });
  });
  it("holds a stranger with neither link nor history, while a missing host link remains exactly retryable", async () => {
    await paired(); await erased(G); await player(H).removeRoom(R, 3);
    expect(await (await call(path(), "POST", BODY, H)).json()).toEqual(released(H));
    const stranger = randomToken(16); unwrap(await player(stranger).create(stranger, hash, "b".repeat(64)));
    const before = await playerBytes(stranger); expect((await call(path(), "POST", BODY, stranger)).status).toBe(409);
    expect(await playerBytes(stranger)).toEqual(before);
  });
  it("rechecks original device and active identity after the actual awaited root terminal call", async () => {
    await paired(); await erased();
    for (const mode of ["device", "deleting"]) {
      await changeIdentity(G, "state", "active"); await changeIdentity(G, "device_hash", hash);
      let after: Awaited<ReturnType<typeof playerBytes>> | undefined;
      await runInDurableObject(root(), instance => {
        const original = instance.campaignTerminalFact;
        const spy = vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignTerminalFact").mockImplementation(async function(this: typeof instance, id: string) {
          if (this !== instance) return original.call(this, id);
          const out = await original.call(instance, id); spy.mockRestore();
          await changeIdentity(G, mode === "device" ? "device_hash" : "state", mode === "device" ? "c".repeat(64) : "deleting");
          after = await playerBytes(); return out;
        });
      });
      expect((await call(path(), "POST", BODY)).status).toBe(401); expect(await playerBytes()).toEqual(after);
    }
  });
  it("holds a changed link/history scope rather than silently recapturing it after root await", async () => {
    await paired(); await erased(); let after: Awaited<ReturnType<typeof playerBytes>> | undefined;
    await runInDurableObject(root(), instance => {
      const original = instance.campaignTerminalFact;
      const spy = vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignTerminalFact").mockImplementation(async function(this: typeof instance, id: string) {
        if (this !== instance) return original.call(this, id);
        const out = await original.call(instance, id); spy.mockRestore();
        unwrap(await player().addRoom({ room_id: OTHER, invite_code: "", host: false, api_version: 2 })); after = await playerBytes(); return out;
      });
    });
    expect((await call(path(), "POST", BODY)).status).toBe(409); expect(await playerBytes()).toEqual(after);
    expect((await call(path(), "POST", BODY)).status).toBe(200);
  });
  it("rolls all closed-key updates back when the final exact link removal fails", async () => {
    await paired(); unwrap(await player().reserveCampaignJoin(join("terminal-second-key-0001"), hash)); await erased();
    const scope = unwrap(await player().campaignTerminalScope(R, hash)), fact = unwrap(await root().campaignTerminalFact(R));
    await runInDurableObject(player(), async (_, ctx) => {
      const before = await inventory(ctx), original = ctx.storage.sql.exec.bind(ctx.storage.sql);
      const spy = vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((sql: string, ...args: unknown[]) => {
        if (sql === "DELETE FROM rooms WHERE room_id=? AND data=?") throw new Error("terminal_remove_failed"); return original(sql, ...args);
      }) as typeof ctx.storage.sql.exec);
      try { expect(await finalizeCampaignTerminalLink(ctx.storage, G, scope, fact, hash)).toMatchObject({ ok: false }); }
      finally { spy.mockRestore(); }
      expect(await inventory(ctx)).toEqual(before);
    });
    expect((await call(path(), "POST", BODY)).status).toBe(200);
  });
  it("never treats caller body, boolean or a wrong-root acknowledgement as terminal evidence", async () => {
    await paired(); await erased(); const scope = unwrap(await player().campaignTerminalScope(R, hash)), before = await playerBytes();
    for (const bad of [{ deleted: true }, { schema_version: 1, status: "deleted", campaign_room_id: OTHER, room_id: OTHER }]) {
      expect(await player().finalizeCampaignTerminalLink(scope, bad, hash)).toMatchObject({ ok: false });
    }
    for (const body of [{ ...BODY, acknowledged: true }, { schema_version: 2 }, []]) expect((await call(path(), "POST", body)).status).toBe(422);
    expect(await playerBytes()).toEqual(before);
  });
  it("allows blocked terminal cleanup during campaign pauses but holds unmarked and globally paused requests", async () => {
    await paired(); unwrap(await env.SAFETY_PROFILES.getByName(H).setBlock(H, hash, G, true));
    expect((await call("/v2/campaigns/" + R)).status).toBe(403); await erased(); const before = await playerBytes();
    expect((await call(path(), "POST", BODY, G, {}, false)).status).toBe(409);
    expect((await call(path(), "POST", BODY, G, { V2_ROOMS_ENABLED: "false" })).status).toBe(503);
    expect(await playerBytes()).toEqual(before);
    expect((await call(path(), "POST", BODY, G, { CAMPAIGN_CREATION_ENABLED: "false", CAMPAIGN_MUTATIONS_ENABLED: "false" })).status).toBe(200);
  });
  it.each(["link", "device"])("rechecks %s changes before returning terminal list discovery", async mode => {
    await paired(); await erased();
    await runInDurableObject(root(), instance => {
      const original = instance.campaignTerminalFact;
      const spy = vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignTerminalFact").mockImplementation(async function(this: typeof instance, id: string) {
        if (this !== instance) return original.call(this, id);
        const out = await original.call(instance, id); spy.mockRestore();
        if (mode === "link") await player().removeRoom(R, 3);
        else await changeIdentity(G, "device_hash", "c".repeat(64));
        return out;
      });
    });
    const listed = await call("/v2/campaigns"); expect(listed.status).toBe(mode === "link" ? 409 : 401);
    expect(await listed.json()).toEqual({ error: { code: mode === "link" ? "campaign_link_unavailable" : "identity_unavailable", retryable: false } });
  });
  it("persists keyed Join2 provenance before the sole fresh HTTP membership call", async () => {
    expect((await call("/v2/campaigns", "POST", create(), H)).status).toBe(201); let observed = false;
    await runInDurableObject(root(), instance => {
      const original = instance.campaignHttpJoin;
      const spy = vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignHttpJoin").mockImplementation(async function(this: typeof instance, ...args: Parameters<typeof instance.campaignHttpJoin>) {
        if (this !== instance) return original.apply(this, args);
        spy.mockRestore();
        const admitted = unwrap(await player().campaignJoinAttempt(join(), hash)); expect(admitted?.room_id).toBe(R);
        const scope = unwrap(await player().campaignTerminalScope(R, hash)); expect(scope.open_join_keys).toEqual([join().idempotency_key]);
        observed = true; return original.apply(instance, args);
      });
    });
    const joined = await call("/v2/campaigns/join", "POST", join()); expect(joined.status).toBe(200); expect(observed).toBe(true);
    expect((await joined.json<{ campaign: CampaignView }>()).campaign.guest_id).toBe(G);
  });
});
