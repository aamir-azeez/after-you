import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { MAX_CHECKPOINT_BYTES, MAX_V2_BODY_BYTES } from "../src/v2/protocol";
import { physicalRecording, scaledLimits, turnLimits } from "../src/v2/protocol-physical-recording";
import { conservatory, longWayHome, longWayHomeV2 } from "../src/v2/protocol-journey";
import { wishingWell } from "../src/v2/protocol-cooperative";
import definition from "../../game/tests/fixtures/cooperative/the-wishing-well-definition.json";
import longB from "../../game/tests/fixtures/cooperative/back-for-you-b-long.json";

async function withChecks(record: Record<string, unknown>, count: number): Promise<Record<string, unknown>> {
  const duration = record.duration_ticks as number;
  const checks = Array.from({ length: count }, (_, index) => ({ tick: index + 1 === count ? duration : index + 1, state_hash: index + 1 === count ? record.final_state_hash : "0".repeat(64) }));
  const body: Record<string, unknown> = { ...record, replay_checks: checks }; delete body.recording_hash;
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}

// A pinned definition may declare its own turn lengths (rules 9 and later).
// Without them every adapter keeps the published caps and bounds.
describe("declared turn limits", () => {
  it("are read only from a rules 9 definition that sets them, and must leave the receiver the longer turn", () => {
    expect(turnLimits({ simulation_version: 9 })).toBeUndefined();
    expect(turnLimits({ simulation_version: 8, turn_limits: { a_ticks: 2700, b_ticks: 3000 } })).toBeUndefined();
    expect(turnLimits({ simulation_version: 9, turn_limits: { a_ticks: 2700, b_ticks: 3000 } })).toEqual({ a_ticks: 2700, b_ticks: 3000 });
    for (const bad of [{ a_ticks: 0, b_ticks: 10 }, { a_ticks: 10, b_ticks: 10 }, { a_ticks: 1.5, b_ticks: 10 }, { a_ticks: 10, b_ticks: 9_001 }, { b_ticks: 10 }, null])
      expect(() => turnLimits({ simulation_version: 9, turn_limits: bad })).toThrow("invalid turn_limits");
  });

  it("grow the published comfort bounds by the longer turn", () => {
    expect(scaledLimits({ a_ticks: 900, b_ticks: 1200 })).toEqual({ recording_bytes: 65_536, recording_values: 24_000, checkpoint_bytes: MAX_CHECKPOINT_BYTES, checkpoint_values: 24_000,
      turn_body_bytes: MAX_V2_BODY_BYTES, turn_body_values: 32_000 });
    expect(scaledLimits({ a_ticks: 2700, b_ticks: 3000 })).toEqual({ recording_bytes: 196_608, recording_values: 72_000, checkpoint_bytes: 688_128, checkpoint_values: 72_000,
      turn_body_bytes: 983_040, turn_body_values: 96_000 });
  });

  it("leave the published adapters alone", () => {
    for (const adapter of [conservatory, longWayHome, longWayHomeV2, wishingWell]) expect(adapter.limits).toBeUndefined();
  });

  it("set the turn cap for each role, still lowered by maxTicks, and allow one replay check a second", async () => {
    const supported = wishingWell.supported_simulation_versions ?? [wishingWell.simulation_version];
    const ticks = longB.duration_ticks;
    const fits = { a_ticks: ticks - 1, b_ticks: ticks }, short = { a_ticks: ticks - 2, b_ticks: ticks - 1 };
    expect(await physicalRecording(definition, wishingWell.key, 6, supported, undefined, fits)(longB)).toEqual(longB);
    await expect(physicalRecording(definition, wishingWell.key, 6, supported, undefined, short)(longB)).rejects.toThrow();
    await expect(physicalRecording(definition, wishingWell.key, 6, supported, ticks - 1, fits)(longB)).rejects.toThrow();
    const most = Math.floor(ticks / 30) + 1;
    const dense = await withChecks(longB, most), over = await withChecks(longB, most + 1);
    expect(await physicalRecording(definition, wishingWell.key, 6, supported, undefined, fits)(dense)).toEqual(dense);
    await expect(physicalRecording(definition, wishingWell.key, 6, supported, undefined, fits)(over)).rejects.toMatchObject({ code: "invalid_replay_checks" });
  });
});
