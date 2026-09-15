class_name PairReactionStore
extends RefCounted
## Optional preset journals only. Caller verifies controller schema/receipts.
## erase_owner is only for confirmed account-data deletion, never sign-out.
const Save = preload("res://services/local_save.gd")
const MAX_FILE := 32 * 1024
const MAX_VALUE := 16 * 1024
const MAX_PAIRS := 128
const MAX_FILES := MAX_PAIRS * 3
var directory := "user://pair-reactions"
var _stores: Dictionary = {}
var _retired_owners: Dictionary = {}

func _init(root_path: String = "user://pair-reactions") -> void:
	directory = root_path

func load_scope(scope: String) -> Dictionary:
	var path := _path(scope)
	if path.is_empty(): return {"ok": false, "error": "invalid_scope"}
	if _retired_owners.has(scope.split(":")[1]): return {"ok": false, "error": "owner_erased"}
	var exists := false
	for suffix: String in ["", ".tmp", ".backup"]:
		if not FileAccess.file_exists(path + suffix): continue
		exists = true
		var file := FileAccess.open(path + suffix, FileAccess.READ)
		if file == null or file.get_length() > MAX_FILE:
			return {"ok": false, "error": "unreadable_save"}
		var parser := JSON.new()
		var value: Variant = parser.data if parser.parse(file.get_as_text()) == OK else null
		file.close()
		# Corrupt/truncated JSON may use a complete generation. A readable but
		# unfamiliar generation must never be replaced by an older backup.
		if value is Dictionary and not _envelope(value, scope):
			return {"ok": false, "error": "unsupported_save"}
	var store := Save.new(path)
	store.load_data()
	if store.read_only or (exists and store.loaded_from.is_empty()):
		return {"ok": false, "error": "unreadable_save"}
	_stores[scope] = store
	return {"ok": true, "found": exists, "value": store.data.get("pair_reaction_value", {}).duplicate(true)}

func save_scope(scope: String, value: Dictionary) -> Dictionary:
	var path := _path(scope)
	if path.is_empty() or not _journal(value, scope): return {"ok": false, "error": "invalid_save"}
	# Re-read even with a cached instance so a readable future generation cannot
	# be overwritten by a stale controller after an interrupted app update.
	var loaded := load_scope(scope)
	if not loaded.get("ok", false): return loaded
	var folder := path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return {"ok": false, "error": "storage_unavailable"}
	var listing := _inventory(folder)
	if not listing.ok: return listing
	if not loaded.found and listing.count >= MAX_PAIRS: return {"ok": false, "error": "local_reaction_history_full"}
	var store: RefCounted = _stores[scope]
	if int(store.data.get("generation", 0)) >= 2147483647: return {"ok": false, "error": "unsupported_save"}
	var saved: bool = store.update_values({"pair_reaction_scope": scope, "pair_reaction_value": value.duplicate(true)})
	return {"ok": true} if saved else {"ok": false, "error": "storage_unavailable"}

func erase_owner(owner: String) -> Dictionary:
	if not _matches(owner, "^[A-Za-z0-9_-]{22}$"): return {"ok": false, "error": "invalid_owner"}
	# Retire this instance before any filesystem operation. A late old-owner
	# callback cannot recreate journals even if cleanup needs an explicit retry.
	_retired_owners[owner] = true
	for scope: String in _stores.keys():
		if scope.begins_with("pair-reaction-v1:" + owner + ":"): _stores.erase(scope)
	var folder := directory.path_join(owner.sha256_text())
	if not DirAccess.dir_exists_absolute(folder): return {"ok": not FileAccess.file_exists(folder)}
	var listing := _inventory(folder)
	if not listing.ok: return listing
	var removed := true
	for filename: String in listing.files:
		if DirAccess.remove_absolute(folder.path_join(filename)) != OK: removed = false
	return {"ok": true} if removed else {"ok": false, "error": "storage_unavailable"}

func _path(scope: String) -> String:
	if not _matches(scope, "^pair-reaction-v1:[A-Za-z0-9_-]{22}:[A-Za-z0-9_-]{22}:p(?:[0-9]|[12][0-9]|3[01])-[01]$"): return ""
	return directory.path_join(scope.split(":")[1].sha256_text()).path_join(scope.sha256_text() + ".json")

static func _inventory(folder: String) -> Dictionary:
	var listing := DirAccess.open(folder)
	if listing == null or listing.list_dir_begin() != OK: return {"ok": false, "error": "storage_unavailable"}
	var files: Array[String] = []
	var pairs: Dictionary = {}
	var name := listing.get_next()
	var valid := true
	while not name.is_empty():
		if listing.current_is_dir() or not _matches(name, "^[a-f0-9]{64}\\.json(?:\\.tmp|\\.backup)?$") or files.size() >= MAX_FILES:
			valid = false
			break
		files.append(name)
		pairs[name.trim_suffix(".tmp").trim_suffix(".backup")] = true
		if pairs.size() > MAX_PAIRS:
			valid = false
			break
		name = listing.get_next()
	listing.list_dir_end()
	return {"ok": true, "files": files, "count": pairs.size()} if valid else {"ok": false, "error": "unsupported_save"}

static func _envelope(value: Dictionary, scope: String) -> bool:
	if value.get("version") != 1 or not _generation(value.get("generation")) or value.get("pair_reaction_scope") != scope or not value.get("pair_reaction_value") is Dictionary or not _journal(value.pair_reaction_value, scope): return false
	for key: Variant in value:
		if key not in ["version", "generation", "settings", "attempts", "completed", "replays", "room", "pair_reaction_scope", "pair_reaction_value"]: return false
	if value.has("settings") and not Save.default_settings_envelope_valid(value.settings): return false
	for key: String in ["attempts", "completed", "replays", "room"]:
		if value.has(key) and (not value[key] is Dictionary or not value[key].is_empty()): return false
	return true

static func _journal(value: Dictionary, scope: String) -> bool:
	# The controller still verifies receipts, pending hashes and state semantics.
	# This shallow contract prevents a stale cached writer replacing a future
	# journal or another owner/pair even when its outer LocalSave version is1.
	if value.size() != 6 or value.get("schema_version") != 1 or value.get("owner") != scope.split(":")[1]: return false
	for key: String in ["target", "state", "pending", "last_receipt"]:
		if not value.get(key) is Dictionary: return false
	var target: Dictionary = value.target
	if target.size() != 6 or target.get("room_id") != scope.split(":")[2] or target.get("pair_id") != scope.split(":")[3]: return false
	for key: String in ["a_hash", "b_hash"]:
		if not target.get(key) is String or not _matches(target[key], "^[a-f0-9]{64}$"): return false
	for key: String in ["host_id", "guest_id"]:
		if not target.get(key) is String or not _matches(target[key], "^[A-Za-z0-9_-]{22}$"): return false
	if target.host_id == target.guest_id or value.owner not in [target.host_id, target.guest_id]: return false
	return _bounded(value)

static func _bounded(value: Dictionary) -> bool:
	var pending: Array = [{"value": value, "depth": 0}]
	var count := 0
	while not pending.is_empty():
		var item: Dictionary = pending.pop_back()
		count += 1
		if count > 2048 or item.depth > 12: return false
		var next: Variant = item.value
		if next is String:
			if next.length() > MAX_VALUE: return false
		elif next is Dictionary:
			if next.size() > 128: return false
			for key: Variant in next:
				if not key is String or key.length() > 128: return false
				pending.append({"value": next[key], "depth": item.depth + 1})
		elif next is Array:
			if next.size() > 128: return false
			for child: Variant in next: pending.append({"value": child, "depth": item.depth + 1})
		elif next is float:
			if not is_finite(next): return false
		elif next != null and not (next is int or next is bool): return false
	return JSON.stringify(value).to_utf8_buffer().size() <= MAX_VALUE

static func _matches(value: String, pattern: String) -> bool:
	var expression := RegEx.new()
	expression.compile(pattern)
	var found := expression.search(value)
	return found != null and found.get_string() == value

static func _generation(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 2147483647 and value == int(value)
