import { env } from "cloudflare:workers";
import { reset, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { chapter, recordingV2, boundedValue, boundedTurnValue, MAX_V2_BODY_BYTES, MAX_CHECKPOINT_BYTES } from "../src/v2/protocol";
import { highAndLow, rollingHome } from "../src/v2/protocol-cooperative";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { RoomSnapshotV2, MutationV2 } from "../src/v2/room";
import native from "../../game/tests/fixtures/comfort8/recordings.json";
import denseNative from "../../game/tests/fixtures/comfort8/dense-physical.json";
import oldRelayA from "../../game/tests/fixtures/v2/relay-a.json";
import oldPhysicalA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import oldJourneyA from "../../game/tests/fixtures/journey/a-light-above-a.json";

type Pair = { a: ChapterRecording; b: ChapterRecording };
type PhysicalProof = { pairs: Pair[]; checkpoints: ChapterCheckpoint[] };
const proofs = native as unknown as Record<string, PhysicalProof>;
const dense = denseNative as unknown as PhysicalProof;
const relay = native.relay as unknown as Pair & PhysicalProof & { checkpoint: ChapterCheckpoint };
type Account = { player_id: string; device_token: string };
let requestNo = 0;
const key = () => crypto.randomUUID();
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
async function rehash(value: Record<string, unknown>) {
  const { recording_hash: ignored, ...body } = value; void ignored;
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}
async function call(path: string, method = "GET", owner?: Account, body?: unknown, overrides: Record<string, unknown> = {}): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true", ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.15." + ++requestNo,
      ...(owner ? { "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }),
  configured);
}
async function account(): Promise<Account> {
  const reply = await call("/v1/identity", "POST", undefined, {});
  expect(reply.status).toBe(201); return reply.json<Account>();
}
afterEach(async () => { await reset(); });

describe("version8 comfort proof boundaries", () => {
  it.each(["rolling-home", "high-and-low", "a-house-for-two", "conservatory", "long-way-home"])("accepts native full two-pair %s without changing authored schema", async name => {
    const proof = proofs[name], adapter = chapter(proof.pairs[0].a);
    expect(proof.pairs).toHaveLength(2);
    expect(adapter.simulation_version).not.toBe(8);
    expect(adapter.supported_simulation_versions).toContain(8);
    for (const [index, pair] of proof.pairs.entries()) {
      const a = await adapter.recording(pair.a), b = await adapter.recording(pair.b);
      expect(a.simulation_version).toBe(8); expect(b.simulation_version).toBe(8);
      expect(a.schema_version).toBe(adapter.recording_version);
      expect(await adapter.checkpoint(proof.checkpoints[index + 1], proof.checkpoints[index], a, b)).toEqual(proof.checkpoints[index + 1]);
    }
  });

  it("accepts native Relay8 late handoff and preserves released2/6/7 recording bytes", async () => {
    const adapter = chapter(relay.a), a = await adapter.recording(relay.a), b = await adapter.recording(relay.b);
    expect(b.duration_ticks).toBeGreaterThan(600);
    expect(await adapter.checkpoint(relay.checkpoint, adapter.initial(), a, b)).toEqual(relay.checkpoint);
    expect(relay.pairs).toHaveLength(2);
    for (const [index, pair] of relay.pairs.entries()) {
      expect(await adapter.checkpoint(relay.checkpoints[index + 1], relay.checkpoints[index], await adapter.recording(pair.a), await adapter.recording(pair.b))).toEqual(relay.checkpoints[index + 1]);
    }
    for (const old of [oldRelayA, oldPhysicalA, oldJourneyA]) expect(await recordingV2(old)).toEqual(old);
    await expect(adapter.checkpoint(relay.checkpoint, adapter.initial(), { ...a, simulation_version: 2 }, b)).rejects.toMatchObject({ code: "checkpoint_recording_mismatch" });
  });

  it("rejects mixed physical versions within a pair and across completed stages", async () => {
    for (const name of ["high-and-low", "long-way-home"]) {
      const proof = proofs[name], adapter = chapter(proof.pairs[0].a), old = adapter.simulation_version;
      const first = proof.pairs[0], last = proof.pairs[1];
      await expect(adapter.checkpoint(proof.checkpoints[1], proof.checkpoints[0], { ...first.a, simulation_version: old }, first.b)).rejects.toMatchObject({ code: "checkpoint_recording_mismatch" });
      await expect(adapter.checkpoint(proof.checkpoints[2], proof.checkpoints[1], { ...last.a, simulation_version: old }, { ...last.b, simulation_version: old })).rejects.toMatchObject({ code: "checkpoint_recording_mismatch" });
    }
  });

  it("admits all actual dense1200 actions/checks/full proof while keeping old structural caps", async () => {
    for (const [index, pair] of dense.pairs.entries()) {
      expect(pair.a.actions).toHaveLength(900); expect(pair.b.actions).toHaveLength(1200);
      expect(pair.b.replay_checks).toHaveLength(40);
      expect(await highAndLow.recording(pair.a)).toEqual(pair.a);
      expect(await highAndLow.recording(pair.b)).toEqual(pair.b);
      expect(await highAndLow.checkpoint(dense.checkpoints[index + 1], dense.checkpoints[index], pair.a, pair.b)).toEqual(dense.checkpoints[index + 1]);
    }
    const packet = structuredClone(denseNative.packet);
    expect(() => boundedTurnValue(packet)).not.toThrow();
    expect(() => boundedValue(packet, MAX_V2_BODY_BYTES)).toThrowError(expect.objectContaining({ code: "structure_too_large" }));
    expect(() => boundedValue(packet.checkpoint, MAX_CHECKPOINT_BYTES)).not.toThrow();
    for (const version of [6, 7, 9]) {
      packet.recording.simulation_version = version;
      expect(() => boundedTurnValue(packet)).toThrowError(expect.objectContaining({ code: "structure_too_large" }));
    }
    packet.recording.simulation_version = 8;
    packet.recording.role = "a";
    expect(() => boundedTurnValue(packet)).toThrowError(expect.objectContaining({ code: "structure_too_large" }));
    packet.recording.role = "b";
    for (const schema of [2, 4]) {
      packet.recording.schema_version = schema;
      expect(() => boundedTurnValue(packet)).toThrowError(expect.objectContaining({ code: "structure_too_large" }));
    }
    for (const old of [oldPhysicalA, oldJourneyA]) {
      const bad = await rehash({ ...dense.pairs[0].b, schema_version: old.schema_version, simulation_version: old.simulation_version,
        level_id: old.level_id, level_version: old.level_version, definition_hash: old.definition_hash, stage_id: old.stage_id });
      await expect(recordingV2(bad)).rejects.toBeDefined();
    }
    const tooLong = structuredClone(dense.pairs[0].a);
    tooLong.duration_ticks = 901; tooLong.actions.push({ ticks: 1, x: 0, z: 0, action: false });
    await expect(highAndLow.recording(await rehash(tooLong))).rejects.toBeDefined();
    const tooManyChecks = structuredClone(dense.pairs[0].b);
    tooManyChecks.replay_checks.unshift({ tick: 1, state_hash: tooManyChecks.final_state_hash });
    // This is the structural41-check envelope, not a claimed native recording.
    expect((await highAndLow.recording(await rehash(tooManyChecks))).replay_checks).toHaveLength(41);
    tooManyChecks.replay_checks = Array.from({ length: 42 }, (_, i) => ({ tick: i + 1, state_hash: tooManyChecks.final_state_hash }));
    await expect(highAndLow.recording(await rehash(tooManyChecks))).rejects.toBeDefined();
  });

  it("keeps malicious comfort envelopes bounded by nodes, depth and bytes", () => {
    const recording = { schema_version: 6, simulation_version: 8, role: "b" };
    expect(() => boundedTurnValue({ recording, extra: Array(32000).fill(0) })).toThrow();
    let deep: unknown = 0; for (let i = 0; i < 17; i++) deep = [deep];
    expect(() => boundedTurnValue({ recording, deep })).toThrow();
    expect(() => boundedTurnValue({ recording, extra: Array(1000).fill("x".repeat(512)) })).toThrowError(expect.objectContaining({ code: "value_too_large" }));
  });

  it("runs the full dense native proof through real HTTP and Room dispatch, preserving lost-reply retry", async () => {
    const host = await account(), guest = await account();
    const create = { ...highAndLow.key, simulation_version: 8, idempotency_key: key() };
    const made = await call("/v2/rooms", "POST", host, create); expect(made.status).toBe(200);
    const waiting = await made.json<RoomSnapshotV2>();
    expect(waiting.simulation_version).toBe(8);
    const oldJoin = await call("/v2/rooms/join", "POST", guest, { invite_code: waiting.invite_code, supported_simulation_versions: [2, 4, 5, 6, 7] });
    expect(oldJoin.status).toBe(422);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: waiting.invite_code, supported_simulation_versions: [2, 4, 5, 6, 7, 8] });
    expect(joined.status).toBe(200); let room = await joined.json<RoomSnapshotV2>();
    for (const [index, pair] of dense.pairs.entries()) {
      for (const recording of [pair.a, pair.b]) {
        const owner = recording.player_slot === "p0" ? host : guest;
        const body = { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording,
          ...(recording.role === "b" ? { checkpoint: dense.checkpoints[index + 1] } : {}) };
        const path = `/v2/rooms/${room.room_id}/turns`;
        const reply = await call(path, "POST", owner, body); expect(reply.status).toBe(200);
        const accepted = await reply.json<MutationV2>();
        await evictDurableObject(env.ROOMS_V2.getByName(room.room_id));
        const retry = await call(path, "POST", owner, body); expect(retry.status).toBe(200);
        expect(await retry.json()).toEqual(accepted); room = accepted.room;
      }
    }
    expect(room.checkpoint).toEqual(dense.checkpoints[2]);
    const archive = value(await env.ROOMS_V2.getByName(room.room_id).exportSnapshot("d".repeat(40)));
    const restored = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await restored.restoreSnapshot(archive, room.room_id)).toMatchObject({ ok: true });
    const roundtrip = value(await restored.exportSnapshot("d".repeat(40)));
    expect(JSON.parse(roundtrip).payload.tables).toEqual(JSON.parse(archive).payload.tables);
    expect(value(await restored.snapshot(host.player_id)).simulation_version).toBe(8);
    const oldCreate = await call("/v2/rooms", "POST", host, { ...highAndLow.key, idempotency_key: key() });
    expect(oldCreate.status).toBe(200);
    const oldRoom = await oldCreate.json<RoomSnapshotV2>();
    expect(oldRoom.simulation_version ?? highAndLow.simulation_version).toBe(6);
  });

  it("allows a dense8 envelope through the paid route preflight, then rejects its wrong chapter", async () => {
    const host = await account(), guest = await account(), code = "SYNTHETIC-COMFORT-HOST";
    const granted = await call("/v1/tester-access", "POST", host, { schema_version: 1, code },
      { TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + code) });
    expect(granted.status).toBe(200);
    const made = await call("/v2/rooms", "POST", host, { ...rollingHome.key, simulation_version: 8, idempotency_key: key() });
    expect(made.status).toBe(200); const waiting = await made.json<RoomSnapshotV2>();
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: waiting.invite_code, supported_simulation_versions: [8] });
    expect(joined.status).toBe(200); const room = await joined.json<RoomSnapshotV2>();
    const packet = { ...denseNative.packet, base_revision: room.revision, branch: room.branch, idempotency_key: key() };
    const reply = await call(`/v2/rooms/${room.room_id}/turns`, "POST", guest, packet);
    // Deliberately mismatched native chapter: this proves the premium envelope
    // reaches normal chapter validation, not that High inputs solve Rolling.
    expect(reply.status).toBe(422);
    expect(await reply.json()).toMatchObject({ error: { code: "recording_chapter_mismatch" } });
    const after = await call(`/v2/rooms/${room.room_id}`, "GET", host);
    expect((await after.json<RoomSnapshotV2>()).revision).toBe(room.revision);
  });
});
