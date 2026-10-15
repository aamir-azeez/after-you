/**
 * The backend's one log line: an event name plus a few short, safe fields, written as
 * JSON for `wrangler tail` and Workers logs. Never pass tokens, player or room ids,
 * request bodies or upstream text; pass codes, counts and HTTP statuses only.
 */
export type LogDetail = Record<string, string | number | boolean>;
export function logWarning(event: string, detail: LogDetail = {}): void {
  console.warn(JSON.stringify({ event, ...detail }));
}
/** Our own error codes ("unowned_notification_alarm") pass through; any other message, which could quote stored data, is reduced to the error's class name. */
export function errorCode(error: unknown): string {
  if (error instanceof Error) return /^[a-z][a-z0-9_]{0,63}$/.test(error.message) ? error.message : error.name.slice(0, 64);
  return typeof error;
}
/** Upstream codes such as "INVALID_ARGUMENT" pass through; anything else reads "other". */
export function upstreamCode(value: unknown): string {
  return typeof value === "string" && /^[A-Z][A-Z0-9_]{0,63}$/.test(value) ? value : "other";
}
