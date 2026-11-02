import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { randomToken } from "../src/protocol";
import { makeHint, type SendResult } from "../src/notifications";
import { sendPollenPush } from "../src/pollen/grant-push";
import type { FriendRoomEvent } from "../src/friend-room-events";
import { configJson } from "./config";
import { meterRows } from "./meter";

// The one per-phone push loop (notification-phones.ts) as each of its three callers uses it: which phones
// each picks, how each answers a failed or gone token, and what each tells its own retry. These pin the
// behaviour the three separate loops had, including where the three differ. FCM is never reached: the
// Player's sender is stubbed. Synthetic identities and tokens only.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Sent = { token: string; platform: unknown; current: boolean };
const DAY = 86_400_000;
/** Rows the Player reads and writes for one delivery to two phones, measured on the three separate loops before they were shared. */
const TURN_ROWS = { player: { read: 13, written: 0 } }, HOSTING_ROWS = { player: { read: 30, written: 0 } }, POLLEN_ROWS = { player: { read: 7, written: 0 } };
const shared = env as unknown as Record<string, unknown>;
const saved = { CONFIG: shared.CONFIG, FCM_SERVICE_ACCOUNT_JSON: shared.FCM_SERVICE_ACCOUNT_JSON };
/** Shape-valid only; the sender is stubbed, so no key is ever used. */
const FCM = JSON.stringify({ project_id: "afteryou-synthetic", client_email: "test@afteryou-synthetic.iam.gserviceaccount.com", private_key: ["-----BEGIN PRIVATE KEY-----", "AAAA", "-----END PRIVATE KEY-----", ""].join("\n") });
let address = 0;
function configure(features: string[], fcm = true): void {
  shared.CONFIG = configJson({ features });
  if (fcm) shared.FCM_SERVICE_ACCOUNT_JSON = FCM; else delete shared.FCM_SERVICE_ACCOUNT_JSON;
}
beforeEach(() => configure(["NOTIFICATIONS_ENABLED", "IOS_PUSH_ENABLED", "FRIEND_ROOM_EVENTS_ENABLED"]));
afterEach(async () => {
  for (const [key, value] of Object.entries(saved)) { if (value === undefined) delete shared[key]; else shared[key] = value; }
  vi.restoreAllMocks(); await reset();
});
async function call(path: string, method = "GET", account?: Account, body?: unknown, extra: Record<string, string> = {}): Promise<Response> {
  return worker.fetch(new Request("https://push-phones.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.95." + (++address % 250),
    "X-AfterYou-Friend-Events": "2", ...(account ? { "X-Player-Id": account.player_id, Authorization: `Bearer ${account.device_token}` } : {}), ...extra },
    body: body === undefined ? undefined : JSON.stringify(body) }), env);
}
const create = async (): Promise<Account> => { const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201); return made.json<Account>(); };
const player = (account: Account) => env.PLAYERS.getByName(account.player_id);
const IOS_TURNS_OFF = { "X-AfterYou-Platform": "ios", "X-AfterYou-Push-Categories": "hosting" };
/** Registers a phone and returns its binding. A registration erases rows older than 30 days, so age rows only after the last one. */
async function phone(account: Account, token: string, extra: Record<string, string> = {}): Promise<string> {
  const binding = randomToken(16);
  expect((await call("/v1/notifications/registration", "POST", account, { schema_version: 1, token, binding_epoch: binding }, extra)).status).toBe(200);
  return binding;
}
/** Moves each binding's updated_at the given number of days back. */
async function age(account: Account, days: Record<string, number>): Promise<void> {
  await runInDurableObject(player(account), (_, ctx) => {
    for (const [binding, back] of Object.entries(days)) ctx.storage.sql.exec("UPDATE notification_registrations SET data=json_set(data,'$.updated_at',?) WHERE binding_epoch=?", Date.now() - back * DAY, binding);
  });
}
/** A row left by another device by a client that reads hosting events (a registration erases these, so add it after the last one). */
async function otherDevice(account: Account, token: string): Promise<void> {
  await runInDurableObject(player(account), (_, ctx) => { ctx.storage.sql.exec("INSERT INTO notification_registrations VALUES (?,?)", randomToken(16), JSON.stringify({ token, device_hash: "o".repeat(43), updated_at: Date.now(), friend_events: 2 })); });
}
/** The Player's own memory of finished pushes, by key. */
const finished = (account: Account) => runInDurableObject(player(account), instance => [...(Reflect.get(instance, "finishedPushes") as Set<string>)]);
/** Five rows for the current device, one more than a Player may hold. */
async function overfill(account: Account): Promise<void> {
  await runInDurableObject(player(account), (_, ctx) => {
    const identity = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data) as { device_hash: string };
    ctx.storage.sql.exec("DELETE FROM notification_registrations");
    for (let index = 0; index < 5; index++) ctx.storage.sql.exec("INSERT INTO notification_registrations VALUES (?,?)", randomToken(16), JSON.stringify({ token: `synthetic-overflow-token-${index}`, device_hash: identity.device_hash, updated_at: Date.now() }));
  });
}
const tokens = (account: Account) => runInDurableObject(player(account), (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations").toArray().map(row => (JSON.parse(row.data) as { token: string }).token).sort());
/**
 * Runs `work` inside the Player with its sender stubbed: each token answers from `answers` (default "sent"),
 * after the sender's own current check when `checkCurrent` (a "cancelled" when it fails, as the real sender does).
 */
async function stubbed<T>(account: Account, answers: Record<string, SendResult[]>, work: (instance: import("../src/player").Player, ctx: DurableObjectState) => Promise<T>, checkCurrent = false): Promise<{ value: T; sent: Sent[] }> {
  return runInDurableObject(player(account), async (instance, ctx) => {
    const sent: Sent[] = [];
    const sender = Reflect.get(instance, "notificationSender") as { send: (...args: unknown[]) => Promise<SendResult> };
    vi.spyOn(sender, "send").mockImplementation(async (...args: unknown[]) => {
      const [token, , , still, platform] = args as [string, string, unknown, () => boolean | Promise<boolean>, string];
      const current = checkCurrent ? await still() : true;
      sent.push({ token, platform, current });
      if (!current) return { status: "cancelled" };
      return answers[token]?.shift() ?? { status: "sent" };
    });
    const value = await work(instance, ctx);
    return { value, sent: sent.sort((a, b) => a.token.localeCompare(b.token)) };
  });
}

describe("the turn push through the shared loop", () => {
  async function room() {
    const host = await create(), guest = await create();
    const made = await call("/v1/rooms", "POST", host, { idempotency_key: crypto.randomUUID() }); expect(made.status).toBe(200);
    const created = await made.json<{ room_id: string; invite_code: string }>();
    const joined = await call("/v1/rooms/join", "POST", guest, { invite_code: created.invite_code }); expect(joined.status).toBe(200);
    const snapshot = await joined.json<{ room_id: string; revision: number }>();
    return { host, guest, hint: makeHint("legacy", snapshot.room_id, snapshot.revision) };
  }
  it("erases rows older than 30 days or from another device before choosing, and skips an iPhone with turns off", async () => {
    const { guest, hint } = await room();
    await phone(guest, "synthetic-turn-fresh");
    const days29 = await phone(guest, "synthetic-turn-29-days"), days31 = await phone(guest, "synthetic-turn-31-days");
    await phone(guest, "synthetic-turn-iphone-off", IOS_TURNS_OFF);
    await age(guest, { [days29]: 29, [days31]: 31 });
    await otherDevice(guest, "synthetic-turn-other-device");
    const run = await stubbed(guest, {}, instance => instance.deliverTurnNotification(hint));
    expect(run.sent.map(item => `${item.token}:${item.platform}`)).toEqual(["synthetic-turn-29-days:android", "synthetic-turn-fresh:android"]);
    expect(run.value).toEqual({ delivered: true, retry_after_ms: 0 });
    // The 31 day and other-device rows are gone for good; the skipped iPhone's row stays.
    expect(await tokens(guest)).toEqual(["synthetic-turn-29-days", "synthetic-turn-fresh", "synthetic-turn-iphone-off"]);
  });
  it("erases a gone token, keeps a refused one, retries only the phone that failed and tells the outbox to retry", async () => {
    const { guest, hint } = await room();
    for (const token of ["synthetic-turn-gone", "synthetic-turn-refused", "synthetic-turn-busy", "synthetic-turn-fine"]) await phone(guest, token);
    const answers: Record<string, SendResult[]> = { "synthetic-turn-gone": [{ status: "invalid_token" }], "synthetic-turn-refused": [{ status: "rejected" }],
      "synthetic-turn-busy": [{ status: "retry", retry_after_ms: 120_000 }, { status: "sent" }] };
    const first = await stubbed(guest, answers, instance => instance.deliverTurnNotification(hint));
    expect(first.value).toEqual({ delivered: false, retry_after_ms: 120_000 });
    expect(first.sent).toHaveLength(4);
    expect(await tokens(guest)).toEqual(["synthetic-turn-busy", "synthetic-turn-fine", "synthetic-turn-refused"]);
    const second = await stubbed(guest, answers, instance => instance.deliverTurnNotification(hint));
    expect(second.sent.map(item => item.token)).toEqual(["synthetic-turn-busy"]);
    expect(second.value).toEqual({ delivered: true, retry_after_ms: 0 });
    const keys = await finished(guest);
    expect(keys).toHaveLength(4);
    for (const key of keys) expect(key.startsWith(`room:${hint.event_id}:`)).toBe(true);
  });
  it("keeps a gone token's row that changed during the send, and answers an over-full table with a retry and no send", async () => {
    const { guest, hint } = await room();
    const binding = await phone(guest, "synthetic-turn-replaced");
    const run = await runInDurableObject(player(guest), async (instance, ctx) => {
      const sender = Reflect.get(instance, "notificationSender") as { send: (...args: unknown[]) => Promise<SendResult> };
      vi.spyOn(sender, "send").mockImplementation(async () => {
        ctx.storage.sql.exec("UPDATE notification_registrations SET data=json_set(data,'$.updated_at',?) WHERE binding_epoch=?", Date.now() + 1, binding);
        return { status: "invalid_token" };
      });
      return instance.deliverTurnNotification(hint);
    });
    expect(run).toEqual({ delivered: true, retry_after_ms: 0 });
    expect(await tokens(guest)).toEqual(["synthetic-turn-replaced"]);
    await overfill(guest);
    const full = await stubbed(guest, {}, instance => instance.deliverTurnNotification(hint));
    expect(full).toEqual({ value: { delivered: false }, sent: [] });
  });
  it("still tries each phone with notifications unconfigured, and keeps the hint for a retry", async () => {
    const { guest, hint } = await room();
    await phone(guest, "synthetic-turn-unconfigured");
    configure(["NOTIFICATIONS_ENABLED", "IOS_PUSH_ENABLED"], false);
    const run = await stubbed(guest, { "synthetic-turn-unconfigured": [{ status: "unconfigured" }] }, instance => instance.deliverTurnNotification(hint));
    expect(run.sent.map(item => item.token)).toEqual(["synthetic-turn-unconfigured"]);
    expect(run.value).toEqual({ delivered: false, retry_after_ms: 0 });
  });
  it("costs the Player the same rows per delivery, every phone checked again after the token step", async () => {
    const { guest, hint } = await room();
    for (const token of ["synthetic-turn-cost-one", "synthetic-turn-cost-two"]) await phone(guest, token);
    const run = await meterRows({ player: player(guest) }, () => stubbed(guest, {}, instance => instance.deliverTurnNotification(hint), true));
    console.log("turn push rows", JSON.stringify(run.rows));
    expect(run.value.sent.map(item => item.token)).toEqual(["synthetic-turn-cost-one", "synthetic-turn-cost-two"]);
    expect(run.rows).toEqual(TURN_ROWS);
  });
});

describe("the hosting push through the shared loop", () => {
  /** An accepted pair with a shared room, the guest subscribed, and one queued hosting event for the guest. */
  async function hosting(register: (guest: Account) => Promise<void>) {
    const host = await create(), guest = await create();
    const requested = await call("/v1/friends/request", "POST", host, { schema_version: 1, friend_code: guest.player_id }); expect(requested.status).toBe(200);
    const { request_id: requestId } = await requested.json<{ request_id: string }>();
    expect((await call("/v1/friends/accept", "POST", guest, { schema_version: 1, player_id: host.player_id, request_id: requestId })).status).toBe(200);
    const made = await call("/v1/rooms", "POST", host, { idempotency_key: crypto.randomUUID() }); expect(made.status).toBe(200);
    const room = await made.json<{ room_id: string }>();
    expect((await call("/v1/friends/share", "POST", host, { schema_version: 1, room: { api_version: 1, room_id: room.room_id } })).status).toBe(200);
    await register(guest);
    expect((await call(`/v1/friends/${host.player_id}/notifications`, "POST", guest, { schema_version: 1, request_id: requestId, action: "subscribe" })).status).toBe(200);
    expect((await call("/v1/social/publication", "POST", host, { schema_version: 1, room: { api_version: 1, room_id: room.room_id }, publication_id: randomToken(16) })).status).toBe(200);
    const rows = await runInDurableObject(env.FRIEND_ROOM_EVENTS.getByName(guest.player_id), (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_event_queue").toArray());
    expect(rows).toHaveLength(1);
    const { created_at, attempts, next_at, push_state, ...event } = JSON.parse(rows[0].data) as FriendRoomEvent & Record<string, unknown>;
    return { guest, event: event as FriendRoomEvent };
  }
  it("chooses every row but an old client's (iPhones: social-events.test.ts); a row older than 30 days or from another device is tried and cancelled", async () => {
    const { guest, event } = await hosting(async account => {
      await phone(account, "synthetic-hosting-fresh");
      const days31 = await phone(account, "synthetic-hosting-31-days");
      await phone(account, "synthetic-hosting-old-client", { "X-AfterYou-Friend-Events": "1" });
      await age(account, { [days31]: 31 });
      await otherDevice(account, "synthetic-hosting-other-device");
    });
    const run = await stubbed(guest, {}, instance => instance.deliverFriendRoomNotification(event), true);
    expect(run.sent).toEqual([{ token: "synthetic-hosting-31-days", platform: "android", current: false }, { token: "synthetic-hosting-fresh", platform: "android", current: true },
      { token: "synthetic-hosting-other-device", platform: "android", current: false }]);
    expect(run.value).toEqual({ status: "done" });
    // Nothing erases the old row here, unlike the turn push.
    expect(await tokens(guest)).toEqual(["synthetic-hosting-31-days", "synthetic-hosting-fresh", "synthetic-hosting-old-client", "synthetic-hosting-other-device"]);
  });
  it("cancels the event when its only phones are older than 30 days", async () => {
    const { guest, event } = await hosting(async account => { await age(account, { [await phone(account, "synthetic-hosting-stale-only")]: 31 }); });
    const run = await stubbed(guest, {}, instance => instance.deliverFriendRoomNotification(event), true);
    expect(run.sent).toEqual([{ token: "synthetic-hosting-stale-only", platform: "android", current: false }]);
    expect(run.value).toEqual({ status: "cancelled" });
  });
  it("erases a gone token, keeps a refused one, retries with the longest wait and then only the phone that failed", async () => {
    const { guest, event } = await hosting(async account => { for (const token of ["synthetic-hosting-gone", "synthetic-hosting-refused", "synthetic-hosting-busy"]) await phone(account, token); });
    const answers: Record<string, SendResult[]> = { "synthetic-hosting-gone": [{ status: "invalid_token" }], "synthetic-hosting-refused": [{ status: "rejected" }], "synthetic-hosting-busy": [{ status: "retry", retry_after_ms: 90_000 }] };
    const run = await stubbed(guest, answers, instance => instance.deliverFriendRoomNotification(event), true);
    expect(run.value).toEqual({ status: "retry", retry_after_ms: 90_000 });
    expect(await tokens(guest)).toEqual(["synthetic-hosting-busy", "synthetic-hosting-refused"]);
    const keys = await finished(guest);
    expect(keys).toHaveLength(2);
    for (const key of keys) expect(key.startsWith(`friend:${event.event_id}:`)).toBe(true);
    const again = await stubbed(guest, answers, instance => instance.deliverFriendRoomNotification(event), true);
    expect(again.sent.map(item => item.token)).toEqual(["synthetic-hosting-busy"]);
    expect(again.value).toEqual({ status: "done" });
  });
  it("is done without a send when unconfigured, and retries with no wait over an over-full table", async () => {
    const { guest, event } = await hosting(account => phone(account, "synthetic-hosting-unconfigured").then(() => undefined));
    configure(["NOTIFICATIONS_ENABLED", "IOS_PUSH_ENABLED", "FRIEND_ROOM_EVENTS_ENABLED"], false);
    expect(await stubbed(guest, {}, instance => instance.deliverFriendRoomNotification(event))).toEqual({ value: { status: "done" }, sent: [] });
    await overfill(guest);
    expect(await stubbed(guest, {}, instance => instance.deliverFriendRoomNotification(event))).toEqual({ value: { status: "retry" }, sent: [] });
  });
  it("costs the Player the same rows per delivery, every phone checked again after the token step", async () => {
    const { guest, event } = await hosting(async account => { for (const token of ["synthetic-hosting-cost-one", "synthetic-hosting-cost-two"]) await phone(account, token); });
    const run = await meterRows({ player: player(guest) }, () => stubbed(guest, {}, instance => instance.deliverFriendRoomNotification(event), true));
    console.log("hosting push rows", JSON.stringify(run.rows));
    expect(run.value).toEqual({ value: { status: "done" }, sent: [{ token: "synthetic-hosting-cost-one", platform: "android", current: true }, { token: "synthetic-hosting-cost-two", platform: "android", current: true }] });
    expect(run.rows).toEqual(HOSTING_ROWS);
  });
});

describe("the monthly Pollen push through the shared loop", () => {
  const lines = [{ key: "grant:1:1", amount: 4750 }];
  const deviceHash = (ctx: DurableObjectState) => (JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data) as { device_hash: string }).device_hash;
  function push(instance: import("../src/player").Player, ctx: DurableObjectState, memory = new Set<string>()) {
    const sender = Reflect.get(instance, "notificationSender") as import("../src/notifications").FcmSender;
    return sendPollenPush(ctx.storage, env, sender, deviceHash(ctx), hash => hash === deviceHash(ctx), lines,
      { finished: key => memory.has(key), finish: (key, sent) => { if (sent.status === "sent" || sent.status === "invalid_token" || sent.status === "rejected") memory.add(key); } });
  }
  it("reaches this device's phones registered in the last 62 days only (iPhones: pollen-grant-alarm.test.ts) and erases nothing it skipped", async () => {
    const account = await create();
    await phone(account, "synthetic-pollen-fresh");
    const days31 = await phone(account, "synthetic-pollen-31-days"), days63 = await phone(account, "synthetic-pollen-63-days");
    await age(account, { [days31]: 31, [days63]: 63 });
    await otherDevice(account, "synthetic-pollen-other-device");
    const run = await stubbed(account, {}, (instance, ctx) => push(instance, ctx), true);
    expect(run.sent).toEqual([{ token: "synthetic-pollen-31-days", platform: "android", current: true }, { token: "synthetic-pollen-fresh", platform: "android", current: true }]);
    expect(run.value).toEqual([{ status: "sent" }, { status: "sent" }]);
    expect(await tokens(account)).toEqual(["synthetic-pollen-31-days", "synthetic-pollen-63-days", "synthetic-pollen-fresh", "synthetic-pollen-other-device"]);
  });
  it("erases a gone token, keeps a refused one, never retries itself and on a repeat sends only to the phone that failed", async () => {
    const account = await create();
    for (const token of ["synthetic-pollen-gone", "synthetic-pollen-refused", "synthetic-pollen-busy"]) await phone(account, token);
    const memory = new Set<string>();
    const answers: Record<string, SendResult[]> = { "synthetic-pollen-gone": [{ status: "invalid_token" }], "synthetic-pollen-refused": [{ status: "rejected" }], "synthetic-pollen-busy": [{ status: "retry", retry_after_ms: 60_000 }] };
    const first = await stubbed(account, answers, (instance, ctx) => push(instance, ctx, memory));
    expect(first.sent).toHaveLength(3);
    expect(await tokens(account)).toEqual(["synthetic-pollen-busy", "synthetic-pollen-refused"]);
    const again = await stubbed(account, answers, (instance, ctx) => push(instance, ctx, memory));
    expect(again.sent.map(item => item.token)).toEqual(["synthetic-pollen-busy"]);
  });
  it("remembers finished phones in the Player's own memory, so the Player's repeat sends only to the phone that failed", async () => {
    const account = await create();
    for (const token of ["synthetic-pollen-player-busy", "synthetic-pollen-player-fine"]) await phone(account, token);
    const answers: Record<string, SendResult[]> = { "synthetic-pollen-player-busy": [{ status: "retry", retry_after_ms: 60_000 }] };
    const pushPollen = (instance: import("../src/player").Player) => (Reflect.get(instance, "pushPollen") as (lines: readonly { key: string; amount: number }[]) => Promise<void>).call(instance, lines);
    const first = await stubbed(account, answers, instance => pushPollen(instance));
    expect(first.sent.map(item => item.token)).toEqual(["synthetic-pollen-player-busy", "synthetic-pollen-player-fine"]);
    const keys = await finished(account);
    expect(keys).toHaveLength(1);
    expect(keys[0]).toMatch(/^pollen:pollen_[a-f0-9]{32}:/);
    const again = await stubbed(account, answers, instance => pushPollen(instance));
    expect(again.sent.map(item => item.token)).toEqual(["synthetic-pollen-player-busy"]);
  });
  it("sends nothing when unconfigured or over a full table, and logs only the full table", async () => {
    const account = await create();
    await phone(account, "synthetic-pollen-unconfigured");
    const warnings = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    configure(["NOTIFICATIONS_ENABLED"], false);
    expect(await stubbed(account, {}, (instance, ctx) => push(instance, ctx))).toEqual({ value: [], sent: [] });
    configure(["NOTIFICATIONS_ENABLED"]);
    await overfill(account);
    expect(await stubbed(account, {}, (instance, ctx) => push(instance, ctx))).toEqual({ value: [], sent: [] });
    expect(warnings.mock.calls.map(args => String(args[0]))).toEqual([JSON.stringify({ event: "pollen_push_failed", reason: "registration_state" })]);
  });
  it("costs the Player the same rows per push, every phone checked again after the token step", async () => {
    const account = await create();
    for (const token of ["synthetic-pollen-cost-one", "synthetic-pollen-cost-two"]) await phone(account, token);
    const run = await meterRows({ player: player(account) }, () => stubbed(account, {}, (instance, ctx) => push(instance, ctx), true));
    console.log("pollen push rows", JSON.stringify(run.rows));
    expect(run.value.sent.map(item => item.token)).toEqual(["synthetic-pollen-cost-one", "synthetic-pollen-cost-two"]);
    expect(run.rows).toEqual(POLLEN_ROWS);
  });
});
