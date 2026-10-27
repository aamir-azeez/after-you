import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { noteFullJourney, type PollenReceipt, type WalletView } from "../src/pollen/wallet";
import { POLLEN_PLAYER_TABLES, POLLEN_ROOM_TABLES } from "../src/storage-schema";
import { countingEnv, meterRows } from "./meter";
import { currentSnapshotSchema } from "../src/snapshot";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

// Pollen earning through the Worker: one Player credit per accepted turn, retries and claims that pay
// once, the room boost, first clears, the flag off, and erasure. Synthetic identities only.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Reply = MutationV2 & { pollen?: PollenReceipt | { schema_version: 1; pending: true } };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const ON = { FEATURES: "POLLEN_EARN", POLLEN_SECRET: SECRET }, OFF = {}, ASK = { [POLLEN_HEADER]: "1" };
const DAY = 86_400_000;
const key = () => crypto.randomUUID();
let address = 0;

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string | undefined> = ON, headers: Record<string, string> = ASK, base: Env = env): Promise<Response> {
  const configured = Object.assign({ ...base }, { V2_ROOMS_ENABLED: "true", ...vars }) as Env;
  return worker.fetch(new Request("https://pollen.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.91." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function counted(path: string, method: string, account: Account, body: unknown, vars: Record<string, string> = ON, headers: Record<string, string> = ASK) {
  const meter = countingEnv({ ...env, V2_ROOMS_ENABLED: "true", ...vars } as unknown as Env);
  const response = await call(path, method, account, body, vars, headers, meter.env);
  return { response, calls: meter.calls };
}

/** Objects read POLLEN_SECRET from their own env, which in this runtime is the shared test env: set it there and take it back after. */
const shared = env as unknown as Record<string, unknown>;
beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
afterEach(async () => { delete shared.POLLEN_SECRET; vi.restoreAllMocks(); await reset(); });
const realNow = Date.now.bind(Date);
let offset = 0;
beforeEach(() => { offset = 0; vi.spyOn(Date, "now").mockImplementation(() => realNow() + offset); });

async function create(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201);
  return made.json<Account>();
}
/** A Full Journey end on the player's own record, as a RevenueCat check would note it. */
async function subscribe(account: Account, until = Date.now() + 30 * DAY): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => noteFullJourney(state.storage, until, Date.now()));
}
async function room(host: Account, guest: Account, vars: Record<string, string> = ON): Promise<RoomSnapshotV2> {
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH }, vars);
  expect(made.status).toBe(200);
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }, vars); expect(joined.status).toBe(200);
  return joined.json<RoomSnapshotV2>();
}
const turnBody = (current: RoomSnapshotV2, recording: unknown, checkpoint?: unknown, extra: Record<string, unknown> = {}) =>
  ({ base_revision: current.revision, branch: current.branch, idempotency_key: key(), recording, ...(checkpoint === undefined ? {} : { checkpoint }), ...extra });
async function turn(current: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown, vars: Record<string, string> = ON, headers: Record<string, string> = ASK): Promise<Reply> {
  const sent = await call(`/v2/rooms/${current.room_id}/turns`, "POST", account, turnBody(current, recording, checkpoint), vars, headers);
  expect(sent.status).toBe(200); return sent.json<Reply>();
}
const wallet = async (account: Account) => (await call("/v1/pollen", "GET", account)).json<WalletView>();
/** Player ids are random, so a relay turn may bloom: what a bank turn of `amount` pays at its own roll. */
const bloomed = (turn: PollenReceipt["turn"]) => turn!.amount * turn!.bloom + turn!.boost;
const receipt = (reply: Reply): PollenReceipt => { expect(reply.pollen).toBeDefined(); expect(reply.pollen).not.toHaveProperty("pending"); return reply.pollen as PollenReceipt; };
const tableNames = (stub: DurableObjectStub) => runInDurableObject(stub, async (_, state) =>
  state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'pollen_%' ORDER BY name").toArray().map(row => row.name));

describe("Pollen from turns", () => {
  it("answers the capability only to a phone that asks while earning works", async () => {
    const host = await create();
    const read = async (vars: Record<string, string | undefined>, headers: Record<string, string>) => (await call("/v2/capabilities", "GET", host, undefined, vars, headers)).json<Record<string, unknown>>();
    expect(await read(ON, ASK)).toMatchObject({ pollen_version: 1 });
    expect(await read(ON, {})).not.toHaveProperty("pollen_version");
    expect(await read(OFF, ASK)).not.toHaveProperty("pollen_version");
    expect(await read({ FEATURES: "POLLEN_EARN", POLLEN_SECRET: undefined }, ASK)).not.toHaveProperty("pollen_version");
    expect(await read({ FEATURES: "POLLEN_EARN", POLLEN_SECRET: "too-short" }, ASK)).not.toHaveProperty("pollen_version");
  });
  it("adds exactly one Player call to an accepted turn, and nothing at all while off", async () => {
    const host = await create(), guest = await create();
    const off = await room(host, guest, OFF), on = await room(host, guest);
    const offTurn = await counted(`/v2/rooms/${off.room_id}/turns`, "POST", host, turnBody(off, firstA), OFF);
    const onTurn = await counted(`/v2/rooms/${on.room_id}/turns`, "POST", host, turnBody(on, firstA));
    expect(offTurn.response.status).toBe(200); expect(onTurn.response.status).toBe(200);
    expect(onTurn.calls).toEqual([...offTurn.calls, "PLAYERS.creditTurn"]);
    const offReply = await offTurn.response.json<Reply>(), onReply = await onTurn.response.json<Reply>();
    expect(offReply).not.toHaveProperty("pollen");
    expect(onReply).not.toHaveProperty("pollen_facts");
    const paid = receipt(onReply);
    expect(paid).toMatchObject({ turn: { kind: "bank", base: 89, amount: 89, boost: 0 } });
    expect([1, 2, 3]).toContain(paid.turn!.bloom);
    expect([paid.earned, paid.balance, paid.turn!.total]).toEqual([89 * paid.turn!.bloom, 89 * paid.turn!.bloom, 89 * paid.turn!.bloom]);
    // Off, no Pollen table is made anywhere.
    expect(await tableNames(env.ROOMS_V2.getByName(off.room_id))).toEqual([]);
    expect((await tableNames(env.ROOMS_V2.getByName(on.room_id)))).toEqual(["pollen_turn_facts"]);
  });
  it("pays a host's turn only once a friend has joined, also on a later claim", async () => {
    const host = await create(), guest = await create();
    const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
    const created = await made.json<RoomSnapshotV2>();
    const alone = await turn(created, host, firstA);
    expect(alone.room.guest_id).toBeNull();
    expect(alone.pollen).toEqual({ schema_version: 1, earned: 0, balance: 0, clears: [] });
    const claim = { schema_version: 1, claims: [{ room_id: alone.room.room_id, recording_hash: firstA.recording_hash }] };
    const claimed = await (await call("/v1/pollen/turn-claims", "POST", host, claim)).json<{ results: { status: string; receipt?: PollenReceipt }[] }>();
    expect(claimed.results).toMatchObject([{ status: "credited", receipt: { earned: 0 } }]);
    expect(await wallet(host)).toMatchObject({ balance: 0, bank: 12 });
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: created.invite_code });
    expect(joined.status).toBe(200);
    const together = await turn(await joined.json<RoomSnapshotV2>(), guest, firstB, middle);
    expect(receipt(together).turn).toMatchObject({ kind: "bank", amount: 89 });
  });
  it("credits without the header too, and keeps the reply as it was for that phone", async () => {
    const host = await create(), guest = await create();
    const current = await room(host, guest);
    const reply = await turn(current, host, firstA, undefined, ON, {});
    expect(reply).not.toHaveProperty("pollen");
    const now = await wallet(host);
    expect(now.bank).toBe(11);
    expect([89, 178, 267]).toContain(now.balance);
  });
  it("credits the same turn once when its commit is sent again", async () => {
    const host = await create(), guest = await create();
    const current = await room(host, guest), body = { ...turnBody(current, firstA), tries: 1 };
    const first = await call(`/v2/rooms/${current.room_id}/turns`, "POST", host, body);
    const again = await call(`/v2/rooms/${current.room_id}/turns`, "POST", host, body);
    expect(first.status).toBe(200); expect(again.status).toBe(200);
    const one = receipt(await first.json<Reply>()), two = receipt(await again.json<Reply>());
    expect(one).toMatchObject({ turn: { amount: 111, bonuses: ["first_try"] } });
    expect(two).toEqual(one);
    expect(await wallet(host)).toMatchObject({ balance: one.earned, bank: 11 });
  });
  it("answers 200 with pending when the credit fails, and a later claim credits it once", async () => {
    const host = await create(), guest = await create();
    const current = await room(host, guest);
    const failing = { ...env, PLAYERS: new Proxy(env.PLAYERS, { get(target, name) {
      if (name !== "getByName") { const value = Reflect.get(target, name); return typeof value === "function" ? value.bind(target) : value; }
      return (id: string) => new Proxy(target.getByName(id), { get(stub, method) {
        if (method === "creditTurn") return () => Promise.reject(new Error("player_unreachable"));
        const value = Reflect.get(stub, method);
        // An RPC method is itself a stub, so call it through the stub rather than with bind().
        return typeof method !== "string" || typeof value !== "function" ? value : (...args: unknown[]) => (stub as unknown as Record<string, (...a: unknown[]) => unknown>)[method](...args);
      } });
    } }) } as unknown as Env;
    const sent = await call(`/v2/rooms/${current.room_id}/turns`, "POST", host, turnBody(current, firstA), ON, ASK, failing);
    expect(sent.status).toBe(200);
    const reply = await sent.json<Reply>();
    expect(reply.pollen).toEqual({ schema_version: 1, pending: true });
    expect(reply.room.revision).toBe(current.revision + 1);
    expect(await wallet(host)).toMatchObject({ balance: 0, bank: 12 });
    const claim = { schema_version: 1, claims: [{ room_id: current.room_id, recording_hash: reply.receipt.recording_hash }] };
    const claimed = await counted("/v1/pollen/turn-claims", "POST", host, claim);
    expect(claimed.calls).toEqual(["PLAYERS.authorize", "ROOMS_V2.pollenTurnFacts", "PLAYERS.creditTurn"]);
    const first = await claimed.response.json<{ results: { status: string; receipt?: PollenReceipt }[] }>();
    expect(first.results).toMatchObject([{ status: "credited", receipt: { turn: { kind: "bank", amount: 89 } } }]);
    const paid = first.results[0].receipt!;
    expect([paid.earned, paid.balance]).toEqual([bloomed(paid.turn), bloomed(paid.turn)]);
    const second = await (await call("/v1/pollen/turn-claims", "POST", host, claim)).json<{ results: { status: string; receipt?: PollenReceipt }[] }>();
    expect(second.results[0]).toEqual(first.results[0]);
    expect(await wallet(host)).toMatchObject({ balance: paid.earned, bank: 11 });
    // Only the turn's own player may claim it.
    const stolen = await (await call("/v1/pollen/turn-claims", "POST", guest, claim)).json<{ results: { status: string; code?: string }[] }>();
    expect(stolen.results).toEqual([{ ...claim.claims[0], status: "refused", code: "pollen_turn_not_found" }]);
  });
  it("does nothing at all while the flag is on but POLLEN_SECRET is missing", async () => {
    const host = await create(), guest = await create();
    delete shared.POLLEN_SECRET;
    const current = await room(host, guest, { FEATURES: "POLLEN_EARN" });
    const sent = await counted(`/v2/rooms/${current.room_id}/turns`, "POST", host, turnBody(current, firstA), { FEATURES: "POLLEN_EARN" });
    expect(sent.response.status).toBe(200);
    expect(sent.calls).not.toContain("PLAYERS.creditTurn");
    expect(await sent.response.json()).not.toHaveProperty("pollen");
    expect(await tableNames(env.ROOMS_V2.getByName(current.room_id))).toEqual([]);
  });
  it("boosts both players 10% for each Full Journey member, frozen at each turn", async () => {
    const cases: [boolean, boolean, number][] = [[false, false, 0], [true, false, 10], [false, true, 10], [true, true, 20]];
    for (const [hostPays, guestPays, percent] of cases) {
      const host = await create(), guest = await create();
      if (hostPays) await subscribe(host);
      if (guestPays) await subscribe(guest);
      let current = await room(host, guest);
      const hostTurn = await turn(current, host, firstA);
      current = hostTurn.room;
      const guestTurn = await turn(current, guest, firstB, middle);
      for (const reply of [hostTurn, guestTurn]) {
        const paid = receipt(reply).turn!;
        // The boost is worked out on the unboosted amount, never on a bloom.
        expect(paid, `${hostPays} ${guestPays}`).toMatchObject({ amount: 89, boost_percent: percent, boost: Math.floor((89 * percent * 2 + 100) / 200) });
        expect(paid.total).toBe(bloomed(paid));
        // Whose Full Journey it was, from the turn player's side, for the results line.
        const mine = reply === hostTurn ? hostPays : guestPays, theirs = reply === hostTurn ? guestPays : hostPays;
        if (percent > 0) expect(paid.boost_from).toEqual([...(mine ? ["you"] : []), ...(theirs ? ["partner"] : [])]);
        else expect(paid).not.toHaveProperty("boost_from");
      }
    }
  });
  it("stops boosting once a Full Journey period has ended", async () => {
    const host = await create(), guest = await create();
    await subscribe(host, Date.now() + DAY);
    const current = await room(host, guest);
    offset = 2 * DAY;
    expect(receipt(await turn(current, host, firstA)).turn).toMatchObject({ boost_percent: 0 });
  });
  it("pays both players' first clears on the turn that finishes the chapter together", async () => {
    const host = await create(), guest = await create();
    await subscribe(guest);
    let current = await room(host, guest);
    const earned = { host: 0, guest: 0 };
    for (const [account, recording, checkpoint, who] of [[host, firstA, undefined, "host"], [guest, firstB, middle, "guest"], [guest, secondA, undefined, "guest"]] as const) {
      const reply = await turn(current, account, recording, checkpoint);
      earned[who] += receipt(reply).earned; current = reply.room;
    }
    const finish = await counted(`/v2/rooms/${current.room_id}/turns`, "POST", host, turnBody(current, secondB, final));
    expect(finish.response.status).toBe(200);
    expect(finish.calls.filter(name => name.startsWith("PLAYERS.credit")).sort()).toEqual(["PLAYERS.creditTogetherClear", "PLAYERS.creditTurn"]);
    const done = receipt(await finish.response.json<Reply>());
    expect(done.clears).toEqual([{ kind: "clear", level_id: "relay-isles", amount: 1200, boost_percent: 10, boost: 120, total: 1320 }]);
    expect(done.earned).toBe(bloomed(done.turn) + 1320);
    expect(await wallet(host)).toMatchObject({ balance: earned.host + done.earned });
    expect(await wallet(guest)).toMatchObject({ balance: earned.guest + 1320 });
    // The partner's clear can be claimed again from the room: it pays nothing more.
    const again = await (await call("/v1/pollen/clear-claims", "POST", guest, { schema_version: 1, claims: [{ room_id: current.room_id }] })).json<{ results: { status: string; receipt?: PollenReceipt }[] }>();
    expect(again.results).toMatchObject([{ room_id: current.room_id, status: "credited", receipt: { earned: 0, balance: earned.guest + 1320 } }]);
  });
  it("recovers a partner's first clear the finishing turn could not pay, by that partner's own room claim", async () => {
    const host = await create(), guest = await create();
    let current = await room(host, guest);
    for (const [account, recording, checkpoint] of [[host, firstA, undefined], [guest, firstB, middle], [guest, secondA, undefined]] as const) current = (await turn(current, account, recording, checkpoint)).room;
    const failing = { ...env, PLAYERS: new Proxy(env.PLAYERS, { get(target, name) {
      if (name !== "getByName") { const value = Reflect.get(target, name); return typeof value === "function" ? value.bind(target) : value; }
      return (id: string) => new Proxy(target.getByName(id), { get(stub, method) {
        if (method === "creditTogetherClear") return () => Promise.reject(new Error("player_unreachable"));
        const value = Reflect.get(stub, method);
        return typeof method !== "string" || typeof value !== "function" ? value : (...args: unknown[]) => (stub as unknown as Record<string, (...a: unknown[]) => unknown>)[method](...args);
      } });
    } }) } as unknown as Env;
    const finish = await call(`/v2/rooms/${current.room_id}/turns`, "POST", host, turnBody(current, secondB, final), ON, ASK, failing);
    expect(finish.status).toBe(200);
    expect(receipt(await finish.json<Reply>()).clears.map(line => line.kind)).toEqual(["clear"]);
    const before = (await wallet(guest)).balance;
    const claimed = await (await call("/v1/pollen/clear-claims", "POST", guest, { schema_version: 1, claims: [{ room_id: current.room_id }] })).json<{ results: { status: string; receipt?: PollenReceipt }[] }>();
    expect(claimed.results).toMatchObject([{ status: "credited", receipt: { earned: 1200, clears: [{ kind: "clear", total: 1200 }] } }]);
    expect((await wallet(guest)).balance).toBe(before + 1200);
    const again = await (await call("/v1/pollen/clear-claims", "POST", guest, { schema_version: 1, claims: [{ room_id: current.room_id }] })).json<{ results: { status: string; receipt?: PollenReceipt }[] }>();
    expect(again.results[0].receipt!.earned).toBe(0);
  });
  it("pays a solo first clear the app claims once, and a paid chapter's only with Full Journey", async () => {
    const free = await create(), member = await create();
    await subscribe(member);
    const claim = (account: Account, levels: string[]) => call("/v1/pollen/clear-claims", "POST", account, { schema_version: 1, claims: levels.map(level_id => ({ level_id })) })
      .then(response => response.json<{ results: Record<string, unknown>[] }>());
    expect((await claim(free, ["first-steps", "rolling-home", "nowhere"])).results).toMatchObject([
      { level_id: "first-steps", status: "credited", receipt: { earned: 1200 } },
      { level_id: "rolling-home", status: "refused", code: "full_journey_required" },
      { level_id: "nowhere", status: "refused", code: "unsupported_chapter" }]);
    expect((await claim(free, ["first-steps"])).results).toMatchObject([{ status: "credited", receipt: { earned: 0, balance: 1200 } }]);
    expect((await claim(member, ["rolling-home"])).results).toMatchObject([{ status: "credited", receipt: { earned: 2200, clears: [{ boost_percent: 10, boost: 200 }] } }]);
    const bad = await call("/v1/pollen/clear-claims", "POST", free, { schema_version: 1, claims: [{ level_id: "first-steps", room_id: "x".repeat(22) }] });
    expect(bad.status).toBe(400);
  });
  it("reads the wallet and its history on auth's own Player call", async () => {
    const host = await create(), guest = await create();
    const paid = receipt(await turn(await room(host, guest), host, firstA)).earned;
    const read = await counted("/v1/pollen", "GET", host, undefined);
    expect(read.calls).toEqual(["PLAYERS.authorizeWallet"]);
    expect(await read.response.json()).toEqual({ schema_version: 1, balance: paid, earned: paid, bank: 11 });
    const history = await counted("/v1/pollen/history", "GET", host, undefined);
    expect(history.calls).toEqual(["PLAYERS.authorizeWallet"]);
    expect(await history.response.json()).toMatchObject({ schema_version: 1, entries: [{ kind: "turn", amount: paid, level_id: "relay-isles", stage_id: "relay", role: "a" }] });
  });
  it("answers every Pollen route 404 as before while the flag is off, before reading the body", async () => {
    const host = await create();
    for (const [path, method] of [["/v1/pollen", "GET"], ["/v1/pollen/history", "GET"], ["/v1/pollen/turn-claims", "POST"], ["/v1/pollen/clear-claims", "POST"]]) {
      const response = await counted(path, method, host, method === "POST" ? "not json" : undefined, OFF);
      expect(response.response.status, path).toBe(404);
      expect(response.calls).toEqual(["PLAYERS.authorize"]);
    }
  });
  it("never fails a turn or a claim over a stored facts row it cannot read", async () => {
    const host = await create(), guest = await create();
    const current = await room(host, guest);
    const first = await turn(current, host, firstA);
    await runInDurableObject(env.ROOMS_V2.getByName(current.room_id), async (_, state) => { state.storage.sql.exec("UPDATE pollen_turn_facts SET data='{\"schema_version\":9}'"); });
    const facts = await env.ROOMS_V2.getByName(current.room_id).pollenTurnFacts(host.player_id, first.receipt.recording_hash!);
    expect(facts).toEqual({ ok: false, status: 404, code: "pollen_turn_not_found" });
    const next = await turn(first.room, guest, firstB, middle);
    expect(next.room.revision).toBe(first.room.revision + 1);
  });
  it("costs the measured rows per turn, retry and claim", async () => {
    const host = await create(), guest = await create();
    // The first turn in each room and the first credit in each wallet create the tables; measure the next turn.
    const plain = (await turn(await room(host, guest, OFF), host, firstA, undefined, OFF)).room;
    const current = (await turn(await room(host, guest), host, firstA)).room, body = turnBody(current, firstB, middle);
    await (await call("/v1/pollen/clear-claims", "POST", guest, { schema_version: 1, claims: [{ level_id: "high-and-low" }] })).json();
    const stubs = { room: env.ROOMS_V2.getByName(current.room_id), player: env.PLAYERS.getByName(guest.player_id) };
    const off = await meterRows({ room: env.ROOMS_V2.getByName(plain.room_id), player: env.PLAYERS.getByName(guest.player_id) }, () => call(`/v2/rooms/${plain.room_id}/turns`, "POST", guest, turnBody(plain, firstB, middle), OFF));
    const on = await meterRows(stubs, () => call(`/v2/rooms/${current.room_id}/turns`, "POST", guest, body));
    const retry = await meterRows(stubs, () => call(`/v2/rooms/${current.room_id}/turns`, "POST", guest, body));
    const claim = await meterRows(stubs, () => call("/v1/pollen/turn-claims", "POST", guest, { schema_version: 1, claims: [{ room_id: current.room_id, recording_hash: firstB.recording_hash }] }));
    const extra = { room: on.rows.room.written - off.rows.room.written, player: on.rows.player.written - off.rows.player.written };
    console.log("pollen rows per turn", JSON.stringify({ off: off.rows, on: on.rows, extra, retry: retry.rows, claim: claim.rows }));
    // One facts row in the room; one claim row and the wallet row in the Player.
    expect(extra).toEqual({ room: 1, player: 2 });
    expect(retry.rows.player.written).toBe(0);
    expect(claim.rows.room.written + claim.rows.player.written).toBe(0);
  });
});

describe("Pollen storage", () => {
  it("drops every Pollen table with the room", async () => {
    const host = await create(), guest = await create();
    await subscribe(guest);
    const current = await room(host, guest);
    await turn(current, host, firstA);
    expect(await tableNames(env.ROOMS_V2.getByName(current.room_id))).toEqual(POLLEN_ROOM_TABLES.map(table => table.name).sort());
    expect((await call(`/v2/rooms/${current.room_id}`, "DELETE", host, undefined, ON, { "X-AfterYou-Close-If": "in-play" })).status).toBe(200);
    expect(await tableNames(env.ROOMS_V2.getByName(current.room_id))).toEqual([]);
  });
  it("lets a room with Pollen facts export, and refuses to export a Player with a wallet", async () => {
    const host = await create(), guest = await create();
    const current = await room(host, guest);
    await turn(current, host, firstA);
    const commit = "a".repeat(40);
    expect((await env.ROOMS_V2.getByName(current.room_id).exportSnapshot(commit)).ok).toBe(true);
    expect(await env.PLAYERS.getByName(host.player_id).exportSnapshot(commit)).toEqual({ ok: false, status: 400, code: "pollen_snapshot_unsupported" });
    // The runtime schema check (campaign capture, identity deletion scope) still accepts the wallet.
    await runInDurableObject(env.PLAYERS.getByName(host.player_id), async (_, state) => { expect(() => currentSnapshotSchema(state.storage, "Player")).not.toThrow(); });
    expect((await env.PLAYERS.getByName(guest.player_id).exportSnapshot(commit)).ok).toBe(true);
  });
  it("erases the wallet with the account", async () => {
    const player = await create();
    expect((await call("/v1/pollen/clear-claims", "POST", player, { schema_version: 1, claims: [{ level_id: "first-steps" }] })).status).toBe(200);
    expect(await tableNames(env.PLAYERS.getByName(player.player_id))).toEqual(POLLEN_PLAYER_TABLES.map(table => table.name).sort());
    expect((await call("/v1/identity", "DELETE", player)).status).toBe(200);
    expect(await tableNames(env.PLAYERS.getByName(player.player_id))).toEqual([]);
    expect((await call("/v1/pollen", "GET", player)).status).toBe(401);
  });
});
