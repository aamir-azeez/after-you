import { ApiError, canonicalJson, digest, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, integer, isObject, object, text } from "../protocol";
import { chapter, exact, type RecordingV2 } from "./protocol";
import type { PairV2, RoomStateV2 } from "./room";
import { initializeReplayTransfer } from "./storage-schema";

export const MAX_REPLAY_ARCHIVE_BYTES = 16 * 1024 * 1024;
const MAX_REPLAY_ARCHIVE_NODES = 2_000_000;
const MAX_REPLAY_ARCHIVE_DEPTH = 20;
type RoomFacts = Omit<RoomStateV2, "checkpoint" | "invite_code"> & { checkpoint_hash: string };
type TurnFacts = { turn_id: string; player_id: string; accepted_revision: number; recording_hash: string };
type PairFacts = { pair_id: string; branch: number; stage_index: number; a_hash: string; b_hash: string; checkpoint_hash: string };
export type ReplayArchive = { schema_version: 1; room: Omit<RoomStateV2, "invite_code">; turns: (Omit<TurnFacts, "recording_hash"> & { recording: RecordingV2 })[]; pairs: PairV2[] };
export type ReplayManifest = { schema_version: 1; epoch: number; archive_hash: string; room: RoomFacts; turns: TurnFacts[]; pairs: PairFacts[] };
export type ReplayTransfer = { schema_version: 1; manifest: ReplayManifest; acked_player_ids: string[]; transferred: boolean };
export type TransferredRoom = Omit<RoomStateV2, "checkpoint"> & { replay_transfer_version: 1; checkpoint_hash: string };
type Row = Record<string, string | number>;
export function need(value: unknown, code = "invalid_replay_transfer"): asserts value { if (!value) throw new ApiError(409, code); }
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
const hash = (v: unknown) => typeof v === "string" && HASH_PATTERN.test(v);
function iso(value: unknown): void { need(typeof value === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value); }
export function transferredRoom(storage: DurableObjectStorage): TransferredRoom | null {
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0];
  const value = row ? JSON.parse(row.data) : null;
  return value?.replay_transfer_version === 1 ? value as TransferredRoom : null;
}
export function readReplayTransfer(storage: DurableObjectStorage): ReplayTransfer | null {
  if (!storage.sql.exec("SELECT name FROM sqlite_master WHERE name='replay_transfer'").toArray().length) return null;
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM replay_transfer WHERE id=1").toArray()[0];
  return row ? JSON.parse(row.data) as ReplayTransfer : null;
}
export function clearReplayTransfer(storage: DurableObjectStorage): void {
  if (storage.sql.exec("SELECT name FROM sqlite_master WHERE name='replay_transfer'").toArray().length) storage.sql.exec("DELETE FROM replay_transfer");
}
function writeTransfer(storage: DurableObjectStorage, value: ReplayTransfer): void {
  initializeReplayTransfer(storage);
  storage.sql.exec("INSERT INTO replay_transfer VALUES (1,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data", JSON.stringify(value));
}
export function captureReplay(storage: DurableObjectStorage, room: RoomStateV2): ReplayArchive {
  need(room.stage_index === 2 && room.guest_id !== null && room.a_turn_id === null, "replay_not_complete");
  const { invite_code: _invite, ...safe } = room; void _invite;
  const turns = storage.sql.exec<{ turn_id: string; player_id: string; accepted_revision: number; data: string }>("SELECT turn_id,player_id,accepted_revision,data FROM turns ORDER BY rowid LIMIT 129").toArray();
  const pairs = storage.sql.exec<{ data: string }>("SELECT data FROM pairs ORDER BY rowid LIMIT 65").toArray();
  need(turns.length <= 128 && pairs.length <= 64);
  const value: ReplayArchive = { schema_version: 1, room: safe,
    turns: turns.map(({ data, ...facts }) => ({ ...facts, recording: JSON.parse(data) as RecordingV2 })), pairs: pairs.map(row => JSON.parse(row.data) as PairV2) };
  need(new TextEncoder().encode(canonicalJson(value)).byteLength <= MAX_REPLAY_ARCHIVE_BYTES, "replay_archive_too_large");
  return value;
}
export function factsForArchive(archive: ReplayArchive, epoch: number, archiveHash: string): ReplayManifest {
  const { checkpoint, ...room } = archive.room;
  return { schema_version: 1, epoch, archive_hash: archiveHash, room: { ...room, checkpoint_hash: checkpoint.checkpoint_hash },
    turns: archive.turns.map(({ recording, ...turn }) => ({ ...turn, recording_hash: recording.recording_hash })),
    pairs: archive.pairs.map(pair => ({ pair_id: pair.pair_id, branch: pair.branch, stage_index: pair.stage_index,
      a_hash: pair.a.recording_hash, b_hash: pair.b.recording_hash, checkpoint_hash: pair.checkpoint.checkpoint_hash })) };
}
/** The caller captured immutable rows before hashing and owns the final transaction. */
export function prepareReplayTransfer(storage: DurableObjectStorage, archive: ReplayArchive, archiveHash: string): ReplayTransfer {
  const prior = readReplayTransfer(storage);
  if (prior && !prior.transferred && prior.manifest.archive_hash === archiveHash) {
    need(same(prior.manifest, factsForArchive(archive, prior.manifest.epoch, archiveHash)), "replay_manifest_mismatch");
    return prior;
  }
  need(!prior?.transferred, "replay_transferred");
  const value: ReplayTransfer = { schema_version: 1, manifest: factsForArchive(archive, (prior?.manifest.epoch ?? 0) + 1, archiveHash), acked_player_ids: [], transferred: false };
  validateTransfer(value);
  writeTransfer(storage, value);
  return value;
}
export function parseTransferKey(input: unknown): { schema_version: 1; epoch: number; archive_hash: string } {
  const value = object(input); exact(value, ["schema_version", "epoch", "archive_hash"]);
  need(value.schema_version === 1);
  return { schema_version: 1, epoch: integer(value.epoch, 1, Number.MAX_SAFE_INTEGER), archive_hash: text(value.archive_hash, HASH_PATTERN) };
}
export function matchingTransfer(storage: DurableObjectStorage, key: ReturnType<typeof parseTransferKey>): ReplayTransfer {
  const value = readReplayTransfer(storage);
  need(value && value.manifest.epoch === key.epoch && value.manifest.archive_hash === key.archive_hash, "stale_replay_ack");
  return value;
}
/** Compact only coordinates/checkpoint proofs. Photo bytes retain their own two-ACK protocol. */
export function acknowledgeReplay(storage: DurableObjectStorage, room: RoomStateV2, player: string, value: ReplayTransfer): ReplayTransfer {
  const members = [room.host_id, room.guest_id]; need(members.includes(player) && room.guest_id !== null);
  if (!value.acked_player_ids.includes(player)) value.acked_player_ids.push(player);
  value.acked_player_ids = members.filter(id => id !== null && value.acked_player_ids.includes(id)) as string[];
  value.transferred = value.acked_player_ids.length === 2;
  if (value.transferred) {
    const { checkpoint, ...metadata } = room;
    const tombstone: TransferredRoom = { ...metadata, replay_transfer_version: 1, checkpoint_hash: checkpoint.checkpoint_hash };
    storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(tombstone));
    for (const turn of value.manifest.turns) storage.sql.exec("UPDATE turns SET data=? WHERE turn_id=?", JSON.stringify({ recording_hash: turn.recording_hash }), turn.turn_id);
    for (const pair of value.manifest.pairs) storage.sql.exec("UPDATE pairs SET data=? WHERE pair_id=?", JSON.stringify(compactPair(pair)), pair.pair_id);
  }
  writeTransfer(storage, value);
  return value;
}
export function compactPair(pair: PairFacts) {
  return { pair_id: pair.pair_id, branch: pair.branch, stage_index: pair.stage_index, a: { recording_hash: pair.a_hash }, b: { recording_hash: pair.b_hash }, checkpoint: { checkpoint_hash: pair.checkpoint_hash } };
}
function boundedArchiveStructure(value: unknown): void {
  // Existing checkpoint proofs are bounded at depth 16. The archive adds at
  // most three wrappers; the node cap matches native transfer validation.
  // Iterators keep a wide actions array from allocating one stack entry per node.
  const pending: { children: Iterator<unknown>; depth: number }[] = [{ children: [value].values(), depth: 0 }];
  let nodes = 0;
  while (pending.length) {
    const frame = pending.at(-1)!, item = frame.children.next();
    if (item.done) { pending.pop(); continue; }
    if (++nodes > MAX_REPLAY_ARCHIVE_NODES || frame.depth > MAX_REPLAY_ARCHIVE_DEPTH) throw new ApiError(413, "structure_too_large");
    if (Array.isArray(item.value)) pending.push({ children: item.value.values(), depth: frame.depth + 1 });
    else if (isObject(item.value)) pending.push({ children: Object.values(item.value).values(), depth: frame.depth + 1 });
  }
}
export async function checkedRestore(input: unknown): Promise<{ key: ReturnType<typeof parseTransferKey>; archive: ReplayArchive }> {
  const value = object(input); exact(value, ["schema_version", "epoch", "archive_hash", "archive"]);
  const key = parseTransferKey({ schema_version: value.schema_version, epoch: value.epoch, archive_hash: value.archive_hash });
  need(isObject(value.archive), "invalid_replay_archive");
  boundedArchiveStructure(value.archive);
  const serialized = canonicalJson(value.archive);
  need(new TextEncoder().encode(serialized).byteLength <= MAX_REPLAY_ARCHIVE_BYTES, "replay_archive_too_large");
  need(await digest(serialized) === key.archive_hash, "replay_archive_mismatch");
  return { key, archive: value.archive as ReplayArchive };
}
/** Exact server-retained content hash authorizes restoration, never arbitrary imported SQL. */
export function restoreReplay(storage: DurableObjectStorage, tombstone: TransferredRoom, transfer: ReplayTransfer, archive: ReplayArchive): ReplayTransfer {
  need(transfer.transferred && same(factsForArchive(archive, transfer.manifest.epoch, transfer.manifest.archive_hash), transfer.manifest), "replay_archive_mismatch");
  // A restore cannot roll back photo uploads/deletions, reactions, or any retry receipt.
  const { replay_transfer_version: _version, checkpoint_hash: _hash, ...metadata } = tombstone; void _version; void _hash;
  storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify({ ...metadata, checkpoint: archive.room.checkpoint }));
  for (const turn of archive.turns) storage.sql.exec("UPDATE turns SET data=? WHERE turn_id=?", JSON.stringify(turn.recording), turn.turn_id);
  for (const pair of archive.pairs) storage.sql.exec("UPDATE pairs SET data=? WHERE pair_id=?", JSON.stringify(pair), pair.pair_id);
  const next: ReplayTransfer = { ...transfer, manifest: { ...transfer.manifest, epoch: transfer.manifest.epoch + 1 }, acked_player_ids: [], transferred: false };
  writeTransfer(storage, next);
  return next;
}

/** Metadata remains verifiable after the bytes it describes have left the server. */
export function validateTransfer(input: unknown): ReplayTransfer {
  const value = object(input); exact(value, ["schema_version", "manifest", "acked_player_ids", "transferred"]); need(value.schema_version === 1 && typeof value.transferred === "boolean");
  const m = object(value.manifest); exact(m, ["schema_version", "epoch", "archive_hash", "room", "turns", "pairs"]);
  need(m.schema_version === 1 && hash(m.archive_hash)); integer(m.epoch, 1, Number.MAX_SAFE_INTEGER);
  const r = object(m.room); exact(r, ["schema_version", "room_id", "revision", "branch", "stage_index", "level_id", "level_version", "definition_hash", "host_id", "guest_id", "checkpoint_hash", "a_turn_id", "completed_pair_ids", "invite_expires_at", "created_at", "updated_at", ...(r.simulation_version === undefined ? [] : ["simulation_version"])]);
  const selected = chapter(r); need(r.schema_version === 2 && r.stage_index === 2 && r.a_turn_id === null && hash(r.checkpoint_hash));
  text(r.room_id, ID_PATTERN); text(r.host_id, ID_PATTERN); text(r.guest_id, ID_PATTERN); need(r.host_id !== r.guest_id);
  integer(r.revision, 1, Number.MAX_SAFE_INTEGER); integer(r.branch, 0, 31); for (const name of ["created_at", "updated_at", "invite_expires_at"]) iso(r[name]);
  const simulation = r.simulation_version ?? selected.simulation_version;
  need((selected.supported_simulation_versions ?? [selected.simulation_version]).includes(simulation as number));
  need(Array.isArray(m.turns) && m.turns.length >= 4 && m.turns.length <= 128 && Array.isArray(m.pairs) && m.pairs.length >= 2 && m.pairs.length <= 64);
  const turns = new Map<string, Record<string, unknown>>();
  for (const item of m.turns) {
    const t = object(item); exact(t, ["turn_id", "player_id", "accepted_revision", "recording_hash"]); text(t.turn_id, /^t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$/); need(hash(t.recording_hash));
    const [branch, index, role] = (t.turn_id as string).slice(1).split("-"); need(Number(branch) <= Number(r.branch));
    const first = selected.stages[Number(index)].first_player_slot === "p0" ? r.host_id : r.guest_id;
    need(t.player_id === (role === "a" ? first : first === r.host_id ? r.guest_id : r.host_id)); integer(t.accepted_revision, 1, Number(r.revision));
    need(!turns.has(t.turn_id as string)); turns.set(t.turn_id as string, t);
  }
  const pairs = new Map<string, Record<string, unknown>>();
  for (const item of m.pairs) {
    const p = object(item); exact(p, ["pair_id", "branch", "stage_index", "a_hash", "b_hash", "checkpoint_hash"]);
    integer(p.branch, 0, Number(r.branch)); integer(p.stage_index, 0, 1); need(p.pair_id === `p${p.branch}-${p.stage_index}` && !pairs.has(String(p.pair_id)) && hash(p.checkpoint_hash));
    need(turns.get(`t${p.branch}-${p.stage_index}-a`)?.recording_hash === p.a_hash && turns.get(`t${p.branch}-${p.stage_index}-b`)?.recording_hash === p.b_hash);
    pairs.set(String(p.pair_id), p);
  }
  need(Array.isArray(r.completed_pair_ids) && r.completed_pair_ids.length === 2);
  r.completed_pair_ids.forEach((id, index) => need(pairs.get(String(id))?.stage_index === index));
  need(pairs.get(String(r.completed_pair_ids[1]))?.checkpoint_hash === r.checkpoint_hash);
  need(pairs.get(String(r.completed_pair_ids[1]))?.branch === r.branch);
  for (const t of turns.values()) {
    const [branch, index, role] = String(t.turn_id).slice(1).split("-");
    if (Number(branch) === r.branch) need(r.completed_pair_ids[Number(index)] === `p${branch}-${index}`);
    if (role === "b") need(pairs.has(`p${branch}-${index}`));
  }
  need(Array.isArray(value.acked_player_ids) && same(value.acked_player_ids, [r.host_id, r.guest_id].filter(id => (value.acked_player_ids as unknown[]).includes(id))));
  need(value.transferred === (value.acked_player_ids.length === 2));
  return value as ReplayTransfer;
}
export function validateCompactedReplay(rows: Row[][], raw: Record<string, unknown>, transfer: ReplayTransfer) {
  const m = transfer.manifest;
  need(transfer.transferred && raw.replay_transfer_version === 1);
  const { invite_code, replay_transfer_version: _version, ...safe } = raw; void _version;
  text(invite_code, /^[A-F0-9]{20}$/); need(same(safe, m.room));
  const [, turns, pairs, operations] = rows;
  need(turns.length === m.turns.length && pairs.length === m.pairs.length);
  for (const row of turns) { const t = m.turns.find(t => t.turn_id === row.turn_id); need(t && t.player_id === row.player_id && t.accepted_revision === row.accepted_revision && same(JSON.parse(String(row.data)), { recording_hash: t.recording_hash })); }
  for (const row of pairs) { const p = m.pairs.find(p => p.pair_id === row.pair_id); need(p && same(JSON.parse(String(row.data)), compactPair(p))); }
  const checkpoints = new Map([[chapter(m.room).initial().checkpoint_hash, 0], ...m.pairs.map(p => [p.checkpoint_hash, p.stage_index + 1] as [string, number])]);
  const revisions = new Set<number>(), seen = new Set<string>();
  for (const row of operations) {
    const r = object(JSON.parse(String(row.receipt))); exact(r, ["schema_version", "room_id", "idempotency_key", "request_hash", "operation", "accepted_revision", "branch", "stage_index", "stage_id", "turn_id", "recording_hash", "pair_id", "checkpoint_hash"]);
    const [owner, key, ...extra] = String(row.request_key).split(":"); need(!extra.length && [m.room.host_id, m.room.guest_id].includes(owner)); text(key, IDEMPOTENCY_PATTERN);
    need(r.schema_version === 2 && r.room_id === m.room.room_id && r.idempotency_key === key && r.request_hash === row.request_hash && hash(r.request_hash));
    integer(r.accepted_revision, 1, m.room.revision); need(!revisions.has(Number(r.accepted_revision))); revisions.add(Number(r.accepted_revision));
    integer(r.branch, 0, m.room.branch); integer(r.stage_index, 0, 1); need(r.stage_id === chapter(m.room).stages[Number(r.stage_index)].id && checkpoints.has(String(r.checkpoint_hash)));
    if (r.operation === "turns") {
      const t = m.turns.find(t => t.turn_id === r.turn_id); need(t && t.player_id === owner && t.accepted_revision === r.accepted_revision && t.recording_hash === r.recording_hash && !seen.has(t.turn_id)); seen.add(t.turn_id);
      need(t.turn_id.startsWith(`t${r.branch}-${r.stage_index}-`));
      if (t.turn_id.endsWith("-a")) need(r.pair_id === null && checkpoints.get(String(r.checkpoint_hash)) === r.stage_index);
      else { const p = m.pairs.find(p => p.pair_id === r.pair_id); need(p && p.pair_id === `p${r.branch}-${r.stage_index}` && p.checkpoint_hash === r.checkpoint_hash); }
    } else need(r.operation === "fork" && Number(r.branch) > 0 && r.turn_id === null && r.recording_hash === null && r.pair_id === null && checkpoints.get(String(r.checkpoint_hash)) === r.stage_index);
  }
  need(seen.size === turns.length, "snapshot_missing_receipt");
  return { state: m.room, turns: new Map(m.turns.map(t => [t.turn_id, { recording: { recording_hash: t.recording_hash }, row: { player_id: t.player_id } }])), pairs: new Map(m.pairs.map(p => [p.pair_id, { a: { recording_hash: p.a_hash }, b: { recording_hash: p.b_hash } }])) };
}
