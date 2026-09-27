import { ApiError, IDEMPOTENCY_PATTERN, ID_PATTERN, boundedJson, canonicalJson, digest, object, text, type Outcome } from "./protocol";
import { TERMS_VERSION } from "./public-policy";
import { interactionBlocked, parseReport, type SafetyReport } from "./safety";
import { campaignRequestContext, type CampaignRoomContext } from "./v2/campaign-room-access";
const unwrap = <T>(value: Outcome<T>): T => { if (!value.ok) throw new ApiError(value.status, value.code); return value.value; };
const exact = (value: Record<string, unknown>, keys: string[]) => { if (Object.keys(value).length !== keys.length || Object.keys(value).some(key => !keys.includes(key))) throw new ApiError(400, "invalid_safety_request"); };
export const safetyEnabled = (env: Env) => String(env.SAFETY_ENFORCEMENT_ENABLED) === "true";
export async function safetyMembers(env: Env, owner: string, family: string, room: string, context?: CampaignRoomContext) {
  text(room, ID_PATTERN); if (!["legacy", "relay"].includes(family)) throw new ApiError(400, "invalid_safety_request");
  return unwrap(family === "legacy" ? await env.ROOMS.getByName(room).safetyMembers(owner) : await env.ROOMS_V2.getByName(room).safetyMembers(owner, context));
}
export async function requireInteraction(env: Env, owner: string, family: string, room: string, context?: CampaignRoomContext): Promise<void> {
  const members = await safetyMembers(env, owner, family, room, context);
  if (await interactionBlocked(env, members.host_id, members.guest_id)) throw new ApiError(403, "player_blocked");
}
export async function requirePhotoTerms(env: Env, owner: string): Promise<void> {
  if (safetyEnabled(env) && !(await env.SAFETY_PROFILES.getByName(owner).terms(owner)).accepted) throw new ApiError(403, "terms_acceptance_required");
}
export async function routeSafety(request: Request, path: string, owner: string, env: Env): Promise<unknown> {
  const profile = env.SAFETY_PROFILES.getByName(owner), inbox = env.SAFETY_INBOX.getByName("moderation-v1");
  const deviceHash = await digest(request.headers.get("Authorization")!.slice(7));
  if (path === "/v1/safety/config" && request.method === "GET") return { schema_version: 1, enforced: safetyEnabled(env), terms_version: TERMS_VERSION, privacy_path: "/privacy", deletion_path: "/account-deletion", rules_path: "/community-rules" };
  if (path === "/v1/safety/terms") {
    if (request.method === "GET") return profile.terms(owner);
    if (request.method === "POST") {
      const input = object(await boundedJson(request, 1024)); exact(input, ["schema_version", "terms_version"]);
      if (input.schema_version !== 1 || typeof input.terms_version !== "string") throw new ApiError(400, "invalid_safety_request");
      return unwrap(await profile.accept(owner, deviceHash, input.terms_version));
    }
  }
  if (path === "/v1/safety/blocks" && request.method === "GET") return profile.blocks(owner);
  const blockId = path.match(/^\/v1\/safety\/blocks\/([A-Za-z0-9_-]{22})$/);
  if (blockId && request.method === "DELETE") return unwrap(await profile.setBlock(owner, deviceHash, blockId[1], false));
  if (path === "/v1/safety/block" && request.method === "POST") {
    const input = object(await boundedJson(request, 2048)); exact(input, ["schema_version", "room_family", "room_id"]);
    if (input.schema_version !== 1 || typeof input.room_family !== "string" || typeof input.room_id !== "string") throw new ApiError(400, "invalid_safety_request");
    const context = input.room_family === "relay" ? await campaignRequestContext(request, input.room_id, deviceHash) : undefined;
    const members = await safetyMembers(env, owner, input.room_family, input.room_id, context);
    const peer = members.host_id === owner ? members.guest_id : members.host_id;
    if (!peer) throw new ApiError(409, "room_partner_required");
    // Recheck room publication after the first membership lookup yields.
    if (context) await safetyMembers(env, owner, input.room_family, input.room_id, context);
    return unwrap(await profile.setBlock(owner, deviceHash, peer, true));
  }
  const reportKey = path.match(/^\/v1\/safety\/reports\/([A-Za-z0-9_-]{16,80})$/);
  if (reportKey && request.method === "GET") return unwrap(await inbox.reportReceipt(owner, text(reportKey[1], IDEMPOTENCY_PATTERN)));
  if (path === "/v1/safety/report" && request.method === "POST") {
    const body = parseReport(await boundedJson(request, 4096));
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
    return unwrap(await inbox.submit(report, deviceHash));
  }
  throw new ApiError(404, "not_found");
}
