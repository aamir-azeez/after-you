import { routePhotoTransfer } from "./photo-transfer-routes";
import { ApiError, ID_PATTERN, SECRET_PATTERN, IDEMPOTENCY_PATTERN, boundedJson, canonicalJson, digest, exactKeys, integer, object, randomToken, recording, text, type Outcome, type RoomSnapshot } from "./protocol";
import { entitlement } from "./entitlement";
import { routeTesterAccess } from "./tester-access";
import { PRESENCE_SESSION, roomPresence } from "./presence";
import { publicPolicy } from "./public-policy";
import { requireInteraction, routeSafety } from "./safety-routes";
import { interactionBlocked } from "./safety";
import { routeSafetyOperator } from "./safety-operator";
export { SafetyProfile, SafetyInbox } from "./safety";
import { deleteLinkedIdentity, roomDeletionDispatcher, roomLinkVersion } from "./room-links";
import { routeV2 } from "./v2/routes";
import { BINDING_PATTERN, validNotificationToken } from "./notifications";
export { PhotoTransfer, PhotoTransferBudget } from "./photo-transfer";
export { Player } from "./player";
export { Room } from "./room";
export { RoomV2 } from "./v2/room";

const responseHeaders = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" };
function json(value: unknown, status = 200): Response { return new Response(JSON.stringify(value), { status, headers: responseHeaders }); }
function unwrap<T>(result: Outcome<T>): T { if (!result.ok) throw new ApiError(result.status, result.code); return result.value; }
function result<T>(outcome: Outcome<T>): Response { return json(unwrap(outcome)); }
function invite(value: unknown): string {
  if (typeof value !== "string" || value.length > 40) throw new ApiError(400, "invalid_invite");
  return text(value.replace(/[\s-]/g, "").toUpperCase(), /^[A-F0-9]{20}$/, "invalid_invite");
}
async function auth(request: Request, env: Env, deleting = false): Promise<string> {
  const id = request.headers.get("X-Player-Id");
  if (!id || !ID_PATTERN.test(id)) throw new ApiError(401, "invalid_auth");
  const value = request.headers.get("Authorization");
  if (!value?.startsWith("Bearer ")) throw new ApiError(401, "invalid_auth");
  const token = value.slice(7);
  if (!SECRET_PATTERN.test(token)) throw new ApiError(401, "invalid_auth");
  const hash = await digest(token);
  if (!await env.PLAYERS.getByName(id).authorize(hash, deleting) && !(deleting && await env.SAFETY_PROFILES.getByName(id).deletionReceipt(id, hash))) throw new ApiError(401, "invalid_auth");
  if (!(await env.PLAYER_LIMITER.limit({ key: id })).success) throw new ApiError(429, "rate_limited");
  return id;
}
async function publicLimit(request: Request, env: Env): Promise<void> {
  // Bootstrap has no player identity yet. The edge-provided IP is used only as an ephemeral limiter key.
  const address = request.headers.get("CF-Connecting-IP") || "local";
  if (!(await env.PUBLIC_LIMITER.limit({ key: await digest(address) })).success) throw new ApiError(429, "rate_limited");
}
async function ensurePremium(snapshot: RoomSnapshot, nextLevel: boolean, env: Env): Promise<void> {
  if (snapshot.level_index + (nextLevel ? 1 : 0) < 3) return;
  const access = await entitlement(snapshot.host_id, env);
  if (!access.full_journey) throw new ApiError(access.status === "verified" ? 402 : 503, access.status === "verified" ? "host_unlock_required" : "entitlement_unavailable");
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url); const path = url.pathname;
      const policy = publicPolicy(request); if (policy) return policy;
      if (url.search) throw new ApiError(400, "query_not_supported");
      if (path === "/health" && request.method === "GET") return json({ status: "ok", api_version: 1, environment: env.ENVIRONMENT });
      if (path.startsWith("/operator/safety/")) { await publicLimit(request, env); return json(await routeSafetyOperator(request, path, env)); }
      if (request.method === "OPTIONS") return new Response(null, { status: 405, headers: responseHeaders });
      if (path === "/v1/identity" && request.method === "POST") {
        await publicLimit(request, env); const input = object(await boundedJson(request, 4096)); exactKeys(input, []);
        const player_id = randomToken(16), device_token = randomToken(), recovery_code = randomToken();
        unwrap(await env.PLAYERS.getByName(player_id).create(player_id, await digest(device_token), await digest(recovery_code)));
        return json({ player_id, device_token, recovery_code }, 201);
      }
      if (path === "/v1/identity/recover" && request.method === "POST") {
        await publicLimit(request, env); const input = object(await boundedJson(request, 4096));
        exactKeys(input, ["player_id", "recovery_code", "idempotency_key", "next_device_token", "next_recovery_code"]);
        // Legacy clients cannot safely receive server-generated secrets if their
        // response is lost. Reject that protocol without rotating anything.
        if (input.idempotency_key === undefined || input.next_device_token === undefined || input.next_recovery_code === undefined) throw new ApiError(400, "recovery_request_required");
        const player_id = text(input.player_id, ID_PATTERN), recovery = text(input.recovery_code, SECRET_PATTERN);
        const idempotency_key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
        const nextDevice = text(input.next_device_token, SECRET_PATTERN), nextRecovery = text(input.next_recovery_code, SECRET_PATTERN);
        const requestHash = await digest(canonicalJson({ player_id, recovery_code: recovery, idempotency_key, next_device_token: nextDevice, next_recovery_code: nextRecovery }));
        return result(await env.PLAYERS.getByName(player_id).recover(await digest(recovery), await digest(nextDevice), await digest(nextRecovery), requestHash));
      }
      if (path === "/v1/identity/deletion-ack" && request.method === "POST") {
        await publicLimit(request, env);
        const owner = text(request.headers.get("X-Player-Id"), ID_PATTERN, "invalid_auth");
        const authorization = request.headers.get("Authorization");
        if (!authorization?.startsWith("Bearer ") || !SECRET_PATTERN.test(authorization.slice(7))) throw new ApiError(401, "invalid_auth");
        const input = object(await boundedJson(request, 1024)); exactKeys(input, ["schema_version"]);
        if (Object.keys(input).length !== 1 || input.schema_version !== 1) throw new ApiError(400, "invalid_safety_request");
        return result(await env.SAFETY_PROFILES.getByName(owner).acknowledgeDeletion(owner, await digest(authorization.slice(7))));
      }
      const playerId = await auth(request, env, path === "/v1/identity" && request.method === "DELETE");
      const player = env.PLAYERS.getByName(playerId);
      if (path === "/v1/presence") {
        if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
        const input = object(await boundedJson(request, 1024));
        if (Object.keys(input).length !== 3 || input.schema_version !== 1 || typeof input.session_id !== "string" || !PRESENCE_SESSION.test(input.session_id) || typeof input.online !== "boolean") throw new ApiError(400, "invalid_presence_request");
        return result(await player.updatePresence(playerId, await digest(request.headers.get("Authorization")!.slice(7)), input.session_id, input.online));
      }
      const presenceMatch = path.match(/^\/v([12])\/rooms\/([A-Za-z0-9_-]{22})\/presence$/);
      if (presenceMatch) {
        if (request.method !== "GET") throw new ApiError(405, "method_not_allowed");
        return json(await roomPresence(env, playerId, await digest(request.headers.get("Authorization")!.slice(7)), presenceMatch[1] === "1" ? "legacy" : "relay", presenceMatch[2]));
      }
      if (path === "/v1/tester-access") return json(await routeTesterAccess(request, playerId, env));
      if (path.startsWith("/v1/safety/")) return json(await routeSafety(request, path, playerId, env));
      if (path === "/v1/photo-transfer" || path.startsWith("/v1/photo-transfer/")) return await routePhotoTransfer(request, path, playerId, env);
      if (path === "/v1/notifications/registration" && (request.method === "POST" || request.method === "DELETE")) {
        const input = object(await boundedJson(request, 8192));
        exactKeys(input, ["schema_version", "binding_epoch", ...(request.method === "POST" ? ["token"] : [])]);
        if (input.schema_version !== 1) throw new ApiError(400, "invalid_notification_registration");
        const epoch = text(input.binding_epoch, BINDING_PATTERN, "invalid_notification_registration");
        const deviceHash = await digest(request.headers.get("Authorization")!.slice(7));
        if (request.method === "DELETE") return result(await player.unregisterNotifications(deviceHash, epoch));
        if (!validNotificationToken(input.token)) throw new ApiError(400, "invalid_notification_registration");
        return result(await player.registerNotifications(deviceHash, input.token, epoch));
      }
      if (path === "/v1/identity" && request.method === "GET") return json({ player_id: playerId });
      if (path === "/v1/identity" && request.method === "DELETE") {
        if (await env.SAFETY_PROFILES.getByName(playerId).deletionReceipt(playerId, await digest(request.headers.get("Authorization")!.slice(7)))) return json({ deleted: true });
        const dispatcher = roomDeletionDispatcher(env.ROOMS, (link, id) => env.ROOMS_V2.getByName(link.room_id).eraseForPlayer(id, link.host));
        return result(await deleteLinkedIdentity(playerId, player, dispatcher, await digest(request.headers.get("Authorization")!.slice(7))));
      }
      if (path === "/v1/entitlement" && request.method === "GET") {
        const checked = await entitlement(playerId, env);
        if (!await player.authorize(await digest(request.headers.get("Authorization")!.slice(7)))) throw new ApiError(401, "invalid_auth");
        return json(checked);
      }
      if (path.startsWith("/v2/")) return await routeV2(request, path, playerId, env);
      if (path === "/v1/rooms" && request.method === "GET") {
        const snapshots: RoomSnapshot[] = [];
        for (const link of await player.listRooms()) {
          if (roomLinkVersion(link) !== 1) continue;
          const item = await env.ROOMS.getByName(link.room_id).snapshot(playerId);
          if (item.ok) { if (!await interactionBlocked(env, item.value.host_id, item.value.guest_id)) snapshots.push(item.value); } else if (item.status === 404) await player.removeRoom(link.room_id);
        }
        return json({ rooms: snapshots });
      }
      if (path === "/v1/rooms" && request.method === "POST") {
        const input = object(await boundedJson(request, 4096)); exactKeys(input, ["idempotency_key"]);
        const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
        const invite_code = [...crypto.getRandomValues(new Uint8Array(10))].map(value => value.toString(16).padStart(2, "0")).join("").toUpperCase();
        const link = unwrap(await player.reserveRoom(key, { room_id: (await digest(invite_code)).slice(0, 22), invite_code, host: true }));
        return result(await env.ROOMS.getByName(link.room_id).initialize(link.room_id, playerId, link.invite_code));
      }
      if (path === "/v1/rooms/join" && request.method === "POST") {
        const input = object(await boundedJson(request, 4096)); exactKeys(input, ["invite_code"]);
        const code = invite(input.invite_code), roomId = (await digest(code)).slice(0, 22);
        const alreadyLinked = (await player.listRooms()).some(link => roomLinkVersion(link) === 1 && link.room_id === roomId);
        unwrap(await player.addRoom({ room_id: roomId, invite_code: "", host: false }));
        const joined = await env.ROOMS.getByName(roomId).join(playerId, code);
        if (!joined.ok) { if (!alreadyLinked) await player.removeRoom(roomId); return result(joined); }
        if (!await player.authorize(await digest(request.headers.get("Authorization")!.slice(7)))) {
          await env.ROOMS.getByName(roomId).eraseForPlayer(playerId); throw new ApiError(401, "identity_unavailable");
        }
        return result(joined);
      }
      const match = path.match(/^\/v1\/rooms\/([a-zA-Z0-9_-]{22})(?:\/(turns|fork|advance|collection|reactions))?$/);
      if (!match) throw new ApiError(404, "not_found");
      const roomId = match[1], operation = match[2]; const room = env.ROOMS.getByName(roomId);
      if (request.method !== "DELETE") await requireInteraction(env, playerId, "legacy", roomId);
      if (!operation && request.method === "GET") return result(await room.snapshot(playerId));
      if (!operation && request.method === "DELETE") { const deleted = unwrap(await room.eraseForPlayer(playerId)); await player.removeRoom(roomId); return json(deleted); }
      if (operation === "collection" && request.method === "GET") return json({ islands: unwrap(await room.collection(playerId)) });
      if (request.method !== "POST" || operation === "collection") throw new ApiError(405, "method_not_allowed");
      const input = object(await boundedJson(request));
      exactKeys(input, ["base_revision", "idempotency_key", ...(operation === "turns" ? ["recording"] : operation === "reactions" ? ["reaction"] : [])]);
      const revision = integer(input.base_revision, 0, Number.MAX_SAFE_INTEGER), key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
      const requestHash = await digest(canonicalJson({ operation, ...input }));
      // Reconciliation reads an already accepted result. Entitlement checks apply
      // only to new mutations, not retries evaluated against a later island.
      const operationState = unwrap(await room.operationSnapshot(playerId, key, requestHash));
      if (operationState.accepted) return json(operationState.room);
      const snapshot = operationState.room;
      if (operation === "turns") { const value = recording(input.recording); await ensurePremium(snapshot, false, env); return result(await room.commit(playerId, revision, key, requestHash, value)); }
      if (operation === "fork") { await ensurePremium(snapshot, false, env); return result(await room.fork(playerId, revision, key, requestHash)); }
      if (operation === "advance") { await ensurePremium(snapshot, true, env); return result(await room.advance(playerId, revision, key, requestHash)); }
      if (operation === "reactions") {
        if (input.reaction !== "love" && input.reaction !== "sparkles" && input.reaction !== "again") throw new ApiError(400, "invalid_reaction");
        return result(await room.react(playerId, revision, key, requestHash, input.reaction));
      }
      throw new ApiError(404, "not_found");
    } catch (error) {
      if (error instanceof ApiError) {
        const response = json({ error: { code: error.code, retryable: error.status === 429 || error.status === 503 } }, error.status);
        if (error.status === 429 || error.status === 503) response.headers.set("Retry-After", error.status === 429 ? "60" : "15");
        return response;
      }
      // Never log request bodies, credentials, invite codes or upstream error payloads.
      return json({ error: { code: "service_unavailable", retryable: true } }, 503);
    }
  }
} satisfies ExportedHandler<Env>;
