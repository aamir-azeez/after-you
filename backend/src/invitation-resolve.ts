import { ApiError, boundedJson, digest, exactKeys, object, text } from "./protocol";

/** Authenticated, read-only classification; the normal join route stays authoritative. */
export async function resolveInvitation(request: Request, env: Env): Promise<{ schema_version: 1; family: "legacy" | "relay"; api_version: 1 | 2 }> {
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = object(await boundedJson(request, 4096)); exactKeys(input, ["invite_code"]);
  if (typeof input.invite_code !== "string" || input.invite_code.length > 40) throw new ApiError(400, "invalid_invite");
  const code = text(input.invite_code.replace(/[\s-]/g, "").toUpperCase(), /^[A-F0-9]{20}$/, "invalid_invite");
  const [legacyId, relayId] = await Promise.all([digest(code), digest("v2:" + code)]);
  const [legacy, relay] = await Promise.all([
    env.ROOMS.getByName(legacyId.slice(0, 22)).resolvesInvitation(code),
    env.ROOMS_V2.getByName(relayId.slice(0, 22)).resolvesInvitation(code)
  ]);
  if (legacy && relay) throw new ApiError(409, "ambiguous_invite");
  if (!legacy && !relay) throw new ApiError(404, "invite_not_found");
  return legacy ? { schema_version: 1, family: "legacy", api_version: 1 } : { schema_version: 1, family: "relay", api_version: 2 };
}
