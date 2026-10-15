import { historyPresent, initializeHistory } from "./storage-schema";

/** Sent by clients that keep downloaded room attempts durably and byte for byte. */
export const HISTORY_HEADER = "X-AfterYou-History";
export type HistorySupport = 0 | 1;
export type HistoryMember = { schema_version: 1; version: HistorySupport };

/** Off unless the deploy pins HISTORY_OFFLOAD_ENABLED=true. */
export function historyEnabled(env: Env): boolean { return String((env as Env & { HISTORY_OFFLOAD_ENABLED?: string }).HISTORY_OFFLOAD_ENABLED) === "true"; }
/** What a member's request says, or undefined while offload is off (nothing is then recorded). */
export function historySupport(request: Request, env: Env): HistorySupport | undefined {
  return historyEnabled(env) ? request.headers.get(HISTORY_HEADER) === "1" ? 1 : 0 : undefined;
}

export function historyMembers(storage: DurableObjectStorage): Map<string, HistorySupport> {
  if (!historyPresent(storage)) return new Map();
  return new Map(storage.sql.exec<{ player_id: string; data: string }>("SELECT player_id,data FROM history_members").toArray()
    .map(row => [row.player_id, (JSON.parse(row.data) as HistoryMember).version]));
}

/**
 * Records what a member's latest room request said about history support. A room
 * nobody has asked for gets no new tables, and a row is written only when the
 * value changes, so ordinary requests cost no write.
 */
export function noteHistorySupport(storage: DurableObjectStorage, player: string, version: HistorySupport): void {
  storage.transactionSync(() => {
    if (!historyPresent(storage) && (version === 0 || !initializeHistory(storage))) return;
    if (historyMembers(storage).get(player) === version) return;
    storage.sql.exec("INSERT INTO history_members VALUES (?,?) ON CONFLICT(player_id) DO UPDATE SET data=excluded.data", player, JSON.stringify({ schema_version: 1, version } satisfies HistoryMember));
  });
}

/** Both members' latest room requests said they keep attempts. */
export function bothSupport(storage: DurableObjectStorage, host: string, guest: string | null): boolean {
  const members = historyMembers(storage);
  return guest !== null && members.get(host) === 1 && members.get(guest) === 1;
}

export function clearHistory(storage: DurableObjectStorage): void {
  if (!historyPresent(storage)) return;
  storage.sql.exec("DELETE FROM history_attempts"); storage.sql.exec("DELETE FROM history_members");
}
