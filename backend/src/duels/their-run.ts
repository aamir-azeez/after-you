import { canonicalJson, fail, ok, type Outcome } from "../protocol";
import { bytesDigest, encodeBlob } from "../blob-codec";
import { DUEL_RUN_TABLES } from "../storage-schema";
import type { CheckpointV2 } from "../v2/protocol";
import { duelLink, recordDuelLink } from "./room-link";
import { STALL_MS } from "./rules";

/**
 * The other pair's copy of a friend duel's run, kept in the room it was played in.
 *
 * After a friend duel each pair may watch the other pair's run. The run's
 * bytes never leave the room that played it: in the commit that first
 * finishes the run (v2/room.ts, beside markDuelDone) the room copies its final
 * checkpoint here, with the other pair's two players (DuelLink.others) as the
 * players still to download it. A copy, because after that a redo moves the
 * room's checkpoint and the own pair's replay transfer (v2/replay-transfer.ts)
 * compacts its recordings; the own pair keeps that path, unchanged, and this
 * copy is only for the other pair. The final checkpoint nests every turn of
 * the finishing branch and holds no player or room id, as a board replay
 * (leaderboards/replays.ts).
 *
 * - Served in the shared blob format (blob-codec.ts): encoded once, right after
 *   the finishing commit or at the first download, whichever comes first.
 * - Acknowledged by each of the other pair once their phone has kept it; the
 *   copy goes when both have. A repeat, or an acknowledgement after the copy is
 *   gone, answers ok; one naming other bytes is refused.
 * - Gone at the latest THEIR_RUN_KEEP_MS after the duel ends: the board's
 *   hourly sweep (duels/store.ts run copies) tells the room, and a copy found
 *   past THEIR_RUN_FALLBACK_MS on a download goes then too. Erasure: an erased
 *   player leaves the waiting list, and a run they played in goes.
 *
 * One row at most per room, so no object grows with the number of players.
 */
export const THEIR_RUN_KEEP_MS = 90 * 86_400_000;
/** A duel ends at most STALL_MS after its last turn, so a copy this old is past its duel's end plus the keep in every case. */
export const THEIR_RUN_FALLBACK_MS = THEIR_RUN_KEEP_MS + STALL_MS;

/** `raw`: the canonical bytes sit unencoded in `body` until encodeTheirRun runs. */
type Row = { duel_id: string; finished_ms: number; pending: string[]; digest: string | null; byte_length: number | null; raw: boolean };
export type TheirRun = { duel_id: string; digest: string; byte_length: number; body: Uint8Array };

const [TABLE] = DUEL_RUN_TABLES;

function present(storage: DurableObjectStorage): boolean {
  return storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", TABLE.name).toArray().length > 0;
}
function read(storage: DurableObjectStorage): { row: Row; body: Uint8Array | null } | null {
  if (!present(storage)) return null;
  const found = storage.sql.exec<{ data: string; body: ArrayBuffer | null }>("SELECT data,body FROM duel_their_run WHERE id=1").toArray()[0];
  return found ? { row: JSON.parse(found.data) as Row, body: found.body ? new Uint8Array(found.body) : null } : null;
}
function write(storage: DurableObjectStorage, row: Row, body: Uint8Array | null): void {
  storage.sql.exec("INSERT OR REPLACE INTO duel_their_run VALUES (1,?,?)", JSON.stringify(row), body);
}
function remove(storage: DurableObjectStorage): void {
  if (present(storage)) storage.sql.exec("DELETE FROM duel_their_run");
}

/**
 * In the commit that first finishes a friend duel's run (before markDuelDone): copies the final
 * checkpoint for the other pair. True when a copy was made, so the caller encodes it after the commit.
 */
export function keepTheirRun(storage: DurableObjectStorage, checkpoint: CheckpointV2, now: number): boolean {
  const link = duelLink(storage);
  if (!link || link.kind !== "friend" || link.done || !link.others?.length || read(storage)) return false;
  // Never fails the turn: a copy that cannot be made is simply not there (the other pair reads it as gone).
  try {
    storage.sql.exec(TABLE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
    write(storage, { duel_id: link.duel_id, finished_ms: now, pending: [...link.others], digest: null, byte_length: null, raw: true }, new TextEncoder().encode(canonicalJson(checkpoint)));
    return true;
  } catch { return false; }
}

/** Encodes a raw copy into the blob format; a no-op once encoded or gone. Never throws. */
export async function encodeTheirRun(storage: DurableObjectStorage): Promise<void> {
  try {
    const held = read(storage);
    if (!held?.row.raw || !held.body) return;
    const bytes = held.body;
    const [digest, body] = [await bytesDigest(bytes), await encodeBlob(bytes)];
    storage.transactionSync(() => {
      const now = read(storage);
      // Only the copy this call read: an ack or a drop in between wins.
      if (!now?.row.raw || now.row.duel_id !== held.row.duel_id) return;
      write(storage, { ...now.row, raw: false, digest, byte_length: bytes.byteLength }, body);
    });
  } catch { /* The next download encodes it. */ }
}

/** The copy for `viewer`, one of the other pair, encoding it first if needed; 410 once it is gone. */
export async function serveTheirRun(storage: DurableObjectStorage, viewer: string, now: number): Promise<Outcome<TheirRun>> {
  const link = duelLink(storage);
  // A duel's room with no link left was erased with its run.
  if (!link) return fail(410, "their_run_gone");
  if (link.kind !== "friend") return fail(404, "their_run_not_found");
  let held = read(storage);
  // No copy held (taken by both, swept, or dropped at an erasure) reads as gone; the board already checked who asks.
  if (held && !link.others?.includes(viewer)) return fail(404, "their_run_not_found");
  if (held && now - held.row.finished_ms > THEIR_RUN_FALLBACK_MS) { storage.transactionSync(() => remove(storage)); held = null; }
  if (!held) return fail(410, "their_run_gone");
  if (held.row.raw) { await encodeTheirRun(storage); held = read(storage); }
  if (!held) return fail(410, "their_run_gone");
  // Still raw: the encode failed this time, and the next try may not.
  if (held.row.raw || !held.body || !held.row.digest || held.row.byte_length === null) return fail(503, "their_run_unavailable");
  return ok({ duel_id: held.row.duel_id, digest: held.row.digest, byte_length: held.row.byte_length, body: held.body });
}

/** `viewer`'s phone keeps the copy named by `digest`; the copy goes once the other pair both have. */
export function acknowledgeTheirRun(storage: DurableObjectStorage, viewer: string, digest: string): Outcome<{ kept: boolean }> {
  const link = duelLink(storage);
  if (!link || link.kind !== "friend" || !link.others?.includes(viewer)) return fail(404, "their_run_not_found");
  return storage.transactionSync(() => {
    const held = read(storage);
    if (!held) return ok({ kept: false });
    if (held.row.digest !== digest) return fail(409, "their_run_mismatch");
    const pending = held.row.pending.filter(id => id !== viewer);
    if (!pending.length) { remove(storage); return ok({ kept: false }); }
    if (pending.length !== held.row.pending.length) write(storage, { ...held.row, pending }, held.body);
    return ok({ kept: true });
  });
}

/**
 * The board's sweep (duels/store.ts), retry safe. With no `player`, the keep is over: the copy for
 * `duelId` goes, and the room forgets the other pair, so a run finished later is never copied. With
 * one, an erased player: they leave the room's list of the other pair and the copy's waiting list, and
 * the copy goes if they played the run.
 */
export function dropTheirRun(storage: DurableObjectStorage, duelId: string, player: string | null): boolean {
  return storage.transactionSync(() => {
    const link = duelLink(storage);
    if (!link || link.duel_id !== duelId) return false;
    if (player === null || link.others?.includes(player)) recordDuelLink(storage, { ...link, others: player === null ? [] : link.others!.filter(id => id !== player) });
    const held = read(storage);
    if (!held) return true;
    if (player === null || link.members.includes(player)) { remove(storage); return true; }
    const pending = held.row.pending.filter(id => id !== player);
    if (!pending.length) remove(storage);
    else if (pending.length !== held.row.pending.length) write(storage, { ...held.row, pending }, held.body);
    return true;
  });
}
