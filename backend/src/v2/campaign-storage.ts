import { ApiError, canonicalJson, digest, HASH_PATTERN, ID_PATTERN, isObject } from "../protocol";
import type { TableDefinition } from "../storage-schema";
import { chapter, sameChapter } from "./chapters";
import { boundedCampaign, campaignContinue, campaignContinueResult, campaignDefinition, campaignRequestHash, campaignView, type CampaignDefinitionResolver } from "./campaign-protocol";
import type { CampaignChapterPin, CampaignContinue, CampaignContinueReceipt, CampaignDefinition, CampaignKey, CampaignOrigin, CampaignPending, CampaignView } from "./campaign-types";

/** Fixed SQL only. These tables are created solely by the explicit schema6 initializer. */
export const CAMPAIGN_TABLES: readonly TableDefinition[] = [
  { name: "campaign_anchor", schema: "CREATE TABLE campaign_anchor (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", columns: ["rowid", "id", "data"], maxRows: 1,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,id,data FROM campaign_anchor ORDER BY campaign_anchor.rowid LIMIT 2", insert: "INSERT INTO campaign_anchor (rowid,id,data) VALUES (CAST(? AS INTEGER),?,?)" },
  { name: "campaign_member", schema: "CREATE TABLE campaign_member (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", columns: ["rowid", "id", "data"], maxRows: 1,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,id,data FROM campaign_member ORDER BY campaign_member.rowid LIMIT 2", insert: "INSERT INTO campaign_member (rowid,id,data) VALUES (CAST(? AS INTEGER),?,?)" },
  { name: "campaign_operations", schema: "CREATE TABLE campaign_operations (request_key TEXT PRIMARY KEY, request_hash TEXT NOT NULL, receipt TEXT NOT NULL)", columns: ["rowid", "request_key", "request_hash", "receipt"], maxRows: 16,
    select: "SELECT CAST(rowid AS TEXT) AS rowid,request_key,request_hash,receipt FROM campaign_operations ORDER BY campaign_operations.rowid LIMIT 17", insert: "INSERT INTO campaign_operations (rowid,request_key,request_hash,receipt) VALUES (CAST(? AS INTEGER),?,?,?)" }
];
export type StoredCampaignAnchor = { schema_version: 1; state: "live"; definition: CampaignDefinition; control: CampaignView; pending: CampaignPending | null; closed_before_branches: number[]; deletion: { room_ids: string[]; completed_room_ids: string[] } | null };
export type StoredCampaignMember = { schema_version: 1; campaign_room_id: string; campaign_key: CampaignKey; room_id: string; chapter_index: number; chapter: CampaignChapterPin; host_id: string; guest_id: string | null; transition_id: string | null; status: "provisional" | "active" | "sealed" | "deleting"; seal: { transition_id: string; origin: CampaignOrigin } | null };
export type DeletedCampaignAnchor = { schema_version: 1; state: "deleted"; campaign_room_id: string };
export type DeletedCampaignMember = { schema_version: 1; status: "deleted"; campaign_room_id: string; room_id: string };
type Row = Record<string, string | number>;
type CapturedTable = { name: string; rows: Row[] };
function need(value: unknown): asserts value { if (!value) throw new ApiError(422, "invalid_campaign_storage"); }
function exact(value: unknown, keys: readonly string[]): Record<string, unknown> { need(isObject(value) && Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value,k))); return value; }
function text(value: unknown, pattern = ID_PATTERN): asserts value is string { need(typeof value === "string" && pattern.test(value)); }
function integer(value: unknown, max: number): asserts value is number { need(typeof value === "number" && Number.isSafeInteger(value) && value >= 0 && value <= max); }
function same(a: unknown,b: unknown): boolean { return canonicalJson(a) === canonicalJson(b); }
function parsed(row: Row, field: "data" | "receipt", max: number): Record<string,unknown> { need(typeof row[field] === "string"); const value: unknown=JSON.parse(row[field]); boundedCampaign(value,max,4096,14); need(isObject(value)); return value; }
function singleton(rows: Row[], max: number): Record<string,unknown> | null { need(rows.length <= 1); if (!rows.length) return null; need(rows[0].rowid === "1" && rows[0].id === 1); return parsed(rows[0],"data",max); }
function campaignKey(value: unknown): CampaignKey { const k=exact(value,["campaign_id","campaign_version","definition_hash"]); text(k.campaign_id,/^[a-z][a-z0-9-]{0,47}$/); integer(k.campaign_version,Number.MAX_SAFE_INTEGER); need(k.campaign_version>0); text(k.definition_hash,HASH_PATTERN); return k as CampaignKey; }
function knownPin(value: unknown): CampaignChapterPin { const p=exact(value,["level_id","level_version","definition_hash","simulation_version","premium"]); integer(p.simulation_version,Number.MAX_SAFE_INTEGER);const found=chapter(p); need((found.supported_simulation_versions ?? [found.simulation_version]).includes(p.simulation_version) && p.premium===found.premium); return p as CampaignChapterPin; }
function keyOf(definition: CampaignDefinition): CampaignKey { return {campaign_id:definition.campaign_id,campaign_version:definition.campaign_version,definition_hash:definition.definition_hash}; }
function source(value: unknown): CampaignOrigin["source"] { const s=exact(value,["room_id","revision","branch","checkpoint_hash"]);text(s.room_id);integer(s.revision,Number.MAX_SAFE_INTEGER);integer(s.branch,31);text(s.checkpoint_hash,HASH_PATTERN);return s as CampaignOrigin["source"]; }
function origin(value: unknown): CampaignOrigin { const o=exact(value,["expected_revision","from_index","source"]);integer(o.expected_revision,Number.MAX_SAFE_INTEGER);integer(o.from_index,7);source(o.source);return o as CampaignOrigin; }

/** Read-only target guard. Schema6 alone is enough, including empty/deleted objects. */
export function campaignStoragePresent(storage: DurableObjectStorage): boolean {
  const version=storage.sql.exec<{schema_version:number}>("SELECT schema_version FROM metadata WHERE id=1").toArray()[0]?.schema_version;
  if (version===6) return true;
  return storage.sql.exec<{name:string}>("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('campaign_anchor','campaign_member','campaign_operations')").toArray().length>0;
}

/** Detached data only; this function performs no storage writes or external RPC. */
export async function validateCampaignStorage(captured: CapturedTable[], gameplay: Record<string,unknown> | null, historyEmpty: boolean, resolveDefinition: CampaignDefinitionResolver = () => undefined): Promise<{roomId:string|null}> {
  need(captured.length===3 && captured.every((t,i)=>t.name===CAMPAIGN_TABLES[i].name && t.rows.length<=CAMPAIGN_TABLES[i].maxRows));
  const anchor=singleton(captured[0].rows,32768),member=singleton(captured[1].rows,4096),operations=captured[2].rows;
  if (!member) { need(!anchor && !operations.length && gameplay===null);return {roomId:null}; }
  need(member.schema_version===1);text(member.room_id);text(member.campaign_room_id);
  const root=member.room_id===member.campaign_room_id;
  if (member.status==="deleted") {
    exact(member,["schema_version","status","campaign_room_id","room_id"]);need(same(gameplay,{deleted:true}) && !operations.length);
    if(root){const a=exact(anchor,["schema_version","state","campaign_room_id"]);need(a.schema_version===1 && a.state==="deleted" && a.campaign_room_id===member.room_id);}else need(anchor===null);
    return {roomId:member.room_id};
  }
  exact(member,["schema_version","campaign_room_id","campaign_key","room_id","chapter_index","chapter","host_id","guest_id","transition_id","status","seal"]);
  const mkey=campaignKey(member.campaign_key),pin=knownPin(member.chapter);integer(member.chapter_index,7);text(member.host_id);need(member.guest_id===null || typeof member.guest_id==="string" && ID_PATTERN.test(member.guest_id));need(member.host_id!==member.guest_id);
  need(["provisional","active","sealed","deleting"].includes(String(member.status)));
  if(root)need(member.chapter_index===0 && member.transition_id===null && member.status!=="provisional");else{text(member.transition_id,HASH_PATTERN);need(member.chapter_index>0);}
  if(!root)need(member.guest_id!==null);
  if(gameplay===null)need(member.status==="provisional" || member.status==="deleting");
  else {
    need(gameplay.deleted!==true && gameplay.room_id===member.room_id && gameplay.host_id===member.host_id && gameplay.guest_id===member.guest_id && sameChapter(gameplay as {level_id:string;level_version:number;definition_hash:string},pin));
    const adapter=chapter(pin);need((gameplay.simulation_version ?? adapter.simulation_version)===pin.simulation_version);
    if(member.status==="provisional")need(!root && historyEmpty && gameplay.revision===1 && gameplay.branch===0 && gameplay.stage_index===0 && gameplay.a_turn_id===null && same(gameplay.completed_pair_ids,[]) && same(gameplay.checkpoint,adapter.initial()));
  }
  if(member.seal!==null){const seal=exact(member.seal,["transition_id","origin"]);text(seal.transition_id,HASH_PATTERN);const from=origin(seal.origin);need(member.status==="sealed" || member.status==="deleting");need(gameplay && gameplay.stage_index===2 && from.from_index===member.chapter_index && same(from.source,{room_id:member.room_id,revision:gameplay.revision,branch:gameplay.branch,checkpoint_hash:(gameplay.checkpoint as Record<string,unknown>).checkpoint_hash}));}
  else need(member.status!=="sealed");
  if(!root){need(anchor===null && !operations.length);const candidate=resolveDefinition(mkey);need(candidate);const definition=await campaignDefinition(candidate,p=>{try{return !!knownPin(p);}catch{return false;}});need(same(keyOf(definition),mkey) && same(definition.chapters[member.chapter_index],pin));return {roomId:member.room_id};}
  const a=exact(anchor,["schema_version","state","definition","control","pending","closed_before_branches","deletion"]);need(a.schema_version===1 && a.state==="live");
  const definition=await campaignDefinition(a.definition,p=>{try{return !!knownPin(p);}catch{return false;}}),registry=(k:CampaignKey)=>same(k,keyOf(definition))?definition:undefined;
  const view=await campaignView(a.control,member.host_id,registry);need(view.player_slot==="p0" && view.campaign_room_id===member.room_id && same(view.campaign_key,mkey) && view.guest_id===member.guest_id && same(view.chapters[0].chapter,pin));
  need(gameplay && gameplay.invite_code===view.invite_code && gameplay.invite_expires_at===view.invite_expires_at);
  if(member.seal!==null && view.chapters[0].completion===null)need(view.transition?.origin.from_index===0);
  if(view.state==="deleting")need(member.status==="deleting");else need(member.status!=="deleting");
  if(view.chapters[0].completion){const seal=exact(member.seal,["transition_id","origin"]),completion=view.chapters[0].completion;need(seal.transition_id===completion.transition_id && same(seal.origin,{expected_revision:completion.from_campaign_revision,from_index:0,source:{room_id:member.room_id,revision:completion.source_revision,branch:completion.source_branch,checkpoint_hash:completion.checkpoint_hash}}));}
  if(view.transition===null)need(a.pending===null);else {
    const pending=exact(a.pending,["transition_id","phase","origin","target_intent"]);need(same({transition_id:pending.transition_id,phase:pending.phase,origin:pending.origin},view.transition));
    if(view.current_index===definition.chapters.length-1)need(pending.target_intent===null);else{const target=exact(pending.target_intent,["room_id","invite_code","index","chapter"]);text(target.room_id);text(target.invite_code,/^[A-F0-9]{20}$/);need(target.index===view.current_index+1 && same(target.chapter,definition.chapters[view.current_index+1]) && !view.chapters.some(c=>c.room_id===target.room_id));need((await digest("v2:"+target.invite_code)).slice(0,22)===target.room_id);}
    if(view.current_index===0){if(view.transition.phase!=="prepared")need(member.seal!==null);if(member.seal!==null)need(same(member.seal,{transition_id:view.transition.transition_id,origin:view.transition.origin}));}
  }
  need(Array.isArray(a.closed_before_branches) && a.closed_before_branches.length===definition.chapters.length);
  a.closed_before_branches.forEach((f,i)=>{integer(f,31);const c=view.chapters[i];if(c.room_id===null)need(f===0);if(i===0)need(typeof gameplay.branch==="number" && gameplay.branch>=f);if(c.completion)need(c.completion.source_branch>=f);if(view.transition?.origin.from_index===i)need(view.transition.origin.source.branch>=f);});
  if(view.state!=="deleting")need(a.deletion===null);else {
    const deletion=exact(a.deletion,["room_ids","completed_room_ids"]),ids=view.chapters.flatMap(c=>c.room_id?[c.room_id]:[]);
    const pending=a.pending as CampaignPending|null;if(pending?.target_intent)ids.push(pending.target_intent.room_id);
    need(same(deletion.room_ids,ids) && ids.length<=8 && new Set(ids).size===ids.length && Array.isArray(deletion.completed_room_ids));
    need(new Set(deletion.completed_room_ids).size===deletion.completed_room_ids.length && deletion.completed_room_ids.every(id=>typeof id==="string" && id!==member.room_id && ids.includes(id)));
  }
  for(const row of operations){
    const stored=parsed(row,"receipt",8192);text(row.request_key,/^[A-Za-z0-9_-]{22}:[a-f0-9]{64}$/);text(row.request_hash,HASH_PATTERN);
    let owner:string,request:CampaignContinue,receipt:CampaignContinueReceipt|undefined;
    if(stored.status==="pending") {exact(stored,["status","player_id","request","transition_id"]);text(stored.player_id);owner=stored.player_id;request=await campaignContinue(stored.request,member.room_id,owner,registry);}
    else {exact(stored,["status","receipt"]);need(stored.status==="accepted" && isObject(stored.receipt));receipt=stored.receipt as CampaignContinueReceipt;text(receipt.player_id);owner=receipt.player_id;request=await campaignContinue({schema_version:1,idempotency_key:receipt.idempotency_key,campaign_key:receipt.campaign_key,...origin(receipt.origin)},member.room_id,owner,registry);}
    need(row.request_key===owner+":"+request.idempotency_key && row.request_hash===await campaignRequestHash(member.room_id,owner,request));
    const projection=owner===view.host_id?view:{...view,player_slot:"p1",invite_code:null,invite_expires_at:null};
    const result=receipt?{schema_version:1,operation:"campaign_continue",status:"accepted",receipt,campaign:projection}:{schema_version:1,operation:"campaign_continue",status:"pending",player_id:owner,idempotency_key:request.idempotency_key,request_hash:row.request_hash,transition_id:stored.transition_id,campaign:projection};
    await campaignContinueResult(result,member.room_id,owner,request,registry);
  }
  return {roomId:member.room_id};
}
