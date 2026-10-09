import { ApiError, ID_PATTERN, boundedJson, digest, object, text, type Outcome } from "./protocol";
import { interactionBlocked } from "./safety";
import { sameFriendLink, validSharedFriendRoom, type FriendEdge } from "./friends";
import { FRIEND_ROOM_EVENTS_ENABLED, type FriendRoomEvent } from "./friend-room-events";
import type { FriendPublication } from "./friend-room-event-storage";

const unwrap = <T>(value: Outcome<T>): T => { if (!value.ok) throw new ApiError(value.status, value.code); return value.value; };
const exact = (value: Record<string, unknown>, keys: string[]) => {
  if (Object.keys(value).length !== keys.length || keys.some(key => !Object.hasOwn(value, key)) || value.schema_version !== 1) throw new ApiError(400, "invalid_friend_notification");
};
async function relationship(env: Env, owner: string, host: string, requestId: string): Promise<[FriendEdge, FriendEdge]> {
  if (owner === host || !ID_PATTERN.test(host) || !ID_PATTERN.test(requestId)) throw new ApiError(400, "invalid_friend_notification");
  if (await interactionBlocked(env, owner, host)) throw new ApiError(403, "player_blocked");
  const [recipient, publisher] = await Promise.all([env.PLAYERS.getByName(owner).friendEdge(owner, host), env.PLAYERS.getByName(host).friendEdge(host, owner)]);
  if (!recipient || !publisher || !recipient.link.accepted || !publisher.link.accepted || recipient.link.request_id !== requestId || !sameFriendLink(recipient.link, publisher.link, owner)) throw new ApiError(409, "friend_request_changed");
  return [recipient, publisher];
}
function event(host: string, recipient: string, requestId: string, publication: FriendPublication): FriendRoomEvent {
  return { schema_version: 1, category: "room_available", event_id: `${host}_${publication.publication_epoch}`, host_id: host, recipient_id: recipient,
    request_id: requestId, publication_epoch: publication.publication_epoch, room: publication.room, published_at: publication.published_at };
}
async function roomAvailable(env: Env, host: string, recipient: string, publication: FriendPublication): Promise<boolean> {
  const result = publication.room.api_version === 1 ? await env.ROOMS.getByName(publication.room.room_id).friendInvite(host, recipient) : await env.ROOMS_V2.getByName(publication.room.room_id).friendInvite(host, recipient);
  return result.ok;
}
/** Best-effort cross-DO fanout after Player has committed its authoritative epoch. */
async function enqueueFor(env: Env, host: string, recipient: string, requestId: string, publication: FriendPublication): Promise<boolean> {
  try {
    const [current, subscription] = await Promise.all([relationship(env, recipient, host, requestId), env.PLAYERS.getByName(recipient).friendSubscription(recipient, host)]);
    const latest = await env.PLAYERS.getByName(host).friendPublication(host);
    if (!current || !subscription?.enabled || subscription.request_id !== requestId || latest?.publication_epoch !== publication.publication_epoch ||
      await interactionBlocked(env, host, recipient) || !await roomAvailable(env, host, recipient, publication)) return false;
    const queued = await env.FRIEND_ROOM_EVENTS.getByName(recipient).enqueue(event(host, recipient, requestId, publication));
    return queued.ok && queued.value.queued;
  } catch { return false; }
}
export async function publishSocialRoom(request: Request, owner: string, env: Env): Promise<unknown> {
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = object(await boundedJson(request, 1024)); exact(input, ["schema_version", "room", "publication_id"]);
  if (!validSharedFriendRoom(input.room)) throw new ApiError(400, "invalid_friend_publication");
  const publicationId = text(input.publication_id, /^[A-Za-z0-9_-]{22}$/, "invalid_friend_publication");
  const hash = await digest(request.headers.get("Authorization")!.slice(7));
  const host = env.PLAYERS.getByName(owner);
  const current = await host.friendList(owner, hash, false);
  if (!current.ok) throw new ApiError(current.status, current.code);
  const publication = unwrap(await host.publishFriendRoom(owner, hash, publicationId, input.room));
  let queued = 0;
  if (FRIEND_ROOM_EVENTS_ENABLED(env)) {
    const candidates = current.value.links.filter(link => link.accepted);
    const results = await Promise.all(candidates.map(async link => {
      const subscription = await env.PLAYERS.getByName(link.player_id).friendSubscription(link.player_id, owner);
      if (!subscription?.enabled || subscription.request_id !== link.request_id) {
        try { await env.FRIEND_ROOM_EVENTS.getByName(link.player_id).revoke(owner); } catch { /* eligibility rechecks cancel stale work */ }
        return false;
      }
      return enqueueFor(env, owner, link.player_id, link.request_id, publication);
    }));
    queued = results.filter(Boolean).length;
  }
  // Publication remains successful even when one recipient's independent DO is unavailable.
  return { schema_version: 1, publication_epoch: publication.publication_epoch, queued };
}
export async function socialInbox(owner: string, env: Env): Promise<unknown> {
  const player = env.PLAYERS.getByName(owner), preferences = await player.friendSubscriptions(owner);
  if (!FRIEND_ROOM_EVENTS_ENABLED(env)) return { schema_version: 1, available: false, events: [], preferences };
  const inbox = env.FRIEND_ROOM_EVENTS.getByName(owner);
  const queued = await inbox.inbox(), visible: FriendRoomEvent[] = [];
  for (const item of queued) {
    try {
      const [links, subscription, publication, allowed, roomOk] = await Promise.all([
        Promise.all([player.friendEdge(owner, item.host_id), env.PLAYERS.getByName(item.host_id).friendEdge(item.host_id, owner)]),
        player.friendSubscription(owner, item.host_id), env.PLAYERS.getByName(item.host_id).friendPublication(item.host_id),
        interactionBlocked(env, owner, item.host_id), roomAvailable(env, item.host_id, owner, { schema_version: 1, publication_epoch: item.publication_epoch, publication_id: "a".repeat(22), room: item.room, published_at: item.published_at })
      ]);
      const [a, b] = links;
      if (!a || !b || !a.link.accepted || !b.link.accepted || a.link.request_id !== item.request_id || b.link.request_id !== item.request_id || !sameFriendLink(a.link, b.link, owner) ||
        !subscription?.enabled || subscription.request_id !== item.request_id || !publication || publication.publication_epoch !== item.publication_epoch || publication.room.room_id !== item.room.room_id ||
        publication.room.api_version !== item.room.api_version || allowed || !roomOk || Date.now() - item.published_at >= 24 * 60 * 60 * 1000) {
        await inbox.revoke(item.host_id, item.event_id); continue;
      }
      visible.push(item);
    } catch { /* inaccessible events are omitted; the alarm repeats eligibility checks before any push */ }
  }
  return { schema_version: 1, available: visible.length > 0, events: visible.map(item => ({ event_id: item.event_id, category: item.category, player_id: item.host_id,
    request_id: item.request_id, publication_epoch: item.publication_epoch, room: item.room, published_at: item.published_at })), preferences };
}
export async function friendNotifications(request: Request, owner: string, hostId: string, env: Env): Promise<unknown> {
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const raw = object(await boundedJson(request, 1024));
  if (raw.action === "ack") {
    exact(raw, ["schema_version", "request_id", "action", "event_id"]);
    const requestId = text(raw.request_id, ID_PATTERN), eventId = text(raw.event_id, /^[A-Za-z0-9_-]{22}_[1-9][0-9]{0,15}$/);
    if (!eventId.startsWith(`${hostId}_`)) throw new ApiError(400, "invalid_friend_notification");
    // Acknowledgement only removes this exact rendered event. A repeat is successful.
    unwrap(await env.FRIEND_ROOM_EVENTS.getByName(owner).acknowledge(eventId, owner, requestId));
    return { schema_version: 1, acknowledged: true, request_id: requestId };
  }
  exact(raw, ["schema_version", "request_id", "action"]);
  const requestId = text(raw.request_id, ID_PATTERN);
  if (raw.action !== "subscribe" && raw.action !== "unsubscribe") throw new ApiError(400, "invalid_friend_notification");
  const player = env.PLAYERS.getByName(owner);
  if (raw.action === "subscribe") {
    await relationship(env, owner, hostId, requestId);
    unwrap(await player.setFriendSubscription(owner, hostId, requestId, true));
    try { await relationship(env, owner, hostId, requestId); }
    catch (error) { await player.setFriendSubscription(owner, hostId, requestId, false); throw error; }
    const publication = await env.PLAYERS.getByName(hostId).friendPublication(hostId);
    if (publication) await enqueueFor(env, hostId, owner, requestId, publication);
    return { schema_version: 1, subscribed: true, request_id: requestId };
  }
  unwrap(await player.setFriendSubscription(owner, hostId, requestId, false));
  await env.FRIEND_ROOM_EVENTS.getByName(owner).revoke(hostId);
  return { schema_version: 1, subscribed: false, request_id: requestId };
}
