import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { chapter, checkpointV2, initialCheckpoint } from "../src/v2/protocol";
import { CHAPTERS } from "../src/v2/chapters";
import { MAX_ROW_BYTES, MAX_REPLAY_ARCHIVE_BYTES } from "../src/v2/row-bound";
import { CARRY_RECORD_KEYS, DEFAULT_TURN_CAP, MAX_OPEN_TURN_TICKS, OPEN_CHECKPOINT_KEYS, OPEN_CHECKPOINT_SCHEMA, OPEN_TURN_ID_PATTERN, PACKED_RECORDING_VALUES, carryFits, fingerprint, handoffTick, isFingerprint, mustFinish, openAccepted, openTurnLimits, packedRecordingBytes, recordingBytes, timelineShares, turnId, turnNumber, turnSlot } from "../src/v2/open-turns";
import { MAX_PACKED_CHARS, checkTicks, packRecording, unpackRecording } from "../src/v2/recording-codec";
import { conservatoryV2, firstStepsV2, fogMarsh, longWayHomeV2, longWayHomeV3, relayIslesV3, theFalls, turnOfTheTideV2, turnOfTheTideV3, wishingWellV2 } from "../src/v2/protocol-journey";
import { highAndLowV2, houseForTwoV2, rollingHomeV2 } from "../src/v2/protocol-cooperative";
import { comfortRules, openControls, openTurns, piecesRules, sharedBall, tideRules, type ChapterCheckpoint, type ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import type { RedoStateV2 } from "../src/redo-control";
import carrySetA from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-a.json";
import carrySetB from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-b.json";
import carrySetEnd from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-checkpoint.json";
import carrySlackA from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-a.json";
import carrySlackB from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-b.json";
import carrySlackEnd from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-checkpoint.json";
import { physicalAccepted, scaledLimits, turnLimits } from "../src/v2/protocol-physical-recording";
import tideV2Definition from "../src/v2/turn-of-the-tide-v2.json";
import { withConfig } from "./config";
import { grantFullJourney } from "./full-journey";
import { decodeBlob } from "../src/blob-codec";
import { countingEnv, meterRows } from "./meter";

/**
 * Open turns (v2/open-turns.ts) on Turn of the Tide@3 pinned to rules 19 under a key only this file knows (CARRY). The
 * server never simulates, so the chains here are built from the native fixtures' first two turns: a pass is the fixture's
 * second turn not finished, a later turn swaps the pip, chains its source and takes over at its hand-off, with stand-in
 * world hashes, and every record and checkpoint is hashed again. Every turn goes packed (v2/recording-codec.ts), as an
 * open turns room takes no other form.
 */
type Account = { player_id: string; device_token: string };
type Rec = Record<string, any>;
const CARRY = vi.hoisted(() => ({ level_id: "turn-of-the-tide", level_version: 98, definition_hash: "c".repeat(64) }));
vi.mock("../src/v2/chapters", async original => {
  const actual = await original<typeof import("../src/v2/chapters")>();
  const { journeyAdapter } = await import("../src/v2/protocol-journey");
  const { canonicalJson: canonical, digest: hash } = await import("../src/protocol");
  const definition = { ...structuredClone((await import("../src/v2/turn-of-the-tide-v3.json")).default), version: CARRY.level_version, simulation_version: 19 };
  const { checkpoint_hash: _old, proof, ...body } = { ...structuredClone((await import("../src/v2/turn-of-the-tide-v3-initial.json")).default), level_version: CARRY.level_version, definition_hash: CARRY.definition_hash } as Record<string, unknown>; void _old;
  const carried = journeyAdapter(definition as never, { ...body, checkpoint_hash: await hash(canonical(body)), proof } as never, CARRY.definition_hash, 7);
  const mocked = (value: unknown) => value !== null && typeof value === "object" && (value as Record<string, unknown>).level_id === CARRY.level_id && (value as Record<string, unknown>).level_version === CARRY.level_version && (value as Record<string, unknown>).definition_hash === CARRY.definition_hash ? carried : null;
  return { ...actual, chapter: (value: unknown) => mocked(value) ?? actual.chapter(value), chapterKey: (value: unknown) => mocked(value) ? { ...carried.key } : actual.chapterKey(value),
    chapterFlag: (entry: unknown) => entry === carried ? "" : actual.chapterFlag(entry as never), creatable: (entry: unknown, e: Env) => entry === carried || actual.creatable(entry as never, e) };
});
const FLAGS = { TURN_OF_THE_TIDE_V3_CHAPTER_ENABLED: "true", NOTIFICATIONS_ENABLED: "false" };
const NEW_CLIENT = [2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 18, 19, 20, 21];
const adapter = chapter(CARRY);
/** A native record or checkpoint under CARRY's pin. */
const pinned = (value: Rec): Rec => ({ ...structuredClone(value), level_version: CARRY.level_version, definition_hash: CARRY.definition_hash });
const [setA, setB, slackA, slackB, setEnd, slackEnd] = [carrySetA, carrySetB, carrySlackA, carrySlackB, carrySetEnd, carrySlackEnd].map(value => pinned(value as Rec));
const key = () => crypto.randomUUID();
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.15." + (++address % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) }), withConfig({ ...env, ...FLAGS }));
}
async function json<T>(response: Promise<Response>, status = 200): Promise<T> {
  const result = await response, text = await result.text();
  expect(result.status, text).toBe(status); return JSON.parse(text) as T;
}
const account = () => json<Account>(call("/v1/identity", "POST", undefined, {}), 201);
/** `record` hashed again, packed first when it is in the JSON form; checks the fixture lacks (a longer turn) take a stand-in hash, as the server never replays. */
async function hashed(record: Rec): Promise<Rec> {
  const { recording_hash: _old, ...body } = record; void _old;
  if (Array.isArray(body.actions)) {
    const { actions, replay_checks, ...rest } = body, known = new Map((replay_checks as Rec[]).map(check => [check.tick, check.state_hash]));
    const checks = checkTicks(body.duration_ticks).map(tick => ({ tick, state_hash: tick === body.duration_ticks ? body.final_state_hash : known.get(tick) ?? "0".repeat(64) }));
    return hashed({ ...rest, packed: packRecording(actions, checks, body.duration_ticks) });
  }
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}
/** `record` exactly as it is, hashed again in the JSON form. */
async function hashedJson(record: Rec): Promise<Rec> { const { recording_hash: _old, ...body } = record; void _old; return { ...body, recording_hash: await digest(canonicalJson(body)) }; }
/** A packed fixture's runs and checks listed again (short check hashes stay short). */
function listed(record: Rec): { actions: Rec[]; replay_checks: Rec[] } {
  return unpackRecording(record.packed, record.duration_ticks, record.final_state_hash, record.duration_ticks) as { actions: Rec[]; replay_checks: Rec[] };
}
/** A packed fixture in the JSON form, hashed again: what an app that records JSON would send. */
async function jsonForm(record: Rec): Promise<Rec> { return hashedJson({ ...bare(record), ...listed(record) }); }
/** `record` without its packed runs and checks. */
function bare(record: Rec): Rec { const { packed: _packed, ...rest } = structuredClone(record); void _packed; return rest; }
/** `checkpoint` hashed again; a published checkpoint keeps its proof (never hashed), an open turns one nests none. */
async function sealed(checkpoint: Rec): Promise<Rec> { const { checkpoint_hash: _old, proof, ...body } = checkpoint; void _old; return { ...body, checkpoint_hash: await digest(canonicalJson(body)), ...(proof ? { proof } : {}) }; }
/** A turn as the server keeps it once its partner played over it: its record without `packed`. */
const print = (turn: Rec) => fingerprint(turn as ChapterRecording) as Rec;
const other = (slot: string) => slot === "p0" ? "p1" : "p0";

/**
 * The next turn after `turns` (the stage's turns so far): the fixture's second turn, played by the pip its number belongs
 * to in a stage `first` starts, over the latest turn, from its hand-off world at its hand-off tick, closing the stage or not.
 */
async function later(fixtureB: Rec, first: string, turns: Rec[], closes: boolean, checkpointHash: string, extraTicks = 0): Promise<Rec> {
  const n = turns.length + 1, memory = turns.at(-1)!, ticks = fixtureB.duration_ticks + extraTicks;
  return hashed({ ...structuredClone(fixtureB), checkpoint_hash: checkpointHash, player_slot: turnSlot(first, n), source_recording_hash: memory.recording_hash,
    handoff_tick: handoffTick(memory as ChapterRecording, (turns.at(-2) ?? null) as ChapterRecording | null), start_hash: memory.handoff_hash, handoff_hash: await digest(`world ${checkpointHash} ${n} ${ticks}`),
    duration_ticks: fixtureB.duration_ticks + extraTicks, actions: [...listed(fixtureB).actions, ...(extraTicks ? [{ ticks: extraTicks, x: 0, z: 0, action: false }] : [])],
    replay_checks: extraTicks ? [...listed(fixtureB).replay_checks.slice(0, -1), { tick: fixtureB.duration_ticks + extraTicks, state_hash: fixtureB.final_state_hash }] : listed(fixtureB).replay_checks,
    completed: closes, outcome: { ...fixtureB.outcome, objective_complete: closes } });
}
/**
 * The checkpoint that closes a stage with `turns` (by hash, no proof), from the fixture's own end state with both pips where
 * its goal pip ended, naming the pip that did not close the stage to start the next.
 */
async function closing(fixtureEnd: Rec, previous: Rec, turns: Rec[], together = true): Promise<Rec> {
  const { a_recording_hash: _a, b_recording_hash: _b, proof: _proof, ...rest } = structuredClone(fixtureEnd); void _a; void _b; void _proof;
  const goalPip = rest.players[other(fixtureEnd === setEnd ? setA.player_slot : slackA.player_slot)];
  // Apart: the first pip back where the stage started it, away from the goal.
  rest.players = together ? { p0: { ...goalPip }, p1: { ...goalPip } } : { ...rest.players, [turns[0].player_slot]: structuredClone(previous.players[turns[0].player_slot]) };
  return sealed({ ...rest, schema_version: OPEN_CHECKPOINT_SCHEMA, previous_checkpoint_hash: previous.checkpoint_hash, turn_hashes: turns.map(turn => turn.recording_hash), next_first_slot: other(turns.at(-1)!.player_slot) });
}
/** A stage's chain: turn 1 by the pip `previous` names (the host's on the first stage) and `passes` passes, then the closing turn and its checkpoint. */
async function chain(stage: 0 | 1, previous: Rec, passes: number): Promise<{ turns: Rec[]; checkpoint: Rec }> {
  const [fixtureA, fixtureB, fixtureEnd] = stage === 0 ? [setA, setB, setEnd] : [slackA, slackB, slackEnd];
  const first = previous.next_first_slot ?? "p0";
  const turns: Rec[] = [await hashed({ ...structuredClone(fixtureA), checkpoint_hash: previous.checkpoint_hash, player_slot: first })];
  for (let n = 2; n <= passes + 2; n++) turns.push(await later(fixtureB, first, turns, n === passes + 2, previous.checkpoint_hash));
  return { turns, checkpoint: await closing(fixtureEnd, previous, turns) };
}
/** The members who start and follow the stage after `checkpoint`: the first stage's first pip is the host's (`first`). */
const pips = (checkpoint: Rec, first: Account, second: Account): [Account, Account] => checkpoint.next_first_slot === "p1" ? [second, first] : [first, second];
const initial = () => initialCheckpoint(adapter.key) as unknown as Rec;
const validate = (checkpoint: Rec, previous: Rec, turns: Rec[]) =>
  checkpointV2(checkpoint, previous as ChapterCheckpoint, turns[0] as ChapterRecording, turns.at(-1) as ChapterRecording, turns.slice(1, -1) as ChapterRecording[]);

async function room(): Promise<{ host: Account; guest: Account; room: RoomSnapshotV2; first: Account; second: Account }> {
  const host = await account(), guest = await account(); await grantFullJourney(host);
  const made = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { ...adapter.key, idempotency_key: key() }));
  const joined = await json<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: made.invite_code, supported_simulation_versions: NEW_CLIENT }));
  return { host, guest, room: joined, first: host, second: guest };
}
const send = (room: RoomSnapshotV2, who: Account, recording: Rec, checkpoint?: Rec, extra: Record<string, unknown> = {}, status = 200) =>
  json<MutationV2>(call(`/v2/rooms/${room.room_id}/turns`, "POST", who, { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}), ...extra }), status);
const read = (room: RoomSnapshotV2, who: Account) => json<RoomSnapshotV2>(call(`/v2/rooms/${room.room_id}`, "GET", who));
const failure = async (response: Promise<Response>, status: number, code: string) => { const result = await response; expect(result.status).toBe(status); expect(await result.json()).toMatchObject({ error: { code } }); };

afterEach(async () => { await reset(); vi.restoreAllMocks(); });

describe("open turns: rules and bounds", () => {
  it("gives only the open controls chapters open turns, with a cap a stage and bounds that never grow with the stages", () => {
    for (const row of CHAPTERS) {
      const open = row.adapter.open_turns;
      expect(open !== undefined, row.adapter.key.level_id + "@" + row.adapter.key.level_version).toBe([longWayHomeV3, turnOfTheTideV3, conservatoryV2, highAndLowV2, wishingWellV2, firstStepsV2, rollingHomeV2, houseForTwoV2, theFalls, fogMarsh, relayIslesV3].includes(row.adapter));
      if (!open) continue;
      expect(open.caps).toEqual(row.adapter.stages.map(stage => (stage as { turn_cap?: number }).turn_cap ?? DEFAULT_TURN_CAP));
      expect(row.adapter.max_branches).toBe(open.branches);
      expect(open.branches).toBe(7);
      expect(open).not.toHaveProperty("stage_bytes");
      const limits = row.adapter.limits!;
      // The closing turn's body (one recording and a flat checkpoint) stays far inside the Worker's 10 ms (test/compressed-rooms.test.ts).
      expect(limits.turn_body_bytes).toBe(open.recording_bytes + 2 * 16_384);
      expect(limits.turn_body_bytes).toBeLessThanOrEqual(1_250_000 / 4);
      // A flat checkpoint, whatever the stage; a pair row holds it and two fingerprints.
      expect(limits.checkpoint_bytes).toBe(16_384);
      expect(limits.checkpoint_bytes + 2 * limits.recording_bytes! + 16_384).toBeLessThanOrEqual(MAX_ROW_BYTES);
      // Every row a room may hold: 128 turn rows and 64 pair rows as fingerprints, and two full turns a branch.
      expect(128 * (2_048 + 16_384) + 64 * (2 * 2_048 + 2 * 16_384) + open.branches * 2 * open.recording_bytes).toBeLessThanOrEqual(MAX_REPLAY_ARCHIVE_BYTES);
    }
    // Eight stages (the most a room's ids name) at the rules' longest turn take the same bounds as one: nothing nests.
    const widest = packedRecordingBytes(MAX_OPEN_TURN_TICKS);
    expect(openTurnLimits(Array.from({ length: 8 }, () => ({ turn_cap: 20 })), widest, 7)).toMatchObject({ recording_bytes: widest, branches: 7 });
    expect(openTurnLimits([{}], widest, 7)).toMatchObject({ recording_bytes: widest, branches: 7 });
    // The packed string bound every room shares sets the longest turn now: it still fits a row and a body with room to spare.
    expect(() => openTurnLimits([{}, {}, {}, {}, {}], 2_048 + MAX_PACKED_CHARS, 7)).not.toThrow();
    // The published chapters' bounds are exactly what they were.
    expect(longWayHomeV2.limits).toBeUndefined();
    expect(turnOfTheTideV2.limits).toEqual(scaledLimits(turnLimits(tideV2Definition)!));
    expect(() => openTurnLimits([{ turn_cap: 1 }], 65_536, 7)).toThrow("invalid turn_cap");
    expect(() => openTurnLimits([{ turn_cap: 21 }], 65_536, 7)).toThrow("invalid turn_cap");
    expect(() => openTurnLimits([{ turn_cap: 9 }], 65_536, 7)).not.toThrow();
  });
  it("sizes every bound by the widest packed turn: a new stick every tick, at most the bound", async () => {
    // Turn of the Tide@3's fallback turns: 1,800 ticks each (60 s).
    const ticks = 1800;
    expect(adapter.open_turns!.recording_bytes).toBe(packedRecordingBytes(ticks));
    expect(adapter.limits!.recording_values).toBe(PACKED_RECORDING_VALUES);
    // Every field of the header at its widest the parser allows, every run one tick, every stick at its far end.
    const actions = Array.from({ length: ticks }, (_, i) => ({ ticks: 1, x: i % 2 ? -100 : 100, z: -100, action: i % 3 === 0 }));
    const widest = await hashed({ ...structuredClone(setB), duration_ticks: ticks, actions, replay_checks: [], source_recording_hash: "f".repeat(64), checkpoint_hash: "f".repeat(64), final_state_hash: "f".repeat(64),
      catch_assistance: false, completed: false, outcome: { source_ready: true, objective_complete: false } });
    expect(recordingBytes(widest as ChapterRecording)).toBeLessThanOrEqual(packedRecordingBytes(ticks));
    expect(recordingBytes(widest as ChapterRecording)).toBeGreaterThan(packedRecordingBytes(ticks) - 2_048);
    expect(await adapter.recording(widest)).toEqual(widest);
    // The longest open turn, ten minutes, packs well inside the packed string bound every room shares (a third to spare).
    const longest = Array.from({ length: MAX_OPEN_TURN_TICKS }, (_, i) => ({ ticks: 1, x: i % 2 ? -100 : 100, z: -100, action: false }));
    expect(packRecording(longest, checkTicks(MAX_OPEN_TURN_TICKS).map(tick => ({ tick, state_hash: "f".repeat(64) })), MAX_OPEN_TURN_TICKS).length * 1.5).toBeLessThan(MAX_PACKED_CHARS);
    expect(turnLimits({ simulation_version: 19, turn_limits: { a_ticks: MAX_OPEN_TURN_TICKS, b_ticks: MAX_OPEN_TURN_TICKS } })).toEqual({ a_ticks: MAX_OPEN_TURN_TICKS, b_ticks: MAX_OPEN_TURN_TICKS });
    expect(() => turnLimits({ simulation_version: 19, turn_limits: { a_ticks: 9000, b_ticks: MAX_OPEN_TURN_TICKS + 1 } })).toThrow("invalid turn_limits");
    expect(() => turnLimits({ simulation_version: 13, turn_limits: { a_ticks: 9000, b_ticks: 9001 } })).toThrow("invalid turn_limits");
    expect(() => openTurnLimits([{}, {}, {}, {}], packedRecordingBytes(MAX_OPEN_TURN_TICKS), 7)).not.toThrow();
    // Under a ninth of the same JSON turn's bytes, the header allowance included.
    expect(packedRecordingBytes(3000) * 9).toBeLessThan(recordingBytes(await hashedJson({ ...bare(setB), duration_ticks: 3000, actions: Array.from({ length: 3000 }, (_, i) => actions[i % ticks]), replay_checks: checkTicks(3000).map(tick => ({ tick, state_hash: "f".repeat(64) })) }) as ChapterRecording));
  });
  it("names turns by letter, a and b first, and gives odd turns to the stage's first pip", () => {
    expect([1, 2, 3, 20].map(n => turnId(3, 1, n))).toEqual(["t3-1-a", "t3-1-b", "t3-1-c", "t3-1-t"]);
    expect(["t3-1-a", "t3-1-c", "t3-1-t"].map(turnNumber)).toEqual([1, 3, 20]);
    expect(OPEN_TURN_ID_PATTERN.test("t31-7-t") && !OPEN_TURN_ID_PATTERN.test("t3-1-u")).toBe(true);
    expect([1, 2, 3, 4].map(n => turnSlot("p1", n))).toEqual(["p1", "p0", "p1", "p0"]);
    const open = adapter.open_turns!;
    expect(mustFinish(open, 0, 1)).toBe(false);
    expect(mustFinish(open, 0, open.caps[0] - 1)).toBe(false);
    expect(mustFinish(open, 0, open.caps[0])).toBe(true);
  });
  it("checks a stage's whole chain by its turns' fingerprints: order, pips, memories, lengths, and no proof", async () => {
    const start = initial(), { turns, checkpoint } = await chain(0, start, 2);
    expect(await validate(checkpoint, start, turns)).toEqual(checkpoint);
    // The room holds every turn before the closing one as its fingerprint; the chain checks the same.
    expect(await validate(checkpoint, start, [...turns.slice(0, -1).map(print), turns.at(-1)!])).toEqual(checkpoint);
    // A checkpoint that still nests its turns is refused, though its hash is the same.
    await expect(validate({ ...checkpoint, proof: { checkpoint: start, turns } }, start, turns)).rejects.toMatchObject({ code: "unexpected_fields" });
    // The stage ends only with both pips in its goal area.
    await expect(validate(await closing(setEnd as Rec, start, turns, false), start, turns)).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    // Two turns are a chain too, in the same shape.
    const two = await chain(0, start, 0);
    expect((await validate(two.checkpoint, start, two.turns)).turn_hashes).toHaveLength(2);
    // The wrong pip on a later turn.
    const swapped = [...turns]; swapped[2] = await hashed({ ...turns[2], player_slot: other(turns[2].player_slot) });
    swapped[3] = await hashed({ ...turns[3], source_recording_hash: swapped[2].recording_hash });
    await expect(validate(await closing(setEnd as Rec, start, swapped), start, swapped)).rejects.toMatchObject({ code: "checkpoint_recording_mismatch" });
    // A pass that ends before the friend's replay beside it is over: turn 2 runs 656 ticks past turn 3's hand-off.
    const longer = [turns[0]]; longer.push(await later(setB, "p0", longer, false, start.checkpoint_hash, 600));
    longer.push(await later(setB, "p0", longer, false, start.checkpoint_hash)); longer.push(await later(setB, "p0", longer, true, start.checkpoint_hash));
    await expect(validate(await closing(setEnd as Rec, start, longer), start, longer)).rejects.toMatchObject({ code: "checkpoint_recording_mismatch" });
    // A pass that says it finished, or a closing turn that did not.
    const finishedPass = [...turns]; finishedPass[1] = await hashed({ ...turns[1], completed: true, outcome: { ...turns[1].outcome, objective_complete: true } });
    await expect(validate(await closing(setEnd as Rec, start, finishedPass), start, finishedPass)).rejects.toMatchObject({ code: "checkpoint_recording_mismatch" });
    // A memory out of order.
    const broken = [turns[0], turns[2], turns[1], turns[3]];
    await expect(validate(await closing(setEnd as Rec, start, broken), start, broken)).rejects.toMatchObject({ code: "checkpoint_source_mismatch" });
    // The published shape is refused on open rules.
    const { turn_hashes: _hashes, ...published } = structuredClone(two.checkpoint); void _hashes;
    const twoTurns = await sealed({ ...published, schema_version: 7, a_recording_hash: two.turns[0].recording_hash, b_recording_hash: two.turns[1].recording_hash, proof: { checkpoint: start, a: two.turns[0], b: two.turns[1] } });
    await expect(checkpointV2(twoTurns, start as ChapterCheckpoint, two.turns[0] as ChapterRecording, two.turns[1] as ChapterRecording)).rejects.toMatchObject({ status: 400 });
    // Past the stage's cap.
    const capped = await chain(0, start, adapter.open_turns!.caps[0] - 1);
    await expect(validate(capped.checkpoint, start, capped.turns)).rejects.toMatchObject({ code: "checkpoint_recording_mismatch" });
  });
});

describe("open turns: a first turn ended early", () => {
  it("takes a first turn whose own part is not done on open turns only, and the next turn closes the stage over it", async () => {
    const start = initial();
    const early = await hashed({ ...structuredClone(setA as Rec), checkpoint_hash: start.checkpoint_hash, outcome: { ...(setA as Rec).outcome, source_ready: false } });
    const closingTurn = await later(setB, "p0", [early], true, start.checkpoint_hash);
    const turns = [early, await hashed({ ...closingTurn, outcome: { ...closingTurn.outcome, source_ready: false } })];
    const checkpoint = await closing(setEnd as Rec, start, turns);
    expect(openAccepted(early as ChapterRecording)).toBe(true);
    expect(await validate(checkpoint, start, turns)).toEqual(checkpoint);
    // Older rules (13 and before) keep asking a first turn for its part.
    expect(physicalAccepted({ ...early, simulation_version: 13 } as ChapterRecording)).toBe(false);
    expect(physicalAccepted({ ...(setA as Rec), simulation_version: 13 } as ChapterRecording)).toBe(true);
    // A first turn still never finishes the stage.
    expect(openAccepted({ ...early, completed: true, outcome: { ...early.outcome, objective_complete: true } } as ChapterRecording)).toBe(false);
    // In a room: the early first turn is taken, and the friend's turn over it closes the stage.
    const { room: joined, first, second } = await room();
    const one = await send(joined, first, early);
    expect(one.room).toMatchObject({ active_role: "b", active_player_id: second.player_id });
    const two = await send(one.room, second, turns[1], checkpoint);
    expect(two.room).toMatchObject({ stage_index: 1, checkpoint });
  });
});

describe("open turns: a friend room", () => {
  it("plays a stage in four turns and the next in two, each turn the other pip's, with whose turn and how many are left", async () => {
    const { room: joined, first, second } = await room();
    expect(joined.open_turns).toEqual({ turn: 1, cap: adapter.open_turns!.caps[0], must_finish: false, pass_bytes: adapter.open_turns!.recording_bytes, turn_hashes: [], newest: null, closing: null, wanted: [] });
    const { turns, checkpoint } = await chain(0, initial(), 2);
    const one = await send(joined, first, turns[0]);
    expect(one.receipt.turn_id).toBe(`t0-0-a`);
    expect(one.room).toMatchObject({ active_role: "b", active_player_id: second.player_id });
    // A pass carries no checkpoint, and an early checkpoint on one is refused.
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", second, { base_revision: one.room.revision, branch: 0, idempotency_key: key(), recording: turns[1], checkpoint }), 422, "pass_with_checkpoint");
    const two = await send(one.room, second, turns[1]);
    expect(two.receipt).toMatchObject({ turn_id: "t0-0-b", pair_id: null });
    // Turn 1 only as its fingerprint now; the newest turn in full is the memory the next turn plays over.
    expect(two.room).toMatchObject({ stage_index: 0, active_role: "b", active_player_id: first.player_id, recording_a: print(turns[0]) });
    expect(two.room.recording_a).not.toHaveProperty("packed");
    expect(two.room.open_turns).toMatchObject({ turn: 3, turn_hashes: [turns[0].recording_hash, turns[1].recording_hash], newest: turns[1], closing: null });
    expect(two.room).not.toHaveProperty("open_stage");
    // The wrong pip, or a memory that is not the latest turn.
    await send(two.room, second, turns[2], undefined, {}, 409);
    await send(two.room, first, await hashed({ ...turns[2], source_recording_hash: turns[0].recording_hash }), undefined, {}, 409);
    const three = await send(two.room, first, turns[2]);
    expect(three.receipt.turn_id).toBe("t0-0-c");
    expect(three.room).toMatchObject({ active_player_id: second.player_id });
    // The room holds the memory the next turn replays, and every earlier turn by hash.
    expect((await read(three.room, second)).open_turns).toMatchObject({ turn_hashes: turns.slice(0, 3).map(turn => turn.recording_hash), newest: turns[2] });
    const four = await send(three.room, second, turns[3], checkpoint);
    expect(four.receipt).toMatchObject({ turn_id: "t0-0-d", pair_id: "p0-0" });
    expect(four.room).toMatchObject({ stage_index: 1, checkpoint, a_turn_id: null, active_role: "a" });
    expect(four.room.checkpoint).not.toHaveProperty("proof");
    expect(four.room.open_turns).toMatchObject({ turn: 1, turn_hashes: [], newest: null, closing: turns[3] });
    // Stage two closes in two turns, as before open turns.
    const next = await chain(1, checkpoint, 0), [slackFirst, slackSecond] = pips(checkpoint, first, second);
    const five = await send(four.room, slackFirst, next.turns[0]), six = await send(five.room, slackSecond, next.turns[1], next.checkpoint);
    expect(six.room).toMatchObject({ stage_index: 2, active_role: "complete", active_player_id: null, checkpoint: next.checkpoint });
    expect(six.room.open_turns).toMatchObject({ turn: 0, cap: 0, must_finish: false, turn_hashes: [], newest: null, closing: next.turns[1] });
    // Its pair row holds the first and closing turns as fingerprints and the flat checkpoint that names every turn.
    const pair = await json<Rec>(call(`/v2/rooms/${joined.room_id}/pairs/p0-0`, "GET", first));
    expect(pair.a).toEqual(print(turns[0])); expect(pair.b).toEqual(print(turns[3])); expect(pair.checkpoint).toEqual(checkpoint);
  });
  it("makes the cap's turn finish the stage", async () => {
    const { room: joined, first, second } = await room();
    const cap = adapter.open_turns!.caps[0], { turns } = await chain(0, initial(), cap - 1);
    let current = (await send(joined, first, turns[0])).room;
    for (let n = 2; n < cap; n++) current = (await send(current, n % 2 ? first : second, await hashed({ ...turns[n - 1], completed: false, outcome: { ...turns[n - 1].outcome, objective_complete: false } }))).room;
    expect(current.open_turns).toMatchObject({ turn: cap, must_finish: true });
    const pass = await hashed({ ...turns[cap - 1], completed: false, outcome: { ...turns[cap - 1].outcome, objective_complete: false } });
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", cap % 2 ? first : second, { base_revision: current.revision, branch: current.branch, idempotency_key: key(), recording: pass }), 409, "turn_must_finish");
  });
  it("takes a room on its cap's turn back by a redo, and again by starting over", async () => {
    const { room: joined, first, second } = await room();
    const cap = adapter.open_turns!.caps[0], { turns } = await chain(0, initial(), cap - 1);
    const pass = (n: number) => hashed({ ...turns[n - 1], completed: false, outcome: { ...turns[n - 1].outcome, objective_complete: false } });
    async function toCap(start: RoomSnapshotV2): Promise<RoomSnapshotV2> {
      let current = (await send(start, first, turns[0])).room;
      for (let n = 2; n < cap; n++) current = (await send(current, n % 2 ? first : second, await pass(n))).room;
      expect(current.open_turns).toMatchObject({ turn: cap, must_finish: true });
      return current;
    }
    const capped = await toCap(joined);
    const [mover, friend] = cap % 2 ? [first, second] : [second, first];
    // The pip on the cap's turn asks to redo the friend's turn before it; the friend agrees.
    const path = `/v2/rooms/${joined.room_id}/redo`, headers = { "X-AfterYou-Poll-Redo": "1", "X-AfterYou-Redo-Extras": "1" };
    const state = await json<RedoStateV2>(call(path, "GET", mover, undefined, headers));
    expect(state.source).toMatchObject({ a_hash: (await pass(cap - 1)).recording_hash, stage_index: 0 });
    const asked = await json<RedoStateV2>(call(path, "POST", mover, { action: "request", source: state.source }));
    const redone = await json<MutationV2>(call(`/v2/rooms/${joined.room_id}/fork`, "POST", friend, { base_revision: capped.revision, branch: capped.branch, stage_index: 0, idempotency_key: key(), redo_request_id: asked.request!.request_id }));
    expect(redone.room.open_turns).toMatchObject({ turn: 1, must_finish: false, turn_hashes: [] });
    // Played to the cap again, then started over by agreement: the stage opens on its first turn.
    const again = await toCap(redone.room);
    const over = { room_id: joined.room_id, revision: again.revision, branch: again.branch, stage_index: 0, a_hash: again.checkpoint.checkpoint_hash, first_player_id: second.player_id, second_player_id: first.player_id };
    const request = await json<RedoStateV2>(call(path, "POST", first, { action: "request", source: over }));
    const wiped = await json<MutationV2>(call(`/v2/rooms/${joined.room_id}/fork`, "POST", second, { base_revision: again.revision, branch: again.branch, stage_index: 0, idempotency_key: key(), redo_request_id: request.request!.request_id }));
    expect(wiped.room).toMatchObject({ stage_index: 0, a_turn_id: null });
    expect(wiped.room.open_turns).toMatchObject({ turn: 1, must_finish: false, turn_hashes: [], newest: null });
  });
  it("shows whose turn it is in the room list after each pass", async () => {
    const { room: joined, first, second } = await room();
    const { turns } = await chain(0, initial(), 2);
    const status = async (who: Account) => (await json<{ rooms: { room_id: string; status: string }[] }>(call("/v1/room-inbox", "GET", who))).rooms.find(row => row.room_id === joined.room_id)?.status;
    const one = await send(joined, first, turns[0]);
    expect([await status(first), await status(second)]).toEqual(["waiting_for_their_turn", "your_turn"]);
    await send(one.room, second, turns[1]);
    expect([await status(first), await status(second)]).toEqual(["your_turn", "waiting_for_their_turn"]);
  });
  it("gives the room list the turn and the cap only to apps that draw the turn dots", async () => {
    const { room: joined, first, second } = await room();
    const { turns } = await chain(0, initial(), 2);
    type Row = { room_id: string; open_turns?: { turn: number; cap: number } };
    const row = async (who: Account, dots: boolean) => (await json<{ rooms: Row[] }>(call("/v1/room-inbox", "GET", who, undefined, dots ? { "X-AfterYou-Open-Turns": "1" } : {}))).rooms.find(entry => entry.room_id === joined.room_id)!;
    const one = await send(joined, first, turns[0]);
    const cap = (one.room as unknown as { open_turns: { cap: number } }).open_turns.cap;
    expect([(await row(first, true)).open_turns, (await row(second, true)).open_turns]).toEqual([{ turn: 2, cap }, { turn: 2, cap }]);
    expect("open_turns" in await row(first, false)).toBe(false);
    await send(one.room, second, turns[1]);
    expect((await row(second, true)).open_turns).toEqual({ turn: 3, cap });
  });
  it("plays my turn again at turn three, keeping turns one and two on the new branch, until the friend has it", async () => {
    const { room: joined, first, second } = await room();
    const { turns } = await chain(0, initial(), 2);
    const one = await send(joined, first, turns[0]), two = await send(one.room, second, turns[1]);
    const three = await send(await read(two.room, first), first, turns[2]);
    // The friend has not read it: the first pip may replace it. The new turn three keeps the same memory.
    const again = await later(setB, "p0", turns.slice(0, 2), false, initial().checkpoint_hash, 15);
    const replaced = await send(three.room, first, again, undefined, { replaces: turns[2].recording_hash });
    expect(replaced.receipt).toMatchObject({ branch: 1, turn_id: "t1-0-c" });
    expect(replaced.room).toMatchObject({ a_turn_id: "t1-0-a", recording_a: print(turns[0]) });
    expect(replaced.room.open_turns).toMatchObject({ turn_hashes: [turns[0], turns[1], again].map(turn => turn.recording_hash), newest: again });
    // Once the friend's phone has read it, it stays.
    const seen = await read(replaced.room, second);
    expect(seen.active_player_id).toBe(second.player_id);
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", first, { base_revision: seen.revision, branch: seen.branch, idempotency_key: key(), recording: turns[2], replaces: again.recording_hash }), 409, "turn_already_seen");
    // And the friend closes the stage over the new turn three.
    const closingTurn = await later(setB, "p0", [turns[0], turns[1], again], true, initial().checkpoint_hash, 15);
    const done = await send(seen, second, closingTurn, await closing(setEnd as Rec, initial(), [turns[0], turns[1], again, closingTurn]));
    expect(done.room).toMatchObject({ stage_index: 1, branch: 1, completed_pair_ids: ["p1-0"] });
  });
  it("redoes the stage and starts over from any turn", async () => {
    const { room: joined, first, second } = await room();
    const { turns } = await chain(0, initial(), 2);
    const one = await send(joined, first, turns[0]), two = await send(one.room, second, turns[1]), three = await send(two.room, first, turns[2]);
    // The redo names the latest turn: the friend who played it agrees, the pip whose turn is next asks.
    const path = `/v2/rooms/${joined.room_id}/redo`, headers = { "X-AfterYou-Poll-Redo": "1", "X-AfterYou-Redo-Extras": "1" };
    const state = await json<RedoStateV2>(call(path, "GET", second, undefined, headers));
    expect(state.source).toMatchObject({ a_hash: turns[2].recording_hash, first_player_id: first.player_id, second_player_id: second.player_id, stage_index: 0 });
    const asked = await json<RedoStateV2>(call(path, "POST", second, { action: "request", source: state.source }));
    expect(asked.request?.status).toBe("pending");
    const forked = await json<MutationV2>(call(`/v2/rooms/${joined.room_id}/fork`, "POST", first, { base_revision: three.room.revision, branch: 0, stage_index: 0, idempotency_key: key(), redo_request_id: asked.request!.request_id }));
    expect(forked.room).toMatchObject({ branch: 1, stage_index: 0, a_turn_id: null, active_player_id: first.player_id });
    expect(forked.room.open_turns).toMatchObject({ turn: 1, turn_hashes: [], newest: null });
    // Played again to turn three, then started over by agreement.
    const again = await send(forked.room, first, turns[0]), twice = await send(again.room, second, turns[1]);
    const over = { room_id: joined.room_id, revision: twice.room.revision, branch: twice.room.branch, stage_index: 0, a_hash: twice.room.checkpoint.checkpoint_hash, first_player_id: second.player_id, second_player_id: first.player_id };
    const request = await json<RedoStateV2>(call(path, "POST", first, { action: "request", source: over }));
    const wiped = await json<MutationV2>(call(`/v2/rooms/${joined.room_id}/fork`, "POST", second, { base_revision: twice.room.revision, branch: twice.room.branch, stage_index: 0, idempotency_key: key(), redo_request_id: request.request!.request_id }));
    expect(wiped.room).toMatchObject({ stage_index: 0, a_turn_id: null });
    expect(wiped.room.open_turns).toMatchObject({ turn_hashes: [], newest: null, closing: null, wanted: [] });
  });
  it("writes one more row a later turn (its memory becomes a fingerprint) and one on the poll that acknowledges a closing turn", async () => {
    const { room: joined, first, second } = await room();
    const { turns, checkpoint } = await chain(0, initial(), 1);
    const cursors: { rowsRead: number; rowsWritten: number }[] = [];
    await runInDurableObject(env.ROOMS_V2.getByName(joined.room_id), (_, ctx) => {
      const original = ctx.storage.sql.exec.bind(ctx.storage.sql);
      vi.spyOn(ctx.storage.sql, "exec").mockImplementation(((query: string, ...bindings: unknown[]) => { const cursor = original(query, ...bindings); cursors.push(cursor); return cursor; }) as typeof ctx.storage.sql.exec);
    });
    const metered = async <T>(run: () => Promise<T>) => { const from = cursors.length; const value = await run(); const rows = cursors.slice(from).reduce((sum, cursor) => ({ read: sum.read + cursor.rowsRead, written: sum.written + cursor.rowsWritten }), { read: 0, written: 0 }); return { value, rows }; };
    const one = await metered(() => send(joined, first, turns[0]));
    const pass = await metered(() => send(one.value.room, second, turns[1]));
    const poll = await metered(() => read(pass.value.room, first));
    const close = await metered(() => send(poll.value, first, turns[2], checkpoint));
    const known = (room: RoomSnapshotV2) => ({ "X-AfterYou-Known-Room": `${room.revision}.${room.branch}` });
    const quiet = await metered(() => json<Rec>(call(`/v2/rooms/${joined.room_id}`, "GET", first, undefined, known(close.value.room))));
    const ack = await metered(() => json<Rec>(call(`/v2/rooms/${joined.room_id}`, "GET", second, undefined, known(close.value.room))));
    const after = await metered(() => json<Rec>(call(`/v2/rooms/${joined.room_id}`, "GET", second, undefined, known(close.value.room))));
    expect([quiet.value, ack.value, after.value].every(reply => reply.unchanged === true)).toBe(true);
    // Before fingerprints: 7, 10, 1 and 9. A pass and a closing turn now also turn the turn before them into its fingerprint
    // (one row each); the partner's poll that acknowledges the closing turn writes that one row; every other poll none.
    expect([one, pass, poll, close, quiet, ack, after].map(step => step.rows.written)).toEqual([7, 11, 1, 10, 0, 1, 0]);
  });
  it("is refused to old apps", async () => {
    const host = await account(), oldGuest = await account(); await grantFullJourney(host);
    const made = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { ...adapter.key, idempotency_key: key() }));
    await failure(call("/v2/rooms/join", "POST", oldGuest, { invite_code: made.invite_code, supported_simulation_versions: [2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] }), 422, "unsupported_simulation_version");
  });
  it("keeps a published room's replies and stored room free of open turns fields", async () => {
    const host = await account(); await grantFullJourney(host);
    const made = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { ...turnOfTheTideV2.key, idempotency_key: key() }));
    expect(made).not.toHaveProperty("open_turns");
    await runInDurableObject(env.ROOMS_V2.getByName(made.room_id), (_, ctx) => {
      const data = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data;
      expect(data).not.toContain("open_stage");
    });
    expect(chapter(turnOfTheTideV2.key).open_turns).toBeUndefined();
  });
});

const stub = (room: RoomSnapshotV2) => env.ROOMS_V2.getByName(room.room_id);
/** The turn rows still held in full (runs and all), in the order they were written. */
const full = (room: RoomSnapshotV2) => runInDurableObject(stub(room), (_, ctx) => ctx.storage.sql.exec<{ turn_id: string; data: string | ArrayBuffer }>("SELECT turn_id,data FROM turns ORDER BY rowid").toArray()
  .filter(row => typeof row.data !== "string" || row.data.includes('"packed":')).map(row => row.turn_id));

describe("open turns: fingerprints, history and replays", () => {
  const known = (room: { revision: number; branch: number }) => ({ "X-AfterYou-Known-Room": `${room.revision}.${room.branch}` });
  const poll = (room: RoomSnapshotV2, who: Account, at: { revision: number; branch: number } = room) => json<Rec>(call(`/v2/rooms/${room.room_id}`, "GET", who, undefined, known(at)));
  const value = <T>(outcome: { ok: boolean; value?: T; code?: string }): T => { if (!outcome.ok) throw new Error(outcome.code); return outcome.value!; };
  /** Both stages: the first with `passes` passes, the second closed in two; each turn the pip its number says. */
  async function finished(passes = 2) {
    const made = await room(), { first, second } = made;
    const one = await chain(0, initial(), passes), two = await chain(1, one.checkpoint, 1);
    const [slackFirst, slackSecond] = pips(one.checkpoint, first, second);
    let current = made.room;
    for (const [i, turn] of one.turns.entries()) current = (await send(current, i % 2 ? second : first, turn, i === one.turns.length - 1 ? one.checkpoint : undefined)).room;
    for (const [i, turn] of two.turns.entries()) current = (await send(current, i % 2 ? slackSecond : slackFirst, turn, i === two.turns.length - 1 ? two.checkpoint : undefined)).room;
    return { ...made, room: current, one, two, slackFirst, slackSecond };
  }

  it("keeps the closing turn full until the member who did not play it names its revision, on a poll or with their next turn", async () => {
    const { room: joined, first, second } = await room();
    const one = await chain(0, initial(), 1);
    let current = joined;
    for (const [i, turn] of one.turns.entries()) {
      current = (await send(current, i % 2 ? second : first, turn, i === one.turns.length - 1 ? one.checkpoint : undefined)).room;
      // Turn k becomes its fingerprint as turn k+1 is taken: only the newest is full.
      expect(await full(current)).toEqual([turnId(0, 0, i + 1)]);
    }
    const closer = first, partner = second;
    // The closer's own poll, the partner's plain read and a poll naming an older revision all leave it full.
    expect(await poll(current, closer)).toMatchObject({ unchanged: true });
    expect((await read(current, partner)).open_turns!.closing).toEqual(one.turns[2]);
    expect((await poll(current, partner, { revision: current.revision - 1, branch: current.branch })).open_turns.closing).toEqual(one.turns[2]);
    expect(await full(current)).toEqual(["t0-0-c"]);
    // The partner's poll at its revision: the row keeps its fingerprint, the revision stays, and the view no longer carries it.
    expect(await poll(current, partner)).toMatchObject({ unchanged: true, revision: current.revision });
    expect(await full(current)).toEqual([]);
    expect((await read(current, closer)).open_turns).toMatchObject({ closing: null, newest: null, turn_hashes: [] });
    const pair = await json<Rec>(call(`/v2/rooms/${joined.room_id}/pairs/p0-0`, "GET", partner));
    expect(pair).toMatchObject({ a: print(one.turns[0]), b: print(one.turns[2]), checkpoint: one.checkpoint });
    // Stage two: the partner's next turn acknowledges the closing turn it played over, with no poll at all.
    const two = await chain(1, one.checkpoint, 1), [slackFirst, slackSecond] = pips(one.checkpoint, first, second);
    for (const [i, turn] of two.turns.entries()) {
      current = (await send(current, i % 2 ? slackSecond : slackFirst, turn, i === two.turns.length - 1 ? two.checkpoint : undefined)).room;
      if (i === 0) expect(await full(current)).toEqual(["t0-1-a"]);
    }
    const lastCloser = two.turns.length % 2 ? slackFirst : slackSecond, lastPartner = lastCloser === first ? second : first;
    expect(await full(current)).toEqual(["t0-1-c"]);
    expect(current.open_turns).toMatchObject({ turn: 0, closing: two.turns[2] });
    // The final turn waits for the partner's poll as every closing turn does.
    expect(await poll(current, lastPartner)).toMatchObject({ unchanged: true });
    expect(await full(current)).toEqual([]);
  });

  it("sends turns back to a phone that lost them: it asks, the partner's next poll names them, the partner's phone sends them", async () => {
    const { room: joined, second, first } = await room();
    const one = await chain(0, initial(), 2);
    let current = joined;
    for (const [i, turn] of one.turns.entries()) current = (await send(current, i % 2 ? second : first, turn, i === one.turns.length - 1 ? one.checkpoint : undefined)).room;
    const path = `/v2/rooms/${joined.room_id}/turn-copies`, hashes = one.turns.map(turn => turn.recording_hash);
    const copies = (who: Account, action: string, body: unknown, status = 200) => json<Rec>(call(path + action, "POST", who, body), status);
    const rows = () => runInDurableObject(stub(current), (_, ctx) => ({ wants: ctx.storage.sql.exec("SELECT * FROM turn_wants").toArray().length, copies: ctx.storage.sql.exec("SELECT * FROM turn_copies").toArray().length }));
    // Nobody asked yet: polls carry no `wanted` and read no send-back table.
    expect(await poll(current, second)).toEqual({ schema_version: 1, unchanged: true, revision: current.revision, branch: current.branch, updated_at: current.updated_at });
    // The closer's partner lost every turn of the stage: the closing turn is still full, so it comes back at once; the rest are wanted.
    const asked = await copies(first, "/want", { schema_version: 1, recording_hashes: hashes });
    expect(asked).toEqual({ schema_version: 1, copies: [one.turns[3]], more: false });
    const wanted = hashes.slice(0, 3).sort();
    expect(await poll(current, second)).toMatchObject({ unchanged: true, wanted });
    expect((await read(current, second)).open_turns!.wanted).toEqual(wanted);
    expect((await read(current, first)).open_turns!.wanted).toEqual([]);
    // The partner's phone sends them: only wanted turns of this room, each a whole turn whose hash is its own.
    const changed = { ...one.turns[0], final_state_hash: "0".repeat(64) };
    await failure(call(path, "POST", second, { schema_version: 1, turns: [changed] }), 422, "recording_hash_mismatch");
    const counting = countingEnv(withConfig({ ...env, ...FLAGS }));
    const sent = await meterRows({ room: stub(current) }, () => json<Rec>(worker.fetch(new Request(`https://after-you.test${path}`, { method: "POST",
      headers: { "Content-Type": "application/json", "X-Player-Id": second.player_id, Authorization: "Bearer " + second.device_token }, body: JSON.stringify({ schema_version: 1, turns: one.turns }) }), counting.env)));
    expect(sent.value).toEqual({ schema_version: 1, kept: hashes.slice(0, 3) });
    expect(counting.calls.filter(name => name.startsWith("ROOMS_V2."))).toEqual(["ROOMS_V2.turnCopies"]);
    expect(sent.rows.room.written).toBe(3);
    expect(await copies(second, "", { schema_version: 1, turns: one.turns })).toEqual({ schema_version: 1, kept: hashes.slice(0, 3) });
    expect(await poll(current, second)).not.toHaveProperty("wanted");
    // The asking phone asks again and has them all; its acknowledgement drops the copies.
    const again = await meterRows({ room: stub(current) }, () => copies(first, "/want", { schema_version: 1, recording_hashes: hashes }));
    expect(again.value).toEqual({ schema_version: 1, copies: one.turns, more: false });
    expect(again.rows.room.written).toBe(1);
    expect(await rows()).toEqual({ wants: 0, copies: 3 });
    const acked = await meterRows({ room: stub(current) }, () => copies(first, "/ack", { schema_version: 1, recording_hashes: hashes }));
    expect(acked.value).toEqual({ schema_version: 1, acknowledged: hashes });
    expect(await rows()).toEqual({ wants: 0, copies: 0 });
    console.log("turn send-back rows written:", JSON.stringify({ send: sent.rows.room.written, ask_delivering: again.rows.room.written, ack: acked.rows.room.written }));
    // A copy handed over and never acknowledged goes with the room's next turn.
    expect(await copies(first, "/want", { schema_version: 1, recording_hashes: [hashes[0]] })).toMatchObject({ copies: [] });
    await copies(second, "", { schema_version: 1, turns: [one.turns[0]] });
    expect((await copies(first, "/want", { schema_version: 1, recording_hashes: [hashes[0]] })).copies).toEqual([one.turns[0]]);
    const two = await chain(1, one.checkpoint, 1), [slackFirst] = pips(one.checkpoint, first, second);
    current = (await send(current, slackFirst, two.turns[0])).room;
    expect(await rows()).toEqual({ wants: 0, copies: 0 });
    // Only turns of this room, and only in an open turns room.
    await failure(call(path + "/want", "POST", first, { schema_version: 1, recording_hashes: ["0".repeat(64)] }), 422, "turn_not_in_room");
    const host = await account(); await grantFullJourney(host);
    const published = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { ...turnOfTheTideV2.key, idempotency_key: key() }));
    await failure(call(`/v2/rooms/${published.room_id}/turn-copies/want`, "POST", host, { schema_version: 1, recording_hashes: hashes }), 409, "open_turns_only");
  });
  it("keeps a finished room's history: fingerprints in its attempt, offloaded and sent back, then a fork from its pair row", async () => {
    const { room: done, first, second, one } = await finished();
    const host = done.host_id, guest = done.guest_id!, room = stub(done);
    for (const who of [first, second]) await poll(done, who);
    const view = value(await room.history(host, 1)); value(await room.history(guest, 1));
    expect(view.attempts).toHaveLength(1);
    const bytes = value(await room.historyAttempt(guest, 0, 1));
    const blob = JSON.parse(new TextDecoder().decode((await decodeBlob(bytes, view.attempts[0].byte_length))!)) as Rec;
    // The attempt lists every turn as its fingerprint and each pair's flat checkpoint, so its bytes never move.
    expect(blob).toMatchObject({ format: "after-you.attempt", format_version: 2, checkpoint: done.checkpoint, checkpoints: [one.checkpoint, done.checkpoint] });
    expect(blob.turns).toHaveLength(7); expect(blob.turns.every((turn: Rec) => !("packed" in turn))).toBe(true);
    expect(blob).not.toHaveProperty("open_turn");
    const before = value(await room.snapshot(host));
    for (const player of [host, guest]) value(await room.acknowledgeHistory(player, 0, { schema_version: 1, link: view.attempts[0].link }, 1));
    expect(await room.snapshot(host)).toMatchObject({ ok: false, code: "replay_transferred" });
    // Sent back, the room is as it was, and a fork goes back to stage two from its first pair's checkpoint.
    expect(value(await room.uploadHistory(guest, 0, bytes, 1)).attempts[0]).toMatchObject({ state: "held" });
    expect(value(await room.snapshot(host))).toEqual(before);
    const forked = value(await room.fork(host, { base_revision: before.revision, branch: before.branch, stage_index: 1, idempotency_key: key() })).room;
    expect(forked).toMatchObject({ branch: 1, stage_index: 1, checkpoint: one.checkpoint, completed_pair_ids: ["p0-0"] });
    expect(value(await room.history(host, 1)).attempts).toHaveLength(1);
  });

  it("transfers a finished room's replays with every turn as its fingerprint, exports it compacted and restores it", async () => {
    const { room: done } = await finished(), host = done.host_id, guest = done.guest_id!, room = stub(done);
    const state = value(await room.snapshot(host));
    const offered = value(await room.replayTransfer(host));
    expect(offered.archive!.turns.every(turn => !("packed" in turn.recording))).toBe(true);
    expect(offered.archive!.room.checkpoint).toEqual(done.checkpoint);
    const ack = { schema_version: 1, epoch: offered.manifest.epoch, archive_hash: offered.manifest.archive_hash };
    for (const player of [host, guest]) value(await room.acknowledgeReplayTransfer(player, ack));
    // A transferred room with passes exports and restores (each pass has its receipt, and no pair).
    const compacted = await room.exportSnapshot("d".repeat(40));
    expect(await env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()).restoreSnapshot(value(compacted), done.room_id)).toMatchObject({ ok: true });
    value(await room.restoreReplayTransfer(guest, { ...ack, archive: offered.archive }));
    // Back from its fingerprints: the same room, less the final turn the partner had not acknowledged yet.
    expect(value(await room.snapshot(host))).toEqual({ ...state, open_turns: { ...state.open_turns, closing: null } });
  });
});

describe("open turns: a hard room", () => {
  const HARD = { "X-AfterYou-Hard-Mode": "1" };
  type Reset = { room: RoomSnapshotV2; failure: Rec };
  type Slips = { failures: number; list: (Rec & { slip: Rec | null })[] };
  async function hardRoom(): Promise<{ room: RoomSnapshotV2; first: Account; second: Account }> {
    const host = await account(), guest = await account(); await grantFullJourney(host);
    const made = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { ...adapter.key, idempotency_key: key(), mode: "hard" }));
    const joined = await json<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: made.invite_code, supported_simulation_versions: NEW_CLIENT }, HARD));
    return { room: joined, first: host, second: guest };
  }
  /** A slip's reset; under open turns a slip over a pass brings the turns under its memory from the phone's copy (`chain`). */
  const reset = (room: RoomSnapshotV2, who: Account, slip: Rec, chain?: Rec[]) => call(`/v2/rooms/${room.room_id}/hard-reset`, "POST", who,
    { base_revision: room.revision, branch: room.branch, idempotency_key: key(), reason: "failed_turn", stage_index: room.stage_index, role: room.active_role, slip, ...(chain ? { chain } : {}) });
  const slipped = (room: RoomSnapshotV2, who: Account, slip: Rec, chain?: Rec[]) => json<Reset>(reset(room, who, slip, chain));
  const slips = (room: RoomSnapshotV2, who: Account, seen = 0) => json<Slips>(call(`/v2/rooms/${room.room_id}/hard/${seen}`, "GET", who));
  /** Stage one's first three turns from `room`: two passes over turn 1, so turns 1 and 2 are fingerprints and turn 3 is full. */
  async function threeTurns(room: RoomSnapshotV2, first: Account, second: Account, turns: Rec[]): Promise<RoomSnapshotV2> {
    const one = await send(room, first, turns[0]), two = await send(one.room, second, turns[1]);
    return (await send(two.room, first, turns[2])).room;
  }

  it("plays a stage in several turns, keeps a slip over a pass with the turns under it from the phone's copy, and starts again", async () => {
    const { room: joined, first, second } = await hardRoom();
    expect(joined.hard).toEqual({ schema_version: 1, failures: 0, over: false, last: null });
    const { turns, checkpoint } = await chain(0, initial(), 2);
    const three = await threeTurns(joined, first, second, turns);
    expect(three.open_turns).toMatchObject({ turn: 4, turn_hashes: turns.slice(0, 3).map(turn => turn.recording_hash), newest: turns[2] });
    // The room holds turns 1 and 2 only as fingerprints.
    expect(await full(three)).toEqual([turnId(0, 0, 3)]);
    // The second pip slips on turn 4 and sends the turns under its memory from its own copy: the room matches them to its
    // fingerprints and keeps the slip whole, with its memory (turn 3, held in full) and those turns.
    const slip = await later(setB, "p0", turns.slice(0, 3), false, initial().checkpoint_hash, 9);
    const reset = await slipped(three, second, slip, [turns[0], turns[1]]);
    expect(reset.room).toMatchObject({ branch: 1, stage_index: 0, a_turn_id: null, active_role: "a", active_player_id: first.player_id });
    expect(reset.room.open_turns).toMatchObject({ turn: 1, turn_hashes: [], newest: null });
    expect(reset.failure).toMatchObject({ by: second.player_id, stage_index: 0, role: "b", reason: "failed_turn" });
    const kept = await slips(joined, first);
    expect(kept.list[0].slip).toEqual({ recording: slip, checkpoint: initial(), prior: turns[2], chain: [turns[0], turns[1]] });
    // The partner's phone replays it from the slip alone, while the turn rows stay fingerprints (the left branch keeps its newest).
    expect(await full(three)).toEqual([turnId(0, 0, 3)]);
    // A slip on turn 2 keeps its memory alone, as a two-turn room does.
    const again = await send(reset.room, first, turns[0]);
    const early = await slipped(again.room, second, turns[1]);
    expect((await slips(joined, first, 1)).list[0].slip).toEqual({ recording: turns[1], checkpoint: initial(), prior: turns[0] });
    // The run after it plays the whole chapter, passes and all, and finishes.
    let current = (await send(early.room, first, turns[0])).room;
    current = (await send(current, second, turns[1])).room;
    current = (await send(current, first, turns[2])).room;
    current = (await send(current, second, turns[3], checkpoint)).room;
    expect(current).toMatchObject({ stage_index: 1, branch: 2, hard: { failures: 2, over: false } });
    const next = await chain(1, checkpoint, 0), [slackFirst] = pips(checkpoint, first, second);
    current = (await send(current, slackFirst, next.turns[0])).room;
    current = (await send(current, slackFirst === first ? second : first, next.turns[1], next.checkpoint)).room;
    expect(current.active_role).toBe("complete");
  });
  it("drops a slip whose turns under its memory are not the room's, and still starts the run again", async () => {
    const { room: joined, first, second } = await hardRoom();
    const { turns } = await chain(0, initial(), 2);
    const slip = await later(setB, "p0", turns.slice(0, 3), false, initial().checkpoint_hash, 9);
    // Another turn 2 that checks on its own but is not the one the room took.
    const otherTwo = await later(setB, "p0", [turns[0]], false, initial().checkpoint_hash, 3);
    // Missing, out of order, another turn, and a fingerprint where a whole turn belongs (the chapter keeps 7 branches, so 5 resets here).
    const wrong: (Rec[] | undefined)[] = [undefined, [turns[1], turns[0]], [turns[0], otherTwo], [turns[0], print(turns[1])]];
    let current = joined;
    for (const [i, sent] of wrong.entries()) {
      const done = await slipped(await threeTurns(current, first, second, turns), second, slip, sent);
      expect(done.room).toMatchObject({ branch: i + 1, stage_index: 0, a_turn_id: null, hard: { failures: i + 1, over: false } });
      expect((await slips(joined, first, i)).list[0]).toMatchObject({ number: i + 1, by: second.player_id, slip: null });
      current = done.room;
    }
    // A slip on turn 2 has no turns under its memory, so a chain with it is not the room's either.
    const one = await send(current, first, turns[0]);
    await slipped(one.room, second, turns[1], [turns[0]]);
    expect((await slips(joined, first, wrong.length)).list[0].slip).toBeNull();
    // A chain needs a slip.
    const two = await read(current, first);
    await failure(call(`/v2/rooms/${joined.room_id}/hard-reset`, "POST", first, { base_revision: two.revision, branch: two.branch, idempotency_key: key(), reason: "failed_turn",
      stage_index: two.stage_index, role: two.active_role, chain: [turns[0]] }), 400, "unexpected_fields");
  });
  it("takes only first tries and never plays a turn again", async () => {
    const { room: joined, first, second } = await hardRoom();
    const { turns } = await chain(0, initial(), 2);
    const one = await send(joined, first, turns[0]), two = await send(one.room, second, turns[1]);
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", first, { base_revision: two.room.revision, branch: two.room.branch, idempotency_key: key(), recording: turns[2], tries: 2 }), 409, "hard_run_retry");
    const three = await send(two.room, first, turns[2]);
    const again = await later(setB, "p0", turns.slice(0, 2), false, initial().checkpoint_hash, 15);
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", first, { base_revision: three.room.revision, branch: three.room.branch, idempotency_key: key(), recording: again, replaces: turns[2].recording_hash }), 409, "hard_run_no_redo");
  });
  it("ends the run when the room cannot hold another one with every stage at its cap", async () => {
    const { room: joined, first, second } = await hardRoom();
    const { turns } = await chain(0, initial(), 1);
    const caps = adapter.open_turns!.caps.reduce((sum, cap) => sum + cap, 0);
    // Two turns a stage would still fit; a whole run at every stage's cap would not.
    const filler = 128 - caps;
    expect(filler + 1 + 2 * adapter.stages.length).toBeLessThanOrEqual(128);
    await runInDurableObject(env.ROOMS_V2.getByName(joined.room_id), (_, ctx) => {
      for (let n = 0; n < filler; n++) ctx.storage.sql.exec("INSERT INTO turns VALUES (?,?,?,?)", `x${n}`, first.player_id, 0, "{}");
    });
    const one = await send(joined, first, turns[0]);
    const reset = await slipped(one.room, second, turns[1]);
    expect(reset.room).toMatchObject({ branch: 0, a_turn_id: one.room.a_turn_id, hard: { failures: 1, over: true } });
  });
});

describe("open turns: snapshot restore", () => {
  type Archive = { payload: { tables: { name: string; rows: Rec[] }[]; summary: Rec }; checksum: { value: string } };
  const commit = "d".repeat(40);
  async function exported(stub: { exportSnapshot(commit: string): Promise<{ ok: boolean; value?: string; code?: string }> }): Promise<string> {
    const result = await stub.exportSnapshot(commit); expect(result, result.code).toMatchObject({ ok: true }); return result.value!;
  }
  const restore = (roomId: string, archive: string) => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()).restoreSnapshot(archive, roomId);
  /** Exports the live room, restores it into an empty object and exports that again: the same tables and summary. */
  async function roundTrip(roomId: string): Promise<Archive> {
    const archive = await exported(env.ROOMS_V2.getByName(roomId)), target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await target.restoreSnapshot(archive, roomId)).toMatchObject({ ok: true });
    const original = JSON.parse(archive) as Archive, again = JSON.parse(await exported(target)) as Archive;
    expect(again.payload.tables).toEqual(original.payload.tables); expect(again.payload.summary).toEqual(original.payload.summary);
    return original;
  }
  const roomRow = (archive: Archive) => archive.payload.tables[0].rows[0];
  async function tampered(archive: Archive, change: (room: Rec) => void): Promise<string> {
    const copy = structuredClone(archive), room = JSON.parse(roomRow(copy).data); change(room); roomRow(copy).data = JSON.stringify(room);
    copy.checksum.value = await digest(canonicalJson(copy.payload)); return canonicalJson(copy);
  }

  it("restores a room mid stage with its passes, and refuses a changed open stage", async () => {
    const { room: joined, first, second } = await room();
    const { turns } = await chain(0, initial(), 2);
    const one = await send(joined, first, turns[0]), two = await send(one.room, second, turns[1]);
    await send(two.room, first, turns[2]);
    const archive = await roundTrip(joined.room_id);
    expect(JSON.parse(roomRow(archive).data).open_stage.passes.map((pass: Rec) => pass.turn_id)).toEqual(["t0-0-b", "t0-0-c"]);
    for (const change of [
      (state: Rec) => { state.open_stage.passes[1].recording_hash = turns[1].recording_hash; },
      (state: Rec) => { state.open_stage.passes[0].turn_id = "t0-0-c"; },
      (state: Rec) => { state.open_stage.passes.pop(); },
      (state: Rec) => { delete state.open_stage; },
    ]) expect(await restore(joined.room_id, await tampered(archive, change))).toMatchObject({ ok: false, code: "snapshot_open_stage_mismatch" });
  });
  it("restores a finished two stage room with passes", async () => {
    const { room: joined, first, second } = await room();
    const { turns, checkpoint } = await chain(0, initial(), 2);
    let current = joined;
    for (const [i, turn] of turns.entries()) current = (await send(current, i % 2 ? second : first, turn, i === turns.length - 1 ? checkpoint : undefined)).room;
    const next = await chain(1, checkpoint, 1), [slackFirst, slackSecond] = pips(checkpoint, first, second);
    for (const [i, turn] of next.turns.entries()) current = (await send(current, i % 2 ? slackSecond : slackFirst, turn, i === next.turns.length - 1 ? next.checkpoint : undefined)).room;
    expect(current).toMatchObject({ stage_index: 2, active_role: "complete" });
    const archive = await roundTrip(joined.room_id);
    expect(archive.payload.summary).toMatchObject({ state: "active", branch: 0 });
    expect(archive.payload.tables.find(table => table.name === "turns")!.rows).toHaveLength(7);
  });
  it("restores a room after a pass played again, with the turns it copied and no receipt of their own", async () => {
    const { room: joined, first, second } = await room();
    const { turns } = await chain(0, initial(), 2);
    const one = await send(joined, first, turns[0]), two = await send(one.room, second, turns[1]);
    const three = await send(await read(two.room, first), first, turns[2]);
    const again = await later(setB, "p0", turns.slice(0, 2), false, initial().checkpoint_hash, 15);
    const replaced = await send(three.room, first, again, undefined, { replaces: turns[2].recording_hash });
    const mid = await roundTrip(joined.room_id);
    expect(mid.payload.tables.find(table => table.name === "operations")!.rows).toHaveLength(4);
    // A copy that no longer matches the turn it came from has no receipt to stand on.
    const changedCopy = structuredClone(mid), copy = changedCopy.payload.tables[1].rows.find(row => row.turn_id === "t1-0-b")!;
    copy.accepted_revision++;
    changedCopy.checksum.value = await digest(canonicalJson(changedCopy.payload));
    expect(await restore(joined.room_id, canonicalJson(changedCopy))).toMatchObject({ ok: false, code: "snapshot_missing_receipt" });
    const seen = await read(replaced.room, second);
    const closingTurn = await later(setB, "p0", [turns[0], turns[1], again], true, initial().checkpoint_hash, 15);
    await send(seen, second, closingTurn, await closing(setEnd as Rec, initial(), [turns[0], turns[1], again, closingTurn]));
    expect((await roundTrip(joined.room_id)).payload.summary).toMatchObject({ state: "active", branch: 1 });
  });
});

describe("open turns: packed turns only", () => {
  it("takes packed turns with the packed recordings switch off and says nothing of it, and refuses a JSON turn", async () => {
    const { room: joined, first, second } = await room(), start = initial();
    expect(joined).not.toHaveProperty("packed_recordings");
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", first, { base_revision: joined.revision, branch: 0, idempotency_key: key(), recording: await jsonForm({ ...structuredClone(setA), checkpoint_hash: start.checkpoint_hash }) }), 422, "packed_recording_required");
    const { turns, checkpoint } = await chain(0, start, 1);
    expect(turns.every(turn => "packed" in turn)).toBe(true);
    const one = await send(joined, first, turns[0]);
    const two = await send(one.room, second, turns[1]);
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", first, { base_revision: two.room.revision, branch: 0, idempotency_key: key(), recording: await jsonForm({ ...structuredClone(setB), checkpoint_hash: start.checkpoint_hash, player_slot: setA.player_slot, source_recording_hash: turns[1].recording_hash }), checkpoint }), 422, "packed_recording_required");
    expect((await send(two.room, first, turns[2], checkpoint)).receipt).toMatchObject({ turn_id: "t0-0-c", pair_id: "p0-0" });
  });
});

/**
 * Carry-over turns (rules 18 to 21, claude-20261011/carry-over-turns/design.md) on CARRY. The server never simulates: each turn names its start world, its hand-off
 * tick and the world it hands to the next turn, and the server checks that they chain. Hand-offs here are worked out from
 * the design's timeline, S(1) = S(2) = 0, S(k) = S(k-2) + L(k-2) and H(k) = S(k) - S(k-1), not from the server's own sum.
 */
describe("carry-over turns", () => {
  /** H(k) for each turn of a stage whose turns last `lengths`, straight from the design's S. */
  function handoffs(lengths: number[]): number[] {
    const start: number[] = [];
    for (let k = 1; k <= lengths.length; k++) start.push(k <= 2 ? 0 : start[k - 3] + lengths[k - 3]);
    return start.map((s, i) => i === 0 ? 0 : s - start[i - 1]);
  }
  const header = (n: number, ticks: number, handoff: number, done = false) =>
    ({ duration_ticks: ticks, handoff_tick: handoff, start_hash: `s${n}`, handoff_hash: n === 1 ? "s1" : `s${n + 1}`, completed: done }) as unknown as ChapterRecording;
  /** `actions` held still for `pad` more ticks (a still last run grows, as the codec keeps no two equal runs side by side). */
  function padded(actions: Rec[], pad: number): Rec[] {
    const last = actions.at(-1);
    if (!pad) return actions;
    if (last && last.x === 0 && last.z === 0 && !last.action) return [...actions.slice(0, -1), { ...last, ticks: last.ticks + pad }];
    return [...actions, { ticks: pad, x: 0, z: 0, action: false }];
  }
  /** Turn `n` of a stage: fixture `fixture`'s runs padded to `ticks`, pip `slot`'s, over `turns` (the stage's turns so far), its hand-off from S unless `change` says otherwise. */
  async function carryTurn(fixture: Rec, checkpoint: Rec, slot: string, turns: Rec[], ticks: number, closes = false, change: (turn: Rec) => void = () => {}): Promise<Rec> {
    const n = turns.length + 1, h = handoffs([...turns.map(turn => turn.duration_ticks), ticks]).at(-1)!;
    const start = turns.at(-1)?.handoff_hash ?? await digest(`start ${checkpoint.checkpoint_hash}`);
    const { packed: _packed, recording_hash: _hash, ...rest } = structuredClone(fixture); void _packed; void _hash;
    const runs = listed(fixture), pad = ticks - fixture.duration_ticks;
    const turn: Rec = { ...rest, simulation_version: 19, level_version: CARRY.level_version, definition_hash: CARRY.definition_hash, checkpoint_hash: checkpoint.checkpoint_hash,
      role: n === 1 ? "a" : "b", player_slot: slot, source_recording_hash: turns.at(-1)?.recording_hash ?? "", duration_ticks: ticks,
      actions: padded(runs.actions, pad), replay_checks: runs.replay_checks,
      completed: n > 1 && closes, outcome: { source_ready: true, objective_complete: n > 1 && closes },
      handoff_tick: h, start_hash: start, handoff_hash: n === 1 ? start : await digest(`world ${checkpoint.checkpoint_hash} ${n} ${ticks}`) };
    change(turn);
    return hashed(turn);
  }
  /** The checkpoint closing a stage with `turns` from fixture end `end`, naming `next` (by default the pip that did not close it) to start the next stage. */
  async function carryClosing(end: Rec, previous: Rec, turns: Rec[], next = other(turns.at(-1)!.player_slot)): Promise<Rec> {
    return sealed({ ...await closing(end, previous, turns), next_first_slot: next });
  }
  const refused = (room: RoomSnapshotV2, who: Account, recording: Rec, code: string) =>
    failure(call(`/v2/rooms/${room.room_id}/turns`, "POST", who, { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording }), 409, code);
  async function carryRoom() {
    const host = await account(), guest = await account();
    const made = await json<RoomSnapshotV2>(call("/v2/rooms", "POST", host, { ...CARRY, idempotency_key: key() }));
    return { host, guest, room: await json<RoomSnapshotV2>(call("/v2/rooms/join", "POST", guest, { invite_code: made.invite_code, supported_simulation_versions: NEW_CLIENT })) };
  }

  it("plays open turns on 18 to 21 only, with schema 9 checkpoints and the hand-off fields", () => {
    const rules = Array.from({ length: 22 }, (_, n) => n);
    expect([rules.filter(openTurns), rules.filter(openControls), rules.filter(tideRules), rules.filter(piecesRules), rules.filter(sharedBall)])
      .toEqual([[18, 19, 20, 21], [12, 13, 18, 19, 20, 21], [10, 13, 19, 20], [20], [21]]);
    expect(rules.filter(comfortRules)).toEqual([8, 9, 10, 12, 13, 18, 19, 20, 21]);
    expect(adapter.open_turns).toMatchObject({ branches: 7 });
    expect([OPEN_CHECKPOINT_SCHEMA, OPEN_CHECKPOINT_KEYS.at(-2)]).toEqual([9, "next_first_slot"]);
    expect(CARRY_RECORD_KEYS).toEqual(["handoff_tick", "start_hash", "handoff_hash"]);
  });

  it("counts a run's carry-over turns by what each adds to the shared timeline", () => {
    // The design's Falls stage 1: S(4) = 40 s, so the stage lasts 40 + 45 = 85 s, or 60 s when turn 4 closes it at 20 s.
    expect(timelineShares([8, 40, 70, 45])).toEqual([8, 32, 38, 7]);
    expect(timelineShares([8, 40, 70, 20])).toEqual([8, 32, 38, -18]);
    expect(timelineShares([30])).toEqual([30]);
  });

  it("works each hand-off out from the turn before and the one under it, as the timeline says", () => {
    // The design's Falls: 8 s, 40 s and 70 s, then the friend's turn ending at 45 s or exactly at the rest of the 70 s.
    expect(handoffs([240, 1200, 2100, 1350, 300])).toEqual([0, 0, 240, 960, 1140]);
    const lengths = [240, 1200, 2100, 1350, 300, 900, 37, 1800];
    const h = handoffs(lengths);
    for (let k = 2; k <= lengths.length; k++) {
      const memory = header(k - 1, lengths[k - 2], h[k - 2]), before = k > 2 ? header(k - 2, lengths[k - 3], h[k - 3]) : null;
      expect(handoffTick(memory, before), `turn ${k}`).toBe(h[k - 1]);
    }
    // Turn 1 hands off at 0 from its own start; turn 2 takes over at turn 1's tick 0 and lasts at least all of it.
    expect(carryFits(header(1, 240, 0), null, null)).toBe(true);
    expect(carryFits({ ...header(1, 240, 0), handoff_hash: "s2" } as ChapterRecording, null, null)).toBe(false);
    expect(carryFits({ ...header(1, 240, 3) } as ChapterRecording, null, null)).toBe(false);
    const one = header(1, 240, 0), two = header(2, 1200, 0), three = header(3, 2100, 240);
    expect(carryFits({ ...two, start_hash: "s1" } as ChapterRecording, one, null)).toBe(true);
    expect(carryFits({ ...two, start_hash: "s1", duration_ticks: 239 } as ChapterRecording, one, null)).toBe(false);
    // Turn 3: from turn 2's hand-off world, at turn 1's length, and a pass outlasts the rest of turn 2 (960 ticks).
    expect(carryFits(three, two, one)).toBe(true);
    expect(carryFits({ ...three, start_hash: "x" } as ChapterRecording, two, one)).toBe(false);
    expect(carryFits({ ...three, handoff_tick: 0 } as ChapterRecording, two, one)).toBe(false);
    expect(carryFits({ ...three, duration_ticks: 959 } as ChapterRecording, two, one)).toBe(false);
    expect(carryFits({ ...three, duration_ticks: 960 } as ChapterRecording, two, one)).toBe(true);
    // A closing turn ends the moment both pips are at the goal, the rest of the replay dropped (owner, 2026-11-21).
    expect(carryFits({ ...three, duration_ticks: 10, completed: true } as ChapterRecording, two, one)).toBe(true);
    expect(carryFits({ ...three, duration_ticks: 10, completed: true, handoff_tick: 0 } as ChapterRecording, two, one)).toBe(false);
  });

  it("takes each stage's first pip from the checkpoint before it, and refuses a broken chain, a short pass and a wrong next pip", async () => {
    const { host, guest, room: joined } = await carryRoom(), start = joined.checkpoint as Rec;
    // The first stage starts with the host's pip.
    expect(joined).toMatchObject({ first_player_id: host.player_id, active_player_id: host.player_id, active_role: "a" });
    // A first turn is its own next start.
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", host, { base_revision: joined.revision, branch: 0, idempotency_key: key(),
      recording: await carryTurn(setA as Rec, start, "p0", [], 577, false, turn => { turn.handoff_hash = "a".repeat(64); }) }), 422, "invalid_handoff");
    const t1 = await carryTurn(setA as Rec, start, "p0", [], 577);
    let current = (await send(joined, host, t1)).room;
    // Turn 2 starts from turn 1's start world, at its tick 0.
    await refused(current, guest, await carryTurn(setB as Rec, start, "p1", [t1], 1300, false, turn => { turn.start_hash = "b".repeat(64); }), "source_recording_mismatch");
    await refused(current, guest, await carryTurn(setB as Rec, start, "p1", [t1], 1300, false, turn => { turn.handoff_tick = 1; }), "source_recording_mismatch");
    const t2 = await carryTurn(setB as Rec, start, "p1", [t1], 1300);
    current = (await send(current, guest, t2)).room;
    // Turn 3 takes over at turn 1's length (577) and, as a pass, outlasts the rest of turn 2 (723 ticks).
    expect(t2.handoff_hash).not.toBe(t1.handoff_hash);
    await refused(current, host, await carryTurn(setB as Rec, start, "p0", [t1, t2], 722), "source_recording_mismatch");
    await refused(current, host, await carryTurn(setB as Rec, start, "p0", [t1, t2], 1400, false, turn => { turn.handoff_tick = 0; }), "source_recording_mismatch");
    await refused(current, host, await carryTurn(setB as Rec, start, "p0", [t1, t2], 1400, false, turn => { turn.start_hash = t1.handoff_hash; }), "source_recording_mismatch");
    const t3 = await carryTurn(setB as Rec, start, "p0", [t1, t2], 1400);
    current = (await send(current, host, t3)).room;
    // Turn 4 hands off at 723 with 677 ticks of turn 3 left, and closes the stage sooner: the rest of the replay is dropped.
    const t4 = await carryTurn(setB as Rec, start, "p1", [t1, t2, t3], (setB as Rec).duration_ticks, true);
    expect([t4.handoff_tick, t3.duration_ticks - t4.handoff_tick]).toEqual([723, 677]);
    await failure(call(`/v2/rooms/${joined.room_id}/turns`, "POST", guest, { base_revision: current.revision, branch: 0, idempotency_key: key(), recording: t4,
      checkpoint: await carryClosing(setEnd as Rec, start, [t1, t2, t3, t4], "p1") }), 422, "checkpoint_recording_mismatch");
    const stageOne = await carryClosing(setEnd as Rec, start, [t1, t2, t3, t4]);
    expect(stageOne.next_first_slot).toBe("p0");
    current = (await send(current, guest, t4, stageOne)).room;
    // The guest closed it, so the host's pip starts stage two, where the definition names the guest's.
    expect(adapter.stages[1].first_player_slot).toBe("p1");
    expect(current).toMatchObject({ stage_index: 1, checkpoint: stageOne, first_player_id: host.player_id, active_player_id: host.player_id, active_role: "a" });
    const status = async (who: Account) => (await json<{ rooms: { room_id: string; status: string }[] }>(call("/v1/room-inbox", "GET", who))).rooms.find(row => row.room_id === joined.room_id)?.status;
    expect([await status(host), await status(guest)]).toEqual(["your_turn", "waiting_for_their_turn"]);
    await refused(current, guest, await carryTurn(slackA as Rec, stageOne, "p1", [], 557), "wrong_turn");
    await refused(current, host, await carryTurn(slackA as Rec, stageOne, "p1", [], 557), "wrong_turn");
    const s1 = await carryTurn(slackA as Rec, stageOne, "p0", [], 557);
    current = (await send(current, host, s1)).room;
    expect([await status(host), await status(guest)]).toEqual(["waiting_for_their_turn", "your_turn"]);
    const s2 = await carryTurn(slackB as Rec, stageOne, "p1", [s1], 827, true), stageTwo = await carryClosing(slackEnd as Rec, stageOne, [s1, s2]);
    current = (await send(current, guest, s2, stageTwo)).room;
    expect(current).toMatchObject({ stage_index: 2, active_role: "complete", checkpoint: stageTwo });
    expect(stageTwo.next_first_slot).toBe("p0");
    // The finished room's snapshot restores, and its replays transfer with every turn as its fingerprint.
    const exported = await stub(current).exportSnapshot("d".repeat(40));
    expect(exported).toMatchObject({ ok: true });
    expect(await env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()).restoreSnapshot((exported as { value: string }).value, current.room_id)).toMatchObject({ ok: true });
    const offered = await stub(current).replayTransfer(host.player_id);
    expect(offered).toMatchObject({ ok: true });
    const archive = (offered as { value: { archive: { turns: { recording: Rec }[] } } }).value.archive;
    expect(archive.turns.map(turn => turn.recording.handoff_tick)).toEqual(expect.arrayContaining([0, 0, 577, 723]));
    expect(archive.turns.every(turn => isFingerprint(turn.recording))).toBe(true);
  });

  it("keeps the hand-off fields under each turn's hash and in its fingerprint", async () => {
    const start = initialCheckpoint(CARRY) as unknown as Rec, t1 = await carryTurn(setA as Rec, start, "p0", [], 577);
    const t2 = await carryTurn(setB as Rec, start, "p1", [t1], 700);
    for (const turn of [t1, t2]) expect(await adapter.recording(turn)).toBeTruthy();
    expect(await adapter.recording(print(t2), true)).toMatchObject({ handoff_tick: 0, start_hash: t1.handoff_hash, handoff_hash: t2.handoff_hash });
    // A changed field breaks the hash; a turn without them is refused.
    await expect(adapter.recording({ ...t2, handoff_tick: 1 })).rejects.toMatchObject({ code: "recording_hash_mismatch" });
    const { handoff_tick: _h, start_hash: _s, handoff_hash: _o, ...older } = t2; void _h; void _s; void _o;
    await expect(adapter.recording(await hashed(older))).rejects.toBeTruthy();
  });
});
