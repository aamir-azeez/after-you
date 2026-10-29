import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Inbox = { schema_version: 1; rooms: { room_id: string; status: string; api_version: number }[] };
const key = () => crypto.randomUUID();
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env };
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + ++address, ...headers,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body)
  }), configured);
}
async function create(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
async function newRoom(host: Account): Promise<RoomSnapshotV2> {
  const result = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  expect(result.status).toBe(200); return result.json<RoomSnapshotV2>();
}
async function pair() {
  const host = await create(), guest = await create(), room = await newRoom(host);
  const result = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }); expect(result.status).toBe(200);
  return { host, guest, room: await result.json<RoomSnapshotV2>() };
}
async function submit(room: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  const result = await call(`/v2/rooms/${room.room_id}/turns`, "POST", account,
    { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint === undefined ? {} : { checkpoint }) });
  expect(result.status).toBe(200); return result.json<MutationV2>();
}
async function completed() {
  const { host, guest, room } = await pair();
  const a = await submit(room, host, firstA);
  const b = await submit(a.room, guest, firstB, middle);
  const c = await submit(b.room, guest, secondA);
  const d = await submit(c.room, host, secondB, final);
  expect(d.room.active_role).toBe("complete");
  return { host, guest, room: d.room };
}
const leave = (version: 1 | 2, roomId: string, account: Account, body: unknown = { schema_version: 1 }) => call(`/v${version}/rooms/${roomId}/leave`, "POST", account, body);
const inbox = async (account: Account, closed = false) =>
  (await call("/v1/room-inbox", "GET", account, undefined, closed ? { "X-AfterYou-Room-Inbox": "2" } : {})).json<Inbox>();
const CLOSE_IF = { "X-AfterYou-Close-If": "in-play" };
const errorCode = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
afterEach(async () => { await reset(); });

describe("leaving and closing rooms", () => {
  it("refuses to quietly leave a room that is still in play; closing it ends it for both", async () => {
    const lonely = await create(), waiting = await newRoom(lonely);
    const refused = await leave(2, waiting.room_id, lonely);
    expect(refused.status).toBe(409); expect(await errorCode(refused)).toBe("room_not_closed");
    expect((await env.PLAYERS.getByName(lonely.player_id).listRooms()).map(link => link.room_id)).toEqual([waiting.room_id]);

    const { host, guest, room } = await pair();
    expect((await leave(2, room.room_id, guest)).status).toBe(409);
    expect((await call(`/v2/rooms/${room.room_id}`, "DELETE", host, undefined, CLOSE_IF)).status).toBe(200);
    expect((await inbox(host)).rooms).toEqual([]);
    // Older clients keep the exact status list they validate; newer ones see it closed.
    expect((await inbox(guest)).rooms).toMatchObject([{ room_id: room.room_id, status: "unavailable" }]);
    expect((await inbox(guest, true)).rooms).toMatchObject([{ room_id: room.room_id, status: "closed", api_version: 2 }]);
    expect((await call(`/v2/rooms/${room.room_id}`, "DELETE", guest)).status).toBe(404);
    const removed = await leave(2, room.room_id, guest);
    expect(removed.status).toBe(200); expect(await removed.json()).toEqual({ schema_version: 1, removed: true });
    expect((await inbox(guest, true)).rooms).toEqual([]);
    expect((await leave(2, room.room_id, guest)).status).toBe(200);
  });

  it("keeps a finished room linked for both, and a stale Close cannot erase its replays", async () => {
    const { host, guest, room } = await completed();
    // Still a member of finished play: the link stays so identity deletion can erase it.
    const kept = await leave(2, room.room_id, guest);
    expect(kept.status).toBe(409); expect(await errorCode(kept)).toBe("room_not_closed");
    const finished = await call(`/v2/rooms/${room.room_id}`, "DELETE", guest, undefined, CLOSE_IF);
    expect(finished.status).toBe(409); expect(await errorCode(finished)).toBe("room_finished");
    expect((await inbox(guest, true)).rooms).toMatchObject([{ room_id: room.room_id, status: "completed" }]);
    expect((await inbox(host, true)).rooms).toMatchObject([{ room_id: room.room_id, status: "completed" }]);
    const collection = await call(`/v2/rooms/${room.room_id}/collection`, "GET", host);
    expect(collection.status).toBe(200);
    expect((await collection.json<{ pairs: unknown[] }>()).pairs).toHaveLength(2);
  });

  it("closes a legacy room for both and shows it closed only to newer clients", async () => {
    const host = await create(), guest = await create();
    const made = await (await call("/v1/rooms", "POST", host, { idempotency_key: key() })).json<{ room_id: string; invite_code: string }>();
    expect((await call("/v1/rooms/join", "POST", guest, { invite_code: made.invite_code })).status).toBe(200);
    expect((await leave(1, made.room_id, guest)).status).toBe(409);
    expect((await call(`/v1/rooms/${made.room_id}`, "DELETE", guest, undefined, CLOSE_IF)).status).toBe(200);
    expect((await inbox(host)).rooms).toMatchObject([{ room_id: made.room_id, status: "unavailable", api_version: 1 }]);
    expect((await inbox(host, true)).rooms).toMatchObject([{ room_id: made.room_id, status: "closed", api_version: 1 }]);
    expect((await leave(1, made.room_id, host)).status).toBe(200);
    expect((await inbox(host, true)).rooms).toEqual([]);
  });

  it("works for legacy rooms, never touches the other link version, and validates its request", async () => {
    const host = await create();
    const made = await call("/v1/rooms", "POST", host, { idempotency_key: key() });
    expect(made.status).toBe(200);
    const legacy = await made.json<{ room_id: string }>();
    expect((await leave(1, legacy.room_id, host)).status).toBe(409);
    // Old clients send no close-if header and keep the original DELETE.
    expect((await call(`/v1/rooms/${legacy.room_id}`, "DELETE", host)).status).toBe(200);
    expect((await leave(1, legacy.room_id, host)).status).toBe(200);
    expect((await leave(1, legacy.room_id, host, { schema_version: 2 })).status).toBe(400);
    expect((await leave(1, legacy.room_id, host, { schema_version: 1, extra: true })).status).toBe(400);
    expect((await call(`/v1/rooms/${legacy.room_id}/leave`, "GET", host)).status).toBe(405);
    expect((await call(`/v2/rooms/${legacy.room_id}/leave/extra`, "POST", host, { schema_version: 1 })).status).toBe(405);
    expect((await call(`/v2/rooms/${legacy.room_id}/leave`, "POST", undefined, { schema_version: 1 })).status).toBe(401);
    // A link of the other version is never touched.
    const relay = await newRoom(host);
    const finished = await env.PLAYERS.getByName(host.player_id).listRooms();
    expect((await leave(1, relay.room_id, host)).status).toBe(200);
    expect(await env.PLAYERS.getByName(host.player_id).listRooms()).toEqual(finished);
  });

  it("lets a stranger learn nothing and change nothing", async () => {
    const { host, room } = await pair(), stranger = await create();
    expect((await leave(2, room.room_id, stranger)).status).toBe(200);
    expect((await inbox(host)).rooms).toMatchObject([{ room_id: room.room_id }]);
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", host)).status).toBe(200);
  });
});
