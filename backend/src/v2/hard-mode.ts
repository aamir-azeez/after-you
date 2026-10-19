import { ApiError, IDEMPOTENCY_PATTERN, integer, object, text } from "../protocol";
import { exact } from "./protocol-relay";

/**
 * Hard rooms: a chapter played whole by two friends with no retries. The phone
 * that slips (a turn started twice, a turn that cannot be kept, a drowning)
 * sends one reset; the room goes back to its first stage for both, and keeps a
 * short record of the slip so both phones can say who slipped and watch it.
 * The room never runs physics: the slip is a recording kept for replays only,
 * never a turn, a draft or a checkpoint.
 *
 * Storage follows turn_tries: two tables created only by a hard room's
 * creation, so every other room's storage and every view of it is unchanged.
 * - hard_run (one row): the run's summary, as the room view shows it.
 * - hard_failures: the newest MAX_KEPT slips, each with the reset request that
 *   recorded it (idempotency key and hash), so a resend answers the same.
 * Operator snapshots leave both out (like turn_tries); the full room erase and
 * a restore drop them.
 */
export const HARD_RUN = {
  name: "hard_run",
  schema: "CREATE TABLE hard_run (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)"
} as const;
export const HARD_FAILURES = {
  name: "hard_failures",
  schema: "CREATE TABLE hard_failures (seq INTEGER PRIMARY KEY, request_key TEXT NOT NULL UNIQUE, request_hash TEXT NOT NULL, data TEXT NOT NULL)"
} as const;
/** Sent on GET /v2/capabilities and on a join by clients that play hard rooms. */
export const HARD_MODE_HEADER = "X-AfterYou-Hard-Mode";
/** Slips a room keeps with their recordings. */
export const MAX_KEPT = 5;
export const REASONS = ["retry", "failed_turn", "drowned"] as const;
export type Reason = typeof REASONS[number];
/** Who slipped, where and how, as a view shows the last one. */
export type Failure = { by: string; stage_index: number; role: "a" | "b"; reason: Reason; at: string };
/** A kept slip: the turn's recording, the checkpoint it was played from and its first turn (role b). */
export type Slip = { recording: unknown; checkpoint: unknown; prior: unknown | null };
export type HardRun = { schema_version: 1; failures: number; over: boolean; last: Failure | null };
/** A kept slip as read: its number among the room's slips (1 for the first), who slipped and the slip. */
export type KeptFailure = Failure & { number: number; slip: Slip | null };
export type HardFailures = { schema_version: 1; failures: number; list: KeptFailure[] };
/** Bytes of slips one read returns; older slips past it come without their recording. */
export const READ_SLIP_BYTES = 3_000_000;
export type ResetInput = { base_revision: number; branch: number; idempotency_key: string; reason: Reason; stage_index: number; role: "a" | "b"; slip?: Record<string, unknown> };

export function hardWanted(request: Request): boolean { return request.headers.get(HARD_MODE_HEADER) === "1"; }

/** The create body's optional mode: undefined, or "hard". */
export function parseMode(body: Record<string, unknown>): "hard" | undefined {
  if (body.mode === undefined) return undefined;
  if (body.mode !== "hard") throw new ApiError(422, "unsupported_room_mode");
  return "hard";
}

/** GET .../hard/<n>: how many of the room's slips a phone has already seen (0 when absent). */
export function parseSince(item: string | undefined): number {
  if (item === undefined) return 0;
  if (!/^[0-9]{1,9}$/.test(item)) throw new ApiError(422, "invalid_since");
  return Number(item);
}

export function parseReset(value: unknown, stages: number): ResetInput {
  const input = object(value);
  exact(input, ["base_revision", "branch", "idempotency_key", "reason", "stage_index", "role", ...(input.slip === undefined ? [] : ["slip"])]);
  if (!REASONS.includes(input.reason as Reason)) throw new ApiError(422, "invalid_reason");
  if (input.role !== "a" && input.role !== "b") throw new ApiError(422, "invalid_role");
  return { base_revision: integer(input.base_revision, 0, Number.MAX_SAFE_INTEGER), branch: integer(input.branch, 0, 31),
    idempotency_key: text(input.idempotency_key, IDEMPOTENCY_PATTERN), reason: input.reason as Reason,
    stage_index: integer(input.stage_index, 0, Math.max(0, stages - 1)), role: input.role,
    ...(input.slip === undefined ? {} : { slip: object(input.slip) }) };
}

/** Its own query text, so row meters can tell it from other features' table lookups. */
export const HARD_LOOKUP = "SELECT name FROM sqlite_master WHERE type='table' AND name='hard_run'";
function present(storage: DurableObjectStorage): boolean {
  return storage.sql.exec(HARD_LOOKUP).toArray().length > 0;
}

/** Remembers, per room object, whether it is a hard room, so a view reads the table list at most once. */
export class HardMemo {
  private known: boolean | undefined;
  run(storage: DurableObjectStorage): HardRun | null {
    if (this.known === false) return null;
    if (this.known === undefined) { this.known = present(storage); if (!this.known) return null; }
    const row = storage.sql.exec<{ data: string }>("SELECT data FROM hard_run WHERE id=1").toArray()[0];
    return row ? JSON.parse(row.data) as HardRun : null;
  }
  forget(): void { this.known = undefined; }
}

/** A new hard room; the caller owns the transaction that creates the room row. */
export function initializeHard(storage: DurableObjectStorage, memo: HardMemo): void {
  storage.sql.exec(HARD_RUN.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec(HARD_FAILURES.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  const run: HardRun = { schema_version: 1, failures: 0, over: false, last: null };
  storage.sql.exec("INSERT OR IGNORE INTO hard_run VALUES (1,?)", JSON.stringify(run));
  memo.forget();
}

/** The answer a reset already made for this request, or null; a key reused with another body is refused. */
export function priorReset(storage: DurableObjectStorage, player: string, key: string, hash: string): Failure | null {
  const row = storage.sql.exec<{ request_hash: string; data: string }>("SELECT request_hash,data FROM hard_failures WHERE request_key=?", player + ":" + key).toArray()[0];
  if (!row) return null;
  if (row.request_hash !== hash) throw new ApiError(409, "idempotency_key_reused");
  const { slip: _slip, ...failure } = JSON.parse(row.data) as Failure & { slip: Slip | null }; void _slip;
  return failure;
}

/** Records a slip; keeps only the newest MAX_KEPT. The caller owns the transaction. */
export function recordFailure(storage: DurableObjectStorage, memo: HardMemo, player: string, key: string, hash: string, failure: Failure, slip: Slip | null, over: boolean): HardRun {
  const current = memo.run(storage);
  if (!current) throw new ApiError(409, "not_hard_room");
  storage.sql.exec("INSERT INTO hard_failures (request_key,request_hash,data) VALUES (?,?,?)", player + ":" + key, hash, JSON.stringify({ ...failure, slip }));
  storage.sql.exec("DELETE FROM hard_failures WHERE seq NOT IN (SELECT seq FROM hard_failures ORDER BY seq DESC LIMIT ?)", MAX_KEPT);
  const next: HardRun = { schema_version: 1, failures: current.failures + 1, over: current.over || over, last: failure };
  storage.sql.exec("UPDATE hard_run SET data=? WHERE id=1", JSON.stringify(next));
  return next;
}

/**
 * The kept slips after the `since`th, oldest first, with the total ever made.
 * A row's seq is its slip's number: each reset inserts one row and counts one
 * failure, and rows are only ever pruned from the oldest end. A phone asks
 * for what it has not seen, normally one slip; the newest slips keep their
 * recordings up to READ_SLIP_BYTES, so a read always fits a phone's answer.
 */
export function failuresView(storage: DurableObjectStorage, memo: HardMemo, since = 0): HardFailures | null {
  const run = memo.run(storage);
  if (!run) return null;
  const rows = storage.sql.exec<{ seq: number; data: string }>("SELECT seq,data FROM hard_failures WHERE seq>? ORDER BY seq DESC LIMIT ?", since, MAX_KEPT).toArray();
  let bytes = 0;
  const list = rows.map(row => {
    bytes += row.data.length;
    const item = JSON.parse(row.data) as Failure & { slip: Slip | null };
    return { ...item, number: row.seq, slip: bytes > READ_SLIP_BYTES ? null : item.slip };
  }).reverse();
  return { schema_version: 1, failures: run.failures, list };
}

/** For the full room erase and a snapshot restore. */
export function clearHard(storage: DurableObjectStorage, memo?: HardMemo): void {
  storage.sql.exec("DROP TABLE IF EXISTS hard_failures");
  storage.sql.exec("DROP TABLE IF EXISTS hard_run");
  memo?.forget();
}

/** The tables as sqlite_master lists them, so snapshot schema checks can let them pass. */
export function isHardTable(row: { name: string; sql: string }): boolean {
  return (row.name === HARD_RUN.name && row.sql === HARD_RUN.schema) || (row.name === HARD_FAILURES.name && row.sql === HARD_FAILURES.schema);
}
