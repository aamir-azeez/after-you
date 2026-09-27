import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { encode } from "jpeg-js";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { exportSnapshot, validateSnapshot, restoreSnapshot } from "../src/snapshot";
import { campaignJoin } from "../src/v2/campaign-protocol";
import { campaignAdmissionHash, type CampaignAdmissionIntent } from "../src/v2/campaign-admission-intent";
import { cancelCampaignCreation, finalizeCampaignJoinCancellation, reserveCampaignCreation, reserveCampaignJoin } from "../src/v2/campaign-player";
import { initializeCampaignRoot, joinCampaignRoot, cancelCampaignJoinRoot } from "../src/v2/campaign-root";
import { exportRoomV2, validateRoomV2, restoreRoomV2 } from "../src/v2/snapshot";
import { initializeCampaignStorageSchema, initializeCampaignJoinSchema } from "../src/v2/storage-schema";
import { getReactionOperation, mutateReaction, parseReaction } from "../src/v2/reactions";
import type { CampaignDefinition, CampaignJoin, CampaignKey } from "../src/v2/campaign-types";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";

const H=fixture.active_view.host_id,G=fixture.active_view.guest_id!,R=fixture.active_view.campaign_room_id,I=fixture.active_view.invite_code!;
const D="a".repeat(64),RECOVERY="b".repeat(64),A="join-attempt-key-0001",B="join-attempt-key-0002",K="create-attempt-key-0001";
const definition=fixture.definition as CampaignDefinition,key=fixture.active_view.campaign_key as CampaignKey;
const resolver=(candidate:CampaignKey)=>canonicalJson(candidate)===canonicalJson(key)?definition:undefined;
const join=(id=A):CampaignJoin=>({schema_version:2,idempotency_key:id,invite_code:I,campaign_key:structuredClone(key),supported_simulation_versions:[6]});
const create=()=>({schema_version:1 as const,idempotency_key:K,campaign_key:structuredClone(key)});
const intent=()=>({creation_schema:2 as const,link:{room_id:R,invite_code:I,host:true,api_version:3},campaign_key:structuredClone(key)});
function value<T>(out:Outcome<T>):T { if(!out.ok)throw new Error(out.code);return out.value; }
async function root(){const stub=env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());value(await runInDurableObject(stub,(_,ctx)=>initializeCampaignRoot(ctx.storage,{schema_version:1,host_id:H,intent:intent()},resolver)));return stub;}
async function player(owner=G){const stub=env.PLAYERS.get(env.PLAYERS.newUniqueId());value(await stub.create(owner,D,RECOVERY));return stub;}
async function inventory(ctx:DurableObjectState){
  const alarm=await ctx.storage.getAlarm(),kv=[...ctx.storage.kv.list()];
  const tables=ctx.storage.sql.exec<{name:string;sql:string}>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray();
  return {alarm,kv,tables:tables.map(t=>{if(t.name==="_cf_METADATA"){expect(isAlarmMetadataTable(t)).toBe(true);return {...t,rows:null};}return {...t,rows:ctx.storage.sql.exec('SELECT * FROM "'+t.name+'" ORDER BY rowid').toArray()};})};
}
const cancelRoot=(stub:ReturnType<typeof env.ROOMS_V2.get>,body=join(),owner=G)=>runInDurableObject(stub,(_,ctx)=>cancelCampaignJoinRoot(ctx.storage,owner,body,resolver));
const joinRoot=(stub:ReturnType<typeof env.ROOMS_V2.get>,body=join(),owner=G)=>runInDurableObject(stub,(_,ctx)=>joinCampaignRoot(ctx.storage,owner,body,resolver));
afterEach(async()=>{vi.restoreAllMocks();await reset();});

describe("disabled exact admission cancellation fences",()=>{
  it("matches native admission hash identity and holds unchanged keyless Join1",async()=>{
    expect(await campaignAdmissionHash(G,"join",join())).toBe(await digest(canonicalJson({owner_player_id:G,path:"/v2/campaigns/join",body:join()})));
    const legacy={schema_version:1,invite_code:I,campaign_key:key,supported_simulation_versions:[6]},bytes=JSON.stringify(legacy),r=await root();
    expect(()=>campaignJoin(legacy,resolver)).toThrow();
    await runInDurableObject(r,async(_,ctx)=>{const before=await inventory(ctx);expect(await joinCampaignRoot(ctx.storage,G,legacy,resolver)).toMatchObject({ok:false});expect(await cancelCampaignJoinRoot(ctx.storage,G,legacy,resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(before);});
    expect(JSON.stringify(legacy)).toBe(bytes);
    const p=await player();expect(await p.reserveCampaignGuest(R,D)).toMatchObject({ok:false,code:"campaign_join_attempt_required"});
  });
  it("closes a fresh Create key durably and never turns it into another allocation",async()=>{
    const p=await player(H),first=value(await p.cancelCampaignCreation(create(),D));expect(first.status).toBe("cancelled");
    await evictDurableObject(p);expect(value(await p.cancelCampaignCreation(create(),D))).toEqual(first);
    expect(await p.reserveCampaignRoom(K,intent(),D)).toMatchObject({ok:false,code:"campaign_admission_cancelled"});
    expect(await p.campaignCreation(K,key,D)).toMatchObject({ok:false,code:"campaign_admission_cancelled"});expect(await p.listRooms()).toEqual([]);
    await runInDurableObject(p,async(_,ctx)=>{const before=await inventory(ctx);expect(await cancelCampaignCreation(ctx.storage,H,{...create(),campaign_key:{...key,campaign_version:2}},D)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(before);});
  });
  it("returns an admitted Create without changing it and holds a missing canonical link",async()=>{
    const p=await player(H);value(await p.reserveCampaignRoom(K,intent(),D));
    await runInDurableObject(p,async(_,ctx)=>{const before=await inventory(ctx);expect(value(await cancelCampaignCreation(ctx.storage,H,create(),D))).toEqual({status:"admitted",intent:intent()});expect(await inventory(ctx)).toEqual(before);});
    await p.removeRoom(R,3);expect(await p.cancelCampaignCreation(create(),D)).toMatchObject({ok:false,code:"campaign_link_unavailable"});expect(await p.listRooms()).toEqual([]);
  });
  it("rechecks both orders of Create cancellation versus a hash-await reservation",async()=>{
    for(const cancellationFirst of [true,false]){
      const p=await player(H);await runInDurableObject(p,async(_,ctx)=>{
        const original=crypto.subtle.digest.bind(crypto.subtle);let rival:unknown;
        const spy=vi.spyOn(crypto.subtle,"digest").mockImplementationOnce(async(algorithm,data)=>{spy.mockRestore();rival=cancellationFirst?await cancelCampaignCreation(ctx.storage,H,create(),D):await reserveCampaignCreation(ctx.storage,H,K,intent(),D);return original(algorithm,data);});
        const out=cancellationFirst?await reserveCampaignCreation(ctx.storage,H,K,intent(),D):await cancelCampaignCreation(ctx.storage,H,create(),D);
        expect(rival).toMatchObject({ok:true});expect(out).toMatchObject({ok:false,code:"campaign_player_changed"});
        expect(value(await cancelCampaignCreation(ctx.storage,H,create(),D)).status).toBe(cancellationFirst?"cancelled":"admitted");
      });
    }
  });
  it("cancels before any Player reservation and rejects every delayed use of that key",async()=>{
    const r=await root(),p=await player(),ack=value(await cancelRoot(r));
    expect(ack.status).toBe("cancelled");expect(value(await p.finalizeCampaignJoinCancellation(join(),ack,D))).toEqual(ack);
    expect(await p.reserveCampaignJoin(join(),D)).toMatchObject({ok:false,code:"campaign_admission_cancelled"});
    expect(await joinRoot(r)).toMatchObject({ok:false,code:"campaign_admission_cancelled"});expect(await p.listRooms()).toEqual([]);
    await evictDurableObject(r);await evictDurableObject(p);expect(value(await cancelRoot(r))).toEqual(ack);expect(value(await p.finalizeCampaignJoinCancellation(join(),ack,D))).toEqual(ack);
  });
  it("keeps a shared prelink for new attempt B and never reopens closed A after B joins",async()=>{
    const r=await root(),p=await player();value(await p.reserveCampaignJoin(join(),D));value(await p.reserveCampaignJoin(join(B),D));
    const ack=value(await cancelRoot(r));value(await p.finalizeCampaignJoinCancellation(join(),ack,D));expect(await p.listRooms()).toHaveLength(1);
    value(await joinRoot(r,join(B)));const accepted=value(await cancelRoot(r));expect(accepted.status).toBe("accepted");
    await runInDurableObject(p,async(_,ctx)=>{const before=await inventory(ctx);expect(value(await finalizeCampaignJoinCancellation(ctx.storage,G,join(),accepted,D,resolver)).status).toBe("accepted");expect(await inventory(ctx)).toEqual(before);expect(JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM creations WHERE request_key=?",A).one().data).state).toBe("closed");});
    expect(await p.listRooms()).toHaveLength(1);
  });
  it("cannot drop B's link when B reserves during finalization of A's lost cancellation reply",async()=>{
    const r=await root(),p=await player();value(await p.reserveCampaignJoin(join(),D));const ack=value(await cancelRoot(r));
    await runInDurableObject(p,async(_,ctx)=>{
      const original=crypto.subtle.digest.bind(crypto.subtle);const spy=vi.spyOn(crypto.subtle,"digest").mockImplementationOnce(async(algorithm,data)=>{spy.mockRestore();value(await reserveCampaignJoin(ctx.storage,G,join(B),D));return original(algorithm,data);});
      expect(await finalizeCampaignJoinCancellation(ctx.storage,G,join(),ack,D,resolver)).toMatchObject({ok:false,code:"campaign_player_changed"});
      expect(value(await finalizeCampaignJoinCancellation(ctx.storage,G,join(),ack,D,resolver)).status).toBe("cancelled");
    });
    value(await joinRoot(r,join(B)));expect(await p.listRooms()).toHaveLength(1);
  });
  it("releases a prelink only after every open key is closed and retains both fences",async()=>{
    const r=await root(),p=await player();value(await p.reserveCampaignJoin(join(),D));value(await p.reserveCampaignJoin(join(B),D));
    value(await p.finalizeCampaignJoinCancellation(join(),value(await cancelRoot(r)),D));expect(await p.listRooms()).toHaveLength(1);
    value(await p.finalizeCampaignJoinCancellation(join(B),value(await cancelRoot(r,join(B))),D));expect(await p.listRooms()).toEqual([]);
    expect(await p.reserveCampaignJoin(join(),D)).toMatchObject({ok:false,code:"campaign_admission_cancelled"});expect(await p.reserveCampaignJoin(join(B),D)).toMatchObject({ok:false,code:"campaign_admission_cancelled"});
  });
  it("does not trust foreign, changed-key, changed-body or malformed cancellation acknowledgements",async()=>{
    const r=await root(),p=await player();value(await p.reserveCampaignJoin(join(),D));const ack=value(await cancelRoot(r));
    await runInDurableObject(p,async(_,ctx)=>{const before=await inventory(ctx);
      for(const bad of [{...ack,player_id:H},{...ack,request_hash:"f".repeat(64)},{...ack,idempotency_key:B},{...ack,campaign_room_id:"X".repeat(22)},{...ack,extra:true}])expect(await finalizeCampaignJoinCancellation(ctx.storage,G,join(),bad,D,resolver)).toMatchObject({ok:false});
      expect(await finalizeCampaignJoinCancellation(ctx.storage,G,{...join(),supported_simulation_versions:[6,7]},ack,D,resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("rolls Player closure and link removal back on the final delete failure",async()=>{
    const r=await root(),p=await player();value(await p.reserveCampaignJoin(join(),D));const ack=value(await cancelRoot(r));
    await runInDurableObject(p,async(_,ctx)=>{const before=await inventory(ctx),original=ctx.storage.sql.exec.bind(ctx.storage.sql);let sawClosed=false;
      const spy=vi.spyOn(ctx.storage.sql,"exec").mockImplementation(((sql:string,...args:unknown[])=>{if(sql==="DELETE FROM rooms WHERE room_id=? AND data=?"){sawClosed=JSON.parse(String(original("SELECT data FROM creations WHERE request_key=?",A).one().data)).state==="closed";throw new Error("delete_failed");}return original(sql,...args);}) as typeof ctx.storage.sql.exec);
      try{expect(await finalizeCampaignJoinCancellation(ctx.storage,G,join(),ack,D,resolver)).toMatchObject({ok:false});}finally{spy.mockRestore();}expect(sawClosed).toBe(true);expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("holds original credentials when recovery or deletion wins cancellation validation",async()=>{
    for(const remove of [false,true]){const r=await root(),p=await player();value(await p.reserveCampaignJoin(join(),D));const ack=value(await cancelRoot(r));
      await runInDurableObject(p,async(instance,ctx)=>{const original=crypto.subtle.digest.bind(crypto.subtle);let changed:unknown;
        const spy=vi.spyOn(crypto.subtle,"digest").mockImplementationOnce(async(algorithm,data)=>{spy.mockRestore();if(remove)value(instance.beginDelete([1,2,3],D));else value(instance.recover(RECOVERY,"c".repeat(64),"d".repeat(64),"e".repeat(64)));changed=await inventory(ctx);return original(algorithm,data);});
        expect(await finalizeCampaignJoinCancellation(ctx.storage,G,join(),ack,D,resolver)).toMatchObject({ok:false,code:"identity_unavailable"});expect(await inventory(ctx)).toEqual(changed);
      });
    }
  });
  it("exports strict new Player fences and root7 rows, preserving old root6 archive shape",async()=>{
    const r=await root(),p=await player(H);
    await runInDurableObject(r,async(_,ctx)=>{const old=await exportRoomV2(ctx,"f".repeat(40),resolver);expect((await validateRoomV2(old,R,resolver)).payload).toMatchObject({format_version:8,database_schema_version:6});value(await cancelCampaignJoinRoot(ctx.storage,G,join(),resolver));const current=await exportRoomV2(ctx,"f".repeat(40),resolver);expect((await validateRoomV2(current,R,resolver)).payload).toMatchObject({format_version:9,database_schema_version:7});await expect(restoreRoomV2(ctx,current,R,resolver)).rejects.toThrow("campaign_restore_unsupported");expect((await validateRoomV2(old,R,resolver)).payload.format_version).toBe(8);});
    value(await p.cancelCampaignCreation(create(),D));
    await runInDurableObject(p,async(_,ctx)=>{const raw=await exportSnapshot(ctx,"Player","f".repeat(40));expect((await validateSnapshot(raw,"Player",H)).payload.format_version).toBe(6);await expect(restoreSnapshot(ctx,"Player",raw,H)).rejects.toThrow("campaign_restore_unsupported");});
  });
  it("holds unknown tables, KV and unowned alarms without installing an anchor fence",async()=>{
    for(const mode of ["table","kv","alarm"]){const r=await root();await runInDurableObject(r,async(_,ctx)=>{
      if(mode==="table")ctx.storage.sql.exec("CREATE TABLE future_state (data TEXT)");else if(mode==="kv")await ctx.storage.put("future",1);else await ctx.storage.setAlarm(Date.now()+3600000);
      const before=await inventory(ctx);expect(await cancelCampaignJoinRoot(ctx.storage,G,join(),resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(before);
    });}
  });
  it("holds impossible empty schema7 but preserves an exact initialized root7 retry",async()=>{
    const empty=env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());await runInDurableObject(empty,async(_,ctx)=>{
      initializeCampaignStorageSchema(ctx.storage);initializeCampaignJoinSchema(ctx.storage);const before=await inventory(ctx);
      expect(await initializeCampaignRoot(ctx.storage,{schema_version:1,host_id:H,intent:intent()},resolver)).toMatchObject({ok:false,code:"campaign_root_collision"});expect(await inventory(ctx)).toEqual(before);
    });
    const r=await root();value(await cancelRoot(r));await runInDurableObject(r,async(_,ctx)=>{const before=await inventory(ctx);expect(value(await initializeCampaignRoot(ctx.storage,{schema_version:1,host_id:H,intent:intent()},resolver)).created).toBe(false);expect(await inventory(ctx)).toEqual(before);});
  });
  it("retains bounded closed keys instead of evicting any fence into fresh state",async()=>{
    const r=await root();value(await cancelRoot(r));
    await runInDurableObject(r,async(_,ctx)=>{for(let i=1;i<128;i++){const request=join("closed-join-key-"+String(i).padStart(4,"0"));ctx.storage.sql.exec("INSERT INTO campaign_join_attempts VALUES(?,?,?)",G+":"+request.idempotency_key,await campaignAdmissionHash(G,"join",request),JSON.stringify({schema_version:1,player_id:G,request,status:"cancelled"}));}
      const before=await inventory(ctx);expect(value(await cancelCampaignJoinRoot(ctx.storage,G,join(B),resolver)).status).toBe("cancelled");expect(await joinCampaignRoot(ctx.storage,G,join(B),resolver)).toMatchObject({ok:false,code:"campaign_join_history_full"});expect(await inventory(ctx)).toEqual(before);expect(value(await cancelCampaignJoinRoot(ctx.storage,G,join(),resolver)).status).toBe("cancelled");});
    const p=await player(H);await runInDurableObject(p,async(_,ctx)=>{for(let i=0;i<128;i++){const request={...create(),idempotency_key:"closed-create-key-"+String(i).padStart(4,"0")};const row:CampaignAdmissionIntent={creation_schema:3,admission:"create",player_id:H,request,request_hash:await campaignAdmissionHash(H,"create",request),state:"closed",room_id:null};ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)",request.idempotency_key,JSON.stringify(row));}
      const before=await inventory(ctx);expect(await cancelCampaignCreation(ctx.storage,H,create(),D)).toMatchObject({ok:false,code:"creation_history_full"});expect(await reserveCampaignCreation(ctx.storage,H,K,intent(),D)).toMatchObject({ok:false,code:"creation_history_full"});expect(await inventory(ctx)).toEqual(before);});
  });
  it("keeps accepted reaction/proof/photo bytes and receipt retries across root6 to7 promotion",async()=>{
    const r=await root();
    // Exact historical schema6 membership fixture, then genuine accepted A/B.
    await runInDurableObject(r,(_,ctx)=>{for(const table of ["room","campaign_member","campaign_anchor"]){const raw=JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM "+table).one().data);if(table==="campaign_anchor"){raw.control.guest_id=G;raw.control.state="active";raw.control.revision=1;}else{raw.guest_id=G;if(table==="room")raw.revision=1;}ctx.storage.sql.exec("UPDATE "+table+" SET data=?",JSON.stringify(raw));}});
    let current=value(await r.snapshot(H));current=value(await r.commit(H,{base_revision:current.revision,branch:0,idempotency_key:"historical-host-a",recording:highA})).room;
    value(await r.commit(G,{base_revision:current.revision,branch:0,idempotency_key:"historical-guest-b",recording:highB,checkpoint:middle}));
    const body={idempotency_key:"retained-reaction-key",a_hash:highA.recording_hash,b_hash:highB.recording_hash,expected_reaction_revision:0,reaction:"love"};
    const reaction=value(await r.react(H,"p0-0",body));
    const pixels=new Uint8Array(8*8*4).fill(127);for(let i=3;i<pixels.length;i+=4)pixels[i]=255;
    const jpeg=new Uint8Array(encode({data:pixels,width:8,height:8},50).data);
    const sha256=[...new Uint8Array(await crypto.subtle.digest("SHA-256",jpeg))].map(v=>v.toString(16).padStart(2,"0")).join("");
    const photo=value(await r.updatePhoto(H,"t0-0-a",{idempotency_key:"retained-photo-key",recording_hash:highA.recording_hash,expected_photo_revision:0,expected_photo_hash:null,jpeg_base64:btoa(String.fromCharCode(...jpeg)),sha256}));
    await runInDurableObject(r,async(_,ctx)=>{const names=["turns","pairs","operations","photos","photo_operations","pair_reactions","reaction_operations"],rows=()=>names.map(name=>ctx.storage.sql.exec('SELECT * FROM "'+name+'" ORDER BY rowid').toArray());const before=rows();
      value(await cancelCampaignJoinRoot(ctx.storage,"X".repeat(22),join(),resolver));expect(rows()).toEqual(before);
      const state=JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM room").one().data);expect(value(getReactionOperation(ctx.storage,state,H,body.idempotency_key))).toEqual(reaction);
      const parsed=await parseReaction("p0-0",body);expect(value(ctx.storage.transactionSync(()=>mutateReaction(ctx.storage,state,H,parsed)))).toEqual(reaction);expect(rows()).toEqual(before);
    });
    await evictDurableObject(r);expect(value(await r.reactionOperation(H,body.idempotency_key))).toEqual(reaction);
    expect(value(await r.photoOperation(H,"retained-photo-key"))).toEqual(photo);
  });
});
