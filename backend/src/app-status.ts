/**
 * Required-update gate: GET /v1/app-status tells a client whether its version is too old
 * for online play. It needs no identity. Clients from 0.6.2 send
 * `X-AfterYou-Client: <version> <channel>` on every request.
 *
 * The minimums are CONFIG's min_client_version (config.ts). A missing or malformed minimum
 * means no minimum, so a bad value can never lock anyone out. The `dev` channel (desktop
 * development builds) is never gated.
 *
 * A client that sends `X-AfterYou-Switches: 1` also gets `switches`: the public switches
 * Home draws its rows from, the same for every player (duels, leaderboards). Clients
 * that do not ask get the same bytes as before, so their strict reading of a "required"
 * answer is untouched. Reading them costs no Durable Object request.
 */
import { flags, type ServerVars } from "./flags";
import { MAX_VERSION_LENGTH, compareVersions, parseVersion, serverConfig, type Version } from "./config";
import { duelsOn } from "./duels/turn-hook";

export { compareVersions };
export const CLIENT_HEADER = "X-AfterYou-Client";
export const SWITCHES_HEADER = "X-AfterYou-Switches";
export const CHANNELS = ["play", "github", "app_store", "dev"] as const;
export type Channel = typeof CHANNELS[number];
const MAX_HEADER_LENGTH = MAX_VERSION_LENGTH + 1 + 9;

/** The version and channel a client named, or null for a missing or malformed header. */
export function clientHeader(request: Request): { version: Version; text: string; channel: Channel } | null {
  const value = request.headers.get(CLIENT_HEADER);
  if (value === null || value.length > MAX_HEADER_LENGTH) return null;
  const parts = value.split(" ");
  if (parts.length !== 2 || !(CHANNELS as readonly string[]).includes(parts[1])) return null;
  const version = parseVersion(parts[0]);
  return version ? { version, text: parts[0], channel: parts[1] as Channel } : null;
}
/** The app a request comes from, for the version gates (flags.ts Reach): its version, or null when it names none, which is older than any gate. */
export function clientReach(request: Request): Version | null { return clientHeader(request)?.version ?? null; }

/** The minimum a channel needs, or null when it is missing or malformed. */
export function channelMinimum(env: ServerVars, channel: Channel): { version: Version; text: string } | null {
  if (channel === "dev") return null;
  const text = serverConfig(env).min_client_version[channel];
  const version = parseVersion(text);
  return version && typeof text === "string" ? { version, text } : null;
}

/** Home's public switches, the same for every player: each mirrors its /v2/capabilities field. */
export type Switches = { duels: boolean; leaderboards: boolean };
export type AppStatus = ({ schema_version: 1; gate: "off" } | { schema_version: 1; gate: "required"; min_version: string; channel: Channel }) & { switches?: Switches };

export function switches(env: ServerVars): Switches {
  return { duels: duelsOn(env), leaderboards: flags.leaderboards(env) };
}

/** The answer for one request. Only a valid header and a valid, higher minimum say "required". */
export function appStatus(request: Request, env: ServerVars): AppStatus {
  const extra = request.headers.get(SWITCHES_HEADER) === "1" ? { switches: switches(env) } : {};
  const off: AppStatus = { schema_version: 1, gate: "off", ...extra };
  const client = clientHeader(request);
  if (!client) return off;
  const minimum = channelMinimum(env, client.channel);
  if (!minimum || compareVersions(client.version, minimum.version) >= 0) return off;
  return { schema_version: 1, gate: "required", min_version: minimum.text, channel: client.channel, ...extra };
}
