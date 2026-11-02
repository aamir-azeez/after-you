import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { parseConfig } from "../src/config";
import { FLAG_NAMES } from "../src/flags";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { TEST_CODE_SALT, testCodeHash } from "../src/test-codes";
import { entitlement } from "../src/entitlement";
import { paidUntil } from "../src/pollen/routes";
import { validateSnapshot } from "../src/snapshot";
import { rollingHome } from "../src/v2/protocol-cooperative";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import weightA from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";
import weightB from "../../game/tests/fixtures/cooperative/weight-of-a-friend-b.json";
import rollingMiddle from "../../game/tests/fixtures/cooperative/weight-of-a-friend-checkpoint.json";
import homeA from "../../game/tests/fixtures/cooperative/bring-it-home-a.json";
import { withConfig } from "./config";

// Synthetic codes and ids only, unrelated to any configured code, secret or player.
const GRANT = "SYNTHETIC-GRANT-KEEPSAKES-CODE", RESET = "SYNTHETIC-RESET-KEEPSAKES-CODE", TOGGLE = "SYNTHETIC-TOGGLE-JOURNEY-CODE", TESTER_CODE = "SYNTHETIC-TESTER-ACCESS-CODE";
const COMMIT = "b".repeat(40);
type Account = { player_id: string; device_token: string; recovery_code: string };
const value = <T>(r: Outcome<T>): T => { if (!r.ok) throw new Error(r.code); return r.value; };
const codes = async () => ({ grant_keepsakes: await testCodeHash("grant_keepsakes", GRANT), reset_keepsakes: await testCodeHash("reset_keepsakes", RESET), toggle_full_journey: await testCodeHash("toggle_full_journey", TOGGLE) });
const playConfig = { REVENUECAT_SECRET_KEY: "synthetic-only", revenuecat: { project_id: "projSynthetic", play_entitlement_lookup_id: "entlPlay", play_product_id: "prodPlay" } };
/** CONFIG with the test codes and `testers` listed; the tester access code is on too, so both kinds of code meet. */
const configured = async (testers: Account[], extra: Record<string, unknown> = {}) => ({ ...playConfig, revenuecat: { ...playConfig.revenuecat, tester_ids: testers.map(t => t.player_id) },
  test_codes: await codes(), TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + TESTER_CODE), ...extra });
let ip = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = playConfig): Promise<Response> {
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.7." + (++ip % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), withConfig({ ...env, ...overrides }) as unknown as Env);
}
const account = async () => { const r = await call("/v1/identity", "POST", undefined, {}); expect(r.status).toBe(201); return r.json<Account>(); };
const type = (a: Account, code: string, config: Record<string, unknown>) => call("/v1/tester-access", "POST", a, { schema_version: 1, code }, config);
/** RevenueCat stand-in: the Play purchase is owned. Counts calls. */
const owned = () => vi.spyOn(globalThis, "fetch").mockImplementation(async url => Response.json((url instanceof Request ? url.url : String(url)).includes("active_entitlements") ?
  { object: "list", items: [{ entitlement_id: "entlPlay", expires_at: null }], next_page: null } :
  { object: "list", items: [{ object: "purchase", product_id: "prodPlay", store: "play_store", environment: "production", status: "owned", ownership: "purchased", purchased_at: Date.now() - 10000 }], next_page: null }));
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("test codes in CONFIG", () => {
  it("reads each action's hash, refuses a malformed map as a whole and reports actions it does not know", async () => {
    const hashes = await codes();
    const good = parseConfig(JSON.stringify({ test_codes: hashes }), FLAG_NAMES);
    expect(good.problems).toEqual([]); expect(good.unknown).toEqual([]);
    expect([...good.config.test_codes]).toEqual(Object.entries(hashes));
    for (const bad of [[], "x", { grant_keepsakes: "A".repeat(64) }, { grant_keepsakes: hashes.grant_keepsakes, reset_keepsakes: hashes.grant_keepsakes }, { grant_keepsakes: 7 }]) {
      const check = parseConfig(JSON.stringify({ test_codes: bad }), FLAG_NAMES);
      expect(check.config.test_codes.size, JSON.stringify(bad)).toBe(0); expect(check.problems).toHaveLength(1);
    }
    const later = parseConfig(JSON.stringify({ test_codes: { ...hashes, later_action: hashes.grant_keepsakes.replace(/.$/, "0") } }), FLAG_NAMES);
    expect(later.unknown).toEqual(["test_codes.later_action"]); expect(later.config.test_codes.size).toBe(3);
  });
  it("salts each hash with its action, so one code's hash never stands for another action", async () => {
    expect(await testCodeHash("grant_keepsakes", GRANT)).toBe(await digest(TEST_CODE_SALT + "grant_keepsakes:" + GRANT));
    expect(await testCodeHash("reset_keepsakes", GRANT)).not.toBe(await testCodeHash("grant_keepsakes", GRANT));
  });
});

describe("test codes through the tester code route", () => {
  it("does nothing for a player outside the tester list: the same 403 as a wrong code, and a grant answers as before", async () => {
    const tester = await account(), other = await account(), config = await configured([tester]);
    for (const code of [GRANT, RESET, TOGGLE, "SYNTHETIC-WRONG-CODE"]) {
      const r = await type(other, code, config);
      expect(r.status).toBe(403); expect(await r.json()).toEqual({ error: { code: "tester_access_unavailable", retryable: false } });
    }
    expect(await env.PLAYERS.getByName(other.player_id).storedAccess(other.player_id)).toEqual({ grant: null, full_journey_off: false });
    const receipt = await (await type(other, TESTER_CODE, config)).json();
    const spent = { ...config, TESTER_CODE_LIMITER: { limit: async () => { throw new Error("a granted non-tester must not spend an attempt"); } } };
    expect(await (await type(other, TOGGLE, spent)).json()).toEqual(receipt);
    expect((await env.PLAYERS.getByName(other.player_id).storedAccess(other.player_id)).full_journey_off).toBe(false);
  });
  it("answers each keepsake action to a listed tester and writes nothing on the server", async () => {
    const tester = await account(), config = await configured([tester]);
    const before = value(await env.PLAYERS.getByName(tester.player_id).exportSnapshot(COMMIT));
    expect(await (await type(tester, GRANT, config)).json()).toEqual({ schema_version: 1, player_id: tester.player_id, test_action: "grant_keepsakes" });
    expect(await (await type(tester, RESET, config)).json()).toEqual({ schema_version: 1, player_id: tester.player_id, test_action: "reset_keepsakes" });
    const after = JSON.parse(value(await env.PLAYERS.getByName(tester.player_id).exportSnapshot(COMMIT)));
    expect(after.payload.tables).toEqual(JSON.parse(before).payload.tables);
    // A wrong code is a wrong tester code; the real tester code still grants tester access.
    expect((await type(tester, "SYNTHETIC-WRONG-CODE", config)).status).toBe(403);
    expect(await (await type(tester, TESTER_CODE, config)).json()).toMatchObject({ granted: true, access_source: "tester_grant" });
  });
  it("still takes test codes from a tester who already has tester access, and limits every attempt", async () => {
    const tester = await account(), keys: string[] = [];
    const counting = await configured([tester], { TESTER_CODE_LIMITER: { limit: async ({ key }: { key: string }) => { keys.push(key); return { success: true }; } } });
    const receipt = await (await type(tester, TESTER_CODE, counting)).json();
    expect(await (await type(tester, GRANT, counting)).json()).toMatchObject({ test_action: "grant_keepsakes" });
    expect(await (await type(tester, "SYNTHETIC-WRONG-CODE", counting)).json()).toEqual(receipt);
    expect(keys.filter(k => k.startsWith("owner:"))).toHaveLength(3); expect(keys.join()).not.toContain(GRANT);
    const limited = await configured([tester], { TESTER_CODE_LIMITER: { limit: async () => ({ success: false }) } });
    const r = await type(tester, TOGGLE, limited);
    expect(r.status).toBe(429); expect(await r.json()).toEqual({ error: { code: "tester_rate_limited", retryable: true } });
    expect((await env.PLAYERS.getByName(tester.player_id).storedAccess(tester.player_id)).full_journey_off).toBe(false);
  });
  it("needs the current credential", async () => {
    const tester = await account(), config = await configured([tester]);
    expect((await type({ ...tester, device_token: "x".repeat(43) }, TOGGLE, config)).status).toBe(401);
    expect((await env.PLAYERS.getByName(tester.player_id).storedAccess(tester.player_id)).full_journey_off).toBe(false);
  });
});

describe("the Full Journey switch", () => {
  it("toggles: off answers verified-not-entitled with no provider call, on brings the real purchase back", async () => {
    const tester = await account(), config = await configured([tester]), requests = owned();
    const vars = withConfig({ ...env, ...config }) as unknown as Env;
    expect(await entitlement(tester.player_id, vars)).toMatchObject({ full_journey: true, access_source: "play_purchase" });
    const calls = requests.mock.calls.length;
    expect(await (await type(tester, TOGGLE, config)).json()).toEqual({ schema_version: 1, player_id: tester.player_id, test_action: "full_journey_off" });
    const off = await entitlement(tester.player_id, vars);
    expect(off).toMatchObject({ full_journey: false, status: "verified", access_source: "tester_switched_off", player_id: tester.player_id });
    expect(requests.mock.calls.length).toBe(calls);
    // The wallet keeps the real Full Journey end: nothing is noted from the switched-off answer.
    expect(paidUntil(off, undefined)).toBeUndefined();
    const api = await call("/v1/entitlement", "GET", tester, undefined, config);
    expect(await api.json()).toMatchObject({ full_journey: false, access_source: "tester_switched_off" });
    expect(await (await call("/v2/capabilities", "GET", tester, undefined, config)).json()).toMatchObject({ full_journey_off: true });
    expect((await call("/v2/rooms", "POST", tester, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, config)).status).toBe(402);

    expect(await (await type(tester, TOGGLE, config)).json()).toEqual({ schema_version: 1, player_id: tester.player_id, test_action: "full_journey_on" });
    expect(await entitlement(tester.player_id, vars)).toMatchObject({ full_journey: true, access_source: "play_purchase" });
    expect(await (await call("/v2/capabilities", "GET", tester, undefined, config)).json()).not.toHaveProperty("full_journey_off");
    expect((await call("/v2/rooms", "POST", tester, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, config)).status).toBe(200);
  });
  it("overrides a stored tester grant too, and leaves it in place for when the switch goes back", async () => {
    const tester = await account(), config = await configured([tester]);
    await type(tester, TESTER_CODE, config); await type(tester, TOGGLE, config);
    expect(await entitlement(tester.player_id, withConfig({ ...env, ...config }) as unknown as Env)).toMatchObject({ full_journey: false, access_source: "tester_switched_off" });
    await type(tester, TOGGLE, config);
    expect(await entitlement(tester.player_id, withConfig({ ...env, ...config }) as unknown as Env)).toMatchObject({ full_journey: true, access_source: "tester_grant" });
  });
  it("holds a tester host's room turns at once, without waiting out the room's memo", async () => {
    const host = await account(), guest = await account(), config = await configured([host]); owned();
    const created = await call("/v2/rooms", "POST", host, { ...rollingHome.key, idempotency_key: crypto.randomUUID() }, config); expect(created.status).toBe(200);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: (await created.json<RoomSnapshotV2>()).invite_code, supported_simulation_versions: [6] }, config);
    const room = await joined.json<RoomSnapshotV2>();
    const turn = (snapshot: RoomSnapshotV2, who: Account, recording: unknown, checkpoint?: unknown) => call(`/v2/rooms/${snapshot.room_id}/turns`, "POST", who,
      { base_revision: snapshot.revision, branch: snapshot.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) }, config);
    const a = await turn(room, host, weightA); expect(a.status).toBe(200);
    const afterA = (await a.json<MutationV2>()).room;
    await type(host, TOGGLE, config);
    const b = await turn(afterA, guest, weightB, rollingMiddle); expect(b.status).toBe(402);
    await type(host, TOGGLE, config);
    const again = await turn(afterA, guest, weightB, rollingMiddle); expect(again.status).toBe(200);
    expect((await turn((await again.json<MutationV2>()).room, guest, homeA)).status).toBe(200);
  });
  it("rides in a format 9 Player archive and goes with account deletion", async () => {
    const tester = await account(), config = await configured([tester]), player = env.PLAYERS.getByName(tester.player_id);
    await type(tester, TOGGLE, config);
    const archive = value(await player.exportSnapshot(COMMIT)), parsed = JSON.parse(archive);
    expect(parsed.payload.format_version).toBe(9);
    expect(JSON.parse(parsed.payload.tables[0].rows[0].data).full_journey_off).toBe(true);
    await expect(validateSnapshot(archive, "Player", tester.player_id)).resolves.toBeDefined();
    for (const mutate of [(p: any) => { p.format_version = 8; }, (p: any) => { const row = p.tables[0].rows[0]; const data = JSON.parse(row.data); data.full_journey_off = false; row.data = JSON.stringify(data); }]) {
      const modified = JSON.parse(archive); mutate(modified.payload); modified.checksum.value = await digest(canonicalJson(modified.payload));
      await expect(validateSnapshot(canonicalJson(modified), "Player", tester.player_id)).rejects.toThrow();
    }
    await type(tester, TOGGLE, config);
    expect(JSON.parse(value(await player.exportSnapshot(COMMIT))).payload.format_version).toBe(1);
    await type(tester, TOGGLE, config);
    expect((await call("/v1/identity", "DELETE", tester, undefined, config)).status).toBe(200);
    expect(await player.storedAccess(tester.player_id)).toEqual({ grant: null, full_journey_off: false });
  });
});
