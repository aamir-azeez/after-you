import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { openCostly, withConfig } from "./config";
import { countingEnv, meterAllRows, meterRows } from "./meter";
import { MAX_FRIENDS, MAX_INCOMING_REQUESTS } from "../src/friends";
import { FRIEND_DECLINE_MS } from "../src/friend-declines";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Link = { player_id: string; request_id: string; status: "incoming" | "outgoing" | "accepted" };
type List = { friends: Link[] };
let address = 0;
// Friend requests are in the costly class; these tests are about the lists, so its bucket always allows.
const OPEN = openCostly(env);
async function call(path: string, method = "GET", a?: Account, body?: unknown, overrides: Partial<Env> = {}) {
  return worker.fetch(new Request("https://friend-guards.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.11." + (++address % 250), ...(a ? { "X-Player-Id": a.player_id, Authorization: "Bearer " + a.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), withConfig({ ...env, ...OPEN, ...overrides }));
}
async function create(): Promise<Account> { const r = await call("/v1/identity", "POST", undefined, {}); expect(r.status).toBe(201); return r.json<Account>(); }
const request = (a: Account, b: Account) => call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: b.player_id });
const remove = (a: Account, b: Account, id: string) => call("/v1/friends/" + b.player_id, "DELETE", a, { schema_version: 1, request_id: id });
const list = async (a: Account) => {
  // The list has its own 30 second floor; tests read it as a fresh phone would after it.
  await runInDurableObject(env.PLAYERS.getByName(a.player_id), async (_, ctx) => {
    const row = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one(), identity = JSON.parse(row.data);
    if (identity.social) { identity.social.next_refresh_at = 0; ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity)); }
  });
  const r = await call("/v1/friends", "GET", a); expect(r.status).toBe(200); return (await r.json<List>()).friends;
};
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("incoming requests never fill a list", () => {
  it("keeps at most MAX_INCOMING_REQUESTS pending incoming requests, pushing out the oldest and clearing it on its sender's side", async () => {
    const victim = await create(), senders: Account[] = [];
    for (let i = 0; i <= MAX_INCOMING_REQUESTS; i++) { const s = await create(); senders.push(s); expect((await request(s, victim)).status).toBe(200); }
    const incoming = (await list(victim)).filter(row => row.status === "incoming").map(row => row.player_id);
    expect(incoming.length).toBe(MAX_INCOMING_REQUESTS);
    expect(incoming).not.toContain(senders[0].player_id);
    expect(incoming).toContain(senders[MAX_INCOMING_REQUESTS].player_id);
    // The pushed-out sender keeps no hidden slot.
    expect(await env.PLAYERS.getByName(senders[0].player_id).friendEdge(senders[0].player_id, victim.player_id)).toBeNull();
    // The victim can still add friends of their own.
    const friend = await create();
    expect((await request(victim, friend)).status).toBe(200);
  });

  it("never pushes out a friend or an outgoing request: a list of those still answers friend_list_full", async () => {
    const owner = await create();
    for (let i = 0; i < MAX_FRIENDS; i++) expect((await request(owner, await create())).status).toBe(200);
    const stranger = await create(), refused = await request(stranger, owner);
    expect(refused.status).toBe(409);
    expect((await refused.json<{ error: { code: string } }>()).error.code).toBe("friend_list_full");
  });
});

describe("an Add into a full list", () => {
  it("takes the place of the oldest pending incoming request, so strangers never stop a player adding", async () => {
    const owner = await create(), strangers: Account[] = [];
    for (let i = 0; i < MAX_INCOMING_REQUESTS; i++) { const s = await create(); strangers.push(s); expect((await request(s, owner)).status).toBe(200); }
    for (let i = 0; i < MAX_FRIENDS - MAX_INCOMING_REQUESTS; i++) expect((await request(owner, await create())).status).toBe(200);
    expect((await request(owner, await create())).status).toBe(200);
    expect(await env.PLAYERS.getByName(owner.player_id).friendEdge(owner.player_id, strangers[0].player_id)).toBeNull();
    expect(await env.PLAYERS.getByName(strangers[0].player_id).friendEdge(strangers[0].player_id, owner.player_id)).toBeNull();
    // An Add the other side refuses (its own list full of friends and outgoing requests) loses nobody's request.
    const full = await create();
    for (let i = 0; i < MAX_FRIENDS; i++) expect((await request(full, await create())).status).toBe(200);
    const kept = strangers[1];
    expect((await request(owner, full)).status).toBe(409);
    expect(await env.PLAYERS.getByName(owner.player_id).friendEdge(owner.player_id, kept.player_id)).not.toBeNull();
    expect(await env.PLAYERS.getByName(kept.player_id).friendEdge(kept.player_id, owner.player_id)).not.toBeNull();
  }, 60_000);
});

describe("repeats write nothing", () => {
  it("an unchanged share and a repeated accept leave both lists and their refresh floors alone", async () => {
    const a = await create(), b = await create();
    const sent = await (await request(a, b)).json<Link>();
    const accept = () => call("/v1/friends/accept", "POST", b, { schema_version: 1, player_id: a.player_id, request_id: sent.request_id });
    expect((await accept()).status).toBe(200);
    const stubs = { a: env.PLAYERS.getByName(a.player_id) as unknown as DurableObjectStub, b: env.PLAYERS.getByName(b.player_id) as unknown as DurableObjectStub };
    const again = await meterRows(stubs, accept);
    expect(again.value.status).toBe(200); expect(again.rows.a.written).toBe(0); expect(again.rows.b.written).toBe(0);
    const room = await (await call("/v1/rooms", "POST", a, { idempotency_key: crypto.randomUUID() })).json<{ room_id: string }>();
    const share = () => call("/v1/friends/share", "POST", a, { schema_version: 1, room: { api_version: 1, room_id: room.room_id } });
    expect((await share()).status).toBe(200);
    const same = await meterRows(stubs, share, /identity/);
    expect(same.value.status).toBe(200); expect(same.rows.a.written).toBe(0);
  });
});

describe("a declined request", () => {
  it("bars the same sender for seven days, and the decliner's own Add clears it", async () => {
    const a = await create(), b = await create();
    const sent = await (await request(a, b)).json<Link>();
    expect((await remove(b, a, sent.request_id)).status).toBe(200);
    const again = await request(a, b);
    expect(again.status).toBe(404);
    expect((await again.json<{ error: { code: string } }>()).error.code).toBe("friend_unavailable");
    // The refused sender keeps no half request.
    expect(await env.PLAYERS.getByName(a.player_id).friendEdge(a.player_id, b.player_id)).toBeNull();
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + FRIEND_DECLINE_MS + 1000);
    expect((await request(a, b)).status).toBe(200);
  });

  it("does not bar anyone after a cancelled outgoing request or a removed friend, and Add from the decliner works at once", async () => {
    const a = await create(), b = await create();
    const sent = await (await request(a, b)).json<Link>();
    expect((await remove(b, a, sent.request_id)).status).toBe(200);
    const added = await (await request(b, a)).json<Link>();
    expect(added.status).toBe("outgoing");
    // b cancels their own request: a is not barred from asking b.
    expect((await remove(b, a, added.request_id)).status).toBe(200);
    expect((await request(a, b)).status).toBe(200);
  });
});

describe("a removal of nothing", () => {
  it("writes no row anywhere and opens no stored object, for any player id", async () => {
    const a = await create(), b = await create(), stranger = "Q".repeat(22);
    for (const peer of [b.player_id, stranger]) {
      const { value, rows } = await meterAllRows(() => call("/v1/friends/" + peer, "DELETE", a, { schema_version: 1, request_id: "r".repeat(22) }));
      expect(value.status).toBe(200);
      expect(rows.written).toBe(0);
    }
    const counted = countingEnv(withConfig({ ...env, ...OPEN }));
    await worker.fetch(new Request("https://friend-guards.test/v1/friends/" + b.player_id, { method: "DELETE", headers: { "Content-Type": "application/json", "X-Player-Id": a.player_id, Authorization: "Bearer " + a.device_token, "CF-Connecting-IP": "198.18.12.1" },
      body: JSON.stringify({ schema_version: 1, request_id: "r".repeat(22) }) }), counted.env);
    // auth, own forget, the peer's forget; no friend event revokes.
    expect(counted.calls).toEqual(["PLAYERS.authorize", "PLAYERS.friendForget", "PLAYERS.friendForget"]);
  });

  it("stores nothing for a request to an id nobody has, not even the block check's profile", async () => {
    const a = await create();
    const { value, rows } = await meterAllRows(() => request(a, { player_id: "W".repeat(22), device_token: "", recovery_code: "" }));
    expect(value.status).toBe(404); expect(rows.written).toBe(0);
  });

  it("leaves the friends list's refresh floor alone, as does Add on an existing request", async () => {
    const a = await create(), b = await create();
    await request(a, b); await list(a);
    expect((await call("/v1/friends", "GET", a)).status).toBe(429);
    expect((await remove(a, await create(), "r".repeat(22))).status).toBe(200);
    expect((await request(a, b)).status).toBe(200);
    expect((await call("/v1/friends", "GET", a)).status).toBe(429);
  });
});

describe("block from Friends", () => {
  it("blocks a request's sender by its row with no shared room, and takes the row off both lists", async () => {
    const a = await create(), b = await create();
    const sent = await (await request(a, b)).json<Link>();
    const blocked = await call("/v1/safety/blocks/" + a.player_id, "POST", b, { schema_version: 1, request_id: sent.request_id });
    expect(blocked.status).toBe(200);
    expect(await blocked.json()).toEqual({ schema_version: 1, blocked: true, player_id: a.player_id });
    expect(await list(b)).toEqual([]);
    expect(await env.PLAYERS.getByName(a.player_id).friendEdge(a.player_id, b.player_id)).toBeNull();
    expect((await (await call("/v1/safety/blocks", "GET", b)).json<{ blocked_players: string[] }>()).blocked_players).toEqual([a.player_id]);
    const again = await request(a, b);
    expect(again.status).toBe(403);
  });

  it("refuses a player who is not on the caller's list, or a stale row, without blocking", async () => {
    const a = await create(), b = await create(), stranger = await create();
    const sent = await (await request(a, b)).json<Link>();
    for (const [peer, id] of [[stranger.player_id, sent.request_id], [a.player_id, "s".repeat(22)]]) {
      const r = await call("/v1/safety/blocks/" + peer, "POST", b, { schema_version: 1, request_id: id });
      expect(r.status).toBe(404);
      expect((await r.json<{ error: { code: string } }>()).error.code).toBe("friend_unavailable");
    }
    expect((await (await call("/v1/safety/blocks", "GET", b)).json<{ blocked_players: string[] }>()).blocked_players).toEqual([]);
    expect((await call("/v1/safety/blocks/" + a.player_id, "POST", b, { schema_version: 1 })).status).toBe(400);
  });
});
