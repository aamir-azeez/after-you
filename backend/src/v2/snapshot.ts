import { canonicalJson, digest, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, isObject } from "../protocol";
import { SnapshotError } from "../snapshot";
import { RELAY_KEY, acceptedRecording, chapter, checkpointV2, recordingV2, type CheckpointV2, type RecordingV2 } from "./protocol";
import { sameChapter } from "./chapters";
import { LEGACY_ROOM_V2_TABLES, METADATA_SCHEMA, ROOM_V2_TABLES } from "./storage-schema";
import { checkPhoto } from "./photo-image";
import { MAX_PHOTOS, MAX_PHOTO_OPERATIONS } from "./photos";
import { isAlarmMetadataTable, notificationAlarmOwned, notificationTables, resetNotificationRuntime } from "../notification-storage";

export const MAX_ROOM_V2_ARCHIVE_BYTES = 24 * 1024 * 1024;
const MAX_ROW_BYTES = 512 * 1024;
type Row = Record<string, string | number>;
type Table = { name: string; schema: string; columns: string[]; rows: Row[] };
type Summary = { state: "empty" | "deleted" | "active"; revision: number | null; branch: number | null };
export type RoomV2Archive = { payload: {
  format: "after-you-object-snapshot"; format_version: 3 | 4 | 5; database_schema_version: 2 | 3; object_kind: "RoomV2";
  logical_id: string | null; source_object_id: string; source_commit: string; exported_at: string;
  summary: Summary; tables: Table[];
}; checksum: { algorithm: "SHA-256"; value: string } };

function need(value: unknown, code = "invalid_v2_snapshot"): asserts value { if (!value) throw new SnapshotError(code); }
function exact(value: unknown, keys: string[]): Record<string, unknown> {
  need(isObject(value) && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)));
  return value;
}
function text(value: unknown, pattern: RegExp): value is string { return typeof value === "string" && pattern.test(value); }
function integer(value: unknown, max = Number.MAX_SAFE_INTEGER): value is number { return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 && value <= max; }
function iso(value: unknown): void { need(text(value, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value); }
function bounded(textValue: string, max: number): void { need(textValue.length <= max && new TextEncoder().encode(textValue).byteLength <= max, "snapshot_too_large"); }
function same(first: unknown, second: unknown): boolean { return canonicalJson(first) === canonicalJson(second); }
function envelopeDepth(value: unknown): void {
  const pending = [{ value, depth: 0 }]; let nodes = 0;
  while (pending.length) {
    const item = pending.pop()!; need(++nodes <= 20000 && item.depth <= 16, "snapshot_structure_limit");
    if (Array.isArray(item.value) || isObject(item.value)) {
      const children: unknown[] = Object.values(item.value);
      need(children.length + pending.length <= 20000, "snapshot_structure_limit");
      for (const child of children) pending.push({ value: child, depth: item.depth + 1 });
    }
  }
}
function parseData(value: unknown): Record<string, unknown> {
  need(typeof value === "string"); bounded(value, MAX_ROW_BYTES);
  let parsed: unknown;
  try { parsed = JSON.parse(value); } catch { throw new SnapshotError("invalid_snapshot_json"); }
  need(isObject(parsed));
  // Stored JSON may contain whitespace, but duplicate keys must not silently
  // discard a value when the restored coordinator later parses it.
  const stack: { keys: Set<string> | null; key: boolean }[] = [];
  for (const match of value.matchAll(/"(?:\\.|[^"\\])*"|[{}\[\],:]/g)) {
    const token = match[0], frame = stack.at(-1);
    if (token === "{" || token === "[") { need(stack.length < 20, "snapshot_json_depth"); stack.push({ keys: token === "{" ? new Set() : null, key: token === "{" }); }
    else if (token === "}" || token === "]") stack.pop();
    else if (token === "," && frame?.keys) frame.key = true;
    else if (token.startsWith('"') && frame?.keys && frame.key) { const key: string = JSON.parse(token); need(!frame.keys.has(key), "snapshot_duplicate_json_key"); frame.keys.add(key); frame.key = false; }
  }
  return parsed;
}
function schema(storage: DurableObjectStorage): void {
  const found = storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name != '_cf_KV' ORDER BY name").toArray().filter(row => !isAlarmMetadataTable(row));
  const expected = [{ name: "metadata", schema: METADATA_SCHEMA }, ...ROOM_V2_TABLES, ...notificationTables("RoomV2")].sort((a, b) => a.name.localeCompare(b.name));
  need(found.length === expected.length && found.every((row, i) => row.name === expected[i].name && row.sql === expected[i].schema), "unsupported_storage_schema");
  const metadata = storage.sql.exec<{ id: number; schema_version: number }>("SELECT id,schema_version FROM metadata LIMIT 2").toArray();
  need(metadata.length === 1 && metadata[0].id === 1 && metadata[0].schema_version === 3, "unsupported_storage_schema");
  need([...storage.kv.list({ limit: 1 })].length === 0, "unsupported_storage_kv");
}
function tables(value: unknown, legacy = false): Table[] {
  const definitions = legacy ? LEGACY_ROOM_V2_TABLES : ROOM_V2_TABLES;
  need(Array.isArray(value) && value.length === definitions.length);
  let size = 0;
  return value.map((raw, index) => {
    const table = exact(raw, ["name", "schema", "columns", "rows"]), definition = definitions[index];
    need(table.name === definition.name && table.schema === definition.schema && same(table.columns, definition.columns), "unsupported_storage_schema");
    need(Array.isArray(table.rows) && table.rows.length <= definition.maxRows, "snapshot_row_limit");
    let last = 0n; const unique = new Set<string>();
    const rows: Row[] = table.rows.map(rawRow => {
      const row = exact(rawRow, definition.columns);
      need(text(row.rowid, /^[1-9][0-9]{0,18}$/)); const id = BigInt(row.rowid);
      need(id > last && id <= 9223372036854775807n, "snapshot_row_order"); last = id;
      need(Object.values(row).every(v => typeof v === "string" || (typeof v === "number" && Number.isSafeInteger(v))));
      const primary = String(row[definition.columns[1]]); need(!unique.has(primary), "snapshot_duplicate_key"); unique.add(primary);
      const stored = row[definition.name.endsWith("operations") ? "receipt" : "data"]; parseData(stored);
      size += new TextEncoder().encode(canonicalJson(row)).byteLength; need(size <= MAX_ROOM_V2_ARCHIVE_BYTES - 4096, "snapshot_too_large");
      return row as Row;
    });
    return { name: definition.name, schema: definition.schema, columns: definition.columns, rows };
  });
}

/** Structural consistency, not native game-physics verification. */
async function content(copied: Table[]): Promise<{ logicalId: string | null; summary: Summary; newChapter?: boolean }> {
  const [roomRows, turnRows, pairRows, operationRows, photoRows = [], photoOperationRows = []] = copied.map(table => table.rows);
  if (!roomRows.length) { need(!turnRows.length && !pairRows.length && !operationRows.length && !photoRows.length && !photoOperationRows.length, "snapshot_orphan_rows"); return { logicalId: null, summary: { state: "empty", revision: null, branch: null } }; }
  need(roomRows[0].id === 1 && roomRows[0].rowid === "1");
  const rawState = parseData(roomRows[0].data);
  if (same(rawState, { deleted: true })) { need(!turnRows.length && !pairRows.length && !operationRows.length && !photoRows.length && !photoOperationRows.length, "snapshot_orphan_rows"); return { logicalId: null, summary: { state: "deleted", revision: null, branch: null } }; }
  const state = exact(rawState, ["schema_version", "room_id", "revision", "branch", "stage_index", "level_id", "level_version", "definition_hash", "host_id", "guest_id", "checkpoint", "a_turn_id", "completed_pair_ids", "invite_code", "invite_expires_at", "created_at", "updated_at"]);
  need(state.schema_version === 2);
  let selected;
  try { selected = chapter(state); } catch { throw new SnapshotError("unsupported_snapshot_chapter"); }
  need(text(state.room_id, ID_PATTERN) && text(state.host_id, ID_PATTERN) && (state.guest_id === null || text(state.guest_id, ID_PATTERN)) && state.host_id !== state.guest_id);
  need(integer(state.revision) && integer(state.branch, 31) && integer(state.stage_index, 2));
  need(text(state.invite_code, /^[A-F0-9]{20}$/)); for (const name of ["created_at", "updated_at", "invite_expires_at"]) iso(state[name]);
  const turns = new Map<string, { recording: RecordingV2; row: Row }>();
  for (const row of turnRows) {
    need(text(row.turn_id, /^t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$/) && integer(row.accepted_revision) && row.accepted_revision > 0 && row.accepted_revision <= state.revision);
    let recording: RecordingV2;
    try { recording = await recordingV2(parseData(row.data), selected.key); } catch { throw new SnapshotError("invalid_snapshot_recording"); }
    const [branch, index, role] = row.turn_id.slice(1).split("-");
    need(Number(branch) <= state.branch && recording.stage_id === selected.stages[Number(index)].id && recording.role === role);
    need(row.player_id === (recording.player_slot === "p0" ? state.host_id : state.guest_id) && row.player_id !== null);
    need(acceptedRecording(recording));
    turns.set(row.turn_id, { recording, row });
  }
  const initial = selected.initial();
  const checkpoints = new Map<string, CheckpointV2>([[initial.checkpoint_hash, initial]]);
  const pairs = new Map<string, { a: RecordingV2; b: RecordingV2; checkpoint: CheckpointV2 }>();
  for (const row of pairRows) {
    need(text(row.pair_id, /^p(?:[0-9]|[12][0-9]|3[01])-[01]$/));
    const pair = exact(parseData(row.data), ["pair_id", "branch", "stage_index", "a", "b", "checkpoint"]);
    need(pair.pair_id === row.pair_id && integer(pair.branch, state.branch) && integer(pair.stage_index, 1) && row.pair_id === `p${pair.branch}-${pair.stage_index}`);
    const a = turns.get(`t${pair.branch}-${pair.stage_index}-a`), b = turns.get(`t${pair.branch}-${pair.stage_index}-b`);
    need(a && b && same(pair.a, a.recording) && same(pair.b, b.recording));
    const previous = checkpoints.get(a.recording.checkpoint_hash);
    need(previous && previous.stage_index === pair.stage_index && b.recording.checkpoint_hash === previous.checkpoint_hash && b.recording.source_recording_hash === a.recording.recording_hash && b.recording.duration_ticks >= a.recording.duration_ticks);
    let checkpoint: CheckpointV2;
    try { checkpoint = await checkpointV2(pair.checkpoint, previous, a.recording, b.recording); } catch { throw new SnapshotError("invalid_snapshot_checkpoint"); }
    checkpoints.set(checkpoint.checkpoint_hash, checkpoint); pairs.set(row.pair_id, { a: a.recording, b: b.recording, checkpoint });
  }
  need(Array.isArray(state.completed_pair_ids) && state.completed_pair_ids.length === state.stage_index);
  let current = initial;
  for (const [index, id] of state.completed_pair_ids.entries()) {
    need(typeof id === "string"); const pair = pairs.get(id);
    need(pair && pair.checkpoint.stage_index === index + 1 && pair.checkpoint.previous_checkpoint_hash === current.checkpoint_hash);
    current = pair.checkpoint;
  }
  need(same(state.checkpoint, current));
  for (const { recording } of turns.values()) need(checkpoints.has(recording.checkpoint_hash), "snapshot_orphan_turn");
  const activeId = `t${state.branch}-${state.stage_index}-a`;
  need(state.a_turn_id === (state.stage_index < 2 && turns.has(activeId) ? activeId : null));
  if (state.a_turn_id !== null) { const active = turns.get(String(state.a_turn_id)); need(active && active.recording.checkpoint_hash === current.checkpoint_hash); }
  // Historical attempts remain replayable. Within the current branch, every
  // accepted turn must agree with the live cursor or a completed active pair;
  // hiding an existing turn would make the next insert collide with its key.
  for (const [id, turn] of turns) {
    const [branch, index] = id.slice(1).split("-").map(Number);
    if (branch !== state.branch) continue;
    need(index <= state.stage_index);
    if (index < state.stage_index) need(state.completed_pair_ids[index] === `p${branch}-${index}`);
    else need(turn.recording.role === "a" && state.a_turn_id === id);
  }
  const operationTurns = new Set<string>(), revisions = new Set<number>();
  for (const row of operationRows) {
    need(typeof row.request_key === "string" && text(row.request_hash, HASH_PATTERN));
    const [owner, key, ...extra] = row.request_key.split(":");
    need(!extra.length && (owner === state.host_id || owner === state.guest_id) && IDEMPOTENCY_PATTERN.test(key));
    const r = exact(parseData(row.receipt), ["schema_version", "room_id", "idempotency_key", "request_hash", "operation", "accepted_revision", "branch", "stage_index", "stage_id", "turn_id", "recording_hash", "pair_id", "checkpoint_hash"]);
    need(r.schema_version === 2 && r.room_id === state.room_id && r.idempotency_key === key && r.request_hash === row.request_hash && integer(r.accepted_revision) && r.accepted_revision > 0 && r.accepted_revision <= state.revision && !revisions.has(r.accepted_revision)); revisions.add(r.accepted_revision);
    need(integer(r.branch, state.branch) && integer(r.stage_index, 1) && r.stage_id === selected.stages[r.stage_index].id && typeof r.checkpoint_hash === "string" && checkpoints.has(r.checkpoint_hash));
    if (r.operation === "turns") {
      need(typeof r.turn_id === "string"); const turn = turns.get(r.turn_id);
      need(turn && turn.row.player_id === owner && turn.row.accepted_revision === r.accepted_revision && turn.recording.recording_hash === r.recording_hash && r.turn_id === `t${r.branch}-${r.stage_index}-${turn.recording.role}` && !operationTurns.has(r.turn_id)); operationTurns.add(r.turn_id);
      if (turn.recording.role === "a") need(r.pair_id === null && r.checkpoint_hash === turn.recording.checkpoint_hash);
      else { need(r.pair_id === `p${r.branch}-${r.stage_index}`); const pair = pairs.get(String(r.pair_id)); need(pair && pair.checkpoint.checkpoint_hash === r.checkpoint_hash); }
    } else need(r.operation === "fork" && r.branch > 0 && r.turn_id === null && r.recording_hash === null && r.pair_id === null && checkpoints.get(r.checkpoint_hash)?.stage_index === r.stage_index);
  }
  need(operationTurns.size === turns.size, "snapshot_missing_receipt");
  const photos = new Map<string, Record<string, unknown>>();
  let photoCount = 0;
  for (const row of photoRows) {
    need(typeof row.turn_id === "string"); const turn = turns.get(row.turn_id); need(turn, "snapshot_orphan_photo");
    const photo = exact(parseData(row.data), ["schema_version", "turn_id", "owner_player_id", "recording_hash", "photo_revision", "sha256", "width", "height", "byte_length", "jpeg_base64", "updated_at"]);
    need(photo.schema_version === 1 && photo.turn_id === row.turn_id && photo.owner_player_id === turn.row.player_id && photo.recording_hash === turn.recording.recording_hash && integer(photo.photo_revision, MAX_PHOTO_OPERATIONS) && photo.photo_revision > 0);
    iso(photo.updated_at);
    if (photo.sha256 === null) need(photo.width === null && photo.height === null && photo.byte_length === 0 && photo.jpeg_base64 === null);
    else {
      need(++photoCount <= MAX_PHOTOS, "snapshot_photo_limit");
      let checked;
      try { checked = await checkPhoto(photo.jpeg_base64, photo.sha256); } catch { throw new SnapshotError("invalid_snapshot_photo"); }
      need(photo.width === checked.width && photo.height === checked.height && photo.byte_length === checked.byte_length, "snapshot_photo_metadata_mismatch");
    }
    photos.set(row.turn_id, photo);
  }
  need(photoOperationRows.length + photoCount <= MAX_PHOTO_OPERATIONS, "snapshot_photo_history_limit");
  const photoRevisions = new Map<string, Set<number>>();
  for (const row of photoOperationRows) {
    need(typeof row.request_key === "string" && text(row.request_hash, HASH_PATTERN));
    const [owner, key, ...extra] = row.request_key.split(":");
    need(!extra.length && IDEMPOTENCY_PATTERN.test(key));
    const receipt = exact(parseData(row.receipt), ["schema_version", "room_id", "idempotency_key", "request_hash", "operation", "turn_id", "recording_hash", "photo_revision", "photo_hash"]);
    need(typeof receipt.turn_id === "string"); const photo = photos.get(receipt.turn_id); need(photo, "snapshot_orphan_photo_receipt");
    need(receipt.schema_version === 1 && receipt.room_id === state.room_id && receipt.idempotency_key === key && receipt.request_hash === row.request_hash && owner === photo.owner_player_id && receipt.recording_hash === photo.recording_hash && integer(receipt.photo_revision, Number(photo.photo_revision)) && receipt.photo_revision > 0);
    need(receipt.operation === "photo_upload" ? text(receipt.photo_hash, HASH_PATTERN) : receipt.operation === "photo_delete" && receipt.photo_hash === null);
    const revisions = photoRevisions.get(receipt.turn_id) ?? new Set<number>();
    need(!revisions.has(receipt.photo_revision), "snapshot_duplicate_photo_revision"); revisions.add(receipt.photo_revision); photoRevisions.set(receipt.turn_id, revisions);
    if (receipt.photo_revision === photo.photo_revision) need(receipt.photo_hash === photo.sha256, "snapshot_photo_receipt_mismatch");
  }
  for (const [id, photo] of photos) need(photoRevisions.get(id)?.size === photo.photo_revision, "snapshot_missing_photo_receipt");
  return { logicalId: state.room_id, summary: { state: "active", revision: state.revision, branch: state.branch }, newChapter: !sameChapter(selected.key, RELAY_KEY) };
}

export async function exportRoomV2(ctx: DurableObjectState, sourceCommit: string): Promise<string> {
  need(text(sourceCommit, /^[a-f0-9]{40}$/), "invalid_source_commit");
  const alarm = await ctx.storage.getAlarm();
  const copied = ctx.storage.transactionSync(() => {
    schema(ctx.storage);
    need(notificationAlarmOwned(ctx.storage, "RoomV2", alarm), "unsupported_storage_alarm");
    return tables(ROOM_V2_TABLES.map(def => ({ name: def.name, schema: def.schema, columns: def.columns, rows: ctx.storage.sql.exec(def.select).toArray() })));
  });
  // No storage cursor or live mutable state crosses validation/hash awaits.
  const checked = await content(copied);
  const payload: RoomV2Archive["payload"] = { format: "after-you-object-snapshot", format_version: checked.newChapter ? 5 : 4, database_schema_version: 3, object_kind: "RoomV2", logical_id: checked.logicalId, source_object_id: ctx.id.toString(), source_commit: sourceCommit, exported_at: new Date().toISOString(), summary: checked.summary, tables: copied };
  const body = canonicalJson(payload); bounded(body, MAX_ROOM_V2_ARCHIVE_BYTES);
  const serialized = canonicalJson({ payload, checksum: { algorithm: "SHA-256", value: await digest(body) } }); bounded(serialized, MAX_ROOM_V2_ARCHIVE_BYTES); return serialized;
}

export async function validateRoomV2(serialized: string, expectedLogicalId: string | null): Promise<RoomV2Archive> {
  need(typeof serialized === "string"); bounded(serialized, MAX_ROOM_V2_ARCHIVE_BYTES);
  need(expectedLogicalId === null || text(expectedLogicalId, ID_PATTERN), "snapshot_identity_mismatch");
  let raw: unknown; try { raw = JSON.parse(serialized); } catch { throw new SnapshotError("invalid_snapshot_json"); }
  envelopeDepth(raw);
  const archive = exact(raw, ["payload", "checksum"]);
  // Canonical envelope also rejects duplicate top-level keys; raw data strings
  // are retained exactly and separately checked by parseData.
  need(canonicalJson(raw) === serialized, "noncanonical_snapshot");
  const p = exact(archive.payload, ["format", "format_version", "database_schema_version", "object_kind", "logical_id", "source_object_id", "source_commit", "exported_at", "summary", "tables"]);
  const legacy = p.format_version === 3 && p.database_schema_version === 2;
  need(p.format === "after-you-object-snapshot" && (legacy || ((p.format_version === 4 || p.format_version === 5) && p.database_schema_version === 3)) && p.object_kind === "RoomV2", "unsupported_snapshot_format");
  need(text(p.source_object_id, HASH_PATTERN) && text(p.source_commit, /^[a-f0-9]{40}$/)); iso(p.exported_at);
  const checksum = exact(archive.checksum, ["algorithm", "value"]);
  need(checksum.algorithm === "SHA-256" && text(checksum.value, HASH_PATTERN) && await digest(canonicalJson(p)) === checksum.value, "snapshot_checksum_mismatch");
  const copied = tables(p.tables, legacy), checked = await content(copied);
  need(!checked.newChapter || p.format_version === 5, "unsupported_snapshot_format");
  need(p.logical_id === checked.logicalId && p.logical_id === expectedLogicalId, "snapshot_identity_mismatch");
  need(same(p.summary, checked.summary), "snapshot_summary_mismatch");
  return { payload: { format: "after-you-object-snapshot", format_version: p.format_version as 3 | 4 | 5, database_schema_version: legacy ? 2 : 3, object_kind: "RoomV2", logical_id: checked.logicalId, source_object_id: p.source_object_id, source_commit: p.source_commit, exported_at: String(p.exported_at), summary: checked.summary, tables: copied }, checksum: { algorithm: "SHA-256", value: checksum.value } };
}

export async function restoreRoomV2(ctx: DurableObjectState, serialized: string, expectedLogicalId: string | null): Promise<{ restored: true; checksum: string }> {
  const archive = await validateRoomV2(serialized, expectedLogicalId);
  await ctx.storage.transaction(async () => {
    const alarm = await ctx.storage.getAlarm();
    schema(ctx.storage);
    need(notificationAlarmOwned(ctx.storage, "RoomV2", alarm), "unsupported_storage_alarm");
    for (const def of ROOM_V2_TABLES) need(ctx.storage.sql.exec(def.select).toArray().length === 0, "snapshot_target_not_empty");
    for (const [index, def] of ROOM_V2_TABLES.entries()) for (const row of archive.payload.tables[index]?.rows ?? []) ctx.storage.sql.exec(def.insert, ...def.columns.map(column => row[column]));
    await resetNotificationRuntime(ctx.storage, "RoomV2");
  });
  return { restored: true, checksum: archive.checksum.value };
}
