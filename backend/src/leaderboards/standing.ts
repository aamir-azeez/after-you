import { shownName } from "../display-names";
import { indexedPartners } from "../room-index";
import { MIN_ACCOUNT_AGE_MS, MIN_PARTNERS } from "./rules";

/**
 * A player's standing for ranking, read inside their Player object without
 * writing anything: when the account was made, their shown display name, and
 * how many different partners they have taken turns alongside.
 *
 * Partners come from the Player's room index (room-index.ts indexedPartners),
 * which keeps each linked room's last projection with both members and its
 * revision. A room counts once its revision shows both members took a turn
 * (join is 1, the first turn 2, the partner's turn 3; a hard room's slip also
 * moves it, so this is a floor, not an exact count). Rooms the index never saw
 * do not count, so the check fails closed. While MIN_PARTNERS is 0 the index is
 * not read at all and partners reads 0.
 */
export type Standing = { created_ms: number; display_name: string | null; partners: number };

/** Partners counted, at most this many (the rule needed 2 before it was relaxed). */
const PARTNER_SCAN_LIMIT = 8;
const TURNS_ALONGSIDE_REVISION = 3;

export function playerStanding(storage: DurableObjectStorage, identity: { player_id: string; state: string; created_at: string; display_name?: string } | null): Standing | null {
  if (!identity || identity.state !== "active") return null;
  const created_ms = Date.parse(identity.created_at);
  if (!Number.isFinite(created_ms)) return null;
  return { created_ms, display_name: shownName(identity.display_name), partners: MIN_PARTNERS > 0 ? indexedPartners(storage, identity.player_id, TURNS_ALONGSIDE_REVISION, PARTNER_SCAN_LIMIT) : 0 };
}

/** Whether a player may rank a run that finished at `finishedMs`. Null standing (no identity) never may. */
export function eligible(standing: Standing | null, finishedMs: number): boolean {
  return standing !== null && standing.created_ms <= finishedMs - MIN_ACCOUNT_AGE_MS && standing.partners >= MIN_PARTNERS;
}
