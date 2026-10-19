import { env } from "cloudflare:workers";
import { reset, runInDurableObject as openRaw } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { makeHint } from "../src/notifications";
import { randomToken } from "../src/protocol";
import type { CampaignRoomContext } from "../src/v2/campaign-room-access";
import { meterAllRows } from "./meter";
import { runInDurableObject as openWithTables } from "./room-objects";

// An object nobody has written to (a room, a Player or a SafetyProfile opened by an id that was
// never used) holds no storage. Each read it can be asked answers exactly what the same object
// with empty tables answers, and stores nothing.

afterEach(async () => { await reset(); });
const P = "p".repeat(22), Q = "q".repeat(22), CODE = "A".repeat(20), KEY = "k".repeat(32), HASH = "d".repeat(64);
type V2 = DurableObjectStub<import("../src/v2/room").RoomV2>;
type V1 = DurableObjectStub<import("../src/room").Room>;
type PlayerStub = DurableObjectStub<import("../src/player").Player>;
type ProfileStub = DurableObjectStub<import("../src/safety").SafetyProfile>;
type Read<S> = [string, (stub: S, id: string) => Promise<unknown>];
const source = { room_id: "r".repeat(22), revision: 1, branch: 0, stage_index: 0, a_hash: "a".repeat(64), first_player_id: P, second_player_id: Q };
const story = (id: string): CampaignRoomContext => ({ schema_version: 2, room_id: id, device_hash: HASH });

const RELAY_READS: Read<V2>[] = [
  ["join", room => room.join(P, CODE)],
  ["join naming rules versions", room => room.join(P, CODE, [2])],
  ["resolvesInvitation", room => room.resolvesInvitation(CODE)],
  ["safetyMembers", room => room.safetyMembers(P)],
  ["safetyMembers from a Story client", (room, id) => room.safetyMembers(P, story(id))],
  ["interactionAllowed", room => room.interactionAllowed(P, undefined, "t".repeat(22))],
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
  ["redo request", room => room.redo(P, { action: "request", source }, HASH)],
  ["history", room => room.history(P)],
  ["tries", room => room.tries(P)],
  ["end reactions", room => room.endReactions(P)],
];
const LEGACY_READS: Read<V1>[] = [
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
const PLAYER_READS: Read<PlayerStub>[] = [
  ["authorize", player => player.authorize(HASH)],
  ["authorize while deleting", player => player.authorize(HASH, true)],
  ["authorizeRoom", player => player.authorizeRoom(HASH, "r".repeat(22))],
  ["rotateSafetyToken", player => player.rotateSafetyToken()],
  ["liveHint for a room", player => player.liveHint(P, { kind: "room", room_id: "r".repeat(22), revision: 1 })],
  ["liveHint from a friend", player => player.liveHint(P, { kind: "friends", from: Q, request_id: "q".repeat(22) })],
];
const PROFILE_READS: Read<ProfileStub>[] = [
  ["deletionReceipt", (profile, id) => profile.deletionReceipt(id, HASH)],
  ["acknowledgeDeletion", (profile, id) => profile.acknowledgeDeletion(id, HASH)],
  ["acknowledgeDeletion with a bad hash", (profile, id) => profile.acknowledgeDeletion(id, "x")],
];

async function answer(work: () => Promise<unknown>): Promise<unknown> {
  try { return await work(); } catch (error) { return { threw: String(error) }; }
}
/** Each read on a blank object, against the same read on an object whose tables exist but hold no rows. */
async function compare<S extends DurableObjectStub>(namespace: { getByName(id: string): S }, reads: Read<S>[]) {
  for (const [name, read] of reads) {
    const blankId = randomToken(16), emptyId = randomToken(16), empty = namespace.getByName(emptyId);
    await openWithTables(empty as DurableObjectStub, () => undefined);
    const expected = await answer(() => read(empty, emptyId));
    const blank = await meterAllRows(() => answer(() => read(namespace.getByName(blankId), blankId)));
    expect({ name, answer: blank.value, written: blank.rows.written }).toEqual({ name, answer: expected, written: 0 });
    expect(await tables(namespace.getByName(blankId) as DurableObjectStub)).toBe(0);
  }
}
async function tables(stub: DurableObjectStub): Promise<number> {
  return openRaw(stub, async (_, ctx) => ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE '_cf_%'").toArray().length);
}

describe("an object nobody has written to", () => {
  it("answers every Relay room read as an empty room does and stores nothing", async () => { await compare(env.ROOMS_V2, RELAY_READS); });
  it("answers every legacy room read as an empty room does and stores nothing", async () => { await compare(env.ROOMS, LEGACY_READS); });
  it("answers the Player identity checks as a Player with no identity does and stores nothing", async () => { await compare(env.PLAYERS, PLAYER_READS); });
  it("answers the SafetyProfile deletion checks as an empty profile does and stores nothing", async () => { await compare(env.SAFETY_PROFILES, PROFILE_READS); });

  it("stores nothing for requests that name random player ids, and real players work as before", async () => {
    let address = 0;
    const send = (method: string, id: string, token = randomToken()) => worker.fetch(new Request("https://after-you.test/v1/identity", { method,
      headers: { "CF-Connecting-IP": "198.18.30." + (++address % 250), "X-Player-Id": id, Authorization: "Bearer " + token } }), env);
    const ids = Array.from({ length: 20 }, () => randomToken(16));
    // On main each of these opened a Player (and, for DELETE, a SafetyProfile) and created its tables.
    const flood = await meterAllRows(async () => { const codes = []; for (const id of ids) codes.push((await send("GET", id)).status, (await send("DELETE", id)).status); return codes; });
    expect({ codes: [...new Set(flood.value)], written: flood.rows.written }).toEqual({ codes: [401], written: 0 });
    for (const id of ids.slice(0, 3)) {
      expect(await tables(env.PLAYERS.getByName(id))).toBe(0);
      expect(await tables(env.SAFETY_PROFILES.getByName(id))).toBe(0);
    }
    const created = await (await worker.fetch(new Request("https://after-you.test/v1/identity", { method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.31.1" }, body: "{}" }), env)).json<{ player_id: string; device_token: string }>();
    expect(await (await send("GET", created.player_id, created.device_token)).json()).toEqual({ player_id: created.player_id });
    expect((await send("DELETE", created.player_id, created.device_token)).status).toBe(200);
  });
});
