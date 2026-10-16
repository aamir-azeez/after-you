import { ApiError, IDEMPOTENCY_PATTERN, boundedJson, canonicalJson, digest, inviteRoomId, newInvite, object, parseInvite, readBounded, text, unwrap, type Outcome } from "../protocol";
import { bytes, json, bearerDigest } from "../http";
import { flags } from "../flags";
import { roomLinkVersion, type RoomLink } from "../room-links";
import { reserveWithinRoomLimit } from "../room-limit";
import { MAX_V2_BODY_BYTES, exact, boundedTurnValue } from "./protocol";
import { advertisedChapters, chapter, creatable } from "./chapters";
import { MAX_ROOM_STAGES } from "./chapter-types";
import { stageWithin } from "./room-stage";
import type { KnownRoom, PolledRoomV2, RoomLobbyV2 } from "./room";
import { PHOTO_TURN_PATTERN } from "./photos";
import { REACTION_PAIR_PATTERN } from "./reactions";
import { requireInteraction, requirePhotoTerms } from "../safety-routes";
import { partnerBlocks } from "../safety";
import { routeCampaign } from "./campaign-routes";
import { advertisedCampaigns } from "./campaign-registry";
import { campaignRequestContext } from "./campaign-room-access";
import { campaignProductionEnabled } from "./campaign-production";
import { MAX_REPLAY_ARCHIVE_BYTES } from "./replay-transfer";
import { leaveRoom, requireInPlay } from "../room-leave";
import { HISTORY_HEADER, historySupport } from "./history";
import { MAX_ATTEMPT_BYTES } from "./history-blob";
import { parsePosition } from "./history-room";
import { requireHostAccess, requireRoomHostAccess } from "./host-access";

/** A raw body of at most `max` bytes. */
async function boundedBytes(request: Request, max: number): Promise<Uint8Array> {
  if (request.headers.get("content-type")?.toLowerCase() !== "application/octet-stream") throw new ApiError(415, "bytes_required");
  if (Number(request.headers.get("content-length")) > max) throw new ApiError(413, "body_too_large");
  if (!request.body) throw new ApiError(400, "body_required");
  const data = await readBounded(request.body, max);
  if (!data) throw new ApiError(413, "body_too_large");
  return data;
}
/** A client opts into chapters with more than two stages with a header (like X-AfterYou-Campaign-Schema); the router refuses query strings, and older servers ignore unknown headers. */
/** Sent by 0.6.1 and later on a room read: the client treats 410 replay_transferred as a finished room. */
export const FINISHED_ROOM_HEADER = "X-AfterYou-Finished-Room";
/**
 * 0.6.0 and older stop all online play when their saved last room answers 410
 * replay_transferred. With LEGACY_TRANSFERRED_ROOM_UNBLOCK=true (off when unset),
 * such a client gets the Story boundary answer instead, which those builds accept
 * and move past. Its cost on those builds: that room reads as Story for the app
 * session, and a redo of the finished room cannot restore its replay.
 */
function legacyTransferredUnblock(request: Request, env: Env, context: unknown): boolean {
  return flags.legacyTransferredRoomUnblock(env) && context === undefined && request.headers.get(FINISHED_ROOM_HEADER) !== "2";
}
/**
 * A room poll may name the revision and branch it already holds as
 * `<revision>.<branch>`. A standalone room that still matches answers with a
 * small `unchanged` reply. No header, a stale one or a malformed one gets the
 * full snapshot, byte for byte what older builds receive.
 */
export const KNOWN_ROOM_HEADER = "X-AfterYou-Known-Room";
export function knownRoom(request: Request): KnownRoom | undefined {
  const match = /^(0|[1-9][0-9]{0,14})\.(0|[1-9][0-9]?)$/.exec(request.headers.get(KNOWN_ROOM_HEADER) ?? "");
  return match ? { revision: Number(match[1]), branch: Number(match[2]) } : undefined;
}
/**
 * Sent with X-AfterYou-Known-Room by a client that reads the redo state from its poll instead of
 * a separate GET /redo. Its capabilities then say poll_redo_version 1, and both poll replies end
 * with `redo`. Without it every byte is as before.
 */
export const POLL_REDO_HEADER = "X-AfterYou-Poll-Redo";
function pollRedo(request: Request): boolean { return request.headers.get(POLL_REDO_HEADER) === "1"; }
function roomLevel(request: Request): number { return request.headers.get("X-AfterYou-Room-Level") === "2" ? 2 : 1; }
/** 0.5.x clients send at most 8; later clients may list more rules numbers. */
export const MAX_JOIN_VERSIONS = 16;
function requireEnabled(env: Env): void { if (!flags.v2Rooms(env)) throw new ApiError(503, "v2_mutations_disabled"); }
async function reauthorize(request: Request, playerId: string, env: Env): Promise<void> {
  // Provider I/O yields; recovery/deletion must revoke the old device before a new mutation.
  if (!await env.PLAYERS.getByName(playerId).authorize(await bearerDigest(request))) throw new ApiError(401, "identity_unavailable");
}

/** Called only after the shared Player authentication/rate limiter succeeds. */
export async function routeV2(request: Request, path: string, playerId: string, env: Env): Promise<Response> {
  const player = env.PLAYERS.getByName(playerId);
  if (path === "/v2/capabilities" && request.method === "GET") return json({ api_version: 2,
    mutations_enabled: flags.v2Rooms(env), recording_version: 2, simulation_version: 2,
    photo_uploads_enabled: flags.v2Rooms(env) && flags.relayPhotos(env),
    preset_reactions_enabled: flags.v2Rooms(env) && flags.presetReactions(env),
    photo_delivery_enabled: flags.photoDelivery(env),
    replay_transfer_version: flags.replayTransfer(env) ? 1 : 0,
    ...(flags.finishedRoomLeave(env) ? { room_leave_version: 1 } : {}),
    ...(campaignProductionEnabled() ? { campaign_control_version: 2, campaign_redo_version: 1 } : {}),
    campaign_creation_enabled: flags.v2Rooms(env) && flags.campaignCreation(env) && advertisedCampaigns(env).length > 0,
    campaign_mutations_enabled: campaignProductionEnabled() && flags.v2Rooms(env) && flags.campaignMutations(env),
    campaign_definitions: advertisedCampaigns(env),
    chapters: advertisedChapters(env, roomLevel(request)),
    ...(roomLevel(request) >= 2 ? { room_level: 2, max_join_versions: MAX_JOIN_VERSIONS, max_stages: MAX_ROOM_STAGES } : {}),
    // Only clients that keep attempts ask; everyone else gets the same bytes as before.
    ...(request.headers.get(HISTORY_HEADER) === "1" ? { history_version: 1, history_offload_enabled: flags.historyOffload(env) } : {}),
    ...(pollRedo(request) ? { poll_redo_version: 1 } : {}),
    validation: "structural_client_replay_required" });
  if (path === "/v2/campaigns" || path.startsWith("/v2/campaigns/")) return routeCampaign(request, path, playerId, env);
  if (path === "/v2/rooms" && request.method === "GET") {
    const rooms: RoomLobbyV2[] = [], blocked = partnerBlocks(env, playerId);
    for (const link of await player.listRooms()) {
      if (roomLinkVersion(link) !== 2) continue;
      const snapshot = await env.ROOMS_V2.getByName(link.room_id).lobbySnapshot(playerId);
      if (snapshot.ok) { if (!await blocked(snapshot.value.host_id, snapshot.value.guest_id)) rooms.push(snapshot.value); }
      else if (snapshot.status === 404) await player.removeRoom(link.room_id, 2);
      else unwrap(snapshot);
    }
    return json({ rooms });
  }
  if (path === "/v2/rooms" && request.method === "POST") {
    requireEnabled(env);
    const input = object(await boundedJson(request, 4096)); exact(input, ["idempotency_key", "level_id", "level_version", "definition_hash", ...(input.simulation_version === undefined ? [] : ["simulation_version"])]);
    const selected = chapter(input);
    if (input.simulation_version !== undefined && (!Number.isInteger(input.simulation_version) || input.simulation_version === selected.simulation_version || !(selected.supported_simulation_versions ?? []).includes(input.simulation_version as number))) throw new ApiError(422, "unsupported_simulation_version");
    if (!creatable(selected, env)) throw new ApiError(503, "chapter_creation_disabled");
    const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
    if (selected.premium) {
      // A retained intent is already admitted. A lost creation response must not
      // require another purchase check or lose its original invite/room link.
      const previous = unwrap(await player.chapterCreation(key, selected.key, input.simulation_version as number | undefined));
      if (!previous) { await requireHostAccess(playerId, env); await reauthorize(request, playerId, env); }
    }
    const invite_code = newInvite();
    const proposed: RoomLink = { room_id: await inviteRoomId(invite_code, 2), invite_code, host: true, api_version: 2 };
    const intent = unwrap(await reserveWithinRoomLimit(env, playerId, settled => player.reserveChapterRoom(key, proposed, selected.key, input.simulation_version as number | undefined, settled)));
    const link = intent.link;
    return json(unwrap(await env.ROOMS_V2.getByName(link.room_id).initialize(link.room_id, playerId, link.invite_code, intent.chapter, intent.simulation_version)));
  }
  if (path === "/v2/rooms/join" && request.method === "POST") {
    requireEnabled(env);
    const input = object(await boundedJson(request, 4096)); exact(input, ["invite_code", ...(input.supported_simulation_versions === undefined ? [] : ["supported_simulation_versions"])]);
    const versions = input.supported_simulation_versions;
    if (versions !== undefined && (!Array.isArray(versions) || !versions.length || versions.length > MAX_JOIN_VERSIONS || versions.some(version => !Number.isInteger(version) || version < 1) || new Set(versions).size !== versions.length)) throw new ApiError(422, "unsupported_simulation_version");
    const code = parseInvite(input.invite_code);
    const roomId = await inviteRoomId(code, 2), room = env.ROOMS_V2.getByName(roomId);
    const alreadyLinked = (await player.listRooms()).some(link => roomLinkVersion(link) === 2 && link.room_id === roomId);
    unwrap(await reserveWithinRoomLimit(env, playerId, settled => player.addRoom({ room_id: roomId, invite_code: "", host: false, api_version: 2 }, settled)));
    const joined = await room.join(playerId, code, versions as number[] | undefined);
    if (!joined.ok) { if (!alreadyLinked) await player.removeRoom(roomId, 2); return json(unwrap(joined)); }
    // A deletion that ran between link reservation and joining must not leave a
    // deleted identity newly attached to someone else's room.
    if (!await player.authorize(await bearerDigest(request))) {
      await room.eraseForPlayer(playerId); throw new ApiError(401, "identity_unavailable");
    }
    return json(joined.value);
  }
  const transferMatch = path.match(/^\/v2\/rooms\/([a-zA-Z0-9_-]{22})\/replay-transfer(?:\/(manifest|ack|restore|operations)(?:\/([a-zA-Z0-9_-]{16,80}))?)?$/);
  if (transferMatch) {
    const [, roomId, action, key] = transferMatch, target = env.ROOMS_V2.getByName(roomId);
    // Standalone only. Never promote a Story room through an ordinary route.
    if (await campaignRequestContext(request, roomId) !== undefined) throw new ApiError(409, "replay_transfer_standalone_only");
    await requireInteraction(env, playerId, "relay", roomId);
    if (request.method === "GET" && !key && (!action || action === "manifest")) return json(unwrap(await target.replayTransfer(playerId, !action,
      flags.replayTransfer(env))));
    if (request.method === "GET" && action === "operations" && key) return json(unwrap(await target.replayTransferOperation(playerId, text(key, IDEMPOTENCY_PATTERN))));
    if (request.method === "POST" && !key && (action === "ack" || action === "restore")) {
      if (action === "ack" && !flags.replayTransfer(env)) throw new ApiError(503, "replay_transfer_disabled");
      if (!(await env.PHOTO_ACK_LIMITER.limit({ key: "replay:" + playerId + ":" + roomId })).success) throw new ApiError(429, "replay_transfer_rate_limited");
      const input = await boundedJson(request, action === "restore" ? MAX_REPLAY_ARCHIVE_BYTES + 4096 : 4096);
      await reauthorize(request, playerId, env);
      if (action === "ack") return json(unwrap(await target.acknowledgeReplayTransfer(playerId, input)));
      return json(unwrap(await target.restoreReplayTransfer(playerId, input)));
    }
    throw new ApiError(405, "method_not_allowed");
  }
  const historyMatch = path.match(/^\/v2\/rooms\/([a-zA-Z0-9_-]{22})\/history(?:\/([0-9]{1,2})(?:\/(ack|want))?)?$/);
  if (historyMatch) {
    const [, roomId, item, action] = historyMatch, target = env.ROOMS_V2.getByName(roomId), support = historySupport(request, env);
    if (await campaignRequestContext(request, roomId) !== undefined) throw new ApiError(409, "history_standalone_only");
    await requireInteraction(env, playerId, "relay", roomId);
    if (request.method === "GET" && item === undefined) return json(unwrap(await target.history(playerId, support)));
    const position = item === undefined ? -1 : parsePosition(item);
    if (request.method === "GET" && !action && position >= 0) return bytes(unwrap(await target.historyAttempt(playerId, position, support)));
    if (request.method !== "POST" || position < 0) throw new ApiError(405, "method_not_allowed");
    // Offload needs the flag; asking for an attempt and sending one back never do, so nothing becomes unrecoverable.
    if (action === "ack" && !flags.historyOffload(env)) throw new ApiError(503, "history_offload_disabled");
    if (!(await env.PHOTO_ACK_LIMITER.limit({ key: "history:" + playerId + ":" + roomId })).success) throw new ApiError(429, "history_rate_limited");
    if (!action) {
      const body = await boundedBytes(request, MAX_ATTEMPT_BYTES + 1);
      await reauthorize(request, playerId, env);
      return json(unwrap(await target.uploadHistory(playerId, position, body, support)));
    }
    const input = await boundedJson(request, 4096);
    await reauthorize(request, playerId, env);
    return json(unwrap(action === "ack" ? await target.acknowledgeHistory(playerId, position, input, support) : await target.wantHistory(playerId, position, input, support)));
  }
  const deliveryMatch = path.match(/^\/v2\/rooms\/([a-zA-Z0-9_-]{22})\/photos\/(t(?:[0-9]|[12][0-9]|3[01])-[0-7]-[ab])\/(delivery|ack)$/);
  if (deliveryMatch) {
    const [, roomId, turnId, action] = deliveryMatch, target = env.ROOMS_V2.getByName(roomId);
    await stageWithin(target, turnId, "not_found", 404);
    const context = await campaignRequestContext(request, roomId);
    await requireInteraction(env, playerId, "relay", roomId, context);
    if (action === "delivery" && request.method === "GET") return json(unwrap(await target.photoDelivery(playerId, turnId, context)));
    if (action === "ack" && request.method === "POST") {
      if (!flags.photoDelivery(env)) throw new ApiError(503, "photo_delivery_disabled");
      if (!(await env.PHOTO_ACK_LIMITER.limit({ key: playerId + ":" + roomId })).success) throw new ApiError(429, "photo_ack_rate_limited");
      return json(unwrap(await target.acknowledgePhoto(playerId, turnId, await boundedJson(request, 4096), context)));
    }
    throw new ApiError(405, "method_not_allowed");
  }
  const match = path.match(/^\/v2\/rooms\/([a-zA-Z0-9_-]{22})(?:\/(turns|fork|redo|collection|operations|pairs|photos|photo-operations|reactions|reaction-operations|leave)(?:\/([a-zA-Z0-9_-]{1,80}))?)?$/);
  if (!match) throw new ApiError(404, "not_found");
  const [, id, operation, item] = match, room = env.ROOMS_V2.getByName(id);
  // Only the caller's own standalone link; Story rooms are version 3 links and are never removed here.
  if (operation === "leave") {
    if (item || request.method !== "POST") throw new ApiError(405, "method_not_allowed");
    return json(await leaveRoom(request, playerId, env, 2, id));
  }
  const context = await campaignRequestContext(request, id);
  // DELETE photo bypasses the interaction gate so owners can remove media.
  // It must still negotiate before inspecting recording/photo authority.
  if (request.method === "DELETE") unwrap(await room.campaignRoomNegotiation(context !== undefined));
  if (request.method !== "DELETE") await requireInteraction(env, playerId, "relay", id, context);
  if (operation === "redo" && !item) {
    if (request.method === "GET") return json(unwrap(await room.redo(playerId, undefined, await bearerDigest(request))));
    if (request.method === "POST") { requireEnabled(env); return json(unwrap(await room.redo(playerId, await boundedJson(request, 4096), await bearerDigest(request)))); }
    throw new ApiError(405, "method_not_allowed");
  }
  if (!operation && request.method === "GET") {
    const known = context === undefined ? knownRoom(request) : undefined;
    const snapshot: Outcome<PolledRoomV2> = known !== undefined ? await room.snapshotIfChanged(playerId, known, historySupport(request, env), pollRedo(request))
      : await room.snapshot(playerId, context, context === undefined ? historySupport(request, env) : undefined);
    if (!snapshot.ok && snapshot.code === "replay_transferred" && legacyTransferredUnblock(request, env, context)) throw new ApiError(409, "campaign_client_required");
    return json(unwrap(snapshot));
  }
  if (!operation && request.method === "DELETE") {
    await requireInPlay(request, () => room.memberRoomState(playerId));
    const deleted = unwrap(await room.eraseForPlayer(playerId)); await player.removeRoom(id, 2); return json(deleted);
  }
  if (operation === "operations" && item && request.method === "GET") return json(unwrap(await room.operation(playerId, text(item, IDEMPOTENCY_PATTERN), context)));
  if (operation === "pairs" && item && request.method === "GET") { const pairId = text(item, /^p\d{1,2}-[0-7]$/); await stageWithin(room, pairId, "invalid_field"); return json(unwrap(await room.pairRecording(playerId, pairId, context))); }
  if (operation === "collection" && !item && request.method === "GET") return json(unwrap(await room.collection(playerId, context)));
  if (operation === "photo-operations" && item && request.method === "GET") return json(unwrap(await room.photoOperation(playerId, text(item, IDEMPOTENCY_PATTERN), context)));
  if (operation === "reaction-operations" && item && request.method === "GET") return json(unwrap(await room.reactionOperation(playerId, text(item, IDEMPOTENCY_PATTERN), context)));
  if (operation === "reactions" && item) {
    const pairId = text(item, REACTION_PAIR_PATTERN, "invalid_reaction_pair"); await stageWithin(room, pairId, "invalid_reaction_pair");
    if (request.method === "GET") return json(unwrap(await room.reactions(playerId, pairId, context)));
    if (request.method === "POST") {
      requireEnabled(env);
      if (!flags.presetReactions(env)) throw new ApiError(503, "preset_reactions_disabled");
      return json(unwrap(await room.react(playerId, pairId, await boundedJson(request, 4096), context)));
    }
  }
  if (operation === "photos" && item) {
    const turnId = text(item, PHOTO_TURN_PATTERN, "invalid_photo_turn"); await stageWithin(room, turnId, "invalid_photo_turn");
    if (request.method === "GET") return json(unwrap(await room.photo(playerId, turnId, context)));
    if (request.method === "POST" || request.method === "DELETE") {
      // Removing a photo remains possible while new gameplay/uploads are paused.
      if (request.method === "POST") {
        requireEnabled(env);
        if (!flags.relayPhotos(env)) throw new ApiError(503, "photo_uploads_disabled");
        await requirePhotoTerms(env, playerId);
      }
      const input = await boundedJson(request, request.method === "DELETE" ? 4096 : 224 * 1024);
      return json(unwrap(await room.updatePhoto(playerId, turnId, input, request.method === "DELETE", context)));
    }
  }
  if (request.method !== "POST" || item || (operation !== "turns" && operation !== "fork")) throw new ApiError(405, "method_not_allowed");
  requireEnabled(env);
  // A receiver turn of a longer chapter may exceed the published body bound; only its own room may raise it.
  let bodyLimit = MAX_V2_BODY_BYTES;
  if (operation === "turns" && Number(request.headers.get("content-length")) > bodyLimit) {
    try { const probe = await room.snapshot(playerId, context); if (probe.ok) bodyLimit = chapter(probe.value).limits?.turn_body_bytes ?? bodyLimit; } catch { /* keep the published bound */ }
  }
  const input = await boundedJson(request, operation === "fork" ? 4096 : bodyLimit);
  if (operation === "fork" && object(input).redo_request_id !== undefined) await reauthorize(request, playerId, env);
  const snapshot = unwrap(await room.snapshot(playerId, context, context === undefined ? historySupport(request, env) : undefined));
  const storyGuard = context ? await room.campaignWriteAvailability() : null;
  if (chapter(snapshot).premium || storyGuard) {
    boundedTurnValue(input, operation === "turns" ? chapter(snapshot).limits : undefined);
    const body = object(input);
    exact(body, operation === "fork" ? ["base_revision", "idempotency_key", "branch", "stage_index", ...(body.redo_request_id === undefined ? [] : ["redo_request_id"])] :
      ["base_revision", "idempotency_key", "branch", "recording", ...(object(body.recording).role === "b" ? ["checkpoint"] : [])]);
    const key = text(body.idempotency_key, IDEMPOTENCY_PATTERN), previous = await room.operation(playerId, key, context);
    if (previous.ok) {
      if (previous.value.receipt.request_hash !== await digest(canonicalJson({ operation, ...body }))) throw new ApiError(409, "idempotency_key_reused");
      // Hashing may yield after the first receipt projection. Campaign access
      // must still be current at the final read, including original device.
      return json(context ? unwrap(await room.operation(playerId, key, context)) : previous.value);
    }
    if (previous.code !== "operation_not_found") unwrap(previous);
    if (storyGuard) unwrap(storyGuard);
    // Access belongs to the room's host even when the guest is taking this turn.
    await requireRoomHostAccess(room, snapshot.host_id, env);
    await reauthorize(request, playerId, env);
  }
  return json(unwrap(operation === "turns" ? await room.commit(playerId, input, context) : await room.fork(playerId, input, context, await bearerDigest(request))));
}
