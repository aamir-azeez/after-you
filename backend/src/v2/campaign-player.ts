import { ApiError, canonicalJson, digest, equalHash, fail, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, isObject, ok, type Outcome } from "../protocol";
import { roomLinkVersion, validRoomLink, type RoomLink } from "../room-links";
import { boundedCampaign } from "./campaign-protocol";
import { campaignCreation, validCampaignCreation, type CampaignCreation } from "./campaign-creation-intent";
import { readCreation } from "./creation-intent";
import type { CampaignKey } from "./campaign-types";
import { campaignAdmissionHash, campaignAdmissionIntent, campaignAdmissionRequest, cancellationReceipt, validCampaignAdmissionIntent, type CampaignAdmissionIntent, type CampaignCancellationReceipt } from "./campaign-admission-intent";
import { campaignJoinCancellationAck, type CampaignJoinCancellation } from "./campaign-join-cancellation";
import type { CampaignDefinitionResolver } from "./campaign-protocol";
import type { CampaignJoin } from "./campaign-types";
import { currentSnapshotSchema } from "../snapshot";
import { notificationAlarmOwned } from "../notification-storage";
import { presenceAlarmOwned } from "../presence";

type LinkRow = { rowid: string; room_id: string; data: string };
type CreationRow = { rowid: string; request_key: string; data: string };
type Capture = { identity: { rowid: string; id: number; data: string }[]; rooms: LinkRow[]; creations: CreationRow[] };
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
function need(value: unknown, code = "campaign_player_unavailable", status = 409): asserts value { if (!value) throw new ApiError(status, code); }
function failure(e: unknown): Outcome<never> { return e instanceof ApiError ? fail(e.status, e.code) : fail(409, "campaign_player_unavailable"); }
function capture(storage: DurableObjectStorage): Capture {
  currentSnapshotSchema(storage, "Player");
  const identity = storage.sql.exec<{ rowid: string; id: number; data: string }>("SELECT CAST(rowid AS TEXT) AS rowid,id,data FROM identity ORDER BY rowid LIMIT 2").toArray();
  const rooms = storage.sql.exec<LinkRow>("SELECT CAST(rowid AS TEXT) AS rowid,room_id,data FROM rooms ORDER BY rowid LIMIT 21").toArray();
  const creations = storage.sql.exec<CreationRow>("SELECT CAST(rowid AS TEXT) AS rowid,request_key,data FROM creations ORDER BY rowid LIMIT 129").toArray();
  need(identity.length === 1 && identity[0].rowid === "1" && identity[0].id === 1 && rooms.length <= 20 && creations.length <= 128);
  return { identity, rooms, creations };
}
function authorize(saved: Capture, owner: string, deviceHash: string): void {
  need(typeof owner === "string" && ID_PATTERN.test(owner) && typeof deviceHash === "string" && HASH_PATTERN.test(deviceHash), "identity_unavailable", 401);
  const identity: unknown = JSON.parse(saved.identity[0].data);
  need(isObject(identity) && identity.player_id === owner && identity.state === "active" && typeof identity.device_hash === "string" && equalHash(identity.device_hash, deviceHash), "identity_unavailable", 401);
}
function key(value: unknown): asserts value is CampaignKey {
  boundedCampaign(value, 4096);
  need(isObject(value) && Object.keys(value).length === 3 && typeof value.campaign_id === "string" && /^[a-z][a-z0-9-]{0,47}$/.test(value.campaign_id) &&
    typeof value.campaign_version === "number" && Number.isSafeInteger(value.campaign_version) && value.campaign_version > 0 && typeof value.definition_hash === "string" && HASH_PATTERN.test(value.definition_hash), "invalid_campaign_key", 422);
}
function existing(saved: Capture, requestKey: string, campaignKey: CampaignKey): CampaignCreation | null {
  const row = saved.creations.find(r => r.request_key === requestKey); if (!row) return null;
  const previous: unknown = JSON.parse(row.data);
  if (validCampaignAdmissionIntent(previous)) {
    need(previous.admission === "create" && same(previous.request.campaign_key, campaignKey), "idempotency_campaign_mismatch");
    need(previous.state !== "closed", "campaign_admission_cancelled");
  }
  need(validCampaignCreation(previous), "idempotency_version_mismatch"); need(same(previous.campaign_key, campaignKey), "idempotency_campaign_mismatch");
  const link = saved.rooms.find(r => r.room_id === previous.link.room_id);
  // A removed link is not permission to initialize the same allocation again.
  need(link && same(JSON.parse(link.data), previous.link), "campaign_link_unavailable");
  return structuredClone(previous);
}
function guard(storage: DurableObjectStorage, saved: Capture, owner: string, deviceHash: string): void {
  const now = capture(storage); authorize(now, owner, deviceHash); need(same(now, saved), "campaign_player_changed");
}
async function guardedTransaction<T>(storage: DurableObjectStorage, saved: Capture, owner: string, deviceHash: string, apply: () => T): Promise<T> {
  return storage.transaction(async () => {
    const alarm = await storage.getAlarm();
    need(notificationAlarmOwned(storage, "Player", null) && presenceAlarmOwned(storage, alarm), "campaign_player_unavailable");
    guard(storage, saved, owner, deviceHash); return apply();
  });
}

/** Protect all campaign/unknown intents, including missing-link holds. This
 * replaces only the old blanket pruning statements. With ordinary-only rows it
 * keeps the same newest128 history. A full protected set holds instead of turning
 * an old campaign retry into a new allocation. Caller owns the write transaction. */
export function pruneCreationHistory(storage: DurableObjectStorage): void {
  const rows = storage.sql.exec<CreationRow>("SELECT CAST(rowid AS TEXT) AS rowid,request_key,data FROM creations ORDER BY creations.rowid DESC LIMIT 130").toArray();
  need(rows.length <= 129, "creation_history_unavailable"); if (rows.length <= 128) return;
  const ordinary = rows.filter((row, index) => {
    if (index === 0) return false; // never erase the just-saved request
    try {
      const value: unknown = JSON.parse(row.data);
      if (validCampaignCreation(value)) return false;
      return validRoomLink(value) && [1, 2].includes(roomLinkVersion(value)) || readCreation(value) !== null;
    } catch { return false; }
  });
  need(ordinary.length >= rows.length - 128, "creation_history_full");
  for (const row of ordinary.reverse().slice(0, rows.length - 128)) storage.sql.exec("DELETE FROM creations WHERE request_key=?", row.request_key);
}

/** Read-only admission lookup. Full caller credentials are rechecked locally. */
export function readCampaignCreation(storage: DurableObjectStorage, owner: string, requestKey: string, campaignKey: unknown, deviceHash: string): Outcome<CampaignCreation | null> {
  try { need(typeof requestKey === "string" && IDEMPOTENCY_PATTERN.test(requestKey), "invalid_idempotency_key", 422); key(campaignKey);
    const saved = capture(storage); authorize(saved, owner, deviceHash); return ok(existing(saved, requestKey, campaignKey));
  } catch (e) { return failure(e); }
}
/** Caller first checks a retained exact intent, then performs fresh admission.
 * Full intent plus the one host api3 link are installed in one local transaction. */
export async function reserveCampaignCreation(storage: DurableObjectStorage, owner: string, requestKey: string, value: unknown, deviceHash: string): Promise<Outcome<CampaignCreation>> {
  try {
    boundedCampaign(value, 4096); const detached = structuredClone(value); need(typeof requestKey === "string" && IDEMPOTENCY_PATTERN.test(requestKey), "invalid_idempotency_key", 422);
    const saved = capture(storage); authorize(saved, owner, deviceHash);
    const proposed = await campaignCreation(detached); need(proposed, "invalid_campaign_creation", 422);
    return await guardedTransaction(storage, saved, owner, deviceHash, () => {
      guard(storage, saved, owner, deviceHash); const previous = existing(saved, requestKey, proposed.campaign_key); if (previous) return ok(previous);
      need(!saved.rooms.some(r => r.room_id === proposed.link.room_id), "room_version_conflict"); need(saved.rooms.length < 20, "room_limit_reached");
      // Preserve every admitted campaign key. Known ordinary history can still be
      // compacted using the same protected planner as ordinary creation.
      storage.sql.exec("INSERT INTO creations VALUES(?,?)", requestKey, JSON.stringify(proposed));
      storage.sql.exec("INSERT INTO rooms VALUES(?,?)", proposed.link.room_id, JSON.stringify(proposed.link));
      pruneCreationHistory(storage); return ok(structuredClone(proposed));
    });
  } catch (e) { return failure(e); }
}
/** This is a durable capacity reservation, not proof of membership. Unknown Join
 * outcomes retain it. Only a later fenced cancellation/cascade may remove it. */
export function reserveCampaignGuestLink(_storage: DurableObjectStorage, _owner: string, _roomId: string, _deviceHash: string): Outcome<RoomLink> {
  // Retained binding has no attempt key and cannot bypass a closed Join fence.
  return fail(409, "campaign_join_attempt_required");
}

export async function reserveCampaignJoin(storage: DurableObjectStorage, owner: string, value: unknown, deviceHash: string): Promise<Outcome<RoomLink>> {
  try {
    const request = campaignAdmissionRequest(value, "join") as CampaignJoin, saved = capture(storage); authorize(saved, owner, deviceHash);
    const requestHash = await campaignAdmissionHash(owner, "join", request), roomId = (await digest("v2:" + request.invite_code)).slice(0,22);
    const proposed: RoomLink = { room_id: roomId, invite_code: "", host: false, api_version: 3 };
    const row = saved.creations.find(r => r.request_key === request.idempotency_key);
    const previous = row ? await campaignAdmissionIntent(JSON.parse(row.data), owner) : null;
    if (row) need(previous && previous.admission === "join" && same(previous.request, request) && previous.request_hash === requestHash, "idempotency_campaign_mismatch");
    return await guardedTransaction(storage, saved, owner, deviceHash, () => {
      guard(storage, saved, owner, deviceHash);
      const old = saved.rooms.find(r => r.room_id === roomId);
      if (previous) {
        need(previous.state === "open", "campaign_admission_cancelled");
        need(old && same(JSON.parse(old.data), proposed), "campaign_link_unavailable"); return ok(proposed);
      }
      if (old) need(same(JSON.parse(old.data), proposed), "room_version_conflict");
      else need(saved.rooms.length < 20, "room_limit_reached");
      const intent: CampaignAdmissionIntent = { creation_schema: 3, admission: "join", player_id: owner, request, request_hash: requestHash, room_id: roomId, state: "open" };
      storage.sql.exec("INSERT INTO creations VALUES(?,?)", request.idempotency_key, JSON.stringify(intent));
      if (!old) storage.sql.exec("INSERT INTO rooms VALUES(?,?)", roomId, JSON.stringify(proposed));
      pruneCreationHistory(storage); return ok(proposed);
    });
  } catch (e) { return failure(e); }
}

/** Fixed internal caller passes the actual anchor acknowledgement. Exact parsing
 * proves binding; only the anchor RPC supplies authority. No public ack endpoint. */
export async function finalizeCampaignJoinCancellation(storage: DurableObjectStorage, owner: string, value: unknown, acknowledged: unknown, deviceHash: string, resolver: CampaignDefinitionResolver = () => undefined): Promise<Outcome<CampaignJoinCancellation>> {
  try {
    const request = campaignAdmissionRequest(value, "join") as CampaignJoin;
    boundedCampaign(acknowledged, 16384); const detachedAck = structuredClone(acknowledged);
    const saved = capture(storage); authorize(saved, owner, deviceHash);
    const ack = await campaignJoinCancellationAck(detachedAck, owner, request, resolver);
    const row = saved.creations.find(r => r.request_key === request.idempotency_key);
    const previous = row ? await campaignAdmissionIntent(JSON.parse(row.data), owner) : null;
    if (row) need(previous && previous.admission === "join" && same(previous.request, request) && previous.request_hash === ack.request_hash, "idempotency_campaign_mismatch");
    let otherOpen = false;
    for (const other of saved.creations) {
      if (other.request_key === request.idempotency_key) continue;
      const raw: unknown = JSON.parse(other.data);
      if (validCampaignAdmissionIntent(raw)) {
        const known = await campaignAdmissionIntent(raw, owner); need(known && known.request.idempotency_key === other.request_key);
        otherOpen ||= known.admission === "join" && known.room_id === ack.campaign_room_id && known.state === "open";
      } else need(validCampaignCreation(raw) || validRoomLink(raw) || readCreation(raw), "campaign_player_unavailable");
    }
    return await guardedTransaction(storage, saved, owner, deviceHash, () => {
      guard(storage, saved, owner, deviceHash);
      const oldLink = saved.rooms.find(r => r.room_id === ack.campaign_room_id);
      if (ack.status === "accepted") {
        // Never reopen a closed A if B later established this membership.
        const expected: RoomLink = { room_id: ack.campaign_room_id, api_version: 3, host: ack.campaign!.host_id === owner,
          invite_code: ack.campaign!.host_id === owner ? ack.campaign!.invite_code! : "" };
        need(oldLink && same(JSON.parse(oldLink.data), expected), "campaign_link_unavailable");
        return ok(ack);
      }
      const expected: RoomLink = { room_id: ack.campaign_room_id, invite_code: "", host: false, api_version: 3 };
      if (oldLink) need(same(JSON.parse(oldLink.data), expected), "room_version_conflict");
      const closed: CampaignAdmissionIntent = { creation_schema: 3, admission: "join", player_id: owner, request, request_hash: ack.request_hash, room_id: ack.campaign_room_id, state: "closed" };
      if (!row) storage.sql.exec("INSERT INTO creations VALUES(?,?)", request.idempotency_key, JSON.stringify(closed));
      else if (previous?.state !== "closed") storage.sql.exec("UPDATE creations SET data=? WHERE request_key=?", JSON.stringify(closed), request.idempotency_key);
      if (oldLink && !otherOpen) storage.sql.exec("DELETE FROM rooms WHERE room_id=? AND data=?", ack.campaign_room_id, oldLink.data);
      pruneCreationHistory(storage); return ok(ack);
    });
  } catch (e) { return failure(e); }
}

export type CampaignCreateCancellation = { status: "cancelled"; receipt: CampaignCancellationReceipt } | { status: "admitted"; intent: CampaignCreation };
/** Local monotone fence. The fixed caller must recover admitted allocations;
 * it cannot turn an existing reservation into a cancellation or recreate a link. */
export async function cancelCampaignCreation(storage: DurableObjectStorage, owner: string, value: unknown, deviceHash: string): Promise<Outcome<CampaignCreateCancellation>> {
  try {
    const request = campaignAdmissionRequest(value, "create"), saved = capture(storage); authorize(saved, owner, deviceHash);
    const requestHash = await campaignAdmissionHash(owner, "create", request);
    const row = saved.creations.find(r => r.request_key === request.idempotency_key);
    const raw: unknown = row ? JSON.parse(row.data) : null;
    const closed = raw && validCampaignAdmissionIntent(raw) ? await campaignAdmissionIntent(raw, owner) : null;
    return await guardedTransaction(storage, saved, owner, deviceHash, () => {
      guard(storage, saved, owner, deviceHash);
      if (row) {
        if (closed) {
          need(closed.admission === "create" && closed.request_hash === requestHash && same(closed.request, request), "idempotency_campaign_mismatch");
          need(closed.state === "closed", "campaign_player_unavailable");
          return ok({ status: "cancelled", receipt: cancellationReceipt(closed) });
        }
        // existing() verifies the canonical api3 link; missing links remain a
        // durable hold and cannot be resurrected by the cancellation path.
        const admitted = existing(saved, request.idempotency_key, request.campaign_key);
        need(admitted, "campaign_player_unavailable"); return ok({ status: "admitted", intent: admitted });
      }
      const intent: CampaignAdmissionIntent = { creation_schema: 3, admission: "create", player_id: owner, request,
        request_hash: requestHash, state: "closed", room_id: null };
      storage.sql.exec("INSERT INTO creations VALUES(?,?)", request.idempotency_key, JSON.stringify(intent));
      pruneCreationHistory(storage); return ok({ status: "cancelled", receipt: cancellationReceipt(intent) });
    });
  } catch (e) { return failure(e); }
}
