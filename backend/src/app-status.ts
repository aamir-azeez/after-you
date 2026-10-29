/**
 * Required-update gate: GET /v1/app-status tells a client whether its version is too old
 * for online play. It needs no identity. Clients from 0.6.2 send
 * `X-AfterYou-Client: <version> <channel>` on every request.
 *
 * The minimums are CONFIG's min_client_version (config.ts). A missing or malformed minimum
 * means no minimum, so a bad value can never lock anyone out. The `dev` channel (desktop
 * development builds) is never gated.
 */
import type { ServerVars } from "./flags";
import { MAX_VERSION_LENGTH, parseVersion, serverConfig, type Version } from "./config";

export const CLIENT_HEADER = "X-AfterYou-Client";
export const CHANNELS = ["play", "github", "app_store", "dev"] as const;
export type Channel = typeof CHANNELS[number];
const MAX_HEADER_LENGTH = MAX_VERSION_LENGTH + 1 + 9;

/** Semantic version precedence: negative when a is older, 0 when equal, positive when newer. */
export function compareVersions(a: Version, b: Version): number {
  for (let i = 0; i < 3; i++) if (a.core[i] !== b.core[i]) return a.core[i] < b.core[i] ? -1 : 1;
  if (a.pre.length === 0 || b.pre.length === 0) return a.pre.length === b.pre.length ? 0 : a.pre.length === 0 ? 1 : -1;
  for (let i = 0; i < Math.min(a.pre.length, b.pre.length); i++) {
    const x = a.pre[i], y = b.pre[i];
    if (x === y) continue;
    const xn = /^[0-9]+$/.test(x), yn = /^[0-9]+$/.test(y);
    if (xn && yn) return Number(x) < Number(y) ? -1 : 1;
    if (xn !== yn) return xn ? -1 : 1;
    return x < y ? -1 : 1;
  }
  return a.pre.length === b.pre.length ? 0 : a.pre.length < b.pre.length ? -1 : 1;
}

/** The version and channel a client named, or null for a missing or malformed header. */
export function clientHeader(request: Request): { version: Version; text: string; channel: Channel } | null {
  const value = request.headers.get(CLIENT_HEADER);
  if (value === null || value.length > MAX_HEADER_LENGTH) return null;
  const parts = value.split(" ");
  if (parts.length !== 2 || !(CHANNELS as readonly string[]).includes(parts[1])) return null;
  const version = parseVersion(parts[0]);
  return version ? { version, text: parts[0], channel: parts[1] as Channel } : null;
}

/** The minimum a channel needs, or null when it is missing or malformed. */
export function channelMinimum(env: ServerVars, channel: Channel): { version: Version; text: string } | null {
  if (channel === "dev") return null;
  const text = serverConfig(env).min_client_version[channel];
  const version = parseVersion(text);
  return version && typeof text === "string" ? { version, text } : null;
}

export type AppStatus = { schema_version: 1; gate: "off" } | { schema_version: 1; gate: "required"; min_version: string; channel: Channel };

/** The answer for one request. Only a valid header and a valid, higher minimum say "required". */
export function appStatus(request: Request, env: ServerVars): AppStatus {
  const off: AppStatus = { schema_version: 1, gate: "off" };
  const client = clientHeader(request);
  if (!client) return off;
  const minimum = channelMinimum(env, client.channel);
  if (!minimum || compareVersions(client.version, minimum.version) >= 0) return off;
  return { schema_version: 1, gate: "required", min_version: minimum.text, channel: client.channel };
}
