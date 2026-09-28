import { env } from "cloudflare:workers";
import { reset, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { recording, type LegacySimulationVersion, type Recording, type Role } from "../src/protocol";
import type { PortableSnapshot } from "../src/snapshot";

const host = "H".repeat(22), guest = "G".repeat(22), roomId = "R".repeat(22);
const invite = "A".repeat(20), commit = "f".repeat(40);
const room = () => env.ROOMS.get(env.ROOMS.newUniqueId());

// These are structural server fixtures, not native replay proofs. Native tests
// separately generate/replay the real comfort recordings and their state hashes.
function structuralRecording(version: LegacySimulationVersion, role: Role, duration: number): Recording {
  const stateHash = (role === "a" ? "a" : "b").repeat(64);
  const checkpoints: Recording["checkpoints"] = [];
  for (let tick = 30; tick < duration; tick += 30) checkpoints.push({ tick, state_hash: stateHash });
  checkpoints.push({ tick: duration, state_hash: stateHash });
  return {
    schema_version: 1, simulation_version: version, level_id: "first-light", level_version: 1,
    role, duration_ticks: duration, tick_rate: 30, catch_assistance: true,
    actions: [{ ticks: duration, x: 0, z: 0, action: false }], checkpoints,
    final_state_hash: stateHash, completed: role === "b",
    outcome: { threw_seed: true, caught_seed: role === "b", planted_seed: role === "b" },
    ...(role === "b" ? { source_recording_hash: "a".repeat(64) } : {})
  };
}

async function exported(stub: ReturnType<typeof room>): Promise<string> {
  const result = await stub.exportSnapshot(commit);
  if (!result.ok) throw new Error(result.code);
  return result.value;
}

afterEach(async () => { await reset(); });

describe("legacy comfort recording boundaries", () => {
  it.each([
    [8, "b", 900], [8, "a", 600], [6, "b", 600], [1, "b", 600]
  ] as const)("accepts rules %i role %s at its %i-tick boundary", (version, role, duration) => {
    const input = structuralRecording(version, role, duration);
    expect(recording(JSON.parse(JSON.stringify(input)))).toEqual(input);
  });

  it.each([
    [8, "b", 901], [8, "a", 601], [6, "b", 601], [1, "b", 601]
  ] as const)("rejects rules %i role %s at %i ticks", (version, role, duration) => {
    expect(() => recording(structuralRecording(version, role, duration))).toThrow("invalid_integer");
  });

  it("validates the whole 900-frame action trace and retains strict action/checkpoint bounds", () => {
    const dense = structuralRecording(8, "b", 900);
    dense.actions = Array.from({ length: 900 }, (_, tick) => ({ ticks: 1, x: tick % 2 ? 100 : -100, z: 0, action: false }));
    expect(recording(dense)).toEqual(dense);
    expect(() => recording({ ...dense, actions: [...dense.actions, dense.actions[0]] })).toThrow("invalid_actions");
    expect(() => recording({ ...dense, actions: [{ ticks: 901, x: 0, z: 0, action: false }] })).toThrow("invalid_integer");
    expect(() => recording({ ...dense, actions: dense.actions.slice(1) })).toThrow("action_duration_mismatch");
    expect(() => recording({ ...dense, checkpoints: [{ tick: 901, state_hash: dense.final_state_hash }] })).toThrow("invalid_integer");
  });
});

describe("legacy rules stay pinned across portable snapshots", () => {
  it.each([1, 6, 8] as const)("roundtrips rules %i with archived completed turns and exact mutation receipts", async version => {
    const source = room(), target = room();
    expect((await source.initialize(roomId, host, invite, version)).ok).toBe(true);
    expect((await source.join(guest, invite, version)).ok).toBe(true);
    const first = recording(structuralRecording(version, "a", 600));
    const second = recording(structuralRecording(version, "b", version === 8 ? 900 : 600));
    expect((await source.commit(host, 1, "comfort-first-key-01", "1".repeat(64), first)).ok).toBe(true);
    expect((await source.commit(guest, 2, "comfort-second-key-1", "2".repeat(64), second)).ok).toBe(true);
    expect((await source.react(host, 3, "comfort-react-key-01", "3".repeat(64), "love")).ok).toBe(true);
    expect((await source.fork(host, 4, "comfort-fork-key-001", "4".repeat(64))).ok).toBe(true);
    const original = await exported(source), archive = JSON.parse(original) as PortableSnapshot;
    const saved = archive.payload.tables.find(table => table.name === "archive")!;
    expect(saved.rows).toHaveLength(1);
    const completed = JSON.parse(String(saved.rows[0].data));
    expect(completed.simulation_version ?? 1).toBe(version);
    expect(completed.recordings).toEqual({ a: first, b: second });
    expect(completed.reactions).toEqual({ [host]: "love" });
    expect(await target.restoreSnapshot(original, roomId)).toEqual({ ok: true, value: { restored: true, checksum: archive.checksum.value } });
    await evictDurableObject(target);
    const restored = JSON.parse(await exported(target)) as PortableSnapshot;
    expect(restored.payload.tables).toEqual(archive.payload.tables);
    expect(restored.payload.summary).toEqual({ state: "active", revision: 5, attempt: 1 });
    expect(await target.collection(host)).toEqual(await source.collection(host));
    expect(await target.snapshot(guest)).toEqual(await source.snapshot(guest));
    // An accepted response lost before export still reconciles after eviction.
    expect(await target.commit(guest, 2, "comfort-second-key-1", "2".repeat(64), second)).toEqual(await source.snapshot(guest));
    expect(await target.commit(guest, 2, "comfort-second-key-1", "5".repeat(64), second)).toMatchObject({ ok: false, code: "idempotency_key_reused" });
    const wrongVersion = version === 8 ? 6 : 8;
    expect(await target.commit(host, 5, "comfort-wrong-key-01", "6".repeat(64), structuralRecording(wrongVersion, "a", 600))).toMatchObject({ ok: false, code: "unsupported_simulation_version" });
    expect((JSON.parse(await exported(target)) as PortableSnapshot).payload.tables).toEqual(archive.payload.tables);
  });
});
