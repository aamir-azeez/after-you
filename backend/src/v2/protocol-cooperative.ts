import { checkRoutesAndLevers, openPhysicalRecording, physicalRecording, physicalAccepted as accepted } from "./protocol-physical-recording";
import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object } from "../protocol";
import { boundedValue, exact, MAX_CHECKPOINT_BYTES } from "./protocol-relay";
import { comfortRules, openControls, openTurns, sharedBall, type ChapterAdapter, type ChapterCheckpoint, type ChapterRecording } from "./chapter-types";
import { openAccepted, openBallProblem, openCheckpointShape, openStageEnds, openTurnsProblem } from "./open-turns";
import highDefinition from "./high-and-low.json";
import highInitial from "./high-and-low-initial.json";
import rollingDefinition from "./rolling-home.json";
import rollingInitial from "./rolling-home-initial.json";
import houseDefinition from "./a-house-for-two.json";
import houseInitial from "./a-house-for-two-initial.json";
import wellDefinition from "./the-wishing-well.json";
import wellInitial from "./the-wishing-well-initial.json";
import highV2Definition from "./high-and-low-v2.json";
import highV2Initial from "./high-and-low-v2-initial.json";
import wellV2Definition from "./the-wishing-well-v2.json";
import wellV2Initial from "./the-wishing-well-v2-initial.json";
import rollingV2Definition from "./rolling-home-v2.json";
import rollingV2Initial from "./rolling-home-v2-initial.json";
import houseV2Definition from "./a-house-for-two-v2.json";
import houseV2Initial from "./a-house-for-two-v2-initial.json";

export const HIGH_AND_LOW_HASH = "3b6576badcdd214630373a0f51040706e014845d9b8bc17483bd887f04a9ff40";
export const ROLLING_HOME_HASH = "3362e8afd9fb3504868ab4b8b436050f62fe601e5c7ff8fea995424064f2dbff";
export const HOUSE_HASH = "f14fb0abf330fa46afdb61078a8e8e99cee4cc2ade845304508cc90b05d27995";
export const WISHING_WELL_HASH = "14cfffbdd9b23cee06056548f29bbae7f1e95c348315ff3ff0098b7190ee5f3e";
export const HIGH_AND_LOW_V2_HASH = "79593b0e7e0b2a8fb055643dafb74734e332d26c8814e33415e233d186e80a58";
export const WISHING_WELL_V2_HASH = "f99b1dbf05ec73274773822eee85e2a7eb7f56b674a18201221f6396ff319dda";
export const ROLLING_HOME_V2_HASH = "6d8c6e7f2cdf75cabc49b48d9e72451f7f7b12c1c3cb13f6d00e489ff34f51b8";
export const HOUSE_V2_HASH = "f3df2ecdb01a9b02ce3a3dfd4f3ba649d061ff7cfbf1f184ee312d4ea4202270";

type Surface = { id: string; rect_cm: number[]; height_cm?: number; owner_slot?: string; axis?: string; from_height_cm?: number; to_height_cm?: number };
type Marker = { id: string; position_cm: number[]; surface_id: string; radius_cm: number; owner_slot?: string; prop_id?: string };
type Definition = {
  id: string; version: number; simulation_version: number; premium: boolean; turn_limits?: unknown; islands: Surface[]; bridges: Surface[]; stairs: Surface[];
  props: (Marker & { kind: string })[];
  stages: { id: string; version: number; first_player_slot: string; turn_cap?: number; gates: { route_id: string }[]; levers: Marker[]; ball_pads: Marker[]; pressure_pads: Marker[];
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
export function adapter(definition: Definition, initial: ChapterCheckpoint, definitionHash: string): ChapterAdapter {
  const key = Object.freeze({ level_id: definition.id, level_version: definition.version, definition_hash: definitionHash });
  function catalog(value: Record<string, unknown>): void { need(value.level_id === key.level_id && value.level_version === key.level_version && value.definition_hash === key.definition_hash, "unsupported_chapter"); }
  // A definition declaring rules 9+ plays only those rules; published chapters keep 6/8.
  const pinned = definition.simulation_version >= 9 ? definition.simulation_version : 0;
  const supported: readonly number[] = pinned ? [pinned] : [6, 8];
  // Open turns (14, open-turns.ts): a stage takes turns until both players stand at its goal; bounds and parser as every family's.
  const opened = openTurns(definition.simulation_version) ? openPhysicalRecording(definition, key, 6, supported) : undefined;
  const recording = opened ? opened.recording : physicalRecording(definition, key, 6, supported);
  async function checkpoint(value: unknown, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording, passes: readonly ChapterRecording[] = []): Promise<ChapterCheckpoint> {
    if (opened) return openCheckpoint(value, previous, [a, ...passes, b]);
    boundedValue(value, MAX_CHECKPOINT_BYTES);
    const c = object(value); exact(c, CHECKPOINT_KEYS); catalog(c);
    const index = previous.stage_index + 1, stage = definition.stages[index - 1];
    need(c.schema_version === 6 && c.stage_index === index && stage && index <= definition.stages.length && c.completed_stage_id === stage.id && c.next_stage_id === (definition.stages[index]?.id ?? ""), "checkpoint_stage_mismatch");
    need(supported.includes(a.simulation_version) && b.simulation_version === a.simulation_version && a.role === "a" && b.role === "b" && accepted(a) && accepted(b), "checkpoint_recording_mismatch");
    if (previous.stage_index > 0) need(object(object(object(previous).proof).a).simulation_version === a.simulation_version, "checkpoint_recording_mismatch");
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
    const surfacePosition = (value: unknown, slot?: string) => onSurface(value, routes, slot);
    for (const [slot, value] of Object.entries(players)) { exact(object(value), ["x", "z", "height", "surface_id"]); surfacePosition(value, slot); }
    const first = object(players[stage.first_player_slot]), second = object(players[stage.first_player_slot === "p0" ? "p1" : "p0"]);
    // A pushed ball reaches its cradle before the player behind it does.
    if (stage.goal_policy.kind !== "ball_home") need(inside(second, stage.goal), "checkpoint_goal_mismatch");
    if (stage.source_policy.kind === "hold_switch") {
      // Open controls (12): the pad holds for either player.
      const pad = stage.pressure_pads.find(pad => pad.id === stage.source_policy.pad_id)!;
      need(inside(first, pad) || (openControls(a.simulation_version) && inside(second, pad)), "checkpoint_source_position_mismatch");
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
      const radius = destination ? (comfortRules(a.simulation_version) ? destination.radius_cm : destination.radius_cm - definitionProp.radius_cm) : 0;
      need(destination && prop.status === (claimed ? "claimed" : fitted ? "fitted" : "free") && prop.holder_slot === holder && prop.socket_id === (fitted ? destination.id : "") && inside(prop, destination, radius), "checkpoint_prop_mismatch");
      if (comfortRules(a.simulation_version) && fitted) need(prop.x === destination.position_cm[0] && prop.z === destination.position_cm[1], "checkpoint_prop_mismatch");
    }
    return hashed(c);
  }
  /** A player or prop where it stands: inside a floor of the definition, at that floor's height, on a crossing only while it is latched. */
  function onSurface(value: unknown, routes: readonly unknown[], slot?: string): Record<string, unknown> {
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
  async function hashed(c: Record<string, unknown>): Promise<ChapterCheckpoint> {
    const { checkpoint_hash, proof: ignoredProof, ...body } = c; void ignoredProof;
    need(typeof checkpoint_hash === "string" && HASH_PATTERN.test(checkpoint_hash) && await digest(canonicalJson(body)) === checkpoint_hash, "checkpoint_hash_mismatch");
    return c as ChapterCheckpoint;
  }
  /** Open turns (open-turns.ts): the stage's turns by hash and a flat checkpoint, as the journey's. Both players end at the bell, and the
   * first turn's own part is not asked again. A route latches only where it was open at the end, so the routes are the earlier ones plus
   * any of this stage's gates; levers keep their values but this stage's. The turns are stored rows, so only header fields are read.
   * The shared ball (17, openBallProblem): a ball home stage ends with its ball in the cradle and both players on the cradle's floor. */
  async function openCheckpoint(value: unknown, previous: ChapterCheckpoint, all: readonly ChapterRecording[]): Promise<ChapterCheckpoint> {
    const { open, limits } = opened!;
    boundedValue(value, limits.checkpoint_bytes, limits.checkpoint_values);
    const shape = openCheckpointShape(open);
    const c = object(value); exact(c, shape.keys); catalog(c);
    const index = previous.stage_index + 1, stage = definition.stages[index - 1];
    need(c.schema_version === shape.schema && c.stage_index === index && stage && c.completed_stage_id === stage.id && c.next_stage_id === (definition.stages[index]?.id ?? ""), "checkpoint_stage_mismatch");
    need(all.every(turn => turn.simulation_version === pinned) && all[0].role === "a" && all.slice(1).every(turn => turn.role === "b") &&
      all.every((turn, i) => openAccepted(turn) && (i === 0 || turn.completed === (i === all.length - 1))), "checkpoint_recording_mismatch");
    need(c.previous_checkpoint_hash === previous.checkpoint_hash && all.every((turn, i) => turn.checkpoint_hash === previous.checkpoint_hash && turn.stage_id === stage.id &&
      (i === 0 || turn.source_recording_hash === all[i - 1].recording_hash)), "checkpoint_source_mismatch");
    const problem = openTurnsProblem(open, index - 1, stage, previous, all, c);
    need(!problem, problem);
    const mechanisms = object(c.mechanisms), prior = object(object(previous).mechanisms); exact(mechanisms, ["latched_bridges", "props", "levers"]);
    const { routes } = checkRoutesAndLevers(mechanisms, prior, definition.stages, index);
    const players = object(c.players); exact(players, ["p0", "p1"]);
    for (const [slot, player] of Object.entries(players)) { exact(object(player), ["x", "z", "height", "surface_id"]); onSurface(player, routes, slot); }
    const props = object(mechanisms.props); exact(props, definition.props.map(prop => prop.id));
    const ball = sharedBall(pinned), home = ball && stage.goal_policy.kind === "ball_home";
    need((stage.goal_policy.kind === "ring" || home) && openStageEnds(slot => home ? object(players[slot]).surface_id === stage.goal.surface_id : inside(object(players[slot]), stage.goal), true), "checkpoint_goal_mismatch");
    need(ball || definition.props.length === 0, "checkpoint_prop_mismatch");
    if (ball) {
      const problem = openBallProblem(props, object(prior.props), definition.props, stage, value => {
        exact(object(value), ["status", "holder_slot", "socket_id", "x", "z", "height", "surface_id"]); return onSurface(value, routes);
      });
      need(!problem, problem);
    }
    return hashed(c);
  }
  return { key, recording_version: 6, simulation_version: pinned || 6, supported_simulation_versions: supported, premium: definition.premium, require_supported_simulation_on_join: true,
    stages: definition.stages, initial: () => structuredClone(initial), recording, checkpoint, accepted: opened ? openAccepted : accepted,
    ...(opened ? { limits: opened.limits, max_branches: opened.open.branches, open_turns: opened.open } : {}) };
}

export const highAndLow = adapter(highDefinition, highInitial, HIGH_AND_LOW_HASH);
export const rollingHome = adapter(rollingDefinition, rollingInitial, ROLLING_HOME_HASH);
export const houseForTwo = adapter(houseDefinition, houseInitial, HOUSE_HASH);
/** Free; pinned to rules 9 by its definition, so 0.5.x guests are refused on join. */
export const wishingWell = adapter(wellDefinition, wellInitial, WISHING_WELL_HASH);
/** Open turns (14): High and Low@1 with a lever atop the stair and one in the garden, so both players end at each bell. Unreleased. */
export const highAndLowV2 = adapter(highV2Definition, highV2Initial, HIGH_AND_LOW_V2_HASH);
/** Open turns (14): the Wishing Well with both players at each bell, no owned crossing, and held steps at the garden gate and the rope ladder. Unreleased. */
export const wishingWellV2 = adapter(wellV2Definition, wellV2Initial, WISHING_WELL_V2_HASH);
/** Open turns with the shared ball (17): both players push the ball, a player holds each bridge for the other, and the last stage
 * ends with the ball in its cradle and both players home. Unreleased. */
export const rollingHomeV2 = adapter(rollingV2Definition, rollingV2Initial, ROLLING_HOME_V2_HASH);
/** Open turns with the shared ball (17): both players at each bell, a held step at the loft stairs and at the lower hall's passage. Unreleased. */
export const houseForTwoV2 = adapter(houseV2Definition, houseV2Initial, HOUSE_V2_HASH);
