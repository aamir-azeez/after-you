import { encodeProof } from "../src/leaderboards/proofs";
import type { CheckpointV2 } from "../src/v2/protocol";
import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { CHAPTERS } from "../src/v2/chapters";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { boardKey, boardKeys, developerBest } from "../src/leaderboards/boards";
import { DEVELOPER_BESTS } from "../src/leaderboards/developer-bests";
import { JOB_TOKEN_LABEL, deriveJobToken } from "../src/leaderboards/job-token";
import { compareRuns, holdsFor, strictlyFirst, TOP_PLACES, KEPT_RANKED, MAX_UNCHECKED, MAX_CHECKED, MAX_WAITING_PER_MEMBER, MAX_REPLAY_BYTES, MIN_ACCOUNT_AGE_MS, MIN_PARTNERS } from "../src/leaderboards/rules";
import { entryId, finishedRun, pairKey, runTicks, type LeaderboardRun } from "../src/leaderboards/run";
import { eligible, playerStanding, type Standing } from "../src/leaderboards/standing";
import { VIEW_TTL_MS, cachedView, forgetViews, storeView } from "../src/leaderboards/view-cache";
import { forgetReplays } from "../src/leaderboards/replays";
import { bytesDigest, decodeBlob, ENCODING_DEFLATE } from "../src/blob-codec";
import { emptyView, type BoardView } from "../src/leaderboards/view";
import { countingEnv, meterAllRows, meterRows } from "./meter";
import { PLATFORM_LINKS_OBJECT } from "../src/platform-links";
import { noteFullJourney } from "../src/pollen/wallet";
import { POLLEN_CLIENT, withConfig } from "./config";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import { legacyShippedGhost, legacyShippedTicks } from "../src/duels/legacy-shipped-our-run";
import { blankSide, newGhostRace, type Duel } from "../src/duels/model";
import { OWNER_ALIAS } from "../src/owner";

// Every board has a developers' best now, so a test that needs the "no best yet"
// path clears one board's best here; afterEach puts the real values back.
const bests = vi.hoisted(() => ({ live: {} as Record<string, number | null>, real: {} as Record<string, number | null> }));
vi.mock("../src/leaderboards/developer-bests", async original => {
  const actual = await original<typeof import("../src/leaderboards/developer-bests")>();
  Object.assign(bests.real, actual.DEVELOPER_BESTS);
  return { DEVELOPER_BESTS: Object.assign(bests.live, actual.DEVELOPER_BESTS) };
});

// Synthetic identities only: every account here is made by POST /v1/identity in the test runtime.
type Account = { player_id: string; device_token: string; recovery_code: string };
const OPERATOR = "o".repeat(43);
type Vars = Record<string, unknown>;
const ON: Vars = { features: ["LEADERBOARDS"], DISPLAY_NAMES_ENABLED: "true", SAFETY_OPERATOR_TOKEN: OPERATOR };
const OFF: Vars = { ...ON, features: [] };
const RELAY_BOARD = "relay-isles@2";
const RELAY_TICKS = [firstA, firstB, secondA, secondB].reduce((sum, turn) => sum + turn.duration_ticks, 0);
const DAY = 86_400_000;
let address = 0;

function configured(vars: Vars = ON, base: Env = env): Env { return withConfig(Object.assign({ ...base }, vars)) as Env; }
async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Vars = ON, headers: Record<string, string> = {}, target: Env = configured(vars)): Promise<Response> {
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), target);
}
async function create(): Promise<Account> { const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201); return made.json<Account>(); }
function turn(room: RoomSnapshotV2, recording: unknown, checkpoint?: unknown, idempotency_key = crypto.randomUUID()) {
  return { base_revision: room.revision, branch: room.branch, idempotency_key, recording, ...(checkpoint === undefined ? {} : { checkpoint }) };
}
async function submit(room: RoomSnapshotV2, account: Account, body: unknown, vars = ON, target?: Env): Promise<Response> {
  return call(`/v2/rooms/${room.room_id}/turns`, "POST", account, body, vars, {}, target);
}

type Any = Record<string, unknown>;
async function rerecord(input: Any): Promise<Any> { const body = { ...input }; delete body.recording_hash; return { ...input, recording_hash: await digest(canonicalJson(body)) }; }
async function rehash(input: Any): Promise<Any> { const body = { ...input }; delete body.checkpoint_hash; delete body.proof; return { ...input, checkpoint_hash: await digest(canonicalJson(body)) }; }
/**
 * The Relay fixtures with catch assistance off, every hash and link redone. The
 * server checks structure and hashes, not physics, so it accepts them; only the
 * offline replay (the Godot job) would find they no longer replay.
 */
async function unassistedRelay() {
  const a1 = await rerecord({ ...firstA, catch_assistance: false });
  const b1 = await rerecord({ ...firstB, catch_assistance: false, source_recording_hash: a1.recording_hash });
  const mid = await rehash({ ...middle, a_recording_hash: a1.recording_hash, b_recording_hash: b1.recording_hash, proof: { ...(middle.proof as Any), a: a1, b: b1 } });
  const a2 = await rerecord({ ...secondA, catch_assistance: false, checkpoint_hash: mid.checkpoint_hash });
  const b2 = await rerecord({ ...secondB, catch_assistance: false, checkpoint_hash: mid.checkpoint_hash, source_recording_hash: a2.recording_hash });
  const fin = await rehash({ ...final, previous_checkpoint_hash: mid.checkpoint_hash, a_recording_hash: a2.recording_hash, b_recording_hash: b2.recording_hash, proof: { previous_checkpoint: mid, a: a2, b: b2 } });
  return { a1, b1, mid, a2, b2, fin };
}
/** A Relay room played up to its final turn (catch assistance off unless `assisted`); `last` sends it. */
async function almostDone(host?: Account, guest?: Account, vars = ON, assisted = false) {
  host ??= await create(); guest ??= await create();
  const t = assisted ? { a1: firstA, b1: firstB, mid: middle, a2: secondA, b2: secondB, fin: final } : await unassistedRelay();
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), level_id: "relay-isles", level_version: 2, definition_hash: CHAPTERS[0].adapter.key.definition_hash }, vars);
  expect(made.status).toBe(200);
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }, vars);
  let room = await joined.json<RoomSnapshotV2>();
  for (const [who, recording, checkpoint] of [[host, t.a1], [guest, t.b1, t.mid], [guest, t.a2]] as [Account, unknown, unknown?][]) {
    const answer = await submit(room, who, turn(room, recording, checkpoint), vars); expect(answer.status).toBe(200);
    room = (await answer.json<MutationV2>()).room;
  }
  const body = turn(room, t.b2, t.fin);
  return { host, guest, room, body, final: t.fin, last: (vars2 = vars, target?: Env) => submit(room, host!, body, vars2, target) };
}
/** Makes an account old enough and gives it turns alongside two partners, as its room index would show. */
async function season(account: Account, partners = 2, ageDays = 8): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => {
    ctx.storage.sql.exec("UPDATE identity SET data=json_set(data,'$.created_at',?) WHERE id=1", new Date(Date.now() - ageDays * DAY).toISOString());
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS room_index (room_id TEXT PRIMARY KEY, api_version INTEGER NOT NULL, state TEXT NOT NULL, activity_ms INTEGER NOT NULL, observed_at INTEGER NOT NULL, checked_at INTEGER NOT NULL, entry TEXT)");
    for (let index = 0; index < partners; index++) {
      const entry = { ok: true, value: { membership: { host_id: account.player_id, guest_id: `partner${index}`.padEnd(22, "x"), you_are_host: true }, revision: 5 } };
      ctx.storage.sql.exec("INSERT INTO room_index VALUES (?,?,?,?,?,?,?)", `room${index}`.padEnd(22, "r"), 2, "finished", 0, 0, 0, JSON.stringify(entry));
    }
  });
}
const operator = (action: string, body: unknown, token = OPERATOR, vars = ON) => call(`/operator/leaderboards/${action}`, "POST", undefined, body, vars, { Authorization: "Bearer " + token });
const board = (key = RELAY_BOARD) => env.LEADERBOARD_BOARDS.getByName(key);
async function view(key = RELAY_BOARD, vars = ON): Promise<BoardView> { const read = await call(`/v1/leaderboards/${key}`, "GET", undefined, undefined, vars); expect(read.status).toBe(200); return read.json<BoardView>(); }
async function runJob(): Promise<{ entries: { board: string; entry_id: string; ticks: number; proof_hash: string; checkpoint: unknown }[] }> {
  const pending = await operator("pending", { schema_version: 1 }, await deriveJobToken(OPERATOR));
  expect(pending.status).toBe(200);
  return pending.json();
}
async function pass(entries: { board: string; entry_id: string; ticks: number; proof_hash: string }[], valid = true, delta = 0) {
  const answer = await operator("verdicts", { schema_version: 1, verdicts: entries.map(entry => ({ board: entry.board, entry_id: entry.entry_id, proof_hash: entry.proof_hash, valid, measured_ticks: entry.ticks + delta, reason: valid ? "" : "replay_mismatch" })) }, await deriveJobToken(OPERATOR));
  expect(answer.status).toBe(200);
  return answer.json<{ ranked: string[] }>();
}

/** A synthetic run for the board's own ordering rules. */
let serial = 0;
async function run(ticks: number, finished_ms: number, members: [string, string] = [`a${++serial}`.padEnd(22, "a"), `b${serial}`.padEnd(22, "b")]): Promise<LeaderboardRun & { checkpoint: CheckpointV2 }> {
  const checkpoint = { stage_index: 2, marker: serial } as never as CheckpointV2;
  return { schema_version: 1, board: RELAY_BOARD, entry_id: await entryId(`room${++serial}`.padEnd(22, "z"), 0), pair_key: await pairKey(...members), members, ticks,
    finished_at: new Date(finished_ms).toISOString(), finished_ms, chapter: { ...CHAPTERS[0].adapter.key }, simulation_version: 8, checkpoint, proof: await encodeProof(checkpoint) };
}
async function rankDirect(entry: LeaderboardRun, best: number | null = 1, owner: string | null = null) {
  const stub = board();
  await stub.submit(RELAY_BOARD, entry, undefined, owner);
  await stub.standings(RELAY_BOARD, [{ entry_id: entry.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
  const work = await stub.pendingWork();
  const mine = work.replay.find(item => item.entry_id === entry.entry_id)!;
  return stub.verdicts(RELAY_BOARD, [{ entry_id: entry.entry_id, proof_hash: mine.proof_hash, valid: true, measured_ticks: entry.ticks, reason: "" }], best, 0, owner);
}

beforeEach(async () => { await forgetViews(boardKeys()); forgetReplays(); });
afterEach(async () => { Object.assign(bests.live, bests.real); await reset(); });

describe("leaderboard rules", () => {
  it("orders by ticks, then by when the last turn was accepted", () => {
    expect(compareRuns({ ticks: 10, finished_ms: 5, entry_id: "b" }, { ticks: 11, finished_ms: 1, entry_id: "a" })).toBeLessThan(0);
    expect(compareRuns({ ticks: 10, finished_ms: 1, entry_id: "b" }, { ticks: 10, finished_ms: 2, entry_id: "a" })).toBeLessThan(0);
    expect(strictlyFirst(10, [{ ticks: 10 }])).toBe(false);
    expect(strictlyFirst(9, [{ ticks: 10 }])).toBe(true);
  });
  it("ranks any checked run straight away, however fast, and holds only a run on a board with no best yet", () => {
    expect(holdsFor(1, 100, null)).toEqual([]);
    expect(holdsFor(1, 100, 100)).toEqual([]);
    expect(holdsFor(500, null, null)).toEqual(["no_developer_best"]);
  });
  it("has one board per chapter version and a developers' best slot for each", () => {
    expect(new Set(boardKeys()).size).toBe(boardKeys().length);
    expect(Object.keys(DEVELOPER_BESTS).sort()).toEqual([...boardKeys()].sort());
    for (const row of CHAPTERS) expect(boardKeys().includes(boardKey(row.adapter.key)), boardKey(row.adapter.key)).toBe(row.flag === "");
    for (const key of boardKeys()) expect(developerBest(key)).toBe(bests.real[key]);
    bests.live[RELAY_BOARD] = null;
    expect(developerBest(RELAY_BOARD)).toBeNull();
  });
  it("lets any account with an identity rank while the account check is relaxed, and never one without", () => {
    // Relaxed on 2026-10-29 (rules.ts): no account age, no partner count.
    expect([MIN_ACCOUNT_AGE_MS, MIN_PARTNERS]).toEqual([0, 0]);
    const now = Date.now(), fresh: Standing = { created_ms: now, display_name: null, partners: 0 };
    expect(eligible(fresh, now)).toBe(true);
    expect(eligible({ ...fresh, created_ms: now - 8 * DAY, partners: 2 }, now)).toBe(true);
    expect(eligible(null, now)).toBe(false);
  });
  it("times a whole unassisted run and refuses an assisted or partial one", async () => {
    const { fin, mid } = await unassistedRelay();
    expect(runTicks(fin as never, 2)).toEqual({ ticks: RELAY_TICKS, simulation_version: firstA.simulation_version });
    expect(runTicks(mid as never, 2)).toBeNull();
    // The fixtures as recorded had catch assistance on, which never ranks.
    expect(runTicks(final as never, 2)).toBeNull();
    const assisted = structuredClone(fin) as { proof: { b: { catch_assistance: boolean } } };
    assisted.proof.b.catch_assistance = true;
    expect(runTicks(assisted as never, 2)).toBeNull();
  });
});

describe("posting finished runs", () => {
  it("posts only a final turn, with one board request, and leaves the reply unchanged", async () => {
    const off = await almostDone(undefined, undefined, OFF), on = await almostDone();
    const { value: plain, rows: plainRows } = await meterAllRows(() => off.last(OFF));
    const meter = countingEnv(configured(ON));
    const { value: posted, rows } = await meterAllRows(() => on.last(ON, meter.env));
    expect(posted.status).toBe(200);
    const [a, b] = [await plain.json<MutationV2>(), await posted.json<MutationV2>()];
    expect(Object.keys(b).sort()).toEqual(Object.keys(a).sort());
    expect(JSON.stringify(b)).not.toContain("pair_key");
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual(["LEADERBOARD_BOARDS.submit"]);
    console.log(`final turn with a post: ${meter.calls.length} DO requests (${meter.calls.join(", ")}), ${rows.written} rows written; the same turn with leaderboards off: ${plainRows.written}`);
    const shown = await view();
    expect(shown.top).toEqual([]);
    expect(shown.checking).toEqual([await entryId(on.room.room_id, on.room.branch)]);
    // A second run on the same board: the board's tables already exist.
    const again = await almostDone();
    const { rows: againRows } = await meterAllRows(() => again.last());
    console.log(`final turn posting to a board that already has tables: ${againRows.written} rows written (turn alone: ${plainRows.written})`);
    // Earlier turns never post.
    const early = await almostDone(), counted = countingEnv(configured(ON));
    expect(counted.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual([]);
    void early;
  });
  it("checks the accounts itself when the board's unchecked runs are full, so runs without an account cannot crowd out real players", async () => {
    // The full pool holds runs whose players have no identity; they never qualify.
    for (let index = 0; index < MAX_UNCHECKED; index++) await board().submit(RELAY_BOARD, await run(5, 5000 + index));
    // Since the account check was relaxed (rules.ts), a brand-new pair qualifies like a seasoned one.
    const newcomers = await almostDone();
    expect((await newcomers.last()).status).toBe(200);
    const host = await create(), guest = await create();
    await season(host); await season(guest);
    const real = await almostDone(host, guest), meter = countingEnv(configured(ON));
    expect((await real.last(ON, meter.env)).status).toBe(200);
    console.log(`final turn on a crowded board: ${meter.calls.filter(name => name.startsWith("LEADERBOARD") || name === "PLAYERS.leaderboardStanding").join(", ")}`);
    const replay = (await board().pendingWork()).replay.map(item => item.entry_id).sort();
    expect(replay).toEqual([await entryId(real.room.room_id, real.room.branch), await entryId(newcomers.room.room_id, newcomers.room.branch)].sort());
  });
  it("answers a retried final turn as known, so the run is posted once", async () => {
    const played = await almostDone();
    expect((await played.last()).status).toBe(200);
    expect((await submit(played.room, played.host, played.body)).status).toBe(200);
    expect((await view()).checking).toHaveLength(1);
  });
  it("posts nothing for a run with catch assistance on", async () => {
    const played = await almostDone(undefined, undefined, ON, true);
    const meter = countingEnv(configured(ON));
    expect((await played.last(ON, meter.env)).status).toBe(200);
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual([]);
  });
  it("posts nothing while the flag is off", async () => {
    const played = await almostDone(undefined, undefined, OFF);
    const meter = countingEnv(configured(OFF));
    expect((await played.last(OFF, meter.env)).status).toBe(200);
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual([]);
    expect((await call(`/v1/leaderboards/${RELAY_BOARD}`, "GET", undefined, undefined, OFF)).status).toBe(401);
  });
  it("while off, deletes an account that never touched leaderboards with one read and stores nothing", async () => {
    const account = await create(), meter = countingEnv(configured(OFF));
    expect((await call("/v1/identity", "DELETE", account, undefined, OFF, {}, meter.env)).status).toBe(200);
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual(["LEADERBOARD_MEMBERS.read"]);
    expect(await env.LEADERBOARD_MEMBERS.getByName(account.player_id).read()).toEqual({ schema_version: 1, show_name: false, boards: [], revision: 0 });
  });
  it("while off, an operator name clear on an account that never touched leaderboards only reads, so its deletion still stores nothing", async () => {
    const account = await create(), meter = countingEnv(configured(OFF));
    const cleared = await call(`/operator/safety/players/${account.player_id}/clear-name`, "POST", undefined, { schema_version: 1 }, OFF, { Authorization: "Bearer " + OPERATOR }, meter.env);
    expect(cleared.status).toBe(200);
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual(["LEADERBOARD_MEMBERS.read"]);
    expect(await env.LEADERBOARD_MEMBERS.getByName(account.player_id).read()).toEqual({ schema_version: 1, show_name: false, boards: [], revision: 0 });
    const deleting = countingEnv(configured(OFF));
    expect((await call("/v1/identity", "DELETE", account, undefined, OFF, {}, deleting.env)).status).toBe(200);
    expect(deleting.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual(["LEADERBOARD_MEMBERS.read"]);
    expect(await env.LEADERBOARD_MEMBERS.getByName(account.player_id).read()).toEqual({ schema_version: 1, show_name: false, boards: [], revision: 0 });
  });
  it("skips the board when the cached board already holds ten faster runs", async () => {
    for (let index = 0; index < TOP_PLACES; index++) await rankDirect(await run(10 + index, 1000 + index));
    await view(); // caches the full board
    const played = await almostDone(), meter = countingEnv(configured(ON));
    expect((await played.last(ON, meter.env)).status).toBe(200);
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual([]);
  });
});

describe("board reads", () => {
  it("serves a cached board without any Durable Object request, and never shows ids", async () => {
    const entry = await run(100, 1000);
    await rankDirect(entry);
    const first = countingEnv(configured(ON));
    const read = await call(`/v1/leaderboards/${RELAY_BOARD}`, "GET", undefined, undefined, ON, {}, first.env);
    expect(first.calls).toEqual(["LEADERBOARD_BOARDS.view"]);
    const body = await read.text();
    for (const id of [...entry.members, entry.pair_key]) expect(body).not.toContain(id);
    const second = countingEnv(configured(ON));
    await call(`/v1/leaderboards/${RELAY_BOARD}`, "GET", undefined, undefined, ON, {}, second.env);
    expect(second.calls).toEqual([]);
    console.log(`board view: cold ${first.calls.length} DO request, cached ${second.calls.length}`);
  });
  it("answers 404 for a board that is not a known chapter version", async () => {
    const someone = await create();
    expect((await call("/v1/leaderboards/relay-isles@9", "GET", someone)).status).toBe(404);
  });
});

describe("board ordering", () => {
  it("ranks a faster run that finished earlier but was verified later above, and both keep the Gold leaf", async () => {
    const later = await run(100, 2000), earlier = await run(90, 1000);
    await board().submit(RELAY_BOARD, earlier);
    await rankDirect(later);
    let shown = await board().view(RELAY_BOARD);
    expect(shown.top.map(row => row.entry_id)).toEqual([later.entry_id]);
    expect(shown.top[0].gold_leaf).toBe(true);
    await board().standings(RELAY_BOARD, [{ entry_id: earlier.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    const work = await board().pendingWork();
    await board().verdicts(RELAY_BOARD, [{ entry_id: earlier.entry_id, proof_hash: work.replay[0].proof_hash, valid: true, measured_ticks: 90, reason: "" }], 1);
    shown = await board().view(RELAY_BOARD);
    expect(shown.top.map(row => row.entry_id)).toEqual([earlier.entry_id, later.entry_id]);
    expect(shown.top[0].gold_leaf).toBe(true);
    for (const member of later.members) expect((await board().rewardsFor(member)).map(grant => grant.reward).sort()).toEqual(["gold_leaf", "top10_ribbon"]);
    for (const member of earlier.members) expect((await board().rewardsFor(member)).map(grant => grant.reward).sort()).toEqual(["gold_leaf", "top10_ribbon"]);
  });
  it("gives a tie for first to the earlier finish, and no Gold leaf to a run that only ties", async () => {
    const late = await run(100, 2000), early = await run(100, 1000);
    await board().submit(RELAY_BOARD, early);
    await rankDirect(late);
    await board().standings(RELAY_BOARD, [{ entry_id: early.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    const work = await board().pendingWork();
    await board().verdicts(RELAY_BOARD, [{ entry_id: early.entry_id, proof_hash: work.replay[0].proof_hash, valid: true, measured_ticks: 100, reason: "" }], 1);
    const shown = await board().view(RELAY_BOARD);
    expect(shown.top.map(row => row.entry_id)).toEqual([early.entry_id, late.entry_id]);
    expect(shown.top[0].gold_leaf).toBe(false);
    expect((await board().rewardsFor(early.members[0])).map(grant => grant.reward)).toEqual(["top10_ribbon"]);
    expect((await board().rewardsFor(late.members[0])).map(grant => grant.reward).sort()).toEqual(["gold_leaf", "top10_ribbon"]);
  });
  it("keeps one entry per pair, their best", async () => {
    const pair: [string, string] = ["p".repeat(22), "q".repeat(22)];
    const slow = await run(200, 1000, pair), fast = await run(150, 2000, [pair[1], pair[0]]);
    await rankDirect(slow);
    expect((await board().submit(RELAY_BOARD, await run(250, 3000, pair))).status).toBe("not_placed");
    await rankDirect(fast);
    const shown = await board().view(RELAY_BOARD);
    expect(shown.top.map(row => row.entry_id)).toEqual([fast.entry_id]);
    // The slower run's ribbon stays.
    expect((await board().rewardsFor(pair[0])).filter(grant => grant.entry_id === slow.entry_id).map(grant => grant.reward)).toContain("top10_ribbon");
  });
  it("refuses a run ten faster runs beat", async () => {
    for (let index = 0; index < TOP_PLACES; index++) await rankDirect(await run(10 + index, 1000 + index));
    expect((await board().submit(RELAY_BOARD, await run(20, 1))).status).toBe("not_placed");
  });
  it("never lets unchecked runs push anyone out, and takes a checked run past them", async () => {
    for (let index = 0; index < MAX_UNCHECKED; index++) expect((await board().submit(RELAY_BOARD, await run(5, 5000 + index))).status).toBe("checking");
    const real = await run(50, 1);
    expect((await board().submit(RELAY_BOARD, real)).status).toBe("crowded");
    const checked = { entry_id: real.entry_id, eligible: true, reason: "", members: [{ show: true, name: "Ada", rev: 1 }, { show: false, name: null, rev: 1 }] };
    expect((await board().submit(RELAY_BOARD, real, { ...checked, eligible: false })).status).toBe("ineligible");
    expect((await board().submit(RELAY_BOARD, real, checked)).status).toBe("checking");
    expect((await board().pendingWork()).replay.map(item => item.entry_id)).toEqual([real.entry_id]);
    // The checked pool keeps its fastest runs.
    for (let index = 1; index < MAX_CHECKED; index++) { const entry = await run(60 + index, 1); expect((await board().submit(RELAY_BOARD, entry, { ...checked, entry_id: entry.entry_id })).status).toBe("checking"); }
    const slow = await run(500, 1);
    expect((await board().submit(RELAY_BOARD, slow, { ...checked, entry_id: slow.entry_id })).status).toBe("busy");
    const quick = await run(40, 1);
    expect((await board().submit(RELAY_BOARD, quick, { ...checked, entry_id: quick.entry_id })).status).toBe("checking");
    expect((await board().pendingWork()).replay).toHaveLength(MAX_CHECKED);
  });
  it("leaves no tombstone for a run pushed out of the full checked pool, so its retry is taken again, and unchecked posts push nobody out", async () => {
    const ranked = await run(30, 1);
    await rankDirect(ranked);
    const checkedFor = (entry: LeaderboardRun) => ({ entry_id: entry.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 1 }, { show: false, name: null, rev: 1 }] });
    const pool: LeaderboardRun[] = [];
    for (let index = 0; index < MAX_CHECKED; index++) { const entry = await run(60 + index, 1); pool.push(entry); expect((await board().submit(RELAY_BOARD, entry, checkedFor(entry))).status).toBe("checking"); }
    // A flood of unchecked posts fills its own pool, then answers crowded: the checked and ranked runs stay.
    for (let index = 0; index < MAX_UNCHECKED; index++) expect((await board().submit(RELAY_BOARD, await run(2, 9000 + index))).status).toBe("checking");
    expect((await board().submit(RELAY_BOARD, await run(1, 1))).status).toBe("crowded");
    expect((await board().pendingWork()).replay.map(item => item.entry_id).sort()).toEqual(pool.map(entry => entry.entry_id).sort());
    expect((await board().view(RELAY_BOARD)).top.map(row => row.entry_id)).toEqual([ranked.entry_id]);
    // A faster checked run pushes out the slowest; that run's retry is a new post, never "known".
    const quick = await run(40, 1), pushed = pool[pool.length - 1];
    expect((await board().submit(RELAY_BOARD, quick, checkedFor(quick))).status).toBe("checking");
    expect((await board().submit(RELAY_BOARD, pushed)).status).toBe("crowded");
    expect((await board().submit(RELAY_BOARD, pushed, checkedFor(pushed))).status).toBe("busy");
    // Once the fast one fails its replay, the pushed out run's retry is taken.
    const work = await board().pendingWork();
    await board().verdicts(RELAY_BOARD, [{ entry_id: quick.entry_id, proof_hash: work.replay.find(item => item.entry_id === quick.entry_id)!.proof_hash, valid: false, measured_ticks: 0, reason: "mismatch" }], 1);
    expect((await board().submit(RELAY_BOARD, pushed, checkedFor(pushed))).status).toBe("checking");
    await runInDurableObject(board(), async (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT outcome FROM lb_outcomes WHERE outcome='crowded'").toArray()).toEqual([]);
    });
  });
  it("lets one player wait in at most MAX_WAITING_PER_MEMBER other pairs' runs, and again once one is judged", async () => {
    const player = "w".repeat(22), partner = (n: number) => `m${n}`.padEnd(22, "m");
    const entries: LeaderboardRun[] = [];
    for (let n = 0; n < MAX_WAITING_PER_MEMBER; n++) { const entry = await run(100 + n, 1, [player, partner(n)]); entries.push(entry); expect((await board().submit(RELAY_BOARD, entry)).status).toBe("checking"); }
    const extra = await run(50, 1, [partner(9), player]);
    expect((await board().submit(RELAY_BOARD, extra)).status).toBe("busy");
    expect((await board().submit(RELAY_BOARD, extra, { entry_id: extra.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 1 }, { show: false, name: null, rev: 1 }] })).status).toBe("busy");
    // Someone else posts as before.
    expect((await board().submit(RELAY_BOARD, await run(50, 1))).status).toBe("checking");
    // One of the player's runs is judged (here, found ineligible): the next post is taken.
    await board().standings(RELAY_BOARD, [{ entry_id: entries[0].entry_id, eligible: false, reason: "erased", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    expect((await board().submit(RELAY_BOARD, extra)).status).toBe("checking");
  });
  it("sends a run the job could not judge to a person, and never writes an older name choice over a newer one", async () => {
    const entry = await run(100, 1000);
    await board().submit(RELAY_BOARD, entry);
    await board().setMember(RELAY_BOARD, entry.members[0], false, null, 5);
    await board().standings(RELAY_BOARD, [{ entry_id: entry.entry_id, eligible: true, reason: "", members: [{ show: true, name: "Ada", rev: 3 }, { show: true, name: "Bo", rev: 3 }] }]);
    await runInDurableObject(board(), async (_, ctx) => {
      const data = JSON.parse(String(ctx.storage.sql.exec("SELECT data FROM lb_entries").one().data));
      expect(data.members.map((member: { show: boolean; name: string | null }) => [member.show, member.name])).toEqual([[false, null], [true, "Bo"]]);
    });
    const work = await board().pendingWork();
    await board().verdicts(RELAY_BOARD, [{ entry_id: entry.entry_id, proof_hash: work.replay[0].proof_hash, valid: false, measured_ticks: 0, reason: "replay_error" }], 1);
    expect((await board().reviewList()).map(item => [item.entry_id, item.holds])).toEqual([[entry.entry_id, ["replay_error"]]]);
  });
  it("drops a failed replay or a time that does not match, and ignores a verdict on another proof", async () => {
    const fake = await run(100, 1000), wrong = await run(100, 1001);
    for (const entry of [fake, wrong]) {
      await board().submit(RELAY_BOARD, entry);
      await board().standings(RELAY_BOARD, [{ entry_id: entry.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    }
    const work = await board().pendingWork();
    const hash = (id: string) => work.replay.find(item => item.entry_id === id)!.proof_hash;
    await board().verdicts(RELAY_BOARD, [{ entry_id: fake.entry_id, proof_hash: "0".repeat(64), valid: true, measured_ticks: 100, reason: "" }], 1);
    expect((await board().view(RELAY_BOARD)).checking).toHaveLength(2);
    await board().verdicts(RELAY_BOARD, [{ entry_id: fake.entry_id, proof_hash: hash(fake.entry_id), valid: false, measured_ticks: 100, reason: "" },
      { entry_id: wrong.entry_id, proof_hash: hash(wrong.entry_id), valid: true, measured_ticks: 99, reason: "" }], 1);
    const shown = await board().view(RELAY_BOARD);
    expect(shown.top).toEqual([]);
    expect(shown.checking).toEqual([]);
    // A dropped run never comes back on a retried post.
    expect((await board().submit(RELAY_BOARD, fake)).status).toBe("known");
  });
  it("keeps a few ranked runs below the top 10", async () => {
    for (let index = 0; index < KEPT_RANKED + 2; index++) await rankDirect(await run(200 - index, 1000 + index));
    await runInDurableObject(board(), async (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT COUNT(*) AS n FROM lb_entries WHERE state='ranked'").one().n).toBe(KEPT_RANKED);
    });
    expect((await board().view(RELAY_BOARD)).top).toHaveLength(TOP_PLACES);
  });
  it("holds a run for a person, and a strike takes the run and its rewards", async () => {
    const first = await run(100, 1000);
    await rankDirect(first);
    const held = await run(10, 500);
    await rankDirect(held, null);
    let review = await board().reviewList();
    expect(review.map(item => [item.entry_id, item.holds])).toEqual([[held.entry_id, ["no_developer_best"]]]);
    expect((await board().view(RELAY_BOARD)).checking).toEqual([held.entry_id]);
    await board().review(RELAY_BOARD, held.entry_id, true);
    expect((await board().view(RELAY_BOARD)).top.map(row => [row.entry_id, row.gold_leaf])).toEqual([[held.entry_id, true], [first.entry_id, false]]);
    await board().strike(RELAY_BOARD, held.entry_id);
    expect(await board().rewardsFor(held.members[0])).toEqual([]);
    const shown = await board().view(RELAY_BOARD);
    expect(shown.top.map(row => [row.entry_id, row.gold_leaf])).toEqual([[first.entry_id, true]]);
    expect((await board().rewardsFor(first.members[0])).map(grant => grant.reward).sort()).toEqual(["gold_leaf", "top10_ribbon"]);
    review = await board().reviewList();
    expect(review).toEqual([]);
  });
  it("takes the rewards of a struck run even after the pair's faster run replaced it", async () => {
    const pair: [string, string] = ["s".repeat(22), "t".repeat(22)];
    const fake = await run(100, 1000, pair), faster = await run(90, 2000, pair);
    await rankDirect(fake);
    await rankDirect(faster);
    expect((await board().rewardsFor(pair[0])).filter(grant => grant.entry_id === fake.entry_id)).not.toEqual([]);
    expect((await board().strike(RELAY_BOARD, fake.entry_id)).done).toBe(true);
    expect((await board().rewardsFor(pair[0])).filter(grant => grant.entry_id === fake.entry_id)).toEqual([]);
    expect((await board().view(RELAY_BOARD)).top.map(row => row.entry_id)).toEqual([faster.entry_id]);
  });
  it("gives the Gold leaf to a run a strike leaves strictly first", async () => {
    const fake = await run(100, 2000), tied = await run(100, 1000);
    await board().submit(RELAY_BOARD, tied);
    await rankDirect(fake);
    await board().standings(RELAY_BOARD, [{ entry_id: tied.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    const work = await board().pendingWork();
    await board().verdicts(RELAY_BOARD, [{ entry_id: tied.entry_id, proof_hash: work.replay[0].proof_hash, valid: true, measured_ticks: 100, reason: "" }], 1);
    expect((await board().rewardsFor(tied.members[0])).map(grant => grant.reward)).toEqual(["top10_ribbon"]);
    await board().strike(RELAY_BOARD, fake.entry_id);
    expect((await board().rewardsFor(tied.members[0])).map(grant => grant.reward).sort()).toEqual(["gold_leaf", "top10_ribbon"]);
    expect((await board().view(RELAY_BOARD)).top[0].gold_leaf).toBe(true);
  });
});

describe("the replay job and the person's review", () => {
  it("checks accounts, hands out proofs, and ranks a passed run; the job credential cannot review", async () => {
    const host = await create(), guest = await create();
    await season(host); await season(guest);
    bests.live[RELAY_BOARD] = null;
    const played = await almostDone(host, guest);
    expect((await played.last()).status).toBe(200);
    const meter = countingEnv(configured(ON));
    const pendingCall = await call("/operator/leaderboards/pending", "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + await deriveJobToken(OPERATOR) }, meter.env);
    const { entries } = await pendingCall.json<{ entries: { board: string; entry_id: string; ticks: number; proof_hash: string; byte_length: number; body: string }[] }>();
    console.log(`hourly pull with one new run: ${meter.calls.length} DO requests (${boardKeys().length} boards)`);
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({ board: RELAY_BOARD, ticks: RELAY_TICKS });
    // The run goes out in the shared blob format: its body decodes to the canonical checkpoint its hash names.
    expect(entries[0]).not.toHaveProperty("checkpoint");
    const sent = await decodeBlob(Uint8Array.from(atob(entries[0].body), char => char.charCodeAt(0)), entries[0].byte_length);
    expect(JSON.parse(new TextDecoder().decode(sent!))).toEqual(played.final);
    expect(await bytesDigest(sent!)).toBe(entries[0].proof_hash);
    // No developers' best yet: the passed run waits for a person.
    expect((await pass(entries)).ranked).toEqual([]);
    expect((await operator("review", { schema_version: 1, board: RELAY_BOARD, entry_id: entries[0].entry_id, action: "approve" }, await deriveJobToken(OPERATOR))).status).toBe(403);
    const list = await (await operator("review-list", { schema_version: 1 })).json<{ boards: { board: string; entries: { holds: string[] }[] }[] }>();
    expect(list.boards[0].entries[0].holds).toEqual(["no_developer_best"]);
    expect((await operator("review", { schema_version: 1, board: RELAY_BOARD, entry_id: entries[0].entry_id, action: "approve" })).status).toBe(200);
    const shown = await view();
    expect(shown.top).toMatchObject([{ rank: 1, ticks: RELAY_TICKS, names: null, gold_leaf: true }]);
    expect((await board().rewardsFor(host.player_id)).map(grant => grant.reward).sort()).toEqual(["gold_leaf", "top10_ribbon"]);
    // Nothing left to do.
    expect((await runJob()).entries).toEqual([]);
  });
  it("ranks a brand-new pair with no other partners once the replay passes, reading no partners", async () => {
    const host = await create(), guest = await create();
    const played = await almostDone(host, guest);
    await played.last();
    const meter = countingEnv(configured(ON));
    const pending = await call("/operator/leaderboards/pending", "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + await deriveJobToken(OPERATOR) }, meter.env);
    const { entries } = await pending.json<{ entries: { board: string; entry_id: string; ticks: number; proof_hash: string }[] }>();
    expect(entries).toHaveLength(1);
    expect(meter.calls.filter(name => name === "PLAYERS.leaderboardStanding")).toHaveLength(2);
    // The standing never reads the room index while MIN_PARTNERS is 0.
    for (const account of [host, guest])
      await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, ctx) => {
        ctx.storage.sql.exec("DROP TABLE IF EXISTS room_index");
        expect(playerStanding(ctx.storage, { player_id: account.player_id, state: "active", created_at: new Date().toISOString() })?.partners).toBe(0);
      });
    await pass(entries);
    await operator("review", { schema_version: 1, board: RELAY_BOARD, entry_id: entries[0].entry_id, action: "approve" });
    expect((await view()).top).toMatchObject([{ rank: 1, entry_id: entries[0].entry_id }]);
  });
  it("still drops a run when a player was erased before the check", async () => {
    const host = await create(), guest = await create();
    const played = await almostDone(host, guest);
    await played.last();
    expect((await call("/v1/identity", "DELETE", guest)).status).toBe(200);
    expect((await runJob()).entries).toEqual([]);
    expect((await view()).checking).toEqual([]);
  });
  it("derives the job credential exactly as scripts/leaderboard-job-token.mjs does", async () => {
    expect(JOB_TOKEN_LABEL).toBe("after-you leaderboard replay job v1");
    // scripts/leaderboard-job-token.test.mjs pins the same value for the script.
    expect(await deriveJobToken(OPERATOR)).toBe("fuUHqWRoTemuAoI-8DEgp8eiGMj_zGBq6GzaHBLQRqs");
    expect(await deriveJobToken(OPERATOR)).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });
  it("refuses other credentials, and reads as disabled while the flag is off", async () => {
    expect((await operator("pending", { schema_version: 1 }, "x".repeat(43))).status).toBe(401);
    expect((await operator("pending", { schema_version: 1 }, await deriveJobToken("y".repeat(43)))).status).toBe(401);
    const off = await operator("pending", { schema_version: 1 }, await deriveJobToken(OPERATOR), OFF);
    expect(off.status).toBe(503);
    expect((await off.json<{ error: { code: string } }>()).error.code).toBe("leaderboards_disabled");
  });
  it("drops a run the replay rejects", async () => {
    const host = await create(), guest = await create();
    await season(host); await season(guest);
    const played = await almostDone(host, guest);
    await played.last();
    const { entries } = await runJob();
    await pass(entries, true, 1);
    expect(await view()).toMatchObject({ top: [], checking: [] });
  });
});

/** A real pair's run, played, checked, held for a person (the relay board's best cleared), approved and ranked first. */
async function rankedPair() {
  bests.live[RELAY_BOARD] = null;
  const host = await create(), guest = await create();
  for (const [account, name] of [[host, "Ada"], [guest, "Bo"]] as [Account, string][]) {
    await season(account);
    expect((await call("/v1/profile/name", "PUT", account, { schema_version: 1, display_name: name, revision: 1 })).status).toBe(200);
  }
  const played = await almostDone(host, guest);
  await played.last();
  const { entries } = await runJob();
  await pass(entries);
  await operator("review", { schema_version: 1, board: RELAY_BOARD, entry_id: entries[0].entry_id, action: "approve" });
  return { host, guest, room: played.room };
}

describe("names and privacy", () => {
  const show = (account: Account, value: boolean) => call("/v1/leaderboards/me", "PUT", account, { schema_version: 1, show_name: value });
  it("shows names only once both players opt in, and hides them again when one opts out", async () => {
    const { host, guest } = await rankedPair();
    expect((await (await call("/v1/leaderboards/me", "GET", host)).json<{ show_name: boolean }>()).show_name).toBe(false);
    expect((await view()).top[0].names).toBeNull();
    expect((await show(host, true)).status).toBe(200);
    expect((await view()).top[0].names).toBeNull();
    await show(guest, true);
    expect((await view()).top[0].names).toEqual(["Ada", "Bo"]);
    await call("/v1/profile/name", "PUT", guest, { schema_version: 1, display_name: "Cy", revision: 2 });
    expect((await view()).top[0].names).toEqual(["Ada", "Cy"]);
    await show(host, false);
    expect((await view()).top[0].names).toBeNull();
    // The same choice again writes no row: neither the member nor any board (it only repairs a board that missed it).
    const member = env.LEADERBOARD_MEMBERS.getByName(host.player_id) as unknown as DurableObjectStub;
    const repeat = await meterRows({ member, board: board() as unknown as DurableObjectStub }, () => show(host, false));
    expect(repeat.value.status).toBe(200);
    expect(repeat.rows.member.written).toBe(0); expect(repeat.rows.board.written).toBe(0);
    // Repeated again within MEMBER_REPEAT_GAP_MS, the boards are not even asked, and the answer is retryable so the phone keeps the choice.
    const counted = countingEnv(withConfig({ ...env, ...ON }));
    const quiet = await worker.fetch(new Request("https://leaderboards.test/v1/leaderboards/me", { method: "PUT", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.77", "X-Player-Id": host.player_id, Authorization: "Bearer " + host.device_token },
      body: JSON.stringify({ schema_version: 1, show_name: false }) }), counted.env);
    expect(quiet.status).toBe(429); expect(counted.calls.filter(name => name.startsWith("LEADERBOARD_BOARDS."))).toEqual([]);
  });
  it("takes a name off the boards when an operator clears it, and forgets an erased account", async () => {
    const { host, guest } = await rankedPair();
    await show(host, true); await show(guest, true);
    expect((await call(`/operator/safety/players/${guest.player_id}/clear-name`, "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + OPERATOR })).status).toBe(200);
    expect((await view()).top[0].names).toBeNull();
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    expect(await board().rewardsFor(host.player_id)).toEqual([]);
    expect((await board().rewardsFor(guest.player_id)).length).toBe(2);
    expect((await view()).top).toHaveLength(1);
    await runInDurableObject(board(), async (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT data FROM lb_entries").toArray().map(row => String(row.data)).join()).not.toContain(host.player_id);
    });
  });
  it("lets a player report a ranked run once", async () => {
    await rankedPair();
    const reporter = await create(), id = (await view()).top[0].entry_id;
    const path = `/v1/leaderboards/${RELAY_BOARD}/entries/${id}/report`;
    expect((await call(path, "POST", reporter, { schema_version: 1 })).status).toBe(200);
    expect((await call(path, "POST", reporter, { schema_version: 1 })).status).toBe(200);
    expect((await call(`/v1/leaderboards/${RELAY_BOARD}/entries/${"0".repeat(32)}/report`, "POST", reporter, { schema_version: 1 })).status).toBe(404);
    const list = await (await operator("review-list", { schema_version: 1 })).json<{ boards: { entries: { reports: number }[] }[] }>();
    expect(list.boards[0].entries[0].reports).toBe(1);
  });
});

describe("kept replays", () => {
  type ReplayAnswer = { schema_version: number; board: string; entry_id: string; rank: number; ticks: number; names: string[] | null; digest: string; byte_length: number; body: string };
  const replayPath = (id: string, key = RELAY_BOARD) => `/v1/leaderboards/${key}/replay/${id}`;
  const kept = async () => runInDurableObject(board(), async (_, ctx) => ctx.storage.sql.exec<{ entry_id: string }>("SELECT entry_id FROM lb_replays ORDER BY entry_id").toArray().map(row => row.entry_id));
  async function decoded(answer: ReplayAnswer): Promise<unknown> {
    const body = Uint8Array.from(atob(answer.body), char => char.charCodeAt(0));
    const bytes = await decodeBlob(body, answer.byte_length);
    expect(bytes).not.toBeNull();
    expect(await bytesDigest(bytes!)).toBe(answer.digest);
    return JSON.parse(new TextDecoder().decode(bytes!));
  }

  it("reads a run stored raw before the blob format, sends it encoded, and keeps it as its replay", async () => {
    const legacy = await run(100, 1000);
    const stub = board();
    await stub.submit(RELAY_BOARD, legacy);
    await stub.standings(RELAY_BOARD, [{ entry_id: legacy.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    // Put it back as an older board stored it: raw text, no blob row.
    const text = canonicalJson(legacy.checkpoint), hash = await digest(text);
    await runInDurableObject(stub, async (_, ctx) => {
      ctx.storage.sql.exec("DELETE FROM lb_proof_blobs");
      ctx.storage.sql.exec("INSERT INTO lb_proofs VALUES (?,?,?)", legacy.entry_id, hash, text);
    });
    const work = await stub.pendingWork();
    const item = work.replay.find(entry => entry.entry_id === legacy.entry_id)!;
    expect(item).toMatchObject({ proof_hash: hash, byte_length: new TextEncoder().encode(text).byteLength });
    expect(item).not.toHaveProperty("checkpoint");
    await runInDurableObject(stub, async (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT COUNT(*) AS n FROM lb_proofs").one().n).toBe(0);
      expect(ctx.storage.sql.exec("SELECT COUNT(*) AS n FROM lb_proof_blobs").one().n).toBe(1);
    });
    const answer = await stub.verdicts(RELAY_BOARD, [{ entry_id: legacy.entry_id, proof_hash: hash, valid: true, measured_ticks: legacy.ticks, reason: "" }], 1);
    expect(answer.ranked.map(note => note.entry_id)).toEqual([legacy.entry_id]);
    expect(answer.view.top[0].replay_hash).toBe(hash);
  });

  it("drops a raw run whose text no longer matches its hash, never sending it", async () => {
    const legacy = await run(100, 1000);
    const stub = board();
    await stub.submit(RELAY_BOARD, legacy);
    await stub.standings(RELAY_BOARD, [{ entry_id: legacy.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    await runInDurableObject(stub, async (_, ctx) => {
      ctx.storage.sql.exec("DELETE FROM lb_proof_blobs");
      ctx.storage.sql.exec("INSERT INTO lb_proofs VALUES (?,?,?)", legacy.entry_id, "0".repeat(64), canonicalJson(legacy.checkpoint));
    });
    expect((await stub.pendingWork()).replay).toEqual([]);
    expect((await stub.view(RELAY_BOARD)).checking).toEqual([]);
  });

  it("takes a verdict on a raw run handed out before the blob format, converting it then", async () => {
    const legacy = await run(100, 1000);
    const stub = board();
    await stub.submit(RELAY_BOARD, legacy);
    await stub.standings(RELAY_BOARD, [{ entry_id: legacy.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    const text = canonicalJson(legacy.checkpoint), hash = await digest(text);
    await runInDurableObject(stub, async (_, ctx) => {
      ctx.storage.sql.exec("DELETE FROM lb_proof_blobs");
      ctx.storage.sql.exec("INSERT INTO lb_proofs VALUES (?,?,?)", legacy.entry_id, hash, text);
    });
    const answer = await stub.verdicts(RELAY_BOARD, [{ entry_id: legacy.entry_id, proof_hash: hash, valid: true, measured_ticks: legacy.ticks, reason: "" }], 1);
    expect(answer.view.top[0]).toMatchObject({ entry_id: legacy.entry_id, replay_hash: hash });
  });

  it("keeps the replay of each top 10 run, deflated with the hash of its canonical checkpoint, and deletes it once the run is pushed below place 10", async () => {
    // Within 0.85 of each other, so no run waits for a person (rules.ts WIDE_MARGIN_RATIO).
    const slow = await run(115, 1000);
    const meterRank = await meterRows({ board: board() }, () => rankDirect(slow));
    const hash = await digest(canonicalJson(slow.checkpoint));
    expect((await board().view(RELAY_BOARD)).top[0].replay_hash).toBe(hash);
    await runInDurableObject(board(), async (_, ctx) => {
      const row = ctx.storage.sql.exec<{ proof_hash: string; byte_length: number; body: ArrayBuffer }>("SELECT proof_hash,byte_length,body FROM lb_replays").one();
      const bytes = await decodeBlob(new Uint8Array(row.body), row.byte_length);
      expect([row.proof_hash, new TextDecoder().decode(bytes!)]).toEqual([hash, canonicalJson(slow.checkpoint)]);
      expect(new Uint8Array(row.body)[0]).toBe(ENCODING_DEFLATE);
      expect(ctx.storage.sql.exec("SELECT COUNT(*) AS n FROM lb_proofs").one().n).toBe(0);
      expect(ctx.storage.sql.exec("SELECT COUNT(*) AS n FROM lb_proof_blobs").one().n).toBe(0);
    });
    const faster: LeaderboardRun[] = [];
    for (let index = 0; index < TOP_PLACES; index++) { faster.push(await run(100 + index, 2000 + index)); await rankDirect(faster.at(-1)!); }
    const fastest = await run(95, 1);
    const meterPush = await meterRows({ board: board() }, () => rankDirect(fastest));
    console.log(`ranking a run: ${meterRank.rows.board.read} rows read, ${meterRank.rows.board.written} written (first run); one that pushes another below place 10: ${meterPush.rows.board.read} read, ${meterPush.rows.board.written} written`);
    const ranked = await runInDurableObject(board(), async (_, ctx) => ctx.storage.sql.exec<{ entry_id: string }>("SELECT entry_id FROM lb_entries WHERE state='ranked'").toArray().map(row => row.entry_id));
    // The slow run and the slowest of the ten keep their times below the top 10, without replays.
    expect(ranked).toContain(slow.entry_id);
    expect(ranked).toHaveLength(TOP_PLACES + 2);
    const top = (await board().view(RELAY_BOARD)).top;
    expect(await kept()).toEqual(top.map(row => row.entry_id).sort());
    expect(top.every(row => row.replay_hash !== null)).toBe(true);
  });
  it("keeps a held run's replay until the person answers: approve keeps it in the top 10, reject deletes it", async () => {
    const first = await run(100, 1000);
    await rankDirect(first);
    const held = await run(10, 500), refused = await run(11, 600);
    await rankDirect(held, null);
    await rankDirect(refused, null);
    expect((await kept()).sort()).toEqual([first.entry_id, held.entry_id, refused.entry_id].sort());
    // Waiting for a person shows no Watch: only ranked rows are on the board.
    expect((await board().view(RELAY_BOARD)).top.map(row => row.entry_id)).toEqual([first.entry_id]);
    await board().review(RELAY_BOARD, held.entry_id, true);
    await board().review(RELAY_BOARD, refused.entry_id, false);
    expect((await kept()).sort()).toEqual([first.entry_id, held.entry_id].sort());
  });
  it("keeps the replay of a run the job could not judge while a person looks, and of nothing it drops", async () => {
    const unjudged = await run(100, 1000), mismatched = await run(101, 1001);
    for (const entry of [unjudged, mismatched]) {
      await board().submit(RELAY_BOARD, entry);
      await board().standings(RELAY_BOARD, [{ entry_id: entry.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    }
    const work = await board().pendingWork(), hash = (id: string) => work.replay.find(item => item.entry_id === id)!.proof_hash;
    await board().verdicts(RELAY_BOARD, [{ entry_id: unjudged.entry_id, proof_hash: hash(unjudged.entry_id), valid: false, measured_ticks: 0, reason: "unknown_chapter" },
      { entry_id: mismatched.entry_id, proof_hash: hash(mismatched.entry_id), valid: true, measured_ticks: 99, reason: "" }], 1);
    expect(await kept()).toEqual([unjudged.entry_id]);
    await board().review(RELAY_BOARD, unjudged.entry_id, true);
    expect((await board().view(RELAY_BOARD)).top).toMatchObject([{ entry_id: unjudged.entry_id, replay_hash: hash(unjudged.entry_id) }]);
  });
  it("never serves a board view from the data centre cache past its time", async () => {
    const stored = Date.now();
    await storeView(emptyView(RELAY_BOARD), stored);
    expect(await cachedView(RELAY_BOARD, stored + 1000)).not.toBeNull();
    expect(await cachedView(RELAY_BOARD, stored + VIEW_TTL_MS + 1)).toBeNull();
  });
  it("deletes the replay of a struck run and of a run its pair's faster run replaced", async () => {
    const pair: [string, string] = ["u".repeat(22), "v".repeat(22)];
    const older = await run(200, 1000, pair), newer = await run(150, 2000, pair), fake = await run(120, 3000);
    for (const entry of [older, newer, fake]) await rankDirect(entry);
    expect((await kept()).sort()).toEqual([newer.entry_id, fake.entry_id].sort());
    await board().strike(RELAY_BOARD, fake.entry_id);
    expect(await kept()).toEqual([newer.entry_id]);
  });
  it("keeps no replay above MAX_REPLAY_BYTES, and the run still ranks", async () => {
    const big = await run(100, 1000);
    const noise = Array.from({ length: 7 }, () => [...crypto.getRandomValues(new Uint8Array(60_000))].map(byte => byte.toString(16).padStart(2, "0")).join("")).join("");
    (big.checkpoint as unknown as Record<string, unknown>).noise = noise;
    big.proof = await encodeProof(big.checkpoint);
    await rankDirect(big);
    expect((await board().view(RELAY_BOARD)).top).toMatchObject([{ entry_id: big.entry_id, replay_hash: null }]);
    expect(await kept()).toEqual([]);
    expect(MAX_REPLAY_BYTES).toBe(360 * 1024);
  });
  it("serves a top 10 replay to anyone with no ids, for one board request and then none", async () => {
    const { host, guest, room } = await rankedPair();
    const id = (await view()).top[0].entry_id;
    await forgetViews(boardKeys());
    const cold = countingEnv(configured(ON));
    const first = await call(replayPath(id), "GET", undefined, undefined, ON, {}, cold.env);
    expect(first.status).toBe(200);
    expect(cold.calls).toEqual(["LEADERBOARD_BOARDS.replay"]);
    const text = await first.clone().text(), answer = await first.json<ReplayAnswer>();
    for (const secret of [host.player_id, guest.player_id, room.room_id, await pairKey(host.player_id, guest.player_id), host.device_token]) expect(text).not.toContain(secret);
    expect(Object.keys(answer).sort()).toEqual(["board", "body", "byte_length", "digest", "entry_id", "finished_on", "gold_leaf", "names", "rank", "schema_version", "ticks"]);
    expect(answer).toMatchObject({ schema_version: 1, board: RELAY_BOARD, entry_id: id, rank: 1, ticks: RELAY_TICKS, names: null });
    expect(await decoded(answer)).toEqual((await unassistedRelay()).fin);
    const warm = countingEnv(configured(ON));
    expect((await call(replayPath(id), "GET", undefined, undefined, ON, {}, warm.env)).status).toBe(200);
    expect(warm.calls).toEqual([]);
    // A new isolate's memory: the view is cached by the first answer, the body is not.
    forgetReplays();
    const bodyOnly = countingEnv(configured(ON));
    const { rows } = await meterRows({ board: board() }, () => call(replayPath(id), "GET", undefined, undefined, ON, {}, bodyOnly.env));
    expect(bodyOnly.calls).toEqual(["LEADERBOARD_BOARDS.replay"]);
    console.log(`replay view: cold ${cold.calls.length} DO request, cached ${warm.calls.length}, body not cached ${bodyOnly.calls.length} (${rows.board.read} rows read, ${rows.board.written} written); ${answer.body.length} base64 chars for ${answer.byte_length} canonical bytes`);
  });
  it("shows names in a replay only as the board does", async () => {
    const { host, guest } = await rankedPair();
    for (const account of [host, guest]) expect((await call("/v1/leaderboards/me", "PUT", account, { schema_version: 1, show_name: true })).status).toBe(200);
    const id = (await view()).top[0].entry_id;
    expect((await (await call(replayPath(id))).json<ReplayAnswer>()).names).toEqual(["Ada", "Bo"]);
    await call("/v1/leaderboards/me", "PUT", guest, { schema_version: 1, show_name: false });
    expect((await (await call(replayPath(id))).json<ReplayAnswer>()).names).toBeNull();
  });
  it("deletes the replay of a deleted account's run, keeping its time, and refuses it", async () => {
    const { host } = await rankedPair();
    const id = (await view()).top[0].entry_id;
    expect((await call(replayPath(id))).status).toBe(200);
    expect((await call("/v1/identity", "DELETE", host)).status).toBe(200);
    const shown = await view();
    expect(shown.top).toMatchObject([{ entry_id: id, names: null, replay_hash: null }]);
    expect(await kept()).toEqual([]);
    const meter = countingEnv(configured(ON));
    expect((await call(replayPath(id), "GET", undefined, undefined, ON, {}, meter.env)).status).toBe(404);
    expect(meter.calls).toEqual([]);
    await forgetViews(boardKeys()); forgetReplays();
    expect((await call(replayPath(id))).status).toBe(404);
  });
  it("refuses a run below place 10, an unknown run, another board and the flag off", async () => {
    const runs: LeaderboardRun[] = [];
    // The slowest ranks first: a run ten ranked runs beat never enters.
    const eleventh = await run(115, 1000);
    await rankDirect(eleventh);
    for (let index = 0; index < TOP_PLACES; index++) { runs.push(await run(100 + index, 2000 + index)); await rankDirect(runs.at(-1)!); }
    expect((await board().view(RELAY_BOARD)).top.map(row => row.entry_id)).not.toContain(eleventh.entry_id);
    await forgetViews(boardKeys());
    expect((await call(replayPath(eleventh.entry_id))).status).toBe(404);
    expect((await call(replayPath(runs[0].entry_id))).status).toBe(200);
    expect((await call(replayPath("0".repeat(32)))).status).toBe(404);
    expect((await call(replayPath(runs[0].entry_id, "first-steps@1"))).status).toBe(404);
    expect((await call(replayPath(runs[0].entry_id, "relay-isles@9"))).status).not.toBe(200);
    const off = countingEnv(configured(OFF));
    expect((await call(replayPath(runs[0].entry_id), "GET", undefined, undefined, OFF, {}, off.env)).status).not.toBe(200);
    expect(off.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual([]);
  });
});

describe("finishedRun", () => {
  it("names a run as the phone does (game/tests/test_leaderboard_screen.gd pins the same id)", async () => {
    expect(await entryId("A".repeat(22), 3)).toBe("950c0a948aa0ab431b848fba650fa348");
  });
  it("needs the receipt to be the room's latest change and a second player", async () => {
    const played = await almostDone();
    const answer = await (await played.last()).json<MutationV2>();
    expect(await finishedRun(answer, undefined)).toMatchObject({ board: RELAY_BOARD, ticks: RELAY_TICKS });
    expect(await finishedRun(answer, { schema_version: 2 })).toBeNull();
    expect(await finishedRun({ ...answer, room: { ...answer.room, revision: answer.room.revision + 1 } }, undefined)).toBeNull();
    expect(await finishedRun({ ...answer, room: { ...answer.room, guest_id: null } }, undefined)).toBeNull();
  });
});

describe("looks on rows (art 01)", () => {
  const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
  const LOOKS: Vars = { ...ON, features: ["LEADERBOARDS", "POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_LOOKS"], POLLEN_SECRET: SECRET };
  const NO_LOOKS: Vars = { ...LOOKS, features: ["LEADERBOARDS", "POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"] };
  const HAT = { hat: "straw_hat" }, DAISY = { hat: "daisy" };
  const ROW_KEYS = ["entry_id", "finished_on", "gold_leaf", "names", "rank", "replay_hash", "ticks"];
  const shared = env as unknown as Record<string, unknown>;
  beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
  afterEach(() => { delete shared.POLLEN_SECRET; });

  /** Buys and wears `look` through the shop, as the phone would (pollen-looks.test.ts). */
  async function wear(account: Account, look: Record<string, string>): Promise<void> {
    const prices: Record<string, number> = { daisy: 1000, straw_hat: 5000 };
    await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
      noteFullJourney(state.storage, Date.now() + DAY, Date.now());
      state.storage.sql.exec("UPDATE pollen_wallet SET data=json_set(data,'$.balance',100000,'$.earned',100000) WHERE id=1");
    });
    for (const id of Object.values(look)) expect((await call("/v1/pollen/spend", "POST", account, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id, expected_cost: prices[id] }, LOOKS, POLLEN_CLIENT)).status).toBe(200);
    expect((await call("/v1/pollen/equip", "POST", account, { schema_version: 1, idempotency_key: crypto.randomUUID(), revision: Date.now(), look }, LOOKS)).status).toBe(200);
  }
  /** A seasoned pair in a straw hat (host) and a daisy (guest), their run played to its final turn with `vars`. */
  async function dressedPair(vars: Vars = LOOKS) {
    bests.live[RELAY_BOARD] = null;
    const host = await create(), guest = await create();
    await season(host); await season(guest);
    await wear(host, HAT); await wear(guest, DAISY);
    return { host, guest, played: await almostDone(host, guest, vars) };
  }
  async function rankAll(): Promise<void> {
    const { entries } = await runJob();
    await pass(entries);
    for (const entry of entries) await operator("review", { schema_version: 1, board: RELAY_BOARD, entry_id: entry.entry_id, action: "approve" });
  }
  const storedMembers = () => runInDurableObject(board(), async (_, ctx) =>
    ctx.storage.sql.exec<{ data: string }>("SELECT data FROM lb_entries").toArray().map(row => (JSON.parse(row.data) as { members: { look?: unknown }[] }).members));

  it("stores both looks with the run at submit, on the request it already makes, and keeps them out of the reply", async () => {
    const { played } = await dressedPair();
    const meter = countingEnv(configured(LOOKS));
    // The phone asks for every beside field, so the reply is the one that carries the most.
    const everything = { "X-AfterYou-Looks": "1", "X-AfterYou-Display-Names": "1", "X-AfterYou-End-Reactions": "1", "X-AfterYou-Run-Reactions": "1", "X-AfterYou-Pollen": "1", ...POLLEN_CLIENT };
    const send = () => call(`/v2/rooms/${played.room.room_id}/turns`, "POST", played.host, played.body, LOOKS, everything, meter.env);
    const { value: answer, rows } = await meterRows({ board: board() }, send);
    expect(answer.status).toBe(200);
    const reply = await answer.json<Record<string, unknown>>();
    expect(reply.partner_look).toEqual(DAISY);
    expect(reply.pollen).toBeDefined();
    expect(JSON.stringify(reply)).not.toContain("board_looks");
    // A retried final turn (same key) answers the same way and the board knows the run already.
    const retried = await send();
    expect(retried.status).toBe(200);
    expect(await retried.text()).not.toContain("board_looks");
    expect((await board().view(RELAY_BOARD)).checking).toHaveLength(1);
    // The retry finds its run in the board the first post cached (submit.ts postRun), so it asks the board nothing.
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual(["LEADERBOARD_BOARDS.submit"]);
    // Host first, as `members` and `names`.
    const [members] = await storedMembers();
    expect(members.map(member => member.look)).toEqual([HAT, DAISY]);
    // The same run with looks off writes the same board rows: the looks ride in the entry row it already writes.
    await reset(); await forgetViews(boardKeys()); shared.POLLEN_SECRET = SECRET;
    const plain = await dressedPair(NO_LOOKS);
    const { rows: plainRows } = await meterRows({ board: board() }, () => plain.played.last(NO_LOOKS));
    expect(rows.board.written).toBe(plainRows.board.written);
    expect((await storedMembers())[0].map(member => member.look)).toEqual([undefined, undefined]);
    console.log(`final turn with looks and its retry: ${meter.calls.length} DO requests (${meter.calls.join(", ")}); board rows written ${rows.board.written} with looks, ${plainRows.board.written} without`);
  });
  it("keeps both looks on a run posted after its pair linked their platform accounts", async () => {
    const RULE: Vars = { ...LOOKS, features: [...(LOOKS.features as string[]), "LEADERBOARD_REQUIRE_PLATFORM"] };
    const { host, guest, played } = await dressedPair(RULE);
    expect((await played.last(RULE)).status).toBe(200);
    expect((await view(RELAY_BOARD, RULE)).checking).toEqual([]);
    const links = env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT);
    await links.link("play_games", "1".repeat(64), host.player_id, false); await links.link("play_games", "2".repeat(64), guest.player_id, false);
    const posted = await call("/v1/leaderboards/post", "POST", guest, { schema_version: 1, room_id: played.room.room_id }, RULE);
    expect(await posted.json()).toEqual({ schema_version: 1, status: "posted" });
    expect((await storedMembers())[0].map(member => member.look)).toEqual([HAT, DAISY]);
  });

  it("serves a ranked row with both looks, also for a pair that hides its names, from the cached read", async () => {
    const { played } = await dressedPair();
    await played.last(LOOKS);
    await rankAll();
    await forgetViews(boardKeys());
    const cold = countingEnv(configured(LOOKS));
    const shown = await (await call(`/v1/leaderboards/${RELAY_BOARD}`, "GET", undefined, undefined, LOOKS, {}, cold.env)).json<BoardView>();
    expect(cold.calls).toEqual(["LEADERBOARD_BOARDS.view"]);
    expect(shown.top).toHaveLength(1);
    expect(shown.top[0]).toMatchObject({ rank: 1, names: null, looks: [HAT, DAISY] });
    // An older phone reads the same fields plus one it ignores.
    expect(Object.keys(shown.top[0]).sort()).toEqual([...ROW_KEYS, "looks"].sort());
    const warm = countingEnv(configured(LOOKS));
    expect((await (await call(`/v1/leaderboards/${RELAY_BOARD}`, "GET", undefined, undefined, LOOKS, {}, warm.env)).json<BoardView>()).top[0].looks).toEqual([HAT, DAISY]);
    expect(warm.calls).toEqual([]);
    // While looks are off the same cached board reads as it did before looks.
    expect(Object.keys((await view(RELAY_BOARD, ON)).top[0]).sort()).toEqual(ROW_KEYS);
    console.log(`board read with looks: cold ${cold.calls.length} DO request, cached ${warm.calls.length}; row ${JSON.stringify(shown.top[0]).length} bytes`);
  });

  it("shows the looks beside shown names too", async () => {
    const { host, guest, played } = await dressedPair();
    for (const [account, name] of [[host, "Ada"], [guest, "Bo"]] as [Account, string][]) {
      expect((await call("/v1/profile/name", "PUT", account, { schema_version: 1, display_name: name, revision: 1 }, LOOKS)).status).toBe(200);
      expect((await call("/v1/leaderboards/me", "PUT", account, { schema_version: 1, show_name: true }, LOOKS)).status).toBe(200);
    }
    await played.last(LOOKS);
    await rankAll();
    expect((await view(RELAY_BOARD, LOOKS)).top[0]).toMatchObject({ names: ["Ada", "Bo"], looks: [HAT, DAISY] });
  });

  it("takes the erased player's look off the board and its storage; the partner keeps theirs", async () => {
    const { host, played } = await dressedPair();
    await played.last(LOOKS);
    await rankAll();
    expect((await call("/v1/identity", "DELETE", host, undefined, LOOKS)).status).toBe(200);
    expect((await view(RELAY_BOARD, LOOKS)).top[0]).toMatchObject({ names: null, replay_hash: null, looks: [{}, DAISY] });
    const [members] = await storedMembers();
    expect(members.map(member => member.look)).toEqual([undefined, DAISY]);
    expect(JSON.stringify(members)).not.toContain("straw_hat");
  });

  it("stores no looks for a run finished while looks are off, and serves the default for it", async () => {
    const { played } = await dressedPair(NO_LOOKS);
    await played.last(NO_LOOKS);
    await rankAll();
    expect((await view(RELAY_BOARD, LOOKS)).top[0].looks).toEqual([{}, {}]);
  });

  it("serves a stored look the catalogue no longer has as the default, and takes only a whole pair from the room", async () => {
    const entry = { ...await run(100, 1000), looks: [HAT, DAISY] };
    await rankDirect(entry);
    // A look kept before its item left the catalogue.
    await runInDurableObject(board(), async (_, ctx) => {
      ctx.storage.sql.exec("UPDATE lb_entries SET data=json_set(data,'$.members[0].look',json(?)) WHERE entry_id=?", JSON.stringify({ hat: "retired_hat" }), entry.entry_id);
    });
    expect((await board().view(RELAY_BOARD)).top[0].looks).toEqual([{}, DAISY]);
    const played = await almostDone();
    const answer = await (await played.last()).json<MutationV2>();
    expect((await finishedRun(answer, undefined, [DAISY]))?.looks).toBeUndefined();
    expect((await finishedRun(answer, undefined))?.looks).toBeUndefined();
    expect((await finishedRun(answer, undefined, [HAT, DAISY]))?.looks).toEqual([HAT, DAISY]);
  });
});

describe("pairs that share a player", () => {
  it("ranks A and B, then B and C, as two entries, so B is on the board twice", async () => {
    bests.live[RELAY_BOARD] = 1;
    const a = await create(), b = await create(), c = await create();
    const first = await almostDone(a, b), second = await almostDone(c, b);
    expect((await first.last()).status).toBe(200);
    expect((await second.last()).status).toBe(200);
    const { entries } = await runJob();
    expect(entries).toHaveLength(2);
    await pass(entries);
    const ids = [await entryId(first.room.room_id, first.room.branch), await entryId(second.room.room_id, second.room.branch)];
    expect((await board().view(RELAY_BOARD)).top.map(row => row.entry_id).sort()).toEqual(ids.sort());
    expect(await pairKey(a.player_id, b.player_id)).not.toBe(await pairKey(b.player_id, c.player_id));
  });
});

describe("the platform rule (LEADERBOARD_REQUIRE_PLATFORM)", () => {
  const PLATFORM: Vars = { ...ON, features: ["LEADERBOARDS", "LEADERBOARD_REQUIRE_PLATFORM"] };
  const links = () => env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT);
  let external = 0;
  const link = async (account: Account) => {
    expect((await links().link("play_games", (++external).toString(16).padStart(64, "0"), account.player_id, false)).status).toBe("linked");
  };
  const repost = (account: Account, roomId: string, vars = PLATFORM, target?: Env) => call("/v1/leaderboards/post", "POST", account, { schema_version: 1, room_id: roomId }, vars, {}, target);

  it("keeps a run off the board while either player has no platform link, for one read and no row written", async () => {
    for (const linked of [[], ["host"], ["guest"]]) {
      await forgetViews(boardKeys());
      const played = await almostDone(undefined, undefined, PLATFORM);
      for (const who of linked) await link(who === "host" ? played.host : played.guest);
      const meter = countingEnv(configured(PLATFORM));
      const { value: answer, rows } = await meterRows({ board: board() as unknown as DurableObjectStub, links: links() as unknown as DurableObjectStub }, () => played.last(PLATFORM, meter.env));
      expect(answer.status).toBe(200);
      expect(Object.keys(await answer.json<MutationV2>())).not.toContain("leaderboard");
      expect(meter.calls.filter(name => name.startsWith("LEADERBOARD") || name.startsWith("PLATFORM"))).toEqual(["PLATFORM_LINKS.accountsAmong"]);
      expect(rows.links.written + rows.board.written).toBe(0);
      expect(await view(RELAY_BOARD, PLATFORM)).toMatchObject({ top: [], checking: [] });
    }
  });
  it("posts a run both of whose players are linked, any provider, with one more request than without the rule", async () => {
    const played = await almostDone(undefined, undefined, PLATFORM);
    await link(played.host);
    expect((await links().link("game_center", "f".repeat(64), played.guest.player_id, false)).status).toBe("linked");
    const meter = countingEnv(configured(PLATFORM));
    expect((await played.last(PLATFORM, meter.env)).status).toBe(200);
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD") || name.startsWith("PLATFORM"))).toEqual(["PLATFORM_LINKS.accountsAmong", "LEADERBOARD_BOARDS.submit"]);
    expect((await view(RELAY_BOARD, PLATFORM)).checking).toEqual([await entryId(played.room.room_id, played.room.branch)]);
  });
  it("reads no link while the rule is off, and says it is on only while it is", async () => {
    const played = await almostDone();
    const meter = countingEnv(configured(ON));
    expect((await played.last(ON, meter.env)).status).toBe(200);
    expect(meter.calls.filter(name => name.startsWith("PLATFORM"))).toEqual([]);
    const capability = async (vars: Vars) => (await call("/v2/capabilities", "GET", played.host, undefined, vars, { "X-AfterYou-Leaderboards": "1" })).json<Record<string, unknown>>();
    expect(await capability(ON)).not.toHaveProperty("leaderboards_platform_required");
    expect(await capability(PLATFORM)).toMatchObject({ leaderboards_version: 1, leaderboards_platform_required: 1 });
    expect(await capability({ ...ON, features: ["LEADERBOARD_REQUIRE_PLATFORM"] })).not.toHaveProperty("leaderboards_version");
    // The post route is there only while the rule is.
    expect((await repost(played.host, played.room.room_id, ON)).status).toBe(404);
  });
  it("posts the room's run once both have linked since it finished, from either member, and says who is missing until then", async () => {
    const played = await almostDone(undefined, undefined, PLATFORM);
    expect((await played.last(PLATFORM)).status).toBe(200);
    const id = await entryId(played.room.room_id, played.room.branch);
    expect(await (await repost(played.guest, played.room.room_id)).json()).toEqual({ schema_version: 1, status: "platform_required", you: false, partner: false });
    await link(played.host);
    expect(await (await repost(played.guest, played.room.room_id)).json()).toEqual({ schema_version: 1, status: "platform_required", you: false, partner: true });
    expect(await (await repost(played.host, played.room.room_id)).json()).toEqual({ schema_version: 1, status: "platform_required", you: true, partner: false });
    expect((await view(RELAY_BOARD, PLATFORM)).checking).toEqual([]);
    await link(played.guest);
    const meter = countingEnv(configured(PLATFORM));
    expect(await (await repost(played.guest, played.room.room_id, PLATFORM, meter.env)).json()).toEqual({ schema_version: 1, status: "posted" });
    console.log(`posting a room's run after linking: ${meter.calls.join(", ")}`);
    expect(meter.calls.filter(name => !name.startsWith("PLAYERS."))).toEqual(["ROOMS_V2.boardSnapshot", "PLATFORM_LINKS.accountsAmong", "LEADERBOARD_BOARDS.submit"]);
    expect((await view(RELAY_BOARD, PLATFORM)).checking).toEqual([id]);
    // Its time and finish are the room's final turn: the job checks it as any other.
    const { entries } = await runJob();
    expect(entries.map(entry => [entry.entry_id, entry.ticks])).toEqual([[id, RELAY_TICKS]]);
    // Again, from the other member: already there, and the cached board says so with no board request.
    const again = countingEnv(configured(PLATFORM));
    expect(await (await repost(played.host, played.room.room_id, PLATFORM, again.env)).json()).toEqual({ schema_version: 1, status: "posted" });
    expect(again.calls.filter(name => name.startsWith("LEADERBOARD"))).toEqual([]);
    expect((await view(RELAY_BOARD, PLATFORM)).checking).toEqual([id]);
  });
  it("posts nothing for a room that is not a finished run, an assisted one, or someone else's", async () => {
    const played = await almostDone(undefined, undefined, PLATFORM);
    await link(played.host); await link(played.guest);
    expect(await (await repost(played.host, played.room.room_id)).json()).toEqual({ schema_version: 1, status: "not_postable" });
    const assisted = await almostDone(undefined, undefined, PLATFORM, true);
    expect((await assisted.last(PLATFORM)).status).toBe(200);
    await link(assisted.host); await link(assisted.guest);
    expect(await (await repost(assisted.host, assisted.room.room_id)).json()).toEqual({ schema_version: 1, status: "not_postable" });
    expect((await played.last(PLATFORM)).status).toBe(200);
    const stranger = await create();
    expect((await repost(stranger, played.room.room_id)).status).toBe(404);
    expect((await call("/v1/leaderboards/post", "POST", played.host, { schema_version: 1, room_id: "nope" }, PLATFORM)).status).toBe(400);
    expect((await call("/v1/leaderboards/post", "GET", played.host, undefined, PLATFORM)).status).toBe(405);
  });
});

describe("pair keys by platform account (PAIR-KEYS.md)", () => {
  const PLATFORM: Vars = { ...ON, features: ["LEADERBOARDS", "LEADERBOARD_REQUIRE_PLATFORM"] };
  const links = () => env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT);
  const hash = (letter: string) => letter.repeat(64);
  const linkBoth = async (host: Account, guest: Account, accounts: [string, string], replace = false) => {
    expect((await links().link("play_games", hash(accounts[0]), host.player_id, replace)).status).toBe("linked");
    expect((await links().link("game_center", hash(accounts[1]), guest.player_id, replace)).status).toBe("linked");
  };
  const keyed = async (ticks: number, finished_ms: number, members: [string, string], account_key?: string): Promise<LeaderboardRun> => ({ ...await run(ticks, finished_ms, members), ...(account_key ? { account_key } : {}) });
  const entryRows = async () => runInDurableObject(board(), async (_, ctx) => ctx.storage.sql.exec<{ entry_id: string; pair_key: string; state: string; data: string }>("SELECT entry_id,pair_key,state,data FROM lb_entries").toArray());

  it("counts two identity pairs behind the same two platform accounts as one pair, for the same one read", async () => {
    const first = await almostDone(undefined, undefined, PLATFORM);
    await linkBoth(first.host, first.guest, ["a", "b"]);
    expect((await first.last(PLATFORM)).status).toBe(200);
    const firstId = await entryId(first.room.room_id, first.room.branch);
    // The same two people on two new identities: "Keep this phone" moves each link.
    const second = await almostDone(undefined, undefined, PLATFORM);
    await linkBoth(second.host, second.guest, ["a", "b"], true);
    const meter = countingEnv(configured(PLATFORM));
    expect((await second.last(PLATFORM, meter.env)).status).toBe(200);
    expect(meter.calls.filter(name => name.startsWith("LEADERBOARD") || name.startsWith("PLATFORM"))).toEqual(["PLATFORM_LINKS.accountsAmong", "LEADERBOARD_BOARDS.submit"]);
    // An equal time behind the same accounts never enters: the pair's own run finished first.
    expect((await view(RELAY_BOARD, PLATFORM)).checking).toEqual([firstId]);
    // Other accounts are another pair.
    const third = await almostDone(undefined, undefined, PLATFORM);
    await linkBoth(third.host, third.guest, ["c", "d"]);
    expect((await third.last(PLATFORM)).status).toBe(200);
    expect((await view(RELAY_BOARD, PLATFORM)).checking.sort()).toEqual([firstId, await entryId(third.room.room_id, third.room.branch)].sort());
    // The key is kept in the entry's JSON, never in a view.
    const rows = await entryRows();
    const accountKeys = rows.map(row => (JSON.parse(row.data) as { account_key?: string }).account_key);
    expect(accountKeys.every(key => typeof key === "string" && /^[a-f0-9]{64}$/.test(key))).toBe(true);
    const shown = JSON.stringify(await view(RELAY_BOARD, PLATFORM)) + JSON.stringify(await board().view(RELAY_BOARD));
    for (const secret of [...accountKeys as string[], ...rows.map(row => row.pair_key), "account_key", hash("a")]) expect(shown).not.toContain(secret);
  });

  it("matches a pair's entry from before the rule by its player ids, and supersedes it", async () => {
    const members: [string, string] = ["p".repeat(22), "q".repeat(22)];
    const old = await keyed(900, 1_000, members);
    expect((await rankDirect(old)).ranked.map(note => note.entry_id)).toEqual([old.entry_id]);
    // After the flip the same players carry an account key too. A slower run is no better than their own.
    expect((await board().submit(RELAY_BOARD, await keyed(950, 2_000, members, hash("k")))).status).toBe("not_placed");
    const faster = await keyed(800, 3_000, members, hash("k"));
    expect((await rankDirect(faster)).ranked.map(note => note.entry_id)).toEqual([faster.entry_id]);
    expect((await board().view(RELAY_BOARD)).top.map(row => row.entry_id)).toEqual([faster.entry_id]);
    // Other identities behind the same accounts: slower never enters, faster replaces, and the board keeps one row.
    expect((await board().submit(RELAY_BOARD, await keyed(850, 4_000, ["r".repeat(22), "s".repeat(22)], hash("k")))).status).toBe("not_placed");
    const moved = await keyed(700, 5_000, ["r".repeat(22), "s".repeat(22)], hash("k"));
    expect((await rankDirect(moved)).ranked.map(note => note.entry_id)).toEqual([moved.entry_id]);
    expect((await board().view(RELAY_BOARD)).top.map(row => row.entry_id)).toEqual([moved.entry_id]);
    // Rule off again: runs carry no account key and match by player ids only.
    const plain = await keyed(750, 6_000, ["t".repeat(22), "u".repeat(22)]);
    expect((await rankDirect(plain)).ranked.map(note => note.entry_id)).toEqual([plain.entry_id]);
    expect((await board().view(RELAY_BOARD)).top.map(row => row.entry_id)).toEqual([moved.entry_id, plain.entry_id]);
  });

  it("drops the account key with an erased player's id", async () => {
    const members: [string, string] = ["v".repeat(22), "w".repeat(22)];
    await rankDirect(await keyed(900, 1_000, members, hash("e")));
    expect((await entryRows())[0].data).toContain("account_key");
    await board().forget(RELAY_BOARD, members[0]);
    const [row] = await entryRows();
    expect(row.state).toBe("ranked");
    expect(row.data).not.toContain("account_key");
    expect(row.data).not.toContain(members[0]);
  });
});

describe("Our run", () => {
  // A synthetic owner: the id CONFIG's alias would name (owner.ts), handed to the board as the Worker hands it.
  const OWNER = "o".repeat(22);
  const partner = (letter: string): [string, string] => [OWNER, letter.repeat(22)];
  const ourRows = () => runInDurableObject(board(), async (_, ctx) => ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM lb_our_run").one().n);
  // The race the Worker hands the board: an older app's carries the run it shipped, which an app that plays Our run never races.
  const ghostRace = (duelId = "d".repeat(32), plays = true) => board().duelCreate(newGhostRace({ duel_id: duelId, board: RELAY_BOARD, chapter: { ...CHAPTERS[0].adapter.key }, steps: 4, starter: "x".repeat(22),
    a: blankSide(["x".repeat(22), "y".repeat(22)], "k".repeat(64)), ghost: legacyShippedGhost(RELAY_BOARD, 4)! }, Date.now()), plays);
  // Slower than the run older apps shipped (legacyShippedTicks): the owner's first run is Our run whatever its time.
  const T = legacyShippedTicks(RELAY_BOARD)! + 100;

  it("is the owner pair's first checked run, whatever its time, and only a faster owner run replaces it", async () => {
    expect((await board().view(RELAY_BOARD)).our_run).toBeUndefined();
    const first = await run(T - 10, 1000, partner("p"));
    const { rows } = await meterRows({ board: board() }, () => rankDirect(first, 1, OWNER));
    const view = await board().view(RELAY_BOARD);
    expect(view.our_run).toEqual({ entry_id: first.entry_id, ticks: T - 10, replay_hash: view.top[0].replay_hash, names: null, looks: [{}, {}] });
    // Slower than Our run, a faster run of another pair, a failed check, the owner's run with no owner named: none replace it.
    await rankDirect(await run(T - 5, 2000, partner("q")), 1, OWNER);
    await rankDirect(await run(T - 50, 3000), 1, OWNER);
    const failed = await run(T - 70, 5000, partner("s"));
    await board().submit(RELAY_BOARD, failed, undefined, OWNER);
    await board().standings(RELAY_BOARD, [{ entry_id: failed.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    const work = (await board().pendingWork()).replay.find(item => item.entry_id === failed.entry_id)!;
    await board().verdicts(RELAY_BOARD, [{ entry_id: failed.entry_id, proof_hash: work.proof_hash, valid: false, measured_ticks: failed.ticks, reason: "replay_mismatch" }], 1, 0, OWNER);
    expect((await board().view(RELAY_BOARD)).our_run?.entry_id).toBe(first.entry_id);
    await rankDirect(await run(T - 60, 4000, partner("r")), 1, null);
    expect((await board().view(RELAY_BOARD)).our_run?.entry_id).toBe(first.entry_id);
    // A faster owner run, with any partner, takes its one row.
    const faster = await run(T - 80, 6000, partner("t"));
    await rankDirect(faster, 1, OWNER);
    expect((await board().view(RELAY_BOARD)).our_run).toMatchObject({ entry_id: faster.entry_id, ticks: T - 80 });
    // The one row is replaced whole: only the new run's replay copy is kept.
    expect(await ourRows()).toBe(1);
    expect(await runInDurableObject(board(), async (_, ctx) => ctx.storage.sql.exec<{ proof_hash: string }>("SELECT proof_hash FROM lb_our_run").toArray().map(row => row.proof_hash)))
      .toEqual([await digest(canonicalJson(faster.checkpoint))]);
    console.log(`Our run kept with a checked run: ${rows.board.read} rows read, ${rows.board.written} written in all for the post, account check and verdict`);
  });

  it("enters a full board for the check, keeps its replay after the run misses the top 10, and is the only Our run an app that plays it races", async () => {
    for (let index = 0; index < TOP_PLACES; index++) await rankDirect(await run(100 + index, 1000 + index));
    const owners = await run(300, 9000, partner("p"));
    expect((await rankDirect(owners, 1, OWNER)).ranked).toEqual([]);
    const view = await board().view(RELAY_BOARD);
    expect(view.top.map(row => row.entry_id)).not.toContain(owners.entry_id);
    const hash = await digest(canonicalJson(owners.checkpoint));
    expect(view.our_run).toMatchObject({ entry_id: owners.entry_id, ticks: 300, replay_hash: hash });
    // Its replay is served like a top 10 run's, with no place and no names.
    const served = await call(`/v1/leaderboards/${RELAY_BOARD}/replay/${owners.entry_id}`);
    expect(served.status).toBe(200);
    expect(await served.json()).toMatchObject({ entry_id: owners.entry_id, rank: null, ticks: 300, names: null, gold_leaf: false, digest: hash });
    // The duel lobby's race list and a new race against Our run take its time; a retried create keeps the race as made.
    // Only for an app that plays it: an older app keeps the run it shipped (LEGACY), so its own copy still plays.
    const reader = await create(), duels = { ...ON, features: ["LEADERBOARDS", "DUELS"] };
    const listed = async (headers: Record<string, string>) => ((await (await call("/v1/duels/ghosts", "GET", reader, undefined, duels, headers)).json()) as { boards: { board: string; developer: number | null }[] }).boards.find(item => item.board === RELAY_BOARD)!.developer;
    expect(await listed({ "X-AfterYou-Our-Run": "1" })).toBe(300);
    expect(await listed({})).toBe(legacyShippedTicks(RELAY_BOARD));
    const raced = (await ghostRace()) as Duel;
    expect(raced.ghost).toEqual({ source: "developer", entry_id: owners.entry_id, rank: null, ticks: 300, names: null, replay_hash: hash, looks: [{}, {}] });
    expect(((await ghostRace()) as Duel).ghost).toEqual(raced.ghost);
    expect(((await ghostRace("e".repeat(32), false)) as Duel).ghost).toEqual(legacyShippedGhost(RELAY_BOARD, 4));
  });

  it("takes the owner's played run, named by CONFIG's alias, with its time after each turn from its replay", async () => {
    const owner = await create(), mate = await create();
    const owned: Vars = { ...ON, friend_aliases: { [OWNER_ALIAS]: owner.player_id } };
    // Ten faster runs fill the board, and the cached board says so: the post still goes, as the owner's run beats Our run.
    for (let index = 0; index < TOP_PLACES; index++) await rankDirect(await run(100 + index, 1000 + index));
    await view(RELAY_BOARD, owned);
    const played = await almostDone(owner, mate, owned);
    expect((await played.last()).status).toBe(200);
    const { entries } = await (await operator("pending", { schema_version: 1 }, await deriveJobToken(OPERATOR), owned)).json<{ entries: { board: string; entry_id: string; ticks: number; proof_hash: string }[] }>();
    expect(entries.map(entry => entry.ticks)).toEqual([RELAY_TICKS]);
    const verdicts = entries.map(entry => ({ board: entry.board, entry_id: entry.entry_id, proof_hash: entry.proof_hash, valid: true, measured_ticks: entry.ticks, reason: "" }));
    expect((await operator("verdicts", { schema_version: 1, verdicts }, await deriveJobToken(OPERATOR), owned)).status).toBe(200);
    expect((await view(RELAY_BOARD, owned)).our_run).toMatchObject({ entry_id: entries[0].entry_id, ticks: RELAY_TICKS });
    expect(((await ghostRace()) as Duel).ghost!.splits).toEqual([140, 280, 430, RELAY_TICKS]);
  });

  it("shows the pair's looks, and their names only while both show them on boards, on the board, its replay and the race", async () => {
    const HAT = { hat: "straw_hat" }, DAISY = { hat: "daisy" };
    const mine = { ...await run(T - 10, 1000, partner("p")), looks: [HAT, DAISY] };
    await rankDirect(mine, 1, OWNER);
    expect((await board().view(RELAY_BOARD)).our_run).toMatchObject({ names: null, looks: [HAT, DAISY] });
    expect(((await ghostRace()) as Duel).ghost).toMatchObject({ names: null, looks: [HAT, DAISY] });
    await board().setMember(RELAY_BOARD, OWNER, true, "Ada", 1);
    expect((await board().view(RELAY_BOARD)).our_run?.names).toBeNull();
    await board().setMember(RELAY_BOARD, "p".repeat(22), true, "Bo", 1);
    expect((await board().view(RELAY_BOARD)).our_run?.names).toEqual(["Ada", "Bo"]);
    const served = await (await call(`/v1/leaderboards/${RELAY_BOARD}/replay/${mine.entry_id}`)).json<{ names: string[] | null }>();
    expect(served.names).toEqual(["Ada", "Bo"]);
    await board().setMember(RELAY_BOARD, OWNER, false, null, 2);
    expect((await board().view(RELAY_BOARD)).our_run).toMatchObject({ names: null, looks: [HAT, DAISY] });
  });

  it("is gone when either player's account is erased or the run is struck, and a race against it is refused until the owner's next run", async () => {
    expect(await ghostRace()).toBe("ghost_not_found");
    const mine = await run(T - 10, 1000, partner("p"));
    await rankDirect(mine, 1, OWNER);
    await board().forget(RELAY_BOARD, "p".repeat(22));
    expect((await board().view(RELAY_BOARD)).our_run).toBeUndefined();
    expect(await ourRows()).toBe(0);
    expect(await ghostRace()).toBe("ghost_not_found");
    expect(((await ghostRace("e".repeat(32), false)) as Duel).ghost).toEqual(legacyShippedGhost(RELAY_BOARD, 4));
    const again = await run(T - 10, 2000, partner("q"));
    await rankDirect(again, 1, OWNER);
    expect((await board().view(RELAY_BOARD)).our_run?.entry_id).toBe(again.entry_id);
    await board().strike(RELAY_BOARD, again.entry_id);
    expect((await board().view(RELAY_BOARD)).our_run).toBeUndefined();
  });

  it("takes the owner's run that ranked before Our run could move on their next post", async () => {
    const before = await run(T - 30, 1000, partner("p"));
    await rankDirect(before, 1, null);
    expect((await board().view(RELAY_BOARD)).our_run).toBeUndefined();
    const next = await run(T - 5, 2000, partner("p"));
    expect((await board().submit(RELAY_BOARD, next, undefined, OWNER)).status).toBe("not_placed");
    expect((await board().view(RELAY_BOARD)).our_run).toMatchObject({ entry_id: before.entry_id, ticks: T - 30 });
  });
});
