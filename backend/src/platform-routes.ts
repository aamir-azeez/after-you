import { ApiError, ID_PATTERN, IDEMPOTENCY_PATTERN, SECRET_PATTERN, boundedJson, canonicalJson, digest, exactKeys, isObject, object, text, unwrap } from "./protocol";
import { flags, type ServerVars } from "./flags";
import { json } from "./http";
import { GAME_CENTER_WINDOW_MS, gameCenterNonceSource, playGamesConfig, verifyGameCenter, verifyPlayGames, type Verified } from "./platform-verify";
import { PLATFORM_LINKS_OBJECT, type PlatformProvider } from "./platform-links";

/**
 * Platform games accounts (Play Games, Game Center) as a way back to an existing friend identity.
 *
 * - POST /v1/platform/link    (signed in) link the verified account to the caller, or report a conflict.
 * - POST /v1/platform/unlink  (signed in) remove the caller's link for one provider.
 * - POST /v1/platform/restore (public)    rotate the linked player's credentials to the ones this
 *   device proposes, exactly like recovery with a recovery code (Player.restoreLinked).
 *
 * Each provider is absent unless its flag is "true": the paths then answer as before (404 after
 * auth, 401 for restore). A flag that is on without its config answers 503 platform_unavailable.
 * GET /v2/capabilities names a provider only to a client that sends X-AfterYou-Platform-Games: 1.
 */
export const PLATFORM_HEADER = "X-AfterYou-Platform-Games";
export const LINK_PATH = "/v1/platform/link", UNLINK_PATH = "/v1/platform/unlink", RESTORE_PATH = "/v1/platform/restore";
const MAX_BODY = 8192;

export function providerEnabled(provider: PlatformProvider, env: ServerVars): boolean {
  return provider === "play_games" ? flags.playGames(env) : flags.gameCenter(env);
}
export function anyProviderEnabled(env: ServerVars): boolean { return flags.playGames(env) || flags.gameCenter(env); }

/** Capability fields: empty unless a provider is on (and configured) and the client asked. */
export function platformCapability(request: Request, env: ServerVars): Record<string, number | string> {
  if (request.headers.get(PLATFORM_HEADER) !== "1") return {};
  const out: Record<string, number | string> = {};
  const play = flags.playGames(env) ? playGamesConfig(env) : null;
  // The web client id is public: the phone needs it to ask Google for a server auth code.
  if (play) { out.play_games_version = 1; out.play_games_web_client_id = play.clientId; }
  if (flags.gameCenter(env)) out.game_center_version = 1;
  return out;
}

function provider(value: unknown, env: ServerVars): PlatformProvider {
  if (value !== "play_games" && value !== "game_center") throw new ApiError(400, "invalid_platform_provider");
  if (!providerEnabled(value, env)) throw new ApiError(404, "not_found");
  return value;
}

type Proof = { externalHash: string; nonce?: string; nonceExpiresAt: number };
/** The verified account as a hash, plus a one-time nonce for signatures that could be replayed. */
async function prove(kind: PlatformProvider, credential: unknown, env: ServerVars): Promise<Proof> {
  let verified: Verified, nonce: string | undefined;
  if (kind === "play_games") {
    // A Play Games auth code is single use at Google, so it needs no nonce of ours.
    if (!isObject(credential) || Object.keys(credential).join() !== "server_auth_code") throw new ApiError(400, "invalid_platform_credential");
    verified = await verifyPlayGames(credential.server_auth_code, env);
  } else {
    verified = await verifyGameCenter(credential, env);
    const source = verified.ok ? gameCenterNonceSource(credential) : null;
    if (verified.ok && source === null) throw new ApiError(401, "platform_credential_invalid");
    if (source !== null) nonce = await digest(source);
  }
  if (!verified.ok) {
    if (verified.reason === "invalid") throw new ApiError(401, "platform_credential_invalid");
    throw new ApiError(503, "platform_unavailable");
  }
  return { externalHash: await digest(`${kind}:${verified.external_id}`), nonce, nonceExpiresAt: Date.now() + 2 * GAME_CENTER_WINDOW_MS };
}

async function limitPublic(request: Request, env: Env): Promise<void> {
  // Restore is public and costs two upstream calls: a tight IP bucket of its own key space.
  const ip = await digest(request.headers.get("CF-Connecting-IP") || "local");
  if (!(await env.TESTER_CODE_LIMITER.limit({ key: "platform-ip:" + ip })).success) throw new ApiError(429, "rate_limited");
}

/** Signed-in link and unlink. Returns null for any other path, or when the provider is off, so routing falls through. */
export async function routePlatform(request: Request, path: string, playerId: string, env: Env & ServerVars): Promise<Response | null> {
  if ((path !== LINK_PATH && path !== UNLINK_PATH) || !anyProviderEnabled(env)) return null;
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = object(await boundedJson(request, MAX_BODY));
  const links = env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT);
  if (path === UNLINK_PATH) {
    exactKeys(input, ["schema_version", "provider"]);
    if (input.schema_version !== 1) throw new ApiError(400, "invalid_platform_request");
    const kind = provider(input.provider, env);
    return json({ schema_version: 1, provider: kind, unlinked: await links.unlink(kind, playerId) });
  }
  exactKeys(input, ["schema_version", "provider", "credential", "replace", "recovery_code"]);
  if (input.schema_version !== 1 || (input.replace !== undefined && typeof input.replace !== "boolean")) throw new ApiError(400, "invalid_platform_request");
  const kind = provider(input.provider, env);
  // A link can later rotate this identity's recovery code (restore), so it needs the recovery code too:
  // a device token alone never gets that power. Checked before any upstream call.
  const recovery = text(input.recovery_code, SECRET_PATTERN, "invalid_recovery");
  if (!(await env.TESTER_CODE_LIMITER.limit({ key: "platform-player:" + playerId })).success) throw new ApiError(429, "rate_limited");
  if (!(await env.PLAYERS.getByName(playerId).recoveryMatches(await digest(recovery)))) throw new ApiError(401, "invalid_recovery");
  const proof = await prove(kind, input.credential, env);
  const answer = await links.link(kind, proof.externalHash, playerId, input.replace === true, proof.nonce, proof.nonceExpiresAt);
  if (answer.status === "replayed") throw new ApiError(401, "platform_credential_invalid");
  return json({ schema_version: 1, provider: kind, status: answer.status, changed: answer.changed });
}

/** Public restore. Null when no provider is on, so the path falls through to auth() (401) as before. */
export async function routePlatformRestore(request: Request, path: string, env: Env & ServerVars): Promise<Response | null> {
  if (path !== RESTORE_PATH || request.method !== "POST" || !anyProviderEnabled(env)) return null;
  await limitPublic(request, env);
  const input = object(await boundedJson(request, MAX_BODY));
  exactKeys(input, ["schema_version", "provider", "credential", "idempotency_key", "next_device_token", "next_recovery_code"]);
  if (input.schema_version !== 1) throw new ApiError(400, "invalid_platform_request");
  const kind = provider(input.provider, env);
  const idempotency_key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
  const nextDevice = text(input.next_device_token, SECRET_PATTERN), nextRecovery = text(input.next_recovery_code, SECRET_PATTERN);
  // The credential is left out: a retry after a lost reply carries a fresh one-time code.
  const requestHash = await digest(canonicalJson({ provider: kind, idempotency_key, next_device_token: nextDevice, next_recovery_code: nextRecovery }));
  const proof = await prove(kind, input.credential, env);
  const links = env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT);
  const found = await links.lookup(kind, proof.externalHash, proof.nonce, proof.nonceExpiresAt);
  if ("replayed" in found) throw new ApiError(401, "platform_credential_invalid");
  if (found.player_id === null || !ID_PATTERN.test(found.player_id)) throw new ApiError(404, "platform_link_not_found");
  const restored = await env.PLAYERS.getByName(found.player_id).restoreLinked(await digest(nextDevice), await digest(nextRecovery), requestHash);
  if (!restored.ok && restored.code === "identity_absent") {
    // The linked player was erased between link and restore: drop the stale row so the account is free.
    await links.forget(kind, proof.externalHash, found.player_id);
    throw new ApiError(404, "platform_link_not_found");
  }
  const value = unwrap(restored);
  return json({ schema_version: 1, provider: kind, player_id: value.player_id, restored: true });
}
