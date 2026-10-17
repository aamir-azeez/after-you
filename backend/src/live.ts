import { ApiError, ID_PATTERN } from "./protocol";
import { json } from "./http";
import { flags, type ServerVars } from "./flags";
import type { FriendLink } from "./friends";

/**
 * One hibernated WebSocket per phone, held by the player's own Player object.
 * The server writes small hints to it; the app answers each with one ordinary
 * read, so every access rule stays on the read routes.
 *
 * - The socket opens at LIVE_PATH with the usual bearer headers (never the URL).
 * - Live state is only the sockets and their attachments: no tables, no alarms,
 *   no per-connection timers, so an idle socket costs nothing.
 * - Keepalive "ping" is answered by the runtime ("pong") without waking the object.
 */
export const LIVE_PATH = "/v1/live";
/** Clients that can use the socket send this on GET /v2/capabilities; everyone else gets the same bytes as before. */
export const LIVE_CAPABILITY_HEADER = "X-AfterYou-Live";
export const LIVE_VERSION = 1;
/** Sockets one player may hold (two phones plus a reconnect each). A newer one closes the oldest. */
export const MAX_LIVE_SOCKETS = 4;
/** An early friends refresh a hint grants comes at most this soon after the previous list read
 * (the app waits a second longer, timed from its own request, so the grant always covers it). */
export const LIVE_FRIENDS_REFRESH_SECONDS = 2;
export const LIVE_PING = "ping";
export const LIVE_PONG = "pong";
/** Close codes: replaced by a newer socket; identity revoked (recovery or deletion); unexpected client message. */
export const LIVE_CLOSE = Object.freeze({ replaced: 4000, revoked: 4401, unexpected: 1008 });
const DEVICE_HEADER = "X-AfterYou-Live-Device";

/** What a source object asks a recipient's Player to announce. Binding only. */
export type LiveHint =
  | { kind: "room"; room_id: string; revision: number }
  | { kind: "friends"; from: string; request_id: string };
/**
 * What the phone receives. A hint names nothing the phone could not already read.
 * `friends_changed` (a friend's shared room, an accepted request) comes with an
 * early list read the server opened; `friend_requests_changed` (a request
 * arrived, was cancelled, or a friend was removed) does not, so a stranger's
 * request/cancel loop never drives extra list reads on the phone.
 */
export type LiveMessage = { type: "room_changed"; room: string; seq: number } | { type: "friends_changed" } | { type: "friend_requests_changed" };
type Attachment = { device_hash: string; opened_at: number };

export function validLiveHint(value: unknown): value is LiveHint {
  if (typeof value !== "object" || value === null) return false;
  const hint = value as Record<string, unknown>;
  if (hint.kind === "room") return Object.keys(hint).length === 3 && typeof hint.room_id === "string" && ID_PATTERN.test(hint.room_id) && Number.isSafeInteger(hint.revision) && Number(hint.revision) >= 0;
  if (hint.kind === "friends") return Object.keys(hint).length === 3 && typeof hint.from === "string" && ID_PATTERN.test(hint.from) && typeof hint.request_id === "string" && ID_PATTERN.test(hint.request_id);
  return false;
}
export function liveMessage(hint: LiveHint): LiveMessage {
  return hint.kind === "room" ? { type: "room_changed", room: hint.room_id, seq: hint.revision } : { type: "friends_changed" };
}

/** The capability fields for GET /v2/capabilities: empty unless the flag is on and the client asked. */
export function liveCapability(request: Request, env: ServerVars): { live_version?: number } {
  return flags.liveConnection(env) && request.headers.get(LIVE_CAPABILITY_HEADER) === "1" ? { live_version: LIVE_VERSION } : {};
}

/** Router side, after auth(): hands the upgrade to the player's own object with only the device hash. */
export async function forwardLiveUpgrade(request: Request, player: { fetch(request: Request): Promise<Response> }, deviceHash: string): Promise<Response> {
  if (request.method !== "GET") throw new ApiError(405, "method_not_allowed");
  if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") throw new ApiError(426, "upgrade_required");
  return player.fetch(new Request("https://player.internal" + LIVE_PATH, { headers: { Upgrade: "websocket", [DEVICE_HEADER]: deviceHash } }));
}

/** Player side: accepts the socket when `current(hash)` still authorizes that device, in this same synchronous step. */
export function acceptLiveSocket(ctx: DurableObjectState, request: Request, env: ServerVars, current: (deviceHash: string) => boolean): Response {
  if (!flags.liveConnection(env) || new URL(request.url).pathname !== LIVE_PATH || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return json({ error: { code: "not_found", retryable: true } }, 404);
  const deviceHash = request.headers.get(DEVICE_HEADER) ?? "";
  if (!current(deviceHash)) return liveUnauthorized();
  const pair = new WebSocketPair();
  ctx.acceptWebSocket(pair[1]);
  pair[1].serializeAttachment({ device_hash: deviceHash, opened_at: Date.now() } satisfies Attachment);
  const open = ctx.getWebSockets().map(socket => ({ socket, at: attachment(socket)?.opened_at ?? 0 })).sort((a, b) => b.at - a.at);
  for (const extra of open.slice(MAX_LIVE_SOCKETS)) close(extra.socket, LIVE_CLOSE.replaced, "replaced");
  return new Response(null, { status: 101, webSocket: pair[0] });
}

/** The refusal for an upgrade whose device credential is not current (also a blank Player's answer). */
export function liveUnauthorized(): Response { return json({ error: { code: "invalid_auth", retryable: true } }, 401); }

/** The keepalive answer, set once per object; the runtime replies without waking it. */
export function setLiveAutoResponse(ctx: DurableObjectState): void {
  ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(LIVE_PING, LIVE_PONG));
}

/**
 * The open sockets of the current device credential. Any other socket (a
 * credential since rotated or deleted) is closed here instead of written to.
 */
export function liveSockets(ctx: DurableObjectState, deviceHash: string | null): WebSocket[] {
  const kept: WebSocket[] = [];
  for (const socket of ctx.getWebSockets()) {
    if (deviceHash !== null && attachment(socket)?.device_hash === deviceHash) kept.push(socket);
    else close(socket, LIVE_CLOSE.revoked, "revoked");
  }
  return kept;
}
export function sendLive(sockets: WebSocket[], message: LiveMessage): number {
  const text = JSON.stringify(message);
  let sent = 0;
  for (const socket of sockets) { try { socket.send(text); sent++; } catch { /* a closing socket; the phone reconnects */ } }
  return sent;
}
export function closeLiveSockets(ctx: DurableObjectState, code: number = LIVE_CLOSE.revoked): void {
  for (const socket of ctx.getWebSockets()) close(socket, code, "closed");
}
/** Hibernation handlers: a phone only ever sends the auto-answered ping, so anything else closes it. */
export function liveMessageReceived(socket: WebSocket): void { close(socket, LIVE_CLOSE.unexpected, "unexpected"); }
export function liveClosed(socket: WebSocket, code: number): void { close(socket, code === 1005 || code === 1006 || code < 1000 || code > 4999 ? 1000 : code, "closed"); }

function attachment(socket: WebSocket): Attachment | null {
  try { const value = socket.deserializeAttachment() as Attachment | null; return value && typeof value.device_hash === "string" ? value : null; } catch { return null; }
}
function close(socket: WebSocket, code: number, reason: string): void { try { socket.close(code, reason); } catch { /* already closed */ } }

type Waiter = (promise: Promise<unknown>) => void;
type PlayerHints = { getByName(name: string): { liveHint(owner: string, hint: LiveHint): Promise<boolean> } };
/** A room's members after a change; the recipient is whoever did not act. */
export type LiveRoomMembers = { room_id: string; host_id: string; guest_id: string | null; revision: number };
export function liveRoomHint(room: LiveRoomMembers): LiveHint { return { kind: "room", room_id: room.room_id, revision: room.revision }; }
/** The member a change by `actor` is announced to: the other one, or null. */
export function liveRecipient(room: Pick<LiveRoomMembers, "host_id" | "guest_id">, actor: string): string | null {
  const other = actor === room.host_id ? room.guest_id : room.host_id;
  return other && other !== actor ? other : null;
}

/** After a room write commits: one hint to the partner, best effort. Off: no call at all. */
export function announceRoomChange(env: ServerVars & { PLAYERS: PlayerHints }, wait: Waiter, room: LiveRoomMembers, actor: string): void {
  if (!flags.liveConnection(env)) return;
  const recipient = liveRecipient(room, actor);
  if (!recipient) return;
  wait(env.PLAYERS.getByName(recipient).liveHint(recipient, liveRoomHint(room)).catch(() => false));
}
/** One hint to each accepted friend that a shared room changed, best effort; it also opens the friend's next list read early. Off: no call at all. */
export function announceToFriends(env: ServerVars & { PLAYERS: PlayerHints }, owner: string, links: readonly FriendLink[]): Promise<unknown> {
  if (!flags.liveConnection(env)) return Promise.resolve();
  return Promise.all(links.filter(link => link.accepted).map(link =>
    env.PLAYERS.getByName(link.player_id).liveHint(link.player_id, { kind: "friends", from: owner, request_id: link.request_id }).catch(() => false)));
}
