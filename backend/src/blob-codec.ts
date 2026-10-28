import { readBounded } from "./protocol";

/**
 * The one format for a stored or sent recording, checkpoint or replay body:
 * one encoding byte (0 raw, 1 deflate in zlib framing, which is what Godot's
 * COMPRESSION_DEFLATE reads and writes) and the payload. Its record keeps the
 * canonical byte length and the SHA-256 of the canonical bytes, so hashes
 * always cover the uncompressed bytes and a decode stops at the expected
 * length (a deflate bomb costs nothing). The game reads it with
 * game/services/blob_codec.gd.
 *
 * Room history (v2/history-blob.ts) and leaderboard replays
 * (leaderboards/board.ts) both use it; test/blob-format.test.ts keeps every
 * other stored or served body going through here.
 */
export const ENCODING_RAW = 0, ENCODING_DEFLATE = 1;

export async function bytesDigest(bytes: Uint8Array): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(b => b.toString(16).padStart(2, "0")).join("");
}

/** A corrupt deflate stream errors while it is read; that counts as no body. */
async function drain(stream: ReadableStream<Uint8Array>, limit: number): Promise<Uint8Array | null> {
  try { return await readBounded(stream, limit); } catch { return null; }
}
function through(bytes: Uint8Array, transform: CompressionStream | DecompressionStream): ReadableStream<Uint8Array> {
  const writer = transform.writable.getWriter();
  writer.write(bytes).then(() => writer.close()).catch(() => undefined);
  return transform.readable;
}

/** The tagged body for canonical `bytes`, deflated unless `encoding` says raw. */
export async function encodeBlob(bytes: Uint8Array, encoding = ENCODING_DEFLATE): Promise<Uint8Array> {
  const payload = encoding === ENCODING_RAW ? bytes : await drain(through(bytes, new CompressionStream("deflate")), Number.MAX_SAFE_INTEGER);
  const out = new Uint8Array(payload!.byteLength + 1); out[0] = encoding; out.set(payload!, 1);
  return out;
}

/** The canonical bytes, never more than `expectedLength` of them, or null when the body is not exactly that long. */
export async function decodeBlob(body: Uint8Array, expectedLength: number): Promise<Uint8Array | null> {
  if (body.byteLength < 1) return null;
  const payload = body.subarray(1);
  const bytes = body[0] === ENCODING_RAW ? (payload.byteLength <= expectedLength ? payload : null)
    : body[0] === ENCODING_DEFLATE ? await drain(through(payload, new DecompressionStream("deflate")), expectedLength) : null;
  return bytes && bytes.byteLength === expectedLength ? bytes : null;
}

/** A tagged body as standard base64, for a JSON answer. Built in chunks so a large body never overflows the call stack. */
export function blobBase64(body: Uint8Array): string {
  let binary = "";
  for (let start = 0; start < body.byteLength; start += 0x8000) binary += String.fromCharCode(...body.subarray(start, start + 0x8000));
  return btoa(binary);
}
