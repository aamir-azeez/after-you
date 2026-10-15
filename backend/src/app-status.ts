/**
 * Required-update gate: GET /v1/app-status tells a client whether its version is too old
 * for online play. It needs no identity. Clients from 0.6.2 send
 * `X-AfterYou-Client: <version> <channel>` on every request.
 *
 * Everything here sits behind UPDATE_GATE_ENABLED. Unless that var is exactly "true" the
 * route does not exist and the request falls through to the authenticated routes, which
 * answer as they always have (401 without credentials). A missing, empty or malformed
 * minimum means no minimum, so a bad var can never lock anyone out. The `dev` channel
 * (desktop development builds) is never gated.
 */
import { flags, type ServerVars } from "./flags";

export const CLIENT_HEADER = "X-AfterYou-Client";
export const CHANNELS = ["play", "github", "app_store", "dev"] as const;
export type Channel = typeof CHANNELS[number];
const MINIMUM_VAR: Record<Exclude<Channel, "dev">, keyof ServerVars> = {
  play: "MIN_CLIENT_VERSION_PLAY",
  github: "MIN_CLIENT_VERSION_GITHUB",
  app_store: "MIN_CLIENT_VERSION_APP_STORE"
};
/** Longest version string either side accepts; the header adds a space and a channel. */
export const MAX_VERSION_LENGTH = 40;
const MAX_HEADER_LENGTH = MAX_VERSION_LENGTH + 1 + 9;
// Semantic version without build metadata: 0.6.2, 0.6.2-rc.1. No leading zeros.
const NUMBER = "(0|[1-9][0-9]{0,3})";
const VERSION = new RegExp(`^${NUMBER}\\.${NUMBER}\\.${NUMBER}(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$`);

export type Version = { core: [number, number, number]; pre: string[] };

export function parseVersion(value: unknown): Version | null {
  if (typeof value !== "string" || value.length > MAX_VERSION_LENGTH) return null;
  const found = VERSION.exec(value);
  if (!found) return null;
  const pre = found[4] === undefined ? [] : found[4].split(".");
  // A numeric pre-release identifier has no leading zeros either (semver 9).
  if (pre.some(part => /^[0-9]+$/.test(part) && (part.length > 1 && part.startsWith("0") || part.length > 6))) return null;
  return { core: [Number(found[1]), Number(found[2]), Number(found[3])], pre };
}

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

/** The minimum a channel needs, or null when its var is missing, empty or malformed. */
export function channelMinimum(env: ServerVars, channel: Channel): { version: Version; text: string } | null {
  if (channel === "dev") return null;
  const text = env[MINIMUM_VAR[channel]];
  const version = parseVersion(text);
  return version && typeof text === "string" ? { version, text } : null;
}

export type AppStatus = { schema_version: 1; gate: "off" } | { schema_version: 1; gate: "required"; min_version: string; channel: Channel };

/** The answer for one request. Only an enabled gate, a valid header and a valid, higher minimum say "required". */
export function appStatus(request: Request, env: ServerVars): AppStatus {
  const off: AppStatus = { schema_version: 1, gate: "off" };
  if (!flags.updateGate(env)) return off;
  const client = clientHeader(request);
  if (!client) return off;
  const minimum = channelMinimum(env, client.channel);
  if (!minimum || compareVersions(client.version, minimum.version) >= 0) return off;
  return { schema_version: 1, gate: "required", min_version: minimum.text, channel: client.channel };
}
