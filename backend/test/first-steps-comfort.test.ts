import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { adapter } from "../src/v2/protocol-first-steps";
import source from "../../game/tests/fixtures/first_steps/a-little-lift-a.json";
import receiver from "../../game/tests/fixtures/first_steps/a-little-lift-b.json";
import native from "../../game/tests/fixtures/comfort8/first-steps.json";

// Deliberately structural input: native tests separately verify actual routes.
async function envelope(version: number, role: "a" | "b", duration: number) {
  const frozen = role === "a" ? source : receiver;
  const replay_checks = [];
  for (let tick = 30; tick < duration; tick += 30) replay_checks.push({ tick, state_hash: frozen.final_state_hash });
  replay_checks.push({ tick: duration, state_hash: frozen.final_state_hash });
  const { recording_hash: ignored, ...body } = {
    ...structuredClone(frozen), simulation_version: version, duration_ticks: duration,
    actions: Array.from({ length: duration }, (_, index) => ({ ticks: 1, x: index % 2 ? -100 : 100, z: 0, action: false })),
    replay_checks
  };
  void ignored;
  return { ...body, recording_hash: await digest(canonicalJson(body)) };
}

describe("First Steps receiver comfort boundaries", () => {
  it("accepts both actual native late handoffs and the complete nested proof", async () => {
    let previous = adapter.initial();
    for (const pair of native.pairs) {
      const a = await adapter.recording(pair.a), b = await adapter.recording(pair.b);
      expect(a.simulation_version).toBe(8);
      expect(b.simulation_version).toBe(8);
      expect(a.duration_ticks).toBeLessThanOrEqual(600);
      expect(b.duration_ticks).toBeGreaterThan(600);
      expect(adapter.accepted(a) && adapter.accepted(b)).toBe(true);
      expect(await adapter.checkpoint(pair.checkpoint, previous, a, b)).toEqual(pair.checkpoint);
      await expect(adapter.checkpoint(pair.checkpoint, previous, a, { ...b, simulation_version: 5 })).rejects.toMatchObject({ code: "unsupported_simulation_version" });
      previous = pair.checkpoint;
    }
    expect(previous.stage_index).toBe(2);
    expect(previous.next_stage_id).toBe("");
  });
  it.each([[8, "b", 900], [8, "a", 600], [5, "b", 600], [4, "b", 600]] as const)(
    "accepts rules%i %s at%d ticks, including a dense native-sized action list", async (version, role, duration) => {
      const record = await envelope(version, role, duration);
      expect(await adapter.recording(record)).toEqual(record);
    });
  it.each([[8, "b", 901], [8, "a", 601], [5, "b", 601], [4, "b", 601]] as const)(
    "rejects rules%i %s at%d ticks", async (version, role, duration) => {
      await expect(adapter.recording(await envelope(version, role, duration))).rejects.toMatchObject({ code: "invalid_integer" });
    });
  it("keeps body integrity and ordered replay checks mandatory in the longer turn", async () => {
    const record = await envelope(8, "b", 900);
    await expect(adapter.recording({ ...record, simulation_version: 5 })).rejects.toMatchObject({ code: "invalid_integer" });
    await expect(adapter.recording({ ...record, actions: record.actions.slice(1) })).rejects.toMatchObject({ code: "action_duration_mismatch" });
    await expect(adapter.recording({ ...record, replay_checks: [...record.replay_checks].reverse() })).rejects.toMatchObject({ code: "unordered_replay_checks" });
    await expect(adapter.recording({ ...record, recording_hash: "f".repeat(64) })).rejects.toMatchObject({ code: "recording_hash_mismatch" });
  });
});
