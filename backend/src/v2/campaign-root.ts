import { ApiError, canonicalJson, fail, ID_PATTERN, isObject, ok, type Outcome } from "../protocol";
import { notificationAlarmOwned } from "../notification-storage";
import { chapter } from "./chapters";
import { campaignCreation, type CampaignCreation } from "./campaign-creation-intent";
import { boundedCampaign, campaignDefinition, campaignJoin, type CampaignDefinitionResolver } from "./campaign-protocol";
import { campaignAccessUnchanged, prepareCampaignAccess } from "./campaign-source";
import { emptyCampaignRoomStorage } from "./campaign-target";
import { roomV2StorageSchema } from "./snapshot";
import { initializeCampaignStorageSchema, initializeCampaignJoinSchema } from "./storage-schema";
import type { CampaignDefinition, CampaignEnvelope, CampaignView, CampaignJoin } from "./campaign-types";
import { campaignAdmissionHash, campaignAdmissionRequest } from "./campaign-admission-intent";
import { MAX_CAMPAIGN_JOIN_ATTEMPTS, joinFact, type CampaignJoinFact } from "./campaign-join-storage";
import type { CampaignJoinCancellation } from "./campaign-join-cancellation";
import type { StoredCampaignAnchorV2, StoredCampaignMemberV2 } from "./campaign-storage";
import type { RoomStateV2 } from "./room";

export type CampaignRootInitialization = { schema_version: 1; host_id: string; intent: CampaignCreation };
export type CampaignRootInitialized = { schema_version: 1; status: "initialized"; created: boolean; campaign: CampaignView };
const emptyResolver: CampaignDefinitionResolver = () => undefined;
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
function need(value: unknown, code = "campaign_root_unavailable", status = 409): asserts value { if (!value) throw new ApiError(status, code); }
function failure(e: unknown): Outcome<never> { return e instanceof ApiError ? fail(e.status, e.code) : fail(409, "campaign_root_unavailable"); }
function exact(value: unknown, keys: string[]): Record<string, unknown> { need(isObject(value) && Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k)), "invalid_campaign_root", 422); return value; }
function project(v: CampaignView, owner: string): CampaignView {
  need(v.host_id === owner || v.guest_id === owner, "campaign_owner_mismatch", 403);
  return structuredClone(v.host_id === owner ? v : { ...v, player_slot: "p1", invite_code: null, invite_expires_at: null });
}
function durable(storage: DurableObjectStorage): { anchor: StoredCampaignAnchorV2; member: StoredCampaignMemberV2; gameplay: RoomStateV2 } {
  return { anchor: JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM campaign_anchor WHERE id=1").one().data) as StoredCampaignAnchorV2,
    member: JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member WHERE id=1").one().data) as StoredCampaignMemberV2,
    gameplay: JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data) as RoomStateV2 };
}
async function initialization(value: unknown, resolver: CampaignDefinitionResolver): Promise<{ input: CampaignRootInitialization; definition: CampaignDefinition }> {
  const x = exact(value, ["schema_version", "host_id", "intent"]);
  need(x.schema_version === 1 && typeof x.host_id === "string" && ID_PATTERN.test(x.host_id), "invalid_campaign_root", 422);
  const input = x as CampaignRootInitialization;
  // Freeze both the proposed allocation and the finite registered definition
  // before hash validation yields to another event.
  const proposed = resolver(input.intent?.campaign_key), frozen = proposed ? structuredClone(proposed) : undefined;
  need(frozen, "unsupported_campaign", 422);
  const intent = await campaignCreation(input.intent); need(intent, "invalid_campaign_creation", 422);
  const definition = await campaignDefinition(frozen, pin => {
    try { const selected = chapter(pin); return selected.premium === pin.premium && (selected.supported_simulation_versions ?? [selected.simulation_version]).includes(pin.simulation_version); } catch { return false; }
  });
  need(same(intent.campaign_key, { campaign_id: definition.campaign_id, campaign_version: definition.campaign_version, definition_hash: definition.definition_hash }), "campaign_binding_mismatch");
  return { input: { schema_version: 1, host_id: input.host_id, intent }, definition };
}

/** Caller supplies an authenticated, durable Player reservation. No HTTP route,
 * Player mutation or account/provider lookup is performed inside this helper. */
export async function initializeCampaignRoot(storage: DurableObjectStorage, value: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignRootInitialized>> {
  try {
    boundedCampaign(value, 4096); const detached = structuredClone(value);
    const version = roomV2StorageSchema(storage), empty = emptyCampaignRoomStorage(storage, version);
    need(!empty || version !== 7, "campaign_root_collision");
    const { input, definition } = await initialization(detached, resolver), { intent, host_id } = input;
    const access = empty ? null : await prepareCampaignAccess(storage, resolver);
    need(empty || access?.anchor, "campaign_root_collision");
    return await storage.transaction(async () => {
      const alarm = await storage.getAlarm();
      need(roomV2StorageSchema(storage) === version && notificationAlarmOwned(storage, "RoomV2", alarm), "campaign_state_changed");
      if (empty) {
        need(emptyCampaignRoomStorage(storage, version) && alarm === null, "campaign_state_changed");
        const selected = chapter(definition.chapters[0]), now = Date.now(), created = new Date(now).toISOString(), expires = new Date(now + 7 * 86_400_000).toISOString();
        const gameplay: RoomStateV2 = { schema_version: 2, room_id: intent.link.room_id, revision: 0, branch: 0, stage_index: 0, ...selected.key,
          simulation_version: definition.chapters[0].simulation_version, host_id, guest_id: null, checkpoint: selected.initial(), a_turn_id: null, completed_pair_ids: [],
          invite_code: intent.link.invite_code, invite_expires_at: expires, created_at: created, updated_at: created };
        const control: CampaignView = { schema_version: 2, api_version: 2, campaign_room_id: intent.link.room_id, campaign_key: intent.campaign_key, revision: 0,
          host_id, guest_id: null, player_slot: "p0", state: "waiting", current_index: 0, chapters: definition.chapters.map((pin, index) => ({ chapter: structuredClone(pin), room_id: index === 0 ? intent.link.room_id : null, completion: null })),
          transition: null, invite_code: intent.link.invite_code, invite_expires_at: expires, activation: null };
        const anchor: StoredCampaignAnchorV2 = { schema_version: 2, state: "live", definition: structuredClone(definition), control, pending: null, closed_before_branches: definition.chapters.map(() => 0), deletion: null, activation: null };
        const member: StoredCampaignMemberV2 = { schema_version: 2, campaign_room_id: intent.link.room_id, campaign_key: intent.campaign_key, room_id: intent.link.room_id,
          chapter_index: 0, chapter: structuredClone(definition.chapters[0]), host_id, guest_id: null, transition_id: null, status: "active", seal: null, incoming: null };
        initializeCampaignStorageSchema(storage);
        storage.sql.exec("INSERT INTO room VALUES(1,?)", JSON.stringify(gameplay));
        storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(member));
        storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify(anchor));
      } else {
        need(access?.anchor && campaignAccessUnchanged(storage, access), "campaign_state_changed");
        need(access.anchor.control.state !== "deleting" && access.member.status !== "deleting", "campaign_deleting");
        need(access.member.room_id === intent.link.room_id && access.member.room_id === access.member.campaign_room_id && access.member.host_id === host_id && same(access.anchor.definition, definition) &&
          same(access.member.campaign_key, intent.campaign_key) && access.gameplay?.invite_code === intent.link.invite_code, "campaign_root_binding_mismatch");
      }
      const saved = durable(storage);
      return ok({ schema_version: 1, status: "initialized", created: empty, campaign: project(saved.anchor.control, host_id) });
    });
  } catch (e) { return failure(e); }
}

/** Caller reserves the guest's api3 link/capacity first, then reauthorizes and
 * handles deletion/cancellation through the later trusted lifecycle adapter. */
export async function joinCampaignRoot(storage: DurableObjectStorage, owner: string, value: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignEnvelope>> {
  try {
    boundedCampaign(value, 4096); const detached = structuredClone(value); need(ID_PATTERN.test(owner), "invalid_campaign_owner", 422);
    const access = await prepareCampaignAccess(storage, resolver); need(access?.anchor && access.member.room_id === access.member.campaign_room_id, "campaign_root_unavailable");
    const a = access.anchor, local: CampaignDefinitionResolver = key => same(key, a.control.campaign_key) ? a.definition : undefined;
    const input = campaignJoin(detached, local);
    need(same(input.campaign_key, a.control.campaign_key) && input.invite_code === a.control.invite_code, "campaign_binding_mismatch");
    const requestHash = await campaignAdmissionHash(owner, "join", input);
    const rows = access.captured.tables[3]?.rows ?? [], old = rows.find(row => row.request_key === owner + ":" + input.idempotency_key);
    if (old) need(old.request_hash === requestHash && same(joinFact(JSON.parse(String(old.data))).request, input), "idempotency_campaign_mismatch");
    return await storage.transaction(async () => {
      const alarm = await storage.getAlarm();
      need(notificationAlarmOwned(storage, "RoomV2", alarm), "campaign_state_changed");
      need(campaignAccessUnchanged(storage, access), "campaign_state_changed");
      need(a.control.state !== "deleting" && access.member.status !== "deleting", "campaign_deleting");
      if (owner === a.control.host_id || owner === a.control.guest_id) return ok({ campaign: project(a.control, owner) });
      need(!old, "campaign_admission_cancelled");
      need(rows.length < MAX_CAMPAIGN_JOIN_ATTEMPTS, "campaign_join_history_full");
      need(a.control.state === "waiting" && a.control.guest_id === null && access.member.status === "active" && access.member.guest_id === null && access.gameplay?.guest_id === null, "campaign_full");
      need(typeof a.control.invite_expires_at === "string" && Date.now() <= Date.parse(a.control.invite_expires_at), "invite_expired", 410);
      const gameplay = structuredClone(access.gameplay) as RoomStateV2, member = structuredClone(access.member), next = structuredClone(a);
      need(gameplay.revision < Number.MAX_SAFE_INTEGER && next.control.revision < Number.MAX_SAFE_INTEGER, "campaign_revision_limit");
      // Host A may already be accepted while waiting. Preserve every recording,
      // checkpoint, photo and operation byte; only membership and clocks change.
      gameplay.guest_id = owner; gameplay.revision++; gameplay.updated_at = new Date().toISOString();
      member.guest_id = owner; next.control.guest_id = owner; next.control.state = "active"; next.control.revision++;
      const fact: CampaignJoinFact = { schema_version: 1, player_id: owner, request: input, status: "accepted" };
      initializeCampaignJoinSchema(storage);
      storage.sql.exec("INSERT INTO campaign_join_attempts VALUES(?,?,?)", owner + ":" + input.idempotency_key, requestHash, JSON.stringify(fact));
      storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(gameplay));
      storage.sql.exec("UPDATE campaign_member SET data=? WHERE id=1", JSON.stringify(member));
      storage.sql.exec("UPDATE campaign_anchor SET data=? WHERE id=1", JSON.stringify(next));
      return ok({ campaign: project(durable(storage).anchor.control, owner) });
    });
  } catch (e) { return failure(e); }
}

/** The anchor fence wins against any delayed Join with this exact attempt key.
 * This helper never mutates Player links or trusts a caller-supplied decision. */
export async function cancelCampaignJoinRoot(storage: DurableObjectStorage, owner: string, value: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignJoinCancellation>> {
  try {
    const input = campaignAdmissionRequest(value, "join") as CampaignJoin; need(ID_PATTERN.test(owner), "invalid_campaign_owner", 422);
    const access = await prepareCampaignAccess(storage, resolver); need(access?.anchor && access.member.room_id === access.member.campaign_room_id, "campaign_root_unavailable");
    const a = access.anchor;
    need(same(input.campaign_key, a.control.campaign_key) && input.invite_code === a.control.invite_code, "campaign_binding_mismatch");
    const requestHash = await campaignAdmissionHash(owner, "join", input);
    const rows = access.captured.tables[3]?.rows ?? [], old = rows.find(row => row.request_key === owner + ":" + input.idempotency_key);
    if (old) need(old.request_hash === requestHash && same(joinFact(JSON.parse(String(old.data))).request, input), "idempotency_campaign_mismatch");
    return await storage.transaction(async () => {
      const alarm = await storage.getAlarm();
      need(notificationAlarmOwned(storage, "RoomV2", alarm), "campaign_state_changed");
      need(campaignAccessUnchanged(storage, access), "campaign_state_changed");
      const common = { schema_version: 1 as const, admission: "join" as const, operation: "campaign_admission_cancel" as const,
        player_id: owner, idempotency_key: input.idempotency_key, request_hash: requestHash, campaign_room_id: access.member.room_id, campaign_key: input.campaign_key };
      // Current membership wins the response without reopening an older closed key.
      if (owner === a.control.host_id || owner === a.control.guest_id) return ok({ ...common, status: "accepted", campaign: project(a.control, owner) });
      if (!old) {
        need(a.control.state !== "deleting" && access.member.status !== "deleting", "campaign_deleting");
        need(rows.length < MAX_CAMPAIGN_JOIN_ATTEMPTS, "campaign_join_history_full");
        const fact: CampaignJoinFact = { schema_version: 1, player_id: owner, request: input, status: "cancelled" };
        initializeCampaignJoinSchema(storage);
        storage.sql.exec("INSERT INTO campaign_join_attempts VALUES(?,?,?)", owner + ":" + input.idempotency_key, requestHash, JSON.stringify(fact));
      } else need(joinFact(JSON.parse(String(old.data))).status === "cancelled", "campaign_state_changed");
      return ok({ ...common, status: "cancelled", campaign: null });
    });
  } catch (e) { return failure(e); }
}
