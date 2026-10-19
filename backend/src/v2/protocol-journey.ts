import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object } from "../protocol";
import { boundedValue, exact, MAX_CHECKPOINT_BYTES } from "./protocol-relay";
import { checkTurnBounds, physicalRecording, physicalAccepted as accepted, scaledLimits, turnLimits, type TurnLimits } from "./protocol-physical-recording";
import type { ChapterAdapter, ChapterCheckpoint, ChapterRecording } from "./chapter-types";
import conservatoryDefinition from "./conservatory.json";
import conservatoryInitial from "./conservatory-initial.json";
import homeDefinition from "./long-way-home.json";
import homeInitial from "./long-way-home-initial.json";
import homeV2Definition from "./long-way-home-v2.json";
import homeV2Initial from "./long-way-home-v2-initial.json";
import tideDefinition from "./turn-of-the-tide.json";
import tideInitial from "./turn-of-the-tide-initial.json";
import tideV2Definition from "./turn-of-the-tide-v2.json";
import tideV2Initial from "./turn-of-the-tide-v2-initial.json";

export const CONSERVATORY_HASH = "fd9fce12c4facd5fd659eedd5a510ea6b0ad796925458ccb73b4b37a893530d5";
export const LONG_WAY_HOME_HASH = "bce3ddd36386ebb32f011b8d6afe95316992809030ea828b473bbbc3e1c6bb7f";
export const LONG_WAY_HOME_V2_HASH = "4541bd920062e244f202fbe6ee95363a1f53ae5afc490ad600112af9f01a8c77";
export const TURN_OF_THE_TIDE_HASH = "3a6d111455aa69e60c440cc6f04a0656292ed9c40b31c66a7f999c85cd2a911a";
export const TURN_OF_THE_TIDE_V2_HASH = "e15ff1e40da4084ddf291165ea5dea86335c92b388bb3a2fa841c959d1f056a7";
type Surface = { id: string; rect_cm: number[]; height_cm?: number; owner_slot?: string; axis?: string; from_height_cm?: number; to_height_cm?: number };
type Marker = { id: string; position_cm: number[]; surface_id: string; height_cm: number; radius_cm: number; owner_slot: string };
type Predicate = { all?: Predicate[]; any?: Predicate[]; control_id?: string; value?: string; lever_id?: string; pad_id?: string; signal_id?: string };
type Control = Marker & { values: string[]; initial: string };
type Stage = { id: string; version: number; first_player_slot: string; controls: Control[]; levers: Marker[]; pressure_pads: Marker[];
  gates: { route_id: string; when?: Predicate }[]; entry_latch_routes: string[]; goal: Marker; goal_policy: { kind?: string; when?: Predicate };
  source_policy: { kind: string; when?: Predicate; endpoint?: Marker; branches?: { pad_id: string }[] } };
type Definition = { id: string; version: number; simulation_version: number; premium: boolean; islands: Surface[]; bridges: Surface[]; stairs: Surface[]; stages: Stage[]; turn_limits?: TurnLimits };
const CHECKPOINT_KEYS = ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"];
function need(value: unknown, code: string): asserts value { if (!value) throw new ApiError(422, code); }
function near(player: Record<string, unknown>, marker: Marker): boolean {
  return player.surface_id === marker.surface_id && player.height === marker.height_cm &&
    (Number(player.x) - marker.position_cm[0]) ** 2 + (Number(player.z) - marker.position_cm[1]) ** 2 <= marker.radius_cm ** 2;
}

/** These two pinned circuits have a unique alignment for each required light.
 * This is an envelope sanity check, not a second ray/physics simulator. Native
 * replay remains required to establish every control action and entry latch. */
function signals(controls: Record<string, unknown>): Record<string, boolean> {
  return { "high-light": controls["court-fork"] === "slash" && controls["high-return"] === "slash" && controls["preserved-turn"] === "backslash",
    "garden-light": controls["gallery-fork"] === "backslash" && controls["garden-return"] === "slash",
    "crossing-light": controls["lower-fork"] === "backslash" && controls["crossing-return"] === "slash",
    "second-light": controls["final-mirror"] === "slash" };
}

function adapter(definition: Definition, initial: ChapterCheckpoint, definitionHash: string, maxBranches?: number): ChapterAdapter {
  const key = Object.freeze({ level_id: definition.id, level_version: definition.version, definition_hash: definitionHash });
  // A definition declaring rules 9 or later plays only those; older ones keep 7 and 8.
  const pinned = definition.simulation_version >= 9 ? definition.simulation_version : 0;
  const supported: readonly number[] = pinned ? [pinned] : [7, 8];
  // Tide rules (10 and later) latch no route: a player may end a stage on a
  // stub only while one of this stage's gates for it holds on the end state.
  const tideRules = definition.simulation_version >= 10;
  // Longer turns, when the definition declares them, carry bounds grown to fit.
  const turns = turnLimits(definition), limits = turns ? scaledLimits(turns) : undefined;
  if (limits) checkTurnBounds(limits, maxBranches);
  const recording = physicalRecording(definition, key, 7, supported, undefined, turns, limits);
  async function checkpoint(value: unknown, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording): Promise<ChapterCheckpoint> {
    boundedValue(value, limits?.checkpoint_bytes ?? MAX_CHECKPOINT_BYTES, limits?.checkpoint_values);
    const c = object(value); exact(c, CHECKPOINT_KEYS);
    need(c.level_id === key.level_id && c.level_version === key.level_version && c.definition_hash === key.definition_hash, "unsupported_chapter");
    const index = previous.stage_index + 1, stage = definition.stages[index - 1];
    need(c.schema_version === 7 && c.stage_index === index && stage && index <= definition.stages.length && c.completed_stage_id === stage.id && c.next_stage_id === (definition.stages[index]?.id ?? ""), "checkpoint_stage_mismatch");
    need(supported.includes(a.simulation_version) && b.simulation_version === a.simulation_version && a.role === "a" && b.role === "b" && accepted(a) && accepted(b), "checkpoint_recording_mismatch");
    if (previous.stage_index > 0) need(object(object(object(previous).proof).a).simulation_version === a.simulation_version, "checkpoint_recording_mismatch");
    need(c.previous_checkpoint_hash === previous.checkpoint_hash && c.a_recording_hash === a.recording_hash && c.b_recording_hash === b.recording_hash &&
      a.checkpoint_hash === previous.checkpoint_hash && b.checkpoint_hash === previous.checkpoint_hash && b.source_recording_hash === a.recording_hash && a.stage_id === stage.id && b.stage_id === stage.id, "checkpoint_source_mismatch");
    const proof = object(c.proof); exact(proof, ["checkpoint", "a", "b"]);
    need(canonicalJson(proof.checkpoint) === canonicalJson(previous) && canonicalJson(proof.a) === canonicalJson(a) && canonicalJson(proof.b) === canonicalJson(b), "checkpoint_proof_mismatch");
    const mechanisms = object(c.mechanisms), prior = object(object(previous).mechanisms);
    exact(mechanisms, ["latched_bridges", "props", "levers", "controls"]); exact(object(mechanisms.props), []);
    // Controls by id: a control repeated in both stages (the same entry) is
    // listed once, may change while its stage plays, and is held otherwise.
    const controls = object(mechanisms.controls), priorControls = object(prior.controls);
    const ids = [...new Set(definition.stages.flatMap(s => s.controls.map(control => control.id)))];
    exact(controls, ids);
    for (const id of ids) {
      need(typeof controls[id] === "string", "checkpoint_control_mismatch");
      const value = controls[id] as string, current = stage.controls.find(control => control.id === id);
      if (current) need(current.values.includes(value), "checkpoint_control_mismatch");
      else need(controls[id] === priorControls[id] && definition.stages.some(s => s.controls.some(control => control.id === id && control.values.includes(value))), "checkpoint_control_mismatch");
    }
    const levers = object(mechanisms.levers), priorLevers = object(prior.levers), leverIds = definition.stages.slice(0, index).flatMap(s => s.levers.map(lever => lever.id));
    need(Object.keys(levers).every(id => leverIds.includes(id)) && Object.keys(priorLevers).every(id => id in levers), "checkpoint_mechanism_mismatch");
    for (const id of Object.keys(levers)) need(typeof levers[id] === "boolean" && (stage.levers.some(lever => lever.id === id) || levers[id] === priorLevers[id]), "checkpoint_mechanism_mismatch");
    const routes = mechanisms.latched_bridges, previousRoutes = prior.latched_bridges as string[];
    need(Array.isArray(routes) && routes.every(route => typeof route === "string") && canonicalJson(routes) === canonicalJson([...new Set(routes)].sort()), "checkpoint_mechanism_mismatch");
    const allowed = new Set([...previousRoutes, ...stage.gates.map(gate => gate.route_id)]);
    need(routes.every(route => allowed.has(route)) && previousRoutes.every(route => routes.includes(route)), "checkpoint_mechanism_mismatch");
    if (tideRules) need(routes.length === 0, "checkpoint_mechanism_mismatch");
    const players = object(c.players), stubs: string[] = []; exact(players, ["p0", "p1"]);
    for (const [slot, value] of Object.entries(players)) {
      const p = object(value); exact(p, ["x", "z", "height", "surface_id"]);
      const x = integer(p.x, -10_000, 10_000), z = integer(p.z, -10_000, 10_000), height = integer(p.height, 0, 10_000);
      const surface = [...definition.islands, ...definition.bridges, ...definition.stairs].find(surface => surface.id === p.surface_id);
      need(surface && x >= surface.rect_cm[0] && x <= surface.rect_cm[2] && z >= surface.rect_cm[1] && z <= surface.rect_cm[3] && (!surface.owner_slot || surface.owner_slot === slot), "checkpoint_surface_mismatch");
      if (!definition.islands.includes(surface)) { if (tideRules) stubs.push(surface.id); else need(routes.includes(surface.id), "checkpoint_surface_mismatch"); }
      const axis = surface.axis === "z" ? 1 : 0, coordinate = axis === 0 ? x : z;
      const expectedHeight = surface.from_height_cm === undefined ? surface.height_cm : Math.round(surface.from_height_cm +
        (surface.to_height_cm! - surface.from_height_cm) * (coordinate - surface.rect_cm[axis]) / (surface.rect_cm[axis + 2] - surface.rect_cm[axis]));
      need(height === expectedHeight, "checkpoint_surface_mismatch");
    }
    const source = object(players[stage.first_player_slot]), receiver = object(players[stage.first_player_slot === "p0" ? "p1" : "p0"]), light = signals(controls);
    function predicate(value: Predicate = {}): boolean {
      if (value.all) return value.all.every(predicate);
      if (value.any) return value.any.some(predicate);
      if (value.control_id) return controls[value.control_id] === value.value;
      if (value.lever_id) return levers[value.lever_id] === true;
      if (value.signal_id) return light[value.signal_id] === true;
      if (value.pad_id) { const pad = stage.pressure_pads.find(pad => pad.id === value.pad_id); return !!pad && near(object(players[pad.owner_slot]), pad); }
      return true;
    }
    for (const id of stubs) need(stage.gates.some(gate => gate.route_id === id && predicate(gate.when)), "checkpoint_surface_mismatch");
    need(near(receiver, stage.goal) && predicate(stage.goal_policy.when), "checkpoint_goal_mismatch");
    const policy = stage.source_policy;
    need(policy.kind === "choice_pad" ? policy.branches!.some(branch => predicate({ pad_id: branch.pad_id })) :
      predicate(policy.when) && (!policy.endpoint || near(source, policy.endpoint)), "checkpoint_source_position_mismatch");
    if (definition.id === "conservatory" && index === 1) need(source.surface_id === "court", "checkpoint_source_position_mismatch");
    if (definition.id === "long-way-home" && index === 1) need(stage.gates.every(gate => routes.includes(gate.route_id)), "checkpoint_mechanism_mismatch");
    if (!tideRules) for (const gate of stage.gates) {
      const open = previousRoutes.includes(gate.route_id) || predicate(gate.when);
      need(!open || routes.includes(gate.route_id), "checkpoint_mechanism_mismatch");
      if (!open && !stage.entry_latch_routes.includes(gate.route_id)) need(!routes.includes(gate.route_id), "checkpoint_mechanism_mismatch");
    }
    const { checkpoint_hash, proof: ignoredProof, ...body } = c; void ignoredProof;
    need(typeof checkpoint_hash === "string" && HASH_PATTERN.test(checkpoint_hash) && await digest(canonicalJson(body)) === checkpoint_hash, "checkpoint_hash_mismatch");
    return c as ChapterCheckpoint;
  }
  return { key, recording_version: 7, simulation_version: pinned || 7, supported_simulation_versions: supported, premium: definition.premium, require_supported_simulation_on_join: true,
    stages: definition.stages, initial: () => structuredClone(initial), recording, checkpoint, accepted, ...(limits ? { limits } : {}), ...(maxBranches === undefined ? {} : { max_branches: maxBranches }) };
}
export const conservatory = adapter(conservatoryDefinition, conservatoryInitial, CONSERVATORY_HASH);
export const longWayHome = adapter(homeDefinition, homeInitial, LONG_WAY_HOME_HASH);
/** The harder finale. Pinned to rules 9 by its definition, so 0.5.x guests are refused on join. */
export const longWayHomeV2 = adapter(homeV2Definition, homeV2Initial, LONG_WAY_HOME_V2_HASH);
/** Free; pinned to rules 9 by its definition, so 0.5.x guests are refused on join.
 * Seven branches keep its widest replay archive and room snapshot under their caps. */
export const turnOfTheTide: ChapterAdapter = adapter(tideDefinition, tideInitial, TURN_OF_THE_TIDE_HASH, 7);
/** Free; pinned to tide rules (10) by its definition, so guests whose client never offered 10 are refused on join.
 * No route latches: a stub a player ends on must be open on the end state.
 * Seven branches, as @1, keep its widest replay archive and room snapshot under their caps. */
export const turnOfTheTideV2: ChapterAdapter = adapter(tideV2Definition, tideV2Initial, TURN_OF_THE_TIDE_V2_HASH, 7);
