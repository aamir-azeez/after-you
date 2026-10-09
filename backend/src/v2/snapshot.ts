import { campaignStoragePresent, validateCampaignStorage } from "./campaign-storage";
import type { CampaignDefinitionResolver } from "./campaign-protocol";
import { canonicalJson, digest, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, isObject } from "../protocol";
import { SnapshotError } from "../snapshot";
import { RELAY_KEY, acceptedRecording, chapter, checkpointV2, recordingV2, type CheckpointV2, type RecordingV2 } from "./protocol";
import { sameChapter } from "./chapters";
import { LEGACY_ROOM_V2_TABLES, METADATA_SCHEMA, ROOM_V2_TABLES, ROOM_V2_REACTION_TABLES, initializePairReactions, initializePhotoDelivery, ROOM_V2_DELIVERY_TABLES, ROOM_V2_CAMPAIGN_TABLES, ROOM_V2_CAMPAIGN_JOIN_TABLES, ROOM_V2_TRANSFER_TABLES, initializeReplayTransfer } from "./storage-schema";
import { validateCompactedReplay, validateTransfer } from "./replay-transfer";
import { isPreset, MAX_PAIR_REACTIONS, MAX_REACTION_OPERATIONS } from "./reactions";
import { checkPhoto } from "./photo-image";
import { MAX_PHOTOS, MAX_PHOTO_OPERATIONS } from "./photos";
import { isAlarmMetadataTable, notificationAlarmOwned, notificationTables, resetNotificationRuntime } from "../notification-storage";
import { REDO_TABLE, redoRuntimeValid, resetRedo } from "../redo-control";
import { ROOM_INBOX_ACTIVITY, clearRoomInboxActivity } from "../room-inbox-storage";

export const MAX_ROOM_V2_ARCHIVE_BYTES = 24 * 1024 * 1024;
const MAX_ROW_BYTES = 512 * 1024;
type Row = Record<string, string | number>;
type Table = { name: string; schema: string; columns: string[]; rows: Row[] };
type Summary = { state: "empty" | "deleted" | "active" | "transferred"; revision: number | null; branch: number | null };
export type RoomV2Archive = { payload: {
  format: "after-you-object-snapshot"; format_version: 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10; database_schema_version: 2 | 3 | 4 | 5 | 6 | 7 | 8; object_kind: "RoomV2";
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
function definitions(version: number) { return version === 2 ? LEGACY_ROOM_V2_TABLES : version === 3 ? ROOM_V2_TABLES : version === 4 ? ROOM_V2_REACTION_TABLES : version === 5 ? ROOM_V2_DELIVERY_TABLES : version === 6 ? ROOM_V2_CAMPAIGN_TABLES : version === 7 ? ROOM_V2_CAMPAIGN_JOIN_TABLES : ROOM_V2_TRANSFER_TABLES; }
function schema(storage: DurableObjectStorage): 3 | 4 | 5 | 6 | 7 | 8 {
  const metadata = storage.sql.exec<{ id: number; schema_version: number }>("SELECT id,schema_version FROM metadata LIMIT 2").toArray();
  need(metadata.length === 1 && metadata[0].id === 1 && [3, 4, 5, 6, 7, 8].includes(metadata[0].schema_version), "unsupported_storage_schema");
  const version = metadata[0].schema_version as 3 | 4 | 5 | 6 | 7 | 8;
  const found = storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name != '_cf_KV' ORDER BY name").toArray().filter(row => !isAlarmMetadataTable(row));
  // Operational inbox activity is a known runtime table, but is never exported
  // with recordings, checkpoints, or other gameplay archive data.
  const expected = [{ name: "metadata", schema: METADATA_SCHEMA }, ...definitions(version), ...notificationTables("RoomV2"), REDO_TABLE, ROOM_INBOX_ACTIVITY].sort((a, b) => a.name.localeCompare(b.name));
  need(found.length === expected.length && found.every((row, i) => row.name === expected[i].name && row.sql === expected[i].schema), "unsupported_storage_schema");
  need(redoRuntimeValid(storage), "unsupported_redo_state");
  need([...storage.kv.list({ limit: 1 })].length === 0, "unsupported_storage_kv");
  return version;
}
/** Read-only fixed schema helpers for the local campaign target initializer. */
export { definitions as roomV2StorageDefinitions, schema as roomV2StorageSchema };
function tables(value: unknown, version: number): Table[] {
  const selected = definitions(version);
  need(Array.isArray(value) && value.length === selected.length);
  let size = 0;
  return value.map((raw, index) => {
    const table = exact(raw, ["name", "schema", "columns", "rows"]), definition = selected[index];
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
async function content(copied: Table[], version=5, resolver: CampaignDefinitionResolver = () => undefined): Promise<{ logicalId: string | null; summary: Summary; newChapter?: boolean }> {
  if (version === 8) {
    const base = copied.slice(0, ROOM_V2_DELIVERY_TABLES.length), rows = copied.at(-1)!.rows;
    need(rows.length <= 1);
    const raw = base[0].rows.length ? parseData(base[0].rows[0].data) : null;
    if (!rows.length) { need(!raw || same(raw, { deleted: true })); return content(base); }
    need(rows[0].id === 1 && rows[0].rowid === "1");
    try {
      const transfer = validateTransfer(parseData(rows[0].data));
      if (raw?.replay_transfer_version === 1) {
        const checked = validateCompactedReplay(base.map(t => t.rows), raw, transfer);
        const [, , , , photos, photoOperations, reactions, reactionOperations, deliveries] = base.map(t => t.rows);
        await mediaContent(checked.state, checked.turns, checked.pairs, photos, photoOperations, reactions, reactionOperations, deliveries);
        return { logicalId: checked.state.room_id, summary: { state: "transferred", revision: checked.state.revision, branch: checked.state.branch }, newChapter: !sameChapter(chapter(checked.state).key, RELAY_KEY) };
      }
      need(!transfer.transferred && raw && raw.room_id === transfer.manifest.room.room_id && raw.host_id === transfer.manifest.room.host_id && raw.guest_id === transfer.manifest.room.guest_id && sameChapter(chapter(raw).key, chapter(transfer.manifest.room).key));
      need(Number(raw.revision) >= transfer.manifest.room.revision && Number(raw.branch) >= transfer.manifest.room.branch);
      // A live room may have forked since its last offered transfer. Old ACKs
      // remain inert: the final ACK transaction recomputes the current archive.
      for (const t of transfer.manifest.turns) { const stored = base[1].rows.find(row => row.turn_id === t.turn_id); need(stored && stored.player_id === t.player_id && stored.accepted_revision === t.accepted_revision && parseData(stored.data).recording_hash === t.recording_hash); }
      for (const p of transfer.manifest.pairs) { const stored = base[2].rows.find(row => row.pair_id === p.pair_id); need(stored); const pair = parseData(stored.data); need(isObject(pair.a) && pair.a.recording_hash === p.a_hash && isObject(pair.b) && pair.b.recording_hash === p.b_hash && isObject(pair.checkpoint) && pair.checkpoint.checkpoint_hash === p.checkpoint_hash); }
      return content(base);
    } catch (error) { if (error instanceof SnapshotError) throw error; throw new SnapshotError("invalid_replay_transfer_snapshot"); }
  }
  if (version===6 || version===7) {
    const base=copied.slice(0,ROOM_V2_DELIVERY_TABLES.length), checked=await content(base);
    const gameplay=base[0].rows.length?parseData(base[0].rows[0].data):null;
    try {
      const sidecars=await validateCampaignStorage(copied.slice(ROOM_V2_DELIVERY_TABLES.length),gameplay,base.slice(1).every(t=>t.rows.length===0),resolver);
      return {...checked,logicalId:sidecars.roomId};
    } catch { throw new SnapshotError("invalid_campaign_snapshot"); }
  }
  const [roomRows, turnRows, pairRows, operationRows, photoRows = [], photoOperationRows = [], reactionRows = [], reactionOperationRows = [], deliveryRows = []] = copied.map(table => table.rows);
  if (!roomRows.length) { need(!copied.slice(1).some(table => table.rows.length), "snapshot_orphan_rows"); return { logicalId: null, summary: { state: "empty", revision: null, branch: null } }; }
  need(roomRows[0].id === 1 && roomRows[0].rowid === "1");
  const rawState = parseData(roomRows[0].data);
  if (same(rawState, { deleted: true })) { need(!copied.slice(1).some(table => table.rows.length), "snapshot_orphan_rows"); return { logicalId: null, summary: { state: "deleted", revision: null, branch: null } }; }
  const state = exact(rawState, ["schema_version", "room_id", "revision", "branch", "stage_index", "level_id", "level_version", "definition_hash", "host_id", "guest_id", "checkpoint", "a_turn_id", "completed_pair_ids", "invite_code", "invite_expires_at", "created_at", "updated_at", ...(rawState.simulation_version === undefined ? [] : ["simulation_version"])]);
  need(state.schema_version === 2);
  let selected;
  try { selected = chapter(state); } catch { throw new SnapshotError("unsupported_snapshot_chapter"); }
  const simulationVersion = state.simulation_version ?? selected.simulation_version;
  need(typeof simulationVersion === "number" && Number.isInteger(simulationVersion) && (selected.supported_simulation_versions ?? [selected.simulation_version]).includes(simulationVersion), "unsupported_snapshot_simulation");
  need(text(state.room_id, ID_PATTERN) && text(state.host_id, ID_PATTERN) && (state.guest_id === null || text(state.guest_id, ID_PATTERN)) && state.host_id !== state.guest_id);
  need(integer(state.revision) && integer(state.branch, 31) && integer(state.stage_index, 2));
  need(text(state.invite_code, /^[A-F0-9]{20}$/)); for (const name of ["created_at", "updated_at", "invite_expires_at"]) iso(state[name]);
  const turns = new Map<string, { recording: RecordingV2; row: Row }>();
  for (const row of turnRows) {
    need(text(row.turn_id, /^t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$/) && integer(row.accepted_revision) && row.accepted_revision > 0 && row.accepted_revision <= state.revision);
    let recording: RecordingV2;
    try { recording = await recordingV2(parseData(row.data), selected.key); } catch { throw new SnapshotError("invalid_snapshot_recording"); }
    need(recording.simulation_version === simulationVersion, "snapshot_simulation_mismatch");
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
  await mediaContent(state, turns, pairs, photoRows, photoOperationRows, reactionRows, reactionOperationRows, deliveryRows);
  return { logicalId: state.room_id, summary: { state: "active", revision: state.revision, branch: state.branch }, newChapter: !sameChapter(selected.key, RELAY_KEY) };
}

async function mediaContent(state: Record<string, unknown>, turns: Map<string, { recording: { recording_hash: string }; row: Row }>, pairs: Map<string, { a: { recording_hash: string }; b: { recording_hash: string } }>, photoRows: Row[], photoOperationRows: Row[], reactionRows: Row[], reactionOperationRows: Row[], deliveryRows: Row[]): Promise<void> {
  const deliveries = new Map<string, Record<string, unknown>>();
  for (const row of deliveryRows) {
    const d = exact(parseData(row.data), ["schema_version", "turn_id", "recording_hash", "photo_revision", "sha256", "intended_player_ids", "acked_player_ids", "removed"]);
    need(d.schema_version === 1 && d.turn_id === row.turn_id && typeof row.turn_id === "string" && turns.has(row.turn_id));
    need(text(d.recording_hash, HASH_PATTERN) && text(d.sha256, HASH_PATTERN) && integer(d.photo_revision, MAX_PHOTO_OPERATIONS) && d.photo_revision > 0);
    need(state.guest_id !== null && same(d.intended_player_ids, [state.host_id, state.guest_id]));
    need(Array.isArray(d.acked_player_ids) && d.acked_player_ids.length >= 1 && d.acked_player_ids.length <= 2 && new Set(d.acked_player_ids).size === d.acked_player_ids.length);
    need(d.acked_player_ids.every(id => id === state.host_id || id === state.guest_id) && same(d.acked_player_ids, [state.host_id, state.guest_id].filter(id => (d.acked_player_ids as unknown[]).includes(id))));
    need(d.removed === (d.acked_player_ids.length === 2));
    deliveries.set(row.turn_id, d);
  }
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
      if (photo.jpeg_base64 === null) {
        const d = deliveries.get(row.turn_id); need(d?.removed === true, "snapshot_missing_photo_payload");
        need(integer(photo.width, 960) && photo.width > 0 && integer(photo.height, 960) && photo.height > 0 && integer(photo.byte_length, 160 * 1024) && photo.byte_length > 0);
      } else {
        let checked;
        try { checked = await checkPhoto(photo.jpeg_base64, photo.sha256); } catch { throw new SnapshotError("invalid_snapshot_photo"); }
        need(photo.width === checked.width && photo.height === checked.height && photo.byte_length === checked.byte_length, "snapshot_photo_metadata_mismatch");
      }
    }
    photos.set(row.turn_id, photo);
  }
  for (const [id, d] of deliveries) {
    const photo = photos.get(id); need(photo && photo.recording_hash === d.recording_hash && photo.photo_revision === d.photo_revision && photo.sha256 === d.sha256, "snapshot_delivery_mismatch");
    need(d.removed === (photo.jpeg_base64 === null), "snapshot_delivery_payload_mismatch");
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
  const reactions = new Map<string, Record<string, unknown>>();
  need(reactionRows.length <= MAX_PAIR_REACTIONS && reactionOperationRows.length <= MAX_REACTION_OPERATIONS, "snapshot_reaction_limit");
  const reactionKeys = ["schema_version", "pair_id", "player_id", "a_hash", "b_hash", "reaction_revision", "reaction"];
  function reaction(value: Record<string, unknown>): void {
    need(value.schema_version === 1 && typeof value.pair_id === "string" && typeof value.player_id === "string" && (value.player_id === state.host_id || value.player_id === state.guest_id));
    const pair = pairs.get(value.pair_id); need(pair && value.a_hash === pair.a.recording_hash && value.b_hash === pair.b.recording_hash, "snapshot_orphan_reaction");
    need(integer(value.reaction_revision, MAX_REACTION_OPERATIONS) && value.reaction_revision > 0 && isPreset(value.reaction));
  }
  for (const row of reactionRows) {
    const value = exact(parseData(row.data), reactionKeys); reaction(value);
    need(row.reaction_key === `${value.pair_id}:${value.player_id}`);
    reactions.set(String(row.reaction_key), value);
  }
  const reactionRevisions = new Map<string, Set<number>>();
  for (const row of reactionOperationRows) {
    const receipt = exact(parseData(row.receipt), [...reactionKeys, "room_id", "idempotency_key", "request_hash"]); reaction(receipt);
    need(receipt.room_id === state.room_id && text(receipt.idempotency_key, IDEMPOTENCY_PATTERN) && text(row.request_hash, HASH_PATTERN) && receipt.request_hash === row.request_hash && row.request_key === `${receipt.player_id}:${receipt.idempotency_key}`);
    const reactionKey = `${receipt.pair_id}:${receipt.player_id}`, latest = reactions.get(reactionKey); need(latest, "snapshot_orphan_reaction_receipt");
    const revision = Number(receipt.reaction_revision); need(revision <= Number(latest.reaction_revision));
    const seen = reactionRevisions.get(reactionKey) ?? new Set<number>(); need(!seen.has(revision), "snapshot_duplicate_reaction_revision"); seen.add(revision); reactionRevisions.set(reactionKey, seen);
    if (receipt.reaction_revision === latest.reaction_revision) need(receipt.reaction === latest.reaction, "snapshot_reaction_receipt_mismatch");
    // Full immutable request is reconstructible from its accepted revision.
    need(await digest(canonicalJson({ operation: "pair_reaction", pair_id: receipt.pair_id, idempotency_key: receipt.idempotency_key, a_hash: receipt.a_hash, b_hash: receipt.b_hash, expected_reaction_revision: revision - 1, reaction: receipt.reaction })) === receipt.request_hash, "snapshot_reaction_request_mismatch");
  }
  for (const [id, value] of reactions) need(reactionRevisions.get(id)?.size === value.reaction_revision, "snapshot_missing_reaction_receipt");
}

export async function exportRoomV2(ctx: DurableObjectState, sourceCommit: string, resolver: CampaignDefinitionResolver = () => undefined): Promise<string> {
  need(text(sourceCommit, /^[a-f0-9]{40}$/), "invalid_source_commit");
  const alarm = await ctx.storage.getAlarm();
  const captured = ctx.storage.transactionSync(() => {
    const version = schema(ctx.storage);
    need(notificationAlarmOwned(ctx.storage, "RoomV2", alarm), "unsupported_storage_alarm");
    return { version, copied: tables(definitions(version).map(def => ({ name: def.name, schema: def.schema, columns: def.columns, rows: ctx.storage.sql.exec(def.select).toArray() })), version) };
  });
  const { version, copied } = captured;
  // No storage cursor or live mutable state crosses validation/hash awaits.
  const checked = await content(copied,version,resolver);
  const payload: RoomV2Archive["payload"] = { format: "after-you-object-snapshot", format_version: version === 8 ? 10 : version === 7 ? 9 : version === 6 ? 8 : version === 5 ? 7 : version === 4 ? 6 : checked.newChapter ? 5 : 4, database_schema_version: version, object_kind: "RoomV2", logical_id: checked.logicalId, source_object_id: ctx.id.toString(), source_commit: sourceCommit, exported_at: new Date().toISOString(), summary: checked.summary, tables: copied };
  const body = canonicalJson(payload); bounded(body, MAX_ROOM_V2_ARCHIVE_BYTES);
  const serialized = canonicalJson({ payload, checksum: { algorithm: "SHA-256", value: await digest(body) } }); bounded(serialized, MAX_ROOM_V2_ARCHIVE_BYTES); return serialized;
}

export async function validateRoomV2(serialized: string, expectedLogicalId: string | null, resolver: CampaignDefinitionResolver = () => undefined): Promise<RoomV2Archive> {
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
  need(p.format === "after-you-object-snapshot" && (legacy || ((p.format_version === 4 || p.format_version === 5) && p.database_schema_version === 3) || (p.format_version === 6 && p.database_schema_version === 4) || (p.format_version === 7 && p.database_schema_version === 5) || (p.format_version === 8 && p.database_schema_version === 6) || (p.format_version === 9 && p.database_schema_version === 7) || (p.format_version === 10 && p.database_schema_version === 8)) && p.object_kind === "RoomV2", "unsupported_snapshot_format");
  need(text(p.source_object_id, HASH_PATTERN) && text(p.source_commit, /^[a-f0-9]{40}$/)); iso(p.exported_at);
  const checksum = exact(archive.checksum, ["algorithm", "value"]);
  need(checksum.algorithm === "SHA-256" && text(checksum.value, HASH_PATTERN) && await digest(canonicalJson(p)) === checksum.value, "snapshot_checksum_mismatch");
  const copied = tables(p.tables, Number(p.database_schema_version)), checked = await content(copied,Number(p.database_schema_version),resolver);
  need(!checked.newChapter || [5, 6, 7, 8, 9, 10].includes(Number(p.format_version)), "unsupported_snapshot_format");
  need(p.logical_id === checked.logicalId && p.logical_id === expectedLogicalId, "snapshot_identity_mismatch");
  need(same(p.summary, checked.summary), "snapshot_summary_mismatch");
  return { payload: { format: "after-you-object-snapshot", format_version: p.format_version as RoomV2Archive["payload"]["format_version"], database_schema_version: p.database_schema_version as RoomV2Archive["payload"]["database_schema_version"], object_kind: "RoomV2", logical_id: checked.logicalId, source_object_id: p.source_object_id, source_commit: p.source_commit, exported_at: String(p.exported_at), summary: checked.summary, tables: copied }, checksum: { algorithm: "SHA-256", value: checksum.value } };
}

export async function restoreRoomV2(ctx: DurableObjectState, serialized: string, expectedLogicalId: string | null, resolver: CampaignDefinitionResolver = () => undefined): Promise<{ restored: true; checksum: string }> {
  const archive = await validateRoomV2(serialized, expectedLogicalId,resolver);
  need(archive.payload.database_schema_version!==6 && archive.payload.database_schema_version!==7,"campaign_restore_unsupported");
  await ctx.storage.transaction(async () => {
    const alarm = await ctx.storage.getAlarm();
    need(!campaignStoragePresent(ctx.storage),"campaign_restore_unsupported");
    const version = schema(ctx.storage);
    need(notificationAlarmOwned(ctx.storage, "RoomV2", alarm), "unsupported_storage_alarm");
    for (const def of definitions(version)) need(ctx.storage.sql.exec(def.select).toArray().length === 0, "snapshot_target_not_empty");
    if (archive.payload.database_schema_version === 5) initializePhotoDelivery(ctx.storage);
    if (archive.payload.database_schema_version === 4) initializePairReactions(ctx.storage);
    if (archive.payload.database_schema_version === 8) initializeReplayTransfer(ctx.storage);
    for (const [index, def] of definitions(archive.payload.database_schema_version).entries()) for (const row of archive.payload.tables[index]?.rows ?? []) ctx.storage.sql.exec(def.insert, ...def.columns.map(column => row[column]));
    await resetNotificationRuntime(ctx.storage, "RoomV2");
    resetRedo(ctx.storage);
    clearRoomInboxActivity(ctx.storage);
  });
  return { restored: true, checksum: archive.checksum.value };
}
