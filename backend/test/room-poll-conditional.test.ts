import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import type { HistoryView } from "../src/v2/history-room";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { CHAINS, play, playA } from "./history-chains";
import { HISTORY, ON, account, call, relayPair, type Account } from "./history-http";
import { countingEnv, meterRows } from "./meter";
import worker from "../src/index";
import type { RedoState } from "../src/redo-control";

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

// A client that sends X-AfterYou-Poll-Redo with its known room reads the redo state from
// the poll itself, so a waiting phone no longer makes a second request for it.
describe("redo state in the conditional poll", () => {
  const POLL_REDO = { "X-AfterYou-Poll-Redo": "1" };
  /** The opted-in reply is the old reply with the exact GET /redo body as its last key. */
  async function expectFolded(path: string, who: Account, held: { revision: number; branch: number }) {
    const plain = await call(path, "GET", who, undefined, {}, known(held));
    const opted = await call(path, "GET", who, undefined, {}, { ...known(held), ...POLL_REDO });
    const redo = await call(path + "/redo", "GET", who);
    expect([plain.status, opted.status, redo.status]).toEqual([200, 200, 200]);
    const plainText = await plain.text();
    expect(await opted.text()).toBe(plainText.slice(0, -1) + ',"redo":' + await redo.text() + "}");
    expect([...opted.headers.entries()]).toEqual([...plain.headers.entries()]);
    return JSON.parse(plainText) as { unchanged?: true };
  }

  it("carries the same redo state as GET /redo through every redo step, unchanged or not", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`;
    for (const who of [host, guest]) expect(await expectFolded(path, who, room)).toMatchObject({ unchanged: true });
    const moved = await playA(env.ROOMS_V2.getByName(room.room_id), room, CHAINS[0].stages[0], players(host, guest));
    // The guest still holds the old revision, so it gets the full view with redo.
    expect((await expectFolded(path, guest, room)).unchanged).toBeUndefined();
    for (const who of [host, guest]) expect(await expectFolded(path, who, moved)).toMatchObject({ unchanged: true });
    const offered = await (await call(path + "/redo", "GET", guest)).json<RedoState>();
    expect(offered.source).not.toBeNull();
    expect((await call(path + "/redo", "POST", guest, { action: "request", source: offered.source })).status).toBe(200);
    for (const who of [host, guest]) await expectFolded(path, who, moved);
    expect((await (await call(path, "GET", host, undefined, {}, { ...known(moved), ...POLL_REDO })).json<{ redo: RedoState }>()).redo.request?.status).toBe("pending");
    expect((await call(path + "/redo", "POST", host, { action: "decline", source: offered.source })).status).toBe(200);
    for (const who of [host, guest]) await expectFolded(path, who, moved);
  });

  it("changes nothing without both headers, and refuses as before", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`, stranger = await account();
    const plain = await call(path, "GET", guest), alone = await call(path, "GET", guest, undefined, {}, POLL_REDO);
    expect(await alone.text()).toBe(await plain.text());
    expect(await code(await call(path, "GET", stranger, undefined, {}, { ...known(room), ...POLL_REDO }))).toBe(await code(await call(path, "GET", stranger)));
    expect((await call("/v1/safety/block", "POST", guest, { schema_version: 1, room_family: "relay", room_id: room.room_id })).status).toBe(200);
    for (const who of [host, guest]) expect(await code(await call(path, "GET", who, undefined, {}, { ...known(room), ...POLL_REDO }))).toBe("403 player_blocked");
    expect(await code(await call(path + "/redo", "GET", host))).toBe("403 player_blocked");
  });

  it("is offered on capabilities only to a client that sends the header", async () => {
    const who = await account();
    const plain = await (await call("/v2/capabilities", "GET", who)).text(), opted = await (await call("/v2/capabilities", "GET", who, undefined, {}, POLL_REDO)).json<Record<string, unknown>>();
    expect(plain).not.toContain("poll_redo_version");
    expect(opted.poll_redo_version).toBe(1);
    const { poll_redo_version: _, ...rest } = opted; void _;
    expect(rest).toEqual(JSON.parse(plain));
  });

  it("replaces a poll and a redo read with one poll", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`;
    const moved = await playA(env.ROOMS_V2.getByName(room.room_id), room, CHAINS[0].stages[0], players(host, guest));
    const stub = env.ROOMS_V2.getByName(room.room_id);
    await counted(path, host, known(moved)); // warm
    const before = await meterRows({ room: stub }, async () => [await counted(path, host, known(moved)), await counted(path + "/redo", host)]);
    const after = await meterRows({ room: stub }, async () => [await counted(path, host, { ...known(moved), ...POLL_REDO })]);
    const total = (list: string[][]) => list.reduce((sum, calls) => sum + calls.length, 0);
    expect({ requests: before.value.length, routerRpcs: total(before.value), roomRows: before.rows.room.read })
      .toEqual({ requests: 2, routerRpcs: 10, roomRows: 23 });
    // GET /redo also makes 3 calls from inside the room (2 block checks, 1 authorize): 13 Durable Object requests before, 5 after.
    expect(before.value[1].at(-1)).toBe("ROOMS_V2.redo");
    expect({ requests: after.value.length, routerRpcs: total(after.value), roomRows: after.rows.room.read })
      .toEqual({ requests: 1, routerRpcs: 5, roomRows: 12 });
  });
});

let countedAddress = 0;
/** One Worker request; returns the Durable Object RPCs the Worker made for it. */
async function counted(path: string, who: Account, headers: Record<string, string> = {}): Promise<string[]> {
  const { env: counting, calls } = countingEnv(env); Object.assign(counting, { V2_ROOMS_ENABLED: "true" });
  const response = await worker.fetch(new Request("https://after-you.test" + path, { headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + (++countedAddress % 250),
    "X-Player-Id": who.player_id, Authorization: "Bearer " + who.device_token, ...headers } }), counting);
  expect(response.status).toBe(200); await response.arrayBuffer();
  return calls;
}
