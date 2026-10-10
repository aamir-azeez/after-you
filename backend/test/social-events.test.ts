import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, randomToken } from "../src/protocol";
import { makeFriendRoomHint, validFriendRoomHint } from "../src/notifications";

type Account = { player_id: string; device_token: string; recovery_code: string };
type FriendLink = { player_id: string; request_id: string; status: string };
type Room = { room_id: string; invite_code: string };
type Inbox = { schema_version: 1; available: boolean; events: Array<{ event_id: string; category: string; player_id: string; request_id: string; publication_epoch: number; room: { api_version: number; room_id: string } }>; preferences: Array<{ player_id: string; request_id: string; enabled: boolean }> };
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, enabled = true): Promise<Response> {
  const headers = { "Content-Type": "application/json", "CF-Connecting-IP": `198.18.8.${++address}`, ...(account ? { "X-Player-Id": account.player_id, Authorization: `Bearer ${account.device_token}` } : {}) };
  const settings: Env = { ...env }; Object.assign(settings, { FRIEND_ROOM_EVENTS_ENABLED: enabled ? "true" : "false", V2_ROOMS_ENABLED: "true" });
  return worker.fetch(new Request(`https://social-events.test${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }), settings);
}
async function configureInbox(recipient: string): Promise<void> {
  await runInDurableObject(env.FRIEND_ROOM_EVENTS.getByName(recipient), instance => {
    const objectEnv = Reflect.get(instance, "env") as { FRIEND_ROOM_EVENTS_ENABLED?: string };
    objectEnv.FRIEND_ROOM_EVENTS_ENABLED = "true";
  });
}
async function create(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function pair() {
  const host = await create(), guest = await create();
  const requested = await call("/v1/friends/request", "POST", host, { schema_version: 1, friend_code: guest.player_id }); expect(requested.status).toBe(200);
  const outgoing = await requested.json<FriendLink>();
  expect((await call("/v1/friends/accept", "POST", guest, { schema_version: 1, player_id: host.player_id, request_id: outgoing.request_id })).status).toBe(200);
  const created = await call("/v1/rooms", "POST", host, { idempotency_key: crypto.randomUUID() }); expect(created.status).toBe(200);
  const room = await created.json<Room>();
  expect(await (await call("/v1/friends/share", "POST", host, { schema_version: 1, room: { api_version: 1, room_id: room.room_id } })).json()).toMatchObject({ schema_version: 1, shared_room: { room_id: room.room_id } });
  return { host, guest, requestId: outgoing.request_id, room };
}
async function subscription(host: Account, guest: Account, requestId: string, action: "subscribe" | "unsubscribe") {
  return call(`/v1/friends/${host.player_id}/notifications`, "POST", guest, { schema_version: 1, request_id: requestId, action });
}
async function publish(host: Account, room: Room, id: string) {
  return call("/v1/social/publication", "POST", host, { schema_version: 1, room: { api_version: 1, room_id: room.room_id }, publication_id: id });
}
async function eventRows(recipient: string) {
  return runInDurableObject(env.FRIEND_ROOM_EVENTS.getByName(recipient), (_, ctx) => ctx.storage.sql.exec<{ host_id: string; data: string }>("SELECT host_id,data FROM friend_room_event_queue").toArray());
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("friend room publication events", () => {
  it("allows hosting delivery to an accepted friend before joining the advertised room", async () => {
    const { host, guest, requestId, room } = await pair();
    await configureInbox(guest.player_id);
    expect((await subscription(host,guest,requestId,"subscribe")).status).toBe(200);
    expect((await publish(host,room,randomToken(16))).status).toBe(200);
    const rows = await eventRows(guest.player_id);
    expect(rows).toHaveLength(1);
    const { created_at, attempts, next_at, push_state, ...event } = JSON.parse(rows[0].data);
    await runInDurableObject(env.PLAYERS.getByName(guest.player_id), async (instance, ctx) => {
      expect(ctx.storage.sql.exec("SELECT room_id FROM rooms WHERE room_id=?",room.room_id).toArray()).toHaveLength(0);
      // With no phone token, retain the in-app event and finish push safely.
      expect(await instance.deliverFriendRoomNotification(event)).toEqual({status:"done"});
    });
  });

  it("keeps the feature off by default and does not change legacy friend response shapes", async () => {
    const pairState = await pair();
    const featureOff = await call("/v1/social/inbox", "GET", pairState.guest, undefined, false);
    expect(await featureOff.json()).toEqual({ schema_version: 1, available: false, events: [], preferences: [] });
    const oldList = await call("/v1/friends", "GET", pairState.guest);
    expect(await oldList.json()).toMatchObject({ schema_version: 1, friend_code: pairState.guest.player_id, shared_room: null,
      friends: [{ player_id: pairState.host.player_id, request_id: pairState.requestId, status: "accepted", online: false, expires_after_seconds: 0, join_available: true }] });
    expect(await call("/v1/social/publication", "POST", pairState.host, { schema_version: 1, room: { api_version: 1, room_id: pairState.room.room_id }, publication_id: randomToken(16) }, false).then(r => r.status)).toBe(200);
    expect(await eventRows(pairState.guest.player_id)).toEqual([]);
  });

  it("uses a host-authored epoch, reuses it on retries, commits the inbox before push and acks idempotently", async () => {
    const pairState = await pair();
    await configureInbox(pairState.guest.player_id);
    expect((await subscription(pairState.host, pairState.guest, pairState.requestId, "subscribe")).status).toBe(200);
    const publicationId = randomToken(16), first = await publish(pairState.host, pairState.room, publicationId), firstBody = await first.json<{ publication_epoch: number; queued: number }>();
    expect(first.status).toBe(200); expect(firstBody).toEqual({ schema_version: 1, publication_epoch: 1, queued: 1 });
    expect(await eventRows(pairState.guest.player_id)).toHaveLength(1);
    expect(await (await publish(pairState.host, pairState.room, publicationId)).json()).toEqual(firstBody);
    const archive = await env.PLAYERS.getByName(pairState.host.player_id).exportSnapshot("a".repeat(40));
    expect(archive.ok).toBe(true);
    if (archive.ok) expect(archive.value).not.toContain("friend_room_publication");
    const inbox = await (await call("/v1/social/inbox", "GET", pairState.guest)).json<Inbox>();
    expect(inbox).toMatchObject({ schema_version: 1, available: true, events: [{ category: "room_available", player_id: pairState.host.player_id, request_id: pairState.requestId, publication_epoch: 1, room: { api_version: 1, room_id: pairState.room.room_id } }],
      preferences: [{ player_id: pairState.host.player_id, request_id: pairState.requestId, enabled: true }] });
    const pushHint = makeFriendRoomHint(pairState.host.player_id, { api_version: 1, room_id: pairState.room.room_id }, 1, inbox.events[0].event_id);
    expect(pushHint.kind).toBe("friend_room_available"); expect(validFriendRoomHint(pushHint)).toBe(true);
    const eventId = inbox.events[0].event_id;
    const ack = { schema_version: 1, request_id: pairState.requestId, action: "ack", event_id: eventId };
    expect(await (await call(`/v1/friends/${pairState.host.player_id}/notifications`, "POST", pairState.guest, ack)).json()).toEqual({ schema_version: 1, acknowledged: true, request_id: pairState.requestId });
    expect(await (await call(`/v1/friends/${pairState.host.player_id}/notifications`, "POST", pairState.guest, ack)).json()).toEqual({ schema_version: 1, acknowledged: true, request_id: pairState.requestId });
    expect(await eventRows(pairState.guest.player_id)).toEqual([]);
  });

  it("acks an event that was cancelled, revoked or expired before the client acked as a benign success", async () => {
    const pairState = await pair();
    await configureInbox(pairState.guest.player_id);
    expect((await subscription(pairState.host, pairState.guest, pairState.requestId, "subscribe")).status).toBe(200);
    expect((await publish(pairState.host, pairState.room, randomToken(16))).status).toBe(200);
    const eventId = `${pairState.host.player_id}_1`;
    // The host revokes (unshare/newer epoch/expiry) so the queued row is gone before the guest acks.
    await runInDurableObject(env.FRIEND_ROOM_EVENTS.getByName(pairState.guest.player_id), instance => (instance as unknown as { revoke: (host: string) => Promise<void> }).revoke(pairState.host.player_id));
    expect(await eventRows(pairState.guest.player_id)).toEqual([]);
    const ack = { schema_version: 1, request_id: pairState.requestId, action: "ack", event_id: eventId };
    const response = await call(`/v1/friends/${pairState.host.player_id}/notifications`, "POST", pairState.guest, ack);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ schema_version: 1, acknowledged: true, request_id: pairState.requestId });
    // An event that was never queued at all is equally a benign success.
    const neverQueued = { schema_version: 1, request_id: pairState.requestId, action: "ack", event_id: `${pairState.host.player_id}_9` };
    expect(await (await call(`/v1/friends/${pairState.host.player_id}/notifications`, "POST", pairState.guest, neverQueued)).json()).toEqual({ schema_version: 1, acknowledged: true, request_id: pairState.requestId });
  });

  it("replaces and revokes old epochs on a new publication, unshare, block, and friendship removal", async () => {
    const pairState = await pair(); await subscription(pairState.host, pairState.guest, pairState.requestId, "subscribe");
    await configureInbox(pairState.guest.player_id);
    const first = await publish(pairState.host, pairState.room, randomToken(16)); expect(first.status).toBe(200);
    const next = await publish(pairState.host, pairState.room, randomToken(16)); expect(await next.json()).toMatchObject({ publication_epoch: 2, queued: 1 });
    expect(await eventRows(pairState.guest.player_id)).toHaveLength(1);
    expect((await call("/v1/friends/share", "POST", pairState.host, { schema_version: 1, room: null })).status).toBe(200);
    expect(await eventRows(pairState.guest.player_id)).toEqual([]);
    await call("/v1/friends/share", "POST", pairState.host, { schema_version: 1, room: { api_version: 1, room_id: pairState.room.room_id } });
    await publish(pairState.host, pairState.room, randomToken(16));
    const hostHash = await digest(pairState.host.device_token);
    await runInDurableObject(env.SAFETY_PROFILES.getByName(pairState.host.player_id), instance => instance.setBlock(pairState.host.player_id, hostHash, pairState.guest.player_id, true));
    const hidden = await (await call("/v1/social/inbox", "GET", pairState.guest)).json<Inbox>();
    expect(hidden.events).toEqual([]);
    expect(await eventRows(pairState.guest.player_id)).toEqual([]);
  });

  it("caps recipient queue rows, expires queued work and leaves no alarm after clear", async () => {
    const account = await create(), inbox = env.FRIEND_ROOM_EVENTS.getByName(account.player_id);
    await configureInbox(account.player_id);
    const now = Date.now();
    for (let i = 0; i < 20; i++) {
      const host = randomToken(16), room = { api_version: 1 as const, room_id: randomToken(16) };
      const result = await inbox.enqueue({ schema_version: 1, category: "room_available", event_id: `${host}_1`, host_id: host, recipient_id: account.player_id,
        request_id: randomToken(16), publication_epoch: 1, room, published_at: now });
      expect(result).toMatchObject({ ok: true, value: { queued: true } });
    }
    const tooManyHost = randomToken(16);
    expect(await inbox.enqueue({ schema_version: 1, category: "room_available", event_id: `${tooManyHost}_1`, host_id: tooManyHost, recipient_id: account.player_id,
      request_id: randomToken(16), publication_epoch: 1, room: { api_version: 1, room_id: randomToken(16) }, published_at: now })).toMatchObject({ ok: false, code: "friend_event_queue_full" });
    await runInDurableObject(inbox, async (_, ctx) => {
      for (const row of ctx.storage.sql.exec<{ host_id: string; data: string }>("SELECT host_id,data FROM friend_room_event_queue").toArray()) {
        const value = JSON.parse(row.data); value.created_at = now - 24 * 60 * 60 * 1000 - 1;
        ctx.storage.sql.exec("UPDATE friend_room_event_queue SET data=? WHERE host_id=?", JSON.stringify(value), row.host_id);
      }
      await ctx.storage.setAlarm(now - 1);
    });
    await runInDurableObject(inbox, async instance => (instance as unknown as { alarm: () => Promise<void> }).alarm());
    await runInDurableObject(inbox, async (_, ctx) => expect(await ctx.storage.getAlarm()).toBeNull());
    expect(await eventRows(account.player_id)).toEqual([]);
  });

  it("retries the exact event with bounded exponential delay and stops at six attempts", async () => {
    const account = await create(), inbox = env.FRIEND_ROOM_EVENTS.getByName(account.player_id); await configureInbox(account.player_id);
    const host = randomToken(16), requestId = randomToken(16), eventId = `${host}_1`, event = { schema_version: 1 as const, category: "room_available" as const, event_id: eventId,
      host_id: host, recipient_id: account.player_id, request_id: requestId, publication_epoch: 1, room: { api_version: 1 as const, room_id: randomToken(16) }, published_at: Date.now() };
    expect(await inbox.enqueue(event)).toMatchObject({ ok: true, value: { queued: true } });
    let originalPlayers: Env["PLAYERS"] | undefined;
    await runInDurableObject(inbox, async (instance, ctx) => {
      const objectEnv = Reflect.get(instance, "env") as Env; originalPlayers = objectEnv.PLAYERS;
      objectEnv.PLAYERS = { getByName: () => ({ deliverFriendRoomNotification: async (queued: unknown) => { expect(queued).toMatchObject({ event_id: eventId }); return { status: "retry" }; } }) } as unknown as Env["PLAYERS"];
      const row = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue WHERE host_id=?", host).one().data);
      row.created_at = Date.now() - 5000; row.published_at = row.created_at; row.next_at = Date.now() - 1000;
      ctx.storage.sql.exec("UPDATE friend_room_event_queue SET data=? WHERE host_id=?", JSON.stringify(row), host); await ctx.storage.setAlarm(Date.now() - 1);
      await (instance as unknown as { alarm: () => Promise<void> }).alarm();
      const pending = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue WHERE host_id=?", host).one().data);
      expect(pending).toMatchObject({ event_id: eventId, attempts: 1, push_state: "pending" });
      expect(pending.next_at - Date.now()).toBeGreaterThanOrEqual(29_000);
      pending.attempts = 5; pending.next_at = Date.now() - 1000;
      ctx.storage.sql.exec("UPDATE friend_room_event_queue SET data=? WHERE host_id=?", JSON.stringify(pending), host); await ctx.storage.setAlarm(Date.now() - 1);
      await (instance as unknown as { alarm: () => Promise<void> }).alarm();
      expect(ctx.storage.sql.exec("SELECT * FROM friend_room_event_queue").toArray()).toEqual([]);
      expect(await ctx.storage.getAlarm()).toBeNull();
      objectEnv.PLAYERS = originalPlayers;
    });
  });
});
