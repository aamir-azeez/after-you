import { ID_PATTERN, isObject, type Outcome } from "./protocol";

/** Missing api_version is the original v1 link; never rewrite stored legacy JSON. */
export type RoomLink = { room_id: string; invite_code: string; host: boolean; api_version?: number };
export function roomLinkVersion(link: RoomLink): number { return link.api_version === undefined ? 1 : link.api_version; }
export function validRoomLink(value: unknown): value is RoomLink {
  if (!isObject(value) || Object.keys(value).some(key => !["room_id", "invite_code", "host", "api_version"].includes(key))) return false;
  if (typeof value.room_id !== "string" || !ID_PATTERN.test(value.room_id) || typeof value.host !== "boolean") return false;
  if (value.host ? typeof value.invite_code !== "string" || !/^[A-F0-9]{20}$/.test(value.invite_code) : value.invite_code !== "") return false;
  return !Object.hasOwn(value, "api_version") || (typeof value.api_version === "number" && Number.isSafeInteger(value.api_version) && value.api_version > 0);
}

export type RoomEraser = (link: RoomLink, playerId: string) => Promise<Outcome<{ deleted: boolean }>>;
export type RoomDeletionDispatcher = { supportedVersions: number[]; erase: RoomEraser };
type DeletingPlayer = Pick<DurableObjectStub<import("./player").Player>, "beginDelete" | "removeRoom" | "finishDelete">;

export async function deleteLinkedIdentity(playerId: string, player: DeletingPlayer, dispatcher: RoomDeletionDispatcher): Promise<Outcome<{ deleted: true }>> {
  const started = await player.beginDelete(dispatcher.supportedVersions);
  if (!started.ok) return started;
  for (const link of started.value) {
    const erased = await dispatcher.erase(link, playerId);
    if (!erased.ok && erased.status !== 404) return erased;
    await player.removeRoom(link.room_id, roomLinkVersion(link));
  }
  return player.finishDelete();
}

/** Internal integration seam only. No v2 binding, HTTP route or creation is enabled. */
export function roomDeletionDispatcher(rooms: Env["ROOMS"], v2?: RoomEraser): RoomDeletionDispatcher {
  return {
    supportedVersions: v2 ? [1, 2] : [1],
    async erase(link, playerId) {
      const version = roomLinkVersion(link);
      if (version === 1) return rooms.getByName(link.room_id).eraseForPlayer(playerId, link.host);
      if (version === 2) return v2 ? v2(link, playerId) : { ok: false, status: 503, code: "room_service_unavailable" };
      return { ok: false, status: 409, code: "unsupported_room_version" };
    }
  };
}
