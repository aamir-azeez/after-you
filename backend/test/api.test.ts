import { env, exports } from "cloudflare:workers";
import { reset, evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { entitlement, makeProviderRequest } from "../src/entitlement";
import worker from "../src/index";
import { LEVEL_IDS, randomToken, type Recording, type RoomSnapshot } from "../src/protocol";
import firstA from "../../game/tests/fixtures/first-light-a.json";
import firstB from "../../game/tests/fixtures/first-light-b.json";

type Credentials = { player_id: string; device_token: string; recovery_code: string };
let address = 0;
const key = () => crypto.randomUUID();
async function call(path: string, method = "GET", body?: unknown, account?: Credentials): Promise<Response> {
  const headers: Record<string, string> = { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + (++address) };
  if (account) { headers.Authorization = "Bearer " + account.device_token; headers["X-Player-Id"] = account.player_id; }
  return exports.default.fetch(new Request("https://after-you.test" + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }));
}
const create = async () => (await call("/v1/identity", "POST", {})).json<Credentials>();
const rotation = (account: Credentials) => ({ player_id: account.player_id, recovery_code: account.recovery_code, idempotency_key: key(), next_device_token: randomToken(), next_recovery_code: randomToken() });
const rotatedCredentials = (body: ReturnType<typeof rotation>): Credentials => ({ player_id: body.player_id, device_token: body.next_device_token, recovery_code: body.next_recovery_code });
async function newRoom(host: Credentials): Promise<RoomSnapshot> {
  const response = await call("/v1/rooms", "POST", { idempotency_key: key() }, host);
  expect(response.status).toBe(200); return response.json<RoomSnapshot>();
}
async function pair() {
  const a = await create(), b = await create(); const created = await newRoom(a);
  const joined = await call("/v1/rooms/join", "POST", { invite_code: created.invite_code }, b);
  expect(joined.status).toBe(200);
  return { a, b, room: await joined.json<RoomSnapshot>() };
}
function synthetic(role: "a" | "b", level = LEVEL_IDS[0]): Recording {
  return {
    schema_version: 1, simulation_version: 1, level_version: 1, tick_rate: 30, level_id: level,
    role, duration_ticks: 30, catch_assistance: true,
    actions: [{ ticks: 30, x: 0, z: 0, action: true }], checkpoints: [{ tick: 30, state_hash: role.repeat(64) }],
    final_state_hash: role.repeat(64), completed: role === "b",
    outcome: { threw_seed: role === "a", caught_seed: role === "b", planted_seed: role === "b" },
    ...(role === "b" ? { source_recording_hash: "a".repeat(64) } : {})
  };
}
async function commit(room: RoomSnapshot, account: Credentials, recording: unknown, idempotency_key = key()) {
  return call(`/v1/rooms/${room.room_id}/turns`, "POST", { base_revision: room.revision, idempotency_key, recording }, account);
}
async function complete(room: RoomSnapshot, a: Credentials, b: Credentials) {
  const first = room.first_player_id === a.player_id ? a : b, second = first === a ? b : a;
  const firstResponse = await commit(room, first, synthetic("a", room.level_id as typeof LEVEL_IDS[0]));
  expect(firstResponse.status).toBe(200);
  const next = await firstResponse.json<RoomSnapshot>();
  const secondResponse = await commit(next, second, synthetic("b", room.level_id as typeof LEVEL_IDS[0]));
  expect(secondResponse.status).toBe(200); return secondResponse.json<RoomSnapshot>();
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("native client HTTP contract in Workers runtime", () => {
  it("creates opaque credentials and rejects a different credential", async () => {
    const account = await create(); expect(account.player_id).toHaveLength(22); expect(account.device_token).toHaveLength(43);
    expect((await call("/v1/identity", "GET", undefined, account)).status).toBe(200);
    expect((await call("/v1/identity", "GET", undefined, { ...account, device_token: "x".repeat(43) })).status).toBe(401);
  });
  it("stores only hashes of device/recovery credentials", async () => {
    const account = await create();
    await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
      const dump = JSON.stringify(state.storage.sql.exec("SELECT * FROM identity").toArray());
      expect(dump).not.toContain(account.device_token); expect(dump).not.toContain(account.recovery_code);
    });
  });
  it("rotates both credentials on recovery and invalidates the old ones", async () => {
    const account = await create(); const room = await newRoom(account);
    const body = rotation(account), next = rotatedCredentials(body);
    const recovered = await call("/v1/identity/recover", "POST", body);
    expect(recovered.status).toBe(200); expect(await recovered.json()).toEqual({ player_id: account.player_id, recovered: true });
    expect((await call("/v1/identity", "GET", undefined, account)).status).toBe(401);
    expect((await call(`/v1/rooms/${room.room_id}`, "GET", undefined, next)).status).toBe(200);
    expect((await call("/v1/identity/recover", "POST", rotation(account))).status).toBe(409);
  });
  it("retries an accepted recovery after a lost response and durable-object eviction", async () => {
    const account = await create(), body = rotation(account), next = rotatedCredentials(body);
    // Deliberately discard the first acknowledgement; the device already saved body.
    expect((await call("/v1/identity/recover", "POST", body)).status).toBe(200);
    await evictDurableObject(env.PLAYERS.getByName(account.player_id));
    const retry = await call("/v1/identity/recover", "POST", body);
    expect(retry.status).toBe(200); expect(await retry.json()).toEqual({ player_id: account.player_id, recovered: true });
    expect((await call("/v1/identity", "GET", undefined, next)).status).toBe(200);
    expect((await call("/v1/identity", "GET", undefined, account)).status).toBe(401);
    await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
      const dump = JSON.stringify(state.storage.sql.exec("SELECT * FROM identity").toArray());
      for (const secret of [account.device_token, account.recovery_code, body.next_device_token, body.next_recovery_code, body.idempotency_key]) expect(dump).not.toContain(secret);
      expect(dump).toContain("recovery_receipt");
    });
  });
  it("rejects changed recovery secrets and keys without disturbing the accepted rotation", async () => {
    const account = await create(), body = rotation(account), next = rotatedCredentials(body);
    expect((await call("/v1/identity/recover", "POST", body)).status).toBe(200);
    for (const change of [{ idempotency_key: key() }, { next_device_token: randomToken() }, { next_recovery_code: randomToken() }]) {
      const retry = await call("/v1/identity/recover", "POST", { ...body, ...change });
      expect(retry.status).toBe(409); expect(await retry.json()).toEqual({ error: { code: "recovery_request_mismatch", retryable: false } });
    }
    expect((await call("/v1/identity", "GET", undefined, next)).status).toBe(200);
    expect((await call("/v1/identity/recover", "POST", body)).status).toBe(200);
  });
  it("supersedes the prior recovery receipt on a subsequent valid rotation", async () => {
    const account = await create(), first = rotation(account), next = rotatedCredentials(first);
    expect((await call("/v1/identity/recover", "POST", first)).status).toBe(200);
    const second = rotation(next), latest = rotatedCredentials(second);
    expect((await call("/v1/identity/recover", "POST", second)).status).toBe(200);
    expect((await call("/v1/identity/recover", "POST", first)).status).toBe(401);
    expect((await call("/v1/identity", "GET", undefined, next)).status).toBe(401);
    expect((await call("/v1/identity/recover", "POST", second)).status).toBe(200);
    expect((await call("/v1/identity", "GET", undefined, latest)).status).toBe(200);
  });
  it("rejects legacy and incomplete recovery bodies before changing credentials", async () => {
    const account = await create(), body = rotation(account);
    for (const input of [{ player_id: account.player_id, recovery_code: account.recovery_code }, { ...body, idempotency_key: undefined }]) {
      const response = await call("/v1/identity/recover", "POST", input);
      expect(response.status).toBe(400); expect(await response.json()).toEqual({ error: { code: "recovery_request_required", retryable: false } });
      expect((await call("/v1/identity", "GET", undefined, account)).status).toBe(200);
    }
    expect((await call("/v1/identity/recover", "POST", body)).status).toBe(200);
  });
  it("refuses credential reuse within a rotation", async () => {
    const account = await create(), body = rotation(account);
    for (const change of [{ next_device_token: body.next_recovery_code }, { next_recovery_code: account.recovery_code }, { next_device_token: account.device_token }, { next_recovery_code: account.device_token }, { next_device_token: account.recovery_code }]) {
      const response = await call("/v1/identity/recover", "POST", { ...body, ...change });
      expect(response.status).toBe(400); expect(await response.json()).toEqual({ error: { code: "invalid_rotation", retryable: false } });
    }
    expect((await call("/v1/identity", "GET", undefined, account)).status).toBe(200);
  });
  it("erases the current recovery receipt when deleting an identity", async () => {
    const account = await create(), body = rotation(account), next = rotatedCredentials(body);
    expect((await call("/v1/identity/recover", "POST", body)).status).toBe(200);
    expect((await call("/v1/identity", "DELETE", undefined, next)).status).toBe(200);
    expect((await call("/v1/identity/recover", "POST", body)).status).toBe(401);
    await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
      expect(state.storage.sql.exec("SELECT * FROM identity").toArray()).toEqual([]);
    });
  });
  it("rate-limits recovery retries before inspecting or rotating credentials", async () => {
    const account = await create(), body = rotation(account);
    const limit = vi.fn().mockResolvedValue({ success: false });
    const response = await worker.fetch(new Request("https://after-you.test/v1/identity/recover", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }), { ...env, PUBLIC_LIMITER: { limit } });
    expect(response.status).toBe(429); expect(response.headers.get("Retry-After")).toBe("60"); expect(limit).toHaveBeenCalledTimes(1);
    expect((await call("/v1/identity", "GET", undefined, account)).status).toBe(200);
    expect((await call("/v1/identity/recover", "POST", body)).status).toBe(200);
  });
  it("creates rooms idempotently even if the first response is lost", async () => {
    const account = await create(); const body = { idempotency_key: key() };
    const first = await (await call("/v1/rooms", "POST", body, account)).json<RoomSnapshot>();
    const second = await (await call("/v1/rooms", "POST", body, account)).json<RoomSnapshot>();
    expect(second.room_id).toBe(first.room_id);
    expect((await (await call("/v1/rooms", "GET", undefined, account)).json<{ rooms: RoomSnapshot[] }>()).rooms).toHaveLength(1);
  });
  it("keeps outsider snapshots and a third participant out", async () => {
    const { a, room } = await pair(); const third = await create();
    expect((await call(`/v1/rooms/${room.room_id}`, "GET", undefined, third)).status).toBe(404);
    const host = await (await call(`/v1/rooms/${room.room_id}`, "GET", undefined, a)).json<RoomSnapshot>();
    expect((await call("/v1/rooms/join", "POST", { invite_code: host.invite_code }, third)).status).toBe(409);
    expect((await (await call("/v1/rooms", "GET", undefined, third)).json<{ rooms: RoomSnapshot[] }>()).rooms).toHaveLength(0);
  });
  it("accepts the actual successful Godot A/B recordings unchanged", async () => {
    const { a, b, room } = await pair();
    const aResponse = await commit(room, a, firstA); expect(aResponse.status).toBe(200);
    const next = await aResponse.json<RoomSnapshot>();
    expect(next.recordings.a).toEqual(firstA);
    const bResponse = await commit(next, b, firstB); expect(bResponse.status).toBe(200);
    const finished = await bResponse.json<RoomSnapshot>();
    expect(finished.active_role).toBe("complete"); expect(finished.recordings.b).toEqual(firstB);
  });
  it("survives object eviction with exact committed records", async () => {
    const { a, room } = await pair(); const next = await (await commit(room, a, firstA)).json<RoomSnapshot>();
    await evictDurableObject(env.ROOMS.getByName(room.room_id));
    const restored = await (await call(`/v1/rooms/${room.room_id}`, "GET", undefined, a)).json<RoomSnapshot>();
    expect(restored.recordings).toEqual(next.recordings); expect(restored.revision).toBe(next.revision);
  });
  it("rejects role and source-recording mismatches", async () => {
    const { a, b, room } = await pair(); expect((await commit(room, b, firstA)).status).toBe(409);
    const next = await (await commit(room, a, firstA)).json<RoomSnapshot>();
    expect((await commit(next, b, { ...firstB, source_recording_hash: "0".repeat(64) })).status).toBe(409);
  });
  it("reconciles duplicate accepted turn retries without another revision", async () => {
    const { a, room } = await pair(); const requestKey = key();
    const first = await (await commit(room, a, firstA, requestKey)).json<RoomSnapshot>();
    const retry = await (await commit(room, a, firstA, requestKey)).json<RoomSnapshot>();
    expect(retry.revision).toBe(first.revision);
    expect((await commit(room, a, { ...firstA, catch_assistance: false }, requestKey)).status).toBe(409);
  });
  it("treats JSON object key reordering as the same retry", async () => {
    const { a, room } = await pair(); const requestKey = key();
    const first = await (await commit(room, a, firstA, requestKey)).json<RoomSnapshot>();
    const reordered = Object.fromEntries(Object.entries(firstA).reverse());
    const retry = await commit(room, a, reordered, requestKey);
    expect(retry.status).toBe(200); expect((await retry.json<RoomSnapshot>()).revision).toBe(first.revision);
  });
  it("serializes concurrent different commits against one revision", async () => {
    const { a, room } = await pair();
    const responses = await Promise.all([commit(room, a, firstA), commit(room, a, firstA)]);
    expect(responses.map(r => r.status).sort()).toEqual([200, 409]);
  });
  it("forks an attempt without mutating the completed archived replay", async () => {
    const { a, b, room } = await pair(); const finished = await complete(room, a, b);
    const forkResponse = await call(`/v1/rooms/${room.room_id}/fork`, "POST", { base_revision: finished.revision, idempotency_key: key() }, a);
    expect(forkResponse.status).toBe(200); const fork = await forkResponse.json<RoomSnapshot>();
    expect(fork.recordings).toEqual({ a: null, b: null }); expect(fork.attempt).toBe(1);
    const collection = await (await call(`/v1/rooms/${room.room_id}/collection`, "GET", undefined, b)).json<{ islands: RoomSnapshot[] }>();
    expect(collection.islands[0].recordings).toEqual(finished.recordings);
  });
  it("rejects stale states after partner joins", async () => {
    const a = await create(), b = await create(), room = await newRoom(a);
    await call("/v1/rooms/join", "POST", { invite_code: room.invite_code }, b);
    expect((await commit(room, a, firstA)).status).toBe(409);
  });
  it("alternates roles and fails closed on premium progression without a server key", async () => {
    const { a, b, room } = await pair(); let current = room;
    for (let index = 0; index < 3; index++) {
      current = await complete(current, a, b);
      const advance = await call(`/v1/rooms/${room.room_id}/advance`, "POST", { base_revision: current.revision, idempotency_key: key() }, a);
      if (index === 2) { expect(advance.status).toBe(503); break; }
      expect(advance.status).toBe(200); current = await advance.json<RoomSnapshot>();
      expect(current.first_player_id).toBe(index === 0 ? b.player_id : a.player_id);
    }
  });
  it("does not accept a local entitlement Boolean or unexpected field", async () => {
    const a = await create(); expect((await call("/v1/rooms", "POST", { idempotency_key: key(), full_journey: true }, a)).status).toBe(400);
    const status = await (await call("/v1/entitlement", "GET", undefined, a)).json<{ full_journey: boolean; status: string }>();
    expect(status).toMatchObject({ full_journey: false, status: "unconfigured" });
  });
  it("uses the host's verified purchase for a guest entering premium and rejects revocation", async () => {
    const { a, b, room } = await pair(); let current = room;
    for (let index = 0; index < 3; index++) {
      current = await complete(current, a, b);
      if (index < 2) current = await (await call(`/v1/rooms/${room.room_id}/advance`, "POST", { base_revision: current.revision, idempotency_key: key() }, a)).json<RoomSnapshot>();
    }
    const spy = vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(Response.json({ object: "list", items: [{ entitlement_id: "entltest", expires_at: null }], next_page: null }));
    const configured = { ...env, REVENUECAT_SECRET_KEY: "test-only-key", REVENUECAT_PROJECT_ID: "projtest", REVENUECAT_ENTITLEMENT_LOOKUP_ID: "entltest" };
    const request = new Request(`https://after-you.test/v1/rooms/${room.room_id}/advance`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Player-Id": b.player_id, Authorization: "Bearer " + b.device_token },
      body: JSON.stringify({ base_revision: current.revision, idempotency_key: key() })
    });
    const premium = await worker.fetch(request, configured);
    expect(premium.status).toBe(200);
    expect((spy.mock.calls[0][0] as Request).url).toBe(`https://api.revenuecat.com/v2/projects/projtest/customers/${a.player_id}/active_entitlements?limit=100`);
    current = await premium.json<RoomSnapshot>(); expect(current.level_index).toBe(3);
    spy.mockResolvedValueOnce(Response.json({ object: "list", items: [], next_page: null }));
    const revoked = await worker.fetch(new Request(`https://after-you.test/v1/rooms/${room.room_id}/turns`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Player-Id": b.player_id, Authorization: "Bearer " + b.device_token },
      body: JSON.stringify({ base_revision: current.revision, idempotency_key: key(), recording: synthetic("a", current.level_id as typeof LEVEL_IDS[0]) })
    }), configured);
    expect(revoked.status).toBe(402);
  });
  it("rejects incomplete outcomes, unsupported versions and action duration errors", async () => {
    const { a, room } = await pair();
    expect((await commit(room, a, { ...firstA, simulation_version: 900 })).status).toBe(422);
    expect((await commit(room, a, { ...firstA, duration_ticks: 1 })).status).toBe(400);
    expect((await commit(room, a, { ...firstA, outcome: { threw_seed: false, caught_seed: false, planted_seed: false } })).status).toBe(422);
  });
  it("bounds bodies before reading all content", async () => {
    const a = await create(); const room = await newRoom(a);
    expect((await call(`/v1/rooms/${room.room_id}/turns`, "POST", { recording: "x".repeat(100_000) }, a)).status).toBe(413);
  });
  it("uses only preset reactions and requires a completed island", async () => {
    const { a, b, room } = await pair();
    expect((await call(`/v1/rooms/${room.room_id}/reactions`, "POST", { base_revision: room.revision, idempotency_key: key(), reaction: "custom chat" }, a)).status).toBe(400);
    const finished = await complete(room, a, b);
    const response = await call(`/v1/rooms/${room.room_id}/reactions`, "POST", { base_revision: finished.revision, idempotency_key: key(), reaction: "love" }, b);
    expect((await response.json<RoomSnapshot>()).reactions[b.player_id]).toBe("love");
  });
  it("deletes shared recordings and identity credentials", async () => {
    const { a, b, room } = await pair(); await complete(room, a, b);
    expect((await call("/v1/identity", "DELETE", undefined, a)).status).toBe(200);
    expect((await call("/v1/identity", "GET", undefined, a)).status).toBe(401);
    expect((await call(`/v1/rooms/${room.room_id}`, "GET", undefined, b)).status).toBe(404);
    expect((await (await call("/v1/rooms", "GET", undefined, b)).json<{ rooms: RoomSnapshot[] }>()).rooms).toHaveLength(0);
    await runInDurableObject(env.ROOMS.getByName(room.room_id), async (_, state) => {
      expect(state.storage.sql.exec("SELECT * FROM archive").toArray()).toEqual([]);
      expect(state.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data).toBe('{"deleted":true}');
    });
  });
  it("does not allocate a deletion tombstone for an unrelated room", async () => {
    const account = await create();
    expect((await call("/v1/rooms/aaaaaaaaaaaaaaaaaaaaaa", "DELETE", undefined, account)).status).toBe(404);
    await runInDurableObject(env.ROOMS.getByName("aaaaaaaaaaaaaaaaaaaaaa"), async (_, state) => {
      expect(state.storage.sql.exec("SELECT * FROM room").toArray()).toEqual([]);
    });
  });
  it("does not recreate a pending room after identity deletion tombstones it", async () => {
    const a = await create(), roomId = "eeeeeeeeeeeeeeeeeeeeee";
    const stub = env.ROOMS.getByName(roomId);
    expect((await stub.eraseForPlayer(a.player_id, true)).ok).toBe(true);
    expect(await stub.initialize(roomId, a.player_id, "A".repeat(20))).toMatchObject({ ok: false, status: 410 });
  });
  it("blocks bootstrap abuse with a bounded rate limiter", async () => {
    const statuses = [];
    for (let count = 0; count < 22; count++) {
      const response = await exports.default.fetch(new Request("https://after-you.test/v1/identity", {
        method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.12" }, body: "{}"
      }));
      statuses.push(response.status);
    }
    expect(statuses.filter(status => status === 201)).toHaveLength(20);
    expect(statuses.slice(-2)).toEqual([429, 429]);
  });
});

describe("RevenueCat server verification", () => {
  it("checks the actual Workers request constructor used for outbound calls", () => {
    const request = makeProviderRequest("https://api.revenuecat.com/v2/projects/test/customers/test/active_entitlements", "test-only-key");
    expect(request.redirect).toBe("manual");
    expect(request.headers.get("Authorization")).toBe("Bearer test-only-key");
  });
  it("requires a real server key and never calls the provider when absent", async () => {
    const spy = vi.spyOn(globalThis, "fetch");
    expect((await entitlement("player", env)).status).toBe("unconfigured"); expect(spy).not.toHaveBeenCalled();
  });
  it("recognizes a provider-confirmed non-expiring purchase", async () => {
    const spy = vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({ subscriber: { entitlements: { full_journey: { purchase_date: "2020-01-01T00:00:00Z", expires_date: null } } } }));
    expect((await entitlement("player", { ...env, REVENUECAT_API_VERSION: "1", REVENUECAT_SECRET_KEY: "test-only-key" })).full_journey).toBe(true);
    expect((spy.mock.calls[0][0] as Request).url).toBe("https://api.revenuecat.com/v1/subscribers/player");
  });
  it("rejects expired, missing or malformed provider entitlements", async () => {
    const spy = vi.spyOn(globalThis, "fetch");
    for (const entry of [{ purchase_date: "2020-01-01", expires_date: "2021-01-01" }, { expires_date: null }, { purchase_date: "2099-01-01", expires_date: null }]) {
      spy.mockResolvedValueOnce(Response.json({ subscriber: { entitlements: { full_journey: entry } } }));
      expect((await entitlement("player", { ...env, REVENUECAT_API_VERSION: "1", REVENUECAT_SECRET_KEY: "test-only-key" })).full_journey).toBe(false);
    }
  });
  it("fails closed on provider errors and overlarge replies", async () => {
    const spy = vi.spyOn(globalThis, "fetch").mockRejectedValueOnce(new Error("connection failed"));
    expect((await entitlement("player", { ...env, REVENUECAT_API_VERSION: "1", REVENUECAT_SECRET_KEY: "test-only-key" })).status).toBe("unavailable");
    spy.mockResolvedValueOnce(new Response("x".repeat(270_000)));
    expect((await entitlement("player", { ...env, REVENUECAT_API_VERSION: "1", REVENUECAT_SECRET_KEY: "test-only-key" })).full_journey).toBe(false);
  });
  it("treats a missing subscriber as not purchased rather than an outage", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 404 }));
    expect(await entitlement("player", { ...env, REVENUECAT_API_VERSION: "1", REVENUECAT_SECRET_KEY: "test-only-key" })).toMatchObject({ full_journey: false, status: "verified" });
  });
  it("requires V2 project and opaque entitlement IDs before sending the secret", async () => {
    const spy = vi.spyOn(globalThis, "fetch");
    expect((await entitlement("player", { ...env, REVENUECAT_SECRET_KEY: "test-only-key" })).status).toBe("unconfigured");
    expect(spy).not.toHaveBeenCalled();
  });
  it("V2 grants only the configured active entitlement and tolerates a lifetime expiry", async () => {
    const configured = { ...env, REVENUECAT_SECRET_KEY: "test-only-key", REVENUECAT_PROJECT_ID: "projtest", REVENUECAT_ENTITLEMENT_LOOKUP_ID: "entltest" };
    const spy = vi.spyOn(globalThis, "fetch");
    for (const [entry, allowed] of [
      [{ entitlement_id: "entltest", expires_at: null }, true],
      [{ entitlement_id: "entltest", expires_at: Date.now() + 100000 }, true],
      [{ entitlement_id: "entlother", expires_at: null }, false],
      [{ entitlement_id: "entltest", expires_at: 0 }, false],
      [{ entitlement_id: "entltest" }, false]
    ] as const) {
      spy.mockResolvedValueOnce(Response.json({ object: "list", items: [entry], next_page: null }));
      expect((await entitlement("player", configured)).full_journey).toBe(allowed);
    }
  });
  it("V2 never follows an arbitrary pagination URL with the server credential", async () => {
    const configured = { ...env, REVENUECAT_SECRET_KEY: "test-only-key", REVENUECAT_PROJECT_ID: "projtest", REVENUECAT_ENTITLEMENT_LOOKUP_ID: "entltest" };
    const spy = vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({ object: "list", items: [], next_page: "https://elsewhere.example/private" }));
    expect((await entitlement("player", configured)).status).toBe("unavailable");
    expect(spy).toHaveBeenCalledTimes(1);
  });
});
