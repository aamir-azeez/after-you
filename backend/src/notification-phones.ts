import { MAX_REGISTRATIONS, pushCategoryAllowed, type FcmSender, type NotificationEnvironment, type PushHint, type SendResult } from "./notifications";

/**
 * The one per-phone push loop for a Player's registered phones, used by the turn and redo push
 * (player.ts deliverTurnNotification), the hosting push (player.ts deliverFriendRoomNotification) and the
 * monthly Pollen push (pollen/grant-push.ts). Two steps, so each caller keeps its own early exits between them:
 * pushPhones picks the rows, sendToPhones sends to each one in parallel. What each caller does with the
 * results (outbox retry for turns, queue retry for hosting, nothing for Pollen) stays with the caller.
 */

/** The Player's memory of pushes already finished per event and phone, so a repeat sends only to phones that failed. */
export type FinishedPushes = { finished: (key: string) => boolean; finish: (key: string, sent: SendResult) => void };
/** A registration row's data (notification-storage.ts validRegistrationKeys has the exact shape). */
export type PushRegistration = { token: string; device_hash: string; updated_at: number; friend_events?: number; platform?: string; categories?: string };
/** One stored row, kept byte for byte so a send can tell whether it changed, and its parsed data. */
export type PushPhone = { binding_epoch: string; data: string; registration: PushRegistration };

export type PhoneSelection = {
  /**
   * "redo": only rows with a redo opt-in row in notification_categories (redo requests); "all" otherwise.
   * This picks the rows only: a caller that opts in also checks the opt-in row again in its stillCurrent.
   */
  optIn: "all" | "redo";
  /**
   * The caller's own rule on top of the iOS category check: the hosting push's client gate, the
   * Pollen push's device and reach. The turn push erases stale and other-device rows before this
   * read instead, so it includes every row.
   */
  include: (registration: PushRegistration) => boolean;
};
/** The rows that may get `kind`. Null when more rows than MAX_REGISTRATIONS are stored; each caller answers that its own way. */
export function pushPhones(storage: DurableObjectStorage, env: NotificationEnvironment, kind: PushHint["kind"], selection: PhoneSelection): PushPhone[] | null {
  const rows = storage.sql.exec<{ binding_epoch: string; data: string }>(selection.optIn === "redo"
    ? "SELECT r.binding_epoch AS binding_epoch,r.data AS data FROM notification_registrations r JOIN notification_categories c ON c.binding_epoch=r.binding_epoch LIMIT 5"
    : "SELECT binding_epoch,data FROM notification_registrations LIMIT 5").toArray();
  if (rows.length > MAX_REGISTRATIONS) return null;
  return rows.flatMap(row => {
    const registration = JSON.parse(row.data) as PushRegistration;
    // An iOS alert shows without app code, so its category opt-out is applied here (flag on only).
    return selection.include(registration) && pushCategoryAllowed(env, registration, kind) ? [{ binding_epoch: row.binding_epoch, data: row.data, registration }] : [];
  });
}

export type PhoneSend = {
  /** The finished-memory key's first part: "room" (turn and redo), "friend" or "pollen". */
  family: "room" | "friend" | "pollen";
  hint: PushHint;
  /** The Player's device check for a row's device_hash. */
  authorized: (deviceHash: string) => boolean;
  /** The caller's extra conditions for a phone to stay current, read after the device and unchanged-row checks. */
  stillCurrent?: (phone: PushPhone) => boolean;
  /**
   * The check the sender runs after its OAuth step, given this phone's current check; it may ask other
   * objects (rooms, friends, safety). Without it the sender runs the current check itself.
   */
  confirm?: (current: () => boolean) => Promise<boolean>;
};
/**
 * One try per phone, all in parallel (they share one OAuth exchange). A phone already finished for this
 * event answers "sent" without a send. The sender cancels a phone that stops being current; a token FCM
 * calls gone is erased while its row is still current. Every result goes to memory.finish, which decides what to keep.
 */
export function sendToPhones(storage: DurableObjectStorage, sender: FcmSender, phones: readonly PushPhone[], memory: FinishedPushes, plan: PhoneSend): Promise<SendResult[]> {
  return Promise.all(phones.map(async (phone): Promise<SendResult> => {
    const { registration } = phone;
    const key = `${plan.family}:${plan.hint.event_id}:${phone.binding_epoch}:${registration.token}`;
    if (memory.finished(key)) return { status: "sent" };
    // A recovery, deletion or new registration during the OAuth exchange cancels this phone's send.
    const current = () => plan.authorized(registration.device_hash) &&
      storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations WHERE binding_epoch=?", phone.binding_epoch).toArray()[0]?.data === phone.data &&
      (plan.stillCurrent?.(phone) ?? true);
    const confirm = plan.confirm;
    const sent = await sender.send(registration.token, phone.binding_epoch, plan.hint, confirm ? () => confirm(current) : current, registration.platform === "ios" ? "ios" : "android");
    if (sent.status === "invalid_token" && current()) storage.sql.exec("DELETE FROM notification_registrations WHERE binding_epoch=? AND data=?", phone.binding_epoch, phone.data);
    memory.finish(key, sent);
    return sent;
  }));
}
