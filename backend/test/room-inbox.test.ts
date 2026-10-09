import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { LEVEL_IDS, type Recording, type RoomSnapshot } from "../src/protocol";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";

type Account = { player_id: string; device_token: string; recovery_code: string };
let address = 0;
const key = () => crypto.randomUUID();
async function call(path: string, method = "GET", account?: Account, body?: unknown, v2Enabled = true): Promise<Response> {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: v2Enabled ? "true" : "false" });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + ++address,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body)
  }), configured);
}
const create = async () => (await call("/v1/identity", "POST", undefined, {})).json<Account>();
function legacyTurn(room: RoomSnapshot): Recording {
  return { schema_version: 1, simulation_version: 1, level_version: 1, tick_rate: 30, level_id: room.level_id as typeof LEVEL_IDS[number],
    role: "a", duration_ticks: 30, catch_assistance: true, actions: [{ ticks: 30, x: 0, z: 0, action: true }],
    checkpoints: [{ tick: 30, state_hash: "a".repeat(64) }], final_state_hash: "a".repeat(64), completed: false,
    outcome: { threw_seed: true, caught_seed: false, planted_seed: false } };
}
afterEach(async () => { await reset(); });

describe("authenticated metadata-only room inbox", () => {
  it("keeps unavailable rooms visible, gives old rooms a zero baseline, and advances only on remote activity", async () => {
    const host = await create(), guest = await create();
    const made = await call("/v1/rooms", "POST", host, { idempotency_key: key() });
    expect(made.status).toBe(200);
    const room = await made.json<RoomSnapshot>();
    const beforeJoin = await call("/v1/room-inbox", "GET", host);
    expect(beforeJoin.status).toBe(200);
    expect(await beforeJoin.json()).toMatchObject({ schema_version: 1, rooms: [{ room_id: room.room_id, family: "legacy", api_version: 1,
      chapter: { id: "first-light", version: 1 }, membership: { host_id: host.player_id, guest_id: null, you_are_host: true },
      status: "waiting_for_friend", revision: 0, remote_activity_sequence: 0 }] });
    const joined = await call("/v1/rooms/join", "POST", guest, { invite_code: room.invite_code });
    expect(joined.status).toBe(200);
    let hostInbox = await (await call("/v1/room-inbox", "GET", host)).json<{ rooms: { remote_activity_sequence: number; status: string }[] }>();
    let guestInbox = await (await call("/v1/room-inbox", "GET", guest)).json<{ rooms: { remote_activity_sequence: number; status: string }[] }>();
    expect(hostInbox.rooms[0]).toMatchObject({ remote_activity_sequence: 1, status: "your_turn" });
    expect(guestInbox.rooms[0]).toMatchObject({ remote_activity_sequence: 0, status: "waiting_for_their_turn" });

    const updated = await joined.json<RoomSnapshot>();
    const firstTurn = await call(`/v1/rooms/${room.room_id}/turns`, "POST", host,
      { base_revision: updated.revision, idempotency_key: key(), recording: legacyTurn(room) });
    expect(firstTurn.status).toBe(200);
    guestInbox = await (await call("/v1/room-inbox", "GET", guest)).json<{ rooms: { remote_activity_sequence: number; status: string }[] }>();
    expect(guestInbox.rooms[0]).toMatchObject({ remote_activity_sequence: 1, status: "your_turn" });
    const serialized = JSON.stringify(guestInbox);
    expect(serialized).not.toMatch(/recording|checkpoint|invite_code/i);
  });

  it("projects Relay room metadata without returning turns or checkpoints", async () => {
    const host = await create();
    const creation = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: RELAY.version, definition_hash: DEFINITION_HASH });
    expect(creation.status).toBe(200);
    const room = await creation.json<RoomSnapshotV2>();
    const inbox = await call("/v1/room-inbox", "GET", host);
    expect(inbox.status).toBe(200);
    const body = await inbox.text();
    expect(JSON.parse(body)).toMatchObject({ rooms: [{ room_id: room.room_id, family: "relay", api_version: 2,
      chapter: { id: RELAY.id, version: RELAY.version }, membership: { host_id: host.player_id, guest_id: null },
      status: "waiting_for_friend", revision: 0, remote_activity_sequence: 0 }] });
    expect(body).not.toMatch(/recording|checkpoint|invite_code/i);
  });

  it("classifies activity sequences as operational and resets them across portable room snapshots", async () => {
    const host = await create();
    const made = await call("/v1/rooms", "POST", host, { idempotency_key: key() });
    const room = await made.json<RoomSnapshot>(), source = env.ROOMS.getByName(room.room_id);
    await runInDurableObject(source, (_, state) => {
      state.storage.sql.exec("INSERT INTO room_inbox_activity VALUES (?,?,?)", host.player_id, 9, new Date().toISOString());
    });
    const archive = await source.exportSnapshot("f".repeat(40));
    expect(archive.ok).toBe(true);
    if (!archive.ok) return;
    const payload = JSON.parse(archive.value) as { payload: { tables: { name: string }[] } };
    expect(payload.payload.tables.map(table => table.name)).not.toContain("room_inbox_activity");
    expect(archive.value).not.toContain("room_inbox_activity");

    const target = env.ROOMS.get(env.ROOMS.newUniqueId());
    expect(await target.restoreSnapshot(archive.value, room.room_id)).toMatchObject({ ok: true });
    expect(await target.inboxProjection(host.player_id)).toMatchObject({ ok: true, value: { remote_activity_sequence: 0 } });
  });

  it("requires authentication and does not alter legacy friends response contracts", async () => {
    expect((await call("/v1/room-inbox")).status).toBe(401);
    const account = await create();
    const friends = await call("/v1/friends", "GET", account);
    expect(friends.status).toBe(200);
    expect(Object.keys(await friends.json()).sort()).toEqual(["schema_version", "friend_code", "friends", "refresh_after_seconds", "shared_room"].sort());
  });

  it("resolves invite families without reserving membership; the normal join remains authoritative", async () => {
    const host = await create(), guest = await create();
    const made = await call("/v1/rooms", "POST", host, { idempotency_key: key() });
    const legacy = await made.json<RoomSnapshot>();
    const beforeLinks = await env.PLAYERS.getByName(guest.player_id).listRooms();
    const resolved = await call("/v1/invitations/resolve", "POST", guest, { invite_code: legacy.invite_code!.toLowerCase() });
    expect(resolved.status).toBe(200);
    expect(await resolved.json()).toEqual({ schema_version: 1, family: "legacy", api_version: 1 });
    expect(await env.PLAYERS.getByName(guest.player_id).listRooms()).toEqual(beforeLinks);
    expect(await env.ROOMS.getByName(legacy.room_id).snapshot(host.player_id)).toMatchObject({ value: { revision: 0, guest_id: null } });
    expect((await call("/v1/rooms/join", "POST", guest, { invite_code: legacy.invite_code })).status).toBe(200);
    expect((await env.PLAYERS.getByName(guest.player_id).listRooms()).some(link => link.room_id === legacy.room_id)).toBe(true);

    const relayHost = await create();
    const relayCreation = await call("/v2/rooms", "POST", relayHost, { idempotency_key: key(), level_id: RELAY.id, level_version: RELAY.version, definition_hash: DEFINITION_HASH });
    const relay = await relayCreation.json<RoomSnapshotV2>();
    const relayResolved = await call("/v1/invitations/resolve", "POST", guest, { invite_code: relay.invite_code });
    expect(relayResolved.status).toBe(200);
    expect(await relayResolved.json()).toEqual({ schema_version: 1, family: "relay", api_version: 2 });
    expect((await env.PLAYERS.getByName(guest.player_id).listRooms()).some(link => link.room_id === relay.room_id)).toBe(false);
  });
});
