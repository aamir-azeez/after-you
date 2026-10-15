import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { ROOM_INBOX_CONCURRENCY, roomInbox, type RoomInboxEntry, type RoomInboxProjection } from "../src/room-inbox";
import { roomLinkVersion, type RoomLink } from "../src/room-links";
import { interactionBlocked } from "../src/safety";
import { fail, ok, type Outcome, type RoomSnapshot } from "../src/protocol";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";

type Account = { player_id: string; device_token: string; recovery_code: string };
let address = 0;
const key = () => crypto.randomUUID();
async function call(path: string, method = "GET", account?: Account, body?: unknown): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true" });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.3." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
const create = async () => (await call("/v1/identity", "POST", undefined, {})).json<Account>();
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

/** The serial loop as it was before bounded fan-out, kept to pin the response bytes. */
async function serialInbox(playerId: string, environment: Env, showClosed = false): Promise<{ schema_version: 1; rooms: RoomInboxEntry[] }> {
  const fallback = (link: RoomLink, status: RoomInboxEntry["status"] = "unavailable"): RoomInboxEntry => {
    const version = roomLinkVersion(link);
    return { room_id: link.room_id, family: version === 1 ? "legacy" : version === 2 ? "relay" : version === 3 ? "story" : "unknown",
      api_version: version, chapter: { id: null, version: null }, membership: { host_id: null, guest_id: null, you_are_host: link.host }, status,
      revision: null, remote_activity_sequence: 0, activity_at: null };
  };
  const rooms: RoomInboxEntry[] = [];
  for (const link of await environment.PLAYERS.getByName(playerId).listRooms()) {
    const version = roomLinkVersion(link);
    if (version !== 1 && version !== 2) { rooms.push(fallback(link)); continue; }
    const result = version === 1 ? await environment.ROOMS.getByName(link.room_id).inboxProjection(playerId) : await environment.ROOMS_V2.getByName(link.room_id).inboxProjection(playerId);
    if (!result.ok) { rooms.push(fallback(link, showClosed && result.status === 410 ? "closed" : "unavailable")); continue; }
    if (await interactionBlocked(environment, result.value.membership.host_id!, result.value.membership.guest_id)) continue;
    rooms.push({ ...result.value, family: version === 1 ? "legacy" : "relay", api_version: version });
  }
  rooms.sort((a, b) => (Date.parse(b.activity_at ?? "") || 0) - (Date.parse(a.activity_at ?? "") || 0));
  return { schema_version: 1, rooms };
}

const ME = "m".repeat(22), PARTNER = "p".repeat(22);
const roomId = (index: number) => "r" + String(index).padStart(21, "0");
function projection(index: number): RoomInboxProjection {
  // Rooms alternate who hosts, as they do between two friends.
  const host = index % 2 === 0;
  return { room_id: roomId(index), chapter: { id: RELAY.id, version: RELAY.version }, membership: { host_id: host ? ME : PARTNER, guest_id: host ? PARTNER : ME, you_are_host: host },
    status: "your_turn", revision: index, remote_activity_sequence: 1, activity_at: new Date(Date.UTC(2026, 0, 1, 0, index)).toISOString() };
}
/** A stub environment: twenty Relay links shared with one partner. */
function fakeEnv(project: (id: string) => Promise<Outcome<RoomInboxProjection>>) {
  const links: RoomLink[] = Array.from({ length: 20 }, (_, index) => ({ room_id: roomId(index), invite_code: "", host: true, api_version: 2 }));
  const counts = { hasBlocked: 0, inFlight: 0, maxInFlight: 0 };
  const stub = {
    PLAYERS: { getByName: () => ({ listRooms: async () => links }) },
    ROOMS: { getByName: () => ({ inboxProjection: async () => fail(404, "room_not_found") }) },
    ROOMS_V2: { getByName: (id: string) => ({ inboxProjection: async () => {
      counts.inFlight++; counts.maxInFlight = Math.max(counts.maxInFlight, counts.inFlight);
      try { await new Promise(resolve => setTimeout(resolve, 1)); return await project(id); } finally { counts.inFlight--; }
    } }) },
    SAFETY_PROFILES: { getByName: () => ({ hasBlocked: async () => { counts.hasBlocked++; await new Promise(resolve => setTimeout(resolve, 1)); return false; } }) }
  };
  return { env: stub as unknown as Env, counts };
}

describe("room inbox fan-out", () => {
  it("checks the block list once per pair and reads only a few rooms at a time", async () => {
    const { env: stub, counts } = fakeEnv(async id => ok(projection(Number(id.slice(1)))));
    const result = await roomInbox(ME, stub);
    expect(result.rooms).toHaveLength(20);
    expect(counts.hasBlocked).toBeLessThanOrEqual(2);
    expect(counts.maxInFlight).toBeLessThanOrEqual(ROOM_INBOX_CONCURRENCY);
    expect(result.rooms.map(room => room.room_id)).toEqual(Array.from({ length: 20 }, (_, index) => roomId(19 - index)));
  });

  it("shows a room that throws as unavailable while the others still list", async () => {
    const broken = roomId(7);
    const { env: stub } = fakeEnv(async id => { if (id === broken) throw new Error("room_storage_unavailable"); return ok(projection(Number(id.slice(1)))); });
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const result = await roomInbox(ME, stub, true);
    expect(warn.mock.calls.map(args => JSON.parse(String(args[0])))).toEqual([{ event: "room_inbox_entry_failed", api_version: 2, reason: "room_storage_unavailable" }]);
    expect(JSON.stringify(warn.mock.calls)).not.toContain(broken);
    expect(result.rooms).toHaveLength(20);
    expect(result.rooms.find(room => room.room_id === broken)).toEqual({ room_id: broken, family: "relay", api_version: 2, chapter: { id: null, version: null },
      membership: { host_id: null, guest_id: null, you_are_host: true }, status: "unavailable", revision: null, remote_activity_sequence: 0, activity_at: null });
    expect(result.rooms.filter(room => room.status === "your_turn")).toHaveLength(19);
  });

  it("returns the same bytes as the serial list for live, blocked, closed and missing rooms", async () => {
    const me = await create(), friend = await create(), blocker = await create(), leaver = await create();
    const legacy = await (await call("/v1/rooms", "POST", me, { idempotency_key: key() })).json<RoomSnapshot>();
    const relay = async () => (await call("/v2/rooms", "POST", me, { idempotency_key: key(), level_id: RELAY.id, level_version: RELAY.version, definition_hash: DEFINITION_HASH })).json<RoomSnapshotV2>();
    const waiting = await relay(), shared = await relay(), blocked = await relay(), closed = await relay();
    for (const [room, guest] of [[shared, friend], [blocked, blocker], [closed, leaver]] as const)
      expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
    expect((await call("/v1/safety/block", "POST", blocker, { schema_version: 1, room_family: "relay", room_id: blocked.room_id })).status).toBe(200);
    expect((await call(`/v2/rooms/${closed.room_id}`, "DELETE", leaver)).status).toBe(200);
    expect(await env.PLAYERS.getByName(me.player_id).addRoom({ room_id: "z".repeat(22), invite_code: "", host: false, api_version: 2 })).toMatchObject({ ok: true });
    for (const showClosed of [false, true]) {
      const expected = JSON.stringify(await serialInbox(me.player_id, env, showClosed));
      expect(JSON.stringify(await roomInbox(me.player_id, env, showClosed))).toBe(expected);
      const listed = (JSON.parse(expected) as { rooms: RoomInboxEntry[] }).rooms;
      expect(listed.map(room => room.room_id).sort()).toEqual([legacy.room_id, waiting.room_id, shared.room_id, closed.room_id, "z".repeat(22)].sort());
      expect(listed.find(room => room.room_id === closed.room_id)?.status).toBe(showClosed ? "closed" : "unavailable");
    }
  });
});
