import { env } from "cloudflare:workers";
import { reset, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { conservatory, longWayHome } from "../src/v2/protocol-journey";
import { chapter, recordingV2, checkpointV2, initialCheckpoint, boundedValue, MAX_RECORDING_BYTES, MAX_CHECKPOINT_BYTES, MAX_V2_BODY_BYTES } from "../src/v2/protocol";
import type { ChapterAdapter, ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import conservatoryDefinition from "../../game/tests/fixtures/journey/conservatory-definition.json";
import conservatoryFirst from "../../game/tests/fixtures/journey/a-light-above-checkpoint.json";
import conservatoryFinal from "../../game/tests/fixtures/journey/conservatory-final-checkpoint.json";
import homeDefinition from "../../game/tests/fixtures/journey/long-way-home-definition.json";
import homeFirst from "../../game/tests/fixtures/journey/the-path-you-leave-checkpoint.json";
import homeFinal from "../../game/tests/fixtures/journey/long-way-home-final-checkpoint.json";
import correctedSelector from "../../game/tests/fixtures/journey/validation/corrected-selector.json";
import gardenEnding from "../../game/tests/fixtures/journey/validation/garden-ending.json";
import changedWindow from "../../game/tests/fixtures/journey/validation/changed-window.json";
import closedShutter from "../../game/tests/fixtures/journey/validation/closed-return-shutter.json";

const cases = [
  { adapter: conservatory, definition: conservatoryDefinition, middle: conservatoryFirst, final: conservatoryFinal },
  { adapter: longWayHome, definition: homeDefinition, middle: homeFirst, final: homeFinal }
];
type Account = { player_id: string; device_token: string };
let requestNo = 0;
const operationKey = () => crypto.randomUUID(), CODE = "SYNTHETIC-JOURNEY-HOST";
async function call(path: string, method = "GET", owner?: Account, body?: unknown, enabled = true) {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: String(enabled), TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE),
    REVENUECAT_VERIFICATION_MODE: "play_store", REVENUECAT_SECRET_KEY: "synthetic-only", REVENUECAT_PROJECT_ID: "projSynthetic", REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID: "entlPlay", REVENUECAT_PLAY_PRODUCT_ID: "prodPlay", REVENUECAT_PLAY_ENVIRONMENT: "production" });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.3." + ++requestNo,
    ...(owner ? { "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }),
  configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function grant(owner: Account) { expect((await call("/v1/tester-access", "POST", owner, { schema_version: 1, code: CODE })).status).toBe(200); }
async function room(selected: ChapterAdapter) {
  const host = await account(), guest = await account(); await grant(host);
  const response = await call("/v2/rooms", "POST", host, { ...selected.key, idempotency_key: operationKey() }); expect(response.status).toBe(200);
  const created = await response.json<RoomSnapshotV2>();
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: created.invite_code, supported_simulation_versions: [7] }); expect(joined.status).toBe(200);
  return { host, guest, current: await joined.json<RoomSnapshotV2>() };
}
async function rehash(value: Record<string, unknown>) {
  const { checkpoint_hash: ignored, proof, ...body } = value; void ignored; void proof;
  return { ...value, checkpoint_hash: await digest(canonicalJson(body)) };
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("registered journey chapters", () => {
  it.each([correctedSelector,gardenEnding,changedWindow,closedShutter])("accepts native corrections without forcing final lever or sole-branch history ($checkpoint_hash)", async checkpoint => {
    const selected = chapter(checkpoint), a = await selected.recording(checkpoint.proof.a), b = await selected.recording(checkpoint.proof.b);
    expect(await selected.checkpoint(checkpoint,checkpoint.proof.checkpoint,a,b)).toEqual(checkpoint);
  });
  it("keeps both paid chapters behind one independent default-off creation gate", async () => {
    expect(env.JOURNEY_CHAPTERS_ENABLED).toBe("false");
    const host = await account(); await grant(host);
    const before = await (await call("/v2/capabilities", "GET", host, undefined, false)).json<{ chapters: { level_id: string }[] }>();
    expect(before.chapters.some(c => c.level_id === "conservatory" || c.level_id === "long-way-home")).toBe(false);
    for (const fixture of cases) expect((await call("/v2/rooms", "POST", host, { ...fixture.adapter.key, idempotency_key: operationKey() }, false)).status).toBe(503);
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual([]);
    const after = await (await call("/v2/capabilities", "GET", host)).json<{ chapters: Record<string, unknown>[] }>();
    for (const fixture of cases) expect(after.chapters).toContainEqual({ ...fixture.adapter.key, premium: true, recording_version: 7, simulation_version: 7 });
  });
  it.each(cases)("requires only the host's existing unlock and retries one creation ($adapter.key.level_id)", async fixture => {
    vi.spyOn(globalThis,"fetch").mockImplementation(async () => Response.json({ object:"list",items:[],next_page:null }));
    const host = await account(), body = { ...fixture.adapter.key, idempotency_key: operationKey() };
    const denied = await call("/v2/rooms", "POST", host, body); expect(denied.status).toBe(402);
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual([]);
    await grant(host);
    const first = await call("/v2/rooms", "POST", host, body); expect(first.status).toBe(200); const created = await first.json<RoomSnapshotV2>();
    expect(await (await call("/v2/rooms", "POST", host, body)).json()).toEqual(created);
    const guest = await account();
    for (const versions of [undefined, [2,4,5,6]]) {
      const deniedJoin = await call("/v2/rooms/join", "POST", guest, { invite_code: created.invite_code, ...(versions ? { supported_simulation_versions: versions } : {}) });
      expect(deniedJoin.status).toBe(422); expect(await env.PLAYERS.getByName(guest.player_id).listRooms()).toEqual([]);
    }
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: created.invite_code, supported_simulation_versions: [2,4,5,6,7] }); expect(joined.status).toBe(200);
    expect((await joined.json<RoomSnapshotV2>()).guest_id).toBe(guest.player_id);
    expect((await call(`/v2/rooms/${created.room_id}`, "GET", guest, undefined, false)).status).toBe(200);
  });
  it.each(cases)("retains exact native pins and both complete proof pairs ($adapter.key.level_id)", async fixture => {
    const selected = fixture.adapter;
    expect(chapter(selected.key)).toBe(selected); expect(await digest(canonicalJson(fixture.definition))).toBe(selected.key.definition_hash);
    let previous = initialCheckpoint(selected.key);
    for (const checkpoint of [fixture.middle, fixture.final]) {
      const a = await recordingV2(checkpoint.proof.a, selected.key), b = await recordingV2(checkpoint.proof.b, selected.key);
      expect(await checkpointV2(checkpoint, previous, a, b)).toEqual(checkpoint); previous = checkpoint;
      expect(() => boundedValue(a, MAX_RECORDING_BYTES)).not.toThrow(); expect(() => boundedValue(checkpoint, MAX_CHECKPOINT_BYTES)).not.toThrow();
      expect(() => boundedValue({ base_revision: 4, branch: 0, idempotency_key: operationKey(), recording: b, checkpoint }, MAX_V2_BODY_BYTES)).not.toThrow();
      const wrong = { ...a, simulation_version: 6 }; await expect(selected.recording(wrong)).rejects.toMatchObject({ code: "unsupported_simulation_version" });
    }
  });
  it.each(cases)("fits the maximum four-record proof under existing wire and node limits ($adapter.key.level_id)", async fixture => {
    // Synthetic hashes test structural capacity only; native route acceptance
    // is covered by the separately exported normal and correction witnesses.
    const hash = "f".repeat(64);
    async function maximum(base: Record<string,unknown>, previous: ChapterCheckpoint, source = "") {
      const body = { ...base, checkpoint_hash:previous.checkpoint_hash, source_recording_hash:source, duration_ticks:900,catch_assistance:false,
        actions:Array.from({length:900},(_,i)=>({ticks:1,x:-100,z:i%2?-99:-100,action:false})),
        replay_checks:[{tick:1,state_hash:hash},...Array.from({length:30},(_,i)=>({tick:(i+1)*30,state_hash:hash}))],final_state_hash:hash };
      delete (body as Record<string,unknown>).recording_hash;
      return fixture.adapter.recording({...body,recording_hash:await digest(canonicalJson(body))});
    }
    async function next(base: Record<string,unknown>, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording) {
      return fixture.adapter.checkpoint(await rehash({...base,previous_checkpoint_hash:previous.checkpoint_hash,a_recording_hash:a.recording_hash,b_recording_hash:b.recording_hash,proof:{checkpoint:previous,a,b}}),previous,a,b);
    }
    const initial=fixture.adapter.initial(),a=await maximum(fixture.middle.proof.a,initial),b=await maximum(fixture.middle.proof.b,initial,a.recording_hash);
    const middle=await next(fixture.middle,initial,a,b),a2=await maximum(fixture.final.proof.a,middle),b2=await maximum(fixture.final.proof.b,middle,a2.recording_hash);
    const final=await next(fixture.final,middle,a2,b2),packet={base_revision:Number.MAX_SAFE_INTEGER,branch:31,idempotency_key:"k".repeat(80),recording:b2,checkpoint:final};
    for(const record of [a,b,a2,b2]) expect(()=>boundedValue(record,MAX_RECORDING_BYTES)).not.toThrow();
    expect(()=>boundedValue(final,MAX_CHECKPOINT_BYTES)).not.toThrow();expect(()=>boundedValue(packet,MAX_V2_BODY_BYTES)).not.toThrow();
    let nodes=0; const pending:unknown[]=[packet];
    while(pending.length){const value=pending.pop();nodes++;if(value!==null && typeof value==="object")pending.push(...Object.values(value));}
    expect(nodes).toBeLessThanOrEqual(24000);
    console.log("Journey maximum envelope",fixture.adapter.key.level_id,{bytes:new TextEncoder().encode(JSON.stringify(packet)).length,nodes});
    await expect(fixture.adapter.recording({...a,duration_ticks:901})).rejects.toMatchObject({code:"invalid_integer"});
  });
  it.each(cases)("uses the same durable roles, receipts, archive and fork lifecycle ($adapter.key.level_id)", async fixture => {
    const paired = await room(fixture.adapter); let current = paired.current;
    for (const [checkpoint, owners] of [[fixture.middle, [paired.host, paired.guest]], [fixture.final, [paired.guest, paired.host]]] as const) {
      for (const [index, recording] of [checkpoint.proof.a, checkpoint.proof.b].entries()) {
        const body = { base_revision: current.revision, branch: current.branch, idempotency_key: operationKey(), recording, ...(index ? { checkpoint } : {}) };
        const wrong = await call(`/v2/rooms/${current.room_id}/turns`, "POST", owners[1-index], body); expect(wrong.status).toBe(409);
        const response = await call(`/v2/rooms/${current.room_id}/turns`, "POST", owners[index], body); expect(response.status).toBe(200);
        const accepted = await response.json<MutationV2>();
        expect(await (await call(`/v2/rooms/${current.room_id}/turns`, "POST", owners[index], body)).json()).toEqual(accepted);
        current = accepted.room;
      }
    }
    expect(current.active_role).toBe("complete"); expect(current.checkpoint).toEqual(fixture.final);
    const stub = env.ROOMS_V2.getByName(current.room_id); await evictDurableObject(stub);
    expect(await (await call(`/v2/rooms/${current.room_id}`, "GET", paired.host)).json()).toEqual(current);
    const fork = await call(`/v2/rooms/${current.room_id}/fork`, "POST", paired.host, { base_revision: current.revision, branch: current.branch, stage_index: 1, idempotency_key: operationKey() });
    expect(fork.status).toBe(200); expect((await fork.json<MutationV2>()).room.checkpoint).toEqual(fixture.middle);
  });
  it.each(cases)("rejects rehashed foreign controls, lost latches and invalid endpoints ($adapter.key.level_id)", async fixture => {
    const checkpoint = fixture.final, a = await fixture.adapter.recording(checkpoint.proof.a), b = await fixture.adapter.recording(checkpoint.proof.b);
    const variants: Record<string, unknown>[] = [];
    const badControl = structuredClone(checkpoint); const control = Object.keys(badControl.mechanisms.controls)[0]; (badControl.mechanisms.controls as Record<string,string>)[control] = "invented"; variants.push(badControl);
    const oldControl = structuredClone(checkpoint); (oldControl.mechanisms.controls as Record<string,string>)[control] = "changed"; variants.push(oldControl);
    const lost = structuredClone(checkpoint); lost.mechanisms.latched_bridges.shift(); variants.push(lost);
    const future = structuredClone(checkpoint); future.mechanisms.latched_bridges.push("unknown-route"); future.mechanisms.latched_bridges.sort(); variants.push(future);
    const far = structuredClone(checkpoint); far.players.p1.x += 200; variants.push(far);
    for (const altered of variants) await expect(fixture.adapter.checkpoint(await rehash(altered), fixture.middle, a, b)).rejects.toBeDefined();
  });
});
