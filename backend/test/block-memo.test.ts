import { env } from "cloudflare:workers";
import { evictDurableObject, reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { Player } from "../src/player";
import { SafetyProfile } from "../src/safety";
import { RoomV2 } from "../src/v2/room";
import { UnblockedPairMemo } from "../src/v2/block-memo";
import { digest } from "../src/protocol";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { call, relayPair, type Account } from "./history-http";
import { countingEnv } from "./meter";
import { runInDurableObject } from "./room-objects";

// A Relay room remembers that its two players are not blocking each other, per player safety token,
// so a poll stops asking both SafetyProfiles. A block gives both players a new token before it answers.

afterEach(async () => { vi.restoreAllMocks(); await reset(); });
const code = async (response: Response) => `${response.status} ${response.status === 200 ? "ok" : (await response.json<{ error: { code: string } }>()).error.code}`;
const poll = (who: Account, room: { room_id: string; revision: number; branch: number }) =>
  call(`/v2/rooms/${room.room_id}`, "GET", who, undefined, {}, { "X-AfterYou-Known-Room": `${room.revision}.${room.branch}` });
const block = (by: Account, room: { room_id: string }) => call("/v1/safety/block", "POST", by, { schema_version: 1, room_family: "relay", room_id: room.room_id });
async function secondRoom(host: Account, guest: Account): Promise<RoomSnapshotV2> {
  const created = await call("/v2/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: (await created.json<RoomSnapshotV2>()).invite_code });
  expect(joined.status).toBe(200);
  return joined.json<RoomSnapshotV2>();
}
let address = 0;
async function countedPoll(who: Account, room: RoomSnapshotV2): Promise<string[]> {
  const { env: counting, calls } = countingEnv(env); Object.assign(counting, { V2_ROOMS_ENABLED: "true" });
  const response = await worker.fetch(new Request(`https://after-you.test/v2/rooms/${room.room_id}`, { headers: { "CF-Connecting-IP": "198.18.9." + (++address % 250),
    "X-Player-Id": who.player_id, Authorization: "Bearer " + who.device_token, "X-AfterYou-Known-Room": `${room.revision}.${room.branch}` } }), counting);
  expect(response.status).toBe(200); await response.arrayBuffer();
  return calls;
}
const everyone = async (pairs: [Account, RoomSnapshotV2][]) => Promise.all(pairs.map(async ([who, room]) => code(await poll(who, room))));

describe("unblocked pair memo", () => {
  it("lets a warm poll skip both block lookups", async () => {
    const { guest, room } = await relayPair(), hasBlocked = vi.spyOn(SafetyProfile.prototype, "hasBlocked");
    const calls = ["PLAYERS.authorizeRoom", "ROOMS_V2.interactionAllowed", "ROOMS_V2.snapshotIfChanged"];
    expect(await countedPoll(guest, room)).toEqual(calls);
    expect(hasBlocked).toHaveBeenCalledTimes(2);
    hasBlocked.mockClear();
    // Before the memo a poll made 5 calls: authorize, safetyMembers, 2 hasBlocked, snapshotIfChanged.
    expect(await countedPoll(guest, room)).toEqual(calls);
    expect(hasBlocked).toHaveBeenCalledTimes(0);
  });

  it("refuses the very next poll in every shared room after a block, linked or not, for 2 calls and no room", async () => {
    const { host, guest, room } = await relayPair(), other = await secondRoom(host, guest), outsider = await relayPair();
    // The blocker no longer holds a link to the second room; the guest still does.
    await runInDurableObject(env.PLAYERS.getByName(host.player_id), (_, ctx) => { ctx.storage.sql.exec("DELETE FROM rooms WHERE room_id=?", other.room_id); });
    const shared: [Account, RoomSnapshotV2][] = [[host, room], [guest, room], [guest, other]];
    expect(await everyone([...shared, [outsider.guest, outsider.room]])).toEqual(["200 ok", "200 ok", "200 ok", "200 ok"]);
    const rotations = vi.spyOn(Player.prototype, "rotateSafetyToken"), lists = vi.spyOn(Player.prototype, "listRooms");
    const names = Object.getOwnPropertyNames(RoomV2.prototype).filter(name => name !== "constructor");
    const rooms = names.map(name => vi.spyOn(RoomV2.prototype as unknown as Record<string, () => unknown>, name));
    const roomMethods = () => names.filter((_, index) => rooms[index].mock.calls.length > 0);
    // The block itself, as the route calls it after reading the room's members: 2 Player calls and no room call.
    expect(await env.SAFETY_PROFILES.getByName(host.player_id).setBlock(host.player_id, await digest(host.device_token), guest.player_id, true)).toMatchObject({ ok: true });
    expect({ rotations: rotations.mock.calls.length, listRooms: lists.mock.calls.length, roomMethods: roomMethods() }).toEqual({ rotations: 2, listRooms: 0, roomMethods: [] });
    expect(await everyone(shared)).toEqual(["403 player_blocked", "403 player_blocked", "403 player_blocked"]);
    expect(await code(await poll(outsider.guest, outsider.room))).toBe("200 ok");
    expect(await code(await call(`/v1/safety/blocks/${guest.player_id}`, "DELETE", host))).toBe("200 ok");
    expect(await everyone(shared)).toEqual(["200 ok", "200 ok", "200 ok"]);
  });

  it("answers a block even when a room the pair shares is broken", async () => {
    const { host, guest, room } = await relayPair(), other = await secondRoom(host, guest);
    expect(await everyone([[guest, room], [guest, other]])).toEqual(["200 ok", "200 ok"]);
    await runInDurableObject(env.ROOMS_V2.getByName(other.room_id), (_, ctx) => { ctx.storage.sql.exec("DROP TABLE room"); });
    expect(await code(await block(host, room))).toBe("200 ok");
    expect(await code(await poll(guest, room))).toBe("403 player_blocked");
  });

  it("never remembers a blocked pair; an operator block and a restored block clear it too", async () => {
    const { host, guest, room } = await relayPair();
    expect(await code(await poll(guest, room))).toBe("200 ok");
    expect(await env.SAFETY_PROFILES.getByName(host.player_id).operatorBlock(host.player_id, guest.player_id)).toMatchObject({ ok: true });
    const hasBlocked = vi.spyOn(SafetyProfile.prototype, "hasBlocked");
    for (let i = 0; i < 3; i++) expect(await code(await poll(guest, room))).toBe("403 player_blocked");
    expect(hasBlocked).toHaveBeenCalledTimes(6);

    const second = await relayPair(), profile = env.SAFETY_PROFILES.getByName(second.guest.player_id);
    expect((await block(second.guest, second.room)).status).toBe(200);
    const archive = await profile.exportSnapshot(second.guest.player_id);
    await runInDurableObject(profile, (_, ctx) => { ctx.storage.sql.exec("DELETE FROM safety_profile"); });
    for (const who of [second.host, second.guest]) expect(await code(await poll(who, second.room))).toBe("200 ok");
    expect(await profile.restoreSnapshot(second.guest.player_id, archive)).toMatchObject({ ok: true });
    for (const who of [second.host, second.guest]) expect(await code(await poll(who, second.room))).toBe("403 player_blocked");
  });

  it("asks again after a Player restarts, since its new token is one no room has seen", async () => {
    const { guest, room } = await relayPair();
    expect(await code(await poll(guest, room))).toBe("200 ok");
    await evictDurableObject(env.PLAYERS.getByName(guest.player_id));
    const hasBlocked = vi.spyOn(SafetyProfile.prototype, "hasBlocked");
    expect(await code(await poll(guest, room))).toBe("200 ok");
    expect(hasBlocked).toHaveBeenCalledTimes(2);
  });

  it("does not let a check that began before a block admit the new token", async () => {
    const memo = new UnblockedPairMemo();
    let finish!: (blocked: boolean) => void;
    const running = memo.blocked("a", "old", "a", "b", () => new Promise(resolve => { finish = resolve; }));
    // The block lands and the next request, with the new token, is refused while the old check is still out.
    expect(await memo.blocked("a", "new", "a", "b", async () => true)).toBe(true);
    finish(false);
    expect(await running).toBe(false);
    const check = vi.fn(async () => true);
    expect(await memo.blocked("a", "new", "a", "b", check)).toBe(true);
    expect(check).toHaveBeenCalledTimes(1);
  });

  it("forgets after the backstop expiry even without a new token", async () => {
    const memo = new UnblockedPairMemo(), check = vi.fn(async () => false), now = Date.now();
    expect(await memo.blocked("a", "t", "a", "b", check)).toBe(false);
    expect(await memo.blocked("a", "t", "a", "b", check)).toBe(false);
    expect(check).toHaveBeenCalledTimes(1);
    vi.spyOn(Date, "now").mockReturnValue(now + 10 * 60_000 + 1);
    expect(await memo.blocked("a", "t", "a", "b", check)).toBe(false);
    expect(check).toHaveBeenCalledTimes(2);
  });
});
