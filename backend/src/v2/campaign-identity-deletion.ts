import { ApiError, fail, isObject, type Outcome } from "../protocol";
import type { CampaignLinkReleased, RoomLink } from "../room-links";
import { campaignDeleted, type CampaignDeleted, type CampaignNotMember } from "./campaign-deletion";
import { campaignJoinCancellationAck } from "./campaign-join-cancellation";
import type { CampaignIdentityScope } from "./campaign-player";
import type { CampaignDefinitionResolver } from "./campaign-protocol";
import type { CampaignJoin } from "./campaign-types";

type DeletingPlayer = {
  campaignIdentityDeletionScope(link: RoomLink, deviceHash: string): Promise<Outcome<CampaignIdentityScope>>;
  finalizeCampaignIdentityDeletion(scope: unknown, evidence: unknown, deviceHash: string): Promise<Outcome<CampaignLinkReleased>>;
};
export type CampaignIdentityRooms = {
  erase(owner: string, roomId: string, allocation: unknown): Promise<Outcome<CampaignDeleted | CampaignNotMember>>;
  cancel(owner: string, roomId: string, request: CampaignJoin): Promise<Outcome<unknown>>;
};
function unwrap<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new ApiError(outcome.status, outcome.code); return outcome.value; }
/** Fixed authenticated dispatcher closure carries the original device hash.
 * Every RPC is an actual binding call; no unverified public ack is accepted. */
export async function deleteCampaignIdentityLink(player: DeletingPlayer, rooms: CampaignIdentityRooms, owner: string, link: RoomLink, deviceHash: string, resolver: CampaignDefinitionResolver = () => undefined): Promise<Outcome<CampaignLinkReleased>> {
  try {
    const scope = unwrap(await player.campaignIdentityDeletionScope(link, deviceHash));
    if (scope.owner_player_id !== owner || scope.link.room_id !== link.room_id) throw new ApiError(409, "campaign_deletion_binding_mismatch");
    let root = unwrap(await rooms.erase(owner, link.room_id, scope.allocation));
    if (root.status === "deleted") return await player.finalizeCampaignIdentityDeletion(scope, campaignDeleted(root, link.room_id), deviceHash);
    if (!isObject(root) || Object.keys(root).length !== 4 || root.schema_version !== 1 || root.status !== "not_member" || root.campaign_room_id !== link.room_id || root.player_id !== owner)
      throw new ApiError(409, "campaign_deletion_ack_mismatch");
    if (scope.link.host || scope.join_attempts.length === 0 || scope.join_attempts.length > 128) throw new ApiError(409, "campaign_prelink_unresolved");
    const acknowledgements: unknown[] = [];
    for (const attempt of scope.join_attempts) {
      const returned = await rooms.cancel(owner, link.room_id, attempt);
      if (!returned.ok) {
        root = unwrap(await rooms.erase(owner, link.room_id, null));
        if (root.status === "deleted") return await player.finalizeCampaignIdentityDeletion(scope, campaignDeleted(root, link.room_id), deviceHash);
        throw new ApiError(returned.status, returned.code);
      }
      // Treat this only as a reason to re-query the actual root. Its durable
      // membership check, followed by an exact tombstone ack, owns deletion;
      // a retained campaign need not remain in the fresh-admission registry.
      if (isObject(returned.value) && returned.value.status === "accepted") {
        root = unwrap(await rooms.erase(owner, link.room_id, null));
        return await player.finalizeCampaignIdentityDeletion(scope, campaignDeleted(root, link.room_id), deviceHash);
      }
      const ack = await campaignJoinCancellationAck(returned.value, owner, attempt, resolver);
      if (ack.status !== "cancelled") throw new ApiError(409, "campaign_prelink_unresolved");
      acknowledgements.push(ack);
    }
    return await player.finalizeCampaignIdentityDeletion(scope, { schema_version: 1, status: "cancelled", player_id: owner, campaign_room_id: link.room_id, acknowledgements }, deviceHash);
  } catch (error) { return error instanceof ApiError ? fail(error.status, error.code) : fail(503, "campaign_deletion_unavailable"); }
}
