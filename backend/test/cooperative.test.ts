import { env } from "cloudflare:workers";
import { reset, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, type Outcome } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { RELAY_KEY, acceptedRecording, chapter, checkpointV2, initialCheckpoint, recordingV2, boundedValue, MAX_RECORDING_BYTES, MAX_CHECKPOINT_BYTES, MAX_V2_BODY_BYTES } from "../src/v2/protocol";
import { highAndLow, rollingHome, houseForTwo } from "../src/v2/protocol-cooperative";
import type { ChapterAdapter, ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import type { RoomV2Archive } from "../src/v2/snapshot";
import type { PortableSnapshot } from "../src/snapshot";
import highDefinition from "../../game/tests/fixtures/cooperative/high-and-low-definition.json";
import highInitial from "../../game/tests/fixtures/cooperative/high-and-low-initial-checkpoint.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import highMiddle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import highFinal from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";
import rollingDefinition from "../../game/tests/fixtures/cooperative/rolling-home-definition.json";
import rollingInitial from "../../game/tests/fixtures/cooperative/rolling-home-initial-checkpoint.json";
import weightA from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";
import weightB from "../../game/tests/fixtures/cooperative/weight-of-a-friend-b.json";
import rollingMiddle from "../../game/tests/fixtures/cooperative/weight-of-a-friend-checkpoint.json";
import homeA from "../../game/tests/fixtures/cooperative/bring-it-home-a.json";
import homeB from "../../game/tests/fixtures/cooperative/bring-it-home-b.json";
import rollingFinal from "../../game/tests/fixtures/cooperative/rolling-home-final-checkpoint.json";
import houseDefinition from "../../game/tests/fixtures/cooperative/a-house-for-two-definition.json";
import houseInitial from "../../game/tests/fixtures/cooperative/a-house-for-two-initial-checkpoint.json";
import openA from "../../game/tests/fixtures/cooperative/open-the-house-a.json";
import openB from "../../game/tests/fixtures/cooperative/open-the-house-b.json";
import houseMiddle from "../../game/tests/fixtures/cooperative/open-the-house-checkpoint.json";
import belowA from "../../game/tests/fixtures/cooperative/the-room-below-a.json";
import belowB from "../../game/tests/fixtures/cooperative/the-room-below-b.json";
import houseFinal from "../../game/tests/fixtures/cooperative/a-house-for-two-final-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
const key = () => crypto.randomUUID(), source = "d".repeat(40), CODE = "SYNTHETIC-COOPERATIVE-TESTER";
const cases = [
  { adapter: highAndLow, definition: highDefinition, initial: highInitial, a: highA, b: highB, middle: highMiddle, a2: lowA, b2: lowB, final: highFinal },
  { adapter: rollingHome, definition: rollingDefinition, initial: rollingInitial, a: weightA, b: weightB, middle: rollingMiddle, a2: homeA, b2: homeB, final: rollingFinal },
  { adapter: houseForTwo, definition: houseDefinition, initial: houseInitial, a: openA, b: openB, middle: houseMiddle, a2: belowA, b2: belowB, final: houseFinal }
];
const playConfig = { REVENUECAT_VERIFICATION_MODE: "play_store", REVENUECAT_SECRET_KEY: "synthetic-only", REVENUECAT_PROJECT_ID: "projSynthetic", REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID: "entlPlay", REVENUECAT_PLAY_PRODUCT_ID: "prodPlay", REVENUECAT_PLAY_ENVIRONMENT: "production" };
let requestNo = 0;
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true", HOUSE_CHAPTER_ENABLED: "true", ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.1." + ++requestNo,
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }),
  configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function grant(host: Account): Promise<void> {
  expect((await call("/v1/tester-access", "POST", host, { schema_version: 1, code: CODE }, { TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE) })).status).toBe(200);
}
async function newRoom(host: Account, selected: ChapterAdapter, idempotency_key = key(), overrides: Record<string, unknown> = {}): Promise<RoomSnapshotV2> {
  const response = await call("/v2/rooms", "POST", host, { ...selected.key, idempotency_key }, overrides); expect(response.status).toBe(200); return response.json<RoomSnapshotV2>();
}
function turn(room: RoomSnapshotV2, recording: unknown, checkpoint?: unknown) { return { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) }; }
async function submit(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown, overrides: Record<string, unknown> = {}): Promise<MutationV2> {
  const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, turn(room, recording, checkpoint), overrides); expect(response.status).toBe(200); return response.json<MutationV2>();
}
async function pair(selected: ChapterAdapter, tester = true, overrides: Record<string, unknown> = {}) {
  const host = await account(), guest = await account(); if (selected.premium && tester) await grant(host);
  const created = await newRoom(host, selected, key(), overrides);
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: created.invite_code, supported_simulation_versions: [2, 4, 5, 6] }); expect(joined.status).toBe(200);
  return { host, guest, room: await joined.json<RoomSnapshotV2>() };
}
async function complete(fixture: typeof cases[number]) {
  const { host, guest, room } = await pair(fixture.adapter);
  const a = await submit(room, host, fixture.a), b = await submit(a.room, guest, fixture.b, fixture.middle);
  const c = await submit(b.room, guest, fixture.a2), d = await submit(c.room, host, fixture.b2, fixture.final);
  return { host, guest, initial: room, room: d.room, responses: [a, b, c, d] };
}
async function rehash<T extends Record<string, unknown>>(input: T, hashKey = "recording_hash"): Promise<T> {
  const body = { ...input }; delete body[hashKey]; if (hashKey === "checkpoint_hash") delete body.proof;
  return { ...input, [hashKey]: await digest(canonicalJson(body)) };
}
async function recover(owner: Account): Promise<Account> {
  const next = { ...owner, device_token: randomToken(), recovery_code: randomToken() };
  const response = await call("/v1/identity/recover", "POST", undefined, { player_id: owner.player_id, recovery_code: owner.recovery_code, idempotency_key: key(), next_device_token: next.device_token, next_recovery_code: next.recovery_code }); expect(response.status).toBe(200); return next;
}
function provider(access: boolean | (() => boolean) = true) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => Response.json((url instanceof Request ? url.url : String(url)).includes("active_entitlements") ?
    { object: "list", items: (typeof access === "function" ? access() : access) ? [{ entitlement_id: "entlPlay", expires_at: null }] : [], next_page: null } :
    { object: "list", items: [{ object: "purchase", product_id: "prodPlay", store: "play_store", environment: "production", status: "owned", ownership: "purchased", purchased_at: Date.now() - 10000 }], next_page: null }));
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("bounded cooperative chapters", () => {
  it("keeps rollout off by default, independent from First Steps, with authored free/paid metadata", async () => {
    expect(env.COOP_CHAPTERS_ENABLED).toBe("false");
    expect(env.HOUSE_CHAPTER_ENABLED).toBe("false");
    const host = await account(), off = { COOP_CHAPTERS_ENABLED: "false", HOUSE_CHAPTER_ENABLED: "false", FIRST_STEPS_ENABLED: "true" };
    const before = await (await call("/v2/capabilities", "GET", host, undefined, off)).json<{ chapters: { level_id: string }[] }>();
    expect(before.chapters.map(c => c.level_id)).toEqual(["relay-isles", "first-steps"]);
    for (const selected of [highAndLow, rollingHome, houseForTwo]) expect((await call("/v2/rooms", "POST", host, { ...selected.key, idempotency_key: key() }, off)).status).toBe(503);
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual([]);
    const on = await (await call("/v2/capabilities", "GET", host)).json<{ chapters: Record<string, unknown>[] }>();
    expect(on.chapters).toEqual([{ ...RELAY_KEY, premium: false, recording_version: 2, simulation_version: 2, supported_simulation_versions: [2, 8] },
      { ...highAndLow.key, premium: false, recording_version: 6, simulation_version: 6, supported_simulation_versions: [6, 8] }, { ...rollingHome.key, premium: true, recording_version: 6, simulation_version: 6, supported_simulation_versions: [6, 8] },
      { ...houseForTwo.key, premium: true, recording_version: 6, simulation_version: 6, supported_simulation_versions: [6, 8] }]);
  });
  it("gates House independently and preserves existing chapter availability", async () => {
    const host = await account(), off = { HOUSE_CHAPTER_ENABLED: "false" };
    const before = await (await call("/v2/capabilities", "GET", host, undefined, off)).json<{ chapters: { level_id: string }[] }>();
    expect(before.chapters.map(c => c.level_id)).toEqual(["relay-isles", "high-and-low", "rolling-home"]);
    expect((await call("/v2/rooms", "POST", host, { ...houseForTwo.key, idempotency_key: key() }, off)).status).toBe(503);
    await grant(host);
    const onlyHouse = { COOP_CHAPTERS_ENABLED: "false" };
    const enabled = await (await call("/v2/capabilities", "GET", host, undefined, onlyHouse)).json<{ chapters: { level_id: string }[] }>();
    expect(enabled.chapters.map(c => c.level_id)).toEqual(["relay-isles", "a-house-for-two"]);
    const room = await newRoom(host, houseForTwo, key(), onlyHouse);
    expect(await (await call(`/v2/rooms/${room.room_id}`, "GET", host, undefined, off)).json()).toEqual(room);
  });
  it.each(cases)("pins native definitions, all recording bytes and the two-stage proof chain ($adapter.key.level_id)", async fixture => {
    expect(await digest(canonicalJson(fixture.definition))).toBe(fixture.adapter.key.definition_hash);
    expect(chapter(fixture.adapter.key)).toBe(fixture.adapter); expect(initialCheckpoint(fixture.adapter.key)).toEqual(fixture.initial);
    const records = await Promise.all([fixture.a, fixture.b, fixture.a2, fixture.b2].map(record => recordingV2(record, fixture.adapter.key)));
    records.forEach((record, i) => { expect(record).toEqual([fixture.a, fixture.b, fixture.a2, fixture.b2][i]); expect(acceptedRecording(record)).toBe(true); });
    const middle = await checkpointV2(fixture.middle, initialCheckpoint(fixture.adapter.key), records[0], records[1]); expect(middle).toEqual(fixture.middle);
    expect(await checkpointV2(fixture.final, middle, records[2], records[3])).toEqual(fixture.final);
  });
  it.each(cases)("requires simulation6 support before reserving a guest seat ($adapter.key.level_id)", async fixture => {
    const host = await account(), guest = await account(); if (fixture.adapter.premium) await grant(host);
    const room = await newRoom(host, fixture.adapter);
    for (const versions of [undefined, [2, 4, 5]]) {
      const rejected = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, ...(versions ? { supported_simulation_versions: versions } : {}) });
      expect(rejected.status).toBe(422); expect(await rejected.json()).toMatchObject({ error: { code: "unsupported_simulation_version" } });
      expect(await env.PLAYERS.getByName(guest.player_id).listRooms()).toEqual([]); expect(value(await env.ROOMS_V2.getByName(room.room_id).snapshot(host.player_id))).toEqual(room);
    }
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: [6] })).status).toBe(200);
  });
  it.each(cases)("runs both role-swapped stages, protects invitations and preserves collection/retry bytes ($adapter.key.level_id)", async fixture => {
    const { host, guest, room } = await pair(fixture.adapter), stranger = await account(), path = `/v2/rooms/${room.room_id}`;
    expect((await call(path, "GET", stranger)).status).toBe(404);
    expect((await call("/v2/rooms/join", "POST", stranger, { invite_code: "F".repeat(20), supported_simulation_versions: [6] })).status).toBe(404);
    const hostView = await (await call(path, "GET", host)).json<RoomSnapshotV2>();
    expect(room.invite_code).toBeUndefined(); expect(hostView.invite_code).toMatch(/^[A-F0-9]{20}$/);
    expect((await call("/v2/rooms/join", "POST", stranger, { invite_code: hostView.invite_code, supported_simulation_versions: [6] })).status).toBe(409);
    expect(await env.PLAYERS.getByName(stranger.player_id).listRooms()).toEqual([]);
    expect((await call(path + "/turns", "POST", guest, turn(room, fixture.a))).status).toBe(409);
    const body = turn(room, fixture.a), aResponse = await call(path + "/turns", "POST", host, body); expect(aResponse.status).toBe(200); const a = await aResponse.json<MutationV2>();
    expect(a.room.recording_a).toEqual(fixture.a);
    const b = await submit(a.room, guest, fixture.b, fixture.middle); expect(b.room.active_player_id).toBe(guest.player_id);
    const c = await submit(b.room, guest, fixture.a2), d = await submit(c.room, host, fixture.b2, fixture.final);
    expect(d.room).toMatchObject({ stage_index: 2, active_role: "complete", checkpoint: fixture.final });
    const retry = await call(path + "/turns", "POST", host, body, { COOP_CHAPTERS_ENABLED: "false", HOUSE_CHAPTER_ENABLED: "false" }); expect(retry.status).toBe(200); expect(await retry.json()).toEqual({ receipt: a.receipt, room: d.room });
    expect((await call(path + "/turns", "POST", host, { ...body, branch: 1 })).status).toBe(409);
    const collection = await (await call(path + "/collection", "GET", host)).json<{ pairs: unknown[] }>(); expect(collection.pairs).toHaveLength(2);
    expect(await (await call(path + "/pairs/p0-0", "GET", guest)).json()).toMatchObject({ a: fixture.a, b: fixture.b, checkpoint: fixture.middle });
  });
  it.each(cases)("roundtrips snapshots, forks from a retained checkpoint and keeps original receipts ($adapter.key.level_id)", async fixture => {
    const done = await complete(fixture), stub = env.ROOMS_V2.getByName(done.room.room_id);
    const forkBody = { base_revision: done.room.revision, branch: done.room.branch, stage_index: 1, idempotency_key: key() };
    const forkResponse = await call(`/v2/rooms/${done.room.room_id}/fork`, "POST", done.host, forkBody); expect(forkResponse.status).toBe(200); const fork = await forkResponse.json<MutationV2>();
    expect(fork.room).toMatchObject({ branch: 1, stage_index: 1, checkpoint: fixture.middle, active_player_id: done.guest.player_id });
    const a = await submit(fork.room, done.guest, fixture.a2); await submit(a.room, done.host, fixture.b2, fixture.final);
    const archive = value(await stub.exportSnapshot(source)), saved = JSON.parse(archive) as RoomV2Archive;
    expect(saved.payload).toMatchObject({ format_version: 5, database_schema_version: 3 });
    const restored = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()); expect(await restored.restoreSnapshot(archive, done.room.room_id)).toMatchObject({ ok: true });
    expect((JSON.parse(value(await restored.exportSnapshot(source))) as RoomV2Archive).payload.tables).toEqual(saved.payload.tables);
    expect(value(await restored.operation(done.host.player_id, done.responses[0].receipt.idempotency_key)).receipt).toEqual(done.responses[0].receipt);
    expect(value(await restored.collection(done.host.player_id)).pairs).toHaveLength(3);
    const playerArchive = value(await env.PLAYERS.getByName(done.host.player_id).exportSnapshot(source)), playerCopy = env.PLAYERS.get(env.PLAYERS.newUniqueId());
    expect(await playerCopy.restoreSnapshot(playerArchive, done.host.player_id)).toMatchObject({ ok: true });
    expect((JSON.parse(value(await playerCopy.exportSnapshot(source))) as PortableSnapshot).payload.tables).toEqual((JSON.parse(playerArchive) as PortableSnapshot).payload.tables);
  });
  it("rejects chapter, role, outcome, chain, geometry and mechanism tampering without changing stored progress", async () => {
    await expect(recordingV2(highA, rollingHome.key)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
    await expect(recordingV2({ ...highA, duration_ticks: highA.duration_ticks + 1 })).rejects.toMatchObject({ code: "action_duration_mismatch" });
    await expect(recordingV2(await rehash({ ...highA, player_slot: "p1" }))).rejects.toMatchObject({ code: "wrong_player_slot" });
    const { host, guest, room } = await pair(highAndLow), path = `/v2/rooms/${room.room_id}`;
    const failed = await rehash({ ...highA, outcome: { source_ready: false, objective_complete: false } });
    expect((await call(path + "/turns", "POST", host, turn(room, failed))).status).toBe(422);
    const a = await submit(room, host, highA);
    const badProof = structuredClone(highMiddle); badProof.proof.a.recording_hash = "f".repeat(64);
    expect((await call(path + "/turns", "POST", guest, turn(a.room, highB, badProof))).status).toBe(422);
    const badHeight = structuredClone(highMiddle); badHeight.players.p1.height += 1;
    expect((await call(path + "/turns", "POST", guest, turn(a.room, highB, await rehash(badHeight, "checkpoint_hash")))).status).toBe(422);
    const badMechanism = structuredClone(highMiddle); badMechanism.mechanisms.latched_bridges.push("invented-bridge");
    expect((await call(path + "/turns", "POST", guest, turn(a.room, highB, await rehash(badMechanism, "checkpoint_hash")))).status).toBe(422);
    expect(value(await env.ROOMS_V2.getByName(room.room_id).snapshot(host.player_id))).toEqual(a.room);
  });
  it("retains packet, proof depth and structural node caps", async () => {
    expect([MAX_RECORDING_BYTES, MAX_CHECKPOINT_BYTES, MAX_V2_BODY_BYTES]).toEqual([49152, 229376, 327680]);
    let nested: unknown = {}; for (let i = 0; i < 18; i++) nested = { nested };
    expect(() => boundedValue(nested, MAX_CHECKPOINT_BYTES)).toThrowError();
    expect(() => boundedValue(Array.from({ length: 24001 }, () => 0), MAX_CHECKPOINT_BYTES)).toThrowError();
    const huge = { ...highA, actions: Array.from({ length: 600 }, () => ({ ticks: 1, x: 0, z: 0, action: false })), replay_checks: Array.from({ length: 600 }, (_, i) => ({ tick: i + 1, state_hash: "a".repeat(64) })) };
    await expect(recordingV2(huge)).rejects.toMatchObject({ status: 413 });
    const { host, room } = await pair(highAndLow);
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { padding: "x".repeat(MAX_V2_BODY_BYTES) })).status).toBe(413);
  });
  it("requires the named second House plate and exact claimed final weight without weakening published props", async () => {
    const { host, guest, room } = await pair(houseForTwo), path = `/v2/rooms/${room.room_id}`;
    const first = await submit(room, host, openA);
    const wrongPlate = structuredClone(houseMiddle);
    Object.assign(wrongPlate.mechanisms.props["house-ball"], { x: -288, z: 112 });
    expect((await call(path + "/turns", "POST", guest, turn(first.room, openB, await rehash(wrongPlate, "checkpoint_hash")))).status).toBe(422);
    expect(value(await env.ROOMS_V2.getByName(room.room_id).snapshot(host.player_id))).toEqual(first.room);
    const middle = await submit(first.room, guest, openB, houseMiddle), second = await submit(middle.room, guest, belowA);
    const retained = value(await env.ROOMS_V2.getByName(room.room_id).snapshot(host.player_id));
    for (const changes of [{ status: "free", holder_slot: "" }, { status: "fitted", holder_slot: "", socket_id: "sunroom-weight" }, { holder_slot: "p1" }, { x: 464, z: 0 }]) {
      const invalid = structuredClone(houseFinal); Object.assign(invalid.mechanisms.props["house-ball"], changes);
      expect((await call(path + "/turns", "POST", host, turn(second.room, belowB, await rehash(invalid, "checkpoint_hash")))).status).toBe(422);
      expect(value(await env.ROOMS_V2.getByName(room.room_id).snapshot(host.player_id))).toEqual(retained);
    }
    expect((await submit(second.room, host, belowB, houseFinal)).room.active_role).toBe("complete");
    await expect(recordingV2(openA, rollingHome.key)).rejects.toMatchObject({ code: "recording_chapter_mismatch" });
    const oldFinal = structuredClone(rollingFinal);
    Object.assign(oldFinal.mechanisms.props["round-ball"], { status: "claimed", holder_slot: "p0", socket_id: "" });
    await expect(checkpointV2(await rehash(oldFinal, "checkpoint_hash"), rollingMiddle as ChapterCheckpoint, homeA as ChapterRecording, homeB as ChapterRecording)).rejects.toMatchObject({ code: "checkpoint_prop_mismatch" });
  });
  it.each(cases)("fits maximum 900-tick encodings and a full two-stage proof without widening caps ($adapter.key.level_id)", async fixture => {
    // Deliberately synthetic state hashes: this tests the maximum valid wire
    // encoding and structural admission, not a claim that these inputs solve
    // the native level. Native solution/replay evidence lives in the fixtures.
    const stateHash = "f".repeat(64);
    async function maximumRecord(base: Record<string, unknown>, previous: ChapterCheckpoint, sourceHash = ""): Promise<ChapterRecording> {
      return recordingV2(await rehash({ ...base, checkpoint_hash: previous.checkpoint_hash, source_recording_hash: sourceHash,
        duration_ticks: 900, catch_assistance: false,
        // Adjacent frames differ, so the native RLE writer cannot merge them.
        actions: Array.from({ length: 900 }, (_, i) => ({ ticks: 1, x: -100, z: i % 2 ? -99 : -100, action: false })),
        // Include the envelope's extra check allowance as well as its native
        // 30-tick cadence, so even the admitted worst case stays bounded.
        replay_checks: [{ tick: 1, state_hash: stateHash }, ...Array.from({ length: 30 }, (_, i) => ({ tick: (i + 1) * 30, state_hash: stateHash }))], final_state_hash: stateHash }), fixture.adapter.key);
    }
    async function nextCheckpoint(base: Record<string, unknown>, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording): Promise<ChapterCheckpoint> {
      return checkpointV2(await rehash({ ...base, previous_checkpoint_hash: previous.checkpoint_hash, a_recording_hash: a.recording_hash, b_recording_hash: b.recording_hash,
        proof: { checkpoint: previous, a, b } }, "checkpoint_hash"), previous, a, b);
    }
    const initial = initialCheckpoint(fixture.adapter.key), a1 = await maximumRecord(fixture.a, initial), b1 = await maximumRecord(fixture.b, initial, a1.recording_hash);
    const middle = await nextCheckpoint(fixture.middle, initial, a1, b1), a2 = await maximumRecord(fixture.a2, middle), b2 = await maximumRecord(fixture.b2, middle, a2.recording_hash);
    const final = await nextCheckpoint(fixture.final, middle, a2, b2);
    function assertBounds(value: unknown, bytes: number) {
      let nodes = 0, depth = 0; const pending = [{ value, depth: 0 }];
      while (pending.length) {
        const item = pending.pop()!; nodes++; depth = Math.max(depth, item.depth);
        if (item.value !== null && typeof item.value === "object") for (const child of Object.values(item.value)) pending.push({ value: child, depth: item.depth + 1 });
      }
      const size = new TextEncoder().encode(JSON.stringify(value)).byteLength;
      expect(size).toBeLessThanOrEqual(bytes);
      expect(nodes).toBeLessThanOrEqual(24000); expect(depth).toBeLessThanOrEqual(16);
      expect(() => boundedValue(value, bytes)).not.toThrow();
      return { bytes: size, nodes, depth };
    }
    for (const record of [a1, b1, a2, b2]) { expect(record.actions).toHaveLength(900); expect(record.replay_checks).toHaveLength(31); assertBounds(record, MAX_RECORDING_BYTES); }
    const finalSize = assertBounds(final, MAX_CHECKPOINT_BYTES);
    const packet = { base_revision: Number.MAX_SAFE_INTEGER, branch: 31, idempotency_key: "k".repeat(80), recording: b2, checkpoint: final };
    const packetSize = assertBounds(packet, MAX_V2_BODY_BYTES);
    if (fixture.adapter === houseForTwo) console.log("House maximum wire envelope", { record: assertBounds(b2, MAX_RECORDING_BYTES), checkpoint: finalSize, packet: packetSize });
    // Reject the next check and tick rather than widening the envelope.
    const with32 = await rehash({ ...a1, replay_checks: [{ tick: 1, state_hash: stateHash }, { tick: 2, state_hash: stateHash }, ...a1.replay_checks.slice(1)] });
    await expect(recordingV2(with32)).rejects.toMatchObject({ code: "invalid_replay_checks" });
    await expect(recordingV2(await rehash({ ...a1, duration_ticks: 901, actions: [...a1.actions, { ticks: 1, x: 0, z: 0, action: false }] }))).rejects.toMatchObject({ status: 400, code: "invalid_integer" });
  });
});

describe.each(cases.filter(fixture => fixture.adapter.premium))("host-owned cooperative access ($adapter.key.level_id)", fixture => {
  it("keeps the free chapter available without a purchase/provider and rejects denied paid creation without leaving room links", async () => {
    const host = await account(), requests = provider(false);
    await newRoom(host, highAndLow); expect(requests).not.toHaveBeenCalled();
    const before = await env.PLAYERS.getByName(host.player_id).listRooms();
    const denied = await call("/v2/rooms", "POST", host, { ...fixture.adapter.key, idempotency_key: key() }, playConfig); expect(denied.status).toBe(402); expect(await denied.json()).toMatchObject({ error: { code: "host_unlock_required" } });
    requests.mockResolvedValue(new Response(null, { status: 503 }));
    const unavailable = await call("/v2/rooms", "POST", host, { ...fixture.adapter.key, idempotency_key: key() }, playConfig); expect(unavailable.status).toBe(503); expect(await unavailable.json()).toMatchObject({ error: { code: "entitlement_unavailable" } });
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual(before);
  });
  it("uses only the host's verified Play purchase while the guest joins and takes turns without buying", async () => {
    const requests = provider(), { host, guest, room } = await pair(fixture.adapter, false, playConfig);
    expect(requests).toHaveBeenCalledTimes(2);
    const a = await submit(room, host, fixture.a, undefined, playConfig), b = await submit(a.room, guest, fixture.b, fixture.middle, playConfig);
    expect(b.room.stage_index).toBe(1); expect(requests).toHaveBeenCalledTimes(6);
    for (const [input] of requests.mock.calls) { const url = input instanceof Request ? input.url : String(input); expect(url).toContain(`/customers/${host.player_id}/`); expect(url).not.toContain(guest.player_id); }
    expect(await env.PLAYERS.getByName(guest.player_id).storedTesterGrant(guest.player_id)).toBeNull();
  });
  it("rejects creation key reuse across free/paid chapters before contacting a purchase provider", async () => {
    const host = await account(), creationKey = key(), room = await newRoom(host, highAndLow, creationKey), requests = provider(false);
    const response = await call("/v2/rooms", "POST", host, { ...fixture.adapter.key, idempotency_key: creationKey }, playConfig);
    expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ error: { code: "idempotency_chapter_mismatch" } }); expect(requests).not.toHaveBeenCalled();
    expect((await env.PLAYERS.getByName(host.player_id).listRooms()).map(link => link.room_id)).toEqual([room.room_id]);
  });
  it("returns retained creation and accepted turn/fork receipts without repeating payment checks after access loss", async () => {
    const requests = provider(), host = await account(), guest = await account(), creationKey = key(), created = await newRoom(host, fixture.adapter, creationKey, playConfig);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: created.invite_code, supported_simulation_versions: [6] }); const room = await joined.json<RoomSnapshotV2>();
    const body = turn(room, fixture.a), aResponse = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body, playConfig); expect(aResponse.status).toBe(200); const a = await aResponse.json<MutationV2>();
    const forkBody = { base_revision: a.room.revision, branch: a.room.branch, stage_index: 0, idempotency_key: key() }, forkResponse = await call(`/v2/rooms/${room.room_id}/fork`, "POST", host, forkBody, playConfig); expect(forkResponse.status).toBe(200); const fork = await forkResponse.json<MutationV2>();
    requests.mockClear().mockResolvedValue(new Response(null, { status: 503 }));
    expect(await newRoom(host, fixture.adapter, creationKey, playConfig)).toEqual(fork.room);
    expect(await (await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body, playConfig)).json()).toEqual({ receipt: a.receipt, room: fork.room });
    expect(await (await call(`/v2/rooms/${room.room_id}/fork`, "POST", host, forkBody, playConfig)).json()).toEqual(fork);
    expect(requests).not.toHaveBeenCalled();
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { ...body, branch: 1 }, playConfig)).status).toBe(409); expect(requests).not.toHaveBeenCalled();
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, turn(fork.room, fixture.a), playConfig)).status).toBe(503);
    expect((await call(`/v2/rooms/${room.room_id}/fork`, "POST", host, { ...forkBody, base_revision: fork.room.revision, branch: fork.room.branch, idempotency_key: key() }, playConfig)).status).toBe(503);
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", guest)).status).toBe(200); expect((await call(`/v2/rooms/${room.room_id}/operations/${a.receipt.idempotency_key}`, "GET", host)).status).toBe(200);
  });
  it("preserves the tester grant and exact room after recovery and eviction without another purchase", async () => {
    const { host, guest, room } = await pair(fixture.adapter), requests = provider(false), next = await recover(host);
    await evictDurableObject(env.PLAYERS.getByName(host.player_id)); await evictDurableObject(env.ROOMS_V2.getByName(room.room_id));
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", host)).status).toBe(401);
    const a = await submit(room, next, fixture.a), b = await submit(a.room, guest, fixture.b, fixture.middle);
    expect(b.room.stage_index).toBe(1); expect(requests).not.toHaveBeenCalled();
    expect((await call(`/v2/rooms/${room.room_id}`, "DELETE", next)).status).toBe(200); expect((await call(`/v2/rooms/${room.room_id}`, "GET", guest)).status).toBe(404);
  });
  it("admits the same retained turn once host access returns and never creates a duplicate receipt", async () => {
    let owned = true; const requests = provider(() => owned), { host, room } = await pair(fixture.adapter, false, playConfig), body = turn(room, fixture.a), path = `/v2/rooms/${room.room_id}`;
    owned = false;
    expect((await call(path + "/turns", "POST", host, body, playConfig)).status).toBe(402);
    expect((await call(path + "/operations/" + body.idempotency_key, "GET", host)).status).toBe(404);
    expect(value(await env.ROOMS_V2.getByName(room.room_id).snapshot(host.player_id)).revision).toBe(room.revision);
    owned = true;
    const accepted = await call(path + "/turns", "POST", host, body, playConfig); expect(accepted.status).toBe(200); const result = await accepted.json<MutationV2>();
    requests.mockClear();
    expect(await (await call(path + "/turns", "POST", host, body, playConfig)).json()).toEqual(result); expect(requests).not.toHaveBeenCalled();
    expect(result.room.revision).toBe(room.revision + 1);
  });
  it("rejects stale credentials when recovery happens during paid creation lookup", async () => {
    const host = await account(); let rotated = false;
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => { if (!rotated) { rotated = true; await recover(host); } return Response.json({ object: "list", items: [{ entitlement_id: "entlPlay", expires_at: null }], next_page: null }); });
    const response = await call("/v2/rooms", "POST", host, { ...fixture.adapter.key, idempotency_key: key() }, { ...playConfig, REVENUECAT_REVIEWER_IDS: host.player_id });
    expect(response.status).toBe(401); expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual([]);
  });
  it("rejects a new turn after credential recovery during the host's purchase lookup", async () => {
    const requests = provider(), { host, room } = await pair(fixture.adapter, false, playConfig); let next: Account | undefined;
    requests.mockImplementation(async () => { if (!next) next = await recover(host); return Response.json({ object: "list", items: [{ entitlement_id: "entlPlay", expires_at: null }], next_page: null }); });
    const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, turn(room, fixture.a), { ...playConfig, REVENUECAT_REVIEWER_IDS: host.player_id });
    expect(response.status).toBe(401); expect(value(await env.ROOMS_V2.getByName(room.room_id).snapshot(host.player_id)).revision).toBe(room.revision);
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", next)).status).toBe(200);
  });
});
