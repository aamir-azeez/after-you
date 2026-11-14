import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { CHAPTERS } from "../src/v2/chapters";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { boardKeys } from "../src/leaderboards/boards";
import { forgetViews } from "../src/leaderboards/view-cache";
import { forgetCachedListings } from "../src/duels/public-list";
import { spotFor, type JoinAs } from "../src/duels/public";
import { DIRECTORY_NAME } from "../src/duels/directory";
import { PUBLIC_OPEN_MS, PUBLIC_STALL_MS } from "../src/duels/rules";
import type { Duel, DuelView } from "../src/duels/model";
import { POLLEN_CLIENT, configJson } from "./config";
import { countAllRequests } from "./meter";
import { PUBLIC_DUELS_HEADER, PUBLIC_TERMS_VERSION, TERMS_VERSION } from "../src/public-policy";
import spots from "../../game/tests/fixtures/public_duels/spots.json";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import { ledgerLines } from "../src/pollen/wallet";
import { countingEnv } from "./meter";

// Public duels end to end through the Worker (duels/public.ts, public-routes.ts): the list, posting, joining in any
// order, leaving, the masked rooms, blocks, reports, friend asks and the held extra. Synthetic identities only.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Any = Record<string, unknown>;
type Row = { duel_id: string; board: string; mine: boolean; sides: { steps: number; seats: { open: boolean; label: string | null; you?: true }[] }[] };
const SECRET = "synthetic-pollen-secret-for-tests-only-0003";
const OPERATOR = "o".repeat(43);
const ON = { CONFIG: configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "PUBLIC_DUELS", "DISPLAY_NAMES_ENABLED"] }), POLLEN_SECRET: SECRET, SAFETY_OPERATOR_TOKEN: OPERATOR };
const OFF = { ...ON, CONFIG: configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN"] }) };
const RELAY = "relay-isles@2";
const RELAY_KEY = { level_id: "relay-isles", level_version: 2, definition_hash: CHAPTERS[0].adapter.key.definition_hash };
let address = 0;

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, unknown> = ON, headers: Record<string, string> = {}): Promise<Response> {
  return worker.fetch(new Request("https://public.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + (++address % 250), "X-AfterYou-Pollen": "1", ...POLLEN_CLIENT,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), Object.assign({ ...env }, vars) as Env);
}
async function ok<T = Any>(response: Promise<Response>, status = 200): Promise<T> {
  const answer = await response;
  const text = await answer.text();
  expect(answer.status, text).toBe(status);
  return JSON.parse(text) as T;
}
const errorOf = async (response: Promise<Response>) => (await (await response).json<{ error: Any }>()).error;
async function create(): Promise<Account> { return ok<Account>(call("/v1/identity", "POST", undefined, {}), 201); }
async function befriend(a: Account, b: Account): Promise<void> {
  const { request_id } = await ok<{ request_id: string }>(call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: b.player_id }));
  await ok(call("/v1/friends/accept", "POST", b, { schema_version: 1, player_id: a.player_id, request_id }));
}
async function partner(a: Account, b: Account): Promise<void> {
  await befriend(a, b);
  await ok(call("/v1/duels/party/invite", "POST", a, { schema_version: 1, friend: b.player_id }));
  await ok(call("/v1/duels/party/accept", "POST", b, { schema_version: 1, from: a.player_id }));
}
/** Accepts the public duel rules, as the phone's rules screen does. */
async function acceptRules(account: Account): Promise<void> {
  const knows = { [PUBLIC_DUELS_HEADER]: "1" };
  const { terms_version } = await ok<{ terms_version: string }>(call("/v1/safety/terms", "GET", account, undefined, ON, knows));
  expect(terms_version).toBe(PUBLIC_TERMS_VERSION);
  await ok(call("/v1/safety/terms", "POST", account, { schema_version: 1, terms_version }, ON, knows));
}
/** A player with the community rules accepted; public duels are on by default, so nothing else. */
async function player(): Promise<Account> {
  const account = await create();
  await acceptRules(account);
  return account;
}
const setSwitch = (account: Account, on: boolean) => call("/v1/duels/public/me", "PUT", account, { schema_version: 1, on });
const post = (account: Account, as: JoinAs = "alone", key = crypto.randomUUID(), vars: Record<string, unknown> = ON) =>
  call("/v1/duels/public", "POST", account, { schema_version: 1, idempotency_key: key, board: RELAY, as }, vars);
/** The costly class's 5 a minute (limits.ts) let through, for a test that posts more than that on purpose. */
const UNLIMITED = { ...ON, TESTER_CODE_LIMITER: { limit: async () => ({ success: true }) } };
const join = (account: Account, duel: { duel_id: string }, as: JoinAs = "alone", seat: number | null = null, key = crypto.randomUUID()) =>
  call(`/v1/duels/public/${RELAY}/${duel.duel_id}/join`, "POST", account, { schema_version: 1, idempotency_key: key, as, seat });
const detail = (account: Account, duel: { duel_id: string }) => ok<{ duel: DuelView; held?: Any; pay?: Any }>(call(`/v1/duels/${RELAY}/${duel.duel_id}`, "GET", account));
/** The list as `account` reads it, once the board's change reached the directory (it goes after the board's reply). */
async function listFor(account: Account, until: (rows: Row[]) => boolean = () => true, scope = "all"): Promise<{ rows: Row[]; text: string }> {
  for (let tries = 0; ; tries++) {
    await forgetCachedListings();
    const answer = await call(`/v1/duels/public/list/${scope}/newest/0`, "GET", account);
    const text = await answer.text();
    expect(answer.status, text).toBe(200);
    const rows = (JSON.parse(text) as { rows: Row[] }).rows;
    if (until(rows) || tries >= 20) return { rows, text };
    await new Promise(resolve => setTimeout(resolve, 25));
  }
}
const boardDuel = (id: string) => runInDurableObject(env.LEADERBOARD_BOARDS.getByName(RELAY), async (_, ctx) =>
  JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM duels WHERE duel_id=?", id).one().data) as Duel);
const rewriteDuel = (id: string, change: (duel: Duel) => void) => runInDurableObject(env.LEADERBOARD_BOARDS.getByName(RELAY), async (_, ctx) => {
  const duel = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM duels WHERE duel_id=?", id).one().data) as Duel;
  change(duel);
  ctx.storage.sql.exec("UPDATE duels SET data=? WHERE duel_id=?", JSON.stringify(duel), id);
});
const openRoom = (host: Account, duel: DuelView) => call("/v2/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), ...RELAY_KEY, duel: { duel_id: duel.duel_id, board: duel.board } });

async function rerecord(input: Any): Promise<Any> { const body = { ...input }; delete body.recording_hash; return { ...input, recording_hash: await digest(canonicalJson(body)) }; }
async function rehash(input: Any): Promise<Any> { const body = { ...input }; delete body.checkpoint_hash; delete body.proof; return { ...input, checkpoint_hash: await digest(canonicalJson(body)) }; }
/** The Relay's first stage, unassisted (a duel room takes no Forgiving catches): two turns. */
async function firstStage(): Promise<[Any, Any, Any]> {
  const a1 = await rerecord({ ...firstA, catch_assistance: false });
  const b1 = await rerecord({ ...firstB, catch_assistance: false, source_recording_hash: a1.recording_hash });
  const mid = await rehash({ ...middle, a_recording_hash: a1.recording_hash, b_recording_hash: b1.recording_hash, proof: { ...(middle.proof as Any), a: a1, b: b1 } });
  return [a1, b1, mid];
}
const turn = (room: RoomSnapshotV2, recording: unknown, checkpoint?: unknown) =>
  ({ base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint === undefined ? {} : { checkpoint }) });

const shared = env as unknown as Record<string, unknown>;
beforeEach(async () => { shared.POLLEN_SECRET = SECRET; await forgetViews(boardKeys()); await forgetCachedListings(); });
afterEach(async () => { delete shared.POLLEN_SECRET; await reset(); });

describe("spot rules", () => {
  it("answer the shared table the phone reads too", () => {
    for (const item of spots.cases) {
      const answer = spotFor(item.seats, item.as as JoinAs, item.wanted);
      expect(answer, item.name).toEqual("seat" in item ? { seat: item.seat } : { reason: item.reason });
    }
  });
});

describe("public duels", () => {
  it("are absent while PUBLIC_DUELS is off, and the lobby and capability say nothing of them", async () => {
    const a = await create();
    for (const [path, method, body] of [["/v1/duels/public/list/all/newest/0", "GET"], ["/v1/duels/public", "POST", { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, as: "alone" }],
      ["/v1/duels/public/me", "PUT", { schema_version: 1, on: true }]] as [string, string, unknown?][]) expect((await call(path, method, a, body, OFF)).status, path).toBe(method === "PUT" ? 405 : 404);
    const lobby = await ok<Any>(call("/v1/duels", "GET", a, undefined, OFF));
    expect(lobby).not.toHaveProperty("public");
    const caps = await ok<Any>(call("/v2/capabilities", "GET", a, undefined, OFF, { "X-AfterYou-Duels": "1" }));
    expect(caps).not.toHaveProperty("public_duels_version");
    expect(await ok<Any>(call("/v2/capabilities", "GET", a, undefined, ON, { "X-AfterYou-Duels": "1" }))).toMatchObject({ public_duels_version: 1 });
  });

  it("show the public duel rules only to phones that know them, so older phones keep the rules and photo checks they know", async () => {
    const a = await create();
    expect(await ok<Any>(call("/v1/safety/config", "GET", a))).toMatchObject({ terms_version: TERMS_VERSION });
    expect(await ok<Any>(call("/v1/safety/config", "GET", a, undefined, ON, { [PUBLIC_DUELS_HEADER]: "1" }))).toMatchObject({ terms_version: PUBLIC_TERMS_VERSION });
    expect(await ok<Any>(call("/v1/safety/config", "GET", a, undefined, OFF, { [PUBLIC_DUELS_HEADER]: "1" }))).toMatchObject({ terms_version: TERMS_VERSION });
    // An older phone's acceptance stands for photos; it never covers the newer rules, and the lobby says so.
    await ok(call("/v1/safety/terms", "POST", a, { schema_version: 1, terms_version: TERMS_VERSION }));
    expect(await ok<Any>(call("/v1/safety/terms", "GET", a))).toMatchObject({ accepted: true });
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a))).public).toMatchObject({ rules: false, partner_rules: null });
    expect(await ok<Any>(call("/v1/safety/terms", "GET", a, undefined, ON, { [PUBLIC_DUELS_HEADER]: "1" }))).toMatchObject({ accepted: false });
    expect((await errorOf(call("/v1/duels/public/me", "PUT", a, { schema_version: 1, on: true })))).toMatchObject({ code: "terms_acceptance_required" });
    // An older phone posting the newer rules is refused; the newer acceptance covers the older rules.
    expect((await call("/v1/safety/terms", "POST", a, { schema_version: 1, terms_version: PUBLIC_TERMS_VERSION })).status).toBe(409);
    const blocks = await ok<Any>(call("/v1/safety/blocks", "GET", a));
    expect(Object.keys(blocks).sort()).toEqual(["blocked_players", "schema_version"]);
    expect(await ok<Any>(call("/v1/safety/blocks", "GET", a, undefined, ON, { [PUBLIC_DUELS_HEADER]: "1" }))).toMatchObject({ duel_blocks: [] });
  });

  it("send no acceptance time beside rules not accepted, so a phone that accepted only the photo rules can read the public ones and accept them", async () => {
    // game/services/safety_client.gd valid_terms: exactly four keys, a time only beside accepted true, null otherwise.
    const phoneTakes = (v: Any, version: string) => Object.keys(v).length === 4 && v.schema_version === 1 && v.terms_version === version && typeof v.accepted === "boolean" &&
      (v.accepted ? typeof v.accepted_at === "string" && v.accepted_at.length >= 20 && v.accepted_at.length <= 40 : v.accepted_at === null);
    const knows = { [PUBLIC_DUELS_HEADER]: "1" };
    const b = await create();
    const photo = await ok<Any>(call("/v1/safety/terms", "POST", b, { schema_version: 1, terms_version: TERMS_VERSION }));
    expect(phoneTakes(photo, TERMS_VERSION)).toBe(true);
    expect(await ok<Any>(call("/v1/safety/terms", "GET", b))).toEqual(photo);
    const config = await ok<Any>(call("/v1/safety/config", "GET", b, undefined, ON, knows));
    const unaccepted = await ok<Any>(call("/v1/safety/terms", "GET", b, undefined, ON, knows));
    expect(unaccepted).toEqual({ schema_version: 1, terms_version: PUBLIC_TERMS_VERSION, accepted: false, accepted_at: null });
    expect(phoneTakes(unaccepted, String(config.terms_version))).toBe(true);
    const accepted = await ok<Any>(call("/v1/safety/terms", "POST", b, { schema_version: 1, terms_version: config.terms_version }, ON, knows));
    expect(phoneTakes(accepted, PUBLIC_TERMS_VERSION) && accepted.accepted).toBe(true);
    expect(accepted.accepted_at).not.toBe(photo.accepted_at);
    expect(await ok<Any>(call("/v1/safety/terms", "GET", b, undefined, ON, knows))).toEqual(accepted);
    await ok(call("/v1/duels/public/me", "PUT", b, { schema_version: 1, on: true }, ON, knows));
  });

  it("serve the rules and privacy pages that say public duels are on unless turned off only while public duels are on", async () => {
    const page = async (path: string, vars: Record<string, unknown>) => (await call(path, "GET", undefined, undefined, vars)).text();
    for (const path of ["/privacy", "/community-rules"]) expect(await page(path, OFF), path).not.toMatch(/public duel/i);
    const rules = await page("/community-rules", ON), privacy = await page("/privacy", ON);
    expect(rules).toContain(`Version ${PUBLIC_TERMS_VERSION}. After You connects two invited players, and in public duels it connects players who don't know each other.`);
    expect(rules).toContain("before uploading shared photos or playing a public duel.");
    expect(rules).toContain("Public duels are on unless you turn them off in Settings, for example on a child's phone.");
    expect(rules).not.toMatch(/turn them on|turning on public duels/);
    expect(privacy).toContain("Public duels let you duel players you don't know. They are on unless you turn them off in Settings, for example on a child's phone.");
    expect(privacy).toContain("In a public duel, players you don't know see your name only if you turn on Show my name");
    expect(privacy).toContain("room/photo-reference metadata (for a public duel, the duel and seat)");
    // Today's page otherwise: everything else on it is unchanged.
    expect(privacy.replace(/<p>Public duels let you[^]*?<\/p>| In a public duel, players[^"<]*?there\.| \(for a public duel, the duel and seat\)/g, "")).toBe(await page("/privacy", OFF));
  });

  it("are on by default and stored only when switched off, need the rules for every post and join, and a paused player can neither post nor join", async () => {
    const a = await create();
    // Never touched: on, with nothing stored, and the first post asks for the rules.
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a))).public).toMatchObject({ on: true, paused: false });
    expect((await errorOf(post(a))).code).toBe("terms_acceptance_required");
    expect((await errorOf(setSwitch(a, true))).code).toBe("terms_acceptance_required");
    // The Member object makes its table only on its first write (lazy-storage.ts).
    const member = () => runInDurableObject(env.LEADERBOARD_MEMBERS.getByName(a.player_id), async (_, ctx) =>
      ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='lb_member'").toArray().length
        ? ctx.storage.sql.exec<{ data: string }>("SELECT data FROM lb_member WHERE id=1").toArray()[0]?.data ?? null : null);
    expect(await member()).toBeNull();
    // Off is kept, needs no rules, and stops posting; on again needs the rules and stores nothing.
    expect(await ok<Any>(setSwitch(a, false))).toEqual({ schema_version: 1, on: false, show_name: false, paused: false });
    expect(JSON.parse((await member())!)).toMatchObject({ public_off: true });
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a))).public).toMatchObject({ on: false });
    await acceptRules(a);
    expect((await errorOf(post(a))).code).toBe("public_duels_off");
    expect(await ok<Any>(setSwitch(a, true))).toMatchObject({ on: true });
    expect(JSON.parse((await member())!)).not.toHaveProperty("public_off");
    await ok(post(a));
    const b = await player();
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", b))).public).toMatchObject({ version: 1, on: true, paused: false, partner_on: null, running: 0, rules: true, partner_rules: null });
    // A first post writes the Member row the pause goes into.
    await ok(post(b));
    await runInDurableObject(env.LEADERBOARD_MEMBERS.getByName(b.player_id), async (_, ctx) => {
      ctx.storage.sql.exec("UPDATE lb_member SET data=json_set(data,'$.public_paused',json('true')) WHERE id=1");
    });
    expect((await errorOf(post(b))).code).toBe("public_paused");
    // A post or join that was on its way when the player was paused (or switched off) learns it with its pointer, in the same request.
    const ref = { duel_id: "f".repeat(32), board: RELAY, at: Date.now(), public: true as const };
    expect(await env.LEADERBOARD_MEMBERS.getByName(b.player_id).addPublicRef(b.player_id, ref, Date.now())).toEqual({ open: false });
    expect(await env.LEADERBOARD_MEMBERS.getByName(a.player_id).addPublicRef(a.player_id, ref, Date.now())).toEqual({ open: true });
  });

  it("post to the list with no id in it, and a retried post answers the same duel", async () => {
    const [a, reader] = await Promise.all([player(), player()]);
    const key = crypto.randomUUID();
    const first = (await ok<{ duel: DuelView }>(post(a, "alone", key))).duel;
    expect((await ok<{ duel: DuelView }>(post(a, "alone", key))).duel.duel_id).toBe(first.duel_id);
    expect(first.public).toMatchObject({ seats_open: 3 });
    expect(first.sides[0].seats).toEqual([{ open: false, you: true, label: null }, { open: true, you: false, label: null }]);
    const { rows, text } = await listFor(reader, found => found.length > 0);
    expect(rows.map(row => row.duel_id)).toEqual([first.duel_id]);
    expect(rows[0]).toMatchObject({ mine: false, sides: [{ seats: [{ open: false, label: null }, { open: true, label: null }] }, { seats: [{ open: true }, { open: true }] }] });
    expect(text).not.toContain(a.player_id);
    const own = await listFor(a, found => found.length > 0);
    expect(own.rows[0]).toMatchObject({ mine: true, sides: [{ seats: [{ you: true }, { open: true }] }, {}] });
    // One chapter's scope lists it; another chapter's does not.
    expect((await listFor(reader, found => found.length > 0, RELAY)).rows).toHaveLength(1);
    expect((await listFor(reader, () => true, `${CHAPTERS[1].adapter.key.level_id}@${CHAPTERS[1].adapter.key.level_version}`)).rows).toHaveLength(0);
  });

  it("seat a lone joiner beside the poster first, answer a repeat with the same duel, and take a whole pair for a party", async () => {
    const [poster, lone, p1, p2] = await Promise.all([player(), player(), player(), player()]);
    await partner(p1, p2);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    const joined = (await ok<{ duel: DuelView }>(join(lone, posted))).duel;
    expect(joined.mine).toBe(0);
    expect(joined.sides[0].seats).toEqual([{ open: false, you: false, label: null }, { open: false, you: true, label: null }]);
    // A stranger's id never shows; the partner seat reads as taken, its member null.
    expect(joined.sides[0].members).toEqual([null, lone.player_id]);
    expect((await ok<{ duel: DuelView }>(join(lone, posted))).duel.duel_id).toBe(posted.duel_id);
    const party = (await ok<{ duel: DuelView }>(join(p1, posted, "party"))).duel;
    expect(party.mine).toBe(1);
    // A party knows each other: ids shown on their own side, strangers still hidden.
    expect(party.sides[1]!.members.sort()).toEqual([p1.player_id, p2.player_id].sort());
    expect(party.sides[0].members).toEqual([null, null]);
    expect(party.public?.seats_open).toBe(0);
    expect(JSON.stringify(party)).not.toContain(poster.player_id);
    // Full: off the list.
    expect((await listFor(lone, found => found.length === 0)).rows).toHaveLength(0);
    // Maya is told at once; the party's duel is on her lobby.
    expect((await ok<{ duels: DuelView[] }>(call("/v1/duels", "GET", p2))).duels.map(view => view.duel_id)).toContain(posted.duel_id);
  });

  it("let only one of two parties take the last pair spot, and the loser gets spot_taken every time", async () => {
    const [poster, lone, p1, p2, q1, q2] = await Promise.all([player(), player(), player(), player(), player(), player()]);
    await partner(p1, p2); await partner(q1, q2);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await ok(join(lone, posted));
    const answers = await Promise.all([join(p1, posted, "party"), join(q1, posted, "party")]);
    const statuses = answers.map(answer => answer.status).sort();
    expect(statuses).toEqual([200, 409]);
    const loser = answers[0].status === 409 ? q1 : p1;
    const lost = await errorOf(join(answers[0].status === 409 ? p1 : q1, posted, "party"));
    expect(lost).toMatchObject({ code: "spot_taken", row: null });
    void loser;
  });

  it("put a seat back on the list when its player leaves before entering, end a side once they entered, and withdraw a duel its last player leaves", async () => {
    const [poster, lone] = await Promise.all([player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await ok(join(lone, posted));
    // The seat is free again: the leaver is no longer in the duel, so their answer names none.
    expect(await ok<Any>(call(`/v1/duels/${RELAY}/${posted.duel_id}/leave`, "POST", lone, { schema_version: 1 }))).toEqual({ schema_version: 1, duel: null, left: true });
    expect((await ok<{ duels: DuelView[] }>(call("/v1/duels", "GET", lone))).duels).toEqual([]);
    expect((await detail(poster, posted)).duel.public?.seats_open).toBe(3);
    // The poster opens their room: entered. Leaving now, as the only player left, withdraws the duel.
    await ok(openRoom(poster, (await detail(poster, posted)).duel));
    const view = (await ok<{ duel: DuelView }>(call(`/v1/duels/${RELAY}/${posted.duel_id}/leave`, "POST", poster, { schema_version: 1 }))).duel;
    expect(view.status).toBe("withdrawn");
    expect((await errorOf(join(lone, posted))).code).toBe("spot_taken");
  });

  it("wait on the other seat after a host played the first turn alone, open or taken, never entering it, in any order", async () => {
    const [poster, lone, other] = await Promise.all([player(), player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    const room = await ok<RoomSnapshotV2>(openRoom(poster, posted));
    const [a1, b1, mid] = await firstStage();
    await ok(call(`/v2/rooms/${room.room_id}/turns`, "POST", poster, turn(room, a1)));
    // The seat beside the poster is open: the side waits on it ("Waiting for a partner"), never on the poster.
    let side = (await detail(poster, posted)).duel.sides[0];
    expect(side).toMatchObject({ steps: 1, turn: 1, splits: [a1.duration_ticks] });
    expect(side.seats![1].open).toBe(true);
    expect((await boardDuel(posted.duel_id)).sides[0].turn).toBeNull();
    // A stranger takes it: their turn as both see it, and the seat is still not entered.
    await ok(join(lone, posted));
    side = (await detail(lone, posted)).duel.sides[0];
    expect([side.turn, side.members[1]]).toEqual([1, lone.player_id]);
    expect((await detail(poster, posted)).duel.sides[0]).toMatchObject({ turn: 1, members: [poster.player_id, null] });
    let stored = await boardDuel(posted.duel_id);
    expect([stored.sides[0].turn, stored.public!.seats[1].entered]).toEqual([null, undefined]);
    // They leave before entering: the seat goes back on the list, and the side waits on the open seat again.
    expect(await ok<Any>(call(`/v1/duels/${RELAY}/${posted.duel_id}/leave`, "POST", lone, { schema_version: 1 }))).toEqual({ schema_version: 1, duel: null, left: true });
    const back = (await detail(poster, posted)).duel;
    expect([back.public?.seats_open, back.sides[0].turn, back.sides[0].seats![1].open]).toEqual([3, 1, true]);
    // Another takes it, enters and plays: the room names every turn from then on.
    const mine = (await ok<{ duel: DuelView }>(join(other, posted))).duel;
    expect([mine.sides[0].turn, mine.sides[0].members[1]]).toEqual([1, other.player_id]);
    const entered = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", other, { invite_code: mine.sides[0].invite_code }));
    await ok(call(`/v2/rooms/${entered.room_id}/turns`, "POST", other, turn(entered, b1, mid)));
    stored = await boardDuel(posted.duel_id);
    expect([stored.public!.seats[1].entered, stored.sides[0].steps, stored.sides[0].turn]).toEqual([true, 2, other.player_id]);
    expect((await detail(poster, posted)).duel.sides[0]).toMatchObject({ turn: 1, splits: [a1.duration_ticks, (a1.duration_ticks as number) + (b1.duration_ticks as number)] });
  });

  it("end a side waiting on its other seat as nobody_joined while the seat is open, and as stalled once taken but never entered", async () => {
    const [poster, lone, p1, p2, late] = await Promise.all([player(), player(), player(), player(), player()]);
    await partner(p1, p2);
    const [a1] = await firstStage();
    const firstTurn = async (duel: DuelView) => { const room = await ok<RoomSnapshotV2>(openRoom(poster, duel)); await ok(call(`/v2/rooms/${room.room_id}/turns`, "POST", poster, turn(room, a1))); };
    const open = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await firstTurn(open);
    await rewriteDuel(open.duel_id, duel => { duel.public!.open_until_ms = Date.now() - 1; });
    expect((await errorOf(join(late, open))).code).toBe("spot_taken");
    const unjoined = (await detail(poster, open)).duel;
    expect([unjoined.status, unjoined.result?.reason, unjoined.sides[0].turn]).toEqual(["unfinished", "nobody_joined", null]);
    const taken = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await firstTurn(taken);
    await ok(join(lone, taken));
    await ok(join(p1, taken, "party"));
    expect((await detail(lone, taken)).duel.sides[0].turn).toBe(1);
    await rewriteDuel(taken.duel_id, duel => { duel.accepted_ms! -= PUBLIC_STALL_MS; for (const side of duel.sides) if (side?.last_ms) side.last_ms -= PUBLIC_STALL_MS; duel.public!.posted_ms -= PUBLIC_STALL_MS; });
    const stalled = (await detail(poster, taken)).duel;
    expect([stalled.status, stalled.result?.reason, stalled.sides[0].turn]).toEqual(["unfinished", "stalled", null]);
    const stored = await boardDuel(taken.duel_id);
    expect([stored.public!.seats[1].entered, stored.result?.forfeit]).toEqual([undefined, undefined]);
  });

  it("refuse a join after the spots closed, and end the duel as nobody_joined with no win or loss", async () => {
    const [poster, late] = await Promise.all([player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await rewriteDuel(posted.duel_id, duel => { duel.public!.open_until_ms = Date.now() - 1; duel.public!.posted_ms -= PUBLIC_OPEN_MS; });
    expect((await errorOf(join(late, posted))).code).toBe("spot_taken");
    const view = (await detail(poster, posted)).duel;
    expect([view.status, view.result?.reason, view.result?.outcome]).toEqual(["unfinished", "nobody_joined", "none"]);
  });

  it("show a stranger in the shared room only as a stand-in, with no name, no presence and no photos", async () => {
    const [poster, lone] = await Promise.all([player(), player()]);
    await ok(call("/v1/profile/name", "PUT", poster, { schema_version: 1, display_name: "Kite", revision: Date.now() }));
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    const room = await ok<RoomSnapshotV2>(openRoom(poster, posted));
    const mine = (await ok<{ duel: DuelView }>(join(lone, posted))).duel;
    const invite = mine.sides[0].invite_code as string;
    expect(invite).toBeTruthy();
    const joined = await call("/v2/rooms/join", "POST", lone, { invite_code: invite }, ON, { "X-AfterYou-Display-Names": "1" });
    const text = await joined.text();
    expect(joined.status, text).toBe(200);
    expect(text).not.toContain(poster.player_id);
    expect(text).not.toContain("Kite");
    const seen = JSON.parse(text) as RoomSnapshotV2;
    expect(seen.guest_id).toBe(lone.player_id);
    expect(seen.host_id).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(seen).not.toHaveProperty("duel_masks");
    // The host sees the guest's stand-in too, on every read: the room, the inbox, presence.
    for (const [path, account] of [[`/v2/rooms/${room.room_id}`, poster], ["/v1/room-inbox", poster], ["/v1/room-inbox", lone]] as [string, Account][]) {
      const body = await (await call(path, "GET", account, undefined, ON, { "X-AfterYou-Display-Names": "1" })).text();
      const other = account === poster ? lone : poster;
      expect(body, path).not.toContain(other.player_id);
    }
    expect(await ok<Any>(call(`/v2/rooms/${room.room_id}/presence`, "GET", lone))).toMatchObject({ partner_online: false });
    // Even while the stranger is online nothing about it is read: the room answers after its pair gate, 2 requests with a warm memo (it was 9).
    for (const [asker, other] of [[lone, poster], [poster, lone]] as [Account, Account][]) {
      await ok(call("/v1/presence", "POST", other, { schema_version: 1, session_id: "d".repeat(36), online: true }));
      expect(await ok<Any>(call(`/v2/rooms/${room.room_id}/presence`, "GET", asker))).toEqual({ schema_version: 1, partner_joined: true, partner_online: false, expires_after_seconds: 0 });
      const read = await countAllRequests(env, async () => ok<Any>(call(`/v2/rooms/${room.room_id}/presence`, "GET", asker)));
      expect(read.value).toEqual({ schema_version: 1, partner_joined: true, partner_online: false, expires_after_seconds: 0 });
      expect(read.calls.sort()).toEqual(["PLAYERS.authorizeRoom", "ROOMS_V2.partnerPresence"]);
    }
    // The board knows the guest entered: their leaving now ends the side instead of reopening the seat.
    expect((await boardDuel(posted.duel_id)).public!.seats[1].entered).toBe(true);
  });

  it("read a list page again for auth and the reader's Member row only, and read their own blocks afresh once a block changes their safety token", async () => {
    const [poster, reader] = await Promise.all([player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await listFor(reader, rows => rows.some(row => row.duel_id === posted.duel_id));
    const page = () => countAllRequests(env, async () => ok<{ rows: Row[] }>(call("/v1/duels/public/list/all/newest/0", "GET", reader)));
    // The listing is cached in this isolate too, so a page read again is auth and the Member row: 2 requests (it was 3).
    const again = await page();
    expect(again.value.rows.map(row => row.duel_id)).toContain(posted.duel_id);
    expect(again.calls.sort()).toEqual(["LEADERBOARD_MEMBERS.read", "PLAYERS.authorizeNamed"]);
    // A block (here of the poster, through the seat) gives the reader a new token: the next page reads their blocks and hides the duel.
    await ok(join(reader, posted));
    await ok(call(`/v1/duels/public/${RELAY}/${posted.duel_id}/block`, "POST", reader, { schema_version: 1, seat: 0 }));
    const second = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await forgetCachedListings();
    const after = await page();
    expect(after.calls).toContain("SAFETY_PROFILES.blocks");
    expect(after.value.rows.map(row => row.duel_id)).not.toContain(second.duel_id);
  });

  it("block by seat, leaving the duel for your own partner, list the block by handle only, and hide the blocker's duels from the blocked", async () => {
    const [poster, lone, reader] = await Promise.all([player(), player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await ok(join(lone, posted));
    const blocked = await ok<{ blocked: boolean; left: boolean }>(call(`/v1/duels/public/${RELAY}/${posted.duel_id}/block`, "POST", lone, { schema_version: 1, seat: 0 }));
    expect(blocked).toEqual({ schema_version: 1, blocked: true, left: true });
    const list = await ok<{ blocked_players: string[]; duel_blocks: { handle: string; label: string | null }[] }>(call("/v1/safety/blocks", "GET", lone, undefined, ON, { [PUBLIC_DUELS_HEADER]: "1" }));
    expect(list.blocked_players).toEqual([]);
    // An older phone never sees the id either, only without the handles.
    expect(await ok<Any>(call("/v1/safety/blocks", "GET", lone))).toEqual({ schema_version: 1, blocked_players: [] });
    expect(list.duel_blocks).toHaveLength(1);
    expect(JSON.stringify(list)).not.toContain(poster.player_id);
    // The poster's next post never lists for the player who blocked them, or for the poster from theirs.
    const again = (await ok<{ duel: DuelView }>(post(poster))).duel;
    expect((await listFor(reader, rows => rows.some(row => row.duel_id === again.duel_id))).rows.map(row => row.duel_id)).toContain(again.duel_id);
    expect((await listFor(lone)).rows.map(row => row.duel_id)).not.toContain(again.duel_id);
    expect((await errorOf(join(lone, again))).code).toBe("spot_taken");
    await ok(call(`/v1/safety/blocks/duel/${list.duel_blocks[0].handle}`, "DELETE", lone));
    expect((await ok<{ duel_blocks: unknown[] }>(call("/v1/safety/blocks", "GET", lone, undefined, ON, { [PUBLIC_DUELS_HEADER]: "1" }))).duel_blocks).toEqual([]);
  });

  it("count reports from three different players in a week as a pause that takes the player's duels off the list", async () => {
    const [target, r1, r2, r3, reader] = await Promise.all([player(), player(), player(), player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(target))).duel;
    for (const reporter of [r1, r2, r3]) await ok(join(reporter, posted));
    const second = (await ok<{ duel: DuelView }>(post(target))).duel;
    for (const [reporter, again] of [[r1, false], [r1, true], [r2, false], [r3, false]] as [Account, boolean][]) {
      const receipt = await ok<Any>(call(`/v1/duels/public/${RELAY}/${posted.duel_id}/report`, "POST", reporter, { schema_version: 1, idempotency_key: crypto.randomUUID(), seat: 0, reason: "harassment" }));
      expect(receipt, String(again)).toMatchObject({ received: true });
    }
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", target))).public).toMatchObject({ paused: true });
    expect((await listFor(reader, rows => !rows.some(row => row.duel_id === second.duel_id))).rows.map(row => row.duel_id)).not.toContain(second.duel_id);
    expect((await errorOf(post(target))).code).toBe("public_paused");
    // An operator's clear puts them back.
    await ok(call(`/operator/safety/players/${target.player_id}/public-unpause`, "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + OPERATOR }));
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", target))).public).toMatchObject({ paused: false });
    expect((await listFor(reader, rows => rows.some(row => row.duel_id === second.duel_id))).rows.map(row => row.duel_id)).toContain(second.duel_id);
  });

  it("never seat a player who switched off: their open duels leave the list, a join is refused, and neither a pause clear nor another player's change lists them", async () => {
    const [poster, other, lone, reader] = await Promise.all([player(), player(), player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    const shared = (await ok<{ duel: DuelView }>(post(other))).duel;
    await ok(join(poster, shared));
    expect((await listFor(reader, rows => rows.length === 2)).rows).toHaveLength(2);
    await ok(setSwitch(poster, false));
    // Both duels holding the poster are off the list, and the board refuses a join to either.
    expect((await listFor(reader, rows => rows.length === 0)).rows).toEqual([]);
    expect((await errorOf(join(lone, posted))).code).toBe("spot_taken");
    expect((await errorOf(join(lone, shared))).code).toBe("spot_taken");
    expect((await boardDuel(posted.duel_id)).public!.seats[0]).toMatchObject({ hidden: true });
    // A pause and its clear on the other player in the shared duel leave the poster's mark alone.
    await runInDurableObject(env.LEADERBOARD_MEMBERS.getByName(other.player_id), async (_, ctx) => {
      ctx.storage.sql.exec("UPDATE lb_member SET data=json_set(data,'$.public_paused',json('true')) WHERE id=1");
    });
    await ok(call(`/operator/safety/players/${other.player_id}/public-unpause`, "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + OPERATOR }));
    // The poster's own pause clear, while switched off, keeps them off the list too.
    await ok(call(`/operator/safety/players/${poster.player_id}/public-unpause`, "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + OPERATOR }));
    expect((await listFor(reader, () => true)).rows).toEqual([]);
    // On again: both come back.
    await ok(setSwitch(poster, true));
    expect((await listFor(reader, rows => rows.length === 2)).rows.map(row => row.duel_id).sort()).toEqual([posted.duel_id, shared.duel_id].sort());
    expect((await ok<{ duel: DuelView }>(join(lone, posted))).duel.duel_id).toBe(posted.duel_id);
    // A seat whose player switched off and then gave it back before entering starts clear for the next one.
    await ok(setSwitch(lone, false));
    expect((await boardDuel(posted.duel_id)).public!.seats[1]).toMatchObject({ hidden: true });
    await ok(call(`/v1/duels/${RELAY}/${posted.duel_id}/leave`, "POST", lone, { schema_version: 1 }));
    expect((await boardDuel(posted.duel_id)).public!.seats[1]).toEqual({ label: null });
    expect((await listFor(reader, rows => rows.some(row => row.duel_id === posted.duel_id))).rows.map(row => row.duel_id)).toContain(posted.duel_id);
    // An on sent again (its reply lost after a failed hiding) settles the marks again, though the switch did not change.
    await rewriteDuel(shared.duel_id, duel => { duel.public!.seats[0].hidden = true; });
    await forgetCachedListings();
    await ok(setSwitch(other, true));
    expect((await boardDuel(shared.duel_id)).public!.seats[0]).not.toHaveProperty("hidden");
  });

  it("hold a party's partner to the same switch and rules, and the lobby says whether the partner is open", async () => {
    const [a, b, poster] = await Promise.all([player(), create(), player()]);
    await befriend(a, b);
    await ok(call("/v1/duels/party/invite", "POST", a, { schema_version: 1, friend: b.player_id }));
    // The accept's own answer says the rules are not accepted yet, so Maya's phone asks for them right after.
    expect((await ok<{ public: Any }>(call("/v1/duels/party/accept", "POST", b, { schema_version: 1, from: a.player_id }))).public).toMatchObject({ rules: false, partner_rules: true });
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    // Maya never opened public duels: her switch is on by default, but she has not accepted the rules, and the lobby
    // says so from the party read it makes anyway, so the phone greys a party post or join before the tap.
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a))).public).toMatchObject({ on: true, partner_on: true, rules: true, partner_rules: false });
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", b))).public).toMatchObject({ rules: false, partner_rules: true });
    expect((await errorOf(post(a, "party"))).code).toBe("partner_rules_required");
    expect((await errorOf(join(a, posted, "party"))).code).toBe("partner_rules_required");
    await acceptRules(b);
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a))).public).toMatchObject({ rules: true, partner_rules: true });
    await ok(setSwitch(b, false));
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a))).public).toMatchObject({ partner_on: false });
    expect((await errorOf(join(a, posted, "party"))).code).toBe("partner_public_off");
    await ok(setSwitch(b, true));
    expect((await ok<{ duel: DuelView }>(join(a, posted, "party"))).duel.mine).toBe(1);
  });

  it("keep each player's accepted rules on their Member row, written again when lost and never by an older phone", async () => {
    const [a, b] = await Promise.all([player(), create()]);
    await partner(a, b);
    const stored = (id: string) => runInDurableObject(env.LEADERBOARD_MEMBERS.getByName(id), async (_, ctx) =>
      (JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM lb_member WHERE id=1").toArray()[0]?.data ?? "{}") as Any).rules_version ?? null);
    expect(await stored(a.player_id)).toBe(PUBLIC_TERMS_VERSION);
    // An older phone accepts the rules it knows: nothing for public duels is written.
    await ok(call("/v1/safety/terms", "POST", b, { schema_version: 1, terms_version: TERMS_VERSION }));
    expect(await stored(b.player_id)).toBeNull();
    // The copy lost after the SafetyProfile took the rules: the lobby greys, the next accept or post writes it again.
    await acceptRules(b);
    const drop = (id: string) => runInDurableObject(env.LEADERBOARD_MEMBERS.getByName(id), async (_, ctx) => {
      ctx.storage.sql.exec("UPDATE lb_member SET data=json_remove(data,'$.rules_version') WHERE id=1");
    });
    await drop(b.player_id);
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a))).public).toMatchObject({ partner_rules: false });
    await acceptRules(b);
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a))).public).toMatchObject({ partner_rules: true });
    await drop(b.player_id);
    await ok(post(a, "party"));
    expect(await stored(b.player_id)).toBe(PUBLIC_TERMS_VERSION);
    // With public duels off the lobby has no public part at all, and an accept then writes nothing.
    const c = await create();
    expect((await ok<Any>(call("/v1/duels", "GET", c, undefined, OFF))).public).toBeUndefined();
    await ok(call("/v1/safety/terms", "POST", c, { schema_version: 1, terms_version: TERMS_VERSION }, OFF, { [PUBLIC_DUELS_HEADER]: "1" }));
    expect(await runInDurableObject(env.LEADERBOARD_MEMBERS.getByName(c.player_id), async (_, ctx) =>
      ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='lb_member'").toArray().length)).toBe(0);
  });

  it("send a friend request by seat only once the duel is over, which the asker's own list does not show until accepted", async () => {
    const [poster, lone] = await Promise.all([player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await ok(join(lone, posted));
    const ask = () => call(`/v1/duels/public/${RELAY}/${posted.duel_id}/friend`, "POST", lone, { schema_version: 1, seat: 0 });
    expect((await errorOf(ask())).code).toBe("duel_not_over");
    await rewriteDuel(posted.duel_id, duel => { duel.status = "unfinished"; duel.result = { winner: null, reason: "stalled", decided_ms: Date.now(), margin_ticks: null }; });
    expect(await ok<Any>(ask())).toEqual({ schema_version: 1, sent: true });
    const asker = await (await call("/v1/friends", "GET", lone)).text();
    expect(asker).not.toContain(poster.player_id);
    const asked = await ok<{ friends: { player_id: string; status: string; request_id: string }[] }>(call("/v1/friends", "GET", poster));
    expect(asked.friends).toEqual([expect.objectContaining({ player_id: lone.player_id, status: "incoming" })]);
    await ok(call("/v1/friends/accept", "POST", poster, { schema_version: 1, player_id: lone.player_id, request_id: asked.friends[0].request_id }));
    expect(await (await call("/v1/friends", "GET", lone)).text()).toContain(poster.player_id);
  });

  it("hold the duel extra of a public duel's turns, show it while it runs, and at a stall pay the player who played and not the one who stopped", async () => {
    const [poster, lone, p1, p2] = await Promise.all([player(), player(), player(), player()]);
    await partner(p1, p2);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    let room = await ok<RoomSnapshotV2>(openRoom(poster, posted));
    const mine = (await ok<{ duel: DuelView }>(join(lone, posted))).duel;
    room = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", lone, { invite_code: mine.sides[0].invite_code }));
    await ok(join(p1, posted, "party"));
    const [a1, b1, mid] = await firstStage();
    const players = { [room.host_id]: poster, [room.guest_id ?? ""]: lone };
    const first = await ok<MutationV2 & { pollen?: { turn: Any } }>(call(`/v2/rooms/${room.room_id}/turns`, "POST", poster, turn(room, a1)));
    void players;
    const second = await ok<MutationV2 & { pollen?: { turn: Any } }>(call(`/v2/rooms/${first.room.room_id}/turns`, "POST", lone, turn(first.room, b1, mid)));
    for (const reply of [first, second]) {
      expect(reply.pollen?.turn).toHaveProperty("duel_held");
      expect(reply.pollen?.turn).not.toHaveProperty("duel");
    }
    // Turn replies show each player only the other's stand-in.
    expect(JSON.stringify(first)).not.toContain(lone.player_id);
    expect(JSON.stringify(second)).not.toContain(poster.player_id);
    const held = (second.pollen!.turn.duel_held as number);
    expect(held).toBeGreaterThan(0);
    expect((await detail(lone, posted)).held).toEqual({ amount: held, state: "running" });
    // Nobody plays for the stall time: the Relay's second stage opens with the guest, so the joiner stopped; the poster played theirs.
    expect((await boardDuel(posted.duel_id)).sides[0].turn).toBe(lone.player_id);
    await rewriteDuel(posted.duel_id, duel => { duel.accepted_ms! -= PUBLIC_STALL_MS; for (const side of duel.sides) if (side?.last_ms) side.last_ms -= PUBLIC_STALL_MS; duel.public!.posted_ms -= PUBLIC_STALL_MS; });
    const ended = await detail(poster, posted);
    expect([ended.duel.status, ended.duel.result?.reason]).toEqual(["unfinished", "stalled"]);
    const paid = (first.pollen!.turn.duel_held as number);
    expect(ended.held).toEqual({ amount: paid, state: "paid" });
    // A repeat answers the same and pays nothing twice.
    expect((await detail(poster, posted)).held).toEqual({ amount: paid, state: "paid" });
    expect((await detail(lone, posted)).held).toEqual({ amount: held, state: "forfeit", reason: "stopped" });
  });

  it("admit a joiner to the side's room only through the board, close a side its entered player left, and carry the duel on past an erasure", async () => {
    const [poster, lone, p1, p2, stranger] = await Promise.all([player(), player(), player(), player(), player()]);
    await partner(p1, p2);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    const room = await ok<RoomSnapshotV2>(openRoom(poster, posted));
    // Someone not seated is refused by the room, even holding the invite code.
    expect((await call("/v2/rooms/join", "POST", stranger, { invite_code: room.invite_code })).status).toBe(403);
    await ok(join(lone, posted));
    await ok(call("/v2/rooms/join", "POST", lone, { invite_code: room.invite_code }));
    await ok(join(p1, posted, "party"));
    // The joiner entered: leaving now ends side 0, and its seats never go back on the list.
    await ok(call(`/v1/duels/${RELAY}/${posted.duel_id}/leave`, "POST", lone, { schema_version: 1 }));
    const after = await boardDuel(posted.duel_id);
    expect([after.status, after.sides[0].left, after.sides[0].left_by, after.public!.forfeit]).toEqual(["running", true, 1, [1]]);
    expect((await detail(p1, posted)).duel.public?.seats_open).toBe(0);
    // The poster's account goes: their id leaves the duel, which carries on for the other pair.
    await ok(call("/v1/identity", "DELETE", poster));
    const erased = await boardDuel(posted.duel_id);
    expect(JSON.stringify(erased)).not.toContain(poster.player_id);
    expect((await detail(p1, posted)).duel.status).toBe("running");
  });

  it("share one limit of 10 with friend duels: posts past it are refused, and so is a friend challenge", async () => {
    const [a1, a2, b1, b2] = await Promise.all([player(), player(), player(), player()]);
    await partner(a1, a2); await partner(b1, b2); await befriend(a1, b1);
    for (let index = 0; index < 10; index++) await ok(post(a1, "alone", crypto.randomUUID(), UNLIMITED));
    expect((await ok<{ public: Any }>(call("/v1/duels", "GET", a1))).public).toMatchObject({ running: 10 });
    expect((await errorOf(post(a1, "alone", crypto.randomUUID(), UNLIMITED))).code).toBe("duel_limit_reached");
    const challenge = call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: RELAY });
    expect((await errorOf(challenge)).code).toBe("duel_limit_reached");
  });

  it("keep the directory's rows only while listed, and drop an erased player's rows", async () => {
    const [poster, lone] = await Promise.all([player(), player()]);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await listFor(lone, rows => rows.length === 1);
    await ok(call("/v1/identity", "DELETE", poster));
    const rows = await runInDurableObject(env.PUBLIC_DUEL_DIRECTORY.getByName(DIRECTORY_NAME), async (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM listings").toArray());
    expect(rows.map(row => row.data).join()).not.toContain(poster.player_id);
    expect((await listFor(lone, found => found.length === 0)).rows).toHaveLength(0);
    void posted;
  });
});

describe("public duel payout receipts", () => {
  const LATER = ["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead"];
  const receipts = async (id: string) => Object.keys((await boardDuel(id)).receipts ?? {}).sort();
  const lines = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) =>
    [...ledgerLines(ctx.storage, "duelextra:"), ...ledgerLines(ctx.storage, "duelwin:")].map(line => [line.key.split(":")[0], line.amount]));
  async function counted(account: Account, duel: { duel_id: string }) {
    const meter = countingEnv(Object.assign({ ...env }, ON) as Env);
    const answer = await ok<{ duel: DuelView; held?: Any; pay?: Any; win_bonus?: Any }>(call(`/v1/duels/${RELAY}/${duel.duel_id}`, "GET", account, undefined, Object.assign({ ...meter.env }, ON)));
    return { answer, calls: meter.calls };
  }
  /** The Relay's whole run, `slower` ticks more on its last turn: four turns, host first. */
  async function wholeRun(slower = 0): Promise<[0 | 1, Any, Any?][]> {
    const [a1, b1, mid] = await firstStage();
    const a2 = await rerecord({ ...secondA, catch_assistance: false, checkpoint_hash: mid.checkpoint_hash });
    const last = secondB.actions.length - 1;
    const actions = secondB.actions.map((action, index) => index === last ? { ...action, ticks: action.ticks + slower } : action);
    const replay_checks = secondB.replay_checks.map((check, index) => index === secondB.replay_checks.length - 1 ? { ...check, tick: check.tick + slower } : check);
    const b2 = await rerecord({ ...secondB, catch_assistance: false, actions, replay_checks, duration_ticks: secondB.duration_ticks + slower, checkpoint_hash: mid.checkpoint_hash, source_recording_hash: a2.recording_hash });
    const fin = await rehash({ ...final, previous_checkpoint_hash: mid.checkpoint_hash, a_recording_hash: a2.recording_hash, b_recording_hash: b2.recording_hash, proof: { previous_checkpoint: mid, a: a2, b: b2 } });
    return [[0, a1], [1, b1, mid], [1, a2], [0, b2, fin]];
  }
  async function playAll(room: RoomSnapshotV2, players: [Account, Account], run: [0 | 1, Any, Any?][]) {
    for (const [who, recording, checkpoint] of run) room = (await ok<MutationV2>(call(`/v2/rooms/${room.room_id}/turns`, "POST", players[who], turn(room, recording, checkpoint)))).room;
  }

  /** A public duel of four strangers played to its end: the poster and a lone joiner beat a pair by 40 ticks. */
  async function decided() {
    const [poster, lone, p1, p2] = await Promise.all([player(), player(), player(), player()]);
    await partner(p1, p2);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await ok<RoomSnapshotV2>(openRoom(poster, posted));
    const mine = (await ok<{ duel: DuelView }>(join(lone, posted))).duel;
    const joinedA = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", lone, { invite_code: mine.sides[0].invite_code }));
    const theirs = (await ok<{ duel: DuelView }>(join(p1, posted, "party"))).duel;
    const roomB = await ok<RoomSnapshotV2>(openRoom(p1, theirs));
    const joinedB = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", p2, { invite_code: roomB.invite_code }));
    await playAll(joinedA, [poster, lone], await wholeRun(0));
    await playAll(joinedB, [p1, p2], await wholeRun(40));
    return { poster, lone, p1, p2, posted };
  }

  it("pay each of the four their held extra and the winners their bonus once, then answer every later read from the duel row", async () => {
    const { poster, lone, p1, p2, posted } = await decided();
    const everyone = [poster, lone, p1, p2];
    const firsts = [];
    for (const account of everyone) {
      const first = await counted(account, posted);
      expect(first.answer.duel.status).toBe("decided");
      expect(first.calls).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead", "PLAYERS.duelRoomPay", "PLAYERS.settlePublicDuel", "LEADERBOARD_BOARDS.duelReceipt"]);
      expect(first.answer.held).toMatchObject({ state: "paid" });
      expect((first.answer.held as { amount: number }).amount).toBeGreaterThan(0);
      firsts.push(first.answer);
    }
    expect(await receipts(posted.duel_id)).toEqual(["0", "1", "2", "3"]);
    for (const [index, account] of everyone.entries()) {
      const later = await counted(account, posted);
      expect(later.calls).toEqual(LATER);
      expect({ held: later.answer.held, pay: later.answer.pay }).toEqual({ held: firsts[index].held, pay: firsts[index].pay });
    }
    // One held extra line each, and one win line for each winner, however many reads and lobbies.
    await Promise.all(everyone.map(account => ok(call("/v1/duels", "GET", account))));
    for (const [index, account] of [poster, lone].entries()) expect(await lines(account)).toEqual([["duelextra", (firsts[index].held as { amount: number }).amount], ["duelwin", 250]]);
    for (const account of [p1, p2]) expect((await lines(account)).map(line => line[0])).toEqual(["duelextra"]);
    const text = JSON.stringify((await boardDuel(posted.duel_id)).receipts);
    for (const account of everyone) expect(text).not.toContain(account.player_id);
  }, 60_000);

  it("keep no receipt while nothing held was summed yet, so a held turn whose credit lands late is still paid", async () => {
    const { lone, posted } = await decided();
    // The joiner's held turns have not reached their wallet yet (a credit that failed, waiting for the phone's turn claim).
    const wallet = env.PLAYERS.getByName(lone.player_id);
    const HELD = "kind='turn' AND json_extract(data,'$.receipt.turn.duel_held') > 0";
    const pending = await runInDurableObject(wallet, async (_, ctx) => {
      const rows = ctx.storage.sql.exec<{ claim_key: string; kind: string; amount: number; created_at: number; data: string }>("SELECT claim_key,kind,amount,created_at,data FROM pollen_claims WHERE " + HELD).toArray();
      ctx.storage.sql.exec("DELETE FROM pollen_claims WHERE " + HELD);
      return rows;
    });
    expect(pending.length).toBeGreaterThan(0);
    const early = await counted(lone, posted);
    expect(early.answer.held).toEqual({ amount: 0, state: "paid" });
    expect(early.calls).not.toContain("LEADERBOARD_BOARDS.duelReceipt");
    expect(await receipts(posted.duel_id)).toEqual([]);
    // The claims land; the next read sums and pays them, and only then keeps its receipt.
    await runInDurableObject(wallet, async (_, ctx) => {
      for (const item of pending) ctx.storage.sql.exec("INSERT INTO pollen_claims (claim_key,kind,amount,created_at,data) VALUES (?,?,?,?,?)", item.claim_key, item.kind, item.amount, item.created_at, item.data);
    });
    const held = pending.reduce((sum, item) => sum + (JSON.parse(item.data) as { receipt: { turn: { duel_held: number } } }).receipt.turn.duel_held, 0);
    const late = await counted(lone, posted);
    expect(late.answer.held).toEqual({ amount: held, state: "paid" });
    expect(late.calls).toContain("LEADERBOARD_BOARDS.duelReceipt");
    expect((await lines(lone))[0]).toEqual(["duelextra", held]);
    expect((await counted(lone, posted)).calls).toEqual(LATER);
  }, 60_000);

  it("keep no receipt for a side whose room never finished its run, which may still hold duel turns, and still pay once", async () => {
    const [poster, lone, p1, p2] = await Promise.all([player(), player(), player(), player()]);
    await partner(p1, p2);
    const posted = (await ok<{ duel: DuelView }>(post(poster))).duel;
    await ok<RoomSnapshotV2>(openRoom(poster, posted));
    const mine = (await ok<{ duel: DuelView }>(join(lone, posted))).duel;
    const room = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", lone, { invite_code: mine.sides[0].invite_code }));
    await ok(join(p1, posted, "party"));
    const [a1] = await firstStage();
    const first = await ok<MutationV2 & { pollen?: { turn: Any } }>(call(`/v2/rooms/${room.room_id}/turns`, "POST", poster, turn(room, a1)));
    await rewriteDuel(posted.duel_id, duel => { duel.accepted_ms! -= PUBLIC_STALL_MS; for (const side of duel.sides) if (side?.last_ms) side.last_ms -= PUBLIC_STALL_MS; duel.public!.posted_ms -= PUBLIC_STALL_MS; });
    const held = first.pollen!.turn.duel_held as number;
    for (let read = 0; read < 2; read++) {
      const seen = await counted(poster, posted);
      expect(seen.answer.held).toEqual({ amount: held, state: "paid" });
      expect(seen.calls).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead", "PLAYERS.duelRoomPay", "PLAYERS.settlePublicDuel"]);
    }
    expect(await lines(poster)).toEqual([["duelextra", held]]);
    // The pair that never opened a room has nothing that can still change: kept on its first read.
    expect((await counted(p1, posted)).calls).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead", "PLAYERS.settlePublicDuel", "LEADERBOARD_BOARDS.duelReceipt"]);
    expect((await counted(p1, posted)).calls).toEqual(LATER);
    expect(await receipts(posted.duel_id)).toEqual(["2"]);
  }, 60_000);
});
