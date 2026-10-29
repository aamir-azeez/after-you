import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { withConfig } from "./config";
import { canonicalJson, digest } from "../src/protocol";
import { chapter, checkpointV2, initialCheckpoint, recordingV2, acceptedRecording, boundedTurnValue, boundedValue, MAX_CHECKPOINT_BYTES, MAX_V2_BODY_BYTES } from "../src/v2/protocol";
import { physicalRecording, scaledLimits } from "../src/v2/protocol-physical-recording";
import { conservatory, longWayHome, longWayHomeV2, turnOfTheTide, TURN_OF_THE_TIDE_HASH } from "../src/v2/protocol-journey";
import { advertisedChapters, creatable } from "../src/v2/chapters";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import definition from "../../game/tests/fixtures/journey/turn-of-the-tide-definition.json";
import initial from "../../game/tests/fixtures/journey/turn-of-the-tide-initial-checkpoint.json";
import setA from "../../game/tests/fixtures/journey/set-the-tide-a.json";
import setB from "../../game/tests/fixtures/journey/set-the-tide-b.json";
import middle from "../../game/tests/fixtures/journey/set-the-tide-checkpoint.json";
import seaLockA from "../../game/tests/fixtures/journey/slack-water-a.json";
import seaLockB from "../../game/tests/fixtures/journey/slack-water-b.json";
import seaLockFinal from "../../game/tests/fixtures/journey/slack-water-checkpoint.json";
import boomA from "../../game/tests/fixtures/journey/slack-water-boom-a.json";
import boomB from "../../game/tests/fixtures/journey/slack-water-boom-b.json";
import boomFinal from "../../game/tests/fixtures/journey/slack-water-boom-checkpoint.json";
import puntA from "../../game/tests/fixtures/journey/slack-water-punt-a.json";
import puntB from "../../game/tests/fixtures/journey/slack-water-punt-b.json";
import puntFinal from "../../game/tests/fixtures/journey/slack-water-punt-checkpoint.json";
import latestA from "../../game/tests/fixtures/journey/slack-water-latest-a.json";
import latestB from "../../game/tests/fixtures/journey/slack-water-latest-b.json";
import latestFinal from "../../game/tests/fixtures/journey/slack-water-latest-checkpoint.json";
import final from "../../game/tests/fixtures/journey/turn-of-the-tide-final-checkpoint.json";
import homeV2PathA from "../../game/tests/fixtures/journey/long-way-home-v2-the-path-you-leave-a.json";
import bundledDefinition from "../src/v2/turn-of-the-tide.json";
import bundledInitial from "../src/v2/turn-of-the-tide-initial.json";
import { TIDE_CHAINS } from "./turn-of-the-tide-chains";

type Account = { player_id: string; device_token: string };
const key = () => crypto.randomUUID();
const OLD_CLIENT = [2, 4, 5, 6, 7, 8], NEW_CLIENT = [2, 4, 5, 6, 7, 8, 9];
const ON = {};
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}): Promise<Response> {
  const configured: Env = withConfig({ ...env, ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.12." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function submit(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  const body = { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
  const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, body, ON); expect(response.status).toBe(200); return response.json<MutationV2>();
}
/** `record` at `ticks` with `checks` replay checks, every action entry at its
 * widest when `widest`, else idling to the end; rehashed. Only the structure is valid. */
async function stretched(record: Record<string, any>, ticks: number, checks = Math.floor(ticks / 30) + 1, widest = false): Promise<Record<string, any>> {
  const body: Record<string, any> = structuredClone(record); delete body.recording_hash;
  if (widest) body.actions = Array.from({ length: ticks }, (_, index) => ({ action: false, ticks: 1, x: -100, z: index % 2 ? -99 : -100 }));
  else body.actions.push({ action: false, ticks: ticks - body.duration_ticks, x: 0, z: 0 });
  body.duration_ticks = ticks;
  body.replay_checks = Array.from({ length: checks }, (_, index) => ({ tick: index + 1 === checks ? ticks : index + 1, state_hash: body.final_state_hash }));
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}
/** The stage-2 checkpoint with every action entry of its four records at the
 * widest form and the turn's whole cap: the most a real one can carry. */
function widestCheckpoint(checkpoint: Record<string, any>): Record<string, any> {
  const widest = structuredClone(checkpoint);
  for (const record of [widest.proof.a, widest.proof.b, widest.proof.checkpoint.proof.a, widest.proof.checkpoint.proof.b]) {
    const ticks = record.role === "a" ? 2700 : 3000;
    record.actions = Array.from({ length: ticks }, (_, index) => ({ action: false, ticks: 1, x: -100, z: index % 2 ? -99 : -100 }));
    record.duration_ticks = ticks;
  }
  return widest;
}
async function rehash(input: Record<string, unknown>): Promise<Record<string, unknown>> {
  const body = { ...input }; delete body.checkpoint_hash; delete body.proof;
  return { ...input, checkpoint_hash: await digest(canonicalJson(body)) };
}
async function stageOne(): Promise<ChapterCheckpoint> {
  const start = initialCheckpoint(turnOfTheTide.key) as ChapterCheckpoint;
  const a = await recordingV2(setA, turnOfTheTide.key) as ChapterRecording, b = await recordingV2(setB, turnOfTheTide.key) as ChapterRecording;
  return checkpointV2(middle, start, a, b);
}
afterEach(async () => { await reset(); });

describe("Turn of the Tide (free, rules 9, behind its own flag)", () => {
  it("bundles the exact native definition and initial checkpoint", async () => {
    expect(bundledDefinition).toEqual(definition); expect(bundledInitial).toEqual(initial);
    expect(await digest(canonicalJson(definition))).toBe(TURN_OF_THE_TIDE_HASH);
    expect(turnOfTheTide.key).toEqual({ level_id: "turn-of-the-tide", level_version: 1, definition_hash: TURN_OF_THE_TIDE_HASH });
    expect(turnOfTheTide).toMatchObject({ premium: false, recording_version: 7, simulation_version: 9, supported_simulation_versions: [9], require_supported_simulation_on_join: true });
    expect(chapter(turnOfTheTide.key)).toBe(turnOfTheTide); expect(initialCheckpoint(turnOfTheTide.key)).toEqual(initial);
  });
  it("takes premium from each definition, so the paid journeys stay paid", () => {
    expect(definition.premium).toBe(false);
    for (const paid of [conservatory, longWayHome, longWayHomeV2]) expect(paid.premium).toBe(true);
  });
  it("advertises exactly its pinned rules, free", async () => {
    const on: Env = withConfig({ ...env });
    expect(creatable(turnOfTheTide, on)).toBe(true);
    expect(advertisedChapters(on).find(entry => entry.level_id === "turn-of-the-tide")).toEqual({ ...turnOfTheTide.key, premium: false, recording_version: 7, simulation_version: 9, supported_simulation_versions: [9] });
  });
  it("accepts every native way to win, including a first turn past 900 ticks and a receiver past 2,700", async () => {
    const start = initialCheckpoint(turnOfTheTide.key) as ChapterCheckpoint;
    const [a1, b1] = await Promise.all([setA, setB].map(record => recordingV2(record, turnOfTheTide.key))) as ChapterRecording[];
    expect(a1).toEqual(setA); expect(b1).toEqual(setB); expect(acceptedRecording(a1) && acceptedRecording(b1)).toBe(true);
    const first = await checkpointV2(middle, start, a1, b1); expect(first).toEqual(middle);
    for (const [a, b, end] of [[seaLockA, seaLockB, seaLockFinal], [boomA, boomB, boomFinal], [puntA, puntB, puntFinal], [latestA, latestB, latestFinal]]) {
      const ra = await recordingV2(a, turnOfTheTide.key) as ChapterRecording, rb = await recordingV2(b, turnOfTheTide.key) as ChapterRecording;
      expect(ra).toEqual(a); expect(rb).toEqual(b); expect(acceptedRecording(ra) && acceptedRecording(rb)).toBe(true);
      expect(await checkpointV2(end, first, ra, rb)).toEqual(end);
    }
    expect(final).toEqual(seaLockFinal);
    expect(latestA.duration_ticks).toBeGreaterThan(900); expect(latestB.duration_ticks).toBeGreaterThan(2700);
    expect(() => boundedTurnValue({ schema_version: 2, recording: latestB, checkpoint: latestFinal }, turnOfTheTide.limits)).not.toThrow();
    // Every other native chain: HALF, HIGH and two stage-1 variants, each from
    // its own stage-1 checkpoint through all three ways.
    expect(Object.keys(TIDE_CHAINS)).toEqual(["half", "high", "low-half-first-stones", "half-winch"]);
    for (const [name, chain] of Object.entries(TIDE_CHAINS)) {
      const [setOneA, setOneB, setOneEnd] = chain.set;
      const [ra1, rb1] = await Promise.all([setOneA, setOneB].map(record => recordingV2(record, turnOfTheTide.key))) as ChapterRecording[];
      expect(ra1, name).toEqual(setOneA); expect(rb1, name).toEqual(setOneB); expect(acceptedRecording(ra1) && acceptedRecording(rb1)).toBe(true);
      const chainFirst = await checkpointV2(setOneEnd, start, ra1, rb1); expect(chainFirst, name).toEqual(setOneEnd);
      expect(Object.keys(chain.ways)).toEqual(["boom", "sea-lock", "punt"]);
      for (const [way, [a, b, end]] of Object.entries(chain.ways)) {
        const ra = await recordingV2(a, turnOfTheTide.key) as ChapterRecording, rb = await recordingV2(b, turnOfTheTide.key) as ChapterRecording;
        expect(ra, name + " " + way).toEqual(a); expect(rb, name + " " + way).toEqual(b); expect(acceptedRecording(ra) && acceptedRecording(rb)).toBe(true);
        expect(await checkpointV2(end, chainFirst, ra, rb), name + " " + way).toEqual(end);
      }
    }
  });
  it("reaches the adapter paths the LOW chain never does", () => {
    type End = { players: Record<string, { surface_id: string }>; mechanisms: { latched_bridges: string[]; controls: Record<string, string>; levers: Record<string, boolean> } };
    const end = (name: string) => TIDE_CHAINS[name].set[2] as End;
    // A ends stage 1 off the islands, on a latched waiting step.
    expect(end("half").players.p0.surface_id).toBe("quay-step"); expect(end("high").players.p0.surface_id).toBe("bollard-step");
    expect(end("half").mechanisms.latched_bridges).toContain("quay-step"); expect(end("high").mechanisms.latched_bridges).toContain("bollard-step");
    // jetty-3 reads the bollard pad from the final positions; the lock is kept east.
    expect(end("high").mechanisms.latched_bridges).toContain("jetty-3");
    expect(end("half").mechanisms.latched_bridges).toContain("lock-east"); expect(end("low-half-first-stones").mechanisms.latched_bridges).toContain("lock-east");
    expect(end("low-half-first-stones").mechanisms.latched_bridges).toEqual(expect.arrayContaining(["slipway", "stones-1", "stones-2", "stones-3", "lock-east"]));
    // A stowed winch and the line and gangway levers are held through stage 2.
    expect(end("half").mechanisms.controls.winch).toBe("stowed"); expect(end("half-winch").mechanisms.controls.winch).toBe("slip");
    expect(end("high").mechanisms.levers).toMatchObject({ line: true, gangway: true });
    for (const way of Object.values(TIDE_CHAINS.high.ways)) {
      const done = way[2] as End;
      expect(done.mechanisms.controls.winch).toBe("stowed"); expect(done.mechanisms.levers).toMatchObject({ line: true, gangway: true });
    }
  });
  it("reads controls by id: the repeated tide and lock are listed once, and only a stage's own controls move", async () => {
    const ids = definition.stages.flatMap(stage => stage.controls.map(control => control.id));
    expect(ids.filter(id => id === "tide").length).toBe(2); expect(ids.filter(id => id === "lock").length).toBe(2);
    expect(Object.keys(middle.mechanisms.controls).sort()).toEqual(["basin", "chamber", "lock", "tide", "winch"]);
    // Stage 1 leaves the sea and the chamber where they started; stage 2 keeps the winch.
    expect(middle.mechanisms.controls).toMatchObject({ chamber: "half", basin: "shut" });
    expect(seaLockFinal.mechanisms.controls.winch).toBe(middle.mechanisms.controls.winch);
    // p0 turns the shared tide wheel in stage 2.
    expect(seaLockFinal.mechanisms.controls.tide).not.toBe(middle.mechanisms.controls.tide);
    const start = initialCheckpoint(turnOfTheTide.key) as ChapterCheckpoint;
    const a1 = await recordingV2(setA, turnOfTheTide.key) as ChapterRecording, b1 = await recordingV2(setB, turnOfTheTide.key) as ChapterRecording;
    const earlySea = structuredClone(middle) as Record<string, any>; earlySea.mechanisms.controls.basin = "low";
    await expect(checkpointV2(await rehash(earlySea), start, a1, b1)).rejects.toMatchObject({ code: "checkpoint_control_mismatch" });
    const earlyChamber = structuredClone(middle) as Record<string, any>; earlyChamber.mechanisms.controls.chamber = "low";
    await expect(checkpointV2(await rehash(earlyChamber), start, a1, b1)).rejects.toMatchObject({ code: "checkpoint_control_mismatch" });
    const first = await stageOne();
    const a = await recordingV2(seaLockA, turnOfTheTide.key) as ChapterRecording, b = await recordingV2(seaLockB, turnOfTheTide.key) as ChapterRecording;
    const lateWinch = structuredClone(seaLockFinal) as Record<string, any>; lateWinch.mechanisms.controls.winch = lateWinch.mechanisms.controls.winch === "slip" ? "stowed" : "slip";
    await expect(checkpointV2(await rehash(lateWinch), first, a, b)).rejects.toMatchObject({ code: "checkpoint_control_mismatch" });
    const missing = structuredClone(seaLockFinal) as Record<string, any>; delete missing.mechanisms.controls.basin;
    await expect(checkpointV2(await rehash(missing), first, a, b)).rejects.toMatchObject({ code: "unexpected_fields" });
    // A control value must be a string: ["high"] would pass a coerced value
    // check but read as unset in every gate.
    for (const id of ["tide", "basin", "winch"]) {
      const wrapped = structuredClone(seaLockFinal) as Record<string, any>; wrapped.mechanisms.controls[id] = [wrapped.mechanisms.controls[id]];
      await expect(checkpointV2(await rehash(wrapped), first, a, b)).rejects.toMatchObject({ code: "checkpoint_control_mismatch" });
    }
  });
  it("takes 2,700 ticks for A and 3,000 for B from its definition, with bounds grown to fit", async () => {
    expect(definition.turn_limits).toEqual({ a_ticks: 2700, b_ticks: 3000 });
    expect(turnOfTheTide.limits).toEqual(scaledLimits({ a_ticks: 2700, b_ticks: 3000 }));
    expect(turnOfTheTide.limits).toEqual({ recording_bytes: 196_608, recording_values: 72_000, checkpoint_bytes: 688_128, checkpoint_values: 72_000, turn_body_bytes: 983_040, turn_body_values: 96_000 });
    expect(turnOfTheTide.max_branches).toBe(7);
    // Each role's cap, and one replay check a second plus the last.
    for (const [record, ticks] of [[setA, 2700], [setB, 3000]] as const) {
      const most = Math.floor(ticks / 30) + 1;
      const fits = await stretched(record, ticks);
      expect(await recordingV2(fits, turnOfTheTide.key)).toEqual(fits);
      await expect(recordingV2(await stretched(record, ticks + 1), turnOfTheTide.key)).rejects.toMatchObject({ code: "invalid_integer" });
      await expect(recordingV2(await stretched(record, ticks, most + 1), turnOfTheTide.key)).rejects.toMatchObject({ code: "invalid_replay_checks" });
    }
    // A first turn may not take the receiver's longer cap.
    await expect(recordingV2(await stretched(setA, 3000), turnOfTheTide.key)).rejects.toMatchObject({ code: "invalid_integer" });
    // The widest full-length records fit the tide's bounds, and only because its definition grows them.
    const supported = turnOfTheTide.supported_simulation_versions ?? [9];
    for (const [record, ticks] of [[setA, 2700], [setB, 3000]] as const) {
      const widest = await stretched(record, ticks, Math.floor(ticks / 30) + 1, true);
      expect(await recordingV2(widest, turnOfTheTide.key)).toEqual(widest);
      await expect(physicalRecording(definition, turnOfTheTide.key, 7, supported, undefined, { a_ticks: 2700, b_ticks: 3000 })(widest)).rejects.toMatchObject({ code: "value_too_large" });
      await expect(physicalRecording(definition, turnOfTheTide.key, 7, supported)(widest)).rejects.toThrow();
    }
    const checkpoint = widestCheckpoint(latestFinal), limits = turnOfTheTide.limits!;
    expect(() => boundedValue(checkpoint, limits.checkpoint_bytes, limits.checkpoint_values)).not.toThrow();
    expect(() => boundedValue(checkpoint, MAX_CHECKPOINT_BYTES)).toThrow(/too_large/);
    const body = { schema_version: 2, recording: await stretched(latestB, 3000, 101, true), checkpoint };
    expect(() => boundedTurnValue(body, limits)).not.toThrow();
    expect(() => boundedTurnValue(body)).toThrow(/too_large/);
  });
  it("lets a tide receiver turn past the published body bound reach the proof over HTTP", async () => {
    const host = await account(), guest = await account();
    const created = await call("/v2/rooms", "POST", host, { ...turnOfTheTide.key, idempotency_key: key() }, ON); expect(created.status).toBe(200);
    const room = await created.json<RoomSnapshotV2>();
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: NEW_CLIENT }, ON); expect(joined.status).toBe(200);
    const a = await submit(await joined.json<RoomSnapshotV2>(), host, setA), b = await submit(a.room, guest, setB, middle);
    const c = await submit(b.room, guest, latestA);
    expect(c.room).toMatchObject({ stage_index: 1, active_player_id: host.player_id });
    const recording = await stretched(latestB, 3000, 101, true), checkpoint = widestCheckpoint(latestFinal);
    const body = { base_revision: c.room.revision, branch: c.room.branch, idempotency_key: key(), recording, checkpoint };
    // Sent with its length, as a client does, so the route asks the room for its bound.
    const text = JSON.stringify(body); expect(text.length).toBeGreaterThan(MAX_V2_BODY_BYTES);
    const configured: Env = withConfig({ ...env, ...ON });
    const reply = await worker.fetch(new Request(`https://after-you.test/v2/rooms/${c.room.room_id}/turns`, { method: "POST", body: text, headers: { "Content-Type": "application/json",
      "Content-Length": String(text.length), "CF-Connecting-IP": "198.18.12." + (++requestNo % 250), "X-Player-Id": host.player_id, Authorization: "Bearer " + host.device_token } }), configured);
    // Past the size gates, the made-up receiver is refused by the proof itself.
    expect(reply.status).toBe(422);
    expect((await reply.json<{ error: { code: string } }>()).error.code).not.toMatch(/too_large/);
    const d = await submit(c.room, host, latestB, latestFinal);
    expect(d.room).toMatchObject({ stage_index: 2, active_role: "complete", checkpoint: latestFinal });
  });
  it("refuses other rules, other chapters' records and end states the native proof could not make", async () => {
    const renumbered = { ...setA, simulation_version: 8 }; const { recording_hash: _hash, ...body } = renumbered; void _hash;
    await expect(recordingV2({ ...renumbered, recording_hash: await digest(canonicalJson(body)) }, turnOfTheTide.key)).rejects.toMatchObject({ code: "unsupported_simulation_version" });
    await expect(recordingV2(homeV2PathA, turnOfTheTide.key)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
    await expect(recordingV2(setA, longWayHomeV2.key)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
    const first = await stageOne();
    const a = await recordingV2(seaLockA, turnOfTheTide.key) as ChapterRecording, b = await recordingV2(seaLockB, turnOfTheTide.key) as ChapterRecording;
    // At a half sea the gate post p1 stands on is under water, so it cannot have been kept.
    const wrongSea = structuredClone(seaLockFinal) as Record<string, any>; wrongSea.mechanisms.controls.basin = "half";
    await expect(checkpointV2(await rehash(wrongSea), first, a, b)).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
    const awayFromLantern = structuredClone(seaLockFinal) as Record<string, any>; awayFromLantern.players.p0 = { ...awayFromLantern.players.p0, z: 100 };
    await expect(checkpointV2(await rehash(awayFromLantern), first, a, b)).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    const offPost = structuredClone(seaLockFinal) as Record<string, any>; offPost.players.p1 = { ...offPost.players.p1, x: -290, z: -136 };
    await expect(checkpointV2(await rehash(offPost), first, a, b)).rejects.toMatchObject({ code: "checkpoint_source_position_mismatch" });
    // The sluice belongs to the first stage, so the second cannot turn it off.
    const sluiceOff = structuredClone(seaLockFinal) as Record<string, any>; sluiceOff.mechanisms.levers.sluice = false;
    await expect(checkpointV2(await rehash(sluiceOff), first, a, b)).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
  });
  it("refuses a 0.5.x guest before the seat is taken, and plays both stages to completion", async () => {
    const host = await account(), oldGuest = await account(), guest = await account();
    const created = await call("/v2/rooms", "POST", host, { ...turnOfTheTide.key, idempotency_key: key() }, ON);
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
    const a = await submit(seated, host, setA), b = await submit(a.room, guest, setB, middle);
    expect(b.room).toMatchObject({ stage_index: 1, active_player_id: guest.player_id, checkpoint: middle });
    const c = await submit(b.room, guest, boomA), d = await submit(c.room, host, boomB, boomFinal);
    expect(d.room).toMatchObject({ stage_index: 2, active_role: "complete", checkpoint: boomFinal });
  });
});
