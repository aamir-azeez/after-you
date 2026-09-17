import { env } from "cloudflare:workers";
import { reset, runInDurableObject, runDurableObjectAlarm, evictDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, randomToken, type Outcome } from "../src/protocol";
import { RELAY_KEY } from "../src/v2/chapters";
import { PRESENCE_TTL_MS } from "../src/presence";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Room = { room_id: string; invite_code: string };
const COMMIT = "a".repeat(40), SESSION = "a".repeat(36), NEXT_SESSION = "b".repeat(36);
let address = 0;
const realNow = Date.now.bind(Date);
const configuredEnvironments = new Map<{ PRESENCE_ENABLED?: string }, string | undefined>();
const value = <T>(r: Outcome<T>): T => { if (!r.ok) throw new Error(r.code); return r.value; };
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}) {
  const configured: Env = { ...env };
  Object.assign(configured, { PRESENCE_ENABLED: "true", V2_ROOMS_ENABLED: "true", ...overrides });
  return worker.fetch(new Request("https://game.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.1." + ++address, ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function create() { const r = await call("/v1/identity", "POST", undefined, {}); expect(r.status).toBe(201); return r.json<Account>(); }
async function configured(a: Account, enabled = "true") {
  await runInDurableObject(env.PLAYERS.getByName(a.player_id), instance => {
    const target = Reflect.get(instance, "env") as { PRESENCE_ENABLED?: string };
    if (!configuredEnvironments.has(target)) configuredEnvironments.set(target, target.PRESENCE_ENABLED);
    target.PRESENCE_ENABLED = enabled;
  });
}
async function heartbeat(a: Account, online = true, session = SESSION, overrides: Record<string, unknown> = {}) {
  return call("/v1/presence", "POST", a, { schema_version: 1, session_id: session, online }, overrides);
}
async function pair(version = 1, joined = true) {
  const host = await create(), guest = await create(); await configured(host); await configured(guest);
  const prefix = `/v${version}/rooms`;
  const made = await call(prefix, "POST", host, { idempotency_key: crypto.randomUUID(), ...(version === 2 ? RELAY_KEY : {}) }); expect(made.status).toBe(200);
  const room = await made.json<Room>();
  if (joined) expect((await call(prefix + "/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
  return { host, guest, room, prefix, path: prefix + "/" + room.room_id };
}
async function recover(a: Account) {
  const next = { ...a, device_token: randomToken(), recovery_code: randomToken() };
  expect((await call("/v1/identity/recover", "POST", undefined, { player_id: a.player_id, recovery_code: a.recovery_code, idempotency_key: crypto.randomUUID(), next_device_token: next.device_token, next_recovery_code: next.recovery_code })).status).toBe(200);
  return next;
}
beforeEach(() => { vi.spyOn(Date, "now").mockReturnValue(realNow() + 3_600_000); });
afterEach(async () => {
  for (const [target, original] of configuredEnvironments) {
    if (original === undefined) delete target.PRESENCE_ENABLED; else target.PRESENCE_ENABLED = original;
  }
  configuredEnvironments.clear(); vi.restoreAllMocks(); await reset();
});

describe("short-lived room-scoped presence", () => {
  it("defaults off, permits offline cleanup, and rejects unauthenticated or malformed requests", async () => {
    const a = await create();
    expect((await heartbeat(a)).status).toBe(503);
    expect(await (await heartbeat(a, false)).json()).toEqual({ schema_version: 1, heartbeat_seconds: 30, expires_after_seconds: 90 });
    expect((await call("/v1/presence", "POST", undefined, {})).status).toBe(401);
    for (const body of [{ schema_version: 2, session_id: SESSION, online: true }, { schema_version: 1, session_id: "A".repeat(36), online: true }, { schema_version: 1, session_id: crypto.randomUUID(), online: true }, { schema_version: 1, session_id: SESSION, online: 1 }, { schema_version: 1, session_id: SESSION, online: true, owner: a.player_id }]) {
      expect((await call("/v1/presence", "POST", a, body)).status).toBe(400);
    }
    expect((await call("/v1/presence", "GET", a)).status).toBe(405);
    expect((await call("/v1/presence/" + a.player_id, "GET", a)).status).toBe(404);
    expect((await heartbeat({ ...a, device_token: randomToken() })).status).toBe(401);
    await configured(a);
    expect((await heartbeat(a)).status).toBe(200);
    await configured(a, "false"); expect((await heartbeat(a)).status).toBe(503);
    expect((await heartbeat(a, false)).status).toBe(200);
    expect(await env.PLAYERS.getByName(a.player_id).presenceExpiry(a.player_id)).toBe(0);
  });
  it.each([1, 2])("keeps v%s room state unchanged and reveals only the paired member's remaining TTL", async version => {
    const p = await pair(version, false), outsider = await create();
    const waiting = await call(p.path + "/presence", "GET", p.host);
    expect(await waiting.json()).toEqual({ schema_version: 1, partner_joined: false, partner_online: false, expires_after_seconds: 0 });
    expect((await call(p.path + "/presence")).status).toBe(401);
    expect((await call(p.path + "/presence", "GET", outsider)).status).toBe(404);
    expect((await call(p.prefix + "/join", "POST", p.guest, { invite_code: p.room.invite_code })).status).toBe(200);
    const before = await (await call(p.path, "GET", p.host)).json();
    expect(await (await call(p.path + "/presence", "GET", p.host)).json()).toEqual({ schema_version: 1, partner_joined: true, partner_online: false, expires_after_seconds: 0 });
    const ack = await heartbeat(p.guest); expect(ack.status).toBe(200); expect(await ack.json()).toEqual({ schema_version: 1, heartbeat_seconds: 30, expires_after_seconds: 90 });
    const online = await (await call(p.path + "/presence", "GET", p.host)).json<Record<string, unknown>>();
    expect(online).toEqual({ schema_version: 1, partner_joined: true, partner_online: true, expires_after_seconds: expect.any(Number) });
    expect(Number(online.expires_after_seconds)).toBeGreaterThan(85); expect(Number(online.expires_after_seconds)).toBeLessThanOrEqual(90);
    expect(await (await call(p.path + "/presence", "GET", p.guest)).json()).toMatchObject({ partner_online: false, expires_after_seconds: 0 });
    expect((await call(p.path + "/presence", "GET", p.host, undefined, { PRESENCE_ENABLED: "false" })).status).toBe(503);
    expect(await (await call(p.path, "GET", p.host)).json()).toEqual(before);
    expect((await heartbeat(p.guest, false)).status).toBe(200);
    expect(await (await call(p.path + "/presence", "GET", p.host)).json()).toMatchObject({ partner_online: false, expires_after_seconds: 0 });
  });
  it("bounds eight independent sessions and stale background messages cannot hide a newer session", async () => {
    const p = await pair();
    for (let i = 0; i < 8; i++) expect((await heartbeat(p.guest, true, i.toString(16).padStart(36, "0"))).status).toBe(200);
    expect((await heartbeat(p.guest, true, NEXT_SESSION)).status).toBe(409);
    expect((await heartbeat(p.guest, true, "0".repeat(36))).status).toBe(200);
    expect((await heartbeat(p.guest, false, "0".repeat(36))).status).toBe(200);
    expect((await heartbeat(p.guest, true, NEXT_SESSION)).status).toBe(200);
    expect((await heartbeat(p.guest, false, "0".repeat(36))).status).toBe(200);
    expect(await (await call(p.path + "/presence", "GET", p.host)).json()).toMatchObject({ partner_online: true });
    for (let i = 1; i < 8; i++) expect((await heartbeat(p.guest, false, i.toString(16).padStart(36, "0"))).status).toBe(200);
    expect((await heartbeat(p.guest, false, NEXT_SESSION)).status).toBe(200);
    expect(await (await call(p.path + "/presence", "GET", p.host)).json()).toMatchObject({ partner_online: false });
  });
  it("survives eviction, expires at ninety seconds, and its consumed alarm removes all operational rows", async () => {
    const p = await pair(); expect((await heartbeat(p.guest)).status).toBe(200);
    const target = env.PLAYERS.getByName(p.guest.player_id), expires = await target.presenceExpiry(p.guest.player_id);
    await evictDurableObject(target);
    expect(await target.presenceExpiry(p.guest.player_id)).toBe(expires);
    vi.spyOn(Date, "now").mockReturnValue(expires - 1);
    expect(await (await call(p.path + "/presence", "GET", p.host)).json()).toMatchObject({ partner_online: true, expires_after_seconds: 1 });
    vi.spyOn(Date, "now").mockReturnValue(expires);
    expect(await (await call(p.path + "/presence", "GET", p.host)).json()).toMatchObject({ partner_online: false, expires_after_seconds: 0 });
    expect(await runDurableObjectAlarm(target)).toBe(true);
    await runInDurableObject(target, async (instance, ctx) => {
      expect(ctx.storage.sql.exec("SELECT * FROM presence_leases").toArray()).toEqual([]);
      expect(ctx.storage.sql.exec("SELECT * FROM presence_alarm").toArray()).toEqual([]);
      expect(await ctx.storage.getAlarm()).toBeNull();
      await instance.alarm(); expect(await ctx.storage.getAlarm()).toBeNull();
    });
  });
  it("preserves a live lease on an early alarm and expires it without a presence read", async () => {
    const a = await create(); await configured(a); expect((await heartbeat(a)).status).toBe(200);
    const target = env.PLAYERS.getByName(a.player_id), expires = await target.presenceExpiry(a.player_id);
    expect(await runDurableObjectAlarm(target)).toBe(true);
    expect(await target.presenceExpiry(a.player_id)).toBe(expires);
    vi.spyOn(Date, "now").mockReturnValue(expires + 1);
    expect(await runDurableObjectAlarm(target)).toBe(true);
    await runInDurableObject(target, async (_, ctx) => { expect(ctx.storage.sql.exec("SELECT * FROM presence_leases").toArray()).toEqual([]); expect(await ctx.storage.getAlarm()).toBeNull(); });
  });
  it("revokes all presence on recovery and reauthenticates an update/read after the limiter yields", async () => {
    const p = await pair(); expect((await heartbeat(p.guest)).status).toBe(200); const next = await recover(p.guest);
    expect((await heartbeat(p.guest)).status).toBe(401);
    expect(await (await call(p.path + "/presence", "GET", p.host)).json()).toMatchObject({ partner_online: false });
    expect((await heartbeat(next)).status).toBe(200);
    let current: Account | null = null;
    expect((await heartbeat(next, true, NEXT_SESSION, { PLAYER_LIMITER: { limit: async () => { current = await recover(next); return { success: true }; } } })).status).toBe(401);
    expect(await env.PLAYERS.getByName(p.guest.player_id).presenceExpiry(p.guest.player_id)).toBe(0);
    expect((await call(p.path + "/presence", "GET", current!, undefined, { PLAYER_LIMITER: { limit: async () => { await recover(current!); return { success: true }; } } })).status).toBe(401);
  });
  it.each([1, 2])("honors both-direction blocks, partner deletion and room deletion for v%s", async version => {
    const p = await pair(version); expect((await heartbeat(p.guest)).status).toBe(200);
    expect((await call("/v1/safety/block", "POST", p.guest, { schema_version: 1, room_family: version === 1 ? "legacy" : "relay", room_id: p.room.room_id })).status).toBe(200);
    for (const actor of [p.host, p.guest]) expect((await call(p.path + "/presence", "GET", actor)).status).toBe(403);
    expect((await call("/v1/safety/blocks/" + p.host.player_id, "DELETE", p.guest)).status).toBe(200);
    expect((await call("/v1/identity", "DELETE", p.guest)).status).toBe(200);
    expect(await env.PLAYERS.getByName(p.guest.player_id).presenceExpiry(p.guest.player_id)).toBe(0);
    expect((await call(p.path + "/presence", "GET", p.host)).status).toBe(404);
    expect((await heartbeat(p.guest)).status).toBe(401);
  });
  it("rechecks deletion and blocks after a deferred partner read instead of returning stale presence", async () => {
    for (const action of ["block", "delete"] as const) {
      const p = await pair(); expect((await heartbeat(p.guest)).status).toBe(200);
      const players = { getByName: (id: string) => {
        const target = env.PLAYERS.getByName(id);
        return {
          authorize: (hash: string) => target.authorize(hash),
          presenceExpiry: async (owner: string) => {
            const expires = await target.presenceExpiry(owner);
            if (action === "delete") value(await env.ROOMS.getByName(p.room.room_id).eraseForPlayer(p.guest.player_id));
            else value(await env.SAFETY_PROFILES.getByName(p.guest.player_id).setBlock(p.guest.player_id, await digest(p.guest.device_token), p.host.player_id, true));
            return expires;
          }
        };
      } };
      expect((await call(p.path + "/presence", "GET", p.host, undefined, { PLAYERS: players })).status).toBe(action === "delete" ? 404 : 403);
    }
  });
  it("omits leases from existing portable formats and restores offline without relaxing unknown storage holds", async () => {
    const a = await create(); await configured(a); expect((await heartbeat(a)).status).toBe(200);
    const source = env.PLAYERS.getByName(a.player_id), serialized = value(await source.exportSnapshot(COMMIT));
    const archive = JSON.parse(serialized); expect(archive.payload.format_version).toBe(1); expect(archive.payload.tables.map((t: { name: string }) => t.name)).toEqual(["identity", "rooms", "creations"]);
    const target = env.PLAYERS.getByName(randomToken(16)); value(await target.restoreSnapshot(serialized, a.player_id));
    expect(await target.presenceExpiry(a.player_id)).toBe(0); expect(await target.authorize(await digest(a.device_token))).toBe(true);
    const before = JSON.parse(value(await source.exportSnapshot(COMMIT))).payload.tables;
    await runInDurableObject(source, async (_, ctx) => { ctx.storage.sql.exec("CREATE TABLE unexpected_presence (data TEXT)"); });
    expect(await source.exportSnapshot(COMMIT)).toMatchObject({ ok: false, code: "unsupported_storage_schema" });
    await runInDurableObject(source, async (_, ctx) => { ctx.storage.sql.exec("DROP TABLE unexpected_presence"); ctx.storage.sql.exec("UPDATE presence_leases SET session_id='bad'"); });
    expect(await source.exportSnapshot(COMMIT)).toMatchObject({ ok: false, code: "unsupported_storage_alarm" });
    expect(JSON.parse(value(await target.exportSnapshot(COMMIT))).payload.tables).toEqual(before);
  });
  it("does not overwrite an unknown alarm and keeps the normal player rate limit", async () => {
    const a = await create(); await configured(a); const target = env.PLAYERS.getByName(a.player_id), due = Date.now() + PRESENCE_TTL_MS;
    await runInDurableObject(target, async (_, ctx) => { await ctx.storage.setAlarm(due); });
    expect((await heartbeat(a)).status).toBe(503);
    await runInDurableObject(target, async (_, ctx) => { expect(await ctx.storage.getAlarm()).toBe(due); expect(ctx.storage.sql.exec("SELECT * FROM presence_leases").toArray()).toEqual([]); });
    expect(await target.exportSnapshot(COMMIT)).toMatchObject({ ok: false, code: "unsupported_storage_alarm" });
    expect((await heartbeat(a, true, SESSION, { PLAYER_LIMITER: { limit: async () => ({ success: false }) } })).status).toBe(429);
  });
});
