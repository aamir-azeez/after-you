import { ApiError, HASH_PATTERN, IDEMPOTENCY_PATTERN, canonicalJson, digest, object, text } from "../protocol";
import { parseRedoMutation, validRedoSource, type RedoMutation, type RedoSource, type RedoState } from "../redo-control";
import { boundedCampaign } from "./campaign-protocol";
import type { CampaignHttpAccess } from "./campaign-room-access";
import type { CampaignChapterPin, CampaignKey, CampaignView } from "./campaign-types";
import { exact } from "./protocol";
import type { ReceiptV2 } from "./room";

export type CampaignRedoBinding = {
  campaign_room_id: string; campaign_key: CampaignKey; chapter_index: number;
  chapter: CampaignChapterPin; room_id: string;
};
export type CampaignRedoMode = "read" | "mutate" | "accept" | "operation";
export type CampaignRedoAccept = { schema_version: 1; binding: CampaignRedoBinding; source: RedoSource; request_id: string; idempotency_key: string };
export type CampaignRedoEnvelope = { schema_version: 1; binding: CampaignRedoBinding } & ({ redo: RedoState } | { receipt: ReceiptV2 });
export const sameRedoValue = (a: unknown, b: unknown): boolean => canonicalJson(a) === canonicalJson(b);
function need(value: unknown, code = "campaign_redo_binding_mismatch", status = 409): asserts value { if (!value) throw new ApiError(status, code); }

/** Publication is authority; a supplied binding is only an exact expectation. */
export function campaignRedoBinding(view: CampaignView, index: number): CampaignRedoBinding {
  need(Number.isSafeInteger(index) && index >= 0 && index < view.chapters.length, "campaign_room_unpublished");
  const entry = view.chapters[index];
  need(entry.room_id && index <= view.current_index, "campaign_room_unpublished");
  return { campaign_room_id: view.campaign_room_id, campaign_key: structuredClone(view.campaign_key), chapter_index: index,
    chapter: structuredClone(entry.chapter), room_id: entry.room_id };
}
export function campaignRedoAccess(access: CampaignHttpAccess, binding: CampaignRedoBinding, fresh = false): void {
  need(access && sameRedoValue(campaignRedoBinding(access.publication, access.member.chapter_index), binding));
  if (fresh) need(access.publication.state === "active" && access.publication.current_index === binding.chapter_index &&
    access.publication.transition === null && access.publication.activation === null && access.member.status === "active" && access.member.seal === null,
  "campaign_redo_not_current");
}
export function campaignRedoMutations(env: Env): void {
  need(String(env.V2_ROOMS_ENABLED) === "true", "v2_mutations_disabled", 503);
  need(String(env.CAMPAIGN_MUTATIONS_ENABLED) === "true", "campaign_mutations_disabled", 503);
}
export async function campaignRedoInput(value: unknown, binding: CampaignRedoBinding, accept: true): Promise<CampaignRedoAccept>;
export async function campaignRedoInput(value: unknown, binding: CampaignRedoBinding, accept: false): Promise<RedoMutation>;
export async function campaignRedoInput(value: unknown, binding: CampaignRedoBinding, accept: boolean): Promise<CampaignRedoAccept | RedoMutation> {
  boundedCampaign(value, 4096); const input = object(value);
  exact(input, accept ? ["schema_version", "binding", "source", "request_id", "idempotency_key"] : ["schema_version", "binding", "action", "source"]);
  need(input.schema_version === 1 && sameRedoValue(input.binding, binding), "campaign_redo_binding_mismatch", 422);
  need(validRedoSource(input.source) && input.source.room_id === binding.room_id, "invalid_redo_request", 400);
  if (!accept) return parseRedoMutation({ action: input.action, source: input.source });
  const request_id = text(input.request_id, HASH_PATTERN), idempotency_key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
  need(request_id === await digest(canonicalJson(input.source)), "invalid_redo_request", 400);
  return { schema_version: 1, binding, source: structuredClone(input.source), request_id, idempotency_key };
}
export function campaignRedoFork(input: CampaignRedoAccept) {
  return { base_revision: input.source.revision, branch: input.source.branch, stage_index: input.source.stage_index,
    idempotency_key: input.idempotency_key, redo_request_id: input.request_id };
}
/** Never attach today's room snapshot to a historical acceptance envelope. */
export function campaignRedoReceipt(receipt: ReceiptV2, binding: CampaignRedoBinding, key: string): ReceiptV2 {
  need(receipt.operation === "fork" && receipt.room_id === binding.room_id && receipt.idempotency_key === key &&
    receipt.turn_id === null && receipt.recording_hash === null && receipt.pair_id === null, "operation_not_found", 404);
  return structuredClone(receipt);
}
