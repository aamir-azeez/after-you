import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { digest, randomToken, type Outcome } from "../src/protocol";
import { FRIEND_REFRESH_SECONDS } from "../src/friends";
import { FRIEND_ALIAS_HEADER } from "../src/friend-aliases";
import { MAX_FRIEND_ALIASES, aliasesFrom } from "../src/config";

type Account = { player_id: string; device_token: string; recovery_code: string };
let address = 0;
const value = <T>(r: Outcome<T>): T => { if (!r.ok) throw new Error(r.code); return r.value; };
/** `aliases` is the JSON text of CONFIG's friend_aliases, written into CONFIG as it is, so a malformed one makes CONFIG malformed. */
async function call(path: string, method: string, a: Account | undefined, body: unknown, aliases?: string, headers: Record<string, string> = {}) {
  const config: Record<string, unknown> = aliases === undefined ? {} : { CONFIG: `{"friend_aliases":${aliases}}` };
  return worker.fetch(new Request("https://aliases.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.9." + ++address, ...(a ? { "X-Player-Id": a.player_id, Authorization: "Bearer " + a.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), Object.assign({}, env, config));
}
async function create(): Promise<Account> { const r = await call("/v1/identity", "POST", undefined, {}); expect(r.status).toBe(201); return r.json<Account>(); }
const request = (a: Account, code: unknown, aliases?: string) => call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: code }, aliases);
const profile = (a: Account, aliases?: string, optIn = false) => call("/v1/friends", "GET", a, undefined, aliases, optIn ? { [FRIEND_ALIAS_HEADER]: "2" } : {});
const reply = async (r: Response) => ({ status: r.status, body: await r.text() });
const unknownId = () => randomToken(16);
const later = () => vi.spyOn(Date, "now").mockReturnValue(Date.now() + (FRIEND_REFRESH_SECONDS + 1) * 1000);

afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("owner-reserved friend aliases", () => {
  it("parses only a small strict alias map and fails closed otherwise", () => {
    const id = randomToken(16), other = randomToken(16);
    const parseFriendAliases = (raw: string | undefined) => { try { return aliasesFrom(JSON.parse(raw ?? "")) ?? { byAlias: new Map() }; } catch { return { byAlias: new Map() }; } };
    expect([...aliasesFrom({ aamir: id, b0b: other })!.byAlias]).toEqual([["aamir", id], ["b0b", other]]);
    expect(aliasesFrom({ aamir: id })!.byId.get(id)).toBe("aamir");
    const many = Object.fromEntries(Array.from({ length: MAX_FRIEND_ALIASES + 1 }, (_, i) => ["alias" + i, randomToken(16)]));
    for (const raw of [undefined, "", "{", "null", "[]", "\"aamir\"", "42", JSON.stringify(many),
      JSON.stringify({ Aamir: id }), JSON.stringify({ aa: id }), JSON.stringify({ "1aamir": id }), JSON.stringify({ a_mir: id }), JSON.stringify({ aamiraamiraamir12: id }),
      JSON.stringify({ aamir: id.slice(1) }), JSON.stringify({ aamir: 7 }), JSON.stringify({ aamir: id, again: id }), JSON.stringify({ aamir: id, __proto__x: other })]) {
      expect(parseFriendAliases(raw).byAlias.size).toBe(0);
    }
    expect(aliasesFrom(Object.fromEntries(Object.entries(many).slice(0, MAX_FRIEND_ALIASES)))!.byAlias.size).toBe(MAX_FRIEND_ALIASES);
  });

  it("resolves an alias case-insensitively and then runs the unchanged request path", async () => {
    const a = await create(), b = await create(), aliases = JSON.stringify({ bfriend: b.player_id });
    const sent = await request(a, "BFriend", aliases); expect(sent.status).toBe(200);
    const link = await sent.json<{ player_id: string; request_id: string; status: string }>();
    expect(link).toMatchObject({ schema_version: 1, player_id: b.player_id, status: "outgoing" });
    // Sending again by id or by alias reaches the same pending request.
    expect(await (await request(a, b.player_id, aliases)).json()).toEqual(link);
    expect(await (await request(a, "bfriend", aliases)).json()).toEqual(link);
    // The aliased player accepts by id as usual.
    const accepted = await call("/v1/friends/accept", "POST", b, { schema_version: 1, player_id: a.player_id, request_id: link.request_id }, aliases);
    expect(accepted.status).toBe(200); expect((await accepted.json<{ status: string }>()).status).toBe("accepted");
  });

  it("answers an unknown alias exactly like an unknown id and keeps other errors", async () => {
    const a = await create(), b = await create(), aliases = JSON.stringify({ bfriend: b.player_id });
    const missingId = await reply(await request(a, unknownId(), aliases));
    expect(missingId.status).toBe(404);
    for (const code of ["nobody", "constructor", "toString", "hasOwnProperty"]) expect(await reply(await request(a, code, aliases))).toEqual(missingId);
    // Aliases stay off without CONFIG and when it is malformed, while ids keep working.
    for (const config of [undefined, "{}", "not json", JSON.stringify({ bfriend: b.player_id, Bad: a.player_id })]) {
      expect(await reply(await request(a, "bfriend", config))).toEqual(missingId);
    }
    const garbage = await reply(await request(a, "a!b"));
    expect(garbage.status).toBe(400); expect(garbage.body).toContain("invalid_friend_code");
    for (const code of ["ab", "1abc", "friend-bfriend", "x".repeat(17), 12, null]) expect(await reply(await request(a, code, aliases))).toEqual(garbage);
    // Self by alias is the same refusal as self by id.
    const self = JSON.stringify({ myself: a.player_id });
    expect(await reply(await request(a, "myself", self))).toEqual(await reply(await request(a, a.player_id, self)));
  });

  it("keeps blocks in force for a request by alias", async () => {
    const a = await create(), b = await create(), aliases = JSON.stringify({ afriend: a.player_id });
    value(await env.SAFETY_PROFILES.getByName(a.player_id).setBlock(a.player_id, await digest(a.device_token), b.player_id, true));
    const byId = await reply(await request(b, a.player_id, aliases));
    expect(byId.status).toBe(403);
    expect(await reply(await request(b, "afriend", aliases))).toEqual(byId);
  });

  it("adds friend_alias only for an aliased owner whose client asks for it", async () => {
    const a = await create(), b = await create(), aliases = JSON.stringify({ aamir: a.player_id });
    const plain = (owner: Account) => JSON.stringify({ schema_version: 1, friend_code: owner.player_id, refresh_after_seconds: FRIEND_REFRESH_SECONDS, shared_room: null, friends: [] });
    // Without the header the aliased owner's profile is byte-identical to the old five keys.
    expect(await reply(await profile(a, aliases))).toEqual({ status: 200, body: plain(a) });
    const clock = later();
    const asked = await profile(a, aliases, true); expect(asked.status).toBe(200);
    expect(await asked.text()).toBe(JSON.stringify({ schema_version: 1, friend_code: a.player_id, friend_alias: "aamir", refresh_after_seconds: FRIEND_REFRESH_SECONDS, shared_room: null, friends: [] }));
    clock.mockRestore();
    // Everyone else gets the old body even when asking, and an invalid var adds nothing.
    expect(await reply(await profile(b, aliases, true))).toEqual({ status: 200, body: plain(b) });
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 2 * (FRIEND_REFRESH_SECONDS + 1) * 1000);
    expect(await reply(await profile(a, "{\"aamir\":1}", true))).toEqual({ status: 200, body: plain(a) });
  });
});
