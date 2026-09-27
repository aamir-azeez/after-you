import { ApiError, canonicalJson, digest, fail, HASH_PATTERN, isObject, ok, type Outcome } from "../protocol";
import { chapter } from "./chapters";
import { boundedCampaign, campaignContinue, campaignContinueKey, campaignContinueResult, campaignRequestHash, campaignResumeActivation, continueOrigin, type CampaignDefinitionResolver } from "./campaign-protocol";
import { campaignAccessUnchanged, campaignSource, prepareCampaignAccess, type CampaignAccess, type SourceDecision, type SourceRequest } from "./campaign-source";
import { campaignTargetActivated, campaignTargetInitialized, campaignTargetInitialization, type TargetActivateRequest, type TargetInitializeRequest } from "./campaign-target";
import type { CampaignActivationDebt, StoredCampaignAnchorV2 } from "./campaign-storage";
import type { CampaignContinue, CampaignContinueReceipt, CampaignContinueResult, CampaignEnvelope, CampaignOrigin, CampaignPending, CampaignView } from "./campaign-types";

type Access = NonNullable<CampaignAccess> & { anchor: StoredCampaignAnchorV2 };
type Alias = { status: "pending"; player_id: string; request: CampaignContinue; transition_id: string } | { status: "accepted"; receipt: CampaignContinueReceipt };
type OperationRow = { request_key: string; request_hash: string; receipt: string };
/** Internal server dependencies, never wire fields. Policy is a pure synchronous
 * persisted-state check; callbacks must not mutate the supplied detached values. */
export type CampaignControlDependencies = {
  mutationPolicy: (owner: string, view: CampaignView) => Outcome<true>;
  admitFresh: (owner: string, view: CampaignView, body: CampaignContinue) => Promise<Outcome<true>>;
  allocate: () => { transition_id: string; invite_code: string };
  source: (request: SourceRequest, seal: boolean) => Promise<Outcome<unknown>>;
  initialize: (request: TargetInitializeRequest) => Promise<Outcome<unknown>>;
  activate: (request: TargetActivateRequest) => Promise<Outcome<unknown>>;
};
const emptyResolver: CampaignDefinitionResolver = () => undefined;
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
function need(value: unknown, code = "campaign_state_changed", status = 409): asserts value { if (!value) throw new ApiError(status, code); }
function unwrap<T>(value: Outcome<T>): T { if (!value.ok) throw new ApiError(value.status, value.code); return value.value; }
function failure(error: unknown): Outcome<never> { return error instanceof ApiError ? fail(error.status, error.code) : fail(503, "campaign_state_unavailable"); }
function projection(a: StoredCampaignAnchorV2, owner: string): CampaignView {
  const v = a.control; need(owner === v.host_id || owner === v.guest_id, "campaign_owner_mismatch", 403);
  return structuredClone(owner === v.host_id ? v : { ...v, player_slot: "p1", invite_code: null, invite_expires_at: null });
}
function registry(a: StoredCampaignAnchorV2): CampaignDefinitionResolver { const d = structuredClone(a.definition); return k => same(k, a.control.campaign_key) ? d : undefined; }
async function read(storage: DurableObjectStorage, owner: string, resolver: CampaignDefinitionResolver): Promise<Access> {
  const access = await prepareCampaignAccess(storage, resolver);
  need(access?.anchor && access.member.room_id === access.member.campaign_room_id, "campaign_state_unavailable");
  projection(access.anchor, owner); need(campaignAccessUnchanged(storage, access));
  return access as Access;
}
function live(access: Access, owner: string, deps: CampaignControlDependencies): void {
  need(access.anchor.control.state !== "deleting" && access.member.status !== "deleting", "campaign_deleting");
  need(unwrap(deps.mutationPolicy(owner, projection(access.anchor, owner))) === true, "campaign_mutation_disabled");
}
function transaction<T>(storage: DurableObjectStorage, access: Access, owner: string, deps: CampaignControlDependencies, body: () => T): T {
  return storage.transactionSync(() => { need(campaignAccessUnchanged(storage, access)); live(access, owner, deps); return body(); });
}
function save(storage: DurableObjectStorage, a: StoredCampaignAnchorV2): void { storage.sql.exec("UPDATE campaign_anchor SET data=? WHERE id=1", JSON.stringify(a)); }
function bump(a: StoredCampaignAnchorV2): void { need(a.control.revision < Number.MAX_SAFE_INTEGER, "campaign_revision_limit"); a.control.revision++; }
function rows(access: Access): OperationRow[] { return access.captured.tables[2].rows as OperationRow[]; }
function receipt(a: StoredCampaignAnchorV2, owner: string, body: CampaignContinue, hash: string): CampaignContinueReceipt | null {
  const from = continueOrigin(body), c = a.control.chapters[from.from_index], done = c?.completion;
  if (!done || c.room_id !== from.source.room_id || !same({ expected_revision: done.from_campaign_revision, from_index: from.from_index,
    source: { room_id: c.room_id, revision: done.source_revision, branch: done.source_branch, checkpoint_hash: done.checkpoint_hash } }, from)) return null;
  const final = from.from_index === a.control.chapters.length - 1;
  return { schema_version: 1, operation: "campaign_continue", campaign_room_id: a.control.campaign_room_id, campaign_key: structuredClone(body.campaign_key),
    player_id: owner, idempotency_key: body.idempotency_key, request_hash: hash, transition_id: done.transition_id, origin: from,
    accepted_revision: done.accepted_campaign_revision, outcome: final ? "finished" : "advanced", next_index: final ? null : from.from_index + 1,
    next_room_id: final ? null : a.control.chapters[from.from_index + 1].room_id };
}
function result(access: Access, owner: string, body: CampaignContinue, hash: string): CampaignContinueResult | null {
  const a = access.anchor, accepted = receipt(a, owner, body, hash);
  if (accepted) return { schema_version: 1, operation: "campaign_continue", status: "accepted", receipt: accepted, campaign: projection(a, owner) };
  const row = rows(access).find(r => r.request_key === owner + ":" + body.idempotency_key);
  if (!row) return null;
  need(row.request_hash === hash, "campaign_idempotency_mismatch");
  const saved = JSON.parse(row.receipt) as Alias;
  need(saved.status === "pending" && same(saved.request, body) && a.pending?.transition_id === saved.transition_id);
  return { schema_version: 1, operation: "campaign_continue", status: "pending", player_id: owner, idempotency_key: body.idempotency_key,
    request_hash: hash, transition_id: saved.transition_id, campaign: projection(a, owner) };
}
function alias(storage: DurableObjectStorage, access: Access, owner: string, body: CampaignContinue, hash: string): void {
  const key = owner + ":" + body.idempotency_key, existing = rows(access).find(r => r.request_key === key);
  if (existing) { need(existing.request_hash === hash, "campaign_idempotency_mismatch"); return; }
  need(rows(access).length < 16, "campaign_operation_limit");
  const done = receipt(access.anchor, owner, body, hash);
  const stored: Alias = done ? { status: "accepted", receipt: done } : { status: "pending", player_id: owner, request: structuredClone(body), transition_id: access.anchor.pending!.transition_id };
  storage.sql.exec("INSERT INTO campaign_operations(request_key,request_hash,receipt) VALUES(?,?,?)", key, hash, JSON.stringify(stored));
}
function sourceRequest(a: StoredCampaignAnchorV2, pending: Pick<CampaignPending, "transition_id" | "origin">): SourceRequest {
  const i = pending.origin.from_index, v = a.control; need(v.guest_id !== null, "campaign_waiting");
  return { schema_version: 1, binding: { campaign_room_id: v.campaign_room_id, campaign_key: structuredClone(v.campaign_key), room_id: pending.origin.source.room_id,
    chapter_index: i, chapter: structuredClone(v.chapters[i].chapter), host_id: v.host_id, guest_id: v.guest_id,
    member_transition_id: i === 0 ? null : v.chapters[i - 1].completion!.transition_id }, attempt: { transition_id: pending.transition_id, origin: structuredClone(pending.origin) } };
}
function sourceAck(value: unknown, expected: SourceRequest, seal: boolean): SourceDecision {
  boundedCampaign(value, 4096); need(isObject(value), "invalid_campaign_source_ack");
  const fork = value.status === "source_forked", keys = ["schema_version", "status", "binding", "attempt", ...(fork ? ["closed_before_branch", "observed_branch"] : [])];
  need(Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k)) && value.schema_version === 1 && same(value.binding, expected.binding) && same(value.attempt, expected.attempt), "invalid_campaign_source_ack");
  if (fork) need(value.closed_before_branch === expected.attempt.origin.source.branch + 1 && typeof value.observed_branch === "number" && Number.isInteger(value.observed_branch) && value.observed_branch >= Number(value.closed_before_branch) && value.observed_branch <= 31, "invalid_campaign_source_ack");
  else need(value.status === "sealed" || !seal && value.status === "ready", "invalid_campaign_source_ack");
  return structuredClone(value) as SourceDecision;
}
function targetRequest(a: StoredCampaignAnchorV2, intent: CampaignPending | CampaignActivationDebt): TargetInitializeRequest {
  const target = intent.target_intent, v = a.control; need(target && v.guest_id, "campaign_target_unavailable");
  return { schema_version: 1, binding: { campaign_room_id: v.campaign_room_id, campaign_key: structuredClone(v.campaign_key), room_id: target.room_id,
    chapter_index: target.index, chapter: structuredClone(target.chapter), host_id: v.host_id, guest_id: v.guest_id, member_transition_id: intent.transition_id },
    origin: structuredClone(intent.origin), target_intent: structuredClone(target) };
}
function samePending(a: StoredCampaignAnchorV2, p: CampaignPending): boolean {
  return a.pending !== null && same({ ...a.pending, phase: p.phase }, p);
}
function rejected(access: Access, owner: string, body: CampaignContinue, hash: string): CampaignContinueResult {
  need(body.expected_revision <= access.anchor.control.revision && access.anchor.control.chapters[body.from_index]?.room_id === body.source.room_id, "campaign_source_mismatch");
  return { schema_version: 1, operation: "campaign_continue", status: "rejected", receipt: { schema_version: 1, operation: "campaign_continue",
    campaign_room_id: access.anchor.control.campaign_room_id, campaign_key: structuredClone(body.campaign_key), player_id: owner, idempotency_key: body.idempotency_key,
    request_hash: hash, origin: continueOrigin(body), reason: "source_forked", closed_before_branch: body.source.branch + 1 }, campaign: projection(access.anchor, owner) };
}
async function emit(storage: DurableObjectStorage, access: Access, owner: string, body: CampaignContinue, hash: string, candidate: CampaignContinueResult, resolver: CampaignDefinitionResolver): Promise<Outcome<CampaignContinueResult>> {
  for (let pass = 0; pass < 3; pass++) {
    const checked = await campaignContinueResult(candidate, access.anchor.control.campaign_room_id, owner, body, registry(access.anchor));
    if (campaignAccessUnchanged(storage, access)) return ok(checked);
    access = await read(storage, owner, resolver);
    const current = result(access, owner, body, hash);
    if (current) candidate = current;
    else { need(candidate.status === "rejected"); candidate = rejected(access, owner, body, hash); }
  }
  throw new ApiError(409, "campaign_state_changed");
}

/** GET helpers never insert aliases, dispatch work, clear debt or schedule alarms. */
export async function readCampaignControl(storage: DurableObjectStorage, owner: string, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignEnvelope>> {
  try { const a = await read(storage, owner, resolver); return ok({ campaign: projection(a.anchor, owner) }); } catch (e) { return failure(e); }
}
export async function readCampaignOperation(storage: DurableObjectStorage, owner: string, key: string, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignContinueResult>> {
  try {
    need(typeof key === "string" && HASH_PATTERN.test(key), "invalid_campaign_operation", 422);
    const access = await read(storage, owner, resolver), a = access.anchor;
    const row = rows(access).find(r => r.request_key === owner + ":" + key);
    if (row) {
      const saved = JSON.parse(row.receipt) as Alias;
      const body = saved.status === "pending" ? saved.request : { schema_version: 1 as const, idempotency_key: key, campaign_key: saved.receipt.campaign_key, ...saved.receipt.origin };
      return await emit(storage, access, owner, body, row.request_hash, result(access, owner, body, row.request_hash)!, resolver);
    }
    for (let i = 0; i < a.control.chapters.length; i++) {
      const c = a.control.chapters[i], done = c.completion; if (!done) continue;
      const origin: CampaignOrigin = { expected_revision: done.from_campaign_revision, from_index: i, source: { room_id: c.room_id!, revision: done.source_revision, branch: done.source_branch, checkpoint_hash: done.checkpoint_hash } };
      if (await campaignContinueKey(a.control.campaign_room_id, a.control.campaign_key, owner, origin) !== key) continue;
      const body: CampaignContinue = { schema_version: 1, idempotency_key: key, campaign_key: a.control.campaign_key, ...origin };
      const hash = await campaignRequestHash(a.control.campaign_room_id, owner, body);
      need(campaignAccessUnchanged(storage, access)); return await emit(storage, access, owner, body, hash, result(access, owner, body, hash)!, resolver);
    }
    need(campaignAccessUnchanged(storage, access)); return fail(404, "operation_not_found");
  } catch (e) { return failure(e); }
}

async function discharge(storage: DurableObjectStorage, owner: string, token: string, deps: CampaignControlDependencies, resolver: CampaignDefinitionResolver): Promise<Access> {
  let access = await read(storage, owner, resolver); live(access, owner, deps);
  const debt = access.anchor.activation;
  if (!debt || debt.transition_id !== token) {
    need(access.anchor.control.chapters.some(c => c.completion?.transition_id === token), "campaign_transition_mismatch"); return access;
  }
  const request: TargetActivateRequest = { ...targetRequest(access.anchor, debt), accepted_revision: debt.accepted_revision };
  let error: unknown;
  try { const response = await deps.activate(structuredClone(request)); await campaignTargetActivated(unwrap(response), request, registry(access.anchor)); } catch (e) { error = e; }
  access = await read(storage, owner, resolver); live(access, owner, deps);
  if (!access.anchor.activation || access.anchor.activation.transition_id !== token) {
    need(access.anchor.control.chapters.some(c => c.completion?.transition_id === token), "campaign_transition_mismatch"); return access;
  }
  need(same(access.anchor.activation, debt)); if (error) throw error;
  transaction(storage, access, owner, deps, () => { const a = structuredClone(access.anchor); a.activation = null; a.control.activation = null; bump(a); save(storage, a); });
  return await read(storage, owner, resolver);
}
export async function resumeCampaignActivation(storage: DurableObjectStorage, owner: string, value: unknown, deps: CampaignControlDependencies, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignEnvelope>> {
  try {
    boundedCampaign(value, 4096); const input = structuredClone(value);
    const access = await read(storage, owner, resolver); live(access, owner, deps);
    const body = campaignResumeActivation(input, registry(access.anchor)); need(same(body.campaign_key, access.anchor.control.campaign_key), "campaign_binding_mismatch");
    const current = await discharge(storage, owner, body.transition_id, deps, resolver); return ok({ campaign: projection(current.anchor, owner) });
  } catch (e) { return failure(e); }
}

/** One deliberate call makes at most one source seal, initializer and activator
 * request. Every retry uses the durable identity; GET does no recovery work. */
export async function continueCampaignControl(storage: DurableObjectStorage, owner: string, value: unknown, deps: CampaignControlDependencies, resolver: CampaignDefinitionResolver = emptyResolver): Promise<Outcome<CampaignContinueResult>> {
  try {
    boundedCampaign(value, 4096); const input = structuredClone(value);
    let access = await read(storage, owner, resolver); live(access, owner, deps);
    const body = await campaignContinue(input, access.anchor.control.campaign_room_id, owner, registry(access.anchor));
    const hash = await campaignRequestHash(access.anchor.control.campaign_room_id, owner, body), origin = continueOrigin(body);
    access = await read(storage, owner, resolver); live(access, owner, deps);
    let found = result(access, owner, body, hash);
    if (found?.status === "accepted") { transaction(storage, access, owner, deps, () => alias(storage, access, owner, body, hash)); return await emit(storage, access, owner, body, hash, found, resolver); }
    const old = access.anchor.control.chapters[body.from_index]?.completion;
    if (old && old.source_branch > body.source.branch && old.source_revision > body.source.revision) return await emit(storage, access, owner, body, hash, rejected(access, owner, body, hash), resolver);
    if (!access.anchor.pending) {
      const initial = access, v = access.anchor.control;
      need(v.activation === null, "campaign_activation_pending"); need(v.state === "active" && v.guest_id && body.from_index === v.current_index && body.source.room_id === v.chapters[v.current_index].room_id, "campaign_source_mismatch");
      // A fork rejection requires an actual source observation, not a copied fence.
      const allocation = structuredClone(deps.allocate());
      need(HASH_PATTERN.test(allocation.transition_id) && /^[A-F0-9]{20}$/.test(allocation.invite_code) && !v.chapters.some(c => c.completion?.transition_id === allocation.transition_id), "invalid_campaign_allocation");
      const pending: CampaignPending = { transition_id: allocation.transition_id, phase: "prepared", origin, target_intent: null };
      const source = sourceRequest(access.anchor, pending);
      let observation: SourceDecision | undefined, observationError: unknown;
      if (body.from_index === 0) {
        const s = access.gameplay!;
        if (Number(s.branch) > body.source.branch && Number(s.revision) > body.source.revision) observation = { schema_version: 1, status: "source_forked", binding: source.binding, attempt: source.attempt, closed_before_branch: body.source.branch + 1, observed_branch: Number(s.branch) };
        else {
          need(access.member.status === "active" && access.member.seal === null && s.stage_index === chapter(v.chapters[0].chapter).stages.length && s.a_turn_id === null && same(body.source, { room_id: s.room_id, revision: s.revision, branch: s.branch, checkpoint_hash: (s.checkpoint as Record<string, unknown>).checkpoint_hash }), "campaign_source_mismatch");
          observation = { schema_version: 1, status: "ready", binding: source.binding, attempt: source.attempt };
        }
      } else {
        try { observation = sourceAck(unwrap(await deps.source(structuredClone(source), false)), source, false); }
        catch (e) { observationError = e; }
      }
      access = await read(storage, owner, resolver); live(access, owner, deps);
      found = result(access, owner, body, hash); if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
      // A concurrent caller may have prepared this origin while observation was
      // pending. Its durable transition must be reconciled by the seal phase.
      if (!access.anchor.pending && observationError) throw observationError;
      if (observation?.status === "source_forked" && !access.anchor.pending) return await emit(storage, access, owner, body, hash, rejected(access, owner, body, hash), resolver);
      if (!access.anchor.pending) {
        need(access.fingerprint === initial.fingerprint && body.expected_revision === v.revision, "campaign_revision_conflict");
        let admissionError: unknown;
        try { need(unwrap(await deps.admitFresh(owner, projection(access.anchor, owner), structuredClone(body))) === true, "campaign_admission_denied"); }
        catch (e) { admissionError = e; }
        access = await read(storage, owner, resolver); live(access, owner, deps);
        found = result(access, owner, body, hash); if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
        if (!access.anchor.pending && admissionError) throw admissionError;
        if (!access.anchor.pending && body.from_index < v.chapters.length - 1) {
          pending.target_intent = { room_id: (await digest("v2:" + allocation.invite_code)).slice(0, 22), invite_code: allocation.invite_code, index: body.from_index + 1, chapter: structuredClone(v.chapters[body.from_index + 1].chapter) };
          need(!v.chapters.some(c => c.room_id === pending.target_intent!.room_id), "campaign_target_conflict");
          await campaignTargetInitialization(targetRequest(initial.anchor, pending), registry(initial.anchor));
        }
        access = await read(storage, owner, resolver); live(access, owner, deps);
        found = result(access, owner, body, hash); if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
        if (!access.anchor.pending) {
          need(access.fingerprint === initial.fingerprint);
          transaction(storage, access, owner, deps, () => { const a = structuredClone(access.anchor); a.pending = pending; a.control.transition = { transition_id: pending.transition_id, phase: pending.phase, origin: structuredClone(origin) }; a.control.state = "continuing"; bump(a); save(storage, a);
            alias(storage, { ...access, anchor: a }, owner, body, hash); });
        }
      }
    }
    access = await read(storage, owner, resolver); live(access, owner, deps);
    found = result(access, owner, body, hash); if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
    need(access.anchor.pending && same(access.anchor.pending.origin, origin), "campaign_transition_mismatch");
    transaction(storage, access, owner, deps, () => alias(storage, access, owner, body, hash));
    access = await read(storage, owner, resolver);
    live(access, owner, deps); found = result(access, owner, body, hash);
    if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
    need(access.anchor.pending && same(access.anchor.pending.origin, origin), "campaign_transition_mismatch");
    const pending = structuredClone(access.anchor.pending!);
    if (pending.phase === "prepared") {
      live(access, owner, deps); const request = sourceRequest(access.anchor, pending); let response: SourceDecision | undefined, error: unknown;
      try { response = sourceAck(unwrap(body.from_index === 0 ? await campaignSource(storage, request, true, registry(access.anchor)) : await deps.source(structuredClone(request), true)), request, true); } catch (e) { error = e; }
      access = await read(storage, owner, resolver); live(access, owner, deps);
      found = result(access, owner, body, hash); if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
      need(samePending(access.anchor, pending));
      if (access.anchor.pending!.phase === "prepared") {
        if (error) throw error;
        if (response!.status === "source_forked") {
          transaction(storage, access, owner, deps, () => {
            const a = structuredClone(access.anchor); a.closed_before_branches[body.from_index] = Math.max(a.closed_before_branches[body.from_index], body.source.branch + 1);
            a.pending = null; a.control.transition = null; a.control.state = "active"; bump(a);
            for (const row of rows(access)) { const saved = JSON.parse(row.receipt) as Alias; if (saved.status === "pending" && saved.transition_id === pending.transition_id) storage.sql.exec("DELETE FROM campaign_operations WHERE request_key=?", row.request_key); }
            save(storage, a);
          });
          access = await read(storage, owner, resolver);
          return await emit(storage, access, owner, body, hash, rejected(access, owner, body, hash), resolver);
        }
        transaction(storage, access, owner, deps, () => { const a = structuredClone(access.anchor); a.pending!.phase = "source_sealed"; a.control.transition!.phase = "source_sealed"; bump(a); save(storage, a); });
      }
    }
    access = await read(storage, owner, resolver); live(access, owner, deps);
    found = result(access, owner, body, hash); if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
    need(samePending(access.anchor, pending));
    if (access.anchor.pending!.phase === "source_sealed" && pending.target_intent) {
      const request = targetRequest(access.anchor, pending); let error: unknown;
      try { await campaignTargetInitialized(unwrap(await deps.initialize(structuredClone(request))), request, registry(access.anchor)); } catch (e) { error = e; }
      access = await read(storage, owner, resolver); live(access, owner, deps);
      found = result(access, owner, body, hash); if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
      need(samePending(access.anchor, pending));
      if (access.anchor.pending!.phase === "source_sealed") {
        if (error) throw error;
        transaction(storage, access, owner, deps, () => { const a = structuredClone(access.anchor); a.pending!.phase = "target_initialized"; a.control.transition!.phase = "target_initialized"; bump(a); save(storage, a); });
      }
    }
    access = await read(storage, owner, resolver); live(access, owner, deps);
    found = result(access, owner, body, hash); if (found?.status === "accepted") return await emit(storage, access, owner, body, hash, found, resolver);
    need(samePending(access.anchor, pending) && access.anchor.pending!.phase === (pending.target_intent ? "target_initialized" : "source_sealed"));
    transaction(storage, access, owner, deps, () => {
      const a = structuredClone(access.anchor); bump(a);
      a.control.chapters[body.from_index].completion = { source_revision: body.source.revision, source_branch: body.source.branch, checkpoint_hash: body.source.checkpoint_hash,
        transition_id: pending.transition_id, from_campaign_revision: body.expected_revision, accepted_campaign_revision: a.control.revision };
      if (pending.target_intent) {
        a.control.current_index = pending.target_intent.index; a.control.chapters[pending.target_intent.index].room_id = pending.target_intent.room_id; a.control.state = "active";
        a.activation = { transition_id: pending.transition_id, origin: structuredClone(origin), target_intent: structuredClone(pending.target_intent), accepted_revision: a.control.revision }; a.control.activation = { transition_id: pending.transition_id };
      } else { a.control.state = "complete"; a.activation = null; a.control.activation = null; }
      a.pending = null; a.control.transition = null;
      for (const row of rows(access)) {
        const saved = JSON.parse(row.receipt) as Alias;
        if (saved.status === "pending" && saved.transition_id === pending.transition_id) {
          const done = receipt(a, saved.player_id, saved.request, row.request_hash); need(done);
          storage.sql.exec("UPDATE campaign_operations SET receipt=? WHERE request_key=?", JSON.stringify({ status: "accepted", receipt: done }), row.request_key);
        }
      }
      save(storage, a);
    });
    // Failed activation leaves an accepted receipt plus visible durable debt.
    if (pending.target_intent) {
      try { await discharge(storage, owner, pending.transition_id, deps, resolver); } catch { /* explicit Resume owns subsequent attempts */ }
    }
    access = await read(storage, owner, resolver); live(access, owner, deps); return await emit(storage, access, owner, body, hash, result(access, owner, body, hash)!, resolver);
  } catch (e) { return failure(e); }
}
