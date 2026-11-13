extends RefCounted
## A top 10 run's replay as GET /v1/leaderboards/<board>/replay/<entry> sends it
## (backend src/leaderboards/replays.ts): what its board row shows, and the run's
## final checkpoint in the shared blob format (services/blob_codec.gd), base64 in
## `body`. Decoded, hash-checked and unwound into the shared replay viewer's parts
## (services/checkpoint_pairs.gd), each part naming only the chapter: the answer
## carries no player id or room id, and the viewer plays it in its leaderboard
## mode. Pure, so it runs on a worker (services/worker_reaper.gd).
const BlobCodec = preload("res://services/blob_codec.gd")
const CheckpointPairs = preload("res://services/checkpoint_pairs.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomStages = preload("res://services/room_stages.gd")
const Typed = preload("res://services/typed_values.gd")
## The server keeps no encoded replay above this (backend rules.ts MAX_REPLAY_BYTES).
const MAX_BODY_BYTES := 1536 * 1024
## Canonical checkpoint bytes accepted (the history store's own limit).
const MAX_CANONICAL_BYTES := 4 * 1024 * 1024
const ANSWER_KEYS := ["schema_version", "board", "entry_id", "rank", "ticks", "finished_on", "names", "gold_leaf", "digest", "byte_length", "body"]

## The viewer's parts for `answer`, or [] unless it is exactly the replay the row
## named (`entry_id` and `replay_hash` on `board`) and a whole run of `chapter_key`.
static func parts(answer: Variant, board: String, entry_id: String, replay_hash: String, chapter_key: String) -> Array:
	var kept := blob(answer, board, entry_id, replay_hash)
	return [] if kept.is_empty() else checkpoint_parts(kept.body, kept.byte_length, replay_hash, chapter_key)

## The answer's replay still encoded, {digest, byte_length, body} as services/duel_their_run.gd
## keeps a run, or {} unless it is exactly the replay the row named. Nothing is decoded.
static func blob(answer: Variant, board: String, entry_id: String, replay_hash: String) -> Dictionary:
	# Fields a later server adds are ignored, as a board's are (leaderboard_client.gd valid_view).
	if not answer is Dictionary or ANSWER_KEYS.any(func(key: String) -> bool: return not answer.has(key)): return {}
	if not Typed.equal(answer.schema_version, 1) or not Typed.equal(answer.board, board) or not Typed.equal(answer.entry_id, entry_id) or not Typed.equal(answer.digest, replay_hash): return {}
	if not Typed.whole_number(answer.byte_length) or not answer.body is String: return {}
	return {"digest": replay_hash, "byte_length": int(answer.byte_length), "body": answer.body}

## The viewer's parts for a whole run of `chapter_key` whose final checkpoint is
## `body` (the shared blob format, base64) of `byte_length` canonical bytes
## hashing to `digest`, or [] when it is not exactly that. A duel's other pair's
## run (services/duel_their_run.gd) is read here too.
static func checkpoint_parts(body: Variant, byte_length: Variant, digest: String, chapter_key: String) -> Array:
	if not Typed.whole_number(byte_length) or not body is String or body.length() > (MAX_BODY_BYTES + 2) / 3 * 4: return []
	var bytes := BlobCodec.verified(Marshalls.base64_to_raw(body), int(byte_length), digest, MAX_CANONICAL_BYTES)
	if bytes.is_empty(): return []
	var checkpoint: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not checkpoint is Dictionary or Registry.resolve(checkpoint) != chapter_key: return []
	var pairs := CheckpointPairs.pairs(chapter_key, checkpoint, 0)
	if pairs.size() != RoomStages.count(Registry.definition(chapter_key)): return []
	var result: Array = []
	for pair: Dictionary in pairs: result.append({"schema_version": 1, "room": {"family": "chapter", "chapter_key": chapter_key}, "pair": pair})
	return result
