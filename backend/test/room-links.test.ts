import { env, exports } from "cloudflare:workers";
import { reset, evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { canonicalJson, digest, fail, ok, type RoomSnapshot } from "../src/protocol";
import { deleteLinkedIdentity, roomDeletionDispatcher, roomLinkVersion, type RoomLink } from "../src/room-links";
import type { PortableSnapshot } from "../src/snapshot";

type Account = { player_id: string; device_token: string; recovery_code: string };
const key = () => crypto.randomUUID();
const commit = "f".repeat(40);
let address = 0;
async function call(path: string, method: string, account?: Account, body?: unknown): Promise<Response> {
  return exports.default.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + ++address,
      ...(account ? { Authorization: "Bearer " + account.device_token, "X-Player-Id": account.player_id } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body)
  }));
}
const create = async () => (await call("/v1/identity", "POST", undefined, {})).json<Account>();
async function legacyRoom(account: Account): Promise<RoomSnapshot> {
  const response = await call("/v1/rooms", "POST", account, { idempotency_key: key() });
  expect(response.status).toBe(200); return response.json<RoomSnapshot>();
}
function futureLink(version = 2, letter = "v"): RoomLink {
  return { room_id: letter.repeat(22), invite_code: "", host: false, api_version: version };
}
async function exported(player: ReturnType<typeof env.PLAYERS.getByName>): Promise<PortableSnapshot> {
  const response = await player.exportSnapshot(commit);
  if (!response.ok) throw new Error(response.code);
  return JSON.parse(response.value) as PortableSnapshot;
}
async function encode(archive: PortableSnapshot): Promise<string> {
  archive.checksum.value = await digest(canonicalJson(archive.payload)); return canonicalJson(archive);
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("room-link compatibility in the actual Workers runtime", () => {
  it("keeps newly created legacy links and portable snapshots byte-compatible", async () => {
    const account = await create(), room = await legacyRoom(account), player = env.PLAYERS.getByName(account.player_id);
    const link = { room_id: room.room_id, invite_code: room.invite_code, host: true };
    expect(await player.listRooms()).toEqual([link]);
    expect(roomLinkVersion(link as RoomLink)).toBe(1);
    const archive = await exported(player);
    expect(archive.payload.format_version).toBe(1);
    expect(archive.payload.database_schema_version).toBe(1);
    expect(archive.payload.tables[1].rows[0].data).toBe(JSON.stringify(link));
    expect((await call("/v1/identity", "DELETE", account)).status).toBe(200);
    expect((await call("/v1/identity", "GET", account)).status).toBe(401);
  });

  it("lists only v1 rooms and prunes only genuinely absent v1 links", async () => {
    const account = await create(), existing = await legacyRoom(account), player = env.PLAYERS.getByName(account.player_id);
    const newer = futureLink(), unknown = futureLink(47, "u"), missing = { room_id: "m".repeat(22), invite_code: "", host: false };
    await player.addRoom(newer); await player.addRoom(unknown); await player.addRoom(missing);
    // A same-ID v1 fixture must not leak into a v2 link's list or get touched.
    const wrongNamespace = env.ROOMS.getByName(newer.room_id);
    await wrongNamespace.initialize(newer.room_id, account.player_id, "C".repeat(20));
    for (let attempt = 0; attempt < 2; attempt++) {
      const listed = await call("/v1/rooms", "GET", account);
      expect(listed.status).toBe(200);
      expect((await listed.json<{ rooms: RoomSnapshot[] }>()).rooms.map(room => room.room_id)).toEqual([existing.room_id]);
    }
    await evictDurableObject(player);
    const retained = await player.listRooms();
    expect(retained).toContainEqual(newer); expect(retained).toContainEqual(unknown);
    expect(retained.some(link => link.room_id === missing.room_id)).toBe(false);
    expect((await wrongNamespace.snapshot(account.player_id)).ok).toBe(true);
  });

  it("preserves every room and active credentials when v2 deletion is unconfigured", async () => {
    const account = await create(), oldRoom = await legacyRoom(account), player = env.PLAYERS.getByName(account.player_id);
    await player.addRoom(futureLink());
    const before = await exported(player);
    const response = await call("/v1/identity", "DELETE", account);
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: { code: "room_service_unavailable", retryable: true } });
    expect((await exported(player)).payload.tables).toEqual(before.payload.tables);
    expect((await call("/v1/identity", "GET", account)).status).toBe(200);
    expect((await env.ROOMS.getByName(oldRoom.room_id).snapshot(account.player_id)).ok).toBe(true);
    expect((await call("/v2/rooms", "POST", account, { idempotency_key: key() })).status).toBe(404);
  });

  it("does not erase an unknown version even when a v2 eraser is configured", async () => {
    const account = await create(), oldRoom = await legacyRoom(account), player = env.PLAYERS.getByName(account.player_id);
    await player.addRoom(futureLink(47));
    const v2 = vi.fn(async () => ok({ deleted: true }));
    expect(await deleteLinkedIdentity(account.player_id, player, roomDeletionDispatcher(env.ROOMS, v2)))
      .toEqual({ ok: false, status: 409, code: "unsupported_room_version" });
    expect(v2).not.toHaveBeenCalled();
    expect(await player.authorize(await digest(account.device_token))).toBe(true);
    expect((await env.ROOMS.getByName(oldRoom.room_id).snapshot(account.player_id)).ok).toBe(true);
    expect((await call("/v1/identity", "DELETE", account)).status).toBe(409);
    expect(await roomDeletionDispatcher(env.ROOMS).erase(futureLink(), account.player_id)).toMatchObject({ ok: false, status: 503 });
    expect(await roomDeletionDispatcher(env.ROOMS, v2).erase(futureLink(47), account.player_id)).toMatchObject({ ok: false, status: 409 });
  });

  it("uses the explicit v2 eraser seam and resumes a failed deletion without losing its link", async () => {
    const account = await create(), player = env.PLAYERS.getByName(account.player_id), newer = futureLink();
    await player.addRoom(newer);
    const oldRoom = await legacyRoom(account); // Newer row is erased first, then v2 fails.
    const failed = vi.fn(async () => fail(503, "test_unavailable"));
    expect(await deleteLinkedIdentity(account.player_id, player, roomDeletionDispatcher(env.ROOMS, failed))).toMatchObject({ ok: false, status: 503 });
    expect(failed).toHaveBeenCalledWith(newer, account.player_id);
    expect(await player.authorize(await digest(account.device_token))).toBe(false);
    expect(await player.authorize(await digest(account.device_token), true)).toBe(true);
    expect((await env.ROOMS.getByName(oldRoom.room_id).snapshot(account.player_id)).ok).toBe(false);
    expect(await player.listRooms()).toEqual([newer]);
    expect(await player.finishDelete()).toEqual({ ok: false, status: 409, code: "deletion_not_ready" });
    const accepted = vi.fn(async () => ok({ deleted: true }));
    expect(await deleteLinkedIdentity(account.player_id, player, roomDeletionDispatcher(env.ROOMS, accepted))).toEqual({ ok: true, value: { deleted: true } });
    expect(accepted).toHaveBeenCalledWith(newer, account.player_id);
    expect(await player.listRooms()).toEqual([]);
    expect(await player.authorize(await digest(account.device_token), true)).toBe(false);
    expect((await env.ROOMS.getByName(oldRoom.room_id).snapshot(account.player_id)).ok).toBe(false);
  });

  it("guards legacy join, cleanup and creation retries against a version collision", async () => {
    const host = await create(), guest = await create(), room = await legacyRoom(host), player = env.PLAYERS.getByName(guest.player_id);
    const newer = { ...futureLink(), room_id: room.room_id };
    await player.addRoom(newer);
    const joined = await call("/v1/rooms/join", "POST", guest, { invite_code: room.invite_code });
    expect(joined.status).toBe(409);
    expect(await joined.json()).toMatchObject({ error: { code: "room_version_conflict" } });
    await player.removeRoom(newer.room_id); // v1 cleanup must not remove a v2 link.
    expect(await player.listRooms()).toEqual([newer]);
    const requestKey = key(), versionedHost = { ...futureLink(2, "w"), host: true, invite_code: "E".repeat(20) };
    expect((await player.reserveRoom(requestKey, versionedHost)).ok).toBe(true);
    const { api_version: omitted, ...legacy } = versionedHost;
    expect(omitted).toBe(2);
    expect(await player.reserveRoom(requestKey, legacy)).toMatchObject({ ok: false, code: "idempotency_version_mismatch" });
    expect(await player.reserveRoom(key(), legacy)).toMatchObject({ ok: false, code: "room_version_conflict" });
    expect(await player.finishDelete()).toMatchObject({ ok: false, code: "deletion_not_ready" });
  });

  it("cannot add another version after deletion starts", async () => {
    const account = await create(), player = env.PLAYERS.getByName(account.player_id);
    expect(await player.beginDelete()).toEqual({ ok: true, value: [] });
    expect(await player.addRoom(futureLink())).toMatchObject({ ok: false, code: "identity_unavailable" });
    expect(await player.reserveRoom(key(), { ...futureLink(), host: true, invite_code: "A".repeat(20) })).toMatchObject({ ok: false, code: "identity_unavailable" });
    expect(await player.finishDelete()).toEqual({ ok: true, value: { deleted: true } });
  });

  it("round-trips mixed and unknown room versions, raw JSON and receipt bytes as snapshot format2", async () => {
    const account = await create(), room = await legacyRoom(account), source = env.PLAYERS.getByName(account.player_id);
    await source.addRoom(futureLink(1, "e")); await source.addRoom(futureLink());
    await source.reserveRoom(key(), { ...futureLink(47, "u"), host: true, invite_code: "F".repeat(20) });
    await runInDurableObject(source, async (_, state) => {
      const row = state.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", room.room_id).one();
      state.storage.sql.exec("UPDATE rooms SET data=? WHERE room_id=?", JSON.stringify(JSON.parse(row.data), null, 2), room.room_id);
    });
    const archive = await exported(source), target = env.PLAYERS.get(env.PLAYERS.newUniqueId());
    expect(archive.payload.format_version).toBe(2); expect(archive.payload.database_schema_version).toBe(1);
    expect((await target.restoreSnapshot(canonicalJson(archive), account.player_id)).ok).toBe(true);
    await evictDurableObject(target);
    expect((await exported(target)).payload.tables).toEqual(archive.payload.tables);
    expect(await target.listRooms()).toEqual(await source.listRooms());
    expect((await target.restoreSnapshot(canonicalJson(archive), account.player_id))).toMatchObject({ ok: false, code: "snapshot_target_not_empty" });
    archive.payload.format_version = 1;
    expect(await env.PLAYERS.get(env.PLAYERS.newUniqueId()).restoreSnapshot(await encode(archive), account.player_id))
      .toMatchObject({ ok: false, code: "unsupported_snapshot_format" });
    const oldRoomExport = await env.ROOMS.getByName(room.room_id).exportSnapshot(commit);
    if (!oldRoomExport.ok) throw new Error(oldRoomExport.code);
    const oldRoomArchive = JSON.parse(oldRoomExport.value) as PortableSnapshot;
    expect(oldRoomArchive.payload.format_version).toBe(1);
    oldRoomArchive.payload.format_version = 2;
    expect(await env.ROOMS.get(env.ROOMS.newUniqueId()).restoreSnapshot(await encode(oldRoomArchive), room.room_id))
      .toMatchObject({ ok: false, code: "unsupported_snapshot_format" });
  });

  it.each([0, -1, 1.5, null, "2", true, Number.MAX_SAFE_INTEGER + 1])("rejects malformed stored/imported api_version %s without mutation", async version => {
    const account = await create(), source = env.PLAYERS.getByName(account.player_id);
    const value = { ...futureLink(), api_version: version };
    expect(await source.addRoom(value as RoomLink)).toMatchObject({ ok: false, code: "invalid_room_link" });
    expect(await source.listRooms()).toEqual([]);
    await source.addRoom(futureLink());
    const archive = await exported(source), target = env.PLAYERS.get(env.PLAYERS.newUniqueId());
    archive.payload.tables[1].rows[0].data = JSON.stringify(value);
    expect(await target.restoreSnapshot(await encode(archive), account.player_id)).toMatchObject({ ok: false, status: 400 });
    expect((await exported(target)).payload.summary.state).toBe("empty");
  });
});
