import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { Player } from "../src/player";
import { SafetyProfile } from "../src/safety";
import { digest, randomToken } from "../src/protocol";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { LIVE_CAPABILITY_HEADER, LIVE_PATH, MAX_LIVE_SOCKETS } from "../src/live";
import { CHAINS, fork, play, playA, playB } from "./history-chains";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Socket = { ws: WebSocket; messages: unknown[]; closes: number[] };
const ON = { V2_ROOMS_ENABLED: "true", LIVE_CONNECTION_ENABLED: "true", PRESENCE_ENABLED: "true" };
const OFF = { ...ON, LIVE_CONNECTION_ENABLED: "false" };
let address = 0;
const SESSION = "c".repeat(36);

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string> = ON, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, vars);
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201);
  const created = await made.json<Account>();
  await objectFlags(env.PLAYERS.getByName(created.player_id));
  return created;
}

/** Objects read their flags from their own env; tests turn them on there and put them back after. */
const changed = new Map<Record<string, unknown>, Record<string, unknown>>();
async function objectFlags(stub: DurableObjectStub, vars: Record<string, string> = ON): Promise<void> {
  await runInDurableObject(stub, instance => {
    const target = Reflect.get(instance, "env") as Record<string, unknown>;
    const saved = changed.get(target) ?? {};
    for (const [key, value] of Object.entries(vars)) { if (!Object.hasOwn(saved, key)) saved[key] = target[key]; target[key] = value; }
    changed.set(target, saved);
  });
}
afterEach(async () => {
  for (const [target, saved] of changed) for (const [key, value] of Object.entries(saved)) { if (value === undefined) delete target[key]; else target[key] = value; }
  changed.clear(); vi.restoreAllMocks(); await reset();
});

async function connect(who: Account, vars: Record<string, string> = ON): Promise<Socket> {
  const answer = await call(LIVE_PATH, "GET", who, undefined, vars, { Upgrade: "websocket" });
  expect(answer.status).toBe(101);
  const ws = answer.webSocket!; ws.accept();
  const socket: Socket = { ws, messages: [], closes: [] };
  ws.addEventListener("message", event => socket.messages.push(String(event.data) === "pong" ? "pong" : JSON.parse(String(event.data))));
  ws.addEventListener("close", event => socket.closes.push(event.code));
  return socket;
}
async function until(condition: () => boolean, ms = 8000): Promise<void> {
  const end = Date.now() + ms;
  while (!condition()) { if (Date.now() > end) throw new Error("timed out"); await new Promise(resolve => setTimeout(resolve, 5)); }
}
const settle = () => new Promise(resolve => setTimeout(resolve, 60));
const roomEvents = (socket: Socket) => socket.messages.filter(m => typeof m === "object" && (m as { type: string }).type === "room_changed");
const friendEvents = (socket: Socket) => socket.messages.filter(m => typeof m === "object" && (m as { type: string }).type === "friends_changed");
const presenceEvents = (socket: Socket) => socket.messages.filter(m => typeof m === "object" && (m as { type: string }).type === "presence_changed");

async function relayRoom(host: Account): Promise<RoomSnapshotV2> {
  const created = await call("/v2/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  expect(created.status).toBe(200);
  const room = await created.json<RoomSnapshotV2>();
  await objectFlags(env.ROOMS_V2.getByName(room.room_id));
  return room;
}
async function befriend(a: Account, b: Account): Promise<void> {
  const asked = await call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: b.player_id }); expect(asked.status).toBe(200);
  const { request_id } = await asked.json<{ request_id: string }>();
  expect((await call("/v1/friends/accept", "POST", b, { schema_version: 1, player_id: a.player_id, request_id })).status).toBe(200);
}
async function block(owner: Account, peer: Account): Promise<void> {
  const blocked = await env.SAFETY_PROFILES.getByName(owner.player_id).setBlock(owner.player_id, await digest(owner.device_token), peer.player_id, true);
  expect(blocked.ok).toBe(true);
}
/** Runs one change and checks exactly which sockets got a room hint for it. */
async function step(sockets: { host: Socket; guest: Socket }, change: () => Promise<unknown>, expected: { host: number; guest: number }): Promise<void> {
  const before = { host: roomEvents(sockets.host).length, guest: roomEvents(sockets.guest).length };
  await change();
  await until(() => roomEvents(sockets.host).length >= before.host + expected.host && roomEvents(sockets.guest).length >= before.guest + expected.guest);
  await settle();
  expect({ host: roomEvents(sockets.host).length - before.host, guest: roomEvents(sockets.guest).length - before.guest }).toEqual(expected);
}

describe("live socket upgrade", () => {
  it("is absent with the flag off: the same 404 bytes as any unknown path", async () => {
    const a = await account();
    const off = OFF;
    const live = await call(LIVE_PATH, "GET", a, undefined, off, { Upgrade: "websocket" });
    const unknown = await call("/v1/nothing-here", "GET", a, undefined, off);
    expect(live.status).toBe(404);
    expect(await live.text()).toBe(await unknown.text());
    expect([...live.headers.entries()]).toEqual([...unknown.headers.entries()]);
    // The Worker flag on but the object's off (a half-rolled deploy) still refuses.
    await objectFlags(env.PLAYERS.getByName(a.player_id), { LIVE_CONNECTION_ENABLED: "false" });
    expect((await call(LIVE_PATH, "GET", a, undefined, ON, { Upgrade: "websocket" })).status).toBe(404);
  });

  it("authenticates at upgrade time with the usual bearer headers", async () => {
    const a = await account();
    expect((await call(LIVE_PATH, "GET", undefined, undefined, ON, { Upgrade: "websocket" })).status).toBe(401);
    expect((await call(LIVE_PATH, "GET", { ...a, device_token: randomToken() }, undefined, ON, { Upgrade: "websocket" })).status).toBe(401);
    expect((await call(LIVE_PATH, "GET", a, undefined, ON)).status).toBe(426);
    expect((await call(LIVE_PATH, "POST", a, {}, ON, { Upgrade: "websocket" })).status).toBe(405);
    const socket = await connect(a);
    socket.ws.send("ping");
    await until(() => socket.messages.includes("pong"));
  });

  it("closes every socket when the identity is recovered, and refuses the old credential after", async () => {
    const a = await account(), socket = await connect(a);
    const next = { ...a, device_token: randomToken(), recovery_code: randomToken() };
    expect((await call("/v1/identity/recover", "POST", undefined, { player_id: a.player_id, recovery_code: a.recovery_code, idempotency_key: crypto.randomUUID(), next_device_token: next.device_token, next_recovery_code: next.recovery_code })).status).toBe(200);
    await until(() => socket.closes.length > 0);
    expect(socket.closes[0]).toBe(4401);
    expect((await call(LIVE_PATH, "GET", a, undefined, ON, { Upgrade: "websocket" })).status).toBe(401);
    await connect(next);
  });

  it("keeps at most MAX_LIVE_SOCKETS per player and closes the oldest", async () => {
    const a = await account(), sockets: Socket[] = [];
    for (let index = 0; index <= MAX_LIVE_SOCKETS; index++) { sockets.push(await connect(a)); await new Promise(resolve => setTimeout(resolve, 2)); }
    await until(() => sockets[0].closes.length > 0);
    expect(sockets[0].closes[0]).toBe(4000);
    expect(sockets.slice(1).every(socket => socket.closes.length === 0)).toBe(true);
  });

  it("closes a socket that sends anything but the keepalive", async () => {
    const a = await account(), socket = await connect(a);
    socket.ws.send("hello");
    await until(() => socket.closes.length > 0);
    expect(socket.closes[0]).toBe(1008);
  });
});

describe("capabilities", () => {
  it("adds live_version only with the flag on and the client's header; every other answer keeps its bytes", async () => {
    const a = await account(), off = OFF;
    const plain = await (await call("/v2/capabilities", "GET", a, undefined, off)).text();
    expect(await (await call("/v2/capabilities", "GET", a, undefined, off, { [LIVE_CAPABILITY_HEADER]: "1" })).text()).toBe(plain);
    expect(await (await call("/v2/capabilities", "GET", a, undefined, ON)).text()).toBe(plain);
    expect(await (await call("/v2/capabilities", "GET", a, undefined, ON, { [LIVE_CAPABILITY_HEADER]: "2" })).text()).toBe(plain);
    const live = await (await call("/v2/capabilities", "GET", a, undefined, ON, { [LIVE_CAPABILITY_HEADER]: "1" })).json<Record<string, unknown>>();
    const { live_version, ...rest } = live;
    expect(live_version).toBe(1);
    expect(rest).toEqual(JSON.parse(plain));
  });
});

describe("room hints", () => {
  it("reach only the other member, for a join, turn, fork, redo request and erase", async () => {
    const host = await account(), guest = await account(), stranger = await account();
    const sockets = { host: await connect(host), guest: await connect(guest) }, strangerSocket = await connect(stranger);
    const room = await relayRoom(host), stub = env.ROOMS_V2.getByName(room.room_id), players = { host: host.player_id, guest: guest.player_id };
    let state = room;
    await step(sockets, async () => {
      const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }); expect(joined.status).toBe(200);
      state = await joined.json<RoomSnapshotV2>();
    }, { host: 1, guest: 0 });
    expect(roomEvents(sockets.host).at(-1)).toEqual({ type: "room_changed", room: room.room_id, seq: state.revision });

    const stage = CHAINS[0].stages[0], hostPlaysA = stage.a.player_slot === "p0";
    await step(sockets, async () => { state = await playA(stub, state, stage, players); }, { host: hostPlaysA ? 0 : 1, guest: hostPlaysA ? 1 : 0 });
    expect(roomEvents(hostPlaysA ? sockets.guest : sockets.host).at(-1)).toEqual({ type: "room_changed", room: room.room_id, seq: state.revision });

    const redo = await (await call(`/v2/rooms/${room.room_id}/redo`, "GET", guest)).json<{ source: Record<string, string> }>();
    const second = redo.source.second_player_id === host.player_id ? host : guest;
    await step(sockets, async () => {
      expect((await call(`/v2/rooms/${room.room_id}/redo`, "POST", second, { action: "request", source: redo.source })).status).toBe(200);
    }, { host: second === host ? 0 : 1, guest: second === host ? 1 : 0 });

    await step(sockets, async () => { state = await fork(stub, state, 0, host.player_id); }, { host: 0, guest: 1 });
    await step(sockets, async () => {
      expect((await call(`/v2/rooms/${room.room_id}`, "DELETE", guest, undefined, ON, { "X-AfterYou-Close-If": "in-play" })).status).toBe(200);
    }, { host: 1, guest: 0 });
    expect(strangerSocket.messages).toEqual([]);
  });

  it("tell the member who stays when the other leaves a finished room, and nobody when the last one leaves", async () => {
    const host = await account(), guest = await account();
    const sockets = { host: await connect(host), guest: await connect(guest) };
    const room = await relayRoom(host), stub = env.ROOMS_V2.getByName(room.room_id);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }); expect(joined.status).toBe(200);
    await play(stub, await joined.json<RoomSnapshotV2>(), CHAINS[0], 0, undefined, { host: host.player_id, guest: guest.player_id });
    await settle();
    const leave = (who: Account) => call(`/v2/rooms/${room.room_id}/leave`, "POST", who, { schema_version: 1, leave_finished: true }, { ...ON, FINISHED_ROOM_LEAVE_ENABLED: "true" });
    await step(sockets, async () => { expect((await leave(guest)).status).toBe(200); }, { host: 1, guest: 0 });
    expect(roomEvents(sockets.host).at(-1)).toMatchObject({ type: "room_changed", room: room.room_id });
    await step(sockets, async () => { expect((await leave(host)).status).toBe(200); }, { host: 0, guest: 0 });
  });

  it("ride on the room index push when it goes to the same member, so a hint never arrives twice", async () => {
    const host = await account(), guest = await account();
    const sockets = { host: await connect(host), guest: await connect(guest) };
    const room = await relayRoom(host), stub = env.ROOMS_V2.getByName(room.room_id);
    for (const target of [stub, env.PLAYERS.getByName(host.player_id), env.PLAYERS.getByName(guest.player_id)]) await objectFlags(target, { ...ON, ROOM_INDEX_ENABLED: "true" });
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }); expect(joined.status).toBe(200);
    await settle();
    const indexed = vi.spyOn(Player.prototype, "noteRoomIndex");
    // Finishing the chapter settles the room, so the index pushes to both members on the last turn.
    const players = { host: host.player_id, guest: guest.player_id };
    let state = await joined.json<RoomSnapshotV2>();
    state = await play(stub, state, CHAINS[0], 0, CHAINS[0].stages.length - 1, players);
    const last = CHAINS[0].stages.at(-1)!, hostPlaysB = last.b.player_slot === "p0";
    state = await playA(stub, state, last, players);
    await settle();
    await step(sockets, async () => { state = await playB(stub, state, last, players); }, { host: hostPlaysB ? 0 : 1, guest: hostPlaysB ? 1 : 0 });
    expect(indexed).toHaveBeenCalled();
  });

  it("are never sent for a room the player is not linked to, and survive the object leaving memory", async () => {
    const host = await account(), guest = await account();
    const hostSocket = await connect(host);
    const room = await relayRoom(host);
    await evictDurableObject(env.PLAYERS.getByName(host.player_id));
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
    await until(() => roomEvents(hostSocket).length === 1);
    // The keepalive answer survives the object leaving memory: a ping never needs it awake.
    await evictDurableObject(env.PLAYERS.getByName(host.player_id));
    hostSocket.ws.send("ping");
    await until(() => hostSocket.messages.includes("pong"));
    expect(hostSocket.closes).toEqual([]);
    const delivered = await env.PLAYERS.getByName(host.player_id).liveHint(host.player_id, { kind: "room", room_id: "Z".repeat(22), revision: 1 });
    expect(delivered).toBe(false);
    expect(await env.PLAYERS.getByName(guest.player_id).liveHint(host.player_id, { kind: "room", room_id: room.room_id, revision: 1 })).toBe(false);
  });

  it("cost one hint RPC per change with the flag on and none with it off", async () => {
    const hints = vi.spyOn(Player.prototype, "liveHint");
    const host = await account(), guest = await account();
    const room = await relayRoom(host);
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
    await settle();
    expect(hints).toHaveBeenCalledTimes(1);
    for (const stub of [env.ROOMS_V2.getByName(room.room_id), env.PLAYERS.getByName(host.player_id), env.PLAYERS.getByName(guest.player_id)]) await objectFlags(stub, { LIVE_CONNECTION_ENABLED: "false" });
    const state = await (await call(`/v2/rooms/${room.room_id}`, "GET", guest)).json<RoomSnapshotV2>();
    await playA(env.ROOMS_V2.getByName(room.room_id), state, CHAINS[0].stages[0], { host: host.player_id, guest: guest.player_id });
    await settle();
    expect(hints).toHaveBeenCalledTimes(1);
  });
});

describe("friend hints", () => {
  it("tell accepted friends of a hosted room within one read, and never a stranger, a pending friend or a blocked friend", async () => {
    const host = await account(), friend = await account(), stranger = await account(), pending = await account(), blocked = await account();
    await befriend(host, friend); await befriend(host, blocked);
    expect((await call("/v1/friends/request", "POST", host, { schema_version: 1, friend_code: pending.player_id })).status).toBe(200);
    await block(host, blocked);
    // Each reads its list now, so the next read would be refused for 30 s without a hint.
    for (const who of [friend, blocked]) expect((await call("/v1/friends", "GET", who)).status).toBe(200);
    expect((await call("/v1/friends", "GET", friend)).status).toBe(429);
    const sockets = { friend: await connect(friend), stranger: await connect(stranger), pending: await connect(pending), blocked: await connect(blocked) };
    const room = await relayRoom(host);
    const blocks = vi.spyOn(SafetyProfile.prototype, "hasBlocked");
    expect((await call("/v1/friends/share", "POST", host, { schema_version: 1, room: { api_version: 2, room_id: room.room_id } })).status).toBe(200);
    await until(() => friendEvents(sockets.friend).length === 1);
    await settle();
    expect(sockets.stranger.messages).toEqual([]);
    expect(sockets.pending.messages).toEqual([]);
    expect(sockets.blocked.messages).toEqual([]);
    // Two accepted friends with an open socket: one block check (two profile reads) each.
    expect(blocks.mock.calls.filter(([owner]) => owner === friend.player_id || owner === blocked.player_id || owner === host.player_id)).toHaveLength(4);
    // The hint opened the friend's list read early; the room shows as joinable.
    await new Promise(resolve => setTimeout(resolve, 0));
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 2_100);
    const list = await call("/v1/friends", "GET", friend);
    expect(list.status).toBe(200);
    const page = await list.json<{ friends: { player_id: string; join_available: boolean }[] }>();
    expect(page.friends.find(row => row.player_id === host.player_id)?.join_available).toBe(true);
    // The blocked friend's window was not opened.
    expect((await call("/v1/friends", "GET", blocked)).status).toBe(429);
  });

  it("open a friend's list read early once per read, however many hints arrive", async () => {
    const host = await account(), friend = await account();
    await befriend(host, friend);
    expect((await call("/v1/friends", "GET", friend)).status).toBe(200);
    const socket = await connect(friend);
    const rooms = [await relayRoom(host), await relayRoom(host)];
    for (const room of rooms) expect((await call("/v1/friends/share", "POST", host, { schema_version: 1, room: { api_version: 2, room_id: room.room_id } })).status).toBe(200);
    await until(() => friendEvents(socket).length === 2);
    // Two hints right after a read still leave the read closed until the live floor.
    expect((await call("/v1/friends", "GET", friend)).status).toBe(429);
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 2_100);
    expect((await call("/v1/friends", "GET", friend)).status).toBe(200);
  });

  it("tell friends when a friend comes online, at most once per 20 s and without opening their list read, and push friend requests at no extra RPC", async () => {
    const a = await account(), b = await account(), c = await account();
    await befriend(a, b);
    expect((await call("/v1/friends", "GET", b)).status).toBe(200);
    const socket = await connect(b);
    const hints = vi.spyOn(Player.prototype, "liveHint");
    expect((await call("/v1/presence", "POST", a, { schema_version: 1, session_id: SESSION, online: true })).status).toBe(200);
    await until(() => presenceEvents(socket).length === 1);
    expect(friendEvents(socket)).toHaveLength(0);
    expect((await call("/v1/friends", "GET", b)).status).toBe(429);
    expect((await call("/v1/presence", "POST", a, { schema_version: 1, session_id: SESSION, online: true })).status).toBe(200);
    expect((await call("/v1/presence", "POST", a, { schema_version: 1, session_id: SESSION, online: false })).status).toBe(200);
    expect((await call("/v1/presence", "POST", a, { schema_version: 1, session_id: "d".repeat(36), online: true })).status).toBe(200);
    await settle();
    expect(presenceEvents(socket)).toHaveLength(1);
    expect(hints).toHaveBeenCalledTimes(1);
    // A friend request reaches the recipient from its own object.
    hints.mockClear();
    expect((await call("/v1/friends/request", "POST", c, { schema_version: 1, friend_code: b.player_id })).status).toBe(200);
    await until(() => friendEvents(socket).length === 1);
    expect(hints).not.toHaveBeenCalled();
  });

  it("send nothing with the flag off", async () => {
    const a = await account(), b = await account();
    await befriend(a, b);
    const room = await relayRoom(a);
    for (const who of [a, b]) await objectFlags(env.PLAYERS.getByName(who.player_id), { LIVE_CONNECTION_ENABLED: "false" });
    const hints = vi.spyOn(Player.prototype, "liveHint");
    expect((await call("/v1/friends/share", "POST", a, { schema_version: 1, room: { api_version: 2, room_id: room.room_id } }, OFF)).status).toBe(200);
    expect((await call("/v1/presence", "POST", a, { schema_version: 1, session_id: SESSION, online: true }, OFF)).status).toBe(200);
    await settle();
    expect(hints).not.toHaveBeenCalled();
  });
});
