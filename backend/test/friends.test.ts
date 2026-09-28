import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, type Outcome } from "../src/protocol";
import { FRIEND_REQUEST_TTL_MS, MAX_FRIENDS } from "../src/friends";
import { RELAY_KEY } from "../src/v2/chapters";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Link = { player_id: string; request_id: string; status: "incoming" | "outgoing" | "accepted"; online: boolean; expires_after_seconds: number; join_available: boolean };
type List = { schema_version: 1; friend_code: string; friends: Link[]; shared_room: { api_version: number; room_id: string } | null };
type Room = { room_id: string; invite_code: string };
const SESSION = "a".repeat(36);
let address = 0;
const configured = new Map<{ PRESENCE_ENABLED?: string }, string | undefined>();
const value = <T>(r: Outcome<T>): T => { if (!r.ok) throw new Error(r.code); return r.value; };
async function call(path: string, method = "GET", a?: Account, body?: unknown, overrides: Partial<Env> = {}) {
  return worker.fetch(new Request("https://friends.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.7." + ++address, ...(a ? { "X-Player-Id": a.player_id, Authorization: "Bearer " + a.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), Object.assign({}, env, { PRESENCE_ENABLED: "true", V2_ROOMS_ENABLED: "true" }, overrides));
}
async function create(): Promise<Account> { const r = await call("/v1/identity", "POST", undefined, {}); expect(r.status).toBe(201); return r.json<Account>(); }
async function request(a: Account, b: Account) { return call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: b.player_id }); }
async function accept(a: Account, b: Account, id: string) { return call("/v1/friends/accept", "POST", a, { schema_version: 1, player_id: b.player_id, request_id: id }); }
async function remove(a: Account, b: Account, id: string) { return call("/v1/friends/" + b.player_id, "DELETE", a, { schema_version: 1, request_id: id }); }
async function pair() {
  const a = await create(), b = await create(), sent = await request(a, b); expect(sent.status).toBe(200);
  const link = await sent.json<Link>(); expect((await accept(b, a, link.request_id)).status).toBe(200); return { a, b, id: link.request_id };
}
async function heartbeat(a: Account) {
  await runInDurableObject(env.PLAYERS.getByName(a.player_id), instance => {
    const config = Reflect.get(instance, "env") as { PRESENCE_ENABLED?: string };
    if (!configured.has(config)) configured.set(config, config.PRESENCE_ENABLED); config.PRESENCE_ENABLED = "true";
  });
  expect((await call("/v1/presence", "POST", a, { schema_version: 1, session_id: SESSION, online: true })).status).toBe(200);
}
async function newRoom(a: Account, version: number): Promise<Room> {
  const r = await call(`/v${version}/rooms`, "POST", a, { idempotency_key: crypto.randomUUID(), ...(version === 2 ? RELAY_KEY : {}) }); expect(r.status).toBe(200); return r.json<Room>();
}
async function share(a: Account, room: Room | null, version = 1) { return call("/v1/friends/share", "POST", a, { schema_version: 1, room: room ? { api_version: version, room_id: room.room_id } : null }); }
async function join(a: Account, b: Account, id: string, overrides: Partial<Env> = {}) { return call(`/v1/friends/${b.player_id}/join`, "POST", a, { schema_version: 1, request_id: id }, overrides); }
async function recover(a: Account) {
  const next = { ...a, device_token: randomToken(), recovery_code: randomToken() };
  const r = await call("/v1/identity/recover", "POST", undefined, { player_id: a.player_id, recovery_code: a.recovery_code, idempotency_key: crypto.randomUUID(), next_device_token: next.device_token, next_recovery_code: next.recovery_code }); expect(r.status).toBe(200); return next;
}
function roomInviteHook(roomId: string, after: () => Promise<void>): Env["ROOMS"] {
  return new Proxy(env.ROOMS, { get(target, property, receiver) {
    if (property !== "getByName") return Reflect.get(target, property, receiver);
    return (id: string) => {
      const stub = target.getByName(id);
      if (id !== roomId) return stub;
      return new Proxy(stub, { get(room, method, receiver) {
        if (method !== "friendInvite") return Reflect.get(room, method, receiver);
        return async (host: string, visitor: string) => { const result = await room.friendInvite(host, visitor); await after(); return result; };
      } });
    };
  } });
}
afterEach(async () => {
  for (const [config, old] of configured) { if (old === undefined) delete config.PRESENCE_ENABLED; else config.PRESENCE_ENABLED = old; }
  configured.clear(); vi.restoreAllMocks(); await reset();
});

describe("bounded friends by code", () => {
  it("reads identity once per synchronous social lookup and keeps refresh limits", async () => {
    const p = await pair(); await heartbeat(p.a);
    const hash = await digest(p.a.device_token), wrongHash = await digest(randomToken());
    await runInDurableObject(env.PLAYERS.getByName(p.a.player_id), (instance, ctx) => {
      const original = ctx.storage.sql.exec.bind(ctx.storage.sql);
      let reads = 0;
      const spy = vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((query: string, ...bindings: unknown[]) => {
        if (query === "SELECT data FROM identity WHERE id=1") reads++;
        return original(query, ...bindings);
      }) as typeof ctx.storage.sql.exec);
      function once<T>(operation: () => T): T {
        reads = 0; const result = operation(); expect(reads).toBe(1); return result;
      }
      try {
        expect(once(() => instance.friendList(p.a.player_id, hash))).toMatchObject({ ok: true });
        expect(once(() => instance.friendList(p.a.player_id, hash))).toMatchObject({ ok: false, code: "friends_refresh_limited" });
        expect(once(() => instance.friendList(p.a.player_id, hash, false))).toMatchObject({ ok: true, value: { links: [{ accepted: true }] } });
        const expires = once(() => instance.presenceExpiry(p.a.player_id)); expect(expires).toBeGreaterThan(Date.now());
        expect(once(() => instance.friendEdge(p.a.player_id, p.b.player_id))).toMatchObject({ link: { request_id: p.id, accepted: true }, presence_expires_at: expires });
        expect(once(() => instance.friendList(p.a.player_id, wrongHash, false))).toMatchObject({ ok: false, code: "invalid_auth" });
        expect(once(() => instance.friendList(p.b.player_id, hash, false))).toMatchObject({ ok: false, code: "invalid_auth" });
        expect(once(() => instance.friendEdge(p.b.player_id, p.a.player_id))).toBeNull();
        expect(once(() => instance.presenceExpiry(p.b.player_id))).toBe(0);
      } finally { spy.mockRestore(); }
    });
  });

  it("reloads identity and leases after recovery, a fresh session, eviction and deletion", async () => {
    const p = await pair(); await heartbeat(p.a);
    const target = env.PLAYERS.getByName(p.a.player_id), oldHash = await digest(p.a.device_token);
    expect(await target.friendList(p.a.player_id, oldHash, false)).toMatchObject({ ok: true });
    expect((await target.friendEdge(p.a.player_id, p.b.player_id))?.presence_expires_at).toBeGreaterThan(Date.now());
    expect(await target.presenceExpiry(p.a.player_id)).toBeGreaterThan(Date.now());
    const next = await recover(p.a), nextHash = await digest(next.device_token);
    expect(await target.friendList(p.a.player_id, oldHash, false)).toMatchObject({ ok: false, code: "invalid_auth" });
    expect(await target.friendList(p.a.player_id, nextHash, false)).toMatchObject({ ok: true, value: { links: [{ accepted: true }] } });
    expect(await target.friendEdge(p.a.player_id, p.b.player_id)).toMatchObject({ link: { accepted: true }, presence_expires_at: 0 });
    expect(await target.presenceExpiry(p.a.player_id)).toBe(0);
    await heartbeat(next);
    expect((await call("/v1/presence", "POST", next, { schema_version: 1, session_id: "b".repeat(36), online: true })).status).toBe(200);
    expect((await call("/v1/presence", "POST", next, { schema_version: 1, session_id: SESSION, online: false })).status).toBe(200);
    const expires = await target.presenceExpiry(p.a.player_id); expect(expires).toBeGreaterThan(Date.now());
    expect(await target.friendEdge(p.a.player_id, p.b.player_id)).toMatchObject({ presence_expires_at: expires });
    await evictDurableObject(target);
    expect(await target.friendList(p.a.player_id, nextHash, false)).toMatchObject({ ok: true });
    expect(await target.friendEdge(p.a.player_id, p.b.player_id)).toMatchObject({ presence_expires_at: expires });
    expect(await target.presenceExpiry(p.a.player_id)).toBe(expires);
    value(await target.beginDelete([1, 2], nextHash));
    expect(await target.friendList(p.a.player_id, nextHash, false)).toMatchObject({ ok: false, code: "invalid_auth" });
    expect(await target.friendEdge(p.a.player_id, p.b.player_id)).toBeNull();
    expect(await target.presenceExpiry(p.a.player_id)).toBe(0);
  });

  it("requires consent, retains an idempotent request across eviction, and rejects forged/stale approval", async () => {
    const a = await create(), b = await create(), outsider = await create();
    const sent = await request(a, b), link = await sent.json<Link>(); expect(sent.status).toBe(200); expect(link.status).toBe("outgoing");
    await heartbeat(a);
    const incoming = await (await call("/v1/friends", "GET", b)).json<List>();
    expect(incoming.friend_code).toBe(b.player_id); expect(incoming.friends).toEqual([{ player_id: a.player_id, request_id: link.request_id, status: "incoming", online: false, expires_after_seconds: 0, join_available: false }]);
    expect((await accept(outsider, a, link.request_id)).status).toBe(409);
    expect((await accept(a, b, link.request_id)).status).toBe(409);
    expect((await accept(b, a, randomToken(16))).status).toBe(409);
    await evictDurableObject(env.PLAYERS.getByName(a.player_id));
    expect(await (await request(a, b)).json()).toMatchObject({ request_id: link.request_id, status: "outgoing" });
    expect((await accept(b, a, link.request_id)).status).toBe(200);
    expect((await accept(b, a, link.request_id)).status).toBe(200);
    expect((await (await call("/v1/friends", "GET", b)).json<List>()).friends[0]).toMatchObject({ status: "accepted", online: true });
    expect((await call("/v1/friends", "GET", b)).status).toBe(429);
  });

  it("does not let a list read erase an outgoing request between the two durable writes", async () => {
    const a = await create(), b = await create(), id = randomToken(16), hash = await digest(a.device_token);
    const proposed = value(await env.PLAYERS.getByName(a.player_id).friendPropose(a.player_id, hash, b.player_id, id));
    expect((await (await call("/v1/friends", "GET", a)).json<List>()).friends).toEqual([]);
    expect(await env.PLAYERS.getByName(a.player_id).friendEdge(a.player_id, b.player_id)).toMatchObject({ link: { request_id: id } });
    value(await env.PLAYERS.getByName(b.player_id).friendReceive(b.player_id, a.player_id, id, proposed.created_at));
    expect((await accept(b, a, id)).status).toBe(200);
  });

  it("reconciles an acceptance whose second write was interrupted, without early presence access", async () => {
    const a = await create(), b = await create(), sent = await (await request(a, b)).json<Link>(); await heartbeat(a);
    value(await env.PLAYERS.getByName(b.player_id).friendApprove(b.player_id, await digest(b.device_token), a.player_id, sent.request_id));
    const half = await (await call("/v1/friends", "GET", b)).json<List>();
    expect(half.friends[0]).toMatchObject({ status: "incoming", online: false, join_available: false });
    expect((await accept(b, a, sent.request_id)).status).toBe(200);
    expect((await (await call("/v1/friends", "GET", b)).json<List>()).friends[0]).toMatchObject({ status: "accepted", online: true });
  });

  it.each([1, 2])("shares only an explicitly chosen v%s host room and leaves membership to normal join", async version => {
    const p = await pair(), stranger = await create(), room = await newRoom(p.a, version);
    await heartbeat(p.a);
    expect((await join(p.b, p.a, p.id)).status).toBe(409);
    expect((await share(p.b, room, version)).status).toBe(404);
    expect((await share(p.a, room, version)).status).toBe(200);
    const narrow = version === 1 ? await env.ROOMS.getByName(room.room_id).friendInvite(p.a.player_id, p.b.player_id) : await env.ROOMS_V2.getByName(room.room_id).friendInvite(p.a.player_id, p.b.player_id);
    expect(value(narrow)).toEqual({ room_id: room.room_id, invite_code: room.invite_code });
    expect((await join(stranger, p.a, p.id)).status).toBe(409);
    const descriptor = await join(p.b, p.a, p.id); expect(descriptor.status).toBe(200);
    expect(await descriptor.json()).toEqual({ schema_version: 1, api_version: version, room_id: room.room_id, invite_code: room.invite_code });
    expect(await (await call(`/v${version}/rooms/${room.room_id}`, "GET", p.a)).json()).toMatchObject({ guest_id: null });
    expect((await call(`/v${version}/rooms/join`, "POST", p.b, { invite_code: room.invite_code })).status).toBe(200);
    expect((await join(p.b, p.a, p.id)).status).toBe(200);
    const third = await request(stranger, p.a), thirdId = (await third.json<Link>()).request_id;
    expect((await accept(p.a, stranger, thirdId)).status).toBe(200);
    expect((await join(stranger, p.a, thirdId)).status).toBe(409);
    const listing = await (await call("/v1/friends", "GET", stranger)).json<List>(); expect(listing.friends[0].join_available).toBe(false);
    expect(JSON.stringify(listing)).not.toContain(room.invite_code);
    expect((await share(p.a, null)).status).toBe(200);
    expect((await join(p.b, p.a, p.id)).status).toBe(409);
    expect((await call(`/v${version}/rooms/${room.room_id}`, "DELETE", p.a)).status).toBe(200);
    const deleted = version === 1 ? await env.ROOMS.getByName(room.room_id).friendInvite(p.a.player_id, p.b.player_id) : await env.ROOMS_V2.getByName(room.room_id).friendInvite(p.a.player_id, p.b.player_id);
    expect(deleted).toMatchObject({ ok: false, code: "room_not_found" });
  });

  it.each([1, 2])("lets the existing v%s partner rejoin after invitation expiry without admitting a new guest", async version => {
    const p = await pair(), room = await newRoom(p.a, version); await heartbeat(p.a);
    expect((await call(`/v${version}/rooms/join`, "POST", p.b, { invite_code: room.invite_code })).status).toBe(200);
    const expire = (_: unknown, state: DurableObjectState) => {
      const stored = JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data);
      stored.invite_expires_at = new Date(Date.now() - 1000).toISOString();
      state.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(stored));
    };
    if (version === 1) await runInDurableObject(env.ROOMS.getByName(room.room_id), expire);
    else await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), expire);
    expect((await share(p.a, room, version)).status).toBe(200);
    expect((await join(p.b, p.a, p.id)).status).toBe(200);
    expect((await call(`/v${version}/rooms/join`, "POST", p.b, { invite_code: room.invite_code })).status).toBe(200);
    const third = await create(), sent = await (await request(third, p.a)).json<Link>(); expect((await accept(p.a, third, sent.request_id)).status).toBe(200);
    expect((await join(third, p.a, sent.request_id)).status).toBe(409);
  });

  it.each([{ version: 1, enabled: "true" }, { version: 2, enabled: "true" }, { version: 1, enabled: "false" }, { version: 2, enabled: "false" }])("joins an explicitly shared v$version room without host presence (presence enabled=$enabled)", async ({ version, enabled }) => {
    const p = await pair(), room = await newRoom(p.a, version);
    const overrides: Partial<Env> = enabled === "false" ? { PRESENCE_ENABLED: "false" } : {};
    // The host has never published a presence lease.
    expect((await join(p.b, p.a, p.id, overrides)).status).toBe(409);
    expect((await share(p.a, room, version)).status).toBe(200);
    const listing = await call("/v1/friends", "GET", p.b, undefined, overrides); expect(listing.status).toBe(200);
    expect((await listing.json<List>()).friends).toEqual([{ player_id: p.a.player_id, request_id: p.id, status: "accepted", online: false, expires_after_seconds: 0, join_available: true }]);
    const descriptor = await join(p.b, p.a, p.id, overrides); expect(descriptor.status).toBe(200);
    expect(await descriptor.json()).toEqual({ schema_version: 1, api_version: version, room_id: room.room_id, invite_code: room.invite_code });
    expect(await (await call(`/v${version}/rooms/${room.room_id}`, "GET", p.a)).json()).toMatchObject({ guest_id: null });
    // An explicit offline message only changes the indicator, not shared access.
    await heartbeat(p.a);
    expect((await call("/v1/presence", "POST", p.a, { schema_version: 1, session_id: SESSION, online: false })).status).toBe(200);
    expect((await join(p.b, p.a, p.id, overrides)).status).toBe(200);
    expect((await share(p.a, null)).status).toBe(200);
    expect((await join(p.b, p.a, p.id, overrides)).status).toBe(409);
    expect((await share(p.a, room, version)).status).toBe(200);
    expect((await join(p.b, p.a, p.id, overrides)).status).toBe(200);
    // A descriptor never reserves the vacant guest slot. Normal join rechecks it.
    const stranger = await create();
    expect((await call(`/v${version}/rooms/join`, "POST", stranger, { invite_code: room.invite_code })).status).toBe(200);
    const full = await call(`/v${version}/rooms/join`, "POST", p.b, { invite_code: room.invite_code }); expect(full.status).toBe(409);
    expect(await full.json()).toMatchObject({ error: { code: "room_full" } });
    expect((await join(p.b, p.a, p.id, overrides)).status).toBe(409);
  });

  it("hides blocked friendships, retains shared access after presence expiry, and revokes it on recovery and deletion", async () => {
    const p = await pair(), room = await newRoom(p.a, 1); await heartbeat(p.a); await share(p.a, room);
    expect((await join(p.b, p.a, p.id)).status).toBe(200);
    value(await env.SAFETY_PROFILES.getByName(p.a.player_id).setBlock(p.a.player_id, await digest(p.a.device_token), p.b.player_id, true));
    expect((await request(p.b, p.a)).status).toBe(403);
    expect((await join(p.b, p.a, p.id)).status).toBe(403);
    expect((await (await call("/v1/friends", "GET", p.b)).json<List>()).friends).toEqual([]);
    value(await env.SAFETY_PROFILES.getByName(p.a.player_id).setBlock(p.a.player_id, await digest(p.a.device_token), p.b.player_id, false));
    const clock = vi.spyOn(Date, "now").mockReturnValue(Date.now() + 91_000);
    expect((await join(p.b, p.a, p.id)).status).toBe(200); clock.mockRestore();
    const next = await recover(p.a);
    expect((await call("/v1/friends", "GET", p.a)).status).toBe(401);
    const current = await (await call("/v1/friends", "GET", next)).json<List>(); expect(current.shared_room).toBeNull(); expect(current.friends[0].status).toBe("accepted");
    expect((await join(p.b, next, p.id)).status).toBe(409);
    expect((await call("/v1/identity", "DELETE", next)).status).toBe(200);
    expect(await env.PLAYERS.getByName(p.b.player_id).friendEdge(p.b.player_id, next.player_id)).toBeNull();
  });

  it("rechecks a block made while the shared-room lookup was suspended", async () => {
    const p = await pair(), room = await newRoom(p.a, 1); await heartbeat(p.a); await share(p.a, room);
    const rooms = roomInviteHook(room.room_id, async () => { value(await env.SAFETY_PROFILES.getByName(p.a.player_id).setBlock(p.a.player_id, await digest(p.a.device_token), p.b.player_id, true)); });
    const result = await call("/v1/friends", "GET", p.b, undefined, { ROOMS: rooms }); expect(result.status).toBe(200);
    expect((await result.json<List>()).friends).toEqual([]);
    expect((await join(p.b, p.a, p.id)).status).toBe(403);
  });

  it("does not return an invite to a device revoked during the room lookup", async () => {
    const p = await pair(), room = await newRoom(p.a, 1); await heartbeat(p.a); await share(p.a, room);
    const rooms = roomInviteHook(room.room_id, async () => { await recover(p.b); });
    const result = await join(p.b, p.a, p.id, { ROOMS: rooms }); expect(result.status).toBe(401);
    expect(await result.text()).not.toContain(room.invite_code);
  });

  it("removes both exact tokens idempotently without erasing a newer request", async () => {
    const p = await pair(); expect((await remove(p.a, p.b, p.id)).status).toBe(200);
    expect((await remove(p.a, p.b, p.id)).status).toBe(200);
    expect(await env.PLAYERS.getByName(p.a.player_id).friendEdge(p.a.player_id, p.b.player_id)).toBeNull();
    expect(await env.PLAYERS.getByName(p.b.player_id).friendEdge(p.b.player_id, p.a.player_id)).toBeNull();
    const sent = await (await request(p.a, p.b)).json<Link>(); expect(sent.request_id).not.toBe(p.id);
    expect((await remove(p.a, p.b, p.id)).status).toBe(200);
    expect((await accept(p.b, p.a, sent.request_id)).status).toBe(200);
    expect((await accept(p.b, p.a, p.id)).status).toBe(409);
  });

  it.each(["removed", "orphaned"])("repairs a partial removal when the %s side adds again, with fresh consent", async side => {
    const p = await pair();
    // The first DELETE write committed, but the peer RPC was never delivered.
    value(await env.PLAYERS.getByName(p.a.player_id).friendForget(p.a.player_id, p.b.player_id, p.id, await digest(p.a.device_token)));
    const sender = side === "removed" ? p.a : p.b, recipient = sender === p.a ? p.b : p.a;
    const added = await request(sender, recipient); expect(added.status).toBe(200);
    const fresh = await added.json<Link>(); expect(fresh.request_id).not.toBe(p.id); expect(fresh.status).toBe("outgoing");
    expect((await accept(recipient, sender, fresh.request_id)).status).toBe(200);
    expect((await remove(p.a, p.b, p.id)).status).toBe(200);
    expect(await env.PLAYERS.getByName(sender.player_id).friendEdge(sender.player_id, recipient.player_id)).toMatchObject({ link: { request_id: fresh.request_id, accepted: true } });
  });

  it("reclaims an orphaned accepted slot on refresh without keeping a hidden permanent friend", async () => {
    const p = await pair();
    value(await env.PLAYERS.getByName(p.a.player_id).friendForget(p.a.player_id, p.b.player_id, p.id, await digest(p.a.device_token)));
    expect((await (await call("/v1/friends", "GET", p.b)).json<List>()).friends).toEqual([]);
    expect(await env.PLAYERS.getByName(p.b.player_id).friendEdge(p.b.player_id, p.a.player_id)).toBeNull();
    expect((await request(p.b, p.a)).status).toBe(200);
  });

  it("bounds requests and expires unattended ones without a timer or alarm", async () => {
    const a = await create(), hash = await digest(a.device_token), stub = env.PLAYERS.getByName(a.player_id);
    for (let i = 0; i < MAX_FRIENDS; i++) expect((await stub.friendPropose(a.player_id, hash, randomToken(16), randomToken(16))).ok).toBe(true);
    expect(await stub.friendPropose(a.player_id, hash, randomToken(16), randomToken(16))).toMatchObject({ ok: false, code: "friend_list_full" });
    await runInDurableObject(stub, async (_, state) => expect(await state.storage.getAlarm()).toBeNull());
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + FRIEND_REQUEST_TTL_MS + 1);
    expect((await stub.friendPropose(a.player_id, hash, randomToken(16), randomToken(16))).ok).toBe(true);
  });

  it("keeps old snapshot formats unchanged and validates portable social state", async () => {
    const a = await create(), stub = env.PLAYERS.getByName(a.player_id);
    const old = JSON.parse(value(await stub.exportSnapshot("a".repeat(40)))); expect(old.payload.format_version).toBe(1);
    const b = await create(), sent = await (await request(a, b)).json<Link>(); await accept(b, a, sent.request_id);
    const source = value(await stub.exportSnapshot("b".repeat(40))), archive = JSON.parse(source); expect(archive.payload.format_version).toBe(6);
    const fresh = env.PLAYERS.get(env.PLAYERS.newUniqueId()); expect((await fresh.restoreSnapshot(source, a.player_id)).ok).toBe(true);
    expect(await fresh.friendEdge(a.player_id, b.player_id)).toMatchObject({ link: { request_id: sent.request_id, accepted: true } });
    const identityRow = archive.payload.tables[0].rows[0], identity = JSON.parse(identityRow.data);
    identity.social.links.push(identity.social.links[0]); identityRow.data = JSON.stringify(identity);
    archive.checksum.value = await digest(canonicalJson(archive.payload));
    expect(await env.PLAYERS.get(env.PLAYERS.newUniqueId()).restoreSnapshot(canonicalJson(archive), a.player_id)).toMatchObject({ ok: false, code: "unsupported_friend_state" });
  });

  it("rejects unauthenticated, malformed, unknown, self and oversized requests", async () => {
    const a = await create();
    expect((await call("/v1/friends")).status).toBe(401);
    expect((await request(a, a)).status).toBe(400);
    expect((await request(a, { ...a, player_id: randomToken(16) })).status).toBe(404);
    expect((await call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: "bad" })).status).toBe(400);
    expect((await call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: randomToken(16), extra: true })).status).toBe(400);
    expect((await call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: "a".repeat(2000) })).status).toBe(413);
    expect((await call("/v1/friends/share", "POST", a, { schema_version: 1, room: { api_version: 3, room_id: randomToken(16) } })).status).toBe(400);
  });
});
