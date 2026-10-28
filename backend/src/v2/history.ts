import { ApiError } from "../protocol";
import { flags } from "../flags";
import { ZERO_LINK, attemptBlob, attemptLink, blobBytes, lastStage, type AttemptRoom } from "./history-blob";
import { bytesDigest } from "../blob-codec";
import { historyPresent, initializeHistory } from "./storage-schema";

/** Sent by clients that keep downloaded room attempts durably and byte for byte. */
export const HISTORY_HEADER = "X-AfterYou-History";
export type HistorySupport = 0 | 1;
export type HistoryMember = { schema_version: 1; version: HistorySupport };

/** What a member's request says, or undefined while offload is off (nothing is then recorded). */
export function historySupport(request: Request, env: Env): HistorySupport | undefined {
  return flags.historyOffload(env) ? request.headers.get(HISTORY_HEADER) === "1" ? 1 : 0 : undefined;
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

/** One finished attempt in the room's chain. `acked` and `wanted` hold member ids. */
export type AttemptRecord = {
  schema_version: 1; position: number; branch: number; digest: string; link: string; byte_length: number; last_stage: number;
  state: "held" | "offloaded"; acked: string[]; wanted: string[]; pair_ids: string[];
};
export function storedAttempts(storage: DurableObjectStorage): AttemptRecord[] {
  if (!historyPresent(storage)) return [];
  return storage.sql.exec<{ data: string }>("SELECT data FROM history_attempts ORDER BY position").toArray().map(row => JSON.parse(row.data) as AttemptRecord);
}
export function writeAttempt(storage: DurableObjectStorage, record: AttemptRecord): void {
  storage.sql.exec("INSERT INTO history_attempts VALUES (?,?) ON CONFLICT(position) DO UPDATE SET data=excluded.data", record.position, JSON.stringify(record));
}
/** Attempts 0..branch-1 are finished; a complete room's current attempt is finished too. */
export function finishedAttempts(branch: number, complete: boolean): number { return branch + (complete ? 1 : 0); }

/**
 * Every finished attempt in order: the stored chain, extended by attempts that
 * finished since, each built from its held rows. Rows of a finished attempt never
 * change, so a lazily built record equals one built when the attempt finished.
 * Nothing is written; `fresh` lists the new records and their canonical bytes.
 */
export async function historyChain(storage: DurableObjectStorage, room: AttemptRoom, finished: number): Promise<{ records: AttemptRecord[]; fresh: { record: AttemptRecord; bytes: Uint8Array }[] }> {
  const records = storedAttempts(storage).slice(0, finished), fresh: { record: AttemptRecord; bytes: Uint8Array }[] = [];
  for (let position = records.length; position < finished; position++) {
    const blob = attemptBlob(storage, room, position);
    if (!blob) throw new ApiError(409, "history_rows_offloaded");
    const bytes = blobBytes(blob), hash = await bytesDigest(bytes);
    const record: AttemptRecord = { schema_version: 1, position, branch: position, digest: hash,
      link: await attemptLink(room, position, records.at(-1)?.link ?? ZERO_LINK, hash, bytes.byteLength), byte_length: bytes.byteLength,
      last_stage: lastStage(blob), state: "held", acked: [], wanted: [], pair_ids: blob.rows.pairs.map(pair => pair.pair_id) };
    records.push(record); fresh.push({ record, bytes });
  }
  return { records, fresh };
}
/** Stores newly built records, unless another request stored a different chain first. */
export function persistChain(storage: DurableObjectStorage, fresh: AttemptRecord[]): boolean {
  const stored = storedAttempts(storage);
  for (const record of fresh) {
    const existing = stored[record.position];
    if (existing) { if (existing.link !== record.link) return false; continue; }
    if (record.position !== stored.length) return false;
    writeAttempt(storage, record); stored.push(record);
  }
  return true;
}
