import { describe, expect, it } from "vitest";
import { COMFORT_RULES, OPEN_TURNS_RULES, PIECES_RULES, openControls, openTurns, piecesRules, tideRules } from "../src/v2/chapter-types";
import { gateHolds, sunkTogether, type Marker } from "../src/v2/protocol-journey";

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

  it("never ends a stage with both pips on one sinking stone", () => {
    const stage = { sinking: ["s1", "s2"] };
    const on = (surface_id: string) => ({ x: 0, z: 0, height: 96, surface_id });
    expect(sunkTogether(stage, { p0: on("s1"), p1: on("s1") })).toBe(true);
    expect(sunkTogether(stage, { p0: on("s1"), p1: on("s2") })).toBe(false);
    expect(sunkTogether(stage, { p0: on("big"), p1: on("big") })).toBe(false);
    expect(sunkTogether({}, { p0: on("s1"), p1: on("s1") })).toBe(false);
  });
});
