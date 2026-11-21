import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { DISPLAY_NAMES_HEADER } from "../src/display-names";
import { CLAIM_GRACE_MS, USERNAMES_HEADER, USERNAME_HOLD_MS, USERNAME_SHARDS, usernameProblem, usernameShard, validUsernameFields } from "../src/usernames";
import { NAME_CHANGE_PRICE, nextUsernamePrice } from "../src/pollen/name-price";
import { noteFullJourney } from "../src/pollen/wallet";
import { withConfig } from "./config";
import { countingEnv, meterRows } from "./meter";
import vectors from "../../game/tests/fixtures/display_names/username_vectors.json";

// Synthetic identities only: every account here is made by POST /v1/identity in the test runtime.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Row = { player_id: string; status: string; display_name?: string | null; username?: string | null; request_id: string };
type Page = { friends: Row[]; username?: string | null; display_name?: string | null };
const ON = { DISPLAY_NAMES_ENABLED: "true", USERNAMES_ENABLED: "true" };
const SECRET = "synthetic-pollen-secret-for-tests-only-0002";
const SHOP = { ...ON, features: ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"], POLLEN_SECRET: SECRET };
const ASK = { [USERNAMES_HEADER]: "1", [DISPLAY_NAMES_HEADER]: "1" };
const OPERATOR = "o".repeat(43);
const DAY = 86_400_000;
let address = 0;

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, unknown> = ON, headers: Record<string, string> = ASK, base: Env = env): Promise<Response> {
  const { CONFIG: _objects, ...rest } = base as Env & { CONFIG?: string };
  const configured = withConfig(Object.assign(rest, { SAFETY_OPERATOR_TOKEN: OPERATOR, ...vars })) as Env;
  return worker.fetch(new Request("https://usernames.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.81." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function create(): Promise<Account> { const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201); return made.json<Account>(); }
const claim = (account: Account, username: string, vars: Record<string, unknown> = ON, price?: number) =>
  call("/v1/profile/username", "PUT", account, { schema_version: 1, username, ...(price !== undefined ? { pollen_price: price } : {}) }, vars);
const view = async (account: Account, vars: Record<string, unknown> = ON) => (await call("/v1/profile/username", "GET", account, undefined, vars)).json<{ username: string | null; suggestion?: string; pollen_price?: number; pollen_price_next?: number }>();
const code = async (response: Response) => ({ status: response.status, code: (await response.json<{ error?: { code: string } }>()).error?.code });
const addFriend = (account: Account, friend_code: string, headers: Record<string, string> = ASK) => call("/v1/friends/request", "POST", account, { schema_version: 1, friend_code }, ON, headers);
const friends = async (account: Account, headers: Record<string, string> = ASK) => { advance(31_000); return (await call("/v1/friends", "GET", account, undefined, ON, headers)).json<Page>(); };
const identityOf = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) =>
  JSON.parse(String(state.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data)) as Record<string, unknown>);

const realNow = Date.now.bind(Date);
let offset = 0;
const advance = (ms: number) => { offset += ms; };
beforeEach(() => { offset = 0; vi.spyOn(Date, "now").mockImplementation(() => realNow() + offset); (env as unknown as Record<string, unknown>).POLLEN_SECRET = SECRET; });
afterEach(async () => { delete (env as unknown as Record<string, unknown>).POLLEN_SECRET; vi.restoreAllMocks(); await reset(); });

describe("username rules", () => {
  it("answers every shared vector as the game does", () => {
    for (const [name, answer] of vectors.cases as [string, string][]) expect([name, usernameProblem(name) ?? "ok"]).toEqual([name, answer]);
  });
  it("pins the shard count and hash, which must never change once live", () => {
    expect(USERNAME_SHARDS).toBe(32);
    expect(["thebluebeanie", "abc", "aamir", "zz9"].map(usernameShard)).toEqual(["shard-28", "shard-11", "shard-21", "shard-4"]);
  });
  it("checks stored fields by shape", () => {
    expect(validUsernameFields({ username: "Blue.Bean", username_held: [{ key: "old_one", until: 5 }], username_sets: 2, username_changes: [1] })).toBe(true);
    expect(validUsernameFields({ username: "a" })).toBe(false);
    expect(validUsernameFields({ username_held: [{ key: "Old_One", until: 5 }] })).toBe(false);
  });
});

describe("usernames", () => {
  it("are absent while off: 503, no capability field and friends replies as before", async () => {
    const player = await create();
    expect(await code(await claim(player, "bluebean", { DISPLAY_NAMES_ENABLED: "true" }))).toEqual({ status: 503, code: "usernames_disabled" });
    expect(await code(await claim(player, "bluebean", { USERNAMES_ENABLED: "true" }))).toEqual({ status: 503, code: "usernames_disabled" });
    const caps = await (await call("/v2/capabilities", "GET", player)).json<Record<string, unknown>>();
    expect(caps.usernames_version).toBe(1);
    const off = await (await call("/v2/capabilities", "GET", player, undefined, ON, { [DISPLAY_NAMES_HEADER]: "1" })).json<Record<string, unknown>>();
    expect(off).not.toHaveProperty("usernames_version");
  });

  it("are unique without capitals, keep the capitals shown, and cost one index request on top of the Player write", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    const shard = env.USERNAMES.getByName(usernameShard("thebluebeanie"));
    const meter = countingEnv(env);
    const { value: response, rows } = await meterRows({ shard }, () => call("/v1/profile/username", "PUT", a, { schema_version: 1, username: "TheBlueBeanie" }, ON, ASK, meter.env));
    expect(await response.json()).toEqual({ schema_version: 1, username: "TheBlueBeanie" });
    // The Worker makes the usual auth call and the change; the Player asks the index once (one row written).
    expect(meter.calls).toEqual(["PLAYERS.authorize", "PLAYERS.claimUsername"]);
    expect(rows.shard).toEqual({ read: 0, written: 1 });
    expect(await code(await claim(b, "thebluebeanie"))).toEqual({ status: 409, code: "username_taken" });
    expect(await view(a)).toEqual({ schema_version: 1, username: "TheBlueBeanie" });
    // The display name follows, so rooms, boards and older apps show it.
    expect((await identityOf(a)).display_name).toBe("TheBlueBeanie");
    // A repeat answers the same and changes nothing; capitals alone change it without the index and are not counted.
    expect(await claim(a, "TheBlueBeanie").then(r => r.status)).toBe(200);
    const recase = await meterRows({ shard }, () => claim(a, "theBlueBeanie"));
    expect(recase.value.status).toBe(200); expect(recase.rows.shard).toEqual({ read: 0, written: 0 });
    expect((await identityOf(a)).username_sets).toBe(1);
  });

  it("let exactly one of two players claiming the same name at once have it", async () => {
    const players = await Promise.all([create(), create(), create(), create()]);
    const answers = await Promise.all(players.map(player => claim(player, "Twin.Name").then(r => r.status)));
    expect(answers.filter(status => status === 200)).toHaveLength(1);
    expect(answers.filter(status => status === 409)).toHaveLength(3);
  });

  it("refuse bad, blocked and reserved names, and keep a friend alias for its own player", async () => {
    const [owner, other, third] = await Promise.all([create(), create(), create()]);
    const aliased = { ...ON, friend_aliases: { maple: third.player_id, aamir: owner.player_id } };
    expect(await code(await claim(other, "ab"))).toEqual({ status: 400, code: "invalid_username" });
    expect(await code(await claim(other, "blue..bean"))).toEqual({ status: 400, code: "invalid_username" });
    expect(await code(await claim(other, "BigNazi"))).toEqual({ status: 422, code: "username_refused" });
    expect(await code(await claim(other, "Admin_2"))).toEqual({ status: 422, code: "username_reserved" });
    expect(await code(await claim(other, "friend-abc"))).toEqual({ status: 422, code: "username_reserved" });
    expect(await code(await claim(other, "maple", aliased))).toEqual({ status: 409, code: "username_taken" });
    expect(await code(await claim(other, "aamir", aliased))).toEqual({ status: 409, code: "username_taken" });
    expect(await code(await claim(other, "aamir"))).toEqual({ status: 422, code: "username_reserved" });
    expect((await claim(owner, "aamir", aliased)).status).toBe(200);
  });

  it("hold an old name for its player for 30 days, then let someone else take it", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    expect((await claim(a, "first.name")).status).toBe(200);
    expect((await claim(a, "second.name")).status).toBe(200);
    expect(await code(await claim(b, "first.name"))).toEqual({ status: 409, code: "username_taken" });
    // Past the grace window the holder's Player is asked; it still holds the old name.
    advance(CLAIM_GRACE_MS + 1000);
    expect(await code(await claim(b, "First.Name"))).toEqual({ status: 409, code: "username_taken" });
    // An old link keeps finding them while it is held.
    expect((await addFriend(b, "first.name")).status).toBe(200);
    advance(USERNAME_HOLD_MS);
    expect(await claim(b, "First.Name").then(r => r.status)).toBe(200);
    expect(await code(await claim(a, "first.name"))).toEqual({ status: 409, code: "username_taken" });
  });

  it("let a player take back their own held name, and refuse a sixth change in a day", async () => {
    const a = await create();
    for (const name of ["name.one", "name.two", "name.one", "name.three", "name.four"]) expect([name, (await claim(a, name)).status]).toEqual([name, 200]);
    const limited = await claim(a, "name.five");
    expect(limited.status).toBe(429);
    expect((await limited.json<{ error: { code: string; retry_after_seconds: number } }>()).error).toMatchObject({ code: "username_limited" });
    advance(DAY);
    expect((await claim(a, "name.five")).status).toBe(200);
  });

  it("price changes while the shop is on: two free, then Pollen once even when the request is sent again", async () => {
    const a = await create();
    await runInDurableObject(env.PLAYERS.getByName(a.player_id), async (_, state) => {
      noteFullJourney(state.storage, Date.now() + DAY, Date.now());
      state.storage.sql.exec("UPDATE pollen_wallet SET data=json_set(data,'$.balance',?,'$.earned',?) WHERE id=1", 1800, 1800);
    });
    expect(await view(a, SHOP)).toMatchObject({ username: null, pollen_price: 0, pollen_price_next: 0 });
    expect((await claim(a, "cost.one", SHOP, 0)).status).toBe(200);
    expect((await claim(a, "cost.two", SHOP, 0)).status).toBe(200);
    expect(await view(a, SHOP)).toMatchObject({ pollen_price: NAME_CHANGE_PRICE, pollen_price_next: NAME_CHANGE_PRICE });
    expect(await code(await claim(a, "cost.three", SHOP))).toEqual({ status: 409, code: "name_change_price" });
    expect(await code(await claim(a, "cost.three", SHOP, 0))).toEqual({ status: 409, code: "name_change_price" });
    // The refused claims let the name go again at once.
    const b = await create();
    expect((await claim(b, "cost.three")).status).toBe(200);
    expect((await claim(a, "cost.four", SHOP, NAME_CHANGE_PRICE)).status).toBe(200);
    expect((await claim(a, "cost.four", SHOP, NAME_CHANGE_PRICE)).status).toBe(200);
    // Capitals alone stay free.
    expect((await claim(a, "Cost.Four", SHOP, 0)).status).toBe(200);
    const balance = await runInDurableObject(env.PLAYERS.getByName(a.player_id), async (_, state) =>
      Number(state.storage.sql.exec<{ b: number }>("SELECT json_extract(data,'$.balance') AS b FROM pollen_wallet WHERE id=1").one().b));
    expect(balance).toBe(1800 - NAME_CHANGE_PRICE);
    expect(await code(await claim(a, "cost.five", SHOP, NAME_CHANGE_PRICE))).toEqual({ status: 402, code: "pollen_short" });
  });

  it("make the first username free whatever display names the player had", () => {
    expect(nextUsernamePrice({}, 0)).toBe(0);
    expect(nextUsernamePrice({ username_sets: 1 }, 0)).toBe(0);
    expect(nextUsernamePrice({ username_sets: 2 }, 0)).toBe(NAME_CHANGE_PRICE);
    expect(nextUsernamePrice({ username_sets: 2, display_name_locked_until: 5 }, 10)).toBe(0);
  });

  it("suggest the display name when it passes the rules and nobody has it", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    expect((await call("/v1/profile/name", "PUT", a, { schema_version: 1, display_name: "Maple.Leaf", revision: 1 })).status).toBe(200);
    expect(await view(a)).toEqual({ schema_version: 1, username: null, suggestion: "Maple.Leaf" });
    expect((await claim(b, "maple.leaf")).status).toBe(200);
    expect(await view(a)).toEqual({ schema_version: 1, username: null });
    expect((await call("/v1/profile/name", "PUT", a, { schema_version: 1, display_name: "Two Words", revision: 2 })).status).toBe(200);
    expect(await view(a)).toEqual({ schema_version: 1, username: null });
  });

  it("refuse an older app's display name change while the player has a username", async () => {
    const a = await create();
    await runInDurableObject(env.PLAYERS.getByName(a.player_id), async instance => {
      const target = Reflect.get(instance, "env") as Record<string, unknown>;
      target.CONFIG = withConfig(ON).CONFIG;
    });
    expect((await claim(a, "Kept.Name")).status).toBe(200);
    expect(await code(await call("/v1/profile/name", "PUT", a, { schema_version: 1, display_name: "Other", revision: 1 }))).toEqual({ status: 403, code: "display_name_locked" });
    expect((await call("/v1/profile/name", "PUT", a, { schema_version: 1, display_name: "Kept.Name", revision: 2 })).status).toBe(200);
  });
});

describe("friend codes and the friends list", () => {
  it("add by username, show it on both sides of a request, and leave older replies unchanged", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    expect((await claim(a, "TheBlueBeanie")).status).toBe(200);
    expect((await claim(b, "Sprout_7")).status).toBe(200);
    expect(await (await addFriend(b, "THEBLUEBEANIE")).json()).toMatchObject({ status: "outgoing", player_id: a.player_id });
    const theirs = await friends(a);
    expect(theirs.username).toBe("TheBlueBeanie");
    expect(theirs.friends).toEqual([expect.objectContaining({ player_id: b.player_id, status: "incoming", username: "Sprout_7", display_name: null })]);
    const mine = await friends(b);
    expect(mine.friends).toEqual([expect.objectContaining({ player_id: a.player_id, status: "outgoing", username: "TheBlueBeanie" })]);
    // An app that does not ask gets the reply it always did.
    const older = await friends(a, { [DISPLAY_NAMES_HEADER]: "1" });
    expect(older).not.toHaveProperty("username");
    expect(Object.keys(older.friends[0]).sort()).toEqual(["display_name", "expires_after_seconds", "join_available", "online", "player_id", "request_id", "status"]);
  });

  it("let older apps add a letters-and-digits name through the short name path", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    expect((await claim(a, "Maple22")).status).toBe(200);
    expect((await addFriend(b, "maple22", {})).status).toBe(200);
  });

  it("answer an unknown or let-go name as an unknown code, and costs one index read", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    expect(await code(await addFriend(b, "nobody.here"))).toEqual({ status: 404, code: "friend_unavailable" });
    expect((await claim(a, "was.mine")).status).toBe(200);
    expect((await claim(a, "is.mine")).status).toBe(200);
    advance(USERNAME_HOLD_MS + 1000);
    const meter = countingEnv(env);
    const response = await call("/v1/friends/request", "POST", b, { schema_version: 1, friend_code: "was.mine" }, ON, ASK, meter.env);
    expect(await code(response)).toEqual({ status: 404, code: "friend_unavailable" });
    expect(meter.calls.filter(name => name.startsWith("USERNAMES."))).toEqual(["USERNAMES.lookup"]);
  });

  it("serve a username on the friend link page", async () => {
    const a = await create();
    expect((await claim(a, "Link.Name")).status).toBe(200);
    const page = await call("/v1/friend-link/link.name/name", "GET", undefined, undefined, ON, {});
    expect(await page.json()).toEqual({ schema_version: 1, display_name: "Link.Name" });
  });
});

describe("moderation and erasure", () => {
  it("a moderator clear takes the name away for good and locks new ones for the player", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    expect((await claim(a, "Bad.Name")).status).toBe(200);
    const cleared = await call(`/operator/safety/players/${a.player_id}/clear-name`, "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + OPERATOR });
    expect(cleared.status).toBe(200);
    expect(await view(a)).toEqual({ schema_version: 1, username: null });
    expect(await code(await claim(a, "good.name"))).toEqual({ status: 403, code: "username_locked" });
    advance(CLAIM_GRACE_MS + USERNAME_HOLD_MS);
    expect(await code(await claim(b, "bad.name"))).toEqual({ status: 409, code: "username_taken" });
    expect(await code(await addFriend(b, "bad.name"))).toEqual({ status: 404, code: "friend_unavailable" });
  });

  it("an erased account's names are free again", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    expect((await claim(a, "gone.soon")).status).toBe(200);
    expect((await call("/v1/identity", "DELETE", a)).status).toBeLessThan(300);
    await vi.waitFor(async () => expect(await env.USERNAMES.getByName(usernameShard("gone.soon")).lookup("gone.soon")).toBeNull(), { timeout: 5000 });
    expect((await claim(b, "gone.soon")).status).toBe(200);
  });
});
