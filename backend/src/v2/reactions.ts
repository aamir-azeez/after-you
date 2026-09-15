import { ApiError, HASH_PATTERN, IDEMPOTENCY_PATTERN, canonicalJson, digest, equalHash, fail, integer, object, ok, text, type Outcome } from "../protocol";
import { exact } from "./protocol";
import { initializePairReactions } from "./storage-schema";

export const REACTION_PAIR_PATTERN = /^p(?:[0-9]|[12][0-9]|3[01])-[01]$/;
export const MAX_PAIR_REACTIONS = 128;
export const MAX_REACTION_OPERATIONS = 256;
export type PresetReaction = "love" | "sparkles" | "again";
export function isPreset(value: unknown): value is PresetReaction { return value === "love" || value === "sparkles" || value === "again"; }
type Members = { room_id: string; host_id: string; guest_id: string | null };
type PairHashes = { a_hash: string; b_hash: string };
export type PairReaction = PairHashes & { schema_version: 1; pair_id: string; player_id: string; reaction_revision: number; reaction: PresetReaction };
export type PairReactions = PairHashes & { schema_version: 1; room_id: string; pair_id: string; reactions: PairReaction[] };
export type ReactionReceipt = PairReaction & { room_id: string; idempotency_key: string; request_hash: string };
export type ReactionMutation = { receipt: ReactionReceipt; state: PairReactions };
type Input = PairHashes & { pair_id: string; key: string; expected: number; reaction: PresetReaction; hash: string };

function member(state: Members | null, player: string): state is Members { return !!state && (state.host_id === player || state.guest_id === player); }
function installed(storage: DurableObjectStorage): boolean { return storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata WHERE id=1").one().schema_version === 4; }
function pairHashes(storage: DurableObjectStorage, pairId: string): PairHashes | null {
  const row = storage.sql.exec<{ data: string }>("SELECT data FROM pairs WHERE pair_id=?", pairId).toArray()[0];
  if (!row) return null;
  const pair = JSON.parse(row.data);
  return { a_hash: pair.a.recording_hash, b_hash: pair.b.recording_hash };
}
function view(storage: DurableObjectStorage, state: Members, pairId: string, hashes: PairHashes): PairReactions {
  const rows = installed(storage) ? storage.sql.exec<{ data: string }>("SELECT data FROM pair_reactions WHERE json_extract(data,'$.pair_id')=? LIMIT 3", pairId).toArray() : [];
  if (rows.length > 2) throw new Error("reaction_state_unavailable");
  const reactions = rows.map(row => JSON.parse(row.data) as PairReaction);
  // Deterministic participant order, without exposing identity names or arbitrary text.
  reactions.sort((a, b) => (a.player_id === state.host_id ? 0 : 1) - (b.player_id === state.host_id ? 0 : 1));
  return { schema_version: 1, room_id: state.room_id, pair_id: pairId, ...hashes, reactions };
}
export function getPairReactions(storage: DurableObjectStorage, state: Members | null, player: string, pairId: string): Outcome<PairReactions> {
  if (!member(state, player)) return fail(404, "room_not_found");
  if (!REACTION_PAIR_PATTERN.test(pairId)) return fail(400, "invalid_reaction_pair");
  const hashes = pairHashes(storage, pairId);
  return hashes ? ok(view(storage, state, pairId, hashes)) : fail(404, "pair_not_found");
}
export function getReactionOperation(storage: DurableObjectStorage, state: Members | null, player: string, key: string): Outcome<ReactionMutation> {
  if (!member(state, player)) return fail(404, "room_not_found");
  if (!IDEMPOTENCY_PATTERN.test(key)) return fail(400, "invalid_request");
  const row = installed(storage) ? storage.sql.exec<{ receipt: string }>("SELECT receipt FROM reaction_operations WHERE request_key=?", player + ":" + key).toArray()[0] : null;
  if (!row) return fail(404, "operation_not_found");
  const receipt = JSON.parse(row.receipt) as ReactionReceipt, hashes = pairHashes(storage, receipt.pair_id);
  if (!hashes) throw new Error("reaction_state_unavailable");
  return ok({ receipt, state: view(storage, state, receipt.pair_id, hashes) });
}
export async function parseReaction(pairId: string, value: unknown): Promise<Input> {
  text(pairId, REACTION_PAIR_PATTERN, "invalid_reaction_pair");
  const input = object(value); exact(input, ["idempotency_key", "a_hash", "b_hash", "expected_reaction_revision", "reaction"]);
  const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN), a_hash = text(input.a_hash, HASH_PATTERN), b_hash = text(input.b_hash, HASH_PATTERN);
  const expected = integer(input.expected_reaction_revision, 0, MAX_REACTION_OPERATIONS);
  if (!isPreset(input.reaction)) throw new ApiError(400, "invalid_reaction");
  return { pair_id: pairId, key, a_hash, b_hash, expected, reaction: input.reaction,
    hash: await digest(canonicalJson({ operation: "pair_reaction", pair_id: pairId, ...input })) };
}
/** Called inside the owning room's synchronous transaction after all hash awaits. */
export function mutateReaction(storage: DurableObjectStorage, state: Members | null, player: string, input: Input): Outcome<ReactionMutation> {
  if (!member(state, player)) return fail(404, "room_not_found");
  const hashes = pairHashes(storage, input.pair_id);
  if (!hashes) return fail(404, "pair_not_found");
  if (hashes.a_hash !== input.a_hash || hashes.b_hash !== input.b_hash) return fail(409, "reaction_pair_mismatch");
  const requestKey = player + ":" + input.key, reactionKey = input.pair_id + ":" + player;
  const previous = installed(storage) ? storage.sql.exec<{ request_hash: string; receipt: string }>("SELECT request_hash,receipt FROM reaction_operations WHERE request_key=?", requestKey).toArray()[0] : null;
  if (previous) return equalHash(previous.request_hash, input.hash) ? ok({ receipt: JSON.parse(previous.receipt) as ReactionReceipt, state: view(storage, state, input.pair_id, hashes) }) : fail(409, "idempotency_key_reused");
  const old = installed(storage) ? storage.sql.exec<{ data: string }>("SELECT data FROM pair_reactions WHERE reaction_key=?", reactionKey).toArray()[0] : null;
  const revision = old ? Number(JSON.parse(old.data).reaction_revision) : 0;
  if (revision !== input.expected) return fail(409, "stale_reaction_revision");
  if (installed(storage)) {
    if (storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM reaction_operations").one().n >= MAX_REACTION_OPERATIONS) return fail(409, "reaction_history_full");
    if (!old && storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM pair_reactions").one().n >= MAX_PAIR_REACTIONS) return fail(409, "reaction_room_full");
  }
  // Lazy metadata migration: ordinary gameplay-only rooms retain schema3 and
  // their exact old archive shape until a first valid reaction is persisted.
  initializePairReactions(storage);
  const reaction: PairReaction = { schema_version: 1, pair_id: input.pair_id, player_id: player, ...hashes, reaction_revision: revision + 1, reaction: input.reaction };
  const receipt: ReactionReceipt = { ...reaction, room_id: state.room_id, idempotency_key: input.key, request_hash: input.hash };
  storage.sql.exec("INSERT OR REPLACE INTO pair_reactions VALUES (?,?)", reactionKey, JSON.stringify(reaction));
  storage.sql.exec("INSERT INTO reaction_operations VALUES (?,?,?)", requestKey, input.hash, JSON.stringify(receipt));
  return ok({ receipt, state: view(storage, state, input.pair_id, hashes) });
}
export function clearPairReactions(storage: DurableObjectStorage): void {
  if (!installed(storage)) return;
  storage.sql.exec("DELETE FROM pair_reactions"); storage.sql.exec("DELETE FROM reaction_operations");
}
