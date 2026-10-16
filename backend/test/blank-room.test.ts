import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { makeHint } from "../src/notifications";
import { randomToken } from "../src/protocol";
import type { CampaignRoomContext } from "../src/v2/campaign-room-access";
import { meterAllRows } from "./meter";

// A room object nobody has written to holds no storage. Every read it can be asked answers
// exactly what an empty room always answered, and stores nothing.

afterEach(async () => { await reset(); });
const P = "p".repeat(22), Q = "q".repeat(22), CODE = "A".repeat(20), KEY = "k".repeat(32);
type V2 = DurableObjectStub<import("../src/v2/room").RoomV2>;
type V1 = DurableObjectStub<import("../src/room").Room>;
const source = { room_id: "r".repeat(22), revision: 1, branch: 0, stage_index: 0, a_hash: "a".repeat(64), first_player_id: P, second_player_id: Q };

const RELAY_READS: [string, (room: V2, id: string) => Promise<unknown>][] = [
  ["join", room => room.join(P, CODE)],
  ["join naming rules versions", room => room.join(P, CODE, [2])],
  ["resolvesInvitation", room => room.resolvesInvitation(CODE)],
  ["safetyMembers", room => room.safetyMembers(P)],
  ["safetyMembers from a Story client", (room, id) => room.safetyMembers(P, story(id))],
  ["memberRoomState", room => room.memberRoomState(P)],
  ["inboxProjection", room => room.inboxProjection(P)],
  ["notificationEligible", (room, id) => room.notificationEligible(P, makeHint("relay", id, 2))],
  ["stageCount", room => room.stageCount()],
  ["friendInvite", room => room.friendInvite(P, Q)],
  ["campaignRoomNegotiation", room => room.campaignRoomNegotiation(false)],
  ["campaignRoomNegotiation from a Story client", room => room.campaignRoomNegotiation(true)],
  ["snapshot", room => room.snapshot(P)],
  ["snapshot from a Story client", (room, id) => room.snapshot(P, story(id))],
  ["snapshotIfChanged", room => room.snapshotIfChanged(P, { revision: 0, branch: 0 })],
  ["snapshotIfChanged with redo", room => room.snapshotIfChanged(P, { revision: 0, branch: 0 }, undefined, true)],
  ["lobbySnapshot", room => room.lobbySnapshot(P)],
  ["operation", room => room.operation(P, KEY)],
  ["collection", room => room.collection(P)],
  ["pairRecording", room => room.pairRecording(P, "p0-0")],
  ["reactions", room => room.reactions(P, "p0-0")],
  ["reactionOperation", room => room.reactionOperation(P, KEY)],
  ["photo", room => room.photo(P, "t0-0-a")],
  ["photoOperation", room => room.photoOperation(P, KEY)],
  ["photoDelivery", room => room.photoDelivery(P, "t0-0-a")],
  ["redo", room => room.redo(P)],
  ["redo request", room => room.redo(P, { action: "request", source }, "d".repeat(64))],
  ["history", room => room.history(P)],
];
const LEGACY_READS: [string, (room: V1, id: string) => Promise<unknown>][] = [
  ["join", room => room.join(P, CODE)],
  ["resolvesInvitation", room => room.resolvesInvitation(CODE)],
  ["safetyMembers", room => room.safetyMembers(P)],
  ["memberRoomState", room => room.memberRoomState(P)],
  ["inboxProjection", room => room.inboxProjection(P)],
  ["notificationEligible", (room, id) => room.notificationEligible(P, makeHint("legacy", id, 2))],
  ["friendInvite", room => room.friendInvite(P, Q)],
  ["snapshot", room => room.snapshot(P)],
  ["operationSnapshot", room => room.operationSnapshot(P, KEY, "h".repeat(64))],
  ["collection", room => room.collection(P)],
  ["redo", room => room.redo(P)],
];
function story(id: string): CampaignRoomContext { return { schema_version: 2, room_id: id, device_hash: "d".repeat(64) }; }
async function answer(work: () => Promise<unknown>): Promise<unknown> {
  try { return await work(); } catch (error) { return { threw: String(error) }; }
}
async function stored(room: DurableObjectStub): Promise<{ size: number; tables: number }> {
  return runInDurableObject(room, async (_, ctx) => ({ size: ctx.storage.sql.databaseSize,
    tables: ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE '_cf_%'").toArray().length }));
}

/** What each read answered on main, where every object created its tables when constructed. */
const ROOM_NOT_FOUND = { ok: false, status: 404, code: "room_not_found" }, INVITE_NOT_FOUND = { ok: false, status: 404, code: "invite_not_found" };
const SPECIAL: Record<string, unknown> = { join: INVITE_NOT_FOUND, "join naming rules versions": INVITE_NOT_FOUND, resolvesInvitation: false, memberRoomState: "gone",
  notificationEligible: false, stageCount: 2, campaignRoomNegotiation: { ok: true, value: true }, "campaignRoomNegotiation from a Story client": { ok: true, value: true } };
const golden = (names: string[]) => Object.fromEntries(names.map(name => [name, name in SPECIAL ? SPECIAL[name] : ROOM_NOT_FOUND]));
const RELAY_GOLDEN = golden(RELAY_READS.map(([name]) => name)), LEGACY_GOLDEN = golden(LEGACY_READS.map(([name]) => name));

describe("a room nobody has written to", () => {
  it("answers every Relay read as an empty room did and stores nothing", async () => {
    const answers: Record<string, unknown> = {};
    const metered = await meterAllRows(async () => {
      for (const [name, read] of RELAY_READS) { const id = randomToken(16), room = env.ROOMS_V2.getByName(id); answers[name] = await answer(() => read(room, id)); }
    });
    expect(answers).toEqual(RELAY_GOLDEN);
    expect(metered.rows.written).toBe(0);
    // No table and one empty 4 KB page; on main this was 18 tables and about 78 KB.
    expect(await stored(env.ROOMS_V2.getByName(randomToken(16)))).toEqual({ size: 4096, tables: 0 });
  });
  it("answers every legacy read as an empty room did and stores nothing", async () => {
    const answers: Record<string, unknown> = {};
    const metered = await meterAllRows(async () => {
      for (const [name, read] of LEGACY_READS) { const id = randomToken(16), room = env.ROOMS.getByName(id); answers[name] = await answer(() => read(room, id)); }
    });
    expect(answers).toEqual(LEGACY_GOLDEN);
    expect(metered.rows.written).toBe(0);
  });
});
