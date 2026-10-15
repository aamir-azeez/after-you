import { ApiError, HASH_PATTERN, canonicalJson, integer, object, text } from "../protocol";
import { ZERO_LINK, attemptBlob, attemptLink, attemptRows, blobBytes, bytesDigest, decodeAttempt, encodeAttempt, isStub, type AttemptBlob, type AttemptRoom } from "./history-blob";
import { bothSupport, finishedAttempts, historyChain, persistChain, storedAttempts, writeAttempt, type AttemptRecord } from "./history";
import { chapter, exact } from "./protocol";
import { boundedArchiveStructure, compactPair, type TransferredRoom } from "./replay-transfer";
import type { PairV2, RoomStateV2 } from "./room";
import { historyPresent, initializeHistory } from "./storage-schema";

/** A live room, or a finished one whose replays left the server. */
export type HistoryRoom = RoomStateV2 | TransferredRoom;
export type AttemptView = {
  position: number; branch: number; digest: string; link: string; byte_length: number; last_stage: number; state: "held" | "offloaded";
  acked_by_you: boolean; partner_acked: boolean; wanted_by_partner: boolean; pair_ids: string[];
};
export type HistoryView = { schema_version: 1; mode: "attempts" | "v1_transferred"; head: string; attempts: AttemptView[] };

function need(value: unknown, status: number, code: string): asserts value { if (!value) throw new ApiError(status, code); }
export const roomKey = (room: HistoryRoom): AttemptRoom => ({ room_id: room.room_id, level_id: room.level_id, level_version: room.level_version, definition_hash: room.definition_hash });
export const archived = (room: HistoryRoom): room is TransferredRoom => "replay_transfer_version" in room;
/** Finished attempts: every branch before the current one, and the current one once the room is complete. */
export function finishedOf(room: HistoryRoom): number {
  return finishedAttempts(room.branch, archived(room) || room.stage_index === chapter(room).stages.length);
}
const members = (room: HistoryRoom) => [room.host_id, room.guest_id].filter((id): id is string => id !== null);
const partnerOf = (room: HistoryRoom, player: string) => player === room.host_id ? room.guest_id : room.host_id;
/** Member ids in host, guest order, once each. */
export const memberSet = (room: HistoryRoom, ids: string[]) => members(room).filter(id => ids.includes(id));

function attemptView(record: AttemptRecord, room: HistoryRoom, player: string): AttemptView {
  const partner = partnerOf(room, player);
  return { position: record.position, branch: record.branch, digest: record.digest, link: record.link, byte_length: record.byte_length, last_stage: record.last_stage,
    state: record.state, acked_by_you: record.acked.includes(player), partner_acked: partner !== null && record.acked.includes(partner),
    wanted_by_partner: partner !== null && record.wanted.includes(partner), pair_ids: record.pair_ids };
}
export function historyView(room: HistoryRoom, records: AttemptRecord[], player: string): HistoryView {
  return { schema_version: 1, mode: "attempts", head: records.at(-1)?.link ?? ZERO_LINK, attempts: records.map(record => attemptView(record, room, player)) };
}
export const V1_TRANSFERRED: HistoryView = { schema_version: 1, mode: "v1_transferred", head: ZERO_LINK, attempts: [] };

/**
 * The room's finished attempts. While history tables exist, newly finished
 * attempts are stored so their hashes stay fixed once their rows are stubbed;
 * otherwise (offload never on here) the chain is computed and nothing is written.
 */
export async function loadChain(storage: DurableObjectStorage, room: HistoryRoom, promote: boolean): Promise<AttemptRecord[]> {
  const finished = finishedOf(room), { records, fresh } = await historyChain(storage, roomKey(room), finished);
  if (!fresh.length || (!historyPresent(storage) && !promote)) return records;
  storage.transactionSync(() => {
    need(historyPresent(storage) || initializeHistory(storage), 409, "history_standalone_only");
    need(persistChain(storage, fresh.map(item => item.record)), 409, "history_changed");
  });
  return storedAttempts(storage).slice(0, finished);
}
export function parsePosition(value: string): number { return integer(Number(text(value, /^(?:[0-9]|[12][0-9]|3[01])$/)), 0, 31); }
export function parseAck(input: unknown): string {
  const value = object(input); exact(value, ["schema_version", "link"]);
  need(value.schema_version === 1, 422, "invalid_history_request");
  return text(value.link, HASH_PATTERN);
}
export function parseWant(input: unknown): void {
  const value = object(input); exact(value, ["schema_version"]);
  need(value.schema_version === 1, 422, "invalid_history_request");
}
/** A finished attempt's exact bytes, tagged and deflated; 410 once only its stub is left. */
export async function attemptDownload(storage: DurableObjectStorage, room: HistoryRoom, record: AttemptRecord): Promise<Uint8Array> {
  const blob = record.state === "held" ? attemptBlob(storage, roomKey(room), record.position) : null;
  need(blob, 410, "history_offloaded");
  const bytes = blobBytes(blob);
  need(bytes.byteLength === record.byte_length && await bytesDigest(bytes) === record.digest, 500, "history_rows_inconsistent");
  return encodeAttempt(bytes);
}

/** The uploaded attempt, proven to be the server's own earlier bytes for this room, place and chain. */
export async function checkedUpload(records: AttemptRecord[], position: number, body: Uint8Array, room: HistoryRoom): Promise<AttemptBlob> {
  const record = records[position]; need(record, 404, "history_not_found");
  const bytes = await decodeAttempt(body, record.byte_length);
  need(bytes && await bytesDigest(bytes) === record.digest, 422, "history_mismatch");
  need(await attemptLink(roomKey(room), position, records[position - 1]?.link ?? ZERO_LINK, record.digest, record.byte_length) === record.link, 422, "history_mismatch");
  let blob: unknown;
  try { blob = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes)); } catch { throw new ApiError(422, "history_mismatch"); }
  boundedArchiveStructure(blob);
  return blob as AttemptBlob;
}

/** Puts back every stubbed row the blob proves; rows already full must already equal it. */
export function rebuildRows(storage: DurableObjectStorage, blob: AttemptBlob): void {
  const { pairs, turns } = attemptRows(blob);
  for (const [id, recording] of turns) {
    const row = storage.sql.exec<{ data: string }>("SELECT data FROM turns WHERE turn_id=?", id).toArray()[0];
    need(row && JSON.parse(row.data).recording_hash === recording.recording_hash, 409, "history_rows_inconsistent");
    if (isStub(row.data)) storage.sql.exec("UPDATE turns SET data=? WHERE turn_id=?", JSON.stringify(recording), id);
  }
  for (const [id, pair] of pairs) {
    const row = storage.sql.exec<{ data: string }>("SELECT data FROM pairs WHERE pair_id=?", id).toArray()[0];
    need(row && JSON.parse(row.data).checkpoint.checkpoint_hash === pair.checkpoint.checkpoint_hash, 409, "history_rows_inconsistent");
    if (isStub(row.data)) storage.sql.exec("UPDATE pairs SET data=? WHERE pair_id=?", JSON.stringify(pair), id);
  }
}

/** Upload: an offloaded attempt is held again and the uploader counts as having it; a held one is unchanged. */
export function restoreAttempt(storage: DurableObjectStorage, record: AttemptRecord, blob: AttemptBlob, player: string): AttemptRecord {
  need(canonicalJson(blob.rows.pairs.map(pair => pair.pair_id)) === canonicalJson(record.pair_ids), 409, "history_rows_inconsistent");
  if (record.state === "held") return record;
  rebuildRows(storage, blob);
  const next: AttemptRecord = { ...record, state: "held", acked: [player], wanted: [] };
  writeAttempt(storage, next);
  return next;
}
export function wantAttempt(storage: DurableObjectStorage, room: HistoryRoom, record: AttemptRecord, player: string): AttemptRecord {
  if (record.state === "held" || record.wanted.includes(player)) return record;
  const next = { ...record, wanted: memberSet(room, [...record.wanted, player]) };
  writeAttempt(storage, next);
  return next;
}
/**
 * Marks the caller as holding the attempt durably. When both members have, both
 * said they keep attempts, and the attempt is finished, the server keeps only
 * its hashes: every row the live lineage no longer reads becomes v1's stub.
 */
export function acknowledgeAttempt(storage: DurableObjectStorage, room: HistoryRoom, record: AttemptRecord, player: string): AttemptRecord {
  if (record.state === "offloaded") return record;
  const next = { ...record, acked: memberSet(room, [...record.acked, player]) };
  // A repeated ACK can complete an offload that waited for the partner's support.
  if (next.acked.length === 2 && bothSupport(storage, room.host_id, room.guest_id) && record.position < finishedOf(room)) return offloadAttempt(storage, room, next);
  if (next.acked.length !== record.acked.length) writeAttempt(storage, next);
  return next;
}
function offloadAttempt(storage: DurableObjectStorage, room: HistoryRoom, record: AttemptRecord): AttemptRecord {
  const next: AttemptRecord = { ...record, state: "offloaded", acked: [], wanted: [] };
  writeAttempt(storage, next);
  stubReleased(storage, room);
  return next;
}
/** Rows the live lineage still reads: its completed pairs with their turns, and the open first turn. */
export function liveReferences(room: HistoryRoom): Set<string> {
  const ids = new Set<string>();
  if (archived(room)) return ids;
  for (const id of room.completed_pair_ids) { const [branch, stage] = id.slice(1).split("-"); ids.add(id).add(`t${branch}-${stage}-a`).add(`t${branch}-${stage}-b`); }
  if (room.a_turn_id) ids.add(room.a_turn_id);
  return ids;
}
/** Every row of an offloaded attempt that nothing live reads is a stub; call after anything that moves the lineage. */
export function stubReleased(storage: DurableObjectStorage, room: HistoryRoom): void {
  if (!historyPresent(storage)) return;
  const live = liveReferences(room);
  for (const record of storedAttempts(storage)) {
    if (record.state !== "offloaded") continue;
    for (const row of storage.sql.exec<{ turn_id: string; data: string }>("SELECT turn_id,data FROM turns WHERE turn_id LIKE ?", `t${record.branch}-%`).toArray()) {
      if (live.has(row.turn_id) || isStub(row.data)) continue;
      storage.sql.exec("UPDATE turns SET data=? WHERE turn_id=?", JSON.stringify({ recording_hash: JSON.parse(row.data).recording_hash }), row.turn_id);
    }
    for (const row of storage.sql.exec<{ pair_id: string; data: string }>("SELECT pair_id,data FROM pairs WHERE pair_id LIKE ?", `p${record.branch}-%`).toArray()) {
      if (live.has(row.pair_id) || isStub(row.data)) continue;
      const pair = JSON.parse(row.data) as PairV2;
      storage.sql.exec("UPDATE pairs SET data=? WHERE pair_id=?", JSON.stringify(compactPair({ pair_id: pair.pair_id, branch: pair.branch, stage_index: pair.stage_index,
        a_hash: pair.a.recording_hash, b_hash: pair.b.recording_hash, checkpoint_hash: pair.checkpoint.checkpoint_hash })), row.pair_id);
    }
  }
}
export function offloadedCount(storage: DurableObjectStorage): number { return storedAttempts(storage).filter(record => record.state === "offloaded").length; }
