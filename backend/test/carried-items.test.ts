import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { journeyAdapter, turnOfTheTideV3 } from "../src/v2/protocol-journey";
import { checkItems, itemHolds } from "../src/v2/protocol-items";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import definition from "../../game/tests/fixtures/carried_items/definition.json";
import initial from "../../game/tests/fixtures/carried_items/initial.json";
import a from "../../game/tests/fixtures/carried_items/a.json";
import b from "../../game/tests/fixtures/carried_items/b.json";
import c from "../../game/tests/fixtures/carried_items/c.json";
import closing from "../../game/tests/fixtures/carried_items/checkpoint.json";
import setEnd from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-checkpoint.json";

/**
 * Carried items (rules 16, src/v2/protocol-items.ts) on the phone's witness level
 * (game/tests/carried_items_level.gd; game/tests/test_carried_items.gd writes these files):
 * stage 1 closes over three turns with the pipsport handed up the ladder and carried at the goal.
 */
type Json = Record<string, any>;
const clone = <T>(value: T): T => structuredClone(value);
async function rehash(checkpoint: Json): Promise<ChapterCheckpoint> {
  const { checkpoint_hash: _hash, proof: _proof, ...body } = checkpoint; void _hash; void _proof;
  return { ...checkpoint, checkpoint_hash: await digest(canonicalJson(body)) } as ChapterCheckpoint;
}
async function witness() {
  return journeyAdapter(definition as any, initial as unknown as ChapterCheckpoint, await digest(canonicalJson(definition)));
}
const turns = [a, b, c] as unknown as ChapterRecording[];

describe("carried items", () => {
  it("accepts the witness: every turn, and the closing checkpoint with the pipsport carried", async () => {
    const adapter = await witness();
    expect(adapter.simulation_version).toBe(16);
    expect(adapter.initial()).toEqual(initial);
    for (const turn of turns) expect(await adapter.recording(turn)).toBeTruthy();
    expect(await adapter.checkpoint(closing, adapter.initial(), turns[0], turns[2], [turns[1]])).toEqual(closing);
  });

  it("refuses a checkpoint whose items do not fit the definition or the goal", async () => {
    const adapter = await witness();
    const check = async (change: (value: Json) => void) => {
      const value: Json = clone(closing);
      change(value);
      return adapter.checkpoint(await rehash(value), adapter.initial(), turns[0], turns[2], [turns[1]]);
    };
    await expect(check(value => { delete value.mechanisms.items; })).rejects.toMatchObject({ code: "unexpected_fields" });
    // Left in the post box, the pipsport is not carried at the goal.
    await expect(check(value => { value.mechanisms.items.pipsport = { holder: "", spot: "post", x: -350, z: 80, height: 0, surface_id: "dock" }; })).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    // A raft never rides a pip; an item never rests off its island or away from the spot it names.
    await expect(check(value => { value.mechanisms.items.raft = { holder: "p0", spot: "", x: 0, z: 0, height: 0, surface_id: "" }; })).rejects.toMatchObject({ code: "checkpoint_item_mismatch" });
    await expect(check(value => { value.mechanisms.items.pipsport = { holder: "", spot: "", x: -50, z: 0, height: 0, surface_id: "dock" }; })).rejects.toMatchObject({ code: "checkpoint_item_mismatch" });
    await expect(check(value => { value.mechanisms.items.raft = { holder: "", spot: "berth", x: 0, z: 0, height: 0, surface_id: "" }; })).rejects.toMatchObject({ code: "checkpoint_item_mismatch" });
    // One pip holds one item.
    await expect(check(value => { value.mechanisms.items.pipsport.holder = "p1"; value.mechanisms.items.raft = { holder: "p1", spot: "", x: 0, z: 0, height: 0, surface_id: "" }; })).rejects.toMatchObject({ code: "checkpoint_item_mismatch" });
  });

  it("keeps published chapters at four mechanisms and items on rules 16 only", async () => {
    const value: Json = clone(setEnd);
    value.mechanisms.items = {};
    const tideStart = turnOfTheTideV3.initial();
    const proof = (setEnd as Json).proof;
    await expect(turnOfTheTideV3.checkpoint(await rehash(value), tideStart, proof.turns[0], proof.turns.at(-1), proof.turns.slice(1, -1))).rejects.toMatchObject({ code: "unexpected_fields" });
    const older = { ...clone(definition), simulation_version: 15 };
    expect(() => journeyAdapter(older as any, initial as unknown as ChapterCheckpoint, "0".repeat(64))).toThrow("rules 16");
  });

  it("reads the item terms as the phone does", () => {
    const items = checkItems(clone((closing as Json).mechanisms.items), definition as any);
    expect(itemHolds({ item_id: "pipsport", carried: true }, items)).toBe(true);
    expect(itemHolds({ item_id: "pipsport", spot_id: "post" }, items)).toBe(false);
    expect(itemHolds({ item_id: "raft", spot_id: "mooring" }, items)).toBe(true);
    expect(itemHolds({ item_id: "raft", carried: true }, items)).toBe(false);
    expect(itemHolds({ item_id: "lost", carried: true }, items)).toBe(false);
  });
});
