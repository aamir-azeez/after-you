import { env } from "cloudflare:workers";
import { reset, runInDurableObject, runDurableObjectAlarm, evictDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, canonicalJson, randomToken } from "../src/protocol";
import { readErasure, writeErasure, type ErasureJob } from "../src/account-erasure";
import { TERMS_VERSION } from "../src/public-policy";
type Account = { player_id: string; device_token: string; recovery_code: string };
const realNow = Date.now.bind(Date);
const originals = new Map<Record<string, unknown>, Record<string, unknown>>(); let address = 0;
beforeEach(() => { vi.spyOn(Date, "now").mockReturnValue(realNow() + 3600000); });
afterEach(async () => { for (const [config, original] of originals) for (const [key, val] of Object.entries(original)) { if (val === undefined) delete config[key]; else config[key] = val; } originals.clear(); vi.restoreAllMocks(); await reset(); });
async function call(path: string, method = "GET", account?: Account, body?: unknown) {
  return worker.fetch(new Request("https://game.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.20.0." + ++address, ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), env);
}
const create = async () => { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); };
async function configured(a: Account) {
  const stub = env.SAFETY_PROFILES.getByName(a.player_id);
  await runInDurableObject(stub, async instance => {
    const config = (instance as unknown as { env: Record<string, unknown> }).env;
    const changes = { REVENUECAT_DELETION_ENABLED: "true", REVENUECAT_SECRET_KEY: "synthetic-only", REVENUECAT_PROJECT_ID: "projSynthetic" };
    if (!originals.has(config)) originals.set(config, Object.fromEntries(Object.keys(changes).map(key => [key, config[key]])));
    Object.assign(config, changes);
  }); return stub;
}
async function job(a: Account) { return runInDurableObject(env.SAFETY_PROFILES.getByName(a.player_id), async (_, ctx) => readErasure(ctx.storage)); }
async function due(a: Account) {
  const stub = env.SAFETY_PROFILES.getByName(a.player_id);
  await runInDurableObject(stub, async (_, ctx) => { const current = readErasure(ctx.storage)!; current.next_at = Date.now(); writeErasure(ctx.storage, current); });
  // Alarm remains in the real clock's future; invoke the documented helper once.
  await runDurableObjectAlarm(stub);
}
describe("durable account and provider erasure", () => {
  it("rejects a stale DELETE after recovery during rate limiting, without room or provider deletion", async () => {
    const a = await create(); await configured(a);
    const created = await call("/v1/rooms", "POST", a, { idempotency_key: crypto.randomUUID() }); expect(created.status).toBe(200);
    const room = await created.json<{ room_id: string }>();
    const rotated = { player_id: a.player_id, device_token: randomToken(), recovery_code: randomToken() };
    const provider = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 200 }));
    let delayed = 0;
    const settings = { ...env, PLAYER_LIMITER: { limit: async () => {
      delayed++;
      const response = await call("/v1/identity/recover", "POST", undefined, { player_id: a.player_id, recovery_code: a.recovery_code, idempotency_key: crypto.randomUUID(), next_device_token: rotated.device_token, next_recovery_code: rotated.recovery_code });
      expect(response.status).toBe(200); return { success: true };
    } } } as unknown as Env;
    const response = await worker.fetch(new Request("https://game.test/v1/identity", { method: "DELETE", headers: { "X-Player-Id": a.player_id, Authorization: "Bearer " + a.device_token } }), settings);
    expect(delayed).toBe(1); expect(response.status).toBe(401); expect(provider).not.toHaveBeenCalled(); expect(await job(a)).toBeNull();
    expect((await call("/v1/identity", "GET", rotated)).status).toBe(200);
    expect((await call("/v1/rooms/" + room.room_id, "GET", rotated)).status).toBe(200);
  });
  it("retains only hashed completion evidence for lost DELETE replies, then ACK erases it idempotently", async () => {
    const a = await create(); await call("/v1/safety/terms", "POST", a, { schema_version: 1, terms_version: TERMS_VERSION });
    const stub = await configured(a); const provider = vi.spyOn(globalThis, "fetch").mockImplementation(async (url, options) => {
      expect(String(url)).toBe("https://api.revenuecat.com/v2/projects/projSynthetic/customers/" + a.player_id); expect(options?.method).toBe("DELETE"); expect(options?.redirect).toBe("manual"); return new Response(null, { status: 200 });
    });
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(200);
    expect((await call("/v1/identity", "GET", a)).status).toBe(401);
    expect((await call("/v1/rooms", "GET", a)).status).toBe(401);
    await evictDurableObject(stub);
    expect(await (await call("/v1/identity", "DELETE", a)).json()).toEqual({ deleted: true }); expect(provider).toHaveBeenCalledTimes(1);
    const archive = await stub.exportSnapshot(a.player_id); expect(archive).not.toContain(a.device_token); expect(archive).not.toContain(a.recovery_code);
    expect(await job(a)).toMatchObject({ state: "complete", next_at: null, device_hash: await digest(a.device_token) });
    vi.spyOn(Date, "now").mockReturnValue(realNow() + 60 * 86400000);
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(200);
    expect((await call("/v1/identity/deletion-ack", "POST", { ...a, device_token: "x".repeat(43) }, { schema_version: 1 })).status).toBe(401);
    for (let i = 0; i < 2; i++) expect(await (await call("/v1/identity/deletion-ack", "POST", a, { schema_version: 1 })).json()).toEqual({ schema_version: 1, acknowledged: true });
    expect(await job(a)).toBeNull(); expect((await call("/v1/identity", "DELETE", a)).status).toBe(401);
  });
  it("holds provider failure durably and an alarm finishes cloud cleanup after the request closes", async () => {
    const a = await create(); await configured(a); const provider = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 503 }));
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(503);
    expect(await job(a)).toMatchObject({ state: "pending", attempts: 1 });
    expect((await call("/v1/identity", "GET", a)).status).toBe(401);
    expect((await call("/v1/identity/deletion-ack", "POST", a, { schema_version: 1 })).status).toBe(401);
    provider.mockResolvedValue(new Response(null, { status: 404 })); await due(a);
    expect(await job(a)).toMatchObject({ state: "complete", attempts: 2 });
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(200);
  });
  it("bounds automatic provider retries and resumes only on explicit authenticated retry", async () => {
    const a = await create(); const stub = await configured(a); const provider = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 503 }));
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(503);
    for (let i = 0; i < 7; i++) await due(a);
    expect(provider).toHaveBeenCalledTimes(8); expect(await job(a)).toMatchObject({ state: "pending", attempts: 8 });
    await runInDurableObject(stub, async (_, ctx) => { expect(await ctx.storage.getAlarm()).toBeNull(); });
    provider.mockResolvedValue(new Response(null, { status: 200 }));
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(200); expect(provider).toHaveBeenCalledTimes(9);
  });
  it("reserves retry after provider acceptance when another store temporarily refuses cleanup", async () => {
    const a = await create(); const stub = await configured(a); vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 200 }));
    const inbox = env.SAFETY_INBOX.getByName("moderation-v1");
    await runInDurableObject(inbox, async (_, ctx) => { ctx.storage.sql.exec("CREATE TABLE unknown_hold (data TEXT)"); });
    // Account data must not be forgotten after a failed substore deletion.
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(503);
    expect(await job(a)).toMatchObject({ state: "accepted" });
    await due(a); expect(await job(a)).toMatchObject({ state: "accepted", cleanup_attempts: 1 });
    await runInDurableObject(stub, async (_, ctx) => { expect(await ctx.storage.getAlarm()).not.toBeNull(); });
    await runInDurableObject(inbox, async (_, ctx) => { ctx.storage.sql.exec("DROP TABLE unknown_hold"); });
    await due(a); expect(await job(a)).toMatchObject({ state: "complete" });
  });
  it("preserves exact owner and credential across safety archive restore, with a coherent owned retry alarm", async () => {
    const a = await create(); const stub = await configured(a); vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 503 }));
    await call("/v1/identity", "DELETE", a); const snapshot = JSON.parse(await stub.exportSnapshot(a.player_id));
    const current = snapshot.payload.erasure as ErasureJob; current.next_at = current.created_at;
    snapshot.checksum = await digest(canonicalJson(snapshot.payload));
    const restored = env.SAFETY_PROFILES.get(env.SAFETY_PROFILES.newUniqueId()); expect((await restored.restoreSnapshot(a.player_id, canonicalJson(snapshot))).ok).toBe(true);
    const reread = JSON.parse(await restored.exportSnapshot(a.player_id)); expect(reread.payload.erasure.device_hash).toBe(await digest(a.device_token));
    await runInDurableObject(restored, async (_, ctx) => { expect(await ctx.storage.getAlarm()).toBe(reread.payload.erasure.next_at); });
    expect((await env.SAFETY_PROFILES.get(env.SAFETY_PROFILES.newUniqueId()).restoreSnapshot("z".repeat(22), canonicalJson(snapshot))).ok).toBe(false);
  });
  it("preserves completed-erasure profile absence so a restored completion receipt can be ACKed", async () => {
    const a = await create(); const source = await configured(a); vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 200 }));
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(200);
    const archive = await source.exportSnapshot(a.player_id), envelope = JSON.parse(archive);
    expect(envelope.payload.profile).toBeNull(); expect(envelope.payload.erasure.state).toBe("complete");
    const restored = env.SAFETY_PROFILES.get(env.SAFETY_PROFILES.newUniqueId()); expect((await restored.restoreSnapshot(a.player_id, archive)).ok).toBe(true);
    expect(await restored.deletionReceipt(a.player_id, await digest(a.device_token))).toBe(true);
    expect(await restored.acknowledgeDeletion(a.player_id, await digest(a.device_token))).toEqual({ ok: true, value: { schema_version: 1, acknowledged: true } });
    expect(await restored.deletionReceipt(a.player_id, await digest(a.device_token))).toBe(false);
    envelope.payload.profile = { schema_version: 1, owner: a.player_id, accepted_at: null, terms_version: null, blocks: [] };
    envelope.checksum = await digest(canonicalJson(envelope.payload));
    expect((await env.SAFETY_PROFILES.get(env.SAFETY_PROFILES.newUniqueId()).restoreSnapshot(a.player_id, canonicalJson(envelope))).ok).toBe(false);
  });
});
