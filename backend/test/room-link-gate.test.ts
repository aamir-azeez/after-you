import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { randomToken } from "../src/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { account, call, relayPair, type Account } from "./history-http";
import { countingEnv, meterAllRows } from "./meter";

// A room request names a room id. A player who holds no link to that id (and no Story link,
// whose chapter rooms are not linked one by one) is answered 404 room_not_found by the Player
// check auth() already makes, before any room object is opened.

afterEach(async () => { await reset(); });
const answer = async (response: Response) => `${response.status} ${response.status === 200 ? "ok" : (await response.json<{ error: { code: string } }>()).error.code}`;
let address = 0;
async function counted(path: string, method: string, who: Account, body?: unknown, token = who.device_token): Promise<{ answer: string; calls: string[] }> {
  const { env: counting, calls } = countingEnv(env); Object.assign(counting, { V2_ROOMS_ENABLED: "true", PRESENCE_ENABLED: "true" });
  const response = await worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.7." + (++address % 250),
    "X-Player-Id": who.player_id, Authorization: "Bearer " + token }, body: body === undefined ? undefined : JSON.stringify(body) }), counting);
  return { answer: await answer(response), calls };
}
const ROOM_ROUTES = (id: string): [string, string, unknown?][] => [
  [`/v2/rooms/${id}`, "GET"], [`/v2/rooms/${id}/redo`, "GET"], [`/v2/rooms/${id}/presence`, "GET"], [`/v2/rooms/${id}/collection`, "GET"],
  [`/v2/rooms/${id}/turns`, "POST", {}], [`/v2/rooms/${id}`, "DELETE"], [`/v2/rooms/${id}/history`, "GET"], [`/v2/rooms/${id}/replay-transfer`, "GET"],
  [`/v1/rooms/${id}`, "GET"], [`/v1/rooms/${id}/redo`, "GET"], [`/v1/rooms/${id}/presence`, "GET"], [`/v1/rooms/${id}/turns`, "POST", {}]
];

describe("room link gate", () => {
  it("refuses a room id the player has no link to without opening any room or storing anything", async () => {
    const who = await account(), id = randomToken(16);
    for (const [path, method, body] of ROOM_ROUTES(id)) {
      const metered = await meterAllRows(() => counted(path, method, who, body));
      // On main a room read here opened the room (2 to 4 calls) and stored an empty room: 30 rows for Relay, 17 for legacy.
      expect({ path, method, ...metered.value, written: metered.rows.written }).toEqual({ path, method, answer: "404 room_not_found", calls: ["PLAYERS.authorizeRoom"], written: 0 });
    }
  });

  it("keeps leave a quiet success for an unlinked room, still without opening it", async () => {
    const who = await account();
    for (const version of [1, 2]) expect(await counted(`/v${version}/rooms/${randomToken(16)}/leave`, "POST", who, { schema_version: 1 })).toEqual({ answer: "200 ok", calls: ["PLAYERS.authorize", "PLAYERS.listRooms"] });
  });

  it("answers a stranger to a real room the same code as before, and keeps 401 and 429 first", async () => {
    const { room } = await relayPair(), stranger = await account(), id = room.room_id;
    expect((await counted(`/v2/rooms/${id}`, "GET", stranger)).answer).toBe("404 room_not_found");
    expect((await counted(`/v2/rooms/${id}`, "GET", stranger, undefined, randomToken())).answer).toBe("401 invalid_auth");
    expect((await counted(`/v2/rooms/${randomToken(16)}`, "GET", stranger, undefined, randomToken())).answer).toBe("401 invalid_auth");
  });

  it("lets every create and join path open its room", async () => {
    const host = await account(), guest = await account();
    for (const version of [1, 2] as const) {
      const created = await call(`/v${version}/rooms`, "POST", host, version === 1 ? { idempotency_key: crypto.randomUUID() } : { idempotency_key: crypto.randomUUID(), ...(await relayKey()) });
      expect(created.status).toBe(200);
      const room = await created.json<RoomSnapshotV2>();
      expect(await answer(await call(`/v${version}/rooms/${room.room_id}`, "GET", host))).toBe("200 ok");
      expect(await answer(await call(`/v${version}/rooms/${room.room_id}`, "GET", guest))).toBe("404 room_not_found");
      expect(await (await call("/v1/invitations/resolve", "POST", guest, { invite_code: room.invite_code })).json()).toMatchObject({ api_version: version });
      expect(await answer(await call(`/v${version}/rooms/join`, "POST", guest, { invite_code: room.invite_code }))).toBe("200 ok");
      expect(await answer(await call(`/v${version}/rooms/${room.room_id}`, "GET", guest))).toBe("200 ok");
      expect(await answer(await call(`/v${version}/rooms/${room.room_id}/presence`, "GET", guest, undefined, { PRESENCE_ENABLED: "true" }))).toBe("200 ok");
    }
  });

  it("keeps a player with a Story link on today's path, where the room itself answers", async () => {
    const who = await account(), id = randomToken(16);
    await runInDurableObject(env.PLAYERS.getByName(who.player_id), async (_, ctx) => {
      ctx.storage.sql.exec("INSERT INTO rooms VALUES (?,?)", "s".repeat(22), JSON.stringify({ room_id: "s".repeat(22), invite_code: "", host: false, api_version: 3 }));
    });
    const reached = await counted(`/v2/rooms/${id}`, "GET", who);
    expect(reached.answer).toBe("404 room_not_found");
    expect(reached.calls).toContain("ROOMS_V2.interactionAllowed");
  });

  it("stores nothing for an unknown invite code, a resolve or a join", async () => {
    const who = await account(), code = "0123456789ABCDEF0123";
    const resolve = await meterAllRows(async () => answer(await call("/v1/invitations/resolve", "POST", who, { invite_code: code })));
    // 47 on main: an empty legacy room and an empty Relay room.
    expect({ answer: resolve.value, written: resolve.rows.written }).toEqual({ answer: "404 invite_not_found", written: 0 });
    for (const version of [1, 2]) {
      const join = await meterAllRows(async () => answer(await call(`/v${version}/rooms/join`, "POST", who, { invite_code: version + code.slice(1) })));
      // The player's link is added before the join and removed after it fails: 3 rows in the Player, none in any room
      // (20 for a legacy code and 33 for a Relay code on main, which stored an empty room).
      expect({ answer: join.value, written: join.rows.written }).toEqual({ answer: "404 invite_not_found", written: 3 });
    }
  });

  it("still deletes an identity whose room was reserved but never created", async () => {
    const who = await account(), id = randomToken(16);
    await runInDurableObject(env.PLAYERS.getByName(who.player_id), async (_, ctx) => {
      ctx.storage.sql.exec("INSERT INTO rooms VALUES (?,?)", id, JSON.stringify({ room_id: id, invite_code: "0123456789ABCDEF0123", host: true, api_version: 2 }));
    });
    expect(await answer(await call("/v1/identity", "DELETE", who))).toBe("200 ok");
    expect(await answer(await call("/v1/identity", "GET", who))).toBe("401 invalid_auth");
  });
});

async function relayKey() {
  const { DEFINITION_HASH, RELAY } = await import("../src/v2/protocol");
  return { level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH };
}
