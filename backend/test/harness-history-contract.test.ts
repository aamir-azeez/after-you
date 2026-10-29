import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import type { HistoryView } from "../src/v2/history-room";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { CHAINS, play } from "./history-chains";
import { HISTORY, call, relayPair } from "./history-http";

// game/tests/online_harness/fake_server.gd answers the room history routes for
// the two-phone harness. Every answer it gives is pinned here on the real Worker.

afterEach(async () => { await reset(); });
const code = async (response: Response) => `${response.status} ${response.status === 200 ? "ok" : (await response.json<{ error: { code: string } }>()).error.code}`;

describe("the harness server's room history contract", () => {
  it("lists, serves, confirms, lets go, asks for and takes back a finished room's attempt", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`, players = { host: host.player_id, guest: guest.player_id };
    await play(env.ROOMS_V2.getByName(room.room_id), room, CHAINS[0], 0, undefined, players);
    const capabilities = await (await call("/v2/capabilities", "GET", host, undefined, {}, HISTORY)).json();
    expect(capabilities).toMatchObject({ history_version: 1, history_offload_enabled: true });
    const view = await (await call(path + "/history", "GET", host, undefined, {}, HISTORY)).json<HistoryView>();
    expect(view.attempts.map(a => [a.position, a.state, a.pair_ids])).toEqual([[0, "held", ["p0-0", "p0-1"]]]);
    expect(await code(await call(path + "/history/1", "GET", host, undefined, {}, HISTORY))).toBe("404 history_not_found");
    expect(await code(await call(path + "/history/32", "GET", host, undefined, {}, HISTORY))).toBe("400 invalid_field");
    expect(await code(await call(path + "/history/0/ack", "POST", host, { schema_version: 1, link: "0".repeat(64) }, {}, HISTORY))).toBe("409 history_mismatch");
    const download = await call(path + "/history/0", "GET", guest, undefined, {}, HISTORY);
    expect(download.headers.get("content-type")).toBe("application/octet-stream");
    const bytes = new Uint8Array(await download.arrayBuffer()); expect(bytes[0]).toBe(1);
    for (const who of [host, guest]) expect(await code(await call(path + "/history/0/ack", "POST", who, { schema_version: 1, link: view.head }, {}, HISTORY))).toBe("200 ok");
    expect(await code(await call(path, "GET", guest, undefined, {}, { ...HISTORY, "X-AfterYou-Finished-Room": "2" }))).toBe("410 replay_transferred");
    expect(await code(await call(path + "/pairs/p0-0", "GET", guest, undefined, {}, HISTORY))).toBe("410 replay_transferred");
    expect(await code(await call(path + "/replay-transfer", "GET", host, undefined, {}, HISTORY))).toBe("409 history_offload_active");
    expect(await code(await call(path + "/history/0", "GET", guest, undefined, {}, HISTORY))).toBe("410 history_offloaded");
    const listed = await (await call("/v2/rooms", "GET", host, undefined, {}, HISTORY)).json<{ rooms: Record<string, unknown>[] }>();
    expect(listed.rooms).toMatchObject([{ room_id: room.room_id, active_role: "complete", replay_transfer_version: 1 }]);
    const wanted = await (await call(path + "/history/0/want", "POST", guest, { schema_version: 1 }, {}, HISTORY)).json<HistoryView>();
    expect(wanted.attempts[0]).toMatchObject({ state: "offloaded", wanted_by_partner: false });
    expect((await (await call(path + "/history", "GET", host, undefined, {}, HISTORY)).json<HistoryView>()).attempts[0].wanted_by_partner).toBe(true);
    expect(await code(await call(path + "/history/0", "POST", host, bytes.slice(0, -3), {}, HISTORY))).toBe("422 history_mismatch");
    const back = await (await call(path + "/history/0", "POST", host, bytes, {}, HISTORY)).json<HistoryView>();
    expect(back.attempts[0]).toMatchObject({ state: "held", acked_by_you: true, wanted_by_partner: false });
    const restored = await (await call(path, "GET", host, undefined, {}, HISTORY)).json<RoomSnapshotV2>();
    expect(restored.active_role).toBe("complete");
    const forked = await call(path + "/fork", "POST", host, { base_revision: restored.revision, branch: restored.branch, stage_index: 0, idempotency_key: crypto.randomUUID() }, {}, HISTORY);
    expect(forked.status).toBe(200);
    expect(await code(await call(path + "/history/0/ack", "POST", guest, { schema_version: 1, link: view.head }, {}, HISTORY))).toBe("200 ok");
    expect((await (await call(path + "/history", "GET", host, undefined, {}, HISTORY)).json<HistoryView>()).attempts[0].state).toBe("offloaded");
    // In play now: the offloaded attempt's parts answer history_offloaded, the room itself plays on.
    expect(await code(await call(path + "/pairs/p0-1", "GET", guest, undefined, {}, HISTORY))).toBe("410 history_offloaded");
    expect(await code(await call(path, "GET", guest, undefined, {}, HISTORY))).toBe("200 ok");
  });

  it("nothing leaves while a member's latest room request came from an older build", async () => {
    const { host, guest, room } = await relayPair(), path = `/v2/rooms/${room.room_id}`;
    await play(env.ROOMS_V2.getByName(room.room_id), room, CHAINS[0], 0, undefined, { host: host.player_id, guest: guest.player_id });
    await call(path, "GET", guest, undefined);
    const view = await (await call(path + "/history", "GET", host, undefined, {}, HISTORY)).json<HistoryView>();
    expect(await code(await call(path + "/history/0/ack", "POST", host, { schema_version: 1, link: view.head }, {}, HISTORY))).toBe("200 ok");
    // The older build never calls history; the room keeps its rows and v1 still works.
    expect((await (await call(path + "/history", "GET", host, undefined, {}, HISTORY)).json<HistoryView>()).attempts[0].state).toBe("held");
    expect(await code(await call(path + "/replay-transfer", "GET", guest, undefined))).toBe("200 ok");
  });
});
