import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { digest } from "../src/protocol";
import { partnerBlocks } from "../src/safety";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";

type Account = { player_id: string; device_token: string; recovery_code: string };
let address = 0;
function blockTestCall(path: string, method = "GET", account?: Account, body?: unknown, extra: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env };
  Object.assign(configured, extra);
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.4." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
const call = blockTestCall;
const identity = async () => (await call("/v1/identity", "POST", undefined, {})).json<Account>();
async function pair(host: Account, guest: Account, v2: boolean): Promise<string> {
  const made = await call(v2 ? "/v2/rooms" : "/v1/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), ...(v2 ? { level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH } : {}) });
  const room = await made.json<{ room_id: string; invite_code: string }>();
  expect((await call(v2 ? "/v2/rooms/join" : "/v1/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
  return room.room_id;
}
async function block(owner: Account, peer: Account): Promise<void> {
  expect((await env.SAFETY_PROFILES.getByName(owner.player_id).setBlock(owner.player_id, await digest(owner.device_token), peer.player_id, true)).ok).toBe(true);
}
/** The rooms each of the caller's lists shows: the inbox, GET /v2/rooms and GET /v1/rooms. */
async function listedRooms(account: Account, extra: Record<string, string> = {}): Promise<{ inbox: string[]; relay: string[]; legacy: string[] }> {
  const ids = async (path: string) => (await (await call(path, "GET", account, undefined, extra)).json<{ rooms: { room_id: string }[] }>()).rooms.map(room => room.room_id).sort();
  return { inbox: await ids("/v1/room-inbox"), relay: await ids("/v2/rooms"), legacy: await ids("/v1/rooms") };
}
afterEach(async () => { await reset(); });

describe("block checks per partner", () => {
  it("hide a room blocked in either direction from the inbox and both lists, for both members", async () => {
    const host = await identity(), blocker = await identity(), blocked = await identity(), friend = await identity();
    const rooms = { blocker: [await pair(host, blocker, true), await pair(host, blocker, false)], blocked: [await pair(host, blocked, true), await pair(host, blocked, false)], friend: [await pair(host, friend, true), await pair(host, friend, false)] };
    await block(blocker, host); await block(host, blocked);
    const shown = await listedRooms(host);
    expect(shown.inbox).toEqual([...rooms.friend].sort());
    expect(shown.relay).toEqual([rooms.friend[0]]);
    expect(shown.legacy).toEqual([rooms.friend[1]]);
    for (const member of [blocker, blocked]) expect(await listedRooms(member)).toEqual({ inbox: [], relay: [], legacy: [] });
    expect((await listedRooms(friend)).inbox).toEqual([...rooms.friend].sort());
  }, 60_000);

  it("reads the caller's list once and each partner once, with interactionBlocked's answers", async () => {
    const host = await identity(), a = await identity(), b = await identity();
    await block(b, host);
    let calls = 0;
    const counting = { ...env, SAFETY_PROFILES: { getByName: (name: string) => { const stub = env.SAFETY_PROFILES.getByName(name);
      return { blocks: (owner: string) => { calls++; return stub.blocks(owner); }, hasBlocked: (owner: string, peer: string) => { calls++; return stub.hasBlocked(owner, peer); } }; } } } as unknown as Env;
    const check = partnerBlocks(counting, host.player_id);
    const answers = [await check(host.player_id, a.player_id), await check(a.player_id, host.player_id), await check(host.player_id, b.player_id), await check(b.player_id, host.player_id), await check(host.player_id, null)];
    expect(answers).toEqual([false, false, true, true, false]);
    expect(calls).toBe(3);
  });
});
