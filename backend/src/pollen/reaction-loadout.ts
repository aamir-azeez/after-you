import { isBaseFace, isPackFace, isSingleFace } from "../v2/end-reactions";

/**
 * A player's reaction slots: the faces the React card and the in-run card offer, in the order the player set them.
 * Stored beside the look in the pollen_look row (wardrobe.ts) and saved through the same equip, so it rides the
 * look's idempotency key, receipt and revision; an equip without `reactions` (an older app) keeps the stored slots.
 * The server only keeps it in step between devices: a turn is checked against owned faces (v2/face-packs.ts), never
 * against the slots. Pure: no storage.
 *
 * - SLOT_COUNT places, each a face id or "" for an empty place. FREE_SLOTS are everyone's; each reaction slot item
 *   owned (catalog "reaction_slot") opens the next. A face sits in at most one place, and the heart (Love) stays
 *   outside the slots, on the card's header.
 * - A player who never saved slots has DEFAULT_SLOTS: the free starter faces in the free places.
 */
export const SLOT_COUNT = 6;
export const FREE_SLOTS = 4;
export const DEFAULT_SLOTS: readonly string[] = Object.freeze(["happy", "surprised", "sad", "squeeze", "", ""]);
const HEART = "heart";

/** Whether `value` has the slots' shape: SLOT_COUNT strings, each "" or a face beyond the heart, no face twice. */
export function validSlots(value: unknown): value is string[] {
  if (!Array.isArray(value) || value.length !== SLOT_COUNT) return false;
  const seen = new Set<string>();
  for (const face of value) {
    if (typeof face !== "string") return false;
    if (face === "") continue;
    if (face === HEART || !(isBaseFace(face) || isPackFace(face) || isSingleFace(face)) || seen.has(face)) return false;
    seen.add(face);
  }
  return true;
}

/** Whether a player owning `faces` (the reaction faces, wardrobe.ts ownedFaceIds) and `unlocks` reaction slots may set `slots`. */
export function slotsAllowed(slots: readonly string[], faces: ReadonlySet<string>, unlocks: number): boolean {
  const open = openSlots(unlocks);
  return slots.every((face, index) => face === "" || (index < open && (isBaseFace(face) || faces.has(face))));
}

/** How many places are open for a player with `unlocks` reaction slots. */
export function openSlots(unlocks: number): number {
  return FREE_SLOTS + Math.max(0, Math.min(unlocks, SLOT_COUNT - FREE_SLOTS));
}
