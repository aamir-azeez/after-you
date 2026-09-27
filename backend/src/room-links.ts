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

export type CampaignLinkReleased = { schema_version: 1; operation: "campaign_identity_cleanup"; status: "released"; player_id: string; campaign_room_id: string };
export type RoomEraser = (link: RoomLink, playerId: string) => Promise<Outcome<{ deleted: boolean } | CampaignLinkReleased>>;
export type RoomDeletionDispatcher = { supportedVersions: number[]; erase: RoomEraser };
type DeletingPlayer = Pick<DurableObjectStub<import("./player").Player>, "beginDelete" | "removeRoom" | "finishDelete">;

export async function deleteLinkedIdentity(playerId: string, player: DeletingPlayer, dispatcher: RoomDeletionDispatcher, deviceHash?: string): Promise<Outcome<{ deleted: true }>> {
  const started = await player.beginDelete(dispatcher.supportedVersions, deviceHash);
  if (!started.ok) return started;
  for (const link of started.value) {
    const erased = await dispatcher.erase(link, playerId);
    if (roomLinkVersion(link) === 3) {
      if (!erased.ok) return erased;
      const proof: unknown = erased.value;
      if (!isObject(proof) || Object.keys(proof).length !== 5 || proof.schema_version !== 1 || proof.operation !== "campaign_identity_cleanup" || proof.status !== "released" || proof.player_id !== playerId || proof.campaign_room_id !== link.room_id)
        return { ok: false, status: 409, code: "campaign_deletion_unconfirmed" };
      continue; // the deleting-identity finalizer already removed its exact link
    }
    if (!erased.ok && erased.status !== 404) return erased;
    await player.removeRoom(link.room_id, roomLinkVersion(link));
  }
  return player.finishDelete();
}

/** Internal dispatcher. Mutation feature flags must not disable data deletion. */
export function roomDeletionDispatcher(rooms: Env["ROOMS"], v2?: RoomEraser, campaign?: RoomEraser): RoomDeletionDispatcher {
  return {
    supportedVersions: [1, ...(v2 ? [2] : []), ...(campaign ? [3] : [])],
    async erase(link, playerId) {
      const version = roomLinkVersion(link);
      if (version === 1) return rooms.getByName(link.room_id).eraseForPlayer(playerId, link.host);
      if (version === 2) return v2 ? v2(link, playerId) : { ok: false, status: 503, code: "room_service_unavailable" };
      if (version === 3 && campaign) return campaign(link, playerId);
      return { ok: false, status: 409, code: "unsupported_room_version" };
    }
  };
}
