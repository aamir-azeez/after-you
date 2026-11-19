import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { wishingWell, wishingWellV2 } from "../src/v2/protocol-cooperative";
import type { ChapterAdapter, ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import wellAheadA from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-go-on-ahead-a.json";
import wellAheadB from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-go-on-ahead-b.json";
import wellAheadC from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-go-on-ahead-c.json";
import wellAheadD from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-go-on-ahead-d.json";
import wellAheadE from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-go-on-ahead-e.json";
import wellAheadEnd from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-go-on-ahead-checkpoint.json";
import wellBackA from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-back-for-you-a.json";
import wellBackB from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-back-for-you-b.json";
import wellBackC from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-back-for-you-c.json";
import wellBackEnd from "../../game/tests/fixtures/cooperative/the-wishing-well-v2-back-for-you-checkpoint.json";

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

const WELL: Stage[] = [{ turns: [wellAheadA, wellAheadB, wellAheadC, wellAheadD, wellAheadE], end: wellAheadEnd }, { turns: [wellBackA, wellBackB, wellBackC], end: wellBackEnd }];

describe("cooperative open turns", () => {
  it("takes the Wishing Well@2 witness: every turn and each stage's closing checkpoint", async () => {
    expect(wishingWellV2.simulation_version).toBe(14);
    expect(wishingWellV2.open_turns?.caps).toEqual([10, 20]);
    expect(wishingWellV2.max_branches).toBe(7);
    await playsThrough(wishingWellV2, WELL);
  });

  it("keeps the published Wishing Well on two turns a stage", () => {
    expect(wishingWell.open_turns).toBeUndefined();
    expect(wishingWell.limits).toBeUndefined();
    expect(wishingWell.supported_simulation_versions).toEqual([9]);
  });

  it("refuses a JSON turn, and a closing checkpoint that does not end the stage", async () => {
    const [stage] = WELL, start = wishingWellV2.initial();
    const { packed: _packed, ...unpacked } = stage.turns[0]; void _packed;
    await expect((async () => wishingWellV2.recording({ ...unpacked, actions: [], replay_checks: [] }))()).rejects.toMatchObject({ code: "packed_recording_required" });
    const check = async (change: (value: Json) => void) => {
      const value = flat(structuredClone(stage.end));
      change(value);
      return close(wishingWellV2, await rehash(value), start, stage.turns);
    };
    // One pip away from the bell.
    await expect(check(value => { value.players.p0.x = 1000; })).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    // A turn left out, or the turns named out of order.
    await expect(close(wishingWellV2, flat(stage.end), start, [stage.turns[0], stage.turns[1], stage.turns[4]])).rejects.toMatchObject({ code: "checkpoint_source_mismatch" });
    await expect(check(value => { value.turn_hashes = [...value.turn_hashes].reverse(); })).rejects.toMatchObject({ code: "checkpoint_source_mismatch" });
  });
});
