import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { CHAPTERS } from "../src/v2/chapters";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { boardKey, boardKeys, developerBest } from "../src/leaderboards/boards";
import { DEVELOPER_BESTS } from "../src/leaderboards/developer-bests";
import { JOB_TOKEN_LABEL, deriveJobToken } from "../src/leaderboards/job-token";
import { compareRuns, holdsFor, strictlyFirst, TOP_PLACES, KEPT_RANKED, MAX_UNCHECKED, MAX_CHECKED } from "../src/leaderboards/rules";
import { entryId, finishedRun, pairKey, runTicks, type LeaderboardRun } from "../src/leaderboards/run";
import { eligible, type Standing } from "../src/leaderboards/standing";
import { forgetViews } from "../src/leaderboards/view-cache";
import type { BoardView } from "../src/leaderboards/view";
import { countingEnv, meterAllRows } from "./meter";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

// Synthetic identities only: every account here is made by POST /v1/identity in the test runtime.
type Account = { player_id: string; device_token: string; recovery_code: string };
const OPERATOR = "o".repeat(43);
const ON = { V2_ROOMS_ENABLED: "true", FEATURES: "LEADERBOARDS", DISPLAY_NAMES_ENABLED: "true", SAFETY_OPERATOR_TOKEN: OPERATOR };
const OFF = { ...ON, FEATURES: "" };
const RELAY_BOARD = "relay-isles@2";
const RELAY_TICKS = [firstA, firstB, secondA, secondB].reduce((sum, turn) => sum + turn.duration_ticks, 0);
const DAY = 86_400_000;
let address = 0;

function configured(vars: Record<string, string> = ON, base: Env = env): Env { return Object.assign({ ...base }, vars) as Env; }
async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string> = ON, headers: Record<string, string> = {}, target: Env = configured(vars)): Promise<Response> {
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
async function run(ticks: number, finished_ms: number, members: [string, string] = [`a${++serial}`.padEnd(22, "a"), `b${serial}`.padEnd(22, "b")]): Promise<LeaderboardRun> {
  return { schema_version: 1, board: RELAY_BOARD, entry_id: await entryId(`room${++serial}`.padEnd(22, "z"), 0), pair_key: await pairKey(...members), members, ticks,
    finished_at: new Date(finished_ms).toISOString(), finished_ms, chapter: { ...CHAPTERS[0].adapter.key }, simulation_version: 8, checkpoint: { stage_index: 2, marker: serial } as never };
}
async function rankDirect(entry: LeaderboardRun, best: number | null = 1) {
  const stub = board();
  await stub.submit(RELAY_BOARD, entry);
  await stub.standings(RELAY_BOARD, [{ entry_id: entry.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
  const work = await stub.pendingWork();
  const mine = work.replay.find(item => item.entry_id === entry.entry_id)!;
  return stub.verdicts(RELAY_BOARD, [{ entry_id: entry.entry_id, proof_hash: mine.proof_hash, valid: true, measured_ticks: entry.ticks, reason: "" }], best);
}

beforeEach(async () => { await forgetViews(boardKeys()); });
afterEach(async () => { await reset(); });

describe("leaderboard rules", () => {
  it("orders by ticks, then by when the last turn was accepted", () => {
    expect(compareRuns({ ticks: 10, finished_ms: 5, entry_id: "b" }, { ticks: 11, finished_ms: 1, entry_id: "a" })).toBeLessThan(0);
    expect(compareRuns({ ticks: 10, finished_ms: 1, entry_id: "b" }, { ticks: 10, finished_ms: 2, entry_id: "a" })).toBeLessThan(0);
    expect(strictlyFirst(10, [{ ticks: 10 }])).toBe(false);
    expect(strictlyFirst(9, [{ ticks: 10 }])).toBe(true);
  });
  it("holds a run below 0.8 of the developers' best, a wide new first, and any run on a board with no best yet", () => {
    expect(holdsFor(79, 100, null)).toEqual(["below_floor"]);
    expect(holdsFor(80, 100, null)).toEqual([]);
    expect(holdsFor(84, 100, 100)).toEqual(["wide_margin"]);
    expect(holdsFor(85, 100, 100)).toEqual([]);
    expect(holdsFor(500, null, null)).toEqual(["no_developer_best"]);
  });
  it("has one board per chapter version and a developers' best slot for each", () => {
    expect(new Set(boardKeys()).size).toBe(boardKeys().length);
    expect(Object.keys(DEVELOPER_BESTS).sort()).toEqual([...boardKeys()].sort());
    for (const row of CHAPTERS) expect(boardKeys()).toContain(boardKey(row.adapter.key));
    expect(developerBest(RELAY_BOARD)).toBeNull();
  });
  it("needs an account a week old with two partners", () => {
    const now = Date.now(), seasoned: Standing = { created_ms: now - 8 * DAY, display_name: null, partners: 2 };
    expect(eligible(seasoned, now)).toBe(true);
    expect(eligible({ ...seasoned, created_ms: now - 6 * DAY }, now)).toBe(false);
    expect(eligible({ ...seasoned, partners: 1 }, now)).toBe(false);
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
  it("checks the accounts itself when the board's unchecked runs are full, so new accounts cannot crowd out real players", async () => {
    for (let index = 0; index < MAX_UNCHECKED; index++) await board().submit(RELAY_BOARD, await run(5, 5000 + index));
    const newcomers = await almostDone();
    expect((await newcomers.last()).status).toBe(200);
    const host = await create(), guest = await create();
    await season(host); await season(guest);
    const real = await almostDone(host, guest), meter = countingEnv(configured(ON));
    expect((await real.last(ON, meter.env)).status).toBe(200);
    console.log(`final turn on a crowded board: ${meter.calls.filter(name => name.startsWith("LEADERBOARD") || name === "PLAYERS.leaderboardStanding").join(", ")}`);
    const replay = (await board().pendingWork()).replay.map(item => item.entry_id);
    expect(replay).toEqual([await entryId(real.room.room_id, real.room.branch)]);
    expect((await board().view(RELAY_BOARD)).checking).not.toContain(await entryId(newcomers.room.room_id, newcomers.room.branch));
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
    await rankDirect(held, 1000);
    let review = await board().reviewList();
    expect(review.map(item => [item.entry_id, item.holds])).toEqual([[held.entry_id, ["below_floor", "wide_margin"]]]);
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
    const played = await almostDone(host, guest);
    expect((await played.last()).status).toBe(200);
    const meter = countingEnv(configured(ON));
    const pendingCall = await call("/operator/leaderboards/pending", "POST", undefined, { schema_version: 1 }, ON, { Authorization: "Bearer " + await deriveJobToken(OPERATOR) }, meter.env);
    const { entries } = await pendingCall.json<{ entries: { board: string; entry_id: string; ticks: number; proof_hash: string; checkpoint: unknown }[] }>();
    console.log(`hourly pull with one new run: ${meter.calls.length} DO requests (${boardKeys().length} boards)`);
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({ board: RELAY_BOARD, ticks: RELAY_TICKS });
    expect(entries[0].checkpoint).toEqual(played.final);
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
  it("drops a run whose players are too new or have too few partners", async () => {
    const host = await create(), guest = await create();
    await season(host); await season(guest, 1);
    const played = await almostDone(host, guest);
    await played.last();
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

describe("names and privacy", () => {
  async function rankedPair() {
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
    return { host, guest };
  }
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
