import { DurableObject } from "cloudflare:workers";
import { equalHash, fail, ok, type Outcome } from "./protocol";

type RecoveryReceipt = { previous_recovery_hash: string; request_hash: string };
type Identity = { player_id: string; device_hash: string; recovery_hash: string; state: "active" | "deleting"; created_at: string; recovery_receipt?: RecoveryReceipt };
type RoomLink = { room_id: string; invite_code: string; host: boolean };
export class Player extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS identity (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)");
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS rooms (room_id TEXT PRIMARY KEY, data TEXT NOT NULL)");
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS creations (request_key TEXT PRIMARY KEY, data TEXT NOT NULL)");
    });
  }
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
    this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    return ok({ player_id: identity.player_id, recovered: true });
  }
  reserveRoom(key: string, link: RoomLink): Outcome<RoomLink> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM creations WHERE request_key=?", key).toArray()[0];
    if (old) return ok(JSON.parse(old.data) as RoomLink);
    if (this.ctx.storage.sql.exec<{ total: number }>("SELECT COUNT(*) AS total FROM rooms").one().total >= 20) return fail(409, "room_limit_reached");
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("INSERT INTO creations VALUES (?,?)", key, JSON.stringify(link));
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link));
      this.ctx.storage.sql.exec("DELETE FROM creations WHERE rowid NOT IN (SELECT rowid FROM creations ORDER BY rowid DESC LIMIT 128)");
    });
    return ok(link);
  }
  addRoom(link: RoomLink): Outcome<RoomLink> {
    if (this.identity()?.state !== "active") return fail(401, "identity_unavailable");
    const existing = this.ctx.storage.sql.exec("SELECT room_id FROM rooms WHERE room_id=?", link.room_id).toArray().length;
    if (!existing && this.ctx.storage.sql.exec<{ total: number }>("SELECT COUNT(*) AS total FROM rooms").one().total >= 20) return fail(409, "room_limit_reached");
    this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rooms VALUES (?,?)", link.room_id, JSON.stringify(link));
    return ok(link);
  }
  listRooms(): RoomLink[] {
    return this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM rooms ORDER BY rowid DESC").toArray().map(row => JSON.parse(row.data) as RoomLink);
  }
  removeRoom(roomId: string): void { this.ctx.storage.sql.exec("DELETE FROM rooms WHERE room_id=?", roomId); }
  beginDelete(): RoomLink[] {
    const identity = this.identity();
    if (!identity) return [];
    identity.state = "deleting";
    this.ctx.storage.sql.exec("UPDATE identity SET data=? WHERE id=1", JSON.stringify(identity));
    return this.listRooms();
  }
  finishDelete(): void {
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("DELETE FROM identity");
      this.ctx.storage.sql.exec("DELETE FROM rooms");
      this.ctx.storage.sql.exec("DELETE FROM creations");
    });
  }
}
