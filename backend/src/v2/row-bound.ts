import { ApiError } from "../protocol";

/** One stored row. Rows live in Durable Object SQLite, which caps a row at 2 MB;
 * the widest Turn of the Tide pair row is about 823 KB. */
export const MAX_ROW_BYTES = 1536 * 1024;
/** A room's whole RoomV2 snapshot (snapshot.ts) and its replay archive (replay-transfer.ts); here so chapter adapters can check against them without an import cycle. */
export const MAX_ROOM_V2_ARCHIVE_BYTES = 24 * 1024 * 1024;
export const MAX_REPLAY_ARCHIVE_BYTES = 16 * 1024 * 1024;
/** `value` as the JSON text of one stored row. A turn whose row would pass MAX_ROW_BYTES is
 * refused with 413 turn_too_large; thrown inside the storage transaction, nothing is written. */
export function rowText(value: unknown): string {
  const text = JSON.stringify(value);
  // At most three UTF-8 bytes a UTF-16 unit, so short text needs no encoding.
  if (text.length * 3 > MAX_ROW_BYTES && new TextEncoder().encode(text).byteLength > MAX_ROW_BYTES) throw new ApiError(413, "turn_too_large");
  return text;
}
/** Photos a room keeps at once (photos.ts). */
export const MAX_PHOTOS = 32;
