import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { LEVEL_IDS, digest, type Outcome, type Recording, type RoomSnapshot } from "../src/protocol";
import { TERMS_VERSION } from "../src/public-policy";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { MutationV2, RoomSnapshotV2, RoomV2 } from "../src/v2/room";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import { noteHistorySupport, writeAttempt, type AttemptRecord } from "../src/v2/history";
import { acknowledgeAttempt, offloadedCount } from "../src/v2/history-room";
import { initializeHistory } from "../src/v2/storage-schema";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Inbox = { schema_version: 1; rooms: { room_id: string; status: string; api_version: number; partner_left?: boolean }[] };
const key = () => crypto.randomUUID();
const LEAVE = { schema_version: 1, leave_finished: true };
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env };
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body)
  }), configured);
}
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
const errorCode = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
async function create(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
const links = async (account: Account) => (await env.PLAYERS.getByName(account.player_id).listRooms()).map(link => link.room_id);
const inbox = async (account: Account, headers: Record<string, string> = {}) => (await call("/v1/room-inbox", "GET", account, undefined, headers)).json<Inbox>();
const LEFT = { "X-AfterYou-Room-Leave": "1" };
const LOOKUP = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
const leave = (version: 1 | 2, roomId: string, account: Account, body: unknown = LEAVE) => call(`/v${version}/rooms/${roomId}/leave`, "POST", account, body);

const create2 = (host: Account, idempotency_key: string) => call("/v2/rooms", "POST", host, { idempotency_key, level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
async function relayRoom(host: Account, idempotency_key = key()): Promise<RoomSnapshotV2> {
  const result = await create2(host, idempotency_key);
  expect(result.status).toBe(200); return result.json<RoomSnapshotV2>();
}
async function submit(room: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown): Promise<RoomSnapshotV2> {
  const result = await call(`/v2/rooms/${room.room_id}/turns`, "POST", account,
    { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint === undefined ? {} : { checkpoint }) });
  expect(result.status).toBe(200); return (await result.json<MutationV2>()).room;
}
/** A finished Relay room: the host plays t0-0-a and t0-1-b, the guest t0-0-b and t0-1-a. */
async function finishedRelay(createKey = key()) {
  const host = await create(), guest = await create(), made = await relayRoom(host, createKey);
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: made.invite_code }); expect(joined.status).toBe(200);
  let room = await joined.json<RoomSnapshotV2>();
  room = await submit(room, host, firstA); room = await submit(room, guest, firstB, middle);
  room = await submit(room, guest, secondA); room = await submit(room, host, secondB, final);
  expect(room.active_role).toBe("complete");
  return { host, guest, room, stub: env.ROOMS_V2.getByName(room.room_id) };
}
async function photo(stub: DurableObjectStub<import("../src/v2/room").RoomV2>, owner: Account, turn: string, recordingHash: string, shade: number) {
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(shade), width: 8, height: 8 }, 45).data);
  const jpeg_base64 = btoa(String.fromCharCode(...bytes)), sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  // Shared photos always need the safety terms accepted.
  value(await env.SAFETY_PROFILES.getByName(owner.player_id).accept(owner.player_id, await digest(owner.device_token), TERMS_VERSION));
  value(await stub.updatePhoto(owner.player_id, turn, { idempotency_key: key(), recording_hash: recordingHash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64, sha256 }));
  return { recording_hash: recordingHash, photo_revision: 1, sha256 };
}
const reaction = (a: { recording_hash: string }, b: { recording_hash: string }, choice = "love") =>
  ({ idempotency_key: key(), a_hash: a.recording_hash, b_hash: b.recording_hash, expected_reaction_revision: 0, reaction: choice });

afterEach(async () => { await reset(); });

describe("leaving a finished room", () => {
  it("erases only the leaver's photos, deliveries and reactions, and the partner keeps the room and its replay", async () => {
    const { host, guest, room, stub } = await finishedRelay();
    const hostPhoto = await photo(stub, host, "t0-0-a", firstA.recording_hash, 90);
    const guestPhoto = await photo(stub, guest, "t0-0-b", firstB.recording_hash, 160);
    value(await stub.acknowledgePhoto(host.player_id, "t0-0-a", hostPhoto)); value(await stub.acknowledgePhoto(guest.player_id, "t0-0-a", hostPhoto));
    value(await stub.acknowledgePhoto(host.player_id, "t0-0-b", guestPhoto));
    value(await stub.react(host.player_id, "p0-0", reaction(firstA, firstB, "sparkles")));
    value(await stub.react(guest.player_id, "p0-0", reaction(firstA, firstB)));
    value(await stub.react(guest.player_id, "p0-1", reaction(secondA, secondB, "again")));
    const before = value(await stub.snapshot(host.player_id));

    // Still in the request as plain leave: a finished room is kept, as before.
    expect((await leave(2, room.room_id, guest, { schema_version: 1 })).status).toBe(409);
    const left = await leave(2, room.room_id, guest);
    expect(left.status).toBe(200); expect(await left.json()).toEqual({ schema_version: 1, removed: true });
    expect(await links(guest)).toEqual([]);
    expect((await inbox(guest)).rooms).toEqual([]);

    // The partner's room, turns, replay, photo and reaction stay as they were.
    expect(value(await stub.snapshot(host.player_id))).toEqual(before);
    expect((await inbox(host)).rooms).toMatchObject([{ room_id: room.room_id, status: "completed" }]);
    const collection = await call(`/v2/rooms/${room.room_id}/collection`, "GET", host);
    expect(collection.status).toBe(200); expect((await collection.json<{ pairs: unknown[] }>()).pairs).toHaveLength(2);
    expect(value(await stub.photoDelivery(host.player_id, "t0-0-a"))).toMatchObject({ photo: { sha256: hostPhoto.sha256 }, acked_player_ids: [host.player_id, guest.player_id] });
    expect(value(await stub.reactions(host.player_id, "p0-0")).reactions).toMatchObject([{ player_id: host.player_id, reaction: "sparkles" }]);
    expect(value(await stub.reactions(host.player_id, "p0-1")).reactions).toEqual([]);
    // The leaver's photo and its delivery record are gone from the server.
    expect(value(await stub.photo(host.player_id, "t0-0-b"))).toEqual({ photo: null, jpeg_base64: null });
    expect(value(await stub.photoDelivery(host.player_id, "t0-0-b"))).toMatchObject({ photo: null, available: false, acked_player_ids: [] });
    await runInDurableObject(stub, async (_, ctx) => {
      const owned = (table: string, column: string) => ctx.storage.sql.exec(`SELECT ${column} AS owner FROM ${table}`).toArray().map(row => String(row.owner));
      expect(owned("photos", "json_extract(data,'$.owner_player_id')")).toEqual([host.player_id]);
      expect(owned("pair_reactions", "json_extract(data,'$.player_id')")).toEqual([host.player_id]);
      for (const table of ["photo_operations", "reaction_operations"]) expect(owned(table, "request_key").every(request => request.startsWith(host.player_id + ":")), table).toBe(true);
      expect(owned("photo_delivery", "turn_id")).toEqual(["t0-0-a"]);
    });

    // The leaver is a stranger now: no reads, no new photo or reaction, no close.
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", guest)).status).toBe(404);
    expect((await call(`/v2/rooms/${room.room_id}`, "DELETE", guest)).status).toBe(404);
    expect(await stub.react(guest.player_id, "p0-0", reaction(firstA, firstB))).toMatchObject({ ok: false, status: 404 });
    expect(await stub.photo(guest.player_id, "t0-0-a")).toMatchObject({ ok: false, status: 404 });
    expect(await stub.memberRoomState(guest.player_id)).toBe("gone");
    expect(await stub.memberRoomState(host.player_id)).toBe("finished");
    // Nobody can fork the room back into play.
    const fork = await call(`/v2/rooms/${room.room_id}/fork`, "POST", host, { base_revision: before.revision, idempotency_key: key(), branch: before.branch, stage_index: 0 });
    expect(fork.status).toBe(409); expect(await errorCode(fork)).toBe("room_member_left");
    // Retrying is harmless.
    expect((await leave(2, room.room_id, guest)).status).toBe(200);
  });

  it("erases the whole room when the last member leaves", async () => {
    const { host, guest, room, stub } = await finishedRelay();
    expect((await leave(2, room.room_id, guest)).status).toBe(200);
    expect((await leave(2, room.room_id, host)).status).toBe(200);
    expect(await links(host)).toEqual([]);
    await runInDurableObject(stub, async (_, ctx) => {
      expect(JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data)).toEqual({ deleted: true });
      expect(ctx.storage.sql.exec("SELECT 1 FROM turns").toArray()).toEqual([]);
      expect(ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name='room_departures'").toArray()).toEqual([]);
    });
  });

  it("leaves a room whose replay both phones saved, and the partner still lists it", async () => {
    const { host, guest, room, stub } = await finishedRelay();
    await photo(stub, guest, "t0-0-b", firstB.recording_hash, 160);
    value(await stub.react(guest.player_id, "p0-0", reaction(firstA, firstB)));
    value(await stub.react(host.player_id, "p0-1", reaction(secondA, secondB, "again")));
    const offered = value(await stub.replayTransfer(host.player_id)), ack = { schema_version: 1, epoch: offered.manifest.epoch, archive_hash: offered.manifest.archive_hash };
    value(await stub.acknowledgeReplayTransfer(host.player_id, ack)); value(await stub.acknowledgeReplayTransfer(guest.player_id, ack));
    expect(await stub.memberRoomState(guest.player_id)).toBe("finished");

    expect((await leave(2, room.room_id, guest)).status).toBe(200);
    expect(await links(guest)).toEqual([]);
    expect(await stub.lobbySnapshot(guest.player_id)).toMatchObject({ ok: false, status: 404 });
    expect((await inbox(host)).rooms).toMatchObject([{ room_id: room.room_id, status: "completed" }]);
    const listed = await (await call("/v2/rooms", "GET", host)).json<{ rooms: { room_id: string; replay_transfer_version: number }[] }>();
    expect(listed.rooms).toMatchObject([{ room_id: room.room_id, replay_transfer_version: 1 }]);
    expect(value(await stub.reactions(host.player_id, "p0-0")).reactions).toEqual([]);
    expect(value(await stub.reactions(host.player_id, "p0-1")).reactions).toMatchObject([{ player_id: host.player_id }]);
    await runInDurableObject(stub, async (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT 1 FROM photos").toArray()).toEqual([]);
    });
    expect((await leave(2, room.room_id, host)).status).toBe(200);
    expect(await links(host)).toEqual([]);
    expect(await stub.memberRoomState(host.player_id)).toBe("gone");
  });

  it("finishes a leave whose unlink was lost, with either request body", async () => {
    for (const body of [LEAVE, { schema_version: 1 }]) {
      const { guest, room, stub } = await finishedRelay();
      value(await stub.leaveFinished(guest.player_id));
      expect(await links(guest)).toEqual([room.room_id]);
      expect((await leave(2, room.room_id, guest, body)).status).toBe(200);
      expect(await links(guest)).toEqual([]);
      await reset();
    }
  });

  it("refuses a room still in play, frees a link toward the room cap, and keeps strangers out", async () => {
    const lonely = await create(), waiting = await relayRoom(lonely);
    const refused = await leave(2, waiting.room_id, lonely);
    expect(refused.status).toBe(409); expect(await errorCode(refused)).toBe("room_not_closed");
    expect(await links(lonely)).toEqual([waiting.room_id]);
    const { host, guest, room } = await finishedRelay(), stranger = await create();
    expect((await leave(2, room.room_id, stranger)).status).toBe(200);
    expect(await links(host)).toEqual([room.room_id]);
    expect((await leave(2, room.room_id, guest, { ...LEAVE, leave_finished: "yes" })).status).toBe(400);
    expect((await leave(2, room.room_id, guest, { ...LEAVE, extra: 1 })).status).toBe(400);
    expect((await leave(2, room.room_id, guest)).status).toBe(200);
    expect(await links(guest)).toEqual([]);
  });

  it("leaves a finished legacy island: the leaver's reaction goes everywhere and the partner cannot fork or advance", async () => {
    const host = await create(), guest = await create();
    const made = await (await call("/v1/rooms", "POST", host, { idempotency_key: key() })).json<RoomSnapshot>();
    expect((await call("/v1/rooms/join", "POST", guest, { invite_code: made.invite_code })).status).toBe(200);
    const legacy = env.ROOMS.getByName(made.room_id);
    const play = async (current: RoomSnapshot): Promise<RoomSnapshot> => {
      const first = current.first_player_id === host.player_id ? host : guest, second = first === host ? guest : host;
      const a = value(await legacy.commit(first.player_id, current.revision, key(), "a".repeat(64), recording("a", current.level_id)));
      return value(await legacy.commit(second.player_id, a.revision, key(), "b".repeat(64), recording("b", current.level_id)));
    };
    let current = await play(value(await legacy.snapshot(host.player_id)));
    current = value(await legacy.react(guest.player_id, current.revision, key(), "c".repeat(64), "love"));
    current = value(await legacy.advance(host.player_id, current.revision, key(), "d".repeat(64)));
    current = await play(current);
    current = value(await legacy.react(guest.player_id, current.revision, key(), "e".repeat(64), "again"));
    current = value(await legacy.react(host.player_id, current.revision, key(), "f".repeat(64), "sparkles"));

    expect((await leave(1, made.room_id, guest)).status).toBe(200);
    expect(await links(guest)).toEqual([]);
    const kept = value(await legacy.snapshot(host.player_id));
    expect(kept.reactions).toEqual({ [host.player_id]: "sparkles" });
    expect(kept.revision).toBe(current.revision + 1);
    expect(value(await legacy.collection(host.player_id)).map(island => island.reactions)).toEqual([{ [host.player_id]: "sparkles" }, {}]);
    expect(await legacy.snapshot(guest.player_id)).toMatchObject({ ok: false, status: 404 });
    expect(await legacy.advance(host.player_id, kept.revision, key(), "1".repeat(64))).toMatchObject({ ok: false, code: "room_member_left" });
    expect(await legacy.fork(host.player_id, kept.revision, key(), "2".repeat(64))).toMatchObject({ ok: false, code: "room_member_left" });
    expect((await inbox(host)).rooms).toMatchObject([{ room_id: made.room_id, status: "completed", api_version: 1 }]);
  });

  it("keeps a leaver out of every read and write, on Relay rooms", async () => {
    const { host, guest, room, stub } = await finishedRelay();
    const before = value(await stub.snapshot(host.player_id));
    await photo(stub, host, "t0-0-a", firstA.recording_hash, 90);
    expect((await leave(2, room.room_id, guest)).status).toBe(200);
    for (const [path, method, body] of [[`/v2/rooms/${room.room_id}`, "GET"], [`/v2/rooms/${room.room_id}/collection`, "GET"], [`/v2/rooms/${room.room_id}/redo`, "GET"],
      [`/v2/rooms/${room.room_id}/fork`, "POST", { base_revision: before.revision, idempotency_key: key(), branch: before.branch, stage_index: 0 }]] as const) {
      expect((await call(path, method, guest, body)).status, `${method} ${path}`).toBe(404);
    }
    const upload = await photo(stub, guest, "t0-0-b", firstB.recording_hash, 40).catch((error: Error) => error.message);
    expect(upload).toBe("room_not_found");
    expect(await stub.acknowledgePhoto(guest.player_id, "t0-0-a", { recording_hash: firstA.recording_hash, photo_revision: 1, sha256: "0".repeat(64) })).toMatchObject({ ok: false, status: 404 });
    expect(await stub.reactionOperation(guest.player_id, key())).toMatchObject({ ok: false, status: 404 });
    expect(await stub.inboxProjection(guest.player_id)).toMatchObject({ ok: false, status: 404 });
    expect(await stub.friendInvite(host.player_id, guest.player_id)).toMatchObject({ ok: false, status: 409, code: "room_not_available" });
    // The partner sees that their friend left, but only when their client asks.
    expect((await inbox(host, LEFT)).rooms).toMatchObject([{ room_id: room.room_id, status: "completed", partner_left: true }]);
    expect((await inbox(host)).rooms[0]).not.toHaveProperty("partner_left");
  });

  it("answers a departed host's create retry as a deleted room, on Relay and legacy rooms", async () => {
    const createKey = key(), { host, room, stub } = await finishedRelay(createKey);
    expect((await leave(2, room.room_id, host)).status).toBe(200);
    const retried = await create2(host, createKey);
    expect(retried.status).toBe(410); expect(await errorCode(retried)).toBe("room_deleted");
    expect(await links(host)).toEqual([]);
    expect(await stub.friendInvite(host.player_id, host.player_id)).toMatchObject({ ok: false, status: 404 });

    const legacyHost = await create(), legacyGuest = await create(), legacyKey = key();
    const made = await (await call("/v1/rooms", "POST", legacyHost, { idempotency_key: legacyKey })).json<RoomSnapshot>();
    expect((await call("/v1/rooms/join", "POST", legacyGuest, { invite_code: made.invite_code })).status).toBe(200);
    const legacy = env.ROOMS.getByName(made.room_id);
    const a = value(await legacy.commit(legacyHost.player_id, 1, key(), "a".repeat(64), recording("a", made.level_id)));
    value(await legacy.commit(legacyGuest.player_id, a.revision, key(), "b".repeat(64), recording("b", made.level_id)));
    expect((await leave(1, made.room_id, legacyHost)).status).toBe(200);
    const legacyRetry = await call("/v1/rooms", "POST", legacyHost, { idempotency_key: legacyKey });
    expect(legacyRetry.status).toBe(410); expect(await errorCode(legacyRetry)).toBe("room_deleted");
    expect(await legacy.redo(legacyHost.player_id)).toMatchObject({ ok: false, status: 404 });
    expect(await legacy.friendInvite(legacyHost.player_id, legacyGuest.player_id)).toMatchObject({ ok: false, status: 404 });
    expect(await legacy.inboxProjection(legacyHost.player_id)).toMatchObject({ ok: false, status: 404 });
  });

  it("re-checks the room inside the leave, so a fork that lands first keeps the leaver in", async () => {
    const { host, guest, room, stub } = await finishedRelay();
    const before = value(await stub.snapshot(host.player_id));
    const fork = await call(`/v2/rooms/${room.room_id}/fork`, "POST", host, { base_revision: before.revision, idempotency_key: key(), branch: before.branch, stage_index: 1 });
    expect(fork.status).toBe(200);
    expect(await stub.leaveFinished(guest.player_id)).toEqual({ ok: false, status: 409, code: "room_not_closed" });
    expect(await links(guest)).toEqual([room.room_id]);
    expect(await stub.memberRoomState(guest.player_id)).toBe("in_play");
  });

  it("keeps the partner's photo the leaver never saved, still waiting for its delivery", async () => {
    const { host, guest, room, stub } = await finishedRelay();
    const hostPhoto = await photo(stub, host, "t0-0-a", firstA.recording_hash, 90);
    value(await stub.acknowledgePhoto(host.player_id, "t0-0-a", hostPhoto));
    expect((await leave(2, room.room_id, guest)).status).toBe(200);
    expect(value(await stub.photoDelivery(host.player_id, "t0-0-a"))).toMatchObject({ available: true, acked_player_ids: [host.player_id], intended_player_ids: [host.player_id, guest.player_id] });
    expect(value(await stub.photo(host.player_id, "t0-0-a")).jpeg_base64).not.toBeNull();
  });

  it("refuses a Story room", async () => {
    const { guest, room, stub } = await finishedRelay();
    await runInDurableObject(stub, async (_, ctx) => { ctx.storage.sql.exec("UPDATE metadata SET schema_version=6 WHERE id=1"); });
    const refused = await leave(2, room.room_id, guest);
    expect(refused.status).toBe(409); expect(await errorCode(refused)).toBe("campaign_leave_unavailable");
    expect(await links(guest)).toEqual([room.room_id]);
  });

  it("waits while the partner needs an offloaded attempt back, and offloads nothing after a leave", async () => {
    const { host, guest, room, stub } = await finishedRelay();
    const attempt = (state: "held" | "offloaded", acked: string[], wanted: string[]): AttemptRecord =>
      ({ schema_version: 1, position: 0, branch: 0, digest: "d".repeat(64), link: "e".repeat(64), byte_length: 1, last_stage: 1, state, acked, wanted, pair_ids: ["p0-0", "p0-1"] });
    await runInDurableObject(stub, async (_, ctx) => { initializeHistory(ctx.storage); writeAttempt(ctx.storage, attempt("offloaded", [], [host.player_id])); });
    const waiting = await leave(2, room.room_id, guest);
    expect(waiting.status).toBe(409); expect(await errorCode(waiting)).toBe("history_offload_active");
    // Once nobody waits, the leave goes ahead; the partner's phone holds every offloaded attempt.
    await runInDurableObject(stub, async (_, ctx) => {
      writeAttempt(ctx.storage, attempt("held", [guest.player_id], []));
      noteHistorySupport(ctx.storage, host.player_id, 1); noteHistorySupport(ctx.storage, guest.player_id, 1);
    });
    expect((await leave(2, room.room_id, guest)).status).toBe(200);
    await runInDurableObject(stub, async (_, ctx) => {
      const live = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data);
      const record = acknowledgeAttempt(ctx.storage, live, attempt("held", [guest.player_id], []), host.player_id);
      expect(record).toMatchObject({ state: "held", acked: [host.player_id, guest.player_id] });
      expect(offloadedCount(ctx.storage)).toBe(0);
    });
  });

  it("reads no more rows on a room nobody left: one table lookup per room instance, then nothing", async () => {
    const { host, guest, room, stub } = await finishedRelay();
    await evictDurableObject(stub);
    await runInDurableObject(stub, async (instance: RoomV2, ctx) => {
      const sql = ctx.storage.sql, exec = sql.exec.bind(sql);
      const seen: { query: string }[] = [];
      Object.defineProperty(sql, "exec", { configurable: true, value: (query: string, ...bindings: unknown[]) => { seen.push({ query }); return exec(query, ...bindings); } });
      // Only this branch's queries; the campaign boundary keeps its own existing schema reads.
      const departure = (query: string) => query === LOOKUP || query.includes("room_departures");
      const poll = async () => { seen.length = 0; value(await instance.snapshot(host.player_id)); value(await instance.lobbySnapshot(host.player_id)); expect(await instance.memberRoomState(host.player_id)).toBe("finished"); };
      await poll();
      expect(seen.filter(entry => departure(entry.query)).map(entry => entry.query)).toEqual([LOOKUP]);
      for (let round = 0; round < 3; round++) {
        await poll();
        // Every query a warm poll runs is one it ran before this branch, so it reads the same rows.
        expect(seen.filter(entry => departure(entry.query))).toEqual([]);
      }
      // Once someone has left, a poll reads the departure rows and never the schema again.
      value(await instance.leaveFinished(guest.player_id));
      await poll();
      expect(seen.filter(entry => departure(entry.query)).every(entry => entry.query.includes("room_departures"))).toBe(true);
      delete (sql as unknown as Record<string, unknown>).exec;
    });
    expect(room.room_id).toBeTruthy();
  });
});

function recording(role: "a" | "b", level: string): Recording {
  return {
    schema_version: 1, simulation_version: 1, level_version: 1, tick_rate: 30, level_id: level as typeof LEVEL_IDS[0],
    role, duration_ticks: 30, catch_assistance: true,
    actions: [{ ticks: 30, x: 0, z: 0, action: true }], checkpoints: [{ tick: 30, state_hash: role.repeat(64) }],
    final_state_hash: role.repeat(64), completed: role === "b",
    outcome: { threw_seed: role === "a", caught_seed: role === "b", planted_seed: role === "b" },
    ...(role === "b" ? { source_recording_hash: "a".repeat(64) } : {})
  };
}
