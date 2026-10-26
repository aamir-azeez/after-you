import { ApiError } from "../protocol";
import { entitlement, type Entitlement } from "../entitlement";

/**
 * Premium turn admission windows, kept together so a policy change is one line here.
 * The owner has not yet signed off on the outage grace; setting it to 0 turns it off.
 *
 * FRESH: a premium turn in an existing room skips the purchase provider for this long
 * after the host's purchase was last verified. It covers a normal sitting of
 * back-and-forth turns with one provider check, while a refund or lapsed subscription
 * still stops new turns within a quarter of an hour.
 *
 * OUTAGE_GRACE: when the provider is unreachable, a verification this recent still
 * admits turns in the room it was made for. A "verified, not entitled" answer always refuses.
 */
export const HOST_ACCESS_FRESH_MS = 15 * 60_000;
export const HOST_ACCESS_OUTAGE_GRACE_MS = 60 * 60_000;

/** The one entitlement-to-HTTP mapping: verified but not entitled is 402, anything unverified is 503. */
export function hostAccessRefusal(access: Entitlement): ApiError | null {
  if (access.full_journey) return null;
  return access.status === "verified" ? new ApiError(402, "host_unlock_required") : new ApiError(503, "entitlement_unavailable");
}

/** A direct provider check for the host, used wherever no room memo applies. Answers the admitting check; `onGrant` as in entitlement(). */
export async function requireHostAccess(hostId: string, env: Env, onGrant?: (until: number) => void): Promise<Entitlement> {
  const access = await entitlement(hostId, env, onGrant), refusal = hostAccessRefusal(access);
  if (refusal) throw refusal;
  return access;
}

/**
 * A room's memory of its host's last verified purchase. It lives only in the room's
 * memory: never stored, exported or shown, so eviction only costs one provider check.
 */
export class HostAccessMemo {
  private verified: { host_id: string; at: number } | null = null;
  age(host: string): number | null { return this.verified?.host_id === host ? Math.max(0, Date.now() - this.verified.at) : null; }
  remember(host: string, verified: boolean): void { this.verified = verified ? { host_id: host, at: Date.now() } : null; }
}

/** The room's RPC face of its HostAccessMemo (RoomV2 forwards both calls). */
export type RoomHostAccess = {
  hostAccessAge(host: string): Promise<number | null>;
  rememberHostAccess(host: string, verified: boolean): Promise<void>;
};

/**
 * Same 402/503 answers as requireHostAccess; only the number of provider calls changes. Answers the
 * provider check that admitted the turn, or null when the room's memo (or the outage grace) did.
 */
export async function requireRoomHostAccess(room: RoomHostAccess, hostId: string, env: Env, onGrant?: (until: number) => void): Promise<Entitlement | null> {
  const age = await room.hostAccessAge(hostId);
  if (age !== null && age < HOST_ACCESS_FRESH_MS) return null;
  const access = await entitlement(hostId, env, onGrant), refusal = hostAccessRefusal(access);
  if (!refusal) {
    // Tester grants are read from the host's own record each time, so revoking one stays immediate.
    if (access.access_source !== "tester_grant") await room.rememberHostAccess(hostId, true);
    return access;
  }
  if (access.status === "verified") { if (age !== null) await room.rememberHostAccess(hostId, false); }
  else if (access.status === "unavailable" && age !== null && age < HOST_ACCESS_OUTAGE_GRACE_MS) return null;
  throw refusal;
}
