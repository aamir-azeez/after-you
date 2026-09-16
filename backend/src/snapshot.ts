import { canonicalJson, digest, fail, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, isObject, LEVEL_IDS, ok, recording, type Outcome } from "./protocol";
import { validTesterGrant } from "./tester-access";
import { TABLES, type ObjectKind } from "./storage-schema";
import { validRoomLink } from "./room-links";
import { validChapterCreation } from "./v2/creation-intent";
import { isAlarmMetadataTable, notificationAlarmOwned, notificationTables, resetNotificationRuntime } from "./notification-storage";

export const MAX_SNAPSHOT_BYTES = 24 * 1024 * 1024;
export const MAX_SNAPSHOT_ROW_BYTES = 256 * 1024;
type Row = Record<string, string | number>;
type Table = { name: string; schema: string; columns: string[]; rows: Row[] };
type Summary = { state: "empty" | "active" | "deleting" | "deleted"; revision: number | null; attempt: number | null };
export type SnapshotPayload = {
  format: "after-you-object-snapshot"; format_version: 1 | 2 | 3 | 4; database_schema_version: 1;
  object_kind: ObjectKind; logical_id: string | null; source_object_id: string;
  source_commit: string; exported_at: string; summary: Summary; tables: Table[];
};
export type PortableSnapshot = { payload: SnapshotPayload; checksum: { algorithm: "SHA-256"; value: string } };

/** Deliberately carries no row values, identifiers or secret hashes in the message. */
export class SnapshotError extends Error {
  constructor(code: string) { super(code); this.name = "SnapshotError"; }
}
/** Keep expected maintenance rejections bounded at the RPC boundary. */
export async function snapshotResult<T>(operation: () => Promise<T>): Promise<Outcome<T>> {
  try { return ok(await operation()); }
  catch (error) {
    if (error instanceof SnapshotError) return fail(error.message === "snapshot_target_not_empty" ? 409 : 400, error.message);
    return fail(500, "snapshot_storage_error");
  }
}
function requireValue(condition: unknown, code = "invalid_snapshot"): asserts condition {
  if (!condition) throw new SnapshotError(code);
}
function record(value: unknown, keys: readonly string[]): Record<string, unknown> {
  requireValue(isObject(value));
  const actual = Object.keys(value);
  requireValue(actual.length === keys.length && keys.every(key => Object.hasOwn(value, key)));
  return value;
}
function validText(value: unknown, pattern: RegExp): value is string { return typeof value === "string" && pattern.test(value); }
function safeInteger(value: unknown, min = 0): value is number { return typeof value === "number" && Number.isSafeInteger(value) && value >= min; }
function date(value: unknown): void {
  requireValue(validText(value, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value);
}
function uniqueJsonKeys(serialized: string): void {
  // JSON.parse validates syntax but silently discards duplicate object keys.
  // Scan its bounded input separately, without rewriting stored JSON text.
  const stack: { keys: Set<string> | null; expectingKey: boolean }[] = [];
  for (const match of serialized.matchAll(/"(?:\\.|[^"\\])*"|[{}\[\],:]/g)) {
    const token = match[0], frame = stack.at(-1);
    if (token === "{" || token === "[") {
      requireValue(stack.length < 16, "snapshot_json_depth");
      stack.push({ keys: token === "{" ? new Set() : null, expectingKey: token === "{" });
    } else if (token === "}" || token === "]") stack.pop();
    else if (token === "," && frame?.keys) frame.expectingKey = true;
    else if (token.startsWith('"') && frame?.keys && frame.expectingKey) {
      const key: string = JSON.parse(token);
      requireValue(!frame.keys.has(key), "snapshot_duplicate_json_key");
      frame.keys.add(key); frame.expectingKey = false;
    }
  }
}
function jsonData(value: unknown): Record<string, unknown> {
  requireValue(typeof value === "string" && value.length <= MAX_SNAPSHOT_ROW_BYTES && new TextEncoder().encode(value).byteLength <= MAX_SNAPSHOT_ROW_BYTES, "snapshot_row_too_large");
  let parsed: unknown;
  try { parsed = JSON.parse(value); } catch { throw new SnapshotError("invalid_snapshot_json"); }
  uniqueJsonKeys(value);
  requireValue(isObject(parsed), "invalid_snapshot_json");
  return parsed;
}
function link(value: Record<string, unknown>, formatVersion: 1 | 2 | 3 | 4): void {
  if (Object.hasOwn(value, "api_version")) requireValue(formatVersion >= 2, "unsupported_snapshot_format");
  requireValue(validRoomLink(value));
}
function identity(value: Record<string, unknown>, formatVersion: number): void {
  record(value, ["player_id", "device_hash", "recovery_hash", "state", "created_at", ...(Object.hasOwn(value, "recovery_receipt") ? ["recovery_receipt"] : []), ...(Object.hasOwn(value, "tester_grant") ? ["tester_grant"] : [])]);
  requireValue(validText(value.player_id, ID_PATTERN) && validText(value.device_hash, HASH_PATTERN) && validText(value.recovery_hash, HASH_PATTERN));
  requireValue(value.state === "active" || value.state === "deleting"); date(value.created_at);
  if (Object.hasOwn(value, "tester_grant")) requireValue(formatVersion === 4 && validTesterGrant(value.tester_grant), "unsupported_tester_grant");
  if (value.recovery_receipt !== undefined) {
    const receipt = record(value.recovery_receipt, ["previous_recovery_hash", "request_hash"]);
    requireValue(validText(receipt.previous_recovery_hash, HASH_PATTERN) && validText(receipt.request_hash, HASH_PATTERN));
  }
}
function room(value: Record<string, unknown>): void {
  record(value, ["schema_version", "room_id", "revision", "attempt", "host_id", "guest_id", "level_index", "level_id", "first_player_id", "active_role", "recordings", "completed_islands", "created_at", "updated_at", "invite_code", "invite_expires_at", "reactions"]);
  requireValue(value.schema_version === 1 && validText(value.room_id, ID_PATTERN) && safeInteger(value.revision) && safeInteger(value.attempt));
  requireValue(validText(value.host_id, ID_PATTERN) && (value.guest_id === null || validText(value.guest_id, ID_PATTERN)) && value.host_id !== value.guest_id);
  requireValue(safeInteger(value.level_index) && LEVEL_IDS[value.level_index] === value.level_id);
  requireValue(value.first_player_id === (value.level_index % 2 === 0 ? value.host_id : value.guest_id) && value.first_player_id !== null);
  requireValue(value.active_role === "a" || value.active_role === "b" || value.active_role === "complete");
  requireValue(validText(value.invite_code, /^[A-F0-9]{20}$/));
  date(value.created_at); date(value.updated_at); date(value.invite_expires_at);
  requireValue(Array.isArray(value.completed_islands) && value.completed_islands.length <= 8 && new Set(value.completed_islands).size === value.completed_islands.length);
  for (const level of value.completed_islands) requireValue((LEVEL_IDS as readonly unknown[]).includes(level));
  const recordings = record(value.recordings, ["a", "b"]);
  for (const role of ["a", "b"] as const) {
    const raw = recordings[role];
    if (raw !== null) {
      try {
        const parsed = recording(raw);
        requireValue(parsed.level_id === value.level_id && parsed.role === role);
        requireValue(role === "a" ? parsed.outcome.threw_seed && !parsed.completed && !parsed.source_recording_hash : parsed.completed && parsed.outcome.caught_seed && parsed.outcome.planted_seed);
      } catch { throw new SnapshotError("invalid_snapshot_recording"); }
    }
  }
  requireValue(value.active_role === "a" ? recordings.a === null && recordings.b === null : recordings.a !== null && (value.active_role === "b" ? recordings.b === null : recordings.b !== null));
  if (isObject(recordings.b) && isObject(recordings.a)) requireValue(recordings.b.source_recording_hash === recordings.a.final_state_hash);
  if (value.active_role === "complete") requireValue(value.completed_islands.includes(value.level_id));
  requireValue(isObject(value.reactions) && Object.keys(value.reactions).length <= 2);
  for (const [player, reaction] of Object.entries(value.reactions)) requireValue((player === value.host_id || player === value.guest_id) && typeof reaction === "string" && ["love", "sparkles", "again"].includes(reaction));
}

function rowId(value: unknown): bigint {
  requireValue(validText(value, /^(0|-?[1-9]\d{0,18})$/));
  const id = BigInt(value);
  requireValue(id >= -9223372036854775808n && id <= 9223372036854775807n);
  return id;
}

/** Validate every table/column before issuing any INSERT. Keep raw JSON untouched. */
function tables(input: unknown, kind: ObjectKind, formatVersion: 1 | 2 | 3 | 4 = 4): { tables: Table[]; logicalId: string | null; summary: Summary; versionedLinks: boolean; chapterCreations: boolean; testerGrant: boolean } {
  requireValue(Array.isArray(input) && input.length === TABLES[kind].length);
  const result: Table[] = [];
  const parsed = new Map<string, Record<string, unknown>[]>();
  let versionedLinks = false, chapterCreations = false, testerGrant = false;
  for (const [index, definition] of TABLES[kind].entries()) {
    const table = record(input[index], ["name", "schema", "columns", "rows"]);
    requireValue(table.name === definition.name && table.schema === definition.schema && Array.isArray(table.columns) && table.columns.length === definition.columns.length && table.columns.every((column, i) => column === definition.columns[i]), "unsupported_snapshot_schema");
    requireValue(Array.isArray(table.rows) && table.rows.length <= definition.maxRows, "snapshot_row_limit");
    const keys = new Set<string | number>(); let previous: bigint | null = null;
    const rows: Row[] = [], data: Record<string, unknown>[] = [];
    for (const raw of table.rows) {
      const row = record(raw, definition.columns), id = rowId(row.rowid);
      requireValue(previous === null || id > previous, "snapshot_row_order"); previous = id;
      const primary = row[definition.columns[1]];
      requireValue(typeof primary === "string" || typeof primary === "number");
      requireValue(!keys.has(primary), "snapshot_duplicate_key"); keys.add(primary);
      if (definition.name === "identity" || definition.name === "room") requireValue(row.id === 1 && row.rowid === "1");
      if (definition.name === "archive") requireValue(safeInteger(row.attempt) && row.rowid === String(row.attempt));
      if (definition.name === "rooms") requireValue(validText(row.room_id, ID_PATTERN));
      if (definition.name === "creations") requireValue(validText(row.request_key, IDEMPOTENCY_PATTERN));
      if (definition.name === "operations") requireValue(validText(row.request_key, /^[a-zA-Z0-9_-]{22}:[a-zA-Z0-9_-]{16,80}$/) && validText(row.request_hash, HASH_PATTERN) && safeInteger(row.revision, 1));
      if (row.data !== undefined) {
        const value = jsonData(row.data); data.push(value);
        if (definition.name === "identity") { identity(value, formatVersion); testerGrant ||= Object.hasOwn(value, "tester_grant"); }
        else if (definition.name === "creations" && Object.hasOwn(value, "creation_schema")) {
          requireValue(formatVersion >= 3, "unsupported_snapshot_format");
          requireValue(validChapterCreation(value)); chapterCreations = true;
        } else if (definition.name === "rooms" || definition.name === "creations") {
          link(value, formatVersion); if (definition.name === "rooms") requireValue(value.room_id === row.room_id);
          versionedLinks ||= Object.hasOwn(value, "api_version");
        } else if (definition.name === "room" && value.deleted === true) record(value, ["deleted"]);
        else {
          room(value); if (definition.name === "archive") requireValue(row.attempt === value.attempt);
        }
      }
      const validated: Row = {};
      for (const column of definition.columns) {
        const value = row[column]; requireValue(typeof value === "number" || typeof value === "string"); validated[column] = value;
      }
      rows.push(validated);
    }
    result.push({ name: definition.name, schema: definition.schema, columns: [...definition.columns], rows });
    parsed.set(definition.name, data);
  }
  const head = parsed.get(kind === "Player" ? "identity" : "room")![0];
  if (!head || head.deleted === true) {
    requireValue(result.slice(1).every(table => table.rows.length === 0), "snapshot_orphan_rows");
    return { tables: result, logicalId: null, summary: { state: head ? "deleted" : "empty", revision: null, attempt: null }, versionedLinks, chapterCreations, testerGrant };
  }
  if (kind === "Player") return { tables: result, logicalId: String(head.player_id), summary: { state: head.state as "active" | "deleting", revision: null, attempt: null }, versionedLinks, chapterCreations, testerGrant };
  let complete = 0, incomplete = 0;
  for (const archived of parsed.get("archive")!) {
    requireValue(archived.room_id === head.room_id && archived.host_id === head.host_id && Number(archived.attempt) < Number(head.attempt) && Number(archived.revision) <= Number(head.revision));
    if (archived.active_role === "complete") complete++; else incomplete++;
  }
  requireValue(complete <= 64 && incomplete <= 24, "snapshot_row_limit");
  for (const operation of result[1].rows) {
    requireValue(Number(operation.revision) <= Number(head.revision));
    const actor = String(operation.request_key).split(":")[0]; requireValue(actor === head.host_id || actor === head.guest_id);
  }
  return { tables: result, logicalId: String(head.room_id), summary: { state: "active", revision: Number(head.revision), attempt: Number(head.attempt) }, versionedLinks, chapterCreations, testerGrant };
}

function currentSchema(storage: DurableObjectStorage, kind: ObjectKind): void {
  // Internal SQLite autoindices have null SQL. Any application-defined extra
  // table, index, view or trigger requires review. Only the named ephemeral
  // notification tables are excluded; all gameplay rows retain their old format.
  const found = storage.sql.exec<{ name: string; sql: string }>("SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name != '_cf_KV' ORDER BY name").toArray().filter(row => !isAlarmMetadataTable(row));
  const expected = [...TABLES[kind], ...notificationTables(kind)].sort((a, b) => a.name.localeCompare(b.name));
  requireValue(found.length === expected.length && found.every((row, i) => row.name === expected[i].name && row.sql === expected[i].schema), "unsupported_storage_schema");
  requireValue([...storage.kv.list({ limit: 1 })].length === 0, "unsupported_storage_kv");
}

function bounded(value: string): void {
  requireValue(value.length <= MAX_SNAPSHOT_BYTES && new TextEncoder().encode(value).byteLength <= MAX_SNAPSHOT_BYTES, "snapshot_too_large");
}

export async function exportSnapshot(ctx: DurableObjectState, kind: ObjectKind, sourceCommit: string): Promise<string> {
  requireValue(validText(sourceCommit, /^[a-f0-9]{40}$/), "invalid_source_commit");
  // Storage awaits hold the input gate. After this read, every SQL read and the
  // metadata capture are synchronous; hashing only sees the detached snapshot.
  const alarm = await ctx.storage.getAlarm();
  const payload = ctx.storage.transactionSync((): SnapshotPayload => {
    currentSchema(ctx.storage, kind);
    requireValue(notificationAlarmOwned(ctx.storage, kind, alarm), "unsupported_storage_alarm");
    const copied = TABLES[kind].map(definition => ({ name: definition.name, schema: definition.schema, columns: definition.columns, rows: ctx.storage.sql.exec(definition.select).toArray() }));
    const checked = tables(copied, kind);
    return { format: "after-you-object-snapshot", format_version: checked.testerGrant ? 4 : checked.chapterCreations ? 3 : checked.versionedLinks ? 2 : 1, database_schema_version: 1,
      object_kind: kind, logical_id: checked.logicalId, source_object_id: ctx.id.toString(), source_commit: sourceCommit,
      exported_at: new Date().toISOString(), summary: checked.summary, tables: checked.tables };
  });
  const body = canonicalJson(payload); bounded(body);
  const archive: PortableSnapshot = { payload, checksum: { algorithm: "SHA-256", value: await digest(body) } };
  const serialized = canonicalJson(archive); bounded(serialized); return serialized;
}

export async function validateSnapshot(serialized: string, kind: ObjectKind, expectedLogicalId: string | null): Promise<PortableSnapshot> {
  requireValue(typeof serialized === "string"); bounded(serialized);
  requireValue(expectedLogicalId === null || validText(expectedLogicalId, ID_PATTERN), "snapshot_identity_mismatch");
  let raw: unknown;
  try { raw = JSON.parse(serialized); } catch { throw new SnapshotError("invalid_snapshot_json"); }
  const envelope = record(raw, ["payload", "checksum"]);
  const p = record(envelope.payload, ["format", "format_version", "database_schema_version", "object_kind", "logical_id", "source_object_id", "source_commit", "exported_at", "summary", "tables"]);
  requireValue(p.format === "after-you-object-snapshot" && (p.format_version === 1 || ((p.format_version === 2 || p.format_version === 3 || p.format_version === 4) && kind === "Player")) && p.database_schema_version === 1 && p.object_kind === kind, "unsupported_snapshot_format");
  requireValue(validText(p.source_object_id, HASH_PATTERN) && validText(p.source_commit, /^[a-f0-9]{40}$/)); date(p.exported_at);
  const checked = tables(p.tables, kind, p.format_version);
  requireValue(p.logical_id === checked.logicalId && p.logical_id === expectedLogicalId, "snapshot_identity_mismatch");
  const summary = record(p.summary, ["state", "revision", "attempt"]);
  requireValue(summary.state === checked.summary.state && summary.revision === checked.summary.revision && summary.attempt === checked.summary.attempt, "snapshot_summary_mismatch");
  const checksum = record(envelope.checksum, ["algorithm", "value"]);
  requireValue(checksum.algorithm === "SHA-256" && validText(checksum.value, HASH_PATTERN), "invalid_snapshot_checksum");
  // A canonical envelope rejects duplicate keys and ambiguous serialization.
  // Embedded data strings remain byte-for-byte as stored, including whitespace.
  requireValue(canonicalJson(raw) === serialized, "noncanonical_snapshot");
  requireValue(await digest(canonicalJson(p)) === checksum.value, "snapshot_checksum_mismatch");
  return { payload: { format: "after-you-object-snapshot", format_version: p.format_version, database_schema_version: 1, object_kind: kind,
    logical_id: checked.logicalId, source_object_id: p.source_object_id, source_commit: p.source_commit, exported_at: String(p.exported_at), summary: checked.summary, tables: checked.tables },
    checksum: { algorithm: "SHA-256", value: checksum.value } };
}

export async function restoreSnapshot(ctx: DurableObjectState, kind: ObjectKind, serialized: string, expectedLogicalId: string | null): Promise<{ restored: true; checksum: string }> {
  const archive = await validateSnapshot(serialized, kind, expectedLogicalId);
  // Recheck schema, KV and *all* rows after every await, in the same transaction
  // as the inserts. A concurrent normal write must prevent replacement.
  await ctx.storage.transaction(async () => {
    const alarm = await ctx.storage.getAlarm();
    currentSchema(ctx.storage, kind);
    requireValue(notificationAlarmOwned(ctx.storage, kind, alarm), "unsupported_storage_alarm");
    for (const definition of TABLES[kind]) requireValue(ctx.storage.sql.exec(definition.select).toArray().length === 0, "snapshot_target_not_empty");
    for (const [index, definition] of TABLES[kind].entries()) {
      for (const row of archive.payload.tables[index].rows) ctx.storage.sql.exec(definition.insert, ...definition.columns.map(column => row[column]));
    }
    await resetNotificationRuntime(ctx.storage, kind);
  });
  return { restored: true, checksum: archive.checksum.value };
}
