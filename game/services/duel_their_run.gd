extends RefCounted
## The other pair's run after a friend duel, as GET /v1/duels/<board>/<duel>/their-run
## sends it (backend duels/their-run.ts): the run's final checkpoint in the shared
## blob format (services/blob_codec.gd), base64 in `body`, with no player id or
## room id. The phone keeps its own copy here once it has it, then tells the
## server, which lets its copy go once both players of the other pair have one.
##
## Kept per account under user://duel_runs/<owner>/<duel_id>.json, at most
## MAX_KEPT (the oldest go first), as {digest, byte_length, body, acked}: the bytes
## stay encoded and hash-checked, and are decoded only to play. Pure apart from
## those files, so the parse runs on a worker (services/worker_reaper.gd).
const LeaderboardReplay = preload("res://services/leaderboard_replay.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const ROOT := "user://duel_runs"
const MAX_KEPT := 24
const ANSWER_KEYS := ["schema_version", "duel_id", "board", "digest", "byte_length", "body"]
const DIGEST := "^[a-f0-9]{64}$"
const DUEL_ID := "^[a-f0-9]{32}$"
const OWNER := "^[A-Za-z0-9_-]{22}$"

## {digest, byte_length, body} of the answer, or {} unless it is exactly duel `duel_id` on `board`.
static func valid(answer: Variant, duel_id: String, board: String) -> Dictionary:
	if not answer is Dictionary or ANSWER_KEYS.any(func(key: String) -> bool: return not answer.has(key)): return {}
	if not Typed.equal(answer.schema_version, 1) or not Typed.equal(answer.duel_id, duel_id) or not Typed.equal(answer.board, board): return {}
	if not answer.digest is String or not _matches(answer.digest, DIGEST) or not Typed.whole_number(answer.byte_length) or not answer.body is String: return {}
	return {"digest": answer.digest, "byte_length": int(answer.byte_length), "body": answer.body}

## The viewer's parts for a kept run of `chapter_key`, or [] when it does not decode to one.
static func parts(kept: Dictionary, chapter_key: String) -> Array:
	return LeaderboardReplay.checkpoint_parts(kept.get("body"), kept.get("byte_length"), str(kept.get("digest", "")), chapter_key)

## The run kept for `duel_id` on this phone for `owner`, or {}.
static func kept_run(owner: String, duel_id: String) -> Dictionary:
	if not _matches(duel_id, DUEL_ID) or not _matches(owner, OWNER): return {}
	var text := AtomicFile.read_text(_path(owner, duel_id))
	var value: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not value is Dictionary or not value.get("digest") is String or not _matches(value.digest, DIGEST) or not Typed.whole_number(value.get("byte_length")) or not value.get("body") is String: return {}
	return {"digest": value.digest, "byte_length": int(value.byte_length), "body": value.body, "acked": value.get("acked") == true}

## Keeps `kept` for `duel_id`; true once it is on disk. The oldest past MAX_KEPT go.
static func keep(owner: String, duel_id: String, kept: Dictionary) -> bool:
	if not _matches(duel_id, DUEL_ID) or not _matches(owner, OWNER): return false
	var folder := ROOT.path_join(owner)
	DirAccess.make_dir_recursive_absolute(folder)
	if not AtomicFile.write_text(_path(owner, duel_id), JSON.stringify({"digest": kept.digest, "byte_length": kept.byte_length, "body": kept.body, "acked": kept.get("acked") == true})): return false
	_prune(folder)
	return true

## Drops the run kept for `duel_id` (one that no longer decodes, so the next tap fetches it again).
static func forget(owner: String, duel_id: String) -> void:
	if _matches(duel_id, DUEL_ID) and _matches(owner, OWNER): AtomicFile.remove(_path(owner, duel_id))

## Account erasure (services/deleted_identity_cache_cleanup.gd): every run kept for `owner`, and their folder. True once gone.
static func erase_owner(owner: String, root: String = ROOT) -> bool:
	if not _matches(owner, OWNER): return false
	var folder := root.path_join(owner)
	if not DirAccess.dir_exists_absolute(folder): return true
	for file: String in DirAccess.get_files_at(folder):
		if DirAccess.remove_absolute(folder.path_join(file)) != OK: return false
	return DirAccess.remove_absolute(folder) == OK

static func _prune(folder: String) -> void:
	var files: Array = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".json"): files.append([FileAccess.get_modified_time(folder.path_join(file)), file])
	files.sort()
	while files.size() > MAX_KEPT:
		AtomicFile.remove(folder.path_join(files.pop_front()[1]))

static func _path(owner: String, duel_id: String) -> String:
	return ROOT.path_join(owner).path_join(duel_id + ".json")

static func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.create_from_string(pattern)
	return regex.search(value) != null
