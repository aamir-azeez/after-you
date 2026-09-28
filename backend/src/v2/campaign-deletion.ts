import { ApiError, canonicalJson, fail, ID_PATTERN, isObject, ok, type Outcome } from "../protocol";
import { notificationAlarmOwned, notificationTables } from "../notification-storage";
import { REDO_TABLE, resetRedo } from "../redo-control";
import { boundedCampaign, campaignDefinition, type CampaignDefinitionResolver } from "./campaign-protocol";
import { campaignCreation } from "./campaign-creation-intent";
import { chapter } from "./chapters";
import { campaignAccessUnchanged, prepareCampaignAccess, type CampaignAccess } from "./campaign-source";
import { CAMPAIGN_TABLES, validateCampaignStorage, type StoredCampaignAnchorV2, type StoredCampaignMemberV2 } from "./campaign-storage";
import { CAMPAIGN_JOIN_TABLE } from "./campaign-join-storage";
import type { TargetBinding } from "./campaign-target";
import type { CampaignDefinition, CampaignOrigin } from "./campaign-types";
import { roomV2StorageDefinitions, roomV2StorageSchema } from "./snapshot";
import { initializeCampaignStorageSchema } from "./storage-schema";

export type CampaignDeleted = { schema_version: 1; status: "deleted"; campaign_room_id: string; room_id: string };
export type CampaignNotMember = { schema_version: 1; status: "not_member"; campaign_room_id: string; player_id: string };
export type CampaignChildDeletion = { schema_version: 1; binding: TargetBinding; origin: CampaignOrigin };
export type CampaignDeletionChildren = { erase(request: CampaignChildDeletion, definition: CampaignDefinition): Promise<Outcome<unknown>> };
type Row = Record<string, string | number>;
type Raw = { version: number; tables: { name: string; rows: Row[] }[] };
type Read = { raw: Raw; empty: boolean; terminal: CampaignDeleted | null; access: CampaignAccess };
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
const emptyResolver: CampaignDefinitionResolver = () => undefined;
function need(value: unknown, code = "campaign_deletion_unavailable", status = 409): asserts value { if (!value) throw new ApiError(status, code); }
function failed(error: unknown): Outcome<never> { return error instanceof ApiError ? fail(error.status, error.code) : fail(503, "campaign_deletion_unavailable"); }
function exact(value: unknown, keys: readonly string[]): Record<string, unknown> { need(isObject(value) && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)), "invalid_campaign_deletion", 422); return value; }
function id(value: unknown): asserts value is string { need(typeof value === "string" && ID_PATTERN.test(value), "invalid_campaign_deletion", 422); }

/** Strict terminal evidence, deliberately without former participant IDs. */
export function campaignDeleted(value: unknown, campaignRoomId: string, roomId = campaignRoomId): CampaignDeleted {
  const x = exact(value, ["schema_version", "status", "campaign_room_id", "room_id"]);
  id(campaignRoomId); id(roomId);
  need(x.schema_version === 1 && x.status === "deleted" && x.campaign_room_id === campaignRoomId && x.room_id === roomId, "campaign_deletion_ack_mismatch");
  return structuredClone(x) as CampaignDeleted;
}

/** Fixed table definitions and the snapshot classifier include unknown SQL/KV
 * rejection. Capturing all rows also protects metadata/privacy cleanup. */
function capture(storage: DurableObjectStorage): Raw {
  const version = roomV2StorageSchema(storage);
  need([3, 6, 7].includes(version));
  const tables = roomV2StorageDefinitions(version).map(table => {
    const rows = storage.sql.exec<Row>(table.select).toArray(); need(rows.length <= table.maxRows);
    return { name: table.name, rows };
  });
  for (const table of notificationTables("RoomV2")) {
    const rows = storage.sql.exec<Row>('SELECT * FROM "' + table.name + '" ORDER BY rowid LIMIT 3').toArray();
    need(rows.length <= (table.name === "notification_alarm" ? 1 : 2)); tables.push({ name: table.name, rows });
  }
  const redo = storage.sql.exec<Row>('SELECT * FROM "' + REDO_TABLE.name + '" ORDER BY rowid LIMIT 2').toArray();
  need(redo.length <= 1); tables.push({ name: REDO_TABLE.name, rows: redo });
  return { version, tables };
}
function unchanged(storage: DurableObjectStorage, read: Read): void { need(same(capture(storage), read.raw), "campaign_state_changed"); }
function singleton(raw: Raw, name: string): Record<string, unknown> | null {
  const rows = raw.tables.find(table => table.name === name)?.rows ?? [];
  need(rows.length <= 1); if (!rows.length) return null;
  need(rows[0].rowid === "1" && rows[0].id === 1 && typeof rows[0].data === "string");
  const parsed: unknown = JSON.parse(rows[0].data); need(isObject(parsed)); return parsed;
}
async function read(storage: DurableObjectStorage, resolver: CampaignDefinitionResolver): Promise<Read> {
  const raw = capture(storage), empty = raw.tables.every(table => table.rows.length === 0);
  if (empty) { need(raw.version !== 7, "campaign_deletion_collision"); return { raw, empty, terminal: null, access: null }; }
  const member = singleton(raw, "campaign_member");
  if (member?.status === "deleted") {
    const sidecars = [...CAMPAIGN_TABLES, ...(raw.version === 7 ? [CAMPAIGN_JOIN_TABLE] : [])].map(def => raw.tables.find(table => table.name === def.name)!);
    need(raw.version === 6 || raw.version === 7);
    const retained = new Set(["room", ...sidecars.map(table => table.name)]);
    need(raw.tables.every(table => retained.has(table.name) || table.rows.length === 0));
    await validateCampaignStorage(sidecars, singleton(raw, "room"), true, resolver);
    const terminal = campaignDeleted({ schema_version: 1, status: "deleted", campaign_room_id: member.campaign_room_id, room_id: member.room_id }, String(member.campaign_room_id), String(member.room_id));
    const result: Read = { raw, empty: false, terminal, access: null }; unchanged(storage, result); return result;
  }
  const access = await prepareCampaignAccess(storage, resolver);
  need(access, "campaign_deletion_collision");
  const result: Read = { raw, empty: false, terminal: null, access }; unchanged(storage, result); return result;
}

/** Binding-only terminal observation. It never starts/advances deletion, creates
 * storage or resolves a fresh definition. A child/empty/unknown root is no fact. */
export async function readCampaignRootTerminal(storage: DurableObjectStorage, rootId: string): Promise<Outcome<CampaignDeleted>> {
  try {
    id(rootId);
    const current = await read(storage, emptyResolver);
    need(current.terminal, "campaign_not_terminal");
    const terminal = campaignDeleted(current.terminal, rootId);
    need(await storage.getAlarm() === null, "campaign_deletion_unavailable");
    unchanged(storage, current);
    return ok(terminal);
  } catch (error) { return failed(error); }
}
async function transaction<T>(storage: DurableObjectStorage, current: Read, apply: () => Promise<T> | T): Promise<T> {
  return storage.transaction(async () => {
    const alarm = await storage.getAlarm();
    need(notificationAlarmOwned(storage, "RoomV2", alarm, true), "campaign_deletion_unavailable");
    unchanged(storage, current);
    return await apply();
  });
}
async function tombstone(storage: DurableObjectStorage, root: string, room: string): Promise<CampaignDeleted> {
  initializeCampaignStorageSchema(storage);
  for (const table of roomV2StorageDefinitions(roomV2StorageSchema(storage))) storage.sql.exec('DELETE FROM "' + table.name + '"');
  for (const table of notificationTables("RoomV2")) storage.sql.exec('DELETE FROM "' + table.name + '"');
  resetRedo(storage);
  storage.sql.exec("INSERT INTO room VALUES(1,?)", JSON.stringify({ deleted: true }));
  storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify({ schema_version: 1, status: "deleted", campaign_room_id: root, room_id: room }));
  if (root === room) storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify({ schema_version: 1, state: "deleted", campaign_room_id: root }));
  await storage.deleteAlarm();
  const saved = JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM campaign_member WHERE id=1").one().data);
  return campaignDeleted({ schema_version: 1, status: saved.status, campaign_room_id: saved.campaign_room_id, room_id: saved.room_id }, root, room);
}
async function childRequest(value: unknown, resolver: CampaignDefinitionResolver): Promise<CampaignChildDeletion> {
  boundedCampaign(value, 4096);
  const x = exact(structuredClone(value), ["schema_version", "binding", "origin"]); need(x.schema_version === 1, "invalid_campaign_deletion", 422);
  const b = exact(x.binding, ["campaign_room_id", "campaign_key", "room_id", "chapter_index", "chapter", "host_id", "guest_id", "member_transition_id"]);
  const candidate: StoredCampaignMemberV2 = { schema_version: 2, campaign_room_id: b.campaign_room_id as string, campaign_key: b.campaign_key as TargetBinding["campaign_key"], room_id: b.room_id as string,
    chapter_index: b.chapter_index as number, chapter: b.chapter as TargetBinding["chapter"], host_id: b.host_id as string, guest_id: b.guest_id as string,
    transition_id: b.member_transition_id as string, status: "provisional", seal: null, incoming: { origin: x.origin as CampaignOrigin, accepted_revision: null } };
  need(candidate.room_id !== candidate.campaign_room_id, "invalid_campaign_deletion", 422);
  const entry = resolver(candidate.campaign_key), frozen = entry ? structuredClone(entry) : undefined;
  await validateCampaignStorage(CAMPAIGN_TABLES.map((table, index) => ({ name: table.name, rows: index === 1 ? [{ rowid: "1", id: 1, data: JSON.stringify(candidate) }] : [] })), null, true, key => same(key, candidate.campaign_key) ? frozen : undefined);
  return x as CampaignChildDeletion;
}

/** Trusted root binding only. Its durable deleting intent authorizes this fence. */
export async function eraseCampaignChild(storage: DurableObjectStorage, value: unknown, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignDeleted>> {
  try {
    boundedCampaign(value, 4096); const detached = structuredClone(value), current = await read(storage, resolver);
    const input = await childRequest(detached, resolver), b = input.binding;
    return await transaction(storage, current, async () => {
      if (current.terminal) return ok(campaignDeleted(current.terminal, b.campaign_room_id, b.room_id));
      if (!current.empty) {
        const member = current.access!.member;
        need(current.raw.version === 6 && !current.access!.anchor && same(b, { campaign_room_id: member.campaign_room_id, campaign_key: member.campaign_key, room_id: member.room_id, chapter_index: member.chapter_index, chapter: member.chapter,
          host_id: member.host_id, guest_id: member.guest_id, member_transition_id: member.transition_id }) && same(member.incoming?.origin, input.origin), "campaign_deletion_binding_mismatch");
      }
      return ok(await tombstone(storage, b.campaign_room_id, b.room_id));
    });
  } catch (error) { return failed(error); }
}

/** Only the fixed root binding supplies this validated immutable context. It
 * permits deletion after fresh admission removes a definition from its menu. */
export async function eraseCampaignChildWithDefinition(storage: DurableObjectStorage, value: unknown, definition: unknown): Promise<Outcome<CampaignDeleted>> {
  try {
    boundedCampaign(value, 4096); boundedCampaign(definition, 32768);
    const input = structuredClone(value), context = structuredClone(definition);
    const valid = await campaignDefinition(context, pin => {
      try { const known = chapter(pin); return known.premium === pin.premium && (known.supported_simulation_versions ?? [known.simulation_version]).includes(pin.simulation_version); } catch { return false; }
    });
    const key = { campaign_id: valid.campaign_id, campaign_version: valid.campaign_version, definition_hash: valid.definition_hash };
    return await eraseCampaignChild(storage, input, candidate => same(candidate, key) ? valid : undefined);
  } catch (error) { return failed(error); }
}

function childFrom(anchor: StoredCampaignAnchorV2, roomId: string): CampaignChildDeletion {
  const control = anchor.control, index = control.chapters.findIndex(entry => entry.room_id === roomId);
  let targetIndex: number, origin: CampaignOrigin, token: string;
  if (index > 0) {
    const previous = control.chapters[index - 1], completed = previous.completion; need(completed && previous.room_id);
    targetIndex = index; token = completed.transition_id;
    origin = { expected_revision: completed.from_campaign_revision, from_index: index - 1, source: { room_id: previous.room_id, revision: completed.source_revision, branch: completed.source_branch, checkpoint_hash: completed.checkpoint_hash } };
  } else {
    const pending = anchor.pending; need(pending?.target_intent?.room_id === roomId);
    targetIndex = pending.target_intent.index; token = pending.transition_id; origin = structuredClone(pending.origin);
  }
  need(control.guest_id);
  return { schema_version: 1, binding: { campaign_room_id: control.campaign_room_id, campaign_key: structuredClone(control.campaign_key), room_id: roomId, chapter_index: targetIndex,
    chapter: structuredClone(anchor.definition.chapters[targetIndex]), host_id: control.host_id, guest_id: control.guest_id, member_transition_id: token }, origin };
}

/** Bounded root-owned cascade. No caller-supplied acknowledgement or public route. */
export async function eraseCampaignRoot(storage: DurableObjectStorage, owner: string, rootId: string, allocation: unknown, children: CampaignDeletionChildren, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignDeleted | CampaignNotMember>> {
  try {
    id(owner); id(rootId); boundedCampaign(allocation, 4096); const frozenAllocation = structuredClone(allocation);
    let current = await read(storage, resolver);
    if (current.terminal) return await transaction(storage, current, () => ok(campaignDeleted(current.terminal, rootId)));
    if (current.empty) {
      need(frozenAllocation !== null, "campaign_root_unavailable");
      const allocation = exact(frozenAllocation, ["schema_version", "host_id", "intent"]);
      const admitted = await campaignCreation(allocation.intent);
      need(allocation.schema_version === 1 && allocation.host_id === owner && admitted?.link.room_id === rootId, "campaign_deletion_binding_mismatch");
      return await transaction(storage, current, async () => ok(await tombstone(storage, rootId, rootId)));
    }
    const access = current.access!, anchor = access.anchor;
    need(anchor && access.member.room_id === rootId && access.member.campaign_room_id === rootId, "campaign_deletion_binding_mismatch");
    if (owner !== access.member.host_id && owner !== access.member.guest_id) return await transaction(storage, current, () => ok({ schema_version: 1, status: "not_member", campaign_room_id: rootId, player_id: owner }));
    if (anchor.control.state !== "deleting") {
      await transaction(storage, current, () => {
        need(campaignAccessUnchanged(storage, access), "campaign_state_changed");
        const next = structuredClone(anchor), member = structuredClone(access.member);
        need(next.control.revision < Number.MAX_SAFE_INTEGER, "campaign_revision_limit");
        next.control.state = "deleting"; next.control.revision++; member.status = "deleting";
        next.deletion = { room_ids: next.control.chapters.flatMap(chapter => chapter.room_id ? [chapter.room_id] : []), completed_room_ids: [] };
        if (next.pending?.target_intent) next.deletion.room_ids.push(next.pending.target_intent.room_id);
        storage.sql.exec("UPDATE campaign_member SET data=? WHERE id=1", JSON.stringify(member));
        storage.sql.exec("UPDATE campaign_anchor SET data=? WHERE id=1", JSON.stringify(next));
      });
    }
    // Eight authored chapters bound both durable inventory and remote work.
    for (let step = 0; step < 8; step++) {
      current = await read(storage, resolver);
      if (current.terminal) return await transaction(storage, current, () => ok(campaignDeleted(current.terminal, rootId)));
      const a = current.access?.anchor;
      need(a?.control.campaign_room_id === rootId && a.control.state === "deleting" && a.deletion, "campaign_state_changed");
      const child = a.deletion.room_ids.find(room => room !== rootId && !a.deletion!.completed_room_ids.includes(room));
      if (!child) return await transaction(storage, current, async () => ok(await tombstone(storage, rootId, rootId)));
      const request = childFrom(a, child);
      let problem: unknown = null;
      try { const out = await children.erase(structuredClone(request), structuredClone(a.definition)); if (!out.ok) throw new ApiError(out.status, out.code); campaignDeleted(out.value, rootId, child); }
      catch (error) { problem = error; }
      // A concurrent requester may have finished even after a lost child reply.
      current = await read(storage, resolver);
      if (current.terminal) return await transaction(storage, current, () => ok(campaignDeleted(current.terminal, rootId)));
      const latest = current.access?.anchor; need(latest?.control.state === "deleting" && latest.deletion && same(childFrom(latest, child), request), "campaign_state_changed");
      if (latest.deletion.completed_room_ids.includes(child)) continue;
      if (problem) throw problem;
      await transaction(storage, current, () => {
        const next = structuredClone(latest); next.deletion!.completed_room_ids.push(child);
        storage.sql.exec("UPDATE campaign_anchor SET data=? WHERE id=1", JSON.stringify(next));
      });
    }
    throw new ApiError(503, "campaign_deletion_pending");
  } catch (error) { return failed(error); }
}
