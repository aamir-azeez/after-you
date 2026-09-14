import { decode } from "jpeg-js";
import { ApiError, HASH_PATTERN } from "../protocol";

export const MAX_PHOTO_BYTES = 160 * 1024;
export const MAX_PHOTO_EDGE = 960;
export type CheckedPhoto = { jpeg_base64: string; sha256: string; width: number; height: number; byte_length: number };
function need(value: unknown, code = "invalid_photo_jpeg"): asserts value { if (!value) throw new ApiError(400, code); }

/** Narrow native-encoder profile: baseline, one complete scan, no metadata. */
export function jpegFrame(bytes: Uint8Array): { width: number; height: number } {
  need(bytes.length >= 16 && bytes.length <= MAX_PHOTO_BYTES, "photo_size_limit");
  need(bytes[0] === 255 && bytes[1] === 216);
  let offset = 2, width = 0, height = 0, components = 0, app0 = false, tables = 0, huffman = 0;
  const word = (at: number) => bytes[at] * 256 + bytes[at + 1];
  while (offset + 3 < bytes.length) {
    need(bytes[offset++] === 255);
    const marker = bytes[offset++], length = word(offset);
    need([0xe0, 0xc0, 0xc4, 0xdb, 0xdd, 0xda].includes(marker), "unsupported_photo_format");
    need(length >= 2 && offset + length <= bytes.length);
    if (marker === 0xe0) {
      need(!app0 && length === 16 && [74, 70, 73, 70, 0].every((v, i) => bytes[offset + 2 + i] === v) && bytes[offset + 14] === 0 && bytes[offset + 15] === 0, "photo_metadata_not_allowed");
      app0 = true;
    } else if (marker === 0xc0) {
      need(!width && length >= 11 && bytes[offset + 2] === 8);
      height = word(offset + 3); width = word(offset + 5); components = bytes[offset + 7];
      need(width > 0 && height > 0 && width <= MAX_PHOTO_EDGE && height <= MAX_PHOTO_EDGE, "photo_dimensions_limit");
      need([1, 3].includes(components) && length === 8 + components * 3);
    } else if (marker === 0xdb) tables++;
    else if (marker === 0xc4) huffman++;
    else if (marker === 0xdd) need(length === 4);
    else if (marker === 0xda) {
      need(width && tables && huffman && bytes[offset + 2] === components && length === 6 + 2 * components);
      need(bytes[offset + length - 3] === 0 && bytes[offset + length - 2] === 63 && bytes[offset + length - 1] === 0);
      offset += length;
      let entropy = 0;
      while (offset < bytes.length) {
        if (bytes[offset++] !== 255) { entropy++; continue; }
        while (bytes[offset] === 255) offset++;
        need(offset < bytes.length);
        const next = bytes[offset++];
        if (next === 0) { entropy++; continue; }
        if (next >= 0xd0 && next <= 0xd7) continue;
        need(next === 0xd9 && offset === bytes.length && entropy > 0);
        return { width, height };
      }
      throw new ApiError(400, "invalid_photo_jpeg");
    }
    offset += length;
  }
  throw new ApiError(400, "invalid_photo_jpeg");
}

export async function checkPhoto(encoded: unknown, checksum: unknown): Promise<CheckedPhoto> {
  need(typeof encoded === "string" && encoded.length <= Math.ceil(MAX_PHOTO_BYTES / 3) * 4 && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded), "invalid_photo_encoding");
  need(typeof checksum === "string" && HASH_PATTERN.test(checksum), "invalid_photo_checksum");
  let binary: string;
  try { binary = atob(encoded); } catch { throw new ApiError(400, "invalid_photo_encoding"); }
  need(btoa(binary) === encoded, "invalid_photo_encoding");
  const bytes = Uint8Array.from(binary, value => value.charCodeAt(0)), frame = jpegFrame(bytes);
  const actual = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  need(actual === checksum, "photo_checksum_mismatch");
  try {
    const decoded = decode(bytes, { useTArray: true, formatAsRGBA: true, tolerantDecoding: false, maxResolutionInMP: 1, maxMemoryUsageInMB: 32 });
    need(decoded.width === frame.width && decoded.height === frame.height && decoded.data.length === frame.width * frame.height * 4);
  } catch { throw new ApiError(400, "invalid_photo_jpeg"); }
  return { jpeg_base64: encoded, sha256: actual, ...frame, byte_length: bytes.length };
}
