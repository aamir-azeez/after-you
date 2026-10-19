import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Player } from "../src/player";
import { CHAINS, playA } from "./history-chains";
import { account, call, relayPair } from "./history-http";

// GET /redo is a read. auth() checks the device once; the room still checks membership and
// blocks, so who may see a redo state is unchanged, and the read no longer asks the Player twice.

afterEach(async () => { vi.restoreAllMocks(); await reset(); });
const code = async (response: Response) => `${response.status} ${response.status === 200 ? "ok" : (await response.json<{ error: { code: string } }>()).error.code}`;

describe("redo read", () => {
  it("checks the device once and refuses a stranger, a blocked pair and a replaced device", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}/redo`;
    await playA(env.ROOMS_V2.getByName(room.room_id), room, CHAINS[0].stages[0], { host: host.player_id, guest: guest.player_id });
    // Every device check (authorize, authorizeRoom, authorizeNamed) runs through the one private check.
    const authorize = vi.spyOn(Player.prototype as unknown as { authorized: (deviceHash: string) => unknown }, "authorized");
    expect(await code(await call(path, "GET", guest))).toBe("200 ok");
    // Was 2: auth() and the room's own re-check.
    expect(authorize).toHaveBeenCalledTimes(1);
    expect(await code(await call(path, "GET", await account()))).toBe("404 room_not_found");
    expect(await code(await call(path, "GET", { ...guest, device_token: "x".repeat(43) }))).toBe("401 invalid_auth");
    expect((await call("/v1/safety/block", "POST", host, { schema_version: 1, room_family: "relay", room_id: room.room_id })).status).toBe(200);
    for (const who of [host, guest]) expect(await code(await call(path, "GET", who))).toBe("403 player_blocked");
  });
});
