import { ApiError, ID_PATTERN, boundedJson, digest, object, randomToken, text, type Outcome } from "./protocol";
import { FRIEND_REFRESH_SECONDS, sameFriendLink, validSharedFriendRoom, type FriendEdge, type FriendLink, type SharedFriendRoom } from "./friends";
import { interactionBlocked } from "./safety";
import { presenceEnabled } from "./presence";

const unwrap = <T>(v: Outcome<T>): T => { if (!v.ok) throw new ApiError(v.status, v.code); return v.value; };
const exact = (v: Record<string, unknown>, keys: string[]) => {
  if (Object.keys(v).length !== keys.length || keys.some(k => !Object.hasOwn(v, k)) || v.schema_version !== 1) throw new ApiError(400, "invalid_friend_request");
};
async function authorized(env: Env, owner: string, hash: string): Promise<void> {
  if (!await env.PLAYERS.getByName(owner).authorize(hash)) throw new ApiError(401, "invalid_auth");
}
async function allowed(env: Env, owner: string, peer: string): Promise<void> {
  if (owner === peer) throw new ApiError(400, "invalid_friend_request");
  if (await interactionBlocked(env, owner, peer)) throw new ApiError(403, "player_blocked");
}
const responseLink = (owner: string, link: FriendLink, accepted = link.accepted) => ({ schema_version: 1, player_id: link.player_id, request_id: link.request_id,
  status: accepted ? "accepted" : link.requested_by === owner ? "outgoing" : "incoming" });
async function pair(env: Env, owner: string, peer: string, requestId: string): Promise<[FriendEdge, FriendEdge]> {
  const [a, b] = await Promise.all([env.PLAYERS.getByName(owner).friendEdge(owner, peer), env.PLAYERS.getByName(peer).friendEdge(peer, owner)]);
  if (!a || !b || a.link.request_id !== requestId || !sameFriendLink(a.link, b.link, owner)) throw new ApiError(409, "friend_request_changed");
  return [a, b];
}
async function accept(env: Env, owner: string, hash: string, peer: string, requestId: string) {
  await allowed(env, owner, peer);
  const [a] = await pair(env, owner, peer, requestId);
  if (a.link.requested_by !== peer) throw new ApiError(409, "friend_request_changed");
  unwrap(await env.PLAYERS.getByName(owner).friendApprove(owner, hash, peer, requestId));
  await allowed(env, owner, peer); await authorized(env, owner, hash);
  const [approved] = await pair(env, owner, peer, requestId);
  if (!approved.link.accepted) throw new ApiError(409, "friend_request_changed");
  unwrap(await env.PLAYERS.getByName(peer).friendConfirm(peer, owner, requestId));
  const [current, other] = await pair(env, owner, peer, requestId);
  await allowed(env, owner, peer); await authorized(env, owner, hash);
  if (!current.link.accepted || !other.link.accepted) throw new ApiError(409, "friend_request_changed");
  return responseLink(owner, current.link);
}
/** Never reserves a slot. The normal join route performs the authoritative join. */
async function sharedInvite(env: Env, host: string, visitor: string, shared: SharedFriendRoom | null) {
  if (!shared) return null;
  const result = shared.api_version === 1 ? await env.ROOMS.getByName(shared.room_id).friendInvite(host, visitor) : await env.ROOMS_V2.getByName(shared.room_id).friendInvite(host, visitor);
  if (!result.ok) return null;
  return { api_version: shared.api_version, ...result.value };
}

/** Authenticated only. No public player lookup, room discovery, or additional presence lease. */
export async function routeFriends(request: Request, path: string, owner: string, env: Env): Promise<unknown> {
  const hash = await digest(request.headers.get("Authorization")!.slice(7)), player = env.PLAYERS.getByName(owner);
  if (path === "/v1/friends" && request.method === "GET") {
    const social = unwrap(await player.friendList(owner, hash));
    const friends = (await Promise.all(social.links.map(async link => {
      const other = await env.PLAYERS.getByName(link.player_id).friendEdge(link.player_id, owner);
      // A request can be between its two durable writes. Reads must not remove
      // one side while delivery is still in flight; pending links expire.
      if (!other || !sameFriendLink(link, other.link, owner)) {
        // An accepted edge could only exist after both proposal writes. Its
        // missing/replaced counterpart is a removal, not in-flight delivery.
        if (link.accepted) unwrap(await player.friendForget(owner, link.player_id, link.request_id, hash));
        return null;
      }
      const accepted = link.accepted && other.link.accepted;
      // Recorded turns can be joined while the host is away. Presence only
      // controls the online indicator; reciprocal consent and sharing grant access.
      const invite = accepted ? await sharedInvite(env, link.player_id, owner, other.shared_room) : null;
      const latest = await env.PLAYERS.getByName(link.player_id).friendEdge(link.player_id, owner);
      if (!latest || !sameFriendLink(link, latest.link, owner) || await interactionBlocked(env, owner, link.player_id)) return null;
      const stillAccepted = link.accepted && latest.link.accepted;
      const remaining = stillAccepted && presenceEnabled(env) ? Math.max(0, Math.min(90, Math.ceil((latest.presence_expires_at - Date.now()) / 1000))) : 0;
      const stillShared = invite !== null && latest.shared_room?.room_id === invite.room_id && latest.shared_room.api_version === invite.api_version;
      return { player_id: link.player_id, request_id: link.request_id, status: stillAccepted ? "accepted" : link.requested_by === owner ? "outgoing" : "incoming",
        online: remaining > 0, expires_after_seconds: remaining, join_available: stillAccepted && stillShared };
    }))).filter(x => x !== null);
    // One batched local recheck replaces twenty same-owner RPCs. It also
    // reauthorizes the device after all peer/room I/O and honors removals.
    const current = unwrap(await player.friendList(owner, hash, false));
    const visible = friends.filter(row => current.links.some(link => link.player_id === row.player_id && link.request_id === row.request_id));
    return { schema_version: 1, friend_code: owner, refresh_after_seconds: FRIEND_REFRESH_SECONDS, shared_room: current.shared_room, friends: visible };
  }
  if (path === "/v1/friends/request" && request.method === "POST") {
    const input = object(await boundedJson(request, 1024)); exact(input, ["schema_version", "friend_code"]);
    const peer = text(input.friend_code, ID_PATTERN, "invalid_friend_code"); await allowed(env, owner, peer);
    // Reject nonexistent codes before reserving the caller's limited slots.
    if (!await env.PLAYERS.getByName(peer).safetyIdentityActive(peer)) throw new ApiError(404, "friend_unavailable");
    const [local, remote] = await Promise.all([player.friendEdge(owner, peer), env.PLAYERS.getByName(peer).friendEdge(peer, owner)]);
    // A lost second DELETE reply can leave an orphan. Repair only on an
    // explicit Add action, never on a list read between proposal/delivery.
    if (local && !remote && (local.link.accepted || local.link.requested_by === peer)) unwrap(await player.friendForget(owner, peer, local.link.request_id, hash));
    if (remote && !local && (remote.link.accepted || remote.link.requested_by === owner)) {
      await authorized(env, owner, hash);
      unwrap(await env.PLAYERS.getByName(peer).friendForget(peer, owner, remote.link.request_id));
    } else if (remote && !local && remote.link.requested_by === peer) {
      // Both people explicitly chose Add. Finish delivery of their retained
      // proposal and apply this person's consent through the usual handshake.
      await authorized(env, owner, hash);
      unwrap(await player.friendReceive(owner, peer, remote.link.request_id, remote.link.created_at));
      return accept(env, owner, hash, peer, remote.link.request_id);
    }
    const proposed = unwrap(await player.friendPropose(owner, hash, peer, randomToken(16)));
    if (proposed.requested_by === peer) return accept(env, owner, hash, peer, proposed.request_id);
    const received = await env.PLAYERS.getByName(peer).friendReceive(peer, owner, proposed.request_id, proposed.created_at);
    if (!received.ok) { await player.friendForget(owner, peer, proposed.request_id, hash); return unwrap(received); }
    try {
      const [current, other] = await pair(env, owner, peer, proposed.request_id);
      await allowed(env, owner, peer); await authorized(env, owner, hash);
      if (other.link.accepted && !current.link.accepted) unwrap(await player.friendConfirm(owner, peer, proposed.request_id));
      return responseLink(owner, { ...current.link, accepted: other.link.accepted && (current.link.accepted || current.link.requested_by === owner) });
    } catch (error) {
      // If removal/recovery/deletion won the race, do not leave an actionable
      // invitation behind. Exact-token cleanup cannot remove a newer request.
      if (error instanceof ApiError && ["invalid_auth", "player_blocked", "friend_request_changed"].includes(error.code)) {
        await env.PLAYERS.getByName(peer).friendForget(peer, owner, proposed.request_id);
        await player.friendForget(owner, peer, proposed.request_id);
      }
      throw error;
    }
  }
  if (path === "/v1/friends/accept" && request.method === "POST") {
    const input = object(await boundedJson(request, 1024)); exact(input, ["schema_version", "player_id", "request_id"]);
    return accept(env, owner, hash, text(input.player_id, ID_PATTERN), text(input.request_id, ID_PATTERN));
  }
  if (path === "/v1/friends/share" && request.method === "POST") {
    const input = object(await boundedJson(request, 1024)); exact(input, ["schema_version", "room"]);
    if (input.room !== null && !validSharedFriendRoom(input.room)) throw new ApiError(400, "invalid_friend_request");
    if (input.room !== null) {
      unwrap(input.room.api_version === 1 ? await env.ROOMS.getByName(input.room.room_id).friendInvite(owner, owner) : await env.ROOMS_V2.getByName(input.room.room_id).friendInvite(owner, owner));
    }
    return { schema_version: 1, ...unwrap(await player.friendShare(owner, hash, input.room)) };
  }
  const match = path.match(/^\/v1\/friends\/([A-Za-z0-9_-]{22})(\/join)?$/);
  if (match && (request.method === "DELETE" && !match[2] || request.method === "POST" && match[2])) {
    const input = object(await boundedJson(request, 1024)); exact(input, ["schema_version", "request_id"]);
    const peer = match[1], requestId = text(input.request_id, ID_PATTERN);
    if (request.method === "DELETE") {
      unwrap(await player.friendForget(owner, peer, requestId, hash));
      unwrap(await env.PLAYERS.getByName(peer).friendForget(peer, owner, requestId));
      return { schema_version: 1, removed: true };
    }
    await allowed(env, owner, peer);
    const [a, b] = await pair(env, owner, peer, requestId);
    if (!a.link.accepted || !b.link.accepted) throw new ApiError(409, "friend_not_joinable");
    const invite = await sharedInvite(env, peer, owner, b.shared_room);
    if (!invite) throw new ApiError(409, "friend_not_joinable");
    await allowed(env, owner, peer); await authorized(env, owner, hash);
    const [current, other] = await pair(env, owner, peer, requestId);
    if (!current.link.accepted || !other.link.accepted || other.shared_room?.room_id !== invite.room_id || other.shared_room.api_version !== invite.api_version) throw new ApiError(409, "friend_not_joinable");
    return { schema_version: 1, ...invite };
  }
  throw new ApiError(405, "method_not_allowed");
}
