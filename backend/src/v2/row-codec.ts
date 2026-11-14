import { Buffer } from "node:buffer";
import { ApiError } from "../protocol";
import { decodeBlobSync, encodeBlobSync } from "../blob-codec";
import { flags, type ServerVars } from "../flags";
import { campaignStoragePresent } from "./campaign-storage";
import { MAX_ROW_BYTES } from "./row-bound";

/**
 * How a room keeps its big rows: the room row, turn rows and pair rows. Every version before kept each as JSON text.
 * While COMPRESSED_ROOMS is on (flags.ts), a standalone room writes them deflated:
 * - a turn or pair row as a BLOB: ROW_FORMAT_DEFLATE (one byte), the JSON's UTF-8 length (four bytes, big endian)
 *   and the tagged body of that JSON (blob-codec.ts);
 * - its room row as JSON text still, so SQL keeps reading its small fields (room-inbox.ts, friends.ts), with only
 *   `checkpoint` held as a string: PACKED_CHECKPOINT and the base64 of the same BLOB form of the checkpoint's JSON.
 * The JSON inside is exactly the text that would have been stored, so every recording, checkpoint and hash is as before.
 *
 * Readers take both forms whatever the flag says. Nothing converts in bulk: a room row takes the new form the next
 * time the room changes, a turn or pair row never changes once written, and stubs and tombstones stay text. A room
 * with Story (campaign) storage always writes text: its captures read the room row as text (campaign-source.ts).
 *
 * Every stored form is checked against MAX_ROW_BYTES as written (413 turn_too_large), inside the caller's
 * transaction, so a turn whose row would not fit writes nothing.
 */
export type RowData = string | ArrayBuffer;
export const ROW_FORMAT_DEFLATE = 1;
export const PACKED_CHECKPOINT = "deflate1:";
const HEADER_BYTES = 5;
/** The most JSON one row may hold, deflated or not: far past any chapter's widest row, and well inside a Durable Object's memory. */
export const MAX_ROW_JSON_BYTES = 64 * 1024 * 1024;
const utf8 = new TextEncoder(), text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

function unreadable(): never { throw new ApiError(500, "room_row_unreadable"); }
function fits(bytes: number): void { if (bytes > MAX_ROW_BYTES) throw new ApiError(413, "turn_too_large"); }

/** The BLOB form of `json`. */
function packed(json: string): Uint8Array {
  const bytes = utf8.encode(json);
  if (bytes.byteLength > MAX_ROW_JSON_BYTES) throw new ApiError(413, "turn_too_large");
  const body = encodeBlobSync(bytes), out = new Uint8Array(HEADER_BYTES + body.byteLength);
  out[0] = ROW_FORMAT_DEFLATE; new DataView(out.buffer).setUint32(1, bytes.byteLength); out.set(body, HEADER_BYTES);
  return out;
}
/** The JSON a BLOB form holds. */
function unpacked(bytes: Uint8Array): string {
  if (bytes.byteLength <= HEADER_BYTES || bytes[0] !== ROW_FORMAT_DEFLATE) unreadable();
  const length = new DataView(bytes.buffer, bytes.byteOffset).getUint32(1);
  if (length > MAX_ROW_JSON_BYTES) unreadable();
  const json = decodeBlobSync(bytes.subarray(HEADER_BYTES), length);
  if (!json) unreadable();
  try { return text.decode(json); } catch { return unreadable(); }
}

/** Whether this room writes the deflated forms now. */
export function compressRows(env: ServerVars, storage: DurableObjectStorage): boolean {
  return flags.compressedRooms(env) && !campaignStoragePresent(storage);
}

/** A turn or pair row's JSON text, from either form. */
export function rowJson(data: RowData): string {
  return typeof data === "string" ? data : unpacked(new Uint8Array(data));
}
export function parseRow<T>(data: RowData): T { return JSON.parse(rowJson(data)) as T; }
/** A turn or pair row for `value`, deflated when `compress`. */
export function storedRow(value: unknown, compress: boolean): RowData {
  const json = JSON.stringify(value);
  if (!compress) { fits(Buffer.byteLength(json, "utf8")); return json; }
  const bytes = packed(json); fits(bytes.byteLength);
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

/** A room row's value with its checkpoint as stored; a packed one is read back. Tombstones and markers pass through. */
export function parseRoom(data: string): Record<string, unknown> {
  const value = JSON.parse(data) as Record<string, unknown>;
  if (typeof value.checkpoint !== "string") return value;
  if (!value.checkpoint.startsWith(PACKED_CHECKPOINT)) unreadable();
  let bytes: Uint8Array;
  try { bytes = new Uint8Array(Buffer.from(value.checkpoint.slice(PACKED_CHECKPOINT.length), "base64")); } catch { return unreadable(); }
  return { ...value, checkpoint: JSON.parse(unpacked(bytes)) };
}
/** A room row for `state` (a live room, whose checkpoint is an object), its checkpoint packed when `compress`. */
export function storedRoom(state: { checkpoint: unknown }, compress: boolean): string {
  const json = compress ? JSON.stringify({ ...state, checkpoint: PACKED_CHECKPOINT + Buffer.from(packed(JSON.stringify(state.checkpoint))).toString("base64") }) : JSON.stringify(state);
  fits(Buffer.byteLength(json, "utf8"));
  return json;
}
/** A stored row as every version before kept it: the plain JSON text (operator snapshots, whose format is unchanged). */
export function plainRow(table: "room" | "turns" | "pairs", data: RowData): string {
  if (table !== "room") return rowJson(data);
  if (typeof data !== "string") unreadable();
  return typeof (JSON.parse(data) as Record<string, unknown>).checkpoint === "string" ? JSON.stringify(parseRoom(data)) : data;
}
