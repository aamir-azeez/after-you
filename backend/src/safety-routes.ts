import { ApiError, IDEMPOTENCY_PATTERN, ID_PATTERN, boundedJson, canonicalJson, digest, object, text, type Outcome } from "./protocol";
import { TERMS_VERSION } from "./public-policy";
import { interactionBlocked, parseReport, type SafetyReport } from "./safety";
const unwrap = <T>(value: Outcome<T>): T => { if (!value.ok) throw new ApiError(value.status, value.code); return value.value; };
const exact = (value: Record<string, unknown>, keys: string[]) => { if (Object.keys(value).length !== keys.length || Object.keys(value).some(key => !keys.includes(key))) throw new ApiError(400, "invalid_safety_request"); };
export const safetyEnabled = (env: Env) => String(env.SAFETY_ENFORCEMENT_ENABLED) === "true";
export async function safetyMembers(env: Env, owner: string, family: string, room: string) {
  text(room, ID_PATTERN); if (!["legacy", "relay"].includes(family)) throw new ApiError(400, "invalid_safety_request");
  return unwrap(family === "legacy" ? await env.ROOMS.getByName(room).safetyMembers(owner) : await env.ROOMS_V2.getByName(room).safetyMembers(owner));
}
export async function requireInteraction(env: Env, owner: string, family: string, room: string): Promise<void> {
  const members = await safetyMembers(env, owner, family, room);
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
    const members = await safetyMembers(env, owner, input.room_family, input.room_id);
    const peer = members.host_id === owner ? members.guest_id : members.host_id;
    if (!peer) throw new ApiError(409, "room_partner_required");
    return unwrap(await profile.setBlock(owner, deviceHash, peer, true));
  }
  const reportKey = path.match(/^\/v1\/safety\/reports\/([A-Za-z0-9_-]{16,80})$/);
  if (reportKey && request.method === "GET") return unwrap(await inbox.reportReceipt(owner, text(reportKey[1], IDEMPOTENCY_PATTERN)));
  if (path === "/v1/safety/report" && request.method === "POST") {
    const body = parseReport(await boundedJson(request, 4096));
    const hash = await digest(canonicalJson({ operation: "safety_report", reporter_id: owner, ...body }));
    // A receipt stays reconcilable even if the reported image/room later changes.
    const previous = await inbox.reportReceipt(owner, body.idempotency_key);
    if (previous.ok) { if (previous.value.request_hash !== hash) throw new ApiError(409, "idempotency_key_reused"); return previous.value; }
    const members = await safetyMembers(env, owner, body.room_family, body.room_id);
    const target = members.host_id === owner ? members.guest_id : members.host_id;
    if (!target) throw new ApiError(409, "room_partner_required");
    if (body.photo) {
      const delivery = unwrap(await env.ROOMS_V2.getByName(body.room_id).photoDelivery(owner, body.photo.turn_id));
      if (!delivery.photo || delivery.photo.owner_player_id !== target || delivery.photo.photo_revision !== body.photo.photo_revision || delivery.photo.sha256 !== body.photo.sha256) throw new ApiError(409, "reported_photo_changed");
    }
    const report: SafetyReport = { ...body, reporter_id: owner, target_id: target, request_hash: hash, report_id: await digest(owner + ":" + body.idempotency_key), created_at: Date.now(), resolved_at: null };
    if (!await env.PLAYERS.getByName(owner).authorize(deviceHash)) throw new ApiError(401, "invalid_auth");
    return unwrap(await inbox.submit(report, deviceHash));
  }
  throw new ApiError(404, "not_found");
}
