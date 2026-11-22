import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { chapter } from "../src/v2/protocol";
import { MAX_OPEN_TURN_TICKS, isFingerprint, turnId, turnSlot } from "../src/v2/open-turns";
import { checkTicks, packRecording } from "../src/v2/recording-codec";
import { MAX_REPLAY_ARCHIVE_BYTES, MAX_ROW_BYTES } from "../src/v2/row-bound";
import { parseRow, type RowData } from "../src/v2/row-codec";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { withConfig } from "./config";
import { countingEnv, meterRows } from "./meter";
import setA from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-a.json";
import setEnd from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-checkpoint.json";
import slackA from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-a.json";
import slackEnd from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-checkpoint.json";

/**
 * Open turns fingerprints at their widest (v2/open-turns.ts): a five stage open turns chapter (Turn of the Tide@3's two
 * stages, repeated) whose every turn is the rules' longest, ten minutes, with a new stick every tick. Nothing nests, so
 * every row, body and archive stays as small at the fifth stage as at the first. The chapter (rules 19) exists only in
 * this file; each turn adds a hand-off tick and two hashes.
 */
type Rec = Record<string, any>;
type Account = { player_id: string; device_token: string };
const FIVE = vi.hoisted(() => ({ level_id: "turn-of-the-tide", level_version: 99, definition_hash: "e".repeat(64) }));
vi.mock("../src/v2/chapters", async original => {
  const actual = await original<typeof import("../src/v2/chapters")>();
  const { journeyAdapter } = await import("../src/v2/protocol-journey");
  const { canonicalJson: canonical, digest: hash } = await import("../src/protocol");
  const definition = structuredClone((await import("../src/v2/turn-of-the-tide-v3.json")).default) as Rec;
  const [set, slack] = definition.stages as Rec[];
  definition.version = FIVE.level_version;
  definition.turn_limits = { a_ticks: 18_000, b_ticks: 18_000 };
  definition.stages = [set, slack, { ...structuredClone(set), id: "set-the-tide-2" }, { ...structuredClone(slack), id: "slack-water-2" }, { ...structuredClone(set), id: "set-the-tide-3" }]
    .map(stage => ({ ...stage, turn_cap: 20 }));
  const { checkpoint_hash: _old, proof, ...body } = { ...structuredClone((await import("../src/v2/turn-of-the-tide-v3-initial.json")).default), level_version: FIVE.level_version, definition_hash: FIVE.definition_hash } as Rec; void _old;
  const ours = [journeyAdapter({ ...definition, simulation_version: 19 } as never, { ...body, checkpoint_hash: await hash(canonical(body)), proof } as never, FIVE.definition_hash)];
  const find = (value: unknown) => value !== null && typeof value === "object" ? ours.find(entry => entry.key.level_id === (value as Rec).level_id && entry.key.level_version === (value as Rec).level_version && entry.key.definition_hash === (value as Rec).definition_hash) : undefined;
  return { ...actual, CHAPTERS: [...actual.CHAPTERS, ...ours.map(adapter => ({ adapter, flag: "" }))],
    chapter: (value: unknown) => find(value) ?? actual.chapter(value),
    chapterKey: (value: unknown) => find(value) ? { ...find(value)!.key } : actual.chapterKey(value),
    chapterFlag: (entry: unknown) => ours.includes(entry as never) ? "" : actual.chapterFlag(entry as never),
    creatable: (entry: unknown, e: Env) => ours.includes(entry as never) || actual.creatable(entry as never, e) };
});

const FLAGS = { NOTIFICATIONS_ENABLED: "false" };
const NEW_CLIENT = [2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 18, 19, 20, 21];
const TICKS = MAX_OPEN_TURN_TICKS;
/** The widest packed turn: a new stick every tick, every check (the server never replays, so stand-in hashes). */
const widestPacked = (ticks: number) => packRecording(Array.from({ length: ticks }, (_, i) => ({ ticks: 1, x: i % 2 ? -100 : 100, z: -100, action: i % 3 === 0 })),
  checkTicks(ticks).map(tick => ({ tick, state_hash: "f".repeat(64) })), ticks);
const PACKED = widestPacked(TICKS);
let address = 0;
function request(path: string, method: string, who?: Account, body?: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.16." + (++address % 250),
    ...(who ? { "X-Player-Id": who.player_id, Authorization: "Bearer " + who.device_token } : {}), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
}
async function json<T>(response: Response | Promise<Response>, status = 200): Promise<T> {
  const result = await response, text = await result.text(); expect(result.status, text).toBe(status); return JSON.parse(text) as T;
}
const call = (path: string, method = "GET", who?: Account, body?: unknown, headers: Record<string, string> = {}, vars: Rec = {}) => worker.fetch(request(path, method, who, body, headers), withConfig({ ...env, ...FLAGS, ...vars }));
const account = () => json<Account>(call("/v1/identity", "POST", undefined, {}), 201);
const stages = () => chapter(FIVE).stages as unknown as Rec[];
async function sealed(body: Rec): Promise<Rec> { const { checkpoint_hash: _old, ...rest } = body; void _old; return { ...rest, checkpoint_hash: await digest(canonicalJson(rest)) }; }

/**
 * The next turn of stage `index` after `turns` (the stage's turns so far), ten minutes long, in a stage pip `first` starts,
 * closing the stage or not. It takes over at its hand-off (the length of the turn under its memory, less the memory's
 * hand-off), with stand-in world hashes. `ticks`: shorter turns for the run a phone posts (a board takes runs up to its
 * proof bound); never assisted, so the run can rank.
 */
async function turn(index: number, first: string, checkpointHash: string, turns: Rec[], closes: boolean, ticks = TICKS): Promise<Rec> {
  const stage = stages()[index], fixture = (index % 2 ? slackA : setA) as Rec, n = turns.length + 1;
  const memory = turns.at(-1), before = turns.at(-2), start = memory?.handoff_hash ?? await digest(`start ${index}`);
  const { actions: _a, replay_checks: _c, recording_hash: _h, ...header } = structuredClone(fixture); void _a; void _c; void _h;
  const body = { ...header, level_version: FIVE.level_version, definition_hash: FIVE.definition_hash, stage_id: stage.id, checkpoint_hash: checkpointHash,
    role: n === 1 ? "a" : "b", player_slot: turnSlot(first, n), duration_ticks: ticks, source_recording_hash: memory ? memory.recording_hash : "", catch_assistance: false,
    completed: n > 1 && closes, outcome: { source_ready: true, objective_complete: n > 1 && closes }, final_state_hash: (await digest(`${index}-${n}`)), packed: ticks === TICKS ? PACKED : widestPacked(ticks),
    handoff_tick: before ? before.duration_ticks - memory!.handoff_tick : 0, start_hash: start, handoff_hash: n === 1 ? start : await digest(`world ${index} ${n} ${ticks}`) };
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}
/** The flat checkpoint closing stage `index`: the fixture's end, both pips at its goal, this stage's controls and levers over the ones before. */
async function closing(index: number, previous: Rec, turns: Rec[]): Promise<Rec> {
  const stage = stages()[index], { proof: _p, a_recording_hash: _a, b_recording_hash: _b, next_first_slot: _n, ...end } = structuredClone((index % 2 ? slackEnd : setEnd) as Rec); void _p; void _a; void _b; void _n;
  const own = (values: Rec, ids: string[]) => Object.fromEntries(Object.entries(values).filter(([id]) => ids.includes(id)));
  // Both pips where the fixture's goal pip ended (a stage may start with either pip).
  const goal = end.players[(index % 2 ? slackA : setA).player_slot === "p0" ? "p1" : "p0"];
  return sealed({ ...end, schema_version: 9, next_first_slot: turns.at(-1)!.player_slot === "p0" ? "p1" : "p0",
    level_version: FIVE.level_version, definition_hash: FIVE.definition_hash, stage_index: index + 1, completed_stage_id: stage.id,
    next_stage_id: stages()[index + 1]?.id ?? "", previous_checkpoint_hash: previous.checkpoint_hash, turn_hashes: turns.map(t => t.recording_hash), players: { p0: { ...goal }, p1: { ...goal } },
    mechanisms: { ...end.mechanisms, controls: { ...previous.mechanisms.controls, ...own(end.mechanisms.controls, stage.controls.map((c: Rec) => c.id)) },
      levers: { ...previous.mechanisms.levers, ...own(end.mechanisms.levers, stage.levers.map((l: Rec) => l.id)) } } });
}
/** Every turn row's id, stored size and whether it is full; pair rows' and the room row's sizes. */
const stored = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), (_, ctx) => {
  const size = (data: RowData) => typeof data === "string" ? new TextEncoder().encode(data).byteLength : data.byteLength;
  const turns = ctx.storage.sql.exec<{ turn_id: string; data: RowData }>("SELECT turn_id,data FROM turns ORDER BY rowid").toArray().map(row => ({ id: row.turn_id, bytes: size(row.data), full: !isFingerprint(parseRow<Rec>(row.data)) }));
  const pairs = ctx.storage.sql.exec<{ data: RowData }>("SELECT data FROM pairs").toArray().map(row => size(row.data));
  return { turns, pairs, room: size(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data) };
});

afterEach(async () => { await reset(); vi.restoreAllMocks(); });

describe("open turns fingerprints at their widest", () => {
  it("plays five stages of ten minute turns with every row, body and archive inside its bound, one room request a turn", async () => {
    const host = await account(), guest = await account(), limits = chapter(FIVE).limits!;
    const made = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { ...FIVE, idempotency_key: crypto.randomUUID() }));
    let room = await json<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: made.invite_code, supported_simulation_versions: NEW_CLIENT }));
    const who = (slot: string) => slot === "p0" ? host : guest, partner = (player: Account) => player === host ? guest : host;
    const plan = [6, 5, 4, 3, 3], widest = { body: 0, reply: 0, row: 0, pair: 0, room: 0 };
    const written = { first: [] as number[], pass: [] as number[], closing: [] as number[], acknowledging_poll: [] as number[], quiet_poll: [] as number[] };
    let checkpoint = room.checkpoint as Rec;
    for (const [index, count] of plan.entries()) {
      const turns: Rec[] = [], first = checkpoint.next_first_slot ?? "p0";
      for (let n = 1; n <= count; n++) {
        const closes = n === count, recording = await turn(index, first, checkpoint.checkpoint_hash, turns, closes);
        const next = closes ? await closing(index, checkpoint, [...turns, recording]) : undefined;
        const body = { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording, ...(next ? { checkpoint: next } : {}) };
        const counting = countingEnv(withConfig({ ...env, ...FLAGS }));
        const sent = await meterRows({ room: env.ROOMS_V2.getByName(room.room_id) }, async () => {
          const response = await worker.fetch(request(`/v2/rooms/${room.room_id}/turns`, "POST", who(recording.player_slot), body), counting.env);
          const text = await response.text(); expect(response.status, text).toBe(200); return text;
        });
        // One room request a turn: the Worker passes the body through and the room does the rest (turn-wire.ts).
        expect(counting.calls.filter(name => name.startsWith("ROOMS_V2."))).toEqual(["ROOMS_V2.turnRequest"]);
        widest.body = Math.max(widest.body, JSON.stringify(body).length); widest.reply = Math.max(widest.reply, sent.value.length);
        written[n === 1 ? "first" : closes ? "closing" : "pass"].push(sent.rows.room.written);
        room = (JSON.parse(sent.value) as MutationV2).room;
        turns.push(recording);
        // Only the newest turn is full, and the last closing turn until its partner acknowledges it.
        const rows = await stored(room.room_id), full = rows.turns.filter(row => row.full).map(row => row.id);
        expect(full).toEqual([turnId(0, index, n)]);
        widest.row = Math.max(widest.row, ...rows.turns.map(row => row.bytes)); widest.pair = Math.max(widest.pair, 0, ...rows.pairs); widest.room = Math.max(widest.room, rows.room);
      }
      checkpoint = room.checkpoint as Rec;
      expect(checkpoint).not.toHaveProperty("proof");
      expect(checkpoint.turn_hashes).toEqual(turns.map(t => t.recording_hash));
      // The partner's poll naming this revision acknowledges the closing turn: one row, no new revision.
      const closer = who(turns.at(-1)!.player_slot), reader = partner(closer), known = { "X-AfterYou-Known-Room": `${room.revision}.${room.branch}` };
      const quiet = await meterRows({ room: env.ROOMS_V2.getByName(room.room_id) }, () => json<Rec>(call(`/v2/rooms/${room.room_id}`, "GET", closer, undefined, known)));
      expect(quiet.value).toMatchObject({ unchanged: true }); written.quiet_poll.push(quiet.rows.room.written);
      const ack = await meterRows({ room: env.ROOMS_V2.getByName(room.room_id) }, () => json<Rec>(call(`/v2/rooms/${room.room_id}`, "GET", reader, undefined, known)));
      expect(ack.value).toMatchObject({ unchanged: true, revision: room.revision }); written.acknowledging_poll.push(ack.rows.room.written);
      expect((await stored(room.room_id)).turns.filter(row => row.full)).toEqual([]);
      expect((await json<RoomSnapshotV2>(call(`/v2/rooms/${room.room_id}`, "GET", reader))).open_turns!.closing).toBeNull();
    }
    expect(room).toMatchObject({ stage_index: 5, active_role: "complete" });
    expect((await stored(room.room_id)).turns).toHaveLength(plan.reduce((sum, n) => sum + n, 0));
    // Every row stays far under its bound at the fifth stage as at the first: a full turn, a pair of fingerprints and a flat checkpoint.
    expect(widest.row).toBeLessThanOrEqual(limits.recording_bytes!);
    expect(widest.row).toBeLessThan(MAX_ROW_BYTES / 16);
    expect(widest.pair).toBeLessThan(8_192); expect(widest.room).toBeLessThan(8_192);
    expect(widest.body).toBeLessThanOrEqual(limits.turn_body_bytes);
    // The Worker copies each body and reply once (4 ns a byte, test/compressed-rooms.test.ts): far inside its 10 ms.
    expect((widest.body + widest.reply) * 4 / 1e6).toBeLessThan(2);
    // The replay archive carries every turn as its fingerprint, and the room snapshot restores into a fresh object.
    const transfer = await env.ROOMS_V2.getByName(room.room_id).replayTransfer(host.player_id);
    expect(transfer.ok).toBe(true);
    const archive = (transfer as { value: { archive: { turns: { recording: Rec }[] } } }).value.archive, archiveBytes = new TextEncoder().encode(canonicalJson(archive)).byteLength;
    expect(archive.turns.every(row => isFingerprint(row.recording))).toBe(true);
    expect(archiveBytes).toBeLessThan(MAX_REPLAY_ARCHIVE_BYTES / 100);
    const exported = await env.ROOMS_V2.getByName(room.room_id).exportSnapshot("d".repeat(40));
    expect(exported.ok).toBe(true);
    expect(await env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()).restoreSnapshot((exported as { value: string }).value, room.room_id)).toMatchObject({ ok: true });
    console.log("open turns fingerprints, five stages of 18,000 tick turns:", JSON.stringify({ widest, archive_bytes: archiveBytes, snapshot_bytes: (exported as { value: string }).value.length, rows_written: written }));
    // Rows written: a pass and a closing turn add one (the turn before becomes its fingerprint); the acknowledging poll writes one; any other poll none.
    expect(Math.max(...written.pass)).toBeLessThanOrEqual(Math.max(...written.first) + 4);
    // (The last stage's polls also arm the finished room's replay clock, so only the stages in play are counted.)
    expect(written.acknowledging_poll.slice(0, -1).every(rows => rows === 1)).toBe(true);
    expect(written.quiet_poll.slice(0, -1).every(rows => rows === 0)).toBe(true);
    // Every stage's first pip is the one that did not close the stage before, so the plan's stages start p0, p0, p1, p1, p0.
    expect(room.checkpoint).toMatchObject({ schema_version: 9, next_first_slot: "p1" });
  }, 180_000);
  it("takes an open turns run a phone posts from its own copy only when it is exactly the room's, and posts it again harmlessly", async () => {
    const host = await account(), guest = await account(), BOARDS = { features: ["LEADERBOARDS"] }, TICKS_POSTED = 300;
    const made = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { ...FIVE, idempotency_key: crypto.randomUUID() }));
    let room = await json<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: made.invite_code, supported_simulation_versions: NEW_CLIENT }));
    let nested = room.checkpoint as Rec;
    for (const index of [0, 1, 2, 3, 4]) {
      const turns: Rec[] = [], start = room.checkpoint as Rec, count = index === 1 ? 3 : 2;
      for (let n = 1; n <= count; n++) {
        const recording = await turn(index, start.next_first_slot ?? "p0", start.checkpoint_hash, turns, n === count, TICKS_POSTED);
        const next = n === count ? await closing(index, start, [...turns, recording]) : undefined;
        room = (await json<MutationV2>(call(`/v2/rooms/${room.room_id}/turns`, "POST", recording.player_slot === "p0" ? host : guest,
          { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording, ...(next ? { checkpoint: next } : {}) }))).room;
        turns.push(recording);
      }
      // The phone nests each stage's turns again under the room's own flat checkpoint.
      nested = { ...(room.checkpoint as Rec), proof: { checkpoint: nested, turns } };
    }
    expect(room).toMatchObject({ active_role: "complete" });
    const post = (body: unknown, who = host) => json<Rec>(call(`/v1/leaderboards/post/${room.room_id}`, "POST", who, body, {}, BOARDS));
    const counting = countingEnv(withConfig({ ...env, ...FLAGS, ...BOARDS }));
    const first = await json<Rec>(worker.fetch(request(`/v1/leaderboards/post/${room.room_id}`, "POST", host, { schema_version: 1, checkpoint: nested }), counting.env));
    expect(first).toEqual({ schema_version: 1, status: "posted" });
    // One room request checks it; the board takes it.
    expect(counting.calls.filter(name => name.startsWith("ROOMS_V2."))).toEqual(["ROOMS_V2.postedRun"]);
    expect(await post({ schema_version: 1, checkpoint: nested }, guest)).toEqual({ schema_version: 1, status: "posted" });
    const board = await json<Rec>(call(`/v1/leaderboards/${FIVE.level_id}@${FIVE.level_version}`, "GET", undefined, undefined, {}, BOARDS));
    expect(board.checking ?? board).toBeDefined();
    // A changed turn, a changed stage checkpoint or a missing stage is not this room's run.
    const changedTurn = structuredClone(nested); changedTurn.proof.turns[0].duration_ticks++;
    const changedStage = structuredClone(nested); changedStage.proof.checkpoint.players.p0.x++;
    const shortChain = structuredClone(nested); shortChain.proof.checkpoint = shortChain.proof.checkpoint.proof.checkpoint;
    for (const value of [changedTurn, changedStage, shortChain]) expect((await call(`/v1/leaderboards/post/${room.room_id}`, "POST", host, { schema_version: 1, checkpoint: value }, {}, BOARDS)).status).toBe(422);
    // Somebody else's post, and a post with the leaderboards off, go nowhere.
    const stranger = await account();
    expect((await call(`/v1/leaderboards/post/${room.room_id}`, "POST", stranger, { schema_version: 1, checkpoint: nested }, {}, BOARDS)).status).toBe(404);
    expect((await call(`/v1/leaderboards/post/${room.room_id}`, "POST", host, { schema_version: 1, checkpoint: nested })).status).toBe(404);
  }, 120_000);
});
