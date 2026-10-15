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

// The Godot online scenario harness (game/tests/online_harness/fake_server.gd)
// stands in for this Worker. Each answer it gives the two phones is pinned
// here against the real routes, so the fake cannot drift from the service.

type Account = { player_id: string; device_token: string; recovery_code: string };
type Inbox = { schema_version: 1; rooms: { room_id: string; status: string; chapter: { id: string | null } }[] };
const key = () => crypto.randomUUID();
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", REPLAY_TRANSFER_ENABLED: "true" });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + ++address, ...headers,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body)
  }), configured);
}
async function identity(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
const createBody = (idempotency_key: string) => ({ idempotency_key, level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
async function host(account: Account, idempotency = key()): Promise<RoomSnapshotV2> {
  const result = await call("/v2/rooms", "POST", account, createBody(idempotency)); expect(result.status).toBe(200); return result.json<RoomSnapshotV2>();
}
const join = (account: Account, invite_code: string) => call("/v2/rooms/join", "POST", account, { invite_code });
const turn = (room: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown, idempotency = key(), base = room.revision) =>
  call(`/v2/rooms/${room.room_id}/turns`, "POST", account, { base_revision: base, branch: room.branch, idempotency_key: idempotency, recording, ...(checkpoint === undefined ? {} : { checkpoint }) });
async function accepted(response: Response): Promise<MutationV2> { expect(response.status).toBe(200); return response.json<MutationV2>(); }
const code = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
async function expectError(response: Promise<Response>, status: number, expected: string) {
  const result = await response; expect(result.status).toBe(status); expect(await code(result)).toBe(expected);
}
const inbox = async (account: Account) => (await call("/v1/room-inbox", "GET", account, undefined, { "X-AfterYou-Room-Inbox": "2" })).json<Inbox>();
afterEach(async () => { await reset(); });

describe("the harness server's contract", () => {
  it("joins: again by a member, a full room, a closed invitation, and the host's turn after a join", async () => {
    const owner = await identity(), friend = await identity(), stranger = await identity();
    const room = await host(owner);
    const joined = await join(friend, room.invite_code!); expect(joined.status).toBe(200);
    const again = await join(friend, room.invite_code!); expect(again.status).toBe(200);
    expect((await again.json<RoomSnapshotV2>()).invite_code).toBeUndefined();
    await expectError(join(stranger, room.invite_code!), 409, "room_full");
    // The host's first turn still based on revision 0 after the join is refused, then accepted on 1.
    await expectError(turn(room, owner, firstA), 409, "stale_revision");
    const fresh = await (await call(`/v2/rooms/${room.room_id}`, "GET", owner)).json<RoomSnapshotV2>();
    expect(fresh.revision).toBe(1);
    const same = key();
    const first = await accepted(await turn(fresh, owner, firstA, undefined, same));
    const repeat = await accepted(await turn(fresh, owner, firstA, undefined, same));
    expect(repeat.receipt).toEqual(first.receipt);
    await expectError(turn(fresh, owner, secondA, undefined, same), 409, "idempotency_key_reused");
    const lookup = await call(`/v2/rooms/${room.room_id}/operations/${same}`, "GET", owner);
    expect(lookup.status).toBe(200);
    await expectError(call(`/v2/rooms/${room.room_id}/operations/${key()}`, "GET", owner), 404, "operation_not_found");
    const redo = await call(`/v2/rooms/${room.room_id}/redo`, "GET", friend);
    expect(redo.status).toBe(200); expect(await redo.json()).toMatchObject({ schema_version: 1, request: null });
    const delivery = await call(`/v2/rooms/${room.room_id}/photos/t0-0-a/delivery`, "GET", friend);
    expect(delivery.status).toBe(200); expect(await delivery.json()).toMatchObject({ schema_version: 1, photo: null, available: false });
  });

  it("a room closed mid-turn: every request of the other member answers room_not_found, and its links settle", async () => {
    const owner = await identity(), friend = await identity();
    const idempotency = key();
    const room = await host(owner, idempotency);
    const joined = await (await join(friend, room.invite_code!)).json<RoomSnapshotV2>();
    const afterA = await accepted(await turn(joined, owner, firstA, undefined, key(), joined.revision));
    expect((await call(`/v2/rooms/${room.room_id}`, "DELETE", owner, undefined, { "X-AfterYou-Close-If": "in-play" })).status).toBe(200);
    await expectError(turn(afterA.room, friend, firstB, middle), 404, "room_not_found");
    await expectError(call(`/v2/rooms/${room.room_id}`, "GET", friend), 404, "room_not_found");
    await expectError(call(`/v2/rooms/${room.room_id}/operations/${key()}`, "GET", friend), 404, "room_not_found");
    await expectError(join(friend, room.invite_code!), 404, "invite_not_found");
    await expectError(call("/v2/rooms", "POST", owner, createBody(idempotency)), 410, "room_deleted");
    expect((await inbox(friend)).rooms).toMatchObject([{ room_id: room.room_id, status: "closed", chapter: { id: null } }]);
    expect((await inbox(owner)).rooms).toEqual([]);
    await expectError(call(`/v2/rooms/${room.room_id}`, "DELETE", friend), 404, "room_not_found");
    // Listing rooms drops the closed room's link, so the inbox forgets it too.
    expect((await (await call("/v2/rooms", "GET", friend)).json<{ rooms: unknown[] }>()).rooms).toEqual([]);
    expect((await inbox(friend)).rooms).toEqual([]);
    const resolved = await call("/v1/invitations/resolve", "POST", friend, { invite_code: room.invite_code });
    expect(await resolved.json()).toEqual({ schema_version: 1, family: "relay", api_version: 2 });
  });

  it("a finished room: kept by close-if, refused by leave, and read as replay_transferred once both phones saved it", async () => {
    const owner = await identity(), friend = await identity();
    const room = await host(owner);
    const joined = await (await join(friend, room.invite_code!)).json<RoomSnapshotV2>();
    const a = await accepted(await turn(joined, owner, firstA));
    const b = await accepted(await turn(a.room, friend, firstB, middle));
    const c = await accepted(await turn(b.room, friend, secondA));
    const d = await accepted(await turn(c.room, owner, secondB, final));
    expect(d.room.active_role).toBe("complete");
    expect((await inbox(friend)).rooms).toMatchObject([{ room_id: room.room_id, status: "completed" }]);
    await expectError(call(`/v2/rooms/${room.room_id}`, "DELETE", friend, undefined, { "X-AfterYou-Close-If": "in-play" }), 409, "room_finished");
    await expectError(call(`/v2/rooms/${room.room_id}/leave`, "POST", friend, { schema_version: 1 }), 409, "room_not_closed");
    const download = await call(`/v2/rooms/${room.room_id}/replay-transfer`, "GET", owner);
    expect(download.status).toBe(200);
    const transfer = await download.json<{ manifest: { epoch: number; archive_hash: string }; acked_player_ids: string[]; transferred: boolean; archive: unknown }>();
    expect(transfer.transferred).toBe(false); expect(transfer.archive).not.toBeNull();
    const ack = { schema_version: 1, epoch: transfer.manifest.epoch, archive_hash: transfer.manifest.archive_hash };
    expect((await (await call(`/v2/rooms/${room.room_id}/replay-transfer/ack`, "POST", owner, ack)).json<{ transferred: boolean }>()).transferred).toBe(false);
    expect((await (await call(`/v2/rooms/${room.room_id}/replay-transfer/ack`, "POST", friend, ack)).json<{ transferred: boolean }>()).transferred).toBe(true);
    await expectError(call(`/v2/rooms/${room.room_id}`, "GET", friend, undefined, { "X-AfterYou-Finished-Room": "2" }), 410, "replay_transferred");
    await expectError(call(`/v2/rooms/${room.room_id}`, "GET", friend, undefined, { "X-AfterYou-Finished-Room": "2", "X-AfterYou-Known-Room": `${d.room.revision}.${d.room.branch}` }), 410, "replay_transferred");
    await expectError(join(friend, room.invite_code!), 410, "replay_transferred");
    expect((await inbox(friend)).rooms).toMatchObject([{ room_id: room.room_id, status: "completed" }]);
    const listed = await (await call("/v2/rooms", "GET", owner)).json<{ rooms: { room_id: string; active_role: string; replay_transfer_version: number }[] }>();
    expect(listed.rooms).toMatchObject([{ room_id: room.room_id, active_role: "complete", replay_transfer_version: 1 }]);
    const kept = await call(`/v2/rooms/${room.room_id}/replay-transfer`, "GET", friend);
    expect(kept.status).toBe(200); expect((await kept.json<{ archive: unknown; transferred: boolean }>())).toMatchObject({ archive: null, transferred: true });
  });

  it("a room poll naming the revision and branch it holds answers unchanged until the room moves", async () => {
    const owner = await identity(), friend = await identity();
    const room = await host(owner), path = `/v2/rooms/${room.room_id}`;
    const joined = await (await join(friend, room.invite_code!)).json<RoomSnapshotV2>();
    const poll = (account: Account, held: RoomSnapshotV2) => call(path, "GET", account, undefined, { "X-AfterYou-Known-Room": `${held.revision}.${held.branch}` });
    for (const account of [owner, friend])
      expect(await (await poll(account, joined)).json()).toEqual({ schema_version: 1, unchanged: true, revision: joined.revision, branch: joined.branch, updated_at: joined.updated_at });
    const a = await accepted(await turn(joined, owner, firstA));
    const full = await (await call(path, "GET", friend)).json<RoomSnapshotV2>();
    expect(await (await poll(friend, joined)).json()).toEqual(full);
    expect(await (await poll(friend, a.room)).json()).toEqual({ schema_version: 1, unchanged: true, revision: a.room.revision, branch: a.room.branch, updated_at: a.room.updated_at });
    expect(await (await call(path, "GET", friend, undefined, { "X-AfterYou-Known-Room": "garbage" })).json()).toEqual(full);
  });

  it("refused creates and joins answer the codes the phone treats as final", async () => {
    const owner = await identity(), friend = await identity();
    await expectError(join(friend, "not-a-code"), 400, "invalid_invite");
    await expectError(join(friend, "0123456789ABCDEF0123"), 404, "invite_not_found");
    await expectError(call("/v2/rooms", "POST", owner, { ...createBody(key()), definition_hash: "0".repeat(64) }), 422, "unsupported_chapter");
    // A stranger's leave is a quiet success, so the hub's remove never sticks on it.
    expect((await call("/v2/rooms/" + "A".repeat(22) + "/leave", "POST", friend, { schema_version: 1 })).status).toBe(200);
  });
});
