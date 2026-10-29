import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { CHAPTERS } from "../src/v2/chapters";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { boardKeys, developerBest } from "../src/leaderboards/boards";
import { deriveJobToken } from "../src/leaderboards/job-token";
import { forgetViews } from "../src/leaderboards/view-cache";
import { forgetReplays } from "../src/leaderboards/replays";
import type { DuelView } from "../src/duels/model";
import { countingEnv } from "./meter";
import { configJson } from "./config";
import { bytesDigest, decodeBlob } from "../src/blob-codec";
import { dropRunCopies } from "../src/duels/their-run-sweep";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

// Duels end to end through the Worker: parties, challenges, rooms, turns, the replay check,
// pay and erasure. Synthetic identities only: every account is made by POST /v1/identity here.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Any = Record<string, unknown>;
type Lobby = { party: { partner: string | null; intact: boolean; invites_in: string[]; invite_out: string | null }; duels: DuelView[] };
const OPERATOR = "o".repeat(43);
const SECRET = "synthetic-pollen-secret-for-tests-only-0002";
const ON = { CONFIG: configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN"] }), POLLEN_SECRET: SECRET, SAFETY_OPERATOR_TOKEN: OPERATOR };
const NO_DUELS = { ...ON, CONFIG: configJson({ features: ["LEADERBOARDS", "POLLEN_EARN"] }) };
const RELAY = "relay-isles@2";
const RELAY_KEY = { level_id: "relay-isles", level_version: 2, definition_hash: CHAPTERS[0].adapter.key.definition_hash };
const DAY = 86_400_000;
let address = 0;

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string> = ON, headers: Record<string, string> = {}, base: Env = env): Promise<Response> {
  return worker.fetch(new Request("https://duels.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + (++address % 250), "X-AfterYou-Pollen": "1",
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), Object.assign({ ...base }, vars) as Env);
}
async function ok<T = Any>(response: Promise<Response>, status = 200): Promise<T> {
  const answer = await response;
  const text = await answer.text();
  expect(answer.status, text).toBe(status);
  return JSON.parse(text) as T;
}
async function create(): Promise<Account> { return ok<Account>(call("/v1/identity", "POST", undefined, {}), 201); }
async function befriend(a: Account, b: Account): Promise<void> {
  const { request_id } = await ok<{ request_id: string }>(call("/v1/friends/request", "POST", a, { schema_version: 1, friend_code: b.player_id }));
  await ok(call("/v1/friends/accept", "POST", b, { schema_version: 1, player_id: a.player_id, request_id }));
}
async function partner(a: Account, b: Account): Promise<void> {
  await ok(call("/v1/duels/party/invite", "POST", a, { schema_version: 1, friend: b.player_id }));
  await ok(call("/v1/duels/party/accept", "POST", b, { schema_version: 1, from: a.player_id }));
}
const lobby = (account: Account, vars = ON) => ok<Lobby>(call("/v1/duels", "GET", account, undefined, vars));
/** Old enough, with turns beside two partners, as the board's account rule wants. */
async function season(account: Account): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => {
    ctx.storage.sql.exec("UPDATE identity SET data=json_set(data,'$.created_at',?) WHERE id=1", new Date(Date.now() - 8 * DAY).toISOString());
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS room_index (room_id TEXT PRIMARY KEY, api_version INTEGER NOT NULL, state TEXT NOT NULL, activity_ms INTEGER NOT NULL, observed_at INTEGER NOT NULL, checked_at INTEGER NOT NULL, entry TEXT)");
    for (let index = 0; index < 2; index++) {
      const entry = { ok: true, value: { membership: { host_id: account.player_id, guest_id: `partner${index}`.padEnd(22, "x"), you_are_host: true }, revision: 5 } };
      ctx.storage.sql.exec("INSERT INTO room_index VALUES (?,?,?,?,?,?,?)", `room${index}`.padEnd(22, "r"), 2, "finished", 0, 0, 0, JSON.stringify(entry));
    }
  });
}

async function rerecord(input: Any): Promise<Any> { const body = { ...input }; delete body.recording_hash; return { ...input, recording_hash: await digest(canonicalJson(body)) }; }
async function rehash(input: Any): Promise<Any> { const body = { ...input }; delete body.checkpoint_hash; delete body.proof; return { ...input, checkpoint_hash: await digest(canonicalJson(body)) }; }
/**
 * The Relay fixtures, every hash and link redone, with `slower` more ticks on the last turn and
 * catch assistance as asked (off, as a duel's room takes only unassisted turns). The server checks structure and hashes, not physics.
 */
async function relayRun(slower = 0, assisted = false) {
  const a1 = await rerecord({ ...firstA, catch_assistance: assisted });
  const b1 = await rerecord({ ...firstB, catch_assistance: assisted, source_recording_hash: a1.recording_hash });
  const mid = await rehash({ ...middle, a_recording_hash: a1.recording_hash, b_recording_hash: b1.recording_hash, proof: { ...(middle.proof as Any), a: a1, b: b1 } });
  const a2 = await rerecord({ ...secondA, catch_assistance: assisted, checkpoint_hash: mid.checkpoint_hash });
  const actions = secondB.actions.map((action, index) => index === secondB.actions.length - 1 ? { ...action, ticks: action.ticks + slower } : action);
  const replay_checks = secondB.replay_checks.map((check, index) => index === secondB.replay_checks.length - 1 ? { ...check, tick: check.tick + slower } : check);
  const b2 = await rerecord({ ...secondB, catch_assistance: assisted, actions, replay_checks, duration_ticks: secondB.duration_ticks + slower, checkpoint_hash: mid.checkpoint_hash, source_recording_hash: a2.recording_hash });
  const fin = await rehash({ ...final, previous_checkpoint_hash: mid.checkpoint_hash, a_recording_hash: a2.recording_hash, b_recording_hash: b2.recording_hash, proof: { previous_checkpoint: mid, a: a2, b: b2 } });
  return { turns: [[0, a1], [1, b1, mid], [1, a2], [0, b2, fin]] as [0 | 1, Any, Any?][], ticks: [a1, b1, a2, b2].reduce((sum, turn) => sum + (turn.duration_ticks as number), 0) };
}
function turn(room: RoomSnapshotV2, recording: unknown, checkpoint?: unknown) {
  return { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint === undefined ? {} : { checkpoint }) };
}
/** Opens the side's room for `host` through the create route with the duel field. */
function openRoom(host: Account, duel: DuelView, key = crypto.randomUUID(), vars = ON) {
  return call("/v2/rooms", "POST", host, { idempotency_key: key, ...RELAY_KEY, duel: { duel_id: duel.duel_id, board: duel.board } }, vars);
}
/** Plays the whole run in `room` with `players` [host, guest]; returns each turn's reply. */
async function play(room: RoomSnapshotV2, players: [Account, Account], run: Awaited<ReturnType<typeof relayRun>>): Promise<(MutationV2 & { pollen?: Any })[]> {
  const replies: (MutationV2 & { pollen?: Any })[] = [];
  for (const [who, recording, checkpoint] of run.turns) {
    const reply = await ok<MutationV2 & { pollen?: Any }>(call(`/v2/rooms/${room.room_id}/turns`, "POST", players[who], turn(room, recording, checkpoint)));
    replies.push(reply);
    room = reply.room;
  }
  return replies;
}
const job = async () => ok<{ entries: Any[] }>(call("/operator/leaderboards/pending", "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + await deriveJobToken(OPERATOR) }));
async function verdicts(entries: Any[], valid: (entry: Any) => boolean) {
  return ok(call("/operator/leaderboards/verdicts", "POST", undefined, { schema_version: 1, verdicts: entries.map(entry => ({ board: entry.board, entry_id: entry.entry_id, proof_hash: entry.proof_hash,
    valid: valid(entry), measured_ticks: entry.ticks, reason: valid(entry) ? "" : "replay_failed" })) }, ON, { Authorization: "Bearer " + await deriveJobToken(OPERATOR) }));
}
const detail = (account: Account, duel: DuelView) => ok<{ duel: DuelView; pay?: Any; win_bonus?: Any }>(call(`/v1/duels/${duel.board}/${duel.duel_id}`, "GET", account));

const shared = env as unknown as Record<string, unknown>;
beforeEach(async () => { shared.POLLEN_SECRET = SECRET; await forgetViews(boardKeys()); forgetReplays(); });
afterEach(async () => { delete shared.POLLEN_SECRET; await reset(); });

/** Four friends in two parties: A1 + A2 and B1 + B2, with A1 and B1 friends. */
async function pairs(seasoned = false) {
  const [a1, a2, b1, b2] = await Promise.all([create(), create(), create(), create()]);
  await befriend(a1, a2); await befriend(b1, b2); await befriend(a1, b1);
  await partner(a1, a2); await partner(b1, b2);
  if (seasoned) for (const account of [a1, a2, b1, b2]) await season(account);
  return { a1, a2, b1, b2 };
}
async function challenge(from: Account, to: Account, key = crypto.randomUUID()) {
  return call("/v1/duels/challenge", "POST", from, { schema_version: 1, idempotency_key: key, friend: to.player_id, board: RELAY });
}

describe("duels while off", () => {
  it("answer nothing and advertise nothing without DUELS, or without LEADERBOARDS", async () => {
    const a = await create();
    expect((await call("/v1/duels", "GET", a, undefined, NO_DUELS)).status).toBe(404);
    expect((await call("/v1/duels", "GET", a, undefined, { ...ON, CONFIG: configJson({ features: ["DUELS"] }) })).status).toBe(404);
    const caps = await ok<Any>(call("/v2/capabilities", "GET", a, undefined, NO_DUELS, { "X-AfterYou-Duels": "1" }));
    expect(caps).not.toHaveProperty("duels_version");
    expect(await ok<Any>(call("/v2/capabilities", "GET", a, undefined, ON, { "X-AfterYou-Duels": "1" }))).toHaveProperty("duels_version", 1);
    expect(await ok<Any>(call("/v2/capabilities", "GET", a, undefined, ON))).not.toHaveProperty("duels_version");
  });
});

describe("duel parties", () => {
  it("form only between friends, with the friend's consent, and a new party leaves the old one", async () => {
    const [a, b, c, stranger] = await Promise.all([create(), create(), create(), create()]);
    await befriend(a, b); await befriend(a, c);
    expect((await call("/v1/duels/party/invite", "POST", a, { schema_version: 1, friend: stranger.player_id })).status).toBe(403);
    await ok(call("/v1/duels/party/invite", "POST", a, { schema_version: 1, friend: b.player_id }));
    expect((await lobby(b)).party.invites_in).toEqual([a.player_id]);
    expect((await lobby(a)).party).toMatchObject({ partner: null, invite_out: b.player_id });
    await ok(call("/v1/duels/party/accept", "POST", b, { schema_version: 1, from: a.player_id }));
    // Accepting twice is safe.
    await ok(call("/v1/duels/party/accept", "POST", b, { schema_version: 1, from: a.player_id }));
    expect((await lobby(a)).party).toMatchObject({ partner: b.player_id, intact: true, invite_out: null });
    expect((await lobby(b)).party).toMatchObject({ partner: a.player_id, intact: true, invites_in: [] });
    await partner(a, c);
    expect((await lobby(a)).party).toMatchObject({ partner: c.player_id, intact: true });
    expect((await lobby(b)).party.partner).toBeNull();
    // An invite taken back can no longer be accepted.
    await ok(call("/v1/duels/party/invite", "POST", b, { schema_version: 1, friend: a.player_id }));
    await ok(call("/v1/duels/party/cancel", "POST", b, { schema_version: 1 }));
    expect((await call("/v1/duels/party/accept", "POST", a, { schema_version: 1, from: b.player_id })).status).toBe(409);
    await ok(call("/v1/duels/party/leave", "POST", c, { schema_version: 1 }));
    expect((await lobby(a)).party.partner).toBeNull();
  });
});

describe("friend duels", () => {
  it("run from challenge to result, with rooms, turns, the replay check, pay and the win bonus", async () => {
    const { a1, a2, b1, b2 } = await pairs(true);
    const key = crypto.randomUUID();
    const sent = await ok<{ duel: DuelView }>(challenge(a1, b1, key));
    // A retried challenge answers the same duel.
    expect((await ok<{ duel: DuelView }>(challenge(a1, b1, key))).duel.duel_id).toBe(sent.duel.duel_id);
    expect((await lobby(b2)).duels.map(duel => duel.status)).toEqual(["challenged"]);
    // Accepting twice, from either member, answers the running duel.
    await ok(call(`/v1/duels/${RELAY}/${sent.duel.duel_id}/accept`, "POST", b2, { schema_version: 1 }));
    const accepted = await ok<{ duel: DuelView }>(call(`/v1/duels/${RELAY}/${sent.duel.duel_id}/accept`, "POST", b1, { schema_version: 1 }));
    expect(accepted.duel).toMatchObject({ status: "running", eligible: true, mine: 1 });
    // Only the duel's own pair sees ids across pairs where a friendship was checked.
    expect(accepted.duel.sides[0].members).toEqual([a1.player_id, null]);

    // Both members of a pair open the duel at once: one room is the pair's, the other phone joins it.
    const duel = sent.duel;
    const [first, second] = await Promise.all([openRoom(a1, duel), openRoom(a2, duel)]);
    expect([first.status, second.status].sort()).toEqual([200, 409]);
    const roomA = await (first.status === 200 ? first : second).json<RoomSnapshotV2>();
    const hostA = roomA.host_id === a1.player_id ? a1 : a2, guestA = hostA === a1 ? a2 : a1;
    const view = (await detail(guestA, duel)).duel;
    expect(view.sides[0]).toMatchObject({ room_id: roomA.room_id, hosting: false });
    // Nobody outside the pair may join its room.
    expect((await call("/v2/rooms/join", "POST", b1, { invite_code: view.sides[0].invite_code })).status).toBe(403);
    const joinedA = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guestA, { invite_code: view.sides[0].invite_code }));
    const roomB = await ok<RoomSnapshotV2>(openRoom(b1, duel));
    const joinedB = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", b2, { invite_code: (await detail(b2, duel)).duel.sides[1]!.invite_code }));
    expect(roomB.room_id).toBe(joinedB.room_id);

    const fast = await relayRun(0), slow = await relayRun(40);
    const repliesA = await play(joinedA, [hostA, guestA], fast);
    // A friend duel turn pays the premium beside the plain amount.
    const paid = repliesA[0].pollen as { turn: Any } | undefined;
    expect(paid?.turn).toMatchObject({ kind: "bank", duel_percent: 50 });
    expect(paid!.turn.total).toBe((paid!.turn.amount as number) + (paid!.turn.bloom_extra as number) + (paid!.turn.boost as number) + (paid!.turn.duel as number));
    let seen = (await lobby(b1)).duels[0];
    expect(seen.sides[0]).toMatchObject({ steps: 4, ticks: fast.ticks, finished: true, check: "waiting" });
    await play(joinedB, [b1, b2], slow);
    seen = (await lobby(a2)).duels[0];
    expect(seen).toMatchObject({ status: "running" });
    expect(seen.sides[1]).toMatchObject({ ticks: slow.ticks, finished: true });

    // The replay job gets both runs once each, checked like any board run.
    const entries = (await job()).entries;
    expect(entries.map(entry => entry.ticks).sort()).toEqual([fast.ticks, slow.ticks].sort());
    // Each comes in the shared blob format, never as a raw checkpoint, and decodes to the bytes its hash names.
    for (const entry of entries) {
      expect(entry).not.toHaveProperty("checkpoint");
      const body = Uint8Array.from(atob(entry.body as string), char => char.charCodeAt(0));
      const bytes = await decodeBlob(body, entry.byte_length as number);
      expect(bytes && await bytesDigest(bytes)).toBe(entry.proof_hash);
      expect(JSON.parse(new TextDecoder().decode(bytes!)).stage_index).toBe(2);
    }
    await verdicts(entries, () => true);
    const won = await detail(a1, duel);
    expect(won.duel.result).toMatchObject({ outcome: "won", reason: "faster", margin_ticks: 40 });
    expect(won.win_bonus).toEqual({ amount: 250, counted: true });
    expect(won.pay).toMatchObject({ turns: 2 });
    // A repeat answers the same bonus, and the loser gets none.
    expect((await detail(a1, duel)).win_bonus).toEqual({ amount: 250, counted: true });
    const lost = await detail(b1, duel);
    expect(lost.duel.result!.outcome).toBe("lost");
    expect(lost.win_bonus).toBeUndefined();
    await lobby(a2);
    expect((await detail(a2, duel)).win_bonus).toEqual({ amount: 250, counted: true });
    // A second win against the same pair the same week counts at 0.
    const again = await ok<{ duel: DuelView }>(challenge(a1, b1));
    await ok(call(`/v1/duels/${RELAY}/${again.duel.duel_id}/accept`, "POST", b1, { schema_version: 1 }));
    await ok(call(`/v1/duels/${RELAY}/${again.duel.duel_id}/leave`, "POST", b1, { schema_version: 1 }));
    const replay = await ok<RoomSnapshotV2>(openRoom(a1, again.duel));
    const secondJoined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: replay.invite_code }));
    await play(secondJoined, [a1, a2], fast);
    await verdicts((await job()).entries, () => true);
    const repeat = await detail(a1, again.duel);
    expect(repeat.duel.result).toMatchObject({ outcome: "won", reason: "left" });
    // A win the other pair handed over by leaving pays no bonus: only a win where both runs passed does.
    expect(repeat.win_bonus).toBeUndefined();
  }, 60_000);

  it("never take a Forgiving catches turn in a duel's room, which says it is one, while an ordinary room still does", async () => {
    const { a1, a2, b1 } = await pairs(true);
    const sent = (await ok<{ duel: DuelView }>(challenge(a1, b1))).duel;
    await ok(call(`/v1/duels/${RELAY}/${sent.duel_id}/accept`, "POST", b1, { schema_version: 1 }));
    const room = await ok<RoomSnapshotV2>(openRoom(a1, sent));
    expect(room.duel).toBe(true);
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: room.invite_code }));
    expect(joined.duel).toBe(true);
    const assisted = await relayRun(0, true);
    const refused = await call(`/v2/rooms/${joined.room_id}/turns`, "POST", a1, turn(joined, assisted.turns[0][1]));
    expect(refused.status).toBe(422);
    expect((await refused.json<{ error: { code: string } }>()).error.code).toBe("duel_turn_assisted");
    // Nothing moved: the duel still reads no steps, and the same turn unassisted is taken.
    expect((await lobby(a1)).duels[0].sides[0]).toMatchObject({ steps: 0, ticks: 0 });
    const plain = await relayRun(0);
    await ok(call(`/v2/rooms/${joined.room_id}/turns`, "POST", a1, turn(joined, plain.turns[0][1])));
    // An ordinary room is no duel's room and keeps the player's setting.
    const ordinary = await ok<RoomSnapshotV2>(call("/v2/rooms", "POST", a1, { idempotency_key: crypto.randomUUID(), ...RELAY_KEY }));
    expect(ordinary).not.toHaveProperty("duel");
    const guest = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: ordinary.invite_code }));
    await ok(call(`/v2/rooms/${guest.room_id}/turns`, "POST", a1, turn(guest, assisted.turns[0][1])));
  });

  it("refuse a challenge to a pair that dissolved, and a duel room for the wrong chapter or a hard one", async () => {
    const { a1, b1, b2 } = await pairs();
    const sent = (await ok<{ duel: DuelView }>(challenge(a1, b1))).duel;
    await ok(call("/v1/duels/party/leave", "POST", b2, { schema_version: 1 }));
    expect((await call(`/v1/duels/${RELAY}/${sent.duel_id}/accept`, "POST", b1, { schema_version: 1 })).status).toBe(409);
    expect((await lobby(a1)).duels[0].status).toBe("pair_gone");
    expect((await challenge(a1, b1)).status).toBe(409);
    const other = CHAPTERS[1].adapter.key;
    const wrong = await call("/v2/rooms", "POST", a1, { idempotency_key: crypto.randomUUID(), ...other, duel: { duel_id: sent.duel_id, board: RELAY } });
    expect(wrong.status).toBe(409);
    const hard = await call("/v2/rooms", "POST", a1, { idempotency_key: crypto.randomUUID(), ...RELAY_KEY, mode: "hard", duel: { duel_id: sent.duel_id, board: RELAY } });
    expect(hard.status).toBe(422);
  });

  it("decline with Not now, keep to three at once, and need a party on both sides", async () => {
    const { a1, b1, b2 } = await pairs();
    // A stranger's party is never asked about.
    const stranger = await create();
    expect((await challenge(a1, stranger)).status).toBe(403);
    const lone = await create();
    await befriend(a1, lone);
    expect((await challenge(a1, lone)).status).toBe(409);
    const sent = (await ok<{ duel: DuelView }>(challenge(a1, b1))).duel;
    const declined = await ok<{ duel: DuelView }>(call(`/v1/duels/${RELAY}/${sent.duel_id}/decline`, "POST", b2, { schema_version: 1 }));
    expect(declined.duel.status).toBe("declined");
    expect((await call(`/v1/duels/${RELAY}/${sent.duel_id}/accept`, "POST", b1, { schema_version: 1 })).status).toBe(409);
    const boards = CHAPTERS.slice(1, 5).map(row => `${row.adapter.key.level_id}@${row.adapter.key.level_version}`);
    const statuses: number[] = [];
    for (const key of boards) statuses.push((await call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: key })).status);
    expect(statuses).toEqual([200, 200, 200, 409]);
  });

  it("post an unassisted duel run to the Fastest pair board with its raw time", async () => {
    const { a1, a2, b1 } = await pairs(true);
    const sent = (await ok<{ duel: DuelView }>(challenge(a1, b1))).duel;
    await ok(call(`/v1/duels/${RELAY}/${sent.duel_id}/accept`, "POST", b1, { schema_version: 1 }));
    const room = await ok<RoomSnapshotV2>(openRoom(a1, sent));
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: room.invite_code }));
    const run = await relayRun(0);
    await play(joined, [a1, a2], run);
    const entries = (await job()).entries;
    // One entry for the run, though both the board and the duel wait on it.
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({ ticks: run.ticks });
    expect(entries[0]).not.toHaveProperty("duel");
  });

  it("let a pair that left hand the win to the other once its run passes, and end at erasure", async () => {
    const { a1, a2, b1, b2 } = await pairs(true);
    const sent = (await ok<{ duel: DuelView }>(challenge(a1, b1))).duel;
    await ok(call(`/v1/duels/${RELAY}/${sent.duel_id}/accept`, "POST", b1, { schema_version: 1 }));
    expect((await ok<{ duel: DuelView }>(call(`/v1/duels/${RELAY}/${sent.duel_id}/leave`, "POST", b2, { schema_version: 1 }))).duel.sides[1]!.left).toBe(true);
    expect((await call("/v1/identity", "DELETE", a2)).status).toBe(200);
    const after = (await lobby(a1));
    expect(after.party).toMatchObject({ partner: null });
    expect(after.duels[0]).toMatchObject({ status: "unfinished", result: { outcome: "none", reason: "erased" } });
  });
});

describe("duel erasure", () => {
  it("reaches a party even while duels and leaderboards are off", async () => {
    const [a, b] = await Promise.all([create(), create()]);
    await befriend(a, b);
    await partner(a, b);
    expect((await call("/v1/identity", "DELETE", a, undefined, { CONFIG: configJson({}) })).status).toBe(200);
    const left = await env.LEADERBOARD_MEMBERS.getByName(b.player_id).partyRead(Date.now());
    expect(left.partner).toBeNull();
  });
});

describe("ghost races", () => {
  it("race a recorded time and are decided the moment the pair finishes, paying like normal turns", async () => {
    const { a1, a2 } = await pairs();
    const ghosts = await ok<{ boards: { board: string; developer: number | null; top: unknown[] }[] }>(call("/v1/duels/ghosts", "GET", a1));
    expect(ghosts.boards.find(item => item.board === RELAY)!.developer).toBe(developerBest(RELAY));
    const started = (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }))).duel;
    expect(started).toMatchObject({ kind: "ghost", status: "running", ghost: { source: "developer", ticks: developerBest(RELAY) } });
    const room = await ok<RoomSnapshotV2>(openRoom(a2, started));
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a1, { invite_code: room.invite_code }));
    const run = await relayRun(0);
    const replies = await play(joined, [a2, a1], run);
    expect((replies[0].pollen as { turn: Any }).turn).not.toHaveProperty("duel");
    const done = (await lobby(a1)).duels[0];
    const ghostTicks = developerBest(RELAY)!;
    expect(done).toMatchObject({ status: "decided", result: { outcome: run.ticks < ghostTicks ? "won" : run.ticks > ghostTicks ? "lost" : "draw" } });
    expect((await detail(a1, started)).win_bonus).toBeUndefined();
  });
});

describe("the other pair's run", () => {
  type Run = { schema_version: number; duel_id: string; board: string; digest: string; byte_length: number; body: string };
  const theirRun = (account: Account, duel: DuelView) => call(`/v1/duels/${duel.board}/${duel.duel_id}/their-run`, "GET", account);
  const ack = (account: Account, duel: DuelView, digest: string) => call(`/v1/duels/${duel.board}/${duel.duel_id}/their-run/ack`, "POST", account, { schema_version: 1, digest });
  const code = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
  /** A friend duel with both rooms made, and with `finish` the pairs' runs played: A's (fast), then B's (slow). */
  async function duelWithRooms(finish: ("a" | "b")[] = ["a", "b"]) {
    const accounts = await pairs(true);
    const { a1, a2, b1, b2 } = accounts;
    const duel = (await ok<{ duel: DuelView }>(challenge(a1, b1))).duel;
    await ok(call(`/v1/duels/${RELAY}/${duel.duel_id}/accept`, "POST", b1, { schema_version: 1 }));
    const roomA = await ok<RoomSnapshotV2>(openRoom(a1, duel));
    const joinedA = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: roomA.invite_code }));
    const roomB = await ok<RoomSnapshotV2>(openRoom(b1, duel));
    const joinedB = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", b2, { invite_code: roomB.invite_code }));
    if (finish.includes("a")) await play(joinedA, [a1, a2], await relayRun(0));
    if (finish.includes("b")) await play(joinedB, [b1, b2], await relayRun(40));
    return { ...accounts, duel, roomA, roomB };
  }
  async function decoded(run: Run): Promise<string> {
    const body = Uint8Array.from(atob(run.body), char => char.charCodeAt(0));
    const bytes = await decodeBlob(body, run.byte_length);
    expect(bytes && await bytesDigest(bytes)).toBe(run.digest);
    return new TextDecoder().decode(bytes!);
  }

  it("is the other pair's whole run, with no player or room id, once the duel is over for the pair asking", async () => {
    const { a1, a2, b1, b2, duel, roomA, roomB } = await duelWithRooms(["a"]);
    // B has not finished: A's run waits, and A may not see B's unfinished one.
    expect((await theirRun(b1, duel)).status).toBe(409);
    expect((await theirRun(a1, duel)).status).toBe(404);
    const stranger = await create();
    expect((await theirRun(stranger, duel)).status).toBe(404);
    await play(await ok<RoomSnapshotV2>(call(`/v2/rooms/${roomB.room_id}`, "GET", b1)), [b1, b2], await relayRun(40));
    const run = await ok<Run>(theirRun(b1, duel));
    expect(Object.keys(run).sort()).toEqual(["board", "body", "byte_length", "digest", "duel_id", "schema_version"]);
    expect(run).toMatchObject({ schema_version: 1, duel_id: duel.duel_id, board: RELAY });
    const text = await decoded(run);
    expect(JSON.parse(text).stage_index).toBe(2);
    for (const id of [a1.player_id, a2.player_id, b1.player_id, b2.player_id, roomA.room_id, roomB.room_id]) expect(text.includes(id)).toBe(false);
    // The same bytes every time, and to both of B.
    expect((await ok<Run>(theirRun(b2, duel))).digest).toBe(run.digest);
    expect((await ok<Run>(theirRun(a1, duel))).digest).not.toBe(run.digest);
  }, 60_000);

  it("goes once all four have it: the own pair through replay transfer, the other pair by acknowledgements in any order", async () => {
    const { a1, a2, b1, b2, duel, roomA } = await duelWithRooms();
    const run = await ok<Run>(theirRun(b1, duel));
    // A keeps its own run through replay transfer; the room compacts, and B's copy is untouched.
    const transfer = await ok<{ manifest: { epoch: number; archive_hash: string } }>(call(`/v2/rooms/${roomA.room_id}/replay-transfer`, "GET", a1));
    const key = { schema_version: 1, epoch: transfer.manifest.epoch, archive_hash: transfer.manifest.archive_hash };
    await ok(call(`/v2/rooms/${roomA.room_id}/replay-transfer/ack`, "POST", a2, key));
    expect((await ok<{ transferred: boolean }>(call(`/v2/rooms/${roomA.room_id}/replay-transfer/ack`, "POST", a1, key))).transferred).toBe(true);
    expect((await ok<Run>(theirRun(b2, duel))).digest).toBe(run.digest);
    // Out of order: B2 first, then a wrong digest, then B1; repeats stay ok.
    expect(await ok(ack(b2, duel, run.digest))).toEqual({ schema_version: 1, kept: true });
    expect(await ok(ack(b2, duel, run.digest))).toEqual({ schema_version: 1, kept: true });
    const wrong = await ack(b1, duel, "0".repeat(64));
    expect([wrong.status, await code(wrong)]).toEqual([409, "their_run_mismatch"]);
    expect(await ok(ack(b1, duel, run.digest))).toEqual({ schema_version: 1, kept: false });
    expect(await ok(ack(b1, duel, run.digest))).toEqual({ schema_version: 1, kept: false });
    const gone = await theirRun(b1, duel);
    expect([gone.status, await code(gone)]).toEqual([410, "their_run_gone"]);
    // Only a player of the duel acknowledges, and only a well formed digest.
    expect((await ack(await create(), duel, run.digest)).status).toBe(404);
    expect((await call(`/v1/duels/${RELAY}/${duel.duel_id}/their-run/ack`, "POST", b1, { schema_version: 1, digest: "x" })).status).toBe(400);
  }, 60_000);

  it("goes a year after the duel ends when nobody took it, by the hourly sweep", async () => {
    const { b1, a1, duel, roomA, roomB } = await duelWithRooms();
    await verdicts((await job()).entries, () => true);
    expect((await lobby(a1)).duels[0].status).toBe("decided");
    const stub = env.LEADERBOARD_BOARDS.getByName(RELAY);
    // Not due yet: nothing to sweep, and the run is there.
    expect((await stub.pendingWork(0, 0, Date.now() + 364 * DAY)).copies).toBeUndefined();
    await ok(theirRun(b1, duel));
    const due = (await stub.pendingWork(0, 0, Date.now() + 366 * DAY)).copies!;
    expect(due.map(item => item.room_id).sort()).toEqual([roomA.room_id, roomB.room_id].sort());
    expect(due.every(item => item.duel_id === duel.duel_id && item.player === null)).toBe(true);
    await dropRunCopies(env, RELAY, due);
    expect((await theirRun(b1, duel)).status).toBe(410);
    expect((await theirRun(a1, duel)).status).toBe(410);
    // Each room answered: no row is left, and a second sweep is a no-op.
    expect((await stub.pendingWork(0, 0, Date.now() + 366 * DAY)).copies).toBeUndefined();
    await dropRunCopies(env, RELAY, due);
    // A copy found past its keep on a download goes then too, even with no sweep.
    const later = await duelWithRooms();
    await runInDurableObject(env.ROOMS_V2.getByName(later.roomA.room_id), async (instance: { theirRun(viewer: string, now: number): Promise<{ ok: boolean; code?: string }> }) => {
      expect(await instance.theirRun(later.b1.player_id, Date.now() + 396 * DAY)).toMatchObject({ ok: false, code: "their_run_gone" });
    });
    expect((await theirRun(later.b1, later.duel)).status).toBe(410);
  }, 90_000);

  it("costs the lobby nothing, and a download or an acknowledgement two requests, the board and one room", async () => {
    const { a1, b1, duel } = await duelWithRooms();
    const counted = async (work: (target: Env) => Promise<Response>) => {
      const meter = countingEnv(Object.assign({ ...env }, ON) as Env);
      const answer = await work(meter.env);
      expect(answer.status, await answer.clone().text()).toBe(200);
      return { answer, calls: meter.calls };
    };
    const read = await counted(target => call("/v1/duels", "GET", a1, undefined, ON, {}, target));
    expect(read.calls.filter(name => name.startsWith("ROOMS_V2"))).toEqual([]);
    const fetched = await counted(target => call(`/v1/duels/${duel.board}/${duel.duel_id}/their-run`, "GET", b1, undefined, ON, {}, target));
    const run = await fetched.answer.json<Run>();
    const acked = await counted(target => call(`/v1/duels/${duel.board}/${duel.duel_id}/their-run/ack`, "POST", b1, { schema_version: 1, digest: run.digest }, ON, {}, target));
    // Measured 2026-10-29: each is the board's read and the room's own call, beside the sign-in (3 in all); the lobby stays at 4.
    expect(fetched.calls.filter(name => /LEADERBOARD_BOARDS|ROOMS_V2/.test(name))).toEqual(["LEADERBOARD_BOARDS.duelRead", "ROOMS_V2.theirRun"]);
    expect(acked.calls.filter(name => /LEADERBOARD_BOARDS|ROOMS_V2/.test(name))).toEqual(["LEADERBOARD_BOARDS.duelRead", "ROOMS_V2.acknowledgeTheirRun"]);
  }, 60_000);

  it("drops an erased player from the other room's list and the copy's waiting list, and a run's copy when a player of it goes", async () => {
    // B has not finished when B2 goes: A's copy waits for B1 alone, and A's room no longer names B2.
    const { a1, a2, b1, b2, duel, roomA } = await duelWithRooms(["a"]);
    expect((await call("/v1/identity", "DELETE", b2)).status).toBe(200);
    const linkOf = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (instance: { duelLinkOf(): { others?: string[] } | null }) => instance.duelLinkOf());
    expect((await linkOf(roomA.room_id))?.others).toEqual([b1.player_id]);
    const run = await ok<Run>(theirRun(b1, duel));
    expect(await ok(ack(b1, duel, run.digest))).toEqual({ schema_version: 1, kept: false });
    expect((await theirRun(b1, duel)).status).toBe(410);
    // A player of the run going takes its copy with it, though the room stays for the partner.
    const other = await duelWithRooms();
    await runInDurableObject(env.ROOMS_V2.getByName(other.roomA.room_id), async (instance: { dropTheirRun(duelId: string, player: string | null): boolean }) => {
      expect(instance.dropTheirRun(other.duel.duel_id, other.a2.player_id)).toBe(true);
      expect(instance.dropTheirRun(other.duel.duel_id, other.a2.player_id)).toBe(true);
    });
    expect((await theirRun(other.b1, other.duel)).status).toBe(410);
    void a1; void a2;
  }, 90_000);

  it("sweeps a friend duel's rooms even when the duel never ends or is never read again", async () => {
    const { duel, roomA, roomB, b1 } = await duelWithRooms([]);
    const stub = env.LEADERBOARD_BOARDS.getByName(RELAY);
    expect((await stub.pendingWork(0, 0, Date.now() + 366 * DAY)).copies).toBeUndefined();
    const due = (await stub.pendingWork(0, 0, Date.now() + 396 * DAY + 1)).copies!;
    expect(due.map(item => item.room_id).sort()).toEqual([roomA.room_id, roomB.room_id].sort());
    await dropRunCopies(env, RELAY, due);
    // The rooms forget the other pair: a run finished after that is never copied.
    expect(await runInDurableObject(env.ROOMS_V2.getByName(roomA.room_id), async (instance: { duelLinkOf(): { others?: string[] } | null }) => instance.duelLinkOf()?.others)).toEqual([]);
    void duel; void b1;
  }, 60_000);
});

describe("duel cost", () => {
  it("stays within its request budget per step", async () => {
    const { a1, a2, b1 } = await pairs(true);
    const counted = async (work: (target: Env) => Promise<Response>) => {
      const meter = countingEnv(Object.assign({ ...env }, ON) as Env);
      const answer = await work(meter.env);
      expect(answer.status, await answer.clone().text()).toBe(200);
      return { answer, calls: meter.calls.length };
    };
    const sent = await counted(target => call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: RELAY }, ON, {}, target));
    const duel = (await sent.answer.json<{ duel: DuelView }>()).duel;
    const accepted = await counted(target => call(`/v1/duels/${RELAY}/${duel.duel_id}/accept`, "POST", b1, { schema_version: 1 }, ON, {}, target));
    const read = await counted(target => call("/v1/duels", "GET", a1, undefined, ON, {}, target));
    const room = await ok<RoomSnapshotV2>(openRoom(a1, duel));
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: room.invite_code }));
    const run = await relayRun(0);
    const plain = await counted(target => call(`/v2/rooms/${joined.room_id}/turns`, "POST", a1, turn(joined, run.turns[0][1]), ON, {}, target));
    // Measured 2026-10-28: challenge 24 (friendship checks across both pairs dominate), accept 9, lobby 4, a duel turn 6 (one more than a plain turn).
    expect(sent.calls).toBeLessThanOrEqual(24);
    expect(accepted.calls).toBeLessThanOrEqual(9);
    expect(read.calls).toBeLessThanOrEqual(4);
    expect(plain.calls).toBeLessThanOrEqual(6);
  });
});
