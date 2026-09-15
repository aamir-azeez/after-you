import { isObject } from "./protocol";

export type NotificationEnvironment = { NOTIFICATIONS_ENABLED?: string; FCM_SERVICE_ACCOUNT_JSON?: string };
export type TurnHint = { schema_version: "1"; event_id: string; kind: "turn_ready"; room_id: string; room_family: "legacy" | "relay"; revision: string };
export type SendResult = { status: "sent" | "cancelled" | "invalid_token" | "retry" | "unconfigured"; retry_after_ms?: number };
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
type Account = { project_id: string; client_email: string; private_key: string };
function account(env: NotificationEnvironment): Account | null {
  if (String(env.NOTIFICATIONS_ENABLED) !== "true" || !env.FCM_SERVICE_ACCOUNT_JSON || env.FCM_SERVICE_ACCOUNT_JSON.length > 16_384) return null;
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
  async send(token: string, epoch: string, hint: TurnHint, stillCurrent: () => boolean | Promise<boolean> = () => true): Promise<SendResult> {
    const config = account(this.env); if (!config) return { status: "unconfigured" };
    if (!validNotificationToken(token) || !BINDING_PATTERN.test(epoch) || !validHint(hint)) return { status: "retry" };
    try {
      const access = await this.accessToken(config); if (!access) return { status: "retry" };
      // OAuth may yield long enough for recovery, deletion or token replacement.
      if (!await stillCurrent()) return { status: "cancelled" };
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${config.project_id}/messages:send`, { method: "POST", redirect: "manual", signal: AbortSignal.timeout(5000),
        headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
        body: JSON.stringify({ message: { token, data: { ...hint, binding_epoch: epoch }, android: { priority: "HIGH", ttl: "604800s", restricted_package_name: "com.aamirazeez.afteryou" } } }) });
      const value = await boundedResponse(response);
      if (response.ok && isObject(value) && typeof value.name === "string" && value.name.startsWith(`projects/${config.project_id}/messages/`) && value.name.length <= 512) return { status: "sent" };
      if (response.status === 401) this.access = null;
      const error = isObject(value) && isObject(value.error) ? value.error : null;
      // A generic INVALID_ARGUMENT may describe our payload, so never erase its token.
      if (response.status === 404 && Array.isArray(error?.details) && error.details.some(item => isObject(item) && item["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError" && item.errorCode === "UNREGISTERED")) return { status: "invalid_token" };
      return { status: "retry", retry_after_ms: retryAfter(response) };
    } catch { return { status: "retry" }; }
  }
}
