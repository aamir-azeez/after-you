import type { Outcome } from "./protocol";
import { roomLinkVersion, type RoomLink } from "./room-links";
import type { RoomInboxProjection } from "./room-inbox";
import { memberStateOf, type MemberRoomState } from "./room-leave";

/**
 * The room index: one row per linked v1 or v2 room in the Player's own storage,
 * holding what that room last said about this member. Lists and the inbox use
 * it to choose a bounded page and to skip reading rooms whose rows are fresh.
 * Membership is always checked by the room itself; a row never grants access.
 */

/**
 * Subrequests one request or alarm may spend on the indexed paths. Workers allow
 * 1,000 calls to Cloudflare services per invocation; this keeps 4x margin.
 */
export const ROOM_INDEX_BUDGET = 250;
/** Rooms on its page one inbox request may read live: unindexed and unchecked links and rows in play. */
export const ROOM_INDEX_READS = 60;
/** Rows one inbox request may re-check, oldest check first, so every row past its window is re-verified within ceil(rows / 8) inbox reads. */
export const ROOM_INDEX_RECHECKS = 8;
/**
 * How long a finished or gone row is served without a live read. Rows in play
 * are always read live. A room pushes when it becomes finished, when a fork or
 * advance reopens it and when it is erased, so the window only bounds how long
 * a lost push can last.
 */
export const ROOM_INDEX_SETTLED_FRESH_MS = 24 * 3_600_000;
/** Rooms on one inbox page. Clients from 0.6.0 refuse an inbox of more than 100. */
export const ROOM_INBOX_PAGE = 100;
/** Rooms on one GET /v1/rooms or /v2/rooms page, today's proven size for full room snapshots. */
export const ROOM_LIST_PAGE = 60;
/** Optional request header: a decimal offset into the page order. */
export const ROOM_PAGE_HEADER = "X-AfterYou-Room-Page";
/** Answer header present only when more rooms follow the page: the next offset. */
export const ROOM_NEXT_HEADER = "X-AfterYou-Room-Next";

export const ROOM_INDEX_TABLE = {
  name: "room_index",
  schema: "CREATE TABLE room_index (room_id TEXT PRIMARY KEY, api_version INTEGER NOT NULL, state TEXT NOT NULL, activity_ms INTEGER NOT NULL, observed_at INTEGER NOT NULL, checked_at INTEGER NOT NULL, entry TEXT)"
} as const;
/** Present only while an identity deletion continues in the Player's alarm; `failed` lists the rooms its last batch could not erase. */
export const ROOM_ERASURE_TABLE = {
  name: "room_erasure",
  schema: "CREATE TABLE room_erasure (id INTEGER PRIMARY KEY CHECK(id=1), attempts INTEGER NOT NULL, next_at INTEGER NOT NULL, failed TEXT NOT NULL)"
} as const;
/** Operational tables, accepted by the snapshot schema check only in exactly this form and never exported. */
export const ROOM_INDEX_TABLES = [ROOM_INDEX_TABLE, ROOM_ERASURE_TABLE] as const;
export function isRoomIndexTable(row: { name: string; sql: string }): boolean {
  return ROOM_INDEX_TABLES.some(table => table.name === row.name && table.schema === row.sql);
}

/** "unchecked" marks a link with no lasting answer yet (a failed read, or a 404); it counts as in play, shows as unavailable and is read again. */
export type RoomIndexState = MemberRoomState | "unchecked";
/** What a room said about one member, stamped with the room's own clock. */
export type RoomObservation = { observed_at: number; outcome: Outcome<RoomInboxProjection> };
/** `outcome` is the stored answer: the projection, or the room's 404 or 410. */
export type RoomIndexRow = { state: RoomIndexState; observed_at: number; checked_at: number; outcome: Outcome<RoomInboxProjection> | null };
export type IndexedRoom = { link: RoomLink; row: RoomIndexRow | null; read: boolean };
/** `rooms` is in link order (newest first); `recheck` are rows off the page to re-read for the index only. */
export type RoomIndexPage = { rooms: IndexedRoom[]; recheck: RoomLink[]; next: number | null };
export type RoomFamily = "inbox" | "legacy" | "relay";

type JoinedRow = { data: string; state: RoomIndexState | null; api_version: number | null; activity_ms: number | null; observed_at: number | null; checked_at: number | null; entry: string | null };
type Candidate = { link: RoomLink; position: number; row: RoomIndexRow | null; checked: number; activity: number };

/**
 * The tables exist only once used, so most Players have none. Statements on
 * them run without probing sqlite_master first; "no such table" means empty.
 */
function orMissing<T>(run: () => T, missing: T): T {
  try { return run(); }
  catch (error) { if (error instanceof Error && error.message.includes("no such table")) return missing; throw error; }
}
export function ensureRoomIndex(storage: DurableObjectStorage): void {
  storage.sql.exec(ROOM_INDEX_TABLE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
}
/** Drops both operational tables, after an erasure or a snapshot restore. */
export function dropRoomIndex(storage: DurableObjectStorage): void {
  for (const table of ROOM_INDEX_TABLES) storage.sql.exec(`DROP TABLE IF EXISTS ${table.name}`);
}
export function removeRoomIndexRow(storage: DurableObjectStorage, roomId: string): void {
  orMissing(() => storage.sql.exec("DELETE FROM room_index WHERE room_id=?", roomId), null);
}

/**
 * How many different partners `player` has in rooms whose last projection here
 * reached `minRevision`, counting up to `limit`. Rooms the index never saw do
 * not count, and a Player without the index reads 0 (leaderboards/standing.ts).
 */
export function indexedPartners(storage: DurableObjectStorage, player: string, minRevision: number, limit: number): number {
  const partners = new Set<string>();
  const rows = orMissing(() => storage.sql.exec<{ entry: string }>("SELECT entry FROM room_index WHERE entry IS NOT NULL").toArray(), []);
  for (const row of rows) {
    if (partners.size >= limit) break;
    let outcome: Outcome<RoomInboxProjection>;
    try { outcome = JSON.parse(row.entry) as Outcome<RoomInboxProjection>; } catch { continue; }
    if (!outcome.ok || typeof outcome.value.revision !== "number" || outcome.value.revision < minRevision) continue;
    const { host_id: host, guest_id: guest } = outcome.value.membership;
    const partner = host === player ? guest : guest === player ? host : null;
    if (typeof partner === "string" && partner !== player) partners.add(partner);
  }
  return partners.size;
}

const indexed = (version: number) => version === 1 || version === 2;
/** A projection, 404 or 410 says something lasting; a throw or any other refusal does not. */
const lasting = (outcome: Outcome<RoomInboxProjection>) => outcome.ok || outcome.status === 404 || outcome.status === 410;
/**
 * The stored state of an answer, by the one member-state rule (memberStateOf);
 * null when it says nothing lasting. Only a 410 (the room was erased) is a
 * permanent refusal. A 404 also comes from a room whose link was reserved
 * before the room was initialized, so it is stored as "unchecked": shown as
 * unavailable, read again on the next inbox read, and never settled by the index.
 */
export function observedState(outcome: Outcome<RoomInboxProjection>): RoomIndexState | null {
  if (!lasting(outcome)) return null;
  return !outcome.ok && outcome.status === 404 ? "unchecked" : memberStateOf(outcome);
}

function linkedVersion(storage: DurableObjectStorage, roomId: string): number | null {
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", roomId).toArray()[0];
  return row ? roomLinkVersion(JSON.parse(row.data) as RoomLink) : null;
}

/**
 * Stores one observation of a linked room, newer wins: an observation older
 * than the stored one (by the room's clock) only refreshes `checked_at`. A null
 * observation or one without a lasting answer never replaces an answer; a link
 * without a row then gets an "unchecked" row that any real observation
 * replaces. Unlinked rooms are ignored.
 */
export function recordRoomObservation(storage: DurableObjectStorage, roomId: string, version: number, observation: RoomObservation | null, now = Date.now()): void {
  if (!indexed(version) || linkedVersion(storage, roomId) !== version) return;
  ensureRoomIndex(storage);
  const old = orMissing(() => storage.sql.exec<{ observed_at: number }>("SELECT observed_at FROM room_index WHERE room_id=?", roomId).toArray()[0], undefined);
  const state = observation ? observedState(observation.outcome) : null;
  if (state === null || (old && observation!.observed_at < old.observed_at)) {
    if (old) storage.sql.exec("UPDATE room_index SET checked_at=? WHERE room_id=?", now, roomId);
    else storage.sql.exec("INSERT INTO room_index VALUES (?,?,?,?,?,?,?)", roomId, version, "unchecked", 0, 0, now, null);
    return;
  }
  const outcome = observation!.outcome;
  storage.sql.exec("INSERT OR REPLACE INTO room_index VALUES (?,?,?,?,?,?,?)", roomId, version, state,
    outcome.ok ? Date.parse(outcome.value.activity_at ?? "") || 0 : 0, observation!.observed_at, now, JSON.stringify(outcome));
}

/** Every link, newest first, with its row (null when absent or of another version). */
function joined(storage: DurableObjectStorage): Candidate[] {
  const plain = () => storage.sql.exec<JoinedRow>("SELECT data,NULL AS state,NULL AS api_version,NULL AS activity_ms,NULL AS observed_at,NULL AS checked_at,NULL AS entry FROM rooms ORDER BY rowid DESC").toArray();
  const rows = orMissing(() => storage.sql.exec<JoinedRow>("SELECT r.data AS data,i.state AS state,i.api_version AS api_version,i.activity_ms AS activity_ms,i.observed_at AS observed_at,i.checked_at AS checked_at,i.entry AS entry FROM rooms r LEFT JOIN room_index i ON i.room_id=r.room_id ORDER BY r.rowid DESC").toArray(), null) ?? plain();
  return rows.map((value, position) => {
    const link = JSON.parse(value.data) as RoomLink;
    const row = value.state !== null && value.api_version === roomLinkVersion(link)
      ? { state: value.state, observed_at: value.observed_at!, checked_at: value.checked_at!, outcome: value.entry === null ? null : JSON.parse(value.entry) as Outcome<RoomInboxProjection> }
      : null;
    return { link, position, row, checked: row?.checked_at ?? -1, activity: value.activity_ms ?? 0 };
  });
}

const settledState = (row: RoomIndexRow | null) => row?.state === "finished" || row?.state === "gone";
/** 0: unindexed, unchecked or in play; 1: settled rows; 2: links the index never holds (Story v3 and unknown versions). */
function tier(candidate: Candidate): number {
  if (!indexed(roomLinkVersion(candidate.link))) return 2;
  return settledState(candidate.row) ? 1 : 0;
}
/** Whether a row needs a live read: no row or no lasting answer yet, a room in play, or a settled row checked longer ago than its window. */
function due(candidate: Candidate, now: number): boolean {
  const row = candidate.row;
  return !row || row.state === "unchecked" || row.state === "in_play" || now - row.checked_at >= ROOM_INDEX_SETTLED_FRESH_MS;
}

/**
 * One page of a player's rooms. The page is a slice of the relevance order
 * (rooms in play and unindexed links first, then settled rooms, then links the
 * index never holds; newest activity first within each, then newest link), put
 * back in link order. For the inbox, unindexed and unchecked links and rows in
 * play on the page are marked `read`, unindexed first and
 * then the oldest check, up to ROOM_INDEX_READS. Settled rows are never read
 * just for being on the page: up to ROOM_INDEX_RECHECKS rows past their window,
 * on or off the page, are re-checked by oldest check. The v1 and v2 lists read
 * every room on the page.
 */
export function roomIndexPage(storage: DurableObjectStorage, family: RoomFamily, offset: number, now = Date.now()): RoomIndexPage {
  const all = joined(storage).filter(item => family === "inbox" || roomLinkVersion(item.link) === (family === "legacy" ? 1 : 2));
  const size = family === "inbox" ? ROOM_INBOX_PAGE : ROOM_LIST_PAGE;
  const ordered = [...all].sort((a, b) => tier(a) - tier(b) || b.activity - a.activity || a.position - b.position);
  const start = Math.min(Math.max(0, offset), ordered.length);
  const page = ordered.slice(start, start + size);
  const next = start + size < ordered.length ? start + size : null;
  const onPage = new Set(page);
  const reads = new Set<Candidate>();
  if (family === "inbox") {
    const oldestCheck = (a: Candidate, b: Candidate) => a.checked - b.checked || a.position - b.position;
    const live = (item: Candidate) => indexed(roomLinkVersion(item.link)) && !settledState(item.row) && due(item, now);
    for (const item of page.filter(live).sort(oldestCheck).slice(0, ROOM_INDEX_READS)) reads.add(item);
    for (const item of all.filter(item => item.row && !reads.has(item) && due(item, now)).sort(oldestCheck).slice(0, ROOM_INDEX_RECHECKS)) reads.add(item);
  } else for (const item of page) reads.add(item);
  return {
    rooms: page.sort((a, b) => a.position - b.position).map(item => ({ link: item.link, row: item.row, read: reads.has(item) })),
    recheck: [...reads].filter(item => !onPage.has(item)).map(item => item.link),
    next
  };
}

/** Settled linked rooms by the index, and how many v1 and v2 links still have no row. */
export function roomIndexCount(storage: DurableObjectStorage): { settled: string[]; unindexed: number } {
  const all = joined(storage).filter(item => indexed(roomLinkVersion(item.link)));
  return { settled: all.filter(item => settledState(item.row)).map(item => item.link.room_id), unindexed: all.filter(item => !item.row).length };
}

/**
 * The order an identity deletion above ROOM_DELETION_BATCH (room-links.ts)
 * takes its links in. Rooms the player hosts that the index cannot vouch for as
 * settled come first: in play, unindexed or unchecked. Within those, rooms with
 * no guest and links with no stored answer come before rooms in play with a
 * guest, because every room still waiting for a guest is one of them; so the
 * first batch erases those before a stranger could join one. The rest keep
 * link order.
 */
export function deletionOrder(storage: DurableObjectStorage, links: readonly RoomLink[]): RoomLink[] {
  const rank = new Map<string, number>();
  for (const item of joined(storage)) {
    if (!item.link.host || tier(item) !== 0) continue;
    const outcome = item.row?.outcome;
    rank.set(item.link.room_id, !outcome || !outcome.ok || outcome.value.membership.guest_id === null ? 0 : 1);
  }
  const order = (link: RoomLink) => rank.get(link.room_id) ?? 2;
  return [...links].sort((a, b) => order(a) - order(b));
}

/** v1 and v2 links the index cannot vouch for as settled: unindexed first, then rows in play by oldest check. */
export function roomIndexUnsettled(storage: DurableObjectStorage, limit: number): RoomLink[] {
  return joined(storage).filter(item => tier(item) === 0).sort((a, b) => a.checked - b.checked || a.position - b.position).slice(0, limit).map(item => item.link);
}

/** The alarm delay after a deletion batch: one second after progress, then doubling to an hour while a room keeps failing. */
export function roomErasureDelay(attempts: number): number { return Math.min(3_600_000, 1000 * 2 ** Math.min(attempts, 12)); }
export type RoomErasure = { attempts: number; next_at: number; failed: string[] };
export function roomErasurePending(storage: DurableObjectStorage): RoomErasure | null {
  const row = orMissing(() => storage.sql.exec<{ attempts: number; next_at: number; failed: string }>("SELECT attempts,next_at,failed FROM room_erasure WHERE id=1").toArray()[0], undefined);
  return row ? { attempts: row.attempts, next_at: row.next_at, failed: JSON.parse(row.failed) as string[] } : null;
}
/** Records the next deletion batch; the caller sets the alarm to `next_at`. */
export function writeRoomErasure(storage: DurableObjectStorage, value: RoomErasure): void {
  storage.sql.exec(ROOM_ERASURE_TABLE.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  storage.sql.exec("INSERT OR REPLACE INTO room_erasure VALUES (1,?,?,?)", value.attempts, value.next_at, JSON.stringify(value.failed));
}
export function clearRoomErasure(storage: DurableObjectStorage): void {
  storage.sql.exec(`DROP TABLE IF EXISTS ${ROOM_ERASURE_TABLE.name}`);
}
