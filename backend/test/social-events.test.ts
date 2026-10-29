import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { withConfig } from "./config";
import { digest, randomToken } from "../src/protocol";
import { forgetFcmAccess, makeFriendRoomHint, validFriendRoomHint } from "../src/notifications";

type Account = { player_id: string; device_token: string; recovery_code: string };
type FriendLink = { player_id: string; request_id: string; status: string };
type Room = { room_id: string; invite_code: string };
type Inbox = { schema_version: 1; available: boolean; events: Array<{ event_id: string; category: string; player_id: string; request_id: string; publication_epoch: number; room: { api_version: number; room_id: string } }>; preferences: Array<{ player_id: string; request_id: string; enabled: boolean }> };
let address = 0;
/** Unset by default (gate on); "false" turns the client gate off for one test. */
let clientGate: string | undefined;
async function call(path: string, method = "GET", account?: Account, body?: unknown, enabled = true, capable = true, extra: Record<string, string> = {}): Promise<Response> {
  const headers = { "Content-Type": "application/json", "CF-Connecting-IP": `198.18.8.${++address}`, ...(capable ? { "X-AfterYou-Friend-Events": "2" } : {}), ...(account ? { "X-Player-Id": account.player_id, Authorization: `Bearer ${account.device_token}` } : {}), ...extra };
  // The request carries the flags the objects were given (objectFlags) and its own FRIEND_ROOM_EVENTS_ENABLED.
  const { CONFIG: _, ...base } = env as Env & { CONFIG?: string };
  const settings: Env = withConfig({ ...base, ...objectFlags, FRIEND_ROOM_EVENTS_ENABLED: enabled ? "true" : "false", ...(clientGate === undefined ? {} : { FRIEND_EVENTS_CLIENT_GATE: clientGate }) });
  return worker.fetch(new Request(`https://social-events.test${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }), settings);
}
/** The flags the objects read from their own env (here the shared test env), written there as one CONFIG. */
const objectFlags: Record<string, string> = {};
function writeObjectFlags(objectEnv: Record<string, unknown>, changes: Record<string, string | undefined>): void {
  for (const [name, value] of Object.entries(changes)) { if (value === undefined) delete objectFlags[name]; else objectFlags[name] = value; }
  objectEnv.CONFIG = withConfig(objectFlags).CONFIG;
}
async function configureInbox(recipient: string): Promise<void> {
  await runInDurableObject(env.FRIEND_ROOM_EVENTS.getByName(recipient), instance => {
    writeObjectFlags(Reflect.get(instance, "env") as Record<string, unknown>, { FRIEND_ROOM_EVENTS_ENABLED: "true" });
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
afterEach(async () => {
  clientGate = undefined; for (const name of Object.keys(objectFlags)) delete objectFlags[name];
  delete (env as unknown as Record<string, unknown>).CONFIG; forgetFcmAccess(); vi.restoreAllMocks(); await reset();
});
/** Synthetic, shape-valid push settings for one Player; FCM sends are stubbed. */
const syntheticPush = { FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ project_id: "afteryou-synthetic", client_email: "test@afteryou-synthetic.iam.gserviceaccount.com", private_key: ["-----BEGIN PRIVATE KEY-----", "AAAA", "-----END PRIVATE KEY-----", ""].join(String.fromCharCode(10)) }) };
async function configurePush(player: string, gate?: string, iosPush?: string): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(player), instance => {
    const objectEnv = Reflect.get(instance, "env") as Record<string, unknown>;
    Object.assign(objectEnv, syntheticPush);
    if (gate === undefined) delete objectEnv.FRIEND_EVENTS_CLIENT_GATE; else objectEnv.FRIEND_EVENTS_CLIENT_GATE = gate;
    writeObjectFlags(objectEnv, { NOTIFICATIONS_ENABLED: "true", IOS_PUSH_ENABLED: iosPush });
  });
}

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

  it("hides hosting events from clients that cannot read them and shows them to 0.6.1+", async () => {
    const { host, guest, requestId, room } = await pair();
    await configureInbox(guest.player_id);
    expect((await subscription(host,guest,requestId,"subscribe")).status).toBe(200);
    expect(await (await publish(host,room,randomToken(16))).json()).toMatchObject({ queued: 1 });
    const old = await (await call("/v1/social/inbox", "GET", guest, undefined, true, false)).json<Inbox>();
    expect(old).toEqual({ schema_version: 1, available: false, events: [], preferences: [{ player_id: host.player_id, request_id: requestId, enabled: true }] });
    const current = await (await call("/v1/social/inbox", "GET", guest)).json<Inbox>();
    expect(current.events.map(event => event.room.room_id)).toEqual([room.room_id]);
    expect(await eventRows(guest.player_id)).toHaveLength(1);
    clientGate = "false";
    expect((await (await call("/v1/social/inbox", "GET", guest, undefined, true, false)).json<Inbox>()).events).toHaveLength(1);
  });

  it("pushes a hosting alert only to phones registered by a client that reads hosting events", async () => {
    for (const gate of [undefined, "false"]) {
      const { host, guest, requestId, room } = await pair();
      await configureInbox(guest.player_id);
      await configurePush(guest.player_id, gate);
      const oldEpoch = randomToken(16), newEpoch = randomToken(16);
      expect((await call("/v1/notifications/registration", "POST", guest, { schema_version: 1, token: "synthetic-token-from-060-client", binding_epoch: oldEpoch }, true, false)).status).toBe(200);
      expect((await call("/v1/notifications/registration", "POST", guest, { schema_version: 1, token: "synthetic-token-from-061-client", binding_epoch: newEpoch })).status).toBe(200);
      expect((await subscription(host,guest,requestId,"subscribe")).status).toBe(200);
      expect((await publish(host,room,randomToken(16))).status).toBe(200);
      const rows = await eventRows(guest.player_id);
      expect(rows).toHaveLength(1);
      const { created_at, attempts, next_at, push_state, ...event } = JSON.parse(rows[0].data);
      const tokens = await runInDurableObject(env.PLAYERS.getByName(guest.player_id), async instance => {
        const sent: string[] = [];
        const sender = Reflect.get(instance, "notificationSender") as { send: (token: string) => Promise<{ status: "sent" }> };
        vi.spyOn(sender, "send").mockImplementation(async (token: string) => { sent.push(token); return { status: "sent" }; });
        expect(await instance.deliverFriendRoomNotification(event)).toEqual({ status: "done" });
        return sent.sort();
      });
      expect(tokens).toEqual(gate === "false" ? ["synthetic-token-from-060-client", "synthetic-token-from-061-client"] : ["synthetic-token-from-061-client"]);
      await reset();
    }
  });

  it("retries a hosting alert only to the phone that failed, and a skipped phone never cancels the in-app event", async () => {
    const { host, guest, requestId, room } = await pair();
    await configureInbox(guest.player_id); await configurePush(guest.player_id);
    for (const [binding, token] of [[randomToken(16), "synthetic-hosting-token-one"], [randomToken(16), "synthetic-hosting-token-two"]])
      expect((await call("/v1/notifications/registration", "POST", guest, { schema_version: 1, token, binding_epoch: binding })).status).toBe(200);
    expect((await subscription(host,guest,requestId,"subscribe")).status).toBe(200);
    expect((await publish(host,room,randomToken(16))).status).toBe(200);
    const { created_at, attempts, next_at, push_state, ...event } = JSON.parse((await eventRows(guest.player_id))[0].data);
    const rounds = await runInDurableObject(env.PLAYERS.getByName(guest.player_id), async instance => {
      const sender = Reflect.get(instance, "notificationSender") as { send: (token: string) => Promise<{ status: string; retry_after_ms?: number }> };
      const answers: Record<string, string[]> = { "synthetic-hosting-token-one": ["sent"], "synthetic-hosting-token-two": ["retry", "cancelled", "sent"] };
      let sent: string[] = [];
      vi.spyOn(sender, "send").mockImplementation(async (token: string) => { sent.push(token); return { status: answers[token].shift()! }; });
      const results: { result: unknown; sent: string[] }[] = [];
      for (let round = 0; round < 3; round++) { sent = []; results.push({ result: await instance.deliverFriendRoomNotification(event), sent: sent.sort() }); }
      return results;
    });
    expect(rounds[0]).toEqual({ result: { status: "retry", retry_after_ms: 0 }, sent: ["synthetic-hosting-token-one", "synthetic-hosting-token-two"] });
    expect(rounds[1]).toEqual({ result: { status: "done" }, sent: ["synthetic-hosting-token-two"] });
    expect(rounds[2]).toEqual({ result: { status: "done" }, sent: ["synthetic-hosting-token-two"] });
  });

  it("sends a hosting alert to an iOS phone only with hosting on and the client gate passed, and only while the flag is on", async () => {
    for (const flag of ["true", undefined]) {
      const { host, guest, requestId, room } = await pair();
      await configureInbox(guest.player_id);
      await configurePush(guest.player_id, undefined, flag);
      const register = (token: string, categories: string | null, capable = true) => call("/v1/notifications/registration", "POST", guest, { schema_version: 1, token, binding_epoch: randomToken(16) }, true, capable,
        categories === null ? {} : { "X-AfterYou-Platform": "ios", "X-AfterYou-Push-Categories": categories });
      expect((await register("synthetic-android-token", null)).status).toBe(200);
      expect((await register("synthetic-iphone-hosting", "turns,hosting")).status).toBe(200);
      expect((await register("synthetic-iphone-turns-only", "turns")).status).toBe(200);
      expect((await register("synthetic-iphone-old-gate", "hosting", false)).status).toBe(200);
      expect((await subscription(host,guest,requestId,"subscribe")).status).toBe(200);
      expect((await publish(host,room,randomToken(16))).status).toBe(200);
      const rows = await eventRows(guest.player_id);
      const { created_at, attempts, next_at, push_state, ...event } = JSON.parse(rows[0].data);
      const sent = await runInDurableObject(env.PLAYERS.getByName(guest.player_id), async instance => {
        const calls: string[] = [];
        const sender = Reflect.get(instance, "notificationSender") as { send: (...args: unknown[]) => Promise<{ status: "sent" }> };
        vi.spyOn(sender, "send").mockImplementation(async (...args: unknown[]) => { calls.push(`${args[0]}:${args[4]}`); return { status: "sent" }; });
        expect(await instance.deliverFriendRoomNotification(event)).toEqual({ status: "done" });
        return calls.sort();
      });
      // The sender adds the APNs block for "ios" only while the flag is on (notifications.test.ts).
      expect(sent).toEqual(flag ? ["synthetic-android-token:android", "synthetic-iphone-hosting:ios"] : ["synthetic-android-token:android", "synthetic-iphone-hosting:ios", "synthetic-iphone-turns-only:ios"]);
      await reset();
    }
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
