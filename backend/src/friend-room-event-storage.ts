import { ID_PATTERN, isObject } from "./protocol";
import { validSharedFriendRoom, type SharedFriendRoom } from "./friends";

export const FRIEND_PUBLICATION_TABLE = { name: "friend_room_publication", schema: "CREATE TABLE friend_room_publication (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)" };
export const FRIEND_PUBLICATION_OPS_TABLE = { name: "friend_room_publication_ops", schema: "CREATE TABLE friend_room_publication_ops (publication_id TEXT PRIMARY KEY, data TEXT NOT NULL)" };
export const FRIEND_SUBSCRIPTIONS_TABLE = { name: "friend_room_subscriptions", schema: "CREATE TABLE friend_room_subscriptions (host_id TEXT PRIMARY KEY, data TEXT NOT NULL)" };
export type FriendPublication = { schema_version: 1; publication_epoch: number; publication_id: string; room: SharedFriendRoom; published_at: number };
export type FriendSubscription = { schema_version: 1; request_id: string; enabled: boolean; updated_at: number };
export const PUBLICATION_ID_PATTERN = /^[A-Za-z0-9_-]{22}$/;
export const MAX_PUBLICATION_RECEIPTS = 20;
export const MAX_FRIEND_SUBSCRIPTIONS = 20;
const exact = (v: Record<string, unknown>, keys: string[]) => Object.keys(v).length === keys.length && keys.every(key => Object.hasOwn(v, key));

export function validFriendPublication(value: unknown): value is FriendPublication {
  if (!isObject(value) || !exact(value, ["schema_version", "publication_epoch", "publication_id", "room", "published_at"])) return false;
  return value.schema_version === 1 && Number.isSafeInteger(value.publication_epoch) && Number(value.publication_epoch) > 0 &&
    typeof value.publication_id === "string" && PUBLICATION_ID_PATTERN.test(value.publication_id) && validSharedFriendRoom(value.room) &&
    Number.isSafeInteger(value.published_at) && Number(value.published_at) > 0;
}
export function validFriendSubscription(value: unknown): value is FriendSubscription {
  return isObject(value) && exact(value, ["schema_version", "request_id", "enabled", "updated_at"]) && value.schema_version === 1 &&
    typeof value.request_id === "string" && ID_PATTERN.test(value.request_id) && typeof value.enabled === "boolean" && Number.isSafeInteger(value.updated_at) && Number(value.updated_at) > 0;
}
export function checkedFriendPublication(value: string): FriendPublication | null {
  try { const parsed: unknown = JSON.parse(value); if (validFriendPublication(parsed)) return parsed; } catch { /* invalid persisted operational state is not used */ }
  return null;
}
export function checkedFriendSubscription(value: string): FriendSubscription | null {
  try { const parsed: unknown = JSON.parse(value); if (validFriendSubscription(parsed)) return parsed; } catch { /* invalid persisted operational state is not used */ }
  return null;
}
