import { ID_PATTERN, fail, isObject, ok, type Outcome } from "./protocol";
import { errorCode } from "./log";

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
type DeletingPlayer = Pick<DurableObjectStub<import("./player").Player>, "beginDelete" | "removeRoom" | "finishDelete" | "continueDeletion">;
type Unlinker = { removeRoom(roomId: string, expectedVersion?: number): unknown };

/**
 * Links one identity deletion request erases. At or below it, deletion runs in
 * the request exactly as before; above it, the Player's alarm erases the rest
 * in batches of the same size (Player.continueDeletion).
 */
export const ROOM_DELETION_BATCH = 60;

/**
 * Erases the caller's data in each linked room and drops each link. A room that
 * answers 404 is already gone for this player. With `stopOnFailure` the first
 * failure is returned at once, as identity deletion always did. Otherwise a
 * failed or thrown erase keeps only that room's link, its id goes into
 * `failed`, the other links still go, and the first failure is returned at the end.
 */
export async function eraseRoomLinks(playerId: string, links: readonly RoomLink[], player: Unlinker, dispatcher: RoomDeletionDispatcher, stopOnFailure = true, failed: string[] = []): Promise<Outcome<null>> {
  let failure: Outcome<never> | null = null;
  for (const link of links) {
    let erased: Awaited<ReturnType<RoomEraser>>;
    if (stopOnFailure) erased = await dispatcher.erase(link, playerId);
    else try { erased = await dispatcher.erase(link, playerId); } catch (error) { erased = fail(503, errorCode(error)); }
    let problem: Outcome<never> | null = null;
    if (roomLinkVersion(link) === 3) {
      if (!erased.ok) problem = erased;
      else {
        const proof: unknown = erased.value;
        if (!isObject(proof) || Object.keys(proof).length !== 5 || proof.schema_version !== 1 || proof.operation !== "campaign_identity_cleanup" || proof.status !== "released" || proof.player_id !== playerId || proof.campaign_room_id !== link.room_id)
          problem = fail(409, "campaign_deletion_unconfirmed");
      }
      if (!problem) continue; // the deleting-identity finalizer already removed its exact link
    } else if (!erased.ok && erased.status !== 404) problem = erased;
    if (problem) { if (stopOnFailure) return problem; failure ??= problem; failed.push(link.room_id); continue; }
    await player.removeRoom(link.room_id, roomLinkVersion(link));
  }
  return failure ?? ok(null);
}

/**
 * DELETE /v1/identity. At or below ROOM_DELETION_BATCH links it runs exactly as
 * before: every room, then the finish, in this request.
 *
 * Above it, beginDelete has already revoked the identity: every later request
 * except this DELETE is refused. This request erases v3 links first (only it
 * carries what the campaign path needs) and then v1 and v2 links up to the
 * batch, and hands every remaining link to the Player's alarm, which erases
 * them in batches and finishes the deletion without the client. The answer is
 * the usual 200, so shipped clients clean up and acknowledge as usual; the
 * acknowledgement waits until the erasure is complete (SafetyProfile). Only a
 * v3 link that failed or did not fit in the batch keeps the old answer: its
 * error, or a retryable 503, for the client to retry.
 */
export async function deleteLinkedIdentity(playerId: string, player: DeletingPlayer, dispatcher: RoomDeletionDispatcher, deviceHash?: string): Promise<Outcome<{ deleted: true }>> {
  const started = await player.beginDelete(dispatcher.supportedVersions, deviceHash);
  if (!started.ok) return started;
  const links = started.value;
  if (links.length <= ROOM_DELETION_BATCH) {
    const erased = await eraseRoomLinks(playerId, links, player, dispatcher);
    return erased.ok ? player.finishDelete() : erased;
  }
  const campaign = links.filter(link => roomLinkVersion(link) === 3), rooms = links.filter(link => roomLinkVersion(link) !== 3);
  const campaignBatch = campaign.slice(0, ROOM_DELETION_BATCH), failed: string[] = [];
  const campaignErased = await eraseRoomLinks(playerId, campaignBatch, player, dispatcher);
  if (campaignErased.ok) await eraseRoomLinks(playerId, rooms.slice(0, ROOM_DELETION_BATCH - campaignBatch.length), player, dispatcher, false, failed);
  await player.continueDeletion(failed);
  if (!campaignErased.ok) return campaignErased;
  return campaignBatch.length < campaign.length ? fail(503, "deletion_in_progress") : ok({ deleted: true });
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
