import { DAY_MS } from "./rates";
import { anniversary, grantDue, type GrantState } from "./grant";

/**
 * When the monthly grant wakes the player's Player Durable Object (POLLEN_GRANT_ALARM), as a pure rule over
 * the stored grant state. The Player has one alarm, shared with presence (presence.ts schedulePresence takes
 * this time as its extra wake), so this only names a time; player.ts sets it and runs the settle.
 *
 * - Only a live anchor wakes, and only for a time at which grant.ts grantDue would read RevenueCat. A
 *   subscription that will not renew stays live in storage once its cover runs out (no read lapses it, since
 *   grantDue refuses that read), so it never wakes again: no wake for a cancelled or free player.
 * - The first wake for an instalment is SETTLE_MS after its due date, so the store's renewal is usually
 *   listed by then. A read on or after the due date that paid nothing (grace, a hold, a renewal not listed
 *   yet) is followed by another wake as long after it as that read was late, between LATE_MIN_MS and
 *   LATE_MAX_MS: an hour, two, four, then daily. A failed read writes nothing, so the next wake is counted
 *   from the wake itself the same way. Once reads have found nothing for GIVE_UP_MS past the due date, or
 *   failed that long, the alarm stops, and the wallet read pays as it always did. A wake that comes late
 *   (the Worker was down) still runs: lateness alone is no reason to stop, and the read catches the months up.
 * - Nothing here is stored: the times come from the state's own fields, so a grant state older code saved
 *   reads the same.
 */
export const SETTLE_MS = 15 * 60_000;
export const LATE_MIN_MS = 60 * 60_000;
export const LATE_MAX_MS = DAY_MS;
/** The longest a store keeps retrying a payment (App Store billing retry); then the anchor lapses on a read. */
export const GIVE_UP_MS = 60 * DAY_MS;

const late = (by: number) => Math.min(LATE_MAX_MS, Math.max(LATE_MIN_MS, by));

/**
 * The grant's wake: `at`, when the next settle should run; `run`, whether that time has come (`at` <= now).
 * After a run, call again with the state as stored then: a time that has still come (nothing was written)
 * moves to `now` plus the lateness, so a settle never runs twice in one wake. Null: no wake for the grant.
 */
export function grantWake(state: GrantState | null, fjUntil: number, now: number): { at: number; run: boolean } | null {
  if (state === null || !state.live) return null;
  const due = anniversary(state.anchor, state.next);
  if (state.checked_at - due > GIVE_UP_MS) return null;
  const at = Math.max(state.checked_at >= due ? state.checked_at + late(state.checked_at - due) : due + SETTLE_MS, state.retry_at);
  // The same check the read makes: a time at which it would not read is no wake at all.
  if (!grantDue(state, fjUntil, Math.max(at, now))) return null;
  return { at, run: at <= now };
}

/** The time to set the alarm to after this wake's settle (or none): always later than `now`. */
export function grantAlarmAt(state: GrantState | null, fjUntil: number, now: number): number | null {
  const wake = grantWake(state, fjUntil, now);
  if (wake === null) return null;
  if (!wake.run) return wake.at;
  const due = anniversary(state!.anchor, state!.next), next = now + late(now - due);
  return next - due > GIVE_UP_MS ? null : next;
}
