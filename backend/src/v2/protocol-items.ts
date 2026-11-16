import { ApiError, integer, object } from "../protocol";
import { exact } from "./protocol-relay";
import { piecesRules } from "./chapter-types";

/**
 * Carried items and currents (rules 16, chapter-types.ts PIECES_RULES; the phone's
 * rules are game/core/physical/carried_items.gd). A definition may list "items"
 * ({id, at, carry?}) and "item_spots" ({id, surface_id, position_cm, height_cm});
 * its checkpoints then hold mechanisms.items {id: {holder, spot, x, z, height, surface_id}}.
 * Held: holder "p0"/"p1", spot "", x, z, height 0 and surface_id "". Resting: holder "",
 * at an item spot (its place exactly) or loose on an island (spot "", on its floor at its height).
 * A float ("carry": false) only ever rests at a spot. A pip holds one item.
 * The predicate terms {item_id, carried} and {item_id, spot_id} are read here.
 * An envelope check like the rest of the checkpoint: the phones' replay proves each move.
 */
export type ItemState = { holder: string; spot: string; x: number; z: number; height: number; surface_id: string };
type Island = { id: string; rect_cm: number[]; height_cm?: number };
type ItemSpot = { id: string; surface_id: string; position_cm: number[]; height_cm?: number };
type ItemEntry = { id: string; at: string; carry?: boolean };
export type ItemDefinition = { simulation_version: number; islands: Island[]; items?: ItemEntry[]; item_spots?: ItemSpot[] };
const STATE_KEYS = ["holder", "spot", "x", "z", "height", "surface_id"] as const;

function need(value: unknown, code = "checkpoint_item_mismatch"): asserts value { if (!value) throw new ApiError(422, code); }

/** Whether `definition` lists items, so its checkpoints keep mechanisms.items. */
export function declaresItems(definition: object): boolean {
  const items = (definition as Partial<ItemDefinition>).items;
  return Array.isArray(items) && items.length > 0;
}

/** Throws at load unless a definition with items pins rules 16 and names its items and spots once each. */
export function checkItemDefinition(definition: ItemDefinition): void {
  if (!declaresItems(definition)) return;
  if (!piecesRules(definition.simulation_version)) throw new Error("A definition with items must pin rules 16");
  const spots = new Set((definition.item_spots ?? []).map(spot => spot.id)), ids = new Set(definition.items!.map(item => item.id));
  if (spots.size !== (definition.item_spots ?? []).length || ids.size !== definition.items!.length) throw new Error("Item and item spot ids must be distinct");
}

/** A checkpoint's mechanisms.items, checked against the definition; the states by id. */
export function checkItems(value: unknown, definition: ItemDefinition): Record<string, ItemState> {
  const items = object(value), entries = definition.items ?? [], states: Record<string, ItemState> = {};
  exact(items, entries.map(entry => entry.id));
  const holders = new Set<string>();
  for (const entry of entries) {
    const state = object(items[entry.id]); exact(state, STATE_KEYS);
    need(typeof state.holder === "string" && typeof state.spot === "string" && typeof state.surface_id === "string");
    const x = integer(state.x, -10_000, 10_000), z = integer(state.z, -10_000, 10_000), height = integer(state.height, 0, 10_000);
    if (state.holder !== "") {
      need((state.holder === "p0" || state.holder === "p1") && entry.carry !== false && !holders.has(state.holder));
      need(state.spot === "" && x === 0 && z === 0 && height === 0 && state.surface_id === "");
      holders.add(state.holder);
    } else if (state.spot !== "") {
      const spot = (definition.item_spots ?? []).find(found => found.id === state.spot);
      need(spot && spot.position_cm[0] === x && spot.position_cm[1] === z && (spot.height_cm ?? 0) === height && spot.surface_id === state.surface_id);
    } else {
      const island = definition.islands.find(found => found.id === state.surface_id);
      need(entry.carry !== false && island && x >= island.rect_cm[0] && x <= island.rect_cm[2] && z >= island.rect_cm[1] && z <= island.rect_cm[3] && (island.height_cm ?? 0) === height);
    }
    states[entry.id] = state as ItemState;
  }
  return states;
}

/** Whether `value` is an item term. */
export function isItemTerm(value: object): value is { item_id: string; carried?: boolean; spot_id?: string } {
  return Object.hasOwn(value, "item_id");
}

/** An item term on checked states: carried while a pip holds it, spot_id while it rests there. */
export function itemHolds(value: { item_id: string; carried?: boolean; spot_id?: string }, items: Record<string, ItemState>): boolean {
  const state = Object.hasOwn(items, value.item_id) ? items[value.item_id] : undefined;
  if (!state) return false;
  if (value.carried !== undefined) return (state.holder !== "") === value.carried;
  if (value.spot_id !== undefined) return state.holder === "" && state.spot === value.spot_id;
  return false;
}
