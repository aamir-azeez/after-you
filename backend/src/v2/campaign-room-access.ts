import { ApiError, HASH_PATTERN, ID_PATTERN, canonicalJson, digest, fail, isObject, ok, type Outcome } from "../protocol";
import { chapter } from "./chapters";
import { boundedCampaign, campaignDefinition, campaignView } from "./campaign-protocol";
import { campaignAccessGuard, campaignAccessUnchanged, campaignRoomHint, prepareCampaignAccess, type CampaignAccess } from "./campaign-source";
import type { CampaignDefinition, CampaignView } from "./campaign-types";
import { campaignProductionEnabled } from "./campaign-production";

/** Constructed by the authenticated route. This is request metadata, not an
 * authorization token; each Room call obtains fresh local/anchor authority. */
export type CampaignRoomContext = { schema_version: 2; room_id: string; device_hash: string };
/** Shared authentication has already run. Wrong/absent negotiation is left
 * absent so ordinary rooms keep their existing behavior. */
export async function campaignRequestContext(request: Request, room: string, deviceHash?: string): Promise<CampaignRoomContext | undefined> {
  if (request.headers.get("X-AfterYou-Campaign-Schema") !== "2") return undefined;
  const authorization = request.headers.get("Authorization");
  need(typeof authorization === "string" && authorization.startsWith("Bearer "), "invalid_auth", 401);
  return context({ schema_version: 2, room_id: room, device_hash: deviceHash ?? await digest(authorization.slice(7)) });
}
type Authority = { schema_version: 1; definition: CampaignDefinition; campaign: CampaignView };
export type CampaignHttpAccess = (NonNullable<CampaignAccess> & { publication: CampaignView }) | null;
const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
function need(value: unknown, code = "campaign_state_unavailable", status = 409): asserts value { if (!value) throw new ApiError(status, code); }
function unwrap<T>(result: Outcome<T>): T { if (!result.ok) throw new ApiError(result.status, result.code); return result.value; }
function known(pin: CampaignDefinition["chapters"][number]): boolean {
  try { const a = chapter(pin); return a.premium === pin.premium && (a.supported_simulation_versions ?? [a.simulation_version]).includes(pin.simulation_version); }
  catch { return false; }
}
function context(value: unknown): CampaignRoomContext {
  need(isObject(value) && Object.keys(value).length === 3 && value.schema_version === 2 && typeof value.room_id === "string" && ID_PATTERN.test(value.room_id) &&
    typeof value.device_hash === "string" && HASH_PATTERN.test(value.device_hash), "campaign_client_required");
  return { schema_version: 2, room_id: value.room_id, device_hash: value.device_hash };
}
function project(view: CampaignView, owner: string): CampaignView {
  need(owner === view.host_id || owner === view.guest_id, "campaign_owner_mismatch", 403);
  return structuredClone(owner === view.host_id ? view : { ...view, player_slot: "p1", invite_code: null, invite_expires_at: null });
}
async function authority(value: unknown, owner: string, root: string, room: string): Promise<Authority> {
  boundedCampaign(value); need(isObject(value) && Object.keys(value).length === 3 && value.schema_version === 1 && Object.hasOwn(value, "definition") && Object.hasOwn(value, "campaign"));
  const frozen = structuredClone(value), definition = await campaignDefinition(frozen.definition, known);
  const key = { campaign_id: definition.campaign_id, campaign_version: definition.campaign_version, definition_hash: definition.definition_hash };
  const campaign = await campaignView(frozen.campaign, owner, k => same(k, key) ? definition : undefined);
  need(campaign.campaign_room_id === root && campaign.chapters.some(c => c.room_id === room));
  return { schema_version: 1, definition, campaign };
}

/** Binding-only, read-only publication lookup. A room hint is merely an address;
 * the stored anchor supplies the definition and proves publication/membership. */
export async function campaignRoomAuthority(storage: DurableObjectStorage, owner: string, room: string): Promise<Outcome<Authority>> {
  try {
    need(ID_PATTERN.test(owner) && ID_PATTERN.test(room), "invalid_campaign_room", 422);
    const access = await prepareCampaignAccess(storage);
    need(access?.anchor && access.member.room_id === access.member.campaign_room_id);
    const campaign = project(access.anchor.control, owner);
    need(campaign.chapters.some(c => c.room_id === room), "campaign_room_unpublished");
    need(campaignAccessUnchanged(storage, access), "campaign_state_changed");
    return ok({ schema_version: 1, definition: structuredClone(access.anchor.definition), campaign });
  } catch (e) { return e instanceof ApiError ? fail(e.status, e.code) : fail(409, "campaign_state_unavailable"); }
}

/** Narrow negotiation check for an already durable account safety receipt.
 * It neither grants room access nor requires a live room after deletion. */
export function campaignRoomNegotiation(storage: DurableObjectStorage, supported: boolean): Outcome<true> {
  if (supported) return ok(true);
  try { return campaignRoomHint(storage) !== null ? fail(409, "campaign_client_required") : ok(true); }
  catch { return fail(409, "campaign_state_unavailable"); }
}

export async function prepareCampaignHttpAccess(storage: DurableObjectStorage, env: Env, owner: string, supplied?: CampaignRoomContext): Promise<CampaignHttpAccess> {
  const hint = campaignRoomHint(storage);
  if (hint === null) return null;
  const c = context(supplied); need(c.room_id === hint.room_id, "campaign_binding_mismatch");
  let access: NonNullable<CampaignAccess>, verified: Authority;
  if (hint.room_id === hint.campaign_room_id) {
    const local = await prepareCampaignAccess(storage); need(local?.anchor);
    access = local;
    verified = { schema_version: 1, definition: structuredClone(local.anchor.definition), campaign: project(local.anchor.control, owner) };
  } else {
    const reply = unwrap(await env.ROOMS_V2.getByName(hint.campaign_room_id).campaignRoomAuthority(owner, c.room_id));
    verified = await authority(reply, owner, hint.campaign_room_id, c.room_id);
    const key = verified.campaign.campaign_key;
    const local = await prepareCampaignAccess(storage, k => same(k, key) ? verified.definition : undefined); need(local);
    access = local;
  }
  const m = access.member, v = verified.campaign, entry = v.chapters[m.chapter_index];
  need(m.room_id === c.room_id && m.campaign_room_id === v.campaign_room_id && same(m.campaign_key, v.campaign_key) &&
    m.host_id === v.host_id && m.guest_id === v.guest_id && entry?.room_id === m.room_id && same(entry.chapter, m.chapter), "campaign_binding_mismatch");
  if (m.chapter_index > 0) {
    const previousEntry = v.chapters[m.chapter_index - 1], previous = previousEntry.completion;
    need(previous && m.transition_id === previous.transition_id && m.incoming?.accepted_revision === previous.accepted_campaign_revision &&
      same(m.incoming.origin, { expected_revision: previous.from_campaign_revision, from_index: m.chapter_index - 1,
        source: { room_id: previousEntry.room_id, revision: previous.source_revision, branch: previous.source_branch, checkpoint_hash: previous.checkpoint_hash } }), "campaign_binding_mismatch");
  }
  if (entry.completion) {
    const completed = entry.completion;
    need(same(m.seal, { transition_id: completed.transition_id, origin: { expected_revision: completed.from_campaign_revision, from_index: m.chapter_index,
      source: { room_id: m.room_id, revision: completed.source_revision, branch: completed.source_branch, checkpoint_hash: completed.checkpoint_hash } } }), "campaign_binding_mismatch");
  } else if (m.seal !== null) {
    need(v.transition && same(m.seal, { transition_id: v.transition.transition_id, origin: v.transition.origin }), "campaign_binding_mismatch");
  }
  need(v.state !== "deleting", "campaign_not_active");
  need(m.chapter_index <= v.current_index && (m.chapter_index === v.current_index || m.status === "sealed" && entry.completion !== null), "campaign_room_unpublished");
  need(!(m.chapter_index === v.current_index && v.activation !== null), "campaign_activation_pending");
  if (!await env.PLAYERS.getByName(owner).authorize(c.device_hash)) throw new ApiError(401, "identity_unavailable");
  const result = { ...access, publication: v };
  const guard = campaignHttpAccessGuard(storage, result); if (guard && !guard.ok) throw new ApiError(guard.status, guard.code);
  return result;
}

/** No awaits after this guard and before a local projection/write. Remote
 * deletion takes effect here when its durable local fence arrives. */
export function campaignHttpAccessGuard(storage: DurableObjectStorage, access: CampaignHttpAccess, newGameplay = false): Outcome<never> | null {
  const guard = campaignAccessGuard(storage, access, newGameplay); if (guard) return guard;
  if (access && newGameplay && !campaignProductionEnabled()) return fail(503, "campaign_unavailable");
  if (access && newGameplay && (access.member.chapter_index !== access.publication.current_index || access.publication.state === "complete")) return fail(409, "campaign_source_sealed");
  return null;
}
