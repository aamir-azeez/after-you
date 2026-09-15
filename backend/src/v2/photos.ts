import { canonicalJson, digest, equalHash, fail, HASH_PATTERN, IDEMPOTENCY_PATTERN, integer, object, ok, text, type Outcome } from "../protocol";
import { exact } from "./protocol";
import { checkPhoto, type CheckedPhoto } from "./photo-image";

export const MAX_PHOTOS = 32, MAX_PHOTO_OPERATIONS = 256;
export const PHOTO_TURN_PATTERN = /^t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$/;
type Room = { room_id: string; host_id: string; guest_id: string | null };
export type PhotoState = { schema_version: 1; turn_id: string; owner_player_id: string; recording_hash: string; photo_revision: number; sha256: string | null; width: number | null; height: number | null; byte_length: number; jpeg_base64: string | null; updated_at: string };
export type PhotoMetadata = Omit<PhotoState, "jpeg_base64">;
export type PhotoReceipt = { schema_version: 1; room_id: string; idempotency_key: string; request_hash: string; operation: "photo_upload" | "photo_delete"; turn_id: string; recording_hash: string; photo_revision: number; photo_hash: string | null };
export type PhotoMutation = { receipt: PhotoReceipt; photo: PhotoMetadata | null };
export type ParsedPhotoMutation = { operation: "photo_upload" | "photo_delete"; turn_id: string; key: string; recording_hash: string; expected_revision: number; expected_hash: string | null; request_hash: string; image: CheckedPhoto | null };
const member = (room: Room | null, player: string): room is Room => room !== null && [room.host_id, room.guest_id].includes(player);
export function readPhoto(storage: DurableObjectStorage, turnId: string): PhotoState | null {
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM photos WHERE turn_id=?", turnId).toArray()[0];
  return row ? JSON.parse(row.data) as PhotoState : null;
}
export function photoMetadata(state: PhotoState | null): PhotoMetadata | null { if (!state) return null; const { jpeg_base64: _bytes, ...safe } = state; return safe; }

export async function parsePhotoMutation(turnId: string, value: unknown, remove: boolean): Promise<ParsedPhotoMutation> {
  text(turnId, PHOTO_TURN_PATTERN, "invalid_photo_turn");
  const input = object(value);
  exact(input, ["idempotency_key", "recording_hash", "expected_photo_revision", "expected_photo_hash", ...(remove ? [] : ["jpeg_base64", "sha256"])]);
  const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN), recording_hash = text(input.recording_hash, HASH_PATTERN);
  const expected_revision = integer(input.expected_photo_revision, 0, MAX_PHOTO_OPERATIONS);
  const expected_hash = input.expected_photo_hash === null ? null : text(input.expected_photo_hash, HASH_PATTERN);
  const image = remove ? null : await checkPhoto(input.jpeg_base64, input.sha256);
  const operation = remove ? "photo_delete" : "photo_upload";
  return { operation, turn_id: turnId, key, recording_hash, expected_revision, expected_hash, image, request_hash: await digest(canonicalJson({ operation, turn_id: turnId, ...input })) };
}

export function getPhoto(storage: DurableObjectStorage, room: Room | null, player: string, turnId: string, metadataOnly = false): Outcome<{ photo: PhotoMetadata | null; jpeg_base64: string | null }> {
  if (!member(room, player)) return fail(404, "room_not_found");
  if (!storage.sql.exec("SELECT turn_id FROM turns WHERE turn_id=?", turnId).toArray().length) return fail(404, "turn_not_found");
  const state = readPhoto(storage, turnId);
  if (!metadataOnly && state?.sha256 && !state.jpeg_base64) return fail(410, "photo_payload_delivered");
  return ok({ photo: photoMetadata(state), jpeg_base64: state?.jpeg_base64 ?? null });
}

export function getPhotoOperation(storage: DurableObjectStorage, room: Room | null, player: string, key: string): Outcome<PhotoMutation> {
  if (!member(room, player)) return fail(404, "room_not_found");
  const row = storage.sql.exec<{ receipt: string }>("SELECT receipt FROM photo_operations WHERE request_key=?", player + ":" + key).toArray()[0];
  if (!row) return fail(404, "photo_operation_not_found");
  const receipt = JSON.parse(row.receipt) as PhotoReceipt;
  return ok({ receipt, photo: photoMetadata(readPhoto(storage, receipt.turn_id)) });
}

/** Caller wraps this synchronous function in transactionSync after image validation. */
export function mutatePhoto(storage: DurableObjectStorage, room: Room | null, player: string, input: ParsedPhotoMutation): Outcome<PhotoMutation> {
  if (!member(room, player)) return fail(404, "room_not_found");
  const turn = storage.sql.exec<{ player_id: string; data: string }>("SELECT player_id,data FROM turns WHERE turn_id=?", input.turn_id).toArray()[0];
  if (!turn || turn.player_id !== player) return fail(404, "turn_not_found");
  if (JSON.parse(turn.data).recording_hash !== input.recording_hash) return fail(409, "photo_recording_mismatch");
  const prior = getPhotoOperation(storage, room, player, input.key);
  if (prior.ok) return equalHash(prior.value.receipt.request_hash, input.request_hash) ? prior : fail(409, "idempotency_key_reused");
  const previous = readPhoto(storage, input.turn_id);
  if ((previous?.photo_revision ?? 0) !== input.expected_revision || (previous?.sha256 ?? null) !== input.expected_hash) return fail(409, "stale_photo_revision");
  if (input.operation === "photo_delete" && !previous?.sha256) return fail(404, "photo_not_found");
  const operations = storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM photo_operations").one().n;
  const active = storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM photos WHERE json_extract(data,'$.sha256') IS NOT NULL").one().n;
  const nextActive = active + (input.image ? (previous?.sha256 ? 0 : 1) : -1);
  // Reserve one future deletion receipt per retained image. Filling the bounded
  // receipt history must never make deletion of an existing photo impossible.
  if (operations + 1 + nextActive > MAX_PHOTO_OPERATIONS) return fail(409, "photo_history_full");
  if (input.image && nextActive > MAX_PHOTOS) return fail(409, "photo_room_full");
  const state: PhotoState = { schema_version: 1, turn_id: input.turn_id, owner_player_id: player, recording_hash: input.recording_hash,
    photo_revision: (previous?.photo_revision ?? 0) + 1, sha256: input.image?.sha256 ?? null, width: input.image?.width ?? null,
    height: input.image?.height ?? null, byte_length: input.image?.byte_length ?? 0, jpeg_base64: input.image?.jpeg_base64 ?? null, updated_at: new Date().toISOString() };
  if (storage.sql.exec("SELECT name FROM sqlite_master WHERE name='photo_delivery'").toArray().length) storage.sql.exec("DELETE FROM photo_delivery WHERE turn_id=?", input.turn_id);
  storage.sql.exec("INSERT INTO photos VALUES (?,?) ON CONFLICT(turn_id) DO UPDATE SET data=excluded.data", input.turn_id, JSON.stringify(state));
  const receipt: PhotoReceipt = { schema_version: 1, room_id: room.room_id, idempotency_key: input.key, request_hash: input.request_hash, operation: input.operation,
    turn_id: input.turn_id, recording_hash: input.recording_hash, photo_revision: state.photo_revision, photo_hash: state.sha256 };
  storage.sql.exec("INSERT INTO photo_operations VALUES (?,?,?)", player + ":" + input.key, input.request_hash, JSON.stringify(receipt));
  return ok({ receipt, photo: photoMetadata(state) });
}
