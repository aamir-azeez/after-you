import { DurableObject } from "cloudflare:workers";
import { ApiError, ID_PATTERN, equalHash, fail, isObject, ok, type Outcome } from "./protocol";
import { pruneCreationHistory, readCampaignCreation, reserveCampaignCreation, reserveCampaignGuestLink, reserveCampaignJoin, readCampaignJoin, readCampaignLink, cancelUnreservedCampaignJoin, cancelCampaignCreation, finalizeCampaignJoinCancellation } from "./v2/campaign-player";
import { campaignIdentityDeletionScope, finalizeCampaignIdentityDeletion, campaignTerminalScope, finalizeCampaignTerminalLink, campaignTerminalAdmissionScope, finalizeCampaignTerminalAdmission } from "./v2/campaign-player";
import { emptySocial, FRIEND_REFRESH_SECONDS, FRIEND_REQUEST_TTL_MS, MAX_FRIENDS, validSocial, validSharedFriendRoom, type FriendEdge, type FriendLink, type SharedFriendRoom, type SocialState } from "./friends";
import { initializeSchema } from "./storage-schema";
import { exportSnapshot, restoreSnapshot, snapshotResult } from "./snapshot";
import { roomLinkVersion, validRoomLink, type RoomLink } from "./room-links";
import { readCreation, validChapterCreation, type ChapterCreation } from "./v2/creation-intent";
import { RELAY_KEY, sameChapter } from "./v2/chapters";
import type { ChapterKey } from "./v2/chapter-types";
import { BINDING_PATTERN, FcmSender, MAX_REGISTRATIONS, REGISTRATION_TTL_MS, makeFriendRoomHint, notificationsConfigured, validHint, validNotificationToken, type NotificationEnvironment, type TurnHint } from "./notifications";
import { clearRegistrations, initializeNotifications, type DeliveryResult } from "./notification-storage";
import { checkedFriendPublication, checkedFriendSubscription, FRIEND_PUBLICATION_OPS_TABLE, FRIEND_PUBLICATION_TABLE, FRIEND_SUBSCRIPTIONS_TABLE, MAX_FRIEND_SUBSCRIPTIONS, MAX_PUBLICATION_RECEIPTS, PUBLICATION_ID_PATTERN, type FriendPublication, type FriendSubscription } from "./friend-room-event-storage";
import type { FriendRoomDelivery, FriendRoomEvent } from "./friend-room-events";
import { interactionBlocked } from "./safety";
import { testerReceipt, validTesterGrant, type TesterGrant, type TesterAccess } from "./tester-access";
import { clearPresence, initializePresence, MAX_PRESENCE_SESSIONS, PRESENCE_SESSION, PRESENCE_TTL_MS, presenceAlarmOwned, presenceEnabled, presencePolicy, prunePresence, schedulePresence, type PresencePolicy } from "./presence";

type RecoveryReceipt = { previous_recovery_hash: string; request_hash: string };
type Identity = { player_id: string; device_hash: string; recovery_hash: string; state: "active" | "deleting"; created_at: string; tester_grant?: TesterGrant; recovery_receipt?: RecoveryReceipt; social?: SocialState };
type FriendPublicationState = { schema_version: 1; epoch_counter: number; current: FriendPublication | null };
function isPublicationState(value: unknown): value is FriendPublicationState {
  return isObject(value) && Object.keys(value).length === 3 && value.schema_version === 1 && Number.isSafeInteger(value.epoch_counter) && Number(value.epoch_counter) >= 0 &&
    (value.current === null || checkedFriendPublication(JSON.stringify(value.current)) !== null && (value.current as FriendPublication).publication_epoch <= Number(value.epoch_counter));
}
export class Player extends DurableObject<Env> {
  private readonly notificationSender: FcmSender;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.notificationSender = new FcmSender(env as Env & NotificationEnvironment);
    this.ctx.blockConcurrencyWhile(async () => {
      initializeSchema(this.ctx.storage, "Player");
      initializeNotifications(this.ctx.storage, "Player");
      for (const table of [FRIEND_PUBLICATION_TABLE, FRIEND_PUBLICATION_OPS_TABLE, FRIEND_SUBSCRIPTIONS_TABLE]) this.ctx.storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
      initializePresence(this.ctx.storage);
    });
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
  authorize(deviceHash: string, allowDeleting = false): boolean {
    const identity = this.identity();
    return !!identity && (identity.state === "active" || allowDeleting) && equalHash(identity.device_hash, deviceHash);
  }
  private social(identity: Identity): SocialState {
    if (identity.social !== undefined && !validSocial(identity.social, identity.player_id)) throw new Error("unsupported_friend_state");
    return identity.social ?? emptySocial();
  }
  private writeSocial(identity: Identity, social: SocialState, invalidate = true): void {
    if (invalidate) social.next_refresh_at = 0;
    identity.social = social;
    this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
  }
  friendList(owner: string, deviceHash: string, refresh = true): Outcome<SocialState> {
    const identity = this.identity();
    if (!identity || identity.state !== "active" || !equalHash(identity.device_hash, deviceHash) || identity.player_id !== owner) return fail(401, "invalid_auth");
    const social = this.social(identity), now = Date.now();
    if (!refresh) return ok(social);
    if (social.next_refresh_at > now) return fail(429, "friends_refresh_limited");
    social.links = social.links.filter(link => link.accepted || link.created_at + FRIEND_REQUEST_TTL_MS > now);
    social.next_refresh_at = now + FRIEND_REFRESH_SECONDS * 1000;
    this.writeSocial(identity, social, false);
    return ok(social);
  }
  /** Binding only; list callers must also check the opposite edge and blocks. */
  friendEdge(owner: string, peer: string): FriendEdge | null {
    const identity = this.identity();
    if (!identity || identity.player_id !== owner || identity.state !== "active") return null;
    const social = this.social(identity), link = social.links.find(x => x.player_id === peer);
    if (!link || !link.accepted && link.created_at + FRIEND_REQUEST_TTL_MS <= Date.now()) return null;
    return { link, shared_room: social.shared_room, presence_expires_at: link.accepted ? this.presenceExpiryForIdentity(identity) : 0 };
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
    social.links.push(link); this.writeSocial(identity, social); return ok(link);
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
    link.accepted = true; this.writeSocial(identity, social); return ok(link);
  }
  /** Exact-token removal cannot erase a newer request after a lost reply. */
  friendForget(owner: string, peer: string, requestId: string, deviceHash?: string): Outcome<{ removed: true }> {
    const identity = this.identity();
    if (deviceHash !== undefined && (!this.authorize(deviceHash) || identity?.player_id !== owner)) return fail(401, "invalid_auth");
    if (!identity || identity.player_id !== owner) return ok({ removed: true });
    const social = this.social(identity);
    social.links = social.links.filter(x => x.player_id !== peer || x.request_id !== requestId);
    this.ctx.storage.sql.exec("DELETE FROM friend_room_subscriptions WHERE host_id=? AND json_extract(data,'$.request_id')=?", peer, requestId);
    this.writeSocial(identity, social); return ok({ removed: true });
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
    const link = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", event.room.room_id).toArray()[0];
    if (!link || roomLinkVersion(JSON.parse(link.data)) !== event.room.api_version) return { status: "cancelled" };
    const hostPlayer = this.env.PLAYERS.getByName(event.host_id);
    const [recipientEdge, hostEdge, publication, subscription, pending] = await Promise.all([this.friendEdge(event.recipient_id, event.host_id), hostPlayer.friendEdge(event.host_id, event.recipient_id),
      hostPlayer.friendPublication(event.host_id), this.friendSubscription(event.recipient_id, event.host_id), this.env.FRIEND_ROOM_EVENTS.getByName(event.recipient_id).isPending(event.recipient_id, event.event_id)]);
    if (!recipientEdge || !hostEdge || !recipientEdge.link.accepted || !hostEdge.link.accepted || recipientEdge.link.request_id !== event.request_id || hostEdge.link.request_id !== event.request_id ||
      !subscription?.enabled || subscription.request_id !== event.request_id || !pending || !publication || publication.publication_epoch !== event.publication_epoch || publication.room.room_id !== event.room.room_id || publication.room.api_version !== event.room.api_version ||
      await interactionBlocked(this.env, event.recipient_id, event.host_id)) return { status: "cancelled" };
    const available = event.room.api_version === 1 ? await this.env.ROOMS.getByName(event.room.room_id).friendInvite(event.host_id, event.recipient_id) : await this.env.ROOMS_V2.getByName(event.room.room_id).friendInvite(event.host_id, event.recipient_id);
    if (!available.ok) return { status: "cancelled" };
    const registrations = this.ctx.storage.sql.exec<{ binding_epoch: string; data: string }>("SELECT binding_epoch,data FROM notification_registrations LIMIT 5").toArray();
    if (registrations.length > MAX_REGISTRATIONS) return { status: "retry" };
    if (!registrations.length || !notificationsConfigured(this.env as Env & NotificationEnvironment)) return { status: "done" };
    const outcomes = await Promise.all(registrations.map(async row => {
      const registration = JSON.parse(row.data) as { token: string; device_hash: string; updated_at: number };
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
        makeFriendRoomHint(event.host_id, event.room, event.publication_epoch, event.event_id), eligible);
      if (sent.status === "invalid_token" && current()) this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE binding_epoch=? AND data=?", row.binding_epoch, row.data);
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
      if (online && !presenceEnabled(this.env)) return fail(503, "presence_unavailable");
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
  registerNotifications(deviceHash: string, token: string, epoch: string): Outcome<{ registered: true; binding_epoch: string }> {
    if (!this.authorize(deviceHash)) return fail(401, "invalid_auth");
    if (!validNotificationToken(token) || !BINDING_PATTERN.test(epoch)) return fail(400, "invalid_notification_registration");
    if (!notificationsConfigured(this.env as Env & NotificationEnvironment)) return fail(503, "notifications_unavailable");
    const now = Date.now();
    return this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE json_extract(data,'$.device_hash')!=? OR json_extract(data,'$.updated_at')<? OR (json_extract(data,'$.token')=? AND binding_epoch!=?)", deviceHash, now - REGISTRATION_TTL_MS, token, epoch);
      const old = this.ctx.storage.sql.exec("SELECT binding_epoch FROM notification_registrations WHERE binding_epoch=?", epoch).toArray();
      if (!old.length && this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM notification_registrations").one().n >= MAX_REGISTRATIONS) return fail(409, "notification_registration_limit");
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO notification_registrations VALUES (?,?)", epoch, JSON.stringify({ token, device_hash: deviceHash, updated_at: now }));
      return ok({ registered: true, binding_epoch: epoch });
    });
  }
  unregisterNotifications(deviceHash: string, epoch: string): Outcome<{ unregistered: true }> {
    if (!this.authorize(deviceHash)) return fail(401, "invalid_auth");
    if (!BINDING_PATTERN.test(epoch)) return fail(400, "invalid_notification_registration");
    this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE binding_epoch=?", epoch);
    return ok({ unregistered: true });
  }
  /** Binding only. The router never accepts caller-authored notification events. */
  async deliverTurnNotification(hint: TurnHint): Promise<DeliveryResult> {
    if (!validHint(hint)) return { delivered: true };
    const identity = this.identity(); if (!identity || identity.state !== "active") return { delivered: true };
    const link = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", hint.room_id).toArray()[0];
    if (!link || roomLinkVersion(JSON.parse(link.data)) !== (hint.room_family === "legacy" ? 1 : 2)) return { delivered: true };
    this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE json_extract(data,'$.device_hash')!=? OR json_extract(data,'$.updated_at')<?", identity.device_hash, Date.now() - REGISTRATION_TTL_MS);
    const rows = this.ctx.storage.sql.exec<{ binding_epoch: string; data: string }>("SELECT binding_epoch,data FROM notification_registrations LIMIT 5").toArray();
    if (rows.length > MAX_REGISTRATIONS) return { delivered: false };
    const outcomes = await Promise.all(rows.map(async row => {
      const registration = JSON.parse(row.data) as { token: string; device_hash: string };
      const current = () => this.authorize(registration.device_hash) && this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM notification_registrations WHERE binding_epoch=?", row.binding_epoch).toArray()[0]?.data === row.data &&
        this.ctx.storage.sql.exec("SELECT room_id FROM rooms WHERE room_id=?", hint.room_id).toArray().length === 1;
      const eligible = async () => {
        if (!current()) return false;
        // Another member may have deleted the room while our OAuth request ran;
        // their partner's stale room link is not sufficient membership authority.
        const pending = hint.room_family === "legacy" ? await this.env.ROOMS.getByName(hint.room_id).notificationEligible(identity.player_id, hint) : await this.env.ROOMS_V2.getByName(hint.room_id).notificationEligible(identity.player_id, hint);
        if (!pending || !current()) return false;
        const members = hint.room_family === "legacy" ? await this.env.ROOMS.getByName(hint.room_id).safetyMembers(identity.player_id) : await this.env.ROOMS_V2.getByName(hint.room_id).safetyMembers(identity.player_id);
        return members.ok && !await interactionBlocked(this.env, members.value.host_id, members.value.guest_id) && current();
      };
      const sent = await this.notificationSender.send(registration.token, row.binding_epoch, hint, eligible);
      if (sent.status === "invalid_token" && current()) this.ctx.storage.sql.exec("DELETE FROM notification_registrations WHERE binding_epoch=? AND data=?", row.binding_epoch, row.data);
      return sent;
    }));
    return { delivered: outcomes.every(value => value.status === "sent" || value.status === "invalid_token" || value.status === "cancelled"), retry_after_ms: Math.max(0, ...outcomes.map(value => value.retry_after_ms ?? 0)) };
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
    return ok({ player_id: identity.player_id, recovered: true });
  }
  reserveRoom(key: string, link: RoomLink): Outcome<RoomLink> {
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
    if (this.ctx.storage.sql.exec<{ total: number }>("SELECT COUNT(*) AS total FROM rooms").one().total >= 20) return fail(409, "room_limit_reached");
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
  reserveChapterRoom(key: string, link: RoomLink, chapter: ChapterKey, simulationVersion?: number): Outcome<ChapterCreation> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    const proposed: ChapterCreation = { creation_schema: 1, link, chapter, ...(simulationVersion === undefined ? {} : { simulation_version: simulationVersion }) };
    if (!validChapterCreation(proposed)) return fail(400, "invalid_chapter_creation");
    const previous = this.chapterCreation(key, chapter, simulationVersion);
    if (!previous.ok) return previous;
    if (previous.value) return ok(previous.value);
    const existing = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", link.room_id).toArray()[0];
    if (existing && roomLinkVersion(JSON.parse(existing.data) as RoomLink) !== 2) return fail(409, "room_version_conflict");
    if (this.ctx.storage.sql.exec<{ total: number }>("SELECT COUNT(*) AS total FROM rooms").one().total >= 20) return fail(409, "room_limit_reached");
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
  addRoom(link: RoomLink): Outcome<RoomLink> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    if (!validRoomLink(link)) return fail(400, "invalid_room_link");
    const existing = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", link.room_id).toArray()[0];
    if (existing && roomLinkVersion(JSON.parse(existing.data) as RoomLink) !== roomLinkVersion(link)) return fail(409, "room_version_conflict");
    if (!existing && this.ctx.storage.sql.exec<{ total: number }>("SELECT COUNT(*) AS total FROM rooms").one().total >= 20) return fail(409, "room_limit_reached");
    this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link));
    return ok(link);
  }
  listRooms(): RoomLink[] {
    return this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms ORDER BY rowid DESC").toArray().map(row => JSON.parse(row.data) as RoomLink);
  }
  removeRoom(roomId: string, expectedVersion = 1): void {
    const existing = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", roomId).toArray()[0];
    if (existing && roomLinkVersion(JSON.parse(existing.data) as RoomLink) === expectedVersion) this.ctx.storage.sql.exec("DELETE FROM rooms WHERE room_id=?", roomId);
  }
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
    return ok(links);
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
    });
    await this.env.SAFETY_PROFILES.getByName(owner).markErasureComplete(owner);
    return ok({ deleted: true });
  }
}
