import { Buffer } from "node:buffer";
import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { chapter, checkpointV2, recordingV2 } from "../src/v2/protocol";
import { checkTicks, packRecording, unpackRecording, type Check, type Run } from "../src/v2/recording-codec";
import { PACKED_HEADER } from "../src/v2/packed-rooms";
import { turnOfTheTideV2 } from "../src/v2/protocol-journey";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import native from "../../game/tests/fixtures/comfort8/recordings.json";
import tideA from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-set-the-tide-a.json";
import golden from "../../game/tests/fixtures/v2/packed-recording-golden.json";
import { configJson, withConfig } from "./config";

/** Packed recordings (v2/recording-codec.ts, v2/packed-rooms.ts): the codec, the record checks and which rooms take them. */
type Proof = { pairs: { a: ChapterRecording; b: ChapterRecording }[]; checkpoints: ChapterCheckpoint[] };
type Account = { player_id: string; device_token: string };
const plain = (native as unknown as Record<string, Proof>)["rolling-home"];
const code = "SYNTHETIC-PACKED-HOST";
let requestNo = 0, features: string[] = ["PACKED_RECORDINGS"];
const shared = env as unknown as Record<string, unknown>;
afterEach(async () => { features = ["PACKED_RECORDINGS"]; delete shared.CONFIG; await reset(); });

const hashed = async <T extends Record<string, unknown>>(value: T, key: string): Promise<T> => {
  const body: Record<string, unknown> = { ...value }; delete body[key];
  return { ...body, [key]: await digest(canonicalJson(body)) } as T;
};
/** A record in packed form, its hash made again (the server replays nothing, so a fixture's hashes stand in). */
async function packed(record: ChapterRecording, source = record.source_recording_hash): Promise<ChapterRecording> {
  const { actions, replay_checks, ...rest } = record;
  return hashed({ ...rest, source_recording_hash: source, packed: packRecording(actions!, replay_checks!, record.duration_ticks) } as ChapterRecording, "recording_hash");
}
/** The fixture chapter with every turn packed and every checkpoint made again to nest them. */
async function packedProof(proof: Proof): Promise<Proof> {
  const pairs: Proof["pairs"] = [], checkpoints = [proof.checkpoints[0]];
  for (const [index, pair] of proof.pairs.entries()) {
    const previous = checkpoints[index];
    const a = await packed({ ...pair.a, checkpoint_hash: previous.checkpoint_hash });
    const b = await packed({ ...pair.b, checkpoint_hash: previous.checkpoint_hash }, a.recording_hash);
    const { proof: _proof, ...next } = proof.checkpoints[index + 1] as ChapterCheckpoint & { proof: unknown }; void _proof;
    const body = { ...next, previous_checkpoint_hash: previous.checkpoint_hash, a_recording_hash: a.recording_hash, b_recording_hash: b.recording_hash };
    const made = await hashed(body as unknown as Record<string, unknown>, "checkpoint_hash");
    checkpoints.push({ ...made, proof: { checkpoint: previous, a, b } } as unknown as ChapterCheckpoint);
    pairs.push({ a, b });
  }
  return { pairs, checkpoints };
}

describe("the packed recording codec", () => {
  const runs: Run[] = [{ ticks: 40, x: 0, z: 100, action: false }, { ticks: 1, x: -100, z: -7, action: true }, { ticks: 200, x: 55, z: 0, action: false }];
  const final = "f".repeat(64);
  const checks = (duration: number): Check[] => checkTicks(duration).map((tick, index) => ({ tick, state_hash: tick === duration ? final : (index % 16).toString(16).repeat(64) }));

  it("keeps runs exactly, checks short every second and full every five, and the end as final_state_hash", () => {
    const text = packRecording(runs, checks(241), 241), back = unpackRecording(text, 241, final, 3);
    expect(back.actions).toEqual(runs);
    expect(back.replay_checks.map(check => check.tick)).toEqual([30, 60, 90, 120, 150, 180, 210, 240, 241]);
    expect(back.replay_checks.map(check => check.state_hash.length)).toEqual([16, 16, 16, 16, 64, 16, 16, 16, 64]);
    expect(back.replay_checks.at(-1)!.state_hash).toBe(final);
    expect(back.replay_checks[4].state_hash).toBe("4".repeat(64));
    // Short checks pack the same again: the form is its own canonical encoding.
    expect(packRecording(back.actions, back.replay_checks, 241)).toBe(text);
  });

  it("matches the bytes the game writes", () => {
    for (const item of golden.cases as { duration: number; final: string; actions: Run[]; checks: Check[]; packed: string }[]) {
      expect(packRecording(item.actions, item.checks, item.duration)).toBe(item.packed);
      expect(unpackRecording(item.packed, item.duration, item.final, 9000).actions).toEqual(item.actions);
    }
  });

  it("refuses every other encoding of the same turn", () => {
    const good = new Uint8Array(Buffer.from(packRecording(runs, checks(241), 241), "base64"));
    const bad = (bytes: number[] | Uint8Array) => () => unpackRecording(Buffer.from(Uint8Array.from(bytes)).toString("base64"), 241, final, 3);
    const refused = expect.objectContaining({ status: 422, code: "invalid_packed_recording" });
    expect(bad(good)).not.toThrow();
    expect(bad([...good, 0])).toThrow(refused); // trailing
    expect(bad(good.subarray(0, good.length - 1))).toThrow(refused); // short
    expect(bad([2, ...good.subarray(1)])).toThrow(refused); // unknown format
    // A non-minimal varint for the run count (3 as 0x83 0x00).
    expect(bad([good[0], 0x83, 0x00, ...good.subarray(2)])).toThrow(refused);
    // A stick past 100.
    const wide = Uint8Array.from(good); wide[3] = 101; expect(bad(wide)).toThrow(refused);
    // Two equal runs in a row (40 ticks split 20 + 20).
    expect(() => unpackRecording(packRecording([{ ...runs[0], ticks: 20 }, { ...runs[0], ticks: 20 }, ...runs.slice(1)], checks(241), 241), 241, final, 4)).toThrow(refused);
    expect(() => unpackRecording(packRecording(runs, checks(241), 241), 241, final, 2)).toThrow(refused); // too many runs
    expect(() => unpackRecording(packRecording(runs, checks(241), 241), 240, final, 3)).toThrow(refused); // wrong duration
    expect(() => unpackRecording(packRecording(runs, checks(241), 241) + " ", 241, final, 3)).toThrow(refused); // not canonical base64
    expect(() => unpackRecording(42, 241, final, 3)).toThrow(refused);
  });
});

describe("a packed record", () => {
  it("is taken by the chapter's own checks beside the JSON form, and its hash covers the packed bytes", async () => {
    const proof = await packedProof(plain);
    for (const [index, pair] of proof.pairs.entries()) {
      const a = await recordingV2(pair.a), b = await recordingV2(pair.b);
      expect(await checkpointV2(proof.checkpoints[index + 1], proof.checkpoints[index], a, b)).toEqual(proof.checkpoints[index + 1]);
    }
    const tide = await packed(tideA as unknown as ChapterRecording);
    expect(await turnOfTheTideV2.recording(tide)).toEqual(tide);
    const other = Buffer.from(tide.packed!, "base64"); other[other.length - 1] ^= 1;
    await expect(turnOfTheTideV2.recording({ ...tide, packed: other.toString("base64") })).rejects.toMatchObject({ code: "recording_hash_mismatch" });
    await expect(turnOfTheTideV2.recording({ ...tide, actions: (tideA as { actions: unknown[] }).actions } as never)).rejects.toMatchObject({ code: "unexpected_fields" });
  });

  it("is checked well inside the Worker's CPU on the widest turn", async () => {
    // The tide's longest first turn with a new stick every tick: the most runs any turn can hold.
    const tick = (index: number): Run => ({ ticks: 1, x: index % 2 ? 100 : -100, z: (index * 37) % 201 - 100, action: index % 7 === 0 });
    const json = await hashed({ ...tideA, role: "a", duration_ticks: 2700, actions: Array.from({ length: 2700 }, (_, i) => tick(i)),
      replay_checks: checkTicks(2700).map(t => ({ tick: t, state_hash: (tideA as ChapterRecording).final_state_hash })) } as unknown as ChapterRecording, "recording_hash");
    const widest = await packed(json);
    expect(Buffer.from(widest.packed!, "base64").length).toBeLessThan(2700 * 3 + 2 + 90 * 32);
    const time = async (record: ChapterRecording) => {
      await turnOfTheTideV2.recording(record);
      const started = performance.now();
      for (let round = 0; round < 20; round++) await turnOfTheTideV2.recording(record);
      return (performance.now() - started) / 20;
    };
    const asJson = await time(json), asPacked = await time(widest);
    console.log(`widest tide turn checked: ${asJson.toFixed(3)} ms as JSON, ${asPacked.toFixed(3)} ms packed; ${JSON.stringify(json).length} and ${JSON.stringify(widest).length} bytes`);
    expect(asPacked).toBeLessThan(2);
  });
});

describe("rooms and packed turns", () => {
  async function configured(): Promise<Env> {
    shared.CONFIG = configJson({ features });
    const { CONFIG: _config, ...base } = shared; void _config;
    return withConfig({ ...base, features, TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + code) } as never);
  }
  async function call(path: string, method = "GET", owner?: Account, body?: unknown, reader = false) {
    const headers: Record<string, string> = { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.20." + (++requestNo % 250),
      ...(owner ? { "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token } : {}), ...(reader ? { [PACKED_HEADER]: "1" } : {}) };
    return worker.fetch(new Request("https://after-you.test" + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }), await configured());
  }
  async function account(): Promise<Account> { return (await call("/v1/identity", "POST", undefined, {})).json<Account>(); }
  async function room(hostReads: boolean, guestReads: boolean) {
    const host = await account(), guest = await account();
    expect((await call("/v1/tester-access", "POST", host, { schema_version: 1, code })).status).toBe(200);
    const created = await call("/v2/rooms", "POST", host, { ...chapter(plain.pairs[0].a).key, simulation_version: 8, idempotency_key: crypto.randomUUID() }, hostReads);
    expect(created.status).toBe(200);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: (await created.json<RoomSnapshotV2>()).invite_code, supported_simulation_versions: [8] }, guestReads);
    expect(joined.status).toBe(200);
    return { host, guest, room: await joined.json<RoomSnapshotV2>() };
  }
  const turn = (room: RoomSnapshotV2, recording: ChapterRecording, checkpoint?: ChapterCheckpoint) =>
    ({ base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) });

  it("are told to a phone that asks while the flag is on", async () => {
    const asked = await call("/v2/capabilities", "GET", await account(), undefined, true);
    expect((await asked.json<Record<string, unknown>>()).packed_recordings_version).toBe(1);
    expect((await (await call("/v2/capabilities", "GET", await account())).json<Record<string, unknown>>()).packed_recordings_version).toBeUndefined();
    features = [];
    expect((await (await call("/v2/capabilities", "GET", await account(), undefined, true)).json<Record<string, unknown>>()).packed_recordings_version).toBeUndefined();
  });

  it("play a whole chapter once both members read them, and the room says so only to a phone that asks", async () => {
    const proof = await packedProof(plain);
    const { host, guest, room: start } = await room(true, true);
    const read = await (await call(`/v2/rooms/${start.room_id}`, "GET", guest, undefined, true)).json<Record<string, unknown>>();
    expect(read.packed_recordings).toBe(true);
    expect("packed_recordings" in await (await call(`/v2/rooms/${start.room_id}`, "GET", guest)).json<Record<string, unknown>>()).toBe(false);
    let current = start;
    for (const [index, pair] of proof.pairs.entries()) {
      for (const recording of [pair.a, pair.b]) {
        const actor = recording.player_slot === "p0" ? host : guest;
        const response = await call(`/v2/rooms/${current.room_id}/turns`, "POST", actor, turn(current, recording, recording.role === "b" ? proof.checkpoints[index + 1] : undefined), true);
        expect(response.status, await response.clone().text()).toBe(200);
        const reply = await response.json<MutationV2 & { packed_recordings?: true }>();
        expect(reply.packed_recordings).toBe(true);
        current = reply.room;
      }
    }
    expect(current.checkpoint).toEqual(proof.checkpoints.at(-1));
    // A packed room still takes the JSON form.
    const other = await room(true, true), actor = plain.pairs[0].a.player_slot === "p0" ? other.host : other.guest;
    expect((await call(`/v2/rooms/${other.room.room_id}/turns`, "POST", actor, turn(other.room, plain.pairs[0].a), true)).status).toBe(200);
  });

  it("refuse a packed turn until both members read them", async () => {
    const proof = await packedProof(plain);
    for (const [hostReads, guestReads, flag] of [[true, false, true], [false, true, true], [true, true, false]] as const) {
      features = flag ? ["PACKED_RECORDINGS"] : [];
      const { host, guest, room: current } = await room(hostReads, guestReads);
      const actor = proof.pairs[0].a.player_slot === "p0" ? host : guest;
      const refused = await call(`/v2/rooms/${current.room_id}/turns`, "POST", actor, turn(current, proof.pairs[0].a), true);
      expect(refused.status).toBe(422);
      expect((await refused.json<{ error: { code: string } }>()).error.code).toBe("packed_recording_not_allowed");
      expect("packed_recordings" in await (await call(`/v2/rooms/${current.room_id}`, "GET", guest, undefined, true)).json<Record<string, unknown>>()).toBe(false);
      // The JSON form goes as always.
      expect((await call(`/v2/rooms/${current.room_id}/turns`, "POST", actor, turn(current, plain.pairs[0].a), true)).status).toBe(200);
    }
  });
});

