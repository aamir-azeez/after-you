import { ApiError, HASH_PATTERN, SECRET_PATTERN, boundedJson, canonicalJson, digest, equalHash, object, text, type Outcome } from "./protocol";
const unwrap = <T>(value: Outcome<T>): T => { if (!value.ok) throw new ApiError(value.status, value.code); return value.value; };

/** Separate operator credential; never accepts a player credential or a caller target. */
export async function routeSafetyOperator(request: Request, path: string, env: Env): Promise<unknown> {
  const secret = (env as Env & { SAFETY_OPERATOR_TOKEN?: string }).SAFETY_OPERATOR_TOKEN;
  const authorization = request.headers.get("Authorization");
  if (!secret || !SECRET_PATTERN.test(secret) || !authorization?.startsWith("Bearer ") || !SECRET_PATTERN.test(authorization.slice(7)) || !equalHash(await digest(secret), await digest(authorization.slice(7)))) throw new ApiError(401, "invalid_operator_auth");
  const inbox = env.SAFETY_INBOX.getByName("moderation-v1");
  if (path === "/operator/safety/reports" && request.method === "GET") return { schema_version: 1, reports: await inbox.listReports() };
  const match = path.match(/^\/operator\/safety\/reports\/([a-f0-9]{64})\/(resolve|remove-photo|block)$/);
  if (!match) throw new ApiError(404, "not_found");
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = object(await boundedJson(request, 1024));
  const keys = match[2] === "remove-photo" ? ["schema_version", "photo_revision", "sha256"] : ["schema_version"];
  if (input.schema_version !== 1 || Object.keys(input).length !== keys.length || Object.keys(input).some(key => !keys.includes(key))) throw new ApiError(400, "invalid_safety_request");
  const report = unwrap(await inbox.getReport(text(match[1], HASH_PATTERN)));
  if (match[2] === "resolve") return unwrap(await inbox.resolveReport(report.report_id));
  if (match[2] === "block") return unwrap(await env.SAFETY_PROFILES.getByName(report.reporter_id).operatorBlock(report.reporter_id, report.target_id));
  if (!report.photo || report.room_family !== "relay" || input.photo_revision !== report.photo.photo_revision || input.sha256 !== report.photo.sha256) throw new ApiError(409, "reported_photo_changed");
  const room = env.ROOMS_V2.getByName(report.room_id), key = "moderation_" + report.report_id;
  // The immutable deletion receipt makes a lost response safe even if the owner
  // later shares a replacement. Never remove that newer photo on an old report.
  const previous = await room.photoOperation(report.target_id, key);
  if (!previous.ok) {
    const current = unwrap(await room.photoDelivery(report.reporter_id, report.photo.turn_id)).photo;
    if (!current || current.owner_player_id !== report.target_id || current.sha256 !== report.photo.sha256 || current.photo_revision !== report.photo.photo_revision) throw new ApiError(409, "reported_photo_changed");
    unwrap(await room.updatePhoto(report.target_id, report.photo.turn_id, { idempotency_key: key, recording_hash: current.recording_hash, expected_photo_revision: report.photo.photo_revision, expected_photo_hash: report.photo.sha256 }, true));
  } else {
    const receipt = previous.value.receipt;
    const expected = await digest(canonicalJson({ operation: "photo_delete", turn_id: report.photo.turn_id, idempotency_key: key, recording_hash: receipt.recording_hash, expected_photo_revision: report.photo.photo_revision, expected_photo_hash: report.photo.sha256 }));
    if (receipt.operation !== "photo_delete" || receipt.turn_id !== report.photo.turn_id || receipt.request_hash !== expected || receipt.photo_hash !== null) throw new ApiError(409, "invalid_moderation_receipt");
  }
  unwrap(await inbox.resolveReport(report.report_id)); return { schema_version: 1, removed: true };
}
