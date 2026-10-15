import { ApiError, HASH_PATTERN, canonicalJson, integer, object, text } from "../protocol";
import { ZERO_LINK, attemptBlob, attemptLink, attemptRows, blobBytes, bytesDigest, decodeAttempt, encodeAttempt, isStub, type AttemptBlob, type AttemptRoom } from "./history-blob";
import { finishedAttempts, historyChain, persistChain, storedAttempts, writeAttempt, type AttemptRecord } from "./history";
import { chapter, exact } from "./protocol";
import { boundedArchiveStructure, type TransferredRoom } from "./replay-transfer";
import type { RoomStateV2 } from "./room";
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
export function acknowledgeAttempt(storage: DurableObjectStorage, room: HistoryRoom, record: AttemptRecord, player: string): AttemptRecord {
  if (record.state === "offloaded" || record.acked.includes(player)) return record;
  const next = { ...record, acked: memberSet(room, [...record.acked, player]) };
  writeAttempt(storage, next);
  return next;
}
