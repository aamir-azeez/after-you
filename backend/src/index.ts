import { routePhotoTransfer } from "./photo-transfer-routes";
import { JSON_HEADERS, errorResponse, json, result, bearerDigest } from "./http";
import { flags } from "./flags";
import { ApiError, ID_PATTERN, SECRET_PATTERN, IDEMPOTENCY_PATTERN, boundedJson, canonicalJson, digest, exactKeys, integer, inviteRoomId, legacySimulationVersion, newInvite, object, parseInvite, randomToken, recording, text, type RoomSnapshot, unwrap } from "./protocol";
import { entitlement } from "./entitlement";
import { requireHostAccess } from "./v2/host-access";
import { routeTesterAccess } from "./tester-access";
import { PRESENCE_SESSION, roomPresence } from "./presence";
import { routeFriends } from "./friends-routes";
import { friendNotifications, publishSocialRoom, socialInbox } from "./social-routes";
import { ROOM_INBOX_CLOSED_HEADER, ROOM_INBOX_LEAVE_HEADER, roomInbox } from "./room-inbox";
import { endReactionsWanted } from "./v2/end-reactions";
import { DISPLAY_NAME_PATH, displayNamesShown, friendLinkCode, namesRoomRoute, routeDisplayName, routeFriendLinkName } from "./display-names";
import { leaveRoom, requireInPlay } from "./room-leave";
import { resolveInvitation } from "./invitation-resolve";
import { LIVE_PATH, forwardLiveUpgrade } from "./live";
import { paidUntil, pollenAuthView, pollenEarning, pollenRoute, pollenMember, pollenMemberRoute, pollenTurnRoute, routePollen } from "./pollen/routes";
import type { PollenMember } from "./pollen/turn-facts";
import type { HistoryView, WalletView } from "./pollen/wallet";
import { shopOn } from "./pollen/features";
import { looksMemberRoute, memberLookOf } from "./pollen/looks-routes";
import type { Look } from "./pollen/catalog";
export { FriendRoomEvents } from "./friend-room-events";
import { friendEventsCapable } from "./friend-room-events";
import { publicPolicy } from "./public-policy";
import { appStatus } from "./app-status";
import { routeWaitlist } from "./waitlist";
import { requireInteraction, routeSafety } from "./safety-routes";
import { partnerBlocks } from "./safety";
import { routeSafetyOperator } from "./safety-operator";
export { SafetyProfile, SafetyInbox } from "./safety";
import { deleteLinkedIdentity, roomDeletionDispatcher, roomLinkVersion, type RoomLink } from "./room-links";
import { MAX_ROOM_LINKS, reserveWithinRoomLimit } from "./room-limit";
import { indexedLegacyRooms, indexedRoomInbox, pageOffset, roomSettler, withNext } from "./room-index-lists";
import { routeV2 } from "./v2/routes";
import { campaignRequestContext } from "./v2/campaign-room-access";
import { deleteCampaignIdentityLink } from "./v2/campaign-identity-deletion";
import { DRAIN_PREFIX, routeCampaignDrain } from "./v2/campaign-drain";
import { BINDING_PATTERN, registrationPlatform, validNotificationToken } from "./notifications";
export { PhotoTransfer, PhotoTransferBudget } from "./photo-transfer";
export { Player } from "./player";
export { PlatformLinks } from "./platform-links";
import { routePlatform, routePlatformRestore } from "./platform-routes";
export { Room } from "./room";
export { RoomV2 } from "./v2/room";
export { LeaderboardBoard } from "./leaderboards/board";
export { LeaderboardMember } from "./leaderboards/member";
import { routeLeaderboardRead, routeLeaderboards } from "./leaderboards/routes";
import { OPERATOR_PREFIX as LEADERBOARD_OPERATOR_PREFIX, routeLeaderboardOperator } from "./leaderboards/operator";
import { forgetLeaderboardPlayer, forgetLeaderboardPlayerIfKnown } from "./leaderboards/members";

/**
 * Every route under a room id except leave, which is already a quiet success for a room the caller has
 * no link to and never opens it. A player with no link to that room gets 404 room_not_found before any
 * room object is opened.
 */
const ROOM_ROUTE = /^\/v[12]\/rooms\/([A-Za-z0-9_-]{22})(?:\/(?!leave(?:\/|$))|$)/;
/**
 * The authenticated player, and on a room route its current safety token (Player.authorizeRoom).
 * While display names are on, a room route, room creation and joining also learn the player's
 * display name from the same call (`memberName`: a name, or null when anonymous); otherwise undefined.
 * While Pollen earning is on, a turn, room creation and joining learn the player's Full Journey end
 * the same way (`pollen`), and the wallet reads get their answer from it (`pollenView`).
 * While looks are on, a turn, room creation and joining learn the look the player wears the same way (`memberLook`).
 */
async function auth(request: Request, env: Env, path: string, deleting = false): Promise<{ playerId: string; safetyToken?: string; memberName?: string | null; pollen?: PollenMember; pollenView?: WalletView | HistoryView; memberLook?: Look }> {
  const id = request.headers.get("X-Player-Id");
  if (!id || !ID_PATTERN.test(id)) throw new ApiError(401, "invalid_auth");
  const value = request.headers.get("Authorization");
  if (!value?.startsWith("Bearer ")) throw new ApiError(401, "invalid_auth");
  const token = value.slice(7);
  if (!SECRET_PATTERN.test(token)) throw new ApiError(401, "invalid_auth");
  const hash = await digest(token), player = env.PLAYERS.getByName(id), room = ROOM_ROUTE.exec(path)?.[1];
  // The same single Player call either way; a room route also learns whether the room is linked.
  const memberRoute = pollenMemberRoute(request, path, env), view = pollenAuthView(request, path, env), looks = looksMemberRoute(request, path, env);
  const access: { authorized: boolean; linked: boolean; safety_token?: string; display_name?: string | null; fj_until?: number; pollen?: WalletView | HistoryView; look?: Look } = room !== undefined ? await player.authorizeRoom(hash, room, pollenTurnRoute(request, path, env), looks)
    : namesRoomRoute(request, path, env) || memberRoute || looks ? await player.authorizeNamed(hash, memberRoute, looks) : view !== null ? await player.authorizeWallet(hash, view, shopOn(env))
    : { authorized: await player.authorize(hash, deleting), linked: true };
  if (!access.authorized && !(deleting && await env.SAFETY_PROFILES.getByName(id).deletionReceipt(id, hash))) throw new ApiError(401, "invalid_auth");
  if (!(await env.PLAYER_LIMITER.limit({ key: id })).success) throw new ApiError(429, "rate_limited");
  if (!access.linked) throw new ApiError(404, "room_not_found");
  return { playerId: id, safetyToken: access.safety_token, memberName: flags.displayNames(env) ? access.display_name : undefined, pollen: pollenMember(access), pollenView: access.pollen, memberLook: looks ? memberLookOf(access) : undefined };
}
async function publicLimit(request: Request, env: Env): Promise<void> {
  // Bootstrap has no player identity yet. The edge-provided IP is used only as an ephemeral limiter key.
  const address = request.headers.get("CF-Connecting-IP") || "local";
  if (!(await env.PUBLIC_LIMITER.limit({ key: await digest(address) })).success) throw new ApiError(429, "rate_limited");
}
async function ensurePremium(snapshot: RoomSnapshot, nextLevel: boolean, env: Env): Promise<void> {
  if (snapshot.level_index + (nextLevel ? 1 : 0) < 3) return;
  await requireHostAccess(snapshot.host_id, env);
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url); const path = url.pathname;
      const policy = publicPolicy(request); if (policy) return policy;
      if (url.search) throw new ApiError(400, "query_not_supported");
      if (path === "/health" && request.method === "GET") return json({ status: "ok", api_version: 1, environment: env.ENVIRONMENT });
      // The friend link page's headline name: public, read-only, limited per address.
      const linkCode = friendLinkCode(path);
      if (linkCode !== null && request.method === "GET") { await publicLimit(request, env); return await routeFriendLinkName(request, linkCode, env); }
      // Absent unless UPDATE_GATE_ENABLED is "true": the path then falls through to auth() as before.
      if (path === "/v1/app-status" && request.method === "GET" && flags.updateGate(env)) { await publicLimit(request, env); return json(appStatus(request, env)); }
      if (path.startsWith("/operator/safety/")) { await publicLimit(request, env); return json(await routeSafetyOperator(request, path, env)); }
      if (path.startsWith(LEADERBOARD_OPERATOR_PREFIX)) { await publicLimit(request, env); return await routeLeaderboardOperator(request, path, env); }
      // Absent unless FEATURES lists LEADERBOARDS: a board read is public and cached, so it needs no Player request.
      const board = await routeLeaderboardRead(request, path, env); if (board) return board;
      // Absent unless STORY_DRAIN_ENABLED is "true": the path then falls through to auth() as before.
      if (path.startsWith(DRAIN_PREFIX) && flags.storyDrain(env)) { await publicLimit(request, env); return json(await routeCampaignDrain(request, path, env)); }
      // Absent unless IOS_WAITLIST_ENABLED is "true": the path then falls through as before (OPTIONS 405, others to auth()).
      const waitlist = await routeWaitlist(request, path, env); if (waitlist) return waitlist;
      if (request.method === "OPTIONS") return new Response(null, { status: 405, headers: JSON_HEADERS });
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
      // Absent unless PLAY_GAMES_ENABLED or GAME_CENTER_ENABLED is "true": the path then falls through to auth() as before.
      const restored = await routePlatformRestore(request, path, env); if (restored) return restored;
      if (path === "/v1/identity/deletion-ack" && request.method === "POST") {
        await publicLimit(request, env);
        const owner = text(request.headers.get("X-Player-Id"), ID_PATTERN, "invalid_auth");
        const authorization = request.headers.get("Authorization");
        if (!authorization?.startsWith("Bearer ") || !SECRET_PATTERN.test(authorization.slice(7))) throw new ApiError(401, "invalid_auth");
        const input = object(await boundedJson(request, 1024)); exactKeys(input, ["schema_version"]);
        if (Object.keys(input).length !== 1 || input.schema_version !== 1) throw new ApiError(400, "invalid_safety_request");
        return result(await env.SAFETY_PROFILES.getByName(owner).acknowledgeDeletion(owner, await digest(authorization.slice(7))));
      }
      const { playerId, safetyToken, memberName, pollen, pollenView, memberLook } = await auth(request, env, path, path === "/v1/identity" && request.method === "DELETE");
      const player = env.PLAYERS.getByName(playerId);
      // Absent unless a platform games flag is "true": the paths then answer 404 as before.
      const platform = await routePlatform(request, path, playerId, env); if (platform) return platform;
      // Absent unless LIVE_CONNECTION_ENABLED is "true": the path then answers 404 as before.
      if (path === LIVE_PATH && flags.liveConnection(env)) return await forwardLiveUpgrade(request, player, await bearerDigest(request));
      if (path === "/v1/room-inbox") {
        if (request.method !== "GET") throw new ApiError(405, "method_not_allowed");
        const showClosed = request.headers.get(ROOM_INBOX_CLOSED_HEADER) === "2", showLeft = flags.finishedRoomLeave(env) && request.headers.get(ROOM_INBOX_LEAVE_HEADER) === "1";
        // The face on the friend's latest turn, only for clients that show it while end reactions are on.
        const showReactions = flags.endReactions(env) && endReactionsWanted(request), showNames = displayNamesShown(request, env);
        const links = flags.roomIndex(env) ? null : await player.listRooms();
        if (links && links.length <= MAX_ROOM_LINKS) return json(await roomInbox(playerId, env, showClosed, showLeft, links, showReactions, showNames));
        const page = await indexedRoomInbox(playerId, env, showClosed, showLeft, pageOffset(request), showReactions, showNames);
        return withNext(json(page.body), page.next);
      }
      if (path === DISPLAY_NAME_PATH) return json(await routeDisplayName(request, playerId, env));
      if (pollenRoute(path, env)) return json(await routePollen(request, path, playerId, env, pollenView));
      const leaderboards = await routeLeaderboards(request, path, playerId, env); if (leaderboards !== null) return json(leaderboards);
      if (path === "/v1/invitations/resolve") return json(await resolveInvitation(request, env));
      if (path === "/v1/social/inbox") {
        if (request.method !== "GET") throw new ApiError(405, "method_not_allowed");
        return json(await socialInbox(playerId, env, friendEventsCapable(request)));
      }
      if (path === "/v1/social/publication") return json(await publishSocialRoom(request, playerId, env));
      const friendNotificationsMatch = path.match(/^\/v1\/friends\/([A-Za-z0-9_-]{22})\/notifications$/);
      if (friendNotificationsMatch) return json(await friendNotifications(request, playerId, friendNotificationsMatch[1], env));
      if (path === "/v1/friends" || path.startsWith("/v1/friends/")) return json(await routeFriends(request, path, playerId, env));
      if (path === "/v1/presence") {
        if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
        const input = object(await boundedJson(request, 1024));
        if (Object.keys(input).length !== 3 || input.schema_version !== 1 || typeof input.session_id !== "string" || !PRESENCE_SESSION.test(input.session_id) || typeof input.online !== "boolean") throw new ApiError(400, "invalid_presence_request");
        return result(await player.updatePresence(playerId, await bearerDigest(request), input.session_id, input.online));
      }
      const presenceMatch = path.match(/^\/v([12])\/rooms\/([A-Za-z0-9_-]{22})\/presence$/);
      if (presenceMatch) {
        if (request.method !== "GET") throw new ApiError(405, "method_not_allowed");
        return json(await roomPresence(env, playerId, await bearerDigest(request), presenceMatch[1] === "1" ? "legacy" : "relay", presenceMatch[2], presenceMatch[1] === "2" ? await campaignRequestContext(request, presenceMatch[2]) : undefined));
      }
      if (path === "/v1/tester-access") return json(await routeTesterAccess(request, playerId, env));
      if (path.startsWith("/v1/safety/")) return json(await routeSafety(request, path, playerId, env));
      if (path === "/v1/photo-transfer" || path.startsWith("/v1/photo-transfer/")) return await routePhotoTransfer(request, path, playerId, env);
      if (path === "/v1/notifications/registration" && (request.method === "POST" || request.method === "DELETE")) {
        const input = object(await boundedJson(request, 8192));
        exactKeys(input, ["schema_version", "binding_epoch", ...(request.method === "POST" ? ["token"] : [])]);
        if (input.schema_version !== 1) throw new ApiError(400, "invalid_notification_registration");
        const epoch = text(input.binding_epoch, BINDING_PATTERN, "invalid_notification_registration");
        const deviceHash = await bearerDigest(request);
        if (request.method === "DELETE") return result(await player.unregisterNotifications(deviceHash, epoch));
        if (!validNotificationToken(input.token)) throw new ApiError(400, "invalid_notification_registration");
        const platform = registrationPlatform(request);
        if (platform === "invalid") throw new ApiError(400, "invalid_notification_registration");
        return result(await player.registerNotifications(deviceHash, input.token, epoch, friendEventsCapable(request), platform));
      }
      if (path === "/v1/notifications/categories" && request.method === "POST") {
        // Separate from registration, whose exact keys older servers enforce.
        const input = object(await boundedJson(request, 1024));
        exactKeys(input, ["schema_version", "binding_epoch", "redo_requests"]);
        if (input.schema_version !== 1 || typeof input.redo_requests !== "boolean") throw new ApiError(400, "invalid_notification_categories");
        const epoch = text(input.binding_epoch, BINDING_PATTERN, "invalid_notification_categories");
        return result(await player.setNotificationCategories(await bearerDigest(request), epoch, input.redo_requests));
      }
      if (path === "/v1/identity" && request.method === "GET") return json({ player_id: playerId });
      if (path === "/v1/identity" && request.method === "DELETE") {
        if (await env.SAFETY_PROFILES.getByName(playerId).deletionReceipt(playerId, await bearerDigest(request))) return json({ deleted: true });
        const deviceHash = await bearerDigest(request);
        // Every leaderboard forgets the player first; a retried deletion runs it again. While leaderboards
        // are off only a player who ever touched them is forgotten (a blank member's read stores nothing),
        // and a failure here never holds up the deletion.
        if (flags.leaderboards(env)) await forgetLeaderboardPlayer(env, playerId);
        else await forgetLeaderboardPlayerIfKnown(env, playerId).catch(() => undefined);
        const dispatcher = roomDeletionDispatcher(env.ROOMS, (link, id) => env.ROOMS_V2.getByName(link.room_id).eraseForPlayer(id, link.host),
          (link, id) => deleteCampaignIdentityLink(player, {
            erase: (owner, roomId, allocation) => env.ROOMS_V2.getByName(roomId).eraseCampaignRoot(owner, roomId, allocation),
            cancel: (owner, roomId, body) => env.ROOMS_V2.getByName(roomId).cancelCampaignJoinRoot(owner, body)
          }, id, link, deviceHash));
        return result(await deleteLinkedIdentity(playerId, player, dispatcher, deviceHash));
      }
      if (path === "/v1/entitlement" && request.method === "GET") {
        // While Pollen earning is on, the Full Journey end this check reports is noted by the authorize call it already makes.
        let until: number | undefined;
        const checked = await entitlement(playerId, env, pollenEarning(env) ? value => { until = value; } : undefined);
        if (!await player.authorize(await bearerDigest(request), false, pollenEarning(env) ? paidUntil(checked, until) : undefined)) throw new ApiError(401, "invalid_auth");
        return json(checked);
      }
      if (path.startsWith("/v2/")) return await routeV2(request, path, playerId, env, safetyToken, memberName, pollen, memberLook);
      if (path === "/v1/rooms" && request.method === "GET") {
        const links = flags.roomIndex(env) ? null : await player.listRooms();
        if (!links || links.length > MAX_ROOM_LINKS) { const page = await indexedLegacyRooms(playerId, env, pageOffset(request)); return withNext(json(page.body), page.next); }
        const snapshots: RoomSnapshot[] = [], blocked = partnerBlocks(env, playerId);
        for (const link of links) {
          if (roomLinkVersion(link) !== 1) continue;
          const item = await env.ROOMS.getByName(link.room_id).snapshot(playerId);
          if (item.ok) { if (!await blocked(item.value.host_id, item.value.guest_id)) snapshots.push(item.value); } else if (item.status === 404) await player.removeRoom(link.room_id);
        }
        return json({ rooms: snapshots });
      }
      if (path === "/v1/rooms" && request.method === "POST") {
        const input = object(await boundedJson(request, 4096)); exactKeys(input, ["idempotency_key", "simulation_version"]);
        const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
        const simulationVersion = legacySimulationVersion(input.simulation_version === undefined ? 1 : input.simulation_version);
        const invite_code = newInvite();
        const proposed: RoomLink = { room_id: await inviteRoomId(invite_code, 1), invite_code, host: true };
        const link = unwrap(await reserveWithinRoomLimit(env, playerId, settled => player.reserveRoom(key, proposed, settled), roomSettler(env)));
        return result(await env.ROOMS.getByName(link.room_id).initialize(link.room_id, playerId, link.invite_code, simulationVersion));
      }
      if (path === "/v1/rooms/join" && request.method === "POST") {
        const input = object(await boundedJson(request, 4096)); exactKeys(input, ["invite_code", "simulation_version"]);
        const supportedSimulationVersion = legacySimulationVersion(input.simulation_version === undefined ? 1 : input.simulation_version);
        const code = parseInvite(input.invite_code), roomId = await inviteRoomId(code, 1);
        const alreadyLinked = (await player.listRooms()).some(link => roomLinkVersion(link) === 1 && link.room_id === roomId);
        unwrap(await reserveWithinRoomLimit(env, playerId, settled => player.addRoom({ room_id: roomId, invite_code: "", host: false }, settled), roomSettler(env)));
        const joined = await env.ROOMS.getByName(roomId).join(playerId, code, supportedSimulationVersion);
        if (!joined.ok) { if (!alreadyLinked) await player.removeRoom(roomId); return result(joined); }
        if (!await player.authorize(await bearerDigest(request))) {
          await env.ROOMS.getByName(roomId).eraseForPlayer(playerId); throw new ApiError(401, "identity_unavailable");
        }
        return result(joined);
      }
      const match = path.match(/^\/v1\/rooms\/([a-zA-Z0-9_-]{22})(?:\/(turns|fork|advance|collection|reactions|redo|leave))?$/);
      if (!match) throw new ApiError(404, "not_found");
      const roomId = match[1], operation = match[2]; const room = env.ROOMS.getByName(roomId);
      if (operation === "leave") {
        if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
        return json(await leaveRoom(request, playerId, env, 1, roomId));
      }
      if (request.method !== "DELETE") await requireInteraction(env, playerId, "legacy", roomId);
      if (operation === "redo") {
        if (request.method === "GET") return result(await room.redo(playerId, undefined, await bearerDigest(request)));
        if (request.method === "POST") return result(await room.redo(playerId, await boundedJson(request, 4096), await bearerDigest(request)));
        throw new ApiError(405, "method_not_allowed");
      }
      if (!operation && request.method === "GET") return result(await room.snapshot(playerId));
      if (!operation && request.method === "DELETE") {
        await requireInPlay(request, () => room.memberRoomState(playerId));
        const deleted = unwrap(await room.eraseForPlayer(playerId)); await player.removeRoom(roomId); return json(deleted);
      }
      if (operation === "collection" && request.method === "GET") return json({ islands: unwrap(await room.collection(playerId)) });
      if (request.method !== "POST" || operation === "collection") throw new ApiError(405, "method_not_allowed");
      const input = object(await boundedJson(request));
      exactKeys(input, ["base_revision", "idempotency_key", ...(operation === "turns" ? ["recording"] : operation === "reactions" ? ["reaction"] : operation === "fork" ? ["redo_request_id"] : [])]);
      const redoRequestId = input.redo_request_id === undefined ? undefined : text(input.redo_request_id, /^[a-f0-9]{64}$/, "invalid_redo_request");
      if (redoRequestId !== undefined && !await player.authorize(await bearerDigest(request))) throw new ApiError(401, "invalid_auth");
      const revision = integer(input.base_revision, 0, Number.MAX_SAFE_INTEGER), key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
      const requestHash = await digest(canonicalJson({ operation, ...input }));
      // Reconciliation reads an already accepted result. Entitlement checks apply
      // only to new mutations, not retries evaluated against a later island.
      const operationState = unwrap(await room.operationSnapshot(playerId, key, requestHash));
      if (operationState.accepted) return json(operationState.room);
      const snapshot = operationState.room;
      if (operation === "turns") { const value = recording(input.recording); await ensurePremium(snapshot, false, env); return result(await room.commit(playerId, revision, key, requestHash, value)); }
      if (operation === "fork") { await ensurePremium(snapshot, false, env); return result(await room.fork(playerId, revision, key, requestHash, redoRequestId, redoRequestId === undefined ? undefined : await bearerDigest(request))); }
      if (operation === "advance") { await ensurePremium(snapshot, true, env); return result(await room.advance(playerId, revision, key, requestHash)); }
      if (operation === "reactions") {
        if (input.reaction !== "love" && input.reaction !== "sparkles" && input.reaction !== "again") throw new ApiError(400, "invalid_reaction");
        return result(await room.react(playerId, revision, key, requestHash, input.reaction));
      }
      throw new ApiError(404, "not_found");
    } catch (error) {
      // Never log request bodies, credentials, invite codes or upstream error payloads.
      return errorResponse(error);
    }
  }
} satisfies ExportedHandler<Env>;
