import { shownName, type DisplayNameFields } from "../display-names";

/**
 * The name change price (POLLEN-RULES.md "Prices": the first is free, then 1,000 each), worked out
 * from what the identity already holds. Pure: no storage. Only while the shop is on; with it off
 * every name stays free and nothing here is counted.
 *
 * Always free:
 * - going anonymous (null), and saving the name already set;
 * - the first name, and the first change after it (`display_name_sets` below 2);
 * - the first change after a moderator cleared the name: their lock has passed but is still noted
 *   (applyDisplayName drops it with the change);
 * - a change while the stored name no longer passes the rules or the block list (the filter refused it).
 *
 * A player named before the shop was on counts as one name set, so their next change is free.
 */
export const NAME_CHANGE_PRICE = 1000;
export const MAX_COUNTED_SETS = 2;

function setsSoFar(fields: DisplayNameFields): number {
  return fields.display_name_sets ?? (fields.display_name !== undefined ? 1 : 0);
}

/** What the next change to another name costs: the wallet read shows it beside Save. */
export function nextNamePrice(fields: DisplayNameFields, now: number): number {
  if (fields.display_name_locked_until !== undefined && fields.display_name_locked_until <= now) return 0;
  if (fields.display_name !== undefined && shownName(fields.display_name) === null) return 0;
  return setsSoFar(fields) < MAX_COUNTED_SETS ? 0 : NAME_CHANGE_PRICE;
}

/**
 * What the change after the next one would cost, once the next change to another name goes through
 * (the wallet read sends it as `name_price_next`). The app says "free this time" only when the next
 * change is free and this one is not: a first name (and the free change after it) would mislead.
 */
export function nextNamePriceAfter(fields: DisplayNameFields, now: number): number {
  const after: DisplayNameFields = {};
  countNameSet(after, fields);
  return nextNamePrice(after, now);
}

/** What setting `name` costs now. */
export function namePrice(fields: DisplayNameFields, name: string | null, now: number): number {
  return name === null || name === (fields.display_name ?? null) ? 0 : nextNamePrice(fields, now);
}

/** Counts one more name set, after a change to another non-null name went through. */
export function countNameSet(fields: DisplayNameFields, before: DisplayNameFields): void {
  fields.display_name_sets = Math.min(MAX_COUNTED_SETS, setsSoFar(before) + 1);
}
