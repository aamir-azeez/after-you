import { env, exports } from "cloudflare:workers";
import { reset, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { canonicalJson, digest, type Recording, type RoomSnapshot } from "../src/protocol";
import type { PortableSnapshot } from "../src/snapshot";
import firstA from "../../game/tests/fixtures/first-light-a.json";
import firstB from "../../game/tests/fixtures/first-light-b.json";

type Account = { player_id: string; device_token: string };
let address = 0;
const key = () => crypto.randomUUID();
async function call(path: string, method = "GET", body?: unknown, account?: Account): Promise<Response> {
  const headers: Record<string, string> = { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + (++address) };
  if (account) { headers.Authorization = "Bearer " + account.device_token; headers["X-Player-Id"] = account.player_id; }
  return exports.default.fetch(new Request("https://after-you.test" + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }));
}
const identity = async () => (await call("/v1/identity", "POST", {})).json<Account>();
// These rows exercise the backend's structural/version contract. The Godot
// legacy_cumulative_holds suite verifies real v6 actions and replay hashes.
const record = (role: "a" | "b", version: 1 | 6): Recording => ({ ...(role === "a" ? firstA : firstB), simulation_version: version }) as Recording;
async function submit(room: RoomSnapshot, owner: Account, value: Recording): Promise<Response> {
  return call(`/v1/rooms/${room.room_id}/turns`, "POST", { base_revision: room.revision, idempotency_key: key(), recording: value }, owner);
}
async function pair(version: 1 | 6) {
  const host = await identity(), guest = await identity();
  const response = await call("/v1/rooms", "POST", { idempotency_key: key(), ...(version === 6 ? { simulation_version: 6 } : {}) }, host);
  expect(response.status).toBe(200);
  const created = await response.json<RoomSnapshot>();
  const joined = await call("/v1/rooms/join", "POST", { invite_code: created.invite_code, simulation_version: 6 }, guest);
  expect(joined.status).toBe(200);
  return { host, guest, room: await joined.json<RoomSnapshot>() };
}
async function complete(room: RoomSnapshot, host: Account, guest: Account): Promise<RoomSnapshot> {
  const a = await submit(room, host, record("a", 6)); expect(a.status).toBe(200);
  const b = await submit(await a.json<RoomSnapshot>(), guest, record("b", 6)); expect(b.status).toBe(200);
  return b.json<RoomSnapshot>();
}
afterEach(async () => { await reset(); address = 0; });

describe("Earlier Islands pinned cumulative rules", () => {
  it("keeps old room creation and historical recordings unchanged", async () => {
    const { host, guest, room } = await pair(1);
    expect(room).not.toHaveProperty("simulation_version");
    expect((await submit(room, host, record("a", 6))).status).toBe(422);
    const a = await submit(room, host, record("a", 1)); expect(a.status).toBe(200);
    const b = await submit(await a.json<RoomSnapshot>(), guest, record("b", 1)); expect(b.status).toBe(200);
    expect((await b.json<RoomSnapshot>()).recordings.b).toEqual(firstB);
  });

  it("pins new rooms before their first turn and rejects historical or mixed submissions", async () => {
    const { host, guest, room } = await pair(6);
    expect(room.simulation_version).toBe(6);
    expect((await submit(room, host, record("a", 1))).status).toBe(422);
    const a = await submit(room, host, record("a", 6)); expect(a.status).toBe(200);
    const next = await a.json<RoomSnapshot>();
    expect((await submit(next, guest, record("b", 1))).status).toBe(422);
    expect((await submit(next, guest, record("b", 6))).status).toBe(200);
  });

  it("holds old-client invitations without occupying the guest slot", async () => {
    const host = await identity(), guest = await identity();
    const created = await (await call("/v1/rooms", "POST", { idempotency_key: key(), simulation_version: 6 }, host)).json<RoomSnapshot>();
    const body = { invite_code: created.invite_code };
    expect((await call("/v1/rooms/join", "POST", body, guest)).status).toBe(422);
    const unchanged = await (await call(`/v1/rooms/${created.room_id}`, "GET", undefined, host)).json<RoomSnapshot>();
    expect(unchanged.guest_id).toBeNull(); expect(unchanged.revision).toBe(0);
    expect(await (await call("/v1/rooms", "GET", undefined, guest)).json()).toEqual({ rooms: [] });
    expect((await call("/v1/rooms/join", "POST", { ...body, simulation_version: 6 }, guest)).status).toBe(200);
  });

  it("retains room rules through creation retries, eviction, forks, advancement and restored archives", async () => {
    const host = await identity(), guest = await identity(), requestKey = key();
    const request = { idempotency_key: requestKey, simulation_version: 6 };
    const initial = await (await call("/v1/rooms", "POST", request, host)).json<RoomSnapshot>();
    await evictDurableObject(env.ROOMS.getByName(initial.room_id));
    expect(await (await call("/v1/rooms", "POST", request, host)).json()).toEqual(initial);
    expect((await call("/v1/rooms", "POST", { ...request, simulation_version: 1 }, host)).status).toBe(409);
    let state = await (await call("/v1/rooms/join", "POST", { invite_code: initial.invite_code, simulation_version: 6 }, guest)).json<RoomSnapshot>();
    state = await complete(state, host, guest);
    state = await (await call(`/v1/rooms/${state.room_id}/fork`, "POST", { base_revision: state.revision, idempotency_key: key() }, host)).json<RoomSnapshot>();
    expect(state.simulation_version).toBe(6);
    state = await complete(state, host, guest);
    state = await (await call(`/v1/rooms/${state.room_id}/advance`, "POST", { base_revision: state.revision, idempotency_key: key() }, host)).json<RoomSnapshot>();
    expect(state.simulation_version).toBe(6); expect(state.level_index).toBe(1);
    const source = env.ROOMS.getByName(state.room_id), target = env.ROOMS.get(env.ROOMS.newUniqueId());
    const exported = await source.exportSnapshot("f".repeat(40)); expect(exported.ok).toBe(true);
    if (!exported.ok) throw new Error(exported.code);
    expect((await target.restoreSnapshot(exported.value, state.room_id)).ok).toBe(true);
    await evictDurableObject(target);
    expect(await target.snapshot(host.player_id)).toEqual(await source.snapshot(host.player_id));
    expect(await target.collection(host.player_id)).toEqual(await source.collection(host.player_id));
    const restored = await target.exportSnapshot("f".repeat(40));
    if (!restored.ok) throw new Error(restored.code);
    expect((JSON.parse(restored.value) as PortableSnapshot).payload.tables).toEqual((JSON.parse(exported.value) as PortableSnapshot).payload.tables);
  });

  it("rejects unsupported creation versions and backup ruleset tampering", async () => {
    const host = await identity();
    for (const simulation_version of [0, 2, 5, 7, 6.5, "6", null]) {
      expect((await call("/v1/rooms", "POST", { idempotency_key: key(), simulation_version }, host)).status).toBe(422);
    }
    const pair6 = await pair(6);
    const completed = await complete(pair6.room, pair6.host, pair6.guest);
    const exported = await env.ROOMS.getByName(completed.room_id).exportSnapshot("f".repeat(40));
    if (!exported.ok) throw new Error(exported.code);
    for (const value of [1, 7, "6"]) {
      const archive = JSON.parse(exported.value) as PortableSnapshot;
      const row = archive.payload.tables.find(t => t.name === "room")!.rows[0];
      const state = JSON.parse(String(row.data)); state.simulation_version = value; row.data = JSON.stringify(state);
      archive.checksum.value = await digest(canonicalJson(archive.payload));
      const target = env.ROOMS.get(env.ROOMS.newUniqueId());
      expect((await target.restoreSnapshot(canonicalJson(archive), completed.room_id)).ok).toBe(false);
    }
  });
});
