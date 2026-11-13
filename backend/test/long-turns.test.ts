import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { ApiError, canonicalJson, digest, type Outcome } from "../src/protocol";
import { boundedTurnValue } from "../src/v2/protocol-relay";
import { ARCHIVE_BOUNDS, checkLongTurnBounds, INPUT_RULES, inputRules, LONG_TURN_TICKS, longTurnRows, maxActionEntries, ROW_ENVELOPE_BYTES, scaledLimits, turnLimits, type LongTurnShape } from "../src/v2/protocol-physical-recording";
import { adapter as journeyAdapter, turnOfTheTide } from "../src/v2/protocol-journey";
import { LIGHTHOUSE_LIMITS, LIGHTHOUSE_MAX_BRANCHES } from "../src/v2/protocol-lighthouse";
import { CHAPTERS } from "../src/v2/chapters";
import { MAX_ROW_BYTES, rowText } from "../src/v2/row-bound";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { RoomSnapshotV2 } from "../src/v2/room";
import tideV2Definition from "../src/v2/turn-of-the-tide-v2.json";
import initial from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-initial-checkpoint.json";
import setA from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-set-the-tide-a.json";
import setB from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-set-the-tide-b.json";
import setCheckpoint from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-set-the-tide-checkpoint.json";
import slackA from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-slack-water-a.json";
import slackB from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-slack-water-b.json";
import slackCheckpoint from "../../game/tests/fixtures/journey/turn-of-the-tide-v2-slack-water-checkpoint.json";
import tideA from "../../game/tests/fixtures/journey/set-the-tide-a.json";
import cases from "../../game/tests/fixtures/journey/turn-limits-cases.json";
import { MAX_REPLAY_BYTES } from "../src/leaderboards/rules";

// A new two-stage chapter with capped input and 15 minute turns (index.gd
// DEVELOPMENT_TURN_LIMITS): Turn of the Tide @2's stages under input_rules 1.
type Json = Record<string, any>;
const TURNS = { a_ticks: 26_700, b_ticks: 27_000 };
const LONG = { ...tideV2Definition, input_rules: 1, turn_limits: TURNS };
const HASH = "e".repeat(64);
const RULES = INPUT_RULES[1];
const bytes = (value: unknown) => new TextEncoder().encode(typeof value === "string" ? value : JSON.stringify(value)).byteLength;
const shape: LongTurnShape = { turns: TURNS, rules: RULES, stages: 2, initial_bytes: bytes(initial), id_bytes: LONG.id.length + Math.max(...LONG.stages.map(stage => stage.id.length)) };

/** `template` at `ticks` with every change the cap allows, each entry and check at its widest. Only the structure is valid. */
async function frantic(template: Json, ticks: number, checkpointHash: string, sourceHash: string, entries = maxActionEntries(RULES, ticks)): Promise<Json> {
  const body = structuredClone(template); delete body.recording_hash;
  const checks = Math.floor(ticks / 30) + 1, per = Math.floor(ticks / entries), extra = ticks % entries;
  Object.assign(body, { definition_hash: HASH, duration_ticks: ticks, catch_assistance: false, checkpoint_hash: checkpointHash, source_recording_hash: sourceHash,
    actions: Array.from({ length: entries }, (_, index) => ({ action: false, ticks: per + (index < extra ? 1 : 0), x: -100, z: index % 2 ? -99 : -100 })),
    replay_checks: Array.from({ length: checks }, (_, index) => ({ tick: ticks - checks + 1 + index, state_hash: body.final_state_hash })) });
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}
async function proven(template: Json, previous: Json, a: Json, b: Json): Promise<Json> {
  const body = structuredClone(template); delete body.checkpoint_hash; delete body.proof;
  Object.assign(body, { definition_hash: HASH, previous_checkpoint_hash: previous.checkpoint_hash, a_recording_hash: a.recording_hash, b_recording_hash: b.recording_hash });
  return { ...body, checkpoint_hash: await digest(canonicalJson(body)), proof: { checkpoint: previous, a, b } };
}
type Chain = { a1: Json; b1: Json; cp1: Json; a2: Json; b2: Json; cp2: Json };
async function franticChain(): Promise<Chain> {
  const a1 = await frantic(setA, TURNS.a_ticks, initial.checkpoint_hash, ""), b1 = await frantic(setB, TURNS.b_ticks, initial.checkpoint_hash, a1.recording_hash);
  const cp1 = await proven(setCheckpoint, initial, a1, b1);
  const a2 = await frantic(slackA, TURNS.a_ticks, cp1.checkpoint_hash, ""), b2 = await frantic(slackB, TURNS.b_ticks, cp1.checkpoint_hash, a2.recording_hash);
  return { a1, b1, cp1, a2, b2, cp2: await proven(slackCheckpoint, cp1, a2, b2) };
}

describe("capped input and 15 minute turns", () => {
  it("are read only from a definition that declares input_rules, the same table runtime.gd plays", () => {
    expect(LONG_TURN_TICKS).toBe(27_000);
    expect(RULES).toEqual({ change_ticks: 10, burst: 800, reserve: 30 });
    expect(inputRules(LONG)).toBe(RULES);
    expect(turnLimits(LONG)).toEqual(TURNS);
    expect(inputRules(tideV2Definition)).toBeUndefined();
    expect(() => turnLimits({ ...tideV2Definition, turn_limits: TURNS })).toThrow("invalid turn_limits");
    expect(() => inputRules({ ...LONG, input_rules: 2 })).toThrow("invalid input_rules");
    // The first entry, the allowance of 800 and one change every 10 ticks: three a second.
    expect(maxActionEntries(RULES, 27_000)).toBe(3_501);
    expect(maxActionEntries(RULES, 500)).toBe(500);
    // The table test_long_turn_input.gd also reads, so the game's copies match these.
    expect(cases.capped.input_rules).toEqual(INPUT_RULES);
    expect(cases.capped.long_turn_ticks).toBe(LONG_TURN_TICKS);
    expect(cases.capped.max_replay_bytes).toBe(MAX_REPLAY_BYTES);
    for (const [ticks, entries] of cases.capped.max_action_entries) expect(maxActionEntries(RULES, ticks)).toBe(entries);
  });

  it("fit a frantic 15 minute pair, every allowed change at its widest, in a room row", async () => {
    const long = journeyAdapter(LONG as never, initial as ChapterCheckpoint, HASH, 4);
    const chain = await franticChain();
    for (const record of [chain.a1, chain.b1, chain.a2, chain.b2]) expect(await long.recording(record)).toEqual(record);
    expect(await long.checkpoint(chain.cp1, initial as ChapterCheckpoint, chain.a1 as ChapterRecording, chain.b1 as ChapterRecording)).toEqual(chain.cp1);
    expect(await long.checkpoint(chain.cp2, chain.cp1 as ChapterCheckpoint, chain.a2 as ChapterRecording, chain.b2 as ChapterRecording)).toEqual(chain.cp2);
    const pair = { pair_id: "p3-1", branch: 3, stage_index: 1, a: chain.a2, b: chain.b2, checkpoint: chain.cp2 };
    const rows = longTurnRows(shape);
    // The real widest pair row, the bound the adapter checked at load, and the row bound itself.
    expect(bytes(pair)).toBeGreaterThan(MAX_ROW_BYTES * 0.8);
    expect(bytes(pair)).toBeLessThanOrEqual(rows.pair);
    expect(rows.pair + ROW_ENVELOPE_BYTES).toBeLessThanOrEqual(MAX_ROW_BYTES);
    expect(() => rowText(pair)).not.toThrow();
    expect(bytes(chain.cp2)).toBeLessThanOrEqual(rows.checkpoint);
    expect(Math.max(bytes(chain.a2), bytes(chain.b2))).toBeLessThanOrEqual(rows.recording);
    // The receiver's turn body passes the route's and the room's preflight.
    expect(() => boundedTurnValue({ base_revision: 9, idempotency_key: "k".repeat(64), branch: 3, recording: chain.b2, checkpoint: chain.cp2 }, long.limits)).not.toThrow();
  });

  it("refuse a turn past the cap and a chapter whose turns or branches outgrow the room", async () => {
    const long = journeyAdapter(LONG as never, initial as ChapterCheckpoint, HASH, 4);
    const over = await frantic(setA, TURNS.a_ticks, initial.checkpoint_hash, "", maxActionEntries(RULES, TURNS.a_ticks) + 1);
    await expect(long.recording(over)).rejects.toMatchObject({ code: "invalid_actions" });
    // Four branches of 15 minute pairs fit the replay archive and the room snapshot; a fifth does not.
    expect(() => checkLongTurnBounds(shape, 4)).not.toThrow();
    expect(() => checkLongTurnBounds(shape, 5)).toThrow("max_branches outgrow the room archive bounds");
    expect(() => checkLongTurnBounds(shape, undefined)).toThrow("turn_limits need max_branches");
    expect(4 * rows().branch).toBeLessThanOrEqual(ARCHIVE_BOUNDS.replay_archive_bytes);
    // Three stages of 15 minute turns outgrow a row; the tooling offers shorter turns instead.
    expect(() => checkLongTurnBounds({ ...shape, stages: 3 }, 1)).toThrow("turn_limits outgrow the room row bound");
    expect(() => journeyAdapter(LONG as never, initial as ChapterCheckpoint, HASH, 5)).toThrow("max_branches outgrow the room archive bounds");
    function rows() { return longTurnRows(shape); }
  });

  it("leave every published chapter's bounds exactly as they were", () => {
    const tide = scaledLimits({ a_ticks: 2700, b_ticks: 3000 });
    const expected: Record<string, unknown> = { "turn-of-the-tide@1": tide, "turn-of-the-tide@2": tide, "sleeping-lighthouse@2": LIGHTHOUSE_LIMITS };
    const branches: Record<string, number> = { "turn-of-the-tide@1": 7, "turn-of-the-tide@2": 7, "sleeping-lighthouse@2": LIGHTHOUSE_MAX_BRANCHES };
    for (const { adapter } of CHAPTERS) {
      const name = `${adapter.key.level_id}@${adapter.key.level_version}`;
      expect(adapter.limits, name).toEqual(expected[name]);
      expect(adapter.max_branches, name).toBe(branches[name]);
    }
  });
});

describe("a turn's real row size", () => {
  afterEach(async () => { await reset(); });
  it("is refused with turn_too_large past MAX_ROW_BYTES, counted in UTF-8 bytes", () => {
    const room = (text: string) => ({ text });
    const fill = MAX_ROW_BYTES - bytes(room(""));
    expect(rowText(room("a".repeat(fill)))).toHaveLength(MAX_ROW_BYTES);
    expect(() => rowText(room("a".repeat(fill + 1)))).toThrow(ApiError);
    // Three bytes a character: a third as many characters already reach the bound.
    expect(() => rowText(room("€".repeat(Math.floor(fill / 3) + 1)))).toThrow(expect.objectContaining({ status: 413, code: "turn_too_large" }));
    expect(() => rowText(room("€".repeat(Math.floor(fill / 3))))).not.toThrow();
  });

  it("refuses a turn whose room row would pass the bound, and writes nothing", async () => {
    const HOST = "A".repeat(22), GUEST = "B".repeat(22);
    const stub = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    const unwrap = <T>(result: Outcome<T>): T => { if (!result.ok) throw new Error(result.code); return result.value; };
    unwrap(await stub.initialize("c".repeat(22), HOST, "E".repeat(20), turnOfTheTide.key));
    const state: RoomSnapshotV2 = unwrap(await stub.join(GUEST, "E".repeat(20), [9]));
    // A room row already at the bound: the turn's own write would pass it.
    const before = await runInDurableObject(stub, async (_, ctx) => {
      const raw = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data, room = JSON.parse(raw);
      room.padding = ""; room.padding = "x".repeat(MAX_ROW_BYTES - bytes(room));
      ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(room));
      return JSON.stringify(room);
    });
    const turn = { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: tideA };
    expect(await stub.commit(HOST, turn)).toMatchObject({ ok: false, status: 413, code: "turn_too_large" });
    await runInDurableObject(stub, async (_, ctx) => {
      expect(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data).toBe(before);
      expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM turns").one().n).toBe(0);
      expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM operations").one().n).toBe(0);
    });
    // With room to spare the same turn is taken.
    await runInDurableObject(stub, async (_, ctx) => {
      const room = JSON.parse(before); room.padding = "x".repeat(room.padding.length - 4096);
      ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(room));
    });
    expect(await stub.commit(HOST, { ...turn, idempotency_key: crypto.randomUUID() })).toMatchObject({ ok: true });
  });
});
