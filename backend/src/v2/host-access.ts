import { ApiError } from "../protocol";
import { entitlement } from "../entitlement";

/**
 * A premium turn in an existing room skips the purchase provider for this long
 * after the host's purchase was last verified. 15 minutes covers a normal sitting
 * of back-and-forth turns with one provider check, while a refund or lapsed
 * subscription still stops new turns within a quarter of an hour.
 */
export const HOST_ACCESS_FRESH_MS = 15 * 60_000;
/**
 * When the provider is unreachable, a verification this recent still admits turns
 * in the room it was made for. A "verified, not entitled" answer always refuses.
 */
export const HOST_ACCESS_OUTAGE_GRACE_MS = 60 * 60_000;

/** The room's in-memory memo. It is never stored, so eviction only costs one provider check. */
export type HostAccessMemo = {
  hostAccessAge(host: string): Promise<number | null>;
  rememberHostAccess(host: string, verified: boolean): Promise<void>;
};

/** Same 402/503 answers as a direct check; only the number of provider calls changes. */
export async function requireRoomHostAccess(memo: HostAccessMemo, hostId: string, env: Env): Promise<void> {
  const age = await memo.hostAccessAge(hostId);
  if (age !== null && age < HOST_ACCESS_FRESH_MS) return;
  const access = await entitlement(hostId, env);
  if (access.full_journey) {
    // Tester grants are read from the host's own record each time, so revoking one stays immediate.
    if (access.access_source !== "tester_grant") await memo.rememberHostAccess(hostId, true);
    return;
  }
  if (access.status === "verified") {
    if (age !== null) await memo.rememberHostAccess(hostId, false);
    throw new ApiError(402, "host_unlock_required");
  }
  if (access.status === "unavailable" && age !== null && age < HOST_ACCESS_OUTAGE_GRACE_MS) return;
  throw new ApiError(503, "entitlement_unavailable");
}
