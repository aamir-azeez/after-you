import { afterEach, describe, expect, it, vi } from "vitest";
import { ROOM_INBOX_CONCURRENCY, type RoomInboxProjection } from "../src/room-inbox";
import { indexedRoomInbox } from "../src/room-index-lists";
import type { RoomLink } from "../src/room-links";
import type { RoomObservation } from "../src/room-index";
import { ok, type Outcome } from "../src/protocol";
import { RELAY } from "../src/v2/protocol";

// The inbox is always read through the room index now; these pin its fan-out on a page whose rooms all need a live read.
afterEach(() => { vi.restoreAllMocks(); });

const ME = "m".repeat(22), PARTNER = "p".repeat(22);
const roomId = (index: number) => "r" + String(index).padStart(21, "0");
function projection(index: number): RoomInboxProjection {
  // Rooms alternate who hosts, as they do between two friends.
  const host = index % 2 === 0;
  return { room_id: roomId(index), chapter: { id: RELAY.id, version: RELAY.version }, membership: { host_id: host ? ME : PARTNER, guest_id: host ? PARTNER : ME, you_are_host: host },
    status: "your_turn", revision: index, remote_activity_sequence: 1, activity_at: new Date(Date.UTC(2026, 0, 1, 0, index)).toISOString() };
}
/** A stub environment: an index page of twenty Relay links shared with one partner, each to be read live. */
function fakeEnv(project: (id: string) => Promise<Outcome<RoomInboxProjection>>) {
  const links: RoomLink[] = Array.from({ length: 20 }, (_, index) => ({ room_id: roomId(index), invite_code: "", host: true, api_version: 2 }));
  const counts = { hasBlocked: 0, inFlight: 0, maxInFlight: 0, recorded: 0 };
  const stub = {
    PLAYERS: { getByName: () => ({
      roomIndexPage: async () => ({ rooms: links.map(link => ({ link, row: null, read: true })), recheck: [], next: null }),
      recordRoomIndex: async (_: string, items: unknown[]) => { counts.recorded += items.length; }
    }) },
    ROOMS_V2: { getByName: (id: string) => ({ indexEntry: async (): Promise<RoomObservation> => {
      counts.inFlight++; counts.maxInFlight = Math.max(counts.maxInFlight, counts.inFlight);
      try { await new Promise(resolve => setTimeout(resolve, 1)); return { observed_at: 1, outcome: await project(id) }; } finally { counts.inFlight--; }
    } }) },
    SAFETY_PROFILES: { getByName: () => ({ hasBlocked: async () => { counts.hasBlocked++; await new Promise(resolve => setTimeout(resolve, 1)); return false; } }) }
  };
  return { env: stub as unknown as Env, counts };
}

describe("room inbox fan-out", () => {
  it("checks the block list once per pair and reads only a few rooms at a time", async () => {
    const { env: stub, counts } = fakeEnv(async id => ok(projection(Number(id.slice(1)))));
    const { body } = await indexedRoomInbox(ME, stub, false, false, 0);
    expect(body.rooms).toHaveLength(20);
    expect(counts.hasBlocked).toBeLessThanOrEqual(2);
    expect(counts.maxInFlight).toBeLessThanOrEqual(ROOM_INBOX_CONCURRENCY);
    expect(counts.recorded).toBe(20);
    expect(body.rooms.map(room => room.room_id)).toEqual(Array.from({ length: 20 }, (_, index) => roomId(19 - index)));
  });

  it("shows a room that throws as unavailable while the others still list", async () => {
    const broken = roomId(7);
    const { env: stub } = fakeEnv(async id => { if (id === broken) throw new Error("room_storage_unavailable"); return ok(projection(Number(id.slice(1)))); });
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const { body } = await indexedRoomInbox(ME, stub, true, false, 0);
    expect(warn.mock.calls.map(args => JSON.parse(String(args[0])))).toEqual([{ event: "room_inbox_entry_failed", api_version: 2, reason: "room_storage_unavailable" }]);
    expect(JSON.stringify(warn.mock.calls)).not.toContain(broken);
    expect(body.rooms).toHaveLength(20);
    expect(body.rooms.find(room => room.room_id === broken)).toMatchObject({ room_id: broken, family: "relay", api_version: 2, status: "unavailable", revision: null });
    expect(body.rooms.filter(room => room.status === "your_turn")).toHaveLength(19);
  });
});
