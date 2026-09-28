import { ID_PATTERN, fail, isObject, ok, type Outcome } from "./protocol";

export const MAX_FRIENDS = 20;
export const FRIEND_REFRESH_SECONDS = 30;
export const FRIEND_REQUEST_TTL_MS = 7 * 24 * 60 * 60 * 1000;
export type SharedFriendRoom = { api_version: 1 | 2; room_id: string };
export type FriendLink = { player_id: string; request_id: string; requested_by: string; accepted: boolean; created_at: number };
export type SocialState = { schema_version: 1; links: FriendLink[]; shared_room: SharedFriendRoom | null; next_refresh_at: number };
export type FriendEdge = { link: FriendLink; shared_room: SharedFriendRoom | null; presence_expires_at: number };
export type FriendRoomInvite = { room_id: string; invite_code: string };
export const emptySocial = (): SocialState => ({ schema_version: 1, links: [], shared_room: null, next_refresh_at: 0 });
const exact = (v: Record<string, unknown>, keys: string[]) => Object.keys(v).length === keys.length && keys.every(k => Object.hasOwn(v, k));
export function validSharedFriendRoom(v: unknown): v is SharedFriendRoom {
  return isObject(v) && exact(v, ["api_version", "room_id"]) && (v.api_version === 1 || v.api_version === 2) && typeof v.room_id === "string" && ID_PATTERN.test(v.room_id);
}
export function validSocial(v: unknown, owner: string): v is SocialState {
  return isObject(v) && exact(v, ["schema_version", "links", "shared_room", "next_refresh_at"]) && v.schema_version === 1 &&
    Number.isSafeInteger(v.next_refresh_at) && Number(v.next_refresh_at) >= 0 && (v.shared_room === null || validSharedFriendRoom(v.shared_room)) &&
    Array.isArray(v.links) && v.links.length <= MAX_FRIENDS && new Set(v.links.map(x => isObject(x) ? x.player_id : null)).size === v.links.length &&
    v.links.every(x => isObject(x) && exact(x, ["player_id", "request_id", "requested_by", "accepted", "created_at"]) && typeof x.player_id === "string" && ID_PATTERN.test(x.player_id) && x.player_id !== owner &&
      typeof x.request_id === "string" && ID_PATTERN.test(x.request_id) && (x.requested_by === owner || x.requested_by === x.player_id) && typeof x.accepted === "boolean" && Number.isSafeInteger(x.created_at) && Number(x.created_at) > 0);
}
export function sameFriendLink(a: FriendLink, b: FriendLink, owner: string): boolean {
  return b.player_id === owner && a.request_id === b.request_id && a.requested_by === b.requested_by;
}

/** Binding-only projection: do not move recordings/checkpoints between objects
 * for a foreground friends refresh. SQL extracts only these five metadata fields. */
export function friendRoomInvite(storage: DurableObjectStorage, host: string, visitor: string): Outcome<FriendRoomInvite> {
  const row = storage.sql.exec<{ room_id: string | null; host_id: string | null; guest_id: string | null; invite_code: string | null; invite_expires_at: string | null }>(
    "SELECT json_extract(data,'$.room_id') AS room_id,json_extract(data,'$.host_id') AS host_id,json_extract(data,'$.guest_id') AS guest_id,json_extract(data,'$.invite_code') AS invite_code,json_extract(data,'$.invite_expires_at') AS invite_expires_at FROM room WHERE id=1 AND json_extract(data,'$.deleted') IS NOT 1"
  ).toArray()[0];
  if (!ID_PATTERN.test(host) || !ID_PATTERN.test(visitor) || !row || row.host_id !== host || !row.room_id || !row.invite_code || !/^[A-F0-9]{20}$/.test(row.invite_code)) return fail(404, "room_not_found");
  if (visitor !== host && row.guest_id !== null && row.guest_id !== visitor) return fail(409, "room_not_available");
  const expiry = Date.parse(row.invite_expires_at ?? "");
  // The host can share an existing partnership; an expired invitation never
  // prevents that same guest from returning through the ordinary join route.
  const returning = row.guest_id !== null && (visitor === host || row.guest_id === visitor);
  if (!returning && (!Number.isFinite(expiry) || expiry <= Date.now())) return fail(410, "invite_expired");
  return ok({ room_id: row.room_id, invite_code: row.invite_code });
}
