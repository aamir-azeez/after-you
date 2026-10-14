import { fail, ok, type Outcome } from "./protocol";
import { roomLinkVersion, type RoomLink } from "./room-links";
import { interactionBlocked } from "./safety";
import { remoteRoomActivity } from "./room-inbox-storage";
import { chapter } from "./v2/chapters";

export type RoomInboxStatus = "waiting_for_friend" | "your_turn" | "waiting_for_their_turn" | "completed" | "unavailable" | "closed";
/** Clients from 0.5.2 send this header and understand the "closed" status; older clients validate the status list exactly. */
export const ROOM_INBOX_CLOSED_HEADER = "X-AfterYou-Room-Inbox";
export type RoomInboxEntry = {
  room_id: string; family: "legacy" | "relay" | "story" | "unknown"; api_version: number;
  chapter: { id: string | null; version: number | null };
  membership: { host_id: string | null; guest_id: string | null; you_are_host: boolean };
  status: RoomInboxStatus; revision: number | null; remote_activity_sequence: number; activity_at: string | null;
};
export type RoomInboxProjection = Omit<RoomInboxEntry, "family" | "api_version">;

/** A room erased by a member (closed, or their identity deleted) keeps only a tombstone row. */
function closedRoom(storage: DurableObjectStorage): boolean {
  return storage.sql.exec("SELECT 1 AS closed FROM room WHERE id=1 AND json_extract(data,'$.deleted') IS 1").toArray().length > 0;
}

function turnStatus(player: string, guest: string | null, active: string | null): RoomInboxStatus {
  if (!guest) return "waiting_for_friend";
  if (!active) return "completed";
  return active === player ? "your_turn" : "waiting_for_their_turn";
}

/** Legacy room summary reads only scalar JSON fields and the separate activity row. */
export function legacyInboxProjection(storage: DurableObjectStorage, player: string): Outcome<RoomInboxProjection> {
  const row = storage.sql.exec<{
    room_id: string; revision: number; level_id: string; host_id: string; guest_id: string | null;
    first_player_id: string; active_role: string; updated_at: string;
  }>("SELECT json_extract(data,'$.room_id') AS room_id,json_extract(data,'$.revision') AS revision,json_extract(data,'$.level_id') AS level_id,json_extract(data,'$.host_id') AS host_id,json_extract(data,'$.guest_id') AS guest_id,json_extract(data,'$.first_player_id') AS first_player_id,json_extract(data,'$.active_role') AS active_role,json_extract(data,'$.updated_at') AS updated_at FROM room WHERE id=1 AND json_extract(data,'$.deleted') IS NOT 1").toArray()[0];
  if (!row && closedRoom(storage)) return fail(410, "room_closed");
  if (!row || (row.host_id !== player && row.guest_id !== player)) return fail(404, "room_not_found");
  const active = row.active_role === "complete" ? null : row.active_role === "a" ? row.first_player_id : row.first_player_id === row.host_id ? row.guest_id : row.host_id;
  const activity = remoteRoomActivity(storage, player);
  return ok({
    room_id: row.room_id, chapter: { id: row.level_id, version: 1 },
    membership: { host_id: row.host_id, guest_id: row.guest_id, you_are_host: row.host_id === player },
    status: turnStatus(player, row.guest_id, active), revision: row.revision,
    remote_activity_sequence: activity.sequence, activity_at: row.updated_at ?? activity.at
  });
}

/**
 * Relay-family projection also selects only small room metadata, never turn or pair data.
 * A room whose replay both members saved keeps these fields in its compacted row, so it
 * still reads as the finished chapter rather than an unknown room.
 */
export function relayInboxProjection(storage: DurableObjectStorage, player: string): Outcome<RoomInboxProjection> {
  const row = storage.sql.exec<{
    room_id: string; revision: number; stage_index: number; level_id: string; level_version: number;
    definition_hash: string; host_id: string; guest_id: string | null; a_turn_id: string | null; updated_at: string;
  }>("SELECT json_extract(data,'$.room_id') AS room_id,json_extract(data,'$.revision') AS revision,json_extract(data,'$.stage_index') AS stage_index,json_extract(data,'$.level_id') AS level_id,json_extract(data,'$.level_version') AS level_version,json_extract(data,'$.definition_hash') AS definition_hash,json_extract(data,'$.host_id') AS host_id,json_extract(data,'$.guest_id') AS guest_id,json_extract(data,'$.a_turn_id') AS a_turn_id,json_extract(data,'$.updated_at') AS updated_at FROM room WHERE id=1 AND json_extract(data,'$.deleted') IS NOT 1").toArray()[0];
  if (!row && closedRoom(storage)) return fail(410, "room_closed");
  if (!row || (row.host_id !== player && row.guest_id !== player)) return fail(404, "room_not_found");
  let active: string | null = null;
  try {
    const selected = chapter({ level_id: row.level_id, level_version: row.level_version, definition_hash: row.definition_hash });
    const stage = selected.stages[row.stage_index];
    if (stage) {
      const first = stage.first_player_slot === "p0" ? row.host_id : row.guest_id;
      const second = stage.first_player_slot === "p0" ? row.guest_id : row.host_id;
      active = row.a_turn_id ? second : first;
    }
  } catch { return fail(409, "unsupported_chapter"); }
  const activity = remoteRoomActivity(storage, player);
  return ok({
    room_id: row.room_id, chapter: { id: row.level_id, version: row.level_version },
    membership: { host_id: row.host_id, guest_id: row.guest_id, you_are_host: row.host_id === player },
    status: turnStatus(player, row.guest_id, active), revision: row.revision,
    remote_activity_sequence: activity.sequence, activity_at: row.updated_at ?? activity.at
  });
}

function fallback(link: RoomLink, status: RoomInboxStatus = "unavailable"): RoomInboxEntry {
  const version = roomLinkVersion(link);
  return { room_id: link.room_id, family: version === 1 ? "legacy" : version === 2 ? "relay" : version === 3 ? "story" : "unknown",
    api_version: version, chapter: { id: null, version: null },
    membership: { host_id: null, guest_id: null, you_are_host: link.host }, status,
    revision: null, remote_activity_sequence: 0, activity_at: null };
}

/**
 * Authenticated, bounded summary list. Unavailable links remain visible for recovery.
 * With showClosed, a room another member erased reads "closed" so its remaining
 * member can tell it apart and remove it; otherwise it stays "unavailable".
 */
export async function roomInbox(playerId: string, env: Env, showClosed = false): Promise<{ schema_version: 1; rooms: RoomInboxEntry[] }> {
  const links = await env.PLAYERS.getByName(playerId).listRooms();
  const rooms: RoomInboxEntry[] = [];
  for (const link of links) {
    const version = roomLinkVersion(link);
    if (version !== 1 && version !== 2) { rooms.push(fallback(link)); continue; }
    const result = version === 1
      ? await env.ROOMS.getByName(link.room_id).inboxProjection(playerId)
      : await env.ROOMS_V2.getByName(link.room_id).inboxProjection(playerId);
    if (!result.ok) { rooms.push(fallback(link, showClosed && result.status === 410 ? "closed" : "unavailable")); continue; }
    const value = result.value;
    if (await interactionBlocked(env, value.membership.host_id!, value.membership.guest_id)) continue;
    rooms.push({ ...value, family: version === 1 ? "legacy" : "relay", api_version: version });
  }
  rooms.sort((a, b) => (Date.parse(b.activity_at ?? "") || 0) - (Date.parse(a.activity_at ?? "") || 0));
  return { schema_version: 1, rooms };
}
