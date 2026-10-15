import { isObject } from "./protocol";
import { flags, type ServerVars } from "./flags";
import { errorCode, logWarning, upstreamCode } from "./log";

export type NotificationEnvironment = Pick<ServerVars, "NOTIFICATIONS_ENABLED" | "FCM_SERVICE_ACCOUNT_JSON" | "IOS_PUSH_ENABLED">;
export type TurnHint = { schema_version: "1"; event_id: string; kind: "turn_ready"; room_id: string; room_family: "legacy" | "relay"; revision: string };
export type FriendRoomHint = { schema_version: "1"; event_id: string; kind: "friend_room_available"; host_id: string; room_id: string; room_family: "legacy" | "relay"; publication_epoch: string };
/** A partner's redo request. Same six keys as TurnHint; revision is the requested turn's room revision. */
export type RedoHint = { schema_version: "1"; event_id: string; kind: "redo_requested"; room_id: string; room_family: "legacy" | "relay"; revision: string };
export type RoomHint = TurnHint | RedoHint;
export type PushHint = RoomHint | FriendRoomHint;
/** "rejected": FCM refused this message for this token in a way a retry cannot fix. The token is kept. */
export type SendResult = { status: "sent" | "cancelled" | "invalid_token" | "rejected" | "retry" | "unconfigured"; retry_after_ms?: number };
export const BINDING_PATTERN = /^[A-Za-z0-9_-]{22}$/;
export const MAX_REGISTRATIONS = 4;
export const NOTIFICATION_TTL_MS = 7 * 86_400_000;
export const REGISTRATION_TTL_MS = 30 * 86_400_000;
export const MAX_DELIVERY_ATTEMPTS = 8;
export function validNotificationToken(value: unknown): value is string { return typeof value === "string" && /^[\x21-\x7e]{16,4096}$/.test(value); }
export function validHint(value: unknown): value is TurnHint {
  if (!isObject(value) || Object.keys(value).length !== 6) return false;
  return value.schema_version === "1" && typeof value.event_id === "string" && /^[A-Za-z0-9_-]{16,128}$/.test(value.event_id) &&
    value.kind === "turn_ready" && typeof value.room_id === "string" && /^[A-Za-z0-9_-]{22}$/.test(value.room_id) &&
    (value.room_family === "legacy" || value.room_family === "relay") && typeof value.revision === "string" && /^[1-9][0-9]{0,15}$/.test(value.revision) && Number.isSafeInteger(Number(value.revision));
}
export function makeHint(family: "legacy" | "relay", roomId: string, revision: number): TurnHint {
  return { schema_version: "1", event_id: `${family}_${roomId}_${revision}`, kind: "turn_ready", room_id: roomId, room_family: family, revision: String(revision) };
}
export function makeRedoHint(family: "legacy" | "relay", roomId: string, revision: number, requestId: string): RedoHint {
  return { schema_version: "1", event_id: `redo_${requestId}`, kind: "redo_requested", room_id: roomId, room_family: family, revision: String(revision) };
}
export function validRedoHint(value: unknown): value is RedoHint {
  if (!isObject(value) || Object.keys(value).length !== 6) return false;
  return value.schema_version === "1" && typeof value.event_id === "string" && /^redo_[a-f0-9]{64}$/.test(value.event_id) &&
    value.kind === "redo_requested" && typeof value.room_id === "string" && /^[A-Za-z0-9_-]{22}$/.test(value.room_id) &&
    (value.room_family === "legacy" || value.room_family === "relay") && typeof value.revision === "string" && /^[1-9][0-9]{0,15}$/.test(value.revision) && Number.isSafeInteger(Number(value.revision));
}
export function validRoomHint(value: unknown): value is RoomHint { return validHint(value) || validRedoHint(value); }
export function makeFriendRoomHint(hostId: string, room: { api_version: 1 | 2; room_id: string }, epoch: number, eventId: string): FriendRoomHint {
  return { schema_version: "1", event_id: eventId, kind: "friend_room_available", host_id: hostId, room_id: room.room_id,
    room_family: room.api_version === 1 ? "legacy" : "relay", publication_epoch: String(epoch) };
}
export function validFriendRoomHint(value: unknown): value is FriendRoomHint {
  if (!isObject(value) || Object.keys(value).length !== 7) return false;
  return value.schema_version === "1" && typeof value.event_id === "string" && /^[A-Za-z0-9_-]{22}_[1-9][0-9]{0,15}$/.test(value.event_id) &&
    value.kind === "friend_room_available" && typeof value.host_id === "string" && /^[A-Za-z0-9_-]{22}$/.test(value.host_id) &&
    typeof value.room_id === "string" && /^[A-Za-z0-9_-]{22}$/.test(value.room_id) && (value.room_family === "legacy" || value.room_family === "relay") &&
    typeof value.publication_epoch === "string" && /^[1-9][0-9]{0,15}$/.test(value.publication_epoch) && Number.isSafeInteger(Number(value.publication_epoch));
}
/** Sent only by the iOS app, on a registration POST. Absent means Android, whose row is unchanged. */
export const PLATFORM_HEADER = "X-AfterYou-Platform";
/** The iOS app's enabled push categories. iOS shows an alert without running app code, so the server filters. */
export const PUSH_CATEGORIES_HEADER = "X-AfterYou-Push-Categories";
export const PUSH_CATEGORIES = ["turns,hosting", "turns", "hosting", "none"] as const;
export type IosRegistration = { platform: "ios"; categories: typeof PUSH_CATEGORIES[number] };
/** null: an Android (or older) client. "invalid": a platform header other than an iOS one with a known category list. */
export function registrationPlatform(request: Request): IosRegistration | null | "invalid" {
  const platform = request.headers.get(PLATFORM_HEADER);
  if (platform === null) return null;
  const categories = PUSH_CATEGORIES.find(value => value === request.headers.get(PUSH_CATEGORIES_HEADER));
  return platform === "ios" && categories ? { platform: "ios", categories } : "invalid";
}
export function validIosRegistration(value: Record<string, unknown>): boolean {
  return value.platform === "ios" && PUSH_CATEGORIES.some(item => item === value.categories);
}
/** With the flag on, an iOS row gets only the kinds its app has on: turns (turn and redo) and hosting. */
export function pushCategoryAllowed(env: NotificationEnvironment, registration: { platform?: unknown; categories?: unknown }, kind: PushHint["kind"]): boolean {
  if (!flags.iosPush(env) || registration.platform !== "ios") return true;
  const categories = typeof registration.categories === "string" ? registration.categories.split(",") : [];
  return categories.includes(kind === "friend_room_available" ? "hosting" : "turns");
}
/** The same words as Android's NotificationDelivery and the iOS plugin's local notification. No player data. */
export const PUSH_TITLES: Record<PushHint["kind"], string> = {
  turn_ready: "Your friend left a turn", redo_requested: "Your friend asked for a redo", friend_room_available: "Friend rooms"
};
export const PUSH_BODY = "Open After You to see your shared moment.";
async function sha256Hex(value: string): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))].map(byte => byte.toString(16).padStart(2, "0")).join("");
}
/** An APNs alert for an iOS token. The hint stays in `data`, which FCM delivers as the custom keys the plugin
 * validates for tap routing. No content-available: the plugin would then post a second, local notification. */
export async function apnsAlert(hint: PushHint, nowMs = Date.now()): Promise<Record<string, unknown>> {
  // The plugin's own grouping key, so a newer alert for the same room and kind replaces the older one.
  const digest = await sha256Hex(`${hint.room_family}:${hint.room_id}:${hint.kind}`);
  return {
    headers: { "apns-push-type": "alert", "apns-priority": "10", "apns-expiration": String(Math.floor(nowMs / 1000) + NOTIFICATION_TTL_MS / 1000), "apns-collapse-id": digest },
    payload: { aps: { alert: { title: PUSH_TITLES[hint.kind], body: PUSH_BODY }, sound: "default", "thread-id": `after_you_update:${digest}` } }
  };
}
type Account = { project_id: string; client_email: string; private_key: string };
function account(env: NotificationEnvironment): Account | null {
  if (!flags.notifications(env) || !env.FCM_SERVICE_ACCOUNT_JSON || env.FCM_SERVICE_ACCOUNT_JSON.length > 16_384) return null;
  try {
    const value: unknown = JSON.parse(env.FCM_SERVICE_ACCOUNT_JSON);
    if (!isObject(value) || typeof value.project_id !== "string" || !/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(value.project_id) ||
      typeof value.client_email !== "string" || !/^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.iam\.gserviceaccount\.com$/.test(value.client_email) ||
      typeof value.private_key !== "string" || !/^-----BEGIN PRIVATE KEY-----\n[A-Za-z0-9+/=\r\n]+-----END PRIVATE KEY-----\n?$/.test(value.private_key)) return null;
    return { project_id: value.project_id, client_email: value.client_email, private_key: value.private_key };
  } catch { return null; }
}
export function notificationsConfigured(env: NotificationEnvironment): boolean { return account(env) !== null; }
function base64url(bytes: Uint8Array): string { let raw = ""; for (const byte of bytes) raw += String.fromCharCode(byte); return btoa(raw).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_"); }
function encoded(value: unknown): string { return base64url(new TextEncoder().encode(JSON.stringify(value))); }
/** Responses are bounded before decoding; never return upstream text to callers. */
async function boundedResponse(response: Response): Promise<unknown> {
  if (!response.body) return null;
  const reader = response.body.getReader(), chunks: Uint8Array[] = []; let count = 0;
  try {
    while (true) { const item = await reader.read(); if (item.done) break; count += item.value.byteLength;
      if (count > 16_384) { await reader.cancel(); return null; } chunks.push(item.value); }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(count); let offset = 0; for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes)); } catch { return null; }
}
function retryAfter(response: Response): number {
  const raw = response.headers.get("Retry-After"); if (!raw) return 60_000;
  const parsed = /^\d{1,8}$/.test(raw) ? Number(raw) * 1000 : Date.parse(raw) - Date.now();
  return Number.isFinite(parsed) ? Math.max(60_000, Math.min(86_400_000, parsed)) : 60_000;
}
const FCM_ERROR = "type.googleapis.com/google.firebase.fcm.v1.FcmError", BAD_REQUEST = "type.googleapis.com/google.rpc.BadRequest";
/**
 * The one place that decides what an FCM error means for a token, from FCM's structured
 * error details only (never the HTTP status alone, never message text):
 * - 404 UNREGISTERED: the token is gone ("invalid_token", the caller erases it).
 * - 403 SENDER_ID_MISMATCH, or 400 INVALID_ARGUMENT whose BadRequest names `message.token`:
 *   this token can never take this message ("rejected", the token is kept).
 * Everything else, such as a 400 about our own payload, an IAM or API-access 403, quota,
 * outages and unknown answers, stays "retry". Every failure is logged without the token.
 */
export function fcmFailure(httpStatus: number, error: Record<string, unknown> | null): SendResult {
  const details = Array.isArray(error?.details) ? error.details.filter(isObject) : [];
  const fcmCode = details.find(item => item["@type"] === FCM_ERROR)?.errorCode;
  const tokenField = details.some(item => item["@type"] === BAD_REQUEST && Array.isArray(item.fieldViolations) &&
    item.fieldViolations.some(violation => isObject(violation) && violation.field === "message.token"));
  const result: SendResult =
    httpStatus === 404 && fcmCode === "UNREGISTERED" ? { status: "invalid_token" } :
    httpStatus === 403 && fcmCode === "SENDER_ID_MISMATCH" ? { status: "rejected" } :
    httpStatus === 400 && fcmCode === "INVALID_ARGUMENT" && tokenField ? { status: "rejected" } :
    { status: "retry" };
  logWarning("push_send_failed", { outcome: result.status, http_status: httpStatus, status: upstreamCode(error?.status), fcm_error: upstreamCode(fcmCode), token_field: tokenField });
  return result;
}
/** Per-Player instance cache, not shared request state. No caller can choose a URL. */
export class FcmSender {
  private access: { value: string; expires: number } | null = null;
  constructor(private readonly env: NotificationEnvironment) {}
  private async accessToken(config: Account): Promise<string | null> {
    if (this.access && this.access.expires > Date.now() + 60_000) return this.access.value;
    const raw = atob(config.private_key.replace(/-----[^-]+-----|\s/g, "")), bytes = Uint8Array.from(raw, char => char.charCodeAt(0));
    const key = await crypto.subtle.importKey("pkcs8", bytes, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
    const now = Math.floor(Date.now() / 1000), body = `${encoded({ alg: "RS256", typ: "JWT" })}.${encoded({ iss: config.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 })}`;
    const jwt = `${body}.${base64url(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(body))))}`;
    const response = await fetch("https://oauth2.googleapis.com/token", { method: "POST", redirect: "manual", signal: AbortSignal.timeout(5000),
      headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }) });
    const result = await boundedResponse(response);
    if (!response.ok || !isObject(result) || typeof result.access_token !== "string" || !/^[\x21-\x7e]{16,4096}$/.test(result.access_token) || typeof result.expires_in !== "number" || result.expires_in < 60 || result.expires_in > 3600) return null;
    this.access = { value: result.access_token, expires: Date.now() + result.expires_in * 1000 }; return this.access.value;
  }
  async send(token: string, epoch: string, hint: PushHint, stillCurrent: () => boolean | Promise<boolean> = () => true, platform: "android" | "ios" = "android"): Promise<SendResult> {
    const config = account(this.env); if (!config) return { status: "unconfigured" };
    if (!validNotificationToken(token) || !BINDING_PATTERN.test(epoch) || !(validRoomHint(hint) || validFriendRoomHint(hint))) { logWarning("push_send_failed", { outcome: "retry", reason: "invalid_input" }); return { status: "retry" }; }
    try {
      const access = await this.accessToken(config); if (!access) { logWarning("push_send_failed", { outcome: "retry", reason: "oauth_unavailable" }); return { status: "retry" }; }
      // OAuth may yield long enough for recovery, deletion or token replacement.
      if (!await stillCurrent()) return { status: "cancelled" };
      const message = { token, data: { ...hint, binding_epoch: epoch }, android: { priority: "HIGH", ttl: "604800s", restricted_package_name: "com.aamirazeez.afteryou" } };
      const apns = platform === "ios" && flags.iosPush(this.env) ? await apnsAlert(hint) : null;
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${config.project_id}/messages:send`, { method: "POST", redirect: "manual", signal: AbortSignal.timeout(5000),
        headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
        body: JSON.stringify({ message: apns ? { ...message, apns } : message }) });
      const value = await boundedResponse(response);
      if (response.ok && isObject(value) && typeof value.name === "string" && value.name.startsWith(`projects/${config.project_id}/messages/`) && value.name.length <= 512) return { status: "sent" };
      if (response.status === 401) this.access = null;
      const result = fcmFailure(response.status, isObject(value) && isObject(value.error) ? value.error : null);
      return result.status === "retry" ? { status: "retry", retry_after_ms: retryAfter(response) } : result;
    } catch (error) { logWarning("push_send_failed", { outcome: "retry", reason: errorCode(error) }); return { status: "retry" }; }
  }
}
