import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { wishingWell } from "../src/v2/protocol-cooperative";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import type { RoomInboxEntry } from "../src/room-inbox";
import aheadA from "../../game/tests/fixtures/cooperative/go-on-ahead-a.json";
import aheadB from "../../game/tests/fixtures/cooperative/go-on-ahead-b.json";
import middle from "../../game/tests/fixtures/cooperative/go-on-ahead-checkpoint.json";
import backA from "../../game/tests/fixtures/cooperative/back-for-you-a.json";
import backB from "../../game/tests/fixtures/cooperative/back-for-you-b.json";
import final from "../../game/tests/fixtures/cooperative/the-wishing-well-final-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
const key = () => crypto.randomUUID();
const ON = { WISHING_WELL_CHAPTER_ENABLED: "true", REPLAY_TRANSFER_ENABLED: "true" };
const NEW_CLIENT = [2, 4, 5, 6, 7, 8, 9];
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true", ...ON });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.7." + (++requestNo % 250), ...headers,
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function submit(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  const body = { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
  const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, body); expect(response.status).toBe(200); return response.json<MutationV2>();
}
async function inbox(player: Account): Promise<RoomInboxEntry[]> {
  const response = await call("/v1/room-inbox", "GET", player, undefined, { "X-AfterYou-Room-Inbox": "2" }); expect(response.status).toBe(200);
  return (await response.json<{ rooms: RoomInboxEntry[] }>()).rooms;
}
afterEach(async () => { await reset(); });

describe("a finished room whose replay both players saved", () => {
  it("stays in both inboxes as the finished chapter after the server compacts it", async () => {
    const host = await account(), guest = await account();
    const created = await (await call("/v2/rooms", "POST", host, { ...wishingWell.key, idempotency_key: key() })).json<RoomSnapshotV2>();
    const room = await (await call("/v2/rooms/join", "POST", guest, { invite_code: created.invite_code, supported_simulation_versions: NEW_CLIENT })).json<RoomSnapshotV2>();
    const a = await submit(room, host, aheadA), b = await submit(a.room, guest, aheadB, middle);
    const c = await submit(b.room, guest, backA), d = await submit(c.room, host, backB, final);
    expect(d.room).toMatchObject({ active_role: "complete" });
    const finished = { room_id: room.room_id, family: "relay", api_version: 2, chapter: { id: "the-wishing-well", version: 1 }, status: "completed" };
    for (const player of [host, guest]) expect(await inbox(player)).toEqual([expect.objectContaining(finished)]);
    // Each phone downloads the complete replay and acknowledges it, as on leaving the finished room.
    for (const player of [host, guest]) {
      const offered = await (await call(`/v2/rooms/${room.room_id}/replay-transfer`, "GET", player)).json<{ manifest: { epoch: number; archive_hash: string } }>();
      const ack = await call(`/v2/rooms/${room.room_id}/replay-transfer/ack`, "POST", player, { schema_version: 1, epoch: offered.manifest.epoch, archive_hash: offered.manifest.archive_hash });
      expect(ack.status).toBe(200);
    }
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", host)).status).toBe(410);
    for (const player of [host, guest]) {
      const rooms = await inbox(player);
      expect(rooms).toEqual([expect.objectContaining({ ...finished, membership: { host_id: host.player_id, guest_id: guest.player_id, you_are_host: player === host } })]);
      expect(rooms[0].activity_at).toEqual(expect.any(String));
    }
  });
});
