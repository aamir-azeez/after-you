import { fail, ok, object, text, integer, HASH_PATTERN, type Outcome } from "../protocol";
import { exact } from "./protocol";
import { getPhoto, readPhoto, photoMetadata, type PhotoMetadata } from "./photos";
import { initializePhotoDelivery } from "./storage-schema";

type Members = { room_id: string; host_id: string; guest_id: string | null };
export type DeliveryRow = { schema_version: 1; turn_id: string; recording_hash: string; photo_revision: number; sha256: string; intended_player_ids: string[]; acked_player_ids: string[]; removed: boolean };
export type Delivery = { schema_version: 1; photo: PhotoMetadata | null; available: boolean; removed_reason: "delivered" | "owner_deleted" | null; intended_player_ids: string[]; acked_player_ids: string[] };
export function hasDelivery(storage: DurableObjectStorage): boolean {
  return storage.sql.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='photo_delivery'").toArray().length === 1;
}
export function deliveryRow(storage: DurableObjectStorage, turn: string): DeliveryRow | null {
  if (!hasDelivery(storage)) return null;
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM photo_delivery WHERE turn_id=?", turn).toArray()[0];
  return row ? JSON.parse(row.data) as DeliveryRow : null;
}
export function clearDelivery(storage: DurableObjectStorage, turn?: string): void {
  if (hasDelivery(storage)) storage.sql.exec(turn ? "DELETE FROM photo_delivery WHERE turn_id=?" : "DELETE FROM photo_delivery", ...(turn ? [turn] : []));
}
export function photoDelivery(storage: DurableObjectStorage, room: Members | null, player: string, turn: string): Outcome<Delivery> {
  // The legacy lookup enforces immutable accepted-turn and room membership.
  const allowed = getPhoto(storage, room, player, turn, true);
  if (!allowed.ok) return allowed;
  const state = readPhoto(storage, turn), row = deliveryRow(storage, turn);
  const current = row && state && row.photo_revision === state.photo_revision && row.sha256 === state.sha256 ? row : null;
  return ok({ schema_version: 1, photo: photoMetadata(state), available: !!state?.jpeg_base64,
    removed_reason: current?.removed ? "delivered" : state && !state.sha256 ? "owner_deleted" : null,
    intended_player_ids: [room!.host_id, ...(room!.guest_id ? [room!.guest_id] : [])], acked_player_ids: current?.acked_player_ids ?? [] });
}
/** Caller owns the SQLite transaction. ACK is the client's assertion of durable persistence. */
export function acknowledgePhoto(storage: DurableObjectStorage, room: Members | null, player: string, turn: string, value: unknown): Outcome<Delivery & { acked: true }> {
  const input = object(value); exact(input, ["recording_hash", "photo_revision", "sha256"]);
  const recording = text(input.recording_hash, HASH_PATTERN), revision = integer(input.photo_revision, 1, 256), hash = text(input.sha256, HASH_PATTERN);
  const observed = photoDelivery(storage, room, player, turn); if (!observed.ok) return observed;
  const photo = readPhoto(storage, turn);
  if (!photo || photo.recording_hash !== recording || photo.photo_revision !== revision || photo.sha256 !== hash) return fail(409, "stale_photo_ack");
  if (!room?.guest_id) return fail(409, "photo_recipients_unsettled");
  initializePhotoDelivery(storage);
  const row = deliveryRow(storage, turn) ?? { schema_version: 1, turn_id: turn, recording_hash: recording, photo_revision: revision, sha256: hash,
    intended_player_ids: [room.host_id, room.guest_id], acked_player_ids: [], removed: false } satisfies DeliveryRow;
  if (!row.acked_player_ids.includes(player)) row.acked_player_ids.push(player);
  row.acked_player_ids.sort((a, b) => row.intended_player_ids.indexOf(a) - row.intended_player_ids.indexOf(b));
  row.removed = row.intended_player_ids.every(id => row.acked_player_ids.includes(id));
  if (row.removed && photo.jpeg_base64 !== null) {
    photo.jpeg_base64 = null;
    storage.sql.exec("UPDATE photos SET data=? WHERE turn_id=?", JSON.stringify(photo), turn);
  }
  storage.sql.exec("INSERT OR REPLACE INTO photo_delivery VALUES (?,?)", turn, JSON.stringify(row));
  const updated = photoDelivery(storage, room, player, turn); return updated.ok ? ok({ ...updated.value, acked: true }) : updated;
}
