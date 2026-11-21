/**
 * Light pieces on the server: the phone's game/core/beam_field.gd trace and
 * game/core/physical/light_pieces.gd rules, read from a stage. A stage's optical_field
 * holds lamps (emitters), mirrors, receivers and blockers on one plane; mirror controls
 * turn their mirror to their value, a selector's "optics" {value: {id: {orientation?, enabled?}}}
 * sets entities at its value, and the stage's "lit_when" {lamp id: when} lights a lamp only
 * while its when holds (a light pad, a lens in its cradle). The receivers lit are the signals
 * a gate or goal reads ({"signal_id"}). Definitions are bundled and pinned by hash, so the
 * field is trusted; an envelope check like the rest of a checkpoint, from its end state.
 */
type Point = [number, number];
type Entity = { id: string; position_cm: number[]; enabled: boolean; direction?: string; orientation?: string };
export type OpticalField = { bounds_cm: number[]; emitters: Entity[]; mirrors: Entity[]; receivers: Entity[]; blockers: Entity[] };
type Override = { orientation?: string; enabled?: boolean };
export type LightStage = { optical_field?: OpticalField; lit_when?: Record<string, object>;
  controls: { id: string; kind?: string; initial?: string; optics?: Record<string, Record<string, Override>> }[] };

const DIRECTIONS = ["north", "east", "south", "west"];
/** beam_field.gd MAX_MIRRORS: a trace takes at most four turns at each mirror. */
const MAX_MIRRORS = 32;

/** What the stage's controls set from their values (light_pieces.gd steered). */
function steered(stage: LightStage, controls: Record<string, unknown>): Record<string, Override> {
  const result: Record<string, Override> = {};
  for (const control of stage.controls) {
    const value = String(Object.hasOwn(controls, control.id) ? controls[control.id] : control.initial ?? "");
    if (control.kind === "mirror") { result[control.id] = { orientation: value }; continue; }
    const sets = control.optics && Object.hasOwn(control.optics, value) ? control.optics[value] : undefined;
    for (const [id, state] of Object.entries(sets ?? {})) result[id] = { ...result[id], ...state };
  }
  return result;
}

/** The receivers lit on `stage` ({id: lit}), each lamp with a lit_when lit only while `holds` says so. */
export function lightSignals(stage: LightStage, controls: Record<string, unknown>, holds: (when: object) => boolean): Record<string, boolean> {
  const field = stage.optical_field;
  if (!field) return {};
  const overrides = steered(stage, controls);
  for (const [id, when] of Object.entries(stage.lit_when ?? {})) if (!holds(when)) overrides[id] = { ...overrides[id], enabled: false };
  type Placed = { id: string; kind: string; at: Point; enabled: boolean; direction?: string; orientation?: string };
  const entities: Placed[] = [];
  for (const [kind, list] of [["emitter", field.emitters], ["mirror", field.mirrors], ["receiver", field.receivers], ["blocker", field.blockers]] as const) {
    for (const entity of list) {
      const set = overrides[entity.id] ?? {};
      entities.push({ id: entity.id, kind, at: [entity.position_cm[0], entity.position_cm[1]], enabled: set.enabled ?? entity.enabled,
        direction: entity.direction, orientation: set.orientation ?? entity.orientation });
    }
  }
  entities.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const signals: Record<string, boolean> = {};
  for (const entity of entities) if (entity.kind === "receiver") signals[entity.id] = false;
  const [minX, minZ, maxX, maxZ] = field.bounds_cm;
  const distance = (from: Point, to: Point, direction: string): number => {
    switch (direction) {
      case "north": return from[0] === to[0] ? from[1] - to[1] : -1;
      case "east": return from[1] === to[1] ? to[0] - from[0] : -1;
      case "south": return from[0] === to[0] ? to[1] - from[1] : -1;
      default: return from[1] === to[1] ? from[0] - to[0] : -1;
    }
  };
  const boundary = (from: Point, direction: string): Point =>
    direction === "north" ? [from[0], minZ] : direction === "east" ? [maxX, from[1]] : direction === "south" ? [from[0], maxZ] : [minX, from[1]];
  for (const emitter of entities) {
    if (emitter.kind !== "emitter" || !emitter.enabled) continue;
    let origin = emitter.at, direction = emitter.direction!;
    const visited = new Set<string>();
    for (let step = 0; step < 4 * MAX_MIRRORS + 1; step++) {
      const end = boundary(origin, direction);
      let nearest = distance(origin, end, direction), hit: Placed | undefined;
      for (const candidate of entities) {
        if (!candidate.enabled || candidate.kind === "emitter") continue;
        const proposed = distance(origin, candidate.at, direction);
        if (proposed > 0 && proposed < nearest) { nearest = proposed; hit = candidate; }
      }
      if (!hit || hit.kind === "blocker") break;
      if (hit.kind === "receiver") { signals[hit.id] = true; break; }
      const state = `${hit.id}:${direction}`;
      if (visited.has(state)) break;
      visited.add(state);
      const index = DIRECTIONS.indexOf(direction);
      direction = DIRECTIONS[(hit.orientation === "slash" ? [1, 0, 3, 2] : [3, 2, 1, 0])[index]];
      origin = hit.at;
    }
  }
  return signals;
}
