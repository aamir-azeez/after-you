import { reset } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it } from "vitest";
import type { HistoryView } from "../src/v2/history-room";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { CHAINS, play } from "./history-chains";
import { HISTORY, call, relayPair, type Account } from "./history-http";

afterEach(async () => { await reset(); });
/** What 0.6.1 and later send on a room read (rooms_api.gd), and what 0.6.3 adds. */
const CLIENT_063 = { ...HISTORY, "X-AfterYou-Client": "0.6.3 play", "X-AfterYou-Finished-Room": "2" };
const answer = async (response: Response) => `${response.status} ${response.status === 200 ? "ok" : (await response.json<{ error: { code: string } }>()).error.code}`;
const roomIds = async (response: Response) => (await response.json<{ rooms: { room_id: string; status?: string }[] }>()).rooms;

/** A finished relay room whose only attempt both members' phones confirmed, so the server let it go. */
async function offloaded(): Promise<{ host: Account; guest: Account; room: RoomSnapshotV2 }> {
  const { host, guest, room } = await relayPair(), stub = env.ROOMS_V2.getByName(room.room_id);
  await play(stub, room, CHAINS[0], 0, undefined, { host: host.player_id, guest: guest.player_id });
  const path = `/v2/rooms/${room.room_id}/history`;
  for (const who of [host, guest]) expect((await call(path, "GET", who, undefined, {}, HISTORY)).status).toBe(200);
  const link = (await (await call(path, "GET", host, undefined, {}, HISTORY)).json<HistoryView>()).attempts[0].link;
  for (const who of [host, guest]) expect((await call(`${path}/0/ack`, "POST", who, { schema_version: 1, link }, {}, HISTORY)).status).toBe(200);
  expect((await (await call(path, "GET", guest, undefined, {}, HISTORY)).json<HistoryView>()).attempts[0].state).toBe("offloaded");
  return { host, guest, room };
}

describe("an offloaded room", () => {
  it("answers 0.6.1+ reads 410 replay_transferred and only header-less reads the 0.6.0 unblock, and stays listed", async () => {
    const { host, guest, room } = await offloaded();
    const read = (who: Account, headers: Record<string, string>) => call(`/v2/rooms/${room.room_id}`, "GET", who, undefined, {}, headers);
    for (const who of [host, guest]) {
      // Every client that can ACK (0.6.3) sends X-AfterYou-Finished-Room: 2 on this read, so it gets the finished-room answer.
      expect(await answer(await read(who, CLIENT_063))).toBe("410 replay_transferred");
      expect(await answer(await read(who, { "X-AfterYou-Finished-Room": "2" }))).toBe("410 replay_transferred");
      // 0.6.0 and older send no header and get the Story boundary answer they move past, exactly as for a v1-transferred room.
      expect(await answer(await read(who, {}))).toBe("409 campaign_client_required");
      // The inbox (plain and with closed rooms) and the lobby list keep the room as finished.
      for (const headers of [CLIENT_063, { ...CLIENT_063, "X-AfterYou-Room-Inbox": "2" }]) {
        const inbox = await call("/v1/room-inbox", "GET", who, undefined, {}, headers);
        expect(inbox.status).toBe(200);
        expect((await roomIds(inbox)).find(entry => entry.room_id === room.room_id)?.status).toBe("completed");
      }
      const lobby = await call("/v2/rooms", "GET", who, undefined, {}, CLIENT_063);
      expect(lobby.status).toBe(200);
      expect((await roomIds(lobby)).map(entry => entry.room_id)).toContain(room.room_id);
    }
  });
});
