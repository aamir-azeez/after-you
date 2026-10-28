import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { chapter, checkpointV2, initialCheckpoint, recordingV2, acceptedRecording } from "../src/v2/protocol";
import { turnOfTheTide, turnOfTheTideV2, TURN_OF_THE_TIDE_HASH, TURN_OF_THE_TIDE_V2_HASH } from "../src/v2/protocol-journey";
import { advertisedChapters, chapterFlag, creatable } from "../src/v2/chapters";
import { comfortRules, type ChapterCheckpoint, type ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import definition from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-definition.json";
import initial from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-initial-checkpoint.json";
import setA from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-set-the-tide-a.json";
import setB from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-set-the-tide-b.json";
import middle from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-set-the-tide-checkpoint.json";
import slackA from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-slack-water-a.json";
import slackB from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-slack-water-b.json";
import slackFinal from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-slack-water-checkpoint.json";
import final from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-final-checkpoint.json";
import oneInitial from "../../game/tests/fixtures/journey/turn-of-the-tide-initial-checkpoint.json";
import oneSetA from "../../game/tests/fixtures/journey/set-the-tide-a.json";
import oneSetB from "../../game/tests/fixtures/journey/set-the-tide-b.json";
import oneMiddle from "../../game/tests/fixtures/journey/set-the-tide-checkpoint.json";
import oneSeaLockA from "../../game/tests/fixtures/journey/slack-water-a.json";
import oneSeaLockB from "../../game/tests/fixtures/journey/slack-water-b.json";
import oneSeaLockFinal from "../../game/tests/fixtures/journey/slack-water-checkpoint.json";
import bundledDefinition from "../src/v2/turn-of-the-tide-v2.json";
import bundledInitial from "../src/v2/turn-of-the-tide-v2-initial.json";
import { TIDE_CHAINS } from "./turn-of-the-tide-chains";

type Account = { player_id: string; device_token: string };
const key = () => crypto.randomUUID();
// 0.6.3 sends the first list, and the second to a room-level-2 server; neither offers 10.
const OLD_CLIENTS = [[2, 4, 5, 6, 7, 8], [2, 4, 5, 6, 7, 8, 9], [2, 4, 5, 6, 7, 8, 9, 11]], NEW_CLIENT = [2, 4, 5, 6, 7, 8, 9, 10, 11];
const ON = { TURN_OF_THE_TIDE_V2_CHAPTER_ENABLED: "true" };
const OTHERS_ON = { COOP_CHAPTERS_ENABLED: "true", HOUSE_CHAPTER_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: "true", FIRST_STEPS_ENABLED: "true",
  WISHING_WELL_CHAPTER_ENABLED: "true", LONG_WAY_HOME_V2_CHAPTER_ENABLED: "true", TURN_OF_THE_TIDE_CHAPTER_ENABLED: "true", LIGHTHOUSE_V2_CHAPTER_ENABLED: "true" };
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true", ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.13." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function submit(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  const body = { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
  const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, body, ON); expect(response.status).toBe(200); return response.json<MutationV2>();
}
async function rehash(input: Record<string, unknown>): Promise<Record<string, unknown>> {
  const body = { ...input }; delete body.checkpoint_hash; delete body.proof;
  return { ...input, checkpoint_hash: await digest(canonicalJson(body)) };
}
async function records(a: unknown, b: unknown, adapter = turnOfTheTideV2): Promise<[ChapterRecording, ChapterRecording]> {
  return [await recordingV2(a, adapter.key) as ChapterRecording, await recordingV2(b, adapter.key) as ChapterRecording];
}
async function stageOne(): Promise<ChapterCheckpoint> {
  const [a, b] = await records(setA, setB);
  return checkpointV2(middle, initialCheckpoint(turnOfTheTideV2.key) as ChapterCheckpoint, a, b);
}
afterEach(async () => { await reset(); });

describe("Turn of the Tide version 2 (free, tide rules 10, behind its own flag)", () => {
  it("bundles the exact native definition and initial checkpoint beside @1", async () => {
    expect(bundledDefinition).toEqual(definition); expect(bundledInitial).toEqual(initial);
    expect(await digest(canonicalJson(definition))).toBe(TURN_OF_THE_TIDE_V2_HASH);
    expect(TURN_OF_THE_TIDE_V2_HASH).toBe("1f88aabb592fbf14640b50dd0644755d6afe522cae39d844524ac68b491f0a43");
    expect(initial.checkpoint_hash).toBe("f04821b57f741e692fa350265b24d41d27037026209f8c16f7ef70d4546712e9");
    expect(definition.simulation_version).toBe(10);
    expect(turnOfTheTideV2.key).toEqual({ level_id: "turn-of-the-tide", level_version: 2, definition_hash: TURN_OF_THE_TIDE_V2_HASH });
    expect(turnOfTheTideV2).toMatchObject({ premium: false, recording_version: 7, simulation_version: 10, supported_simulation_versions: [10], require_supported_simulation_on_join: true, max_branches: 7 });
    expect(turnOfTheTideV2.limits).toEqual(turnOfTheTide.limits);
    expect(chapter(turnOfTheTideV2.key)).toBe(turnOfTheTideV2); expect(initialCheckpoint(turnOfTheTideV2.key)).toEqual(initial);
    expect(chapter(turnOfTheTide.key)).toBe(turnOfTheTide);
    expect(turnOfTheTide).toMatchObject({ key: { level_version: 1, definition_hash: TURN_OF_THE_TIDE_HASH }, simulation_version: 9, supported_simulation_versions: [9] });
    // Rules 10 records carry the comfort bounds; no other chapter offers 10.
    expect(comfortRules(10)).toBe(true);
  });
  it("stays off by default: not advertised and not creatable", async () => {
    expect(env.TURN_OF_THE_TIDE_V2_CHAPTER_ENABLED).toBeUndefined();
    expect(chapterFlag(turnOfTheTideV2)).toBe("TURN_OF_THE_TIDE_V2_CHAPTER_ENABLED");
    expect(creatable(turnOfTheTideV2, env)).toBe(false);
    const allOthers: Env = { ...env }; Object.assign(allOthers, OTHERS_ON);
    expect(creatable(turnOfTheTideV2, allOthers)).toBe(false);
    for (const level of [1, 2]) {
      expect(advertisedChapters(allOthers, level).filter(entry => entry.level_id === "turn-of-the-tide").map(entry => [entry.level_version, entry.definition_hash])).toEqual([[1, TURN_OF_THE_TIDE_HASH]]);
    }
    const host = await account();
    const refused = await call("/v2/rooms", "POST", host, { ...turnOfTheTideV2.key, idempotency_key: key() }, OTHERS_ON);
    expect(refused.status).toBe(503); expect(await refused.json()).toMatchObject({ error: { code: "chapter_creation_disabled" } });
  });
  it("advertises exactly its pinned rules, free, when the flag is on, after every older row", async () => {
    const on: Env = { ...env }; Object.assign(on, OTHERS_ON, ON);
    expect(creatable(turnOfTheTideV2, on)).toBe(true);
    const entry = { ...turnOfTheTideV2.key, premium: false, recording_version: 7, simulation_version: 10, supported_simulation_versions: [10] };
    expect(advertisedChapters(on).at(-1)).toEqual(entry);
    expect(advertisedChapters(on, 2).at(-1)).toEqual({ ...entry, stage_count: 2 });
    expect(advertisedChapters(on).filter(item => item.level_id === "turn-of-the-tide").map(item => item.level_version)).toEqual([1, 2]);
  });
  it("accepts the native chain: a stage ending on an open stub, with no route latched", async () => {
    const start = initialCheckpoint(turnOfTheTideV2.key) as ChapterCheckpoint;
    const [a1, b1] = await records(setA, setB);
    expect(a1).toEqual(setA); expect(b1).toEqual(setB); expect(acceptedRecording(a1) && acceptedRecording(b1)).toBe(true);
    const first = await checkpointV2(middle, start, a1, b1); expect(first).toEqual(middle);
    const [a2, b2] = await records(slackA, slackB);
    expect(a2).toEqual(slackA); expect(b2).toEqual(slackB); expect(acceptedRecording(a2) && acceptedRecording(b2)).toBe(true);
    expect(await checkpointV2(slackFinal, first, a2, b2)).toEqual(slackFinal);
    expect(final).toEqual(slackFinal);
    // The paths only rules 10 opens: each stage ends with a player on a stub, and nothing is latched.
    for (const checkpoint of [initial, middle, slackFinal]) expect(checkpoint.mechanisms.latched_bridges).toEqual([]);
    expect(middle.players.p0.surface_id).toBe("wheel-step"); expect(slackFinal.players.p1.surface_id).toBe("gate-post");
  });
  it("refuses a latched route at either stage", async () => {
    const start = initialCheckpoint(turnOfTheTideV2.key) as ChapterCheckpoint;
    const [a1, b1] = await records(setA, setB);
    // wheel-step is one of this stage's gates, so only the no-latch rule refuses it.
    for (const latched of [["wheel-step"], ["sand-1"], ["w-steps-low"]]) {
      const kept = structuredClone(middle) as Record<string, any>; kept.mechanisms.latched_bridges = latched;
      await expect(checkpointV2(await rehash(kept), start, a1, b1), latched[0]).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
    }
    const first = await stageOne(), [a2, b2] = await records(slackA, slackB);
    for (const latched of [["gate-post"], ["towpath"]]) {
      const kept = structuredClone(slackFinal) as Record<string, any>; kept.mechanisms.latched_bridges = latched;
      await expect(checkpointV2(await rehash(kept), first, a2, b2), latched[0]).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
    }
  });
  it("refuses a player on a stub whose gate does not hold, or that this stage does not gate", async () => {
    const start = initialCheckpoint(turnOfTheTideV2.key) as ChapterCheckpoint;
    const [a1, b1] = await records(setA, setB);
    // The wheel step is open only at low water with the winch out and the sluice on.
    const halfTide = structuredClone(middle) as Record<string, any>; halfTide.mechanisms.controls.tide = "half";
    await expect(checkpointV2(await rehash(halfTide), start, a1, b1)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    const stowed = structuredClone(middle) as Record<string, any>; stowed.mechanisms.controls.winch = "stowed";
    await expect(checkpointV2(await rehash(stowed), start, a1, b1)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    const noSluice = structuredClone(middle) as Record<string, any>; noSluice.mechanisms.levers = {};
    await expect(checkpointV2(await rehash(noSluice), start, a1, b1)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    // The towpath is gated only in the second stage.
    const towpath = structuredClone(middle) as Record<string, any>; towpath.players.p0 = { x: 384, z: 400, height: 0, surface_id: "towpath" };
    await expect(checkpointV2(await rehash(towpath), start, a1, b1)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    const first = await stageOne(), [a2, b2] = await records(slackA, slackB);
    // At a half basin the gate post is under water.
    const halfBasin = structuredClone(slackFinal) as Record<string, any>; halfBasin.mechanisms.controls.basin = "half";
    await expect(checkpointV2(await rehash(halfBasin), first, a2, b2)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    const noBar = structuredClone(slackFinal) as Record<string, any>; noBar.mechanisms.levers["sea-bar"] = false;
    await expect(checkpointV2(await rehash(noBar), first, a2, b2)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    // The boom post needs the boom chain, which this end state never pulled.
    const boomPost = structuredClone(slackFinal) as Record<string, any>; boomPost.players.p1 = { x: -268, z: 160, height: 48, surface_id: "boom-post" };
    await expect(checkpointV2(await rehash(boomPost), first, a2, b2)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
  });
  it("refuses other rules and the other version's records", async () => {
    const renumbered = { ...setA, simulation_version: 9 }; const { recording_hash: _hash, ...body } = renumbered; void _hash;
    await expect(recordingV2({ ...renumbered, recording_hash: await digest(canonicalJson(body)) }, turnOfTheTideV2.key)).rejects.toMatchObject({ code: "unsupported_simulation_version" });
    await expect(recordingV2(oneSetA, turnOfTheTideV2.key)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
    await expect(recordingV2(setA, turnOfTheTide.key)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
  });
  it("leaves @1 as it was: its own chain still passes, and a stub there must still be latched", async () => {
    const start = initialCheckpoint(turnOfTheTide.key) as ChapterCheckpoint;
    expect(start).toEqual(oneInitial);
    const [a1, b1] = await records(oneSetA, oneSetB, turnOfTheTide);
    const first = await checkpointV2(oneMiddle, start, a1, b1); expect(first).toEqual(oneMiddle);
    const [a2, b2] = await records(oneSeaLockA, oneSeaLockB, turnOfTheTide);
    expect(await checkpointV2(oneSeaLockFinal, first, a2, b2)).toEqual(oneSeaLockFinal);
    const [halfA, halfB, halfEnd] = TIDE_CHAINS.half.set;
    const [ha, hb] = await records(halfA, halfB, turnOfTheTide);
    expect(await checkpointV2(halfEnd, start, ha, hb)).toEqual(halfEnd);
    const unlatched = structuredClone(halfEnd) as Record<string, any>;
    expect(unlatched.players.p0.surface_id).toBe("quay-step");
    unlatched.mechanisms.latched_bridges = unlatched.mechanisms.latched_bridges.filter((route: string) => route !== "quay-step");
    await expect(checkpointV2(await rehash(unlatched), start, ha, hb)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
  });
  it("refuses a guest whose client never offered rules 10, and plays both stages to completion", async () => {
    const host = await account(), oldGuest = await account(), guest = await account();
    const created = await call("/v2/rooms", "POST", host, { ...turnOfTheTideV2.key, idempotency_key: key() }, ON);
    expect(created.status).toBe(200);
    const room = await created.json<RoomSnapshotV2>();
    expect(room).not.toHaveProperty("simulation_version");
    for (const versions of [undefined, ...OLD_CLIENTS]) {
      const rejected = await call("/v2/rooms/join", "POST", oldGuest, { invite_code: room.invite_code, ...(versions ? { supported_simulation_versions: versions } : {}) }, ON);
      expect(rejected.status).toBe(422); expect(await rejected.json()).toMatchObject({ error: { code: "unsupported_simulation_version" } });
    }
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: NEW_CLIENT }, ON);
    expect(joined.status).toBe(200);
    const a = await submit(await joined.json<RoomSnapshotV2>(), host, setA), b = await submit(a.room, guest, setB, middle);
    expect(b.room).toMatchObject({ stage_index: 1, active_player_id: guest.player_id, checkpoint: middle });
    const c = await submit(b.room, guest, slackA), d = await submit(c.room, host, slackB, slackFinal);
    expect(d.room).toMatchObject({ stage_index: 2, active_role: "complete", checkpoint: slackFinal });
  });
});
