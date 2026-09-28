import { env } from "cloudflare:workers";
import { evictDurableObject, reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome, type RoomSnapshot } from "../src/protocol";
import { RELAY_KEY } from "../src/v2/chapters";
import type { PortableSnapshot } from "../src/snapshot";
import type { RoomSnapshotV2 } from "../src/v2/room";

type Account = { player_id: string; device_token: string };
const commit = "8".repeat(40);
let address = 0;
function value<T>(result: Outcome<T>): T { if (!result.ok) throw new Error(result.code); return result.value; }
async function call(path: string, method: string, owner?: Account, body?: unknown): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true" });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.19.12." + ++address,
      ...(owner ? { "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body)
  }), configured);
}
async function account(): Promise<Account> {
  const response = await call("/v1/identity", "POST", undefined, {});
  expect(response.status).toBe(201); return response.json<Account>();
}
function archive(serialized: string): PortableSnapshot { return JSON.parse(serialized) as PortableSnapshot; }
function creations(serialized: string) { return archive(serialized).payload.tables.find(table => table.name === "creations")!.rows; }

afterEach(async () => { await reset(); });

describe("comfort creation intent retention", () => {
  it.each([undefined, 8] as const)("retries Relay %s after a lost reply and eviction, preserving the exact intent through both archives", async version => {
    const host = await account(), key = crypto.randomUUID();
    const body = { ...RELAY_KEY, idempotency_key: key, ...(version === undefined ? {} : { simulation_version: version }) };
    const made = await call("/v2/rooms", "POST", host, body);
    expect(made.status).toBe(200);
    // Deliberately discard the reply. Recover only from the same saved request
    // and durable server state, as a client with a lost Create response must.
    await made.text();
    const player = env.PLAYERS.getByName(host.player_id), links = await player.listRooms();
    expect(links).toHaveLength(1);
    const link = links[0], room = env.ROOMS_V2.getByName(link.room_id);
    expect(link).toMatchObject({ host: true, api_version: 2 });
    const before = value(await room.snapshot(host.player_id));
    expect(before.simulation_version ?? 2).toBe(version ?? 2);
    const playerArchive = value(await player.exportSnapshot(commit));
    const row = creations(playerArchive).find(row => row.request_key === key)!;
    const expectedIntent = { creation_schema: 1, link, chapter: RELAY_KEY,
      ...(version === undefined ? {} : { simulation_version: version }) };
    // Retained Relay2 keeps its existing raw-link shape; only explicit rules
    // require the versioned creation envelope.
    expect(row.data).toBe(JSON.stringify(version === undefined ? link : expectedIntent));
    expect(archive(playerArchive).payload.format_version).toBe(version === undefined ? 2 : 3);

    await evictDurableObject(player); await evictDurableObject(room);
    const retried = await call("/v2/rooms", "POST", host, body);
    expect(retried.status).toBe(200);
    expect(await retried.json<RoomSnapshotV2>()).toEqual(before);
    expect(archive(value(await player.exportSnapshot(commit))).payload.tables).toEqual(archive(playerArchive).payload.tables);
    const mismatched = await call("/v2/rooms", "POST", host,
      { ...RELAY_KEY, idempotency_key: key, ...(version === undefined ? { simulation_version: 8 } : {}) });
    expect(mismatched.status).toBe(409);
    expect(await mismatched.json()).toMatchObject({ error: { code: "idempotency_simulation_mismatch" } });
    expect(await player.listRooms()).toEqual(links);
    expect(value(await room.snapshot(host.player_id))).toEqual(before);
    expect(archive(value(await player.exportSnapshot(commit))).payload.tables).toEqual(archive(playerArchive).payload.tables);

    const roomArchive = value(await room.exportSnapshot(commit));
    const restoredPlayer = env.PLAYERS.get(env.PLAYERS.newUniqueId());
    const restoredRoom = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await restoredPlayer.restoreSnapshot(playerArchive, host.player_id)).toMatchObject({ ok: true });
    expect(await restoredRoom.restoreSnapshot(roomArchive, before.room_id)).toMatchObject({ ok: true });
    await evictDurableObject(restoredPlayer); await evictDurableObject(restoredRoom);
    expect(archive(value(await restoredPlayer.exportSnapshot(commit))).payload.tables).toEqual(archive(playerArchive).payload.tables);
    expect(archive(value(await restoredRoom.exportSnapshot(commit))).payload.tables).toEqual(archive(roomArchive).payload.tables);
    expect(value(await restoredPlayer.chapterCreation(key, RELAY_KEY, version))).toEqual(expectedIntent);
    // These are actual restored binding calls; public HTTP retry was exercised
    // above against the canonical named objects, not a fake restored router.
    const retained = value(await restoredPlayer.reserveChapterRoom(key,
      { ...link, room_id: "x".repeat(22), invite_code: "E".repeat(20) }, RELAY_KEY, version));
    expect(retained).toEqual(expectedIntent);
    expect(value(await restoredRoom.initialize(retained.link.room_id, host.player_id,
      retained.link.invite_code, retained.chapter, retained.simulation_version))).toEqual(before);
    expect(archive(value(await restoredPlayer.exportSnapshot(commit))).payload.tables).toEqual(archive(playerArchive).payload.tables);
    expect(archive(value(await restoredRoom.exportSnapshot(commit))).payload.tables).toEqual(archive(roomArchive).payload.tables);

    if (version === 8) {
      for (const unsupported of [6, 9]) {
        const invalid = archive(playerArchive);
        const intentRow = invalid.payload.tables.find(table => table.name === "creations")!.rows.find(row => row.request_key === key)!;
        intentRow.data = JSON.stringify({ ...expectedIntent, simulation_version: unsupported });
        invalid.checksum.value = await digest(canonicalJson(invalid.payload));
        const target = env.PLAYERS.get(env.PLAYERS.newUniqueId());
        expect(await target.restoreSnapshot(canonicalJson(invalid), host.player_id)).toMatchObject({ ok: false });
        expect(await target.listRooms()).toEqual([]);
      }
    }
  });

  it("refuses an old capability list for Relay8 without attaching the guest, while implicit Relay2 remains compatible", async () => {
    const host = await account(), guest = await account();
    const made = await call("/v2/rooms", "POST", host,
      { ...RELAY_KEY, idempotency_key: crypto.randomUUID(), simulation_version: 8 });
    expect(made.status).toBe(200); const waiting = await made.json<RoomSnapshotV2>();
    const target = env.ROOMS_V2.getByName(waiting.room_id);
    for (const versions of [undefined, [2, 4, 5, 6, 7]]) {
      const reply = await call("/v2/rooms/join", "POST", guest,
        { invite_code: waiting.invite_code, ...(versions ? { supported_simulation_versions: versions } : {}) });
      expect(reply.status).toBe(422);
      expect(await reply.json()).toMatchObject({ error: { code: "unsupported_simulation_version" } });
      expect(value(await target.snapshot(host.player_id))).toEqual(waiting);
      expect(await env.PLAYERS.getByName(guest.player_id).listRooms()).toEqual([]);
    }
    const joined = await call("/v2/rooms/join", "POST", guest,
      { invite_code: waiting.invite_code, supported_simulation_versions: [2, 4, 5, 6, 7, 8] });
    expect(joined.status).toBe(200);
    expect((await joined.json<RoomSnapshotV2>()).guest_id).toBe(guest.player_id);
    const oldMade = await call("/v2/rooms", "POST", host, { ...RELAY_KEY, idempotency_key: crypto.randomUUID() });
    expect(oldMade.status).toBe(200); const old = await oldMade.json<RoomSnapshotV2>();
    const oldJoined = await call("/v2/rooms/join", "POST", guest, { invite_code: old.invite_code });
    expect(oldJoined.status).toBe(200);
    expect((await oldJoined.json<RoomSnapshotV2>()).simulation_version ?? 2).toBe(2);
  });

  it.each([1, 6, 8] as const)("keeps v1 room rules %s pinned while retaining its existing raw Player-link archive", async version => {
    const host = await account(), key = crypto.randomUUID();
    const body = { idempotency_key: key, ...(version === 1 ? {} : { simulation_version: version }) };
    const made = await call("/v1/rooms", "POST", host, body);
    expect(made.status).toBe(200); const before = await made.json<RoomSnapshot>();
    expect(before.simulation_version ?? 1).toBe(version);
    const player = env.PLAYERS.getByName(host.player_id), room = env.ROOMS.getByName(before.room_id);
    const playerArchive = value(await player.exportSnapshot(commit));
    const links = await player.listRooms();
    expect(links).toHaveLength(1);
    expect(links[0]).toEqual({ room_id: before.room_id, invite_code: before.invite_code, host: true });
    expect(creations(playerArchive).find(row => row.request_key === key)!.data).toBe(JSON.stringify(links[0]));
    expect(archive(playerArchive).payload.format_version).toBe(1);
    await evictDurableObject(player); await evictDurableObject(room);
    const retry = await call("/v1/rooms", "POST", host, body);
    expect(retry.status).toBe(200); expect(await retry.json()).toEqual(before);
    for (const different of [1, 6, 8].filter(candidate => candidate !== version)) {
      const rejected = await call("/v1/rooms", "POST", host, { idempotency_key: key, simulation_version: different });
      expect(rejected.status).toBe(409);
      expect(await rejected.json()).toMatchObject({ error: { code: "idempotency_key_reused" } });
    }
    expect(archive(value(await player.exportSnapshot(commit))).payload.tables).toEqual(archive(playerArchive).payload.tables);
    expect(value(await room.snapshot(host.player_id))).toEqual(before);
    const roomArchive = value(await room.exportSnapshot(commit));
    const restoredPlayer = env.PLAYERS.get(env.PLAYERS.newUniqueId()), restoredRoom = env.ROOMS.get(env.ROOMS.newUniqueId());
    expect(await restoredPlayer.restoreSnapshot(playerArchive, host.player_id)).toMatchObject({ ok: true });
    expect(await restoredRoom.restoreSnapshot(roomArchive, before.room_id)).toMatchObject({ ok: true });
    await evictDurableObject(restoredPlayer); await evictDurableObject(restoredRoom);
    const retained = value(await restoredPlayer.reserveRoom(key,
      { room_id: "y".repeat(22), invite_code: "D".repeat(20), host: true }));
    expect(retained).toEqual(links[0]);
    expect(value(await restoredRoom.initialize(retained.room_id, host.player_id, retained.invite_code, version))).toEqual(before);
    expect(archive(value(await restoredPlayer.exportSnapshot(commit))).payload.tables).toEqual(archive(playerArchive).payload.tables);
    expect(archive(value(await restoredRoom.exportSnapshot(commit))).payload.tables).toEqual(archive(roomArchive).payload.tables);
  });

  it("requires client8 for a legacy8 room and keeps new clients compatible with retained1/6", async () => {
    const host = await account(), guest = await account();
    for (const version of [1, 6, 8]) {
      const made = await call("/v1/rooms", "POST", host,
        { idempotency_key: crypto.randomUUID(), ...(version === 1 ? {} : { simulation_version: version }) });
      expect(made.status).toBe(200); const waiting = await made.json<RoomSnapshot>();
      if (version === 8) {
        for (const old of [1, 6]) {
          const refused = await call("/v1/rooms/join", "POST", guest,
            { invite_code: waiting.invite_code, ...(old === 1 ? {} : { simulation_version: old }) });
          expect(refused.status).toBe(422);
          expect(await refused.json()).toMatchObject({ error: { code: "unsupported_simulation_version" } });
          expect(value(await env.ROOMS.getByName(waiting.room_id).snapshot(host.player_id))).toEqual(waiting);
          expect((await env.PLAYERS.getByName(guest.player_id).listRooms()).some(link => link.room_id === waiting.room_id)).toBe(false);
        }
      }
      const joined = await call("/v1/rooms/join", "POST", guest, { invite_code: waiting.invite_code, simulation_version: 8 });
      expect(joined.status).toBe(200);
      const accepted = await joined.json<RoomSnapshot>();
      expect(accepted.guest_id).toBe(guest.player_id);
      expect(accepted.simulation_version ?? 1).toBe(version);
    }
  });
});
