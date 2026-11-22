import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { highAndLowV2, wishingWell } from "../src/v2/protocol-cooperative";
import type { ChapterAdapter, ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import upperA from "../../game/tests/fixtures/cooperative/high-and-low-v2-upper-path-a.json";
import upperB from "../../game/tests/fixtures/cooperative/high-and-low-v2-upper-path-b.json";
import upperC from "../../game/tests/fixtures/cooperative/high-and-low-v2-upper-path-c.json";
import upperEnd from "../../game/tests/fixtures/cooperative/high-and-low-v2-upper-path-checkpoint.json";
import aroundA from "../../game/tests/fixtures/cooperative/high-and-low-v2-down-and-around-a.json";
import aroundB from "../../game/tests/fixtures/cooperative/high-and-low-v2-down-and-around-b.json";
import aroundC from "../../game/tests/fixtures/cooperative/high-and-low-v2-down-and-around-c.json";
import aroundEnd from "../../game/tests/fixtures/cooperative/high-and-low-v2-down-and-around-checkpoint.json";

/**
 * Cooperative chapters on open turns (src/v2/protocol-cooperative.ts openCheckpoint), played through the phone's witness
 * routes (game/tests/routes/<key>.json; scripts/chapter_fixtures.py writes these fixtures): every turn of every stage,
 * and each stage's flat closing checkpoint, as a room hands them over.
 */
type Json = Record<string, any>;
type Stage = { turns: Json[]; end: Json };
/** A checkpoint as the phone sends it: its own copy less the nested proof (open turns fingerprints, flat). */
function flat(checkpoint: Json): Json {
  const { proof: _proof, ...rest } = checkpoint; void _proof;
  return rest;
}
async function rehash(checkpoint: Json): Promise<ChapterCheckpoint> {
  const { checkpoint_hash: _hash, ...body } = checkpoint; void _hash;
  return { ...checkpoint, checkpoint_hash: await digest(canonicalJson(body)) } as ChapterCheckpoint;
}
function close(adapter: ChapterAdapter, value: Json, previous: Json, turns: Json[]): Promise<ChapterCheckpoint> {
  const all = turns as unknown as ChapterRecording[];
  return adapter.checkpoint(value, previous as ChapterCheckpoint, all[0], all[all.length - 1], all.slice(1, -1));
}
async function playsThrough(adapter: ChapterAdapter, stages: Stage[]): Promise<void> {
  let previous: Json = adapter.initial();
  for (const stage of stages) {
    for (const turn of stage.turns) expect(await adapter.recording(turn)).toBeTruthy();
    const end = flat(stage.end);
    expect(await close(adapter, end, previous, stage.turns)).toEqual(end);
    previous = end;
  }
}

const HIGH: Stage[] = [{ turns: [upperA, upperB, upperC], end: upperEnd }, { turns: [aroundA, aroundB, aroundC], end: aroundEnd }];

describe("cooperative open turns", () => {
  it("takes the High and Low@2 witness: every turn and each stage's closing checkpoint", async () => {
    expect(highAndLowV2.simulation_version).toBe(18);
    expect(highAndLowV2.open_turns?.caps).toEqual([10, 10]);
    expect(highAndLowV2.max_branches).toBe(7);
    await playsThrough(highAndLowV2, HIGH);
  });

  it("keeps the published Wishing Well on two turns a stage", () => {
    expect(wishingWell.open_turns).toBeUndefined();
    expect(wishingWell.limits).toBeUndefined();
    expect(wishingWell.supported_simulation_versions).toEqual([9]);
  });

  it("refuses a JSON turn, and a closing checkpoint that does not end the stage", async () => {
    const [stage] = HIGH, start = highAndLowV2.initial();
    const { packed: _packed, ...unpacked } = stage.turns[0]; void _packed;
    await expect((async () => highAndLowV2.recording({ ...unpacked, actions: [], replay_checks: [] }))()).rejects.toMatchObject({ code: "packed_recording_required" });
    const check = async (change: (value: Json) => void) => {
      const value = flat(structuredClone(stage.end));
      change(value);
      return close(highAndLowV2, await rehash(value), start, stage.turns);
    };
    // One pip away from the bell.
    await expect(check(value => { value.players.p0.x = 0; })).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    // A turn left out, or the turns named out of order.
    await expect(close(highAndLowV2, flat(stage.end), start, [stage.turns[0], stage.turns[2]])).rejects.toMatchObject({ code: "checkpoint_source_mismatch" });
    await expect(check(value => { value.turn_hashes = [...value.turn_hashes].reverse(); })).rejects.toMatchObject({ code: "checkpoint_source_mismatch" });
  });
});
