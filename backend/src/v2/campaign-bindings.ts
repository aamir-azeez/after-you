import { ApiError, canonicalJson, fail, HASH_PATTERN, ID_PATTERN, isObject, ok, type Outcome } from "../protocol";
import { entitlement } from "../entitlement";
import { interactionBlocked } from "../safety";
import { campaignAdmissionHash, campaignAdmissionRequest } from "./campaign-admission-intent";
import { joinFact } from "./campaign-join-storage";
import { boundedCampaign, campaignJoin, campaignContinue, campaignContinueResult as checkedContinueResult } from "./campaign-protocol";
import { campaignAccessUnchanged, campaignSource, prepareCampaignAccess, type CampaignAccess, type SourceRequest } from "./campaign-source";
import { initializeCampaignTarget, activateCampaignTarget, type TargetInitializeRequest, type TargetActivateRequest } from "./campaign-target";
import { initializeCampaignRoot, joinCampaignRoot, cancelCampaignJoinRoot } from "./campaign-root";
import { continueCampaignControl, resumeCampaignActivation, readCampaignControl, readCampaignOperation, type CampaignControlDependencies } from "./campaign-control";
import { definitionResolver, exactCampaignDefinition, retainedCampaign } from "./campaign-registry";
import type { CampaignRoomContext } from "./campaign-room-access";
import type { CampaignCreate, CampaignJoin, CampaignView, CampaignEnvelope, CampaignContinueResult } from "./campaign-types";
import type { StoredCampaignAnchorV2 } from "./campaign-storage";
import { campaignRedoBinding, sameRedoValue, type CampaignRedoBinding, type CampaignRedoEnvelope, type CampaignRedoMode } from "./campaign-redo";

type RootAccess = NonNullable<CampaignAccess> & { anchor: StoredCampaignAnchorV2 };
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
function need(value: unknown, code = "campaign_state_unavailable", status = 409): asserts value { if (!value) throw new ApiError(status, code); }
function unwrap<T>(r: Outcome<T>): T { if (!r.ok) throw new ApiError(r.status, r.code); return r.value; }
function failure(e: unknown): Outcome<never> { return e instanceof ApiError ? fail(e.status, e.code) : fail(503, "campaign_state_unavailable"); }
function caller(owner: string, value: unknown): CampaignRoomContext {
  need(ID_PATTERN.test(owner) && isObject(value) && Object.keys(value).length === 3 && value.schema_version === 2 &&
    typeof value.room_id === "string" && ID_PATTERN.test(value.room_id) && typeof value.device_hash === "string" && HASH_PATTERN.test(value.device_hash), "campaign_client_required");
  return { schema_version: 2, room_id: value.room_id, device_hash: value.device_hash };
}
export function campaignGlobalMutations(env: Env): void { need(String(env.V2_ROOMS_ENABLED) === "true", "v2_mutations_disabled", 503); }
function controlMutations(env: Env): void { campaignGlobalMutations(env); need(String(env.CAMPAIGN_MUTATIONS_ENABLED) === "true", "campaign_mutations_disabled", 503); }
export async function campaignDevice(env: Env, owner: string, hash: string): Promise<void> {
  need(await env.PLAYERS.getByName(owner).authorize(hash), "identity_unavailable", 401);
}
async function policy(env: Env, owner: string, c: CampaignRoomContext, host: string, guest: string | null, block = true): Promise<void> {
  await campaignDevice(env, owner, c.device_hash);
  if (block) need(!await interactionBlocked(env, host, guest), "interaction_blocked", 403);
  await campaignDevice(env, owner, c.device_hash);
}
export async function campaignHostAccess(env: Env, host: string): Promise<void> {
  const a = await entitlement(host, env);
  need(a.full_journey, a.status === "verified" ? "host_unlock_required" : "entitlement_unavailable", a.status === "verified" ? 402 : 503);
}
async function root(storage: DurableObjectStorage, roomId: string): Promise<RootAccess> {
  const a = await prepareCampaignAccess(storage);
  need(a?.anchor && a.member.room_id === roomId && a.member.campaign_room_id === roomId && campaignAccessUnchanged(storage, a), "campaign_root_unavailable");
  return a as RootAccess;
}
function member(a: RootAccess, owner: string): void { need(owner === a.member.host_id || owner === a.member.guest_id, "campaign_owner_mismatch", 403); }
async function owned(storage: DurableObjectStorage, env: Env, owner: string, c: CampaignRoomContext, block = true): Promise<RootAccess> {
  const a = await root(storage, c.room_id); member(a, owner);
  await policy(env, owner, c, a.member.host_id, a.member.guest_id, block);
  need(campaignAccessUnchanged(storage, a), "campaign_state_changed"); return a;
}
async function canonicalLink(env: Env, owner: string, c: CampaignRoomContext, view: CampaignView): Promise<void> {
  const link = unwrap(await env.PLAYERS.getByName(owner).campaignLink(c.room_id, c.device_hash));
  need(link && same(link, { room_id: c.room_id, api_version: 3, host: owner === view.host_id,
    invite_code: owner === view.host_id ? view.invite_code : "" }), "campaign_link_unavailable");
}

/** Fixed authenticated bindings. Context and definitions are constructed by the
 * server; none of these parameters are accepted from an HTTP body. */
export async function campaignBindingRead(storage: DurableObjectStorage, env: Env, owner: string, value: unknown, operation?: string, settlement = false): Promise<Outcome<CampaignEnvelope | CampaignContinueResult>> {
  try {
    const c = caller(owner, value), a = await owned(storage, env, owner, c, !settlement);
    const result = operation === undefined ? await readCampaignControl(storage, owner) : await readCampaignOperation(storage, owner, operation);
    await policy(env, owner, c, a.member.host_id, a.member.guest_id, !settlement);
    need(campaignAccessUnchanged(storage, a), "campaign_state_changed");
    return result;
  } catch (e) { return failure(e); }
}

/** Parent publication selects one child. Historical receipt reads keep that
 * exact index; they never substitute the current chapter or advance control. */
export async function campaignBindingRedo(storage: DurableObjectStorage, env: Env, owner: string, context: unknown,
  index: number, mode: CampaignRedoMode, value: unknown,
  local: (binding: CampaignRedoBinding, context: CampaignRoomContext) => Promise<Outcome<CampaignRedoEnvelope>>): Promise<Outcome<CampaignRedoEnvelope>> {
  try {
    const c = caller(owner, context), a = await owned(storage, env, owner, c);
    need(a.anchor.control.state !== "deleting", "campaign_not_active");
    const binding = campaignRedoBinding(a.anchor.control, index), childContext = { ...c, room_id: binding.room_id };
    const result = binding.room_id === c.room_id ? await local(binding, childContext) :
      await env.ROOMS_V2.getByName(binding.room_id).campaignBoundRedo(owner, binding, mode, value, childContext);
    // The root's gameplay fingerprint legitimately changes for chapter-zero
    // acceptance. Obtain fresh authority instead of comparing that old capture.
    const current = await owned(storage, env, owner, c);
    need(current.anchor.control.state !== "deleting" && sameRedoValue(campaignRedoBinding(current.anchor.control, index), binding), "campaign_binding_mismatch");
    return result;
  } catch (e) { return failure(e); }
}

export async function campaignBindingInitialize(storage: DurableObjectStorage, env: Env, owner: string, value: unknown, context: unknown, retainedDefinition?: unknown) {
  try {
    const input = campaignAdmissionRequest(value, "create") as CampaignCreate, c = caller(owner, context);
    const suppliedDefinition = retainedDefinition === undefined ? undefined : structuredClone(retainedDefinition); campaignGlobalMutations(env);
    const intent = unwrap(await env.PLAYERS.getByName(owner).campaignCreation(input.idempotency_key, input.campaign_key, c.device_hash));
    need(intent && intent.link.room_id === c.room_id, "campaign_allocation_unavailable");
    // An initialized root carries its own immutable definition. An unfinished
    // admitted allocation can use only its exact retained bundled definition.
    const existing = await prepareCampaignAccess(storage);
    const definition = existing?.anchor?.definition ?? suppliedDefinition ?? retainedCampaign(input.campaign_key);
    need(definition, "unsupported_campaign", 422);
    const exact = await exactCampaignDefinition(definition, input.campaign_key);
    if (existing) need(existing.anchor && existing.member.room_id === c.room_id && existing.member.host_id === owner, "campaign_binding_mismatch");
    await policy(env, owner, c, owner, existing?.member.guest_id ?? null);
    const current = unwrap(await env.PLAYERS.getByName(owner).campaignCreation(input.idempotency_key, input.campaign_key, c.device_hash));
    need(current && same(current, intent), "campaign_allocation_unavailable"); campaignGlobalMutations(env);
    if (existing) {
      need(existing.anchor && same(existing.member.campaign_key, input.campaign_key) && same(existing.anchor.definition, exact) &&
        existing.gameplay?.invite_code === intent.link.invite_code, "campaign_root_binding_mismatch");
      await canonicalLink(env, owner, c, existing.anchor.control);
      need(campaignAccessUnchanged(storage, existing), "campaign_state_changed");
      return ok({ schema_version: 1 as const, status: "initialized" as const, created: false, campaign: structuredClone(existing.anchor.control) });
    }
    const result = await initializeCampaignRoot(storage, { schema_version: 1, host_id: owner, intent }, definitionResolver(exact));
    await campaignDevice(env, owner, c.device_hash);
    if (!result.ok) return result;
    const a = await owned(storage, env, owner, c);
    need(same(a.anchor.control.campaign_key, input.campaign_key), "campaign_binding_mismatch");
    const viewed = unwrap(await readCampaignControl(storage, owner));
    return ok({ ...result.value, campaign: viewed.campaign });
  } catch (e) { return failure(e); }
}

/** Invite inspection is internal and read-only. It returns no public guest
 * projection until membership is durable, and performs no capacity reservation. */
export async function campaignBindingInvite(storage: DurableObjectStorage, env: Env, owner: string, value: unknown, context: unknown) {
  try {
    const input = campaignAdmissionRequest(value, "join") as CampaignJoin, c = caller(owner, context), a = await root(storage, c.room_id);
    campaignJoin(input, definitionResolver(a.anchor.definition));
    need(same(input.campaign_key, a.member.campaign_key) && input.invite_code === a.anchor.control.invite_code, "campaign_binding_mismatch");
    const joined = owner === a.member.host_id || owner === a.member.guest_id;
    await policy(env, owner, c, a.member.host_id, joined ? a.member.guest_id : owner);
    need(campaignAccessUnchanged(storage, a), "campaign_state_changed");
    if (!joined) {
      need(a.anchor.control.state === "waiting" && a.member.status === "active" && a.member.guest_id === null, "campaign_full");
      need(a.anchor.control.invite_expires_at && Date.now() <= Date.parse(a.anchor.control.invite_expires_at), "invite_expired", 410);
    }
    return ok({ schema_version: 1 as const, definition: structuredClone(a.anchor.definition), joined });
  } catch (e) { return failure(e); }
}

export async function campaignBindingJoin(storage: DurableObjectStorage, env: Env, owner: string, value: unknown, context: unknown) {
  try {
    const input = campaignAdmissionRequest(value, "join") as CampaignJoin, c = caller(owner, context); campaignGlobalMutations(env);
    const a = await root(storage, c.room_id), joined = owner === a.member.host_id || owner === a.member.guest_id;
    campaignJoin(input, definitionResolver(a.anchor.definition));
    need(same(input.campaign_key, a.member.campaign_key) && input.invite_code === a.anchor.control.invite_code, "campaign_binding_mismatch");
    if (joined) {
      // Pure accepted membership settlement, including a deleting control. Do
      // not run either a Join or cancellation mutator on this retry path.
      const requestHash = await campaignAdmissionHash(owner, "join", input);
      const old = a.captured.tables[3]?.rows.find(row => row.request_key === owner + ":" + input.idempotency_key);
      if (old) need(old.request_hash === requestHash && same(joinFact(JSON.parse(String(old.data))).request, input), "idempotency_campaign_mismatch");
      await policy(env, owner, c, a.member.host_id, a.member.guest_id);
      await canonicalLink(env, owner, c, a.anchor.control); campaignGlobalMutations(env);
      need(campaignAccessUnchanged(storage, a), "campaign_state_changed");
      const view = structuredClone(owner === a.member.host_id ? a.anchor.control : { ...a.anchor.control, player_slot: "p1" as const, invite_code: null, invite_expires_at: null });
      return ok({ campaign: view });
    }
    if (!joined) need(unwrap(await env.PLAYERS.getByName(owner).campaignJoinAttempt(input, c.device_hash)), "campaign_allocation_unavailable");
    await policy(env, owner, c, a.member.host_id, joined ? a.member.guest_id : owner); campaignGlobalMutations(env);
    const result = await joinCampaignRoot(storage, owner, input);
    await campaignDevice(env, owner, c.device_hash); // A rotation never erases accepted membership.
    if (!result.ok) return result;
    await canonicalLink(env, owner, c, result.value.campaign);
    const current = await owned(storage, env, owner, c);
    need(same(current.member.campaign_key, input.campaign_key), "campaign_binding_mismatch");
    return await readCampaignControl(storage, owner);
  } catch (e) { return failure(e); }
}

export async function campaignBindingCancelJoin(storage: DurableObjectStorage, env: Env, owner: string, value: unknown, context: unknown) {
  try {
    const input = campaignAdmissionRequest(value, "join") as CampaignJoin, c = caller(owner, context); campaignGlobalMutations(env);
    await campaignDevice(env, owner, c.device_hash);
    const result = await cancelCampaignJoinRoot(storage, owner, input);
    await campaignDevice(env, owner, c.device_hash);
    return result; // Blocking a partner cannot strand exact admission cleanup.
  } catch (e) { return failure(e); }
}

/** The anchor supplies the full stored immutable definition to these internal
 * child helpers. Resolve only its exact request key; public input cannot use it. */
export async function campaignBindingSource(storage: DurableObjectStorage, value: unknown, seal: boolean, definition: unknown) {
  try {
    boundedCampaign(value, 4096); const request = structuredClone(value) as SourceRequest;
    const exact = await exactCampaignDefinition(definition, request.binding.campaign_key);
    return await campaignSource(storage, request, seal, definitionResolver(exact));
  } catch (e) { return failure(e); }
}
export async function campaignBindingTarget(storage: DurableObjectStorage, value: unknown, activate: boolean, definition: unknown) {
  try {
    boundedCampaign(value, 8192); const request = structuredClone(value) as TargetInitializeRequest | TargetActivateRequest;
    const exact = await exactCampaignDefinition(definition, request.binding.campaign_key);
    return activate ? await activateCampaignTarget(storage, request, definitionResolver(exact)) :
      await initializeCampaignTarget(storage, request, definitionResolver(exact));
  } catch (e) { return failure(e); }
}

export async function campaignBindingAdvance(storage: DurableObjectStorage, env: Env, owner: string, value: unknown, context: unknown, resume: boolean): Promise<Outcome<CampaignEnvelope | CampaignContinueResult>> {
  try {
    boundedCampaign(value, 4096); const input = structuredClone(value), c = caller(owner, context); controlMutations(env);
    const a = await owned(storage, env, owner, c), definition = structuredClone(a.anchor.definition);
    const check = async () => { controlMutations(env); await policy(env, owner, c, a.member.host_id, a.member.guest_id); controlMutations(env); };
    const remote = async (invoke: () => Promise<Outcome<unknown>>): Promise<Outcome<unknown>> => {
      await check(); const outcome = await invoke(); await check(); return outcome;
    };
    const deps: CampaignControlDependencies = {
      mutationPolicy: () => { try { controlMutations(env); return ok(true); } catch (e) { return failure(e); } },
      admitFresh: async (_owner, view, body) => {
        try {
          await check(); const destination = definition.chapters[body.from_index + 1];
          if (destination?.premium) await campaignHostAccess(env, view.host_id);
          await check(); return ok(true);
        } catch (e) { return failure(e); }
      },
      allocate: () => ({ transition_id: [...crypto.getRandomValues(new Uint8Array(32))].map(v => v.toString(16).padStart(2, "0")).join(""),
        invite_code: [...crypto.getRandomValues(new Uint8Array(10))].map(v => v.toString(16).padStart(2, "0")).join("").toUpperCase() }),
      source: (request, seal) => remote(() => env.ROOMS_V2.getByName(request.binding.room_id).campaignBoundSource(request, seal, definition)),
      initialize: request => remote(() => env.ROOMS_V2.getByName(request.binding.room_id).campaignBoundTarget(request, false, definition)),
      activate: request => remote(() => env.ROOMS_V2.getByName(request.binding.room_id).campaignBoundTarget(request, true, definition))
    };
    // The reviewed control helper invokes root-source observation/sealing
    // locally, never through the source callback above.
    if (resume) {
      const resumed = await resumeCampaignActivation(storage, owner, input, deps);
      await check();
      return resumed.ok ? await readCampaignControl(storage, owner) : resumed;
    }
    const result = await continueCampaignControl(storage, owner, input, deps);
    await check();
    if (!result.ok) return result;
    // Authentication/block awaits can overlap a partner's publication. Refresh
    // only local durable evidence here, never run progress/activation twice.
    const decision = result.value;
    if (decision.status !== "rejected") {
      const latest = await readCampaignOperation(storage, owner,
        decision.status === "accepted" ? decision.receipt.idempotency_key : decision.idempotency_key);
      if (!latest.ok) return latest;
      const originalHash = decision.status === "accepted" ? decision.receipt.request_hash : decision.request_hash;
      need(latest.value.status !== "rejected" && (latest.value.status === "accepted" ? latest.value.receipt.request_hash : latest.value.request_hash) === originalHash,
        "campaign_idempotency_mismatch");
      return latest;
    }
    const current = await root(storage, c.room_id); member(current, owner);
    const view = structuredClone(owner === current.member.host_id ? current.anchor.control : { ...current.anchor.control,
      player_slot: "p1" as const, invite_code: null, invite_expires_at: null });
    need(view.state !== "deleting", "campaign_deleting");
    const body = await campaignContinue(input, c.room_id, owner, definitionResolver(current.anchor.definition));
    const checked = await checkedContinueResult({ ...decision, campaign: view }, c.room_id, owner, body, definitionResolver(current.anchor.definition));
    need(campaignAccessUnchanged(storage, current), "campaign_state_changed"); return ok(checked);
  } catch (e) { return failure(e); }
}
