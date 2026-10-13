extends "res://core/physical/two_pair_proof.gd"
## two_pair_proof for sleeping-lighthouse@2 with a verified-checkpoint memo.
## A six-stage checkpoint nests six proofs and every check replays the whole
## prefix. Once a checkpoint's exact canonical bytes have verified, any later
## checkpoint that nests it costs one pair. The shared proof stays untouched.
## Only positive results are kept. Keys are digests of the complete checkpoint
## (proof included), never a caller's checkpoint_hash.
const Catalog = preload("res://core/lighthouse/room_catalog.gd")
## Bump when anything a verification depends on changes (engine, facade,
## catalog or this proof); a persisted index with another stamp is ignored.
const VERIFIER_VERSION := 1
const MEMO_LIMIT := 512
const INDEX_MAX_BYTES := 131072
const INDEX_SCHEMA := 1

static var _memo: Dictionary = {}
static var _memo_mutex := Mutex.new()
## Pair replays run by this proof since the last clear; for tests and timing.
static var pair_replays := 0

func _init(factory: Script) -> void:
	super(Catalog, factory, Catalog.RULES, Catalog.SCHEMA)

func _verify_checkpoint(definition: Dictionary, checkpoint: Dictionary, depth: int) -> Dictionary:
	# Reached only through verify_checkpoint, which has already required the
	# exact bundled definition, so the checkpoint bytes alone name the result.
	var key := Canonical.digest(checkpoint)
	if _known(key): return {"valid": true, "error": ""}
	var result: Dictionary = super._verify_checkpoint(definition, checkpoint, depth)
	if result.valid: _remember(key)
	return result

func _verify_pair(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	_memo_mutex.lock()
	pair_replays += 1
	_memo_mutex.unlock()
	return super._verify_pair(definition, previous, first, second)

static func _known(key: String) -> bool:
	_memo_mutex.lock()
	var found := _memo.has(key)
	if found:
		_memo.erase(key)
		_memo[key] = true
	_memo_mutex.unlock()
	return found

static func _remember(key: String) -> void:
	_memo_mutex.lock()
	_memo.erase(key)
	_memo[key] = true
	while _memo.size() > MEMO_LIMIT: _memo.erase(_memo.keys()[0])
	_memo_mutex.unlock()

static func clear_memo() -> void:
	_memo_mutex.lock()
	_memo.clear()
	pair_replays = 0
	_memo_mutex.unlock()

static func memo_size() -> int:
	_memo_mutex.lock()
	var size := _memo.size()
	_memo_mutex.unlock()
	return size

## Rules, verifier, chapter hash and Godot version: another of any of them
## never inherits a persisted result.
static func stamp() -> String:
	return "|".join(PackedStringArray(["sleeping-lighthouse@2", str(Catalog.RULES), str(VERIFIER_VERSION), Canonical.digest(Catalog.definition()),
		str(Engine.get_version_info().get("string", ""))]))

## The memo as plain data, oldest first, for a caller to persist.
static func export_memo() -> Dictionary:
	_memo_mutex.lock()
	var keys: Array = _memo.keys()
	_memo_mutex.unlock()
	return {"schema_version": INDEX_SCHEMA, "stamp": stamp(), "keys": keys}

## Trusts exported keys only under the current stamp. Anything malformed is
## ignored whole. Returns how many keys were added.
static func import_memo(value: Variant) -> int:
	if not value is Dictionary or value.size() != 3 or value.get("schema_version") != INDEX_SCHEMA or value.get("stamp") != stamp(): return 0
	if not value.get("keys") is Array or value.keys.size() > MEMO_LIMIT: return 0
	for key: Variant in value.keys:
		if not (key is String and key.length() == 64 and key.is_valid_hex_number(false)): return 0
	var added := 0
	_memo_mutex.lock()
	for key: String in value.keys:
		if not _memo.has(key): added += 1
		_memo.erase(key)
		_memo[key] = true
	while _memo.size() > MEMO_LIMIT: _memo.erase(_memo.keys()[0])
	_memo_mutex.unlock()
	return added

static func load_index(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path): return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return 0
	if file.get_length() < 1 or file.get_length() > INDEX_MAX_BYTES:
		file.close()
		return 0
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	return import_memo(json.data) if json.parse(text) == OK else 0

## Writes through a verified temporary file; a failed write keeps the old index.
static func save_index(path: String) -> bool:
	if path.is_empty(): return false
	var text := JSON.stringify(export_memo())
	if text.to_utf8_buffer().size() > INDEX_MAX_BYTES: return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	if not okay or FileAccess.get_file_as_string(temporary) != text: return false
	var target := ProjectSettings.globalize_path(path)
	var backup := target + ".backup"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".backup"): DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(target, backup) != OK: return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), target) != OK:
		if FileAccess.file_exists(path + ".backup"): DirAccess.rename_absolute(backup, target)
		return false
	if FileAccess.file_exists(path + ".backup"): DirAccess.remove_absolute(backup)
	return true
