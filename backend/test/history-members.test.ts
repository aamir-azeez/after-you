import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { runInDurableObject } from "./room-objects";
import { afterEach, describe, expect, it } from "vitest";
import { initializeHistory } from "../src/v2/storage-schema";
import { CHAINS, play } from "./history-chains";
import { HISTORY, call, relayPair } from "./history-http";

const SOURCE = "f".repeat(40);
afterEach(async () => { await reset(); });
const roomOf = (id: string) => env.ROOMS_V2.getByName(id);
async function storage(id: string) {
  return runInDurableObject(roomOf(id), (_, ctx) => ({
    version: ctx.storage.sql.exec<{ v: number }>("SELECT schema_version AS v FROM metadata").one().v,
    tables: ctx.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE name LIKE 'history_%' ORDER BY name").toArray().map(row => row.name),
    members: ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name='history_members'").toArray().length
      ? Object.fromEntries(ctx.storage.sql.exec<{ player_id: string; data: string }>("SELECT player_id,data FROM history_members").toArray().map(row => [row.player_id, JSON.parse(row.data).version])) : null
  }));
}

describe("history support negotiation", () => {
  it("advertises history only to clients that ask", async () => {
    const { host } = await relayPair();
    const plain = await (await call("/v2/capabilities", "GET", host)).text();
    expect(plain).not.toContain("history");
    expect(await (await call("/v2/capabilities", "GET", host, undefined, {}, HISTORY)).json()).toMatchObject({ history_version: 1, history_offload_enabled: true });
  });

  it("records each member's latest room request, but never from the room list", async () => {
    const { host, guest, room } = await relayPair(), path = "/v2/rooms/" + room.room_id;
    const plain = await (await call(path, "GET", host)).text();
    expect(await (await call(path, "GET", host, undefined, {}, HISTORY)).text()).toBe(plain);
    expect(await storage(room.room_id)).toMatchObject({ version: 9, tables: ["history_attempts", "history_members"], members: { [host.player_id]: 1 } });
    await call("/v2/rooms", "GET", guest, undefined, {}, HISTORY);
    expect((await storage(room.room_id)).members).toEqual({ [host.player_id]: 1 });
    await call(path, "GET", guest, undefined);
    expect((await storage(room.room_id)).members).toEqual({ [host.player_id]: 1, [guest.player_id]: 0 });
    await call(path, "GET", guest, undefined, {}, HISTORY);
    await call("/v2/rooms", "GET", host, undefined);
    expect((await storage(room.room_id)).members).toEqual({ [host.player_id]: 1, [guest.player_id]: 1 });
    // A member who goes back to an older build says so on their next room request.
    await call(path, "GET", host, undefined);
    expect((await storage(room.room_id)).members).toEqual({ [host.player_id]: 0, [guest.player_id]: 1 });
    expect(await (await call(path, "GET", host, undefined)).text()).toBe(plain);
  });

  it("keeps replay transfer and operator snapshots working in a room that recorded support", async () => {
    const { host, guest, room } = await relayPair(), path = "/v2/rooms/" + room.room_id, stub = roomOf(room.room_id);
    await call(path, "GET", host, undefined, {}, HISTORY);
    const state = await play(stub, room, CHAINS[0], 0, undefined, { host: host.player_id, guest: guest.player_id });
    const live = await stub.exportSnapshot(SOURCE); expect(live.ok).toBe(true);
    const copy = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await copy.restoreSnapshot(live.ok ? live.value : "", room.room_id)).toMatchObject({ ok: true });
    expect(await copy.snapshot(host.player_id)).toEqual({ ok: true, value: state });
    expect(await storage(room.room_id)).toMatchObject({ version: 9 });
    const offered = await stub.replayTransfer(host.player_id); if (!offered.ok) throw new Error(offered.code);
    const ack = { schema_version: 1, epoch: offered.value.manifest.epoch, archive_hash: offered.value.manifest.archive_hash };
    expect(await stub.acknowledgeReplayTransfer(host.player_id, ack)).toMatchObject({ ok: true });
    expect(await stub.acknowledgeReplayTransfer(guest.player_id, ack)).toMatchObject({ ok: true, value: { transferred: true } });
    const compacted = await stub.exportSnapshot(SOURCE); expect(compacted.ok).toBe(true);
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await target.restoreSnapshot(compacted.ok ? compacted.value : "", room.room_id)).toMatchObject({ ok: true });
    expect(await stub.restoreReplayTransfer(guest.player_id, { ...ack, archive: offered.value.archive })).toMatchObject({ ok: true });
    expect(await stub.snapshot(host.player_id)).toEqual({ ok: true, value: state });
    // Erasing the room clears its history tables too, and the empty room still exports.
    expect(await stub.eraseForPlayer(host.player_id)).toMatchObject({ ok: true });
    expect((await storage(room.room_id)).members).toEqual({});
    expect(await stub.exportSnapshot(SOURCE)).toMatchObject({ ok: true });
  });

  it("never adds history tables to Story rooms", async () => {
    const stub = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    await runInDurableObject(stub, (_, ctx) => {
      for (const version of [6, 7]) {
        ctx.storage.sql.exec("UPDATE metadata SET schema_version=?", version);
        expect(initializeHistory(ctx.storage)).toBe(false);
        expect(ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name LIKE 'history_%'").toArray()).toEqual([]);
      }
    });
  });
});
