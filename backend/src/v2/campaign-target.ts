import { ApiError, canonicalJson, digest, fail, HASH_PATTERN, isObject, ok, type Outcome } from "../protocol";
import { notificationAlarmOwned, notificationTables } from "../notification-storage";
import { chapter } from "./chapters";
import { boundedCampaign, type CampaignDefinitionResolver } from "./campaign-protocol";
import { campaignAccessUnchanged, prepareCampaignAccess, type SourceBinding } from "./campaign-source";
import { CAMPAIGN_TABLES, validateCampaignStorage, type StoredCampaignMemberV2 } from "./campaign-storage";
import type { CampaignOrigin, CampaignTargetIntent } from "./campaign-types";
import type { RoomStateV2 } from "./room";
import { roomV2StorageDefinitions, roomV2StorageSchema } from "./snapshot";
import { initializeCampaignStorageSchema } from "./storage-schema";

export type TargetBinding = Omit<SourceBinding, "member_transition_id"> & { member_transition_id: string };
export type TargetInitializeRequest = { schema_version: 1; binding: TargetBinding; origin: CampaignOrigin; target_intent: CampaignTargetIntent };
export type TargetActivateRequest = TargetInitializeRequest & { accepted_revision: number };
type TargetFact = { schema_version: 1; binding: TargetBinding; origin: CampaignOrigin; target_intent: CampaignTargetIntent; created_at: string; invite_expires_at: string };
export type TargetInitialized = TargetFact & { status: "initialized" };
export type TargetActivated = TargetFact & { status: "activated"; accepted_revision: number };
const emptyResolver: CampaignDefinitionResolver = () => undefined;
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
function need(value: unknown, code = "campaign_target_unavailable", status = 409): asserts value { if (!value) throw new ApiError(status, code); }
function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  need(isObject(value) && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)), "invalid_campaign_target", 422);
  return value;
}
function integer(value: unknown): asserts value is number { need(typeof value === "number" && Number.isSafeInteger(value) && value >= 0, "invalid_campaign_target", 422); }
function iso(value: unknown): asserts value is string {
  need(typeof value === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value, "invalid_campaign_target", 422);
}
function memberFor(input: TargetInitializeRequest): StoredCampaignMemberV2 {
  const b = input.binding;
  return { schema_version: 2, campaign_room_id: b.campaign_room_id, campaign_key: structuredClone(b.campaign_key), room_id: b.room_id,
    chapter_index: b.chapter_index, chapter: structuredClone(b.chapter), host_id: b.host_id, guest_id: b.guest_id,
    transition_id: b.member_transition_id, status: "provisional", seal: null, incoming: { origin: structuredClone(input.origin), accepted_revision: null } };
}
async function request(value: unknown, activation: boolean, resolver: CampaignDefinitionResolver): Promise<TargetInitializeRequest | TargetActivateRequest> {
  boundedCampaign(value, 4096);
  const x = exact(structuredClone(value), ["schema_version", "binding", "origin", "target_intent", ...(activation ? ["accepted_revision"] : [])]);
  need(x.schema_version === 1, "invalid_campaign_target", 422);
  const b = exact(x.binding, ["campaign_room_id", "campaign_key", "room_id", "chapter_index", "chapter", "host_id", "guest_id", "member_transition_id"]);
  need(typeof b.member_transition_id === "string" && HASH_PATTERN.test(b.member_transition_id), "invalid_campaign_target", 422);
  const target = exact(x.target_intent, ["room_id", "invite_code", "index", "chapter"]);
  need(target.room_id === b.room_id && target.index === b.chapter_index && same(target.chapter, b.chapter), "campaign_target_binding_mismatch");
  need(typeof target.invite_code === "string" && /^[A-F0-9]{20}$/.test(target.invite_code), "invalid_campaign_target", 422);
  const input = x as TargetInitializeRequest | TargetActivateRequest, candidate = memberFor(input);
  // Freeze the trusted registry entry before the shared validator's hash await.
  const resolved = resolver(candidate.campaign_key), definition = resolved ? structuredClone(resolved) : undefined;
  const local: CampaignDefinitionResolver = key => same(key, candidate.campaign_key) ? definition : undefined;
  const rows = CAMPAIGN_TABLES.map((table, index) => ({ name: table.name, rows: index === 1 ? [{ rowid: "1", id: 1, data: JSON.stringify(candidate) }] : [] }));
  await validateCampaignStorage(rows, null, true, local);
  need((await digest("v2:" + target.invite_code)).slice(0, 22) === b.room_id, "campaign_target_binding_mismatch");
  if (activation) { integer(x.accepted_revision); need(x.accepted_revision > input.origin.expected_revision, "campaign_publication_mismatch"); }
  return input;
}
export async function campaignTargetInitialization(value: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<TargetInitializeRequest> {
  return await request(value, false, resolver) as TargetInitializeRequest;
}
export async function campaignTargetActivation(value: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<TargetActivateRequest> {
  return await request(value, true, resolver) as TargetActivateRequest;
}
async function acknowledgement(value: unknown, expected: unknown, activation: boolean, resolver: CampaignDefinitionResolver): Promise<TargetInitialized | TargetActivated> {
  boundedCampaign(value, 4096);
  const x = exact(structuredClone(value), ["schema_version", "status", "binding", "origin", "target_intent", "created_at", "invite_expires_at", ...(activation ? ["accepted_revision"] : [])]);
  const input = await request(expected, activation, resolver);
  need(x.schema_version === 1 && x.status === (activation ? "activated" : "initialized"), "invalid_campaign_target_ack", 422);
  need(same(x.binding, input.binding) && same(x.origin, input.origin) && same(x.target_intent, input.target_intent), "campaign_target_binding_mismatch");
  iso(x.created_at); iso(x.invite_expires_at);
  need(Date.parse(x.invite_expires_at) - Date.parse(x.created_at) === 7 * 86_400_000, "invalid_campaign_target_ack", 422);
  if (activation) need(x.accepted_revision === (input as TargetActivateRequest).accepted_revision, "campaign_publication_mismatch");
  return x as TargetInitialized | TargetActivated;
}
export async function campaignTargetInitialized(value: unknown, expected: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<TargetInitialized> {
  return await acknowledgement(value, expected, false, resolver) as TargetInitialized;
}
export async function campaignTargetActivated(value: unknown, expected: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<TargetActivated> {
  return await acknowledgement(value, expected, true, resolver) as TargetActivated;
}

function emptyStorage(storage: DurableObjectStorage, version: number): boolean {
  return [...roomV2StorageDefinitions(version), ...notificationTables("RoomV2")].every(table => storage.sql.exec('SELECT 1 AS present FROM "' + table.name + '" LIMIT 1').toArray().length === 0);
}
function durableRows(storage: DurableObjectStorage): { member: StoredCampaignMemberV2; state: RoomStateV2 } {
  const member = JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member WHERE id=1").one().data) as StoredCampaignMemberV2;
  const state = JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data) as RoomStateV2;
  return { member, state };
}
function fact(member: StoredCampaignMemberV2, state: RoomStateV2): TargetFact {
  need(member.incoming !== null && member.transition_id !== null && member.guest_id !== null && member.room_id !== member.campaign_room_id);
  return { schema_version: 1, binding: { campaign_room_id: member.campaign_room_id, campaign_key: structuredClone(member.campaign_key), room_id: member.room_id,
    chapter_index: member.chapter_index, chapter: structuredClone(member.chapter), host_id: member.host_id, guest_id: member.guest_id, member_transition_id: member.transition_id },
    origin: structuredClone(member.incoming.origin), target_intent: { room_id: member.room_id, invite_code: state.invite_code, index: member.chapter_index, chapter: structuredClone(member.chapter) },
    created_at: state.created_at, invite_expires_at: state.invite_expires_at };
}
function matches(member: StoredCampaignMemberV2, state: RoomStateV2, input: TargetInitializeRequest): void {
  need(["provisional", "active", "sealed"].includes(member.status), "campaign_target_not_active");
  const saved = fact(member, state);
  need(same(saved.binding, input.binding) && same(saved.origin, input.origin) && same(saved.target_intent, input.target_intent), "campaign_target_binding_mismatch");
}
async function target(storage: DurableObjectStorage, value: unknown, activation: boolean, resolver: CampaignDefinitionResolver): Promise<Outcome<TargetInitialized | TargetActivated>> {
  try {
    boundedCampaign(value, 4096); const detached = structuredClone(value);
    const version = roomV2StorageSchema(storage), empty = emptyStorage(storage, version);
    // The shared access parser rejects legacy live authority and malformed sidecars.
    const access = empty ? null : await prepareCampaignAccess(storage, resolver);
    need(empty || access !== null, "campaign_target_collision");
    const input = await request(detached, activation, resolver);
    return await storage.transaction(async () => {
      // Default storage input gates protect this local await. All final checks and
      // writes after it are synchronous; no provider or definition work occurs here.
      const alarm = await storage.getAlarm();
      need(roomV2StorageSchema(storage) === version, "campaign_state_changed");
      need(notificationAlarmOwned(storage, "RoomV2", alarm), "campaign_target_unavailable");
      if (empty) {
        need(emptyStorage(storage, version) && alarm === null, "campaign_state_changed");
        need(!activation, "campaign_target_not_initialized");
        const selected = chapter(input.binding.chapter), now = Date.now(), created = new Date(now).toISOString();
        const state: RoomStateV2 = { schema_version: 2, room_id: input.binding.room_id, revision: 1, branch: 0, stage_index: 0, ...selected.key,
          simulation_version: input.binding.chapter.simulation_version, host_id: input.binding.host_id, guest_id: input.binding.guest_id,
          checkpoint: selected.initial(), a_turn_id: null, completed_pair_ids: [], invite_code: input.target_intent.invite_code,
          created_at: created, updated_at: created, invite_expires_at: new Date(now + 7 * 86_400_000).toISOString() };
        initializeCampaignStorageSchema(storage);
        storage.sql.exec("INSERT INTO room VALUES(1,?)", JSON.stringify(state));
        storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify(memberFor(input)));
      } else {
        need(access !== null && campaignAccessUnchanged(storage, access), "campaign_state_changed");
        need(access.gameplay !== null && access.gameplay.deleted !== true, "campaign_target_not_initialized");
        matches(access.member, access.gameplay as RoomStateV2, input);
        if (activation) {
          const accepted = (input as TargetActivateRequest).accepted_revision, member = access.member;
          need(member.incoming !== null, "campaign_target_binding_mismatch");
          if (member.status === "provisional") {
            need(member.incoming.accepted_revision === null && member.seal === null, "campaign_publication_mismatch");
            storage.sql.exec("UPDATE campaign_member SET data=? WHERE id=1", JSON.stringify({ ...member, status: "active", incoming: { origin: member.incoming.origin, accepted_revision: accepted } }));
          } else need(member.incoming.accepted_revision === accepted, "campaign_publication_mismatch");
        }
      }
      const saved = durableRows(storage), result = fact(saved.member, saved.state);
      if (!activation) return ok({ ...result, status: "initialized" });
      need(saved.member.incoming !== null && saved.member.incoming.accepted_revision !== null, "campaign_publication_mismatch");
      return ok({ ...result, status: "activated", accepted_revision: saved.member.incoming.accepted_revision });
    });
  } catch (error) { return error instanceof ApiError ? fail(error.status, error.code) : fail(409, "campaign_target_unavailable"); }
}

/** Trusted binding-only caller must separately prove its source-sealed pending intent. */
export async function initializeCampaignTarget(storage: DurableObjectStorage, value: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<TargetInitialized>> {
  return await target(storage, value, false, resolver) as Outcome<TargetInitialized>;
}
/** Trusted binding-only caller must separately prove its exact published activation debt. */
export async function activateCampaignTarget(storage: DurableObjectStorage, value: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<TargetActivated>> {
  return await target(storage, value, true, resolver) as Outcome<TargetActivated>;
}
