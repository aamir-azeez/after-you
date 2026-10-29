import { env } from "cloudflare:workers";
import { reset, runInDurableObject as openRaw } from "cloudflare:test";
import { runInDurableObject } from "./room-objects";
import { meterAllRows } from "./meter";
import { afterEach, describe, expect, it, vi } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, type Outcome } from "../src/protocol";
import { isAlarmMetadataTable } from "../src/notification-storage";
import { TERMS_VERSION } from "../src/public-policy";
import { cancelCampaignJoinRoot } from "../src/v2/campaign-root";
import { initializeCampaignTarget, type TargetInitializeRequest } from "../src/v2/campaign-target";
import { initializeCampaignStorageSchema } from "../src/v2/storage-schema";
import { MAX_ERASE_PLAYERS, MAX_SCAN_PLAYERS } from "../src/v2/campaign-drain";
import type { StoredCampaignAnchorV2, StoredCampaignMemberV2 } from "../src/v2/campaign-storage";
import type { CampaignDefinition, CampaignJoin, CampaignKey, CampaignView } from "../src/v2/campaign-types";
import type { RoomStateV2 } from "../src/v2/room";
import fixture from "./fixtures/campaign-control-v2.json";
import highA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import highB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import middle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import lowA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import lowB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import final from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";
import { withConfig } from "./config";

// Synthetic fixture identities only.
const H = fixture.active_view.host_id, G = fixture.active_view.guest_id!, R = fixture.active_view.campaign_room_id, I = fixture.active_view.invite_code!;
const X = "Xguest_never_member_01", U = "Unrelated_player_00001", OTHER = "Q".repeat(22), TOKEN = "c".repeat(64);
const TOKENS: Record<string, string> = { [H]: "h".repeat(43), [G]: "g".repeat(43), [X]: "x".repeat(43), [U]: "u".repeat(43) };
const OPERATOR = "o".repeat(43), RECOVERY = "b".repeat(64);
const definition = fixture.definition as CampaignDefinition, key = fixture.active_view.campaign_key as CampaignKey;
const resolver = (candidate: CampaignKey) => canonicalJson(candidate) === canonicalJson(key) ? definition : undefined;
const ORDINARY_INVITE = "0123456789ABCDEF0123", OTHER_INVITE = "FEDCBA9876543210FEDC", TARGET_INVITE = "EF".repeat(10);
let address = 0;

function value<T>(out: Outcome<T>): T { if (!out.ok) throw new Error(out.code); return out.value; }
const objectId = (player: string) => env.PLAYERS.idFromName(player).toString();
const join = (i = 0): CampaignJoin => ({ schema_version: 2, idempotency_key: "drain-join-key-" + i.toString().padStart(4, "0"), invite_code: I, campaign_key: structuredClone(key), supported_simulation_versions: [6] });
const hostIntent = () => ({ creation_schema: 2 as const, link: { room_id: R, invite_code: I, host: true, api_version: 3 }, campaign_key: structuredClone(key) });
const state = (ctx: DurableObjectState) => JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data) as RoomStateV2;
const v2Id = async (invite: string) => (await digest("v2:" + invite)).slice(0, 22);

type Stub = { id: DurableObjectId };
async function inventory(stub: Stub & object) {
  return runInDurableObject(stub as DurableObjectStub<Rpc.DurableObjectBranded>, async (_, ctx) => ({
    alarm: await ctx.storage.getAlarm(), kv: [...ctx.storage.kv.list()],
    tables: ctx.storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray()
      .map(table => ({ ...table, rows: isAlarmMetadataTable(table) ? null : ctx.storage.sql.exec('SELECT * FROM "' + table.name + '" ORDER BY rowid').toArray() }))
  }));
}
const rows = (ctx: DurableObjectState, sql: string) => ctx.storage.sql.exec(sql).toArray();

/** Sums rows written by every SQL statement each named object runs from now on. */
async function meter(stubs: (Stub & object)[]) {
  const cursors: { rowsWritten: number }[] = [];
  for (const stub of stubs) await runInDurableObject(stub as DurableObjectStub<Rpc.DurableObjectBranded>, (_, ctx) => {
    const original = ctx.storage.sql.exec.bind(ctx.storage.sql);
    vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((query: string, ...bindings: unknown[]) => { const cursor = original(query, ...bindings); cursors.push(cursor); return cursor; }) as typeof ctx.storage.sql.exec);
  });
  return () => cursors.reduce((sum, cursor) => sum + cursor.rowsWritten, 0);
}

/** Durable Object requests the Worker itself makes, by namespace and method. */
function counted() {
  const calls: string[] = [];
  const wrap = <N extends object>(namespace: N, label: string): N => new Proxy(namespace, { get(target, property) {
    const own = Reflect.get(target, property);
    if (property !== "getByName" && property !== "get") return typeof own === "function" ? own.bind(target) : own;
    return (...args: unknown[]) => {
      const stub = Reflect.apply(own as (...a: unknown[]) => object, target, args) as object;
      return new Proxy(stub, { get(object, method) {
        const member = Reflect.get(object, method);
        if (typeof member !== "function" || typeof method !== "string" || method === "then") return member;
        return (...input: unknown[]) => { calls.push(label + "." + method); return Reflect.apply(member, object, input); };
      } });
    };
  } });
  return { calls, env: { PLAYERS: wrap(env.PLAYERS, "Player"), ROOMS_V2: wrap(env.ROOMS_V2, "RoomV2") } };
}

function request(path: string, init: { method?: string; body?: unknown; token?: string | null; player?: string; story?: boolean } = {}) {
  const headers: Record<string, string> = { "Content-Type": "application/json", "CF-Connecting-IP": "198.22.0." + (++address % 250) };
  if (init.story) headers["X-AfterYou-Campaign-Schema"] = "2";
  if (init.token !== null) headers.Authorization = "Bearer " + (init.token ?? OPERATOR);
  if (init.player) { headers["X-Player-Id"] = init.player; headers.Authorization = "Bearer " + TOKENS[init.player]; }
  return new Request("https://game.test" + path, { method: init.method ?? "POST", headers, body: init.body === undefined ? undefined : JSON.stringify(init.body) });
}
async function drain<T = Record<string, unknown>>(action: string, body: unknown, overrides: Record<string, unknown> = {}): Promise<T> {
  const response = await worker.fetch(request("/operator/story/" + action, { body }), withConfig({ ...env, STORY_DRAIN_ENABLED: "true", SAFETY_OPERATOR_TOKEN: OPERATOR, ...overrides }) as unknown as Env);
  const text = await response.text();
  if (response.status !== 200) throw new Error(response.status + " " + text);
  return JSON.parse(text) as T;
}
/** The flag values live on 2026-10-16 (deploy-20261016-roomcap) that are still flags, so routes answer as they do for players today. */
const LIVE_FLAGS = { RELAY_PHOTOS_ENABLED: "true", PHOTO_TRANSFER_ENABLED: "true", NOTIFICATIONS_ENABLED: "true",
  FRIEND_ROOM_EVENTS_ENABLED: "true", TESTER_ACCESS_ENABLED: "true", CAMPAIGN_CREATION_ENABLED: "false", CAMPAIGN_MUTATIONS_ENABLED: "false" };
async function roomRead(owner: string, roomId: string, method = "GET", suffix = "", body?: unknown) {
  const response = await worker.fetch(request("/v2/rooms/" + roomId + suffix, { method, player: owner, body }), withConfig({ ...env, ...LIVE_FLAGS }) as unknown as Env);
  return { status: response.status, headers: [...response.headers], body: await response.text() };
}
/** Every room-scoped route a client can call, as campaign-room-access.test.ts lists them, plus redo, history, replay transfer and leave. */
const ROOM_ROUTES: [string, string, unknown?][] = [
  ["", "GET"], ["", "DELETE"], ["/operations/accepted-turn-key-01", "GET"], ["/collection", "GET"], ["/pairs/p0-0", "GET"],
  ["/photos/t0-0-a", "GET"], ["/photos/t0-0-a", "POST", {}], ["/photos/t0-0-a", "DELETE", {}], ["/photos/t0-0-a/delivery", "GET"], ["/photos/t0-0-a/ack", "POST", {}],
  ["/photo-operations/saved-photo-key-001", "GET"], ["/reactions/p0-0", "GET"], ["/reactions/p0-0", "POST", {}], ["/reaction-operations/saved-react-key-001", "GET"],
  ["/turns", "POST", { base_revision: 0, branch: 0, idempotency_key: "drain-old-client-turn", recording: highA }], ["/fork", "POST", {}], ["/presence", "GET"],
  ["/redo", "GET"], ["/redo", "POST", {}], ["/history", "GET"], ["/history/0", "GET"], ["/replay-transfer", "GET"], ["/replay-transfer/manifest", "GET"], ["/leave", "POST", { schema_version: 1 }]
];
/** What an old client gets from every room route, for both members. */
async function oldClientAnswers(roomIds: string[]) {
  const answers = [];
  for (const id of roomIds) for (const owner of [H, G]) for (const [suffix, method, body] of ROOM_ROUTES) answers.push({ route: method + " " + suffix, ...await roomRead(owner, id, method, suffix, body) });
  return answers;
}

async function identity(owner: string) {
  const player = env.PLAYERS.getByName(owner);
  value(await player.create(owner, await digest(TOKENS[owner]), RECOVERY));
  return player;
}

/** A published two-chapter Story (photo, reaction, Join history, notification, child room), two Story
 * members, a third player whose Join never landed, an ordinary room the members also share, and an
 * unrelated player with an ordinary room of their own. */
async function world() {
  const host = await identity(H), guest = await identity(G), stranger = await identity(X), unrelated = await identity(U);
  value(await host.reserveCampaignRoom("drain-host-create-0001", hostIntent(), await digest(TOKENS[H])));
  value(await guest.reserveCampaignJoin(join(), await digest(TOKENS[G])));
  value(await stranger.reserveCampaignJoin(join(5), await digest(TOKENS[X])));

  const targetId = await v2Id(TARGET_INVITE), root = env.ROOMS_V2.getByName(R), child = env.ROOMS_V2.getByName(targetId);
  value(await root.initialize(R, H, I, definition.chapters[0])); let s = value(await root.join(G, I, [6]));
  for (const [owner, recording, checkpoint] of [[H, highA, null], [G, highB, middle], [G, lowA, null], [H, lowB, final]] as const)
    s = value(await root.commit(owner, { base_revision: s.revision, branch: s.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) })).room;
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  // Shared photos always need the safety terms accepted.
  value(await env.SAFETY_PROFILES.getByName(H).accept(H, await digest(TOKENS[H]), TERMS_VERSION));
  value(await root.updatePhoto(H, "t0-0-a", { idempotency_key: crypto.randomUUID(), recording_hash: highA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64: btoa(String.fromCharCode(...bytes)), sha256 }));
  value(await root.react(G, "p0-0", { idempotency_key: crypto.randomUUID(), a_hash: highA.recording_hash, b_hash: highB.recording_hash, expected_reaction_revision: 0, reaction: "love" }));
  const origin = { expected_revision: 1, from_index: 0, source: { room_id: R, revision: s.revision, branch: s.branch, checkpoint_hash: s.checkpoint.checkpoint_hash } };
  const target = { room_id: targetId, invite_code: TARGET_INVITE, index: 1, chapter: definition.chapters[1] };
  const targetRequest: TargetInitializeRequest = { schema_version: 1, binding: { campaign_room_id: R, campaign_key: key, room_id: targetId, chapter_index: 1, chapter: definition.chapters[1], host_id: H, guest_id: G, member_transition_id: TOKEN }, origin, target_intent: target };
  await runInDurableObject(root, async (_, ctx) => {
    const control = structuredClone(fixture.active_view) as CampaignView; control.invite_expires_at = state(ctx).invite_expires_at;
    control.revision = 5; control.current_index = 1; control.chapters[1].room_id = targetId; control.activation = { transition_id: TOKEN };
    control.chapters[0].completion = { source_revision: s.revision, source_branch: s.branch, checkpoint_hash: s.checkpoint.checkpoint_hash, transition_id: TOKEN, from_campaign_revision: 1, accepted_campaign_revision: 5 };
    const a: StoredCampaignAnchorV2 = { schema_version: 2, state: "live", definition: structuredClone(definition), control, pending: null, closed_before_branches: [0, 0], deletion: null, activation: { transition_id: TOKEN, origin, target_intent: target, accepted_revision: 5 } };
    const m: StoredCampaignMemberV2 = { schema_version: 2, campaign_room_id: R, campaign_key: key, room_id: R, chapter_index: 0, chapter: definition.chapters[0], host_id: H, guest_id: G, transition_id: null, status: "sealed", seal: { transition_id: TOKEN, origin }, incoming: null };
    initializeCampaignStorageSchema(ctx.storage);
    ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify(a)); ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(m));
    value(await cancelCampaignJoinRoot(ctx.storage, OTHER, join(7), resolver));
  });
  value(await runInDurableObject(child, (_, ctx) => initializeCampaignTarget(ctx.storage, targetRequest, resolver)));

  const ordinaryId = await v2Id(ORDINARY_INVITE), ordinary = env.ROOMS_V2.getByName(ordinaryId);
  value(await ordinary.initialize(ordinaryId, H, ORDINARY_INVITE, definition.chapters[0])); const o = value(await ordinary.join(G, ORDINARY_INVITE, [6]));
  value(await ordinary.commit(H, { base_revision: o.revision, branch: o.branch, idempotency_key: crypto.randomUUID(), recording: highA }));
  value(await host.addRoom({ room_id: ordinaryId, invite_code: ORDINARY_INVITE, host: true, api_version: 2 }));
  value(await guest.addRoom({ room_id: ordinaryId, invite_code: "", host: false, api_version: 2 }));
  const otherId = await v2Id(OTHER_INVITE), other = env.ROOMS_V2.getByName(otherId);
  value(await other.initialize(otherId, U, OTHER_INVITE, definition.chapters[0]));
  value(await unrelated.addRoom({ room_id: otherId, invite_code: OTHER_INVITE, host: true, api_version: 2 }));
  return { host, guest, stranger, unrelated, root, child, targetId, ordinary, ordinaryId, other, otherId };
}
type World = Awaited<ReturnType<typeof world>>;
const everyObject = (w: World) => [w.host, w.guest, w.stranger, w.unrelated, w.root, w.child, w.ordinary, w.other];
const snapshotAll = async (w: World) => Promise.all(everyObject(w).map(stub => inventory(stub)));
/** Everything a player holds besides Story rows: identity and non-v3 links. */
async function ordinaryPlayerRows(stub: World["host"]) {
  return runInDurableObject(stub, (_, ctx) => ({ identity: rows(ctx, "SELECT * FROM identity"),
    rooms: rows(ctx, "SELECT room_id,data FROM rooms ORDER BY rowid").filter(row => JSON.parse(String(row.data)).api_version !== 3),
    creations: rows(ctx, "SELECT request_key,data FROM creations ORDER BY rowid").filter(row => ![2, 3].includes(JSON.parse(String(row.data)).creation_schema)) }));
}
const scanAll = () => drain<{ players: { object_id: string; player_id: string; state: string; links: { room_id: string; host: boolean }[]; intents: Record<string, number>; open_intent_rooms: string[] }[] }>("scan", { schema_version: 1, players: [H, G, X, U].map(objectId) });
type Census = { kind: string; children: string[]; pending_targets: string[]; rows: Record<string, number> };
type Count = { anchors: { room_id: string; root: Census; children: (Census & { room_id: string })[] }[]; totals: { campaign_rooms: number; deleted_rooms: number; absent_rooms: number; unreadable_rooms: number; pending_targets: number; rows: Record<string, number>; total_rows: number } };
type Erase = { room_id: string; before: string; root: string; players: { player_id: string; result: string }[]; after: string };
const count = () => drain<Count>("count", { schema_version: 1, anchors: [R] });
const erase = (players = [H, G, X]) => drain<Erase>("erase", { schema_version: 1, anchor: R, players });

afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("operator Story drain", () => {
  it("answers byte-for-byte as before while the flag is off, and only to the operator credential when on", async () => {
    await identity(H);
    const send = async (path: string, init: Parameters<typeof request>[1], vars: Record<string, unknown>) => {
      const response = await worker.fetch(request(path, init), withConfig({ ...env, SAFETY_OPERATOR_TOKEN: OPERATOR, ...vars }) as unknown as Env);
      return { status: response.status, headers: [...response.headers], body: await response.text() };
    };
    const body = { schema_version: 1, players: [objectId(H)] };
    for (const off of [{}, { STORY_DRAIN_ENABLED: "false" }, { STORY_DRAIN_ENABLED: "TRUE" }]) {
      for (const init of [{ body }, { body, player: H }, { method: "GET" }, { body, token: null }]) {
        // Today's answer is the one any unrouted path gets: authentication, then not_found.
        expect(await send("/operator/story/scan", init, off)).toEqual(await send("/operator/unrouted/scan", init, off));
      }
      expect(await send("/operator/story/scan", { body }, off)).toEqual({ status: 401, headers: [["cache-control", "no-store"], ["content-type", "application/json; charset=utf-8"], ["x-content-type-options", "nosniff"]], body: '{"error":{"code":"invalid_auth","retryable":false}}' });
    }
    const on = { STORY_DRAIN_ENABLED: "true" };
    for (const init of [{ body, player: H }, { body, token: "p".repeat(43) }, { body, token: null }, { method: "GET", player: H }])
      expect((await send("/operator/story/scan", init, on)).body).toBe('{"error":{"code":"invalid_operator_auth","retryable":false}}');
    expect((await send("/operator/story/scan", { body }, { ...on, SAFETY_OPERATOR_TOKEN: undefined })).status).toBe(401);
    expect((await send("/operator/story/scan", { method: "GET" }, on)).status).toBe(405);
    expect((await send("/operator/story/other", { body }, on)).status).toBe(404);
    expect((await send("/operator/story/scan", { body: { ...body, extra: 1 } }, on)).status).toBe(400);
    expect((await send("/operator/story/scan", { body: { schema_version: 1, players: Array.from({ length: MAX_SCAN_PLAYERS + 1 }, (_, i) => objectId("P" + i.toString().padStart(21, "0"))) } }, on)).status).toBe(400);
    expect((await send("/operator/story/erase", { body: { schema_version: 1, anchor: R, players: Array.from({ length: MAX_ERASE_PLAYERS + 1 }, (_, i) => "P" + i.toString().padStart(21, "0")) } }, on)).status).toBe(400);
    expect((await send("/operator/story/scan", { body }, on)).status).toBe(200);
  });

  it("counts exactly and writes nothing in the dry run", async () => {
    const w = await world(), before = await snapshotAll(w), written = await meter(everyObject(w));
    const scan = await scanAll();
    expect(scan.players.map(p => [p.player_id, p.state, p.links, p.intents, p.open_intent_rooms])).toEqual([
      [H, "active", [{ room_id: R, host: true }], { allocations: 1, open: 0, closed: 0, unreadable: 0 }, []],
      [G, "active", [{ room_id: R, host: false }], { allocations: 0, open: 1, closed: 0, unreadable: 0 }, [R]],
      [X, "active", [{ room_id: R, host: false }], { allocations: 0, open: 1, closed: 0, unreadable: 0 }, [R]],
      [U, "active", [], { allocations: 0, open: 0, closed: 0, unreadable: 0 }, []]]);
    const counted = await count();
    expect(counted.anchors[0].root).toMatchObject({ kind: "campaign", campaign_room_id: R, state: "active", host_id: H, guest_id: G, children: [w.targetId], pending_targets: [] });
    expect(counted.anchors[0].children.map(c => [c.room_id, c.kind])).toEqual([[w.targetId, "campaign"]]);
    const direct = await runInDurableObject(w.root, (_, ctx) => Object.fromEntries(["turns", "pairs", "photos", "photo_operations", "pair_reactions", "reaction_operations", "operations", "campaign_join_attempts"].map(t => [t, Number(rows(ctx, `SELECT COUNT(*) AS n FROM ${t}`)[0].n)])));
    expect(direct).toMatchObject({ turns: 4, pairs: 2, photos: 1, campaign_join_attempts: 1 });
    for (const [table, n] of Object.entries(direct)) expect(counted.anchors[0].root.rows[table] ?? 0, table).toBe(n);
    expect(counted.totals).toMatchObject({ campaign_rooms: 2, deleted_rooms: 0, absent_rooms: 0, pending_targets: 0 });
    expect(counted.totals.rows.photos).toBe(1); expect(counted.totals.rows.pairs).toBe(2); expect(counted.totals.rows.turns).toBe(4);
    expect(counted.totals.total_rows).toBe(Object.values(counted.totals.rows).reduce((a, b) => a + b, 0));
    expect(written()).toBe(0);
    expect(await snapshotAll(w)).toEqual(before);
  });

  it("erases every Story room, link and open intent, keeps ordinary data, and old clients still get 409", async () => {
    const w = await world();
    const ordinaryBefore = await Promise.all([w.ordinary, w.other, w.unrelated].map(stub => inventory(stub)));
    const playersBefore = await Promise.all([w.host, w.guest, w.stranger].map(ordinaryPlayerRows));
    const readsBefore = await oldClientAnswers([R, w.targetId]);
    expect(readsBefore).toHaveLength(4 * ROOM_ROUTES.length);
    expect(readsBefore.filter(read => read.route !== "POST /leave").map(read => read.status + " " + read.body)).toEqual(Array(4 * (ROOM_ROUTES.length - 1)).fill('409 {"error":{"code":"campaign_client_required","retryable":false}}'));
    // Leave only ever removes the caller's own v2 link, so on a Story room it is the same no-op before and after.
    expect([...new Set(readsBefore.filter(read => read.route === "POST /leave").map(read => read.status + " " + read.body))]).toEqual(['200 {"schema_version":1,"removed":true}']);

    const result = await erase();
    expect(result).toEqual({ schema_version: 1, room_id: R, before: "campaign", root: "erased", players: [{ player_id: H, result: "released" }, { player_id: G, result: "released" }, { player_id: X, result: "released" }], after: "deleted" });
    for (const [stub, roomId] of [[w.root, R], [w.child, w.targetId]] as const) await runInDurableObject(stub, (_, ctx) => {
      for (const table of ["turns", "pairs", "photos", "photo_operations", "photo_delivery", "pair_reactions", "reaction_operations", "operations", "campaign_operations"])
        expect(rows(ctx, `SELECT 1 FROM ${table}`), table).toEqual([]);
      if (roomId === R) expect(rows(ctx, "SELECT 1 FROM campaign_join_attempts")).toEqual([]);
      expect(state(ctx)).toEqual({ deleted: true });
    });
    const scan = await scanAll();
    for (const p of scan.players) { expect(p.links).toEqual([]); expect(p.intents.open).toBe(0); }
    expect((await count()).totals).toMatchObject({ campaign_rooms: 0, deleted_rooms: 1, total_rows: 0 });
    expect(await Promise.all([w.ordinary, w.other, w.unrelated].map(stub => inventory(stub)))).toEqual(ordinaryBefore);
    expect(await Promise.all([w.host, w.guest, w.stranger].map(ordinaryPlayerRows))).toEqual(playersBefore);
    // An old client holding a Story room id is turned away exactly as before the erase.
    expect(await oldClientAnswers([R, w.targetId])).toEqual(readsBefore);
    expect((await roomRead(H, w.ordinaryId)).status).toBe(200);
  }, 60_000); // 96 room requests before and after

  it("answers a Story-capable client (0.6.0 to 0.6.3, header 2) on the campaign list, read and reconcile", async () => {
    const w = await world();
    const story = async (owner: string, method: string, path: string, body?: unknown) => {
      const response = await worker.fetch(request(path, { method, player: owner, body, story: true }), withConfig({ ...env, ...LIVE_FLAGS }) as unknown as Env);
      return response.status + " " + await response.text();
    };
    const calls = (owner: string) => [story(owner, "GET", "/v2/campaigns"), story(owner, "GET", "/v2/campaigns/" + R), story(owner, "GET", "/v2/rooms/" + R), story(owner, "POST", "/v2/campaigns/" + R + "/reconcile-deletion", { schema_version: 1 })];
    const [list, read, room, reconcile] = await Promise.all(calls(H));
    expect(list).toContain('"campaign_room_id":"' + R + '"'); expect(read.startsWith("200 ")).toBe(true); expect(room.startsWith("200 ")).toBe(true);
    expect(reconcile).toBe('409 {"error":{"code":"campaign_not_terminal","retryable":false}}');
    await erase();
    const unavailable = '409 {"error":{"code":"campaign_state_unavailable","retryable":false}}';
    for (const owner of [H, X]) expect(await Promise.all(calls(owner))).toEqual(['200 {"campaigns":[]}', unavailable, unavailable,
      '200 {"schema_version":1,"operation":"campaign_terminal_cleanup","status":"released","player_id":"' + owner + '","campaign_room_id":"' + R + '"}']);
    expect(await story(H, "GET", "/v2/rooms/" + w.targetId)).toBe(unavailable);
  });

  it("is idempotent: a second run writes nothing and changes nothing", async () => {
    const w = await world(); await erase();
    const before = await snapshotAll(w), written = await meter(everyObject(w));
    expect(await erase()).toEqual({ schema_version: 1, room_id: R, before: "deleted", root: "already_deleted", players: [H, G, X].map(id => ({ player_id: id, result: "no_link" })), after: "deleted" });
    expect(written()).toBe(0); expect(await snapshotAll(w)).toEqual(before);
  });

  it("resumes after an interrupted cascade without releasing any link early", async () => {
    const w = await world();
    await runInDurableObject(w.child, async (_, ctx) => { await ctx.storage.setAlarm(Date.now() + 60_000); });
    const stopped = await erase();
    expect(stopped.root).not.toBe("erased"); expect(stopped.players).toEqual([]); expect(stopped.after).toBe("campaign");
    await runInDurableObject(w.root, (_, ctx) => { const a = JSON.parse(String(rows(ctx, "SELECT data FROM campaign_anchor")[0].data)) as StoredCampaignAnchorV2; expect(a.control.state).toBe("deleting"); expect(a.deletion?.completed_room_ids).toEqual([]); });
    expect((await scanAll()).players.slice(0, 3).every(p => p.links.length === 1)).toBe(true);
    await runInDurableObject(w.child, async (_, ctx) => { await ctx.storage.deleteAlarm(); });
    expect(await erase()).toMatchObject({ before: "campaign", root: "erased", after: "deleted" });
    expect((await scanAll()).players.every(p => p.links.length === 0)).toBe(true);
  });

  it("keeps identity deletion working mid-drain, and the drain then leaves that identity alone", async () => {
    const w = await world();
    await runInDurableObject(w.child, async (_, ctx) => { await ctx.storage.setAlarm(Date.now() + 60_000); });
    expect((await erase()).root).not.toBe("erased");
    await runInDurableObject(w.child, async (_, ctx) => { await ctx.storage.deleteAlarm(); });
    const deleting = await worker.fetch(request("/v1/identity", { method: "DELETE", player: G }), env);
    expect(deleting.status).toBe(200); expect(await deleting.json()).toEqual({ deleted: true });
    expect(await erase()).toEqual({ schema_version: 1, room_id: R, before: "deleted", root: "already_deleted", players: [{ player_id: H, result: "released" }, { player_id: G, result: "identity_absent" }, { player_id: X, result: "released" }], after: "deleted" });
    const late = await worker.fetch(request("/v1/identity", { method: "DELETE", player: H }), env);
    expect(late.status).toBe(200); expect(await late.json()).toEqual({ deleted: true });
  });

  it("names the root of an open intent whose link is gone, and the erase closes that intent", async () => {
    const w = await world();
    await runInDurableObject(w.stranger, (_, ctx) => { ctx.storage.sql.exec("DELETE FROM rooms WHERE room_id=?", R); });
    const before = (await scanAll()).players.find(p => p.player_id === X)!;
    expect([before.links, before.intents.open, before.open_intent_rooms]).toEqual([[], 1, [R]]);
    expect((await erase()).players).toContainEqual({ player_id: X, result: "released" });
    const after = (await scanAll()).players.find(p => p.player_id === X)!;
    expect([after.links, after.intents.open, after.intents.closed, after.open_intent_rooms]).toEqual([[], 0, 1, []]);
  });

  it("leaves an identity that is being deleted to identity deletion", async () => {
    const w = await world();
    value(await w.stranger.beginDelete([1, 2, 3], await digest(TOKENS[X])));
    const result = await erase();
    expect(result.players).toEqual([{ player_id: H, result: "released" }, { player_id: G, result: "released" }, { player_id: X, result: "identity_deleting" }]);
    const finished = await worker.fetch(request("/v1/identity", { method: "DELETE", player: X }), env);
    expect(finished.status).toBe(200); expect(await finished.json()).toEqual({ deleted: true });
  });

  it("refuses ordinary rooms and chapter rooms as anchors without touching them", async () => {
    const w = await world(), before = await snapshotAll(w), written = await meter(everyObject(w));
    expect(await drain<Erase>("erase", { schema_version: 1, anchor: w.ordinaryId, players: [H, G] })).toMatchObject({ before: "ordinary", root: "not_campaign_root", players: [] });
    expect(await drain<Erase>("erase", { schema_version: 1, anchor: w.targetId, players: [H, G] })).toMatchObject({ before: "campaign", root: "not_campaign_root", players: [] });
    expect(written()).toBe(0); expect(await snapshotAll(w)).toEqual(before);
  });

  it("fences a host allocation whose root was never created, as identity deletion does", async () => {
    const host = await identity(H);
    value(await host.reserveCampaignRoom("drain-host-create-0001", hostIntent(), await digest(TOKENS[H])));
    expect((await count()).anchors[0].root.kind).toBe("absent");
    expect(await erase([H])).toEqual({ schema_version: 1, room_id: R, before: "absent", root: "erased", players: [{ player_id: H, result: "released" }], after: "deleted" });
    expect(await host.listRooms()).toEqual([]);
    expect((await roomRead(H, R)).body).toBe('{"error":{"code":"campaign_client_required","retryable":false}}');
  });

  it("reports one failing object as unreadable instead of failing its batch", async () => {
    const w = await world(), broken = objectId(X);
    const throwing = <N extends object>(namespace: N, method: string, hit: (args: unknown[]) => boolean): N => new Proxy(namespace, { get(target, property) {
      const own = Reflect.get(target, property);
      if (property !== "get" && property !== "getByName") return typeof own === "function" ? own.bind(target) : own;
      return (...args: unknown[]) => {
        const stub = Reflect.apply(own as (...a: unknown[]) => object, target, args) as object;
        return hit(args) ? new Proxy(stub, { get(object, name) { return name === method ? async () => { throw new Error("object_unavailable"); } : Reflect.get(object, name); } }) : stub;
      };
    } });
    const scan = await drain<{ players: { object_id: string; error?: string; player_id?: string }[] }>("scan", { schema_version: 1, players: [H, X, U].map(objectId) },
      { PLAYERS: throwing(env.PLAYERS, "campaignDrainInventory", args => String(args[0]) === broken) });
    expect(scan.players.map(p => p.error ?? p.player_id)).toEqual([H, "unreadable", U]);
    const counted = await drain<Count>("count", { schema_version: 1, anchors: [R] }, { ROOMS_V2: throwing(env.ROOMS_V2, "campaignDrainCensus", args => args[0] === w.targetId) });
    expect(counted.anchors[0].children.map(c => c.kind)).toEqual(["unreadable"]);
    expect(counted.totals).toMatchObject({ campaign_rooms: 1, unreadable_rooms: 1 });
    const erased = await drain<Erase>("erase", { schema_version: 1, anchor: R, players: [H, G, X] }, { PLAYERS: throwing(env.PLAYERS, "operatorCampaignTerminalScope", args => args[0] === G) });
    expect(erased.players).toEqual([{ player_id: H, result: "released" }, { player_id: G, result: "player_unavailable" }, { player_id: X, result: "released" }]);
    expect((await erase()).players).toEqual([{ player_id: H, result: "no_link" }, { player_id: G, result: "released" }, { player_id: X, result: "no_link" }]);
  });

  it("answers the drain's reads on objects nobody wrote as empty objects do, and stores nothing", async () => {
    const tables = (stub: DurableObjectStub) => openRaw(stub, async (_, ctx) => ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE '_cf_%'").toArray().length);
    const answer = async (work: () => Promise<unknown>) => { try { return await work(); } catch (error) { return { threw: String(error) }; } };
    type Read<S> = [string, (stub: S, id: string) => Promise<unknown>];
    const rooms: Read<DurableObjectStub<import("../src/v2/room").RoomV2>>[] = [["campaignDrainCensus", (room, id) => room.campaignDrainCensus(id)]];
    const players: Read<DurableObjectStub<import("../src/player").Player>>[] = [
      ["campaignDrainInventory", player => player.campaignDrainInventory()], ["operatorCampaignAllocation", player => player.operatorCampaignAllocation(R)],
      ["operatorCampaignTerminalScope", player => player.operatorCampaignTerminalScope(R)],
      ["operatorFinalizeCampaignTerminalLink", player => player.operatorFinalizeCampaignTerminalLink({}, { schema_version: 1, status: "deleted", campaign_room_id: R, room_id: R })]];
    // Each read on a blank object, against the same read on an object whose tables exist but hold no rows.
    async function compare<S extends DurableObjectStub>(namespace: { getByName(id: string): S }, reads: Read<S>[]) {
      for (const [name, read] of reads) {
        const blankId = randomToken(16), emptyId = randomToken(16), empty = namespace.getByName(emptyId);
        await runInDurableObject(empty as DurableObjectStub<Rpc.DurableObjectBranded>, () => undefined);
        const expected = await answer(() => read(empty, emptyId));
        const blank = await meterAllRows(() => answer(() => read(namespace.getByName(blankId), blankId)));
        expect({ name, answer: blank.value, written: blank.rows.written }).toEqual({ name, answer: expected, written: 0 });
        expect(await tables(namespace.getByName(blankId))).toBe(0);
      }
    }
    await compare(env.ROOMS_V2, rooms);
    await compare(env.PLAYERS, players);

    // Through the route: a count of a root nobody created, and a scan and an erase naming players with no data.
    const ghostRoom = randomToken(16), ghostPlayer = "Ghost_player_no_data_1";
    const counted = await meterAllRows(() => drain<Count>("count", { schema_version: 1, anchors: [ghostRoom] }));
    expect({ kind: counted.value.anchors[0].root.kind, written: counted.rows.written }).toEqual({ kind: "absent", written: 0 });
    expect(await tables(env.ROOMS_V2.getByName(ghostRoom))).toBe(0);
    const scanned = await meterAllRows(() => drain<{ players: { player_id: string | null }[] }>("scan", { schema_version: 1, players: [objectId(ghostPlayer)] }));
    expect({ id: scanned.value.players[0].player_id, written: scanned.rows.written }).toEqual({ id: null, written: 0 });
    const w = await world();
    const erased = await drain<Erase>("erase", { schema_version: 1, anchor: R, players: [H, ghostPlayer] });
    expect(erased.players).toEqual([{ player_id: H, result: "released" }, { player_id: ghostPlayer, result: "identity_absent" }]);
    expect(await tables(env.PLAYERS.getByName(ghostPlayer))).toBe(0);
    void w;
  });

  it("costs a bounded number of Durable Object requests and rows per batch", async () => {
    const w = await world(), written = await meter(everyObject(w)), meterBy = counted();
    await drain("scan", { schema_version: 1, players: [H, G, X, U].map(objectId) }, meterBy.env);
    expect(meterBy.calls).toEqual(Array(4).fill("Player.campaignDrainInventory"));
    meterBy.calls.length = 0;
    const counts = await drain<Count>("count", { schema_version: 1, anchors: [R] }, meterBy.env);
    expect(meterBy.calls).toEqual(["RoomV2.campaignDrainCensus", "RoomV2.campaignDrainCensus"]);
    expect(written()).toBe(0);
    meterBy.calls.length = 0;
    await drain("erase", { schema_version: 1, anchor: R, players: [H, G, X] }, meterBy.env);
    // The root's cascade adds one request per chapter room from inside the root.
    expect(meterBy.calls).toEqual(["RoomV2.campaignDrainCensus", "RoomV2.eraseCampaignRoot", "RoomV2.campaignTerminalFact",
      ...[H, G, X].flatMap(() => ["Player.operatorCampaignTerminalScope", "Player.operatorFinalizeCampaignTerminalLink"]), "RoomV2.campaignDrainCensus"]);
    // Deleting a row counts as writing it. On top of the 22 counted rows: the root's deleting mark (anchor, member) and
    // completed child (1), the tombstone marks (root 3, child 2), three link removals and two Join intents closed.
    expect(counts.totals.total_rows).toBe(22);
    expect(written()).toBe(22 + 13);
  });
});
