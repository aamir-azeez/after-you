import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { RELAY_KEY, chapter, checkpointV2, initialCheckpoint, recordingV2, acceptedRecording, boundedTurnValue } from "../src/v2/protocol";
import { wishingWell, WISHING_WELL_HASH } from "../src/v2/protocol-cooperative";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import definition from "../../game/tests/fixtures/cooperative/the-wishing-well-definition.json";
import initial from "../../game/tests/fixtures/cooperative/the-wishing-well-initial-checkpoint.json";
import aheadA from "../../game/tests/fixtures/cooperative/go-on-ahead-a.json";
import aheadB from "../../game/tests/fixtures/cooperative/go-on-ahead-b.json";
import middle from "../../game/tests/fixtures/cooperative/go-on-ahead-checkpoint.json";
import backA from "../../game/tests/fixtures/cooperative/back-for-you-a.json";
import backB from "../../game/tests/fixtures/cooperative/back-for-you-b.json";
import longB from "../../game/tests/fixtures/cooperative/back-for-you-b-long.json";
import final from "../../game/tests/fixtures/cooperative/the-wishing-well-final-checkpoint.json";
import bundledDefinition from "../src/v2/the-wishing-well.json";
import bundledInitial from "../src/v2/the-wishing-well-initial.json";
import { withConfig } from "./config";

type Account = { player_id: string; device_token: string; recovery_code: string };
const key = () => crypto.randomUUID();
const OLD_CLIENT = [2, 4, 5, 6, 7, 8], NEW_CLIENT = [2, 4, 5, 6, 7, 8, 9];
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}): Promise<Response> {
  const configured: Env = withConfig({ ...env, ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.9." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function newRoom(host: Account): Promise<RoomSnapshotV2> {
  const response = await call("/v2/rooms", "POST", host, { ...wishingWell.key, idempotency_key: key() }); expect(response.status).toBe(200); return response.json<RoomSnapshotV2>();
}
async function submit(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  const body = { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
  const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, body); expect(response.status).toBe(200); return response.json<MutationV2>();
}
async function rehashCheckpoint(input: Record<string, unknown>): Promise<Record<string, unknown>> {
  const body = { ...input }; delete body.checkpoint_hash; delete body.proof;
  return { ...input, checkpoint_hash: await digest(canonicalJson(body)) };
}
afterEach(async () => { await reset(); });

describe("The Wishing Well (free, rules 9)", () => {
  it("bundles the exact native definition and initial checkpoint", async () => {
    expect(bundledDefinition).toEqual(definition); expect(bundledInitial).toEqual(initial);
    expect(await digest(canonicalJson(definition))).toBe(WISHING_WELL_HASH);
    expect(wishingWell).toMatchObject({ premium: false, recording_version: 6, simulation_version: 9, supported_simulation_versions: [9], require_supported_simulation_on_join: true });
    expect(chapter(wishingWell.key)).toBe(wishingWell); expect(initialCheckpoint(wishingWell.key)).toEqual(initial);
  });
  it("advertises exactly its pinned rules", async () => {
    const host = await account();
    const caps = await (await call("/v2/capabilities", "GET", host)).json<{ chapters: Record<string, unknown>[] }>();
    expect(caps.chapters[0]).toEqual({ ...RELAY_KEY, premium: false, recording_version: 2, simulation_version: 2, supported_simulation_versions: [2, 8] });
    expect(caps.chapters).toContainEqual({ ...wishingWell.key, premium: false, recording_version: 6, simulation_version: 9, supported_simulation_versions: [9] });
  });
  it("accepts the native recordings and both checkpoints, including a receiver past 900 ticks", async () => {
    const records = await Promise.all([aheadA, aheadB, backA, backB].map(record => recordingV2(record, wishingWell.key)));
    records.forEach((record, index) => { expect(record).toEqual([aheadA, aheadB, backA, backB][index]); expect(acceptedRecording(record)).toBe(true); });
    const first = await checkpointV2(middle, initialCheckpoint(wishingWell.key), records[0], records[1]); expect(first).toEqual(middle);
    expect(await checkpointV2(final, first, records[2], records[3])).toEqual(final);
    expect(longB.duration_ticks).toBeGreaterThan(900);
    expect(await recordingV2(longB, wishingWell.key)).toEqual(longB);
    expect(() => boundedTurnValue({ schema_version: 2, recording: longB, checkpoint: final })).not.toThrow();
  });
  it("refuses other rules and end states the native proof could not have made", async () => {
    const renumbered = { ...aheadA, simulation_version: 8 }; const { recording_hash: _hash, ...body } = renumbered; void _hash;
    await expect(recordingV2({ ...renumbered, recording_hash: await digest(canonicalJson(body)) }, wishingWell.key)).rejects.toMatchObject({ code: "unsupported_simulation_version" });
    const a = await recordingV2(aheadA, wishingWell.key) as ChapterRecording, b = await recordingV2(aheadB, wishingWell.key) as ChapterRecording, start = initialCheckpoint(wishingWell.key) as ChapterCheckpoint;
    const offPad = structuredClone(middle) as Record<string, any>; offPad.players.p0 = { ...offPad.players.p0, x: 1120, z: 40 };
    await expect(checkpointV2(await rehashCheckpoint(offPad), start, a, b)).rejects.toMatchObject({ code: "checkpoint_source_position_mismatch" });
    const gateShut = structuredClone(middle) as Record<string, any>; gateShut.mechanisms.levers["garden-gate"] = false;
    await expect(checkpointV2(await rehashCheckpoint(gateShut), start, a, b)).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
    const stairOpenOnly = structuredClone(middle) as Record<string, any>; stairOpenOnly.mechanisms.latched_bridges = ["cliff-steps"];
    await expect(checkpointV2(await rehashCheckpoint(stairOpenOnly), start, a, b)).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
  });
  it("refuses a 0.5.x guest before the seat is taken, and seats a client that plays rules 9", async () => {
    const host = await account(), oldGuest = await account(), guest = await account();
    const room = await newRoom(host);
    expect(room).not.toHaveProperty("simulation_version");
    for (const versions of [undefined, OLD_CLIENT]) {
      const rejected = await call("/v2/rooms/join", "POST", oldGuest, { invite_code: room.invite_code, ...(versions ? { supported_simulation_versions: versions } : {}) });
      expect(rejected.status).toBe(422); expect(await rejected.json()).toMatchObject({ error: { code: "unsupported_simulation_version" } });
      expect(await env.PLAYERS.getByName(oldGuest.player_id).listRooms()).toEqual([]);
    }
    const hostView = await (await call(`/v2/rooms/${room.room_id}`, "GET", host, undefined)).json<RoomSnapshotV2>();
    expect(hostView.guest_id).toBeNull();
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: NEW_CLIENT });
    expect(joined.status).toBe(200); expect((await joined.json<RoomSnapshotV2>()).guest_id).toBe(guest.player_id);
  });
  it("plays both role-swapped stages through a room to completion", async () => {
    const host = await account(), guest = await account();
    const created = await newRoom(host);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: created.invite_code, supported_simulation_versions: NEW_CLIENT });
    const room = await joined.json<RoomSnapshotV2>();
    const a = await submit(room, host, aheadA), b = await submit(a.room, guest, aheadB, middle);
    expect(b.room).toMatchObject({ stage_index: 1, active_player_id: guest.player_id, checkpoint: middle });
    const c = await submit(b.room, guest, backA), d = await submit(c.room, host, backB, final);
    expect(d.room).toMatchObject({ stage_index: 2, active_role: "complete", checkpoint: final });
  });
});
