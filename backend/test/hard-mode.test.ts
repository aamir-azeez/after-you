import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { type Outcome } from "../src/protocol";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { HARD_FAILURES, HARD_LOOKUP, HARD_RUN, MAX_KEPT, type Failure, type HardFailures } from "../src/v2/hard-mode";
import type { RoomV2 } from "../src/v2/room";
import { countingEnv } from "./meter";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Reset = { room: RoomSnapshotV2; failure: Failure };
const key = () => crypto.randomUUID(), LOOKUP = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
const ON = { HARD_MODE_ENABLED: "true" }, ASK = { "X-AfterYou-Hard-Mode": "1" };
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string> = {}, headers: Record<string, string> = {}, base: Env = env): Promise<Response> {
  const configured: Env = { ...base };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", ...vars });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
const errorCode = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
async function create(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
async function submit(room: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown, extra: Record<string, unknown> = {}): Promise<Response> {
  return call(`/v2/rooms/${room.room_id}/turns`, "POST", account, { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint === undefined ? {} : { checkpoint }), ...extra });
}
async function played(room: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown): Promise<RoomSnapshotV2> {
  const result = await submit(room, account, recording, checkpoint); expect(result.status).toBe(200); return (await result.json<MutationV2>()).room;
}
async function hardRoom(vars = ON): Promise<{ host: Account; guest: Account; room: RoomSnapshotV2 }> {
  const host = await create(), guest = await create();
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH, mode: "hard" }, vars);
  expect(made.status).toBe(200);
  const join = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }, {}, ASK); expect(join.status).toBe(200);
  return { host, guest, room: await join.json<RoomSnapshotV2>() };
}
const resetBody = (room: RoomSnapshotV2, reason = "failed_turn", slip?: unknown) =>
  ({ base_revision: room.revision, branch: room.branch, idempotency_key: key(), reason, stage_index: room.stage_index, role: room.active_role, ...(slip === undefined ? {} : { slip }) });
const sendReset = (room: RoomSnapshotV2, account: Account, body: unknown, vars: Record<string, string> = ON) => call(`/v2/rooms/${room.room_id}/hard-reset`, "POST", account, body, vars);
async function slipped(room: RoomSnapshotV2, account: Account, reason = "failed_turn", slip?: unknown): Promise<Reset> {
  const result = await sendReset(room, account, resetBody(room, reason, slip)); expect(result.status).toBe(200); return result.json<Reset>();
}
const kept = async (roomId: string, account: Account, vars: Record<string, string> = ON, query = "") => call(`/v2/rooms/${roomId}/hard${query}`, "GET", account, undefined, vars);
const tables = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_instance, state) =>
  [HARD_RUN.name, HARD_FAILURES.name].filter(name => state.storage.sql.exec(LOOKUP, name).toArray().length > 0));

afterEach(async () => { await reset(); });

describe("hard rooms", () => {
  it("are advertised only to clients that ask, and only while the flag is on", async () => {
    const host = await create();
    expect(await (await call("/v2/capabilities", "GET", host, undefined, ON)).json()).not.toHaveProperty("hard_mode_version");
    expect(await (await call("/v2/capabilities", "GET", host, undefined, {}, ASK)).json()).not.toHaveProperty("hard_mode_version");
    expect(await (await call("/v2/capabilities", "GET", host, undefined, ON, ASK)).json()).toMatchObject({ hard_mode_version: 1 });
  });

  it("are created only while the flag is on, and an ordinary room's storage and view stay as they were", async () => {
    const host = await create(), guest = await create();
    const off = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH, mode: "hard" });
    expect(off.status).toBe(503); expect(await errorCode(off)).toBe("hard_mode_disabled");
    const odd = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH, mode: "easy" }, ON);
    expect(odd.status).toBe(422); expect(await errorCode(odd)).toBe("unsupported_room_mode");
    const plain = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH }, ON);
    const room = await plain.json<RoomSnapshotV2>();
    expect(room).not.toHaveProperty("hard");
    expect(await tables(room.room_id)).toEqual([]);
    // An ordinary room needs no hard header to join, and its routes stay inert.
    const join = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }); expect(join.status).toBe(200);
    for (const [vars, status, code] of [[{}, 503, "hard_mode_disabled"], [ON, 409, "not_hard_room"]] as const) {
      const read = await kept(room.room_id, host, vars); expect(read.status).toBe(status); expect(await errorCode(read)).toBe(code);
      const reset = await sendReset(room, host, resetBody(await join.clone().json<RoomSnapshotV2>()), vars); expect(reset.status).toBe(status);
    }
    expect(await tables(room.room_id)).toEqual([]);
  });

  it("start with an empty run, and admit only phones that play hard rooms", async () => {
    const host = await create(), guest = await create();
    const idempotency_key = key();
    const made = await call("/v2/rooms", "POST", host, { idempotency_key, level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH, mode: "hard" }, ON);
    const room = await made.json<RoomSnapshotV2>();
    expect(room.hard).toEqual({ schema_version: 1, failures: 0, over: false, last: null });
    // A lost answer resent byte for byte returns the same room.
    const again = await call("/v2/rooms", "POST", host, { idempotency_key, level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH, mode: "hard" }, ON);
    expect((await again.json<RoomSnapshotV2>()).room_id).toBe(room.room_id);
    const old = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code });
    expect(old.status).toBe(409); expect(await errorCode(old)).toBe("hard_mode_client_required");
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }, {}, ASK);
    expect(joined.status).toBe(200); expect((await joined.json<RoomSnapshotV2>()).hard?.failures).toBe(0);
  });

  it("go back to the first stage for both when the player on their turn slips, and keep the slip", async () => {
    const { host, guest, room } = await hardRoom();
    const first = await played(room, host, firstA);
    // Only the player whose turn it is can slip.
    const wrong = await sendReset(first, host, resetBody(first));
    expect(wrong.status).toBe(409); expect(await errorCode(wrong)).toBe("hard_not_your_turn");
    const body = resetBody(first, "drowned", firstB);
    const result = await sendReset(first, guest, body); expect(result.status).toBe(200);
    const { room: after, failure } = await result.json<Reset>();
    expect(after).toMatchObject({ branch: 1, stage_index: 0, a_turn_id: null, revision: first.revision + 1, active_role: "a", active_player_id: host.player_id });
    expect(after.hard).toEqual({ schema_version: 1, failures: 1, over: false, last: failure });
    expect(failure).toMatchObject({ by: guest.player_id, stage_index: 0, role: "b", reason: "drowned" });
    // A resend answers the same, once; a reused key with another body is refused.
    const resent = await sendReset(first, guest, body); expect(resent.status).toBe(200);
    expect((await resent.json<Reset>()).failure).toEqual(failure);
    const reused = await sendReset(first, guest, { ...body, reason: "retry" }); expect(reused.status).toBe(409); expect(await errorCode(reused)).toBe("idempotency_key_reused");
    // The host's poll shows who slipped; both read the slip with its memory.
    const poll = await (await call(`/v2/rooms/${room.room_id}`, "GET", host)).json<RoomSnapshotV2>();
    expect(poll.hard?.last).toEqual(failure);
    for (const member of [host, guest]) {
      const read = await kept(room.room_id, member); expect(read.status).toBe(200);
      const view = await read.json<HardFailures>();
      expect(view.failures).toBe(1);
      expect(view.list).toEqual([{ ...failure, number: 1, slip: { recording: firstB, checkpoint: first.checkpoint, prior: firstA } }]);
    }
    // A turn queued against the old run is refused as stale.
    const stale = await submit(first, guest, firstB, middle); expect(stale.status).toBe(409); expect(await errorCode(stale)).toBe("stale_revision");
    // The new run plays as any room does.
    const replayed = await played(after, host, firstA);
    expect(replayed.a_turn_id).toBe("t1-0-a");
  });

  it("keep a slip on the very first turn without a new branch, and drop a slip that does not fit the turn", async () => {
    const { host, room } = await hardRoom();
    const { room: after, failure } = await slipped(room, host, "retry", firstB);
    expect(after).toMatchObject({ branch: 0, stage_index: 0, revision: room.revision + 1 });
    expect(failure.role).toBe("a");
    const view = await (await kept(room.room_id, host)).json<HardFailures>();
    // firstB is a second turn: it cannot be this first turn's slip, so the reset is kept without it.
    expect(view.list[0].slip).toBeNull();
    const next = await slipped(after, host, "failed_turn", { not: "a recording" });
    expect(next.room.hard?.failures).toBe(2);
  });

  it("take only first tries, never redo, and nothing once the run is over", async () => {
    const { host, guest, room } = await hardRoom();
    const retried = await submit(room, host, firstA, undefined, { tries: 2 });
    expect(retried.status).toBe(409); expect(await errorCode(retried)).toBe("hard_run_retry");
    const first = await played(room, host, firstA);
    const fork = await call(`/v2/rooms/${room.room_id}/fork`, "POST", guest, { base_revision: first.revision, branch: first.branch, idempotency_key: key(), stage_index: 0 });
    expect(fork.status).toBe(409); expect(await errorCode(fork)).toBe("hard_run_no_redo");
    const redo = await call(`/v2/rooms/${room.room_id}/redo`, "POST", guest, { action: "request", source: { room_id: first.room_id, revision: first.revision, branch: first.branch, stage_index: 0, a_hash: firstA.recording_hash, first_player_id: host.player_id, second_player_id: guest.player_id } });
    expect(redo.status).toBe(409); expect(await errorCode(redo)).toBe("hard_run_no_redo");
    // A room with no space for another whole run keeps the slip and ends the run.
    await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_instance, state) => {
      const stored = JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data);
      stored.branch = 31; stored.a_turn_id = null; stored.revision += 1;
      state.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(stored));
    });
    const full = await (await call(`/v2/rooms/${room.room_id}`, "GET", host)).json<RoomSnapshotV2>();
    const second = await played(full, host, firstA);
    const { room: over } = await slipped(second, guest);
    expect(over.hard?.over).toBe(true);
    expect(over).toMatchObject({ branch: 31, a_turn_id: second.a_turn_id });
    // The friend's poll learns it; nothing more is played or reset there.
    const seen = await (await call(`/v2/rooms/${room.room_id}`, "GET", host, undefined, {}, { "X-AfterYou-Known-Room": `${second.revision}.${second.branch}` })).json<RoomSnapshotV2>();
    expect(seen.hard?.over).toBe(true);
    const late = await submit(over, guest, firstB, middle); expect(late.status).toBe(409); expect(await errorCode(late)).toBe("hard_run_over");
    const more = await sendReset(over, guest, resetBody(over)); expect(more.status).toBe(409); expect(await errorCode(more)).toBe("hard_run_over");
  });

  it("keep a first-turn slip without ending the run, even with no branch left", async () => {
    const { host, room } = await hardRoom();
    await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_instance, state) => {
      const stored = JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data);
      stored.branch = 31; stored.revision += 1;
      state.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(stored));
    });
    const full = await (await call(`/v2/rooms/${room.room_id}`, "GET", host)).json<RoomSnapshotV2>();
    // Nothing to undo needs no branch: the run goes on.
    const { room: after } = await slipped(full, host, "retry");
    expect(after.hard).toMatchObject({ failures: 1, over: false });
    expect(after).toMatchObject({ branch: 31, stage_index: 0 });
    expect((await played(after, host, firstA)).a_turn_id).toBe("t31-0-a");
  });

  it("answer a slip only to the room's members, for the turn being played", async () => {
    const { host, guest, room } = await hardRoom();
    const stranger = await create();
    for (const response of [await sendReset(room, stranger, resetBody(room)), await kept(room.room_id, stranger)]) {
      expect(response.status).toBe(404);
    }
    const first = await played(room, host, firstA);
    for (const body of [{ ...resetBody(first), stage_index: 1 }, { ...resetBody(first), role: "a" }]) {
      const result = await sendReset(first, guest, body); expect(result.status).toBe(409); expect(await errorCode(result)).toBe("stale_revision");
    }
    const odd = await kept(room.room_id, host, ON, "/x"); expect(odd.status).toBe(422); expect(await errorCode(odd)).toBe("invalid_since");
  });

  it("read only the slips a phone has not seen", async () => {
    const { host, guest, room } = await hardRoom();
    let current = room;
    for (let index = 0; index < 3; index++) current = (await slipped(current, host, "retry")).room;
    const view = await (await kept(room.room_id, guest, ON, "/2")).json<HardFailures>();
    expect(view.failures).toBe(3);
    expect(view.list.map(item => item.number)).toEqual([3]);
    expect((await (await kept(room.room_id, guest, ON, "/3")).json<HardFailures>()).list).toEqual([]);
    expect((await (await kept(room.room_id, guest)).json<HardFailures>()).list.map(item => item.number)).toEqual([1, 2, 3]);
  });

  it("keep only the newest slips, however many there are", async () => {
    const { host, room } = await hardRoom();
    let current = room;
    for (let index = 0; index < MAX_KEPT + 3; index++) current = (await slipped(current, host, "retry")).room;
    const view = await (await kept(room.room_id, host)).json<HardFailures>();
    expect(view.failures).toBe(MAX_KEPT + 3); expect(view.list).toHaveLength(MAX_KEPT);
    expect(view.list.map(item => item.number)).toEqual([4, 5, 6, 7, 8]);
    const rows = await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_instance, state) => state.storage.sql.exec("SELECT COUNT(*) AS n FROM hard_failures").one().n);
    expect(rows).toBe(MAX_KEPT);
  });

  it("finish as any room does, and keep working if the flag goes off", async () => {
    const { host, guest, room } = await hardRoom();
    let current = await played(room, host, firstA);
    current = await played(current, guest, firstB, middle);
    // The flag turned off part way: the hard room's slip is still kept.
    const { room: back } = await (await sendReset(current, guest, resetBody(current), {})).json<Reset>();
    expect(back).toMatchObject({ branch: 1, stage_index: 0 });
    expect((await kept(room.room_id, host, {})).status).toBe(200);
    current = await played(back, host, firstA);
    current = await played(current, guest, firstB, middle);
    current = await played(current, guest, secondA);
    current = await played(current, host, secondB, final);
    expect(current.active_role).toBe("complete");
    const done = await sendReset(current, host, resetBody({ ...current, active_role: "a", stage_index: 0 } as RoomSnapshotV2));
    expect(done.status).toBe(409); expect(await errorCode(done)).toBe("hard_run_complete");
  });

  it("cost one request and no more per slip, and nothing more per turn", async () => {
    const { host, guest, room } = await hardRoom();
    const counted = countingEnv(env);
    const turn = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording: firstA }, {}, {}, counted.env);
    expect(turn.status).toBe(200);
    const turnCalls = [...counted.calls];
    counted.calls.length = 0;
    const first = (await turn.json<MutationV2>()).room;
    const reset = await call(`/v2/rooms/${room.room_id}/hard-reset`, "POST", guest, resetBody(first), ON, {}, counted.env);
    expect(reset.status).toBe(200);
    // The same calls as an ordinary turn: authorize, interaction, the room's own write.
    expect(turnCalls.filter(name => name.startsWith("ROOMS_V2."))).toEqual(["ROOMS_V2.interactionAllowed", "ROOMS_V2.snapshot", "ROOMS_V2.commit"]);
    expect(counted.calls.filter(name => name.startsWith("ROOMS_V2."))).toEqual(["ROOMS_V2.interactionAllowed", "ROOMS_V2.hardReset"]);
  });

  it("cost a room's polls one table lookup per room object, then nothing, hard or not", async () => {
    for (const hard of [false, true]) {
      const host = await create();
      const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH, ...(hard ? { mode: "hard" } : {}) }, ON);
      const room = await made.json<RoomSnapshotV2>();
      const stub = env.ROOMS_V2.getByName(room.room_id);
      await evictDurableObject(stub);
      await runInDurableObject(stub, async (instance: RoomV2, ctx) => {
        const sql = ctx.storage.sql, exec = sql.exec.bind(sql);
        const seen: string[] = [];
        Object.defineProperty(sql, "exec", { configurable: true, value: (query: string, ...bindings: unknown[]) => { seen.push(query); return exec(query, ...bindings); } });
        const lookups = () => seen.filter(query => query === HARD_LOOKUP || query.includes("hard_run") || query.includes("hard_failures")).length;
        value(await instance.snapshot(host.player_id));
        expect(lookups()).toBe(hard ? 2 : 1);
        for (let round = 0; round < 3; round++) {
          seen.length = 0;
          value(await instance.snapshot(host.player_id));
          // An ordinary room reads nothing more; a hard room reads its one summary row per view.
          expect(lookups()).toBe(hard ? 1 : 0);
        }
      });
    }
  });

  it("are erased with the room and stay out of operator snapshots", async () => {
    const { host, guest, room } = await hardRoom();
    const first = await played(room, host, firstA);
    await slipped(first, guest, "drowned", firstB);
    const stub = env.ROOMS_V2.getByName(room.room_id);
    const archive = value(await stub.exportSnapshot("d".repeat(40)));
    expect(archive).not.toContain(HARD_RUN.name); expect(archive).not.toContain(HARD_FAILURES.name);
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await target.restoreSnapshot(archive, room.room_id)).toMatchObject({ ok: true });
    expect(await tables(room.room_id)).toEqual([HARD_RUN.name, HARD_FAILURES.name]);
    const erased = await call(`/v2/rooms/${room.room_id}`, "DELETE", host, undefined, {}, { "X-AfterYou-Close-If": "in-play" });
    expect(erased.status).toBe(200);
    expect(await tables(room.room_id)).toEqual([]);
  });
});
