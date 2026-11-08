import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { Player } from "../src/player";
import { LIVE_PATH } from "../src/live";
import { canonicalJson, digest } from "../src/protocol";
import { CHAPTERS } from "../src/v2/chapters";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { boardKeys } from "../src/leaderboards/boards";
import { developerGhost } from "../src/duels/developer-ghosts";
import { deriveJobToken } from "../src/leaderboards/job-token";
import { forgetViews } from "../src/leaderboards/view-cache";
import { forgetReplays } from "../src/leaderboards/replays";
import { accept, blankSide, newFriendDuel, newGhostRace, type DuelView } from "../src/duels/model";
import { DuelStore } from "../src/duels/store";
import { MAX_BOARD_DUELS, MAX_FRIEND_DUELS_PER_PAIR, MAX_GHOST_RACES_PER_PAIR, MAX_RECENT_DUELS, MAX_SETTLED_ON_FULL, STALL_MS, UNCLAIMED_RACE_MS } from "../src/duels/rules";
import { pairKey } from "../src/leaderboards/run";
import gameDuelsClient from "../../game/services/duels_client.gd?raw";
import type { LeaderboardBoard } from "../src/leaderboards/board";
import { countAllRequests, countingEnv, meterRows } from "./meter";
import { ledgerLines, noteFullJourney, walletBalance } from "../src/pollen/wallet";
import { PLATFORM_LINKS_OBJECT } from "../src/platform-links";
import { POLLEN_CLIENT, configJson, openCostly } from "./config";
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
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + (++address % 250), "X-AfterYou-Pollen": "1", ...POLLEN_CLIENT,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), Object.assign({ ...base, ...openCostly(base) }, vars) as Env);
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
 * The Relay fixtures, every hash and link redone, with `slower` more ticks on the last turn (fewer
 * when negative, taken from its longer second to last action) and catch assistance as asked (off, as
 * a duel's room takes only unassisted turns). The server checks structure and hashes, not physics.
 */
async function relayRun(slower = 0, assisted = false) {
  const a1 = await rerecord({ ...firstA, catch_assistance: assisted });
  const b1 = await rerecord({ ...firstB, catch_assistance: assisted, source_recording_hash: a1.recording_hash });
  const mid = await rehash({ ...middle, a_recording_hash: a1.recording_hash, b_recording_hash: b1.recording_hash, proof: { ...(middle.proof as Any), a: a1, b: b1 } });
  const a2 = await rerecord({ ...secondA, catch_assistance: assisted, checkpoint_hash: mid.checkpoint_hash });
  const changed = secondB.actions.length - (slower < 0 ? 2 : 1);
  const actions = secondB.actions.map((action, index) => index === changed ? { ...action, ticks: action.ticks + slower } : action);
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
const detail = (account: Account, duel: DuelView) => ok<{ duel: DuelView; pay?: Any; win_bonus?: Any; ghost_bonus?: Any }>(call(`/v1/duels/${duel.board}/${duel.duel_id}`, "GET", account));
/** The duel tables' statements on a board (duels/store.ts), apart from its own runs', for meterRows. */
const DUEL_TABLES = /duel/;
/** Duel runs the Relay board keeps for the replay check. */
const proofRows = () => runInDurableObject(env.LEADERBOARD_BOARDS.getByName(RELAY), async (_, ctx) =>
  ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='duel_proofs'").toArray().length ? ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM duel_proofs").one().n : 0);
/** A friend duel A1 + A2 against B1 + B2, accepted, both rooms open and joined, each pair's host first. */
async function friendRooms(a1: Account, a2: Account, b1: Account, b2: Account) {
  const duel = (await ok<{ duel: DuelView }>(challenge(a1, b1))).duel;
  await ok(call(`/v1/duels/${RELAY}/${duel.duel_id}/accept`, "POST", b1, { schema_version: 1 }));
  const roomA = await ok<RoomSnapshotV2>(openRoom(a1, duel));
  const joinedA = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: roomA.invite_code }));
  const roomB = await ok<RoomSnapshotV2>(openRoom(b1, duel));
  const joinedB = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", b2, { invite_code: roomB.invite_code }));
  return { duel, joinedA, joinedB };
}

const shared = env as unknown as Record<string, unknown>;
/** Objects read their own CONFIG, which the Worker's vars never reach: what a test set there, put back after it. */
const objectConfigs = new Map<Record<string, unknown>, unknown>();
async function objectConfig(stubs: DurableObjectStub[], config: string): Promise<void> {
  for (const stub of stubs) await runInDurableObject(stub, instance => {
    const target = Reflect.get(instance, "env") as Record<string, unknown>;
    if (!objectConfigs.has(target)) objectConfigs.set(target, target.CONFIG);
    target.CONFIG = config;
  });
}
/** Duel run checks on (DUEL_RUN_CHECKS, off by default) at the Relay board, the object that reads them. */
const CHECKS = configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "DUEL_RUN_CHECKS"] });
const checksOn = (config = CHECKS) => objectConfig([env.LEADERBOARD_BOARDS.getByName(RELAY) as unknown as DurableObjectStub], config);
beforeEach(async () => { shared.POLLEN_SECRET = SECRET; await forgetViews(boardKeys()); forgetReplays(); });
afterEach(async () => {
  for (const [target, value] of objectConfigs) { if (value === undefined) delete target.CONFIG; else target.CONFIG = value; }
  objectConfigs.clear();
  delete shared.POLLEN_SECRET; await reset();
});

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
const errorCode = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
/** The board key of a chapter row. */
const boardOfRow = (row: (typeof CHAPTERS)[number]) => `${row.adapter.key.level_id}@${row.adapter.key.level_version}`;
/**
 * `count` friend duels of the pair `members` against made-up pairs, straight onto the boards (`boards[i % length]`)
 * and the pair's pointers, as a busy pair's would be: running, or decided (won or lost) for the cost reads.
 */
async function seedDuels(members: [Account, Account], count: number, boards: string[] = [RELAY], end: "running" | "won" | "lost" = "running"): Promise<DuelView[]> {
  const ids = members.map(member => member.player_id) as [string, string];
  const key = await pairKey(...ids), now = Date.now(), refs: { duel_id: string; board: string; at: number }[] = [];
  for (let index = 0; index < count; index++) {
    const board = boards[index % boards.length], row = CHAPTERS.find(item => boardOfRow(item) === board)!;
    const duel_id = (await digest(`seed\n${key}\n${index}\n${end}\n${now}`)).slice(0, 32);
    const others = [`s${index}`.padEnd(22, "s"), `t${index}`.padEnd(22, "t")] as [string, string];
    const duel = newFriendDuel({ duel_id, board, chapter: { ...row.adapter.key }, steps: row.adapter.stages.length * 2, starter: ids[0], a: blankSide(ids, key), b: blankSide(others, `other${index}`), known: [] }, now);
    Object.assign(duel, { status: "running", accepted_ms: now });
    if (end !== "running") Object.assign(duel, { status: "decided", result: { winner: end === "won" ? 0 : 1, reason: "faster", decided_ms: now, margin_ticks: 30 } });
    await runInDurableObject(env.LEADERBOARD_BOARDS.getByName(board), async (target: LeaderboardBoard) => { target.duelCreate(duel); });
    refs.push({ duel_id, board, at: now });
  }
  for (const id of ids) await env.LEADERBOARD_MEMBERS.getByName(id).partyApply(id, { kind: "add_duels", refs }, now);
  return (await lobby(members[0])).duels.filter(view => refs.some(ref => ref.duel_id === view.duel_id));
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
    // The race ghost rides on the duels capability, only while RACE_GHOST is on, and never without duels.
    expect(await ok<Any>(call("/v2/capabilities", "GET", a, undefined, ON, { "X-AfterYou-Duels": "1" }))).not.toHaveProperty("race_ghost_version");
    const GHOSTED = { ...ON, CONFIG: configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "RACE_GHOST"] }) };
    expect(await ok<Any>(call("/v2/capabilities", "GET", a, undefined, GHOSTED, { "X-AfterYou-Duels": "1" }))).toMatchObject({ duels_version: 1, race_ghost_version: 1 });
    expect(await ok<Any>(call("/v2/capabilities", "GET", a, undefined, { ...ON, CONFIG: configJson({ features: ["LEADERBOARDS", "POLLEN_EARN", "RACE_GHOST"] }) }, { "X-AfterYou-Duels": "1" }))).not.toHaveProperty("race_ghost_version");
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
    await checksOn();
    // Brand new accounts: the win bonus has no account rule (dropped 2026-10-31).
    const { a1, a2, b1, b2 } = await pairs();
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
    expect(won.pay).toMatchObject({ turns: 2, duel_percent: 50 });
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

  it("are decided as the second run finishes while duel run checks are off, paying the win bonus at once and keeping no proof", async () => {
    const board = env.LEADERBOARD_BOARDS.getByName(RELAY) as unknown as DurableObjectStub;
    /** One whole duel, fast A against B 40 ticks slower: the board's rows written from the first turn to the paid result. */
    const whole = async (checks: boolean) => {
      await checksOn(checks ? CHECKS : ON.CONFIG);
      const { a1, a2, b1, b2 } = await pairs();
      const { duel, joinedA, joinedB } = await friendRooms(a1, a2, b1, b2);
      const metered = await meterRows({ board }, async () => {
        await play(joinedA, [a1, a2], await relayRun(0));
        await play(joinedB, [b1, b2], await relayRun(40));
        const seen = (await lobby(b2)).duels.find(item => item.duel_id === duel.duel_id)!;
        if (checks) {
          expect(seen).toMatchObject({ status: "running", result: null });
          expect(await proofRows()).toBe(2);
        } else {
          // Decided in the finishing turn: no run waits and no proof is kept for the replay job (its board run still goes, as ever).
          expect(seen).toMatchObject({ status: "decided", result: { outcome: "lost", reason: "faster", margin_ticks: 40 } });
          expect(seen.sides.map(side => side!.check)).toEqual(["none", "none"]);
          expect(await proofRows()).toBe(0);
        }
        // The job judges the board runs either way; with checks on its verdicts also decide the duel.
        await verdicts((await job()).entries, () => true);
        return detail(a1, duel);
      }, DUEL_TABLES);
      expect(metered.value.duel.result).toMatchObject({ outcome: "won", reason: "faster", margin_ticks: 40 });
      expect(metered.value.win_bonus).toEqual({ amount: 250, counted: true });
      return metered.rows.board.written;
    };
    const on = await whole(true), off = await whole(false);
    // Rows written to the duel tables, measured 2026-11-02: duel run checks cost a friend duel 6 more (the two runs' proofs
    // kept and dropped, and the duel saved again by their verdicts); the board runs cost the same either way. Since
    // 2026-11-04 the paying read adds 1 either way, its receipt on the duel row (duels/payout-receipt.ts).
    expect({ on, off }).toEqual({ on: 17, off: 11 });
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

  it("decline with Not now, keep to the limit at once, and need a party on both sides", async () => {
    const { a1, a2, b1, b2 } = await pairs();
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
    // The pair already has all but two of its duels going: two more go out, and the next is refused.
    expect(MAX_FRIEND_DUELS_PER_PAIR).toBe(10);
    await seedDuels([a1, a2], MAX_FRIEND_DUELS_PER_PAIR - 2);
    const boards = CHAPTERS.slice(1, 4).map(boardOfRow);
    const answers: Response[] = [];
    for (const key of boards) answers.push(await call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: key }));
    expect(answers.map(answer => answer.status)).toEqual([200, 200, 409]);
    expect(await errorCode(answers[2])).toBe("duel_limit_reached");
    // The lobby says the number, so the phone's limit line follows the server.
    const read = await ok<Lobby & { limits: Any }>(call("/v1/duels", "GET", a1));
    expect(read.limits).toEqual({ friend: MAX_FRIEND_DUELS_PER_PAIR, ghost: MAX_GHOST_RACES_PER_PAIR });
    expect(read.duels.filter(duel => duel.status === "running" || duel.status === "challenged")).toHaveLength(MAX_FRIEND_DUELS_PER_PAIR);
  });

  it("take an accept up to the limit of running duels and refuse the one past it", async () => {
    const { a1, b1, b2 } = await pairs();
    const sent = await Promise.all(CHAPTERS.slice(1, 3).map(async row => (await ok<{ duel: DuelView }>(call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: boardOfRow(row) }))).duel));
    await seedDuels([b1, b2], MAX_FRIEND_DUELS_PER_PAIR - 1);
    const first = await call(`/v1/duels/${sent[0].board}/${sent[0].duel_id}/accept`, "POST", b1, { schema_version: 1 });
    expect(first.status).toBe(200);
    const second = await call(`/v1/duels/${sent[1].board}/${sent[1].duel_id}/accept`, "POST", b2, { schema_version: 1 });
    expect(second.status).toBe(409);
    expect(await errorCode(second)).toBe("duel_limit_reached");
  });

  it("refuse a challenge to a player who started the most duels this week, which stays above the limit", async () => {
    const { a1, b1 } = await pairs();
    expect(MAX_RECENT_DUELS).toBe(30);
    const now = Date.now();
    const refs = Array.from({ length: MAX_RECENT_DUELS - 1 }, (_, index) => ({ duel_id: index.toString(16).padStart(32, "a"), board: RELAY, at: now }));
    await env.LEADERBOARD_MEMBERS.getByName(b1.player_id).partyApply(b1.player_id, { kind: "add_duels", refs }, now);
    const boards = CHAPTERS.slice(1, 3).map(boardOfRow);
    const answers: Response[] = [];
    for (const key of boards) answers.push(await call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: key }));
    expect(answers[0].status).toBe(200);
    expect(answers[1].status).toBe(409);
    expect(await errorCode(answers[1])).toBe("opponent_busy");
  });

  it("keep the phone's fallback limits in step with the server's", () => {
    const limit = (name: string) => Number(new RegExp(`^const ${name} := (\\d+)\\s*$`, "m").exec(gameDuelsClient)?.[1]);
    expect(limit("FRIEND_LIMIT")).toBe(MAX_FRIEND_DUELS_PER_PAIR);
    expect(limit("GHOST_LIMIT")).toBe(MAX_GHOST_RACES_PER_PAIR);
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
    expect(ghosts.boards.find(item => item.board === RELAY)!.developer).toBe(developerGhost(RELAY));
    const started = (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }))).duel;
    expect(started).toMatchObject({ kind: "ghost", status: "running", ghost: { source: "developer", ticks: developerGhost(RELAY) } });
    const room = await ok<RoomSnapshotV2>(openRoom(a2, started));
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a1, { invite_code: room.invite_code }));
    const run = await relayRun(0);
    const replies = await play(joined, [a2, a1], run);
    expect((replies[0].pollen as { turn: Any }).turn).not.toHaveProperty("duel");
    const done = (await lobby(a1)).duels[0];
    const ghostTicks = developerGhost(RELAY)!;
    expect(done).toMatchObject({ status: "decided", result: { outcome: run.ticks < ghostTicks ? "won" : run.ticks > ghostTicks ? "lost" : "draw" } });
    expect((await detail(a1, started)).win_bonus).toBeUndefined();
  });

  it("name the partner's turn after a first turn played before the partner joined the room", async () => {
    const { a1, a2 } = await pairs();
    const started = (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }))).duel;
    const room = await ok<RoomSnapshotV2>(openRoom(a2, started));
    const run = await relayRun(0);
    const [, firstTurn] = run.turns[0];
    const first = await ok<MutationV2>(call(`/v2/rooms/${room.room_id}/turns`, "POST", a2, turn(room, firstTurn)));
    expect(first.room).toMatchObject({ guest_id: null, active_role: "b", active_player_id: null });
    const side = (await lobby(a1)).duels[0].sides[0];
    // One turn, its own time, and the partner who has not joined yet to play next: never "Not started".
    expect(side).toMatchObject({ steps: 1, ticks: firstTurn.duration_ticks, turn: side.members.indexOf(a1.player_id) });
    expect((await lobby(a2)).duels[0].sides[0].turn).toBe(side.members.indexOf(a1.player_id));
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a1, { invite_code: room.invite_code }));
    const [, secondTurn, checkpoint] = run.turns[1];
    await ok(call(`/v2/rooms/${room.room_id}/turns`, "POST", a1, turn(joined, secondTurn, checkpoint)));
    expect((await lobby(a2)).duels[0].sides[0]).toMatchObject({ steps: 2, ticks: (firstTurn.duration_ticks as number) + (secondTurn.duration_ticks as number) });
  });
});

describe("the first win over Our run", () => {
  const OURS = developerGhost(RELAY)!;
  const race = async (who: Account) => (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", who, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }))).duel;
  /** Starts a race against the developers' ghost and plays it through with `slower` ticks against the fixtures' run. */
  async function played(host: Account, guest: Account, slower: number, duel?: DuelView) {
    const started = duel ?? await race(host);
    const room = await ok<RoomSnapshotV2>(openRoom(host, started));
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }));
    await play(joined, [host, guest], await relayRun(slower));
    return started;
  }
  /** The player's ghost win lines: [board, amount, duel] each. */
  const lines = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) =>
    !ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name='pollen_claims'").toArray().length ? [] : ctx.storage.sql.exec<{ claim_key: string; amount: number; data: string }>("SELECT claim_key,amount,data FROM pollen_claims WHERE kind='ghostwin'").toArray()
      .map(row => [row.claim_key, row.amount, (JSON.parse(row.data) as { detail: { duel_id: string } }).detail.duel_id]));
  /** The replay job's entries for duel runs of `ticks`, judged `valid`. */
  async function judge(ticks: number, valid: boolean) {
    const entries = (await job()).entries.filter(entry => entry.ticks === ticks);
    expect(entries.length).toBeGreaterThan(0);
    await verdicts(entries, () => valid);
  }

  it("pays each player of the pair once per board, after the check passes, and never for a second win there", async () => {
    await checksOn();
    const { a1, a2 } = await pairs();
    const fast = (await relayRun(-5)).ticks;
    expect(fast).toBeLessThan(OURS);
    const first = await played(a2, a1, -5);
    // Faster than Our run: the race waits for the replay check, and pays nothing yet.
    const waiting = await detail(a1, first);
    expect(waiting.duel).toMatchObject({ status: "running", result: null });
    expect(waiting.duel.sides[0]).toMatchObject({ finished: true, check: "waiting" });
    expect(waiting.ghost_bonus).toBeUndefined();
    expect(await proofRows()).toBe(1);
    await judge(fast, true);
    expect(await proofRows()).toBe(0);
    const won = await detail(a1, first);
    expect(won.duel.result).toMatchObject({ outcome: "won", reason: "faster", margin_ticks: OURS - fast });
    expect(won.ghost_bonus).toEqual({ amount: 100, counted: true });
    expect(won.win_bonus).toBeUndefined();
    // A repeat answers the same; the partner is paid through the lobby, then sees it too.
    expect((await detail(a1, first)).ghost_bonus).toEqual({ amount: 100, counted: true });
    await lobby(a2);
    expect(await lines(a2)).toEqual([["ghostwin:" + RELAY, 100, first.duel_id]]);
    expect((await detail(a2, first)).ghost_bonus).toEqual({ amount: 100, counted: true });

    // A second win on the same board shows and pays nothing extra.
    const second = await played(a1, a2, -5);
    await judge(fast, true);
    const again = await detail(a1, second);
    expect(again.duel.result).toMatchObject({ outcome: "won", reason: "faster" });
    expect(again.ghost_bonus).toBeUndefined();
    await lobby(a2);
    for (const account of [a1, a2]) expect(await lines(account)).toEqual([["ghostwin:" + RELAY, 100, first.duel_id]]);
  }, 60_000);

  it("pays nothing on a loss, a draw, a failed check, or a race against a board run", async () => {
    await checksOn();
    const { a1, a2 } = await pairs();
    // Slower or level with Our run: decided at once, with no proof kept for the check.
    for (const slower of [1, 0]) {
      const done = await detail(a1, await played(a1, a2, slower));
      expect(done.duel.result!.outcome).toBe(slower ? "lost" : "draw");
      expect(done.duel.sides[0].check).toBe("none");
      expect(done.ghost_bonus).toBeUndefined();
      expect(await proofRows()).toBe(0);
    }
    // Faster, but the run fails its check: no result.
    const failed = await played(a1, a2, -5);
    await judge((await relayRun(-5)).ticks, false);
    const refused = await detail(a1, failed);
    expect(refused.duel.result).toMatchObject({ outcome: "none", reason: "failed_check" });
    expect(refused.ghost_bonus).toBeUndefined();
    // A race against a board run, far slower than the pair: decided at once and never paid.
    const now = Date.now(), duelId = "b".repeat(32);
    const boardRace = newGhostRace({ duel_id: duelId, board: RELAY, chapter: RELAY_KEY, steps: 4, starter: a1.player_id, a: blankSide([a1.player_id, a2.player_id], "pair"),
      ghost: { source: "board", entry_id: "e".repeat(32), rank: 1, ticks: OURS * 4, names: null } }, now);
    await runInDurableObject(env.LEADERBOARD_BOARDS.getByName(RELAY), async (board: LeaderboardBoard) => { board.duelCreate(boardRace); });
    for (const id of [a1.player_id, a2.player_id]) await env.LEADERBOARD_MEMBERS.getByName(id).partyApply(id, { kind: "add_duels", refs: [{ duel_id: duelId, board: RELAY, at: now }] }, now);
    const seen = (await lobby(a1)).duels.find(duel => duel.duel_id === duelId)!;
    const beat = await detail(a1, await played(a1, a2, -5, seen));
    expect(beat.duel.result).toMatchObject({ outcome: "won", reason: "faster" });
    expect(beat.duel.sides[0].check).toBe("none");
    expect(beat.ghost_bonus).toBeUndefined();
    expect(await proofRows()).toBe(0);
    await lobby(a2);
    for (const account of [a1, a2]) expect(await lines(account)).toEqual([]);
  }, 60_000);

  it("never pays a win over Our run decided before the check, or one whose run could not be kept for it", async () => {
    await checksOn();
    const { a1, a2 } = await pairs();
    const now = Date.now(), members: [string, string] = [a1.player_id, a2.player_id];
    const ours = { source: "developer" as const, entry_id: null, rank: null, ticks: OURS, names: null };
    // A race this build never checked, decided as a win the moment the pair finished.
    const old = newGhostRace({ duel_id: "c".repeat(32), board: RELAY, chapter: RELAY_KEY, steps: 4, starter: a1.player_id, a: blankSide(members, "pair"), ghost: ours }, now);
    Object.assign(old.sides[0], { finished_ms: now, ticks: OURS - 5, steps: 4, check: "none" });
    Object.assign(old, { status: "decided", result: { winner: 0, reason: "faster", decided_ms: now, margin_ticks: 5 } });
    // A fast finish whose checkpoint never arrived: the check cannot run, so the race ends unchecked.
    const lost = newGhostRace({ duel_id: "f".repeat(32), board: RELAY, chapter: RELAY_KEY, steps: 4, starter: a1.player_id, a: blankSide(members, "pair"), ghost: ours }, now);
    const boards = env.LEADERBOARD_BOARDS.getByName(RELAY);
    for (const duel of [old, lost]) await runInDurableObject(boards, async (board: LeaderboardBoard) => { board.duelCreate(duel); });
    for (const id of members) await env.LEADERBOARD_MEMBERS.getByName(id).partyApply(id, { kind: "add_duels", refs: [old, lost].map(duel => ({ duel_id: duel.duel_id, board: RELAY, at: now })) }, now);
    await boards.duelAct(lost.duel_id, { kind: "claim", player: a1.player_id, room_id: "r".repeat(22), invite_code: "i".repeat(20), room_absent: false });
    const noted = await boards.duelProgress(lost.duel_id, { room_id: "r".repeat(22), revision: 4, steps: 4, ticks: OURS - 5, turn: null, complete: true, at_ms: now, entry_id: "e".repeat(32) });
    expect(noted.ok && noted.value.result).toMatchObject({ reason: "unchecked", winner: null });
    const views = (await lobby(a1)).duels;
    expect(views.find(duel => duel.duel_id === old.duel_id)!.result).toMatchObject({ outcome: "won" });
    for (const duel of [old, lost]) expect((await detail(a1, views.find(view => view.duel_id === duel.duel_id)!)).ghost_bonus).toBeUndefined();
    await lobby(a2);
    for (const account of [a1, a2]) expect(await lines(account)).toEqual([]);
    expect(await proofRows()).toBe(0);
  }, 60_000);

  it("pays a win over Our run at once while duel run checks are off, and settles runs left waiting when they went off as passed", async () => {
    const { a1, a2 } = await pairs();
    const fast = (await relayRun(-5)).ticks;
    // Off: the race is decided as the pair finishes, its win counted without the check, and pays at once.
    await checksOn(ON.CONFIG);
    const now = await detail(a1, await played(a2, a1, -5));
    expect(now.duel).toMatchObject({ status: "decided", result: { outcome: "won", reason: "faster", margin_ticks: OURS - fast } });
    expect(now.duel.sides[0].check).toBe("none");
    expect(now.ghost_bonus).toEqual({ amount: 100, counted: true });
    expect(await proofRows()).toBe(0);

    // Runs finished while checks were on, waiting, when they go off: the next read settles them as passed and drops their proofs.
    const { a1: c1, a2: c2, b1: d1, b2: d2 } = await pairs();
    await checksOn();
    const race = await played(c1, c2, -5);
    const { duel, joinedA, joinedB } = await friendRooms(c1, c2, d1, d2);
    await play(joinedA, [c1, c2], await relayRun(0));
    await play(joinedB, [d1, d2], await relayRun(40));
    expect((await detail(c1, race)).duel.sides[0].check).toBe("waiting");
    expect((await detail(c1, duel)).duel.status).toBe("running");
    expect(await proofRows()).toBe(3);
    await checksOn(ON.CONFIG);
    // A verdict that still finds their proofs (work handed out before, or the board runs' own verdicts on the same entries)
    // decides nothing now, even a failing one: their runs count as passed and the proofs go.
    expect(await proofRows()).toBe(3);
    await verdicts((await job()).entries, () => false);
    expect(await proofRows()).toBe(0);
    const views = (await lobby(c2)).duels;
    expect(views.find(item => item.duel_id === race.duel_id)).toMatchObject({ status: "decided", result: { outcome: "won", reason: "faster" } });
    expect(views.find(item => item.duel_id === duel.duel_id)).toMatchObject({ status: "decided", result: { outcome: "won", reason: "faster", margin_ticks: 40 } });
    expect((await detail(c1, race)).ghost_bonus).toEqual({ amount: 100, counted: true });
    expect((await detail(c1, duel)).win_bonus).toEqual({ amount: 250, counted: true });
    expect(await lines(c2)).toEqual([["ghostwin:" + RELAY, 100, race.duel_id]]);
  }, 60_000);

  it("cost the board fewer rows for a win over Our run while duel run checks are off", async () => {
    const board = env.LEADERBOARD_BOARDS.getByName(RELAY) as unknown as DurableObjectStub;
    const whole = async (checks: boolean) => {
      await checksOn(checks ? CHECKS : ON.CONFIG);
      const { a1, a2 } = await pairs();
      const metered = await meterRows({ board }, async () => {
        const race = await played(a1, a2, -5);
        // The job judges the board run either way; with checks on its verdict also decides the race.
        await verdicts((await job()).entries, () => true);
        return detail(a1, race);
      }, DUEL_TABLES);
      expect(metered.value.ghost_bonus).toEqual({ amount: 100, counted: true });
      return metered.rows.board.written;
    };
    const on = await whole(true), off = await whole(false);
    // Rows written to the duel tables, measured 2026-11-02: the check costs a race won over Our run 7 more. The paying read's
    // receipt adds 1 either way (2026-11-04).
    expect({ on, off }).toEqual({ on: 14, off: 7 });
  }, 60_000);

  it("pays once when two won races on the board are decided together and read at once", async () => {
    const { a1, a2 } = await pairs();
    const races = [await played(a1, a2, -5), await played(a2, a1, -5)];
    await judge((await relayRun(-5)).ticks, true);
    const answers = await Promise.all([...races, ...races].flatMap(duel => [detail(a1, duel), detail(a2, duel)]));
    for (const account of [a1, a2]) {
      const held = await lines(account);
      expect(held).toHaveLength(1);
      const paidBy = held[0][2];
      // Only the race that paid shows the line, to each player and on every read.
      const mine = answers.filter((_, index) => index % 2 === (account === a1 ? 0 : 1));
      expect(mine.filter(answer => answer.ghost_bonus).map(answer => answer.duel.duel_id)).toEqual([paidBy, paidBy]);
    }
  }, 60_000);

  it("costs the first read of a paying race the credit and the receipt on its row, and the lobby no wallet request after", async () => {
    const { a1, a2 } = await pairs();
    const won = await played(a1, a2, -5);
    await judge((await relayRun(-5)).ticks, true);
    const meter = countingEnv(Object.assign({ ...env }, ON) as Env);
    const stubs = { wallet: env.PLAYERS.getByName(a1.player_id), party: env.LEADERBOARD_MEMBERS.getByName(a1.player_id), board: env.LEADERBOARD_BOARDS.getByName(RELAY) };
    const { rows } = await meterRows(stubs, () => ok(call(`/v1/duels/${RELAY}/${won.duel_id}`, "GET", a1, undefined, ON, {}, meter.env)));
    // Measured 2026-11-04: auth, the board read and the room pay as any finished duel's read, then the credit and the
    // receipt the board keeps on the race's row (duels/payout-receipt.ts), which the lobby reads too.
    expect(meter.calls).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead", "PLAYERS.duelRoomPay", "PLAYERS.creditGhostWin", "LEADERBOARD_BOARDS.duelReceipt"]);
    // Rows written: the claim row and the wallet row; the race's row again with the receipt; the party row no longer.
    expect(rows.wallet.written).toBe(2);
    expect(rows.party.written).toBe(0);
    expect(rows.board.written).toBe(1);
    const later = countingEnv(Object.assign({ ...env }, ON) as Env);
    await ok(call("/v1/duels", "GET", a1, undefined, ON, {}, later.env));
    expect(later.calls).toEqual(["PLAYERS.authorize", "LEADERBOARD_MEMBERS.partyRead", "LEADERBOARD_MEMBERS.partyRead", "LEADERBOARD_BOARDS.duelRead"]);
  }, 60_000);
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
    // Measured 2026-10-28: challenge 24 (friendship checks across both pairs dominate), lobby 4, a duel turn 6 (one more than a plain turn).
    // An accept is 5 since 2026-10-31: the four account checks went with the account rule.
    expect(sent.calls).toBeLessThanOrEqual(24);
    expect(accepted.calls).toBeLessThanOrEqual(5);
    expect(read.calls).toBeLessThanOrEqual(4);
    expect(plain.calls).toBeLessThanOrEqual(6);
  });
});

describe("duel lobby reads", () => {
  /** The calls one GET makes, through the counting env. */
  async function calls(account: Account, path: string): Promise<string[]> {
    const meter = countingEnv(Object.assign({ ...env }, ON) as Env);
    const answer = await call(path, "GET", account, undefined, ON, {}, meter.env);
    expect(answer.status, await answer.text()).toBe(200);
    return meter.calls;
  }
  // Measured 2026-11-02, for the hint reads on the phone (game/services/duel_hint_reads.gd): a lobby read is the sign-in, both
  // party rows and one board per chapter holding a duel; one running duel's read is the sign-in and its board.
  it("cost 3 requests plus one per chapter for the lobby, and 2 for one running duel", async () => {
    const { a1, a2 } = await pairs();
    const keys = [...new Set(CHAPTERS.map(boardOfRow))].filter(key => boardKeys().includes(key));
    expect(keys.length).toBeGreaterThanOrEqual(10);
    let held: DuelView[] = [];
    for (const [count, added] of [[1, 1], [5, 4], [10, 5]] as const) {
      held = [...held, ...await seedDuels([a1, a2], added, keys.slice(held.length, held.length + added))];
      const lobbyCalls = await calls(a1, "/v1/duels");
      expect(lobbyCalls).toEqual(["PLAYERS.authorize", "LEADERBOARD_MEMBERS.partyRead", "LEADERBOARD_MEMBERS.partyRead", ...Array(count).fill("LEADERBOARD_BOARDS.duelRead")]);
    }
    expect(held).toHaveLength(10);
    expect(await calls(a1, `/v1/duels/${held[0].board}/${held[0].duel_id}`)).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead"]);
  }, 60_000);

  it("cost an ended duel's read the win bonus once when won, and nothing more when lost", async () => {
    const { a1, a2 } = await pairs();
    const [won] = await seedDuels([a1, a2], 1, [RELAY], "won");
    const [lost] = await seedDuels([a1, a2], 1, [RELAY], "lost");
    // The seeding lobby read already paid the win, so the first read asks the wallet once more (it answers the same, once-only
    // line) and keeps its receipt on the duel row; every read after is the sign-in and the board read only.
    expect(await calls(a1, `/v1/duels/${won.board}/${won.duel_id}`)).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead", "PLAYERS.creditDuelWin", "LEADERBOARD_BOARDS.duelReceipt"]);
    expect(await calls(a1, `/v1/duels/${won.board}/${won.duel_id}`)).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead"]);
    // A loss with no room asks nothing, so it keeps nothing either.
    expect(await calls(a1, `/v1/duels/${lost.board}/${lost.duel_id}`)).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead"]);
  }, 60_000);
});

describe("duel hints", () => {
  // The live socket and duels on, at the Worker and in every object (objects read their own CONFIG).
  const LIVE = { ...ON, CONFIG: configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "LIVE_CONNECTION_ENABLED"] }) };
  const LIVE_OFF = ON;
  type Socket = { messages: Any[] };
  const objectsLive = (stubs: DurableObjectStub[], on = true) => objectConfig(stubs, on ? LIVE.CONFIG : ON.CONFIG);
  afterEach(() => { vi.restoreAllMocks(); });
  async function connect(who: Account): Promise<Socket> {
    const answer = await call(LIVE_PATH, "GET", who, undefined, LIVE, { Upgrade: "websocket" });
    expect(answer.status).toBe(101);
    const ws = answer.webSocket!; ws.accept();
    const socket: Socket = { messages: [] };
    ws.addEventListener("message", event => { const text = String(event.data); if (text !== "pong") socket.messages.push(JSON.parse(text) as Any); });
    return socket;
  }
  const duelEvents = (socket: Socket) => socket.messages.filter(message => message.type === "duels_changed");
  async function until(condition: () => boolean, ms = 8000): Promise<void> {
    const end = Date.now() + ms;
    while (!condition()) { if (Date.now() > end) throw new Error("timed out"); await new Promise(resolve => setTimeout(resolve, 5)); }
  }
  const pause = () => new Promise(resolve => setTimeout(resolve, 80));
  /** Runs one change and checks how many duel hints each socket got for it. */
  async function step(sockets: Record<string, Socket>, change: () => Promise<unknown>, expected: Record<string, number>): Promise<Record<string, Any[]>> {
    const before = Object.fromEntries(Object.entries(sockets).map(([name, socket]) => [name, duelEvents(socket).length]));
    await change();
    await until(() => Object.entries(expected).every(([name, count]) => duelEvents(sockets[name]).length >= before[name] + count));
    await pause();
    const got = Object.fromEntries(Object.entries(sockets).map(([name, socket]) => [name, duelEvents(socket).slice(before[name])]));
    expect(Object.fromEntries(Object.entries(got).map(([name, list]) => [name, list.length]))).toEqual(expected);
    return got;
  }
  const players = (...accounts: Account[]) => accounts.map(account => env.PLAYERS.getByName(account.player_id) as unknown as DurableObjectStub);
  const board = () => env.LEADERBOARD_BOARDS.getByName(RELAY) as unknown as DurableObjectStub;

  it("are said to be on in every duel read while duels and the live socket are both on, so a rolled back server slows nobody", async () => {
    const { a1 } = await pairs();
    const race = (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }, LIVE))).duel;
    const read = (vars: typeof LIVE) => Promise.all([ok<Any>(call("/v1/duels", "GET", a1, undefined, vars)), ok<Any>(call("/v1/duels/" + RELAY + "/" + race.duel_id, "GET", a1, undefined, vars))]);
    for (const answer of await read(LIVE)) expect(answer).toHaveProperty("duel_hints_version", 1);
    for (const answer of await read(LIVE_OFF)) expect(answer).not.toHaveProperty("duel_hints_version");
    // The capability answer keeps its bytes: the pace follows the latest read, never a capability read once per session.
    expect(await ok<Any>(call("/v2/capabilities", "GET", a1, undefined, LIVE, { "X-AfterYou-Duels": "1" }))).not.toHaveProperty("duel_hints_version");
  });

  it("tell only the player whose party row changed: an invite, an accept, a cancel and a leave, never a dismiss", async () => {
    const [a, b, c] = await Promise.all([create(), create(), create()]);
    await befriend(a, b); await befriend(a, c); await befriend(b, c);
    await objectsLive(players(a, b, c));
    const sockets = { a: await connect(a), b: await connect(b), c: await connect(c) };
    const party = (who: Account, action: string, body: Any = {}) => ok(call("/v1/duels/party/" + action, "POST", who, { schema_version: 1, ...body }, LIVE));
    const [invite] = (await step(sockets, () => party(a, "invite", { friend: b.player_id }), { a: 0, b: 1, c: 0 })).b;
    // A party hint names no duel: the lobby reads once.
    expect(invite).toEqual({ type: "duels_changed", at: expect.any(Number) });
    await step(sockets, () => party(b, "accept", { from: a.player_id }), { a: 1, b: 0, c: 0 });
    await step(sockets, () => party(c, "invite", { friend: a.player_id }), { a: 1, b: 0, c: 0 });
    await step(sockets, () => party(a, "dismiss", { from: c.player_id }), { a: 0, b: 0, c: 0 });
    await step(sockets, () => party(c, "invite", { friend: b.player_id }), { a: 0, b: 1, c: 0 });
    await step(sockets, () => party(c, "cancel"), { a: 0, b: 1, c: 0 });
    await step(sockets, () => party(b, "leave"), { a: 1, b: 0, c: 0 });
  });

  it("follow a friend duel's milestones and every turn to the players who did not act", async () => {
    const { a1, a2, b1, b2 } = await pairs();
    await objectsLive([...players(a1, a2, b1, b2), board()]);
    // With duel run checks on, so the check result is news of its own.
    await checksOn(configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "LIVE_CONNECTION_ENABLED", "DUEL_RUN_CHECKS"] }));
    const sockets = { a1: await connect(a1), a2: await connect(a2), b1: await connect(b1), b2: await connect(b2) };
    const path = (duel: DuelView, action: string) => "/v1/duels/" + RELAY + "/" + duel.duel_id + "/" + action;
    let duel!: DuelView;
    const sent = await step(sockets, async () => { duel = (await ok<{ duel: DuelView }>(call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: RELAY }, LIVE))).duel; },
      { a1: 0, a2: 1, b1: 1, b2: 1 });
    expect(sent.b2[0]).toEqual({ type: "duels_changed", duel: duel.duel_id, at: duel.updated_ms });
    await step(sockets, () => ok(call(path(duel, "accept"), "POST", b2, { schema_version: 1 })), { a1: 1, a2: 1, b1: 1, b2: 0 });
    // The second accept changes nothing, so it tells nobody.
    await step(sockets, () => ok(call(path(duel, "accept"), "POST", b1, { schema_version: 1 })), { a1: 0, a2: 0, b1: 0, b2: 0 });
    // A room claimed is news to its own pair only.
    let room!: RoomSnapshotV2;
    await step(sockets, async () => { room = await ok<RoomSnapshotV2>(openRoom(a1, duel)); }, { a1: 0, a2: 1, b1: 0, b2: 0 });
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: room.invite_code }));
    const run = await relayRun(0);
    const hosting: [Account, Account] = joined.host_id === a1.player_id ? [a1, a2] : [a2, a1];
    const named: [string, Account][] = [["a1", a1], ["a2", a2], ["b1", b1], ["b2", b2]];
    const allBut = (actor: Account) => Object.fromEntries(named.map(([name, account]) => [name, account === actor ? 0 : 1]));
    // Every mid-run turn tells the other pair and the partner (whose page shows whose turn it is), none to the player
    // who took it, and no row on the other pair's Players. A retried turn tells nobody. The partner hears once: the
    // room's hint and the duel's in one Player request after the board has the turn (duels/news.ts sendTurnHints), so
    // a turn costs three hint requests, not four. Duel hints counted here; the room hint is the partner's first message.
    const hints = vi.spyOn(Player.prototype, "liveHint"), duelHints = () => hints.mock.calls.filter(([, hint]) => hint.kind === "duels").length;
    let current = joined;
    const others = { b1: players(b1)[0], b2: players(b2)[0] };
    for (const [index, [who, recording, checkpoint]] of run.turns.slice(0, -1).entries()) {
      const actor = hosting[who], partner = hosting[1 - who], body = turn(current, recording, checkpoint), sent = duelHints();
      const counted = await countAllRequests(env, () => meterRows(others, () => step(sockets, async () => {
        const reply = await ok<MutationV2>(call("/v2/rooms/" + joined.room_id + "/turns", "POST", actor, body));
        // The held partner hint is server only: never in the reply.
        expect(JSON.stringify(reply)).not.toContain("duel_partner_hint");
        current = reply.room;
      }, allBut(actor))));
      const told = counted.value;
      expect(duelHints() - sent).toBe(3);
      expect(counted.calls.filter(name => name === "PLAYERS.liveHint")).toHaveLength(2);
      expect(counted.calls.filter(name => name === "PLAYERS.liveHints")).toHaveLength(1);
      // A mid-run turn costs 11 requests in all (12 before the partner's two hints became one). Block checks: the room's
      // gate asks both lists only on a player's first gated request in this room instance (memo), and the commit asks
      // both again after the body is read and hashed, always: that recheck is real, so it stays.
      expect(counted.calls.filter(name => name === "SAFETY_PROFILES.hasBlocked")).toHaveLength(index < 2 ? 4 : 2);
      expect(counted.calls).toHaveLength(index < 2 ? 13 : 11);
      const partnerSaw = sockets[partner === a1 ? "a1" : "a2"].messages.slice(-2).map(message => message.type);
      expect(partnerSaw).toEqual(["room_changed", "duels_changed"]);
      expect(told.rows.b1.written + told.rows.b2.written).toBe(0);
      // The hint names the duel at the time its next read shows, with the new step.
      const seen = (await detail(b1, duel)).duel;
      expect(told.value.b1[0]).toEqual({ type: "duels_changed", duel: duel.duel_id, at: seen.updated_ms });
      expect(seen.sides[0].steps).toBe(index + 1);
      await step(sockets, () => ok(call("/v2/rooms/" + joined.room_id + "/turns", "POST", actor, body)), { a1: 0, a2: 0, b1: 0, b2: 0 });
      expect(duelHints() - sent).toBe(3);
    }
    const [who, recording, checkpoint] = run.turns[run.turns.length - 1];
    const finisher = hosting[who];
    await step(sockets, () => ok(call("/v2/rooms/" + joined.room_id + "/turns", "POST", finisher, turn(current, recording, checkpoint))), allBut(finisher));
    await step(sockets, () => ok(call(path(duel, "leave"), "POST", b2, { schema_version: 1 })), { a1: 1, a2: 1, b1: 1, b2: 0 });
    // The check result has no actor: all four hear the duel end.
    const ended = await step(sockets, async () => verdicts((await job()).entries, () => true), { a1: 1, a2: 1, b1: 1, b2: 1 });
    expect((await detail(a1, duel)).duel).toMatchObject({ status: "decided", updated_ms: ended.a1[0].at });
  }, 60_000);

  it("tell the partner of a new ghost race, and cost one Player request per player told, writing no row", async () => {
    const { a1, a2 } = await pairs();
    await objectsLive([...players(a1, a2), board()]);
    const sockets = { a1: await connect(a1), a2: await connect(a2) };
    const hints = vi.spyOn(Player.prototype, "liveHint");
    const race = (vars: typeof LIVE) => ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }, vars));
    const stubs = { a1: players(a1)[0], a2: players(a2)[0] };
    const told = await meterRows(stubs, () => step(sockets, () => race(LIVE), { a1: 0, a2: 1 }));
    expect(hints).toHaveBeenCalledTimes(1);
    // The same race with hints off writes the same rows: a hint stores nothing.
    await objectsLive(players(a1, a2), false);
    const quiet = await meterRows(stubs, () => race(LIVE_OFF));
    expect(hints).toHaveBeenCalledTimes(1);
    expect(told.rows.a2.written).toBe(quiet.rows.a2.written);
    expect(told.rows.a1.written).toBe(quiet.rows.a1.written);
  });
});

describe("duel looks", () => {
  // Looks on (POLLEN_LOOKS), with the shop to buy and wear them.
  const LOOKS = { ...ON, CONFIG: configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_LOOKS"] }) };
  const ASK = { "X-AfterYou-Looks": "1" };
  const PRICES: Record<string, number> = { daisy: 1000, seashell: 1000, straw_hat: 5000, tide: 20000 };
  /** Buys and wears `look` through the shop, as the phone would. */
  async function wear(account: Account, look: Record<string, string>): Promise<void> {
    await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => {
      noteFullJourney(ctx.storage, Date.now() + DAY, Date.now());
      ctx.storage.sql.exec("UPDATE pollen_wallet SET data=json_set(data,'$.balance',100000,'$.earned',100000) WHERE id=1");
    });
    for (const id of Object.values(look)) await ok(call("/v1/pollen/spend", "POST", account, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id, expected_cost: PRICES[id] }, LOOKS));
    await ok(call("/v1/pollen/equip", "POST", account, { schema_version: 1, idempotency_key: crypto.randomUUID(), revision: Date.now(), look }, LOOKS));
  }
  const looksLobby = (account: Account, vars = LOOKS) => ok<Lobby & { party: { partner_look?: Any } }>(call("/v1/duels", "GET", account, undefined, vars));
  const sideLooks = (view: DuelView) => view.sides.map(side => side?.looks);
  const partyRow = (account: Account) => runInDurableObject(env.LEADERBOARD_MEMBERS.getByName(account.player_id), async (_, ctx) =>
    JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM duel_party WHERE id=1").one().data) as Any);
  const openWith = (host: Account, duel: DuelView) => ok<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), ...RELAY_KEY, duel: { duel_id: duel.duel_id, board: RELAY } }, LOOKS));
  const joinWith = (guest: Account, room: RoomSnapshotV2) => ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }, LOOKS));

  it("dress each side in what its members wear, from their party rows and then each turn in their room, only while looks are on", async () => {
    const { a1, a2, b1, b2 } = await pairs();
    await wear(a1, { hat: "daisy" }); await wear(a2, { hat: "seashell" }); await wear(b1, { hat: "straw_hat" });
    // Each lobby read keeps the reader's look in their own party row; the partner's comes from the row the lobby already reads.
    for (const account of [a1, a2, b1, b2]) await looksLobby(account);
    expect((await looksLobby(a1)).party.partner_look).toEqual({ hat: "seashell" });
    expect((await looksLobby(b1)).party.partner_look).toEqual({});
    expect(await partyRow(b2)).not.toHaveProperty("look");
    // Off, nothing about looks is said.
    expect((await lobby(a1)).party).not.toHaveProperty("partner_look");

    const sent = (await ok<{ duel: DuelView }>(call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: RELAY }, LOOKS))).duel;
    expect(sideLooks(sent)).toEqual([[{ hat: "daisy" }, { hat: "seashell" }], [{ hat: "straw_hat" }, {}]]);
    // The other pair sees A's looks, even for A2, whose id it may not see.
    const accepted = (await ok<{ duel: DuelView }>(call(`/v1/duels/${RELAY}/${sent.duel_id}/accept`, "POST", b1, { schema_version: 1 }, LOOKS))).duel;
    expect(accepted.sides[0].members).toEqual([a1.player_id, null]);
    expect(sideLooks(accepted)).toEqual([[{ hat: "daisy" }, { hat: "seashell" }], [{ hat: "straw_hat" }, {}]]);
    // Looks off: views read as before looks.
    expect(sideLooks((await detail(b1, sent)).duel)).toEqual([undefined, undefined]);

    // A2 changes before joining the room and never opens the lobby again: the room's member look reaches the duel with the next turn.
    await wear(a2, { body: "tide" });
    const room = await openWith(a1, sent);
    const joined = await joinWith(a2, room);
    // In the duel's own room each member reads the partner's look, as in any room.
    expect((await ok<Any>(call(`/v2/rooms/${room.room_id}`, "GET", a2, undefined, LOOKS, ASK))).partner_look).toEqual({ hat: "daisy" });
    expect((await ok<Any>(call(`/v2/rooms/${room.room_id}`, "GET", a1, undefined, LOOKS, ASK))).partner_look).toEqual({ body: "tide" });
    const run = await relayRun(0);
    const reply = await ok<Any>(call(`/v2/rooms/${joined.room_id}/turns`, "POST", a1, turn(joined, run.turns[0][1]), LOOKS));
    // The duel's looks are server only: the turn reply never carries them.
    expect(reply).not.toHaveProperty("duel_looks");
    const seen = (await looksLobby(b2)).duels.find(item => item.duel_id === sent.duel_id)!;
    expect(sideLooks(seen)).toEqual([[{ hat: "daisy" }, { body: "tide" }], [{ hat: "straw_hat" }, {}]]);
  }, 60_000);

  it("race a board run in the looks its row shows, and the developers' run in the default", async () => {
    const { a1, a2 } = await pairs(true);
    await wear(a1, { hat: "daisy" });
    const first = (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }, LOOKS))).duel;
    expect(first.ghost!.looks).toEqual([{}, {}]);
    // A finished run of A puts A on the board in A's looks.
    let current = await joinWith(a2, await openWith(a1, first));
    for (const [who, recording, checkpoint] of (await relayRun(0)).turns) current = (await ok<MutationV2>(call(`/v2/rooms/${current.room_id}/turns`, "POST", [a1, a2][who], turn(current, recording, checkpoint), LOOKS))).room;
    await verdicts((await job()).entries, () => true);
    await forgetViews(boardKeys());
    const top = (await ok<{ boards: { board: string; top: { entry_id: string }[] }[] }>(call("/v1/duels/ghosts", "GET", a1, undefined, LOOKS))).boards.find(item => item.board === RELAY)!.top;
    expect(top.length).toBeGreaterThan(0);
    const raced = (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "board", entry_id: top[0].entry_id }, LOOKS))).duel;
    expect(raced.ghost!.looks).toEqual([{ hat: "daisy" }, {}]);
    // The race keeps the run's replay_hash as the board row names it (the race ghost), and the developers' run has none.
    const row = (await ok<{ top: { entry_id: string; replay_hash: string | null }[] }>(call(`/v1/leaderboards/${RELAY}`, "GET", a1, undefined, LOOKS))).top.find(item => item.entry_id === top[0].entry_id)!;
    expect(row.replay_hash).toMatch(/^[a-f0-9]{64}$/);
    expect(raced.ghost!.replay_hash).toBe(row.replay_hash);
    expect((await detail(a1, raced)).duel.ghost!.replay_hash).toBe(row.replay_hash);
    expect(first.ghost).not.toHaveProperty("replay_hash");
    expect((await detail(a1, raced)).duel.ghost).not.toHaveProperty("looks");
  }, 60_000);

  it("let the other pair's run play in the looks each turn was played in", async () => {
    const { a1, a2, b1, b2 } = await pairs();
    await wear(a1, { hat: "daisy" });
    const sent = (await ok<{ duel: DuelView }>(call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: RELAY }, LOOKS))).duel;
    await ok(call(`/v1/duels/${RELAY}/${sent.duel_id}/accept`, "POST", b1, { schema_version: 1 }, LOOKS));
    const hashes: string[] = [];
    for (const [host, guest, slower] of [[a1, a2, 0], [b1, b2, 40]] as [Account, Account, number][]) {
      let current = await joinWith(guest, await openWith(host, sent));
      for (const [who, recording, checkpoint] of (await relayRun(slower)).turns) {
        current = (await ok<MutationV2>(call(`/v2/rooms/${current.room_id}/turns`, "POST", [host, guest][who], turn(current, recording, checkpoint), LOOKS))).room;
        if (host === a1 && who === 0) hashes.push(recording.recording_hash as string);
      }
    }
    const theirs = (vars: typeof LOOKS) => ok<Any>(call(`/v1/duels/${RELAY}/${sent.duel_id}/their-run`, "GET", b1, undefined, vars));
    const looks = (await theirs(LOOKS)).turn_looks as Record<string, Any>;
    expect(Object.keys(looks).sort()).toEqual([...hashes].sort());
    for (const hash of hashes) expect(looks[hash]).toEqual({ hat: "daisy" });
    expect(await theirs(ON)).not.toHaveProperty("turn_looks");
  }, 60_000);

  it("add no request to any step and write a party row only when a look changed", async () => {
    const { a1, a2, b1 } = await pairs(true);
    await wear(a1, { hat: "daisy" });
    const counted = async (work: (target: Env) => Promise<Response>) => {
      const meter = countingEnv(Object.assign({ ...env }, LOOKS) as Env);
      const answer = await work(meter.env);
      expect(answer.status, await answer.clone().text()).toBe(200);
      return { answer, calls: meter.calls.length };
    };
    const sent = await counted(target => call("/v1/duels/challenge", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: b1.player_id, board: RELAY }, LOOKS, {}, target));
    const duel = (await sent.answer.json<{ duel: DuelView }>()).duel;
    const accepted = await counted(target => call(`/v1/duels/${RELAY}/${duel.duel_id}/accept`, "POST", b1, { schema_version: 1 }, LOOKS, {}, target));
    const read = await counted(target => call("/v1/duels", "GET", a1, undefined, LOOKS, {}, target));
    const joined = await joinWith(a2, await openWith(a1, duel));
    const first = (await relayRun(0)).turns[0][1];
    const played = await counted(target => call(`/v2/rooms/${joined.room_id}/turns`, "POST", a1, turn(joined, first), LOOKS, {}, target));
    // The same budget as with looks off ("stays within its request budget per step").
    expect(sent.calls).toBeLessThanOrEqual(24);
    expect(accepted.calls).toBeLessThanOrEqual(5);
    expect(read.calls).toBeLessThanOrEqual(4);
    expect(played.calls).toBeLessThanOrEqual(6);
    const member = { a1: env.LEADERBOARD_MEMBERS.getByName(a1.player_id) as unknown as DurableObjectStub };
    const same = await meterRows(member, () => looksLobby(a1));
    expect(same.rows.a1.written).toBe(0);
    await wear(a1, { hat: "seashell" });
    const changed = await meterRows(member, () => looksLobby(a1));
    expect(changed.rows.a1.written).toBe(1);
    expect((await partyRow(a1)).look).toEqual({ hat: "seashell" });
  });
});

describe("the platform rule for board posts", () => {
  // LEADERBOARD_REQUIRE_PLATFORM keeps unlinked pairs' runs off the board (leaderboards/platform-rule.ts); duels never wait on a board entry.
  const RULE = ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "LEADERBOARD_REQUIRE_PLATFORM"];
  const PLATFORM = { ...ON, CONFIG: configJson({ features: RULE }) };
  async function playWith(room: RoomSnapshotV2, players: [Account, Account], run: Awaited<ReturnType<typeof relayRun>>, vars: Record<string, string>): Promise<void> {
    for (const [who, recording, checkpoint] of run.turns) room = (await ok<MutationV2>(call(`/v2/rooms/${room.room_id}/turns`, "POST", players[who], turn(room, recording, checkpoint), vars))).room;
  }
  it("still decides a checked friend duel and a ghost race of pairs with no platform link, whose runs stay off the board", async () => {
    await checksOn(configJson({ features: [...RULE, "DUEL_RUN_CHECKS"] }));
    const { a1, a2, b1, b2 } = await pairs();
    const { duel, joinedA, joinedB } = await friendRooms(a1, a2, b1, b2);
    await playWith(joinedA, [a1, a2], await relayRun(0), PLATFORM);
    await playWith(joinedB, [b1, b2], await relayRun(40), PLATFORM);
    const entries = (await job()).entries;
    // Only the duel's own two runs wait for the check: neither run entered the board.
    expect(entries).toHaveLength(2);
    expect((await env.LEADERBOARD_BOARDS.getByName(RELAY).view(RELAY)).checking).toEqual([]);
    await verdicts(entries, () => true);
    expect((await detail(a1, duel)).duel.result).toMatchObject({ outcome: "won", reason: "faster", margin_ticks: 40 });
    const started = (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }, PLATFORM))).duel;
    const room = await ok<RoomSnapshotV2>(openRoom(a2, started, crypto.randomUUID(), PLATFORM));
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a1, { invite_code: room.invite_code }, PLATFORM));
    await playWith(joined, [a2, a1], await relayRun(0), PLATFORM);
    expect((await lobby(a1, PLATFORM)).duels.find(item => item.duel_id === started.duel_id)).toMatchObject({ status: "decided" });
    expect((await env.LEADERBOARD_BOARDS.getByName(RELAY).view(RELAY)).checking).toEqual([]);
  }, 60_000);
});

describe("pair keys by platform account in duels (PAIR-KEYS.md)", () => {
  const PLATFORM = { ...ON, CONFIG: configJson({ features: ["LEADERBOARDS", "DUELS", "POLLEN_EARN", "LEADERBOARD_REQUIRE_PLATFORM"] }) };
  const links = () => env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT);
  const linkAs = async (account: Account, provider: "play_games" | "game_center", letter: string, replace = false) =>
    expect((await links().link(provider, letter.repeat(64), account.player_id, replace)).status).toBe("linked");
  const send = (from: Account, to: Account, vars: Record<string, string>, base: Env = env) =>
    call("/v1/duels/challenge", "POST", from, { schema_version: 1, idempotency_key: crypto.randomUUID(), friend: to.player_id, board: RELAY }, vars, {}, base);

  it("treats identity pairs behind the same two accounts as one opposing pair, for one more read, and only while the rule is on", async () => {
    const { a1, b1, b2 } = await pairs();
    await linkAs(b1, "play_games", "1"); await linkAs(b2, "game_center", "2");
    const meter = countingEnv(Object.assign({ ...env }, PLATFORM) as Env);
    await ok(send(a1, b1, PLATFORM, meter.env));
    expect(meter.calls.filter(name => name.startsWith("PLATFORM"))).toEqual(["PLATFORM_LINKS.accountsAmong"]);
    // The same two people on new identities, their links moved with "Keep this phone".
    const [b3, b4] = await Promise.all([create(), create()]);
    await befriend(b3, b4); await befriend(a1, b3); await partner(b3, b4);
    await linkAs(b3, "play_games", "1", true); await linkAs(b4, "game_center", "2", true);
    const again = await send(a1, b3, PLATFORM);
    expect(again.status).toBe(409);
    expect(await errorCode(again)).toBe("duel_already_open");
    // Rule off: no read, and they are another pair.
    const off = countingEnv(Object.assign({ ...env }, ON) as Env);
    await ok(send(a1, b3, ON, off.env));
    expect(off.calls.filter(name => name.startsWith("PLATFORM"))).toEqual([]);
    // No view carries either key.
    const shown = JSON.stringify(await lobby(a1, PLATFORM)) + JSON.stringify(await lobby(b3, PLATFORM));
    expect(shown).not.toContain("account_key");
    expect(shown).not.toContain("pair_key");
  }, 60_000);

  it("caps the win bonus once a week per opposing pair by either key, before and after the rule", async () => {
    const { a1, a2 } = await pairs();
    const ids = [a1.player_id, a2.player_id] as [string, string];
    const key = await pairKey(...ids), now = Date.now(), refs: { duel_id: string; board: string; at: number }[] = [];
    // Before the rule (id key P), the same pair after it (P with account K), other identities behind K (Q with K), and another pair (R).
    const opponents: [string, string | undefined][] = [["P", undefined], ["P", "K"], ["Q", "K"], ["R", undefined]];
    for (const [index, [pair, account]] of opponents.entries()) {
      const duel_id = (await digest(`won\n${key}\n${index}\n${now}`)).slice(0, 32);
      const others = [`s${index}`.padEnd(22, "s"), `t${index}`.padEnd(22, "t")] as [string, string];
      const duel = newFriendDuel({ duel_id, board: RELAY, chapter: { ...RELAY_KEY }, steps: CHAPTERS[0].adapter.stages.length * 2, starter: ids[0], a: blankSide(ids, key),
        b: blankSide(others, pair.repeat(64), undefined, account?.repeat(64)), known: [] }, now);
      Object.assign(duel, { status: "decided", accepted_ms: now, result: { winner: 0, reason: "faster", decided_ms: now, margin_ticks: 30 } });
      await runInDurableObject(env.LEADERBOARD_BOARDS.getByName(RELAY), async (target: LeaderboardBoard) => { target.duelCreate(duel); });
      refs.push({ duel_id, board: RELAY, at: now });
    }
    for (const id of ids) await env.LEADERBOARD_MEMBERS.getByName(id).partyApply(id, { kind: "add_duels", refs }, now);
    await lobby(a1);
    const lines = await runInDurableObject(env.PLAYERS.getByName(a1.player_id), async (_, ctx) => ledgerLines(ctx.storage, "duelwin:", 16));
    expect(lines).toHaveLength(4);
    const paid = lines.filter(line => line.amount > 0).map(line => String(line.detail.opponent)).sort();
    // One of the three wins over the same people counts and the other pair's win counts. The ids-only and accounts-only wins meet through the line naming both, so a payment order where that line comes last can still count two.
    expect(paid).toHaveLength(2);
    expect(paid).toContain("R".repeat(64));
    expect(lines.filter(line => line.detail.reason === "same_pair")).toHaveLength(2);
  }, 60_000);
});

describe("duel board guards", () => {
  const T0 = 1_900_000_000_000;
  const side = (n: number) => blankSide(["p" + n + "a".padEnd(20, "a"), "p" + n + "b".padEnd(20, "b")], "pk" + n);
  const race = (n: number, now: number) => newGhostRace({ duel_id: n.toString(16).padStart(32, "0"), board: RELAY, chapter: RELAY_KEY, steps: 4, starter: side(n).members[0]!, a: side(n),
    ghost: { source: "developer", entry_id: null, rank: null, ticks: 900, names: null } }, now);
  it("a board full of races nobody opened refuses until they expire, then settles the oldest and takes the new one", async () => {
    await runInDurableObject(env.LEADERBOARD_BOARDS.getByName("guards-" + RELAY), async (_, ctx) => {
      const store = new DuelStore(ctx.storage);
      for (let n = 0; n < MAX_BOARD_DUELS; n++) expect(store.create(race(n, T0 + n), T0 + n)).not.toBeNull();
      const count = () => ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM duels").one().n;
      expect(store.create(race(MAX_BOARD_DUELS, T0 + 3_600_000), T0 + 3_600_000)).toBeNull();
      // Two days on, the oldest unclaimed races have expired: one row goes and the new race fits.
      const later = T0 + UNCLAIMED_RACE_MS + 1_000;
      expect(store.create(race(MAX_BOARD_DUELS + 1, later), later)).not.toBeNull();
      expect(count()).toBe(MAX_BOARD_DUELS);
      expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM duels WHERE status='unfinished'").one().n).toBe(31);
    });
  }, 120_000);
  it("settles expired races however many claimed ones are older, and keeps a decided duel over other settled ones", async () => {
    await runInDurableObject(env.LEADERBOARD_BOARDS.getByName("guards-pinned-" + RELAY), async (_, ctx) => {
      const store = new DuelStore(ctx.storage);
      const claim = (n: number, at: number) => { const duel = race(n, at); store.create(duel, at);
        expect(store.act(duel.duel_id, { kind: "claim", player: duel.sides[0].members[0]!, room_id: "room" + n, invite_code: "code" + n, room_absent: false }, at).ok).toBe(true); return duel; };
      // The oldest rows: a race that was decided, then MAX_SETTLED_ON_FULL claimed races that are still running.
      const won = claim(0, T0);
      expect((await store.progress(won.duel_id, { room_id: "room0", revision: 1, steps: 4, ticks: 500, turn: null, complete: true, at_ms: T0 + 1, entry_id: "e".repeat(32) }, T0 + 1)).ok).toBe(true);
      for (let n = 1; n <= MAX_SETTLED_ON_FULL; n++) claim(n, T0 + 10 + n);
      // One race that ended unfinished long after, then roomless races fill the board.
      const stalled = race(MAX_SETTLED_ON_FULL + 1, T0 + 100);
      store.create(stalled, T0 + 100);
      store.read([stalled.duel_id], T0 + 100 + UNCLAIMED_RACE_MS);
      for (let n = MAX_SETTLED_ON_FULL + 2; n < MAX_BOARD_DUELS; n++) store.create(race(n, T0 + UNCLAIMED_RACE_MS + n), T0 + UNCLAIMED_RACE_MS + n);
      const statusOf = (id: string) => ctx.storage.sql.exec<{ status: string }>("SELECT status FROM duels WHERE duel_id=?", id).toArray()[0]?.status;
      expect(statusOf(won.duel_id)).toBe("decided");
      // Full: the unfinished race goes first, though the decided one is older.
      const next = T0 + UNCLAIMED_RACE_MS + 1_000;
      expect(store.create(race(MAX_BOARD_DUELS, next), next)).not.toBeNull();
      expect(statusOf(stalled.duel_id)).toBeUndefined();
      expect(statusOf(won.duel_id)).toBe("decided");
      // Then the decided one goes before any open race; after that, expired roomless races free rows past the claimed ones.
      expect(store.create(race(MAX_BOARD_DUELS + 1, next), next)).not.toBeNull();
      expect(statusOf(won.duel_id)).toBeUndefined();
      expect(store.create(race(MAX_BOARD_DUELS + 2, next), next)).toBeNull();
      const later = T0 + 2 * UNCLAIMED_RACE_MS + MAX_BOARD_DUELS + 1_000;
      expect(later).toBeLessThan(T0 + STALL_MS);
      expect(store.create(race(MAX_BOARD_DUELS + 3, later), later)).not.toBeNull();
      expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM duels WHERE status='running' AND json_extract(data,'$.sides[0].room') IS NOT NULL").one().n).toBe(MAX_SETTLED_ON_FULL);
    });
  }, 120_000);
  it("a claimed race keeps its board row past the unclaimed limit", async () => {
    await runInDurableObject(env.LEADERBOARD_BOARDS.getByName("guards-claimed-" + RELAY), async (_, ctx) => {
      const store = new DuelStore(ctx.storage);
      for (let n = 0; n < MAX_BOARD_DUELS; n++) {
        const duel = race(n, T0 + n);
        store.create(duel, T0 + n);
        expect(store.act(duel.duel_id, { kind: "claim", player: duel.sides[0].members[0]!, room_id: "room" + n, invite_code: "code" + n, room_absent: false }, T0 + n).ok).toBe(true);
      }
      const later = T0 + UNCLAIMED_RACE_MS + 1_000;
      expect(store.create(race(MAX_BOARD_DUELS, later), later)).toBeNull();
    });
  }, 120_000);
  it("queues a run copy row only for the room a claim made the side's own", async () => {
    await runInDurableObject(env.LEADERBOARD_BOARDS.getByName("guards-copies-" + RELAY), async (_, ctx) => {
      const store = new DuelStore(ctx.storage);
      const [a, b] = [side(1), side(2)];
      const duel = newFriendDuel({ duel_id: "f".repeat(32), board: RELAY, chapter: RELAY_KEY, steps: 4, starter: a.members[0]!, a, b, known: [] }, T0);
      accept(duel, b.members[0]!, T0 + 1, true);
      store.create(duel, T0 + 1);
      const claim = (player: string, room: string) => store.act(duel.duel_id, { kind: "claim", player, room_id: room, invite_code: "i" + room, room_absent: false }, T0 + 2);
      expect(claim(a.members[0]!, "won")).toMatchObject({ ok: true, value: { room: { room_id: "won" } } });
      // The partner's own room lost the race: the side's room is the first one, and no row names the loser.
      expect(claim(a.members[1]!, "lost")).toMatchObject({ ok: true, value: { room: { room_id: "won" } } });
      const rooms = ctx.storage.sql.exec<{ room_id: string }>("SELECT room_id FROM duel_run_copies").toArray().map(row => row.room_id);
      expect(rooms).toEqual(["won"]);
    });
  });
});

describe("payout receipts on an ended duel", () => {
  type Detail = Awaited<ReturnType<typeof detail>>;
  const FIRST_WIN = ["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead", "PLAYERS.duelRoomPay", "PLAYERS.creditDuelWin", "LEADERBOARD_BOARDS.duelReceipt"];
  const LATER = ["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead"];
  const NO_POLLEN = { ...ON, CONFIG: configJson({ features: ["LEADERBOARDS", "DUELS"] }) };
  /** The board's stored row of a duel, as text and as its receipts by seat. */
  const row = (id: string) => runInDurableObject(env.LEADERBOARD_BOARDS.getByName(RELAY), async (_, ctx) => ctx.storage.sql.exec<{ data: string }>("SELECT data FROM duels WHERE duel_id=?", id).one().data);
  const receipts = async (id: string) => (JSON.parse(await row(id)) as { receipts?: Record<string, unknown> }).receipts ?? {};
  /** A player's duel and ghost win lines. */
  const lines = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) =>
    [...ledgerLines(ctx.storage, "duelwin:"), ...ledgerLines(ctx.storage, "ghostwin:")].map(line => [line.key, line.amount]));
  const balanceOf = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => walletBalance(ctx.storage, Date.now()));
  /** One duel read with its Durable Object calls counted, through `base` (a faulty env, say) and `vars`. */
  async function counted(account: Account, duel: DuelView, base: Env = env, vars = ON): Promise<{ answer: Detail; calls: string[] }> {
    const meter = countingEnv(Object.assign({ ...base }, vars) as Env);
    const answer = await ok<Detail>(call(`/v1/duels/${duel.board}/${duel.duel_id}`, "GET", account, undefined, vars, {}, meter.env));
    return { answer, calls: meter.calls };
  }
  type Real = (...args: unknown[]) => Promise<unknown>;
  /** `base` with one RPC on `name`'s stubs replaced: `fault` gets the real call and the arguments. */
  function faulty(base: Env, name: "PLAYERS" | "LEADERBOARD_BOARDS", method: string, fault: (real: Real, ...args: unknown[]) => Promise<unknown>): Env {
    const namespace = base[name] as unknown as DurableObjectNamespace;
    const wrapped = new Proxy(namespace, { get(target, key) {
      if (key !== "getByName") { const value = Reflect.get(target, key); return typeof value === "function" ? value.bind(target) : value; }
      return (id: string) => {
        const stub = target.getByName(id) as unknown as Record<string, Real>;
        return new Proxy(stub, { get(inner, prop) {
          const value = Reflect.get(inner, prop);
          if (typeof prop !== "string" || typeof value !== "function") return value;
          const real: Real = (...args) => inner[prop](...args);
          return prop === method ? (...args: unknown[]) => fault(real, ...args) : real;
        } });
      };
    } });
    return { ...base, [name]: wrapped } as Env;
  }
  /** A friend duel played to its end with duel run checks off: pair A wins by 40 ticks. */
  async function ended() {
    await checksOn(ON.CONFIG);
    const { a1, a2, b1, b2 } = await pairs();
    const { duel, joinedA, joinedB } = await friendRooms(a1, a2, b1, b2);
    await play(joinedA, [a1, a2], await relayRun(0));
    await play(joinedB, [b1, b2], await relayRun(40));
    return { a1, a2, b1, b2, duel };
  }

  it("are kept by the board only on a final duel that seats the player, once, moving no time and telling nobody", async () => {
    await runInDurableObject(env.LEADERBOARD_BOARDS.getByName("receipts-" + RELAY), async (_, ctx) => {
      const told: unknown[] = [];
      const store = new DuelStore(ctx.storage, news => told.push(...news), () => false, changes => told.push(...changes));
      const T0 = 1_900_000_000_000, ids = ["ra", "rb", "rc", "rd"].map(id => id.padEnd(22, "x"));
      const make = (n: number, end: boolean) => {
        const duel = newFriendDuel({ duel_id: n.toString(16).padStart(32, "0"), board: RELAY, chapter: RELAY_KEY, steps: 4, starter: ids[0], a: blankSide([ids[0], ids[1]], "pa"), b: blankSide([ids[2], ids[3]], "pb"), known: [] }, T0);
        Object.assign(duel, { status: "running", accepted_ms: T0 });
        if (end) Object.assign(duel, { status: "decided", result: { winner: 0, reason: "faster", decided_ms: T0, margin_ticks: 30 } });
        store.create(duel, T0);
        return duel.duel_id;
      };
      const rowOf = (id: string) => ctx.storage.sql.exec<{ data: string; updated_ms: number }>("SELECT data,updated_ms FROM duels WHERE duel_id=?", id).one();
      const running = make(1, false), ended = make(2, true);
      const shown = { win_bonus: { amount: 250, counted: true } };
      told.length = 0;
      // A running duel keeps none: a read that saw it running asked nothing.
      expect(store.receipt(running, ids[0], shown)).toBe(false);
      const before = rowOf(ended);
      expect(store.receipt(ended, ids[3], { pay: { turns: 2, plain: 1, blooms: 0, duel: 0, duel_percent: 50, boost: 0, boost_percent: 0, total: 1, held: 0 } })).toBe(true);
      expect(store.receipt(ended, ids[0], shown)).toBe(true);
      // The first receipt for a seat stays; a stranger, or an id no longer seated, keeps none.
      expect(store.receipt(ended, ids[0], { win_bonus: { amount: 0, counted: false } })).toBe(false);
      expect(store.receipt(ended, "zz".padEnd(22, "z"), shown)).toBe(false);
      const after = rowOf(ended);
      expect(after.updated_ms).toBe(before.updated_ms);
      expect((JSON.parse(after.data) as { updated_ms: number }).updated_ms).toBe((JSON.parse(before.data) as { updated_ms: number }).updated_ms);
      expect(Object.keys((JSON.parse(after.data) as { receipts: Record<string, unknown> }).receipts).sort()).toEqual(["0", "3"]);
      expect((JSON.parse(after.data) as { receipts: Record<string, unknown> }).receipts["0"]).toEqual({ v: 1, shown });
      expect(told).toEqual([]);
      // Erasure drops the player's receipt with their id.
      expect(store.forgetPlayer(ids[0], T0 + 1)).toBe(2);
      const erased = rowOf(ended).data;
      expect(erased).not.toContain(ids[0]);
      expect(Object.keys((JSON.parse(erased) as { receipts: Record<string, unknown> }).receipts)).toEqual(["3"]);
    });
  });

  it("pay a won friend duel once and answer every later read from the duel row, two requests, with the same pay", async () => {
    const { a1, b1, duel } = await ended();
    const before = await balanceOf(a1);
    const first = await counted(a1, duel);
    expect(first.answer.win_bonus).toEqual({ amount: 250, counted: true });
    expect(first.calls).toEqual(FIRST_WIN);
    expect(await balanceOf(a1)).toBe(before + 250);
    for (let read = 0; read < 3; read++) {
      const later = await counted(a1, duel);
      expect(later.calls).toEqual(LATER);
      expect({ pay: later.answer.pay, win_bonus: later.answer.win_bonus }).toEqual({ pay: first.answer.pay, win_bonus: first.answer.win_bonus });
    }
    expect(await balanceOf(a1)).toBe(before + 250);
    expect(await lines(a1)).toEqual([["duelwin:" + duel.duel_id, 250]]);
    // The loser's read asks only the room pay, keeps it, and is two requests after.
    const lost = await counted(b1, duel);
    expect(lost.calls).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead", "PLAYERS.duelRoomPay", "LEADERBOARD_BOARDS.duelReceipt"]);
    expect(lost.answer.win_bonus).toBeUndefined();
    const again = await counted(b1, duel);
    expect(again.calls).toEqual(LATER);
    expect(again.answer.pay).toEqual(lost.answer.pay);
    // Kept by seat, never by id: the row names no more ids than before.
    const kept = await receipts(duel.duel_id);
    expect(Object.keys(kept).sort()).toEqual(["0", "2"]);
    expect(JSON.stringify(kept)).not.toMatch(new RegExp([a1, b1].map(account => account.player_id).join("|")));
    // No view shows a receipt to anyone.
    expect(JSON.stringify(first.answer.duel)).not.toContain("receipt");
  }, 60_000);

  it("let the lobby skip a duel the read already paid, though the party row was never told", async () => {
    const { a1, duel } = await ended();
    await counted(a1, duel);
    expect((await env.LEADERBOARD_MEMBERS.getByName(a1.player_id).partyRead(Date.now())).settled).not.toContain(duel.duel_id);
    const meter = countingEnv(Object.assign({ ...env }, ON) as Env);
    await ok(call("/v1/duels", "GET", a1, undefined, ON, {}, meter.env));
    expect(meter.calls).toEqual(["PLAYERS.authorize", "LEADERBOARD_MEMBERS.partyRead", "LEADERBOARD_MEMBERS.partyRead", "LEADERBOARD_BOARDS.duelRead"]);
    expect(await lines(a1)).toEqual([["duelwin:" + duel.duel_id, 250]]);
  }, 60_000);

  it("pay once when two phones of each winner and the lobby read at the same moment", async () => {
    const { a1, a2, duel } = await ended();
    const before = [await balanceOf(a1), await balanceOf(a2)];
    const answers = await Promise.all([detail(a1, duel), detail(a1, duel), detail(a2, duel), detail(a2, duel), lobby(a1), lobby(a2)]);
    for (const answer of answers.slice(0, 4) as Detail[]) expect(answer.win_bonus).toEqual({ amount: 250, counted: true });
    expect([await balanceOf(a1), await balanceOf(a2)]).toEqual(before.map(value => value + 250));
    for (const account of [a1, a2]) expect(await lines(account)).toEqual([["duelwin:" + duel.duel_id, 250]]);
    for (const account of [a1, a2]) expect((await counted(account, duel)).calls).toEqual(LATER);
  }, 60_000);

  it("pay nothing twice when the receipt is lost after the wallet paid, and keep it on the next read", async () => {
    const { a1, duel } = await ended();
    const before = await balanceOf(a1);
    const lost = faulty(env, "LEADERBOARD_BOARDS", "duelReceipt", async () => { throw new Error("lost before the receipt"); });
    expect((await counted(a1, duel, lost)).answer.win_bonus).toEqual({ amount: 250, counted: true });
    expect(await receipts(duel.duel_id)).toEqual({});
    const next = await counted(a1, duel);
    expect(next.answer.win_bonus).toEqual({ amount: 250, counted: true });
    expect(next.calls).toEqual(FIRST_WIN);
    expect((await counted(a1, duel)).calls).toEqual(LATER);
    expect(await balanceOf(a1)).toBe(before + 250);
    expect(await lines(a1)).toEqual([["duelwin:" + duel.duel_id, 250]]);
  }, 60_000);

  it("keep no receipt when the wallet failed, so the next read pays", async () => {
    const { a1, duel } = await ended();
    const before = await balanceOf(a1);
    const down = faulty(env, "PLAYERS", "creditDuelWin", async () => { throw new Error("wallet unreachable"); });
    expect((await counted(a1, duel, down)).answer.win_bonus).toBeUndefined();
    expect(await receipts(duel.duel_id)).toEqual({});
    expect(await balanceOf(a1)).toBe(before);
    expect((await counted(a1, duel)).answer.win_bonus).toEqual({ amount: 250, counted: true });
    expect(await balanceOf(a1)).toBe(before + 250);
    expect((await counted(a1, duel)).calls).toEqual(LATER);
  }, 60_000);

  it("keep no receipt and no id for a player erased mid payout, before or after the wallet answered", async () => {
    const { a1, a2, duel } = await ended();
    const erase = (account: Account) => async (real: Real, ...args: unknown[]) => {
      expect((await call("/v1/identity", "DELETE", account)).status).toBe(200);
      return real(...args);
    };
    // Erased after the wallet paid, before the receipt: the board no longer seats them, so nothing is kept.
    await counted(a1, duel, faulty(env, "LEADERBOARD_BOARDS", "duelReceipt", erase(a1)));
    // Erased before the wallet: it refuses, and nothing is kept either.
    await (await call(`/v1/duels/${duel.board}/${duel.duel_id}`, "GET", a2, undefined, ON, {}, faulty(env, "PLAYERS", "creditDuelWin", erase(a2)))).text();
    const text = await row(duel.duel_id);
    for (const account of [a1, a2]) expect(text).not.toContain(account.player_id);
    expect(await receipts(duel.duel_id)).toEqual({});
  }, 60_000);

  it("drop a player's receipt when their account is erased after it was kept", async () => {
    const { a1, b1, duel } = await ended();
    await counted(a1, duel);
    await counted(b1, duel);
    expect(Object.keys(await receipts(duel.duel_id)).sort()).toEqual(["0", "2"]);
    expect((await call("/v1/identity", "DELETE", a1)).status).toBe(200);
    expect(Object.keys(await receipts(duel.duel_id))).toEqual(["2"]);
    expect((await counted(b1, duel)).calls).toEqual(LATER);
  }, 60_000);

  it("keep nothing for a duel that ends while its read is in flight, and pay on the read after", async () => {
    await checksOn(ON.CONFIG);
    const { a1, a2, b1, b2 } = await pairs();
    const { duel, joinedA, joinedB } = await friendRooms(a1, a2, b1, b2);
    await play(joinedA, [a1, a2], await relayRun(0));
    const run = await relayRun(40);
    const last = run.turns.pop()!;
    const replies = await play(joinedB, [b1, b2], run);
    const before = await balanceOf(a1);
    // The board answers the running duel, then B's last turn ends it before the read replies.
    const racing = faulty(env, "LEADERBOARD_BOARDS", "duelRead", async (real, ...args) => {
      const read = await real(...args);
      await ok(call(`/v2/rooms/${joinedB.room_id}/turns`, "POST", [b1, b2][last[0]], turn(replies[replies.length - 1].room, last[1], last[2])));
      return read;
    });
    const stale = await counted(a1, duel, racing);
    expect(stale.answer.duel.status).toBe("running");
    expect(stale.answer.win_bonus).toBeUndefined();
    expect(await receipts(duel.duel_id)).toEqual({});
    const won = await counted(a1, duel);
    expect([won.answer.duel.status, won.answer.win_bonus]).toEqual(["decided", { amount: 250, counted: true }]);
    expect(won.calls).toEqual(FIRST_WIN);
    expect(await balanceOf(a1)).toBe(before + 250);
  }, 60_000);

  it("keep nothing while Pollen is off, and pay once it is on", async () => {
    const { a1, duel } = await ended();
    const before = await balanceOf(a1);
    const off = await counted(a1, duel, env, NO_POLLEN);
    expect([off.answer.pay, off.answer.win_bonus]).toEqual([undefined, undefined]);
    expect(off.calls).toEqual(LATER);
    expect(await receipts(duel.duel_id)).toEqual({});
    expect((await counted(a1, duel)).calls).toEqual(FIRST_WIN);
    expect(await balanceOf(a1)).toBe(before + 250);
  }, 60_000);

  it("stay safe for older code, which asks the wallet again and gets the same once only line, and for a receipt it does not know", async () => {
    const { a1, b1, duel } = await ended();
    const first = await counted(a1, duel);
    const before = await balanceOf(a1);
    // Older code's read and lobby ask the wallet again whatever the row keeps: the same line answers, nothing more is paid.
    const stored = JSON.parse(await row(duel.duel_id)) as { sides: { pair_key: string }[]; result: { decided_ms: number } };
    const again = await env.PLAYERS.getByName(a1.player_id).creditDuelWin(a1.player_id, { duel_id: duel.duel_id, opponent: stored.sides[1].pair_key, decided_ms: stored.result.decided_ms });
    expect(again).toMatchObject({ ok: true, value: { amount: 250, counted: true } });
    expect(await balanceOf(a1)).toBe(before);
    // A receipt in a shape this code does not know is left alone and the pay asked again, once only.
    await runInDurableObject(env.LEADERBOARD_BOARDS.getByName(RELAY), async (_, ctx) => {
      ctx.storage.sql.exec("UPDATE duels SET data=json_set(data,'$.receipts.\"0\"',json('{\"v\":99}')) WHERE duel_id=?", duel.duel_id);
    });
    const unknown = await counted(a1, duel);
    expect(unknown.answer.win_bonus).toEqual(first.answer.win_bonus);
    expect(unknown.calls).toEqual(FIRST_WIN);
    expect((await receipts(duel.duel_id))["0"]).toEqual({ v: 99 });
    expect(await balanceOf(a1)).toBe(before);
    // Reads and actions on the board keep the receipts.
    await counted(b1, duel);
    await ok(call(`/v1/duels/${RELAY}/${duel.duel_id}/leave`, "POST", b1, { schema_version: 1 }));
    expect(Object.keys(await receipts(duel.duel_id)).sort()).toEqual(["0", "2"]);
  }, 60_000);

  it("pay the first win over Our run once and answer later reads of the race from its row", async () => {
    await checksOn(ON.CONFIG);
    const { a1, a2 } = await pairs();
    const race = (await ok<{ duel: DuelView }>(call("/v1/duels/ghost", "POST", a1, { schema_version: 1, idempotency_key: crypto.randomUUID(), board: RELAY, source: "developer", entry_id: null }))).duel;
    const room = await ok<RoomSnapshotV2>(openRoom(a1, race));
    const joined = await ok<RoomSnapshotV2>(call("/v2/rooms/join", "POST", a2, { invite_code: room.invite_code }));
    await play(joined, [a1, a2], await relayRun(-5));
    const first = await counted(a2, race);
    expect(first.answer.ghost_bonus).toEqual({ amount: 100, counted: true });
    expect(first.calls).toEqual(["PLAYERS.authorize", "LEADERBOARD_BOARDS.duelRead", "PLAYERS.duelRoomPay", "PLAYERS.creditGhostWin", "LEADERBOARD_BOARDS.duelReceipt"]);
    const later = await counted(a2, race);
    expect(later.calls).toEqual(LATER);
    expect([later.answer.ghost_bonus, later.answer.pay]).toEqual([first.answer.ghost_bonus, first.answer.pay]);
    expect(await lines(a2)).toEqual([["ghostwin:" + RELAY, 100]]);
  }, 60_000);
});
