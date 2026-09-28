import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { restoreSnapshot, snapshotResult, validateSnapshot, type PortableSnapshot } from "../src/snapshot";
import { exportRoomV2, restoreRoomV2, validateRoomV2, type RoomV2Archive } from "../src/v2/snapshot";
import { initializeCampaignStorageSchema, initializePairReactions, initializePhotoDelivery, initializeRoomV2Schema } from "../src/v2/storage-schema";
import { CAMPAIGN_TABLES, validateCampaignStorage, type StoredCampaignAnchorV2 as StoredCampaignAnchor, type StoredCampaignMemberV2 as StoredCampaignMember } from "../src/v2/campaign-storage";
import { campaignCreation, validCampaignCreation } from "../src/v2/campaign-creation-intent";
import { campaignContinueKey, campaignRequestHash } from "../src/v2/campaign-protocol";
import type { CampaignContinue, CampaignContinueReceipt, CampaignDefinition, CampaignKey, CampaignOrigin, CampaignView } from "../src/v2/campaign-types";
import fixture from "./fixtures/campaign-control-v2.json";
import legacy from "./fixtures/campaign-contract.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import highMiddle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import highFinal from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";

const definition=fixture.definition as CampaignDefinition, view=fixture.active_view as CampaignView;
const host=view.host_id,guest=view.guest_id!,anchorId=view.campaign_room_id,invite=view.invite_code!,commit="d".repeat(40);
const room=()=>env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()),player=()=>env.PLAYERS.get(env.PLAYERS.newUniqueId());
type RoomStub=ReturnType<typeof room>;
const value=<T>(outcome:Outcome<T>):T=>{if(!outcome.ok)throw new Error(outcome.code);return outcome.value;};
const resolver=(key:CampaignKey)=>canonicalJson(key)===canonicalJson(view.campaign_key)?definition:undefined;
const parseRoom=(raw:string):RoomV2Archive=>JSON.parse(raw);
const parsePlayer=(raw:string):PortableSnapshot=>JSON.parse(raw);
async function encode<T extends RoomV2Archive|PortableSnapshot>(archive:T){archive.checksum.value=await digest(canonicalJson(archive.payload));return canonicalJson(archive);}
async function inventory(ctx:DurableObjectState){
  const alarm=await ctx.storage.getAlarm();
  const tables=ctx.storage.sql.exec<{name:string;sql:string}>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray();
  return {alarm,kv:[...ctx.storage.kv.list()],tables:tables.map(t=>({...t,rows:ctx.storage.sql.exec('SELECT * FROM "'+t.name.replaceAll('"','""')+'" ORDER BY rowid').toArray()}))};
}
function member(index=0,id=anchorId):StoredCampaignMember{return {schema_version:2,incoming:index===0?null:{origin:structuredClone(fixture.accepted_result.receipt.origin),accepted_revision:fixture.accepted_result.receipt.accepted_revision},campaign_room_id:anchorId,campaign_key:structuredClone(view.campaign_key),room_id:id,chapter_index:index,chapter:structuredClone(definition.chapters[index]),host_id:host,guest_id:guest,transition_id:index===0?null:"c".repeat(64),status:"active",seal:null};}
function control(current:CampaignView=view,state?:Record<string,unknown>):StoredCampaignAnchor{return {schema_version:2,activation:null,state:"live",definition:structuredClone(definition),control:{...structuredClone(current),...(state?{invite_expires_at:String(state.invite_expires_at)}:{})},pending:null,closed_before_branches:[0,0],deletion:null};}
function sidecars(a:unknown,m:unknown,ops:Record<string,string|number>[]=[]){return CAMPAIGN_TABLES.map((t,i)=>({name:t.name,rows:i===2?ops:(i===0?a:m)===null?[]:[{rowid:"1",id:1,data:JSON.stringify(i===0?a:m)}]}));}
async function begin(index=0,id=anchorId):Promise<RoomStub>{const stub=room();value(await stub.initialize(id,host,invite,definition.chapters[index]));value(await stub.join(guest,invite,[6]));return stub;}
async function install(stub:RoomStub,a:unknown,m:unknown){await runInDurableObject(stub,async(_,ctx)=>{initializeCampaignStorageSchema(ctx.storage);if(a!==null){const copy=structuredClone(a) as StoredCampaignAnchor;if(copy.state==="live")copy.control.invite_expires_at=JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM room").one().data).invite_expires_at;ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)",JSON.stringify(copy));}if(m!==null)ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)",JSON.stringify(m));});}
async function completed(id=anchorId){const stub=await begin(0,id);let state=value(await stub.snapshot(host));for(const [owner,recording,checkpoint] of [[host,highA,null],[guest,highB,highMiddle],[guest,lowA,null],[host,lowB,highFinal]] as const){state=value(await stub.commit(owner,{base_revision:state.revision,branch:state.branch,idempotency_key:crypto.randomUUID(),recording,...(checkpoint?{checkpoint}:{})})).room;}return stub;}
async function rawState(stub:RoomStub){return runInDurableObject(stub,async(_,ctx)=>JSON.parse(ctx.storage.sql.exec<{data:string}>("SELECT data FROM room WHERE id=1").one().data) as Record<string,unknown>);}
async function campaignExport(stub:RoomStub){return runInDurableObject(stub,async(_,ctx)=>exportRoomV2(ctx,commit,resolver));}
async function sourcePlayer(){const stub=player();value(await stub.create(host,"a".repeat(64),"b".repeat(64)));return stub;}
afterEach(async()=>{vi.restoreAllMocks();await reset();});

describe("disabled campaign storage and archive foundation",()=>{
  it("leaves standalone schema/default archive and exact raw proof rows unchanged",async()=>{
    const stub=await completed(),before=parseRoom(value(await stub.exportSnapshot(commit)));
    expect(before.payload.format_version).toBe(5);expect(before.payload.database_schema_version).toBe(3);
    expect(before.payload.tables.some(t=>t.name.startsWith("campaign_"))).toBe(false);
    const target=room();expect(await target.restoreSnapshot(canonicalJson(before),anchorId)).toMatchObject({ok:true});
    await evictDurableObject(target);expect(parseRoom(value(await target.exportSnapshot(commit))).payload.tables).toEqual(before.payload.tables);
  });
  it("promotes explicitly and retains schema6 through photo/reaction initializers and eviction",async()=>{
    const stub=await begin(),before=parseRoom(value(await stub.exportSnapshot(commit))).payload.tables;
    await install(stub,control(),member());
    await runInDurableObject(stub,async(_,ctx)=>{initializePairReactions(ctx.storage);initializePhotoDelivery(ctx.storage);initializeRoomV2Schema(ctx.storage);expect(ctx.storage.sql.exec<{schema_version:number}>("SELECT schema_version FROM metadata").one().schema_version).toBe(6);});
    await evictDurableObject(stub);const exported=parseRoom(await campaignExport(stub));
    expect(exported.payload.format_version).toBe(8);expect(exported.payload.database_schema_version).toBe(6);
    expect(exported.payload.tables.slice(0,before.length)).toEqual(before);
    expect(exported.payload.tables.slice(-3).map(t=>t.name)).toEqual(CAMPAIGN_TABLES.map(t=>t.name));
  });
  it("preserves accepted source proof strings, outgoing seal and accepted owner aliases",async()=>{
    const stub=await completed(),before=parseRoom(value(await stub.exportSnapshot(commit))).payload.tables;
    const a=control(fixture.accepted_result.campaign as CampaignView),m=member();m.status="sealed";m.seal={transition_id:fixture.accepted_result.receipt.transition_id,origin:fixture.accepted_result.receipt.origin};
    await install(stub,a,m);
    await runInDurableObject(stub,async(_,ctx)=>{ctx.storage.sql.exec("INSERT INTO campaign_operations VALUES(?,?,?)",host+":"+fixture.continue_body.idempotency_key,fixture.expected_request_hash,JSON.stringify({status:"accepted",receipt:fixture.accepted_result.receipt},null,2));});
    const archive=parseRoom(await campaignExport(stub));expect(archive.payload.tables.slice(0,before.length)).toEqual(before);
    expect(String(archive.payload.tables.at(-1)!.rows[0].receipt)).toContain("\n");
    expect((await validateRoomV2(canonicalJson(archive),anchorId,resolver)).payload.tables).toEqual(archive.payload.tables);
  });
  it("exports provisional children only with an exact manifest/index and initial paired state",async()=>{
    const id="B".repeat(22),m=member(1,id);m.status="provisional";m.incoming!.accepted_revision=null;
    const stub=await begin(1,id);await install(stub,null,m);
    const archive=await campaignExport(stub);expect(parseRoom(archive).payload.logical_id).toBe(id);
    await expect(validateRoomV2(archive,id)).rejects.toThrow("invalid_campaign_snapshot");
    const wrong=structuredClone(definition);wrong.chapters.reverse();await expect(validateRoomV2(archive,id,()=>wrong)).rejects.toThrow("invalid_campaign_snapshot");
    const state=await rawState(stub);state.revision=2;
    await expect(validateCampaignStorage(sidecars(null,m),state,true,resolver)).rejects.toThrow();
    await expect(validateCampaignStorage(sidecars(null,m),await rawState(stub),false,resolver)).rejects.toThrow();
    await expect(validateCampaignStorage(sidecars(null,m),null,true,resolver)).resolves.toEqual({roomId:id});
  });
  it("retains an exact prepared alias and all child deletion work while keeping the anchor last",async()=>{
    const stub=await completed(),state=await rawState(stub),a=control(fixture.pending_result.campaign as CampaignView,state),m=member();
    const targetInvite="EF".repeat(10),targetId=(await digest("v2:"+targetInvite)).slice(0,22);
    a.pending={...a.control.transition!,target_intent:{room_id:targetId,invite_code:targetInvite,index:1,chapter:structuredClone(definition.chapters[1])}};
    const ops=[{rowid:"1",request_key:host+":"+fixture.continue_body.idempotency_key,request_hash:fixture.expected_request_hash,receipt:JSON.stringify({status:"pending",player_id:host,request:fixture.continue_body,transition_id:a.pending.transition_id})}];
    await expect(validateCampaignStorage(sidecars(a,m,ops),state,false,resolver)).resolves.toEqual({roomId:anchorId});
    a.control.state="deleting";m.status="deleting";a.deletion={room_ids:[anchorId,targetId],completed_room_ids:[targetId]};
    await expect(validateCampaignStorage(sidecars(a,m,ops),state,false,resolver)).resolves.toEqual({roomId:anchorId});
    a.deletion.room_ids=[anchorId];await expect(validateCampaignStorage(sidecars(a,m,ops),state,false,resolver)).rejects.toThrow();
  });
  it("accepts the legal eight-entry sixteen-owner-alias archive without extending gameplay proofs",async()=>{
    const stub=await completed(),before=parseRoom(value(await stub.exportSnapshot(commit))).payload.tables;
    const full=structuredClone(definition);full.campaign_id="synthetic-eight-storage";full.chapters=Array.from({length:8},()=>structuredClone(definition.chapters[0]));
    const {definition_hash:_previous,...body}=full;full.definition_hash=await digest(canonicalJson(body));
    const key={campaign_id:full.campaign_id,campaign_version:full.campaign_version,definition_hash:full.definition_hash};
    const current=structuredClone(view);current.campaign_key=key;current.current_index=7;current.revision=17;current.state="complete";
    current.chapters=full.chapters.map((pin,index)=>({chapter:pin,room_id:index===0?anchorId:String(index).repeat(22),completion:{source_revision:5,source_branch:0,checkpoint_hash:highFinal.checkpoint_hash,transition_id:(index+1).toString(16).padStart(64,"0"),from_campaign_revision:1+index*2,accepted_campaign_revision:3+index*2}}));
    const a=control(current);a.definition=full;a.closed_before_branches=Array(8).fill(0);
    const m=member();m.campaign_key=key;m.status="sealed";m.seal={transition_id:current.chapters[0].completion!.transition_id,origin:{expected_revision:1,from_index:0,source:{room_id:anchorId,revision:5,branch:0,checkpoint_hash:highFinal.checkpoint_hash}}};
    await install(stub,a,m);
    const aliases:{key:string;hash:string;raw:string}[]=[];
    for(let index=0;index<8;index++)for(const owner of [host,guest]){
      const c=current.chapters[index].completion!,origin:CampaignOrigin={expected_revision:c.from_campaign_revision,from_index:index,source:{room_id:current.chapters[index].room_id!,revision:5,branch:0,checkpoint_hash:highFinal.checkpoint_hash}};
      const request:CampaignContinue={schema_version:1,idempotency_key:await campaignContinueKey(anchorId,key,owner,origin),campaign_key:key,...origin};
      const hash=await campaignRequestHash(anchorId,owner,request),receipt:CampaignContinueReceipt={schema_version:1,operation:"campaign_continue",campaign_room_id:anchorId,campaign_key:key,player_id:owner,idempotency_key:request.idempotency_key,request_hash:hash,transition_id:c.transition_id,origin,accepted_revision:c.accepted_campaign_revision,outcome:index===7?"finished":"advanced",next_index:index===7?null:index+1,next_room_id:index===7?null:current.chapters[index+1].room_id};
      aliases.push({key:owner+":"+request.idempotency_key,hash,raw:JSON.stringify({status:"accepted",receipt})});
    }
    await runInDurableObject(stub,async(_,ctx)=>{for(const alias of aliases)ctx.storage.sql.exec("INSERT INTO campaign_operations VALUES(?,?,?)",alias.key,alias.hash,alias.raw);});
    const archive=parseRoom(await campaignExport(stub));expect(archive.payload.tables.at(-1)!.rows).toHaveLength(16);
    expect(archive.payload.tables.slice(0,before.length)).toEqual(before);
    expect((await validateRoomV2(canonicalJson(archive),anchorId)).payload.tables).toEqual(archive.payload.tables);
  });
  it("exports exact minimal deleted bindings while keeping ordinary live restore forbidden",async()=>{
    for(const root of [true,false]){
      const id=root?anchorId:"B".repeat(22),stub=room();
      await runInDurableObject(stub,async(_,ctx)=>{initializeCampaignStorageSchema(ctx.storage);ctx.storage.sql.exec("INSERT INTO room VALUES(1,?)",JSON.stringify({deleted:true}));});
      await runInDurableObject(stub,async(_,ctx)=>{if(root)ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)",JSON.stringify({schema_version:1,state:"deleted",campaign_room_id:anchorId}));ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)",JSON.stringify({schema_version:1,status:"deleted",campaign_room_id:anchorId,room_id:id}));});
      const raw=await campaignExport(stub);expect(parseRoom(raw).payload.summary.state).toBe("deleted");expect(parseRoom(raw).payload.logical_id).toBe(id);
      expect(await room().restoreSnapshot(raw,id)).toMatchObject({ok:false,code:"campaign_restore_unsupported"});
    }
  });
  it("holds malformed binding, fence, phase, seal, deletion and operation rows",async()=>{
    const stub=await completed(),state=await rawState(stub),a=control(view,state),m=member();
    const changed: [unknown,unknown,Record<string,string|number>[]][]=[];
    let x=structuredClone(a);x.closed_before_branches=[0,1];changed.push([x,m,[]]);
    x=structuredClone(a);x.control.invite_expires_at="2026-01-01T00:00:00.000Z";changed.push([x,m,[]]);
    const wrong=structuredClone(m);wrong.room_id="X".repeat(22);changed.push([a,wrong,[]]);
    const missingSeal=structuredClone(m);missingSeal.status="sealed";changed.push([a,missingSeal,[]]);
    const orphanSeal=structuredClone(m);orphanSeal.status="sealed";orphanSeal.seal={transition_id:fixture.accepted_result.receipt.transition_id,origin:fixture.accepted_result.receipt.origin};changed.push([a,orphanSeal,[]]);
    x=control(fixture.pending_result.campaign as CampaignView);x.pending={...x.control.transition!,target_intent:null};changed.push([x,m,[]]);
    x=structuredClone(a);x.control.state="deleting";x.deletion={room_ids:[anchorId],completed_room_ids:[anchorId]};const deleting=structuredClone(m);deleting.status="deleting";changed.push([x,deleting,[]]);
    changed.push([a,m,[{rowid:"1",request_key:host+":"+fixture.continue_body.idempotency_key,request_hash:fixture.expected_request_hash,receipt:JSON.stringify({status:"rejected",receipt:fixture.rejected_result.receipt})}]]);
    for(const [anchor,mem,ops] of changed)await expect(validateCampaignStorage(sidecars(anchor,mem,ops),state,false,resolver)).rejects.toThrow();
    const overflow=Array.from({length:17},(_,i)=>({rowid:String(i+1),request_key:"unused",request_hash:"unused",receipt:"{}"}));await expect(validateCampaignStorage(sidecars(a,m,overflow),state,false,resolver)).rejects.toThrow();
  });
  it("rejects incoming schema6 before any restore SQL/KV/alarm change",async()=>{
    const source=await begin();await install(source,control(),member());const raw=await campaignExport(source),target=room();
    await runInDurableObject(target,async(_,ctx)=>{const before=await inventory(ctx);expect(await snapshotResult(()=>restoreRoomV2(ctx,raw,anchorId,resolver))).toMatchObject({ok:false,code:"campaign_restore_unsupported"});expect(await inventory(ctx)).toEqual(before);});
    expect(raw).toBe(await encode(parseRoom(raw)));
  });
  it("refuses standalone restore into even an empty schema6 target after validation yields",async()=>{
    const source=await begin(),raw=value(await source.exportSnapshot(commit)),target=room();
    await runInDurableObject(target,async(_,ctx)=>{
      const original=crypto.subtle.digest.bind(crypto.subtle);let after:Awaited<ReturnType<typeof inventory>>|undefined;
      const spy=vi.spyOn(crypto.subtle,"digest").mockImplementationOnce(async(algorithm,data)=>{initializeCampaignStorageSchema(ctx.storage);after=await inventory(ctx);return original(algorithm,data);});
      try{expect(await snapshotResult(()=>restoreRoomV2(ctx,raw,anchorId))).toMatchObject({ok:false,code:"campaign_restore_unsupported"});}finally{spy.mockRestore();}
      expect(await inventory(ctx)).toEqual(after);
      const empty=await exportRoomV2(ctx,commit);expect(parseRoom(empty).payload).toMatchObject({format_version:8,logical_id:null});
    });
  });
  it("keeps unknown schema, extra tables, KV and unowned alarms as hard holds",async()=>{
    for(const variant of ["schema","table","kv","alarm"]){const stub=await begin();await install(stub,control(),member());await runInDurableObject(stub,async(_,ctx)=>{if(variant==="schema")ctx.storage.sql.exec("UPDATE metadata SET schema_version=7");if(variant==="table")ctx.storage.sql.exec("CREATE TABLE surprise(value TEXT)");if(variant==="kv")ctx.storage.kv.put("surprise","kept");if(variant==="alarm")await ctx.storage.setAlarm(Date.now()+3600000);});expect(await stub.exportSnapshot(commit)).toMatchObject({ok:false});}
  });
});

describe("Player campaign content classification without a new SQL schema",()=>{
  it("keeps unrelated unknown links and raw creation strings in their old format",async()=>{
    const stub=await sourcePlayer(),raw=' {"host":true,"invite_code":"'+invite+'","room_id":"'+anchorId+'","api_version":47} ';
    await runInDurableObject(stub,async(_,ctx)=>{ctx.storage.sql.exec("INSERT INTO rooms VALUES(?,?)",anchorId,raw);ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)","creation-key-0047",raw);});
    const archive=value(await stub.exportSnapshot(commit));expect(parsePlayer(archive).payload.format_version).toBe(2);
    const target=player();expect(await target.restoreSnapshot(archive,host)).toMatchObject({ok:true});expect(parsePlayer(value(await target.exportSnapshot(commit))).payload.tables).toEqual(parsePlayer(archive).payload.tables);
  });
  it("exports Player5 with tester grant and exact raw api3 link/creation bytes",async()=>{
    const stub=await sourcePlayer();value(await stub.redeemTesterAccess(host,"a".repeat(64),true));
    const link={room_id:anchorId,invite_code:invite,host:true,api_version:3},raw=JSON.stringify(link,null,2);
    await runInDurableObject(stub,async(_,ctx)=>{ctx.storage.sql.exec("INSERT INTO rooms VALUES(?,?)",anchorId,raw);ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)","creation-key-0003",raw);});
    const archive=value(await stub.exportSnapshot(commit)),parsed=parsePlayer(archive);expect(parsed.payload.format_version).toBe(5);expect(parsed.payload.database_schema_version).toBe(1);
    expect(parsed.payload.tables[1].rows[0].data).toBe(raw);expect(parsed.payload.tables[2].rows[0].data).toBe(raw);expect(JSON.parse(String(parsed.payload.tables[0].rows[0].data)).tester_grant).toMatchObject({schema_version:1});
    expect((await validateSnapshot(archive,"Player",host)).payload.tables).toEqual(parsed.payload.tables);
    const target=player();await runInDurableObject(target,async(_,ctx)=>{const before=await inventory(ctx);expect(await snapshotResult(()=>restoreSnapshot(ctx,"Player",archive,host))).toMatchObject({ok:false,code:"campaign_restore_unsupported"});expect(await inventory(ctx)).toEqual(before);});
  });
  it("validates a separate exact manifest-pinned creation intent and invitation binding",async()=>{
    const intent={creation_schema:2,link:{room_id:anchorId,invite_code:invite,host:true,api_version:3},campaign_key:structuredClone(view.campaign_key)};
    expect(await campaignCreation(intent)).toEqual(intent);expect(validCampaignCreation({...intent,extra:true})).toBe(false);expect(await campaignCreation({...intent,link:{...intent.link,room_id:"X".repeat(22)}})).toBeNull();
    const stub=await sourcePlayer(),raw=JSON.stringify(intent,null,2);await runInDurableObject(stub,async(_,ctx)=>ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)","campaign-create-01",raw).toArray());
    const archive=value(await stub.exportSnapshot(commit));expect(parsePlayer(archive).payload.format_version).toBe(5);expect(parsePlayer(archive).payload.tables[2].rows[0].data).toBe(raw);
    expect(await player().restoreSnapshot(archive,host)).toMatchObject({ok:false,code:"campaign_restore_unsupported"});
  });
  it("refuses api3 in rooms or raw creations across every previously accepted envelope",async()=>{
    for(const table of ["rooms","creations"] as const)for(const version of [2,3,4] as const){
      const stub=await sourcePlayer(),raw=JSON.stringify({room_id:anchorId,invite_code:invite,host:true,api_version:3});
      await runInDurableObject(stub,async(_,ctx)=>ctx.storage.sql.exec(table==="rooms"?"INSERT INTO rooms VALUES(?,?)":"INSERT INTO creations VALUES(?,?)",table==="rooms"?anchorId:"legacy-create-0003",raw).toArray());
      const archive=parsePlayer(value(await stub.exportSnapshot(commit)));archive.payload.format_version=version;const encoded=await encode(archive),target=player();
      expect((await validateSnapshot(encoded,"Player",host)).payload.tables).toEqual(archive.payload.tables);
      await runInDurableObject(target,async(_,ctx)=>{const before=await inventory(ctx);expect(await snapshotResult(()=>restoreSnapshot(ctx,"Player",encoded,host))).toMatchObject({ok:false,code:"campaign_restore_unsupported"});expect(await inventory(ctx)).toEqual(before);});
    }
  });
  it("rechecks campaign-bearing target creations installed during checksum validation",async()=>{
    const source=await sourcePlayer(),raw=value(await source.exportSnapshot(commit)),target=player();
    await runInDurableObject(target,async(_,ctx)=>{
      const original=crypto.subtle.digest.bind(crypto.subtle);let after:Awaited<ReturnType<typeof inventory>>|undefined;
      const spy=vi.spyOn(crypto.subtle,"digest").mockImplementationOnce(async(algorithm,data)=>{ctx.storage.sql.exec("INSERT INTO creations VALUES(?,?)","raced-create-0003",JSON.stringify({room_id:anchorId,invite_code:invite,host:true,api_version:3}));after=await inventory(ctx);return original(algorithm,data);});
      try{expect(await snapshotResult(()=>restoreSnapshot(ctx,"Player",raw,host))).toMatchObject({ok:false,code:"campaign_restore_unsupported"});}finally{spy.mockRestore();}expect(await inventory(ctx)).toEqual(after);
    });
  });
});

describe("sidecar2 activation and legacy archive8 compatibility",()=>{
  it("rejects recomputed child archives with impossible outgoing chronology, reused tokens or wrong predecessor roots",async()=>{
    for(const index of [1,2]){
      const id="B".repeat(22),stub=await completed(id),state=await rawState(stub);
      const oldTables=parseRoom(value(await stub.exportSnapshot(commit))).payload.tables;
      const d=structuredClone(definition);d.chapters=Array.from({length:index+1},()=>structuredClone(definition.chapters[0]));
      const {definition_hash:_previous,...body}=d;d.definition_hash=await digest(canonicalJson(body));
      const campaignKey={campaign_id:d.campaign_id,campaign_version:d.campaign_version,definition_hash:d.definition_hash};
      const resolve=(k:CampaignKey)=>canonicalJson(k)===canonicalJson(campaignKey)?d:undefined;
      const incoming={...structuredClone(fixture.accepted_result.receipt.origin),expected_revision:7,from_index:index-1};
      incoming.source.room_id=index===1?anchorId:"C".repeat(22);
      const m:StoredCampaignMember={schema_version:2,incoming:{origin:incoming,accepted_revision:8},campaign_room_id:anchorId,campaign_key:campaignKey,room_id:id,chapter_index:index,chapter:d.chapters[index],host_id:host,guest_id:guest,transition_id:"8".repeat(64),status:"sealed",seal:{transition_id:"7".repeat(64),origin:{expected_revision:8,from_index:index,source:{room_id:id,revision:Number(state.revision),branch:Number(state.branch),checkpoint_hash:highFinal.checkpoint_hash}}}};
      await install(stub,null,m);
      const raw=await runInDurableObject(stub,async(_,ctx)=>exportRoomV2(ctx,commit,resolve)),archive=parseRoom(raw);
      expect(archive.payload.tables.slice(0,oldTables.length)).toEqual(oldTables);
      expect((await validateRoomV2(raw,id,resolve)).payload.tables).toEqual(archive.payload.tables);
      for(const change of ["zero_revision","preceding_revision","incoming_token","wrong_predecessor"]){
        const bad=structuredClone(archive),row=bad.payload.tables.find(t=>t.name==="campaign_member")!.rows[0];
        const member=JSON.parse(String(row.data)) as StoredCampaignMember;
        if(change==="zero_revision")member.seal!.origin.expected_revision=0;
        if(change==="preceding_revision")member.seal!.origin.expected_revision=7;
        if(change==="incoming_token")member.seal!.transition_id=member.transition_id!;
        if(change==="wrong_predecessor")member.incoming!.origin.source.room_id=index===1?"C".repeat(22):anchorId;
        row.data=JSON.stringify(member);
        await expect(validateRoomV2(await encode(bad),id,resolve)).rejects.toThrow("invalid_campaign_snapshot");
      }
    }
  });
  it("allows absent gameplay only for a never-activated V2 target while retaining V1 archive rules",async()=>{
    const id="B".repeat(22),m=member(1,id);m.status="deleting";
    await expect(validateCampaignStorage(sidecars(null,m),null,true,resolver)).rejects.toThrow();
    const {incoming:_incoming,schema_version:_version,...old}=m;
    await expect(validateCampaignStorage(sidecars(null,{...old,schema_version:1}),null,true,resolver)).resolves.toEqual({roomId:id});
    m.incoming!.accepted_revision=null;
    await expect(validateCampaignStorage(sidecars(null,m),null,true,resolver)).resolves.toEqual({roomId:id});
    m.status="provisional";
    await expect(validateCampaignStorage(sidecars(null,m),null,true,resolver)).resolves.toEqual({roomId:id});
  });
  it("exports and validates exact legacy1 JSON and operation receipts without making it live",async()=>{
    const stub=await completed(),a=control(fixture.accepted_result.campaign as CampaignView),m=member();
    m.status="sealed";m.seal={transition_id:legacy.accepted_result.receipt.transition_id,origin:legacy.accepted_result.receipt.origin};
    const {activation:_debt,control:_view,schema_version:_av,...oldAnchor}=a;
    const {incoming:_incoming,schema_version:_mv,...oldMember}=m;
    await install(stub,{...oldAnchor,schema_version:1,control:structuredClone(legacy.accepted_result.campaign)},{...oldMember,schema_version:1});
    await runInDurableObject(stub,async(_,ctx)=>{ctx.storage.sql.exec("INSERT INTO campaign_operations VALUES(?,?,?)",host+":"+legacy.continue_body.idempotency_key,legacy.expected_request_hash,JSON.stringify({status:"accepted",receipt:legacy.accepted_result.receipt},null,2));});
    const before=await runInDurableObject(stub,async(_,ctx)=>inventory(ctx));
    const raw=await campaignExport(stub),parsed=parseRoom(raw);expect(parsed.payload.format_version).toBe(8);
    expect((await validateRoomV2(raw,anchorId,resolver)).payload.tables).toEqual(parsed.payload.tables);
    expect(await stub.snapshot(host,{schema_version:2,room_id:anchorId,device_hash:"a".repeat(64)})).toMatchObject({ok:false,code:"campaign_state_unavailable"});
    expect(await runInDurableObject(stub,async(_,ctx)=>inventory(ctx))).toEqual(before);
    const target=room(),targetBefore=await runInDurableObject(target,async(_,ctx)=>inventory(ctx));
    expect(await target.restoreSnapshot(raw,anchorId)).toMatchObject({ok:false});
    expect(await runInDurableObject(target,async(_,ctx)=>inventory(ctx))).toEqual(targetBefore);
  });
  it("binds root activation debt to one exact published target and immutable previous completion",async()=>{
    const stub=await completed(),state=await rawState(stub),a=control(fixture.accepted_result.campaign as CampaignView,state),m=member();
    m.status="sealed";m.seal={transition_id:fixture.accepted_result.receipt.transition_id,origin:structuredClone(fixture.accepted_result.receipt.origin)};
    const inviteCode="EF".repeat(10),target=(await digest("v2:"+inviteCode)).slice(0,22);
    a.control.chapters[1].room_id=target;a.control.activation={transition_id:m.seal.transition_id};
    a.activation={transition_id:m.seal.transition_id,origin:structuredClone(m.seal.origin),accepted_revision:fixture.accepted_result.receipt.accepted_revision,target_intent:{room_id:target,invite_code:inviteCode,index:1,chapter:structuredClone(definition.chapters[1])}};
    await expect(validateCampaignStorage(sidecars(a,m),state,false,resolver)).resolves.toEqual({roomId:anchorId});
    for(const change of ["token","revision","origin","target","missing","mixed","marker"]){
      const bad=structuredClone(a) as unknown as Record<string,unknown>,debt=bad.activation as Record<string,unknown>;
      if(change==="token")debt.transition_id="e".repeat(64);
      if(change==="revision")debt.accepted_revision=999;
      if(change==="origin")(debt.origin as Record<string,unknown>).from_index=1;
      if(change==="target")(debt.target_intent as Record<string,unknown>).invite_code="AB".repeat(10);
      if(change==="missing")delete bad.activation;
      if(change==="mixed")bad.schema_version=1;
      if(change==="marker")(bad.control as Record<string,unknown>).activation=null;
      await expect(validateCampaignStorage(sidecars(bad,m),state,false,resolver)).rejects.toThrow();
    }
    await install(stub,a,m);const before=await runInDurableObject(stub,async(_,ctx)=>inventory(ctx));const archive=await campaignExport(stub);
    expect((await validateRoomV2(archive,anchorId,resolver)).payload.format_version).toBe(8);
    expect(await runInDurableObject(stub,async(_,ctx)=>inventory(ctx))).toEqual(before);
    a.control.state="deleting";m.status="deleting";a.deletion={room_ids:[anchorId,target],completed_room_ids:[]};
    await expect(validateCampaignStorage(sidecars(a,m),state,false,resolver)).resolves.toEqual({roomId:anchorId});
  });
  it("requires explicit child publication and keeps unactivated deleting children at the initial state",async()=>{
    const id="B".repeat(22),stub=await begin(1,id),state=await rawState(stub),m=member(1,id);
    await expect(validateCampaignStorage(sidecars(null,m),state,true,resolver)).resolves.toEqual({roomId:id});
    m.incoming!.accepted_revision=null;await expect(validateCampaignStorage(sidecars(null,m),state,true,resolver)).rejects.toThrow();
    m.status="provisional";await expect(validateCampaignStorage(sidecars(null,m),state,true,resolver)).resolves.toEqual({roomId:id});
    m.status="deleting";await expect(validateCampaignStorage(sidecars(null,m),state,true,resolver)).resolves.toEqual({roomId:id});
    await expect(validateCampaignStorage(sidecars(null,m),{...state,revision:2},true,resolver)).rejects.toThrow();
    m.incoming!.origin.from_index=1;await expect(validateCampaignStorage(sidecars(null,m),state,true,resolver)).rejects.toThrow();
  });
});
