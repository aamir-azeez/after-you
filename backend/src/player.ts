import { creditDuelWin, creditGhostWin, duelRoomPay, type DuelRoomPay, type DuelWin, type DuelWinAnswer, type GhostWin } from "./pollen/duel-pay";
import { DurableObject } from "cloudflare:workers";
import { playerStanding, type Standing } from "./leaderboards/standing";
import { answerWhileBlank, openLazyStorage } from "./lazy-storage";
import { flags } from "./flags";
import { ApiError, ID_PATTERN, equalHash, fail, isObject, ok, randomToken, type Outcome } from "./protocol";
import { pruneCreationHistory, readCampaignCreation, reserveCampaignCreation, reserveCampaignGuestLink, reserveCampaignJoin, readCampaignJoin, readCampaignLink, cancelUnreservedCampaignJoin, cancelCampaignCreation, finalizeCampaignJoinCancellation } from "./v2/campaign-player";
import { campaignIdentityDeletionScope, finalizeCampaignIdentityDeletion, campaignTerminalScope, finalizeCampaignTerminalLink, campaignTerminalAdmissionScope, finalizeCampaignTerminalAdmission } from "./v2/campaign-player";
import { emptySocial, FRIEND_REFRESH_SECONDS, FRIEND_REQUEST_TTL_MS, MAX_FRIENDS, MAX_INCOMING_REQUESTS, validSocial, validSharedFriendRoom, type FriendEdge, type FriendLink, type SharedFriendRoom, type SocialState } from "./friends";
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
import { BINDING_PATTERN, FcmSender, MAX_REGISTRATIONS, REGISTRATION_TTL_MS, makeFriendRoomHint, notificationsConfigured, validRoomHint, validNotificationToken, type IosRegistration, type RoomHint, type SendResult } from "./notifications";
import { pushPhones, sendToPhones, type FinishedPushes } from "./notification-phones";
import { clearRegistrations, initializeNotifications, pruneNotificationCategories, type DeliveryResult } from "./notification-storage";
import { checkedFriendPublication, checkedFriendSubscription, FRIEND_PUBLICATION_OPS_TABLE, FRIEND_PUBLICATION_TABLE, FRIEND_SUBSCRIPTIONS_TABLE, MAX_FRIEND_SUBSCRIPTIONS, MAX_PUBLICATION_RECEIPTS, PUBLICATION_ID_PATTERN, type FriendPublication, type FriendSubscription } from "./friend-room-event-storage";
import { FRIEND_EVENTS_CLIENT_GATE, FRIEND_ROOM_PUSH_WINDOW_MS, type FriendRoomDelivery, type FriendRoomEvent } from "./friend-room-events";
import { interactionBlocked } from "./safety";
import { testerReceipt, validTesterGrant, type TesterGrant, type TesterAccess } from "./tester-access";
import { entitlementFresh, type EntitlementMemo } from "./entitlement";
import { MemoryBudget } from "./limits";
import { switchApplies } from "./test-codes";
import { clearPresence, initializePresence, MAX_PRESENCE_SESSIONS, PRESENCE_EXTEND_WITHIN_MS, PRESENCE_SESSION, PRESENCE_TTL_MS, presenceChangeBudget, presenceAlarmOwned, presencePolicy, prunePresence, schedulePresence, type PresencePolicy } from "./presence";
import { applyDisplayName, clearDisplayNameFields, MAX_CLEARED_ROOMS, type DisplayNameFields, type DisplayNameOutcome } from "./display-names";
import { creditClear, creditSoloClear, creditTurn, dropWallet, fullJourneyUntil, historyView, noteFullJourney, payFromWallet, walletBalance, walletView, type HistoryView, type PollenReceipt, type WalletView } from "./pollen/wallet";
import { addDroppedItem, dropWardrobe, equip, noteBoardRewards, ownedItemIds, ownedPackIds, spend, wardrobeView, wornLook, type EquipReceipt, type OpKey, type OwnedView, type SpendReceipt, type WardrobeView } from "./pollen/wardrobe";
import { dropEarned, validEarnedItems } from "./pollen/earned";
import { anyBundlesOn, grantAlarmOn, grantOn, itemDropsOn, refundsOn, sandboxAppStoreOn, type WardrobeMode } from "./pollen/features";
import { knownBoard } from "./leaderboards/boards";
import { dropGrant, grantView, settleGrant, storedGrant, type GrantOutcome, type GrantView } from "./pollen/grant-settle";
import { grantAlarmAt, grantWake } from "./pollen/grant-alarm";
import { sendPollenPush } from "./pollen/grant-push";
import { grantDue, type GrantHint } from "./pollen/grant";
import { readGrant } from "./pollen/grant-provider";
import { claimBundlesFor, claimFor } from "./pollen/claims";
import { bundleCheckDue, bundlesView, dropBundles, pacedClaim, settleBundles, type BundleReply, type BundlesView } from "./pollen/bundle-settle";
import { SANDBOX, lookupBundles, readBundles, sandboxBundles, type BundleAsk } from "./pollen/bundle-provider";
import { RATES } from "./pollen/rates";
import { countNameSet, namePrice, nextNamePrice, nextNamePriceAfter } from "./pollen/name-price";
import type { Look } from "./pollen/catalog";
import type { SpendRequest } from "./pollen/spend";
import { LIVE_FRIENDS_REFRESH_SECONDS, acceptLiveSocket, liveUnauthorized, closeLiveSockets, liveClosed, liveMessage, liveMessageReceived, liveSockets, sendLive, setLiveAutoResponse, validLiveHint, type LiveHint } from "./live";

type RecoveryReceipt = { previous_recovery_hash: string; request_hash: string };
/** `full_journey_off`: a tester's own switch (test-codes.ts): treated as without Full Journey until switched back. Absent otherwise. */
type Identity = { player_id: string; device_hash: string; recovery_hash: string; state: "active" | "deleting"; created_at: string; tester_grant?: TesterGrant; full_journey_off?: true; recovery_receipt?: RecoveryReceipt; social?: SocialState } & DisplayNameFields;
type FriendPublicationState = { schema_version: 1; epoch_counter: number; current: FriendPublication | null };
function isPublicationState(value: unknown): value is FriendPublicationState {
  return isObject(value) && Object.keys(value).length === 3 && value.schema_version === 1 && Number.isSafeInteger(value.epoch_counter) && Number(value.epoch_counter) >= 0 &&
    (value.current === null || checkedFriendPublication(JSON.stringify(value.current)) !== null && (value.current as FriendPublication).publication_epoch <= Number(value.epoch_counter));
}
/** A publication id repeated within this long (a lost reply's retry) fans out again; later it reaches nobody again. */
const PUBLICATION_RETRY_MS = 120_000;
/** New hosted rooms an hour whose publication reaches friends' inboxes; more show on their lists only. */
const MAX_FRESH_PUBLICATIONS_PER_HOUR = 12;
/** A registration the phone repeats unchanged is written again only this long after the last write (its age counts toward REGISTRATION_TTL_MS). */
const REGISTRATION_REFRESH_MS = 86_400_000;
/** The oldest pending request a list holds from someone else, the one a new request takes the place of; null when there is none. */
function oldestIncoming(links: readonly FriendLink[]): FriendLink | null {
  return links.filter(link => !link.accepted && link.requested_by === link.player_id).reduce<FriendLink | null>((oldest, link) => oldest === null || link.created_at < oldest.created_at ? link : oldest, null);
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
  /** The finished-push memory as the shared phone loop (notification-phones.ts) reads it. */
  private readonly pushMemory: FinishedPushes = { finished: key => this.pushFinished(key), finish: (key, sent) => this.finishPush(key, sent) };
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
    // A duel hint names only a duel this player is in (duels/news.ts); the duel reads check that again. Writes nothing.
    if (hint.kind === "duels") return sendLive(liveSockets(this.ctx, identity.device_hash), liveMessage(hint)) > 0;
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
   * A friend change made in this object for this player. `accepted`: a link
   * just became a friendship (this player accepted, or a request they sent was
   * accepted). Otherwise a request arrived, was cancelled or a friend was
   * removed, which opens no early read on the phone.
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
  authorizeNamed(deviceHash: string, pollen = false, looks = false): { authorized: boolean; linked: boolean; display_name?: string | null; fj_until?: number; look?: Look } {
    const identity = this.authorized(deviceHash);
    return identity ? { authorized: true, linked: true, display_name: identity.display_name ?? null, ...(pollen ? { fj_until: this.roomFullJourneyUntil(identity) } : {}), ...this.lookField(looks) } : { authorized: false, linked: true };
  }
  /** The Full Journey end a room copies for its boost: none while the tester switch has this player as without Full Journey. */
  private roomFullJourneyUntil(identity: Identity): number {
    return identity.full_journey_off === true && switchApplies(this.env, identity.player_id) ? 0 : fullJourneyUntil(this.ctx.storage);
  }
  /** `look`: the look the player wears (pollen/wardrobe.ts), only for routes that write it into a room while looks are on. */
  private lookField(looks: boolean): { look?: Look } {
    return looks ? { look: wornLook(this.ctx.storage) } : {};
  }
  /**
   * authorize() for a request that names a room, plus whether this player may reach that room:
   * it holds a link to it, or has Story rows (see storyHeld).
   * An authorized answer also carries the player's current safety token (see v2/block-memo.ts), and with
   * `pollen` (a turn while Pollen earning is on) the player's Full Journey end. With `packs` (a turn from
   * a phone that sends pack faces) also the reaction packs the player owns, for v2/face-packs.ts.
   */
  authorizeRoom(deviceHash: string, roomId: string, pollen = false, looks = false, packs = false): { authorized: boolean; linked: boolean; safety_token?: string; display_name?: string | null; fj_until?: number; look?: Look; face_packs?: string[] } {
    const identity = this.authorized(deviceHash);
    if (!identity) return { authorized: false, linked: false };
    const linked = this.ctx.storage.sql.exec("SELECT 1 FROM rooms WHERE room_id=?", roomId).toArray().length > 0 || this.storyHeld();
    return { authorized: true, linked, safety_token: this.safetyToken, display_name: identity.display_name ?? null, ...(pollen ? { fj_until: this.roomFullJourneyUntil(identity) } : {}), ...this.lookField(looks),
      ...(packs ? { face_packs: ownedPackIds(this.ctx.storage) } : {}) };
  }
  /**
   * authorize() plus the wallet or its history (GET /v1/pollen and /v1/pollen/history), from one call.
   * While the wardrobe is on (`mode`) the wallet also carries it; while the shop is on, with what is sold, the next name change price and the price of the change after it.
   * While the grant is on, the wallet read first pays any monthly instalment that is due (pollen/grant-settle.ts)
   * and carries the player's `grant` ladder once they have one. `hint`: what the phone said about Full Journey
   * (pollen/routes.ts grantHint), which may start a subscriber's first read.
   */
  /** "Just bought Full Journey" wallet hints that may start a RevenueCat read (pollen/grant.ts BOUGHT_GAP_MS): at most 3 a day; later ones count as "held". Memory only. */
  private readonly boughtHints = new MemoryBudget(3, 86_400_000);
  /** The hint a wallet read settles with: "bought" counts against boughtHints only when it alone would start a read. */
  private boughtHint(hint: GrantHint, now: number): GrantHint {
    if (hint !== "bought") return hint;
    try {
      const state = storedGrant(this.ctx.storage), until = fullJourneyUntil(this.ctx.storage);
      if (grantDue(state, until, now, "bought") && !grantDue(state, until, now, "held") && !this.boughtHints.take(now)) return "held";
    } catch { /* the settle reports a malformed grant itself */ }
    return hint;
  }
  async authorizeWallet(deviceHash: string, view: "wallet" | "history", mode: WardrobeMode = "off", hint: GrantHint = "none"): Promise<{ authorized: boolean; linked: boolean; pollen?: WalletView | HistoryView | (WalletView & { grant?: GrantView }) | (WalletView & { grant?: GrantView; wardrobe: OwnedView }) | (WalletView & { grant?: GrantView; wardrobe: WardrobeView; name_price: number; name_price_next: number; bundles?: BundlesView }) }> {
    const identity = this.authorized(deviceHash);
    if (!identity) return { authorized: false, linked: true };
    if (view === "history") return { authorized: true, linked: true, pollen: historyView(this.ctx.storage, Date.now()) };
    const grant = grantOn(this.env), refunds = refundsOn(this.env), bundles = mode === "shop" && anyBundlesOn(this.env);
    if (grant) {
      const said = this.boughtHint(hint, Date.now());
      // A read that saved the grant also sets its alarm to the next instalment (pollen/grant-alarm.ts).
      if (await this.settleGrant(identity.player_id, said) === "settled" || grantAlarmOn(this.env) && this.grantAlarmMissing()) await this.armGrantAlarm();
      // A recovery may have replaced the device while the provider answered.
      if (!this.authorized(deviceHash)) return { authorized: false, linked: true };
    }
    // At most once a day, for a player who bought a bundle: refunds are taken back (and a purchase never claimed is paid).
    if (refunds && bundleCheckDue(this.ctx.storage, Date.now())) {
      await this.checkBundles(identity.player_id);
      if (!this.authorized(deviceHash)) return { authorized: false, linked: true };
    }
    const now = Date.now(), wallet = walletView(this.ctx.storage, now), ladder = grant ? grantView(this.ctx.storage) : undefined;
    const read = ladder ? { ...wallet, grant: ladder } : wallet;
    if (mode === "off") return { authorized: true, linked: true, pollen: read };
    const wardrobe = wardrobeView(this.ctx.storage, mode === "shop");
    return { authorized: true, linked: true, pollen: mode === "shop" ? { ...read, wardrobe, name_price: nextNamePrice(identity, now), name_price_next: nextNamePriceAfter(identity, now), ...(bundles ? { bundles: bundlesView(this.ctx.storage) } : {}) } : { ...read, wardrobe } };
  }
  /** The daily bundle refund check (pollen/bundle-settle.ts); a failure never stops the wallet read it rides on. */
  private async checkBundles(owner: string): Promise<void> {
    try {
      const outcome = await this.settleBundles(owner, true);
      if (outcome.status === "unavailable") logWarning("pollen_bundle_check_failed", { reason: outcome.reason });
      else if (outcome.status === "settled" && outcome.lookup_failed) logWarning("pollen_bundle_lookup_failed", { reason: outcome.lookup_failed });
    } catch (error) { logWarning("pollen_bundle_check_failed", { reason: errorCode(error) }); }
  }
  /**
   * `daily`: the refund check, which also looks up paid bundles a restore moved off this player's list. While
   * POLLEN_SANDBOX_APP_STORE is on, a claim from an App Store build (`appStore`) with nothing new in production also reads
   * the App Store sandbox list (the review identity and a tester always read it, a tester for Play too). A sandbox line keeps
   * that mark, so the refund check looks it up in sandbox and takes it back when refunded, whatever the flag or the lists say by then.
   */
  private settleBundles(owner: string, daily = false, appStore = false) {
    const now = Date.now(), listed = sandboxBundles(owner, this.env), anyone = sandboxAppStoreOn(this.env) && appStore;
    return settleBundles(this.ctx.storage, now, this.pollenActive(owner), {
      read: () => readBundles(owner, this.env),
      claim: purchases => claimBundlesFor(this.env, owner, purchases, now),
      ...(!daily && anyone && !listed ? { sandbox: () => readBundles(owner, this.env, undefined, SANDBOX) } : {}),
      ...(daily ? { lookup: (asks: BundleAsk[]) => lookupBundles(asks, this.env) } : {})
    });
  }
  /**
   * Binding only: credits the player's Play and App Store bundle purchases that RevenueCat lists, and takes back refunded
   * ones (POST /v1/pollen/bundle-claims, pollen/bundle-settle.ts). The device is checked again here. `appStore`: the
   * claim came from an App Store build. Paced per player (bundle-settle.ts pacedClaim): a claim too soon answers 429.
   */
  async pollenBundleClaim(owner: string, deviceHash: string, appStore = false): Promise<Outcome<BundleReply>> {
    const identity = this.authorized(deviceHash);
    if (!identity || identity.player_id !== owner) return fail(401, "invalid_auth");
    const outcome = await pacedClaim(this.ctx.storage, Date.now(), () => this.settleBundles(owner, false, appStore));
    if (outcome === "busy") return fail(429, "rate_limited");
    if (outcome.status === "unavailable") return fail(503, "pollen_bundles_unavailable");
    if (outcome.status === "absent" || !this.authorized(deviceHash)) return fail(401, "invalid_auth");
    return ok(outcome.reply);
  }
  /**
   * The monthly grant check (pollen/grant-settle.ts); a failure never stops the wallet read or the alarm it rides on.
   * `paid`: told what this settle newly paid (the alarm's push).
   */
  private async settleGrant(owner: string, hint: GrantHint, paid?: (lines: readonly { key: string; amount: number }[]) => void): Promise<GrantOutcome | "failed"> {
    const now = Date.now();
    try {
      return await settleGrant(this.ctx.storage, now, this.pollenActive(owner), {
        read: lifetime => readGrant(owner, this.env, lifetime),
        claim: keys => claimFor(this.env, owner, keys, now),
        ...(paid ? { paid } : {})
      }, hint);
    } catch (error) { logWarning("pollen_grant_failed", { reason: errorCode(error) }); return "failed"; }
  }
  /**
   * The monthly grant's part of the Player's one alarm (presence.ts schedulePresence): the next wake for the
   * stored grant (pollen/grant-alarm.ts), only with POLLEN_GRANT_ALARM and an active identity, else none.
   */
  private grantAlarm(now: number): number | null {
    if (!grantAlarmOn(this.env) || this.identity()?.state !== "active") return null;
    try { return grantAlarmAt(storedGrant(this.ctx.storage), fullJourneyUntil(this.ctx.storage), now); }
    catch (error) { logWarning("pollen_grant_alarm_failed", { reason: errorCode(error) }); return null; }
  }
  /** Sets the one alarm from the presence leases and the grant. The caller holds the transaction and checked the alarm is owned. */
  private scheduleAlarm(): Promise<void> { return schedulePresence(this.ctx.storage, this.grantAlarm(Date.now())); }
  /** After a settle that saved the grant: the alarm moves to its next wake, or stops for a grant with none. Writes only on a change. */
  private async armGrantAlarm(): Promise<void> {
    if (!grantAlarmOn(this.env)) return;
    try {
      await this.ctx.storage.transaction(async () => {
        // An identity deletion owns the alarm until it finishes.
        if (roomErasurePending(this.ctx.storage)) return;
        if (!presenceAlarmOwned(this.ctx.storage, await this.ctx.storage.getAlarm())) throw new Error("unowned_presence_alarm");
        await this.scheduleAlarm();
      });
    } catch (error) { logWarning("pollen_grant_alarm_failed", { reason: errorCode(error) }); }
  }
  /** The player whose grant wake has come, for the alarm to settle; null otherwise (presence wakes the alarm far more often). */
  private grantWakeOwner(): string | null {
    const identity = this.identity();
    if (!grantAlarmOn(this.env) || identity?.state !== "active") return null;
    try { return grantWake(storedGrant(this.ctx.storage), fullJourneyUntil(this.ctx.storage), Date.now())?.run ? identity.player_id : null; }
    catch (error) { logWarning("pollen_grant_alarm_failed", { reason: errorCode(error) }); return null; }
  }
  /**
   * Whether a wallet read that settled nothing should still set the grant's wake: one is due and no alarm the marker
   * names comes at or before it (a subscriber paid before POLLEN_GRANT_ALARM went on, or after older code dropped it).
   * One marker row read; the arming writes only then.
   */
  private grantAlarmMissing(): boolean {
    const wake = this.grantAlarm(Date.now());
    if (wake === null) return false;
    const marker = this.ctx.storage.sql.exec<{ due_at: number }>("SELECT due_at FROM presence_alarm WHERE id=1").toArray()[0]?.due_at ?? null;
    return marker === null || marker > wake;
  }
  /** Prunes presence and sets the one alarm again; the alarm handler's own step, so it accepts the alarm it consumed. */
  private async resetAlarm(): Promise<void> {
    await this.ctx.storage.transaction(async () => {
      const actual = await this.ctx.storage.getAlarm();
      if (!presenceAlarmOwned(this.ctx.storage, actual, true)) throw new Error("unowned_presence_alarm");
      prunePresence(this.ctx.storage); await this.scheduleAlarm();
    });
  }
  /** The monthly Pollen push for what the alarm paid (pollen/grant-push.ts); best effort, never thrown. */
  private async pushPollen(lines: readonly { key: string; amount: number }[]): Promise<void> {
    const identity = this.identity();
    if (!identity || identity.state !== "active") return;
    try {
      await sendPollenPush(this.ctx.storage, this.env, this.notificationSender, identity.device_hash, hash => this.authorize(hash), lines, this.pushMemory);
    } catch (error) { logWarning("pollen_push_failed", { reason: errorCode(error) }); }
  }
  /**
   * Binding only: one purchase (POST /v1/pollen/spend, pollen/wardrobe.ts spend). The device is checked
   * again here, in the call that spends, so a recovery that replaced it can never be spent through.
   */
  pollenSpend(owner: string, deviceHash: string, op: OpKey, request: SpendRequest, expected: number): Outcome<SpendReceipt> {
    const identity = this.authorized(deviceHash);
    if (!identity || identity.player_id !== owner) return fail(401, "invalid_auth");
    return spend(this.ctx.storage, op, request, expected, Date.now(), this.pollenActive(owner));
  }
  /** Binding only: wears a look (POST /v1/pollen/equip, pollen/wardrobe.ts equip). */
  pollenEquip(owner: string, deviceHash: string, op: OpKey, look: unknown, revision: number): Outcome<EquipReceipt> {
    const identity = this.authorized(deviceHash);
    if (!identity || identity.player_id !== owner) return fail(401, "invalid_auth");
    return equip(this.ctx.storage, op, look, revision, Date.now(), this.pollenActive(owner));
  }
  /**
   * Binding only: what one leaderboard gives the player now (pollen/wardrobe.ts noteBoardRewards), from the
   * replay job (leaderboards/operator.ts). `items` are earned-only catalogue items; `seq` orders deliveries.
   */
  noteBoardRewards(owner: string, board: string, items: string[], seq: number): Outcome<{ changed: boolean }> {
    if (knownBoard(board) === null || !validEarnedItems(items) || !Number.isSafeInteger(seq) || seq < 1) return fail(400, "invalid_board_rewards");
    if (!this.pollenActive(owner)()) return fail(404, "identity_absent");
    return noteBoardRewards(this.ctx.storage, board, items, seq, Date.now(), this.pollenActive(owner));
  }
  private pollenActive(owner: string): () => boolean {
    return () => { const identity = this.identity(); return identity?.state === "active" && identity.player_id === owner; };
  }
  /**
   * Binding only: credits one accepted turn from the facts its room froze (pollen/wallet.ts creditTurn).
   * While item blooms are on, the credit may also drop an item into the wardrobe (pollen/item-blooms.ts), when
   * `drops` says the app that sent the turn is offered the shop (pollen/routes.ts pollenShopClient).
   */
  creditTurn(owner: string, facts: unknown, drops = false): Promise<Outcome<PollenReceipt>> {
    if (!this.pollenActive(owner)()) return Promise.resolve(fail(404, "identity_absent"));
    return creditTurn(this.ctx.storage, this.env, owner, facts, Date.now(), this.pollenActive(owner), RATES,
      itemDropsOn(this.env, drops) ? { owned: ownedItemIds, give: addDroppedItem } : undefined);
  }
  /**
   * Binding only: a first clear made together, from the facts of the turn that finished the chapter.
   * The room's boost is the same for both members, so the partner's clear uses the frozen percent.
   * `roomId`: that room, so the partner's later clear claim from it answers what it paid (`paid_clears`).
   */
  creditTogetherClear(owner: string, levelId: string, hard: boolean, boost: number, roomId?: string): Outcome<PollenReceipt> {
    return creditClear(this.ctx.storage, { level_id: levelId, hard, boost_percent: boost, ...(roomId ? { room_id: roomId } : {}) }, Date.now(), this.pollenActive(owner));
  }
  /**
   * Binding only: a solo first clear the app claims. A paid chapter needs Full Journey (the stored
   * fj_until; no provider call), and a subscriber's room of one gets one subscriber's boost.
   */
  creditSoloClear(owner: string, levelId: string, premium: boolean): Outcome<PollenReceipt> {
    return creditSoloClear(this.ctx.storage, levelId, premium, Date.now(), this.pollenActive(owner));
  }
  /** Binding only: a friend duel's win bonus, once per duel (pollen/duel-pay.ts). */
  creditDuelWin(owner: string, win: DuelWin): Outcome<DuelWinAnswer> {
    return creditDuelWin(this.ctx.storage, win, Date.now(), this.pollenActive(owner));
  }
  /** Binding only: the first win over the developers' ghost on a board, once per board (pollen/duel-pay.ts). */
  creditGhostWin(owner: string, win: GhostWin): Outcome<DuelWinAnswer> {
    return creditGhostWin(this.ctx.storage, win, Date.now(), this.pollenActive(owner));
  }
  /** Binding only: what the player's turns in a duel's room paid, for its result card. Reads only. */
  duelRoomPay(roomId: string): DuelRoomPay { return duelRoomPay(this.ctx.storage, roomId); }
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
  /**
   * PUT /v1/profile/name after the router cleaned the name (display-names.ts applyDisplayName). One row write, only on a change.
   * `pricing` (only while the shop is on): a change may cost Pollen (pollen/name-price.ts), charged in the same transaction
   * as the change. `shown` is the price the phone showed; one that differs is refused, and a phone that never shows a price
   * (an older app) is refused a paid change with display_name_locked, a code it already settles on.
   */
  setDisplayName(owner: string, deviceHash: string, name: string | null, revision: number, pricing?: { shown?: number }): DisplayNameOutcome {
    return this.ctx.storage.transactionSync((): DisplayNameOutcome => {
    const identity = this.authorized(deviceHash);
    if (!identity || identity.player_id !== owner) return fail(401, "invalid_auth");
    const named = identity.display_name !== undefined, now = Date.now(), before = { ...identity };
    // A repeated or older revision only answers the state (applyDisplayName), so it is never charged.
    const cost = pricing && revision > (identity.display_name_rev ?? 0) ? namePrice(identity, name, now) : 0;
    if (cost > 0) {
      // A change the rules refuse anyway (a lock, the daily limit) answers that refusal, never a price one.
      const trial = applyDisplayName({ ...identity }, name, revision, now);
      if (!trial.outcome.ok) return trial.outcome;
      if (pricing!.shown === undefined) return fail(403, "display_name_locked");
      if (pricing!.shown !== cost) return fail(409, "name_change_price");
      if (walletBalance(this.ctx.storage, now) < cost) return fail(402, "pollen_short");
    }
    const { outcome, changed } = applyDisplayName(identity, name, revision, now);
    const renamed = changed && outcome.ok && name !== null && name !== (before.display_name ?? null);
    if (renamed && pricing) countNameSet(identity, before);
    if (renamed && cost > 0 && payFromWallet(this.ctx.storage, cost, now) === null) throw new Error("pollen_name_charge_failed");
    if (changed) this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    // A name that just went: the v2 rooms that may hold a copy, for the route to clear.
    if (changed && named && identity.display_name === undefined && outcome.ok) return { ...outcome, cleared_rooms: this.listRooms().filter(link => roomLinkVersion(link) === 2).slice(0, MAX_CLEARED_ROOMS).map(link => link.room_id) };
    return outcome;
    });
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
  /**
   * This player's Add. Into a full list it takes the place of the oldest pending incoming request, as a received one
   * does (`evicted`, for the router to clear on its sender's side), so strangers' requests never stop a player adding.
   */
  friendPropose(owner: string, deviceHash: string, peer: string, requestId: string): Outcome<{ link: FriendLink; evicted: FriendLink | null }> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    if (!ID_PATTERN.test(peer) || peer === owner || !ID_PATTERN.test(requestId)) return fail(400, "invalid_friend_request");
    const identity = this.identity()!, social = this.social(identity), before = social.links.length;
    social.links = social.links.filter(link => link.accepted || link.created_at + FRIEND_REQUEST_TTL_MS > Date.now());
    const old = social.links.find(x => x.player_id === peer);
    // An existing link answers as it is: only expired requests dropped here are written, and the list's refresh floor stays.
    if (old) { if (social.links.length !== before) this.writeSocial(identity, social, false); return ok({ link: old, evicted: null }); }
    const evicted = social.links.length >= MAX_FRIENDS ? oldestIncoming(social.links) : null;
    if (social.links.length >= MAX_FRIENDS && !evicted) return fail(409, "friend_list_full");
    if (evicted) social.links = social.links.filter(link => link !== evicted);
    const link: FriendLink = { player_id: peer, request_id: requestId, requested_by: owner, accepted: false, created_at: Date.now() };
    social.links.push(link); this.writeSocial(identity, social); return ok({ link, evicted });
  }
  /**
   * Binding only: router retains the sender's durable proposal across this hop. `consented`: this player chose Add
   * too (the router then accepts at once), so the incoming cap does not apply. Past MAX_INCOMING_REQUESTS, or into
   * a full list, it takes the place of the oldest pending incoming request (`evicted`, for the router to clear on its
   * sender's side); only a list full of friends and outgoing requests refuses it. A stranger's request leaves the
   * list's refresh floor alone, so it can never make an open Friends page read again; the next read shows it.
   */
  friendReceive(owner: string, peer: string, requestId: string, createdAt: number, consented = false): Outcome<{ link: FriendLink; evicted: FriendLink | null }> {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active") return fail(404, "friend_unavailable");
    if (!ID_PATTERN.test(peer) || peer === owner || !ID_PATTERN.test(requestId) || !Number.isSafeInteger(createdAt) || createdAt <= 0) return fail(400, "invalid_friend_request");
    const social = this.social(identity), now = Date.now();
    social.links = social.links.filter(link => link.accepted || link.created_at + FRIEND_REQUEST_TTL_MS > now);
    const old = social.links.find(x => x.player_id === peer);
    if (old) return old.request_id === requestId && old.requested_by === peer ? ok({ link: old, evicted: null }) : fail(409, "friend_request_changed");
    const incoming = social.links.filter(link => !link.accepted && link.requested_by === link.player_id).length;
    const evicted = social.links.length >= MAX_FRIENDS || !consented && incoming >= MAX_INCOMING_REQUESTS ? oldestIncoming(social.links) : null;
    if (social.links.length >= MAX_FRIENDS && !evicted) return fail(409, "friend_list_full");
    if (evicted) social.links = social.links.filter(link => link !== evicted);
    const link: FriendLink = { player_id: peer, request_id: requestId, requested_by: peer, accepted: false, created_at: createdAt };
    social.links.push(link); this.writeSocial(identity, social, consented); this.pushFriendsChanged(identity, false); return ok({ link, evicted });
  }
  friendApprove(owner: string, deviceHash: string, peer: string, requestId: string): Outcome<FriendLink> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    const identity = this.identity()!, social = this.social(identity), link = social.links.find(x => x.player_id === peer);
    if (!link || link.request_id !== requestId || link.requested_by !== peer || !link.accepted && link.created_at + FRIEND_REQUEST_TTL_MS <= Date.now()) return fail(409, "friend_request_changed");
    // The accepter's own phones read the list early: only an accepted row carries the new friend's name, and the reply has none.
    // A repeat of an acceptance already made writes nothing and leaves the list's refresh floor alone.
    if (link.accepted) return ok(link);
    link.accepted = true; this.writeSocial(identity, social); this.pushFriendsChanged(identity, true); return ok(link);
  }
  /** Binding only, after the recipient's matching approval is read. */
  friendConfirm(owner: string, peer: string, requestId: string): Outcome<FriendLink> {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active") return fail(404, "friend_unavailable");
    const social = this.social(identity), link = social.links.find(x => x.player_id === peer);
    if (!link || link.request_id !== requestId || link.requested_by !== owner) return fail(409, "friend_request_changed");
    if (link.accepted) return ok(link);
    link.accepted = true; this.writeSocial(identity, social); this.pushFriendsChanged(identity, true); return ok(link);
  }
  /**
   * Exact-token removal cannot erase a newer request after a lost reply. `changed`: whether a link went. A removal
   * of nothing writes nothing, sends no hint and leaves the list's refresh floor alone, since any player id can be named.
   * `declined`: the link that went was a pending request from `peer` (the router then notes the decline, friend-declines.ts).
   */
  friendForget(owner: string, peer: string, requestId: string, deviceHash?: string): Outcome<{ removed: true; changed: boolean; declined?: true }> {
    const identity = this.identity();
    if (deviceHash !== undefined && (!this.authorize(deviceHash) || identity?.player_id !== owner)) return fail(401, "invalid_auth");
    if (!identity || identity.player_id !== owner) return ok({ removed: true, changed: false });
    const social = this.social(identity), gone = social.links.find(x => x.player_id === peer && x.request_id === requestId);
    if (!gone) return ok({ removed: true, changed: false });
    social.links = social.links.filter(x => x !== gone);
    this.ctx.storage.sql.exec("DELETE FROM friend_room_subscriptions WHERE host_id=? AND json_extract(data,'$.request_id')=?", peer, requestId);
    this.writeSocial(identity, social);
    // A peer's removal (no device hash) reaches this player's open Friends page.
    if (deviceHash === undefined && identity.state === "active") this.pushFriendsChanged(identity, false);
    return ok({ removed: true, changed: true, ...(!gone.accepted && gone.requested_by === peer ? { declined: true as const } : {}) });
  }
  /** `quiet`: the change is past this hour's shareNews, so the router tells no friend (their next read and the events' own checks still see it). */
  friendShare(owner: string, deviceHash: string, room: SharedFriendRoom | null): Outcome<{ shared_room: SharedFriendRoom | null; quiet?: true }> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    if (room !== null && (!validSharedFriendRoom(room) || !this.listRooms().some(x => x.host && x.room_id === room.room_id && roomLinkVersion(x) === room.api_version))) return fail(404, "room_not_found");
    return this.ctx.storage.transactionSync(() => {
      const identity = this.identity()!, social = this.social(identity), old = social.shared_room;
      const changed = old?.room_id !== room?.room_id || old?.api_version !== room?.api_version;
      // The same room again writes nothing and leaves the list's refresh floor alone.
      if (!changed) return ok({ shared_room: room });
      const row = changed ? this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_publication WHERE id=1").toArray()[0] : undefined;
      let publicationState: FriendPublicationState | null = null;
      if (row) {
        try { const parsed: unknown = JSON.parse(row.data); if (!isPublicationState(parsed)) return fail(409, "unsupported_friend_publication"); publicationState = parsed; }
        catch { return fail(409, "unsupported_friend_publication"); }
      }
      social.shared_room = room; this.writeSocial(identity, social);
      if (publicationState?.current) this.ctx.storage.sql.exec("UPDATE friend_room_publication SET data=? WHERE id=1", JSON.stringify({ ...publicationState, current: null }));
      return ok({ shared_room: room, ...(this.shareNews.take(Date.now()) ? {} : { quiet: true as const }) });
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
  /**
   * `fresh`: whether friends should hear of it. A republish of the room already published inside the push window
   * (friend-room-events.ts FRIEND_ROOM_PUSH_WINDOW_MS) answers that publication, with no new epoch and no write.
   */
  publishFriendRoom(owner: string, deviceHash: string, publicationId: string, room: SharedFriendRoom): Outcome<{ publication: FriendPublication; fresh: boolean }> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    if (!PUBLICATION_ID_PATTERN.test(publicationId) || !validSharedFriendRoom(room)) return fail(400, "invalid_friend_publication");
    const identity = this.identity()!, social = this.social(identity);
    if (!social.shared_room || social.shared_room.api_version !== room.api_version || social.shared_room.room_id !== room.room_id) return fail(409, "friend_room_not_shared");
    return this.ctx.storage.transactionSync(() => {
      const existingReceipt = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_publication_ops WHERE publication_id=?", publicationId).toArray()[0];
      if (existingReceipt) {
        const receipt = checkedFriendPublication(existingReceipt.data);
        if (!receipt || receipt.room.api_version !== room.api_version || receipt.room.room_id !== room.room_id) return fail(409, "friend_publication_changed");
        // A lost reply's retry finishes the fan-out of a publication that was fresh when made; any other repeat reaches nobody again.
        const current = this.friendPublication(owner);
        return ok({ publication: receipt, fresh: current?.publication_epoch === receipt.publication_epoch && Date.now() - receipt.published_at < PUBLICATION_RETRY_MS && this.withinPublicationCap(receipt.published_at) });
      }
      const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_publication WHERE id=1").toArray()[0];
      let state = { schema_version: 1 as const, epoch_counter: 0, current: null as FriendPublication | null };
      if (row) {
        try { const parsed: unknown = JSON.parse(row.data); if (!isPublicationState(parsed)) return fail(409, "unsupported_friend_publication"); state = parsed; }
        catch { return fail(409, "unsupported_friend_publication"); }
      }
      const current = state.current;
      if (current && current.room.room_id === room.room_id && current.room.api_version === room.api_version && Date.now() - current.published_at < FRIEND_ROOM_PUSH_WINDOW_MS) return ok({ publication: current, fresh: false });
      if (state.epoch_counter >= Number.MAX_SAFE_INTEGER) return fail(409, "friend_publication_epoch_exhausted");
      const publication: FriendPublication = { schema_version: 1, publication_epoch: state.epoch_counter + 1, publication_id: publicationId, room, published_at: Date.now() };
      state = { schema_version: 1, epoch_counter: publication.publication_epoch, current: publication };
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_publication VALUES (1,?)", JSON.stringify(state));
      this.ctx.storage.sql.exec("INSERT INTO friend_room_publication_ops VALUES (?,?)", publicationId, JSON.stringify(publication));
      this.ctx.storage.sql.exec("DELETE FROM friend_room_publication_ops WHERE publication_id IN (SELECT publication_id FROM friend_room_publication_ops ORDER BY json_extract(data,'$.published_at') DESC LIMIT -1 OFFSET ?)", MAX_PUBLICATION_RECEIPTS);
      return ok({ publication, fresh: this.withinPublicationCap(publication.published_at) });
    });
  }
  /** Whether a publication made at `at` was within MAX_FRESH_PUBLICATIONS_PER_HOUR (the receipts in the hour up to it); past it, friends see the room on their list but get no new event. */
  private withinPublicationCap(at: number): boolean {
    return this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM friend_room_publication_ops WHERE json_extract(data,'$.published_at')>? AND json_extract(data,'$.published_at')<=?", at - 3_600_000, at).one().n <= MAX_FRESH_PUBLICATIONS_PER_HOUR;
  }
  /** Shared-room changes whose hints and revokes reach friends: MAX_FRESH_PUBLICATIONS_PER_HOUR an hour; later ones change only this list (memory only). */
  private readonly shareNews = new MemoryBudget(MAX_FRESH_PUBLICATIONS_PER_HOUR, 3_600_000);
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
  /** `changed`: whether anything was written; the same choice again writes nothing. */
  setFriendSubscription(owner: string, host: string, requestId: string, enabled: boolean): Outcome<{ subscribed: boolean; changed: boolean }> {
    const identity = this.identity(); if (!identity || identity.player_id !== owner || identity.state !== "active") return fail(404, "friend_unavailable");
    if (!ID_PATTERN.test(host) || !ID_PATTERN.test(requestId) || typeof enabled !== "boolean") return fail(400, "invalid_friend_notification");
    return this.ctx.storage.transactionSync(() => {
      const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM friend_room_subscriptions WHERE host_id=?", host).toArray()[0];
      const current = old ? checkedFriendSubscription(old.data) : null, held = current?.enabled === true && current.request_id === requestId;
      if (!old && enabled && this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM friend_room_subscriptions").one().n >= MAX_FRIEND_SUBSCRIPTIONS) return fail(409, "friend_subscription_limit");
      if (enabled && held) return ok({ subscribed: true, changed: false });
      if (enabled) this.ctx.storage.sql.exec("INSERT OR REPLACE INTO friend_room_subscriptions VALUES (?,?)", host, JSON.stringify({ schema_version: 1, request_id: requestId, enabled, updated_at: Date.now() } satisfies FriendSubscription));
      else if (current?.request_id === requestId) this.ctx.storage.sql.exec("DELETE FROM friend_room_subscriptions WHERE host_id=? AND json_extract(data,'$.request_id')=?", host, requestId);
      else return ok({ subscribed: false, changed: false });
      return ok({ subscribed: enabled, changed: true });
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
    // Only a phone whose registration came from a client that reads hosting
    // events (0.6.1+) gets the push; an older one could never acknowledge it.
    // No device or age rule here: a row past REGISTRATION_TTL_MS is chosen and then cancelled by its current check.
    const gated = FRIEND_EVENTS_CLIENT_GATE(this.env);
    const registrations = pushPhones(this.ctx.storage, this.env, "friend_room_available", { optIn: "all", include: data => !gated || data.friend_events === 2 });
    if (registrations === null) return { status: "retry" };
    if (!registrations.length || !notificationsConfigured(this.env)) return { status: "done" };
    const outcomes = await sendToPhones(this.ctx.storage, this.notificationSender, registrations, this.pushMemory, {
      family: "friend", hint: makeFriendRoomHint(event.host_id, event.room, event.publication_epoch, event.event_id), authorized: hash => this.authorize(hash),
      stillCurrent: phone => Date.now() - phone.registration.updated_at < REGISTRATION_TTL_MS,
      confirm: async current => {
        if (!current()) return false;
        const recipientEdge = this.friendEdge(event.recipient_id, event.host_id), hostPlayer = this.env.PLAYERS.getByName(event.host_id);
        const [hostEdge, publication, subscription, pending] = await Promise.all([hostPlayer.friendEdge(event.host_id, event.recipient_id), hostPlayer.friendPublication(event.host_id), this.friendSubscription(event.recipient_id, event.host_id), this.env.FRIEND_ROOM_EVENTS.getByName(event.recipient_id).isPending(event.recipient_id, event.event_id)]);
        if (!recipientEdge || !hostEdge || !recipientEdge.link.accepted || !hostEdge.link.accepted || recipientEdge.link.request_id !== event.request_id || hostEdge.link.request_id !== event.request_id ||
          !subscription?.enabled || subscription.request_id !== event.request_id || !pending || !publication || publication.publication_epoch !== event.publication_epoch || publication.room.room_id !== event.room.room_id || publication.room.api_version !== event.room.api_version) return false;
        if (await interactionBlocked(this.env, event.recipient_id, event.host_id) || !current()) return false;
        const room = event.room.api_version === 1 ? await this.env.ROOMS.getByName(event.room.room_id).friendInvite(event.host_id, event.recipient_id) : await this.env.ROOMS_V2.getByName(event.room.room_id).friendInvite(event.host_id, event.recipient_id);
        return room.ok && current();
      }
    });
    if (outcomes.some(value => value.status === "retry" || value.status === "unconfigured")) return { status: "retry", retry_after_ms: Math.max(0, ...outcomes.map(value => value.retry_after_ms ?? 0)) };
    if (outcomes.length > 0 && outcomes.every(value => value.status === "cancelled")) return { status: "cancelled" };
    return { status: "done" };
  }
  /** Lease rows added or removed lately (presence.ts PRESENCE_CHANGES_PER_MINUTE); memory only. */
  private readonly presenceChanges = presenceChangeBudget();
  /**
   * POST /v1/presence. Writes only when the lease changes: a heartbeat for a lease with more than half its time left
   * answers without writing, and new sessions and offlines past PRESENCE_CHANGES_PER_MINUTE answer the same way.
   */
  async updatePresence(owner: string, deviceHash: string, session: string, online: boolean): Promise<Outcome<PresencePolicy>> {
    if (!PRESENCE_SESSION.test(session) || typeof online !== "boolean") return fail(400, "invalid_presence_request");
    return this.ctx.storage.transaction(async () => {
      const alarm = await this.ctx.storage.getAlarm();
      if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
      if (!presenceAlarmOwned(this.ctx.storage, alarm)) return fail(503, "presence_unavailable");
      prunePresence(this.ctx.storage);
      const now = Date.now();
      const lease = this.ctx.storage.sql.exec<{ device_hash: string; expires_at: number }>("SELECT device_hash,expires_at FROM presence_leases WHERE session_id=?", session).toArray()[0];
      if (online) {
        if (lease && lease.device_hash === deviceHash && lease.expires_at - now > PRESENCE_EXTEND_WITHIN_MS) return ok(presencePolicy());
        if (!lease && this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM presence_leases").one().n >= MAX_PRESENCE_SESSIONS) return fail(409, "presence_session_limit");
        if (!lease && !this.presenceChanges.take(now)) return ok(presencePolicy());
        this.ctx.storage.sql.exec("INSERT OR REPLACE INTO presence_leases VALUES (?,?,?)", session, deviceHash, now + PRESENCE_TTL_MS);
      } else {
        if (!lease || !this.presenceChanges.take(now)) return ok(presencePolicy());
        this.ctx.storage.sql.exec("DELETE FROM presence_leases WHERE session_id=?", session);
      }
      await this.scheduleAlarm();
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
  /**
   * The one alarm: an identity deletion's batches while one runs; otherwise presence lease pruning and, once its wake
   * has come, the monthly grant (pollen/grant-alarm.ts; its provider calls run outside any transaction), then the next
   * wake for both. The push for what the grant paid goes last, after the alarm is set again.
   */
  async alarm(): Promise<void> {
    if (roomErasurePending(this.ctx.storage)) return this.continueRoomErasure();
    const owner = this.grantWakeOwner();
    // Set first, so while the settle waits on RevenueCat the alarm matches its marker (presence and the other owned
    // checks keep working) and a settle cut short still wakes again; a due wake moves to its backoff time.
    await this.resetAlarm();
    if (owner === null) return;
    const paid: { key: string; amount: number }[] = [];
    await this.settleGrant(owner, "none", lines => paid.push(...lines));
    // A deletion that began during the settle took the alarm over.
    if (roomErasurePending(this.ctx.storage)) return;
    await this.resetAlarm();
    if (paid.length) await this.pushPollen(paid);
  }
  /** Binding-only host lookup; the logical owner and active identity must match. */
  storedTesterGrant(owner: string): TesterGrant | null {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active" || !Object.hasOwn(identity, "tester_grant")) return null;
    if (!validTesterGrant(identity.tester_grant)) throw new Error("unsupported_tester_grant");
    return { ...identity.tester_grant };
  }
  /** The last verified Full Journey check (entitlement.ts EntitlementMemo); memory only, never stored. */
  private entitlementMemo: EntitlementMemo | null = null;
  /**
   * Binding only, for the Full Journey check (entitlement.ts): the stored tester grant and the tester switch,
   * from one identity read, so the check makes no more Player calls than before, and the memo of a recent check
   * that found Full Journey while it is still fresh (entitlementFresh).
   */
  storedAccess(owner: string): { grant: TesterGrant | null; full_journey_off: boolean; memo?: EntitlementMemo } {
    const grant = this.storedTesterGrant(owner);
    const identity = this.identity();
    const active = !!identity && identity.player_id === owner && identity.state === "active";
    const memo = active && this.entitlementMemo && entitlementFresh(this.entitlementMemo, Date.now()) ? { memo: this.entitlementMemo } : {};
    return { grant, full_journey_off: active && identity.full_journey_off === true, ...memo };
  }
  /** Binding only (entitlement.ts): remembers a verified check, or forgets the memo with null. Writes nothing. */
  noteEntitlement(owner: string, memo: EntitlementMemo | null): void {
    const identity = this.identity();
    this.entitlementMemo = memo && identity?.player_id === owner && identity.state === "active" ? memo : null;
  }
  /**
   * Binding only, after the route matched a tester's toggle code (test-codes.ts): flips the switch in one
   * synchronous identity write and answers where it now stands. Nothing about the code is kept.
   */
  toggleFullJourneyOff(owner: string, deviceHash: string): Outcome<{ full_journey_off: boolean }> {
    if (!this.authorize(deviceHash) || this.identity()?.player_id !== owner) return fail(401, "invalid_auth");
    const identity = this.identity()!;
    if (identity.full_journey_off === true) delete identity.full_journey_off;
    else identity.full_journey_off = true;
    this.entitlementMemo = null;
    this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    return ok({ full_journey_off: identity.full_journey_off === true });
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
      const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations WHERE binding_epoch=?", epoch).toArray();
      if (!old.length && this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM notification_registrations").one().n >= MAX_REGISTRATIONS) return fail(409, "notification_registration_limit");
      const fields = { token, device_hash: deviceHash, ...(friendEvents ? { friend_events: 2 } : {}), ...(ios ? { platform: ios.platform, categories: ios.categories } : {}) };
      // The phone registers on every cold start: the same registration writes again only to refresh its age once a day.
      const held = old.length ? JSON.parse(old[0].data) as Record<string, unknown> : null;
      const same = held !== null && typeof held.updated_at === "number" && now - held.updated_at < REGISTRATION_REFRESH_MS &&
        Object.keys(held).length === Object.keys(fields).length + 1 && Object.entries(fields).every(([key, value]) => JSON.stringify(held[key]) === JSON.stringify(value));
      if (!same) this.ctx.storage.sql.exec("INSERT OR REPLACE INTO notification_registrations VALUES (?,?)", epoch, JSON.stringify({ token, device_hash: deviceHash, updated_at: now, ...(friendEvents ? { friend_events: 2 } : {}), ...(ios ? { platform: ios.platform, categories: ios.categories } : {}) }));
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
      // Writes only on a change: the phone repeats its choice on every cold start.
      const held = this.ctx.storage.sql.exec("SELECT 1 FROM notification_categories WHERE binding_epoch=?", epoch).toArray().length > 0;
      if (redoRequests && !held) this.ctx.storage.sql.exec("INSERT OR REPLACE INTO notification_categories VALUES (?,?)", epoch, JSON.stringify({ schema_version: 1, redo_requests: true, updated_at: now }));
      else if (!redoRequests && held) this.ctx.storage.sql.exec("DELETE FROM notification_categories WHERE binding_epoch=?", epoch);
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
    // No further rule: the erase above already left only this device's rows within REGISTRATION_TTL_MS.
    const phones = pushPhones(this.ctx.storage, this.env, hint.kind, { optIn: redo ? "redo" : "all", include: () => true });
    if (phones === null) return { delivered: false };
    const outcomes = await sendToPhones(this.ctx.storage, this.notificationSender, phones, this.pushMemory, {
      family: "room", hint, authorized: hash => this.authorize(hash),
      stillCurrent: phone => this.ctx.storage.sql.exec("SELECT room_id FROM rooms WHERE room_id=?", hint.room_id).toArray().length === 1 &&
        (!redo || this.ctx.storage.sql.exec("SELECT binding_epoch FROM notification_categories WHERE binding_epoch=?", phone.binding_epoch).toArray().length === 1),
      confirm: async current => {
        if (!current()) return false;
        // Another member may have deleted the room while our OAuth request ran;
        // their partner's stale room link is not sufficient membership authority.
        const pending = hint.room_family === "legacy" ? await this.env.ROOMS.getByName(hint.room_id).notificationEligible(identity.player_id, hint) : await this.env.ROOMS_V2.getByName(hint.room_id).notificationEligible(identity.player_id, hint);
        if (!pending || !current()) return false;
        const members = hint.room_family === "legacy" ? await this.env.ROOMS.getByName(hint.room_id).safetyMembers(identity.player_id) : await this.env.ROOMS_V2.getByName(hint.room_id).safetyMembers(identity.player_id);
        return members.ok && !await interactionBlocked(this.env, members.value.host_id, members.value.guest_id) && current();
      }
    });
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
   * Rows the room index holds as finished, closed or unavailable are settled
   * too, and the bound may rise (roomLinkBound).
   */
  private roomsFull(settled: readonly string[]): boolean {
    const linked = this.ctx.storage.sql.exec<{ room_id: string }>("SELECT room_id FROM rooms").toArray().map(row => row.room_id);
    const index = roomIndexCount(this.ctx.storage);
    return roomLimitReached(linked, [...settled, ...index.settled], roomLinkBound(index.unindexed === 0));
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
  noteRoomIndex(owner: string, roomId: string, version: number, observation: RoomObservation, hint?: LiveHint): void {
    const identity = this.identity();
    if (identity?.state === "active" && identity.player_id === owner) recordRoomObservation(this.ctx.storage, roomId, version, observation);
    // A live hint that rode on this push (room-index-sync.ts).
    if (hint) this.ctx.waitUntil(this.liveHint(owner, hint).catch(() => false));
  }
  /** The router's live reads from an indexed list; null marks a read that failed. */
  recordRoomIndex(owner: string, observations: { room_id: string; api_version: number; observation: RoomObservation | null }[]): void {
    const identity = this.identity();
    if (identity?.state !== "active" || identity.player_id !== owner) return;
    this.ctx.storage.transactionSync(() => { for (const item of observations) recordRoomObservation(this.ctx.storage, item.room_id, item.api_version, item.observation); });
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
    this.entitlementMemo = null;
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
      dropWardrobe(this.ctx.storage);
      dropEarned(this.ctx.storage);
      dropGrant(this.ctx.storage);
      dropBundles(this.ctx.storage);
      // The one alarm's marker may name a grant wake a month away; nothing is left to wake for.
      this.ctx.storage.sql.exec("DELETE FROM presence_alarm");
    });
    if (!roomErasurePending(this.ctx.storage)) await this.ctx.storage.deleteAlarm();
    await this.env.SAFETY_PROFILES.getByName(owner).markErasureComplete(owner);
    return ok({ deleted: true });
  }
}

// A Player nobody created answers the identity check as one without an identity row, and stores nothing.
answerWhileBlank(Player, { authorize: () => false, authorizeRoom: () => ({ authorized: false, linked: false }), rotateSafetyToken: () => undefined,
  authorizeNamed: () => ({ authorized: false, linked: true }), authorizeWallet: async () => ({ authorized: false, linked: true }),
  creditTurn: async () => fail(404, "identity_absent"), creditTogetherClear: () => fail(404, "identity_absent"), creditSoloClear: () => fail(404, "identity_absent"), creditDuelWin: () => fail(404, "identity_absent"), creditGhostWin: () => fail(404, "identity_absent"), duelRoomPay: () => ({ turns: 0, plain: 0, blooms: 0, duel: 0, duel_percent: 0, boost: 0, boost_percent: 0, total: 0 }), setDisplayName: () => fail(401, "invalid_auth"), pollenSpend: () => fail(401, "invalid_auth"), pollenEquip: () => fail(401, "invalid_auth"), pollenBundleClaim: async () => fail(401, "invalid_auth"), noteBoardRewards: () => fail(404, "identity_absent"), operatorClearDisplayName: () => fail(404, "identity_absent"), publicDisplayName: () => null,
  campaignDrainInventory: () => blankPlayerInventory(), operatorCampaignAllocation: () => null,
  operatorCampaignTerminalScope: async () => fail(404, "identity_absent"), operatorFinalizeCampaignTerminalLink: async () => fail(404, "identity_absent"),
  deletingWith: () => false, noteRoomIndex: () => undefined, leaderboardStanding: () => null,
  // Friend calls can name any player id: one nobody made answers as an empty identity and stores nothing.
  friendEdge: () => null, safetyIdentityActive: () => false, friendReceive: () => fail(404, "friend_unavailable"),
  friendForget: (_owner, _peer, _request, deviceHash) => deviceHash !== undefined ? fail(401, "invalid_auth") : ok({ removed: true as const, changed: false }),
  // A link that outlived its player: the restore route drops it.
  restoreLinked: () => fail(404, "identity_absent"), recoveryMatches: () => false,
  storedAccess: () => ({ grant: null, full_journey_off: false }), noteEntitlement: () => undefined,
  // No identity, so no socket: a hint is dropped and an upgrade (unreachable past auth()) is refused.
  liveHint: async () => false, fetch: () => liveUnauthorized() });
