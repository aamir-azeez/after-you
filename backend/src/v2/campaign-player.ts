import { ApiError, canonicalJson, equalHash, fail, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, isObject, ok, type Outcome } from "../protocol";
import { roomLinkVersion, validRoomLink, type RoomLink } from "../room-links";
import { boundedCampaign } from "./campaign-protocol";
import { campaignCreation, validCampaignCreation, type CampaignCreation } from "./campaign-creation-intent";
import { readCreation } from "./creation-intent";
import type { CampaignKey } from "./campaign-types";

type LinkRow = { rowid: string; room_id: string; data: string };
type CreationRow = { rowid: string; request_key: string; data: string };
type Capture = { identity: { rowid: string; id: number; data: string }[]; rooms: LinkRow[]; creations: CreationRow[] };
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
function need(value: unknown, code = "campaign_player_unavailable", status = 409): asserts value { if (!value) throw new ApiError(status, code); }
function failure(e: unknown): Outcome<never> { return e instanceof ApiError ? fail(e.status, e.code) : fail(409, "campaign_player_unavailable"); }
function capture(storage: DurableObjectStorage): Capture {
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
  need(validCampaignCreation(previous), "idempotency_version_mismatch"); need(same(previous.campaign_key, campaignKey), "idempotency_campaign_mismatch");
  const link = saved.rooms.find(r => r.room_id === previous.link.room_id);
  // A removed link is not permission to initialize the same allocation again.
  need(link && same(JSON.parse(link.data), previous.link), "campaign_link_unavailable");
  return structuredClone(previous);
}
function guard(storage: DurableObjectStorage, saved: Capture, owner: string, deviceHash: string): void {
  const now = capture(storage); authorize(now, owner, deviceHash); need(same(now, saved), "campaign_player_changed");
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
    return storage.transactionSync(() => {
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
export function reserveCampaignGuestLink(storage: DurableObjectStorage, owner: string, roomId: string, deviceHash: string): Outcome<RoomLink> {
  try {
    need(typeof roomId === "string" && ID_PATTERN.test(roomId), "invalid_campaign_room", 422);
    const saved = capture(storage); authorize(saved, owner, deviceHash); const proposed: RoomLink = { room_id: roomId, invite_code: "", host: false, api_version: 3 };
    return storage.transactionSync(() => {
      guard(storage, saved, owner, deviceHash); const old = saved.rooms.find(r => r.room_id === roomId);
      if (old) { need(same(JSON.parse(old.data), proposed), "room_version_conflict"); return ok(proposed); }
      need(saved.rooms.length < 20, "room_limit_reached"); storage.sql.exec("INSERT INTO rooms VALUES(?,?)", roomId, JSON.stringify(proposed)); return ok(proposed);
    });
  } catch (e) { return failure(e); }
}
