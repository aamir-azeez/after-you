import { Buffer } from "node:buffer";
import { ApiError } from "../protocol";

/**
 * Packed recordings: the one codec for a physical turn's inputs and replay checks (the Worker side of
 * game/core/v2/recording_codec.gd, which writes the same bytes).
 *
 * A packed recording keeps every header field of the JSON record (role, stage, hashes) and swaps `actions` and
 * `replay_checks` for one `packed` string: the standard base64 (padded) of
 *   - FORMAT (one byte);
 *   - the run count as a varint, then each run as varint(ticks * 2 + action), stick x and stick z (one signed byte
 *     each, the same integers as the JSON runs, -100..100);
 *   - the replay checks, whose ticks are implied (every CHECK_EVERY ticks before the end, then the end): each the
 *     first SHORT_HASH_BYTES of its state hash, or all FULL_HASH_BYTES where the tick is a multiple of
 *     FULL_CHECK_EVERY. The check at the end is the record's own final_state_hash and is not repeated.
 * Exactly one byte string means each record: varints are minimal, adjacent runs differ, nothing trails, and the base64
 * is the canonical encoding. recording_hash stays the SHA-256 of the record's canonical JSON without it, so a packed
 * record's hash covers these bytes. A room takes packed turns only once both members read them (v2/packed-rooms.ts).
 */
export const PACKED_KEY = "packed";
/** The longest `packed` string any turn needs (9,000 ticks, a new stick every tick), with room to spare. */
export const MAX_PACKED_CHARS = 128 * 1024;
export const FORMAT = 1;
export const CHECK_EVERY = 30, FULL_CHECK_EVERY = 150, SHORT_HASH_BYTES = 8, FULL_HASH_BYTES = 32;
export type Run = { ticks: number; x: number; z: number; action: boolean };
/** A replay check as a packed record reads back: a short state hash (16 hex) or a full one (64 hex). */
export type Check = { tick: number; state_hash: string };

export function isPacked(record: object): boolean { return Object.hasOwn(record, PACKED_KEY); }
/** The packed form's keys for a record family's JSON keys. */
export function packedKeys(keys: readonly string[]): string[] { return [...keys.filter(key => key !== "actions" && key !== "replay_checks"), PACKED_KEY]; }

/** The replay check ticks of a turn `duration` ticks long. */
export function checkTicks(duration: number): number[] {
  const ticks: number[] = [];
  for (let tick = CHECK_EVERY; tick < duration; tick += CHECK_EVERY) ticks.push(tick);
  ticks.push(duration);
  return ticks;
}
/** How many bytes of the state hash the check at `tick` keeps (none at the end: that is final_state_hash). */
export function checkBytes(tick: number, duration: number): number {
  return tick === duration ? 0 : tick % FULL_CHECK_EVERY === 0 ? FULL_HASH_BYTES : SHORT_HASH_BYTES;
}

const HEX = Array.from({ length: 256 }, (_, byte) => byte.toString(16).padStart(2, "0"));
function invalid(): never { throw new ApiError(422, "invalid_packed_recording"); }
function varint(out: number[], value: number): void {
  while (value >= 0x80) { out.push((value & 0x7f) | 0x80); value = Math.floor(value / 128); }
  out.push(value);
}

/** The `packed` string for runs and checks (full or already short hashes); checks must sit on checkTicks(duration). */
export function packRecording(actions: readonly Run[], checks: readonly Check[], duration: number): string {
  const out: number[] = [FORMAT];
  varint(out, actions.length);
  for (const run of actions) { varint(out, run.ticks * 2 + (run.action ? 1 : 0)); out.push(run.x & 0xff, run.z & 0xff); }
  const ticks = checkTicks(duration);
  if (checks.length !== ticks.length) invalid();
  checks.forEach((check, index) => {
    if (check.tick !== ticks[index]) invalid();
    const bytes = checkBytes(check.tick, duration);
    for (let index = 0; index < bytes; index++) {
      const byte = parseInt(check.state_hash.slice(index * 2, index * 2 + 2), 16);
      if (!(byte >= 0)) invalid();
      out.push(byte);
    }
  });
  return Buffer.from(Uint8Array.from(out)).toString("base64");
}

/**
 * The runs and checks a `packed` string holds, for a turn of `duration` ticks ending on `finalHash`, with at most
 * `maxRuns` runs. Anything but the one canonical encoding is refused (422 invalid_packed_recording).
 */
export function unpackRecording(packed: unknown, duration: number, finalHash: string, maxRuns: number): { actions: Run[]; replay_checks: Check[] } {
  if (typeof packed !== "string" || packed.length > 4 * Math.ceil((1 + 5 + maxRuns * 7 + checkTicks(duration).length * FULL_HASH_BYTES) / 3)) invalid();
  const bytes = Buffer.from(packed, "base64");
  if (bytes.toString("base64") !== packed) invalid();
  let at = 0;
  const read = (): number => {
    let value = 0, scale = 1;
    for (let length = 0; length < 5; length++) {
      if (at >= bytes.byteLength) invalid();
      const byte = bytes[at++];
      value += (byte & 0x7f) * scale;
      if (byte < 0x80) { if (length > 0 && byte === 0) invalid(); return value; }
      scale *= 128;
    }
    return invalid();
  };
  const signed = (): number => {
    if (at >= bytes.byteLength) invalid();
    const byte = bytes[at++], value = byte > 127 ? byte - 256 : byte;
    if (value < -100 || value > 100) invalid();
    return value;
  };
  if (bytes[at++] !== FORMAT) invalid();
  const count = read();
  if (count < 1 || count > maxRuns) invalid();
  const actions: Run[] = [];
  let total = 0;
  for (let index = 0; index < count; index++) {
    const head = read(), ticks = Math.floor(head / 2), run = { ticks, x: signed(), z: signed(), action: head % 2 === 1 };
    const last = actions.at(-1);
    if (ticks < 1 || (last && last.x === run.x && last.z === run.z && last.action === run.action)) invalid();
    total += ticks;
    if (total > duration) invalid();
    actions.push(run);
  }
  if (total !== duration) invalid();
  const replay_checks = checkTicks(duration).map(tick => {
    const size = checkBytes(tick, duration);
    if (!size) return { tick, state_hash: finalHash };
    if (at + size > bytes.byteLength) invalid();
    let state_hash = "";
    for (let index = at; index < at + size; index++) state_hash += HEX[bytes[index]];
    at += size;
    return { tick, state_hash };
  });
  if (at !== bytes.byteLength) invalid();
  return { actions, replay_checks };
}
