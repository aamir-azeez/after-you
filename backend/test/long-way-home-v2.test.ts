import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { chapter, checkpointV2, initialCheckpoint, recordingV2, acceptedRecording, boundedTurnValue } from "../src/v2/protocol";
import { longWayHome, longWayHomeV2, LONG_WAY_HOME_HASH, LONG_WAY_HOME_V2_HASH } from "../src/v2/protocol-journey";
import { advertisedChapters, creatable } from "../src/v2/chapters";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import definition from "../../game/tests/fixtures/journey/long-way-home-v2-definition.json";
import initial from "../../game/tests/fixtures/journey/long-way-home-v2-initial-checkpoint.json";
import pathA from "../../game/tests/fixtures/journey/long-way-home-v2-the-path-you-leave-a.json";
import pathB from "../../game/tests/fixtures/journey/long-way-home-v2-the-path-you-leave-b.json";
import middle from "../../game/tests/fixtures/journey/long-way-home-v2-the-path-you-leave-checkpoint.json";
import porchA from "../../game/tests/fixtures/journey/long-way-home-v2-a-place-beside-you-a.json";
import porchB from "../../game/tests/fixtures/journey/long-way-home-v2-a-place-beside-you-b.json";
import porchFinal from "../../game/tests/fixtures/journey/long-way-home-v2-final-checkpoint.json";
import gardenA from "../../game/tests/fixtures/journey/long-way-home-v2-garden-a.json";
import gardenB from "../../game/tests/fixtures/journey/long-way-home-v2-garden-b.json";
import gardenFinal from "../../game/tests/fixtures/journey/long-way-home-v2-garden-checkpoint.json";
import latestA from "../../game/tests/fixtures/journey/long-way-home-v2-latest-a.json";
import latestB from "../../game/tests/fixtures/journey/long-way-home-v2-latest-b.json";
import latestFinal from "../../game/tests/fixtures/journey/long-way-home-v2-latest-checkpoint.json";
import oldPathA from "../../game/tests/fixtures/journey/the-path-you-leave-a.json";
import bundledDefinition from "../src/v2/long-way-home-v2.json";
import bundledInitial from "../src/v2/long-way-home-v2-initial.json";

type Account = { player_id: string; device_token: string };
const key = () => crypto.randomUUID(), CODE = "SYNTHETIC-HOME-V2-HOST";
const OLD_CLIENT = [2, 4, 5, 6, 7, 8], NEW_CLIENT = [2, 4, 5, 6, 7, 8, 9];
const ON = { LONG_WAY_HOME_V2_CHAPTER_ENABLED: "true" };
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}): Promise<Response> {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE),
    REVENUECAT_VERIFICATION_MODE: "play_store", REVENUECAT_SECRET_KEY: "synthetic-only", REVENUECAT_PROJECT_ID: "projSynthetic", REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID: "entlPlay", REVENUECAT_PLAY_PRODUCT_ID: "prodPlay", REVENUECAT_PLAY_ENVIRONMENT: "production", ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.11." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function grant(owner: Account) { expect((await call("/v1/tester-access", "POST", owner, { schema_version: 1, code: CODE })).status).toBe(200); }
async function submit(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  const body = { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
  const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, body, ON); expect(response.status).toBe(200); return response.json<MutationV2>();
}
async function rehash(input: Record<string, unknown>): Promise<Record<string, unknown>> {
  const body = { ...input }; delete body.checkpoint_hash; delete body.proof;
  return { ...input, checkpoint_hash: await digest(canonicalJson(body)) };
}
afterEach(async () => { await reset(); });

describe("Long Way Home version 2 (paid, rules 9, behind its own flag)", () => {
  it("bundles the exact native definition and initial checkpoint beside @1", async () => {
    expect(bundledDefinition).toEqual(definition); expect(bundledInitial).toEqual(initial);
    expect(await digest(canonicalJson(definition))).toBe(LONG_WAY_HOME_V2_HASH);
    expect(longWayHomeV2.key).toEqual({ level_id: "long-way-home", level_version: 2, definition_hash: LONG_WAY_HOME_V2_HASH });
    expect(longWayHomeV2).toMatchObject({ premium: true, recording_version: 7, simulation_version: 9, supported_simulation_versions: [9], require_supported_simulation_on_join: true });
    expect(chapter(longWayHomeV2.key)).toBe(longWayHomeV2); expect(initialCheckpoint(longWayHomeV2.key)).toEqual(initial);
    expect(chapter(longWayHome.key)).toBe(longWayHome);
    expect(longWayHome).toMatchObject({ key: { level_version: 1, definition_hash: LONG_WAY_HOME_HASH }, simulation_version: 7, supported_simulation_versions: [7, 8] });
  });
  it("stays off by default: not advertised and not creatable", async () => {
    expect(env.LONG_WAY_HOME_V2_CHAPTER_ENABLED).toBeUndefined();
    expect(creatable(longWayHomeV2, env)).toBe(false);
    const allOn: Env = { ...env }; Object.assign(allOn, { COOP_CHAPTERS_ENABLED: "true", HOUSE_CHAPTER_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: "true", FIRST_STEPS_ENABLED: "true", WISHING_WELL_CHAPTER_ENABLED: "true" });
    expect(advertisedChapters(allOn).filter(entry => entry.level_id === "long-way-home").map(entry => entry.level_version)).toEqual([1]);
    const host = await account(); await grant(host);
    const refused = await call("/v2/rooms", "POST", host, { ...longWayHomeV2.key, idempotency_key: key() });
    expect(refused.status).toBe(503); expect(await refused.json()).toMatchObject({ error: { code: "chapter_creation_disabled" } });
  });
  it("advertises exactly its pinned rules when the flag is on", async () => {
    const on: Env = { ...env }; Object.assign(on, ON);
    expect(advertisedChapters(on).find(entry => entry.level_id === "long-way-home" && entry.level_version === 2)).toEqual({ ...longWayHomeV2.key, premium: true, recording_version: 7, simulation_version: 9, supported_simulation_versions: [9] });
  });
  it("accepts every native way to win, including a receiver past 900 ticks", async () => {
    const start = initialCheckpoint(longWayHomeV2.key) as ChapterCheckpoint;
    const [a1, b1] = await Promise.all([pathA, pathB].map(record => recordingV2(record, longWayHomeV2.key))) as ChapterRecording[];
    expect(acceptedRecording(a1) && acceptedRecording(b1)).toBe(true);
    const first = await checkpointV2(middle, start, a1, b1); expect(first).toEqual(middle);
    for (const [a, b, final] of [[porchA, porchB, porchFinal], [gardenA, gardenB, gardenFinal], [latestA, latestB, latestFinal]]) {
      const ra = await recordingV2(a, longWayHomeV2.key) as ChapterRecording, rb = await recordingV2(b, longWayHomeV2.key) as ChapterRecording;
      expect(ra).toEqual(a); expect(rb).toEqual(b); expect(acceptedRecording(ra) && acceptedRecording(rb)).toBe(true);
      expect(await checkpointV2(final, first, ra, rb)).toEqual(final);
    }
    expect(latestB.duration_ticks).toBeGreaterThan(900);
    expect(() => boundedTurnValue({ schema_version: 2, recording: latestB, checkpoint: latestFinal })).not.toThrow();
  });
  it("refuses other rules, the other version's records and end states the native proof could not make", async () => {
    const renumbered = { ...pathA, simulation_version: 8 }; const { recording_hash: _hash, ...body } = renumbered; void _hash;
    await expect(recordingV2({ ...renumbered, recording_hash: await digest(canonicalJson(body)) }, longWayHomeV2.key)).rejects.toMatchObject({ code: "unsupported_simulation_version" });
    await expect(recordingV2(oldPathA, longWayHomeV2.key)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
    await expect(recordingV2(pathA, longWayHome.key)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
    const start = initialCheckpoint(longWayHomeV2.key) as ChapterCheckpoint;
    const a1 = await recordingV2(pathA, longWayHomeV2.key) as ChapterRecording, b1 = await recordingV2(pathB, longWayHomeV2.key) as ChapterRecording;
    const first = await checkpointV2(middle, start, a1, b1);
    const a = await recordingV2(gardenA, longWayHomeV2.key) as ChapterRecording, b = await recordingV2(gardenB, longWayHomeV2.key) as ChapterRecording;
    const wrongGate = structuredClone(gardenFinal) as Record<string, any>; wrongGate.mechanisms.controls["walk-gate"] = "rose";
    await expect(checkpointV2(await rehash(wrongGate), first, a, b)).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    const awayFromSeat = structuredClone(gardenFinal) as Record<string, any>; awayFromSeat.players.p1 = { ...awayFromSeat.players.p1, z: 88 };
    await expect(checkpointV2(await rehash(awayFromSeat), first, a, b)).rejects.toMatchObject({ code: "checkpoint_source_position_mismatch" });
  });
  it("refuses a 0.5.x guest before the seat is taken, and plays both stages to completion", async () => {
    const host = await account(), oldGuest = await account(), guest = await account(); await grant(host);
    const created = await call("/v2/rooms", "POST", host, { ...longWayHomeV2.key, idempotency_key: key() }, ON);
    expect(created.status).toBe(200);
    const room = await created.json<RoomSnapshotV2>();
    expect(room).not.toHaveProperty("simulation_version");
    for (const versions of [undefined, OLD_CLIENT]) {
      const rejected = await call("/v2/rooms/join", "POST", oldGuest, { invite_code: room.invite_code, ...(versions ? { supported_simulation_versions: versions } : {}) }, ON);
      expect(rejected.status).toBe(422); expect(await rejected.json()).toMatchObject({ error: { code: "unsupported_simulation_version" } });
    }
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: NEW_CLIENT }, ON);
    expect(joined.status).toBe(200);
    const seated = await joined.json<RoomSnapshotV2>();
    const a = await submit(seated, host, pathA), b = await submit(a.room, guest, pathB, middle);
    expect(b.room).toMatchObject({ stage_index: 1, active_player_id: guest.player_id, checkpoint: middle });
    const c = await submit(b.room, guest, gardenA), d = await submit(c.room, host, gardenB, gardenFinal);
    expect(d.room).toMatchObject({ stage_index: 2, active_role: "complete", checkpoint: gardenFinal });
  });
});
