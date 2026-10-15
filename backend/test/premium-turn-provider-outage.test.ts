import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { HOST_ACCESS_FRESH_MS, HOST_ACCESS_OUTAGE_GRACE_MS } from "../src/v2/host-access";
import { rollingHome } from "../src/v2/protocol-cooperative";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import weightA from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";
import weightB from "../../game/tests/fixtures/cooperative/weight-of-a-friend-b.json";
import rollingMiddle from "../../game/tests/fixtures/cooperative/weight-of-a-friend-checkpoint.json";
import homeA from "../../game/tests/fixtures/cooperative/bring-it-home-a.json";
import homeB from "../../game/tests/fixtures/cooperative/bring-it-home-b.json";
import rollingFinal from "../../game/tests/fixtures/cooperative/rolling-home-final-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
const key = () => crypto.randomUUID(), CODE = "SYNTHETIC-OUTAGE-TESTER";
const playConfig = { REVENUECAT_VERIFICATION_MODE: "play_store", REVENUECAT_SECRET_KEY: "synthetic-only", REVENUECAT_PROJECT_ID: "projSynthetic", REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID: "entlPlay", REVENUECAT_PLAY_PRODUCT_ID: "prodPlay", REVENUECAT_PLAY_ENVIRONMENT: "production" };
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = playConfig): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, { V2_ROOMS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true", ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.9." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
type Provider = "owned" | "not_owned" | "down";
/** RevenueCat stand-in: Play purchase owned, verified as not owned, or answering 503. */
function provider(state: () => Provider) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async url => {
    const current = state();
    if (current === "down") return new Response(null, { status: 503 });
    return Response.json((url instanceof Request ? url.url : String(url)).includes("active_entitlements") ?
      { object: "list", items: current === "owned" ? [{ entitlement_id: "entlPlay", expires_at: null }] : [], next_page: null } :
      { object: "list", items: [{ object: "purchase", product_id: "prodPlay", store: "play_store", environment: "production", status: "owned", ownership: "purchased", purchased_at: Date.now() - 10000 }], next_page: null });
  });
}
async function pair(tester = false) {
  const host = await account(), guest = await account();
  if (tester) expect((await call("/v1/tester-access", "POST", host, { schema_version: 1, code: CODE }, { TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE) })).status).toBe(200);
  const created = await call("/v2/rooms", "POST", host, { ...rollingHome.key, idempotency_key: key() }); expect(created.status).toBe(200);
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: (await created.json<RoomSnapshotV2>()).invite_code, supported_simulation_versions: [6] }); expect(joined.status).toBe(200);
  return { host, guest, room: await joined.json<RoomSnapshotV2>() };
}
function turn(room: RoomSnapshotV2, recording: unknown, checkpoint?: unknown) { return { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) }; }
const post = (room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint?: unknown) => call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, turn(room, recording, checkpoint));
async function accepted(response: Response): Promise<MutationV2> { expect(response.status).toBe(200); return response.json<MutationV2>(); }
/** Moves the room's last verification back in time without touching the clock. */
async function age(room: RoomSnapshotV2, ms: number): Promise<void> {
  await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), instance => {
    const memo = (instance as unknown as { hostAccess: { host_id: string; verified_at: number } | null }).hostAccess;
    expect(memo).not.toBeNull(); memo!.verified_at = Date.now() - ms;
  });
}
const memoAge = (room: RoomSnapshotV2, host: Account) => env.ROOMS_V2.getByName(room.room_id).hostAccessAge(host.player_id);
const ERROR_402 = JSON.stringify({ error: { code: "host_unlock_required", retryable: false } });
const ERROR_503 = JSON.stringify({ error: { code: "entitlement_unavailable", retryable: true } });
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("premium turn host access", () => {
  it("checks the provider once per sitting and honours a recent verification through an outage", async () => {
    let state: Provider = "owned"; const requests = provider(() => state);
    const { host, guest, room } = await pair();
    expect(requests).toHaveBeenCalledTimes(2); // Creation still checks every time.
    expect(await memoAge(room, host)).toBeNull();
    const a = await accepted(await post(room, host, weightA));
    expect(requests).toHaveBeenCalledTimes(4); expect(await memoAge(room, host)).not.toBeNull();
    const b = await accepted(await post(a.room, guest, weightB, rollingMiddle));
    expect(requests).toHaveBeenCalledTimes(4);
    for (const [input] of requests.mock.calls) expect(input instanceof Request ? input.url : String(input)).toContain(`/customers/${host.player_id}/`);

    state = "down"; await age(b.room, HOST_ACCESS_FRESH_MS + 60_000);
    const c = await accepted(await post(b.room, guest, homeA));
    expect(requests).toHaveBeenCalledTimes(5);
    await age(c.room, HOST_ACCESS_OUTAGE_GRACE_MS + 60_000);
    const refused = await post(c.room, host, homeB, rollingFinal);
    expect(refused.status).toBe(503); expect(refused.headers.get("Retry-After")).toBe("15"); expect(await refused.text()).toBe(ERROR_503);

    state = "owned";
    const d = await accepted(await post(c.room, host, homeB, rollingFinal));
    expect(d.room.active_role).toBe("complete");
  });

  it("refuses with 402 when the provider says the host is not entitled, and a later outage cannot bring access back", async () => {
    let state: Provider = "owned"; provider(() => state);
    const { host, guest, room } = await pair();
    const a = await accepted(await post(room, host, weightA));
    state = "not_owned";
    expect((await accepted(await post(a.room, guest, weightB, rollingMiddle))).room.stage_index).toBe(1); // Still inside the fresh window.
    const b = await (await call(`/v2/rooms/${room.room_id}`, "GET", host)).json<RoomSnapshotV2>();
    await age(b, HOST_ACCESS_FRESH_MS + 60_000);
    const denied = await post(b, guest, homeA);
    expect(denied.status).toBe(402); expect(await denied.text()).toBe(ERROR_402);
    expect(await memoAge(room, host)).toBeNull();
    state = "down";
    const unavailable = await post(b, guest, homeA);
    expect(unavailable.status).toBe(503); expect(await unavailable.text()).toBe(ERROR_503);
  });

  it("checks the provider again after the room is evicted", async () => {
    let state: Provider = "owned"; const requests = provider(() => state);
    const { host, guest, room } = await pair();
    const a = await accepted(await post(room, host, weightA)); requests.mockClear();
    await evictDurableObject(env.ROOMS_V2.getByName(room.room_id));
    expect(await memoAge(room, host)).toBeNull();
    state = "down";
    const refused = await post(a.room, guest, weightB, rollingMiddle);
    expect(refused.status).toBe(503); expect(await refused.text()).toBe(ERROR_503); expect(requests).toHaveBeenCalled();
  });

  it("keeps tester grants working without any provider call or memo", async () => {
    const requests = provider(() => "down");
    const { host, guest, room } = await pair(true);
    const a = await accepted(await post(room, host, weightA));
    await accepted(await post(a.room, guest, weightB, rollingMiddle));
    expect(requests).not.toHaveBeenCalled(); expect(await memoAge(room, host)).toBeNull();
  });
});
