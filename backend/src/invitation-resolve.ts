import { ApiError, boundedJson, exactKeys, inviteRoomId, object, parseInvite } from "./protocol";

/** Authenticated, read-only classification; the normal join route stays authoritative. */
export async function resolveInvitation(request: Request, env: Env): Promise<{ schema_version: 1; family: "legacy" | "relay"; api_version: 1 | 2 }> {
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = object(await boundedJson(request, 4096)); exactKeys(input, ["invite_code"]);
  const code = parseInvite(input.invite_code);
  const [legacyId, relayId] = await Promise.all([inviteRoomId(code, 1), inviteRoomId(code, 2)]);
  const [legacy, relay] = await Promise.all([
    env.ROOMS.getByName(legacyId).resolvesInvitation(code),
    env.ROOMS_V2.getByName(relayId).resolvesInvitation(code)
  ]);
  if (legacy && relay) throw new ApiError(409, "ambiguous_invite");
  if (!legacy && !relay) throw new ApiError(404, "invite_not_found");
  return legacy ? { schema_version: 1, family: "legacy", api_version: 1 } : { schema_version: 1, family: "relay", api_version: 2 };
}
