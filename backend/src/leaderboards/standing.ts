import { shownName } from "../display-names";
import { MIN_ACCOUNT_AGE_MS, MIN_PARTNERS } from "./rules";

/**
 * A player's standing for ranking, read inside their Player object without
 * writing anything: when the account was made, their display name, and how
 * many different partners they have taken turns alongside.
 *
 * Partners come from the Player's room index (room-index.ts), which keeps each
 * linked room's last projection with both members and its revision. A room
 * counts once its revision shows both members took a turn (join is 1, the
 * first turn 2, the partner's turn 3). Rooms the index never saw do not
 * count, so the check fails closed: a missing index means no partners.
 */
export type Standing = { created_ms: number; display_name: string | null; partners: number };

/** Partners counted, at most this many (the rule needs 2). */
const PARTNER_SCAN_LIMIT = 8;
const TURNS_ALONGSIDE_REVISION = 3;

export function playerStanding(storage: DurableObjectStorage, identity: { player_id: string; state: string; created_at: string; display_name?: string } | null): Standing | null {
  if (!identity || identity.state !== "active") return null;
  const created_ms = Date.parse(identity.created_at);
  if (!Number.isFinite(created_ms)) return null;
  const partners = new Set<string>();
  let rows: { entry: string }[] = [];
  try { rows = storage.sql.exec<{ entry: string }>("SELECT entry FROM room_index WHERE entry IS NOT NULL").toArray(); } catch { rows = []; }
  for (const row of rows) {
    if (partners.size >= PARTNER_SCAN_LIMIT) break;
    try {
      const outcome = JSON.parse(row.entry) as { ok?: boolean; value?: { membership?: { host_id?: unknown; guest_id?: unknown }; revision?: unknown } };
      const membership = outcome.ok ? outcome.value?.membership : undefined, revision = outcome.value?.revision;
      if (!membership || typeof revision !== "number" || revision < TURNS_ALONGSIDE_REVISION) continue;
      const partner = membership.host_id === identity.player_id ? membership.guest_id : membership.guest_id === identity.player_id ? membership.host_id : null;
      if (typeof partner === "string" && partner !== identity.player_id) partners.add(partner);
    } catch { continue; }
  }
  return { created_ms, display_name: shownName(identity.display_name), partners: partners.size };
}

/** Whether a player may rank a run that finished at `finishedMs`. Null standing (no identity) never may. */
export function eligible(standing: Standing | null, finishedMs: number): boolean {
  return standing !== null && standing.created_ms <= finishedMs - MIN_ACCOUNT_AGE_MS && standing.partners >= MIN_PARTNERS;
}
