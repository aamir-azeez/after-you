import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { type Outcome } from "../src/protocol";
import { chapter, RELAY_KEY } from "../src/v2/protocol";
import type { RoomSnapshotV2, MutationV2 } from "../src/v2/room";
import type { RedoSource, RedoState, RedoStateV2 } from "../src/redo-control";
import a from "../../game/tests/fixtures/v2/relay-a.json";
import b from "../../game/tests/fixtures/v2/relay-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, extra: Record<string, string> = {}) {
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: {
    "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + ++address,
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...extra
  }, body: body === undefined ? undefined : JSON.stringify(body) }), { ...env });
}
async function json<T>(response: Promise<Response>, status = 200): Promise<T> {
  const result = await response; const text = await result.text();
  expect(result.status, text).toBe(status); return JSON.parse(text) as T;
}
const account = () => json<Account>(call("/v1/identity", "POST", undefined, {}), 201);
const key = () => crypto.randomUUID();
const V2 = { "X-AfterYou-Poll-Redo": "1", "X-AfterYou-Redo-Extras": "1" };
function unwrap<T>(value: Outcome<T>): T { if (!value.ok) throw new Error(value.code); return value.value; }
async function made(host: Account) {
  const version = chapter(RELAY_KEY).simulation_version;
  return json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { idempotency_key: key(), ...RELAY_KEY, ...(version === 2 ? {} : { simulation_version: 2 }) }));
}
const join = (room: RoomSnapshotV2, guest: Account) => json<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: [2, 4, 5, 6, 7, 8] }));
const turnBody = (room: RoomSnapshotV2, recording: unknown, extra: Record<string, unknown> = {}) => ({ base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...extra });
const turn = (room: RoomSnapshotV2, owner: Account, recording: unknown, extra: Record<string, unknown> = {}, status = 200) =>
  json<MutationV2>(call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, turnBody(room, recording, extra)), status);
/** Host and guest joined, the host's first turn saved, and the guest has not read the room since. */
async function played() {
  const host = await account(), guest = await account();
  const room = await made(host);
  await join(room, guest);
  const first = await turn((await json<RoomSnapshotV2>(call(`/v2/rooms/${room.room_id}`, "GET", host))), host, a);
  return { host, guest, room: first.room, path: `/v2/rooms/${room.room_id}` };
}
const redoV2 = (path: string, who: Account) => json<RedoStateV2>(call(path + "/redo", "GET", who, undefined, V2));
const startOver = (room: RoomSnapshotV2, asker: Account, friend: Account): RedoSource => ({ room_id: room.room_id, revision: room.revision, branch: room.branch, stage_index: room.stage_index,
  a_hash: room.checkpoint.checkpoint_hash, first_player_id: friend.player_id, second_player_id: asker.player_id });
type Inbox = { rooms: { room_id: string; redo?: { state: string } }[] };
const inboxRedo = async (who: Account, roomId: string, version: string) =>
  (await json<Inbox>(call("/v1/room-inbox", "GET", who, undefined, { "X-AfterYou-Room-Redo": "1", ...(version === "2" ? { "X-AfterYou-Redo-Extras": "1" } : {}) }))).rooms.find(entry => entry.room_id === roomId)?.redo?.state;
/** Rows the room reads and writes from now on (every SQL statement it runs). */
async function meter(roomId: string) {
  const cursors: { rowsRead: number; rowsWritten: number }[] = [];
  await runInDurableObject(env.ROOMS_V2.getByName(roomId), (_, ctx) => {
    const original = ctx.storage.sql.exec.bind(ctx.storage.sql);
    vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((query: string, ...bindings: unknown[]) => { const cursor = original(query, ...bindings); cursors.push(cursor); return cursor; }) as typeof ctx.storage.sql.exec);
  });
  return async <T>(run: () => Promise<T>) => {
    const from = cursors.length; await run();
    return cursors.slice(from).reduce((sum, cursor) => ({ read: sum.read + cursor.rowsRead, written: sum.written + cursor.rowsWritten }), { read: 0, written: 0 });
  };
}
afterEach(async () => { await reset(); });

describe("play my turn again", () => {
  it("replaces the saved first turn in one save until the friend's phone has it", async () => {
    const { host, guest, room, path } = await played();
    expect((await redoV2(path, host)).replace_open).toBe(true);
    expect((await redoV2(path, guest)).replace_open).toBe(false);
    // Version 1 phones read the redo state exactly as before.
    expect(Object.keys(await json<RedoState>(call(path + "/redo", "GET", host))).sort()).toEqual(["request", "schema_version", "source"]);
    const body = turnBody(room, a, { replaces: a.recording_hash });
    const replaced = await json<MutationV2>(call(path + "/turns", "POST", host, body));
    expect(replaced.receipt).toMatchObject({ operation: "turns", accepted_revision: room.revision + 1, branch: room.branch + 1, stage_index: room.stage_index, turn_id: `t${room.branch + 1}-0-a` });
    expect(replaced.room).toMatchObject({ branch: room.branch + 1, revision: room.revision + 1, active_role: "b", a_turn_id: `t${room.branch + 1}-0-a` });
    // A retry answers the same; the friend's save against the old turn is refused.
    expect(await json(call(path + "/turns", "POST", host, body))).toEqual(replaced);
    await turn(room, guest, b, { checkpoint: middle }, 409);
    // The old turn stays in the room's history, and the pair still completes on the new branch.
    await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_instance, ctx) => {
      expect(ctx.storage.sql.exec<{ turn_id: string }>("SELECT turn_id FROM turns ORDER BY turn_id").toArray().map(row => row.turn_id)).toEqual(["t0-0-a", "t1-0-a"]);
    });
    const fresh = await json<RoomSnapshotV2>(call(path, "GET", guest));
    const completed = await turn(fresh, guest, b, { checkpoint: middle });
    expect(completed.room.stage_index).toBe(1);
  });

  it("is refused once the friend read the turn, or joined after it, and says so on the poll", async () => {
    const { host, guest, room, path } = await played();
    await json(call(path, "GET", guest));
    expect((await redoV2(path, host)).replace_open).toBe(false);
    const poll = await json<{ unchanged?: boolean; redo: RedoStateV2 }>(call(path, "GET", host, undefined, { ...V2, "X-AfterYou-Known-Room": `${room.revision}.${room.branch}` }));
    expect(poll).toMatchObject({ unchanged: true, redo: { schema_version: 2, replace_open: false } });
    await json(call(path + "/turns", "POST", host, turnBody(room, a, { replaces: a.recording_hash })), 409);
    // A guest who joins after the first turn gets it in the join reply.
    const host2 = await account(), guest2 = await account();
    const room2 = await made(host2);
    const first = await turn(room2, host2, a);
    expect((await redoV2(`/v2/rooms/${room2.room_id}`, host2)).replace_open).toBe(false);
    await join(room2, guest2);
    expect(first.room.a_turn_id).not.toBeNull();
    const now = await json<RoomSnapshotV2>(call(`/v2/rooms/${room2.room_id}`, "GET", host2));
    const refused = await call(`/v2/rooms/${room2.room_id}/turns`, "POST", host2, turnBody(now, a, { replaces: a.recording_hash }));
    expect(refused.status).toBe(409);
    expect(await refused.json()).toMatchObject({ error: { code: "turn_already_seen" } });
  });

  it("refuses a second turn, a wrong hash and the friend, and exports and restores the replaced room", async () => {
    const { host, guest, room, path } = await played();
    await turn(room, host, a, { replaces: "0".repeat(64) }, 409);
    const replaced = await turn(room, host, a, { replaces: a.recording_hash });
    await turn(replaced.room, guest, b, { checkpoint: middle, replaces: a.recording_hash }, 409);
    const source = env.ROOMS_V2.getByName(room.room_id);
    await json(call(path, "GET", guest));
    const archive = unwrap(await source.exportSnapshot("d".repeat(40)));
    expect(JSON.parse(archive).payload.tables.some((table: { name: string }) => table.name === "redo_seen")).toBe(false);
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    unwrap(await target.restoreSnapshot(archive, room.room_id));
    expect(unwrap(await target.snapshot(host.player_id))).toMatchObject({ branch: replaced.room.branch, a_turn_id: replaced.room.a_turn_id });
  });
});

describe("cost on the Free plan", () => {
  it("meters the rows each new step reads and writes in the room", async () => {
    const { host, guest, room, path } = await played();
    const rows = await meter(room.room_id);
    const known = { "X-AfterYou-Known-Room": `${room.revision}.${room.branch}` };
    const pollV1 = await rows(() => json(call(path, "GET", host, undefined, { "X-AfterYou-Poll-Redo": "1", ...known })));
    const pollV2 = await rows(() => json(call(path, "GET", host, undefined, { ...V2, ...known })));
    const replace = await rows(() => turn(room, host, a, { replaces: a.recording_hash }));
    const replaced = await json<RoomSnapshotV2>(call(path, "GET", host));
    const firstRead = await rows(() => json(call(path, "GET", guest)));
    const secondRead = await rows(() => json(call(path, "GET", guest)));
    const source = startOver(replaced, guest, host);
    const ask = await rows(() => json(call(path + "/redo", "POST", guest, { action: "request", source })));
    const over = (await redoV2(path, host)).start_over!;
    const agree = await rows(() => json(call(path + "/fork", "POST", host, { base_revision: replaced.revision, branch: replaced.branch, stage_index: 0, idempotency_key: key(), redo_request_id: over.request_id })));
    // A plain first turn on the new branch, for comparison with the replacement.
    const fresh = await json<RoomSnapshotV2>(call(path, "GET", host));
    const plain = await rows(() => turn(fresh, host, a));
    // The friend's read of a later first turn, once the table exists: one row.
    const laterRead = await rows(() => json(call(path, "GET", guest)));
    console.log("ROWS", JSON.stringify({ pollV1, pollV2, firstRead, secondRead, laterRead, replace, plain, ask, agree }));
    expect(pollV2.written).toBe(0);
    expect(secondRead.written).toBe(0);
    expect(laterRead.written).toBe(1);
    expect(firstRead.written).toBeLessThanOrEqual(3);
    expect(replace.written - plain.written).toBeLessThanOrEqual(1);
  });
});

describe("start over", () => {
  it("asks, shows only to version 2 phones, and the friend's agreement takes the room back to the first stage", async () => {
    const { host, guest, room, path } = await played();
    const source = startOver(room, guest, host);
    const asked = await json<RedoState>(call(path + "/redo", "POST", guest, { action: "request", source }));
    expect(asked.request).toMatchObject({ status: "pending", source });
    expect(await json(call(path + "/redo", "POST", guest, { action: "request", source }))).toEqual(asked);
    // Version 1 phones see no request, on the room and on Home; a redo request waits for it.
    expect((await json<RedoState>(call(path + "/redo", "GET", host))).request).toBeNull();
    expect(await inboxRedo(host, room.room_id, "1")).toBeUndefined();
    expect(await inboxRedo(host, room.room_id, "2")).toBe("start_over_asked_you");
    expect(await inboxRedo(guest, room.room_id, "2")).toBe("start_over_you_asked");
    const turnSource = (await json<RedoState>(call(path + "/redo", "GET", guest))).source;
    await json(call(path + "/redo", "POST", guest, { action: "request", source: turnSource }), 409);
    expect((await redoV2(path, host)).start_over).toMatchObject({ status: "pending", request_id: asked.request!.request_id });
    const body = { base_revision: room.revision, branch: room.branch, stage_index: 0, idempotency_key: key(), redo_request_id: asked.request!.request_id };
    // Only the friend asked may agree.
    await json(call(path + "/fork", "POST", guest, body), 409);
    const agreed = await json<MutationV2>(call(path + "/fork", "POST", host, body));
    expect(agreed.room).toMatchObject({ branch: room.branch + 1, stage_index: 0, active_role: "a", a_turn_id: null, host_id: host.player_id, guest_id: guest.player_id });
    expect(await json(call(path + "/fork", "POST", host, body))).toEqual(agreed);
    // The old run is gone: only the agreement's own receipt stays, and the room still exports and restores.
    await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_instance, ctx) => {
      const count = (table: string) => ctx.storage.sql.exec<{ n: number }>(`SELECT COUNT(*) AS n FROM ${table}`).one().n;
      expect({ turns: count("turns"), pairs: count("pairs"), operations: count("operations"), redo: count("redo_control") }).toEqual({ turns: 0, pairs: 0, operations: 1, redo: 0 });
    });
    const archive = unwrap(await env.ROOMS_V2.getByName(room.room_id).exportSnapshot("d".repeat(40)));
    unwrap(await env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()).restoreSnapshot(archive, room.room_id));
    // Both phones play on from the first stage; a turn sent against the old run is refused.
    await turn(room, host, a, {}, 409);
    const again = await turn(agreed.room, host, a);
    expect(again.room).toMatchObject({ stage_index: 0, active_role: "b" });
    expect((await redoV2(path, guest)).start_over).toBeNull();
    expect(await inboxRedo(host, room.room_id, "2")).toBeUndefined();
  });

  it("declines, cancels, and is refused with nothing to undo", async () => {
    const host = await account(), guest = await account();
    const room = await made(host);
    const joined = await join(room, guest);
    const path = `/v2/rooms/${room.room_id}`;
    await json(call(path + "/redo", "POST", guest, { action: "request", source: startOver(joined, guest, host) }), 409);
    const first = await turn(joined, host, a);
    const source = startOver(first.room, host, guest);
    await json(call(path + "/redo", "POST", host, { action: "request", source }));
    await json(call(path + "/redo", "POST", host, { action: "decline", source }), 403);
    const declined = await json<RedoState>(call(path + "/redo", "POST", guest, { action: "decline", source }));
    expect(declined.request?.status).toBe("declined");
    expect(await inboxRedo(host, room.room_id, "2")).toBe("start_over_kept");
    await json(call(path + "/fork", "POST", guest, { base_revision: first.room.revision, branch: first.room.branch, stage_index: 0, idempotency_key: key(), redo_request_id: declined.request!.request_id }), 409);
  });
});
