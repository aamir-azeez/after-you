import { physicalRecording, physicalAccepted as accepted } from "./protocol-physical-recording";
import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object } from "../protocol";
import { boundedValue, exact, MAX_CHECKPOINT_BYTES } from "./protocol-relay";
import type { ChapterAdapter, ChapterCheckpoint, ChapterRecording } from "./chapter-types";
import highDefinition from "./high-and-low.json";
import highInitial from "./high-and-low-initial.json";
import rollingDefinition from "./rolling-home.json";
import rollingInitial from "./rolling-home-initial.json";
import houseDefinition from "./a-house-for-two.json";
import houseInitial from "./a-house-for-two-initial.json";

export const HIGH_AND_LOW_HASH = "6aa907e802c92445745a6452c6ec0850dd8e98724e689b58a8ec82915fb08956";
export const ROLLING_HOME_HASH = "d6aaa6006597dd5e4ce4dbc641d94c81c2ab17c55bd80b50c6a240e0e91cff87";
export const HOUSE_HASH = "b868745e7bc025bb8fe5a49b698b15dfb0d428ea9fe905ce46fa46dd27d79867";

type Surface = { id: string; rect_cm: number[]; height_cm?: number; owner_slot?: string; axis?: string; from_height_cm?: number; to_height_cm?: number };
type Marker = { id: string; position_cm: number[]; surface_id: string; radius_cm: number; owner_slot?: string; prop_id?: string };
type Definition = {
  id: string; version: number; premium: boolean; islands: Surface[]; bridges: Surface[]; stairs: Surface[];
  props: (Marker & { kind: string })[];
  stages: { id: string; version: number; first_player_slot: string; gates: { route_id: string }[]; levers: Marker[]; ball_pads: Marker[]; pressure_pads: Marker[];
    goal: Marker; goal_policy: { kind: string; prop_id?: string; socket_id?: string };
    source_policy: { kind: string; pad_id?: string; ball_pad_id?: string; prop_id?: string }; handoff?: Marker }[];
};
const CHECKPOINT_KEYS = ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"];
function need(value: unknown, code: string): asserts value { if (!value) throw new ApiError(422, code); }
function inside(p: Record<string, unknown>, marker: Marker, radius = marker.radius_cm): boolean {
  return p.surface_id === marker.surface_id && (Number(p.x) - marker.position_cm[0]) ** 2 + (Number(p.z) - marker.position_cm[1]) ** 2 <= radius ** 2;
}


/** One bounded structural adapter for the shared native physical simulation.
 * Proof bytes are retained for native deterministic replay; the server does not simulate physics. */
function adapter(definition: Definition, initial: ChapterCheckpoint, definitionHash: string): ChapterAdapter {
  const key = Object.freeze({ level_id: definition.id, level_version: definition.version, definition_hash: definitionHash });
  function catalog(value: Record<string, unknown>): void { need(value.level_id === key.level_id && value.level_version === key.level_version && value.definition_hash === key.definition_hash, "unsupported_chapter"); }
  const recording = physicalRecording(definition, key, 6);
  async function checkpoint(value: unknown, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording): Promise<ChapterCheckpoint> {
    boundedValue(value, MAX_CHECKPOINT_BYTES);
    const c = object(value); exact(c, CHECKPOINT_KEYS); catalog(c);
    const index = previous.stage_index + 1, stage = definition.stages[index - 1];
    need(c.schema_version === 6 && c.stage_index === index && stage && index <= definition.stages.length && c.completed_stage_id === stage.id && c.next_stage_id === (definition.stages[index]?.id ?? ""), "checkpoint_stage_mismatch");
    need(a.simulation_version === 6 && b.simulation_version === 6 && a.role === "a" && b.role === "b" && accepted(a) && accepted(b), "checkpoint_recording_mismatch");
    need(c.previous_checkpoint_hash === previous.checkpoint_hash && c.a_recording_hash === a.recording_hash && c.b_recording_hash === b.recording_hash &&
      a.checkpoint_hash === previous.checkpoint_hash && b.checkpoint_hash === previous.checkpoint_hash && b.source_recording_hash === a.recording_hash &&
      a.stage_id === stage.id && b.stage_id === stage.id, "checkpoint_source_mismatch");
    const proof = object(c.proof); exact(proof, ["checkpoint", "a", "b"]);
    need(canonicalJson(proof.checkpoint) === canonicalJson(previous) && canonicalJson(proof.a) === canonicalJson(a) && canonicalJson(proof.b) === canonicalJson(b), "checkpoint_proof_mismatch");
    const mechanisms = object(c.mechanisms); exact(mechanisms, ["latched_bridges", "props", "levers"]);
    const completedStages = definition.stages.slice(0, index), routes = [...new Set(completedStages.flatMap(stage => stage.gates.map(gate => gate.route_id)))].sort();
    need(canonicalJson(mechanisms.latched_bridges) === canonicalJson(routes), "checkpoint_mechanism_mismatch");
    const levers = object(mechanisms.levers), leverIds = [...new Set(completedStages.flatMap(stage => stage.levers.map(lever => lever.id)))];
    exact(levers, leverIds); need(Object.values(levers).every(value => value === true), "checkpoint_mechanism_mismatch");
    const players = object(c.players); exact(players, ["p0", "p1"]);
    function surfacePosition(value: unknown, slot?: string): Record<string, unknown> {
      const p = object(value), x = integer(p.x, -10_000, 10_000), z = integer(p.z, -10_000, 10_000), height = integer(p.height, 0, 10_000);
      const surface = [...definition.islands, ...definition.bridges, ...definition.stairs].find(surface => surface.id === p.surface_id);
      need(surface && x >= surface.rect_cm[0] && x <= surface.rect_cm[2] && z >= surface.rect_cm[1] && z <= surface.rect_cm[3], "checkpoint_surface_mismatch");
      need(!surface.owner_slot || surface.owner_slot === slot, "checkpoint_surface_mismatch");
      if (definition.bridges.includes(surface) || definition.stairs.includes(surface)) need(routes.includes(surface.id), "checkpoint_surface_mismatch");
      const axis = surface.axis === "z" ? 1 : 0, coordinate = axis === 0 ? x : z;
      const expectedHeight = surface.from_height_cm === undefined ? surface.height_cm :
        surface.from_height_cm + Math.round((surface.to_height_cm! - surface.from_height_cm) * (coordinate - surface.rect_cm[axis]) / (surface.rect_cm[axis + 2] - surface.rect_cm[axis]));
      need(height === expectedHeight, "checkpoint_surface_mismatch"); return p;
    }
    for (const [slot, value] of Object.entries(players)) { exact(object(value), ["x", "z", "height", "surface_id"]); surfacePosition(value, slot); }
    const first = object(players[stage.first_player_slot]), second = object(players[stage.first_player_slot === "p0" ? "p1" : "p0"]);
    // A pushed ball reaches its cradle before the player behind it does.
    if (stage.goal_policy.kind !== "ball_home") need(inside(second, stage.goal), "checkpoint_goal_mismatch");
    if (stage.source_policy.kind === "hold_switch") {
      const pad = stage.pressure_pads.find(pad => pad.id === stage.source_policy.pad_id)!; need(inside(first, pad), "checkpoint_source_position_mismatch");
    }
    const props = object(mechanisms.props); exact(props, definition.props.map(prop => prop.id));
    for (const definitionProp of definition.props) {
      const prop = object(props[definitionProp.id]); exact(prop, ["status", "holder_slot", "socket_id", "x", "z", "height", "surface_id"]); surfacePosition(prop);
      const fitted = stage.goal_policy.kind === "ball_home";
      // A chapter may repurpose one ball on two plates. The accepted source
      // plate is explicit; published one-plate chapters retain the same guard.
      const destination = fitted ? stage.goal : stage.ball_pads.find(pad => pad.prop_id === definitionProp.id &&
        (stage.source_policy.ball_pad_id === undefined || pad.id === stage.source_policy.ball_pad_id));
      // Only this pinned House finale leaves the claimed weight behind to ring
      // a bell. Existing free-on-pad / fitted-in-cradle chapters stay exact.
      const claimed = definition.id === "a-house-for-two" && definition.version === 1 && stage.id === "the-room-below";
      const holder = claimed ? (stage.first_player_slot === "p0" ? "p1" : "p0") : "";
      need(destination && prop.status === (claimed ? "claimed" : fitted ? "fitted" : "free") && prop.holder_slot === holder && prop.socket_id === (fitted ? destination.id : "") && inside(prop, destination, destination.radius_cm - definitionProp.radius_cm), "checkpoint_prop_mismatch");
    }
    const { checkpoint_hash, proof: ignoredProof, ...body } = c; void ignoredProof;
    need(typeof checkpoint_hash === "string" && HASH_PATTERN.test(checkpoint_hash) && await digest(canonicalJson(body)) === checkpoint_hash, "checkpoint_hash_mismatch");
    return c as ChapterCheckpoint;
  }
  return { key, recording_version: 6, simulation_version: 6, premium: definition.premium, require_supported_simulation_on_join: true,
    stages: definition.stages, initial: () => structuredClone(initial), recording, checkpoint, accepted };
}

export const highAndLow = adapter(highDefinition, highInitial, HIGH_AND_LOW_HASH);
export const rollingHome = adapter(rollingDefinition, rollingInitial, ROLLING_HOME_HASH);
export const houseForTwo = adapter(houseDefinition, houseInitial, HOUSE_HASH);
