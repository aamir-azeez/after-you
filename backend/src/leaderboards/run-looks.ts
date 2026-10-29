import { CATALOG, isDefaultLook, validLook, type Catalog, type Look } from "../pollen/catalog";
import { memberLook } from "../pollen/room-looks";

/**
 * Looks on leaderboard rows (art 01): each pair wears what they wore when their run finished.
 *
 * - Taking: the room reads both members' looks (pollen/room-looks.ts memberLook) inside the commit
 *   of the turn that finished the run, while looks are on, and hands them back as `board_looks`
 *   beside the reply. That is the commit the turn already makes, so no Durable Object request is
 *   added. The Worker takes the field out before the phone sees the reply (withoutBoardLooks).
 * - Keeping: the board stores each look on its member (board.ts Member.look), only when it is not
 *   the default, in the row it already writes for the run. Erasure clears the erased member's look.
 * - Serving: every ranked row carries `looks`, the two looks in slot order (host, guest, as
 *   `names`), {} for the default. A hidden-name pair ("A pair") still shows its looks, as the
 *   art does. While looks are off the read leaves the field out (publicView), so a board reads
 *   byte for byte as before. Each stored look is checked again on the way out, so a catalogue
 *   change never serves a slot that no longer exists.
 */
/** Always two looks, host first. An array, not a tuple, since Durable Object calls hand tuples back as arrays. */
export type PairLooks = Look[];

/** Inside the room's commit: both members' looks now, host first. */
export function pairLooks(storage: DurableObjectStorage, host: string, guest: string | null): PairLooks {
  return [memberLook(storage, host), memberLook(storage, guest)];
}

/** The pair's looks as a commit handed them over, or undefined when it handed none or something else. */
export function boardLooksOf(value: unknown): PairLooks | undefined {
  return Array.isArray(value) && value.length === 2 && value.every(look => validLook(look)) ? [value[0], value[1]] : undefined;
}

/** A look as a board may keep it: undefined for the default or anything that is not a look. */
export function keptLook(look: unknown, catalog: Catalog = CATALOG): Look | undefined {
  return validLook(look, catalog) && !isDefaultLook(look) ? look : undefined;
}

/** A stored look as it may be served: the default unless it is still a look. */
export function servedLook(look: unknown, catalog: Catalog = CATALOG): Look {
  return validLook(look, catalog) ? look : {};
}

/** The reply a phone gets: the commit without the board's server-only field. */
export function withoutBoardLooks<T extends { board_looks?: PairLooks }>(committed: T): Omit<T, "board_looks"> {
  if (!("board_looks" in committed)) return committed;
  const { board_looks: _taken, ...reply } = committed;
  return reply;
}
