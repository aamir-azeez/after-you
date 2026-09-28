import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, randomToken, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { campaignAdmissionHash } from "../src/v2/campaign-admission-intent";
import { campaignTerminalAdmissionScope, finalizeCampaignTerminalAdmission } from "../src/v2/campaign-player";
import type { CampaignCreate, CampaignKey } from "../src/v2/campaign-types";
import fixture from "./fixtures/campaign-control-v2.json";

// Substitute only the finite immutable definition. Actual HTTP, named Player
// and Room bindings, allocation, deletion and local transactions stay real.
vi.mock("../src/v2/campaign-registry", async original => {
  const actual = await original<typeof import("../src/v2/campaign-registry")>();
  const f = (await import("./fixtures/campaign-control-v2.json")).default;
  const { canonicalJson } = await import("../src/protocol");
  const retainedCampaign = (k: CampaignKey) => canonicalJson(k) === canonicalJson(f.active_view.campaign_key) ? structuredClone(f.definition) : undefined;
  return { ...actual, retainedCampaign, advertisedCampaigns: () => [structuredClone(f.definition)],
    campaignCreatable: (k: CampaignKey, e: { CAMPAIGN_CREATION_ENABLED?: string }) => e.CAMPAIGN_CREATION_ENABLED === "true" && !!retainedCampaign(k) };
});

const R = fixture.active_view.campaign_room_id, I = fixture.active_view.invite_code!, key = fixture.active_view.campaign_key as CampaignKey;
const T = "a".repeat(43), OTHER = "Q".repeat(22), CANCEL = "/v2/campaigns/cancel";
const flags = { V2_ROOMS_ENABLED: "true", CAMPAIGN_CREATION_ENABLED: "true", CAMPAIGN_MUTATIONS_ENABLED: "true" };
const changed = new Map<object, Record<string, unknown>>();
const unwrap = <T>(out: Outcome<T>): T => { if (!out.ok) throw new Error(out.code); return out.value; };
let H = "", G = "", hash = "", address = 0;
const root = () => env.ROOMS_V2.getByName(R), player = (owner = H) => env.PLAYERS.getByName(owner);
const create = (id = "terminal-create-key-0001"): CampaignCreate => ({ schema_version: 1, idempotency_key: id, campaign_key: key });
async function call(path: string, method = "GET", body?: unknown, owner = H, overrides: Record<string, unknown> = {}, marked = true) {
  const configured: Env = { ...env }; Object.assign(configured, flags, overrides);
  return worker.fetch(new Request("https://terminal-admission.test" + path, { method, headers: {
    "Content-Type":"application/json", "CF-Connecting-IP":"198.22.1." + ++address, "X-Player-Id":owner, Authorization:"Bearer " + T,
    ...(marked ? { "X-AfterYou-Campaign-Schema":"2" } : {}) }, body:body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function inventory(ctx: DurableObjectState) {
  const alarm = await ctx.storage.getAlarm(), kv = [...ctx.storage.kv.list()];
  return { alarm, kv, tables:ctx.storage.sql.exec<{ name:string; sql:string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray().map(t => {
    if (t.name === "_cf_METADATA") { expect(isAlarmMetadataTable(t)).toBe(true); return { ...t, rows:null }; }
    return { ...t, rows:ctx.storage.sql.exec('SELECT * FROM "' + t.name + '" ORDER BY rowid').toArray() };
  }) };
}
const person = () => runInDurableObject(player(), (_, ctx) => inventory(ctx));
const room = () => runInDurableObject(root(), (_, ctx) => inventory(ctx));
async function paired() {
  // The client does not consume the accepted body: its exact saved Create stays unresolved.
  expect((await call("/v2/campaigns","POST",create())).status).toBe(201);
  expect((await call("/v2/campaigns/join","POST",{ schema_version:2, idempotency_key:"terminal-join-key-0001",
    invite_code:I, campaign_key:key, supported_simulation_versions:[6] },G)).status).toBe(200);
}
async function erased() {
  const result = await call("/v1/identity","DELETE",undefined,G,{},false);
  expect(result.status).toBe(200); expect(await result.json()).toEqual({ deleted:true });
  expect(unwrap(await root().campaignTerminalFact(R))).toEqual({ schema_version:1, status:"deleted", campaign_room_id:R, room_id:R });
}
async function expected() {
  return { schema_version:1, operation:"campaign_terminal_admission", admission:"create", status:"terminal", player_id:H,
    idempotency_key:create().idempotency_key, request_hash:await campaignAdmissionHash(H,"create",create()), campaign_room_id:R };
}
async function mutateIdentity(field: "state" | "device_hash", value: string) {
  await runInDurableObject(player(), (_, ctx) => {
    const row = JSON.parse(ctx.storage.sql.exec<{ data:string }>("SELECT data FROM identity WHERE id=1").one().data);
    row[field] = value; ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1",JSON.stringify(row));
  });
}
beforeEach(async () => {
  await reset(); H = randomToken(16); G = randomToken(16); hash = await digest(T); address = 0;
  for (const owner of [H,G]) unwrap(await player(owner).create(owner,hash,"b".repeat(64)));
  await runInDurableObject(root(), instance => {
    const local = Reflect.get(instance,"env") as Record<string,unknown>;
    if (!changed.has(local)) changed.set(local,Object.fromEntries(Object.keys(flags).map(k => [k,local[k]])));
    Object.assign(local,flags);
  });
  const original = crypto.getRandomValues.bind(crypto);
  vi.spyOn(crypto,"getRandomValues").mockImplementation(((array: Uint8Array) => {
    if (array instanceof Uint8Array && array.length === 10) { array.set(I.match(/../g)!.map(x => parseInt(x,16))); return array; }
    return original(array);
  }) as typeof crypto.getRandomValues);
});
afterEach(async () => { vi.restoreAllMocks(); for (const [target,prior] of changed) Object.assign(target,prior); changed.clear(); await reset(); });

describe("exact lost-Create terminal correlation", () => {
  it("correlates actual deleted allocation without cleanup, then repeats after explicit cleanup and eviction", async () => {
    await paired(); await erased(); const before = await person(), beforeRoot = await room();
    const result = await call(CANCEL,"POST",create()); expect(result.status).toBe(200); expect(await result.json()).toEqual(await expected());
    expect(await person()).toEqual(before); expect(await room()).toEqual(beforeRoot);
    expect(await player().listRooms()).toEqual([{ room_id:R, api_version:3, host:true, invite_code:I }]);
    const cleanup = await call("/v2/campaigns/" + R + "/reconcile-deletion","POST",{ schema_version:1 });
    expect(await cleanup.json()).toEqual({ schema_version:1, operation:"campaign_terminal_cleanup", status:"released", player_id:H, campaign_room_id:R });
    const cleaned = await person(); expect(await player().listRooms()).toEqual([]);
    await evictDurableObject(player()); await evictDurableObject(root());
    expect(await (await call(CANCEL,"POST",create())).json()).toEqual(await expected());
    expect(await (await call(CANCEL,"POST",create())).json()).toEqual(await expected());
    expect(await person()).toEqual(cleaned); expect(await room()).toEqual(beforeRoot);
    expect((await call("/v2/campaigns","POST",create())).status).toBe(409);
  });
  it("distinguishes two original keys with the same campaign key and never guesses the other allocation", async () => {
    await paired(); const otherInvite = "EF".repeat(10), otherRoot = (await digest("v2:" + otherInvite)).slice(0,22), otherBody = create("terminal-other-key-0001");
    unwrap(await player().reserveCampaignRoom(otherBody.idempotency_key,{ creation_schema:2,
      link:{ room_id:otherRoot, api_version:3, host:true, invite_code:otherInvite }, campaign_key:key },hash));
    await erased(); const before = await person();
    expect(await (await call(CANCEL,"POST",create())).json()).toEqual(await expected());
    expect((await call(CANCEL,"POST",otherBody)).status).toBe(409); expect(await person()).toEqual(before);
    expect((await call(CANCEL,"POST",{ ...create(),campaign_key:{ ...key,definition_hash:"f".repeat(64) } })).status).toBe(409);
    expect(await person()).toEqual(before);
  });
  it("keeps the old live accepted and unreserved cancelled replies unchanged", async () => {
    await paired(); const live = await (await call(CANCEL,"POST",create())).json<Record<string,unknown>>();
    expect(live).toMatchObject({ operation:"campaign_admission_cancel", admission:"create", status:"accepted" });
    expect(live.campaign).toMatchObject({ campaign_room_id:R });
    const fresh = create("never-allocated-key-0001"), before = await person();
    expect(unwrap(await player().campaignTerminalAdmissionScope(fresh,hash))).toBeNull(); expect(await person()).toEqual(before);
    const cancelled = await (await call(CANCEL,"POST",fresh)).json();
    expect(cancelled).toEqual({ schema_version:1, operation:"campaign_admission_cancel", admission:"create", player_id:H,
      idempotency_key:fresh.idempotency_key,request_hash:await campaignAdmissionHash(H,"create",fresh),status:"cancelled",campaign:null });
    expect(await (await call(CANCEL,"POST",fresh)).json()).toEqual(cancelled);
  });
  it.each(["empty","incomplete","future","malformed","wrong-root"])("holds %s root instead of treating failed observation as terminal", async mode => {
    if (mode === "empty") unwrap(await player().reserveCampaignRoom(create().idempotency_key,{ creation_schema:2,
      link:{ room_id:R,api_version:3,host:true,invite_code:I },campaign_key:key },hash));
    else {
      await paired();
      if (mode === "incomplete") await runInDurableObject(root(),(_,ctx) => {
        const a = JSON.parse(ctx.storage.sql.exec<{ data:string }>("SELECT data FROM campaign_anchor").one().data);
        const m = JSON.parse(ctx.storage.sql.exec<{ data:string }>("SELECT data FROM campaign_member").one().data);
        a.control.state = "deleting"; a.control.revision++; a.deletion = { room_ids:[R],completed_room_ids:[] }; m.status = "deleting";
        ctx.storage.sql.exec("UPDATE campaign_anchor SET data=?",JSON.stringify(a)); ctx.storage.sql.exec("UPDATE campaign_member SET data=?",JSON.stringify(m));
      });
      else {
        await erased(); await runInDurableObject(root(),(_,ctx) => {
          if (mode === "future") ctx.storage.sql.exec("UPDATE metadata SET schema_version=999");
          if (mode === "malformed") ctx.storage.sql.exec("UPDATE campaign_member SET data='not-json'");
          if (mode === "wrong-root") {
            const m = JSON.parse(ctx.storage.sql.exec<{ data:string }>("SELECT data FROM campaign_member").one().data);
            m.campaign_room_id = OTHER; ctx.storage.sql.exec("UPDATE campaign_member SET data=?",JSON.stringify(m));
          }
        });
      }
    }
    const before = await person(), beforeRoot = await room();
    const result = await call(CANCEL,"POST",create());
    if (mode === "incomplete") {
      // Existing admitted recovery may expose a validated deleting view. It
      // still must not claim permanent terminal correlation before deletion.
      expect(result.status).toBe(200);
      expect(await result.json()).toMatchObject({ operation:"campaign_admission_cancel", status:"accepted", campaign:{ state:"deleting",campaign_room_id:R } });
    } else expect(result.status).not.toBe(200);
    expect(await person()).toEqual(before); expect(await room()).toEqual(beforeRoot);
  });
  it.each(["device","deleting","allocation","link","history"])("rechecks %s after actual awaited root observation", async mode => {
    await paired(); await erased(); let after: Awaited<ReturnType<typeof person>> | undefined;
    await runInDurableObject(root(),instance => {
      const original = instance.campaignTerminalFact;
      const spy = vi.spyOn(Object.getPrototypeOf(instance) as typeof instance,"campaignTerminalFact").mockImplementation(async function(this: typeof instance,id: string) {
        if (this !== instance) return original.call(this,id);
        const result = await original.call(instance,id); spy.mockRestore();
        if (mode === "device" || mode === "deleting") await mutateIdentity(mode === "device" ? "device_hash" : "state",mode === "device" ? "c".repeat(64) : "deleting");
        else if (mode === "link") await player().removeRoom(R,3);
        else if (mode === "history") unwrap(await player().addRoom({ room_id:OTHER,api_version:2,host:false,invite_code:"" }));
        else await runInDurableObject(player(),async (_,ctx) => {
          const otherInvite = "EF".repeat(10), otherRoot = (await digest("v2:" + otherInvite)).slice(0,22);
          ctx.storage.sql.exec("UPDATE creations SET data=? WHERE request_key=?",JSON.stringify({ creation_schema:2,
            link:{ room_id:otherRoot,api_version:3,host:true,invite_code:otherInvite },campaign_key:key }),create().idempotency_key);
        });
        after = await person(); return result;
      });
    });
    expect((await call(CANCEL,"POST",create())).status).toBe(["device","deleting"].includes(mode) ? 401 : 409);
    expect(await person()).toEqual(after);
  });
  it("holds future allocation/Player schema and rejects changed owner, request, scope or tombstone without writes", async () => {
    await paired(); await erased(); const scope = unwrap(await player().campaignTerminalAdmissionScope(create(),hash))!, fact = unwrap(await root().campaignTerminalFact(R));
    const before = await person();
    for (const bad of [{ ...scope,owner_player_id:G },{ ...scope,request_hash:"f".repeat(64) },{ ...scope,extra:true },
      { ...scope,request:{ ...scope.request,idempotency_key:"wrong-original-key-0001" } }]) expect(await player().finalizeCampaignTerminalAdmission(bad,fact,hash)).toMatchObject({ ok:false });
    for (const bad of [{ deleted:true },{ ...fact,campaign_room_id:OTHER,room_id:OTHER },{ ...fact,schema_version:2 }]) expect(await player().finalizeCampaignTerminalAdmission(scope,bad,hash)).toMatchObject({ ok:false });
    expect(await player(G).campaignTerminalAdmissionScope(create(),hash)).toMatchObject({ ok:false });
    expect((await call(CANCEL,"POST",{ ...create(),path:"/v2/campaigns/cancel" })).status).toBe(422); expect(await person()).toEqual(before);
    await runInDurableObject(player(),async (_,ctx) => {
      ctx.storage.sql.exec("UPDATE creations SET data=? WHERE request_key=?",JSON.stringify({ creation_schema:999 }),create().idempotency_key);
      const unknown = await inventory(ctx); expect(await campaignTerminalAdmissionScope(ctx.storage,H,create(),hash)).toMatchObject({ ok:false }); expect(await inventory(ctx)).toEqual(unknown);
    });
    await runInDurableObject(player(),async (_,ctx) => {
      // Player's6 is its archive format, not a Room metadata table. A future
      // runtime layout must hold through the existing strict SQL classifier.
      ctx.storage.sql.exec("CREATE TABLE future_generation (schema_version INTEGER NOT NULL)");
      ctx.storage.sql.exec("INSERT INTO future_generation VALUES(999)"); const unknown = await inventory(ctx);
      expect(await finalizeCampaignTerminalAdmission(ctx.storage,H,scope,fact,hash)).toMatchObject({ ok:false }); expect(await inventory(ctx)).toEqual(unknown);
    });
  });
  it("rechecks authority after the final transaction's alarm await and never partially writes", async () => {
    await paired(); await erased(); const scope = unwrap(await player().campaignTerminalAdmissionScope(create(),hash))!, fact = unwrap(await root().campaignTerminalFact(R));
    await runInDurableObject(player(),async (_,ctx) => {
      const before = await inventory(ctx), original = ctx.storage.getAlarm.bind(ctx.storage);
      const spy = vi.spyOn(ctx.storage,"getAlarm").mockImplementationOnce(async () => {
        spy.mockRestore(); const alarm = await original();
        const row = JSON.parse(ctx.storage.sql.exec<{ data:string }>("SELECT data FROM identity WHERE id=1").one().data);
        row.device_hash = "c".repeat(64); ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1",JSON.stringify(row)); return alarm;
      });
      expect(await finalizeCampaignTerminalAdmission(ctx.storage,H,scope,fact,hash)).toMatchObject({ ok:false,code:"identity_unavailable" });
      expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("preserves narrow Cancel header/global-mutation policy and its blocked-room exception", async () => {
    await paired(); unwrap(await env.SAFETY_PROFILES.getByName(H).setBlock(H,hash,G,true)); await erased();
    const before = await person();
    expect((await call(CANCEL,"POST",create(),H,{},false)).status).toBe(409);
    expect((await call(CANCEL,"POST",create(),H,{ V2_ROOMS_ENABLED:"false" })).status).toBe(503);
    expect(await person()).toEqual(before);
    expect(await (await call(CANCEL,"POST",create(),H,{ CAMPAIGN_CREATION_ENABLED:"false",CAMPAIGN_MUTATIONS_ENABLED:"false" })).json()).toEqual(await expected());
    expect(await person()).toEqual(before);
  });
});
