import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import type { HistoryView } from "../src/v2/history-room";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { CHAINS, play, playA } from "./history-chains";
import { HISTORY, ON, account, call, relayPair } from "./history-http";

// A waiting phone polls its room every few seconds. With X-AfterYou-Known-Room
// naming the revision and branch it holds, an unchanged room answers small.
// Every other request keeps today's full snapshot bytes.

afterEach(async () => { await reset(); });
const KNOWN = "X-AfterYou-Known-Room";
const known = (room: { revision: number; branch: number }) => ({ [KNOWN]: `${room.revision}.${room.branch}` });
const code = async (response: Response) => `${response.status} ${response.status === 200 ? "ok" : (await response.json<{ error: { code: string } }>()).error.code}`;
const players = (host: { player_id: string }, guest: { player_id: string }) => ({ host: host.player_id, guest: guest.player_id });

describe("conditional room poll", () => {
  it("answers unchanged only for the member's exact revision and branch", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`;
    for (const who of [host, guest]) {
      const small = await call(path, "GET", who, undefined, {}, known(room));
      expect(small.status).toBe(200);
      expect(await small.json()).toEqual({ schema_version: 1, unchanged: true, revision: room.revision, branch: room.branch, updated_at: room.updated_at });
    }
    const moved = await playA(env.ROOMS_V2.getByName(room.room_id), room, CHAINS[0].stages[0], players(host, guest));
    const stale = await call(path, "GET", guest, undefined, {}, known(room));
    const full = await stale.json<RoomSnapshotV2>();
    expect(full.revision).toBe(moved.revision);
    expect(full.recording_a).not.toBeNull();
    expect(await (await call(path, "GET", guest, undefined, {}, known(moved))).json()).toEqual({ schema_version: 1, unchanged: true, revision: moved.revision, branch: moved.branch, updated_at: moved.updated_at });
  });

  it("keeps today's exact bytes and headers with no header, a stale one or a malformed one", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`;
    const direct = await env.ROOMS_V2.getByName(room.room_id).snapshot(guest.player_id);
    if (!direct.ok) throw new Error(direct.code);
    const plain = await call(path, "GET", guest);
    const expected = await plain.text();
    expect(expected).toBe(JSON.stringify(direct.value));
    for (const header of [`${room.revision + 1}.${room.branch}`, `${room.revision}.${room.branch + 1}`, "", "abc", "1", "1.2.3", "-1.0", "01.0", "1.00", "1.0.", "1234567890123456.0", "1.123"]) {
      const answer = await call(path, "GET", guest, undefined, {}, { [KNOWN]: header });
      expect(answer.status).toBe(200);
      expect(await answer.text()).toBe(expected);
      expect([...answer.headers.entries()]).toEqual([...plain.headers.entries()]);
    }
    // The host's full view still carries its invite code.
    expect((await (await call(path, "GET", host, undefined, {}, { [KNOWN]: "999.0" })).json<RoomSnapshotV2>()).invite_code).toMatch(/^[A-F0-9]{20}$/);
  });

  it("gives an outsider, a removed room and a finished room their usual answers", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`, stranger = await account();
    expect(await code(await call(path, "GET", stranger, undefined, {}, known(room)))).toBe(await code(await call(path, "GET", stranger)));
    const finished = await play(env.ROOMS_V2.getByName(room.room_id), room, CHAINS[0], 0, undefined, players(host, guest));
    expect(await (await call(path, "GET", host, undefined, {}, known(finished))).json()).toMatchObject({ unchanged: true, revision: finished.revision });
    const closed = await relayPair(), closedPath = `/v2/rooms/${closed.room.room_id}`;
    expect((await call(closedPath, "DELETE", closed.host, undefined, {}, { "X-AfterYou-Close-If": "in-play" })).status).toBe(200);
    expect(await code(await call(closedPath, "GET", closed.guest, undefined, {}, known(closed.room)))).toBe(await code(await call(closedPath, "GET", closed.guest)));
  });

  it("still notes the member's history support on an unchanged poll", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`;
    const finished = await play(env.ROOMS_V2.getByName(room.room_id), room, CHAINS[0], 0, undefined, players(host, guest));
    // The guest's latest room request says nothing about keeping attempts, so nothing may leave.
    expect(await (await call(path, "GET", guest, undefined, ON, known(finished))).json()).toMatchObject({ unchanged: true });
    const view = await (await call(path + "/history", "GET", host, undefined, ON, HISTORY)).json<HistoryView>();
    expect(await code(await call(path + "/history/0/ack", "POST", host, { schema_version: 1, link: view.head }, ON, HISTORY))).toBe("200 ok");
    expect((await (await call(path + "/history", "GET", host, undefined, ON, HISTORY)).json<HistoryView>()).attempts[0].state).toBe("held");
    // The same unchanged poll with the history header now counts as support.
    expect(await (await call(path, "GET", guest, undefined, ON, { ...HISTORY, ...known(finished) })).json()).toMatchObject({ unchanged: true });
    expect(await code(await call(path + "/history/0/ack", "POST", guest, { schema_version: 1, link: view.head }, ON, HISTORY))).toBe("200 ok");
    expect((await (await call(path + "/history", "GET", host, undefined, ON, HISTORY)).json<HistoryView>()).attempts[0].state).toBe("offloaded");
  });
});
