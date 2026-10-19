import { isObject, readBounded } from "./protocol";
import { errorCode, logWarning } from "./log";
import type { ServerVars } from "./flags";

/**
 * Proves who a platform games account is, from the platform only. The player id is never read
 * from the client: Play Games answers through Google after a server auth code exchange, and
 * Game Center through Apple's signed identity data. No upstream text, token or id is logged.
 */
export type Verified = { ok: true; external_id: string } | { ok: false; reason: "invalid" | "unavailable" | "unconfigured" };

const PLAY_APP_ID = /^[0-9]{6,20}$/;
const WEB_CLIENT_ID = /^[0-9]{6,20}-[a-z0-9]{8,64}\.apps\.googleusercontent\.com$/;
const CLIENT_SECRET = /^[\x21-\x7e]{8,256}$/;
const AUTH_CODE = /^[\x21-\x7e]{10,2048}$/;
const ACCESS_TOKEN = /^[\x21-\x7e]{16,4096}$/;
const PLAY_PLAYER_ID = /^[A-Za-z0-9_.-]{1,128}$/;
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const TIMEOUT_MS = 5000;

export type PlayGamesConfig = { appId: string; clientId: string; secret: string };
/** All three or nothing: a flag that is on with a missing value fails closed. */
export function playGamesConfig(env: ServerVars): PlayGamesConfig | null {
  const appId = env.PLAY_GAMES_APP_ID, clientId = env.PLAY_GAMES_WEB_CLIENT_ID, secret = env.PLAY_GAMES_CLIENT_SECRET;
  if (typeof appId !== "string" || !PLAY_APP_ID.test(appId)) return null;
  if (typeof clientId !== "string" || !WEB_CLIENT_ID.test(clientId)) return null;
  if (typeof secret !== "string" || !CLIENT_SECRET.test(secret)) return null;
  return { appId, clientId, secret };
}

async function boundedJsonResponse(response: Response): Promise<unknown> {
  if (!response.body) return null;
  const bytes = await readBounded(response.body, 16_384); if (!bytes) return null;
  try { return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes)); } catch { return null; }
}

/** 4xx means the code or token was refused; anything else may pass on a retry. */
const refused = (status: number) => status >= 400 && status < 500 && status !== 408 && status !== 429;

/** Exchanges a one-time server auth code, then asks Games which player the token belongs to for this game. */
export async function verifyPlayGames(code: unknown, env: ServerVars): Promise<Verified> {
  const config = playGamesConfig(env);
  if (!config) return { ok: false, reason: "unconfigured" };
  if (typeof code !== "string" || !AUTH_CODE.test(code)) return { ok: false, reason: "invalid" };
  try {
    // Android server auth codes are exchanged with an empty redirect_uri (Google's server access sample).
    const exchange = await fetch(TOKEN_URL, { method: "POST", redirect: "manual", signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "authorization_code", code, client_id: config.clientId, client_secret: config.secret, redirect_uri: "" }) });
    const token = await boundedJsonResponse(exchange);
    if (!exchange.ok) {
      logWarning("platform_verify_failed", { provider: "play_games", step: "exchange", status: exchange.status });
      return { ok: false, reason: refused(exchange.status) ? "invalid" : "unavailable" };
    }
    if (!isObject(token) || typeof token.access_token !== "string" || !ACCESS_TOKEN.test(token.access_token)) return { ok: false, reason: "unavailable" };
    // applications/{id}/verify binds the token to this game's Play Games project, not only to our OAuth client.
    const verify = await fetch(`https://games.googleapis.com/games/v1/applications/${config.appId}/verify`, { method: "GET", redirect: "manual",
      signal: AbortSignal.timeout(TIMEOUT_MS), headers: { Authorization: `Bearer ${token.access_token}` } });
    const answer = await boundedJsonResponse(verify);
    if (!verify.ok) {
      logWarning("platform_verify_failed", { provider: "play_games", step: "verify", status: verify.status });
      return { ok: false, reason: refused(verify.status) ? "invalid" : "unavailable" };
    }
    if (!isObject(answer) || answer.kind !== "games#applicationVerifyResponse" || typeof answer.player_id !== "string" || !PLAY_PLAYER_ID.test(answer.player_id)) return { ok: false, reason: "unavailable" };
    return { ok: true, external_id: answer.player_id };
  } catch (error) {
    logWarning("platform_verify_failed", { provider: "play_games", step: "transport", reason: errorCode(error) });
    return { ok: false, reason: "unavailable" };
  }
}

// ---- Game Center ----------------------------------------------------------------------------

export const GAME_CENTER_BUNDLE_ID = "com.aamirazeez.afteryou";
const TEAM_PLAYER_ID = /^[A-Za-z0-9:_.-]{1,128}$/;
const BASE64 = /^[A-Za-z0-9+/]{4,4096}={0,2}$/;
/** Apple's signature timestamp is in milliseconds. Outside this window the signature is stale. */
export const GAME_CENTER_WINDOW_MS = 10 * 60_000;

export type GameCenterCredential = { public_key_url: string; signature: string; salt: string; timestamp: number; team_player_id: string };

/** Only Apple's https hosts may serve the signing certificate; no port, user info or query. */
export function gameCenterKeyUrl(raw: unknown): URL | null {
  if (typeof raw !== "string" || raw.length > 512) return null;
  let url: URL;
  try { url = new URL(raw); } catch { return null; }
  if (url.protocol !== "https:" || url.port !== "" || url.username !== "" || url.password !== "" || url.search !== "" || url.hash !== "") return null;
  const host = url.hostname.toLowerCase();
  if (!host.endsWith(".apple.com") || !/^[a-z0-9.-]+$/.test(host)) return null;
  if (!/^\/[A-Za-z0-9/_.-]{1,200}\.cer$/.test(url.pathname)) return null;
  return url;
}

function base64Bytes(value: unknown): Uint8Array | null {
  if (typeof value !== "string" || !BASE64.test(value)) return null;
  try { return Uint8Array.from(atob(value), char => char.charCodeAt(0)); } catch { return null; }
}

/** The exact bytes Apple signs: teamPlayerID, bundle id, timestamp as a big-endian UInt64, then the salt. */
export function gameCenterPayload(teamPlayerId: string, bundleId: string, timestamp: number, salt: Uint8Array): Uint8Array {
  const encoder = new TextEncoder(), player = encoder.encode(teamPlayerId), bundle = encoder.encode(bundleId);
  const out = new Uint8Array(player.length + bundle.length + 8 + salt.length);
  out.set(player, 0); out.set(bundle, player.length);
  new DataView(out.buffer).setBigUint64(player.length + bundle.length, BigInt(timestamp), false);
  out.set(salt, player.length + bundle.length + 8);
  return out;
}

// A minimal DER walk: enough to find a certificate's validity and SubjectPublicKeyInfo.
type Der = { tag: number; start: number; header: number; length: number };
function derAt(bytes: Uint8Array, offset: number): Der | null {
  if (offset + 2 > bytes.length) return null;
  const tag = bytes[offset]; let length = bytes[offset + 1], header = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count < 1 || count > 3 || offset + 2 + count > bytes.length) return null;
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[offset + 2 + i];
    header += count;
  }
  if (offset + header + length > bytes.length) return null;
  return { tag, start: offset, header, length };
}
function children(bytes: Uint8Array, node: Der): Der[] | null {
  const out: Der[] = []; let offset = node.start + node.header; const end = offset + node.length;
  while (offset < end) { const child = derAt(bytes, offset); if (!child) return null; out.push(child); offset = child.start + child.header + child.length; }
  return offset === end ? out : null;
}
function derTime(bytes: Uint8Array, node: Der): number | null {
  const text = new TextDecoder().decode(bytes.subarray(node.start + node.header, node.start + node.header + node.length));
  const match = node.tag === 0x17 ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text) : node.tag === 0x18 ? /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text) : null;
  if (!match) return null;
  let year = Number(match[1]); if (node.tag === 0x17) year += year < 50 ? 2000 : 1900;
  return Date.UTC(year, Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6]));
}
/** SubjectPublicKeyInfo bytes of an X.509 certificate that is valid at `now`, or null. */
export function certificateKey(bytes: Uint8Array, now: number): Uint8Array | null {
  const certificate = derAt(bytes, 0);
  if (!certificate || certificate.tag !== 0x30 || certificate.header + certificate.length !== bytes.length) return null;
  const top = children(bytes, certificate); if (!top || top.length !== 3 || top[0].tag !== 0x30) return null;
  const tbs = children(bytes, top[0]); if (!tbs) return null;
  const fields = tbs[0]?.tag === 0xa0 ? tbs.slice(1) : tbs; // [0] version is optional
  // serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo
  if (fields.length < 6 || fields[3].tag !== 0x30 || fields[5].tag !== 0x30) return null;
  const validity = children(bytes, fields[3]); if (!validity || validity.length !== 2) return null;
  const notBefore = derTime(bytes, validity[0]), notAfter = derTime(bytes, validity[1]);
  if (notBefore === null || notAfter === null || now < notBefore || now > notAfter) return null;
  const key = fields[5];
  return bytes.slice(key.start, key.start + key.header + key.length);
}

/** Certificates by URL for an hour: Apple rotates them rarely and every fetch costs a round trip. */
const certificates = new Map<string, { bytes: Uint8Array; until: number }>();
export function forgetGameCenterCertificates(): void { certificates.clear(); }
async function certificate(url: URL, now: number): Promise<Uint8Array | null> {
  const held = certificates.get(url.href);
  if (held && held.until > now) return held.bytes;
  const response = await fetch(url.href, { method: "GET", redirect: "manual", signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!response.ok || !response.body) return null;
  const bytes = await readBounded(response.body, 16_384); if (!bytes || bytes.length < 64) return null;
  if (certificates.size >= 8) certificates.clear();
  certificates.set(url.href, { bytes, until: now + 3_600_000 });
  return bytes;
}

/**
 * Checks Game Center identity data (GKLocalPlayer fetchItems(forIdentityVerificationSignature:)).
 * The certificate comes only from an apple.com https URL, so TLS vouches for it; the timestamp must be
 * fresh, and the caller also burns the signature once (see PlatformLinks.claim) so it cannot be replayed.
 */
export async function verifyGameCenter(input: unknown, env: ServerVars, now = Date.now()): Promise<Verified> {
  if (!isObject(input)) return { ok: false, reason: "invalid" };
  const keys = Object.keys(input).sort().join(",");
  if (keys !== "public_key_url,salt,signature,team_player_id,timestamp") return { ok: false, reason: "invalid" };
  const url = gameCenterKeyUrl(input.public_key_url), signature = base64Bytes(input.signature), salt = base64Bytes(input.salt);
  const player = input.team_player_id, timestamp = input.timestamp;
  if (!url || !signature || !salt || salt.length > 64 || signature.length > 1024 || typeof player !== "string" || !TEAM_PLAYER_ID.test(player)) return { ok: false, reason: "invalid" };
  if (typeof timestamp !== "number" || !Number.isSafeInteger(timestamp) || Math.abs(now - timestamp) > GAME_CENTER_WINDOW_MS) return { ok: false, reason: "invalid" };
  const bundle = typeof env.GAME_CENTER_BUNDLE_ID === "string" && /^[A-Za-z0-9.-]{3,155}$/.test(env.GAME_CENTER_BUNDLE_ID) ? env.GAME_CENTER_BUNDLE_ID : GAME_CENTER_BUNDLE_ID;
  let der: Uint8Array | null;
  try { der = await certificate(url, now); } catch (error) { der = null; logWarning("platform_verify_failed", { provider: "game_center", step: "transport", reason: errorCode(error) }); }
  if (!der) return { ok: false, reason: "unavailable" };
  try {
    const spki = certificateKey(der, now);
    if (!spki) return { ok: false, reason: "invalid" };
    const key = await crypto.subtle.importKey("spki", spki, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, gameCenterPayload(player, bundle, timestamp, salt));
    return valid ? { ok: true, external_id: player } : { ok: false, reason: "invalid" };
  } catch (error) {
    logWarning("platform_verify_failed", { provider: "game_center", step: "verify", reason: errorCode(error) });
    return { ok: false, reason: "invalid" };
  }
}
