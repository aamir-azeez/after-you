import { DurableObject } from "cloudflare:workers";
import { equalHash, fail, ok, type Outcome } from "./protocol";
import { initializeSchema } from "./storage-schema";
import { exportSnapshot, restoreSnapshot, snapshotResult } from "./snapshot";
import { roomLinkVersion, validRoomLink, type RoomLink } from "./room-links";
import { readCreation, validChapterCreation, type ChapterCreation } from "./v2/creation-intent";
import { RELAY_KEY, sameChapter } from "./v2/chapters";
import type { ChapterKey } from "./v2/chapter-types";
import { BINDING_PATTERN, FcmSender, MAX_REGISTRATIONS, REGISTRATION_TTL_MS, notificationsConfigured, validHint, validNotificationToken, type NotificationEnvironment, type TurnHint } from "./notifications";
import { clearRegistrations, initializeNotifications, type DeliveryResult } from "./notification-storage";
import { interactionBlocked } from "./safety";
import { testerReceipt, validTesterGrant, type TesterGrant, type TesterAccess } from "./tester-access";
import { clearPresence, initializePresence, MAX_PRESENCE_SESSIONS, PRESENCE_SESSION, PRESENCE_TTL_MS, presenceAlarmOwned, presenceEnabled, presencePolicy, prunePresence, schedulePresence, type PresencePolicy } from "./presence";

type RecoveryReceipt = { previous_recovery_hash: string; request_hash: string };
type Identity = { player_id: string; device_hash: string; recovery_hash: string; state: "active" | "deleting"; created_at: string; tester_grant?: TesterGrant; recovery_receipt?: RecoveryReceipt };
export class Player extends DurableObject<Env> {
  private readonly notificationSender: FcmSender;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.notificationSender = new FcmSender(env as Env & NotificationEnvironment);
    this.ctx.blockConcurrencyWhile(async () => {
      initializeSchema(this.ctx.storage, "Player");
      initializeNotifications(this.ctx.storage, "Player");
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
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("INSERT INTO creations VALUES (?,?)", key, JSON.stringify(link));
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link));
      this.ctx.storage.sql.exec("DELETE FROM creations WHERE rowid NOT IN (SELECT rowid FROM creations ORDER BY rowid DESC LIMIT 128)");
    });
    return ok(link);
  }
  reserveChapterRoom(key: string, link: RoomLink, chapter: ChapterKey, simulationVersion?: number): Outcome<ChapterCreation> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    const proposed: ChapterCreation = { creation_schema: 1, link, chapter, ...(simulationVersion === undefined ? {} : { simulation_version: simulationVersion }) };
    if (!validChapterCreation(proposed)) return fail(400, "invalid_chapter_creation");
    const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM creations WHERE request_key=?", key).toArray()[0];
    if (old) {
      const data: unknown = JSON.parse(old.data), previous = readCreation(data);
      if (!previous) return validRoomLink(data) ? fail(409, "idempotency_version_mismatch") : fail(409, "unsupported_creation_intent");
      if (!sameChapter(previous.chapter, chapter)) return fail(409, "idempotency_chapter_mismatch");
      return previous.simulation_version === simulationVersion ? ok(previous) : fail(409, "idempotency_simulation_mismatch");
    }
    const existing = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms WHERE room_id=?", link.room_id).toArray()[0];
    if (existing && roomLinkVersion(JSON.parse(existing.data) as RoomLink) !== 2) return fail(409, "room_version_conflict");
    if (this.ctx.storage.sql.exec<{ total: number }>("SELECT COUNT(*) AS total FROM rooms").one().total >= 20) return fail(409, "room_limit_reached");
    this.ctx.storage.transactionSync(() => {
      // Persist the complete variable creation intent and ordinary room link in
      // the same transaction before the router initializes the other object.
      // Raw v2 links already have one complete implicit intent: frozen Relay2.
      // Keep that older shape while the new chapter is disabled or unselected.
      this.ctx.storage.sql.exec("INSERT INTO creations VALUES (?,?)", key, JSON.stringify(sameChapter(chapter, RELAY_KEY) ? link : proposed));
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link));
      this.ctx.storage.sql.exec("DELETE FROM creations WHERE rowid NOT IN (SELECT rowid FROM creations ORDER BY rowid DESC LIMIT 128)");
    });
    return ok(proposed);
  }
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
    await this.env.PHOTO_TRANSFERS.getByName(owner).eraseOwner(owner, this.ctx.id.toString());
    if (!(await this.env.SAFETY_INBOX.getByName("moderation-v1").eraseReporter(owner)).ok) return fail(503, "safety_cleanup_unavailable");
    await this.env.SAFETY_PROFILES.getByName(owner).eraseOwner(owner);
    if (this.identity()?.state !== "deleting" || this.listRooms().length !== 0) return fail(409, "deletion_not_ready");
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM identity");
      this.ctx.storage.sql.exec("DELETE FROM rooms");
      this.ctx.storage.sql.exec("DELETE FROM creations");
      clearRegistrations(this.ctx.storage);
      clearPresence(this.ctx.storage);
    });
    await this.env.SAFETY_PROFILES.getByName(owner).markErasureComplete(owner);
    return ok({ deleted: true });
  }
}
