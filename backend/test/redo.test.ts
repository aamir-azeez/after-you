import { env } from "cloudflare:workers";
import { reset, evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { randomToken, type Outcome, type RoomSnapshot } from "../src/protocol";
import { chapter, RELAY_KEY } from "../src/v2/protocol";
import type { RoomSnapshotV2, MutationV2 } from "../src/v2/room";
import type { RedoState } from "../src/redo-control";
import a from "../../game/tests/fixtures/v2/relay-a.json";
import b from "../../game/tests/fixtures/v2/relay-b.json";
import gardenA from "../../game/tests/fixtures/v2/garden-a.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import legacyA from "../../game/tests/fixtures/first-light-a.json";
import legacyB from "../../game/tests/fixtures/first-light-b.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown) {
  const configured = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true" });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: {
    "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + ++address,
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {})
  }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function json<T>(response: Promise<Response>, status = 200): Promise<T> { const result = await response; expect(result.status).toBe(status); return result.json<T>(); }
const account = () => json<Account>(call("/v1/identity", "POST", undefined, {}), 201);
const key = () => crypto.randomUUID();
function unwrap<T>(value: Outcome<T>): T { if (!value.ok) throw new Error(value.code); return value.value; }
async function pairV2() {
  const host = await account(), guest = await account();
  // Keep the old fixture protocol covered even when newer comfort rules become
  // the creation default; existing accepted recordings must stay reproducible.
  const version = chapter(RELAY_KEY).simulation_version;
  const room = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { idempotency_key: key(), ...RELAY_KEY, ...(version === 2 ? {} : { simulation_version: 2 }) }));
  const joined = await json<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: [2, 4, 5, 6, 7, 8] }));
  const accepted = await turnV2(joined, host, a);
  return { host, guest, room: accepted.room, path: `/v2/rooms/${room.room_id}` };
}
function turnV2(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown) {
  return json<MutationV2>(call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) }));
}
async function request(path: string, second: Account) {
  const state = await json<RedoState>(call(path + "/redo", "GET", second));
  expect(state.source).not.toBeNull();
  return json<RedoState>(call(path + "/redo", "POST", second, { action: "request", source: state.source }));
}
const acceptance = (room: RoomSnapshotV2, state: RedoState) => ({ base_revision: room.revision, branch: room.branch, stage_index: room.stage_index, idempotency_key: key(), redo_request_id: state.request!.request_id });
async function pairLegacy() {
  const host = await account(), guest = await account();
  const made = await json<RoomSnapshot>(call("/v1/rooms", "POST", host, { idempotency_key: key() }));
  const joined = await json<RoomSnapshot>(call("/v1/rooms/join", "POST", guest, { invite_code: made.invite_code }));
  const path = `/v1/rooms/${made.room_id}`;
  const room = await json<RoomSnapshot>(call(path + "/turns", "POST", host, { base_revision: joined.revision, idempotency_key: key(), recording: legacyA }));
  return { host, guest, room, path };
}
afterEach(async () => { await reset(); });

describe("partner redo requests", () => {
  it("keeps a request advisory, restores it after eviction, and requires the first player's consent", async () => {
    const { host, guest, room, path } = await pairV2();
    const offered = await json<RedoState>(call(path + "/redo", "GET", guest));
    await json(call(path + "/redo", "POST", host, { action: "request", source: offered.source }), 403);
    await json(call(path + "/redo", "GET", await account()), 404);
    const requested = await request(path, guest);
    expect(requested.request?.status).toBe("pending");
    expect(await json(call(path + "/redo", "POST", guest, { action: "request", source: requested.source }))).toEqual(requested);
    expect(await json(call(path, "GET", guest))).toMatchObject({ revision: room.revision, branch: room.branch, a_turn_id: room.a_turn_id });
    await evictDurableObject(env.ROOMS_V2.getByName(room.room_id));
    expect(await json(call(path + "/redo", "GET", host))).toEqual(requested);
    const body = acceptance(room, requested);
    await json(call(path + "/fork", "POST", guest, body), 409);
    const result = await json<MutationV2>(call(path + "/fork", "POST", host, body));
    expect(result.room).toMatchObject({ branch: room.branch + 1, stage_index: room.stage_index, active_role: "a", a_turn_id: null });
    expect(result.room.checkpoint).toEqual(room.checkpoint);
    expect(await json(call(path + "/fork", "POST", host, body))).toEqual(result);
    await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_instance, ctx) => {
      expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM turns").one().n).toBe(1);
      expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM redo_control").one().n).toBe(1);
    });
    const rerecorded = await turnV2(result.room, host, a);
    const completed = await turnV2(rerecorded.room, guest, b, middle);
    expect(completed.room.stage_index).toBe(1);
  });

  it("never rewinds a successful second turn that won the race against consent", async () => {
    const { host, guest, room, path } = await pairV2();
    const requested = await request(path, guest);
    const completed = await turnV2(room, guest, b, middle);
    await json(call(path + "/fork", "POST", host, acceptance(room, requested)), 409);
    expect(await json(call(path, "GET", host))).toMatchObject({ revision: completed.room.revision, stage_index: 1 });
    expect(await json(call(path + "/redo", "GET", host))).toEqual({ schema_version: 1, source: null, request: null });
    const next = await turnV2(completed.room, guest, gardenA);
    const nextRequest = await request(path, host);
    expect(nextRequest.source?.first_player_id).toBe(guest.player_id);
    expect(nextRequest.source?.second_player_id).toBe(host.player_id);
    await json(call(path + "/fork", "POST", host, acceptance(next.room, nextRequest)), 409);
    const redone = await json<MutationV2>(call(path + "/fork", "POST", guest, acceptance(next.room, nextRequest)));
    expect(redone.room.completed_pair_ids).toEqual(completed.room.completed_pair_ids);
    expect(redone.room.checkpoint).toEqual(middle);
  });

  it("makes cancellation and declining idempotent without repeating the same request", async () => {
    const { host, guest, room, path } = await pairLegacy();
    const state = await request(path, guest);
    const declined = await json<RedoState>(call(path + "/redo", "POST", host, { action: "decline", source: state.source }));
    expect(declined.request?.status).toBe("declined");
    expect(await request(path, guest)).toEqual(declined);
    expect(await json(call(path, "GET", guest))).toMatchObject({ revision: room.revision, attempt: room.attempt });
    await json(call(path + "/fork", "POST", host, { base_revision: room.revision, idempotency_key: key(), redo_request_id: state.request!.request_id }), 409);
    const forked = await json<RoomSnapshot>(call(path + "/fork", "POST", host, { base_revision: room.revision, idempotency_key: key() }));
    await json(call(path + "/turns", "POST", host, { base_revision: forked.revision, idempotency_key: key(), recording: legacyA }));
    const again = await request(path, guest);
    const cancelled = await json<RedoState>(call(path + "/redo", "POST", guest, { action: "cancel", source: again.source }));
    expect(cancelled.request?.status).toBe("cancelled");
    expect(await json(call(path + "/redo", "POST", guest, { action: "cancel", source: again.source }))).toEqual(cancelled);
  });

  it("preserves legacy accepted recordings and reconciles a lost acceptance response", async () => {
    const { host, guest, room, path } = await pairLegacy();
    const state = await request(path, guest);
    const body = { base_revision: room.revision, idempotency_key: key(), redo_request_id: state.request!.request_id };
    const forked = await json<RoomSnapshot>(call(path + "/fork", "POST", host, body));
    expect(forked).toMatchObject({ attempt: room.attempt + 1, active_role: "a", recordings: { a: null, b: null } });
    await evictDurableObject(env.ROOMS.getByName(room.room_id));
    expect(await json(call(path + "/fork", "POST", host, body))).toEqual(forked);
    const first = await json<RoomSnapshot>(call(path + "/turns", "POST", host, { base_revision: forked.revision, idempotency_key: key(), recording: legacyA }));
    const complete = await json<RoomSnapshot>(call(path + "/turns", "POST", guest, { base_revision: first.revision, idempotency_key: key(), recording: legacyB }));
    expect(complete.active_role).toBe("complete");
    await runInDurableObject(env.ROOMS.getByName(room.room_id), async (_instance, ctx) => {
      const archived = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM archive WHERE attempt=0").one().data);
      expect(archived.recordings.a).toEqual(legacyA);
    });
  });

  it("exports accepted history while deliberately clearing advisory requests on maintenance restore", async () => {
    for (const family of ["legacy", "relay"] as const) {
      const fixture = family === "legacy" ? await pairLegacy() : await pairV2();
      await request(fixture.path, fixture.guest);
      const namespace = family === "legacy" ? env.ROOMS : env.ROOMS_V2;
      const source = namespace.getByName(fixture.room.room_id);
      const archive = unwrap(await source.exportSnapshot("d".repeat(40)));
      expect(JSON.parse(archive).payload.tables.some((table: { name: string }) => table.name === "redo_control")).toBe(false);
      const target = namespace.get(namespace.newUniqueId());
      unwrap(await target.restoreSnapshot(archive, fixture.room.room_id));
      const state = unwrap(await target.redo(fixture.host.player_id));
      expect(state.request).toBeNull();
      expect(state.source?.a_hash).toBe(family === "legacy" ? legacyA.final_state_hash : a.recording_hash);
    }
  });

  it("rejects invented source turns and erases advisory state with the room", async () => {
    const { host, guest, room, path } = await pairV2();
    const state = await json<RedoState>(call(path + "/redo", "GET", guest));
    await json(call(path + "/redo", "POST", guest, { action: "request", source: { ...state.source, a_hash: "0".repeat(64) } }), 409);
    await request(path, guest);
    await json(call(path, "DELETE", host));
    await json(call(path + "/redo", "GET", guest), 404);
    await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_instance, ctx) => {
      expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM redo_control").one().n).toBe(0);
    });
  });

  it.each(["legacy", "relay"] as const)("reauthorizes %s request and consent after a held body outlives identity recovery", async family => {
    const fixture = family === "legacy" ? await pairLegacy() : await pairV2();
    const source = await json<RedoState>(call(fixture.path + "/redo", "GET", fixture.guest));
    const held = (path: string, owner: Account, body: unknown) => {
      let controller!: ReadableStreamDefaultController<Uint8Array>;
      let reading!: () => void;
      const bodyRead = new Promise<void>(resolve => { reading = resolve; });
      const stream = new ReadableStream<Uint8Array>({ start(value) { controller = value; }, pull() { reading(); } }, { highWaterMark: 0 });
      const configured = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true" });
      const result = worker.fetch(new Request("https://after-you.test" + path, { method: "POST", body: stream, headers: {
        "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + ++address,
        "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token
      } }), configured);
      return { result, bodyRead, release() { controller.enqueue(new TextEncoder().encode(JSON.stringify(body))); controller.close(); } };
    };
    const rotate = async (owner: Account): Promise<Account> => {
      const next = { ...owner, device_token: randomToken(), recovery_code: randomToken() };
      await json(call("/v1/identity/recover", "POST", undefined, { player_id: owner.player_id, recovery_code: owner.recovery_code,
        next_device_token: next.device_token, next_recovery_code: next.recovery_code, idempotency_key: key() }));
      return next;
    };
    const requesting = held(fixture.path + "/redo", fixture.guest, { action: "request", source: source.source });
    await requesting.bodyRead;
    const guest = await rotate(fixture.guest);
    requesting.release();
    expect((await requesting.result).status).toBe(401);
    expect((await json<RedoState>(call(fixture.path + "/redo", "GET", guest))).request).toBeNull();

    const requested = await request(fixture.path, guest);
    const body = { base_revision: fixture.room.revision, idempotency_key: key(), redo_request_id: requested.request!.request_id,
      ...(family === "relay" ? { branch: (fixture.room as RoomSnapshotV2).branch, stage_index: (fixture.room as RoomSnapshotV2).stage_index } : {}) };
    const consenting = held(fixture.path + "/fork", fixture.host, body);
    await consenting.bodyRead;
    const host = await rotate(fixture.host);
    consenting.release();
    expect((await consenting.result).status).toBe(401);
    expect(await json(call(fixture.path, "GET", host))).toMatchObject({ revision: fixture.room.revision, active_role: "b" });
    expect((await json<RedoState>(call(fixture.path + "/redo", "GET", host))).request?.status).toBe("pending");
    // The accepted-receipt fast path must also honor a subsequent rotation.
    await json(call(fixture.path + "/fork", "POST", host, body));
    const reconciling = held(fixture.path + "/fork", host, body);
    await reconciling.bodyRead;
    await rotate(host);
    reconciling.release();
    expect((await reconciling.result).status).toBe(401);
  });
});
