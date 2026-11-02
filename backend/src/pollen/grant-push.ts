import type { ServerVars } from "../flags";
import { logWarning } from "../log";
import { DAY_MS } from "./rates";
import { makePollenHint, notificationsConfigured, type FcmSender, type SendResult } from "../notifications";
import { pushPhones, sendToPhones, type FinishedPushes } from "../notification-phones";

/**
 * How long after a phone last registered (each app open does) it still gets this push. The turn push stops at
 * REGISTRATION_TTL_MS (30 days), but a month can be 31 days, so a player who opened the app on one payday would
 * miss the next. Two months, as FCM's own guidance treats a token as stale; a token FCM calls gone is erased anyway.
 */
export const POLLEN_PUSH_REACH_MS = 62 * DAY_MS;

/**
 * The monthly Pollen push ("Your monthly Pollen is here", "+4,500 Pollen from Full Journey"), sent by the
 * Player after its alarm paid an instalment (pollen/grant-alarm.ts). Through the existing FCM sender to this
 * player's own registered phones: the current device's rows, registered in the last POLLEN_PUSH_REACH_MS. It
 * rides the main notification setting: an iOS row (with IOS_PUSH_ENABLED) gets it only with "turns" on, and an
 * Android phone shows it only with turn notifications on (the app checks, as for turns). An Android app too old
 * to know the message drops it unshown, as does an old iPhone app while IOS_PUSH_ENABLED is off; with it on, iOS
 * shows the server's alert itself, and on an old app a tap just opens the app where it was.
 *
 * Best effort: one try per phone, never retried and never re-arming the alarm, since the Pollen is already
 * paid and the Home card shows it. A token FCM calls gone is erased, as the turn push does. Reads only
 * otherwise: no row is written for a send.
 */
export async function sendPollenPush(storage: DurableObjectStorage, env: ServerVars, sender: FcmSender, deviceHash: string, current: (deviceHash: string) => boolean,
  lines: readonly { key: string; amount: number }[], memory: FinishedPushes): Promise<SendResult[]> {
  if (!lines.length || !notificationsConfigured(env)) return [];
  const hint = await makePollenHint(lines[lines.length - 1].key, lines.reduce((sum, line) => sum + line.amount, 0));
  if (hint === null) return [];
  const now = Date.now();
  // This device's phones registered within the reach; the shared loop adds the iOS "turns" check.
  const phones = pushPhones(storage, env, hint.kind, { optIn: "all", include: data => data.device_hash === deviceHash && now - data.updated_at < POLLEN_PUSH_REACH_MS });
  if (phones === null) { logWarning("pollen_push_failed", { reason: "registration_state" }); return []; }
  return sendToPhones(storage, sender, phones, memory, { family: "pollen", hint, authorized: current });
}
