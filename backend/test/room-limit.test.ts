import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { digest, type Outcome } from "../src/protocol";
import { MAX_ACTIVE_ROOM_LINKS, MAX_ROOM_LINKS } from "../src/room-limit";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import { TERMS_VERSION } from "../src/public-policy";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Inbox = { schema_version: 1; rooms: { room_id: string; status: string }[] };
const key = () => crypto.randomUUID();
/** The exact 409 body every client already knows. */
const LIMIT_BODY = '{"error":{"code":"room_limit_reached","retryable":false}}';
let address = 0;
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env };
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + (++address % 250), ...headers,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body)
  }), configured);
}
async function identity(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
const createV2 = (host: Account) => call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
const createV1 = (host: Account) => call("/v1/rooms", "POST", host, { idempotency_key: key() });
const joinV2 = (guest: Account, invite: string) => call("/v2/rooms/join", "POST", guest, { invite_code: invite });
const joinV1 = (guest: Account, invite: string) => call("/v1/rooms/join", "POST", guest, { invite_code: invite });
async function hosted(host: Account): Promise<RoomSnapshotV2> { const result = await createV2(host); expect(result.status).toBe(200); return result.json<RoomSnapshotV2>(); }
async function inviteV1(host: Account): Promise<string> { const result = await createV1(host); expect(result.status).toBe(200); return (await result.json<{ invite_code: string }>()).invite_code; }
const roomV2 = (roomId: string) => env.ROOMS_V2.getByName(roomId);
const linkedIds = async (account: Account) => (await env.PLAYERS.getByName(account.player_id).listRooms()).map(link => link.room_id);
const memberState = (roomId: string, account: Account) => roomV2(roomId).memberRoomState(account.player_id);
const inbox = async (account: Account) => (await call("/v1/room-inbox", "GET", account)).json<Inbox>();

/** A Relay room both members played to the end, with a photo on the host's first turn. */
async function finished(host: Account, guest: Account): Promise<RoomSnapshotV2> {
  const created = await hosted(host);
  expect((await joinV2(guest, created.invite_code!)).status).toBe(200);
  const room = roomV2(created.room_id);
  let state = value(await room.snapshot(host.player_id));
  for (const [owner, recording, checkpoint] of [[host, firstA, undefined], [guest, firstB, middle], [guest, secondA, undefined], [host, secondB, final]] as const)
    state = value(await room.commit(owner.player_id, { base_revision: state.revision, branch: state.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) })).room;
  expect(state.active_role).toBe("complete");
  return state;
}
async function photo(roomId: string, host: Account): Promise<string> {
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const jpeg_base64 = btoa(String.fromCharCode(...bytes));
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  // Terms are always enforced now, in the room as well as at the router.
  expect((await call("/v1/safety/terms", "POST", host, { schema_version: 1, terms_version: TERMS_VERSION })).status).toBe(200);
  value(await roomV2(roomId).updatePhoto(host.player_id, "t0-0-a", { idempotency_key: key(), recording_hash: firstA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64, sha256 }));
  return jpeg_base64;
}
/** Both members take the replays home, so the server keeps only the room's facts. */
async function transfer(roomId: string, host: Account, guest: Account): Promise<void> {
  const offered = await call(`/v2/rooms/${roomId}/replay-transfer`, "GET", host); expect(offered.status).toBe(200);
  const { manifest } = await offered.json<{ manifest: { epoch: number; archive_hash: string } }>();
  for (const member of [host, guest])
    expect((await call(`/v2/rooms/${roomId}/replay-transfer/ack`, "POST", member, { schema_version: 1, epoch: manifest.epoch, archive_hash: manifest.archive_hash })).status).toBe(200);
}
async function expectLimit(response: Response): Promise<void> {
  expect(response.status).toBe(409); expect(response.headers.get("Content-Type")).toBe("application/json; charset=utf-8"); expect(response.headers.get("Retry-After")).toBeNull();
  expect(await response.text()).toBe(LIMIT_BODY);
}
afterEach(async () => { await reset(); });

describe("room cap", () => {
  it("lets a player with 20 finished or transferred rooms host and join again, and every member keeps those rooms", async () => {
    const host = await identity(), guest = await identity(), other = await identity();
    const done: RoomSnapshotV2[] = [];
    for (let index = 0; index < MAX_ACTIVE_ROOM_LINKS; index++) done.push(await finished(host, guest));
    const picture = await photo(done[0].room_id, host);
    await transfer(done[1].room_id, host, guest);
    expect(await memberState(done[1].room_id, guest)).toBe("finished");
    expect(await linkedIds(host)).toHaveLength(MAX_ACTIVE_ROOM_LINKS);

    // Create and join, v2 and v1, all still work for both members.
    const fresh = await hosted(host);
    expect((await joinV2(guest, (await hosted(other)).invite_code!)).status).toBe(200);
    expect((await createV1(host)).status).toBe(200);
    expect((await joinV1(guest, await inviteV1(other))).status).toBe(200);
    expect((await joinV2(guest, fresh.invite_code!)).status).toBe(200);
    expect(await linkedIds(host)).toHaveLength(MAX_ACTIVE_ROOM_LINKS + 2);
    expect(await linkedIds(guest)).toHaveLength(MAX_ACTIVE_ROOM_LINKS + 3);

    // The finished rooms are untouched: links, replays, the photo and the transferred facts.
    for (const room of done) for (const member of [host, guest]) expect(await linkedIds(member)).toContain(room.room_id);
    for (const member of [host, guest]) {
      const kept = await call(`/v2/rooms/${done[0].room_id}`, "GET", member); expect(kept.status).toBe(200);
      expect(await kept.json<RoomSnapshotV2>()).toMatchObject({ active_role: "complete", checkpoint: done[0].checkpoint, completed_pair_ids: done[0].completed_pair_ids });
      expect(value(await roomV2(done[0].room_id).photo(member.player_id, "t0-0-a")).jpeg_base64).toBe(picture);
      expect((await inbox(member)).rooms.filter(room => done.some(item => item.room_id === room.room_id))).toHaveLength(MAX_ACTIVE_ROOM_LINKS);
    }
    // A 0.6.1+ read; 0.6.0 (no finished-room header) gets the Story boundary instead.
    expect((await call(`/v2/rooms/${done[1].room_id}`, "GET", guest, undefined, { "X-AfterYou-Finished-Room": "2" })).status).toBe(410);

    // Deleting the host still reaches every room through its links, finished ones included.
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    for (const room of [...done, fresh]) expect(await memberState(room.room_id, guest)).toBe("gone");
  }, 120_000);

  it("refuses a 21st room in play with exactly the old answer, on every create and join path", async () => {
    const host = await identity(), other = await identity();
    for (let index = 0; index < MAX_ACTIVE_ROOM_LINKS; index++) await hosted(host);
    const before = await linkedIds(host);
    await expectLimit(await createV2(host));
    await expectLimit(await createV1(host));
    await expectLimit(await joinV2(host, (await hosted(other)).invite_code!));
    await expectLimit(await joinV1(host, await inviteV1(other)));
    expect(await linkedIds(host)).toEqual(before);
  }, 60_000);

  it("counts a closed room as gone, and a finished room again once a fork reopens it", async () => {
    const host = await identity(), guest = await identity();
    for (let index = 0; index < MAX_ACTIVE_ROOM_LINKS - 2; index++) await hosted(host);
    const closed = await hosted(host);
    expect((await joinV2(guest, closed.invite_code!)).status).toBe(200);
    expect((await call(`/v2/rooms/${closed.room_id}`, "DELETE", guest, undefined, { "X-AfterYou-Close-If": "in-play" })).status).toBe(200);
    expect(await memberState(closed.room_id, host)).toBe("gone");
    const done = await finished(host, guest);
    const reopened = value(await roomV2(done.room_id).fork(host.player_id, { base_revision: done.revision, idempotency_key: key(), branch: done.branch, stage_index: 0 }));
    expect(reopened.room.active_role).not.toBe("complete");
    expect(await memberState(done.room_id, host)).toBe("in_play");
    // 18 waiting rooms and the reopened one are in play; the closed one is not.
    expect((await createV2(host)).status).toBe(200);
    await expectLimit(await createV2(host));
  }, 60_000);

  it(`holds at most ${MAX_ROOM_LINKS} links in all, and a full Player still exports and answers campaign reads`, async () => {
    const owner = await identity(), player = env.PLAYERS.getByName(owner.player_id);
    const ids = Array.from({ length: MAX_ROOM_LINKS + 1 }, (_, index) => (index.toString(36) + "x".repeat(22)).slice(0, 22));
    for (const id of ids.slice(0, MAX_ROOM_LINKS)) value(await player.addRoom({ room_id: id, invite_code: "", host: false, api_version: 2 }, ids));
    expect(await player.addRoom({ room_id: ids[MAX_ROOM_LINKS], invite_code: "", host: false, api_version: 2 }, ids)).toEqual({ ok: false, status: 409, code: "room_limit_reached" });
    // An existing link is never refused.
    expect((await player.addRoom({ room_id: ids[0], invite_code: "", host: false, api_version: 2 }, ids)).ok).toBe(true);
    const archive = JSON.parse(value(await player.exportSnapshot("f".repeat(40))));
    expect(archive.payload.tables.find((table: { name: string }) => table.name === "rooms").rows).toHaveLength(MAX_ROOM_LINKS);
    expect(await player.campaignLink("Z".repeat(22), await digest(owner.device_token))).toEqual({ ok: true, value: null });
  });
});
