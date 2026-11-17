import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { COMFORT_RULES, OPEN_TURNS_RULES, PIECES_RULES, openControls, openTurns, piecesRules, tideRules, type ChapterCheckpoint, type ChapterRecording } from "../src/v2/chapter-types";
import { gateHolds, journeyAdapter, sunkTogether, type Marker } from "../src/v2/protocol-journey";
import rideDefinition from "../../game/tests/fixtures/memory_rides/definition.json";
import rideInitial from "../../game/tests/fixtures/memory_rides/initial.json";
import rideA from "../../game/tests/fixtures/memory_rides/a.json";
import rideB from "../../game/tests/fixtures/memory_rides/b.json";
import rideEnd from "../../game/tests/fixtures/memory_rides/checkpoint.json";

const pan: Marker = { id: "pan", position_cm: [0, 0], surface_id: "landing", height_cm: 0, radius_cm: 28 };
const away = { x: 500, z: 500, height: 0, surface_id: "landing" };
function state(levers: Record<string, boolean>, p0 = away, p1 = away) {
  return { controls: { marsh: "LOW" }, levers, light: {}, players: { p0, p1 }, stage: { pressure_pads: [pan] }, open: true };
}

describe("new pieces (rules 16)", () => {
  it("numbers the pieces as tide, open controls and open turns too", () => {
    expect(PIECES_RULES).toEqual([16]);
    expect([15, 16].map(piecesRules)).toEqual([false, true]);
    expect([openControls(16), openTurns(16), tideRules(16), COMFORT_RULES.includes(16), OPEN_TURNS_RULES.includes(16)]).toEqual([true, true, true, true, true]);
  });

  it("reads not in a gate as the client does", () => {
    const flooded = { all: [{ control_id: "marsh", value: "LOW" }, { not: { lever_id: "lantern" } }] };
    expect(gateHolds(flooded, state({}))).toBe(true);
    expect(gateHolds(flooded, state({ lantern: true }))).toBe(false);
    // The weight lift: up while the pan is held, unless the top pan is too.
    const up = { all: [{ pad_id: "pan" }, { not: { pad_id: "top" } }] };
    expect(gateHolds(up, state({}))).toBe(false);
    expect(gateHolds(up, state({}, { x: 0, z: 0, height: 0, surface_id: "landing" }))).toBe(true);
    expect(gateHolds({ not: {} }, state({}))).toBe(false);
  });

  // The ride witness (game/tests/ride_witness.gd; game/tests/test_pieces.gd writes these files): the winch
  // carries the memory up the lift, and its walk into the stilts' edge then takes it on to the lamp.
  it("accepts turns where a lift carries the memory, and the stage they close", async () => {
    const adapter = journeyAdapter(rideDefinition as any, rideInitial as unknown as ChapterCheckpoint, await digest(canonicalJson(rideDefinition)));
    const [a, b] = [rideA, rideB] as unknown as ChapterRecording[];
    expect(adapter.simulation_version).toBe(16);
    for (const turn of [a, b]) expect(await adapter.recording(turn)).toBeTruthy();
    expect(await adapter.checkpoint(rideEnd, adapter.initial(), a, b, [])).toEqual(rideEnd);
    // Left below where its own world kept it, the memory stands on the lift's shut low stop.
    const { checkpoint_hash: _hash, proof: _proof, ...body } = structuredClone(rideEnd) as Record<string, any>; void _hash; void _proof;
    body.players.p0 = { x: 450, z: 200, height: 0, surface_id: "lift-low" };
    const below = { ...body, proof: rideEnd.proof, checkpoint_hash: await digest(canonicalJson(body)) } as unknown as ChapterCheckpoint;
    await expect(adapter.checkpoint(below, adapter.initial(), a, b, [])).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
  });

  it("never ends a stage with both pips on one sinking stone", () => {
    const stage = { sinking: ["s1", "s2"] };
    const on = (surface_id: string) => ({ x: 0, z: 0, height: 96, surface_id });
    expect(sunkTogether(stage, { p0: on("s1"), p1: on("s1") })).toBe(true);
    expect(sunkTogether(stage, { p0: on("s1"), p1: on("s2") })).toBe(false);
    expect(sunkTogether(stage, { p0: on("big"), p1: on("big") })).toBe(false);
    expect(sunkTogether({}, { p0: on("s1"), p1: on("s1") })).toBe(false);
  });
});
