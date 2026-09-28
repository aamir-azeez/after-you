import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, fail, randomToken, type Outcome } from "../src/protocol";
import { eraseCampaignRoot } from "../src/v2/campaign-deletion";
import { campaignContinueKey } from "../src/v2/campaign-protocol";
import { campaignAdmissionHash } from "../src/v2/campaign-admission-intent";
import type { CampaignDefinition, CampaignKey, CampaignView, CampaignJoin } from "../src/v2/campaign-types";
import type { CampaignRoomContext } from "../src/v2/campaign-room-access";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import final from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";
import rollingA from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";
import rollingB from "../../game/tests/fixtures/cooperative/weight-of-a-friend-b.json";
import rollingMiddle from "../../game/tests/fixtures/cooperative/weight-of-a-friend-checkpoint.json";
import homeA from "../../game/tests/fixtures/cooperative/bring-it-home-a.json";
import homeB from "../../game/tests/fixtures/cooperative/bring-it-home-b.json";
import homeFinal from "../../game/tests/fixtures/cooperative/rolling-home-final-checkpoint.json";

// Test-only finite registry substitution. Public bodies/env cannot register
// definitions; real Room bindings receive only the route's immutable definition.
const manifest = vi.hoisted(() => ({ advertised: true, retained: true, extra: null as CampaignDefinition | null }));
vi.mock("../src/v2/campaign-registry", async original => {
  const actual = await original<typeof import("../src/v2/campaign-registry")>();
  const f = (await import("./fixtures/campaign-control-v2.json")).default;
  const { canonicalJson } = await import("../src/protocol");
  const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
  const candidates = () => manifest.extra ? [f.definition, manifest.extra] : [f.definition];
  const retainedCampaign = (k: CampaignKey) => {
    const found = candidates().find(d => same(k, { campaign_id: d.campaign_id, campaign_version: d.campaign_version, definition_hash: d.definition_hash }));
    return manifest.retained && found ? structuredClone(found) : undefined;
  };
  return { ...actual, retainedCampaign,
    advertisedCampaigns: () => manifest.advertised ? [structuredClone(manifest.extra ?? f.definition)] : [],
    campaignCreatable: (k: CampaignKey, e: { CAMPAIGN_CREATION_ENABLED?: string }) => manifest.advertised && e.CAMPAIGN_CREATION_ENABLED === "true" && !!retainedCampaign(k) };
});
const definition = fixture.definition as CampaignDefinition, key = fixture.active_view.campaign_key as CampaignKey;
const R = fixture.active_view.campaign_room_id, I = fixture.active_view.invite_code!, T = "a".repeat(43);
const unwrap = <T>(r: Outcome<T>): T => { if (!r.ok) throw new Error(r.code); return r.value; };
let H = "", G = "", hash = "", address = 0, nextInvite = I;
const changed = new Map<object, Record<string, unknown>>();
const flags = { V2_ROOMS_ENABLED: "true", CAMPAIGN_CREATION_ENABLED: "true", CAMPAIGN_MUTATIONS_ENABLED: "true",
  REVENUECAT_VERIFICATION_MODE: "demo", REVENUECAT_API_VERSION: "1", REVENUECAT_SECRET_KEY: "synthetic-only" };
const root = () => env.ROOMS_V2.getByName(R);
const context = (): CampaignRoomContext => ({ schema_version: 2, room_id: R, device_hash: hash });
const create = () => ({ schema_version: 1 as const, idempotency_key: "campaign-http-create-0001", campaign_key: key });
const join = (id = "campaign-http-join-0001", invite = I): CampaignJoin => ({ schema_version: 2, idempotency_key: id,
  invite_code: invite, campaign_key: key, supported_simulation_versions: [6] });
async function call(path: string, method = "GET", body?: unknown, owner = H, overrides: Record<string, unknown> = {}, marked = true, token = T) {
  const configured: Env = { ...env }; Object.assign(configured, flags, overrides);
  return worker.fetch(new Request("https://campaign.test" + path, { method, headers: { "Content-Type": "application/json",
    "CF-Connecting-IP": "198.19.1." + ++address, "X-Player-Id": owner, Authorization: "Bearer " + token,
    ...(marked ? { "X-AfterYou-Campaign-Schema": "2" } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function configure(overrides: Record<string, unknown> = {}) {
  await runInDurableObject(root(), instance => {
    const local = Reflect.get(instance, "env") as Record<string, unknown>;
    if (!changed.has(local)) changed.set(local, Object.fromEntries(Object.keys(flags).map(k => [k, local[k]])));
    Object.assign(local, flags, overrides);
  });
}
async function made() { const r = await call("/v2/campaigns", "POST", create()); expect(r.status).toBe(201); return r.json<{ campaign: CampaignView }>(); }
async function paired() { await made(); const r = await call("/v2/campaigns/join", "POST", join(), G); expect(r.status).toBe(200); return r.json<{ campaign: CampaignView }>(); }
async function complete(campaignKey = key) {
  let s = unwrap(await root().snapshot(H, context()));
  for (const [owner, recording, checkpoint] of [[H, highA, null], [G, highB, middle], [G, lowA, null], [H, lowB, final]] as const) {
    s = unwrap(await root().commit(owner, { base_revision: s.revision, branch: s.branch, idempotency_key: crypto.randomUUID(), recording,
      ...(checkpoint ? { checkpoint } : {}) }, context())).room;
  }
  const view = unwrap(await root().campaignControl(H)).campaign;
  const origin = { expected_revision: view.revision, from_index: 0, source: { room_id: R, revision: s.revision, branch: s.branch, checkpoint_hash: final.checkpoint_hash } };
  return { schema_version: 1, campaign_key: campaignKey, idempotency_key: await campaignContinueKey(R, campaignKey, H, origin), ...origin };
}
async function bytes() {
  return runInDurableObject(root(), (_, ctx) => ["room", "campaign_member", "campaign_anchor", "campaign_operations", "turns", "pairs"]
    .map(name => [name, ctx.storage.sql.exec(`SELECT * FROM ${name}`).toArray()]));
}
async function block() { unwrap(await env.SAFETY_PROFILES.getByName(H).setBlock(H, hash, G, true)); }

beforeEach(async () => {
  await reset(); H = randomToken(16); G = randomToken(16); hash = await digest(T); address = 0; nextInvite = I;
  manifest.advertised = true; manifest.retained = true; manifest.extra = null;
  for (const owner of [H, G]) unwrap(await env.PLAYERS.getByName(owner).create(owner, hash, "b".repeat(64)));
  await configure();
  const original = crypto.getRandomValues.bind(crypto);
  vi.spyOn(crypto, "getRandomValues").mockImplementation(((array: Uint8Array) => {
    if (array instanceof Uint8Array && array.length === 10) { array.set(nextInvite.match(/../g)!.map(x => parseInt(x, 16))); return array; }
    return original(array);
  }) as typeof crypto.getRandomValues);
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 404 }));
});
afterEach(async () => { vi.restoreAllMocks(); for (const [target, prior] of changed) Object.assign(target, prior); changed.clear(); await reset(); });

describe("fixed campaign HTTP admission and control", () => {
  it("creates a free opening once, keeps one api3 link, and retries after fresh advertisement is retired", async () => {
    const first = await made(); expect(first.campaign.campaign_room_id).toBe(R); expect(globalThis.fetch).not.toHaveBeenCalled();
    const before = await bytes(); manifest.advertised = false;
    const retry = await call("/v2/campaigns", "POST", create(), H, { CAMPAIGN_CREATION_ENABLED: "false" });
    expect(retry.status).toBe(200); expect(await retry.json()).toEqual(first); expect(await bytes()).toEqual(before);
    expect(await env.PLAYERS.getByName(H).listRooms()).toEqual([{ room_id: R, invite_code: I, host: true, api_version: 3 }]);
    expect((await call("/v2/campaigns", "POST", { ...create(), idempotency_key: "another-fresh-create-0001" })).status).toBe(503);
  });
  it("recovers an admitted uninitialized allocation from the retained definition while creation is paused", async () => {
    unwrap(await env.PLAYERS.getByName(H).reserveCampaignRoom(create().idempotency_key, { creation_schema: 2,
      link: { room_id: R, invite_code: I, host: true, api_version: 3 }, campaign_key: key }, hash));
    manifest.advertised = false;
    const r = await call("/v2/campaigns", "POST", create(), H, { CAMPAIGN_CREATION_ENABLED: "false" });
    expect(r.status).toBe(201); expect(globalThis.fetch).not.toHaveBeenCalled();
    expect((await r.json<{ campaign: CampaignView }>()).campaign.state).toBe("waiting");
  });
  it("holds a missing retained definition or missing canonical link without allocating another root", async () => {
    unwrap(await env.PLAYERS.getByName(H).reserveCampaignRoom(create().idempotency_key, { creation_schema: 2,
      link: { room_id: R, invite_code: I, host: true, api_version: 3 }, campaign_key: key }, hash));
    manifest.retained = false; expect((await call("/v2/campaigns", "POST", create())).status).toBe(422);
    manifest.retained = true; await env.PLAYERS.getByName(H).removeRoom(R, 3);
    const r = await call("/v2/campaigns", "POST", create()); expect(r.status).toBe(409);
    expect(await r.json()).toMatchObject({ error: { code: "campaign_link_unavailable" } });
    expect(await env.PLAYERS.getByName(H).listRooms()).toEqual([]);
  });
  it("returns bound guest and own-invite host retries without extra slots after expiry and creation pause", async () => {
    await paired(); const before = await bytes(); const clock = Date.now; vi.spyOn(Date, "now").mockReturnValue(clock() + 8 * 86400000);
    for (const owner of [G, H]) {
      const r = await call("/v2/campaigns/join", "POST", join(), owner, { CAMPAIGN_CREATION_ENABLED: "false" });
      expect(r.status).toBe(200); expect((await r.json<{ campaign: CampaignView }>()).campaign.player_slot).toBe(owner === H ? "p0" : "p1");
      expect(await env.PLAYERS.getByName(owner).listRooms()).toHaveLength(1);
    }
    expect(await bytes()).toEqual(before); expect(globalThis.fetch).not.toHaveBeenCalled();
  });
  it("holds unmarked control requests and global-disabled retries, without silently dropping durable links", async () => {
    await made(); const before = await bytes();
    expect((await call("/v2/campaigns/" + R, "GET", undefined, H, {}, false)).status).toBe(409);
    expect((await call("/v2/campaigns", "POST", create(), H, { V2_ROOMS_ENABLED: "false" })).status).toBe(503);
    expect(await bytes()).toEqual(before); expect(await env.PLAYERS.getByName(H).listRooms()).toHaveLength(1);
  });
  it("preserves accepted Join and links when the original device rotates at the real binding reply boundary", async () => {
    await made(); const nextToken = "b".repeat(43), nextHash = await digest(nextToken);
    await runInDurableObject(root(), instance => {
      const original = instance.campaignHttpJoin;
      const spy = vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignHttpJoin").mockImplementation(async function(this: typeof instance, ...args: Parameters<typeof instance.campaignHttpJoin>) {
        if (this !== instance) return original.apply(this, args);
        const result = await original.apply(instance, args);
        if (result.ok) await runInDurableObject(env.PLAYERS.getByName(G), (_, ctx) => {
          const identity = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data);
          identity.device_hash = nextHash; ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
        });
        spy.mockRestore(); return result;
      });
    });
    const stale = await call("/v2/campaigns/join", "POST", join(), G); expect(stale.status).toBe(401);
    expect(unwrap(await root().campaignControl(H)).campaign.guest_id).toBe(G);
    expect(await env.PLAYERS.getByName(G).listRooms()).toEqual([{ room_id: R, invite_code: "", host: false, api_version: 3 }]);
    const retry = await call("/v2/campaigns/join", "POST", join(), G, {}, true, nextToken); expect(retry.status).toBe(200);
    expect((await retry.json<{ campaign: CampaignView }>()).campaign.guest_id).toBe(G);
  });
  it("lists only anchors without mutating links and holds rather than pruning an unknown root", async () => {
    const first = await made(); const listed = await call("/v2/campaigns"); expect(await listed.json()).toEqual({ campaigns: [first.campaign] });
    await runInDurableObject(root(), (_, ctx) => ctx.storage.sql.exec("UPDATE metadata SET schema_version=999 WHERE id=1"));
    expect((await call("/v2/campaigns")).status).toBe(409); expect(await env.PLAYERS.getByName(H).listRooms()).toHaveLength(1);
  });
  it("requires only the host's access for a fresh paid destination and retains the exact source on402", async () => {
    await paired(); const body = await complete(), before = await bytes(); nextInvite = "CD".repeat(10);
    const denied = await call(`/v2/campaigns/${R}/continue`, "POST", body); expect(denied.status).toBe(402);
    expect(await denied.json()).toMatchObject({ error: { code: "host_unlock_required" } }); expect(await bytes()).toEqual(before);
    unwrap(await env.PLAYERS.getByName(H).redeemTesterAccess(H, hash, true));
    const accepted = await call(`/v2/campaigns/${R}/continue`, "POST", body); expect(accepted.status).toBe(200);
    const result = await accepted.json<{ status: string; campaign: CampaignView }>(); expect(result.status).toBe("accepted");
    expect(result.campaign.current_index).toBe(1); expect(result.campaign.activation).toBeNull();
    expect(await env.PLAYERS.getByName(G).storedTesterGrant(G)).toBeNull();
    expect(await env.PLAYERS.getByName(H).listRooms()).toHaveLength(1); expect(await env.PLAYERS.getByName(G).listRooms()).toHaveLength(1);
    const requests = vi.mocked(globalThis.fetch).mock.calls.length;
    const retry = await call(`/v2/campaigns/${R}/continue`, "POST", body); expect(retry.status).toBe(200);
    expect(vi.mocked(globalThis.fetch).mock.calls).toHaveLength(requests);
    const receipt = await call(`/v2/campaigns/${R}/operations/${body.idempotency_key}`); expect(receipt.status).toBe(200);
    const resume = await call(`/v2/campaigns/${R}/resume`, "POST", { schema_version: 1, campaign_key: key,
      transition_id: result.campaign.chapters[0].completion!.transition_id }); expect(resume.status).toBe(200);
  });
  it("keeps accepted activation debt on unknown replies, GET stays pure, and explicit Resume recovers without repurchase", async () => {
    await paired(); const body = await complete(); nextInvite = "CD".repeat(10);
    unwrap(await env.PLAYERS.getByName(H).redeemTesterAccess(H, hash, true));
    const targetId = (await digest("v2:" + nextInvite)).slice(0, 22);
    await runInDurableObject(env.ROOMS_V2.getByName(targetId), instance => {
      const original = instance.campaignBoundTarget; let failures = 2;
      vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignBoundTarget").mockImplementation(async function(this: typeof instance, ...args: Parameters<typeof instance.campaignBoundTarget>) {
        if (this !== instance) return original.apply(this, args);
        if (args[1] && failures-- > 0) return fail(503, "synthetic_activation_reply_unknown");
        return original.apply(instance, args);
      });
    });
    const response = await call(`/v2/campaigns/${R}/continue`, "POST", body); expect(response.status).toBe(200);
    const accepted = await response.json<{ campaign: CampaignView }>(); expect(accepted.campaign.activation).not.toBeNull();
    const before = await bytes(), token = accepted.campaign.activation!.transition_id;
    expect((await call(`/v2/campaigns/${R}`)).status).toBe(200);
    expect((await call(`/v2/campaigns/${R}/operations/${body.idempotency_key}`)).status).toBe(200); expect(await bytes()).toEqual(before);
    const request = { schema_version: 1, campaign_key: key, transition_id: token };
    const failed = await call(`/v2/campaigns/${R}/resume`, "POST", request); expect(failed.status).toBe(503); expect(await bytes()).toEqual(before);
    await runInDurableObject(env.PLAYERS.getByName(H), (_, ctx) => {
      const identity = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data);
      delete identity.tester_grant; ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    });
    const providerCalls = vi.mocked(globalThis.fetch).mock.calls.length;
    const recovered = await call(`/v2/campaigns/${R}/resume`, "POST", request); expect(recovered.status).toBe(200);
    expect(await recovered.json()).toMatchObject({ campaign: { activation: null, current_index: 1 } });
    expect(vi.mocked(globalThis.fetch).mock.calls).toHaveLength(providerCalls);
  });
  it("returns read-only pending202 after a lost initializer reply and exact Continue retries the original allocation", async () => {
    await paired(); const body = await complete(); nextInvite = "CD".repeat(10);
    unwrap(await env.PLAYERS.getByName(H).redeemTesterAccess(H, hash, true));
    const targetId = (await digest("v2:" + nextInvite)).slice(0, 22), target = env.ROOMS_V2.getByName(targetId);
    await runInDurableObject(target, instance => {
      const original = instance.campaignBoundTarget;
      const spy = vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignBoundTarget").mockImplementation(async function(this: typeof instance, ...args: Parameters<typeof instance.campaignBoundTarget>) {
        if (this !== instance) return original.apply(this, args);
        const actual = await original.apply(instance, args); spy.mockRestore();
        return actual.ok ? fail(503, "synthetic_lost_initialized_reply") : actual;
      });
    });
    expect((await call(`/v2/campaigns/${R}/continue`, "POST", body)).status).toBe(503);
    const before = await bytes(), initialized = await runInDurableObject(target, (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data);
    const pending = await call(`/v2/campaigns/${R}/operations/${body.idempotency_key}`); expect(pending.status).toBe(202);
    expect(await pending.json()).toMatchObject({ status: "pending", idempotency_key: body.idempotency_key,
      campaign: { state: "continuing", transition: { phase: "source_sealed" } } });
    expect(await bytes()).toEqual(before);
    await runInDurableObject(env.PLAYERS.getByName(H), (_, ctx) => {
      const identity = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data);
      delete identity.tester_grant; ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    });
    nextInvite = "EF".repeat(10); // Retry must ignore any new allocation candidate.
    const providerCalls = vi.mocked(globalThis.fetch).mock.calls.length;
    const result = await call(`/v2/campaigns/${R}/continue`, "POST", body); expect(result.status).toBe(200);
    expect(await result.json()).toMatchObject({ status: "accepted", campaign: { chapters: [{ room_id: R }, { room_id: targetId }], activation: null } });
    expect(await runInDurableObject(target, (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data)).toBe(initialized);
    expect(vi.mocked(globalThis.fetch).mock.calls).toHaveLength(providerCalls);
  });
  it("returns200 for an earlier Resume token while preserving a different later activation debt", async () => {
    const { definition_hash: _old, ...content } = structuredClone(definition);
    content.campaign_id = "fixture-three-http"; content.chapters.push(structuredClone(content.chapters[0]));
    manifest.extra = { ...content, definition_hash: await digest(canonicalJson(content)) };
    const k = { campaign_id: content.campaign_id, campaign_version: content.campaign_version, definition_hash: manifest.extra.definition_hash };
    expect((await call("/v2/campaigns", "POST", { ...create(), campaign_key: k })).status).toBe(201);
    expect((await call("/v2/campaigns/join", "POST", { ...join(), campaign_key: k }, G)).status).toBe(200);
    unwrap(await env.PLAYERS.getByName(H).redeemTesterAccess(H, hash, true)); nextInvite = "CD".repeat(10);
    const first = await call(`/v2/campaigns/${R}/continue`, "POST", await complete(k)); expect(first.status).toBe(200);
    const firstView = (await first.json<{ campaign: CampaignView }>()).campaign, firstToken = firstView.chapters[0].completion!.transition_id;
    const childId = firstView.chapters[1].room_id!, child = env.ROOMS_V2.getByName(childId), c = { ...context(), room_id: childId };
    let s = unwrap(await child.snapshot(H, c));
    for (const [owner, recording, checkpoint] of [[H, rollingA, null], [G, rollingB, rollingMiddle], [G, homeA, null], [H, homeB, homeFinal]] as const) {
      s = unwrap(await child.commit(owner, { base_revision: s.revision, branch: s.branch, idempotency_key: crypto.randomUUID(), recording,
        ...(checkpoint ? { checkpoint } : {}) }, c)).room;
    }
    const view = unwrap(await root().campaignControl(H)).campaign, origin = { expected_revision: view.revision, from_index: 1,
      source: { room_id: childId, revision: s.revision, branch: s.branch, checkpoint_hash: homeFinal.checkpoint_hash } };
    const body = { schema_version: 1, campaign_key: k, idempotency_key: await campaignContinueKey(R, k, H, origin), ...origin };
    nextInvite = "EF".repeat(10); const lastId = (await digest("v2:" + nextInvite)).slice(0, 22);
    await runInDurableObject(env.ROOMS_V2.getByName(lastId), instance => {
      const original = instance.campaignBoundTarget;
      vi.spyOn(Object.getPrototypeOf(instance) as typeof instance, "campaignBoundTarget").mockImplementation(function(this: typeof instance, ...args: Parameters<typeof instance.campaignBoundTarget>) {
        if (this !== instance) return original.apply(this, args);
        return args[1] ? Promise.resolve(fail(503, "synthetic_later_activation_hold")) : original.apply(instance, args);
      });
    });
    const second = await call(`/v2/campaigns/${R}/continue`, "POST", body); expect(second.status).toBe(200);
    const later = (await second.json<{ campaign: CampaignView }>()).campaign; expect(later.activation).not.toBeNull();
    expect(later.activation!.transition_id).not.toBe(firstToken); const before = await bytes();
    const earlier = await call(`/v2/campaigns/${R}/resume`, "POST", { schema_version: 1, campaign_key: k, transition_id: firstToken });
    expect(earlier.status).toBe(200); expect((await earlier.json<{ campaign: CampaignView }>()).campaign.activation).toEqual(later.activation);
    expect(await bytes()).toEqual(before);
  });
  it("closes an unseen Create key without allowing a delayed fresh reservation", async () => {
    const r = await call("/v2/campaigns/cancel", "POST", create()); expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ schema_version: 1, operation: "campaign_admission_cancel", admission: "create", status: "cancelled",
      player_id: H, idempotency_key: create().idempotency_key, request_hash: await campaignAdmissionHash(H, "create", create()), campaign: null });
    const late = await call("/v2/campaigns", "POST", create()); expect(late.status).toBe(409); expect(await env.PLAYERS.getByName(H).listRooms()).toEqual([]);
  });
  it("settles accepted Create and Join read-only during deleting while refusing a new guest", async () => {
    await paired(); const body = await complete(); nextInvite = "CD".repeat(10);
    unwrap(await env.PLAYERS.getByName(H).redeemTesterAccess(H, hash, true));
    expect((await call(`/v2/campaigns/${R}/continue`, "POST", body)).status).toBe(200);
    await runInDurableObject(root(), async (_, ctx) => {
      expect(await eraseCampaignRoot(ctx.storage, G, R, null, { erase: async () => fail(503, "synthetic_child_unavailable") })).toMatchObject({ ok: false });
    });
    const before = await bytes();
    for (const [path, input, owner] of [["/v2/campaigns", create(), H], ["/v2/campaigns/join", join(), G]] as const) {
      const result = await call(path, "POST", input, owner, { CAMPAIGN_CREATION_ENABLED: "false" });
      expect(result.status).toBe(200); expect(await result.json()).toMatchObject({ campaign: { state: "deleting" } });
    }
    const outsider = randomToken(16); unwrap(await env.PLAYERS.getByName(outsider).create(outsider, hash, "b".repeat(64)));
    expect((await call("/v2/campaigns/join", "POST", join("fresh-deleting-join-0002"), outsider)).status).toBe(409);
    expect(await env.PLAYERS.getByName(outsider).listRooms()).toEqual([]); expect(await bytes()).toEqual(before);
  });
  it("cancels a nonexistent invite locally, survives eviction and fences that key if the root later appears", async () => {
    const bad = join(); expect((await call("/v2/campaigns/join", "POST", bad, G)).status).toBe(409);
    expect(await env.PLAYERS.getByName(G).listRooms()).toEqual([]);
    const cancelled = await call("/v2/campaigns/join/cancel", "POST", bad, G); expect(cancelled.status).toBe(200);
    expect(await cancelled.json()).toMatchObject({ status: "cancelled", request_hash: await campaignAdmissionHash(G, "join", bad), campaign: null });
    await evictDurableObject(env.PLAYERS.getByName(G)); await made();
    expect((await call("/v2/campaigns/join", "POST", bad, G)).status).toBe(409);
    expect((await call("/v2/campaigns/join", "POST", join("deliberate-new-join-0002"), G)).status).toBe(200);
  });
  it("makes unreserved cancellation and exact reservation mutually exclusive in either order", async () => {
    const a = join(), first = env.PLAYERS.getByName(G);
    expect(await first.cancelUnreservedCampaignJoin(a, hash)).toMatchObject({ ok: true, value: { status: "cancelled" } });
    expect(await first.reserveCampaignJoin(a, hash)).toMatchObject({ ok: false, code: "campaign_admission_cancelled" }); expect(await first.listRooms()).toEqual([]);
    const secondOwner = randomToken(16), second = env.PLAYERS.getByName(secondOwner); unwrap(await second.create(secondOwner, hash, "b".repeat(64)));
    unwrap(await second.reserveCampaignJoin(a, hash));
    expect(await second.cancelUnreservedCampaignJoin(a, hash)).toMatchObject({ ok: true, value: { status: "root_required" } }); expect(await second.listRooms()).toHaveLength(1);
    const racingOwner = randomToken(16), racing = env.PLAYERS.getByName(racingOwner); unwrap(await racing.create(racingOwner, hash, "b".repeat(64)));
    const outcomes = await Promise.all([racing.reserveCampaignJoin(a, hash), racing.cancelUnreservedCampaignJoin(a, hash)]);
    expect(outcomes.some(r => r.ok)).toBe(true);
    // A losing optimistic capture may hold, then the unchanged explicit retry
    // observes whichever local transaction won; neither outcome opens both.
    const final = unwrap(await racing.cancelUnreservedCampaignJoin(a, hash));
    if (final.status === "cancelled") { expect(await racing.reserveCampaignJoin(a, hash)).toMatchObject({ ok: false }); expect(await racing.listRooms()).toEqual([]); }
    else { expect(await racing.reserveCampaignJoin(a, hash)).toMatchObject({ ok: true }); expect(await racing.listRooms()).toHaveLength(1); }
  });
  it("does not mistake a missing host link for never-admitted Join-to-own-invite authority", async () => {
    await made(); await env.PLAYERS.getByName(H).removeRoom(R, 3);
    const input = join("host-own-invite-cancel-0003"), before = await bytes();
    expect(await env.PLAYERS.getByName(H).cancelUnreservedCampaignJoin(input, hash)).toMatchObject({ ok: true, value: { status: "root_required" } });
    const result = await call("/v2/campaigns/join/cancel", "POST", input, H);
    expect(result.status).toBe(409); expect(await result.json()).toMatchObject({ error: { code: "campaign_link_unavailable" } });
    expect(await bytes()).toEqual(before);
    await runInDurableObject(env.PLAYERS.getByName(H), (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT data FROM creations WHERE request_key=?", input.idempotency_key).toArray()).toEqual([]);
    });
  });
  it("allows blocked nonmember fenced cleanup and preserves blocked accepted membership as settlement-only", async () => {
    await made(); const a = join(); unwrap(await env.PLAYERS.getByName(G).reserveCampaignJoin(a, hash)); await block();
    const cancelled = await call("/v2/campaigns/join/cancel", "POST", a, G); expect(cancelled.status).toBe(200);
    expect(await cancelled.json()).toMatchObject({ status: "cancelled", campaign: null }); expect(await env.PLAYERS.getByName(G).listRooms()).toEqual([]);
    unwrap(await env.SAFETY_PROFILES.getByName(H).setBlock(H, hash, G, false));
    const b = join("accepted-other-key-0002"); expect((await call("/v2/campaigns/join", "POST", b, G)).status).toBe(200); await block();
    const before = await bytes(), accepted = await call("/v2/campaigns/join/cancel", "POST", a, G);
    expect(accepted.status).toBe(200); expect(await accepted.json()).toMatchObject({ status: "accepted", campaign: { guest_id: G } });
    expect(await bytes()).toEqual(before); expect((await call(`/v2/campaigns/${R}`, "GET", undefined, G)).status).toBe(403);
    expect((await call(`/v2/rooms/${R}`, "GET", undefined, G)).status).toBe(403); expect(await env.PLAYERS.getByName(G).listRooms()).toHaveLength(1);
  });
});
