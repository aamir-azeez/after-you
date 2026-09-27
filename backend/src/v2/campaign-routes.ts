import { ApiError, boundedJson, canonicalJson, digest, HASH_PATTERN, type Outcome } from "../protocol";
import { roomLinkVersion } from "../room-links";
import { campaignAdmissionHash, campaignAdmissionRequest } from "./campaign-admission-intent";
import { campaignCreate, campaignJoin } from "./campaign-protocol";
import { campaignRequestContext, type CampaignRoomContext } from "./campaign-room-access";
import { campaignCreatable, definitionResolver, retainedCampaign } from "./campaign-registry";
import { campaignDevice, campaignGlobalMutations, campaignHostAccess } from "./campaign-bindings";
import type { CampaignCreate, CampaignJoin, CampaignView } from "./campaign-types";
import { campaignDeleted } from "./campaign-deletion";

const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
function need(v: unknown, code: string, status = 409): asserts v { if (!v) throw new ApiError(status, code); }
function unwrap<T>(r: Outcome<T>): T { if (!r.ok) throw new ApiError(r.status, r.code); return r.value; }
function json(value: unknown, status = 200): Response { return new Response(JSON.stringify(value), { status,
  headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" } }); }
async function context(request: Request, room: string, hash: string): Promise<CampaignRoomContext> {
  const c = await campaignRequestContext(request, room, hash); need(c, "campaign_client_required"); return c;
}
async function matchingLink(env: Env, owner: string, hash: string, view: CampaignView): Promise<void> {
  const link = unwrap(await env.PLAYERS.getByName(owner).campaignLink(view.campaign_room_id, hash));
  need(link && same(link, { room_id: view.campaign_room_id, api_version: 3, host: view.host_id === owner,
    invite_code: view.host_id === owner ? view.invite_code : "" }), "campaign_link_unavailable");
}
const code = () => [...crypto.getRandomValues(new Uint8Array(10))].map(v => v.toString(16).padStart(2, "0")).join("").toUpperCase();

/** Authenticated fixed HTTP adapter. No caller-supplied definition, binding
 * callbacks or acknowledgements cross this boundary. */
export async function routeCampaign(request: Request, path: string, owner: string, env: Env): Promise<Response> {
  need(request.headers.get("X-AfterYou-Campaign-Schema") === "2", "campaign_client_required");
  const hash = await digest(request.headers.get("Authorization")!.slice(7)), player = env.PLAYERS.getByName(owner);
  if (path === "/v2/campaigns" && request.method === "GET") {
    const links = (await player.listRooms()).filter(link => roomLinkVersion(link) === 3);
    need(links.length <= 20, "campaign_list_unavailable");
    const campaigns: CampaignView[] = [];
    for (const link of links) {
      const c = await context(request, link.room_id, hash);
      const target = env.ROOMS_V2.getByName(link.room_id), result = await target.campaignHttpRead(owner, c);
      if (!result.ok) {
        const observed = await target.campaignTerminalFact(link.room_id);
        if (observed.ok) {
          campaignDeleted(observed.value, link.room_id);
          const current = unwrap(await player.campaignLink(link.room_id, hash));
          need(current && same(current, link), "campaign_link_unavailable");
          // Discovery only. The explicit POST obtains fresh terminal evidence
          // and retained provenance before any local or server link release.
          return json({ error: { code: "campaign_terminal_reconciliation_required", campaign_room_id: link.room_id } }, 409);
        }
      }
      const viewed = unwrap(result);
      need("campaign" in viewed, "campaign_list_unavailable");
      await matchingLink(env, owner, hash, viewed.campaign); campaigns.push(viewed.campaign);
    }
    await campaignDevice(env, owner, hash);
    // An incomplete/unknown linked root holds the whole list; never prune it.
    return json({ campaigns });
  }
  const terminal = path.match(/^\/v2\/campaigns\/([A-Za-z0-9_-]{22})\/reconcile-deletion$/);
  if (terminal && request.method === "POST") {
    campaignGlobalMutations(env);
    const input = await boundedJson(request, 512);
    need(typeof input === "object" && input !== null && !Array.isArray(input) && Object.keys(input).length === 1 &&
      "schema_version" in input && input.schema_version === 1, "invalid_campaign_terminal_request", 422);
    const rootId = terminal[1], scope = unwrap(await player.campaignTerminalScope(rootId, hash));
    const evidence = campaignDeleted(unwrap(await env.ROOMS_V2.getByName(rootId).campaignTerminalFact(rootId)), rootId);
    campaignGlobalMutations(env);
    return json(unwrap(await player.finalizeCampaignTerminalLink(scope, evidence, hash)));
  }
  if (path === "/v2/campaigns" && request.method === "POST") {
    campaignGlobalMutations(env);
    const input = campaignAdmissionRequest(await boundedJson(request, 4096), "create") as CampaignCreate;
    let intent = unwrap(await player.campaignCreation(input.idempotency_key, input.campaign_key, hash));
    if (!intent) {
      const definition = retainedCampaign(input.campaign_key);
      need(definition && campaignCreatable(input.campaign_key, env), "campaign_creation_disabled", 503);
      campaignCreate(input, definitionResolver(definition));
      if (definition.chapters[0].premium) await campaignHostAccess(env, owner);
      await campaignDevice(env, owner, hash); campaignGlobalMutations(env);
      need(campaignCreatable(input.campaign_key, env), "campaign_creation_disabled", 503);
      const invite_code = code(), room_id = (await digest("v2:" + invite_code)).slice(0, 22);
      intent = unwrap(await player.reserveCampaignRoom(input.idempotency_key, { creation_schema: 2,
        link: { room_id, invite_code, host: true, api_version: 3 }, campaign_key: input.campaign_key }, hash));
    }
    const c = await context(request, intent.link.room_id, hash);
    const result = unwrap(await env.ROOMS_V2.getByName(intent.link.room_id).campaignHttpInitialize(owner, input, c, retainedCampaign(input.campaign_key)));
    await matchingLink(env, owner, hash, result.campaign);
    return json({ campaign: result.campaign }, result.created ? 201 : 200);
  }
  if (path === "/v2/campaigns/join" && request.method === "POST") {
    campaignGlobalMutations(env);
    const input = campaignAdmissionRequest(await boundedJson(request, 4096), "join") as CampaignJoin;
    const room = (await digest("v2:" + input.invite_code)).slice(0, 22), c = await context(request, room, hash), target = env.ROOMS_V2.getByName(room);
    const known = unwrap(await target.campaignHttpInvite(owner, input, c));
    campaignJoin(input, definitionResolver(known.definition));
    if (!known.joined) {
      const admitted = unwrap(await player.campaignJoinAttempt(input, hash));
      if (!admitted) {
        need(campaignCreatable(input.campaign_key, env), "campaign_creation_disabled", 503);
        await campaignDevice(env, owner, hash); campaignGlobalMutations(env);
        need(campaignCreatable(input.campaign_key, env), "campaign_creation_disabled", 503);
        unwrap(await player.reserveCampaignJoin(input, hash));
      }
    }
    const accepted = unwrap(await target.campaignHttpJoin(owner, input, c));
    await matchingLink(env, owner, hash, accepted.campaign);
    return json(accepted);
  }
  if ((path === "/v2/campaigns/cancel" || path === "/v2/campaigns/join/cancel") && request.method === "POST") {
    campaignGlobalMutations(env);
    const admission = path.endsWith("/join/cancel") ? "join" : "create";
    const input = campaignAdmissionRequest(await boundedJson(request, 4096), admission);
    const request_hash = await campaignAdmissionHash(owner, admission, input);
    const common = { schema_version: 1, operation: "campaign_admission_cancel", admission,
      player_id: owner, idempotency_key: input.idempotency_key, request_hash };
    if (admission === "create") {
      // Correlate only retained exact allocation + actual permanent root fact.
      // This read precedes old Cancel because prior cleanup may remove its link.
      const scope = unwrap(await player.campaignTerminalAdmissionScope(input, hash));
      if (scope) {
        const room = scope.allocation.link.room_id;
        const observed = await env.ROOMS_V2.getByName(room).campaignTerminalFact(room);
        if (observed.ok) {
          const evidence = campaignDeleted(observed.value, room);
          await campaignDevice(env, owner, hash); campaignGlobalMutations(env);
          return json(unwrap(await player.finalizeCampaignTerminalAdmission(scope, evidence, hash)));
        }
      }
      const decision = unwrap(await player.cancelCampaignCreation(input, hash));
      if (decision.status === "cancelled") return json({ ...common, status: "cancelled", campaign: null });
      const room = decision.intent.link.room_id, c = await context(request, room, hash);
      // Already admitted but not initialized remains a hold. Cancel never
      // allocates/initializes gameplay merely to manufacture an accepted view.
      const accepted = unwrap(await env.ROOMS_V2.getByName(room).campaignHttpSettlement(owner, c));
      need("campaign" in accepted, "campaign_state_unavailable");
      await matchingLink(env, owner, hash, accepted.campaign);
      return json({ ...common, status: "accepted", campaign: accepted.campaign });
    }
    const join = input as CampaignJoin, room = (await digest("v2:" + join.invite_code)).slice(0, 22), c = await context(request, room, hash);
    const local = unwrap(await player.cancelUnreservedCampaignJoin(join, hash));
    if (local.status === "cancelled") return json({ ...common, status: "cancelled", campaign: null });
    const decision = unwrap(await env.ROOMS_V2.getByName(room).campaignHttpCancelJoin(owner, join, c));
    if (decision.status === "accepted") {
      need(decision.campaign, "campaign_state_unavailable"); await matchingLink(env, owner, hash, decision.campaign);
      return json({ ...common, status: "accepted", campaign: decision.campaign });
    }
    unwrap(await player.finalizeCampaignJoinCancellation(join, decision, hash));
    return json({ ...common, status: "cancelled", campaign: null });
  }
  const match = path.match(/^\/v2\/campaigns\/([A-Za-z0-9_-]{22})(?:\/(continue|resume|operations)(?:\/([a-f0-9]{64}))?)?$/);
  if (!match) throw new ApiError(404, "not_found");
  const [, room, operation, item] = match, c = await context(request, room, hash), target = env.ROOMS_V2.getByName(room);
  if (!operation && request.method === "GET") return json(unwrap(await target.campaignHttpRead(owner, c)));
  if (operation === "operations" && item && HASH_PATTERN.test(item) && request.method === "GET") {
    const result = unwrap(await target.campaignHttpRead(owner, c, item));
    need("status" in result, "campaign_state_unavailable"); return json(result, result.status === "pending" ? 202 : 200);
  }
  if ((operation === "continue" || operation === "resume") && !item && request.method === "POST") {
    campaignGlobalMutations(env);
    const input = await boundedJson(request, 4096);
    const result = unwrap(await target.campaignHttpAdvance(owner, input, c, operation === "resume"));
    if (operation === "continue") { need("status" in result, "campaign_state_unavailable"); return json(result, result.status === "pending" ? 202 : 200); }
    need("campaign" in result && typeof input === "object" && input !== null && "transition_id" in input, "invalid_campaign_resume", 422);
    return json(result, result.campaign.activation?.transition_id === input.transition_id ? 202 : 200);
  }
  throw new ApiError(405, "method_not_allowed");
}
