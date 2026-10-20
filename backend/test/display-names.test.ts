import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, randomToken, type Outcome } from "../src/protocol";
import { FRIEND_REFRESH_SECONDS } from "../src/friends";
import { LIVE_PATH } from "../src/live";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import type { PortableSnapshot } from "../src/snapshot";
import { DISPLAY_NAMES_HEADER, FRIEND_LINK_MAX_AGE, FRIEND_LINK_ORIGIN, DISPLAY_NAME_LOCK_MS, DISPLAY_NAME_WINDOW_MS, MEMBER_NAMES, MAX_DISPLAY_NAME_CHANGES, blockedName, cleanDisplayName, shownName } from "../src/display-names";
import { countingEnv, meterRows } from "./meter";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

// Synthetic identities only: every account here is made by POST /v1/identity in the test runtime.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Row = Record<string, unknown> & { player_id: string; status: string; display_name?: string | null };
type Page = Record<string, unknown> & { friends: Row[]; display_name?: string | null };
type Entry = { room_id: string; membership: { host_id: string | null }; partner_name?: string | null };
const ON = { DISPLAY_NAMES_ENABLED: "true" }, OFF = { DISPLAY_NAMES_ENABLED: "false" }, ASK = { [DISPLAY_NAMES_HEADER]: "1" };
const OPERATOR = "o".repeat(43);
const key = () => crypto.randomUUID();
let address = 0;

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string | undefined> = ON, headers: Record<string, string> = {}, base: Env = env): Promise<Response> {
  const configured = Object.assign({ ...base }, { V2_ROOMS_ENABLED: "true", SAFETY_OPERATOR_TOKEN: OPERATOR, ...vars }) as Env;
  return worker.fetch(new Request("https://names.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.77." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
/** The same request through stubs that record every Durable Object call the Worker makes. */
async function counted(path: string, method: string, account: Account, body?: unknown, vars: Record<string, string> = ON, headers: Record<string, string> = {}): Promise<{ response: Response; calls: string[] }> {
  const meter = countingEnv({ ...env, V2_ROOMS_ENABLED: "true", ...vars } as unknown as Env);
  const response = await call(path, method, account, body, vars, headers, meter.env);
  return { response, calls: meter.calls };
}
const value = <T>(outcome: Outcome<T>): T => { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; };
const failure = async (response: Response) => ({ status: response.status, body: await response.json<{ error: Record<string, unknown> }>() });
async function create(): Promise<Account> { const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201); return made.json<Account>(); }
let revision = 0;
const setName = (account: Account, name: unknown, rev = ++revision, vars: Record<string, string> = ON) => call("/v1/profile/name", "PUT", account, { schema_version: 1, display_name: name, revision: rev }, vars);
async function named(name: string | null): Promise<Account> {
  const account = await create();
  if (name !== null) expect((await setName(account, name)).status).toBe(200);
  return account;
}

// A moving clock: the friends list refuses a second read within FRIEND_REFRESH_SECONDS, and limits run over a day.
const realNow = Date.now.bind(Date);
let offset = 0;
const advance = (ms: number) => { offset += ms; };
beforeEach(() => { offset = 0; vi.spyOn(Date, "now").mockImplementation(() => realNow() + offset); });

/** Objects read flags from their own env; tests set them there and put them back after. */
const changed = new Map<Record<string, unknown>, Record<string, unknown>>();
async function objectFlags(stub: DurableObjectStub, vars: Record<string, string>): Promise<void> {
  await runInDurableObject(stub, instance => {
    const target = Reflect.get(instance, "env") as Record<string, unknown>;
    const saved = changed.get(target) ?? {};
    for (const [name, setting] of Object.entries(vars)) { if (!Object.hasOwn(saved, name)) saved[name] = target[name]; target[name] = setting; }
    changed.set(target, saved);
  });
}
afterEach(async () => {
  for (const [target, saved] of changed) for (const [name, setting] of Object.entries(saved)) { if (setting === undefined) delete target[name]; else target[name] = setting; }
  changed.clear(); vi.restoreAllMocks(); await reset();
});

async function friends(account: Account, headers: Record<string, string> = ASK, vars: Record<string, string> = ON): Promise<Page> {
  advance((FRIEND_REFRESH_SECONDS + 1) * 1000);
  const page = await call("/v1/friends", "GET", account, undefined, vars, headers); expect(page.status).toBe(200);
  return page.json<Page>();
}
async function rawFriends(account: Account, headers: Record<string, string>, vars: Record<string, string> = ON): Promise<string> {
  advance((FRIEND_REFRESH_SECONDS + 1) * 1000);
  return (await call("/v1/friends", "GET", account, undefined, vars, headers)).text();
}
async function request(from: Account, to: Account): Promise<string> {
  const asked = await call("/v1/friends/request", "POST", from, { schema_version: 1, friend_code: to.player_id }); expect(asked.status).toBe(200);
  return (await asked.json<{ request_id: string }>()).request_id;
}
async function befriend(a: Account, b: Account): Promise<void> {
  const request_id = await request(a, b);
  expect((await call("/v1/friends/accept", "POST", b, { schema_version: 1, player_id: a.player_id, request_id })).status).toBe(200);
}

async function room(host: Account, guest: Account, vars: Record<string, string> = ON): Promise<RoomSnapshotV2> {
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH }, vars);
  expect(made.status).toBe(200);
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }, vars); expect(joined.status).toBe(200);
  return joined.json<RoomSnapshotV2>();
}
const turnBody = (current: RoomSnapshotV2, recording: unknown, checkpoint?: unknown) =>
  ({ base_revision: current.revision, branch: current.branch, idempotency_key: key(), recording, ...(checkpoint === undefined ? {} : { checkpoint }) });
async function turn(current: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown, vars: Record<string, string> = ON, headers: Record<string, string> = {}): Promise<MutationV2> {
  const sent = await call(`/v2/rooms/${current.room_id}/turns`, "POST", account, turnBody(current, recording, checkpoint), vars, headers);
  expect(sent.status).toBe(200); return sent.json<MutationV2>();
}
/** Relay to the end: the host plays t0-0-a and t0-1-b, the guest t0-0-b and t0-1-a. */
async function finish(start: RoomSnapshotV2, host: Account, guest: Account): Promise<RoomSnapshotV2> {
  let current = (await turn(start, host, firstA)).room;
  current = (await turn(current, guest, firstB, middle)).room;
  current = (await turn(current, guest, secondA)).room;
  current = (await turn(current, host, secondB, final)).room;
  expect(current.active_role).toBe("complete");
  return current;
}
const read = (roomId: string, account: Account, headers: Record<string, string> = ASK, vars: Record<string, string> = ON) => call(`/v2/rooms/${roomId}`, "GET", account, undefined, vars, headers);
async function inbox(account: Account, headers: Record<string, string> = ASK, vars: Record<string, string> = ON): Promise<Entry[]> {
  const answer = await call("/v1/room-inbox", "GET", account, undefined, vars, headers); expect(answer.status).toBe(200);
  return (await answer.json<{ rooms: Entry[] }>()).rooms;
}
const roomTable = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_, state) =>
  state.storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name=?", MEMBER_NAMES.name).toArray().length > 0);
const memberRows = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_, state) =>
  state.storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name=?", MEMBER_NAMES.name).toArray().length
    ? state.storage.sql.exec<{ player_id: string; display_name: string }>("SELECT player_id,display_name FROM member_names ORDER BY player_id").toArray() : []);
const identityOf = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
  const row = state.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").toArray()[0];
  return row ? JSON.parse(row.data) as Record<string, unknown> : null;
});
async function editIdentity(account: Account, change: (identity: Record<string, unknown>) => void): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    const identity = JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data) as Record<string, unknown>;
    change(identity); state.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
  });
}
const clearName = (player: string, token = OPERATOR, body: unknown = { schema_version: 1 }) =>
  worker.fetch(new Request(`https://names.test/operator/safety/players/${player}/clear-name`, { method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.78." + (++address % 250), Authorization: "Bearer " + token }, body: JSON.stringify(body) }),
  { ...env, SAFETY_OPERATOR_TOKEN: OPERATOR } as Env);
async function until(condition: () => Promise<boolean> | boolean, ms = 8000): Promise<void> {
  const end = realNow() + ms;
  while (!await condition()) { if (realNow() > end) throw new Error("timed out"); await new Promise(resolve => setTimeout(resolve, 10)); }
}

describe("display name rules", () => {
  it("compose to NFC, collapse spaces, trim and count code points", () => {
    expect(cleanDisplayName("Rene\u0301e")).toEqual({ ok: true, name: "Ren\u00e9e" });
    expect(cleanDisplayName("  Maya   Rose  ")).toEqual({ ok: true, name: "Maya Rose" });
    expect(cleanDisplayName("Maya\u00a0\u3000Rose")).toEqual({ ok: true, name: "Maya Rose" });
    expect(cleanDisplayName("a".repeat(18))).toEqual({ ok: true, name: "a".repeat(18) });
    expect(cleanDisplayName("a".repeat(19))).toEqual({ ok: false, code: "invalid_display_name" });
    // Eighteen letters outside the Basic Multilingual Plane are 36 UTF-16 units and still fit.
    expect(cleanDisplayName("\u{1D49C}".repeat(18))).toMatchObject({ ok: true });
    expect(cleanDisplayName("\u{1D49C}".repeat(19))).toMatchObject({ ok: false });
    expect(cleanDisplayName(" " + "b".repeat(18) + " ")).toEqual({ ok: true, name: "b".repeat(18) });
  });

  it("refuse control, format, separator, private, unassigned and surrogate code points, emoji, symbols and long mark runs", () => {
    const refused = ["", "   ", "\u00a0", "a\u200bb", "a\u200db", "\ufeffMaya", "\u202eevil", "a\u202ab", "\u2066x\u2069", "a\u061cb", "a\nb", "a\tb", "a\u0000b", "a\u2028b", "a\u2029b",
      "\ue000", "\u{F0000}", "\ud800", "a\udc00", "\u0378", "Maya\u{1F642}", "\u2764", "<b>", "[x]", "{x}", "a#b", "a/b", "a+b", "a=b", "a:b", "a;b", "a,b", "a\"b", "a`b", "a~b",
      "Maya$", "Maya@", "\u00a9", "\u2122", "x\u0301\u0302\u0303", "x".repeat(300)];
    for (const name of refused) expect(cleanDisplayName(name), JSON.stringify(name)).toEqual({ ok: false, code: "invalid_display_name" });
    for (const input of [null, undefined, 7, ["Maya"], { name: "Maya" }]) expect(cleanDisplayName(input)).toEqual({ ok: false, code: "invalid_display_name" });
    // Enclosing marks, a mark at the start, and marks that draw nothing.
    for (const name of ["x\u20dd", "x\u0489", "\u0301abc", "a\ufe0fb", "a\u034fb", "a\u180bb", "a\u{e0100}b", "a\u17b4b"]) expect(cleanDisplayName(name), JSON.stringify(name)).toEqual({ ok: false, code: "invalid_display_name" });
    // Names that draw nothing: Hangul fillers, the blank Braille cell, or marks and punctuation with no letter or digit.
    for (const name of ["\u3164", "\uffa0x".slice(0, 1), "\u115f\u1160", "\u2800\u2800", "Kai\u3164", "\u0301\u0302", "!?", "...", "-_-"]) expect(cleanDisplayName(name), JSON.stringify(name)).toEqual({ ok: false, code: "invalid_display_name" });
  });

  it("allow letters and digits of any script, spaces, two marks in a row and . ' - _ ! ?", () => {
    for (const name of ["Kite 41", "Ana-Mar\u00eda", "O'Brien", "O\u2019Brien", "snake_case", "Hey!", "Who?", "Dr. Who", "\u5f35\u5049", "\u0645\u062d\u0645\u062f", "Zo\u00eb", "\u0e2a\u0e21\u0e0a\u0e32\u0e22", "x\u0301\u0302", "\u0661\u0662\u0663"]) {
      expect(cleanDisplayName(name), name).toEqual({ ok: true, name: name.normalize("NFC") });
    }
  });

  it("refuse block-listed names through case, marks, swaps and spacing, and pass words that only contain them", () => {
    for (const name of ["N1gger", "n i g g e r", "F4GGOT", "Kike", "Spic Lord", "Hitler", "KKK fan", "Sieg Heil", "Nazi", "c00n", "P\u00e1k\u00ed", "big_slut", "kys",
      "Nazi!", "Hitler!", "Kys!", "Rape!", "Nazi0", "N a z i", "n.a.z.i", "n\u0430zi", "h\u0456tler", "sluuut"]) {
      expect(blockedName(name), name).toBe(true);
      expect(cleanDisplayName(name), name).toEqual({ ok: false, code: "display_name_refused" });
    }
    for (const name of ["Scunthorpe", "Raccoon", "Cocoon", "Tycoon", "Spice", "Therapist", "Grape", "Pakistan", "Nazir", "Japan", "Wopper", "Kite 41", "Lantern 27", "Dickens", "Classic", "Kirk Kelly", "Sussex", "Shitake Tea"]) {
      expect(blockedName(name), name).toBe(false);
      expect(cleanDisplayName(name), name).toMatchObject({ ok: true });
    }
  });

  it("are checked again whenever a stored name is served", () => {
    expect(shownName("Maya")).toBe("Maya");
    expect(shownName("Spic Lord")).toBeNull();
    expect(shownName(" Maya")).toBeNull();
    expect(shownName(7)).toBeNull();
    expect(shownName(null)).toBeNull();
  });
});

describe("PUT /v1/profile/name", () => {
  it("answers 503 with the flag off after auth alone, and 405 for other methods", async () => {
    const account = await create();
    const off = await counted("/v1/profile/name", "PUT", account, { schema_version: 1, display_name: "Maya", revision: 1 }, OFF);
    expect(await failure(off.response)).toEqual({ status: 503, body: { error: { code: "display_names_disabled", retryable: true } } });
    expect(off.calls).toEqual(["PLAYERS.authorize"]);
    expect((await call("/v1/profile/name", "GET", account)).status).toBe(405);
    expect(await identityOf(account)).not.toHaveProperty("display_name");
  });

  it("stores the server's cleaned name with exactly one Player call after auth", async () => {
    const account = await create();
    const set = await counted("/v1/profile/name", "PUT", account, { schema_version: 1, display_name: "  Rene\u0301e   Moss ", revision: 1_760_000_000_000 });
    expect(set.response.status).toBe(200);
    expect(await set.response.json()).toEqual({ schema_version: 1, display_name: "Ren\u00e9e Moss", revision: 1_760_000_000_000 });
    expect(set.calls).toEqual(["PLAYERS.authorize", "PLAYERS.setDisplayName"]);
    expect(await identityOf(account)).toMatchObject({ display_name: "Ren\u00e9e Moss", display_name_rev: 1_760_000_000_000, display_name_changes: [expect.any(Number)] });
  });

  it("refuses bad bodies and names without touching the stored name", async () => {
    const account = await named("Maya");
    const bodies = [{}, { schema_version: 1, display_name: "Kai" }, { schema_version: 1, revision: 9_000 }, { schema_version: 2, display_name: "Kai", revision: 9_000 },
      { schema_version: 1, display_name: "Kai", revision: 9_000, extra: 1 }, { schema_version: 1, display_name: 5, revision: 9_000 },
      ...[0, -1, 1.5, "9001", null, Number.MAX_SAFE_INTEGER + 1, 2 ** 60].map(rev => ({ schema_version: 1, display_name: "Kai", revision: rev })), [], "Kai", null];
    for (const body of bodies) {
      expect(await failure(await call("/v1/profile/name", "PUT", account, body)), JSON.stringify(body)).toEqual({ status: 400, body: { error: { code: "invalid_display_name", retryable: false } } });
    }
    expect(await failure(await setName(account, "Kai\u200b"))).toEqual({ status: 400, body: { error: { code: "invalid_display_name", retryable: false } } });
    expect(await failure(await setName(account, "Hitler"))).toEqual({ status: 422, body: { error: { code: "display_name_refused", retryable: false } } });
    expect((await identityOf(account))?.display_name).toBe("Maya");
    // A revision more than a day ahead of the server's clock would make every later change stale.
    expect(await failure(await setName(account, "Kai", Number.MAX_SAFE_INTEGER))).toEqual({ status: 400, body: { error: { code: "invalid_display_name", retryable: false } } });
    expect(await failure(await setName(account, "Kai", Date.now() + 2 * 86_400_000))).toEqual({ status: 400, body: { error: { code: "invalid_display_name", retryable: false } } });
    expect((await setName(account, "Kai", Date.now() + 3_600_000)).status).toBe(200);
  });

  it("never lets a late or repeated revision undo a newer change", async () => {
    const account = await create();
    expect(await (await setName(account, "Newer", 10)).json()).toEqual({ schema_version: 1, display_name: "Newer", revision: 10 });
    expect(await (await setName(account, "Older", 7)).json()).toEqual({ schema_version: 1, display_name: "Newer", revision: 10 });
    expect(await (await setName(account, null, 10)).json()).toEqual({ schema_version: 1, display_name: "Newer", revision: 10 });
    // The same name only moves the revision, so an older request still cannot land afterwards.
    expect(await (await setName(account, "Newer", 20)).json()).toEqual({ schema_version: 1, display_name: "Newer", revision: 20 });
    expect(await (await setName(account, "Older", 15)).json()).toEqual({ schema_version: 1, display_name: "Newer", revision: 20 });
    expect(await (await setName(account, null, 21)).json()).toEqual({ schema_version: 1, display_name: null, revision: 21 });
    expect(await identityOf(account)).not.toHaveProperty("display_name");
    // A player who never chose a name reads revision 0.
    const fresh = await create();
    await editIdentity(fresh, identity => { identity.display_name_rev = 5; });
    expect(await (await setName(fresh, "Kai", 5)).json()).toEqual({ schema_version: 1, display_name: null, revision: 5 });
  });

  it("allows five named changes a day, then answers 429 with retry_after_seconds, while anonymous and the same name stay allowed", async () => {
    const account = await create();
    for (let index = 0; index < MAX_DISPLAY_NAME_CHANGES; index++) { expect((await setName(account, "Name " + "abcde"[index])).status).toBe(200); advance(60_000); }
    const limited = await setName(account, "Name f");
    expect(limited.status).toBe(429);
    const seconds = Math.ceil((DISPLAY_NAME_WINDOW_MS - MAX_DISPLAY_NAME_CHANGES * 60_000) / 1000);
    expect(await limited.json()).toEqual({ error: { code: "display_name_limited", retryable: true, retry_after_seconds: seconds } });
    expect(limited.headers.get("Retry-After")).toBe(String(seconds));
    expect((await identityOf(account))?.display_name).toBe("Name e");
    expect(await (await setName(account, "Name e")).json()).toMatchObject({ display_name: "Name e" });
    expect(await (await setName(account, null)).json()).toMatchObject({ display_name: null });
    expect(await (await setName(account, null)).json()).toMatchObject({ display_name: null });
    expect((await setName(account, "Name f")).status).toBe(429);
    advance(DISPLAY_NAME_WINDOW_MS - 4 * 60_000);
    expect((await setName(account, "Name f")).status).toBe(200);
    expect((await identityOf(account))?.display_name_changes).toHaveLength(4);
    // Other errors keep their two keys and their usual Retry-After.
    const other = await call("/v1/profile/name", "PUT", account, { schema_version: 1, display_name: "x", revision: 1 }, OFF);
    expect(other.headers.get("Retry-After")).toBe("15");
  });

  it("survives every other identity write: recovery, platform restore, tester grant and friend changes", async () => {
    const account = await named("Maya"), friend = await named("Kai");
    await befriend(account, friend);
    const player = env.PLAYERS.getByName(account.player_id);
    value(await player.redeemTesterAccess(account.player_id, await digest(account.device_token), true));
    value(await player.recover(await digest(account.recovery_code), await digest(randomToken()), await digest(randomToken()), "a".repeat(64)));
    value(await player.restoreLinked(await digest(randomToken()), await digest(randomToken()), "b".repeat(64)));
    expect(await identityOf(account)).toMatchObject({ display_name: "Maya", tester_grant: expect.any(Object), social: expect.any(Object), recovery_receipt: expect.any(Object) });
  });
});

describe("operator clear-name", () => {
  it("clears the name and the room copies, locks new names for a week and keeps anonymous allowed", async () => {
    const host = await named("Maya"), guest = await named("Kai");
    const current = await room(host, guest);
    expect(await memberRows(current.room_id)).toHaveLength(2);
    expect((await clearName(host.player_id, "x".repeat(43))).status).toBe(401);
    expect((await clearName(host.player_id, OPERATOR, { schema_version: 1, extra: true })).status).toBe(400);
    const cleared = await clearName(host.player_id);
    expect(cleared.status).toBe(200);
    expect(await cleared.json()).toEqual({ schema_version: 1, cleared: true, rooms: 1 });
    expect(await memberRows(current.room_id)).toEqual([{ player_id: guest.player_id, display_name: "Kai" }]);
    expect((await (await read(current.room_id, guest)).json<RoomSnapshotV2>()).partner_name).toBeNull();
    expect(await identityOf(host)).toMatchObject({ display_name_locked_until: expect.any(Number) });
    expect(await identityOf(host)).not.toHaveProperty("display_name");
    expect(await failure(await setName(host, "Maya"))).toEqual({ status: 403, body: { error: { code: "display_name_locked", retryable: false } } });
    expect((await setName(host, null)).status).toBe(200);
    // A repeat is safe and reaches the same rooms.
    expect(await (await clearName(host.player_id)).json()).toEqual({ schema_version: 1, cleared: true, rooms: 1 });
    advance(DISPLAY_NAME_LOCK_MS + 1000);
    expect((await setName(host, "Maya")).status).toBe(200);
    expect(await identityOf(host)).not.toHaveProperty("display_name_locked_until");
    expect((await clearName(randomToken(16))).status).toBe(404);
  });

  it("pushes the partner's room index again so a stored row stops showing the name", async () => {
    const host = await named("Maya"), guest = await named("Kai"), vars = { ...ON, ROOM_INDEX_ENABLED: "true" };
    const done = await finish(await room(host, guest), host, guest);
    for (const stub of [env.ROOMS_V2.getByName(done.room_id), env.PLAYERS.getByName(guest.player_id)]) await objectFlags(stub, vars);
    expect((await inbox(guest, ASK, vars)).find(entry => entry.room_id === done.room_id)?.partner_name).toBe("Maya");
    expect((await inbox(guest, ASK, vars)).find(entry => entry.room_id === done.room_id)?.partner_name).toBe("Maya");
    expect((await clearName(host.player_id)).status).toBe(200);
    await until(async () => (await inbox(guest, ASK, vars)).find(entry => entry.room_id === done.room_id)?.partner_name === null);
  });
});

describe("the friends page", () => {
  it("is byte-identical without the header or with the flag off, and has six keys per row", async () => {
    const a = await named("Maya"), b = await named("Kai"), c = await named("Robin");
    await befriend(a, b); await request(a, c);
    const plain = await rawFriends(a, {});
    const parsed = JSON.parse(plain) as Page;
    expect(Object.keys(parsed)).toEqual(["schema_version", "friend_code", "refresh_after_seconds", "shared_room", "friends"]);
    for (const row of parsed.friends) expect(Object.keys(row)).toEqual(["player_id", "request_id", "status", "online", "expires_after_seconds", "join_available"]);
    expect(await rawFriends(a, ASK, OFF)).toBe(plain);
    expect(await rawFriends(a, {}, OFF)).toBe(plain);
  });

  it("names the caller and only accepted friends, and checks served names again", async () => {
    const a = await named("Maya"), b = await named("Kai"), pending = await named("Robin"), incoming = await named("Sky");
    await befriend(a, b); await request(a, pending); await request(incoming, a);
    const page = await friends(a);
    expect(Object.keys(page)).toEqual(["schema_version", "friend_code", "display_name", "refresh_after_seconds", "shared_room", "friends"]);
    expect(page.display_name).toBe("Maya");
    const byId = Object.fromEntries(page.friends.map(row => [row.player_id, row]));
    expect(byId[b.player_id]).toMatchObject({ status: "accepted", display_name: "Kai" });
    expect(byId[pending.player_id]).toMatchObject({ status: "outgoing", display_name: null });
    expect(byId[incoming.player_id]).toMatchObject({ status: "incoming", display_name: null });
    for (const row of page.friends) expect(Object.keys(row)).toHaveLength(7);
    // An anonymous friend reads null, and a name the list now refuses is served as null.
    expect((await setName(b, null)).status).toBe(200);
    expect((await friends(a)).friends.find(row => row.player_id === b.player_id)?.display_name).toBeNull();
    await editIdentity(b, identity => { identity.display_name = "Spic Lord"; });
    await editIdentity(a, identity => { identity.display_name = "Hitler"; });
    const rechecked = await friends(a);
    expect(rechecked.display_name).toBeNull();
    expect(rechecked.friends.find(row => row.player_id === b.player_id)?.display_name).toBeNull();
    // The friend who accepted sees the caller's name.
    expect((await setName(a, "Maya")).status).toBe(200);
    expect((await friends(b)).friends[0]).toMatchObject({ player_id: a.player_id, display_name: "Maya" });
  });

  it("costs no extra Durable Object call", async () => {
    const a = await named("Maya"), b = await named("Kai"), c = await named("Robin");
    await befriend(a, b); await request(a, c);
    advance((FRIEND_REFRESH_SECONDS + 1) * 1000);
    const without = await counted("/v1/friends", "GET", a, undefined, ON, {});
    advance((FRIEND_REFRESH_SECONDS + 1) * 1000);
    const asked = await counted("/v1/friends", "GET", a, undefined, ON, ASK);
    expect(asked.response.status).toBe(200);
    expect([...asked.calls].sort()).toEqual([...without.calls].sort());
  });
});

describe("room partner names", () => {
  it("come from create, join and turns, and ride beside full room reads and turn replies", async () => {
    const host = await named("Maya"), guest = await named("Kai");
    const current = await room(host, guest);
    expect(await memberRows(current.room_id)).toEqual([{ player_id: host.player_id, display_name: "Maya" }, { player_id: guest.player_id, display_name: "Kai" }].sort((x, y) => (x.player_id < y.player_id ? -1 : 1)));
    const seen = await (await read(current.room_id, guest)).json<RoomSnapshotV2>();
    expect(seen.partner_name).toBe("Maya");
    const { partner_name: _name, ...rest } = seen; void _name;
    expect(rest).toEqual(await (await read(current.room_id, guest, {})).json());
    expect(await (await read(current.room_id, guest, ASK, OFF)).json()).not.toHaveProperty("partner_name");
    expect((await (await read(current.room_id, host)).json<RoomSnapshotV2>()).partner_name).toBe("Kai");
    // Turn replies: beside receipt and room, never inside the room.
    const plain = await turn(current, host, firstA);
    expect(Object.keys(plain)).toEqual(["receipt", "room"]);
    const asked = await turn(plain.room, guest, firstB, middle, ON, ASK);
    expect(Object.keys(asked)).toEqual(["receipt", "room", "partner_name"]);
    expect(asked.partner_name).toBe("Maya");
    expect(asked.room).not.toHaveProperty("partner_name");
    // The small unchanged poll reply stays as it was.
    const small = await (await read(current.room_id, host, { ...ASK, "X-AfterYou-Known-Room": `${asked.room.revision}.${asked.room.branch}` })).json<Record<string, unknown>>();
    expect(Object.keys(small).sort()).toEqual(["branch", "revision", "schema_version", "unchanged", "updated_at"]);
  });

  it("follow a rename at that member's next turn, and leave every room at once when they go anonymous", async () => {
    const host = await named("Maya"), guest = await named("Kai");
    const current = await room(host, guest);
    const first = await turn(current, host, firstA);
    expect((await setName(guest, "Kai Two")).status).toBe(200);
    expect((await (await read(current.room_id, host)).json<RoomSnapshotV2>()).partner_name).toBe("Kai");
    const second = await turn(first.room, guest, firstB, middle);
    expect((await (await read(current.room_id, host)).json<RoomSnapshotV2>()).partner_name).toBe("Kai Two");
    expect((await setName(guest, null)).status).toBe(200);
    expect((await (await read(current.room_id, host)).json<RoomSnapshotV2>()).partner_name).toBeNull();
    expect(await memberRows(current.room_id)).toEqual([{ player_id: host.player_id, display_name: "Maya" }]);
    await turn(second.room, guest, secondA);
    expect((await (await read(current.room_id, host)).json<RoomSnapshotV2>()).partner_name).toBeNull();
    // Already anonymous: a second null clears nothing more and reaches no room.
    expect((await setName(guest, null)).status).toBe(200);
  });

  it("write nothing while the flag is off, and a room without names keeps its storage", async () => {
    const host = await named("Maya"), guest = await named("Kai");
    const current = await room(host, guest, OFF);
    await turn(current, host, firstA, undefined, OFF);
    expect(await roomTable(current.room_id)).toBe(false);
    expect((await (await read(current.room_id, guest)).json<RoomSnapshotV2>()).partner_name).toBeNull();
    const anonymous = await room(await create(), await create());
    expect(await roomTable(anonymous.room_id)).toBe(false);
  });

  it("reach the room inbox for clients that ask, live and from the room index, each member seeing the other", async () => {
    for (const indexed of [false, true]) {
      const host = await named("Maya"), guest = await named("Kai");
      const done = await finish(await room(host, guest), host, guest);
      const open = await room(await named("Robin"), host);
      const vars = { ...ON, ROOM_INDEX_ENABLED: String(indexed) };
      for (const stub of [env.ROOMS_V2.getByName(done.room_id), env.ROOMS_V2.getByName(open.room_id)]) await objectFlags(stub, vars);
      for (let pass = 0; pass < 2; pass++) {
        const hostEntries = await inbox(host, ASK, vars), guestEntries = await inbox(guest, ASK, vars);
        expect(hostEntries.find(entry => entry.room_id === done.room_id)?.partner_name).toBe("Kai");
        expect(hostEntries.find(entry => entry.room_id === open.room_id)?.partner_name).toBe("Robin");
        expect(guestEntries.find(entry => entry.room_id === done.room_id)?.partner_name).toBe("Maya");
      }
      for (const entry of await inbox(host, {}, vars)) expect(entry).not.toHaveProperty("partner_name");
      for (const entry of await inbox(host, ASK, { ...vars, DISPLAY_NAMES_ENABLED: "false" })) expect(entry).not.toHaveProperty("partner_name");
      await objectFlags(env.ROOMS_V2.getByName(done.room_id), { DISPLAY_NAMES_ENABLED: "false" });
      // A room that does not project names while the flag is off still gives every asking entry the key.
      expect((await inbox(guest, ASK, { ...vars, ROOM_INDEX_ENABLED: "false" })).find(entry => entry.room_id === done.room_id)?.partner_name).toBeNull();
      for (const [target, saved] of changed) for (const [name, setting] of Object.entries(saved)) { if (setting === undefined) delete target[name]; else target[name] = setting; }
      changed.clear();
      await reset();
    }
  }, 60_000);

  it("leave with the member who leaves a finished room, and with the whole room", async () => {
    const host = await named("Maya"), guest = await named("Kai");
    const done = await finish(await room(host, guest), host, guest);
    const left = await call(`/v2/rooms/${done.room_id}/leave`, "POST", host, { schema_version: 1, leave_finished: true }, { ...ON, FINISHED_ROOM_LEAVE_ENABLED: "true" });
    expect(left.status).toBe(200);
    expect(await memberRows(done.room_id)).toEqual([{ player_id: guest.player_id, display_name: "Kai" }]);
    expect((await (await read(done.room_id, guest)).json<RoomSnapshotV2>()).partner_name).toBeNull();
    value(await env.ROOMS_V2.getByName(done.room_id).eraseForPlayer(guest.player_id));
    expect(await roomTable(done.room_id)).toBe(false);
  });

  it("stay out of the room's operator snapshot, and a restore starts without them", async () => {
    const host = await named("Maya"), guest = await named("Kai");
    const current = await room(host, guest);
    const archive = value(await env.ROOMS_V2.getByName(current.room_id).exportSnapshot("d".repeat(40)));
    expect(archive).not.toContain(MEMBER_NAMES.name);
    expect(archive).not.toContain("Maya");
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await target.restoreSnapshot(archive, current.room_id)).toMatchObject({ ok: true });
    expect(await runInDurableObject(target, async (_, state) => state.storage.sql.exec("SELECT name FROM sqlite_master WHERE name=?", MEMBER_NAMES.name).toArray().length)).toBe(0);
  });
});

describe("erasure and the Player snapshot", () => {
  it("deleting the online identity deletes the name and the room copies", async () => {
    const host = await named("Maya"), guest = await named("Kai");
    const current = await room(host, guest);
    const deleted = await call("/v1/identity", "DELETE", host);
    expect(deleted.status).toBe(200);
    expect(await identityOf(host)).toBeNull();
    expect(await roomTable(current.room_id)).toBe(false);
  });

  it("exports the name keys as format 8 and restores them; an older format may not carry them", async () => {
    const account = await named("Maya");
    const source = env.PLAYERS.getByName(account.player_id);
    const archive = value(await source.exportSnapshot("d".repeat(40)));
    const parsed = JSON.parse(archive) as PortableSnapshot;
    expect(parsed.payload.format_version).toBe(8);
    const target = env.PLAYERS.get(env.PLAYERS.newUniqueId());
    expect(await target.restoreSnapshot(archive, account.player_id)).toMatchObject({ ok: true });
    expect(await runInDurableObject(target, async (_, state) => JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM identity").one().data))).toMatchObject({ display_name: "Maya", display_name_rev: expect.any(Number) });
    parsed.payload.format_version = 7;
    parsed.checksum.value = await digest(canonicalJson(parsed.payload));
    expect(await env.PLAYERS.get(env.PLAYERS.newUniqueId()).restoreSnapshot(canonicalJson(parsed), account.player_id)).toMatchObject({ ok: false, code: "unsupported_display_name" });
    // A player without any name key keeps the format it had.
    const plain = await create();
    expect((JSON.parse(value(await env.PLAYERS.getByName(plain.player_id).exportSnapshot("d".repeat(40)))) as PortableSnapshot).payload.format_version).toBe(1);
  });
});

describe("capability and request costs", () => {
  it("advertises display_names_version only to asking clients while the flag is on", async () => {
    const account = await create();
    const capabilities = (headers: Record<string, string>, vars: Record<string, string>) => call("/v2/capabilities", "GET", account, undefined, vars, headers).then(response => response.text());
    const before = await capabilities({}, OFF);
    expect(await capabilities({}, ON)).toBe(before);
    expect(await capabilities(ASK, OFF)).toBe(before);
    expect(JSON.parse(await capabilities(ASK, ON))).toMatchObject({ display_names_version: 1 });
  });

  it("adds no Durable Object call to room reads, turns, the inbox, creating or joining", async () => {
    const host = await named("Maya"), guest = await named("Kai");
    const current = await room(host, guest);
    const plainRead = await counted(`/v2/rooms/${current.room_id}`, "GET", guest, undefined, ON, {});
    const namedRead = await counted(`/v2/rooms/${current.room_id}`, "GET", guest, undefined, ON, ASK);
    expect(namedRead.calls).toEqual(plainRead.calls);
    const plainInbox = await counted("/v1/room-inbox", "GET", guest, undefined, ON, {});
    const namedInbox = await counted("/v1/room-inbox", "GET", guest, undefined, ON, ASK);
    expect(namedInbox.calls).toEqual(plainInbox.calls);
    const offTurn = await counted(`/v2/rooms/${current.room_id}/turns`, "POST", host, turnBody(current, firstA), OFF, {});
    expect(offTurn.response.status).toBe(200);
    const next = (await offTurn.response.json<MutationV2>()).room;
    const onTurn = await counted(`/v2/rooms/${current.room_id}/turns`, "POST", guest, turnBody(next, firstB, middle), ON, ASK);
    expect(onTurn.response.status).toBe(200);
    expect(onTurn.calls).toEqual(offTurn.calls);
    const creation = { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH };
    const offCreate = await counted("/v2/rooms", "POST", host, creation, OFF);
    const onCreate = await counted("/v2/rooms", "POST", host, { ...creation, idempotency_key: key() }, ON);
    // auth() asks the same Player once either way; with names on it also learns the name.
    const nameAuth = (calls: string[]) => calls.map((name, index) => index === 0 && name === "PLAYERS.authorize" ? "PLAYERS.authorizeNamed" : name);
    expect(onCreate.calls).toEqual(nameAuth(offCreate.calls));
    const offJoin = await counted("/v2/rooms/join", "POST", guest, { invite_code: (await offCreate.response.json<RoomSnapshotV2>()).invite_code }, OFF);
    const onJoin = await counted("/v2/rooms/join", "POST", await named("Robin"), { invite_code: (await onCreate.response.json<RoomSnapshotV2>()).invite_code }, ON);
    expect(onJoin.calls).toEqual(nameAuth(offJoin.calls));
  });

  it("reads no more rows in a room without names once the room has looked once", async () => {
    const host = await create(), guest = await create();
    const current = await room(host, guest);
    const stub = env.ROOMS_V2.getByName(current.room_id);
    await stub.inboxProjection(guest.player_id);
    const off = await meterRows({ room: stub }, async () => JSON.stringify(await stub.inboxProjection(guest.player_id)));
    await objectFlags(stub, ON);
    await stub.inboxProjection(guest.player_id);
    const on = await meterRows({ room: stub }, async () => JSON.stringify(await stub.inboxProjection(guest.player_id)));
    expect(on.value).toEqual(off.value);
    expect(on.rows.room).toEqual(off.rows.room);
  });
});

describe("a friend request to a room partner", () => {
  /** Opens the live socket for `who` and collects its messages. */
  async function connect(who: Account, vars: Record<string, string>): Promise<unknown[]> {
    const answer = await call(LIVE_PATH, "GET", who, undefined, vars, { Upgrade: "websocket" });
    expect(answer.status).toBe(101);
    const ws = answer.webSocket!; ws.accept();
    const messages: unknown[] = [];
    ws.addEventListener("message", event => { if (String(event.data) !== "pong") messages.push(JSON.parse(String(event.data))); });
    return messages;
  }
  const settle = () => new Promise(resolve => setTimeout(resolve, 80));

  it("has exactly the effects of any other friend request, with no new route and no phone alert", async () => {
    const live = { ...ON, LIVE_CONNECTION_ENABLED: "true" };
    const sender = await named("Maya"), partner = await named("Kai"), other = await named("Robin"), stranger = await named("Sky");
    // The sender knows the partner only from the room membership.
    const shared = await room(sender, partner, live);
    const partnerId = shared.host_id === sender.player_id ? shared.guest_id! : shared.host_id;
    expect(partnerId).toBe(partner.player_id);
    for (const who of [sender, partner, other, stranger]) await objectFlags(env.PLAYERS.getByName(who.player_id), live);
    const fetches = vi.spyOn(globalThis, "fetch");
    const partnerSocket = await connect(partner, live), strangerSocket = await connect(stranger, live);
    const toPartner = await call("/v1/friends/request", "POST", sender, { schema_version: 1, friend_code: partnerId }, live);
    const toStranger = await call("/v1/friends/request", "POST", other, { schema_version: 1, friend_code: stranger.player_id }, live);
    expect(toPartner.status).toBe(200); expect(toStranger.status).toBe(200);
    const shape = (body: Record<string, unknown>) => ({ ...body, player_id: "id", request_id: "request" });
    expect(shape(await toPartner.json())).toEqual(shape(await toStranger.json()));
    await until(() => partnerSocket.length > 0 && strangerSocket.length > 0);
    await settle();
    expect(partnerSocket).toEqual([{ type: "friend_requests_changed" }]);
    expect(strangerSocket).toEqual(partnerSocket);
    // The same incoming row on the recipient's list, and the same social inbox.
    const partnerPage = await friends(partner, {}, live), strangerPage = await friends(stranger, {}, live);
    expect(partnerPage.friends.map(row => ({ status: row.status, join_available: row.join_available }))).toEqual(strangerPage.friends.map(row => ({ status: row.status, join_available: row.join_available })));
    expect(partnerPage.friends[0].status).toBe("incoming");
    const social = async (who: Account) => (await call("/v1/social/inbox", "GET", who, undefined, live)).text();
    expect(await social(partner)).toBe(await social(stranger));
    // A friend request sends no push: nothing left the runtime.
    expect(fetches).not.toHaveBeenCalled();
  });
});

describe("friend link page name", () => {
  const link = (code: string, vars: Record<string, string | undefined> = ON, base: Env = env) => call(`/v1/friend-link/${code}/name`, "GET", undefined, undefined, vars, { Origin: FRIEND_LINK_ORIGIN }, base);
  const answer = async (response: Response) => ({ status: response.status, body: await response.json<Record<string, unknown>>() });
  const none = { status: 200, body: { schema_version: 1, display_name: null } };

  it("answers only the chosen name, for the owner's site, kept briefly", async () => {
    const maya = await named("Maya");
    const response = await link(maya.player_id);
    expect(await answer(response.clone())).toEqual({ status: 200, body: { schema_version: 1, display_name: "Maya" } });
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe("https://aamirazeez.com");
    expect(response.headers.get("Cache-Control")).toBe(`public, max-age=${FRIEND_LINK_MAX_AGE}`);
    expect(response.headers.get("Content-Type")).toBe("application/json; charset=utf-8");
    expect(Object.keys((await answer(await link(maya.player_id))).body)).toEqual(["schema_version", "display_name"]);
  });

  it("looks the same for an unknown code, an anonymous player, no identity and the flag off", async () => {
    const quiet = await named(null), hidden = await named("Kai");
    expect(await answer(await link(quiet.player_id))).toEqual(none);
    expect(await answer(await link(randomToken(16)))).toEqual(none);
    expect(await answer(await link("nobodyhere"))).toEqual(none);
    expect(await answer(await link(hidden.player_id, OFF))).toEqual(none);
    expect(await answer(await link(hidden.player_id, {}))).toEqual(none);
    // A Player nobody made stores nothing for the lookup.
    const stranger = randomToken(16);
    await link(stranger);
    expect(await runInDurableObject(env.PLAYERS.getByName(stranger), async (_, state) => state.storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table'").toArray().length)).toBe(0);
  });

  it("never answers the anonymous name: a player who went anonymous reads as none", async () => {
    const account = await named("Robin");
    expect((await setName(account, null)).status).toBe(200);
    expect(await answer(await link(account.player_id))).toEqual(none);
  });

  it("resolves a short name through FRIEND_ALIASES as Add friend does", async () => {
    const owner = await named("Ash");
    const aliases = { ...ON, FRIEND_ALIASES: JSON.stringify({ ashtest: owner.player_id }) };
    expect(await answer(await link("ashtest", aliases))).toEqual({ status: 200, body: { schema_version: 1, display_name: "Ash" } });
    expect(await answer(await link("AshTest", aliases))).toEqual({ status: 200, body: { schema_version: 1, display_name: "Ash" } });
    expect(await answer(await link("ashtest", ON))).toEqual(none);
  });

  it("costs at most one Player read, and none once kept or with the flag off", async () => {
    const lee = await named("Lee");
    const first = countingEnv({ ...env, V2_ROOMS_ENABLED: "true", ...ON } as unknown as Env);
    await link(lee.player_id, ON, first.env);
    expect(first.calls).toEqual(["PLAYERS.publicDisplayName"]);
    const second = countingEnv({ ...env, V2_ROOMS_ENABLED: "true", ...ON } as unknown as Env);
    expect((await answer(await link(lee.player_id, ON, second.env))).body.display_name).toBe("Lee");
    expect(second.calls).toEqual([]);
    const off = countingEnv({ ...env, V2_ROOMS_ENABLED: "true", ...OFF } as unknown as Env);
    await link(lee.player_id, OFF, off.env);
    expect(off.calls).toEqual([]);
  });

  it("refuses other methods and shapes, and is limited per address", async () => {
    const zoe = await named("Zoe");
    expect((await call(`/v1/friend-link/${zoe.player_id}/name`, "POST", undefined, {}, ON)).status).not.toBe(200);
    expect((await call(`/v1/friend-link/${"x".repeat(40)}/name`, "GET", undefined, undefined, ON)).status).not.toBe(200);
    expect((await call(`/v1/friend-link/${zoe.player_id}`, "GET", undefined, undefined, ON)).status).not.toBe(200);
    let limited = false;
    for (let i = 0; i < 40 && !limited; i++) {
      const response = await worker.fetch(new Request(`https://names.test/v1/friend-link/${zoe.player_id}/name`, { headers: { "CF-Connecting-IP": "198.18.99.1" } }), { ...env, ...ON } as unknown as Env);
      limited = response.status === 429;
    }
    expect(limited).toBe(true);
  });
});
