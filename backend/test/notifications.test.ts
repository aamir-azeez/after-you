import { env } from "cloudflare:workers";
import { runInDurableObject, runDurableObjectAlarm, reset } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, randomToken, type RoomSnapshot, type Outcome } from "../src/protocol";
import { FcmSender, makeFriendRoomHint, makeHint, makeRedoHint, validHint, validRoomHint, type NotificationEnvironment, type PushHint } from "../src/notifications";
import { isAlarmMetadataTable, notificationAlarmOwned, scheduleNotifications } from "../src/notification-storage";
import type { RedoState } from "../src/redo-control";
import type { RoomSnapshotV2, MutationV2 } from "../src/v2/room";
import { RELAY_KEY } from "../src/v2/protocol";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import legacyA from "../../game/tests/fixtures/first-light-a.json";
import legacyB from "../../game/tests/fixtures/first-light-b.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Target = DurableObjectStub<import("../src/player").Player> | DurableObjectStub<import("../src/room").Room> | DurableObjectStub<import("../src/v2/room").RoomV2>;
const source = "887055086a7482a6ebaefd79662d0c20a04f8da7", epoch = "e".repeat(22), token = "synthetic-fcm-registration-token";
let address = 0, config: NotificationEnvironment;
const realNow = Date.now.bind(Date);
const configuredEnvironments = new Map<NotificationEnvironment, NotificationEnvironment>();
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
beforeAll(async () => {
  // Ephemeral synthetic signing material only; no account key or fixture is read.
  const keys = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
  if (!("privateKey" in keys)) throw new Error("synthetic_key_generation_failed");
  const exported = await crypto.subtle.exportKey("pkcs8", keys.privateKey);
  if (!(exported instanceof ArrayBuffer)) throw new Error("synthetic_key_export_failed");
  const bytes = new Uint8Array(exported); let raw = ""; for (const byte of bytes) raw += String.fromCharCode(byte);
  config = { NOTIFICATIONS_ENABLED: "true", FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ project_id: "afteryou-synthetic", client_email: "test@afteryou-synthetic.iam.gserviceaccount.com", private_key: `-----BEGIN PRIVATE KEY-----\n${btoa(raw)}\n-----END PRIVATE KEY-----\n` }) };
});
beforeEach(() => {
  // Native workerd alarms use the real clock. Keep every application due time
  // safely in its future, then force the documented alarm helper exactly once.
  // Production ownership/due checks stay intact; no background alarm races reset().
  const testNow = realNow() + 3_600_000;
  vi.spyOn(Date, "now").mockReturnValue(testNow);
});
afterEach(async () => {
  for (const [target, original] of configuredEnvironments) {
    if (original.NOTIFICATIONS_ENABLED === undefined) delete target.NOTIFICATIONS_ENABLED; else target.NOTIFICATIONS_ENABLED = original.NOTIFICATIONS_ENABLED;
    if (original.FCM_SERVICE_ACCOUNT_JSON === undefined) delete target.FCM_SERVICE_ACCOUNT_JSON; else target.FCM_SERVICE_ACCOUNT_JSON = original.FCM_SERVICE_ACCOUNT_JSON;
    if (original.IOS_PUSH_ENABLED === undefined) delete target.IOS_PUSH_ENABLED; else target.IOS_PUSH_ENABLED = original.IOS_PUSH_ENABLED;
  }
  configuredEnvironments.clear();
  vi.restoreAllMocks(); await reset();
});
async function configured(stub: Target, extra: NotificationEnvironment = {}): Promise<void> {
  await runInDurableObject(stub, async instance => {
    const target = (instance as unknown as { env: NotificationEnvironment }).env;
    if (!configuredEnvironments.has(target)) configuredEnvironments.set(target, { NOTIFICATIONS_ENABLED: target.NOTIFICATIONS_ENABLED, FCM_SERVICE_ACCOUNT_JSON: target.FCM_SERVICE_ACCOUNT_JSON, IOS_PUSH_ENABLED: target.IOS_PUSH_ENABLED });
    Object.assign(target, config, extra);
  });
}
async function call(path: string, method: string, account?: Account, body?: unknown, extra: Record<string, string> = {}): Promise<Response> {
  const settings: Env = { ...env }; Object.assign(settings, { V2_ROOMS_ENABLED: "true" });
  return worker.fetch(new Request("https://afteryou.test" + path, { method, headers: { "CF-Connecting-IP": "198.18.0." + ++address,
    "Content-Type": "application/json", ...(account ? { "X-Player-Id": account.player_id, Authorization: `Bearer ${account.device_token}` } : {}), ...extra },
    body: body === undefined ? undefined : JSON.stringify(body) }), settings);
}
async function create(): Promise<Account> { return (await call("/v1/identity", "POST", undefined, {})).json<Account>(); }
async function pair(v2 = true) {
  const host = await create(), guest = await create();
  const created = await call(v2 ? "/v2/rooms" : "/v1/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), ...(v2 ? RELAY_KEY : {}) });
  const original = await created.json<RoomSnapshotV2>();
  const path = v2 ? "/v2/rooms" : "/v1/rooms", stub = v2 ? env.ROOMS_V2.getByName(original.room_id) : env.ROOMS.getByName(original.room_id);
  await configured(stub); await configured(env.PLAYERS.getByName(host.player_id)); await configured(env.PLAYERS.getByName(guest.player_id));
  const joined = await call(path + "/join", "POST", guest, { invite_code: original.invite_code });
  expect(joined.status).toBe(200);
  return { host, guest, room: await joined.json<RoomSnapshotV2>(), stub, path };
}
async function register(account: Account, binding = epoch, suppliedToken = token) {
  return call("/v1/notifications/registration", "POST", account, { schema_version: 1, token: suppliedToken, binding_epoch: binding });
}
async function rows(stub: Target, table = "notification_outbox") { return runInDurableObject(stub, async (_, ctx) => ctx.storage.sql.exec<{ recipient_id: string; data: string }>(`SELECT * FROM ${table}`).toArray()); }
function provider(status = 200) {
  const messages: Record<string, unknown>[] = [], raw: string[] = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    expect(init?.redirect).toBe("manual");
    if (String(input) === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 });
    expect(String(input)).toBe("https://fcm.googleapis.com/v1/projects/afteryou-synthetic/messages:send");
    raw.push(String(init?.body)); messages.push(JSON.parse(String(init?.body)).message);
    return status === 200 ? Response.json({ name: "projects/afteryou-synthetic/messages/synthetic" }) : Response.json({ error: { details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: status === 404 ? "UNREGISTERED" : "UNAVAILABLE" }] } }, { status, headers: { "Retry-After": "120" } });
  });
  return { messages, raw, spy };
}
async function drain(stub: Target) {
  await runInDurableObject(stub, async (_, ctx) => {
    await ctx.storage.transaction(async () => {
      for (const row of ctx.storage.sql.exec<{ recipient_id: string; data: string }>("SELECT recipient_id,data FROM notification_outbox").toArray()) {
        const data = JSON.parse(row.data); data.created_at = Date.now() - 5000; data.next_at = Date.now() - 1000;
        ctx.storage.sql.exec("UPDATE notification_outbox SET data=? WHERE recipient_id=?", JSON.stringify(data), row.recipient_id);
      }
      await scheduleNotifications(ctx.storage);
    });
  });
  expect(await runDurableObjectAlarm(stub)).toBe(true);
}
function turnBody(room: RoomSnapshotV2, recording: unknown, checkpoint?: unknown) { return { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) }; }
async function categories(account: Account, redo: unknown, binding = epoch) {
  return call("/v1/notifications/categories", "POST", account, { schema_version: 1, binding_epoch: binding, redo_requests: redo });
}
async function askRedo(path: string, roomId: string, second: Account): Promise<RedoState> {
  const offered = await (await call(`${path}/${roomId}/redo`, "GET", second)).json<RedoState>();
  expect(offered.source).not.toBeNull();
  const requested = await call(`${path}/${roomId}/redo`, "POST", second, { action: "request", source: offered.source });
  expect(requested.status).toBe(200);
  return requested.json<RedoState>();
}
async function hints(stub: Target) { return (await rows(stub)).map(row => ({ recipient: row.recipient_id, hint: JSON.parse(row.data).hint as Record<string, string> })); }
/** Host plays A with an opted-in device; the guest (no device) then holds B and may ask for a redo. */
async function redoReady(v2 = true, optIn = true) {
  const paired = await pair(v2), { host, room, stub, path } = paired;
  expect((await register(host, "h".repeat(22), "synthetic-host-fcm-token")).status).toBe(200);
  if (optIn) expect((await categories(host, true, "h".repeat(22))).status).toBe(200);
  const response = await call(path + "/" + room.room_id + "/turns", "POST", host, v2 ? turnBody(room, firstA) : { base_revision: room.revision, idempotency_key: crypto.randomUUID(), recording: legacyA });
  expect(response.status).toBe(200);
  const body = await response.json<MutationV2 | RoomSnapshot>(), after = "receipt" in body ? body.room : body;
  await drain(stub); // The guest has no device, so its turn hint is dropped.
  expect(await rows(stub)).toEqual([]);
  return { ...paired, after };
}

describe("authenticated ephemeral background notification delivery", () => {
  it("defaults off, requires current authentication, exact bounded shape and supports DELETE while off", async () => {
    const account = await create();
    expect((await register(account)).status).toBe(503);
    expect((await call("/v1/notifications/registration", "POST", undefined, {})).status).toBe(401);
    await configured(env.PLAYERS.getByName(account.player_id));
    for (const body of [{ schema_version: 2, binding_epoch: epoch, token }, { schema_version: 1, binding_epoch: "bad", token }, { schema_version: 1, binding_epoch: epoch, token: "x".repeat(4097) }, { schema_version: 1, binding_epoch: epoch, token, url: "https://example.test" }]) expect((await call("/v1/notifications/registration", "POST", account, body)).status).toBe(400);
    expect((await register({ ...account, device_token: randomToken() })).status).toBe(401);
    const result = await register(account); expect(result.status).toBe(200); expect(await result.json()).toEqual({ registered: true, binding_epoch: epoch });
    expect((await register(account)).status).toBe(200); expect(await rows(env.PLAYERS.getByName(account.player_id), "notification_registrations")).toHaveLength(1);
    for (let i = 0; i < 2; i++) expect(await (await call("/v1/notifications/registration", "DELETE", account, { schema_version: 1, binding_epoch: epoch })).json()).toEqual({ unregistered: true });
  });
  it("recovery atomically revokes old token registrations and old credentials cannot re-register", async () => {
    const account = await create(), stub = env.PLAYERS.getByName(account.player_id); await configured(stub); expect((await register(account)).status).toBe(200);
    const body = { player_id: account.player_id, recovery_code: account.recovery_code, idempotency_key: crypto.randomUUID(), next_device_token: randomToken(), next_recovery_code: randomToken() };
    expect((await call("/v1/identity/recover", "POST", undefined, body)).status).toBe(200); expect(await rows(stub, "notification_registrations")).toEqual([]);
    expect((await register(account)).status).toBe(401);
  });
  it("caps current-device registrations and rotates a token without growing or deleting a different binding", async () => {
    const account = await create(), player = env.PLAYERS.getByName(account.player_id); await configured(player);
    for (const char of ["a", "b", "c", "d"]) expect((await register(account, char.repeat(22), token + char)).status).toBe(200);
    expect((await register(account, "f".repeat(22), token + "f")).status).toBe(409);
    expect((await register(account, "a".repeat(22), token + "rotated")).status).toBe(200);
    expect(await rows(player, "notification_registrations")).toHaveLength(4);
    expect((await call("/v1/notifications/registration", "DELETE", account, { schema_version: 1, binding_epoch: "z".repeat(22) })).status).toBe(200);
    expect(await rows(player, "notification_registrations")).toHaveLength(4);
  });
  it("preserves accepted v2 receipts on provider failure, retries the exact event and notifies the other member after B", async () => {
    const { host, guest, room, stub, path } = await pair(); expect((await register(host, "h".repeat(22), "synthetic-host-fcm-token")).status).toBe(200); expect((await register(guest)).status).toBe(200);
    const body = turnBody(room, firstA), accepted = await (await call(path + "/" + room.room_id + "/turns", "POST", host, body)).json<MutationV2>();
    expect(accepted.receipt.accepted_revision).toBe(2);
    const before = await rows(stub); expect(before).toHaveLength(1); expect(before[0].recipient_id).toBe(guest.player_id);
    const failed = provider(503); await drain(stub); expect(failed.messages).toHaveLength(1); failed.spy.mockRestore();
    const pending = await rows(stub); expect(JSON.parse(pending[0].data).attempts).toBe(1); expect(JSON.parse(pending[0].data).hint).toEqual(JSON.parse(before[0].data).hint);
    const retry = await (await call(path + "/" + room.room_id + "/turns", "POST", host, body)).json<MutationV2>(); expect(retry.receipt).toEqual(accepted.receipt); expect(await rows(stub)).toEqual(pending);
    const success = provider(); await drain(stub); expect(success.messages).toHaveLength(1); expect(await rows(stub)).toEqual([]);
    const b = await (await call(path + "/" + room.room_id + "/turns", "POST", guest, turnBody(accepted.room, firstB, middle))).json<MutationV2>();
    expect(b.room.active_player_id).toBe(guest.player_id); expect((await rows(stub))[0].recipient_id).toBe(host.player_id);
    await drain(stub); expect(success.messages.at(-1)?.token).toBe("synthetic-host-fcm-token");
    expect((success.messages.at(-1)?.data as Record<string, string>).kind).toBe("turn_ready");
  });
  it("v1 A/B acceptance also queues only the other member without changing completed replay", async () => {
    const { host, guest, room, stub, path } = await pair(false);
    const first = await (await call(path + "/" + room.room_id + "/turns", "POST", host, { base_revision: room.revision, idempotency_key: crypto.randomUUID(), recording: legacyA })).json<RoomSnapshot>();
    expect(first.active_role).toBe("b"); expect((await rows(stub))[0].recipient_id).toBe(guest.player_id);
    const second = await (await call(path + "/" + room.room_id + "/turns", "POST", guest, { base_revision: first.revision, idempotency_key: crypto.randomUUID(), recording: legacyB })).json<RoomSnapshot>();
    expect(second.active_role).toBe("complete"); expect((await rows(stub)).map(row => row.recipient_id).sort()).toEqual([host.player_id, guest.player_id].sort());
  });
  it.each(["failed insert", "unowned alarm"])("keeps the turn and its hint when alarm bookkeeping fails (%s), and the alarm repairs itself", async failure => {
    const { host, room, stub, path } = await pair();
    await runInDurableObject(stub, async (_, ctx) => {
      if (failure === "failed insert") ctx.storage.sql.exec("CREATE TRIGGER synthetic_notification_failure BEFORE INSERT ON notification_alarm BEGIN SELECT RAISE(ABORT,'synthetic_failure'); END");
      else await ctx.storage.setAlarm(Date.now() + 5000);
    });
    const response = await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA)); expect(response.status).toBe(200);
    const accepted = await response.json<MutationV2>();
    expect(await (await call(path + "/" + room.room_id, "GET", host)).json()).toEqual(accepted.room);
    expect(await rows(stub)).toHaveLength(1);
    await runInDurableObject(stub, async (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT * FROM turns").toArray()).toHaveLength(1); expect(await ctx.storage.getAlarm()).not.toBeNull();
      expect(ctx.storage.sql.exec("SELECT * FROM notification_alarm").toArray()).toEqual([]);
      if (failure === "failed insert") ctx.storage.sql.exec("DROP TRIGGER synthetic_notification_failure");
    });
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    await runInDurableObject(stub, async (_, ctx) => {
      const marker = ctx.storage.sql.exec<{ due_at: number }>("SELECT due_at FROM notification_alarm").one();
      expect(await ctx.storage.getAlarm()).toBe(marker.due_at); expect(notificationAlarmOwned(ctx.storage, "RoomV2", marker.due_at)).toBe(true);
    });
    expect(await rows(stub)).toHaveLength(1);
  });
  it("deletion clears delivery state and registrations before forgetting identity", async () => {
    const { host, guest, room, stub, path } = await pair(); expect((await register(host)).status).toBe(200);
    expect((await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).status).toBe(200);
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    expect(await rows(stub)).toEqual([]); expect(await rows(env.PLAYERS.getByName(host.player_id), "notification_registrations")).toEqual([]);
    expect((await call(path + "/" + room.room_id, "GET", guest)).status).toBe(404);
    await runInDurableObject(stub, async (_, ctx) => expect(await ctx.storage.getAlarm()).toBeNull());
  });
  it("excludes only known ephemeral state from snapshots and restores no registrations or alerts", async () => {
    const { host, guest, room, stub, path } = await pair(); const player = env.PLAYERS.getByName(guest.player_id); expect((await register(guest)).status).toBe(200);
    expect((await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).status).toBe(200);
    const saved = value(await stub.exportSnapshot(source)), savedPlayer = value(await player.exportSnapshot(source));
    for (const serialized of [saved, savedPlayer]) { expect(serialized).not.toContain("notification_"); expect(serialized).not.toContain(token); expect(serialized).not.toContain(epoch); }
    const restored = env.ROOMS_V2.getByName(randomToken(16)), restoredPlayer = env.PLAYERS.getByName(randomToken(16));
    expect((await restored.restoreSnapshot(saved, room.room_id)).ok).toBe(true); expect((await restoredPlayer.restoreSnapshot(savedPlayer, guest.player_id)).ok).toBe(true);
    expect(await rows(restored)).toEqual([]); expect(await rows(restoredPlayer, "notification_registrations")).toEqual([]);
    await runInDurableObject(restored, async (_, ctx) => { expect(await ctx.storage.getAlarm()).toBeNull(); expect(notificationAlarmOwned(ctx.storage, "RoomV2", null)).toBe(true); });
    await runInDurableObject(restored, async (_, ctx) => { await ctx.storage.setAlarm(Date.now() + 60_000); });
    expect(await restored.exportSnapshot(source)).toEqual({ ok: false, status: 400, code: "unsupported_storage_alarm" });
    await runInDurableObject(player, async (_, ctx) => { ctx.storage.sql.exec("CREATE TABLE unrelated (data TEXT)"); });
    expect(await player.exportSnapshot(source)).toEqual({ ok: false, status: 400, code: "unsupported_storage_schema" });
  });
  it("recognizes exactly the protected runtime alarm schema, not similarly named application tables", () => {
    expect(isAlarmMetadataTable({ name: "_cf_METADATA", sql: "CREATE TABLE _cf_METADATA (\n key INTEGER PRIMARY KEY,\n value BLOB\n )" })).toBe(true);
    for (const row of [{ name: "_cf_METADATA_extra", sql: "CREATE TABLE _cf_METADATA (key INTEGER PRIMARY KEY,value BLOB)" }, { name: "_cf_METADATA", sql: "CREATE TABLE _cf_METADATA (key INTEGER PRIMARY KEY,value TEXT)" }, { name: "_cf_METADATA", sql: "CREATE TABLE _cf_METADATA (key INTEGER PRIMARY KEY,value BLOB,secret TEXT)" }]) expect(isAlarmMetadataTable(row)).toBe(false);
  });
  it("handles a consumed alarm and stops retrying at the durable attempt cap", async () => {
    const { host, guest, room, stub, path } = await pair(); expect((await register(guest)).status).toBe(200);
    expect((await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).status).toBe(200);
    const mock = provider(503);
    let consumed: number | null | undefined;
    await runInDurableObject(stub, async (instance, ctx) => {
      const entry = ctx.storage.sql.exec<{ recipient_id: string; data: string }>("SELECT recipient_id,data FROM notification_outbox").one();
      const row = JSON.parse(entry.data); row.attempts = 7; row.created_at = Date.now() - 2000; row.next_at = Date.now() - 1000;
      ctx.storage.sql.exec("UPDATE notification_outbox SET data=? WHERE recipient_id=?", JSON.stringify(row), entry.recipient_id);
      await scheduleNotifications(ctx.storage);
      const roomInstance = instance as unknown as { alarm: () => Promise<void> };
      if (typeof roomInstance.alarm !== "function") throw new Error("missing_room_alarm");
      const original = roomInstance.alarm.bind(roomInstance);
      vi.spyOn(roomInstance, "alarm").mockImplementation(async () => { consumed = await ctx.storage.getAlarm(); await original(); });
    });
    expect(await runDurableObjectAlarm(stub)).toBe(true); expect(consumed).toBeNull();
    await runInDurableObject(stub, async (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT * FROM notification_outbox").toArray()).toEqual([]);
      expect(ctx.storage.sql.exec("SELECT * FROM notification_alarm").toArray()).toEqual([]); expect(await ctx.storage.getAlarm()).toBeNull();
    });
    expect(mock.messages).toHaveLength(1);
  });
  it("a newer accepted turn replacing the same recipient hint survives an older send acknowledgement", async () => {
    const { host, guest, room, stub, path } = await pair();
    const a = await (await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).json<MutationV2>();
    await drain(stub); // Unregistered guest: hint is intentionally dropped.
    const b = await (await call(path + "/" + room.room_id + "/turns", "POST", guest, turnBody(a.room, firstB, middle))).json<MutationV2>();
    expect((await register(host)).status).toBe(200);
    let advancedStatus = 0, advancedRevision = 0;
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => {
      if (String(input).includes("oauth2")) return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 });
      // The old provider response cannot resolve until a real newer commit
      // completes. Keep this one awaited I/O chain instead of resolving a
      // runner-owned deferred promise from another Durable Object context.
      const response = await call(path + "/" + room.room_id + "/turns", "POST", guest, turnBody(b.room, secondA));
      advancedStatus = response.status;
      advancedRevision = (await response.json<MutationV2>()).receipt?.accepted_revision ?? 0;
      return Response.json({ name: "projects/afteryou-synthetic/messages/synthetic" });
    });
    await drain(stub); expect(advancedStatus).toBe(200); expect(advancedRevision).toBe(4);
    const current = await rows(stub); expect(current).toHaveLength(1); expect(current[0].recipient_id).toBe(host.player_id);
    expect(JSON.parse(current[0].data).hint.revision).toBe("4"); expect(JSON.parse(current[0].data).attempts).toBe(0);
  });
  it("FCM sender refuses redirects, bounds responses and only classifies specific UNREGISTERED as token removal", async () => {
    const hint = makeHint("relay", "r".repeat(22), 2), sender = new FcmSender(config), mock = provider(404);
    expect((await sender.send(token, epoch, hint)).status).toBe("invalid_token"); mock.spy.mockRestore();
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response("", { status: 302, headers: { Location: "https://example.test" } }));
    expect((await new FcmSender(config).send(token, epoch, hint)).status).toBe("retry"); vi.restoreAllMocks();
    let cancelled = false;
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(new ReadableStream({ pull(controller) { controller.enqueue(new Uint8Array(20_000)); }, cancel() { cancelled = true; } })));
    expect((await new FcmSender(config).send(token, epoch, hint)).status).toBe("retry"); expect(cancelled).toBe(true);
  });
  it("retries a turn push only to the phone that failed", async () => {
    const { host, guest, room, stub, path } = await pair();
    expect((await register(guest, "a".repeat(22), "synthetic-fcm-token-one")).status).toBe(200);
    expect((await register(guest, "b".repeat(22), "synthetic-fcm-token-two")).status).toBe(200);
    expect((await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).status).toBe(200);
    const posted: string[] = []; let twoStatus = 503;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      if (String(input) === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 });
      const target = JSON.parse(String(init?.body)).message.token as string; posted.push(target);
      if (target === "synthetic-fcm-token-two" && twoStatus !== 200) return Response.json({ error: { code: twoStatus, status: "UNAVAILABLE" } }, { status: twoStatus });
      return Response.json({ name: "projects/afteryou-synthetic/messages/synthetic" });
    });
    await drain(stub);
    expect(posted.sort()).toEqual(["synthetic-fcm-token-one", "synthetic-fcm-token-two"]);
    expect(JSON.parse((await rows(stub))[0].data).attempts).toBe(1);
    posted.length = 0; twoStatus = 200;
    await drain(stub);
    expect(posted).toEqual(["synthetic-fcm-token-two"]); expect(await rows(stub)).toEqual([]);
  });
  const fcmError = (code: string) => ({ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: code });
  const tokenViolation = { "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.token", description: "The registration token is not a valid FCM registration token" }] };
  const finalAnswers = {
    "403 SENDER_ID_MISMATCH": { status: 403, body: { error: { code: 403, status: "PERMISSION_DENIED", details: [fcmError("SENDER_ID_MISMATCH")] } } },
    "400 INVALID_ARGUMENT naming message.token": { status: 400, body: { error: { code: 400, status: "INVALID_ARGUMENT", details: [fcmError("INVALID_ARGUMENT"), tokenViolation] } } }
  };
  it.each(Object.keys(finalAnswers) as (keyof typeof finalAnswers)[])("ends a turn push that FCM answers %s, without retrying it or removing the token", async name => {
    const answer = finalAnswers[name];
    const { host, guest, room, stub, path } = await pair(); expect((await register(guest)).status).toBe(200);
    expect((await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).status).toBe(200);
    let sends = 0;
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => {
      if (String(input) === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 });
      sends++;
      return Response.json(answer.body, { status: answer.status });
    });
    await drain(stub);
    expect(sends).toBe(1); expect(await rows(stub)).toEqual([]);
    expect(await rows(env.PLAYERS.getByName(guest.player_id), "notification_registrations")).toHaveLength(1);
  });
  /** Each FCM answer class: what the sender returns and the one log line it writes, which never carries the token. */
  const answerClasses: [string, () => Response, string, Record<string, unknown>][] = [
    ["404 UNREGISTERED", () => Response.json({ error: { code: 404, status: "NOT_FOUND", details: [fcmError("UNREGISTERED")] } }, { status: 404 }), "invalid_token", { http_status: 404, fcm_error: "UNREGISTERED" }],
    ["403 SENDER_ID_MISMATCH", () => Response.json(finalAnswers["403 SENDER_ID_MISMATCH"].body, { status: 403 }), "rejected", { http_status: 403, fcm_error: "SENDER_ID_MISMATCH" }],
    ["400 INVALID_ARGUMENT naming message.token", () => Response.json(finalAnswers["400 INVALID_ARGUMENT naming message.token"].body, { status: 400 }), "rejected", { http_status: 400, fcm_error: "INVALID_ARGUMENT", token_field: true }],
    ["400 INVALID_ARGUMENT about our payload", () => Response.json({ error: { code: 400, status: "INVALID_ARGUMENT", details: [fcmError("INVALID_ARGUMENT"),
      { "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.data", description: "Invalid value" }] }] } }, { status: 400 }), "retry", { http_status: 400, fcm_error: "INVALID_ARGUMENT", token_field: false }],
    ["400 INVALID_ARGUMENT with no details", () => Response.json({ error: { code: 400, status: "INVALID_ARGUMENT" } }, { status: 400 }), "retry", { http_status: 400, status: "INVALID_ARGUMENT", fcm_error: "other" }],
    ["400 without a JSON body", () => new Response("bad gateway", { status: 400 }), "retry", { http_status: 400, status: "other" }],
    ["403 PERMISSION_DENIED for our credentials", () => Response.json({ error: { code: 403, status: "PERMISSION_DENIED", message: "Permission 'cloudmessaging.messages.create' denied" } }, { status: 403 }), "retry", { http_status: 403, status: "PERMISSION_DENIED", fcm_error: "other" }],
    ["403 SERVICE_DISABLED for the API", () => Response.json({ error: { code: 403, status: "PERMISSION_DENIED", details: [{ "@type": "type.googleapis.com/google.rpc.ErrorInfo", reason: "SERVICE_DISABLED" }] } }, { status: 403 }), "retry", { http_status: 403, fcm_error: "other" }],
    ["404 without UNREGISTERED", () => Response.json({ error: { code: 404, status: "NOT_FOUND" } }, { status: 404 }), "retry", { http_status: 404 }],
    ["500 INTERNAL", () => Response.json({ error: { code: 500, status: "INTERNAL", details: [fcmError("INTERNAL")] } }, { status: 500 }), "retry", { http_status: 500, fcm_error: "INTERNAL" }],
    ["an unknown error code", () => Response.json({ error: { code: 400, status: "FAILED_PRECONDITION", details: [fcmError("SOMETHING_NEW")] } }, { status: 400 }), "retry", { http_status: 400, fcm_error: "SOMETHING_NEW" }]
  ];
  it.each(answerClasses)("classifies FCM %s and logs it without the token", async (_name, answer, outcome, logged) => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => String(input) === "https://oauth2.googleapis.com/token" ?
      Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 }) : answer());
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    expect((await new FcmSender(config).send(token, epoch, makeHint("relay", "r".repeat(22), 2))).status).toBe(outcome);
    expect(warn).toHaveBeenCalledTimes(1);
    expect(JSON.parse(String(warn.mock.calls[0][0]))).toMatchObject({ event: "push_send_failed", outcome, ...logged });
    const written = JSON.stringify(warn.mock.calls);
    for (const secret of [token, epoch, "r".repeat(22), "synthetic-oauth-access-token", "denied", "description"]) expect(written).not.toContain(secret);
  });
  it("logs a push that fails before FCM answers and keeps it retryable", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => { if (String(input) === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 }); throw new TypeError("network down for " + token); });
    expect((await new FcmSender(config).send(token, epoch, makeHint("relay", "r".repeat(22), 2))).status).toBe("retry");
    vi.restoreAllMocks(); vi.spyOn(Date, "now").mockReturnValue(realNow() + 3_600_000);
    const quiet = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 500 }));
    expect((await new FcmSender(config).send(token, epoch, makeHint("relay", "r".repeat(22), 2))).status).toBe("retry");
    expect(JSON.parse(String(warn.mock.calls[0][0]))).toEqual({ event: "push_send_failed", outcome: "retry", reason: "TypeError" });
    expect(JSON.parse(String(quiet.mock.calls[0][0]))).toEqual({ event: "push_send_failed", outcome: "retry", reason: "oauth_unavailable" });
    expect(JSON.stringify([...warn.mock.calls, ...quiet.mock.calls])).not.toContain(token);
  });
  it.each(["recovery", "optout", "room-deletion"])("rechecks %s after delayed OAuth before transmitting FCM", async operation => {
    const { host, guest: account, room, path } = await pair(), player = env.PLAYERS.getByName(account.player_id);
    const roomId = room.room_id; expect((await register(account)).status).toBe(200);
    expect((await call(path + "/" + roomId + "/turns", "POST", host, turnBody(room, firstA))).status).toBe(200);
    expect(await rows(player, "notification_registrations")).toHaveLength(1);
    expect((await player.listRooms()).some(link => link.room_id === roomId)).toBe(true);
    let sends = 0, oauthCalls = 0, changed = false, mutationCode = "";
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => {
      if (String(input).includes("oauth2")) {
        oauthCalls++;
        try {
          // Stubs are I/O-context owned: obtain them inside this provider await,
          // rather than reusing the test runner's captured stub.
          const freshPlayer = env.PLAYERS.getByName(account.player_id);
          const result = operation === "recovery" ? await freshPlayer.recover(await digest(account.recovery_code), await digest(randomToken()), await digest(randomToken()), "d".repeat(64)) : operation === "optout" ? await freshPlayer.unregisterNotifications(await digest(account.device_token), epoch) : await env.ROOMS_V2.getByName(roomId).eraseForPlayer(host.player_id);
          changed = result.ok;
          if (!result.ok) mutationCode = result.code;
        } catch { mutationCode = "mutation_threw"; }
        return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 });
      }
      sends++; return Response.json({});
    });
    await player.deliverTurnNotification(makeHint("relay", roomId, 2));
    expect({ oauthCalls, changed, mutationCode }).toEqual({ oauthCalls: 1, changed: true, mutationCode: "" }); expect(sends).toBe(0);
    if (operation === "room-deletion") expect(await rows(player, "notification_registrations")).toHaveLength(1);
  });
});

describe("partner redo request notifications", () => {
  it("keeps the redo option on its own endpoint, with an exact shape, for a current registration only", async () => {
    const account = await create(), player = env.PLAYERS.getByName(account.player_id);
    expect((await categories(account, true)).status).toBe(503);
    await configured(player);
    expect((await call("/v1/notifications/categories", "POST", undefined, { schema_version: 1, binding_epoch: epoch, redo_requests: true })).status).toBe(401);
    for (const body of [{ schema_version: 2, binding_epoch: epoch, redo_requests: true }, { schema_version: 1, binding_epoch: "bad", redo_requests: true }, { schema_version: 1, binding_epoch: epoch, redo_requests: "true" },
      { schema_version: 1, binding_epoch: epoch }, { schema_version: 1, binding_epoch: epoch, redo_requests: true, token }]) expect((await call("/v1/notifications/categories", "POST", account, body)).status).toBe(400);
    expect((await categories({ ...account, device_token: randomToken() }, true)).status).toBe(401);
    for (const value of [true, false]) expect((await categories(account, value)).status).toBe(404);
    expect((await register(account)).status).toBe(200);
    const on = await categories(account, true); expect(on.status).toBe(200); expect(await on.json()).toEqual({ schema_version: 1, binding_epoch: epoch, redo_requests: true });
    expect(await rows(player, "notification_categories")).toHaveLength(1);
    // The registration request and acknowledgement keep their exact shape.
    expect(await (await register(account, epoch, token + "-rotated")).json()).toEqual({ registered: true, binding_epoch: epoch });
    expect(await rows(player, "notification_categories")).toHaveLength(1);
    const off = await categories(account, false); expect(await off.json()).toEqual({ schema_version: 1, binding_epoch: epoch, redo_requests: false });
    expect(await rows(player, "notification_categories")).toEqual([]);
    expect((await categories(account, true)).status).toBe(200);
    expect(await (await call("/v1/notifications/registration", "DELETE", account, { schema_version: 1, binding_epoch: epoch })).json()).toEqual({ unregistered: true });
    expect(await rows(player, "notification_categories")).toEqual([]);
  });
  it.each(["recovery", "erasure"])("%s clears the redo option with the registrations", async operation => {
    const account = await create(), player = env.PLAYERS.getByName(account.player_id); await configured(player);
    expect((await register(account)).status).toBe(200); expect((await categories(account, true)).status).toBe(200);
    if (operation === "recovery") {
      const body = { player_id: account.player_id, recovery_code: account.recovery_code, idempotency_key: crypto.randomUUID(), next_device_token: randomToken(), next_recovery_code: randomToken() };
      expect((await call("/v1/identity/recover", "POST", undefined, body)).status).toBe(200);
    } else expect((await call("/v1/identity", "DELETE", account)).status).toBe(200);
    expect(await rows(player, "notification_categories")).toEqual([]); expect(await rows(player, "notification_registrations")).toEqual([]);
  });
  it("sends one exact redo_requested push to the first player's opted-in device and never repeats it", async () => {
    const { host, guest, room, stub, path, after } = await redoReady();
    expect((await register(host, "i".repeat(22), "synthetic-host-second-token")).status).toBe(200); // Not opted in.
    const requested = await askRedo(path, room.room_id, guest);
    const hint = { schema_version: "1", event_id: "redo_" + requested.request!.request_id, kind: "redo_requested", room_id: room.room_id, room_family: "relay", revision: String(after.revision) };
    expect(await hints(stub)).toEqual([{ recipient: host.player_id, hint }]);
    const queued = await rows(stub);
    expect((await call(`${path}/${room.room_id}/redo`, "POST", guest, { action: "request", source: requested.source })).status).toBe(200);
    expect(await rows(stub)).toEqual(queued);
    const sent = provider(); await drain(stub);
    expect(sent.messages).toHaveLength(1); expect(sent.messages[0].token).toBe("synthetic-host-fcm-token");
    const data = sent.messages[0].data as Record<string, string>;
    expect(data).toEqual({ ...hint, binding_epoch: "h".repeat(22) }); expect(Object.keys(data)).toHaveLength(7);
    expect(Object.values(data).join("").length).toBeLessThanOrEqual(1024); expect(JSON.stringify(data).length).toBeLessThanOrEqual(2048);
    expect(sent.messages[0].android).toEqual({ priority: "HIGH", ttl: "604800s", restricted_package_name: "com.aamirazeez.afteryou" });
    expect(await rows(stub)).toEqual([]);
    expect((await call(`${path}/${room.room_id}/redo`, "POST", guest, { action: "request", source: requested.source })).status).toBe(200);
    expect(await rows(stub)).toEqual([]);
  });
  it("legacy rooms queue the same hint shape with the legacy family", async () => {
    const { host, guest, room, stub, path, after } = await redoReady(false);
    const requested = await askRedo(path, room.room_id, guest);
    expect(await hints(stub)).toEqual([{ recipient: host.player_id, hint: { schema_version: "1", event_id: "redo_" + requested.request!.request_id, kind: "redo_requested", room_id: room.room_id, room_family: "legacy", revision: String(after.revision) } }]);
    const sent = provider(); await drain(stub);
    expect(sent.messages).toHaveLength(1); expect((sent.messages[0].data as Record<string, string>).kind).toBe("redo_requested");
  });
  it.each(["decline", "cancel"] as const)("a %s before delivery cancels the push", async action => {
    const { host, guest, room, stub, path } = await redoReady();
    const requested = await askRedo(path, room.room_id, guest); expect(await rows(stub)).toHaveLength(1);
    expect((await call(`${path}/${room.room_id}/redo`, "POST", action === "decline" ? host : guest, { action, source: requested.source })).status).toBe(200);
    const sent = provider(); await drain(stub);
    expect(sent.messages).toEqual([]); expect(await rows(stub)).toEqual([]);
  });
  it("sends nothing to a device that never opted in, and consumes the hint", async () => {
    const { guest, room, stub, path } = await redoReady(true, false);
    await askRedo(path, room.room_id, guest); expect(await rows(stub)).toHaveLength(1);
    const sent = provider(); await drain(stub);
    expect(sent.messages).toEqual([]); expect(await rows(stub)).toEqual([]);
  });
  it("the second player's own turn replaces the hint with turn_ready", async () => {
    const { host, guest, room, stub, path, after } = await redoReady();
    await askRedo(path, room.room_id, guest);
    const b = await (await call(path + "/" + room.room_id + "/turns", "POST", guest, turnBody(after as RoomSnapshotV2, firstB, middle))).json<MutationV2>();
    expect(await hints(stub)).toEqual([{ recipient: host.player_id, hint: makeHint("relay", room.room_id, b.room.revision) }]);
  });
  it("accepting the redo clears its hint", async () => {
    const { host, guest, room, stub, path } = await redoReady(), requested = await askRedo(path, room.room_id, guest);
    const after = requested.source!;
    const forked = await call(path + "/" + room.room_id + "/fork", "POST", host, { base_revision: after.revision, branch: after.branch, stage_index: after.stage_index, idempotency_key: crypto.randomUUID(), redo_request_id: requested.request!.request_id });
    expect(forked.status).toBe(200);
    expect((await hints(stub)).filter(row => row.hint.kind === "redo_requested")).toEqual([]);
  });
  it("an opt-out during the provider token request cancels the send", async () => {
    const { host, guest, room, path, after } = await redoReady(), player = env.PLAYERS.getByName(host.player_id);
    const requested = await askRedo(path, room.room_id, guest);
    let sends = 0, changed = false;
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => {
      if (String(input).includes("oauth2")) {
        changed = (await env.PLAYERS.getByName(host.player_id).setNotificationCategories(await digest(host.device_token), "h".repeat(22), false)).ok;
        return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 });
      }
      sends++; return Response.json({});
    });
    await player.deliverTurnNotification(makeRedoHint("relay", room.room_id, after.revision, requested.request!.request_id));
    expect(changed).toBe(true); expect(sends).toBe(0);
  });
  it("queues nothing while notifications are off", async () => {
    const { guest, room, stub, path } = await redoReady();
    await runInDurableObject(stub, async instance => { (instance as unknown as { env: NotificationEnvironment }).env.NOTIFICATIONS_ENABLED = "false"; });
    const quiet = await askRedo(path, room.room_id, guest);
    expect(quiet.request?.status).toBe("pending"); expect(await rows(stub)).toEqual([]);
  });
  it("keeps the redo request and its hint if the alarm cannot be saved, and the alarm repairs itself", async () => {
    const { guest, room, stub, path } = await redoReady();
    await runInDurableObject(stub, async (_, ctx) => { ctx.storage.sql.exec("CREATE TRIGGER synthetic_notification_failure BEFORE INSERT ON notification_alarm BEGIN SELECT RAISE(ABORT,'synthetic_failure'); END"); });
    const offered = await (await call(`${path}/${room.room_id}/redo`, "GET", guest)).json<RedoState>();
    const requested = await call(`${path}/${room.room_id}/redo`, "POST", guest, { action: "request", source: offered.source }); expect(requested.status).toBe(200);
    const pending = await requested.json<RedoState>(); expect(pending.request?.status).toBe("pending");
    expect(await (await call(`${path}/${room.room_id}/redo`, "GET", guest)).json()).toEqual(pending);
    expect((await hints(stub)).map(row => row.hint.kind)).toEqual(["redo_requested"]);
    await runInDurableObject(stub, async (_, ctx) => { expect(await ctx.storage.getAlarm()).not.toBeNull(); ctx.storage.sql.exec("DROP TRIGGER synthetic_notification_failure"); });
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    await runInDurableObject(stub, async (_, ctx) => {
      const marker = ctx.storage.sql.exec<{ due_at: number }>("SELECT due_at FROM notification_alarm").one();
      expect(await ctx.storage.getAlarm()).toBe(marker.due_at); expect(notificationAlarmOwned(ctx.storage, "RoomV2", marker.due_at)).toBe(true);
    });
  });
  it("keeps the option out of snapshots and inside the known operational state", async () => {
    const account = await create(), player = env.PLAYERS.getByName(account.player_id); await configured(player);
    expect((await register(account)).status).toBe(200); expect((await categories(account, true)).status).toBe(200);
    const saved = value(await player.exportSnapshot(source)); expect(saved).not.toContain("notification_"); expect(saved).not.toContain(epoch);
    const restored = env.PLAYERS.getByName(randomToken(16)); expect((await restored.restoreSnapshot(saved, account.player_id)).ok).toBe(true);
    expect(await rows(restored, "notification_categories")).toEqual([]);
    await runInDurableObject(player, async (_, ctx) => {
      expect(notificationAlarmOwned(ctx.storage, "Player", null)).toBe(true);
      ctx.storage.sql.exec("UPDATE notification_categories SET data=?", JSON.stringify({ schema_version: 1, redo_requests: false, updated_at: Date.now() }));
      expect(notificationAlarmOwned(ctx.storage, "Player", null)).toBe(false);
      ctx.storage.sql.exec("DELETE FROM notification_categories");
    });
  });
  it("keeps a registration from a client that reads hosting events inside the known operational state", async () => {
    const account = await create(), player = env.PLAYERS.getByName(account.player_id); await configured(player);
    const registered = await call("/v1/notifications/registration", "POST", account, { schema_version: 1, token, binding_epoch: epoch }, { "X-AfterYou-Friend-Events": "2" });
    expect(registered.status).toBe(200);
    expect(JSON.parse((await rows(player, "notification_registrations"))[0].data).friend_events).toBe(2);
    expect((await player.exportSnapshot(source)).ok).toBe(true);
    await runInDurableObject(player, async (_, ctx) => {
      expect(notificationAlarmOwned(ctx.storage, "Player", null)).toBe(true);
      const row = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations").one().data);
      for (const bad of [{ ...row, friend_events: 3 }, { ...row, friend_events: "2" }, { ...row, extra: 1 }, { token: row.token, device_hash: row.device_hash, friend_events: 2 }]) {
        ctx.storage.sql.exec("UPDATE notification_registrations SET data=?", JSON.stringify(bad));
        expect(notificationAlarmOwned(ctx.storage, "Player", null)).toBe(false);
      }
      ctx.storage.sql.exec("UPDATE notification_registrations SET data=?", JSON.stringify(row));
    });
  });
  it("leaves turn_ready bytes unchanged and keeps the two hint kinds apart", () => {
    const turn = makeHint("relay", "r".repeat(22), 2), redo = makeRedoHint("legacy", "r".repeat(22), 2, "a".repeat(64));
    expect(JSON.stringify(turn)).toBe(`{"schema_version":"1","event_id":"relay_${"r".repeat(22)}_2","kind":"turn_ready","room_id":"${"r".repeat(22)}","room_family":"relay","revision":"2"}`);
    expect(validHint(turn) && validRoomHint(turn) && validRoomHint(redo)).toBe(true); expect(validHint(redo)).toBe(false);
    for (const bad of [{ ...redo, event_id: "legacy_" + "r".repeat(22) + "_2" }, { ...redo, event_id: "redo_" + "A".repeat(64) }, { ...redo, host_id: "h".repeat(22) }, { ...turn, kind: "redo_requested" }])
      expect(validRoomHint(bad)).toBe(false);
  });
});

const ios = { "X-AfterYou-Friend-Events": "2", "X-AfterYou-Platform": "ios", "X-AfterYou-Push-Categories": "turns,hosting" };
async function registerIos(account: Account, binding: string, suppliedToken: string, categories = "turns,hosting") {
  return call("/v1/notifications/registration", "POST", account, { schema_version: 1, token: suppliedToken, binding_epoch: binding }, { ...ios, "X-AfterYou-Push-Categories": categories });
}
/** The message every token got before IOS_PUSH_ENABLED existed, built the old way. */
function androidBytes(suppliedToken: string, binding: string, hint: PushHint): string {
  return JSON.stringify({ message: { token: suppliedToken, data: { ...hint, binding_epoch: binding }, android: { priority: "HIGH", ttl: "604800s", restricted_package_name: "com.aamirazeez.afteryou" } } });
}
async function hex(value: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))), byte => byte.toString(16).padStart(2, "0")).join("");
}
const room22 = "r".repeat(22), host22 = "h".repeat(22);
const sampleHints: PushHint[] = [makeHint("relay", room22, 4), makeRedoHint("legacy", room22, 3, "a".repeat(64)), makeFriendRoomHint(host22, { api_version: 2, room_id: room22 }, 5, `${host22}_5`)];

describe("iOS alert push behind IOS_PUSH_ENABLED", () => {
  it("sends Android tokens, and iOS tokens while the flag is off, exactly today's bytes", async () => {
    const sent = provider();
    for (const flag of [undefined, "false", "TRUE", " true", "1", "true"]) {
      const sender = new FcmSender({ ...config, ...(flag === undefined ? {} : { IOS_PUSH_ENABLED: flag }) });
      for (const hint of sampleHints) {
        expect((await sender.send(token, epoch, hint)).status).toBe("sent");
        expect((await sender.send(token, epoch, hint, () => true, "android")).status).toBe("sent");
        if (flag !== "true") expect((await sender.send(token, epoch, hint, () => true, "ios")).status).toBe("sent");
      }
    }
    expect(sent.raw).toHaveLength(6 * 3 * 2 + 5 * 3);
    const expected = new Set(sampleHints.map(hint => androidBytes(token, epoch, hint)));
    for (const body of sent.raw) expect(expected.has(body)).toBe(true);
    expect(sent.raw[0]).toBe(`{"message":{"token":"${token}","data":{"schema_version":"1","event_id":"relay_${room22}_4","kind":"turn_ready","room_id":"${room22}","room_family":"relay","revision":"4","binding_epoch":"${epoch}"},"android":{"priority":"HIGH","ttl":"604800s","restricted_package_name":"com.aamirazeez.afteryou"}}}`);
  });
  it("gives an iOS token an APNs alert with the app's generic words, its grouping key and the exact hint keys", async () => {
    const sent = provider(), sender = new FcmSender({ ...config, IOS_PUSH_ENABLED: "true" });
    const titles = ["Your friend left a turn", "Your friend asked for a redo", "Friend rooms"];
    for (const [index, hint] of sampleHints.entries()) {
      expect((await sender.send(token, epoch, hint, () => true, "ios")).status).toBe("sent");
      const message = sent.messages[index], digest = await hex(`${hint.room_family}:${hint.room_id}:${hint.kind}`);
      expect(message).toEqual({ token, data: { ...hint, binding_epoch: epoch }, android: { priority: "HIGH", ttl: "604800s", restricted_package_name: "com.aamirazeez.afteryou" },
        apns: { headers: { "apns-push-type": "alert", "apns-priority": "10", "apns-expiration": String(Math.floor(Date.now() / 1000) + 604800), "apns-collapse-id": digest },
          payload: { aps: { alert: { title: titles[index], body: "Open After You to see your shared moment." }, sound: "default", "thread-id": `after_you_update:${digest}` } } } });
      // The plugin drops a payload with any custom key beyond the hint and binding_epoch, and
      // content-available would make it post a second, local notification.
      const apns = message.apns as { headers: Record<string, string>; payload: Record<string, Record<string, unknown>> };
      expect(Object.keys(apns.payload)).toEqual(["aps"]); expect(apns.payload.aps["content-available"]).toBeUndefined();
      expect(apns.headers["apns-collapse-id"]).toMatch(/^[0-9a-f]{64}$/);
      // Generic text only: no room, host or event identifier reaches the visible alert.
      for (const id of [hint.room_id, hint.event_id, "host_id" in hint ? hint.host_id : hint.room_id]) expect(JSON.stringify(apns.payload.aps.alert)).not.toContain(id);
    }
    // The same room and kind share one key; another kind or room does not.
    const turnKey = (sent.messages[0].apns as { headers: Record<string, string> }).headers["apns-collapse-id"];
    expect(turnKey).toBe(await hex(`relay:${room22}:turn_ready`)); expect(turnKey).not.toBe(await hex(`relay:${room22}:redo_requested`));
  });
  it("records the platform only from the iOS headers and refuses a malformed pair", async () => {
    const account = await create(), player = env.PLAYERS.getByName(account.player_id); await configured(player);
    expect((await register(account)).status).toBe(200);
    expect(Object.keys(JSON.parse((await rows(player, "notification_registrations"))[0].data))).toEqual(["token", "device_hash", "updated_at"]);
    for (const headers of <Record<string, string>[]>[{ "X-AfterYou-Platform": "ios" }, { "X-AfterYou-Platform": "android", "X-AfterYou-Push-Categories": "turns" }, { "X-AfterYou-Platform": "IOS", "X-AfterYou-Push-Categories": "turns" },
      { "X-AfterYou-Platform": "ios", "X-AfterYou-Push-Categories": "hosting,turns" }, { "X-AfterYou-Platform": "ios", "X-AfterYou-Push-Categories": "turns, hosting" }, { "X-AfterYou-Platform": "ios", "X-AfterYou-Push-Categories": "" }])
      expect((await call("/v1/notifications/registration", "POST", account, { schema_version: 1, token, binding_epoch: epoch }, headers)).status).toBe(400);
    // A categories header alone is ignored: only the platform header marks an iOS row.
    expect((await call("/v1/notifications/registration", "POST", account, { schema_version: 1, token, binding_epoch: epoch }, { "X-AfterYou-Push-Categories": "turns" })).status).toBe(200);
    expect(Object.keys(JSON.parse((await rows(player, "notification_registrations"))[0].data))).toEqual(["token", "device_hash", "updated_at"]);
    for (const categories of ["turns,hosting", "turns", "hosting", "none"]) {
      expect((await registerIos(account, epoch, token, categories)).status).toBe(200);
      const row = JSON.parse((await rows(player, "notification_registrations"))[0].data);
      expect(row).toEqual({ token, device_hash: row.device_hash, updated_at: row.updated_at, friend_events: 2, platform: "ios", categories });
    }
    expect((await player.exportSnapshot(source)).ok).toBe(true);
    await runInDurableObject(player, async (_, ctx) => {
      expect(notificationAlarmOwned(ctx.storage, "Player", null)).toBe(true);
      const row = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations").one().data);
      const { platform, categories, ...base } = row;
      for (const bad of [{ ...base, platform }, { ...base, categories }, { ...row, platform: "android" }, { ...row, categories: "all" }]) {
        ctx.storage.sql.exec("UPDATE notification_registrations SET data=?", JSON.stringify(bad));
        expect(notificationAlarmOwned(ctx.storage, "Player", null)).toBe(false);
      }
      ctx.storage.sql.exec("UPDATE notification_registrations SET data=?", JSON.stringify(row));
      expect(notificationAlarmOwned(ctx.storage, "Player", null)).toBe(true);
    });
  });
  it("delivers one turn as an alert to the iOS phone and today's bytes to the Android phone", async () => {
    const { host, guest, room, stub, path } = await pair(); await configured(env.PLAYERS.getByName(host.player_id), { IOS_PUSH_ENABLED: "true" });
    expect((await register(host, "h".repeat(22), "synthetic-host-android-token")).status).toBe(200);
    expect((await registerIos(host, "i".repeat(22), "synthetic-host-iphone-token")).status).toBe(200);
    const a = await (await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).json<MutationV2>();
    await drain(stub);
    await (await call(path + "/" + room.room_id + "/turns", "POST", guest, turnBody(a.room, firstB, middle))).json<MutationV2>();
    const hint = (await hints(stub))[0].hint as PushHint;
    const sent = provider(); await drain(stub);
    expect(sent.raw).toHaveLength(2);
    expect(sent.raw).toContain(androidBytes("synthetic-host-android-token", "h".repeat(22), hint));
    const iphone = sent.messages.find(message => message.token === "synthetic-host-iphone-token")!;
    expect(iphone.data).toEqual({ ...hint, binding_epoch: "i".repeat(22) });
    expect((iphone.apns as { payload: { aps: { alert: { title: string } } } }).payload.aps.alert.title).toBe("Your friend left a turn");
    expect(await rows(stub)).toEqual([]);
  });
  it("applies an iOS phone's turn opt-out only while the flag is on, and never to Android", async () => {
    for (const flag of ["true", undefined]) {
      const { host, guest, room, stub, path } = await pair(); await configured(env.PLAYERS.getByName(host.player_id), { IOS_PUSH_ENABLED: flag });
      expect((await register(host, "h".repeat(22), "synthetic-host-android-token")).status).toBe(200);
      expect((await registerIos(host, "i".repeat(22), "synthetic-host-hosting-only", "hosting")).status).toBe(200);
      expect((await registerIos(host, "j".repeat(22), "synthetic-host-nothing-on", "none")).status).toBe(200);
      const a = await (await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).json<MutationV2>();
      await drain(stub);
      await (await call(path + "/" + room.room_id + "/turns", "POST", guest, turnBody(a.room, firstB, middle))).json<MutationV2>();
      const hint = (await hints(stub))[0].hint as PushHint;
      const sent = provider(); await drain(stub);
      if (flag) expect(sent.raw).toEqual([androidBytes("synthetic-host-android-token", "h".repeat(22), hint)]);
      // Flag off: every phone gets today's data-only message; the app filters it, as on Android.
      else expect(sent.raw.sort()).toEqual([androidBytes("synthetic-host-android-token", "h".repeat(22), hint), androidBytes("synthetic-host-hosting-only", "i".repeat(22), hint), androidBytes("synthetic-host-nothing-on", "j".repeat(22), hint)].sort());
      expect(await rows(stub)).toEqual([]);
      sent.spy.mockRestore(); await reset();
    }
  });
  it("sends a redo request as an alert only to an iOS phone with turns on", async () => {
    const { host, guest, room, stub, path, after } = await redoReady();
    await configured(env.PLAYERS.getByName(host.player_id), { IOS_PUSH_ENABLED: "true" });
    expect((await registerIos(host, "i".repeat(22), "synthetic-host-iphone-turns", "turns")).status).toBe(200);
    expect((await categories(host, true, "i".repeat(22))).status).toBe(200);
    expect((await registerIos(host, "j".repeat(22), "synthetic-host-iphone-hosting", "hosting")).status).toBe(200);
    expect((await categories(host, true, "j".repeat(22))).status).toBe(200);
    const requested = await askRedo(path, room.room_id, guest);
    const sent = provider(); await drain(stub);
    const hint = makeRedoHint("relay", room.room_id, after.revision, requested.request!.request_id);
    expect(sent.messages.map(message => message.token).sort()).toEqual(["synthetic-host-fcm-token", "synthetic-host-iphone-turns"]);
    expect(sent.raw).toContain(androidBytes("synthetic-host-fcm-token", "h".repeat(22), hint));
    const iphone = sent.messages.find(message => message.token === "synthetic-host-iphone-turns")!;
    expect((iphone.apns as { payload: { aps: { alert: { title: string } } } }).payload.aps.alert.title).toBe("Your friend asked for a redo");
  });
});
