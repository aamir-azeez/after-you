/**
 * Operator-only count and erase of Story (campaign, api_version 3) data, under /operator/story/.
 *
 * The router reaches this only while CONFIG lists STORY_DRAIN_ENABLED; otherwise the path falls
 * through to player authentication exactly as before. Every request first passes the operator
 * credential check (requireOperator). A player credential never passes it.
 *
 * Durable Objects cannot be listed from the Worker, so a driver supplies the ids in bounded
 * batches. Each request is stateless, which makes a stopped run resumable: run it again.
 * - scan:  Player object ids -> each identity's v3 links and campaign intents. Read-only.
 * - count: campaign root ids -> each root's and child room's rows. Read-only.
 * - erase: one root id plus the player ids holding links to it. The root is erased by the
 *   same cascade identity deletion uses (RoomV2.eraseCampaignRoot), then each active player's
 *   link is released by the same terminal-link path a campaign client uses
 *   (campaignTerminalScope, campaignTerminalFact, finalizeCampaignTerminalLink).
 *   A tombstoned root is not erased again, and a released link is not touched again.
 *   An identity already being deleted is left to identity deletion.
 */
import { ApiError, ID_PATTERN, boundedJson, isObject, object, type Outcome } from "../protocol";
import { roomLinkVersion, validRoomLink } from "../room-links";
import { requireOperator } from "../operator-auth";
import type { ServerVars } from "../flags";
import { validCampaignCreation, type CampaignCreation } from "./campaign-creation-intent";
import { campaignStoragePresent } from "./campaign-storage";

export const DRAIN_PREFIX = "/operator/story/";
/** Player objects per scan: one Durable Object request each. */
export const MAX_SCAN_PLAYERS = 20;
/** Roots per count: up to nine Durable Object requests each (the root and eight chapters). */
export const MAX_COUNT_ANCHORS = 2;
/** Players per erase: a host, a guest and a few guests whose Join never landed. */
export const MAX_ERASE_PLAYERS = 8;
const OBJECT_ID = /^[a-f0-9]{64}$/;

export type CampaignPlayerInventory = {
  schema_version: 1; player_id: string | null; state: "active" | "deleting" | null;
  links: { room_id: string; host: boolean }[];
  /** creation_schema 2 (an admitted Create) and creation_schema 3 (open or closed admission intents). */
  intents: { allocations: number; open: number; closed: number; unreadable: number };
  /** Rooms named by open admission intents, so an open intent whose link is gone still names its root. */
  open_intent_rooms: string[];
};
export type CampaignRoomCensus = {
  schema_version: 1;
  /** absent: no room was ever stored; ordinary: no campaign rows; deleted: only the tombstone marks remain. */
  kind: "absent" | "ordinary" | "campaign" | "deleted" | "unreadable";
  campaign_room_id: string | null; state: string | null; host_id: string | null; guest_id: string | null;
  /** Chapter rooms the root still lists and has not tombstoned. Only filled for a root. */
  children: string[];
  /** A prepared next chapter that may never have been created. It is erased with the root but never read here. */
  pending_targets: string[];
  /** Row count per table for a campaign room (metadata excluded). Empty for every other kind. */
  rows: Record<string, number>;
};

/** The census of a room that holds nothing: never created, or tables with no rows. */
export function absentCensus(): CampaignRoomCensus {
  return { schema_version: 1, kind: "absent", campaign_room_id: null, state: null, host_id: null, guest_id: null, children: [], pending_targets: [], rows: {} };
}
/** The inventory of a Player that holds nothing: no identity, links or intents. */
export function blankPlayerInventory(): CampaignPlayerInventory {
  return { schema_version: 1, player_id: null, state: null, links: [], intents: { allocations: 0, open: 0, closed: 0, unreadable: 0 }, open_intent_rooms: [] };
}

function parsed(data: string): unknown { try { return JSON.parse(data); } catch { return undefined; } }

/** Read-only Player inventory. Runs inside the Player object. */
export function campaignPlayerInventory(storage: DurableObjectStorage): CampaignPlayerInventory {
  const identity = parsed(storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").toArray()[0]?.data ?? "null");
  const known = isObject(identity) && typeof identity.player_id === "string" && (identity.state === "active" || identity.state === "deleting");
  const links: CampaignPlayerInventory["links"] = [];
  for (const row of storage.sql.exec<{ data: string }>("SELECT data FROM rooms ORDER BY rowid").toArray()) {
    const link = parsed(row.data);
    if (validRoomLink(link) && roomLinkVersion(link) === 3) links.push({ room_id: link.room_id, host: link.host });
  }
  const intents = { allocations: 0, open: 0, closed: 0, unreadable: 0 }, openRooms = new Set<string>();
  for (const row of storage.sql.exec<{ data: string }>("SELECT data FROM creations ORDER BY rowid").toArray()) {
    const value = parsed(row.data);
    if (!isObject(value)) { intents.unreadable++; continue; }
    if (value.creation_schema === 2) intents.allocations++;
    else if (value.creation_schema === 3) { if (value.state === "open") { intents.open++; if (typeof value.room_id === "string" && ID_PATTERN.test(value.room_id)) openRooms.add(value.room_id); } else if (value.state === "closed") intents.closed++; else intents.unreadable++; }
  }
  return { schema_version: 1, player_id: known ? identity.player_id as string : null, state: known ? identity.state as "active" | "deleting" : null, links, intents, open_intent_rooms: [...openRooms] };
}

/** The admitted host allocation for a root that was never created, as identity deletion builds it. Read-only. */
export function campaignPlayerAllocation(storage: DurableObjectStorage, roomId: string): { schema_version: 1; host_id: string; intent: CampaignCreation } | null {
  const identity = parsed(storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").toArray()[0]?.data ?? "null");
  if (!isObject(identity) || identity.state !== "active" || typeof identity.player_id !== "string") return null;
  for (const row of storage.sql.exec<{ data: string }>("SELECT data FROM creations ORDER BY rowid").toArray()) {
    const value = parsed(row.data);
    if (validCampaignCreation(value) && value.link.host && value.link.room_id === roomId) return { schema_version: 1, host_id: identity.player_id, intent: value };
  }
  return null;
}

/** Read-only RoomV2 census. Runs inside the room object and never parses gameplay rows. */
export function campaignRoomCensus(storage: DurableObjectStorage, roomId: string): CampaignRoomCensus {
  const census = absentCensus();
  try {
    if (!campaignStoragePresent(storage)) {
      census.kind = storage.sql.exec("SELECT 1 FROM room LIMIT 1").toArray().length ? "ordinary" : "absent";
      return census;
    }
    const member = parsed(storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member WHERE id=1").toArray()[0]?.data ?? "null");
    if (isObject(member) && typeof member.campaign_room_id === "string") census.campaign_room_id = member.campaign_room_id;
    if (isObject(member) && member.status === "deleted") { census.kind = "deleted"; return census; }
    census.kind = "campaign";
    const tables = storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE '\\_cf\\_%' ESCAPE '\\' AND name NOT IN ('metadata','sqlite_sequence') ORDER BY name").toArray();
    for (const { name } of tables) {
      const count = storage.sql.exec<{ n: number }>('SELECT COUNT(*) AS n FROM "' + name.replaceAll('"', '""') + '"').one().n;
      if (count > 0) census.rows[name] = count;
    }
    const anchor = parsed(storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor WHERE id=1").toArray()[0]?.data ?? "null");
    if (!isObject(anchor) || !isObject(anchor.control)) return census;
    const control = anchor.control, deletion = isObject(anchor.deletion) ? anchor.deletion : null;
    census.state = typeof control.state === "string" ? control.state : null;
    census.host_id = typeof control.host_id === "string" ? control.host_id : null;
    census.guest_id = typeof control.guest_id === "string" ? control.guest_id : null;
    const done = new Set(Array.isArray(deletion?.completed_room_ids) ? deletion.completed_room_ids.filter((id): id is string => typeof id === "string") : []);
    const pending = isObject(anchor.pending) && isObject(anchor.pending.target_intent) && typeof anchor.pending.target_intent.room_id === "string" ? anchor.pending.target_intent.room_id : null;
    const chapters = (Array.isArray(control.chapters) ? control.chapters : []).flatMap(entry => isObject(entry) && typeof entry.room_id === "string" ? [entry.room_id] : []);
    const listed = [...chapters, ...(Array.isArray(deletion?.room_ids) ? deletion.room_ids.filter((id): id is string => typeof id === "string" && id !== pending) : [])];
    census.children = [...new Set(listed)].filter(id => id !== roomId && ID_PATTERN.test(id) && !done.has(id));
    if (pending && pending !== roomId && !done.has(pending) && !census.children.includes(pending)) census.pending_targets = [pending];
    return census;
  } catch {
    return { ...census, kind: "unreadable", rows: {} };
  }
}

function input(value: unknown, keys: string[]): Record<string, unknown> {
  const body = object(value);
  if (body.schema_version !== 1 || Object.keys(body).length !== keys.length || keys.some(key => !Object.hasOwn(body, key))) throw new ApiError(400, "invalid_story_drain_request");
  return body;
}
function ids(value: unknown, pattern: RegExp, min: number, max: number): string[] {
  if (!Array.isArray(value) || value.length < min || value.length > max || value.some(item => typeof item !== "string" || !pattern.test(item)) || new Set(value).size !== value.length) throw new ApiError(400, "invalid_story_drain_request");
  return value as string[];
}

export type StoryCountTotals = { campaign_rooms: number; deleted_rooms: number; absent_rooms: number; unreadable_rooms: number; pending_targets: number; rows: Record<string, number>; total_rows: number };
function addRows(totals: StoryCountTotals, room: CampaignRoomCensus): void {
  if (room.kind === "campaign") totals.campaign_rooms++;
  if (room.kind === "deleted") totals.deleted_rooms++;
  if (room.kind === "absent") totals.absent_rooms++;
  if (room.kind === "unreadable") totals.unreadable_rooms++;
  totals.pending_targets += room.pending_targets.length;
  for (const [name, count] of Object.entries(room.rows)) { totals.rows[name] = (totals.rows[name] ?? 0) + count; totals.total_rows += count; }
}

const UNREADABLE: CampaignRoomCensus = { ...absentCensus(), kind: "unreadable" };
/** One failing object reports "unreadable" instead of failing the whole batch. */
async function readCensus(env: Env, roomId: string): Promise<CampaignRoomCensus> {
  try { return await env.ROOMS_V2.getByName(roomId).campaignDrainCensus(roomId); } catch { return structuredClone(UNREADABLE); }
}
async function countAnchor(env: Env, roomId: string) {
  const root = await readCensus(env, roomId);
  const children: (CampaignRoomCensus & { room_id: string })[] = [];
  if (root.kind === "campaign" && root.campaign_room_id === roomId) {
    for (const child of root.children) children.push({ room_id: child, ...await readCensus(env, child) });
  }
  return { room_id: roomId, root, children };
}

type PlayerRelease = { player_id: string; result: string };
async function releaseLink(env: Env, playerId: string, roomId: string, fact: unknown): Promise<PlayerRelease> {
  try {
    const player = env.PLAYERS.getByName(playerId);
    const scope = await player.operatorCampaignTerminalScope(roomId);
    if (!scope.ok) return { player_id: playerId, result: scope.code };
    if (scope.value.link === null && scope.value.open_join_keys.length === 0) return { player_id: playerId, result: "no_link" };
    const released = await player.operatorFinalizeCampaignTerminalLink(scope.value, fact);
    return { player_id: playerId, result: released.ok ? "released" : released.code };
  } catch { return { player_id: playerId, result: "player_unavailable" }; }
}

async function eraseAnchor(env: Env, roomId: string, players: string[]) {
  const room = env.ROOMS_V2.getByName(roomId);
  const before = await readCensus(env, roomId);
  const report = { schema_version: 1 as const, room_id: roomId, before: before.kind, root: "", players: [] as PlayerRelease[], after: "" };
  if (before.kind === "ordinary" || before.kind === "unreadable" || before.campaign_room_id !== null && before.campaign_room_id !== roomId) {
    report.root = before.kind === "unreadable" ? "unreadable" : "not_campaign_root"; report.after = before.kind; return report;
  }
  if (before.kind === "deleted") report.root = "already_deleted";
  else try {
    let erased: Outcome<unknown>;
    if (before.kind === "campaign") erased = before.host_id ? await room.eraseCampaignRoot(before.host_id, roomId, null) : { ok: false, status: 409, code: "campaign_host_unknown" };
    else {
      // Never created: identity deletion fences this id with the host's admitted allocation.
      let allocation = null;
      for (const id of players) { allocation = await env.PLAYERS.getByName(id).operatorCampaignAllocation(roomId); if (allocation) break; }
      erased = allocation ? await room.eraseCampaignRoot(allocation.host_id, roomId, allocation) : { ok: false, status: 409, code: "campaign_allocation_unavailable" };
    }
    report.root = erased.ok ? "erased" : erased.code;
  } catch { report.root = "root_unavailable"; }
  if (report.root === "erased" || report.root === "already_deleted") {
    let fact: Outcome<unknown>;
    try { fact = await room.campaignTerminalFact(roomId); } catch { fact = { ok: false, status: 503, code: "root_unavailable" }; }
    for (const id of players) report.players.push(fact.ok ? await releaseLink(env, id, roomId, fact.value) : { player_id: id, result: fact.code });
  }
  report.after = (await readCensus(env, roomId)).kind;
  return report;
}

/** POST /operator/story/{scan,count,erase}. The router calls this only while the flag is on. */
export async function routeCampaignDrain(request: Request, path: string, env: Env & ServerVars): Promise<unknown> {
  await requireOperator(request, env);
  const action = path.slice(DRAIN_PREFIX.length);
  if (!["scan", "count", "erase"].includes(action)) throw new ApiError(404, "not_found");
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const raw = await boundedJson(request, 4096);
  if (action === "scan") {
    const objects = ids(input(raw, ["schema_version", "players"]).players, OBJECT_ID, 1, MAX_SCAN_PLAYERS);
    const players = [];
    for (const objectId of objects) {
      try { players.push({ object_id: objectId, ...await env.PLAYERS.get(env.PLAYERS.idFromString(objectId)).campaignDrainInventory() }); }
      catch { players.push({ object_id: objectId, schema_version: 1 as const, error: "unreadable" }); }
    }
    return { schema_version: 1, players };
  }
  if (action === "count") {
    const anchors = [];
    const totals: StoryCountTotals = { campaign_rooms: 0, deleted_rooms: 0, absent_rooms: 0, unreadable_rooms: 0, pending_targets: 0, rows: {}, total_rows: 0 };
    for (const roomId of ids(input(raw, ["schema_version", "anchors"]).anchors, ID_PATTERN, 1, MAX_COUNT_ANCHORS)) {
      const counted = await countAnchor(env, roomId);
      addRows(totals, counted.root); for (const child of counted.children) addRows(totals, child);
      anchors.push(counted);
    }
    return { schema_version: 1, anchors, totals };
  }
  const body = input(raw, ["schema_version", "anchor", "players"]);
  const [roomId] = ids([body.anchor], ID_PATTERN, 1, 1);
  return eraseAnchor(env, roomId, ids(body.players, ID_PATTERN, 0, MAX_ERASE_PLAYERS));
}
