import { ApiError, HASH_PATTERN, canonicalJson, digest, integer, object } from "../protocol";
import { boundedStructureLimit, exact } from "./protocol-relay";
import { physicalRecording, physicalAccepted as accepted } from "./protocol-physical-recording";
import type { ChapterAdapter, ChapterCheckpoint, ChapterLimits, ChapterRecording } from "./chapter-types";
import lighthouseDefinition from "./sleeping-lighthouse-v2.json";
import lighthouseInitial from "./sleeping-lighthouse-v2-initial.json";

// sleeping-lighthouse@2: the six Lighthouse stages as one chapter on the shared
// record shape (schema 8, rules 11). Like every chapter, the server checks the
// envelope and the end state each stage can reach; clients replay every turn
// and proof. Each stage embeds its native definition, which these checks read.
export const LIGHTHOUSE_V2_HASH = "0f5a41aa23b53d9f97d47851740a1bdd484371bc128f8b319bed9f509a9e8149";
const SCHEMA = 8, RULES = 11, MAX_TICKS = 600;
type Rect = { id: string; rect_cm: number[] };
type Native = { islands: Rect[]; bridges: (Rect & { receiver_id?: string })[]; optics: { mirrors: { id: string; orientation: string }[] };
  controls?: { id: string; kind: string; optical_id?: string }[]; mirror_control?: { id: string }; props?: { id: string }[]; sockets?: { id: string }[];
  goal_policy?: { kind?: string; checkpoint_flag?: string; prop_id?: string; socket_id?: string } };
type Definition = { id: string; version: number; simulation_version: number; premium: boolean; stages: { id: string; first_player_slot: string; native: Native }[] };
const definition = lighthouseDefinition as unknown as Definition;
const CHECKPOINT_KEYS = ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"];
const PROP_KEYS = ["status", "holder_slot", "socket_id", "x", "z", "surface_id"];
/** Measured structural worst case (every record 600 one-tick entries at the widest
 * form, test_lighthouse_v2_proof): checkpoint 358,808 bytes / 37,289 values,
 * receiver turn body 388,244 / 40,376 at depth 16. */
export const LIGHTHOUSE_LIMITS: Readonly<ChapterLimits> = Object.freeze({ checkpoint_bytes: 393_216, checkpoint_values: 40_000, turn_body_bytes: 425_984, turn_body_values: 44_000 });
/** Seven branches keep the widest six-stage room inside its caps (lighthouse-room-limits):
 * replay archive 14.1 MB of 16 MiB, room snapshot 24.6 MB of 24 MiB less envelope. */
export const LIGHTHOUSE_MAX_BRANCHES = 7;
function need(value: unknown, code: string): asserts value { if (!value) throw new ApiError(422, code); }

const key = Object.freeze({ level_id: definition.id, level_version: definition.version, definition_hash: LIGHTHOUSE_V2_HASH });
const recording = physicalRecording(definition, key, SCHEMA, [RULES], MAX_TICKS);

async function checkpoint(value: unknown, previous: ChapterCheckpoint, a: ChapterRecording, b: ChapterRecording): Promise<ChapterCheckpoint> {
  boundedStructureLimit(value, LIGHTHOUSE_LIMITS.checkpoint_bytes, LIGHTHOUSE_LIMITS.checkpoint_values);
  const c = object(value); exact(c, CHECKPOINT_KEYS);
  need(c.level_id === key.level_id && c.level_version === key.level_version && c.definition_hash === key.definition_hash, "unsupported_chapter");
  const index = previous.stage_index + 1, stage = definition.stages[index - 1];
  need(c.schema_version === SCHEMA && c.stage_index === index && stage && index <= definition.stages.length && c.completed_stage_id === stage.id && c.next_stage_id === (definition.stages[index]?.id ?? ""), "checkpoint_stage_mismatch");
  need(a.simulation_version === RULES && b.simulation_version === RULES && a.role === "a" && b.role === "b" && accepted(a) && accepted(b), "checkpoint_recording_mismatch");
  need(c.previous_checkpoint_hash === previous.checkpoint_hash && c.a_recording_hash === a.recording_hash && c.b_recording_hash === b.recording_hash &&
    a.checkpoint_hash === previous.checkpoint_hash && b.checkpoint_hash === previous.checkpoint_hash && b.source_recording_hash === a.recording_hash && a.stage_id === stage.id && b.stage_id === stage.id, "checkpoint_source_mismatch");
  const proof = object(c.proof); exact(proof, ["checkpoint", "a", "b"]);
  need(canonicalJson(proof.checkpoint) === canonicalJson(previous) && canonicalJson(proof.a) === canonicalJson(a) && canonicalJson(proof.b) === canonicalJson(b), "checkpoint_proof_mismatch");
  const native = stage.native, mechanisms = object(c.mechanisms), prior = object(object(previous).mechanisms);
  exact(mechanisms, ["latched_bridges", "mirrors", "props", "flags"]);
  // Bridges: a sorted set that keeps every earlier bridge and adds only this stage's.
  const routes = mechanisms.latched_bridges, previousRoutes = prior.latched_bridges as string[];
  need(Array.isArray(routes) && routes.every(route => typeof route === "string") && canonicalJson(routes) === canonicalJson([...new Set(routes)].sort()), "checkpoint_mechanism_mismatch");
  const allowedRoutes = new Set([...previousRoutes, ...native.bridges.map(bridge => bridge.id)]);
  need(routes.every(route => allowedRoutes.has(route)) && previousRoutes.every(route => routes.includes(route)), "checkpoint_mechanism_mismatch");
  // Mirrors: known optics only; a mirror this stage cannot turn keeps its value.
  const mirrors = object(mechanisms.mirrors), priorMirrors = object(prior.mirrors);
  const turnable = new Set([...(native.controls ?? []).map(control => control.optical_id ?? control.id), ...(native.mirror_control ? [native.mirror_control.id] : [])]);
  const stageMirrors = new Map(native.optics.mirrors.map(mirror => [mirror.id, mirror.orientation]));
  need(Object.keys(priorMirrors).every(id => id in mirrors), "checkpoint_mechanism_mismatch");
  for (const [id, orientation] of Object.entries(mirrors)) {
    need(orientation === "slash" || orientation === "backslash", "checkpoint_mechanism_mismatch");
    need(id in priorMirrors || stageMirrors.has(id), "checkpoint_mechanism_mismatch");
    if (!turnable.has(id)) need(orientation === (id in priorMirrors ? priorMirrors[id] : stageMirrors.get(id)), "checkpoint_mechanism_mismatch");
  }
  // Props: only props authored so far, exact shape, at a known socket when fitted.
  const props = object(mechanisms.props), priorProps = object(prior.props);
  const propIds = new Set(definition.stages.slice(0, index).flatMap(s => (s.native.props ?? []).map(prop => prop.id)));
  const sockets = new Set(definition.stages.slice(0, index).flatMap(s => (s.native.sockets ?? []).map(socket => socket.id)));
  need(Object.keys(priorProps).every(id => id in props), "checkpoint_mechanism_mismatch");
  for (const [id, raw] of Object.entries(props)) {
    need(propIds.has(id), "checkpoint_mechanism_mismatch");
    const prop = object(raw); exact(prop, PROP_KEYS);
    integer(prop.x, -10_000, 10_000); integer(prop.z, -10_000, 10_000);
    need(typeof prop.status === "string" && typeof prop.holder_slot === "string" && typeof prop.socket_id === "string" && typeof prop.surface_id === "string", "checkpoint_mechanism_mismatch");
    if (prop.status === "fitted") need(prop.holder_slot === "" && sockets.has(prop.socket_id as string), "checkpoint_mechanism_mismatch");
  }
  // Flags: kept, and only this stage's own checkpoint flag may appear (and must, once B completes).
  const flags = object(mechanisms.flags), priorFlags = object(prior.flags), own = native.goal_policy?.checkpoint_flag;
  need(Object.keys(priorFlags).every(id => flags[id] === true), "checkpoint_mechanism_mismatch");
  for (const [id, set] of Object.entries(flags)) need(set === true && (id in priorFlags || id === own), "checkpoint_mechanism_mismatch");
  if (own) need(flags[own] === true, "checkpoint_goal_mismatch");
  const goal = native.goal_policy;
  if (goal && (goal.kind === "fit_prop" || goal.kind === "fit_handoff")) {
    const prop = object(props[goal.prop_id!] ?? {});
    need(prop.status === "fitted" && prop.socket_id === goal.socket_id && prop.holder_slot === "", "checkpoint_goal_mismatch");
  }
  // Players: on a surface this stage has; on a bridge only once it is latched.
  const players = object(c.players); exact(players, ["p0", "p1"]);
  for (const value of Object.values(players)) {
    const p = object(value); exact(p, ["x", "z", "height", "surface_id"]);
    const x = integer(p.x, -10_000, 10_000), z = integer(p.z, -10_000, 10_000); need(p.height === 0, "checkpoint_surface_mismatch");
    const surface = [...native.islands, ...native.bridges].find(surface => surface.id === p.surface_id);
    need(surface && x >= surface.rect_cm[0] && x <= surface.rect_cm[2] && z >= surface.rect_cm[1] && z <= surface.rect_cm[3], "checkpoint_surface_mismatch");
    if (!native.islands.includes(surface as Rect)) need(routes.includes(surface.id), "checkpoint_surface_mismatch");
  }
  const { checkpoint_hash, proof: ignoredProof, ...body } = c; void ignoredProof;
  need(typeof checkpoint_hash === "string" && HASH_PATTERN.test(checkpoint_hash) && await digest(canonicalJson(body)) === checkpoint_hash, "checkpoint_hash_mismatch");
  return c as ChapterCheckpoint;
}

/** Paid; pinned to rules 11, so every client without six-stage support is refused on join. */
export const sleepingLighthouseV2: ChapterAdapter = { key, recording_version: SCHEMA, simulation_version: RULES, supported_simulation_versions: [RULES], premium: definition.premium,
  require_supported_simulation_on_join: true, stages: definition.stages, limits: LIGHTHOUSE_LIMITS, max_branches: LIGHTHOUSE_MAX_BRANCHES,
  initial: () => structuredClone(lighthouseInitial) as unknown as ChapterCheckpoint, recording, checkpoint, accepted };
