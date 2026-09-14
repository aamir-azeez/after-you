import { env } from "cloudflare:workers";
import { reset, evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, type RoomSnapshot } from "../src/protocol";
import { DEFINITION_HASH, MAX_V2_BODY_BYTES, RELAY, checkpointV2, initialCheckpoint, recordingV2 } from "../src/v2/protocol";
import type { MutationV2, PairV2, RoomSnapshotV2 } from "../src/v2/room";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import initialFixture from "../../game/tests/fixtures/v2/initial-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
const key = () => crypto.randomUUID();
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, enabled = true, rooms = env.ROOMS_V2): Promise<Response> {
  const configured: Env = { ...env };
  // Wrangler infers the literal default "false"; the deployed variable can also
  // be "true". Exercise that runtime configuration without altering the DO data.
  Object.assign(configured, { V2_ROOMS_ENABLED: enabled ? "true" : "false" });
  configured.ROOMS_V2 = rooms;
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + ++address,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body)
  }), configured);
}
async function create(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
const creation = (idempotency_key = key()) => ({ idempotency_key, level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
async function newRoom(host: Account): Promise<RoomSnapshotV2> {
  const result = await call("/v2/rooms", "POST", host, creation()); expect(result.status).toBe(200); return result.json<RoomSnapshotV2>();
}
async function pair() {
  const host = await create(), guest = await create(), room = await newRoom(host);
  const result = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }); expect(result.status).toBe(200);
  return { host, guest, room: await result.json<RoomSnapshotV2>() };
}
function body(room: RoomSnapshotV2, recording: unknown, checkpoint?: unknown, idempotency_key = key()) {
  return { base_revision: room.revision, branch: room.branch, idempotency_key, recording, ...(checkpoint === undefined ? {} : { checkpoint }) };
}
async function submit(room: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  const result = await call(`/v2/rooms/${room.room_id}/turns`, "POST", account, body(room, recording, checkpoint));
  expect(result.status).toBe(200); return result.json<MutationV2>();
}
async function complete() {
  const { host, guest, room } = await pair();
  const a = await submit(room, host, firstA);
  const b = await submit(a.room, guest, firstB, middle);
  const c = await submit(b.room, guest, secondA);
  const d = await submit(c.room, host, secondB, final);
  return { host, guest, room: d.room, responses: [a, b, c, d] };
}
async function rehash<T extends Record<string, unknown>>(value: T, hashKey = "recording_hash"): Promise<T> {
  const data: Record<string, unknown> = structuredClone(value); delete data[hashKey];
  if (hashKey === "checkpoint_hash") delete data.proof;
  return { ...value, [hashKey]: await digest(canonicalJson(data)) };
}
afterEach(async () => { await reset(); });

describe("v2 Relay Isles coordination in Workers", () => {
  it("pins the exact native catalog and initial checkpoint hashes", async () => {
    expect(await digest(canonicalJson(RELAY))).toBe(DEFINITION_HASH);
    expect(initialCheckpoint()).toEqual(initialFixture);
    for (const recording of [firstA, firstB, secondA, secondB]) expect(await recordingV2(recording)).toEqual(recording);
    const a = await recordingV2(firstA), b = await recordingV2(firstB);
    const checkpoint = await checkpointV2(middle, initialCheckpoint(), a, b);
    expect(checkpoint).toEqual(middle);
    expect(await checkpointV2(final, checkpoint, await recordingV2(secondA), await recordingV2(secondB))).toEqual(final);
    expect(a.source_recording_hash).toBe("");
  });
  it("keeps mutations off by default and requires authentication", async () => {
    const host = await create();
    expect((await call("/v2/rooms", "POST", host, creation(), false)).status).toBe(503);
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual([]);
    expect((await call("/v2/rooms")).status).toBe(401);
    expect(await (await call("/v2/capabilities", "GET", host, undefined, false)).json()).toMatchObject({ mutations_enabled: false, validation: "structural_client_replay_required" });
  });
  it("rejects unsupported chapters before reserving a link and gives stable creation retries", async () => {
    const host = await create();
    for (const changed of [{ level_id: "invented" }, { level_version: 3 }, { definition_hash: "a".repeat(64) }, { premium: false }]) {
      const response = await call("/v2/rooms", "POST", host, { ...creation(), ...changed });
      expect([400, 422]).toContain(response.status);
    }
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual([]);
    const request = creation(), first = await (await call("/v2/rooms", "POST", host, request)).json<RoomSnapshotV2>();
    const retry = await (await call("/v2/rooms", "POST", host, request)).json<RoomSnapshotV2>();
    expect(retry).toEqual(first);
    expect((await call("/v1/rooms", "POST", host, { idempotency_key: request.idempotency_key })).status).toBe(409);
  });
  it("lets the host leave A before joining while protecting membership and stable slots", async () => {
    const host = await create(), guest = await create(), stranger = await create(), room = await newRoom(host);
    const first = await submit(room, host, firstA);
    expect(first.room).toMatchObject({ active_role: "b", active_player_id: null });
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", stranger)).status).toBe(404);
    expect((await call(`/v2/rooms/${room.room_id}/collection`, "GET", stranger)).status).toBe(404);
    const joined = await (await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).json<RoomSnapshotV2>();
    expect(joined).toMatchObject({ player_slot: "p1", active_player_id: guest.player_id, first_player_id: host.player_id, recording_a: firstA });
    expect(joined.invite_code).toBeUndefined();
    expect((await call("/v2/rooms/join", "POST", stranger, { invite_code: room.invite_code })).status).toBe(409);
    expect((await env.PLAYERS.getByName(stranger.player_id).listRooms())).toEqual([]);
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(joined, firstB, middle))).status).toBe(409);
  });
  it("commits both native fixture pairs unchanged and alternates stage leadership", async () => {
    const result = await complete(), [a, b, c, d] = result.responses;
    expect(a.room.recording_a).toEqual(firstA);
    expect(b.room).toMatchObject({ stage_id: "garden", stage_index: 1, active_role: "a", active_player_id: result.guest.player_id, checkpoint: middle });
    expect(c.room.recording_a).toEqual(secondA);
    expect(d.room).toMatchObject({ stage_id: "", stage_index: 2, active_role: "complete", active_player_id: null, checkpoint: final });
    const collection = await (await call(`/v2/rooms/${result.room.room_id}/collection`, "GET", result.guest)).json<{ pairs: { pair_id: string }[]; active_pair_ids: string[] }>();
    expect(collection.active_pair_ids).toEqual([b.receipt.pair_id, d.receipt.pair_id]);
    expect(collection.pairs).toHaveLength(2);
    const saved = await (await call(`/v2/rooms/${result.room.room_id}/pairs/${b.receipt.pair_id}`, "GET", result.host)).json<PairV2>();
    expect(saved).toMatchObject({ a: firstA, b: firstB, checkpoint: middle });
    await evictDurableObject(env.ROOMS_V2.getByName(result.room.room_id));
    expect((await (await call(`/v2/rooms/${result.room.room_id}`, "GET", result.host)).json<RoomSnapshotV2>()).checkpoint).toEqual(final);
  });
  it("returns the original receipt after advancement, key reordering and eviction", async () => {
    const { host, guest, room } = await pair(), request = body(room, firstA);
    const first = await (await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, request)).json<MutationV2>();
    const advanced = await submit(first.room, guest, firstB, middle);
    await evictDurableObject(env.ROOMS_V2.getByName(room.room_id));
    const reordered = { ...request, recording: Object.fromEntries(Object.entries(firstA).reverse()) };
    const retry = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, reordered);
    expect(retry.status).toBe(200);
    const value = await retry.json<MutationV2>();
    expect(value.receipt).toEqual(first.receipt); expect(value.room.revision).toBe(advanced.room.revision);
    expect(value.room.stage_id).toBe("garden");
    const lookup = await (await call(`/v2/rooms/${room.room_id}/operations/${request.idempotency_key}`, "GET", host, undefined, false)).json<MutationV2>();
    expect(lookup.receipt).toEqual(first.receipt);
    expect((await call(`/v2/rooms/${room.room_id}/operations/${request.idempotency_key}`, "GET", guest)).status).toBe(404);
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { ...request, base_revision: room.revision + 1 })).status).toBe(409);
  });
  it("preserves a B acknowledgement after the following stage has accepted A", async () => {
    const { host, guest, room } = await pair(); const a = await submit(room, host, firstA), request = body(a.room, firstB, middle);
    const b = await (await call(`/v2/rooms/${room.room_id}/turns`, "POST", guest, request)).json<MutationV2>();
    await submit(b.room, guest, secondA);
    const retry = await call(`/v2/rooms/${room.room_id}/turns`, "POST", guest, request);
    expect(retry.status).toBe(200); expect((await retry.json<MutationV2>()).receipt).toEqual(b.receipt);
  });
  it("serializes concurrent turns and leaves no partial state on stale commits", async () => {
    const { host, room } = await pair();
    const results = await Promise.all([call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA)), call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA))]);
    expect(results.map(item => item.status).sort()).toEqual([200, 409]);
    await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_, state) => {
      expect(state.storage.sql.exec("SELECT * FROM turns").toArray()).toHaveLength(1);
      expect(state.storage.sql.exec("SELECT * FROM operations").toArray()).toHaveLength(1);
    });
  });
  it("rejects hashes, missing/extra fields, versions and malformed input before state mutation", async () => {
    const { host, room } = await pair();
    const changes = [ { ...firstA, recording_hash: "0".repeat(64) }, { ...firstA, simulation_version: 1 }, { ...firstA, player_slot: "p1" },
      { ...firstA, duration_ticks: 601 }, { ...firstA, extra: true }, { ...firstA, actions: [{ ticks: 1, x: 101, z: 0, action: false }] },
      { ...firstA, outcome: { ...firstA.outcome, threw_seed: "true" } } ];
    for (const recording of changes) expect([400, 422]).toContain((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, recording))).status);
    const incomplete = await rehash({ ...firstA, outcome: { ...firstA.outcome, threw_seed: false } });
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, incomplete))).status).toBe(422);
    const context = await rehash({ ...firstA, checkpoint_hash: "f".repeat(64) });
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, context))).status).toBe(409);
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { ...body(room, firstA), checkpoint: middle })).status).toBe(400);
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { padding: "x".repeat(MAX_V2_BODY_BYTES) })).status).toBe(413);
    expect((await (await call(`/v2/rooms/${room.room_id}`, "GET", host)).json<RoomSnapshotV2>()).revision).toBe(room.revision);
  });
  it("rejects altered checkpoint lineage, state shapes and exact A substitutions", async () => {
    const { host, guest, room } = await pair(), a = await submit(room, host, firstA);
    const alternateA = await rehash({ ...firstA, actions: [{ ...firstA.actions[0], x: 0 }, ...firstA.actions.slice(1)] });
    const variants = [ { ...middle, stage_index: 2 }, { ...middle, checkpoint_hash: "f".repeat(64) }, { ...middle, proof: { ...middle.proof, a: alternateA } },
      await rehash({ ...middle, players: { ...middle.players, p1: { ...middle.players.p1, x: 100_001 } } }, "checkpoint_hash"),
      await rehash({ ...middle, seed: { status: "held", owner: "p0", socket_id: "" } }, "checkpoint_hash"),
      await rehash({ ...middle, latched_bridges: ["relay-east"] }, "checkpoint_hash") ];
    for (const checkpoint of variants) expect([400, 422]).toContain((await call(`/v2/rooms/${room.room_id}/turns`, "POST", guest, body(a.room, firstB, checkpoint))).status);
    const wrongSource = await rehash({ ...firstB, source_recording_hash: alternateA.recording_hash });
    const altered = await rehash({ ...middle, b_recording_hash: wrongSource.recording_hash, proof: { ...middle.proof, b: wrongSource } }, "checkpoint_hash");
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", guest, body(a.room, wrongSource, altered))).status).toBe(409);
    expect((await (await call(`/v2/rooms/${room.room_id}`, "GET", host)).json<RoomSnapshotV2>()).revision).toBe(a.room.revision);
  });
  it("bounds nested proof trees before recursive canonical hashing", async () => {
    const { host, guest, room } = await pair(), a = await submit(room, host, firstA);
    let nested: unknown = {};
    for (let depth = 0; depth < 30; depth++) nested = { previous_checkpoint: nested };
    const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", guest, body(a.room, firstB, { ...middle, proof: nested }));
    expect(response.status).toBe(413);
    expect(await response.json()).toMatchObject({ error: { code: "structure_too_large" } });
    expect((await (await call(`/v2/rooms/${room.room_id}`, "GET", host)).json<RoomSnapshotV2>()).revision).toBe(a.room.revision);
  });
  it("retains historical pairs and receipts after forking an accepted checkpoint", async () => {
    const { host, guest, room, responses } = await complete();
    const request = { base_revision: room.revision, branch: room.branch, stage_index: 1, idempotency_key: key() };
    const response = await call(`/v2/rooms/${room.room_id}/fork`, "POST", guest, request); expect(response.status).toBe(200);
    const fork = await response.json<MutationV2>();
    expect(fork.room).toMatchObject({ branch: 1, stage_index: 1, checkpoint: middle, active_player_id: guest.player_id, recording_a: null });
    expect(fork.room.completed_pair_ids).toEqual([responses[1].receipt.pair_id]);
    const a = await submit(fork.room, guest, secondA); await submit(a.room, host, secondB, final);
    const retry = await (await call(`/v2/rooms/${room.room_id}/fork`, "POST", guest, request)).json<MutationV2>();
    expect(retry.receipt).toEqual(fork.receipt); expect(retry.room.active_role).toBe("complete");
    const memory = await (await call(`/v2/rooms/${room.room_id}/pairs/${responses[3].receipt.pair_id}`, "GET", host)).json<PairV2>();
    expect(memory.b).toEqual(secondB);
    expect((await call(`/v2/rooms/${room.room_id}/turns`, "POST", guest, body(room, secondA))).status).toBe(409);
  });
  it("keeps v1 and v2 lists distinct and recovery preserves both memberships", async () => {
    const { host, guest, room } = await pair();
    const old = await (await call("/v1/rooms", "POST", host, { idempotency_key: key() })).json<RoomSnapshot>();
    expect((await (await call("/v1/rooms", "GET", host)).json<{ rooms: RoomSnapshot[] }>()).rooms.map(r => r.room_id)).toEqual([old.room_id]);
    expect((await (await call("/v2/rooms", "GET", host)).json<{ rooms: RoomSnapshotV2[] }>()).rooms.map(r => r.room_id)).toEqual([room.room_id]);
    const request = { player_id: host.player_id, recovery_code: host.recovery_code, next_device_token: randomToken(), next_recovery_code: randomToken(), idempotency_key: key() };
    expect((await call("/v1/identity/recover", "POST", undefined, request)).status).toBe(200);
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", host)).status).toBe(401);
    const recovered = { player_id: host.player_id, device_token: request.next_device_token, recovery_code: request.next_recovery_code };
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", recovered)).status).toBe(200);
    expect((await call("/v1/identity", "DELETE", recovered, undefined, false)).status).toBe(200);
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", guest)).status).toBe(404);
    expect((await env.ROOMS.getByName(old.room_id).snapshot(host.player_id)).ok).toBe(false);
    expect((await (await call("/v2/rooms", "GET", guest)).json<{ rooms: unknown[] }>()).rooms).toEqual([]);
  });
  it("erases v2 history and leaves a tombstone that prevents delayed creation", async () => {
    const { host, guest, room } = await complete();
    expect((await call(`/v2/rooms/${room.room_id}`, "DELETE", guest, undefined, false)).status).toBe(200);
    expect((await call(`/v2/rooms/${room.room_id}`, "DELETE", guest, undefined, false)).status).toBe(404);
    expect((await call(`/v2/rooms/${room.room_id}/collection`, "GET", host)).status).toBe(404);
    await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_, state) => {
      for (const table of ["turns", "pairs", "operations"]) expect(state.storage.sql.exec(`SELECT * FROM ${table}`).toArray()).toEqual([]);
      expect(state.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data).toBe('{"deleted":true}');
    });
    const pending = env.ROOMS_V2.getByName("q".repeat(22));
    expect((await pending.eraseForPlayer(host.player_id, true)).ok).toBe(true);
    expect(await pending.initialize("q".repeat(22), host.player_id, "F".repeat(20))).toMatchObject({ ok: false, status: 410 });
  });
  it("tombstones a reserved creation when identity deletion wins before room initialization", async () => {
    const host = await create(), roomId = "n".repeat(22), code = "E".repeat(20);
    const reserved = await env.PLAYERS.getByName(host.player_id).reserveRoom(key(), { room_id: roomId, invite_code: code, host: true, api_version: 2 });
    expect(reserved.ok).toBe(true);
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    expect(await env.ROOMS_V2.getByName(roomId).initialize(roomId, host.player_id, code)).toMatchObject({ ok: false, status: 410 });
    expect((await call("/v2/rooms", "GET", host)).status).toBe(401);
  });
  it("cleans a join accepted after the guest identity was deleted in flight", async () => {
    const host = await create(), guest = await create(), room = await newRoom(host);
    // Interpose only the join boundary while exercising the real HTTP handler,
    // real Player deletion, room mutation, and post-join authorization check.
    const rooms = new Proxy(env.ROOMS_V2, {
      get(target, property) {
        if (property === "getByName") return (name: string) => {
          const stub = target.getByName(name);
          return new Proxy(stub, {
            get(object, method) {
              if (method === "join") return async (player: string, invite: string) => {
                expect((await call("/v1/identity", "DELETE", guest)).status).toBe(200);
                return object.join(player, invite);
              };
              // RPC method proxies are already bound; reading `.bind` attempts
              // a remote method called "bind" rather than Function.bind.
              return Reflect.get(object, method, object);
            }
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      }
    });
    const result = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }, true, rooms);
    expect(result.status).toBe(401);
    expect(await result.json()).toMatchObject({ error: { code: "identity_unavailable" } });
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", host)).status).toBe(404);
    expect((await env.PLAYERS.getByName(guest.player_id).listRooms())).toEqual([]);
  });
});
