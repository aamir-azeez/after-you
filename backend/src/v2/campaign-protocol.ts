import { ApiError, canonicalJson, digest, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, isObject } from "../protocol";
import {
  MAX_CAMPAIGN_CHAPTERS, MAX_CAMPAIGN_CONTROL_BYTES, MAX_CAMPAIGN_DEPTH,
  MAX_CAMPAIGN_LIST_BYTES, MAX_CAMPAIGN_LIST_DEPTH, MAX_CAMPAIGN_LIST_NODES,
  MAX_CAMPAIGN_NODES, MAX_CAMPAIGN_REQUEST_BYTES,
  type CampaignChapterPin, type CampaignContinue, type CampaignContinueResult,
  type CampaignCreate, type CampaignDefinition, type CampaignJoin, type CampaignKey,
  type CampaignList, type CampaignOrigin, type CampaignView
} from "./campaign-types";

const SLUG = /^[a-z][a-z0-9-]{0,47}$/;
const INVITE = /^[A-F0-9]{20}$/;
const ENCODER = new TextEncoder();
const SAFE = Number.MAX_SAFE_INTEGER;
export type CampaignDefinitionResolver = (key: CampaignKey) => CampaignDefinition | undefined;
export type CampaignChapterVerifier = (pin: CampaignChapterPin) => boolean;

function need(condition: unknown, code = "invalid_campaign", status = 422): asserts condition {
  if (!condition) throw new ApiError(status, code);
}
function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  need(isObject(value), "invalid_campaign_object", 400);
  need(Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)), "invalid_campaign_fields", 400);
  return value;
}
function text(value: unknown, regex: RegExp): asserts value is string { need(typeof value === "string" && regex.test(value)); }
function number(value: unknown, min = 0, max = SAFE): asserts value is number { need(typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max); }
function same(a: unknown, b: unknown): boolean { return canonicalJson(a) === canonicalJson(b); }

/** Bounded traversal happens before canonical hashing or recursive validation. */
export function boundedCampaign(value: unknown, bytes = MAX_CAMPAIGN_CONTROL_BYTES, nodes = MAX_CAMPAIGN_NODES, depth = MAX_CAMPAIGN_DEPTH): void {
  type Item = { value: unknown; depth: number; leave?: object };
  const pending: Item[] = [{ value, depth: 0 }], ancestors = new Set<object>();
  let count = 0, size = 0;
  const add = (amount: number) => { size += amount; need(size <= bytes, "campaign_body_too_large", 413); };
  const stringBytes = (s: string) => { need(s.length <= bytes, "campaign_body_too_large", 413); return ENCODER.encode(JSON.stringify(s)).length; };
  while (pending.length) {
    const item = pending.pop()!;
    if (item.leave) { ancestors.delete(item.leave); continue; }
    need(++count <= nodes && item.depth <= depth, "campaign_structure_limit", 413);
    const current = item.value;
    if (current === null) { add(4); continue; }
    if (typeof current === "string") { add(stringBytes(current)); continue; }
    if (typeof current === "boolean") { add(current ? 4 : 5); continue; }
    if (typeof current === "number") { need(Number.isFinite(current), "invalid_campaign_number", 400); add(JSON.stringify(current).length); continue; }
    need(Array.isArray(current) || (isObject(current) && (Object.getPrototypeOf(current) === Object.prototype || Object.getPrototypeOf(current) === null)), "invalid_campaign_json", 400);
    need(!ancestors.has(current), "campaign_cycle", 400);
    ancestors.add(current); pending.push({ value: null, depth: 0, leave: current });
    if (Array.isArray(current)) {
      need(current.length + count <= nodes, "campaign_structure_limit", 413);
      add(2 + Math.max(0, current.length - 1));
      for (let index = current.length - 1; index >= 0; index--) pending.push({ value: current[index], depth: item.depth + 1 });
    } else {
      const keys = Object.keys(current);
      need(keys.length + count <= nodes, "campaign_structure_limit", 413);
      add(2 + Math.max(0, keys.length - 1));
      for (const key of keys) { add(stringBytes(key) + 1); pending.push({ value: current[key], depth: item.depth + 1 }); }
    }
  }
}

function key(value: unknown): CampaignKey {
  const x = exact(value, ["campaign_id", "campaign_version", "definition_hash"]);
  text(x.campaign_id, SLUG); number(x.campaign_version, 1); text(x.definition_hash, HASH_PATTERN);
  return x as CampaignKey;
}
function pin(value: unknown): CampaignChapterPin {
  const x = exact(value, ["level_id", "level_version", "definition_hash", "simulation_version", "premium"]);
  text(x.level_id, SLUG); number(x.level_version, 1); text(x.definition_hash, HASH_PATTERN); number(x.simulation_version, 1); need(typeof x.premium === "boolean");
  return x as CampaignChapterPin;
}
function source(value: unknown): void {
  const x = exact(value, ["room_id", "revision", "branch", "checkpoint_hash"]);
  text(x.room_id, ID_PATTERN); number(x.revision); number(x.branch, 0, 31); text(x.checkpoint_hash, HASH_PATTERN);
}
function origin(value: unknown, count: number): CampaignOrigin {
  const x = exact(value, ["expected_revision", "from_index", "source"]);
  number(x.expected_revision); number(x.from_index, 0, count - 1); source(x.source);
  return x as CampaignOrigin;
}
function definitionKey(definition: CampaignDefinition): CampaignKey {
  return { campaign_id: definition.campaign_id, campaign_version: definition.campaign_version, definition_hash: definition.definition_hash };
}
function resolve(value: unknown, registry: CampaignDefinitionResolver): CampaignDefinition {
  const parsed = key(value), found = registry(parsed);
  need(found && same(definitionKey(found), parsed), "unsupported_campaign");
  return found;
}

/** Registry construction validates the narrative pin, every adapter pin and full hash. */
export async function campaignDefinition(value: unknown, verifyChapter: CampaignChapterVerifier): Promise<CampaignDefinition> {
  boundedCampaign(value);
  const x = exact(value, ["schema_version", "campaign_id", "campaign_version", "story", "chapters", "definition_hash"]);
  need(x.schema_version === 1, "unsupported_campaign_schema");
  key({ campaign_id: x.campaign_id, campaign_version: x.campaign_version, definition_hash: x.definition_hash });
  const story = exact(x.story, ["story_id", "story_version", "content_hash"]);
  text(story.story_id, SLUG); number(story.story_version, 1); text(story.content_hash, HASH_PATTERN);
  need(Array.isArray(x.chapters) && x.chapters.length >= 2 && x.chapters.length <= MAX_CAMPAIGN_CHAPTERS);
  for (const entry of x.chapters) need(verifyChapter(structuredClone(pin(entry))), "unsupported_campaign_chapter");
  const { definition_hash, ...body } = x;
  need(await digest(canonicalJson(body)) === definition_hash, "campaign_definition_hash_mismatch");
  return structuredClone(x) as CampaignDefinition;
}

/** The caller's registry contains definitions validated during registration, never wire definitions. */
export async function campaignView(value: unknown, owner: string, registry: CampaignDefinitionResolver): Promise<CampaignView> {
  boundedCampaign(value); text(owner, ID_PATTERN);
  const x = exact(value, ["schema_version", "api_version", "campaign_room_id", "campaign_key", "revision", "host_id", "guest_id", "player_slot", "state", "current_index", "chapters", "transition", "invite_code", "invite_expires_at"]);
  need(x.schema_version === 1 && x.api_version === 2, "unsupported_campaign_schema");
  const definition = resolve(x.campaign_key, registry);
  text(x.campaign_room_id, ID_PATTERN); text(x.host_id, ID_PATTERN); number(x.revision);
  if (x.guest_id !== null) { text(x.guest_id, ID_PATTERN); need(x.guest_id !== x.host_id); }
  need(owner === x.host_id || owner === x.guest_id, "campaign_owner_mismatch");
  need(x.player_slot === (owner === x.host_id ? "p0" : "p1"));
  if (owner === x.host_id) {
    text(x.invite_code, INVITE);
    need((await digest("v2:" + x.invite_code)).slice(0, 22) === x.campaign_room_id, "campaign_invite_mismatch");
    need(typeof x.invite_expires_at === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(x.invite_expires_at));
    need(Number.isFinite(Date.parse(x.invite_expires_at)) && new Date(x.invite_expires_at).toISOString() === x.invite_expires_at);
  } else need(x.invite_code === null && x.invite_expires_at === null);
  need(["waiting", "active", "continuing", "complete", "deleting"].includes(String(x.state)));
  need(Array.isArray(x.chapters) && x.chapters.length === definition.chapters.length);
  number(x.current_index, 0, definition.chapters.length - 1);
  const rooms = new Set<string>(), transitions = new Set<string>();
  let previousAccepted = 0, currentComplete = false;
  for (let index = 0; index < x.chapters.length; index++) {
    const row = exact(x.chapters[index], ["chapter", "room_id", "completion"]);
    need(same(pin(row.chapter), definition.chapters[index]), "campaign_chapter_mismatch");
    if (index > x.current_index) { need(row.room_id === null && row.completion === null); continue; }
    text(row.room_id, ID_PATTERN); need(!rooms.has(row.room_id)); rooms.add(row.room_id);
    if (index === 0) need(row.room_id === x.campaign_room_id);
    if (row.completion === null) { need(index === x.current_index); continue; }
    const completed = exact(row.completion, ["source_revision", "source_branch", "checkpoint_hash", "transition_id", "from_campaign_revision", "accepted_campaign_revision"]);
    number(completed.source_revision); number(completed.source_branch, 0, 31); text(completed.checkpoint_hash, HASH_PATTERN); text(completed.transition_id, HASH_PATTERN);
    number(completed.from_campaign_revision, previousAccepted); number(completed.accepted_campaign_revision, completed.from_campaign_revision + 1, x.revision);
    need(!transitions.has(completed.transition_id)); transitions.add(completed.transition_id); previousAccepted = completed.accepted_campaign_revision;
    if (index === x.current_index) currentComplete = true;
  }
  const terminal = x.current_index === x.chapters.length - 1 && currentComplete;
  need(!currentComplete || ((x.state === "complete" || x.state === "deleting") && terminal && x.transition === null));
  if (x.state === "waiting" || x.guest_id === null) need(x.current_index === 0 && !currentComplete && x.transition === null && (x.state === "waiting" || x.state === "deleting"));
  if (x.state === "waiting") need(x.guest_id === null);
  if (x.state === "active" || x.state === "continuing" || x.state === "complete") need(x.guest_id !== null);
  if (x.state === "complete") need(terminal && x.transition === null);
  if (x.state === "continuing") need(x.transition !== null);
  if (x.transition !== null) {
    need((x.state === "continuing" || x.state === "deleting") && x.guest_id !== null && !currentComplete);
    const transition = exact(x.transition, ["transition_id", "phase", "origin"]);
    text(transition.transition_id, HASH_PATTERN); need(!transitions.has(transition.transition_id));
    need(["prepared", "source_sealed", "target_initialized"].includes(String(transition.phase)));
    const from = origin(transition.origin, x.chapters.length);
    need(from.from_index === x.current_index && from.source.room_id === (x.chapters[x.current_index] as Record<string, unknown>).room_id);
    need(from.expected_revision >= previousAccepted && from.expected_revision < x.revision);
    need(transition.phase !== "target_initialized" || from.from_index < x.chapters.length - 1);
  } else need(x.state !== "continuing");
  return structuredClone(x) as CampaignView;
}

export async function campaignEnvelope(value: unknown, owner: string, registry: CampaignDefinitionResolver): Promise<{ campaign: CampaignView }> {
  boundedCampaign(value); const x = exact(value, ["campaign"]); return { campaign: await campaignView(x.campaign, owner, registry) };
}
export async function campaignList(value: unknown, owner: string, registry: CampaignDefinitionResolver): Promise<CampaignList> {
  boundedCampaign(value, MAX_CAMPAIGN_LIST_BYTES, MAX_CAMPAIGN_LIST_NODES, MAX_CAMPAIGN_LIST_DEPTH);
  const x = exact(value, ["campaigns"]); need(Array.isArray(x.campaigns) && x.campaigns.length <= 20);
  const campaigns = await Promise.all(x.campaigns.map(view => campaignView(view, owner, registry)));
  need(new Set(campaigns.map(view => view.campaign_room_id)).size === campaigns.length);
  return { campaigns };
}
export function campaignCreate(value: unknown, registry: CampaignDefinitionResolver): CampaignCreate {
  boundedCampaign(value, MAX_CAMPAIGN_REQUEST_BYTES);
  const x = exact(value, ["schema_version", "idempotency_key", "campaign_key"]);
  need(x.schema_version === 1, "unsupported_campaign_schema"); text(x.idempotency_key, IDEMPOTENCY_PATTERN); resolve(x.campaign_key, registry);
  return structuredClone(x) as CampaignCreate;
}
export function campaignJoin(value: unknown, registry: CampaignDefinitionResolver): CampaignJoin {
  boundedCampaign(value, MAX_CAMPAIGN_REQUEST_BYTES);
  const x = exact(value, ["schema_version", "invite_code", "campaign_key", "supported_simulation_versions"]);
  need(x.schema_version === 1, "unsupported_campaign_schema"); text(x.invite_code, INVITE); const definition = resolve(x.campaign_key, registry);
  need(Array.isArray(x.supported_simulation_versions) && x.supported_simulation_versions.length > 0 && x.supported_simulation_versions.length <= 8);
  for (const version of x.supported_simulation_versions) number(version, 1);
  need(new Set(x.supported_simulation_versions).size === x.supported_simulation_versions.length);
  need(definition.chapters.every(chapter => (x.supported_simulation_versions as number[]).includes(chapter.simulation_version)), "unsupported_campaign_simulation");
  return structuredClone(x) as CampaignJoin;
}

export function continueOrigin(body: CampaignContinue): CampaignOrigin {
  return { expected_revision: body.expected_revision, from_index: body.from_index, source: structuredClone(body.source) };
}
export async function campaignContinueKey(campaignRoomId: string, campaignKey: CampaignKey, playerId: string, from: CampaignOrigin): Promise<string> {
  boundedCampaign(from, MAX_CAMPAIGN_REQUEST_BYTES); text(campaignRoomId, ID_PATTERN); text(playerId, ID_PATTERN); key(campaignKey); origin(from, MAX_CAMPAIGN_CHAPTERS);
  return digest(canonicalJson({ operation: "campaign_continue", schema_version: 1, campaign_room_id: campaignRoomId, campaign_key: campaignKey, player_id: playerId, origin: from }));
}
export async function campaignRequestHash(campaignRoomId: string, playerId: string, body: CampaignContinue): Promise<string> {
  boundedCampaign(body, MAX_CAMPAIGN_REQUEST_BYTES); text(campaignRoomId, ID_PATTERN); text(playerId, ID_PATTERN);
  return digest(canonicalJson({ operation: "campaign_continue", campaign_room_id: campaignRoomId, player_id: playerId, body }));
}
export async function campaignContinue(value: unknown, campaignRoomId: string, owner: string, registry: CampaignDefinitionResolver): Promise<CampaignContinue> {
  boundedCampaign(value, MAX_CAMPAIGN_REQUEST_BYTES); text(campaignRoomId, ID_PATTERN); text(owner, ID_PATTERN);
  const x = exact(value, ["schema_version", "idempotency_key", "campaign_key", "expected_revision", "from_index", "source"]);
  need(x.schema_version === 1, "unsupported_campaign_schema"); text(x.idempotency_key, HASH_PATTERN);
  const definition = resolve(x.campaign_key, registry);
  const from = origin({ expected_revision: x.expected_revision, from_index: x.from_index, source: x.source }, definition.chapters.length);
  need(await campaignContinueKey(campaignRoomId, key(x.campaign_key), owner, from) === x.idempotency_key, "campaign_idempotency_mismatch");
  return structuredClone(x) as CampaignContinue;
}

export async function campaignContinueResult(value: unknown, campaignRoomId: string, owner: string, request: CampaignContinue, registry: CampaignDefinitionResolver): Promise<CampaignContinueResult> {
  boundedCampaign(value);
  const body = await campaignContinue(request, campaignRoomId, owner, registry), from = continueOrigin(body);
  need(isObject(value)); const status = value.status;
  need(status === "pending" || status === "accepted" || status === "rejected");
  const x = exact(value, status === "pending" ? ["schema_version", "operation", "status", "player_id", "idempotency_key", "request_hash", "transition_id", "campaign"] : ["schema_version", "operation", "status", "receipt", "campaign"]);
  need(x.schema_version === 1 && x.operation === "campaign_continue", "unsupported_campaign_schema");
  const view = await campaignView(x.campaign, owner, registry), expectedHash = await campaignRequestHash(campaignRoomId, owner, body);
  need(view.campaign_room_id === campaignRoomId && same(view.campaign_key, body.campaign_key));
  if (status === "pending") {
    need(x.player_id === owner && x.idempotency_key === body.idempotency_key && x.request_hash === expectedHash);
    need(view.transition && x.transition_id === view.transition.transition_id && same(view.transition.origin, from));
  } else if (status === "rejected") {
    need(view.guest_id !== null);
    const r = exact(x.receipt, ["schema_version", "operation", "campaign_room_id", "campaign_key", "player_id", "idempotency_key", "request_hash", "origin", "reason", "closed_before_branch"]);
    need(r.schema_version === 1 && r.operation === "campaign_continue" && r.reason === "source_forked");
    need(r.campaign_room_id === campaignRoomId && same(r.campaign_key, body.campaign_key) && r.player_id === owner);
    need(r.idempotency_key === body.idempotency_key && r.request_hash === expectedHash && same(r.origin, from));
    number(r.closed_before_branch, 1, 31);
    need(r.closed_before_branch === from.source.branch + 1 && view.revision >= from.expected_revision && view.current_index >= from.from_index);
    const chapter = view.chapters[from.from_index];
    need(chapter.room_id === from.source.room_id);
    // This is an authenticated server assertion, not a substitute for the
    // transactional fork/seal fence required before a server may emit it.
    if (chapter.completion) need(chapter.completion.source_branch >= r.closed_before_branch && chapter.completion.source_revision > from.source.revision);
    if (view.transition?.origin.from_index === from.from_index) need(view.transition.origin.source.branch >= r.closed_before_branch && view.transition.origin.source.revision > from.source.revision);
  } else {
    const r = exact(x.receipt, ["schema_version", "operation", "campaign_room_id", "campaign_key", "player_id", "idempotency_key", "request_hash", "transition_id", "origin", "accepted_revision", "outcome", "next_index", "next_room_id"]);
    need(r.schema_version === 1 && r.operation === "campaign_continue");
    need(r.campaign_room_id === campaignRoomId && same(r.campaign_key, body.campaign_key) && r.player_id === owner);
    need(r.idempotency_key === body.idempotency_key && r.request_hash === expectedHash && same(r.origin, from));
    text(r.transition_id, HASH_PATTERN); number(r.accepted_revision, from.expected_revision + 1, view.revision);
    const chapter = view.chapters[from.from_index], completion = chapter.completion;
    need(chapter.room_id === from.source.room_id && completion && completion.source_revision === from.source.revision && completion.source_branch === from.source.branch && completion.checkpoint_hash === from.source.checkpoint_hash);
    need(completion.from_campaign_revision === from.expected_revision && completion.accepted_campaign_revision === r.accepted_revision && completion.transition_id === r.transition_id);
    if (r.outcome === "advanced") {
      need(from.from_index < view.chapters.length - 1 && r.next_index === from.from_index + 1);
      need(r.next_room_id === view.chapters[from.from_index + 1].room_id && r.next_room_id !== null);
    } else {
      need(r.outcome === "finished" && from.from_index === view.chapters.length - 1 && r.next_index === null && r.next_room_id === null);
      need((view.state === "complete" || view.state === "deleting") && view.chapters.every(row => row.completion !== null));
    }
  }
  return structuredClone(x) as CampaignContinueResult;
}
