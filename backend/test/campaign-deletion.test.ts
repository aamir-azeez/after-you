// Retained Story protocol coverage; production withdrawal is tested without
// this test-only substitution in campaign-production.test.ts.
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => true, requireCampaignProduction: () => {}
}));

import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { encode } from "jpeg-js";
import { canonicalJson, digest, fail, ok, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable, notificationAlarmOwned, queueTurnHint, scheduleNotifications } from "../src/notification-storage";
import { deleteLinkedIdentity, roomDeletionDispatcher, type RoomLink } from "../src/room-links";
import { eraseCampaignChild, eraseCampaignRoot, readCampaignRootTerminal, type CampaignChildDeletion, type CampaignDeletionChildren } from "../src/v2/campaign-deletion";
import { deleteCampaignIdentityLink, type CampaignIdentityRooms } from "../src/v2/campaign-identity-deletion";
import { finalizeCampaignIdentityDeletion } from "../src/v2/campaign-player";
import { initializeCampaignRoot, joinCampaignRoot, cancelCampaignJoinRoot } from "../src/v2/campaign-root";
import { initializeCampaignTarget, activateCampaignTarget, type TargetInitializeRequest } from "../src/v2/campaign-target";
import { campaignAdmissionHash, type CampaignAdmissionIntent } from "../src/v2/campaign-admission-intent";
import { initializeCampaignStorageSchema } from "../src/v2/storage-schema";
import { exportRoomV2, validateRoomV2 } from "../src/v2/snapshot";
import type { StoredCampaignAnchorV2, StoredCampaignMemberV2 } from "../src/v2/campaign-storage";
import type { CampaignDefinition, CampaignJoin, CampaignKey, CampaignView } from "../src/v2/campaign-types";
import type { RoomStateV2 } from "../src/v2/room";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import final from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";

const H=fixture.active_view.host_id,G=fixture.active_view.guest_id!,R=fixture.active_view.campaign_room_id,I=fixture.active_view.invite_code!;
const D="a".repeat(64),RECOVERY="b".repeat(64),TOKEN="c".repeat(64),OTHER="Q".repeat(22);
const definition=fixture.definition as CampaignDefinition,key=fixture.active_view.campaign_key as CampaignKey;
const resolver=(candidate:CampaignKey)=>canonicalJson(candidate)===canonicalJson(key)?definition:undefined;
const room=()=>env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
type Stub=ReturnType<typeof room>;
function value<T>(out:Outcome<T>):T {if(!out.ok)throw new Error(out.code);return out.value;}
const allocation=()=>({schema_version:1 as const,host_id:H,intent:{creation_schema:2 as const,link:{room_id:R,invite_code:I,host:true,api_version:3},campaign_key:structuredClone(key)}});
const join=(i=0):CampaignJoin=>({schema_version:2,idempotency_key:"deleting-join-key-"+i.toString().padStart(4,"0"),invite_code:I,campaign_key:structuredClone(key),supported_simulation_versions:[6]});
const link=(host=false):RoomLink=>({room_id:R,host,invite_code:host?I:"",api_version:3});
const state=(ctx:DurableObjectState)=>JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM room WHERE id=1").one().data) as RoomStateV2;
function seedRedo(ctx:DurableObjectState,id=R){ctx.storage.sql.exec("INSERT INTO redo_control VALUES(1,?)",JSON.stringify({request_id:TOKEN,status:"pending",source:{room_id:id,revision:1,branch:0,stage_index:0,a_hash:TOKEN,first_player_id:H,second_player_id:G}}));}
const anchor=(ctx:DurableObjectState)=>JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM campaign_anchor WHERE id=1").one().data) as StoredCampaignAnchorV2;
async function inventory(ctx:DurableObjectState){const alarm=await ctx.storage.getAlarm(),kv=[...ctx.storage.kv.list()];return {alarm,kv,tables:ctx.storage.sql.exec<{name:string;sql:string}>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray().map(t=>{if(t.name==="_cf_METADATA"){expect(isAlarmMetadataTable(t)).toBe(true);return {...t,rows:null};}return {...t,rows:ctx.storage.sql.exec('SELECT * FROM "'+t.name+'" ORDER BY rowid').toArray()};})};}
async function waiting(){const stub=room();value(await runInDurableObject(stub,(_,ctx)=>initializeCampaignRoot(ctx.storage,allocation(),resolver)));return stub;}
async function player(owner=G,host=false){const p=env.PLAYERS.get(env.PLAYERS.newUniqueId());value(await p.create(owner,D,RECOVERY));if(host)value(await p.reserveCampaignRoom("deletion-host-key-0001",allocation().intent,D));else value(await p.reserveCampaignJoin(join(),D));return p;}
const noChildren:CampaignDeletionChildren={erase:async()=>{throw new Error("unexpected_child");}};
async function branch(phase:"prepared"|"published",metadata=false,named=false){
  const targetInvite="EF".repeat(10),targetId=(await digest("v2:"+targetInvite)).slice(0,22),root=named?env.ROOMS_V2.getByName(R):room(),child=named?env.ROOMS_V2.getByName(targetId):room(),childId=child.id.toString();
  value(await root.initialize(R,H,I,definition.chapters[0]));let s=value(await root.join(G,I,[6]));
  for(const [owner,recording,checkpoint] of [[H,highA,null],[G,highB,middle],[G,lowA,null],[H,lowB,final]] as const)s=value(await root.commit(owner,{base_revision:s.revision,branch:s.branch,idempotency_key:crypto.randomUUID(),recording,...(checkpoint?{checkpoint}:{})})).room;
  if(metadata){
    const bytes=new Uint8Array(encode({data:new Uint8Array(8*8*4).fill(127),width:8,height:8},45).data),sha256=[...new Uint8Array(await crypto.subtle.digest("SHA-256",bytes))].map(v=>v.toString(16).padStart(2,"0")).join("");
    value(await root.updatePhoto(H,"t0-0-a",{idempotency_key:crypto.randomUUID(),recording_hash:highA.recording_hash,expected_photo_revision:0,expected_photo_hash:null,jpeg_base64:btoa(String.fromCharCode(...bytes)),sha256}));
    value(await root.react(G,"p0-0",{idempotency_key:crypto.randomUUID(),a_hash:highA.recording_hash,b_hash:highB.recording_hash,expected_reaction_revision:0,reaction:"love"}));
    value(await root.acknowledgePhoto(G,"t0-0-a",{recording_hash:highA.recording_hash,photo_revision:1,sha256}));
  }
  const origin={expected_revision:1,from_index:0,source:{room_id:R,revision:s.revision,branch:s.branch,checkpoint_hash:s.checkpoint.checkpoint_hash}};
  const target={room_id:targetId,invite_code:targetInvite,index:1,chapter:definition.chapters[1]};
  const request:TargetInitializeRequest={schema_version:1,binding:{campaign_room_id:R,campaign_key:key,room_id:targetId,chapter_index:1,chapter:definition.chapters[1],host_id:H,guest_id:G,member_transition_id:TOKEN},origin,target_intent:target};
  await runInDurableObject(root,async(_,ctx)=>{
    const gameplay=state(ctx),control=structuredClone(fixture.active_view) as CampaignView;control.invite_expires_at=gameplay.invite_expires_at;
    const a:StoredCampaignAnchorV2={schema_version:2,state:"live",definition:structuredClone(definition),control,pending:null,closed_before_branches:[0,0],deletion:null,activation:null};
    const m:StoredCampaignMemberV2={schema_version:2,campaign_room_id:R,campaign_key:key,room_id:R,chapter_index:0,chapter:definition.chapters[0],host_id:H,guest_id:G,transition_id:null,status:"active",seal:null,incoming:null};
    if(phase==="prepared"){control.revision=2;control.state="continuing";control.transition={transition_id:TOKEN,phase:"prepared",origin};a.pending={...control.transition,target_intent:target};}
    else {control.revision=5;control.current_index=1;control.chapters[0].completion={source_revision:s.revision,source_branch:s.branch,checkpoint_hash:s.checkpoint.checkpoint_hash,transition_id:TOKEN,from_campaign_revision:1,accepted_campaign_revision:5};control.chapters[1].room_id=targetId;control.activation={transition_id:TOKEN};a.activation={transition_id:TOKEN,origin,target_intent:target,accepted_revision:5};m.status="sealed";m.seal={transition_id:TOKEN,origin};}
    initializeCampaignStorageSchema(ctx.storage);ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)",JSON.stringify(a));ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)",JSON.stringify(m));
    if(metadata){value(await cancelCampaignJoinRoot(ctx.storage,OTHER,join(7),resolver));queueTurnHint(ctx.storage,{...env,NOTIFICATIONS_ENABLED:"true"},"relay",gameplay,H);await scheduleNotifications(ctx.storage);}
  });
  if(phase==="published")value(await runInDurableObject(child,(_,ctx)=>initializeCampaignTarget(ctx.storage,request,resolver)));
  const children:CampaignDeletionChildren={erase:async input=>{expect(input.binding.room_id).toBe(targetId);return runInDurableObject(env.ROOMS_V2.get(env.ROOMS_V2.idFromString(childId)),(_,ctx)=>eraseCampaignChild(ctx.storage,input,resolver));}};
  return {root,child,request,children,targetId};
}
async function erase(root:Stub,owner=H,children=noChildren,admitted:unknown=null){return runInDurableObject(root,(_,ctx)=>eraseCampaignRoot(ctx.storage,owner,R,admitted,children,resolver));}
async function deleted(stub:Stub,id=R){await runInDurableObject(stub,async(_,ctx)=>{const archive=await exportRoomV2(ctx,"f".repeat(40),resolver);expect((await validateRoomV2(archive,id,resolver)).payload.summary.state).toBe("deleted");const raw=await inventory(ctx);expect(raw.alarm).toBeNull();for(const table of raw.tables){if(["metadata","room","campaign_member",...(id===R?["campaign_anchor"]:[])].includes(table.name)||table.name==="_cf_METADATA")continue;expect(table.rows,table.name).toEqual([]);}expect(state(ctx)).toEqual({deleted:true});});}
function ports(root:Stub,children=noChildren):CampaignIdentityRooms{return {erase:(owner,_id,allocation)=>erase(root,owner,children,allocation),cancel:(owner,_id,body)=>runInDurableObject(root,(_,ctx)=>cancelCampaignJoinRoot(ctx.storage,owner,body,resolver))};}
function playerPorts(p:Awaited<ReturnType<typeof player>>){return {campaignIdentityDeletionScope:(l:RoomLink,d:string)=>p.campaignIdentityDeletionScope(l,d),finalizeCampaignIdentityDeletion:(scope:unknown,evidence:unknown,d:string)=>runInDurableObject(p,(_,ctx)=>finalizeCampaignIdentityDeletion(ctx.storage,G,scope,evidence,d,resolver))};}
afterEach(async()=>{vi.restoreAllMocks();await reset();});

describe("private campaign cascade and api3 identity cleanup",()=>{
  it("recovers only valid overdue consumed notification metadata during campaign deletion",async()=>{
    const clock=vi.spyOn(Date,"now").mockReturnValue(Date.now()+3_600_000);
    const r=await waiting();value(await runInDurableObject(r,(_,ctx)=>joinCampaignRoot(ctx.storage,G,join(),resolver)));
    await runInDurableObject(r,async(_,ctx)=>{
      queueTurnHint(ctx.storage,{NOTIFICATIONS_ENABLED:"true"},"relay",state(ctx),H);await scheduleNotifications(ctx.storage);
      await ctx.storage.deleteAlarm();clock.mockReturnValue(Date.now()+1001);
      expect(notificationAlarmOwned(ctx.storage,"RoomV2",null)).toBe(false);
      expect(notificationAlarmOwned(ctx.storage,"RoomV2",null,true)).toBe(true);
    });
    value(await erase(r));await deleted(r);
  });
  it.each(["future","missing-marker","missing-outbox","wrong-due","malformed","foreign-room","foreign-recipient","unowned-alarm"])("holds %s notification metadata without changing campaign evidence",async mode=>{
    const clock=vi.spyOn(Date,"now").mockReturnValue(Date.now()+3_600_000);
    const r=await waiting();value(await runInDurableObject(r,(_,ctx)=>joinCampaignRoot(ctx.storage,G,join(),resolver)));
    await runInDurableObject(r,async(_,ctx)=>{
      queueTurnHint(ctx.storage,{NOTIFICATIONS_ENABLED:"true"},"relay",state(ctx),H);await scheduleNotifications(ctx.storage);
      await ctx.storage.deleteAlarm();if(mode!=="future")clock.mockReturnValue(Date.now()+1001);
      if(mode==="missing-marker")ctx.storage.sql.exec("DELETE FROM notification_alarm");
      if(mode==="missing-outbox")ctx.storage.sql.exec("DELETE FROM notification_outbox");
      if(mode==="wrong-due")ctx.storage.sql.exec("UPDATE notification_alarm SET due_at=due_at-1");
      if(mode==="malformed")ctx.storage.sql.exec("UPDATE notification_outbox SET data='{}'");
      if(mode==="foreign-recipient")ctx.storage.sql.exec("UPDATE notification_outbox SET recipient_id=?",OTHER);
      if(mode==="foreign-room"){
        const event=JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM notification_outbox").one().data);
        event.hint.room_id=OTHER;event.hint.event_id=`relay_${OTHER}_${event.hint.revision}`;
        ctx.storage.sql.exec("UPDATE notification_outbox SET data=?",JSON.stringify(event));
      }
      if(mode==="unowned-alarm")await ctx.storage.setAlarm(Date.now()+60000);
      const before=await inventory(ctx);
      expect(await eraseCampaignRoot(ctx.storage,H,R,null,noChildren,resolver)).toMatchObject({ok:false,status:409,code:"campaign_deletion_unavailable"});
      expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("fences a prepared target before root-last removal, including a target never initialized",async()=>{
    const c=await branch("prepared");let visited=0;
    const result=await runInDurableObject(c.root,(_,ctx)=>eraseCampaignRoot(ctx.storage,H,R,null,{erase:async(request,definition)=>{visited++;expect(anchor(ctx).control.state).toBe("deleting");expect(anchor(ctx).deletion).toEqual({room_ids:[R,c.targetId],completed_room_ids:[]});expect(state(ctx).checkpoint).toEqual(final);return c.children.erase(request,definition);}},resolver));
    expect(value(result).status).toBe("deleted");expect(visited).toBe(1);await deleted(c.root);await deleted(c.child,c.targetId);
    await runInDurableObject(c.child,async(_,ctx)=>{const before=await inventory(ctx);expect(await initializeCampaignTarget(ctx.storage,c.request,resolver)).toMatchObject({ok:false});expect(await activateCampaignTarget(ctx.storage,{...c.request,accepted_revision:5},resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(before);});
  });
  it("erases published activation debt and every real proof/photo/reaction/Join/notification row",async()=>{
    const c=await branch("published",true);
    await runInDurableObject(c.root,(_,ctx)=>seedRedo(ctx));
    await runInDurableObject(c.child,(_,ctx)=>seedRedo(ctx,c.targetId));
    value(await erase(c.root,G,c.children));await deleted(c.root);await deleted(c.child,c.targetId);
    await evictDurableObject(c.root);await evictDurableObject(c.child);expect(value(await erase(c.root,H)).status).toBe("deleted");
  });
  it("keeps the root and complete target inventory after a lost child reply, then converges on retry",async()=>{
    const c=await branch("prepared");expect(await erase(c.root,H,{erase:async(request,definition)=>{value(await c.children.erase(request,definition));return fail(503,"lost_child_ack");}})).toMatchObject({ok:false,code:"lost_child_ack"});
    await runInDurableObject(c.root,(_,ctx)=>{expect(anchor(ctx).deletion?.completed_room_ids).toEqual([]);expect(state(ctx).checkpoint).toEqual(final);});
    await evictDurableObject(c.root);value(await erase(c.root,G,c.children));await deleted(c.root);
  });
  it("does not advance durable completion on a wrong or merely boolean child acknowledgement",async()=>{
    for(const bad of [{deleted:true},{schema_version:1,status:"deleted",campaign_room_id:R,room_id:OTHER}]){const c=await branch("prepared");expect(await erase(c.root,H,{erase:async()=>ok(bad)})).toMatchObject({ok:false});await runInDurableObject(c.root,(_,ctx)=>{expect(anchor(ctx).deletion?.completed_room_ids).toEqual([]);expect(state(ctx).checkpoint).toEqual(final);});}
  });
  it("holds foreign, future, extra-table/KV and unowned-alarm children without clearing any bytes",async()=>{
    for(const mode of ["foreign","future","table","kv","alarm","redo","invalid-redo"]){const c=await branch("prepared");await runInDurableObject(c.child,async(instance,ctx)=>{
      if(mode==="foreign")value(await instance.initialize(OTHER,H,"CD".repeat(10),definition.chapters[0]));if(mode==="future")ctx.storage.sql.exec("UPDATE metadata SET schema_version=999");if(mode==="table")ctx.storage.sql.exec("CREATE TABLE unknown_data (data TEXT)");if(mode==="kv")ctx.storage.kv.put("unknown","kept");if(mode==="alarm")await ctx.storage.setAlarm(Date.now()+60000);
      if(mode==="redo")seedRedo(ctx,c.targetId);if(mode==="invalid-redo")ctx.storage.sql.exec("INSERT INTO redo_control VALUES(1,?)","{}");
      const before=await inventory(ctx);expect(await eraseCampaignChild(ctx.storage,{schema_version:1,binding:c.request.binding,origin:c.request.origin},resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(before);
    });}
  });
  it("does not attest complete deletion when a valid redo request remains",async()=>{
    const r=await waiting();value(await erase(r));await deleted(r);
    await runInDurableObject(r,async(_,ctx)=>{
      seedRedo(ctx);const before=await inventory(ctx);
      expect(await readCampaignRootTerminal(ctx.storage,R)).toMatchObject({ok:false});
      expect(await eraseCampaignRoot(ctx.storage,H,R,null,noChildren,resolver)).toMatchObject({ok:false});
      expect(await inventory(ctx)).toEqual(before);
    });
  });
  it("rolls root tombstone and privacy cleanup back if the final anchor write fails",async()=>{
    const c=await branch("published",true);await runInDurableObject(c.root,async(_,ctx)=>{const original=ctx.storage.sql.exec.bind(ctx.storage.sql);let failed=false;
      const spy=vi.spyOn(ctx.storage.sql,"exec").mockImplementation(((sql:string,...args:unknown[])=>{if(sql==="INSERT INTO campaign_anchor VALUES(1,?)"){failed=true;throw new Error("final_anchor_failed");}return original(sql,...args);}) as typeof ctx.storage.sql.exec);
      try{expect(await eraseCampaignRoot(ctx.storage,H,R,null,c.children,resolver)).toMatchObject({ok:false});}finally{spy.mockRestore();}expect(failed).toBe(true);expect(anchor(ctx).deletion?.completed_room_ids).toEqual([c.targetId]);expect(state(ctx).checkpoint).toEqual(final);expect(ctx.storage.sql.exec("SELECT 1 FROM photos").toArray()).toHaveLength(1);
    });value(await erase(c.root,H,c.children));await deleted(c.root);
  });
  it("holds request mutation and same-schema competing initialization at the hash await",async()=>{
    const c=await branch("prepared");await runInDurableObject(c.child,async(_,ctx)=>{initializeCampaignStorageSchema(ctx.storage);const body:CampaignChildDeletion={schema_version:1,binding:structuredClone(c.request.binding),origin:structuredClone(c.request.origin)},original=crypto.subtle.digest.bind(crypto.subtle);let raced:unknown;
      const spy=vi.spyOn(crypto.subtle,"digest").mockImplementationOnce(async(algorithm,data)=>{spy.mockRestore();body.binding.room_id=OTHER;value(await initializeCampaignTarget(ctx.storage,c.request,resolver));raced=await inventory(ctx);return original(algorithm,data);});
      expect(await eraseCampaignChild(ctx.storage,body,resolver)).toMatchObject({ok:false,code:"campaign_state_changed"});expect(await inventory(ctx)).toEqual(raced);
    });
  });
  it("fences an admitted empty host allocation and refuses delayed initialization",async()=>{
    const r=room();expect(await erase(r)).toMatchObject({ok:false});value(await erase(r,H,noChildren,allocation()));await deleted(r);
    await runInDurableObject(r,async(_,ctx)=>{const before=await inventory(ctx);expect(await initializeCampaignRoot(ctx.storage,allocation(),resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(before);});
  });
  it("a nonmember prelink cancels its keys without deleting the host campaign",async()=>{
    const r=await waiting(),p=await player();value(await p.reserveCampaignJoin(join(1),D));value(await p.beginDelete([1,2,3],D));
    value(await deleteCampaignIdentityLink(playerPorts(p),ports(r),G,link(),D,resolver));expect(await p.listRooms()).toEqual([]);
    await runInDurableObject(r,async(_,ctx)=>{expect(anchor(ctx).control.state).toBe("waiting");expect(state(ctx).host_id).toBe(H);expect(await joinCampaignRoot(ctx.storage,G,join(),resolver)).toMatchObject({ok:false,code:"campaign_admission_cancelled"});});
  });
  it("switches from prelink cancellation to the whole cascade if delayed Join already won",async()=>{
    const r=await waiting(),p=await player();value(await p.beginDelete([1,2,3],D));const io=ports(r),cancel=io.cancel;let once=false;
    io.cancel=async(owner,id,body)=>{if(!once){once=true;value(await runInDurableObject(r,(_,ctx)=>joinCampaignRoot(ctx.storage,G,body,resolver)));}return cancel(owner,id,body);};
    value(await deleteCampaignIdentityLink(playerPorts(p),io,G,link(),D,resolver));expect(await p.listRooms()).toEqual([]);await deleted(r);
  });
  it("retains the sole cleanup link across a halfway failure with all128 Join keys, then recovers every fence",async()=>{
    const r=await waiting(),p=await player();await runInDurableObject(p,async(_,ctx)=>{for(let i=1;i<128;i++){const request=join(i),intent:CampaignAdmissionIntent={creation_schema:3,admission:"join",player_id:G,request,request_hash:await campaignAdmissionHash(G,"join",request),state:"open",room_id:R};ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)",request.idempotency_key,JSON.stringify(intent));}});value(await p.beginDelete([1,2,3],D));
    const io=ports(r),cancel=io.cancel;let calls=0;io.cancel=async(...args)=>++calls===65?fail(503,"halfway"):cancel(...args);
    expect(await deleteCampaignIdentityLink(playerPorts(p),io,G,link(),D,resolver)).toMatchObject({ok:false,code:"halfway"});expect(await p.listRooms()).toEqual([link()]);
    await runInDurableObject(r,(_,ctx)=>expect(ctx.storage.sql.exec("SELECT 1 FROM campaign_join_attempts").toArray()).toHaveLength(64));
    await evictDurableObject(r);await evictDurableObject(p);value(await deleteCampaignIdentityLink(playerPorts(p),ports(r),G,link(),D,resolver));expect(await p.listRooms()).toEqual([]);
    await runInDurableObject(r,(_,ctx)=>{expect(anchor(ctx).control.state).toBe("waiting");expect(ctx.storage.sql.exec<{data:string}>("SELECT data FROM campaign_join_attempts").toArray().every(row=>JSON.parse(row.data).status==="cancelled")).toBe(true);expect(ctx.storage.sql.exec("SELECT 1 FROM campaign_join_attempts").toArray()).toHaveLength(128);});
  });
  it("holds missing roots and unrecognized keyless guest prelinks",async()=>{
    for(const absent of [true,false]){const r=absent?room():await waiting(),p=await player();if(!absent)await runInDurableObject(p,(_,ctx)=>ctx.storage.sql.exec("DELETE FROM creations"));value(await p.beginDelete([1,2,3],D));expect(await deleteCampaignIdentityLink(playerPorts(p),ports(r),G,link(),D,resolver)).toMatchObject({ok:false});expect(await p.listRooms()).toEqual([link()]);}
  });
  it("keeps original deleting-device and exact Player bytes across finalizer awaits and failures",async()=>{
    for(const mode of ["device","write"]){const r=await waiting(),p=await player();value(await p.beginDelete([1,2,3],D));const scope=value(await p.campaignIdentityDeletionScope(link(),D)),ack=value(await runInDurableObject(r,(_,ctx)=>cancelCampaignJoinRoot(ctx.storage,G,join(),resolver)));
      await runInDurableObject(p,async(_,ctx)=>{const evidence={schema_version:1,status:"cancelled",player_id:G,campaign_room_id:R,acknowledgements:[ack]},before=await inventory(ctx);
        let changed:unknown;
        if(mode==="device"){const original=crypto.subtle.digest.bind(crypto.subtle),spy=vi.spyOn(crypto.subtle,"digest").mockImplementationOnce(async(algorithm,data)=>{spy.mockRestore();const identity=JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM identity").one().data);identity.device_hash="d".repeat(64);ctx.storage.sql.exec("UPDATE identity SET data=?",JSON.stringify(identity));changed=await inventory(ctx);return original(algorithm,data);});expect(await finalizeCampaignIdentityDeletion(ctx.storage,G,scope,evidence,D,resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(changed);}
        else {const original=ctx.storage.sql.exec.bind(ctx.storage.sql),spy=vi.spyOn(ctx.storage.sql,"exec").mockImplementation(((sql:string,...args:unknown[])=>{if(sql==="DELETE FROM rooms WHERE room_id=? AND data=?")throw new Error("local_remove_failed");return original(sql,...args);}) as typeof ctx.storage.sql.exec);try{expect(await finalizeCampaignIdentityDeletion(ctx.storage,G,scope,evidence,D,resolver)).toMatchObject({ok:false});}finally{spy.mockRestore();}expect(await inventory(ctx)).toEqual(before);}
      });
    }
  });
  it("lets both identities independently release their own links after one minimal root tombstone",async()=>{
    const r=await waiting(),host=await player(H,true),guest=await player();value(await runInDurableObject(r,(_,ctx)=>joinCampaignRoot(ctx.storage,G,join(),resolver)));value(await host.beginDelete([1,2,3],D));value(await guest.beginDelete([1,2,3],D));
    value(await deleteCampaignIdentityLink(host,ports(r),H,link(true),D,resolver));expect(await host.listRooms()).toEqual([]);expect(await guest.listRooms()).toEqual([link()]);
    value(await deleteCampaignIdentityLink(playerPorts(guest),ports(r),G,link(),D,resolver));expect(await guest.listRooms()).toEqual([]);await deleted(r);
  });
  it("api3 dispatch never removes a link on generic404 or a boolean success",async()=>{
    for(const out of [fail(404,"room_not_found"),ok({deleted:true})]){const p=await player();expect(await deleteLinkedIdentity(G,p,roomDeletionDispatcher(env.ROOMS,undefined,async()=>out),D)).toMatchObject({ok:false});expect(await p.listRooms()).toEqual([link()]);}
  });
  it("requires exact finalizer evidence and does not permit ordinary active identity cleanup",async()=>{
    const p=await player();expect(await p.campaignIdentityDeletionScope(link(),D)).toMatchObject({ok:false,code:"identity_unavailable"});value(await p.beginDelete([1,2,3],D));const scope=value(await p.campaignIdentityDeletionScope(link(),D));
    await runInDurableObject(p,async(_,ctx)=>{const before=await inventory(ctx);for(const evidence of [{deleted:true},{schema_version:1,status:"deleted",campaign_room_id:OTHER,room_id:OTHER},{schema_version:1,status:"cancelled",player_id:G,campaign_room_id:R,acknowledgements:[]}])expect(await finalizeCampaignIdentityDeletion(ctx.storage,G,scope,evidence,D,resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(before);});
  });
  it("uses the actual named Room bindings and identity dispatcher with no injected definition registry",async()=>{
    const c=await branch("published",true,true),p=await player(H,true);
    const dispatcher=roomDeletionDispatcher(env.ROOMS,undefined,(l,owner)=>deleteCampaignIdentityLink(p,{
      erase:(id,roomId,allocation)=>env.ROOMS_V2.getByName(roomId).eraseCampaignRoot(id,roomId,allocation),
      cancel:(id,roomId,body)=>env.ROOMS_V2.getByName(roomId).cancelCampaignJoinRoot(id,body)
    },owner,l,D));
    expect(await deleteLinkedIdentity(H,p,dispatcher,D)).toEqual(ok({deleted:true}));await deleted(c.root);await deleted(c.child,c.targetId);
    expect(await p.authorize(D,true)).toBe(false);
  });
  it("fences an actual empty reserved root even when no fresh-admission definition resolver exists",async()=>{
    const p=await player(H,true),r=env.ROOMS_V2.getByName(R);value(await p.beginDelete([3],D));
    value(await deleteCampaignIdentityLink(p,{erase:(owner,id,allocation)=>env.ROOMS_V2.getByName(id).eraseCampaignRoot(owner,id,allocation),cancel:async()=>{throw new Error("unexpected_cancel");}},H,link(true),D));
    expect(await p.listRooms()).toEqual([]);await deleted(r);
  });
  it("rechecks actual named root membership if Join wins prelink cancellation without a registry",async()=>{
    const r=env.ROOMS_V2.getByName(R),p=await player();value(await runInDurableObject(r,(_,ctx)=>initializeCampaignRoot(ctx.storage,allocation(),resolver)));value(await p.beginDelete([3],D));let raced=false;
    value(await deleteCampaignIdentityLink(p,{
      erase:(owner,id,allocation)=>env.ROOMS_V2.getByName(id).eraseCampaignRoot(owner,id,allocation),
      cancel:async(owner,id,body)=>{if(!raced){raced=true;value(await env.ROOMS_V2.getByName(id).joinCampaignRoot(owner,body));}return env.ROOMS_V2.getByName(id).cancelCampaignJoinRoot(owner,body);}
    },G,link(),D));
    expect(raced).toBe(true);expect(await p.listRooms()).toEqual([]);await deleted(r);
  });
  it("uses the permanent root7 saturation fence for a different owner's newer prelink through actual bindings",async()=>{
    const r=env.ROOMS_V2.getByName(R),p=await player();value(await runInDurableObject(r,(_,ctx)=>initializeCampaignRoot(ctx.storage,allocation(),resolver)));
    for(let i=0;i<128;i++)value(await r.cancelCampaignJoinRoot(OTHER,join(i)));
    expect(await r.joinCampaignRoot(G,join())).toMatchObject({ok:false,code:"campaign_join_history_full"});
    const before=await runInDurableObject(r,(_,ctx)=>inventory(ctx));
    const closed=value(await r.cancelCampaignJoinRoot(G,join()));expect(closed.status).toBe("cancelled");expect(closed.request_hash).toBe(await campaignAdmissionHash(G,"join",join()));
    expect(await runInDurableObject(r,(_,ctx)=>inventory(ctx))).toEqual(before);
    value(await p.beginDelete([3],D));value(await deleteCampaignIdentityLink(p,{erase:(owner,id,allocation)=>env.ROOMS_V2.getByName(id).eraseCampaignRoot(owner,id,allocation),cancel:(owner,id,body)=>env.ROOMS_V2.getByName(id).cancelCampaignJoinRoot(owner,body)},G,link(),D));
    expect(await p.listRooms()).toEqual([]);await evictDurableObject(r);expect(await r.joinCampaignRoot(G,join())).toMatchObject({ok:false,code:"campaign_join_history_full"});
    await runInDurableObject(r,(_,ctx)=>{expect(anchor(ctx).control.state).toBe("waiting");expect(ctx.storage.sql.exec("SELECT 1 FROM campaign_join_attempts").toArray()).toHaveLength(128);});
  });
  it("resolves actual membership before saturation and holds changed or unknown root authority",async()=>{
    const r=await waiting();value(await runInDurableObject(r,(_,ctx)=>joinCampaignRoot(ctx.storage,G,join(),resolver)));
    for(let i=0;i<127;i++)value(await runInDurableObject(r,(_,ctx)=>cancelCampaignJoinRoot(ctx.storage,OTHER,join(i),resolver)));
    expect(value(await runInDurableObject(r,(_,ctx)=>joinCampaignRoot(ctx.storage,G,join(900),resolver))).campaign.guest_id).toBe(G);
    expect(value(await runInDurableObject(r,(_,ctx)=>cancelCampaignJoinRoot(ctx.storage,G,join(900),resolver))).status).toBe("accepted");
    await runInDurableObject(r,async(_,ctx)=>{
      const original=crypto.subtle.digest.bind(crypto.subtle);let changed:unknown;
      const spy=vi.spyOn(crypto.subtle,"digest").mockImplementationOnce(async(algorithm,data)=>{spy.mockRestore();ctx.storage.sql.exec("CREATE TABLE unknown_deletion_hold(data TEXT)");changed=await inventory(ctx);return original(algorithm,data);});
      expect(await cancelCampaignJoinRoot(ctx.storage,"Z".repeat(22),join(901),resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(changed);
      expect(await cancelCampaignJoinRoot(ctx.storage,"Z".repeat(22),join(901),resolver)).toMatchObject({ok:false});expect(await inventory(ctx)).toEqual(changed);
    });
  });
});
