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

type RecoveryReceipt = { previous_recovery_hash: string; request_hash: string };
type Identity = { player_id: string; device_hash: string; recovery_hash: string; state: "active" | "deleting"; created_at: string; recovery_receipt?: RecoveryReceipt };
export class Player extends DurableObject<Env> {
  private readonly notificationSender: FcmSender;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.notificationSender = new FcmSender(env as Env & NotificationEnvironment);
    this.ctx.blockConcurrencyWhile(async () => {
      initializeSchema(this.ctx.storage, "Player");
      initializeNotifications(this.ctx.storage, "Player");
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
        return pending && current();
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
  reserveChapterRoom(key: string, link: RoomLink, chapter: ChapterKey): Outcome<ChapterCreation> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    const proposed: ChapterCreation = { creation_schema: 1, link, chapter };
    if (!validChapterCreation(proposed)) return fail(400, "invalid_chapter_creation");
    const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM creations WHERE request_key=?", key).toArray()[0];
    if (old) {
      const data: unknown = JSON.parse(old.data), previous = readCreation(data);
      if (!previous) return validRoomLink(data) ? fail(409, "idempotency_version_mismatch") : fail(409, "unsupported_creation_intent");
      return sameChapter(previous.chapter, chapter) ? ok(previous) : fail(409, "idempotency_chapter_mismatch");
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
  beginDelete(supportedVersions: number[] = [1]): Outcome<RoomLink[]> {
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
    });
    return ok(links);
  }
  deletionInProgress(owner: string): boolean { const identity = this.identity(); return identity?.state === "deleting" && identity.player_id === owner; }
  async finishDelete(): Promise<Outcome<{ deleted: true }>> {
    if (this.identity()?.state !== "deleting" || this.listRooms().length !== 0) return fail(409, "deletion_not_ready");
    await this.env.PHOTO_TRANSFERS.getByName(this.identity()!.player_id).eraseOwner(this.identity()!.player_id, this.ctx.id.toString());
    if (this.identity()?.state !== "deleting" || this.listRooms().length !== 0) return fail(409, "deletion_not_ready");
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM identity");
      this.ctx.storage.sql.exec("DELETE FROM rooms");
      this.ctx.storage.sql.exec("DELETE FROM creations");
      clearRegistrations(this.ctx.storage);
    });
    return ok({ deleted: true });
  }
}
