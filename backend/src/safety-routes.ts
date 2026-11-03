import { ApiError, IDEMPOTENCY_PATTERN, ID_PATTERN, boundedJson, canonicalJson, digest, object, text, unwrap } from "./protocol";
import { bearerDigest } from "./http";
import { LEGACY_STAGE_COUNT } from "./v2/chapter-types";
import { STAGE_TURN_PATTERN, roomStages } from "./v2/room-stage";
import { PUBLIC_DUELS_HEADER, TERMS_VERSION, termsVersionFor } from "./public-policy";
import { flags } from "./flags";
import { blockPlayer, countReport, duelBlocks, leaveForBlock, noteRulesAccepted, publicDuelsOn, unblockHandle } from "./duels/public-routes";
import { interactionBlocked, parseReport, type SafetyReport } from "./safety";
import { campaignRequestContext, type CampaignRoomContext } from "./v2/campaign-room-access";
const exact = (value: Record<string, unknown>, keys: string[]) => { if (Object.keys(value).length !== keys.length || Object.keys(value).some(key => !keys.includes(key))) throw new ApiError(400, "invalid_safety_request"); };
export async function safetyMembers(env: Env, owner: string, family: string, room: string, context?: CampaignRoomContext): Promise<{ host_id: string; guest_id: string | null; public_duel?: true }> {
  text(room, ID_PATTERN); if (!["legacy", "relay"].includes(family)) throw new ApiError(400, "invalid_safety_request");
  return unwrap(family === "legacy" ? await env.ROOMS.getByName(room).safetyMembers(owner) : await env.ROOMS_V2.getByName(room).safetyMembers(owner, context));
}
export async function requireInteraction(env: Env, owner: string, family: string, room: string, context?: CampaignRoomContext, safetyToken?: string): Promise<void> {
  // A Relay room checks its own pair, and with the requester's safety token remembers while they are not blocked.
  if (family === "relay") { unwrap(await env.ROOMS_V2.getByName(text(room, ID_PATTERN)).interactionAllowed(owner, context, safetyToken)); return; }
  const members = await safetyMembers(env, owner, family, room, context);
  if (await interactionBlocked(env, members.host_id, members.guest_id)) throw new ApiError(403, "player_blocked");
}
export async function requirePhotoTerms(env: Env, owner: string): Promise<void> {
  if (!(await env.SAFETY_PROFILES.getByName(owner).terms(owner)).accepted) throw new ApiError(403, "terms_acceptance_required");
}
/** The stage count a reported photo's turn id is checked against: its relay room's own chapter. */
async function reportStages(env: Env, input: unknown): Promise<number> {
  const v = input !== null && typeof input === "object" && !Array.isArray(input) ? input as Record<string, unknown> : {};
  const photo = v.photo !== null && typeof v.photo === "object" && !Array.isArray(v.photo) ? v.photo as Record<string, unknown> : {};
  if (v.room_family !== "relay" || typeof v.room_id !== "string" || !ID_PATTERN.test(v.room_id) || typeof photo.turn_id !== "string" || !STAGE_TURN_PATTERN.test(photo.turn_id)) return LEGACY_STAGE_COUNT;
  const roomId = v.room_id;
  return roomStages(() => env.ROOMS_V2.getByName(roomId), photo.turn_id);
}
/**
 * POST /v1/safety/blocks/<id> with {schema_version: 1, request_id}: blocks a player on the caller's Friends list (a friend,
 * or a request either way) by that link, with no shared room; a room partner is blocked through the room as before.
 * The link then goes from both lists, so a blocked request never keeps a slot. Same answer as a room block.
 */
async function blockFriend(env: Env, owner: string, deviceHash: string, peer: string, raw: unknown) {
  const input = object(raw); exact(input, ["schema_version", "request_id"]);
  if (input.schema_version !== 1) throw new ApiError(400, "invalid_safety_request");
  const requestId = text(input.request_id, ID_PATTERN), player = env.PLAYERS.getByName(owner);
  const edge = await player.friendEdge(owner, peer);
  if (!edge || edge.link.request_id !== requestId) throw new ApiError(404, "friend_unavailable");
  const blocked = unwrap(await env.SAFETY_PROFILES.getByName(owner).setBlock(owner, deviceHash, peer, true));
  unwrap(await player.friendForget(owner, peer, requestId, deviceHash));
  await env.PLAYERS.getByName(peer).friendForget(peer, owner, requestId).catch(() => undefined);
  return blocked;
}
export async function routeSafety(request: Request, path: string, owner: string, env: Env): Promise<unknown> {
  const profile = env.SAFETY_PROFILES.getByName(owner), inbox = env.SAFETY_INBOX.getByName("moderation-v1");
  const deviceHash = await bearerDigest(request);
  if (path === "/v1/safety/config" && request.method === "GET") return { schema_version: 1, enforced: true, terms_version: termsVersionFor(request, env), privacy_path: "/privacy", deletion_path: "/account-deletion", rules_path: "/community-rules" };
  if (path === "/v1/safety/terms") {
    if (request.method === "GET") return profile.terms(owner, termsVersionFor(request, env));
    if (request.method === "POST") {
      const input = object(await boundedJson(request, 1024)); exact(input, ["schema_version", "terms_version"]);
      if (input.schema_version !== 1 || typeof input.terms_version !== "string") throw new ApiError(400, "invalid_safety_request");
      const current = termsVersionFor(request, env);
      const accepted = unwrap(await profile.accept(owner, deviceHash, input.terms_version, current));
      // The public duel rules: the Member row keeps a copy for the lobby (duels/public-routes.ts), every time, so a lost write heals.
      if (current !== TERMS_VERSION) await noteRulesAccepted(env, owner, current, Date.now());
      return accepted;
    }
  }
  if (path === "/v1/safety/blocks" && request.method === "GET") {
    const list = await profile.blocks(owner);
    // A stranger blocked from a public duel never shows by id, flag on or off (duels/public-routes.ts); a phone that knows
    // public duels gets them by handle and label in the extra key, which an older phone (wanting exactly these keys) never sees.
    if (!flags.leaderboards(env)) return list;
    const strangers = await duelBlocks(env, owner);
    const plain = { ...list, blocked_players: list.blocked_players.filter(id => !strangers.ids.has(id)) };
    return publicDuelsOn(env) && request.headers.get(PUBLIC_DUELS_HEADER) === "1" ? { ...plain, duel_blocks: strangers.shown } : plain;
  }
  const duelHandle = path.match(/^\/v1\/safety\/blocks\/duel\/([a-f0-9]{22})$/);
  if (duelHandle && request.method === "DELETE") return unblockHandle(env, request, owner, duelHandle[1]);
  const blockId = path.match(/^\/v1\/safety\/blocks\/([A-Za-z0-9_-]{22})$/);
  if (blockId && request.method === "DELETE") return unwrap(await profile.setBlock(owner, deviceHash, blockId[1], false));
  if (blockId && request.method === "POST") return blockFriend(env, owner, deviceHash, blockId[1], await boundedJson(request, 1024));
  if (path === "/v1/safety/block" && request.method === "POST") {
    const input = object(await boundedJson(request, 2048)); exact(input, ["schema_version", "room_family", "room_id"]);
    if (input.schema_version !== 1 || typeof input.room_family !== "string" || typeof input.room_id !== "string") throw new ApiError(400, "invalid_safety_request");
    const context = input.room_family === "relay" ? await campaignRequestContext(request, input.room_id, deviceHash) : undefined;
    const members = await safetyMembers(env, owner, input.room_family, input.room_id, context);
    const peer = members.host_id === owner ? members.guest_id : members.host_id;
    if (!peer) throw new ApiError(409, "room_partner_required");
    // Recheck room publication after the first membership lookup yields.
    if (context) await safetyMembers(env, owner, input.room_family, input.room_id, context);
    // A public duel room's stranger: blocked by handle, so the reply and the block list never carry their id.
    if (members.public_duel) {
      const handle = await blockPlayer(env, owner, deviceHash, peer, null, Date.now());
      // Their partner, blocked from the room: the player leaves the duel, costing neither of them the held extra (PLAN 7).
      const link = await env.ROOMS_V2.getByName(input.room_id).duelLinkOf();
      if (link) await leaveForBlock(env, owner, link.board, link.duel_id).catch(() => false);
      return { schema_version: 1, blocked: true, player_id: handle };
    }
    return unwrap(await profile.setBlock(owner, deviceHash, peer, true));
  }
  const reportKey = path.match(/^\/v1\/safety\/reports\/([A-Za-z0-9_-]{16,80})$/);
  if (reportKey && request.method === "GET") return unwrap(await inbox.reportReceipt(owner, text(reportKey[1], IDEMPOTENCY_PATTERN)));
  if (path === "/v1/safety/report" && request.method === "POST") {
    const input = await boundedJson(request, 4096);
    const body = parseReport(input, await reportStages(env, input));
    const context = body.room_family === "relay" ? await campaignRequestContext(request, body.room_id, deviceHash) : undefined;
    // A retained receipt can survive room deletion, but known campaign bodies
    // still negotiate the protocol before the account-owned receipt returns.
    if (body.room_family === "relay" && !context) unwrap(await env.ROOMS_V2.getByName(body.room_id).campaignRoomNegotiation(false));
    const hash = await digest(canonicalJson({ operation: "safety_report", reporter_id: owner, ...body }));
    // A receipt stays reconcilable even if the reported image/room later changes.
    const previous = await inbox.reportReceipt(owner, body.idempotency_key);
    if (previous.ok) {
      if (previous.value.request_hash !== hash) throw new ApiError(409, "idempotency_key_reused");
      if (context && !await env.PLAYERS.getByName(owner).authorize(deviceHash)) throw new ApiError(401, "invalid_auth");
      return previous.value;
    }
    const members = await safetyMembers(env, owner, body.room_family, body.room_id, context);
    const target = members.host_id === owner ? members.guest_id : members.host_id;
    if (!target) throw new ApiError(409, "room_partner_required");
    if (body.photo) {
      const delivery = unwrap(await env.ROOMS_V2.getByName(body.room_id).photoDelivery(owner, body.photo.turn_id, context));
      if (!delivery.photo || delivery.photo.owner_player_id !== target || delivery.photo.photo_revision !== body.photo.photo_revision || delivery.photo.sha256 !== body.photo.sha256) throw new ApiError(409, "reported_photo_changed");
    }
    const report: SafetyReport = { ...body, reporter_id: owner, target_id: target, request_hash: hash, report_id: await digest(owner + ":" + body.idempotency_key), created_at: Date.now(), resolved_at: null };
    if (!await env.PLAYERS.getByName(owner).authorize(deviceHash)) throw new ApiError(401, "invalid_auth");
    if (context) await safetyMembers(env, owner, body.room_family, body.room_id, context);
    const receipt = unwrap(await inbox.submit(report, deviceHash));
    // A report on a public duel room's stranger counts toward their pause, as a report from the duel page does.
    if (members.public_duel) await countReport(env, owner, target, report.created_at);
    return receipt;
  }
  throw new ApiError(404, "not_found");
}
