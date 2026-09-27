import { ApiError, canonicalJson, HASH_PATTERN, ID_PATTERN, isObject, fail, ok, type Outcome } from "../protocol";
import { chapter, sameChapter } from "./chapters";
import { boundedCampaign, type CampaignDefinitionResolver } from "./campaign-protocol";
import { CAMPAIGN_TABLES, campaignStoragePresent, validateCampaignStorage, type StoredCampaignAnchorV2, type StoredCampaignMemberV2 } from "./campaign-storage";
import type { CampaignChapterPin, CampaignKey, CampaignOrigin } from "./campaign-types";

export type SourceBinding = { campaign_room_id: string; campaign_key: CampaignKey; room_id: string; chapter_index: number; chapter: CampaignChapterPin; host_id: string; guest_id: string; member_transition_id: string | null };
export type SourceAttempt = { transition_id: string; origin: CampaignOrigin };
export type SourceRequest = { schema_version: 1; binding: SourceBinding; attempt: SourceAttempt };
export type SourceDecision =
  | { schema_version: 1; status: "ready" | "sealed"; binding: SourceBinding; attempt: SourceAttempt }
  | { schema_version: 1; status: "source_forked"; binding: SourceBinding; attempt: SourceAttempt; closed_before_branch: number; observed_branch: number };

type Row = Record<string, string | number>;
type Capture = { version: number; room: Row[]; tables: { name: string; rows: Row[] }[]; historyEmpty: boolean };
export type CampaignAccess = { captured: Capture; fingerprint: string; member: StoredCampaignMemberV2; gameplay: Record<string, unknown> | null; anchor: StoredCampaignAnchorV2 | null } | null;
const emptyResolver: CampaignDefinitionResolver = () => undefined;
function need(value: unknown, code = "campaign_state_unavailable"): asserts value { if (!value) throw new ApiError(409, code); }
function exact(value: unknown, keys: string[]): Record<string, unknown> { need(isObject(value) && Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k)), "invalid_campaign_source"); return value; }
function integer(value: unknown, max = Number.MAX_SAFE_INTEGER): asserts value is number { need(typeof value === "number" && Number.isSafeInteger(value) && value >= 0 && value <= max, "invalid_campaign_source"); }
function text(value: unknown, pattern = ID_PATTERN): asserts value is string { need(typeof value === "string" && pattern.test(value), "invalid_campaign_source"); }
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);

function classified(storage: DurableObjectStorage): boolean {
  const rows = storage.sql.exec<{ id: number; schema_version: number }>("SELECT id,schema_version FROM metadata LIMIT 2").toArray();
  need(rows.length === 1 && rows[0].id === 1 && [2, 3, 4, 5, 6].includes(rows[0].schema_version));
  return campaignStoragePresent(storage);
}

export function campaignBoundaryGuard(storage: DurableObjectStorage, code: string): Outcome<never> | null {
  try { return classified(storage) ? fail(409, code) : null; }
  catch { return fail(409, "campaign_state_unavailable"); }
}

function capture(storage: DurableObjectStorage): Capture | null {
  if (!classified(storage)) return null;
  const version = storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata WHERE id=1").one().schema_version;
  need(version === 6);
  const tables = CAMPAIGN_TABLES.map(t => ({ name: t.name, rows: storage.sql.exec<Row>(t.select).toArray() }));
  const room = storage.sql.exec<Row>("SELECT CAST(rowid AS TEXT) AS rowid,id,data FROM room ORDER BY rowid LIMIT 2").toArray();
  need(room.length <= 1 && (!room.length || room[0].rowid === "1" && room[0].id === 1 && typeof room[0].data === "string"));
  const historyEmpty = ["turns", "pairs", "operations", "photos", "photo_operations", "pair_reactions", "reaction_operations", "photo_delivery"]
    .every(name => storage.sql.exec('SELECT 1 AS present FROM "' + name + '" LIMIT 1').toArray().length === 0);
  return { version, room, tables, historyEmpty };
}

/** Cheap authority/linkage validation; accepted recording bytes are not replayed. */
function gameplayAuthority(value: unknown): asserts value is Record<string, unknown> | null {
  if (value === null || same(value, { deleted: true })) return;
  need(isObject(value));
  const s = exact(value, ["schema_version", "room_id", "revision", "branch", "stage_index", "level_id", "level_version", "definition_hash", "host_id", "guest_id", "checkpoint", "a_turn_id", "completed_pair_ids", "invite_code", "invite_expires_at", "created_at", "updated_at", ...(Object.hasOwn(value, "simulation_version") ? ["simulation_version"] : [])]);
  need(s.schema_version === 2); integer(s.revision); integer(s.branch, 31);
  for (const key of ["room_id", "host_id"]) text(s[key]);
  need(s.guest_id === null || typeof s.guest_id === "string" && ID_PATTERN.test(s.guest_id)); need(s.host_id !== s.guest_id);
  text(s.invite_code, /^[A-F0-9]{20}$/);
  for (const key of ["created_at", "updated_at", "invite_expires_at"]) {
    const stamp = s[key]; need(typeof stamp === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(stamp) && Number.isFinite(Date.parse(stamp)) && new Date(stamp).toISOString() === stamp);
  }
  const adapter = chapter(s); integer(s.stage_index, adapter.stages.length);
  const simulation = s.simulation_version ?? adapter.simulation_version;
  need(typeof simulation === "number" && (adapter.supported_simulation_versions ?? [adapter.simulation_version]).includes(simulation));
  need(s.a_turn_id === null || s.stage_index < adapter.stages.length && s.a_turn_id === `t${s.branch}-${s.stage_index}-a`);
  need(Array.isArray(s.completed_pair_ids) && s.completed_pair_ids.length === s.stage_index);
  const branch = s.branch;
  s.completed_pair_ids.forEach((id, index) => { const match = typeof id === "string" ? /^p(\d{1,2})-([01])$/.exec(id) : null; need(match && Number(match[1]) <= branch && Number(match[2]) === index); });
  const cp = s.checkpoint; need(isObject(cp) && sameChapter(cp as never, adapter.key));
  need(cp.schema_version === adapter.initial().schema_version && cp.stage_index === s.stage_index); text(cp.checkpoint_hash, HASH_PATTERN);
  need(cp.completed_stage_id === (s.stage_index === 0 ? "" : adapter.stages[s.stage_index - 1].id) && cp.next_stage_id === (adapter.stages[s.stage_index]?.id ?? ""));
  if (s.stage_index === 0) need(same(cp, adapter.initial()));
  else for (const key of ["previous_checkpoint_hash", "a_recording_hash", "b_recording_hash"]) text(cp[key], HASH_PATTERN);
}

/** Validate detached data before awaits; every consumer must recheck this token. */
export async function prepareCampaignAccess(storage: DurableObjectStorage, resolver: CampaignDefinitionResolver = emptyResolver): Promise<CampaignAccess> {
  try {
    const captured = capture(storage); if (!captured) return null;
    const gameplay = captured.room.length ? JSON.parse(String(captured.room[0].data)) as Record<string, unknown> : null;
    gameplayAuthority(gameplay);
    await validateCampaignStorage(captured.tables, gameplay, captured.historyEmpty, resolver);
    need(captured.tables[1].rows.length === 1);
    const member = JSON.parse(String(captured.tables[1].rows[0].data)) as StoredCampaignMemberV2;
    const anchor = captured.tables[0].rows.length ? JSON.parse(String(captured.tables[0].rows[0].data)) as StoredCampaignAnchorV2 : null;
    // Archived sidecar1 remains exportable, but is never inferred to be live2.
    need(member.schema_version === 2 && (!anchor || anchor.schema_version === 2));
    return { captured, fingerprint: canonicalJson(captured), member, gameplay, anchor };
  } catch { throw new ApiError(409, "campaign_state_unavailable"); }
}

/** Call after the last await and inside every mutation acceptance transaction. */
export function campaignAccessGuard(storage: DurableObjectStorage, access: CampaignAccess, newGameplay = false): Outcome<never> | null {
  try {
    const current = capture(storage);
    if (!access) return current ? fail(409, "campaign_state_changed") : null;
    if (!current || canonicalJson(current) !== access.fingerprint) return fail(409, "campaign_state_changed");
    if (access.member.status !== "active" && access.member.status !== "sealed") return fail(409, "campaign_not_active");
    if (!access.gameplay || access.gameplay.deleted === true) return fail(409, "campaign_not_active");
    return newGameplay && access.member.status === "sealed" ? fail(409, "campaign_source_sealed") : null;
  } catch { return fail(409, "campaign_state_unavailable"); }
}

function request(value: unknown): SourceRequest {
  boundedCampaign(value, 4096);
  const r = exact(value, ["schema_version", "binding", "attempt"]); need(r.schema_version === 1, "invalid_campaign_source");
  const b = exact(r.binding, ["campaign_room_id", "campaign_key", "room_id", "chapter_index", "chapter", "host_id", "guest_id", "member_transition_id"]);
  for (const key of ["campaign_room_id", "room_id", "host_id", "guest_id"]) text(b[key]);
  integer(b.chapter_index, 7); need(b.host_id !== b.guest_id, "invalid_campaign_source");
  if (b.member_transition_id !== null) text(b.member_transition_id, HASH_PATTERN);
  const k = exact(b.campaign_key, ["campaign_id", "campaign_version", "definition_hash"]);
  text(k.campaign_id, /^[a-z][a-z0-9-]{0,47}$/); integer(k.campaign_version); need(k.campaign_version > 0, "invalid_campaign_source"); text(k.definition_hash, HASH_PATTERN);
  const p = exact(b.chapter, ["level_id", "level_version", "definition_hash", "simulation_version", "premium"]);
  text(p.level_id, /^[a-z][a-z0-9-]{0,47}$/); integer(p.level_version); integer(p.simulation_version); text(p.definition_hash, HASH_PATTERN); need(typeof p.premium === "boolean", "invalid_campaign_source");
  const a = exact(r.attempt, ["transition_id", "origin"]); text(a.transition_id, HASH_PATTERN);
  const o = exact(a.origin, ["expected_revision", "from_index", "source"]); integer(o.expected_revision); integer(o.from_index, 7);
  const s = exact(o.source, ["room_id", "revision", "branch", "checkpoint_hash"]); text(s.room_id); integer(s.revision); integer(s.branch, 31); text(s.checkpoint_hash, HASH_PATTERN);
  need(o.from_index === b.chapter_index && s.room_id === b.room_id, "invalid_campaign_source");
  return structuredClone(r) as SourceRequest;
}

/** Binding-only helper. No live manifest registration or HTTP route exists. */
export async function campaignSource(storage: DurableObjectStorage, value: unknown, seal: boolean, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<SourceDecision>> {
  try {
    const input = request(value), access = await prepareCampaignAccess(storage, resolver);
    return storage.transactionSync(() => {
      need(access, "campaign_source_unavailable");
      const current = capture(storage); need(current && canonicalJson(current) === access.fingerprint, "campaign_state_changed");
      const m = access.member, state = access.gameplay, { binding, attempt } = input;
      need(same(binding, { campaign_room_id: m.campaign_room_id, campaign_key: m.campaign_key, room_id: m.room_id, chapter_index: m.chapter_index, chapter: m.chapter, host_id: m.host_id, guest_id: m.guest_id, member_transition_id: m.transition_id }), "campaign_binding_mismatch");
      if (m.room_id !== m.campaign_room_id) {
        need(m.incoming !== null && m.incoming.accepted_revision !== null && attempt.origin.expected_revision >= m.incoming.accepted_revision && attempt.transition_id !== m.transition_id, "campaign_transition_mismatch");
      }
      if (same(m.seal, attempt)) return ok({ schema_version: 1, status: "sealed", binding, attempt });
      need((m.status === "active" || m.status === "sealed") && state && state.deleted !== true, "campaign_source_unavailable");
      const from = attempt.origin.source;
      if (typeof state.branch === "number" && state.branch > from.branch && typeof state.revision === "number" && state.revision > from.revision) {
        need(m.seal === null || m.seal.origin.source.branch === state.branch && m.seal.origin.source.branch > from.branch, "campaign_seal_conflict");
        return ok({ schema_version: 1, status: "source_forked", binding, attempt, closed_before_branch: from.branch + 1, observed_branch: state.branch });
      }
      need(m.seal === null && m.status === "active", "campaign_seal_conflict");
      need(state.stage_index === chapter(m.chapter).stages.length && state.a_turn_id === null && same(from, { room_id: state.room_id, revision: state.revision, branch: state.branch, checkpoint_hash: (state.checkpoint as Record<string, unknown>).checkpoint_hash }), "campaign_source_mismatch");
      if (m.room_id === m.campaign_room_id) {
        const a = access.anchor;
        need(a?.state === "live" && a.control.state === "continuing" && a.control.current_index === 0 && a.control.chapters[0].completion === null && a.pending?.phase === "prepared" && same({ transition_id: a.pending.transition_id, origin: a.pending.origin }, attempt), "campaign_transition_mismatch");
      }
      if (!seal) return ok({ schema_version: 1, status: "ready", binding, attempt });
      const sealed = { ...m, status: "sealed", seal: attempt };
      storage.sql.exec("UPDATE campaign_member SET data=? WHERE id=1", JSON.stringify(sealed));
      return ok({ schema_version: 1, status: "sealed", binding, attempt });
    });
  } catch (error) {
    return error instanceof ApiError ? fail(error.status, error.code) : fail(409, "campaign_state_unavailable");
  }
}
