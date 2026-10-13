import { env } from "cloudflare:workers";
import { runInDurableObject, runDurableObjectAlarm, reset } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, randomToken, type RoomSnapshot, type Outcome } from "../src/protocol";
import { FcmSender, makeHint, makeRedoHint, validHint, validRoomHint, type NotificationEnvironment } from "../src/notifications";
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
  }
  configuredEnvironments.clear();
  vi.restoreAllMocks(); await reset();
});
async function configured(stub: Target): Promise<void> {
  await runInDurableObject(stub, async instance => {
    const target = (instance as unknown as { env: NotificationEnvironment }).env;
    if (!configuredEnvironments.has(target)) configuredEnvironments.set(target, { NOTIFICATIONS_ENABLED: target.NOTIFICATIONS_ENABLED, FCM_SERVICE_ACCOUNT_JSON: target.FCM_SERVICE_ACCOUNT_JSON });
    Object.assign(target, config);
  });
}
async function call(path: string, method: string, account?: Account, body?: unknown): Promise<Response> {
  const settings: Env = { ...env }; Object.assign(settings, { V2_ROOMS_ENABLED: "true" });
  return worker.fetch(new Request("https://afteryou.test" + path, { method, headers: { "CF-Connecting-IP": "198.18.0." + ++address,
    "Content-Type": "application/json", ...(account ? { "X-Player-Id": account.player_id, Authorization: `Bearer ${account.device_token}` } : {}) },
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
  const messages: Record<string, unknown>[] = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    expect(init?.redirect).toBe("manual");
    if (String(input) === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 });
    expect(String(input)).toBe("https://fcm.googleapis.com/v1/projects/afteryou-synthetic/messages:send");
    messages.push(JSON.parse(String(init?.body)).message);
    return status === 200 ? Response.json({ name: "projects/afteryou-synthetic/messages/synthetic" }) : Response.json({ error: { details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: status === 404 ? "UNREGISTERED" : "UNAVAILABLE" }] } }, { status, headers: { "Retry-After": "120" } });
  });
  return { messages, spy };
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
  it("rolls back turn, receipt and outbox together if local alarm persistence fails", async () => {
    const { host, room, stub, path } = await pair();
    const before = await (await call(path + "/" + room.room_id, "GET", host)).json<RoomSnapshotV2>();
    await runInDurableObject(stub, async (_, ctx) => { ctx.storage.sql.exec("CREATE TRIGGER synthetic_notification_failure BEFORE INSERT ON notification_alarm BEGIN SELECT RAISE(ABORT,'synthetic_failure'); END"); });
    expect((await call(path + "/" + room.room_id + "/turns", "POST", host, turnBody(room, firstA))).status).toBe(503);
    const after = await (await call(path + "/" + room.room_id, "GET", host)).json<RoomSnapshotV2>(); expect(after).toEqual(before); expect(await rows(stub)).toEqual([]);
    await runInDurableObject(stub, async (_, ctx) => { expect(ctx.storage.sql.exec("SELECT * FROM turns").toArray()).toEqual([]); expect(ctx.storage.sql.exec("SELECT * FROM operations").toArray()).toEqual([]); expect(await ctx.storage.getAlarm()).toBeNull(); ctx.storage.sql.exec("DROP TRIGGER synthetic_notification_failure"); });
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
  it("rolls the request and its hint back together if the alarm cannot be saved", async () => {
    const { guest, room, stub, path } = await redoReady();
    await runInDurableObject(stub, async (_, ctx) => { ctx.storage.sql.exec("CREATE TRIGGER synthetic_notification_failure BEFORE INSERT ON notification_alarm BEGIN SELECT RAISE(ABORT,'synthetic_failure'); END"); });
    const offered = await (await call(`${path}/${room.room_id}/redo`, "GET", guest)).json<RedoState>();
    expect((await call(`${path}/${room.room_id}/redo`, "POST", guest, { action: "request", source: offered.source })).status).toBe(503);
    expect(await (await call(`${path}/${room.room_id}/redo`, "GET", guest)).json()).toEqual(offered);
    expect(await rows(stub)).toEqual([]);
    await runInDurableObject(stub, async (_, ctx) => { expect(await ctx.storage.getAlarm()).toBeNull(); ctx.storage.sql.exec("DROP TRIGGER synthetic_notification_failure"); });
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
  it("leaves turn_ready bytes unchanged and keeps the two hint kinds apart", () => {
    const turn = makeHint("relay", "r".repeat(22), 2), redo = makeRedoHint("legacy", "r".repeat(22), 2, "a".repeat(64));
    expect(JSON.stringify(turn)).toBe(`{"schema_version":"1","event_id":"relay_${"r".repeat(22)}_2","kind":"turn_ready","room_id":"${"r".repeat(22)}","room_family":"relay","revision":"2"}`);
    expect(validHint(turn) && validRoomHint(turn) && validRoomHint(redo)).toBe(true); expect(validHint(redo)).toBe(false);
    for (const bad of [{ ...redo, event_id: "legacy_" + "r".repeat(22) + "_2" }, { ...redo, event_id: "redo_" + "A".repeat(64) }, { ...redo, host_id: "h".repeat(22) }, { ...turn, kind: "redo_requested" }])
      expect(validRoomHint(bad)).toBe(false);
  });
});
