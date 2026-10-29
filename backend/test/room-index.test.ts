import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, type Outcome } from "../src/protocol";
import { readErasure, writeErasure } from "../src/account-erasure";
import { MAX_ACTIVE_ROOM_LINKS, MAX_INDEXED_ROOM_LINKS, MAX_ROOM_LINKS } from "../src/room-limit";
import { ROOM_DELETION_BATCH, type RoomLink } from "../src/room-links";
import { ROOM_INBOX_PAGE, ROOM_INDEX_BUDGET, ROOM_INDEX_RECHECKS, ROOM_LIST_PAGE, ROOM_NEXT_HEADER, ROOM_PAGE_HEADER } from "../src/room-index";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import { configJson } from "./config";
import type { RoomSnapshotV2 } from "../src/v2/room";
import type { RoomInboxProjection } from "../src/room-inbox";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Inbox = { schema_version: 1; rooms: { room_id: string; status: string; api_version: number; membership: { host_id: string | null; guest_id: string | null } }[] };
type IndexRow = { room_id: string; api_version: number; state: string; observed_at: number; checked_at: number; entry: string | null };
type Counter = { calls: number; methods: Record<string, number> };
const key = () => crypto.randomUUID();
const LIMIT_BODY = '{"error":{"code":"room_limit_reached","retryable":false}}';
let address = 0;
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }

/**
 * Wraps every Durable Object namespace and rate limiter on an env so each RPC
 * the router makes is counted: the subrequests and Durable Object requests one
 * HTTP request costs. Calls the objects make among themselves are not counted
 * here; they spend their own invocation's budget.
 */
function counted(base: Env): { env: Env; counter: Counter } {
  const counter: Counter = { calls: 0, methods: {} };
  const note = (name: string) => { counter.calls++; counter.methods[name] = (counter.methods[name] ?? 0) + 1; };
  const wrapped: Record<string, unknown> = { ...base };
  for (const [name, binding] of Object.entries(base)) {
    if (binding && typeof binding === "object" && typeof (binding as { getByName?: unknown }).getByName === "function") {
      const namespace = binding as DurableObjectNamespace;
      const stubbed = (stub: object) => new Proxy(stub, { get(target, property) {
        const member = Reflect.get(target, property);
        return typeof member === "function" && typeof property === "string" ? (...args: unknown[]) => { note(`${name}.${property}`); return Reflect.apply(member as (...a: unknown[]) => unknown, target, args); } : member;
      } });
      wrapped[name] = new Proxy(namespace, { get(target, property) {
        const member = Reflect.get(target, property);
        if (property === "getByName" || property === "get") return (...args: unknown[]) => stubbed(Reflect.apply(member as (...a: unknown[]) => object, target, args));
        return typeof member === "function" ? (member as (...a: unknown[]) => unknown).bind(target) : member;
      } });
    } else if (binding && typeof binding === "object" && typeof (binding as { limit?: unknown }).limit === "function") {
      const limiter = binding as RateLimit;
      wrapped[name] = { limit: (options: RateLimitOptions) => { note(`${name}.limit`); return limiter.limit(options); } };
    }
  }
  return { env: wrapped as unknown as Env, counter };
}

/**
 * Runs one Player alarm with the Player's own bindings counted, so a deletion
 * batch's calls can be checked against the budget like a request's.
 */
async function countedAlarm(stub: DurableObjectStub): Promise<number> {
  const holder: { counter?: Counter; saved?: Record<string, unknown> } = {};
  await runInDurableObject(stub, async instance => {
    const target = (instance as unknown as { env: Record<string, unknown> }).env;
    const { env: wrapped, counter } = counted(target as unknown as Env);
    holder.counter = counter; holder.saved = {};
    for (const name of ["PLAYERS", "ROOMS", "ROOMS_V2", "SAFETY_PROFILES", "SAFETY_INBOX", "FRIEND_ROOM_EVENTS", "PHOTO_TRANSFERS"]) { holder.saved[name] = target[name]; target[name] = (wrapped as unknown as Record<string, unknown>)[name]; }
  });
  try { await runDurableObjectAlarm(stub); }
  finally { await runInDurableObject(stub, async instance => { Object.assign((instance as unknown as { env: Record<string, unknown> }).env, holder.saved); }); }
  return holder.counter!.calls;
}

/** Rows read by every SQL cursor in this isolate (the objects run in it), from workerd's own counters. */
const cursors: { rowsRead: number; sql: string }[] = [];
let rowsPatched = false;
async function countRows(): Promise<void> {
  if (rowsPatched) return;
  await runInDurableObject(env.PLAYERS.getByName("rows-probe"), async (_, ctx) => {
    const proto = Object.getPrototypeOf(ctx.storage.sql) as { exec: (...args: unknown[]) => { rowsRead: number } };
    const exec = proto.exec;
    proto.exec = function (this: unknown, ...args: unknown[]) { const cursor = exec.apply(this, args); cursors.push(Object.assign(cursor, { sql: String(args[0]) })); return cursor; };
  });
  rowsPatched = true;
}
function rowsSince(start: number): number { return cursors.slice(start).reduce((sum, cursor) => sum + cursor.rowsRead, 0); }

/**
 * Counts every Durable Object request in the isolate while installed: the
 * router's calls and the calls the objects make among themselves (pushes,
 * block checks), as the Free plan's daily DO request quota does.
 */
async function countEverything(): Promise<{ counter: Counter; restore: () => Promise<void> }> {
  const names = ["PLAYERS", "ROOMS", "ROOMS_V2", "SAFETY_PROFILES", "SAFETY_INBOX", "FRIEND_ROOM_EVENTS", "PHOTO_TRANSFERS", "PHOTO_TRANSFER_BUDGET"];
  const holder: { counter?: Counter; saved?: Record<string, unknown> } = {};
  const probe = env.PLAYERS.getByName("count-probe");
  await runInDurableObject(probe, async instance => {
    const target = (instance as unknown as { env: Record<string, unknown> }).env;
    const { env: wrapped, counter } = counted(target as unknown as Env);
    holder.counter = counter; holder.saved = {};
    for (const name of names) { holder.saved[name] = target[name]; target[name] = (wrapped as unknown as Record<string, unknown>)[name]; }
  });
  return { counter: holder.counter!, restore: () => runInDurableObject(probe, async instance => { Object.assign((instance as unknown as { env: Record<string, unknown> }).env, holder.saved); }) };
}

function settings(): Env {
  return { ...env };
}
function request(path: string, method: string, account?: Account, body?: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + (++address % 250), ...headers,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) });
}
function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  return worker.fetch(request(path, method, account, body, headers), settings());
}
/** One counted request: its answer, router calls and rows read. */
async function measured(path: string, account: Account, headers: Record<string, string> = {}, method = "GET"): Promise<{ response: Response; text: string; calls: number; rows: number; counter: Counter }> {
  const { env: wrapped, counter } = counted(settings());
  const start = cursors.length;
  const response = await worker.fetch(request(path, method, account, undefined, headers), wrapped);
  const text = await response.text();
  return { response, text, calls: counter.calls, rows: rowsSince(start), counter };
}

async function identity(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
/** A synthetic identity made straight in its Player, for bulk setups that would trip the public limiter. */
const tokens = new Map<string, string>();
async function directIdentity(): Promise<Account> {
  const player_id = crypto.randomUUID().replace(/-/g, "").slice(0, 22), device_token = "d".repeat(10) + crypto.randomUUID().replace(/-/g, "");
  const recovery_code = "r".repeat(10) + crypto.randomUUID().replace(/-/g, "");
  value(await env.PLAYERS.getByName(player_id).create(player_id, await digest(device_token), await digest(recovery_code)));
  tokens.set(player_id, device_token);
  return { player_id, device_token, recovery_code };
}
const roomV2 = (roomId: string) => env.ROOMS_V2.getByName(roomId);
/** Bulk setup writes links straight into the Player; the cap itself has its own tests. */
async function directLink(account: Account, link: RoomLink): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => { ctx.storage.sql.exec("INSERT INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link)); });
}
const createV2 = (host: Account) => call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
async function hosted(host: Account): Promise<RoomSnapshotV2> { const result = await createV2(host); expect(result.status).toBe(200); return result.json<RoomSnapshotV2>(); }
/** A v2 room made straight in its objects: the host's link, then the room, like POST /v2/rooms. */
async function directRoom(host: Account, guest?: Account): Promise<RoomSnapshotV2> {
  const invite = [...crypto.getRandomValues(new Uint8Array(10))].map(v => v.toString(16).padStart(2, "0")).join("").toUpperCase();
  const roomId = (await digest("v2:" + invite)).slice(0, 22);
  await directLink(host, { room_id: roomId, invite_code: invite, host: true, api_version: 2 });
  let state = value(await roomV2(roomId).initialize(roomId, host.player_id, invite));
  if (guest) {
    await directLink(guest, { room_id: roomId, invite_code: "", host: false, api_version: 2 });
    state = value(await roomV2(roomId).join(guest.player_id, invite));
  }
  return state;
}
/** Both members play a Relay room to the end. */
async function playOut(room: RoomSnapshotV2, host: Account, guest: Account): Promise<RoomSnapshotV2> {
  let state = room;
  for (const [owner, recording, checkpoint] of [[host, firstA, undefined], [guest, firstB, middle], [guest, secondA, undefined], [host, secondB, final]] as const)
    state = value(await roomV2(room.room_id).commit(owner.player_id, { base_revision: state.revision, branch: state.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) })).room;
  expect(state.active_role).toBe("complete");
  return state;
}
async function finishedRoom(host: Account, guest: Account): Promise<RoomSnapshotV2> { return playOut(await directRoom(host, guest), host, guest); }

async function indexRows(account: Account): Promise<IndexRow[]> {
  return runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) =>
    ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='room_index'").toArray().length
      ? ctx.storage.sql.exec<IndexRow>("SELECT room_id,api_version,state,observed_at,checked_at,entry FROM room_index ORDER BY room_id").toArray() : []);
}
async function indexRow(account: Account, roomId: string): Promise<IndexRow | undefined> { return (await indexRows(account)).find(row => row.room_id === roomId); }
/** Pushes run after the room's answer; wait for the row to say what we expect. */
async function eventually<T>(read: () => Promise<T>, done: (value: T) => boolean): Promise<T> {
  let last = await read();
  for (let attempt = 0; attempt < 200 && !done(last); attempt++) { await new Promise(resolve => setTimeout(resolve, 10)); last = await read(); }
  return last;
}
/** The projection a row stores (rows store the room's whole answer). */
const projection = (row: IndexRow) => (JSON.parse(row.entry!) as { value: RoomInboxProjection }).value;
const stateOf = (account: Account, roomId: string, state: string) => eventually(() => indexRow(account, roomId), row => row?.state === state);
/** Ages every row past its freshness window, as if the last checks were long ago. */
async function age(account: Account, by = 48 * 3_600_000): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => { ctx.storage.sql.exec("UPDATE room_index SET checked_at=checked_at-?", by); });
}
async function tableNames(account: Account): Promise<string[]> {
  return runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => ctx.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").toArray().map(row => row.name));
}
const links = (account: Account) => env.PLAYERS.getByName(account.player_id).listRooms();
const inbox = async (account: Account, headers: Record<string, string> = {}) => (await call("/v1/room-inbox", "GET", account, undefined, headers)).json<Inbox>();
/**
 * Loses the room index push `work` makes for this row, as a push dropped in transit would: waits for the push to
 * land, then puts the row back as it was before.
 */
async function losePush(account: Account, roomId: string, work: () => Promise<unknown>): Promise<void> {
  const before = (await indexRow(account, roomId))!;
  await work();
  await eventually(() => indexRow(account, roomId), row => row?.observed_at !== before.observed_at);
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => {
    ctx.storage.sql.exec("UPDATE room_index SET state=?,observed_at=?,checked_at=?,entry=? WHERE room_id=?", before.state, before.observed_at, before.checked_at, before.entry, roomId);
  });
}

afterEach(async () => { await reset(); }, 300_000);

describe("room index rows", () => {
  it("follow a v2 room through create, join, turns, finish, transfer, close, leave and identity deletion", async () => {
    const host = await identity(), guest = await identity();
    const room = await hosted(host);
    // A room in play is pushed nothing; the first inbox read stores it, and every later one reads it live.
    expect(await indexRow(host, room.room_id)).toBeUndefined();
    await inbox(host);
    expect(projection((await indexRow(host, room.room_id))!)).toMatchObject({ status: "waiting_for_friend", membership: { host_id: host.player_id, guest_id: null } });
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
    await inbox(guest);
    expect(projection((await indexRow(guest, room.room_id))!)).toMatchObject({ status: "waiting_for_their_turn", membership: { host_id: host.player_id, guest_id: guest.player_id } });
    await inbox(host);
    expect(projection((await indexRow(host, room.room_id))!).membership.guest_id).toBe(guest.player_id);
    // The finishing turn pushes both rows to finished.
    const done = await playOut(value(await roomV2(room.room_id).snapshot(host.player_id)), host, guest);
    for (const member of [host, guest]) {
      const row = await stateOf(member, room.room_id, "finished");
      expect(projection(row!)).toEqual(value(await roomV2(room.room_id).inboxProjection(member.player_id)));
    }
    // A replay transfer keeps the room finished in both rows.
    const offered = await (await call(`/v2/rooms/${done.room_id}/replay-transfer`, "GET", host)).json<{ manifest: { epoch: number; archive_hash: string } }>();
    for (const member of [host, guest])
      expect((await call(`/v2/rooms/${done.room_id}/replay-transfer/ack`, "POST", member, { schema_version: 1, epoch: offered.manifest.epoch, archive_hash: offered.manifest.archive_hash })).status).toBe(200);
    expect((await indexRow(host, done.room_id))!.state).toBe("finished");
    await inbox(guest);

    // Close: the closer's row goes with the link; the partner's row reads closed.
    const second = await hosted(host);
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: second.invite_code })).status).toBe(200);
    expect((await call(`/v2/rooms/${second.room_id}`, "DELETE", guest)).status).toBe(200);
    expect(await indexRow(guest, second.room_id)).toBeUndefined();
    await stateOf(host, second.room_id, "gone");
    expect((await inbox(host, { "X-AfterYou-Room-Inbox": "2" })).rooms.find(item => item.room_id === second.room_id)?.status).toBe("closed");
    // Leaving the closed room drops the host's row with its link.
    expect((await call(`/v2/rooms/${second.room_id}/leave`, "POST", host, { schema_version: 1 })).status).toBe(200);
    expect(await indexRow(host, second.room_id)).toBeUndefined();

    // Identity deletion erases the rooms and drops the index tables.
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    expect(await tableNames(host)).not.toContain("room_index");
    await stateOf(guest, done.room_id, "gone");
  }, 60_000);

  it("follow a v1 room through create, join, a turn, a reaction-free close and a 404 prune", async () => {
    const host = await identity(), guest = await identity();
    const made = await call("/v1/rooms", "POST", host, { idempotency_key: key() });
    const room = await made.json<{ room_id: string; invite_code: string; revision: number }>();
    await inbox(host);
    expect(projection((await indexRow(host, room.room_id))!)).toMatchObject({ status: "waiting_for_friend" });
    const joined = await (await call("/v1/rooms/join", "POST", guest, { invite_code: room.invite_code })).json<{ revision: number; level_id: string }>();
    await inbox(host);
    expect(projection((await indexRow(host, room.room_id))!).status).toBe("your_turn");
    const turn = await call(`/v1/rooms/${room.room_id}/turns`, "POST", host, { base_revision: joined.revision, idempotency_key: key(), recording: {
      schema_version: 1, simulation_version: 1, level_version: 1, tick_rate: 30, level_id: joined.level_id, role: "a", duration_ticks: 30, catch_assistance: true,
      actions: [{ ticks: 30, x: 0, z: 0, action: true }], checkpoints: [{ tick: 30, state_hash: "a".repeat(64) }], final_state_hash: "a".repeat(64), completed: false,
      outcome: { threw_seed: true, caught_seed: false, planted_seed: false } } });
    expect(turn.status).toBe(200);
    await inbox(guest);
    expect(projection((await indexRow(guest, room.room_id))!).status).toBe("your_turn");
    expect((await call(`/v1/rooms/${room.room_id}`, "DELETE", host)).status).toBe(200);
    await stateOf(guest, room.room_id, "gone");
    expect(await indexRow(host, room.room_id)).toBeUndefined();
  }, 30_000);

  it("keep the newer observation when an older one arrives late", async () => {
    const host = await identity(), guest = await identity();
    const room = await directRoom(host, guest), done = await playOut(room, host, guest);
    const fresh = await stateOf(host, done.room_id, "finished");
    // An observation from before the finish, as a slow read-back would deliver it.
    const stale = { observed_at: fresh!.observed_at - 1, outcome: { ok: true as const, value: { ...projection(fresh!), status: "your_turn" as const } } };
    await env.PLAYERS.getByName(host.player_id).recordRoomIndex(host.player_id, [{ room_id: done.room_id, api_version: 2, observation: stale }]);
    await env.PLAYERS.getByName(host.player_id).noteRoomIndex(host.player_id, done.room_id, 2, stale);
    const after = await indexRow(host, done.room_id);
    expect(after).toMatchObject({ state: "finished", observed_at: fresh!.observed_at, entry: fresh!.entry });
    // An unlinked room and another member's identity are ignored.
    await env.PLAYERS.getByName(host.player_id).noteRoomIndex(guest.player_id, "Z".repeat(22), 2, stale);
    await env.PLAYERS.getByName(host.player_id).noteRoomIndex(host.player_id, "Z".repeat(22), 2, stale);
    expect((await indexRows(host)).map(row => row.room_id)).toEqual([done.room_id]);
  });

  it("self-heal a fork whose push was lost, within ceil(rows / rechecks) inbox reads", async () => {
    const host = await identity(), guests = [await directIdentity(), await directIdentity()];
    const rooms: RoomSnapshotV2[] = [];
    for (let index = 0; index < 20; index++) rooms.push(await finishedRoom(host, guests[index % 2]));
    for (const room of rooms) await stateOf(host, room.room_id, "finished");
    // The push is lost while the guest reopens one room.
    const target = rooms[13];
    await losePush(host, target.room_id, async () => {
      const reopened = value(await roomV2(target.room_id).fork(guests[1].player_id, { base_revision: target.revision, idempotency_key: key(), branch: target.branch, stage_index: 0 }));
      expect(reopened.room.active_role).not.toBe("complete");
    });
    expect((await indexRow(host, target.room_id))!.state).toBe("finished");
    await age(host);
    let reads = 0;
    while ((await indexRow(host, target.room_id))!.state !== "in_play") { reads++; await inbox(host); expect(reads).toBeLessThanOrEqual(Math.ceil(rooms.length / ROOM_INDEX_RECHECKS) + 1); }
    expect((await inbox(host)).rooms.find(room => room.room_id === target.room_id)?.status).not.toBe("completed");
  }, 60_000);

  it("backfill 60 unindexed links on the first indexed read, and finish an interrupted backfill", async () => {
    const host = await identity(), guests = [await directIdentity(), await directIdentity(), await directIdentity()];
    for (let index = 0; index < 40; index++) await finishedRoom(host, guests[index % 3]);
    for (let index = 0; index < 20; index++) await directRoom(host, index % 2 ? guests[index % 3] : undefined);
    expect(await links(host)).toHaveLength(MAX_ROOM_LINKS);
    // Links from before the index: the finish pushes are in, then the table goes.
    await eventually(() => indexRows(host), rows => rows.filter(row => row.state === "finished").length === 40);
    await runInDurableObject(env.PLAYERS.getByName(host.player_id), async (_, ctx) => { ctx.storage.sql.exec("DROP TABLE room_index"); });
    expect(await tableNames(host)).not.toContain("room_index");
    await countRows();
    const first = await measured("/v1/room-inbox", host, { "X-AfterYou-Room-Inbox": "2" });
    expect(first.response.headers.get(ROOM_NEXT_HEADER)).toBeNull();
    expect((await indexRows(host)).filter(row => row.state !== "unchecked")).toHaveLength(MAX_ROOM_LINKS);
    expect(first.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    // Warm: rows are fresh, so nothing is read live.
    const warm = await measured("/v1/room-inbox", host, { "X-AfterYou-Room-Inbox": "2" });
    expect(warm.text).toBe(first.text);
    // Warm: only the 20 rooms in play are read live.
    expect(warm.counter.methods["ROOMS_V2.indexEntry"] ?? 0).toBe(20);
    // Cold: an hour later every row is past its window. Rows in play are read, settled rows only through the re-checks.
    await age(host);
    const cold = await measured("/v1/room-inbox", host, { "X-AfterYou-Room-Inbox": "2" });
    expect(cold.text).toBe(first.text);
    expect(cold.counter.methods["ROOMS_V2.indexEntry"]).toBeLessThanOrEqual(20 + ROOM_INDEX_RECHECKS);
    const relay = await measured("/v2/rooms", host), legacy = await measured("/v1/rooms", host);
    expect(relay.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET); expect(legacy.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    console.log("ROOM_INDEX_COST 60 links", JSON.stringify({
      inbox_backfill: { calls: first.calls, rows: first.rows }, inbox_warm: { calls: warm.calls, rows: warm.rows }, inbox_cold: { calls: cold.calls, rows: cold.rows },
      relay_indexed: { calls: relay.calls, rows: relay.rows }, legacy_indexed: { calls: legacy.calls, rows: legacy.rows } }));

    // An interrupted backfill: half the rows are gone, and the next read restores them.
    await runInDurableObject(env.PLAYERS.getByName(host.player_id), async (_, ctx) => { ctx.storage.sql.exec("DELETE FROM room_index WHERE rowid % 2 = 0"); });
    expect((await indexRows(host)).length).toBeLessThan(MAX_ROOM_LINKS);
    expect(await (await call("/v1/room-inbox", "GET", host, undefined, { "X-AfterYou-Room-Inbox": "2" })).text()).toBe(first.text);
    expect(await indexRows(host)).toHaveLength(MAX_ROOM_LINKS);
  }, 180_000);

  it("answer an empty player within the budget", async () => {
    await countRows();
    const host = await identity();
    for (const path of ["/v1/room-inbox", "/v2/rooms", "/v1/rooms"]) {
      const result = await measured(path, host);
      expect(result.response.status).toBe(200); expect(result.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    }
  });
});

describe("room index at 500 links", () => {
  it("pages lists and the inbox within the budget, refuses link 501, and deletes every room in bounded batches", async () => {
    await countRows();
    const owner = await identity();
    const partners: Account[] = [];
    for (let index = 0; index < 120; index++) partners.push(await directIdentity());
    const inPlay: string[] = [], all: string[] = [];
    // 20 waiting rooms, 480 finished with 120 different partners.
    for (let index = 0; index < MAX_ACTIVE_ROOM_LINKS; index++) { const room = await directRoom(owner); inPlay.push(room.room_id); all.push(room.room_id); }
    for (let start = 0; start < MAX_INDEXED_ROOM_LINKS - MAX_ACTIVE_ROOM_LINKS; start += 20) {
      const batch = await Promise.all(Array.from({ length: 20 }, (_, offset) => finishedRoom(owner, partners[(start + offset) % partners.length])));
      all.push(...batch.map(room => room.room_id));
    }
    expect(await links(owner)).toHaveLength(MAX_INDEXED_ROOM_LINKS);
    await eventually(() => indexRows(owner), rows => rows.filter(row => row.state === "finished").length === all.length - inPlay.length);

    // The inbox: 100 rooms, every room in play among them, and the next offset.
    const first = await measured("/v1/room-inbox", owner);
    const page = JSON.parse(first.text) as Inbox;
    expect(page.rooms).toHaveLength(ROOM_INBOX_PAGE);
    for (const id of inPlay) expect(page.rooms.map(room => room.room_id)).toContain(id);
    expect(first.response.headers.get(ROOM_NEXT_HEADER)).toBe(String(ROOM_INBOX_PAGE));
    expect(first.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    // Every offset walks all 500 rooms once.
    const seen: string[] = [];
    for (let offset: string | null = "0"; offset !== null;) {
      const response = await call("/v1/room-inbox", "GET", owner, undefined, { [ROOM_PAGE_HEADER]: offset });
      seen.push(...(await response.json<Inbox>()).rooms.map(room => room.room_id));
      offset = response.headers.get(ROOM_NEXT_HEADER);
    }
    expect([...seen].sort()).toEqual([...all].sort());
    const warm = await measured("/v1/room-inbox", owner);
    expect(warm.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    await age(owner);
    const cold = await measured("/v1/room-inbox", owner);
    expect(cold.counter.methods["ROOMS_V2.indexEntry"]).toBeLessThanOrEqual(inPlay.length + ROOM_INDEX_RECHECKS);
    expect(cold.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);

    // A finished room far off the first page is reopened and its push is lost; re-checks find it.
    const firstPage = new Set(page.rooms.map(room => room.room_id));
    const target = all.filter(id => !firstPage.has(id)).at(-1)!;
    const targetState = value(await roomV2(target).snapshot(owner.player_id));
    const partner = partners.find(account => account.player_id === targetState.guest_id)!;
    await losePush(owner, target, async () => value(await roomV2(target).fork(partner.player_id, { base_revision: targetState.revision, idempotency_key: key(), branch: targetState.branch, stage_index: 0 })));
    await age(owner);
    let healReads = 0;
    while ((await indexRow(owner, target))!.state !== "in_play") { healReads++; await inbox(owner); expect(healReads).toBeLessThanOrEqual(Math.ceil(MAX_INDEXED_ROOM_LINKS / ROOM_INDEX_RECHECKS) + 1); }
    expect((await inbox(owner)).rooms.map(room => room.room_id)).toContain(target);

    // The v2 list: 60 rooms, rooms in play first, within the budget.
    const relay = await measured("/v2/rooms", owner);
    const listed = (JSON.parse(relay.text) as { rooms: RoomSnapshotV2[] }).rooms;
    expect(listed).toHaveLength(ROOM_LIST_PAGE);
    for (const id of inPlay) expect(listed.map(room => room.room_id)).toContain(id);
    expect(relay.response.headers.get(ROOM_NEXT_HEADER)).toBe(String(ROOM_LIST_PAGE));
    expect(relay.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    const legacy = await measured("/v1/rooms", owner);
    expect(legacy.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    console.log("ROOM_INDEX_COST 500 links", JSON.stringify({ inbox_first: { calls: first.calls, rows: first.rows, methods: first.counter.methods }, inbox_warm: { calls: warm.calls, rows: warm.rows }, inbox_cold: { calls: cold.calls, rows: cold.rows, methods: cold.counter.methods }, heal_reads: healReads,
      relay: { calls: relay.calls, rows: relay.rows }, legacy: { calls: legacy.calls, rows: legacy.rows } }));

    // The total bound, with the exact old answer.
    const refused = await createV2(owner);
    expect(refused.status).toBe(409); expect(await refused.text()).toBe(LIMIT_BODY);

    // Identity deletion: the request revokes the identity, erases one batch and answers today's 200.
    const deletion = await measured("/v1/identity", owner, {}, "DELETE");
    expect(deletion.response.status).toBe(200);
    expect(JSON.parse(deletion.text)).toEqual({ deleted: true });
    expect(deletion.calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    expect(await links(owner)).toHaveLength(MAX_INDEXED_ROOM_LINKS - ROOM_DELETION_BATCH);
    // Every other request is refused at once, and the acknowledgement waits until the erasure is done.
    expect((await call("/v1/room-inbox", "GET", owner)).status).toBe(401);
    const ack = () => call("/v1/identity/deletion-ack", "POST", owner, { schema_version: 1 });
    const early = await ack();
    expect(early.status).toBe(409); expect(await early.text()).toBe('{"error":{"code":"deletion_not_ready","retryable":false}}');
    // A retry racing the alarm erases another batch and answers 200 again.
    expect((await call("/v1/identity", "DELETE", owner)).status).toBe(200);
    const player = env.PLAYERS.getByName(owner.player_id);
    const alarmCalls: number[] = [];
    for (let batch = 0; batch < 20 && (await runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec("SELECT 1 FROM identity").toArray().length)); batch++) alarmCalls.push(await countedAlarm(player));
    console.log("ROOM_INDEX_COST deletion", JSON.stringify({ request: deletion.calls, alarms: alarmCalls }));
    expect(alarmCalls.length).toBeGreaterThan(0);
    for (const calls of alarmCalls) expect(calls).toBeLessThanOrEqual(ROOM_INDEX_BUDGET);
    // Under load the runtime's own alarm may hold the batch the helper would run; let it finish.
    for (let wait = 0; wait < 120 && (await runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec("SELECT 1 FROM identity").toArray().length)); wait++) {
      await runDurableObjectAlarm(player); await new Promise(resolve => setTimeout(resolve, 250));
    }
    expect(await runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec("SELECT 1 FROM identity").toArray().length)).toBe(0);
    expect(await links(owner)).toHaveLength(0);
    // Every one of the 500 rooms was erased, not just unlinked.
    const erased = await Promise.all(all.map(id => runInDurableObject(roomV2(id), async (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0]?.data)));
    expect(erased.filter(data => data !== '{"deleted":true}')).toEqual([]);
    expect((await call("/v1/identity", "DELETE", owner)).status).toBe(200);
    expect((await ack()).status).toBe(200);
    expect((await call("/v1/identity", "DELETE", owner)).status).toBe(401);
  }, 1_200_000);
});

describe("room cap with the index", () => {
  it("still refuses a 21st room in play with the exact old answer, and passes 60 links only fully indexed", async () => {
    const host = await identity(), guest = await directIdentity();
    for (let index = 0; index < MAX_ACTIVE_ROOM_LINKS; index++) await hosted(host);
    const refused = await createV2(host);
    expect(refused.status).toBe(409); expect(await refused.text()).toBe(LIMIT_BODY);

    const other = await identity();
    for (let index = 0; index < MAX_ROOM_LINKS; index++) await finishedRoom(other, guest);
    await eventually(() => indexRows(other), rows => rows.filter(row => row.state === "finished").length === MAX_ROOM_LINKS);
    // A missing row holds the bound at 60 until the refusal path reads it back.
    const missing = (await links(other))[7].room_id;
    await runInDurableObject(env.PLAYERS.getByName(other.player_id), async (_, ctx) => { ctx.storage.sql.exec("DELETE FROM room_index WHERE room_id=?", missing); });
    expect(await env.PLAYERS.getByName(other.player_id).addRoom({ room_id: "Q".repeat(22), invite_code: "", host: false, api_version: 2 })).toMatchObject({ ok: false, code: "room_limit_reached" });
    expect((await createV2(other)).status).toBe(200);
    expect(await indexRow(other, missing)).toMatchObject({ state: "finished" });
  }, 120_000);
});

describe("room index and Player export", () => {
  it("keeps Player export working and skips the index in it", async () => {
    const host = await identity(), guest = await identity();
    const room = await hosted(host);
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
    await playOut(value(await roomV2(room.room_id).snapshot(host.player_id)), host, guest);
    await inbox(host);
    expect(await tableNames(host)).toContain("room_index");
    const archive = JSON.parse(value(await env.PLAYERS.getByName(host.player_id).exportSnapshot("f".repeat(40))));
    expect(archive.payload.tables.map((table: { name: string }) => table.name)).toEqual(["identity", "rooms", "creations"]);
    // Deleting the identity drops the index again.
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    expect(await tableNames(host)).not.toContain("room_index");
  }, 30_000);
});

describe("room index costs and erasure", () => {
  it("clears the erased member from a partner's row", async () => {
    const host = await identity(), guest = await identity();
    const done = await finishedRoom(host, guest);
    await stateOf(guest, done.room_id, "finished");
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    const row = await stateOf(guest, done.room_id, "gone");
    expect(row!.entry).not.toContain(host.player_id);
  }, 60_000);

  it("finishes a deletion above 60 links whose request batch holds a room that always fails", async () => {
    const owner = await identity(), guest = await directIdentity();
    const rooms: string[] = [];
    for (let index = 0; index < MAX_ROOM_LINKS + 10; index++) rooms.push((await directRoom(owner, index % 2 ? guest : undefined)).room_id);
    // The newest room is first in the request's batch; its erase always throws.
    const broken = rooms.at(-1)!;
    await runInDurableObject(roomV2(broken), async (_, ctx) => { ctx.storage.sql.exec("CREATE TRIGGER synthetic_erase_failure BEFORE UPDATE ON room BEGIN SELECT RAISE(ABORT,'synthetic_failure'); END"); });
    const deleted = await call("/v1/identity", "DELETE", owner);
    expect(deleted.status).toBe(200);
    const player = env.PLAYERS.getByName(owner.player_id);
    for (let batch = 0; batch < 10 && (await links(owner)).length > 1; batch++) await runDurableObjectAlarm(player);
    expect((await links(owner)).map(link => link.room_id)).toEqual([broken]);
    const erasure = await runInDurableObject(player, async (_, ctx) => ({ marker: ctx.storage.sql.exec<{ attempts: number; failed: string }>("SELECT attempts,failed FROM room_erasure").toArray()[0], alarm: await ctx.storage.getAlarm() }));
    expect(erasure.marker.attempts).toBeGreaterThan(0); expect(JSON.parse(erasure.marker.failed)).toEqual([broken]); expect(erasure.alarm).not.toBeNull();
    const others = await Promise.all(rooms.filter(id => id !== broken).map(id => runInDurableObject(roomV2(id), async (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0]?.data)));
    expect(others.filter(data => data !== '{"deleted":true}')).toEqual([]);
    // Once the room can be written again, the next alarm finishes the deletion.
    await runInDurableObject(roomV2(broken), async (_, ctx) => { ctx.storage.sql.exec("DROP TRIGGER synthetic_erase_failure"); });
    await runDurableObjectAlarm(player);
    expect(await runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec("SELECT 1 FROM identity").toArray().length)).toBe(0);
    expect((await call("/v1/identity", "DELETE", owner)).status).toBe(200);
  }, 120_000);

  it("hides a room blocked in either direction from the indexed inbox and both indexed lists", async () => {
    const host = await identity(), blocker = await identity(), blocked = await identity(), friend = await identity();
    const pair = async (guest: Account, v2: boolean) => {
      const made = await call(v2 ? "/v2/rooms" : "/v1/rooms", "POST", host, { idempotency_key: key(), ...(v2 ? { level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH } : {}) });
      const room = await made.json<{ room_id: string; invite_code: string }>();
      expect((await call(v2 ? "/v2/rooms/join" : "/v1/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
      return room.room_id;
    };
    const kept = [await pair(friend, true), await pair(friend, false)];
    await pair(blocker, true); await pair(blocker, false); await pair(blocked, true); await pair(blocked, false);
    for (const [owner, peer] of [[blocker, host], [host, blocked]] as const)
      expect((await env.SAFETY_PROFILES.getByName(owner.player_id).setBlock(owner.player_id, await digest(owner.device_token), peer.player_id, true)).ok).toBe(true);
    const ids = async (path: string, account: Account) => (await (await call(path, "GET", account)).json<{ rooms: { room_id: string }[] }>()).rooms.map(room => room.room_id).sort();
    expect(await ids("/v1/room-inbox", host)).toEqual([...kept].sort());
    expect(await ids("/v2/rooms", host)).toEqual([kept[0]]);
    expect(await ids("/v1/rooms", host)).toEqual([kept[1]]);
    for (const member of [blocker, blocked]) for (const path of ["/v1/room-inbox", "/v2/rooms", "/v1/rooms"]) expect(await ids(path, member)).toEqual([]);
  }, 60_000);

  it("measures a typical player's day: 10 rooms, 5 inbox opens, 3 lobby opens and 20 turns", async () => {
    const day = async () => {
      const owner = await identity(), partners = [await identity(), await identity(), await identity()];
      for (let index = 0; index < 5; index++) await finishedRoom(owner, partners[index % 3]);
      const today: { room: RoomSnapshotV2; guest: Account }[] = [];
      for (let index = 0; index < 5; index++) { const guest = partners[index % 3]; today.push({ room: await directRoom(owner, guest), guest }); }
      await eventually(() => indexRows(owner), rows => rows.length === 10); await age(owner, 12 * 3_600_000);
      await countRows();
      const totals: Counter = { calls: 0, methods: {} };
      let rows = 0;
      for (const [session, { room, guest }] of today.entries()) {
        await age(owner, 3 * 3_600_000);
        const { counter, restore } = await countEverything();
        const start = cursors.length;
        try {
          expect((await call("/v1/room-inbox", "GET", owner)).status).toBe(200);
          if (session < 3) expect((await call("/v2/rooms", "GET", owner)).status).toBe(200);
          let state = room;
          for (const [player, recording, checkpoint] of [[owner, firstA, undefined], [guest, firstB, middle], [guest, secondA, undefined], [owner, secondB, final]] as const) {
            const turn = await call(`/v2/rooms/${room.room_id}/turns`, "POST", player, { base_revision: state.revision, branch: state.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) });
            expect(turn.status).toBe(200); state = (await turn.json<{ room: RoomSnapshotV2 }>()).room;
          }
          await new Promise(resolve => setTimeout(resolve, 100));
        } finally { await restore(); }
        rows += rowsSince(start); totals.calls += counter.calls;
        for (const [name, count] of Object.entries(counter.methods)) totals.methods[name] = (totals.methods[name] ?? 0) + count;
      }
      const counter = totals;
      return { methods: counter.methods, do_requests: counter.calls, rows_read: rows, pushes: counter.methods["PLAYERS.noteRoomIndex"] ?? 0, room_reads: (counter.methods["ROOMS_V2.inboxProjection"] ?? 0) + (counter.methods["ROOMS_V2.indexEntry"] ?? 0) };
    };
    const on = await day();
    console.log("ROOM_INDEX_COST typical day", JSON.stringify({ on }));
    // Pushes only when a room finishes (2 each, 5 rooms).
    expect(on.pushes).toBe(10);
  }, 180_000);

  it("finishes a deletion above 60 links whose provider erasure is held, when the device's acknowledgement retries", async () => {
    const shared = env as unknown as Record<string, string | undefined>;
    const before = { REVENUECAT_SECRET_KEY: shared.REVENUECAT_SECRET_KEY, CONFIG: shared.CONFIG };
    Object.assign(shared, { REVENUECAT_SECRET_KEY: "synthetic-only", CONFIG: configJson({ revenuecat: { project_id: "projSynthetic" } }) });
    const provider = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 503 }));
    try {
      const owner = await identity();
      for (let index = 0; index < MAX_ROOM_LINKS + 1; index++) await directRoom(owner);
      expect((await call("/v1/identity", "DELETE", owner)).status).toBe(200);
      const player = env.PLAYERS.getByName(owner.player_id), safety = env.SAFETY_PROFILES.getByName(owner.player_id);
      for (let batch = 0; batch < 5 && (await links(owner)).length; batch++) await runDurableObjectAlarm(player);
      expect(await links(owner)).toEqual([]);
      const job = () => runInDurableObject(safety, async (_, ctx) => readErasure(ctx.storage));
      const due = async () => { await runInDurableObject(safety, async (_, ctx) => { const current = readErasure(ctx.storage)!; current.next_at = Date.now(); writeErasure(ctx.storage, current); }); await runDurableObjectAlarm(safety); };
      // The provider refuses until the job holds after 8 attempts; nothing else would resume it.
      for (let attempt = 0; attempt < 10 && (await job())!.attempts < 8; attempt++) await due();
      expect(await job()).toMatchObject({ state: "pending", attempts: 8 });
      expect(await runInDurableObject(safety, async (_, ctx) => ctx.storage.getAlarm())).toBeNull();
      const ack = () => call("/v1/identity/deletion-ack", "POST", owner, { schema_version: 1 });
      // The device's acknowledgement retry resumes the held job and answers as before.
      expect((await ack()).status).toBe(401);
      expect(await job()).toMatchObject({ state: "pending", attempts: 0 });
      provider.mockResolvedValue(new Response(null, { status: 200 }));
      await due();
      expect(await job()).toMatchObject({ state: "complete" });
      expect(await runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec("SELECT 1 FROM identity").toArray().length)).toBe(0);
      expect((await ack()).status).toBe(200);
    } finally {
      for (const [name, value] of Object.entries(before)) { if (value === undefined) delete shared[name]; else shared[name] = value; }
      provider.mockRestore();
    }
  }, 120_000);

  it("keeps a 404 read between a link's reservation and its room's start unchecked, never settled, and reads it again", async () => {
    const host = await identity(), player = env.PLAYERS.getByName(host.player_id);
    const invite = "C".repeat(20), roomId = (await digest("v2:" + invite)).slice(0, 22);
    // POST /v2/rooms reserves the link before it starts the room; an inbox read can land in between.
    value(await player.addRoom({ room_id: roomId, invite_code: invite, host: true, api_version: 2 }));
    expect((await inbox(host)).rooms.find(room => room.room_id === roomId)?.status).toBe("unavailable");
    expect(await indexRow(host, roomId)).toMatchObject({ state: "unchecked" });
    expect(await player.roomIndexSettled()).toEqual([]);
    // The read of the room that has not started stored nothing in it.
    expect(await runInDurableObject(roomV2(roomId), async (_, ctx) => ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table'").toArray().length)).toBe(0);
    value(await roomV2(roomId).initialize(roomId, host.player_id, invite));
    expect((await inbox(host)).rooms.find(room => room.room_id === roomId)?.status).toBe("waiting_for_friend");
    expect(await indexRow(host, roomId)).toMatchObject({ state: "in_play" });
  });

  it("erases the deleted host's waiting rooms in the request above 60 links, and picks a lost continuation up again on the next wake", async () => {
    const owner = await identity(), guest = await directIdentity(), stranger = await identity();
    // The oldest link, so link order alone would leave it to a later batch.
    const waiting = await directRoom(owner);
    for (let index = 0; index < MAX_ROOM_LINKS; index++) await finishedRoom(owner, guest);
    await eventually(() => indexRows(owner), rows => rows.filter(row => row.state === "finished").length === MAX_ROOM_LINKS);
    expect((await call("/v1/identity", "DELETE", owner)).status).toBe(200);
    expect(await runInDurableObject(roomV2(waiting.room_id), async (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0]?.data)).toBe('{"deleted":true}');
    const joined = await call("/v2/rooms/join", "POST", stranger, { invite_code: waiting.invite_code });
    expect(joined.status).toBe(404);
    // An alarm lost across a rollback: the next wake of the Player sets it again.
    const player = env.PLAYERS.getByName(owner.player_id);
    const pending = await runInDurableObject(player, async (_, ctx) => { await ctx.storage.deleteAlarm(); return { links: ctx.storage.sql.exec("SELECT 1 FROM rooms").toArray().length, marker: ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='room_erasure'").toArray().length }; });
    expect(pending.marker).toBe(1); expect(pending.links).toBeGreaterThan(0);
    await evictDurableObject(player);
    expect((await call("/v1/identity/deletion-ack", "POST", { ...owner, device_token: "x".repeat(43) }, { schema_version: 1 })).status).toBe(200);
    // The wake set the alarm again (due at once), and it finishes the deletion.
    const identityRows = () => runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec("SELECT 1 FROM identity").toArray().length);
    await eventually(identityRows, rows => rows === 0);
    expect(await runInDurableObject(player, async (_, ctx) => ctx.storage.sql.exec("SELECT 1 FROM identity").toArray().length)).toBe(0);
  }, 120_000);

  it("stores nothing for a deletion acknowledgement or an index push to a player id that never existed", async () => {
    const stranger = { player_id: "Q".repeat(22), device_token: "x".repeat(43), recovery_code: "" };
    expect((await call("/v1/identity/deletion-ack", "POST", stranger, { schema_version: 1 })).status).toBe(200);
    await env.PLAYERS.getByName(stranger.player_id).noteRoomIndex(stranger.player_id, "R".repeat(22), 2, { observed_at: 1, outcome: { ok: false, status: 410, code: "room_closed" } });
    const tables = await runInDurableObject(env.PLAYERS.getByName(stranger.player_id), async (_, ctx) => ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table'").toArray().length);
    expect(tables).toBe(0);
  });

  it("gives the partner's row partner_left when the other member leaves a finished room", async () => {
    const host = await identity(), guest = await identity();
    const done = await finishedRoom(host, guest);
    await stateOf(host, done.room_id, "finished");
    const leaving = (path: string, method: string, account: Account, body?: unknown, headers: Record<string, string> = {}) => {
      return worker.fetch(request(path, method, account, body, headers), settings());
    };
    expect((await leaving(`/v2/rooms/${done.room_id}/leave`, "POST", guest, { schema_version: 1, leave_finished: true })).status).toBe(200);
    const row = await eventually(() => indexRow(host, done.room_id), value => !!value?.entry && projection(value).partner_left === true);
    expect(projection(row!).partner_left).toBe(true);
    const listed = await (await leaving("/v1/room-inbox", "GET", host, undefined, { "X-AfterYou-Room-Leave": "1" })).json<{ rooms: { room_id: string; partner_left?: true }[] }>();
    expect(listed.rooms.find(room => room.room_id === done.room_id)?.partner_left).toBe(true);
  }, 30_000);
});
