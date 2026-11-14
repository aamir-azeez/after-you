import { ApiError, object, readBounded } from "../protocol";
import { bytesDigest, decodeBlob, encodeBlob } from "../blob-codec";
import { flags, type ServerVars } from "../flags";
import { JSON_HEADERS } from "../http";
import { maskedReply, preparedReply } from "../duels/public-mask";
import { CHAPTERS } from "./chapters";
import { MAX_V2_BODY_BYTES, exact } from "./protocol";
import { triesField } from "./turn-tries";
import { endReactionField } from "./end-reactions";
import { runReactionField } from "./run-reactions";

/**
 * Turns and room replies as the Worker passes them through, unread (compressed rooms, flags.ts COMPRESSED_ROOMS).
 *
 * A turn body reaches the room as the bytes the phone sent. An older app sends the turn as JSON, which goes on as
 * it came. A newer one, once the capabilities said `compressed_rooms_version: 1`, sends the same JSON as a tagged
 * blob (blob-codec.ts, deflated) with BODY_LENGTH and BODY_DIGEST, the byte length and SHA-256 of the JSON inside.
 * The room (v2/room.ts turnRequest) inflates, checks and parses it; the idempotency key's request hash covers the
 * parsed JSON, never the bytes, so a turn sent once each way is the same request.
 *
 * Room reads, turn replies, operation reads and pair reads are written by the room too. A phone that sends
 * COMPRESSED_HEADER gets the reply's JSON as a tagged blob with the same two headers (and a turn's Pollen credit in
 * POLLEN_HEADER); any other gets the JSON text, byte for byte what the Worker wrote before. Errors stay JSON.
 */
export const COMPRESSED_HEADER = "X-AfterYou-Compressed";
export const BODY_LENGTH_HEADER = "X-AfterYou-Body-Length";
export const BODY_DIGEST_HEADER = "X-AfterYou-Body-Digest";
export const POLLEN_HEADER = "X-AfterYou-Pollen";
const BLOB_TYPE = "application/octet-stream";
/** The widest turn any chapter takes; the room checks its own chapter's bound before it reads a byte. */
export const MAX_TURN_BODY_BYTES = Math.max(MAX_V2_BODY_BYTES, ...CHAPTERS.map(row => row.adapter.limits?.turn_body_bytes ?? 0));

/** A turn as the phone sent it: JSON bytes (`length` null), or a tagged blob of `length` JSON bytes whose SHA-256 is `digest`. */
export type TurnBody = { bytes: Uint8Array; length: number | null; digest: string | null };
/** A reply the room wrote: JSON text, or the tagged blob of that JSON with its length and SHA-256. */
export type RoomReply = { text: string } | { body: Uint8Array; length: number; digest: string };

/** The capability field, for a phone that asks while compressed rooms are on. */
export function compressedCapability(request: Request, env: ServerVars): { compressed_rooms_version?: 1 } {
  return compressedAsked(request) && flags.compressedRooms(env) ? { compressed_rooms_version: 1 } : {};
}
/** Whether the phone reads compressed replies. */
export function compressedAsked(request: Request): boolean { return request.headers.get(COMPRESSED_HEADER) === "1"; }

/**
 * The turn's bytes, unread (Worker side). JSON keeps boundedJson's answers: 415 json_required, 413 body_too_large
 * and 400 body_required; the room answers 400 invalid_json. A blob needs both headers and a length the widest chapter allows.
 */
export async function readTurnBody(request: Request): Promise<TurnBody> {
  const type = request.headers.get("content-type")?.toLowerCase() ?? "";
  const blob = type === BLOB_TYPE;
  if (!blob && !type.startsWith("application/json")) throw new ApiError(415, "json_required");
  let length: number | null = null, digest: string | null = null;
  if (blob) {
    const declared = request.headers.get(BODY_LENGTH_HEADER) ?? "", hash = request.headers.get(BODY_DIGEST_HEADER) ?? "";
    if (!/^[1-9][0-9]{0,9}$/.test(declared) || !/^[a-f0-9]{64}$/.test(hash)) throw new ApiError(400, "invalid_turn_body");
    length = Number(declared); digest = hash;
    if (length > MAX_TURN_BODY_BYTES) throw new ApiError(413, "body_too_large");
  }
  if (Number(request.headers.get("content-length")) > MAX_TURN_BODY_BYTES + 1) throw new ApiError(413, "body_too_large");
  if (!request.body) throw new ApiError(400, "body_required");
  const bytes = await readBounded(request.body, MAX_TURN_BODY_BYTES + 1);
  if (!bytes || (!blob && bytes.byteLength > MAX_TURN_BODY_BYTES)) throw new ApiError(413, "body_too_large");
  return { bytes, length, digest };
}

/** The turn's JSON value (room side), once its size is inside `max`, the room's own chapter bound. */
export async function decodeTurnBody(body: TurnBody, max: number): Promise<unknown> {
  if ((body.length ?? body.bytes.byteLength) > max) throw new ApiError(413, "body_too_large");
  let bytes = body.bytes;
  if (body.length !== null) {
    const decoded = await decodeBlob(body.bytes, body.length);
    if (!decoded || await bytesDigest(decoded) !== body.digest) throw new ApiError(400, "invalid_turn_body");
    bytes = decoded;
  }
  try { return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes)); }
  catch { throw new ApiError(400, "invalid_json"); }
}

/** A reply's JSON as `viewer` may see it (public duel masks, duels/public-mask.ts), as text or deflated. */
export async function encodeReply(value: Record<string, unknown>, viewer: string, compressed: boolean): Promise<RoomReply> {
  const text = JSON.stringify(maskedReply(value, viewer));
  if (!compressed) return { text };
  const bytes = new TextEncoder().encode(text);
  return { body: await encodeBlob(bytes), length: bytes.byteLength, digest: await bytesDigest(bytes) };
}

/**
 * The answer for a room's reply (Worker side). `pollen`: a turn's credit, last in the JSON text as before
 * (creditCommitted), or in POLLEN_HEADER beside a blob. Masks were applied in the room, so maskedResponse leaves it.
 */
export function replyResponse(reply: RoomReply, pollen?: unknown): Response {
  if ("text" in reply) {
    const text = pollen === undefined ? reply.text : reply.text.slice(0, -1) + ',"pollen":' + JSON.stringify(pollen) + "}";
    return preparedReply(new Response(text, { headers: JSON_HEADERS }));
  }
  return preparedReply(new Response(reply.body, { headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": BLOB_TYPE,
    [BODY_LENGTH_HEADER]: String(reply.length), [BODY_DIGEST_HEADER]: reply.digest, ...(pollen === undefined ? {} : { [POLLEN_HEADER]: asciiJson(pollen) }) } }));
}
/** JSON with every character past ASCII escaped, as a header value must be. */
function asciiJson(value: unknown): string {
  return JSON.stringify(value).replace(/[\u007f-\uffff]/g, char => "\\u" + char.charCodeAt(0).toString(16).padStart(4, "0"));
}
/** A turn body's exact fields, the one list the route (Story turns), the room's premium check and its commit share. */
export function exactTurnFields(value: Record<string, unknown>): void {
  exact(value, ["base_revision", "idempotency_key", "branch", "recording", ...(object(value.recording).role === "b" ? ["checkpoint"] : []), ...triesField(value), ...endReactionField(value), ...runReactionField(value)]);
}
