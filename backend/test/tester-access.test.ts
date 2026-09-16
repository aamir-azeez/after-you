import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, LEVEL_IDS, type Outcome } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { entitlement } from "../src/entitlement";
import { validateSnapshot } from "../src/snapshot";
import { RELAY_KEY } from "../src/v2/chapters";
import firstSteps from "../../game/tests/fixtures/first_steps/definition.json";

// Synthetic fixture only, unrelated to any configured code or secret.
const CODE = "SYNTHETIC-ONLY-TESTER-CODE";
const COMMIT = "a".repeat(40);
type Account = { player_id: string; device_token: string; recovery_code: string };
const value = <T>(r: Outcome<T>): T => { if (!r.ok) throw new Error(r.code); return r.value; };
let ip = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}) {
  return worker.fetch(new Request("https://game.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.0." + ++ip, ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), { ...env, ...overrides } as Env);
}
const account = async () => { const r = await call("/v1/identity", "POST", undefined, {}); expect(r.status).toBe(201); return r.json<Account>(); };
const enabled = async () => ({ TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE) });
const redeem = async (a: Account, code = CODE, config?: Record<string, unknown>) => call("/v1/tester-access", "POST", a, { schema_version: 1, code }, config ?? await enabled());
async function recover(a: Account) {
  const next = { ...a, device_token: randomToken(), recovery_code: randomToken() };
  const r = await call("/v1/identity/recover", "POST", undefined, { player_id: a.player_id, recovery_code: a.recovery_code, idempotency_key: crypto.randomUUID(), next_device_token: next.device_token, next_recovery_code: next.recovery_code });
  expect(r.status).toBe(200); return next;
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("permanent authenticated tester access", () => {
  it("rejects wrong, disabled and missing code configuration without making a grant", async () => {
    const a = await account();
    expect((await redeem(a, CODE.toLowerCase())).status).toBe(403);
    expect((await redeem(a, CODE, { ...await enabled(), TESTER_ACCESS_ENABLED: "false" })).status).toBe(403);
    expect((await redeem(a, CODE, { TESTER_ACCESS_ENABLED: "true" })).status).toBe(403);
    expect(await (await call("/v1/tester-access", "GET", a)).json()).toEqual({ schema_version: 1, granted: false, player_id: a.player_id });
    const archive = JSON.parse(value(await env.PLAYERS.getByName(a.player_id).exportSnapshot(COMMIT)));
    expect(archive.payload.format_version).toBe(1); expect(archive.payload.tables[0].rows[0].data).not.toContain("tester_grant");
  });
  it.each([{ schema_version: 1, code: "short" }, { schema_version: 1, code: " " + CODE }, { schema_version: 2, code: CODE }, { schema_version: 1, code: CODE, player_id: "p".repeat(22) }])("rejects malformed redemption without normalization", async body => {
    const a = await account(); expect((await call("/v1/tester-access", "POST", a, body, await enabled())).status).toBe(400);
  });
  it("preserves the exact grant after lost response, eviction, code rotation and disable", async () => {
    const a = await account(), first = await redeem(a); expect(first.status).toBe(200); const receipt = await first.json();
    expect(receipt).toMatchObject({ schema_version: 1, granted: true, player_id: a.player_id, access_source: "tester_grant", entitlement: "full_journey" });
    await evictDurableObject(env.PLAYERS.getByName(a.player_id));
    expect(await (await call("/v1/tester-access", "GET", a)).json()).toEqual(receipt);
    const rotated = { TESTER_ACCESS_ENABLED: "false", TESTER_CODE_SHA256: "f".repeat(64), TESTER_CODE_LIMITER: { limit: async () => { throw new Error("existing_grant_must_not_spend_attempt"); } } };
    expect(await (await redeem(a, "ANOTHER-SYNTHETIC-CODE", rotated)).json()).toEqual(receipt);
    const b = await account(); expect((await redeem(b, CODE, { TESTER_ACCESS_ENABLED: "false" })).status).toBe(403);
  });
  it("commits one timestamp during concurrent redemption without storing code/hash history", async () => {
    const a = await account(); const replies = await Promise.all([redeem(a), redeem(a), redeem(a)]);
    const receipts = await Promise.all(replies.map(r => r.json())); expect(replies.every(r => r.status === 200)).toBe(true); expect(receipts[1]).toEqual(receipts[0]); expect(receipts[2]).toEqual(receipts[0]);
    const serialized = value(await env.PLAYERS.getByName(a.player_id).exportSnapshot(COMMIT));
    expect(serialized).not.toContain(CODE); expect(serialized).not.toContain(await digest(TESTER_CODE_DOMAIN + CODE));
    const stored = JSON.parse(JSON.parse(serialized).payload.tables[0].rows[0].data);
    expect(stored.tester_grant).toEqual({ schema_version: 1, granted_at: (receipts[0] as { granted_at: string }).granted_at });
  });
  it("restores permanent access with newly rotated credentials and rejects old/wrong owners", async () => {
    const a = await account(), b = await account(); const receipt = await (await redeem(a)).json(); const next = await recover(a);
    expect((await call("/v1/tester-access", "GET", a)).status).toBe(401);
    expect((await redeem(a)).status).toBe(401);
    expect(await (await call("/v1/tester-access", "GET", next)).json()).toEqual(receipt);
    expect((await call("/v1/tester-access", "GET", { ...next, player_id: b.player_id })).status).toBe(401);
    expect(await env.PLAYERS.getByName(a.player_id).storedTesterGrant(b.player_id)).toBeNull();
  });
  it("reauthorizes after attempt limiter yields to credential recovery", async () => {
    const a = await account(); let next: Account | null = null;
    const limits = { limit: async () => { if (!next) next = await recover(a); return { success: true }; } };
    expect((await redeem(a, CODE, { ...await enabled(), TESTER_CODE_LIMITER: limits })).status).toBe(401);
    expect(await (await call("/v1/tester-access", "GET", next!)).json()).toMatchObject({ granted: false });
  });
  it("reauthorizes GET after the general limiter yields to recovery", async () => {
    const a = await account(); await redeem(a); let next: Account | null = null;
    const limits = { limit: async () => { if (!next) next = await recover(a); return { success: true }; } };
    expect((await call("/v1/tester-access", "GET", a, undefined, { PLAYER_LIMITER: limits })).status).toBe(401);
    expect(await (await call("/v1/tester-access", "GET", next!)).json()).toMatchObject({ granted: true });
  });
  it("cannot resurrect a grant after deletion consumes an in-flight attempt", async () => {
    const a = await account(); let erased = false;
    const limits = { limit: async () => { if (!erased) { erased = true; expect((await call("/v1/identity", "DELETE", a)).status).toBe(200); } return { success: true }; } };
    expect((await redeem(a, CODE, { ...await enabled(), TESTER_CODE_LIMITER: limits })).status).toBe(401);
    expect(await env.PLAYERS.getByName(a.player_id).storedTesterGrant(a.player_id)).toBeNull();
    expect(JSON.parse(value(await env.PLAYERS.getByName(a.player_id).exportSnapshot(COMMIT))).payload.summary.state).toBe("empty");
  });
  it("uses separate owner/IP attempt keys and returns a bounded safe rate-limit error", async () => {
    const a = await account(), keys: string[] = [];
    const limit = { limit: async ({ key }: { key: string }) => { keys.push(key); return { success: !key.startsWith("ip:") }; } };
    const r = await redeem(a, CODE, { ...await enabled(), TESTER_CODE_LIMITER: limit });
    expect(r.status).toBe(429); expect(await r.json()).toEqual({ error: { code: "tester_rate_limited", retryable: true } }); expect(r.headers.get("Retry-After")).toBe("60");
    expect(keys[0]).toBe("owner:" + a.player_id); expect(keys[1]).toMatch(/^ip:[a-f0-9]{64}$/); expect(keys.join()).not.toContain(CODE); expect(keys.join()).not.toContain(a.device_token);
  });
  it("grants the host premium gate without any RevenueCat call and leaves purchase records separate", async () => {
    const a = await account(), b = await account(); await redeem(a);
    const requests = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("provider_not_needed"));
    const api = await call("/v1/entitlement", "GET", a); expect(api.status).toBe(200);
    expect(await api.json()).toMatchObject({ full_journey: true, status: "verified", access_source: "tester_grant", entitlement: "full_journey", player_id: a.player_id });
    const room = await (await call("/v1/rooms", "POST", a, { idempotency_key: crypto.randomUUID() })).json<{ room_id: string; invite_code: string }>();
    expect((await call("/v1/rooms/join", "POST", b, { invite_code: room.invite_code })).status).toBe(200);
    // Isolate the existing premium admission boundary without changing gameplay rules.
    await runInDurableObject(env.ROOMS.getByName(room.room_id), async (_instance, ctx) => {
      const row = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one(); const state = JSON.parse(row.data);
      state.level_index = 3; state.level_id = LEVEL_IDS[3]; state.first_player_id = b.player_id;
      ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(state));
    });
    const view = await (await call("/v1/rooms/" + room.room_id, "GET", b)).json<{ revision: number }>();
    const fork = await call("/v1/rooms/" + room.room_id + "/fork", "POST", b, { base_revision: view.revision, idempotency_key: crypto.randomUUID() });
    expect(fork.status).toBe(409); expect(await fork.json()).toMatchObject({ error: { code: "nothing_to_fork" } });
    expect(requests).not.toHaveBeenCalled();
  });
  it("keeps normal Play purchase checks for identities without tester grants", async () => {
    const a = await account();
    const requests = vi.spyOn(globalThis, "fetch").mockImplementation(async url => Response.json(String(url).includes("active_entitlements") ?
      { object: "list", items: [{ entitlement_id: "entlFixture", expires_at: null }], next_page: null } :
      { object: "list", items: [{ object: "purchase", product_id: "prodFixture", store: "play_store", environment: "production", status: "owned", ownership: "purchased", purchased_at: Date.now() - 10000 }], next_page: null }));
    const access = await entitlement(a.player_id, { ...env, REVENUECAT_VERIFICATION_MODE: "play_store", REVENUECAT_SECRET_KEY: "synthetic", REVENUECAT_PROJECT_ID: "projFixture", REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID: "entlFixture", REVENUECAT_PLAY_PRODUCT_ID: "prodFixture", REVENUECAT_PLAY_ENVIRONMENT: "production" });
    expect(access).toMatchObject({ full_journey: true, access_source: "play_purchase", entitlement: "full_journey_play", player_id: a.player_id }); expect(requests).toHaveBeenCalledTimes(2);
    expect(await (await call("/v1/tester-access", "GET", a)).json()).toMatchObject({ granted: false });
  });
  it("erases tester access with account deletion, including completed-erasure ACK", async () => {
    const a = await account(); await redeem(a);
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(200);
    expect((await call("/v1/tester-access", "GET", a)).status).toBe(401);
    expect(await env.PLAYERS.getByName(a.player_id).storedTesterGrant(a.player_id)).toBeNull();
    const snapshot = JSON.parse(value(await env.PLAYERS.getByName(a.player_id).exportSnapshot(COMMIT))); expect(snapshot.payload.format_version).toBe(1); expect(snapshot.payload.tables[0].rows).toEqual([]);
    expect((await call("/v1/identity/deletion-ack", "POST", a, { schema_version: 1 })).status).toBe(200);
    expect((await redeem(a)).status).toBe(401);
  });
});

describe("tester grant portable Player archives", () => {
  it("round trips exact grant in format4 and refuses wrong owner/future grant schema/old format", async () => {
    const a = await account(), receipt = await (await redeem(a)).json();
    const archive = value(await env.PLAYERS.getByName(a.player_id).exportSnapshot(COMMIT)); const parsed = JSON.parse(archive);
    expect(parsed.payload.format_version).toBe(4); expect(parsed.payload.database_schema_version).toBe(1);
    const target = env.PLAYERS.getByName(randomToken(16)); expect((await target.restoreSnapshot(archive, a.player_id)).ok).toBe(true);
    expect(value(await target.testerAccess(a.player_id, await digest(a.device_token)))).toEqual(receipt);
    await expect(validateSnapshot(archive, "Player", randomToken(16))).rejects.toThrow("snapshot_identity_mismatch");
    for (const mutate of [(p: any) => { p.format_version = 3; }, (p: any) => { const row = p.tables[0].rows[0]; const data = JSON.parse(row.data); data.tester_grant.schema_version = 2; row.data = JSON.stringify(data); }, (p: any) => { const row = p.tables[0].rows[0]; const data = JSON.parse(row.data); data.tester_grant.code = "synthetic"; row.data = JSON.stringify(data); }]) {
      const modified = JSON.parse(archive); mutate(modified.payload); modified.checksum.value = await digest(canonicalJson(modified.payload));
      await expect(validateSnapshot(canonicalJson(modified), "Player", a.player_id)).rejects.toThrow("unsupported_tester_grant");
    }
  });
  it("retains each exact older grantless format and supports chapter intent beside a new grant", async () => {
    const a = await account(), player = env.PLAYERS.getByName(a.player_id);
    const output = async () => JSON.parse(value(await player.exportSnapshot(COMMIT))).payload;
    expect((await output()).format_version).toBe(1);
    const link = { api_version: 2 as const, room_id: randomToken(16), invite_code: "A".repeat(20), host: true };
    expect((await player.reserveChapterRoom(crypto.randomUUID(), link, RELAY_KEY)).ok).toBe(true); expect((await output()).format_version).toBe(2);
    const key = { level_id: "first-steps", level_version: 1, definition_hash: await digest(canonicalJson(firstSteps)) };
    expect((await player.reserveChapterRoom(crypto.randomUUID(), { ...link, room_id: randomToken(16) }, key)).ok).toBe(true); expect((await output()).format_version).toBe(3);
    const before = await output(); await redeem(a); const after = await output(); expect(after.format_version).toBe(4); expect(after.tables.slice(1)).toEqual(before.tables.slice(1));
    await expect(validateSnapshot(value(await player.exportSnapshot(COMMIT)), "Player", a.player_id)).resolves.toBeDefined();
  });
});
