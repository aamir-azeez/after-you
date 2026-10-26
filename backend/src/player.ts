import { DurableObject } from "cloudflare:workers";
import { playerStanding, type Standing } from "./leaderboards/standing";
import { answerWhileBlank, openLazyStorage } from "./lazy-storage";
import { flags } from "./flags";
import { ApiError, ID_PATTERN, equalHash, fail, isObject, ok, randomToken, type Outcome } from "./protocol";
import { pruneCreationHistory, readCampaignCreation, reserveCampaignCreation, reserveCampaignGuestLink, reserveCampaignJoin, readCampaignJoin, readCampaignLink, cancelUnreservedCampaignJoin, cancelCampaignCreation, finalizeCampaignJoinCancellation } from "./v2/campaign-player";
import { campaignIdentityDeletionScope, finalizeCampaignIdentityDeletion, campaignTerminalScope, finalizeCampaignTerminalLink, campaignTerminalAdmissionScope, finalizeCampaignTerminalAdmission } from "./v2/campaign-player";
import { emptySocial, FRIEND_REFRESH_SECONDS, FRIEND_REQUEST_TTL_MS, MAX_FRIENDS, validSocial, validSharedFriendRoom, type FriendEdge, type FriendLink, type SharedFriendRoom, type SocialState } from "./friends";
import { initializeSchema } from "./storage-schema";
import { blankPlayerInventory, campaignPlayerAllocation, campaignPlayerInventory } from "./v2/campaign-drain";
import { exportSnapshot, restoreSnapshot, snapshotResult } from "./snapshot";
import { ROOM_DELETION_BATCH, eraseRoomLinks, roomDeletionDispatcher, roomLinkVersion, validRoomLink, type RoomLink } from "./room-links";
import { roomLimitReached, roomLinkBound } from "./room-limit";
import { clearRoomErasure, deletionOrder, dropRoomIndex, recordRoomObservation, removeRoomIndexRow, roomErasureDelay, roomErasurePending, roomIndexCount, roomIndexPage, roomIndexUnsettled, writeRoomErasure, type RoomFamily, type RoomIndexPage, type RoomObservation } from "./room-index";
import { errorCode, logWarning } from "./log";
import { PLATFORM_LINKS_OBJECT } from "./platform-links";
import { readCreation, validChapterCreation, type ChapterCreation } from "./v2/creation-intent";
import { RELAY_KEY, sameChapter } from "./v2/chapters";
import type { ChapterKey } from "./v2/chapter-types";
import { BINDING_PATTERN, FcmSender, MAX_REGISTRATIONS, REGISTRATION_TTL_MS, makeFriendRoomHint, notificationsConfigured, pushCategoryAllowed, validRoomHint, validNotificationToken, type IosRegistration, type RoomHint, type SendResult } from "./notifications";
import { clearRegistrations, initializeNotifications, pruneNotificationCategories, type DeliveryResult } from "./notification-storage";
import { checkedFriendPublication, checkedFriendSubscription, FRIEND_PUBLICATION_OPS_TABLE, FRIEND_PUBLICATION_TABLE, FRIEND_SUBSCRIPTIONS_TABLE, MAX_FRIEND_SUBSCRIPTIONS, MAX_PUBLICATION_RECEIPTS, PUBLICATION_ID_PATTERN, type FriendPublication, type FriendSubscription } from "./friend-room-event-storage";
import { FRIEND_EVENTS_CLIENT_GATE, type FriendRoomDelivery, type FriendRoomEvent } from "./friend-room-events";
import { interactionBlocked } from "./safety";
import { testerReceipt, validTesterGrant, type TesterGrant, type TesterAccess } from "./tester-access";
import { clearPresence, initializePresence, MAX_PRESENCE_SESSIONS, PRESENCE_SESSION, PRESENCE_TTL_MS, presenceAlarmOwned, presencePolicy, prunePresence, schedulePresence, type PresencePolicy } from "./presence";
import { applyDisplayName, clearDisplayNameFields, MAX_CLEARED_ROOMS, type DisplayNameFields, type DisplayNameOutcome } from "./display-names";
import { creditClear, creditSoloClear, creditTurn, dropWallet, fullJourneyUntil, historyView, noteFullJourney, walletView, type HistoryView, type PollenReceipt, type WalletView } from "./pollen/wallet";
import { LIVE_FRIENDS_REFRESH_SECONDS, acceptLiveSocket, liveUnauthorized, closeLiveSockets, liveClosed, liveMessage, liveMessageReceived, liveSockets, sendLive, setLiveAutoResponse, validLiveHint, type LiveHint } from "./live";

type RecoveryReceipt = { previous_recovery_hash: string; request_hash: string };
type Identity = { player_id: string; device_hash: string; recovery_hash: string; state: "active" | "deleting"; created_at: string; tester_grant?: TesterGrant; recovery_receipt?: RecoveryReceipt; social?: SocialState } & DisplayNameFields;
type FriendPublicationState = { schema_version: 1; epoch_counter: number; current: FriendPublication | null };
function isPublicationState(value: unknown): value is FriendPublicationState {
  return isObject(value) && Object.keys(value).length === 3 && value.schema_version === 1 && Number.isSafeInteger(value.epoch_counter) && Number(value.epoch_counter) >= 0 &&
    (value.current === null || checkedFriendPublication(JSON.stringify(value.current)) !== null && (value.current as FriendPublication).publication_epoch <= Number(value.epoch_counter));
}
/** Remembered finished pushes per Player instance; a few events times five phones. */
const MAX_FINISHED_PUSHES = 64;
export class Player extends DurableObject<Env> {
  private readonly notificationSender: FcmSender;
  /**
   * Pushes already finished per event and token, so a retry of the same event sends only to
   * the phones that failed. Memory only and bounded: after eviction a retry sends to every
   * phone again, as it always did.
   */
  private readonly finishedPushes = new Set<string>();
  private pushFinished(key: string): boolean { return this.finishedPushes.has(key); }
  private finishPush(key: string, sent: SendResult): void {
    if (sent.status !== "sent" && sent.status !== "invalid_token" && sent.status !== "rejected") return;
    this.finishedPushes.delete(key); this.finishedPushes.add(key);
    while (this.finishedPushes.size > MAX_FINISHED_PUSHES) this.finishedPushes.delete(this.finishedPushes.values().next().value!);
  }
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.notificationSender = new FcmSender(env);
    this.ctx.blockConcurrencyWhile(async () => {
      openLazyStorage(this, this.ctx.storage, "identity", () => {
        initializeSchema(this.ctx.storage, "Player");
        initializeNotifications(this.ctx.storage, "Player");
        for (const table of [FRIEND_PUBLICATION_TABLE, FRIEND_PUBLICATION_OPS_TABLE, FRIEND_SUBSCRIPTIONS_TABLE]) this.ctx.storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
        initializePresence(this.ctx.storage);
      });
      // A deletion continuation whose alarm was lost (for example across a code
      // rollback) starts again on the object's next wake. A blank Player has no
      // marker table, so this reads nothing and writes nothing.
      if (roomErasurePending(this.ctx.storage) && await this.ctx.storage.getAlarm() === null) await this.ctx.storage.setAlarm(Date.now());
    });
    setLiveAutoResponse(this.ctx);
  }
  /** The live socket (live.ts). The router forwards only an authenticated upgrade with its device hash. */
  fetch(request: Request): Response {
    return acceptLiveSocket(this.ctx, request, this.env, deviceHash => this.authorize(deviceHash));
  }
  webSocketMessage(socket: WebSocket): void { liveMessageReceived(socket); }
  webSocketClose(socket: WebSocket, code: number): void { liveClosed(socket, code); }
  webSocketError(socket: WebSocket): void { liveClosed(socket, 1011); }
  /**
   * Binding only: a hint from the object where something changed. Sent only to
   * this player's open sockets of the current device, and only after the same
   * local checks the matching read makes; a friend hint also checks blocks,
   * paid only when a socket is open. Returns whether any socket got it.
   */
  async liveHint(owner: string, hint: LiveHint): Promise<boolean> {
    if (!flags.liveConnection(this.env) || !validLiveHint(hint)) return false;
    const identity = this.identity();
    if (!identity || identity.state !== "active" || identity.player_id !== owner) { closeLiveSockets(this.ctx); return false; }
    if (!liveSockets(this.ctx, identity.device_hash).length) return false;
    if (hint.kind === "room") {
      const link = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", hint.room_id).toArray()[0];
      if (!link || roomLinkVersion(JSON.parse(link.data) as RoomLink) !== 2) return false;
      return sendLive(liveSockets(this.ctx, identity.device_hash), liveMessage(hint)) > 0;
    }
    if (!this.acceptedFriend(identity, hint.from, hint.request_id)) return false;
    if (await interactionBlocked(this.env, owner, hint.from)) return false;
    const current = this.identity();
    if (!current || current.state !== "active" || current.player_id !== owner || !this.acceptedFriend(current, hint.from, hint.request_id)) return false;
    this.grantFriendsRefresh(current);
    return sendLive(liveSockets(this.ctx, current.device_hash), liveMessage(hint)) > 0;
  }
  private acceptedFriend(identity: Identity, peer: string, requestId: string): boolean {
    const link = this.social(identity).links.find(x => x.player_id === peer);
    return !!link && link.accepted && link.request_id === requestId;
  }
  /** A hint makes the next friends list read due LIVE_FRIENDS_REFRESH_SECONDS after the last one, not FRIEND_REFRESH_SECONDS. */
  private grantFriendsRefresh(identity: Identity): void {
    const social = this.social(identity), now = Date.now();
    // Already open, or already granted: a second hint never shortens it again.
    if (social.next_refresh_at - now <= LIVE_FRIENDS_REFRESH_SECONDS * 1000) return;
    const granted = Math.max(0, social.next_refresh_at - (FRIEND_REFRESH_SECONDS - LIVE_FRIENDS_REFRESH_SECONDS) * 1000);
    if (granted < social.next_refresh_at) { social.next_refresh_at = granted; this.writeSocial(identity, social, false); }
  }
  /**
   * A friend change made in this object for this player. `accepted`: a request
   * this player sent was accepted. Otherwise a request arrived, was cancelled or
   * a friend was removed, which opens no early read on the phone.
   */
  private pushFriendsChanged(identity: Identity, accepted: boolean): void {
    if (flags.liveConnection(this.env)) sendLive(liveSockets(this.ctx, identity.device_hash), { type: accepted ? "friends_changed" : "friend_requests_changed" });
  }
  // Binding-only maintenance primitives; never dispatched by the public router.
  exportSnapshot(sourceCommit: string): Promise<Outcome<string>> { return snapshotResult(() => exportSnapshot(this.ctx, "Player", sourceCommit)); }
  restoreSnapshot(archive: string, expectedLogicalId: string | null): Promise<Outcome<{ restored: true; checksum: string }>> { return snapshotResult(() => restoreSnapshot(this.ctx, "Player", archive, expectedLogicalId)); }
  private identity(): Identity | null {
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").toArray()[0];
    return row ? JSON.parse(row.data) as Identity : null;
  }
  create(playerId: string, deviceHash: string, recoveryHash: string): Outcome<{ player_id: string }> {
    if (this.identity()) return fail(409, "identity_exists");
    this.ctx.storage.sql.exec("INSERT INTO identity VALUES (1, ?)", JSON.stringify({ player_id: playerId, device_hash: deviceHash, recovery_hash: recoveryHash, state: "active", created_at: new Date().toISOString() } satisfies Identity));
    return ok({ player_id: playerId });
  }
  /** Binding only: the platform link route's proof that the caller also holds the recovery code. */
  recoveryMatches(recoveryHash: string): boolean {
    const identity = this.identity();
    return identity?.state === "active" && equalHash(identity.recovery_hash, recoveryHash);
  }
  /**
   * `fullJourneyUntil`: the Full Journey end RevenueCat just reported for this player (0 for none), which
   * the route passes only while Pollen earning is on; an authorized call notes it (pollen/wallet.ts).
   */
  authorize(deviceHash: string, allowDeleting = false, fullJourneyUntil?: number): boolean {
    const identity = this.authorized(deviceHash, allowDeleting);
    if (identity && identity.state === "active" && fullJourneyUntil !== undefined) noteFullJourney(this.ctx.storage, fullJourneyUntil, Date.now());
    return identity !== null;
  }
  /** The identity when `deviceHash` is its current device credential, read once for the check and what rides on it. */
  private authorized(deviceHash: string, allowDeleting = false): Identity | null {
    const identity = this.identity();
    return identity && (identity.state === "active" || allowDeleting) && equalHash(identity.device_hash, deviceHash) ? identity : null;
  }
  /**
   * authorize() plus the player's display name (null when anonymous), from the same identity read.
   * auth() uses it only on the routes that write the name into a room (display-names.ts namesRoomRoute).
   * `pollen`: also the player's Full Journey end (fj_until), for routes that write it into a room while Pollen earning is on.
   */
  authorizeNamed(deviceHash: string, pollen = false): { authorized: boolean; linked: boolean; display_name?: string | null; fj_until?: number } {
    const identity = this.authorized(deviceHash);
    return identity ? { authorized: true, linked: true, display_name: identity.display_name ?? null, ...(pollen ? { fj_until: fullJourneyUntil(this.ctx.storage) } : {}) } : { authorized: false, linked: true };
  }
  /**
   * authorize() for a request that names a room, plus whether this player may reach that room:
   * it holds a link to it, or has Story rows (see storyHeld).
   * An authorized answer also carries the player's current safety token (see v2/block-memo.ts), and with
   * `pollen` (a turn while Pollen earning is on) the player's Full Journey end.
   */
  authorizeRoom(deviceHash: string, roomId: string, pollen = false): { authorized: boolean; linked: boolean; safety_token?: string; display_name?: string | null; fj_until?: number } {
    const identity = this.authorized(deviceHash);
    if (!identity) return { authorized: false, linked: false };
    const linked = this.ctx.storage.sql.exec("SELECT 1 FROM rooms WHERE room_id=?", roomId).toArray().length > 0 || this.storyHeld();
    return { authorized: true, linked, safety_token: this.safetyToken, display_name: identity.display_name ?? null, ...(pollen ? { fj_until: fullJourneyUntil(this.ctx.storage) } : {}) };
  }
  /** authorize() plus the wallet or its history (GET /v1/pollen and /v1/pollen/history), from one call. */
  authorizeWallet(deviceHash: string, view: "wallet" | "history"): { authorized: boolean; linked: boolean; pollen?: WalletView | HistoryView } {
    const identity = this.authorized(deviceHash);
    if (!identity) return { authorized: false, linked: true };
    return { authorized: true, linked: true, pollen: view === "wallet" ? walletView(this.ctx.storage, Date.now()) : historyView(this.ctx.storage) };
  }
  private pollenActive(owner: string): () => boolean {
    return () => { const identity = this.identity(); return identity?.state === "active" && identity.player_id === owner; };
  }
  /** Binding only: credits one accepted turn from the facts its room froze (pollen/wallet.ts creditTurn). */
  creditTurn(owner: string, facts: unknown): Promise<Outcome<PollenReceipt>> {
    if (!this.pollenActive(owner)()) return Promise.resolve(fail(404, "identity_absent"));
    return creditTurn(this.ctx.storage, this.env, owner, facts, Date.now(), this.pollenActive(owner));
  }
  /**
   * Binding only: a first clear made together, from the facts of the turn that finished the chapter.
   * The room's boost is the same for both members, so the partner's clear uses the frozen percent.
   */
  creditTogetherClear(owner: string, levelId: string, hard: boolean, boost: number): Outcome<PollenReceipt> {
    return creditClear(this.ctx.storage, { level_id: levelId, hard, boost_percent: boost }, Date.now(), this.pollenActive(owner));
  }
  /**
   * Binding only: a solo first clear the app claims. A paid chapter needs Full Journey (the stored
   * fj_until; no provider call), and a subscriber's room of one gets one subscriber's boost.
   */
  creditSoloClear(owner: string, levelId: string, premium: boolean): Outcome<PollenReceipt> {
    return creditSoloClear(this.ctx.storage, levelId, premium, Date.now(), this.pollenActive(owner));
  }
  /**
   * Story rooms are not linked one by one, and the Story drain releases a player's v3 links but keeps the
   * Story creation and admission rows that fence them (creation_schema 2 and 3). A player with either may
   * reach any room id, so a Story room keeps giving its own 409 campaign_client_required instead of 404.
   * Read only when the room id itself is not linked.
   */
  private storyHeld(): boolean {
    return this.ctx.storage.sql.exec("SELECT 1 FROM rooms WHERE json_extract(data,'$.api_version')=3 LIMIT 1").toArray().length > 0 ||
      this.ctx.storage.sql.exec("SELECT 1 FROM creations WHERE json_extract(data,'$.creation_schema') IN (2,3) LIMIT 1").toArray().length > 0;
  }
  /**
   * Changes whenever this player blocks or is blocked, so no room keeps treating the pair as unblocked.
   * Memory only and random: a new instance, after eviction or a restore, starts with a value no room has seen.
   */
  private safetyToken = randomToken(16);
  /** Called by SafetyProfile after it stores a block that involves this player. */
  rotateSafetyToken(): void { this.safetyToken = randomToken(16); }
  private social(identity: Identity): SocialState {
    if (identity.social !== undefined && !validSocial(identity.social, identity.player_id)) throw new Error("unsupported_friend_state");
    return identity.social ?? emptySocial();
  }
  private writeSocial(identity: Identity, social: SocialState, invalidate = true): void {
    if (invalidate) social.next_refresh_at = 0;
    identity.social = social;
    this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
  }
  /** `withName`: the answer is a copy that also carries the owner's display name (never stored with the social state). */
  friendList(owner: string, deviceHash: string, refresh = true, withName = false): Outcome<SocialState & { display_name?: string | null }> {
    const identity = this.identity();
    if (!identity || identity.state !== "active" || !equalHash(identity.device_hash, deviceHash) || identity.player_id !== owner) return fail(401, "invalid_auth");
    const social = this.social(identity), now = Date.now();
    if (!refresh) return ok(withName ? { ...social, display_name: identity.display_name ?? null } : social);
    if (social.next_refresh_at > now) return fail(429, "friends_refresh_limited");
    social.links = social.links.filter(link => link.accepted || link.created_at + FRIEND_REQUEST_TTL_MS > now);
    social.next_refresh_at = now + FRIEND_REFRESH_SECONDS * 1000;
    this.writeSocial(identity, social, false);
    return ok(social);
  }
  /** Binding only; list callers must also check the opposite edge and blocks. */
  /** `withName`: also this player's display name; the friends list shows it only on an accepted row. */
  friendEdge(owner: string, peer: string, withName = false): FriendEdge | null {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active") return null;
    const social = this.social(identity), link = social.links.find(x => x.player_id === peer);
    if (!link || !link.accepted && link.created_at + FRIEND_REQUEST_TTL_MS <= Date.now()) return null;
    return { link, shared_room: social.shared_room, presence_expires_at: link.accepted ? this.presenceExpiryForIdentity(identity) : 0,
      ...(withName ? { display_name: identity.display_name ?? null } : {}) };
  }
  /** PUT /v1/profile/name after the router cleaned the name (display-names.ts applyDisplayName). One row write, only on a change. */
  setDisplayName(owner: string, deviceHash: string, name: string | null, revision: number): DisplayNameOutcome {
    const identity = this.authorized(deviceHash);
    if (!identity || identity.player_id !== owner) return fail(401, "invalid_auth");
    const named = identity.display_name !== undefined;
    const { outcome, changed } = applyDisplayName(identity, name, revision, Date.now());
    if (changed) this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    // A name that just went: the v2 rooms that may hold a copy, for the route to clear.
    if (changed && named && identity.display_name === undefined && outcome.ok) return { ...outcome, cleared_rooms: this.listRooms().filter(link => roomLinkVersion(link) === 2).slice(0, MAX_CLEARED_ROOMS).map(link => link.room_id) };
    return outcome;
  }
  /** Binding only (the friend link page): the active identity's stored name, or null. Nothing else leaves. */
  publicDisplayName(owner: string): string | null {
    const identity = this.identity();
    return identity && identity.player_id === owner && identity.state === "active" ? identity.display_name ?? null : null;
  }
  /** Binding only (leaderboards/standing.ts): account age, shown name and partners for the ranking check. Reads only. */
  leaderboardStanding(): Standing | null { return playerStanding(this.ctx.storage, this.identity()); }
  /** Binding only (operator clear-name): clears the name, locks new ones, and returns the v2 rooms that may hold a copy. */
  operatorClearDisplayName(owner: string): Outcome<string[]> {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner) return fail(404, "identity_absent");
    clearDisplayNameFields(identity, Date.now());
    this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    return ok(this.listRooms().filter(link => roomLinkVersion(link) === 2).slice(0, MAX_CLEARED_ROOMS).map(link => link.room_id));
  }
  friendPropose(owner: string, deviceHash: string, peer: string, requestId: string): Outcome<FriendLink> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    if (!ID_PATTERN.test(peer) || peer === owner || !ID_PATTERN.test(requestId)) return fail(400, "invalid_friend_request");
    const identity = this.identity()!, social = this.social(identity);
    social.links = social.links.filter(link => link.accepted || link.created_at + FRIEND_REQUEST_TTL_MS > Date.now());
    const old = social.links.find(x => x.player_id === peer);
    if (old) { this.writeSocial(identity, social); return ok(old); }
    if (social.links.length >= MAX_FRIENDS) return fail(409, "friend_list_full");
    const link: FriendLink = { player_id: peer, request_id: requestId, requested_by: owner, accepted: false, created_at: Date.now() };
    social.links.push(link); this.writeSocial(identity, social); return ok(link);
  }
  /** Binding only: router retains the sender's durable proposal across this hop. */
  friendReceive(owner: string, peer: string, requestId: string, createdAt: number): Outcome<FriendLink> {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active") return fail(404, "friend_unavailable");
    if (!ID_PATTERN.test(peer) || peer === owner || !ID_PATTERN.test(requestId) || !Number.isSafeInteger(createdAt) || createdAt <= 0) return fail(400, "invalid_friend_request");
    const social = this.social(identity);
    social.links = social.links.filter(link => link.accepted || link.created_at + FRIEND_REQUEST_TTL_MS > Date.now());
    const old = social.links.find(x => x.player_id === peer);
    if (old) return old.request_id === requestId && old.requested_by === peer ? ok(old) : fail(409, "friend_request_changed");
    if (social.links.length >= MAX_FRIENDS) return fail(409, "friend_list_full");
    const link: FriendLink = { player_id: peer, request_id: requestId, requested_by: peer, accepted: false, created_at: createdAt };
    social.links.push(link); this.writeSocial(identity, social); this.pushFriendsChanged(identity, false); return ok(link);
  }
  friendApprove(owner: string, deviceHash: string, peer: string, requestId: string): Outcome<FriendLink> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    const identity = this.identity()!, social = this.social(identity), link = social.links.find(x => x.player_id === peer);
    if (!link || link.request_id !== requestId || link.requested_by !== peer || !link.accepted && link.created_at + FRIEND_REQUEST_TTL_MS <= Date.now()) return fail(409, "friend_request_changed");
    link.accepted = true; this.writeSocial(identity, social); return ok(link);
  }
  /** Binding only, after the recipient's matching approval is read. */
  friendConfirm(owner: string, peer: string, requestId: string): Outcome<FriendLink> {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active") return fail(404, "friend_unavailable");
    const social = this.social(identity), link = social.links.find(x => x.player_id === peer);
    if (!link || link.request_id !== requestId || link.requested_by !== owner) return fail(409, "friend_request_changed");
    link.accepted = true; this.writeSocial(identity, social); this.pushFriendsChanged(identity, true); return ok(link);
  }
  /** Exact-token removal cannot erase a newer request after a lost reply. */
  friendForget(owner: string, peer: string, requestId: string, deviceHash?: string): Outcome<{ removed: true }> {
    const identity = this.identity();
    if (deviceHash !== undefined && (!this.authorize(deviceHash) || identity?.player_id !== owner)) return fail(401, "invalid_auth");
    if (!identity || identity.player_id !== owner) return ok({ removed: true });
    const social = this.social(identity);
    social.links = social.links.filter(x => x.player_id !== peer || x.request_id !== requestId);
    this.ctx.storage.sql.exec("DELETE FROM friend_room_subscriptions WHERE host_id=? AND json_extract(data,'$.request_id')=?", peer, requestId);
    this.writeSocial(identity, social);
    // A peer's removal (no device hash) reaches this player's open Friends page.
    if (deviceHash === undefined && identity.state === "active") this.pushFriendsChanged(identity, false);
    return ok({ removed: true });
  }
  friendShare(owner: string, deviceHash: string, room: SharedFriendRoom | null): Outcome<{ shared_room: SharedFriendRoom | null }> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    if (room !== null && (!validSharedFriendRoom(room) || !this.listRooms().some(x => x.host && x.room_id === room.room_id && roomLinkVersion(x) === room.api_version))) return fail(404, "room_not_found");
    return this.ctx.storage.transactionSync(() => {
      const identity = this.identity()!, social = this.social(identity), old = social.shared_room;
      const changed = old?.room_id !== room?.room_id || old?.api_version !== room?.api_version;
      const row = changed ? this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_publication WHERE id=1").toArray()[0] : undefined;
      let publicationState: FriendPublicationState | null = null;
      if (row) {
        try { const parsed: unknown = JSON.parse(row.data); if (!isPublicationState(parsed)) return fail(409, "unsupported_friend_publication"); publicationState = parsed; }
        catch { return fail(409, "unsupported_friend_publication"); }
      }
      social.shared_room = room; this.writeSocial(identity, social);
      if (publicationState?.current) this.ctx.storage.sql.exec("UPDATE friend_room_publication SET data=? WHERE id=1", JSON.stringify({ ...publicationState, current: null }));
      return ok({ shared_room: room });
    });
  }
  /** Separate from SocialState so its exact persisted validator and API shape stay frozen. */
  friendPublication(owner: string): FriendPublication | null {
    const identity = this.identity(); if (!identity || identity.player_id !== owner || identity.state !== "active") return null;
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_publication WHERE id=1").toArray()[0];
    if (!row) return null;
    try {
      const parsed: unknown = JSON.parse(row.data);
      if (!isPublicationState(parsed)) throw new Error("unsupported_friend_publication");
      const social = this.social(identity);
      return parsed.current && social.shared_room?.room_id === parsed.current.room.room_id && social.shared_room.api_version === parsed.current.room.api_version ? parsed.current : null;
    } catch { throw new Error("unsupported_friend_publication"); }
  }
  publishFriendRoom(owner: string, deviceHash: string, publicationId: string, room: SharedFriendRoom): Outcome<FriendPublication> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    if (!PUBLICATION_ID_PATTERN.test(publicationId) || !validSharedFriendRoom(room)) return fail(400, "invalid_friend_publication");
    const identity = this.identity()!, social = this.social(identity);
    if (!social.shared_room || social.shared_room.api_version !== room.api_version || social.shared_room.room_id !== room.room_id) return fail(409, "friend_room_not_shared");
    return this.ctx.storage.transactionSync(() => {
      const existingReceipt = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_publication_ops WHERE publication_id=?", publicationId).toArray()[0];
      if (existingReceipt) {
        const receipt = checkedFriendPublication(existingReceipt.data);
        return receipt && receipt.room.api_version === room.api_version && receipt.room.room_id === room.room_id ? ok(receipt) : fail(409, "friend_publication_changed");
      }
      const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_publication WHERE id=1").toArray()[0];
      let state = { schema_version: 1 as const, epoch_counter: 0, current: null as FriendPublication | null };
      if (row) {
        try { const parsed: unknown = JSON.parse(row.data); if (!isPublicationState(parsed)) return fail(409, "unsupported_friend_publication"); state = parsed; }
        catch { return fail(409, "unsupported_friend_publication"); }
      }
      if (state.epoch_counter >= Number.MAX_SAFE_INTEGER) return fail(409, "friend_publication_epoch_exhausted");
      const publication: FriendPublication = { schema_version: 1, publication_epoch: state.epoch_counter + 1, publication_id: publicationId, room, published_at: Date.now() };
      state = { schema_version: 1, epoch_counter: publication.publication_epoch, current: publication };
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_publication VALUES (1,?)", JSON.stringify(state));
      this.ctx.storage.sql.exec("INSERT INTO friend_room_publication_ops VALUES (?,?)", publicationId, JSON.stringify(publication));
      this.ctx.storage.sql.exec("DELETE FROM friend_room_publication_ops WHERE publication_id IN (SELECT publication_id FROM friend_room_publication_ops ORDER BY json_extract(data,'$.published_at') DESC LIMIT -1 OFFSET ?)", MAX_PUBLICATION_RECEIPTS);
      return ok(publication);
    });
  }
  friendSubscription(owner: string, host: string): FriendSubscription | null {
    const identity = this.identity(); if (!identity || identity.player_id !== owner || identity.state !== "active") return null;
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_subscriptions WHERE host_id=?", host).toArray()[0];
    if (!row) return null;
    const subscription = checkedFriendSubscription(row.data); if (!subscription) throw new Error("unsupported_friend_subscription");
    return subscription;
  }
  friendSubscriptions(owner: string): Array<{ player_id: string; request_id: string; enabled: boolean }> {
    const identity = this.identity(); if (!identity || identity.player_id !== owner || identity.state !== "active") return [];
    return this.ctx.storage.sql.exec<{ host_id: string; data: string }>("SELECT host_id,data FROM friend_room_subscriptions ORDER BY host_id LIMIT 21").toArray().flatMap(row => {
      const sub = checkedFriendSubscription(row.data); if (!sub) throw new Error("unsupported_friend_subscription");
      return [{ player_id: row.host_id, request_id: sub.request_id, enabled: sub.enabled }];
    });
  }
  setFriendSubscription(owner: string, host: string, requestId: string, enabled: boolean): Outcome<{ subscribed: boolean }> {
    const identity = this.identity(); if (!identity || identity.player_id !== owner || identity.state !== "active") return fail(404, "friend_unavailable");
    if (!ID_PATTERN.test(host) || !ID_PATTERN.test(requestId) || typeof enabled !== "boolean") return fail(400, "invalid_friend_notification");
    return this.ctx.storage.transactionSync(() => {
      const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_subscriptions WHERE host_id=?", host).toArray()[0];
      if (!old && enabled && this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM friend_room_subscriptions").one().n >= MAX_FRIEND_SUBSCRIPTIONS) return fail(409, "friend_subscription_limit");
      if (enabled) this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_subscriptions VALUES (?,?)", host, JSON.stringify({ schema_version: 1, request_id: requestId, enabled, updated_at: Date.now() } satisfies FriendSubscription));
      else this.ctx.storage.sql.exec("DELETE FROM friend_room_subscriptions WHERE host_id=? AND json_extract(data,'$.request_id')=?", host, requestId);
      return ok({ subscribed: enabled });
    });
  }
  /** Called only by the recipient-keyed event DO after the in-app row is durable. */
  async deliverFriendRoomNotification(event: FriendRoomEvent): Promise<FriendRoomDelivery> {
    const identity = this.identity(); if (!identity || identity.state !== "active" || identity.player_id !== event.recipient_id) return { status: "cancelled" };
    const hostPlayer = this.env.PLAYERS.getByName(event.host_id);
    const [recipientEdge, hostEdge, publication, subscription, pending] = await Promise.all([this.friendEdge(event.recipient_id, event.host_id), hostPlayer.friendEdge(event.host_id, event.recipient_id),
      hostPlayer.friendPublication(event.host_id), this.friendSubscription(event.recipient_id, event.host_id), this.env.FRIEND_ROOM_EVENTS.getByName(event.recipient_id).isPending(event.recipient_id, event.event_id)]);
    if (!recipientEdge || !hostEdge || !recipientEdge.link.accepted || !hostEdge.link.accepted || recipientEdge.link.request_id !== event.request_id || hostEdge.link.request_id !== event.request_id ||
      !subscription?.enabled || subscription.request_id !== event.request_id || !pending || !publication || publication.publication_epoch !== event.publication_epoch || publication.room.room_id !== event.room.room_id || publication.room.api_version !== event.room.api_version ||
      await interactionBlocked(this.env, event.recipient_id, event.host_id)) return { status: "cancelled" };
    const available = event.room.api_version === 1 ? await this.env.ROOMS.getByName(event.room.room_id).friendInvite(event.host_id, event.recipient_id) : await this.env.ROOMS_V2.getByName(event.room.room_id).friendInvite(event.host_id, event.recipient_id);
    if (!available.ok) return { status: "cancelled" };
    const stored = this.ctx.storage.sql.exec<{ binding_epoch: string; data: string }>("SELECT binding_epoch,data FROM notification_registrations LIMIT 5").toArray();
    if (stored.length > MAX_REGISTRATIONS) return { status: "retry" };
    // Only a phone whose registration came from a client that reads hosting
    // events (0.6.1+) gets the push; an older one could never acknowledge it.
    const gated = FRIEND_EVENTS_CLIENT_GATE(this.env);
    const registrations = stored.filter(row => {
      const data = JSON.parse(row.data) as { friend_events?: number; platform?: string; categories?: string };
      return (!gated || data.friend_events === 2) && pushCategoryAllowed(this.env, data, "friend_room_available");
    });
    if (!registrations.length || !notificationsConfigured(this.env)) return { status: "done" };
    const outcomes = await Promise.all(registrations.map(async (row): Promise<SendResult> => {
      const registration = JSON.parse(row.data) as { token: string; device_hash: string; updated_at: number; platform?: string };
      const pushKey = `friend:${event.event_id}:${row.binding_epoch}:${registration.token}`;
      if (this.pushFinished(pushKey)) return { status: "sent" };
      const current = () => this.authorize(registration.device_hash) && this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations WHERE binding_epoch=?", row.binding_epoch).toArray()[0]?.data === row.data &&
        Date.now() - registration.updated_at < REGISTRATION_TTL_MS;
      const eligible = async (): Promise<boolean> => {
        if (!current()) return false;
        const recipientEdge = this.friendEdge(event.recipient_id, event.host_id), hostPlayer = this.env.PLAYERS.getByName(event.host_id);
        const [hostEdge, publication, subscription, pending] = await Promise.all([hostPlayer.friendEdge(event.host_id, event.recipient_id), hostPlayer.friendPublication(event.host_id), this.friendSubscription(event.recipient_id, event.host_id), this.env.FRIEND_ROOM_EVENTS.getByName(event.recipient_id).isPending(event.recipient_id, event.event_id)]);
        if (!recipientEdge || !hostEdge || !recipientEdge.link.accepted || !hostEdge.link.accepted || recipientEdge.link.request_id !== event.request_id || hostEdge.link.request_id !== event.request_id ||
          !subscription?.enabled || subscription.request_id !== event.request_id || !pending || !publication || publication.publication_epoch !== event.publication_epoch || publication.room.room_id !== event.room.room_id || publication.room.api_version !== event.room.api_version) return false;
        if (await interactionBlocked(this.env, event.recipient_id, event.host_id) || !current()) return false;
        const room = event.room.api_version === 1 ? await this.env.ROOMS.getByName(event.room.room_id).friendInvite(event.host_id, event.recipient_id) : await this.env.ROOMS_V2.getByName(event.room.room_id).friendInvite(event.host_id, event.recipient_id);
        return room.ok && current();
      };
      const sent = await this.notificationSender.send(registration.token, row.binding_epoch,
        makeFriendRoomHint(event.host_id, event.room, event.publication_epoch, event.event_id), eligible, registration.platform === "ios" ? "ios" : "android");
      if (sent.status === "invalid_token" && current()) this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE binding_epoch=? AND data=?", row.binding_epoch, row.data);
      this.finishPush(pushKey, sent);
      return sent;
    }));
    if (outcomes.some(value => value.status === "retry" || value.status === "unconfigured")) return { status: "retry", retry_after_ms: Math.max(0, ...outcomes.map(value => value.retry_after_ms ?? 0)) };
    if (outcomes.length > 0 && outcomes.every(value => value.status === "cancelled")) return { status: "cancelled" };
    return { status: "done" };
  }
  async updatePresence(owner: string, deviceHash: string, session: string, online: boolean): Promise<Outcome<PresencePolicy>> {
    if (!PRESENCE_SESSION.test(session) || typeof online !== "boolean") return fail(400, "invalid_presence_request");
    return this.ctx.storage.transaction(async () => {
      const alarm = await this.ctx.storage.getAlarm();
      if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
      if (online && !flags.presence(this.env)) return fail(503, "presence_unavailable");
      if (!presenceAlarmOwned(this.ctx.storage, alarm)) return fail(503, "presence_unavailable");
      prunePresence(this.ctx.storage);
      if (online) {
        const existing = this.ctx.storage.sql.exec("SELECT session_id FROM presence_leases WHERE session_id=?", session).toArray();
        if (!existing.length && this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM presence_leases").one().n >= MAX_PRESENCE_SESSIONS) return fail(409, "presence_session_limit");
        this.ctx.storage.sql.exec("INSERT OR REPLACE INTO presence_leases VALUES (?,?,?)", session, deviceHash, Date.now() + PRESENCE_TTL_MS);
      } else this.ctx.storage.sql.exec("DELETE FROM presence_leases WHERE session_id=?", session);
      await schedulePresence(this.ctx.storage);
      return ok(presencePolicy());
    });
  }
  /** Binding only: never expose a per-player presence lookup over HTTP. */
  presenceExpiry(owner: string): number {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active") return 0;
    return this.presenceExpiryForIdentity(identity);
  }
  /** Reuse only an owner-validated active identity within the same synchronous call. */
  private presenceExpiryForIdentity(identity: Identity): number {
    prunePresence(this.ctx.storage);
    return this.ctx.storage.sql.exec<{ expires_at: number | null }>("SELECT MAX(expires_at) AS expires_at FROM presence_leases WHERE device_hash=?", identity.device_hash).one().expires_at ?? 0;
  }
  async alarm(): Promise<void> {
    if (roomErasurePending(this.ctx.storage)) return this.continueRoomErasure();
    await this.ctx.storage.transaction(async () => {
      const actual = await this.ctx.storage.getAlarm();
      if (!presenceAlarmOwned(this.ctx.storage, actual, true)) throw new Error("unowned_presence_alarm");
      prunePresence(this.ctx.storage); await schedulePresence(this.ctx.storage);
    });
  }
  /** Binding-only host lookup; the logical owner and active identity must match. */
  storedTesterGrant(owner: string): TesterGrant | null {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active" || !Object.hasOwn(identity, "tester_grant")) return null;
    if (!validTesterGrant(identity.tester_grant)) throw new Error("unsupported_tester_grant");
    return { ...identity.tester_grant };
  }
  testerAccess(owner: string, deviceHash: string): Outcome<TesterAccess> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    return ok(testerReceipt(owner, this.storedTesterGrant(owner)));
  }
  redeemTesterAccess(owner: string, deviceHash: string, codeAccepted: boolean): Outcome<TesterAccess> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    const existing = this.storedTesterGrant(owner);
    if (existing) return ok(testerReceipt(owner, existing));
    if (codeAccepted !== true) return fail(403, "tester_access_unavailable");
    const identity = this.identity()!;
    const grant: TesterGrant = { schema_version: 1, granted_at: new Date().toISOString() };
    identity.tester_grant = grant;
    // One fixed-size identity field, one synchronous write; no code/hash history.
    this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    return ok(testerReceipt(owner, grant));
  }
  registerNotifications(deviceHash: string, token: string, epoch: string, friendEvents = false, ios: IosRegistration | null = null): Outcome<{ registered: true; binding_epoch: string }> {
    if (!this.authorize(deviceHash)) return fail(401, "invalid_auth");
    if (!validNotificationToken(token) || !BINDING_PATTERN.test(epoch)) return fail(400, "invalid_notification_registration");
    if (!notificationsConfigured(this.env)) return fail(503, "notifications_unavailable");
    const now = Date.now();
    return this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE json_extract(data,'$.device_hash')!=? OR json_extract(data,'$.updated_at')<? OR (json_extract(data,'$.token')=? AND binding_epoch!=?)", deviceHash, now - REGISTRATION_TTL_MS, token, epoch);
      const old = this.ctx.storage.sql.exec("SELECT binding_epoch FROM notification_registrations WHERE binding_epoch=?", epoch).toArray();
      if (!old.length && this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM notification_registrations").one().n >= MAX_REGISTRATIONS) return fail(409, "notification_registration_limit");
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO notification_registrations VALUES (?,?)", epoch, JSON.stringify({ token, device_hash: deviceHash, updated_at: now, ...(friendEvents ? { friend_events: 2 } : {}), ...(ios ? { platform: ios.platform, categories: ios.categories } : {}) }));
      pruneNotificationCategories(this.ctx.storage);
      return ok({ registered: true, binding_epoch: epoch });
    });
  }
  unregisterNotifications(deviceHash: string, epoch: string): Outcome<{ unregistered: true }> {
    if (!this.authorize(deviceHash)) return fail(401, "invalid_auth");
    if (!BINDING_PATTERN.test(epoch)) return fail(400, "invalid_notification_registration");
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE binding_epoch=?", epoch);
      pruneNotificationCategories(this.ctx.storage);
    });
    return ok({ unregistered: true });
  }
  /** Optional push categories for one current registration. Only redo requests exist; a row is kept only while on. */
  setNotificationCategories(deviceHash: string, epoch: string, redoRequests: boolean): Outcome<{ schema_version: 1; binding_epoch: string; redo_requests: boolean }> {
    if (!this.authorize(deviceHash)) return fail(401, "invalid_auth");
    if (!BINDING_PATTERN.test(epoch) || typeof redoRequests !== "boolean") return fail(400, "invalid_notification_categories");
    if (redoRequests && !notificationsConfigured(this.env)) return fail(503, "notifications_unavailable");
    const now = Date.now();
    return this.ctx.storage.transactionSync(() => {
      const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations WHERE binding_epoch=?", epoch).toArray()[0];
      const registration = row ? JSON.parse(row.data) as { device_hash: string; updated_at: number } : null;
      if (!registration || registration.device_hash !== deviceHash || now - registration.updated_at >= REGISTRATION_TTL_MS) return fail(404, "notification_registration_missing");
      pruneNotificationCategories(this.ctx.storage);
      if (redoRequests) this.ctx.storage.sql.exec("INSERT OR REPLACE INTO notification_categories VALUES (?,?)", epoch, JSON.stringify({ schema_version: 1, redo_requests: true, updated_at: now }));
      else this.ctx.storage.sql.exec("DELETE FROM notification_categories WHERE binding_epoch=?", epoch);
      return ok({ schema_version: 1 as const, binding_epoch: epoch, redo_requests: redoRequests });
    });
  }
  /** Binding only. The router never accepts caller-authored notification events. */
  async deliverTurnNotification(hint: RoomHint): Promise<DeliveryResult> {
    if (!validRoomHint(hint)) return { delivered: true };
    const redo = hint.kind === "redo_requested";
    const identity = this.identity(); if (!identity || identity.state !== "active") return { delivered: true };
    const link = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", hint.room_id).toArray()[0];
    if (!link || roomLinkVersion(JSON.parse(link.data)) !== (hint.room_family === "legacy" ? 1 : 2)) return { delivered: true };
    this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE json_extract(data,'$.device_hash')!=? OR json_extract(data,'$.updated_at')<?", identity.device_hash, Date.now() - REGISTRATION_TTL_MS);
    pruneNotificationCategories(this.ctx.storage);
    // Redo requests go only to registrations that opted in; older clients never do.
    const rows = this.ctx.storage.sql.exec<{ binding_epoch: string; data: string }>(redo ? "SELECT r.binding_epoch AS binding_epoch,r.data AS data FROM notification_registrations r JOIN notification_categories c ON c.binding_epoch=r.binding_epoch LIMIT 5" : "SELECT binding_epoch,data FROM notification_registrations LIMIT 5").toArray();
    if (rows.length > MAX_REGISTRATIONS) return { delivered: false };
    // An iOS alert shows without app code, so the turn opt-out is applied here (flag on only).
    const allowed = rows.filter(row => pushCategoryAllowed(this.env, JSON.parse(row.data) as { platform?: string; categories?: string }, hint.kind));
    const outcomes = await Promise.all(allowed.map(async (row): Promise<SendResult> => {
      const registration = JSON.parse(row.data) as { token: string; device_hash: string; platform?: string };
      const pushKey = `room:${hint.event_id}:${row.binding_epoch}:${registration.token}`;
      if (this.pushFinished(pushKey)) return { status: "sent" };
      const current = () => this.authorize(registration.device_hash) && this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations WHERE binding_epoch=?", row.binding_epoch).toArray()[0]?.data === row.data &&
        this.ctx.storage.sql.exec("SELECT room_id FROM rooms WHERE room_id=?", hint.room_id).toArray().length === 1 &&
        (!redo || this.ctx.storage.sql.exec("SELECT binding_epoch FROM notification_categories WHERE binding_epoch=?", row.binding_epoch).toArray().length === 1);
      const eligible = async () => {
        if (!current()) return false;
        // Another member may have deleted the room while our OAuth request ran;
        // their partner's stale room link is not sufficient membership authority.
        const pending = hint.room_family === "legacy" ? await this.env.ROOMS.getByName(hint.room_id).notificationEligible(identity.player_id, hint) : await this.env.ROOMS_V2.getByName(hint.room_id).notificationEligible(identity.player_id, hint);
        if (!pending || !current()) return false;
        const members = hint.room_family === "legacy" ? await this.env.ROOMS.getByName(hint.room_id).safetyMembers(identity.player_id) : await this.env.ROOMS_V2.getByName(hint.room_id).safetyMembers(identity.player_id);
        return members.ok && !await interactionBlocked(this.env, members.value.host_id, members.value.guest_id) && current();
      };
      const sent = await this.notificationSender.send(registration.token, row.binding_epoch, hint, eligible, registration.platform === "ios" ? "ios" : "android");
      if (sent.status === "invalid_token" && current()) this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE binding_epoch=? AND data=?", row.binding_epoch, row.data);
      this.finishPush(pushKey, sent);
      return sent;
    }));
    return { delivered: outcomes.every(value => value.status === "sent" || value.status === "invalid_token" || value.status === "rejected" || value.status === "cancelled"), retry_after_ms: Math.max(0, ...outcomes.map(value => value.retry_after_ms ?? 0)) };
  }
  recover(recoveryHash: string, nextDeviceHash: string, nextRecoveryHash: string, requestHash: string): Outcome<{ player_id: string; recovered: true }> {
    const identity = this.identity();
    if (!identity || identity.state !== "active") return fail(401, "invalid_recovery");
    const receipt = identity.recovery_receipt;
    if (receipt && equalHash(receipt.previous_recovery_hash, recoveryHash)) {
      // The client secured the proposed secrets before its first request. A lost
      // acknowledgement may be retried, but a different proposal cannot reuse
      // the consumed recovery code. Only the current rotation has a receipt.
      if (!equalHash(receipt.request_hash, requestHash) || !equalHash(identity.device_hash, nextDeviceHash) || !equalHash(identity.recovery_hash, nextRecoveryHash)) return fail(409, "recovery_request_mismatch");
      return ok({ player_id: identity.player_id, recovered: true });
    }
    if (!equalHash(identity.recovery_hash, recoveryHash)) return fail(401, "invalid_recovery");
    if (equalHash(nextDeviceHash, nextRecoveryHash) || equalHash(nextDeviceHash, identity.device_hash) || equalHash(nextRecoveryHash, identity.device_hash) || equalHash(nextDeviceHash, recoveryHash) || equalHash(nextRecoveryHash, recoveryHash)) return fail(400, "invalid_rotation");
    identity.device_hash = nextDeviceHash; identity.recovery_hash = nextRecoveryHash;
    if (identity.social) { identity.social.shared_room = null; identity.social.next_refresh_at = 0; }
    identity.recovery_receipt = { previous_recovery_hash: recoveryHash, request_hash: requestHash };
    // One SQLite write atomically commits both credential hashes and the receipt.
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
      clearRegistrations(this.ctx.storage);
      clearPresence(this.ctx.storage);
    });
    closeLiveSockets(this.ctx);
    return ok({ player_id: identity.player_id, recovered: true });
  }
  /**
   * Binding only: a verified platform games link (platform-routes.ts) stands in for the recovery code.
   * Same rotation and receipt as recover(): the device proposed both next secrets, and a lost reply
   * may be retried with the same proposal, which answers the same without rotating again.
   */
  restoreLinked(nextDeviceHash: string, nextRecoveryHash: string, requestHash: string): Outcome<{ player_id: string; restored: true }> {
    const identity = this.identity();
    if (!identity) return fail(404, "identity_absent");
    if (identity.state !== "active") return fail(404, "platform_link_not_found");
    const receipt = identity.recovery_receipt;
    if (receipt && equalHash(receipt.request_hash, requestHash) && equalHash(identity.device_hash, nextDeviceHash) && equalHash(identity.recovery_hash, nextRecoveryHash)) return ok({ player_id: identity.player_id, restored: true });
    if (equalHash(nextDeviceHash, nextRecoveryHash) || equalHash(nextDeviceHash, identity.device_hash) || equalHash(nextRecoveryHash, identity.device_hash) || equalHash(nextDeviceHash, identity.recovery_hash) || equalHash(nextRecoveryHash, identity.recovery_hash)) return fail(400, "invalid_rotation");
    const previous = identity.recovery_hash;
    identity.device_hash = nextDeviceHash; identity.recovery_hash = nextRecoveryHash;
    if (identity.social) { identity.social.shared_room = null; identity.social.next_refresh_at = 0; }
    identity.recovery_receipt = { previous_recovery_hash: previous, request_hash: requestHash };
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
      clearRegistrations(this.ctx.storage);
      clearPresence(this.ctx.storage);
    });
    closeLiveSockets(this.ctx);
    return ok({ player_id: identity.player_id, restored: true });
  }
  reserveRoom(key: string, link: RoomLink, settled: readonly string[] = []): Outcome<RoomLink> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    if (!validRoomLink(link)) return fail(400, "invalid_room_link");
    const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM creations WHERE request_key=?", key).toArray()[0];
    if (old) {
      const data: unknown = JSON.parse(old.data);
      const intent = readCreation(data);
      if (intent && !validRoomLink(data)) return roomLinkVersion(link) !== 2 ? fail(409, "idempotency_version_mismatch") : sameChapter(intent.chapter, RELAY_KEY) ? ok(intent.link) : fail(409, "idempotency_chapter_mismatch");
      if (!validRoomLink(data)) return fail(409, "unsupported_creation_intent");
      const previous = data;
      return roomLinkVersion(previous) === roomLinkVersion(link) ? ok(previous) : fail(409, "idempotency_version_mismatch");
    }
    const existing = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", link.room_id).toArray()[0];
    if (existing && roomLinkVersion(JSON.parse(existing.data) as RoomLink) !== roomLinkVersion(link)) return fail(409, "room_version_conflict");
    if (this.roomsFull(settled)) return fail(409, "room_limit_reached");
    try { this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("INSERT INTO creations VALUES (?,?)", key, JSON.stringify(link));
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link));
      pruneCreationHistory(this.ctx.storage);
    }); } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
    return ok(link);
  }
  /** Read a retained creation before checking access for a genuinely new room. */
  chapterCreation(key: string, chapter: ChapterKey, simulationVersion?: number): Outcome<ChapterCreation | null> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM creations WHERE request_key=?", key).toArray()[0];
    if (old) {
      const data: unknown = JSON.parse(old.data), previous = readCreation(data);
      if (!previous) return validRoomLink(data) ? fail(409, "idempotency_version_mismatch") : fail(409, "unsupported_creation_intent");
      if (!sameChapter(previous.chapter, chapter)) return fail(409, "idempotency_chapter_mismatch");
      return previous.simulation_version === simulationVersion ? ok(previous) : fail(409, "idempotency_simulation_mismatch");
    }
    return ok(null);
  }
  reserveChapterRoom(key: string, link: RoomLink, chapter: ChapterKey, simulationVersion?: number, settled: readonly string[] = []): Outcome<ChapterCreation> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    const proposed: ChapterCreation = { creation_schema: 1, link, chapter, ...(simulationVersion === undefined ? {} : { simulation_version: simulationVersion }) };
    if (!validChapterCreation(proposed)) return fail(400, "invalid_chapter_creation");
    const previous = this.chapterCreation(key, chapter, simulationVersion);
    if (!previous.ok) return previous;
    if (previous.value) return ok(previous.value);
    const existing = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", link.room_id).toArray()[0];
    if (existing && roomLinkVersion(JSON.parse(existing.data) as RoomLink) !== 2) return fail(409, "room_version_conflict");
    if (this.roomsFull(settled)) return fail(409, "room_limit_reached");
    try { this.ctx.storage.transactionSync(() => {
      // Persist the complete variable creation intent and ordinary room link in
      // the same transaction before the router initializes the other object.
      // Raw v2 links already have one complete implicit intent: frozen Relay2.
      // Keep that older shape while the new chapter is disabled or unselected.
      this.ctx.storage.sql.exec("INSERT INTO creations VALUES (?,?)", key, JSON.stringify(sameChapter(chapter, RELAY_KEY) && simulationVersion === undefined ? link : proposed));
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link));
      pruneCreationHistory(this.ctx.storage);
    }); } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
    return ok(proposed);
  }
  // Binding-only api3 lifecycle reservations; public routing remains disabled.
  campaignCreation(key: string, campaignKey: unknown, deviceHash: string) { return readCampaignCreation(this.ctx.storage, this.identity()?.player_id ?? "", key, campaignKey, deviceHash); }
  reserveCampaignRoom(key: string, intent: unknown, deviceHash: string) { return reserveCampaignCreation(this.ctx.storage, this.identity()?.player_id ?? "", key, intent, deviceHash); }
  reserveCampaignGuest(roomId: string, deviceHash: string) { return reserveCampaignGuestLink(this.ctx.storage, this.identity()?.player_id ?? "", roomId, deviceHash); }
  reserveCampaignJoin(value: unknown, deviceHash: string) { return reserveCampaignJoin(this.ctx.storage, this.identity()?.player_id ?? "", value, deviceHash); }
  campaignJoinAttempt(value: unknown, deviceHash: string) { return readCampaignJoin(this.ctx.storage, this.identity()?.player_id ?? "", value, deviceHash); }
  campaignLink(roomId: string, deviceHash: string) { return readCampaignLink(this.ctx.storage, this.identity()?.player_id ?? "", roomId, deviceHash); }
  cancelUnreservedCampaignJoin(value: unknown, deviceHash: string) { return cancelUnreservedCampaignJoin(this.ctx.storage, this.identity()?.player_id ?? "", value, deviceHash); }
  cancelCampaignCreation(value: unknown, deviceHash: string) { return cancelCampaignCreation(this.ctx.storage, this.identity()?.player_id ?? "", value, deviceHash); }
  finalizeCampaignJoinCancellation(value: unknown, acknowledged: unknown, deviceHash: string) { return finalizeCampaignJoinCancellation(this.ctx.storage, this.identity()?.player_id ?? "", value, acknowledged, deviceHash); }
  campaignIdentityDeletionScope(link: RoomLink, deviceHash: string) { return campaignIdentityDeletionScope(this.ctx.storage, this.identity()?.player_id ?? "", link, deviceHash); }
  finalizeCampaignIdentityDeletion(scope: unknown, evidence: unknown, deviceHash: string) { return finalizeCampaignIdentityDeletion(this.ctx.storage, this.identity()?.player_id ?? "", scope, evidence, deviceHash); }
  campaignTerminalScope(rootId: string, deviceHash: string) { return campaignTerminalScope(this.ctx.storage, this.identity()?.player_id ?? "", rootId, deviceHash); }
  campaignTerminalAdmissionScope(value: unknown, deviceHash: string) { return campaignTerminalAdmissionScope(this.ctx.storage, this.identity()?.player_id ?? "", value, deviceHash); }
  finalizeCampaignTerminalAdmission(scope: unknown, evidence: unknown, deviceHash: string) { return finalizeCampaignTerminalAdmission(this.ctx.storage, this.identity()?.player_id ?? "", scope, evidence, deviceHash); }
  finalizeCampaignTerminalLink(scope: unknown, evidence: unknown, deviceHash: string) { return finalizeCampaignTerminalLink(this.ctx.storage, this.identity()?.player_id ?? "", scope, evidence, deviceHash); }
  // Binding-only operator Story drain (v2/campaign-drain.ts). The first two only read. The terminal-link
  // pair runs the same functions as above for an active identity, with its own stored device hash;
  // an identity being deleted is left to identity deletion.
  campaignDrainInventory() { return campaignPlayerInventory(this.ctx.storage); }
  operatorCampaignAllocation(roomId: string) { return campaignPlayerAllocation(this.ctx.storage, roomId); }
  private operatorIdentity(): Outcome<Identity> {
    const identity = this.identity();
    if (!identity) return fail(404, "identity_absent");
    return identity.state === "active" ? ok(identity) : fail(409, "identity_deleting");
  }
  operatorCampaignTerminalScope(rootId: string) {
    const identity = this.operatorIdentity(); if (!identity.ok) return identity;
    return campaignTerminalScope(this.ctx.storage, identity.value.player_id, rootId, identity.value.device_hash);
  }
  operatorFinalizeCampaignTerminalLink(scope: unknown, evidence: unknown) {
    const identity = this.operatorIdentity(); if (!identity.ok) return identity;
    return finalizeCampaignTerminalLink(this.ctx.storage, identity.value.player_id, scope, evidence, identity.value.device_hash);
  }
  addRoom(link: RoomLink, settled: readonly string[] = []): Outcome<RoomLink> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    if (!validRoomLink(link)) return fail(400, "invalid_room_link");
    const existing = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", link.room_id).toArray()[0];
    if (existing && roomLinkVersion(JSON.parse(existing.data) as RoomLink) !== roomLinkVersion(link)) return fail(409, "room_version_conflict");
    if (!existing && this.roomsFull(settled)) return fail(409, "room_limit_reached");
    this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link));
    return ok(link);
  }
  /**
   * `settled` comes from the router's reserveWithinRoomLimit (room-limit.ts).
   * With the room index on, rows the index holds as finished, closed or
   * unavailable are settled too, and the bound may rise (roomLinkBound).
   */
  private roomsFull(settled: readonly string[]): boolean {
    const linked = this.ctx.storage.sql.exec<{ room_id: string }>("SELECT room_id FROM rooms").toArray().map(row => row.room_id);
    if (!flags.roomIndex(this.env)) return roomLimitReached(linked, settled);
    const index = roomIndexCount(this.ctx.storage);
    return roomLimitReached(linked, [...settled, ...index.settled], roomLinkBound(true, index.unindexed === 0));
  }
  listRooms(): RoomLink[] {
    return this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms ORDER BY rowid DESC").toArray().map(row => JSON.parse(row.data) as RoomLink);
  }
  removeRoom(roomId: string, expectedVersion = 1): void {
    const existing = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", roomId).toArray()[0];
    if (existing && roomLinkVersion(JSON.parse(existing.data) as RoomLink) === expectedVersion) {
      this.ctx.storage.sql.exec("DELETE FROM rooms WHERE room_id=?", roomId);
      removeRoomIndexRow(this.ctx.storage, roomId);
    }
  }
  // Binding-only room index (room-index.ts). The router and the rooms call these; a row never grants access to a room.
  /** A room's push after a change: what it now says about this member. */
  /** While the index is off (an erase still pushes) it only updates a row that already exists. */
  noteRoomIndex(owner: string, roomId: string, version: number, observation: RoomObservation, hint?: LiveHint): void {
    const identity = this.identity();
    if (identity?.state === "active" && identity.player_id === owner) recordRoomObservation(this.ctx.storage, roomId, version, observation, flags.roomIndex(this.env));
    // A live hint that rode on this push (room-index-sync.ts).
    if (hint) this.ctx.waitUntil(this.liveHint(owner, hint).catch(() => false));
  }
  /** The router's live reads from an indexed list; null marks a read that failed. */
  recordRoomIndex(owner: string, observations: { room_id: string; api_version: number; observation: RoomObservation | null }[]): void {
    const identity = this.identity();
    if (identity?.state !== "active" || identity.player_id !== owner) return;
    this.ctx.storage.transactionSync(() => { for (const item of observations) recordRoomObservation(this.ctx.storage, item.room_id, item.api_version, item.observation, true); });
  }
  /** Linked rooms the index holds as finished or gone. */
  roomIndexSettled(): string[] { return roomIndexCount(this.ctx.storage).settled; }
  roomIndexPage(family: RoomFamily, offset: number): RoomIndexPage { return roomIndexPage(this.ctx.storage, family, offset); }
  /** v1 and v2 links the index cannot vouch for as settled, for a refused reservation to read. */
  roomIndexUnsettled(limit: number): RoomLink[] { return roomIndexUnsettled(this.ctx.storage, limit); }
  beginDelete(supportedVersions: number[] = [1], deviceHash?: string): Outcome<RoomLink[]> {
    // Public deletion carries the original request hash across rate limiting
    // and other awaits. Check it in this same synchronous state transition.
    // Omission is reserved for authenticated binding-only maintenance.
    if (deviceHash !== undefined && !this.authorize(deviceHash, true)) return fail(401, "invalid_auth");
    const identity = this.identity();
    if (!identity) return ok([]);
    const links = this.listRooms();
    // Preflight and the state change are synchronous in this object. A newer
    // unsupported link cannot strand an active identity after partial erasure.
    for (const link of links) {
      const version = roomLinkVersion(link);
      if (!supportedVersions.includes(version)) return version === 2 ? fail(503, "room_service_unavailable") : fail(409, "unsupported_room_version");
    }
    identity.state = "deleting";
    if (identity.social) identity.social.shared_room = null;
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
      clearRegistrations(this.ctx.storage);
      clearPresence(this.ctx.storage);
    });
    closeLiveSockets(this.ctx);
    // Above one deletion batch, hosted rooms still in play (waiting ones included) go first.
    return ok(links.length > ROOM_DELETION_BATCH ? deletionOrder(this.ctx.storage, links) : links);
  }
  /**
   * Binding only: hands the rest of a started identity deletion to this
   * object's alarm. Presence leases were cleared by beginDelete, so the
   * presence alarm marker goes too and the alarm belongs to the deletion.
   * `failed` are rooms the request could not erase; the next batch takes them last.
   */
  async continueDeletion(failed: string[] = []): Promise<void> {
    if (this.identity()?.state !== "deleting") return;
    const pending = roomErasurePending(this.ctx.storage), next = pending?.next_at ?? Date.now() + roomErasureDelay(0);
    this.ctx.storage.transactionSync(() => {
      writeRoomErasure(this.ctx.storage, { attempts: pending?.attempts ?? 0, next_at: next, failed: [...new Set([...(pending?.failed ?? []), ...failed])] });
      this.ctx.storage.sql.exec("DELETE FROM presence_alarm");
    });
    await this.ctx.storage.setAlarm(next);
  }
  /**
   * One deletion batch: up to ROOM_DELETION_BATCH v1 and v2 links, through the
   * same dispatcher the router uses, past any room that fails. Hosted rooms
   * still in play go first (deletionOrder); rooms that failed last time go to
   * the back, so they can never hold up the rest. When
   * no link is left it finishes the deletion as the router would. It never
   * throws; while links remain it runs again a second later, or with a
   * doubling delay up to an hour while rooms keep failing, with no attempt
   * limit. Only v3 links left (they need the request's device hash) end it,
   * and a client retry takes them.
   */
  private async continueRoomErasure(): Promise<void> {
    const storage = this.ctx.storage, pending = roomErasurePending(storage)!;
    const failed: string[] = [];
    let problem: string | null = null;
    try {
      const identity = this.identity();
      if (identity?.state !== "deleting") { clearRoomErasure(storage); return; }
      const dispatcher = roomDeletionDispatcher(this.env.ROOMS, (link, id) => this.env.ROOMS_V2.getByName(link.room_id).eraseForPlayer(id, link.host));
      const before = new Set(pending.failed);
      const rooms = deletionOrder(storage, this.listRooms().filter(link => roomLinkVersion(link) === 1 || roomLinkVersion(link) === 2));
      const batch = [...rooms.filter(link => !before.has(link.room_id)), ...rooms.filter(link => before.has(link.room_id))].slice(0, ROOM_DELETION_BATCH);
      const erased = await eraseRoomLinks(identity.player_id, batch, this, dispatcher, false, failed);
      if (!erased.ok) problem = erased.code;
      const remaining = this.listRooms();
      if (remaining.length === 0) {
        const finished = await this.finishDelete();
        if (finished.ok || finished.code === "provider_deletion_pending") { clearRoomErasure(storage); return; }
        problem = finished.code;
      } else if (!remaining.some(link => roomLinkVersion(link) === 1 || roomLinkVersion(link) === 2)) { clearRoomErasure(storage); return; }
    } catch (error) { problem = errorCode(error); }
    if (!roomErasurePending(storage) || this.identity()?.state !== "deleting") return;
    const attempts = problem === null ? 0 : pending.attempts + 1, next = Date.now() + roomErasureDelay(attempts);
    if (problem !== null) logWarning("room_erasure_batch_failed", { reason: problem, attempts, rooms_failed: failed.length });
    writeRoomErasure(storage, { attempts, next_at: next, failed });
    await storage.setAlarm(next);
  }
  /** Binding only: whether this deviceHash belongs to this owner's identity while its deletion is still running. */
  deletingWith(owner: string, deviceHash: string): boolean {
    const identity = this.identity();
    return identity?.state === "deleting" && identity.player_id === owner && equalHash(identity.device_hash, deviceHash);
  }
  deletionInProgress(owner: string): boolean { const identity = this.identity(); return identity?.state === "deleting" && identity.player_id === owner; }
  safetyIdentityActive(owner: string): boolean { const identity = this.identity(); return identity?.state === "active" && identity.player_id === owner; }
  async finishDelete(): Promise<Outcome<{ deleted: true }>> {
    if (this.identity()?.state !== "deleting" || this.listRooms().length !== 0) return fail(409, "deletion_not_ready");
    const identity = this.identity()!;
    if (!await this.env.SAFETY_PROFILES.getByName(identity.player_id).ensureErasure(identity.player_id, identity.device_hash, this.ctx.id.toString())) return fail(503, "provider_deletion_pending");
    return this.finalizeErasure(identity.player_id, identity.device_hash);
  }
  /** Binding only: erasure alarm completes an already authorized deletion. */
  async finalizeErasure(owner: string, deviceHash: string): Promise<Outcome<{ deleted: true }>> {
    const identity = this.identity();
    if (!identity) { await this.env.SAFETY_PROFILES.getByName(owner).markErasureComplete(owner); return ok({ deleted: true }); }
    if (identity.player_id !== owner || identity.state !== "deleting" || !equalHash(identity.device_hash, deviceHash) || this.listRooms().length !== 0) return fail(409, "deletion_not_ready");
    for (const link of this.social(identity).links) {
      await this.env.PLAYERS.getByName(link.player_id).friendForget(link.player_id, owner, link.request_id);
      await this.env.FRIEND_ROOM_EVENTS.getByName(link.player_id).revoke(owner);
      await this.env.FRIEND_ROOM_EVENTS.getByName(owner).revoke(link.player_id);
    }
    await this.env.FRIEND_ROOM_EVENTS.getByName(owner).clearRecipient(owner);
    await this.env.PHOTO_TRANSFERS.getByName(owner).eraseOwner(owner, this.ctx.id.toString());
    if (!(await this.env.SAFETY_INBOX.getByName("moderation-v1").eraseReporter(owner)).ok) return fail(503, "safety_cleanup_unavailable");
    // Platform games links (Play Games, Game Center) for this player; a repeat deletes nothing.
    await this.env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT).eraseOwner(owner);
    await this.env.SAFETY_PROFILES.getByName(owner).eraseOwner(owner);
    if (this.identity()?.state !== "deleting" || this.listRooms().length !== 0) return fail(409, "deletion_not_ready");
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM identity");
      this.ctx.storage.sql.exec("DELETE FROM rooms");
      this.ctx.storage.sql.exec("DELETE FROM creations");
      this.ctx.storage.sql.exec("DELETE FROM friend_room_publication");
      this.ctx.storage.sql.exec("DELETE FROM friend_room_publication_ops");
      this.ctx.storage.sql.exec("DELETE FROM friend_room_subscriptions");
      clearRegistrations(this.ctx.storage);
      clearPresence(this.ctx.storage);
      dropRoomIndex(this.ctx.storage);
      dropWallet(this.ctx.storage);
    });
    await this.env.SAFETY_PROFILES.getByName(owner).markErasureComplete(owner);
    return ok({ deleted: true });
  }
}

// A Player nobody created answers the identity check as one without an identity row, and stores nothing.
answerWhileBlank(Player, { authorize: () => false, authorizeRoom: () => ({ authorized: false, linked: false }), rotateSafetyToken: () => undefined,
  authorizeNamed: () => ({ authorized: false, linked: true }), authorizeWallet: () => ({ authorized: false, linked: true }),
  creditTurn: async () => fail(404, "identity_absent"), creditTogetherClear: () => fail(404, "identity_absent"), creditSoloClear: () => fail(404, "identity_absent"), setDisplayName: () => fail(401, "invalid_auth"), operatorClearDisplayName: () => fail(404, "identity_absent"), publicDisplayName: () => null,
  campaignDrainInventory: () => blankPlayerInventory(), operatorCampaignAllocation: () => null,
  operatorCampaignTerminalScope: async () => fail(404, "identity_absent"), operatorFinalizeCampaignTerminalLink: async () => fail(404, "identity_absent"),
  deletingWith: () => false, noteRoomIndex: () => undefined, leaderboardStanding: () => null,
  // A link that outlived its player: the restore route drops it.
  restoreLinked: () => fail(404, "identity_absent"), recoveryMatches: () => false,
  // No identity, so no socket: a hint is dropped and an upgrade (unreachable past auth()) is refused.
  liveHint: async () => false, fetch: () => liveUnauthorized() });
