class_name TurnPhotoStore
extends RefCounted
## App-private media journals. Atomic recoverable generations, no credentials.
## Owner separation permits deleting every local photo journal after account
## deletion. Call erase_owner only on an explicit account-data removal flow.
const Save = preload("res://services/local_save.gd")
const MAX_FILE := 384 * 1024
const MAX_VALUE := 256 * 1024
const MAX_TURNS := 128
var directory := "user://turn-photos"
var _stores: Dictionary = {}

func _init(root_path: String = "user://turn-photos") -> void:
	directory = root_path

func load_scope(scope: String) -> Dictionary:
	var path := _path(scope)
	if path == "":
		return {"ok": false, "error": "invalid_scope"}
	var exists := false
	for suffix: String in ["", ".tmp", ".backup"]:
		if not FileAccess.file_exists(path + suffix):
			continue
		exists = true
		var file := FileAccess.open(path + suffix, FileAccess.READ)
		if file == null or file.get_length() > MAX_FILE:
			return {"ok": false, "error": "unreadable_save"}
		var value: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if value is Dictionary and (value.get("version") != 1 or not _generation(value.get("generation")) or value.get("turn_photo_scope") != scope or not value.get("turn_photo_value") is Dictionary):
			return {"ok": false, "error": "unsupported_save"}
	var store := Save.new(path)
	store.load_data()
	if store.read_only or (exists and store.loaded_from == ""):
		return {"ok": false, "error": "unreadable_save"}
	_stores[scope] = store
	return {"ok": true, "found": exists, "value": store.data.get("turn_photo_value", {}).duplicate(true)}

func save_scope(scope: String, value: Dictionary) -> Dictionary:
	var path := _path(scope)
	if path == "" or JSON.stringify(value).to_utf8_buffer().size() > MAX_VALUE:
		return {"ok": false, "error": "invalid_save"}
	if not _stores.has(scope) and not load_scope(scope).get("ok", false):
		return {"ok": false, "error": "unreadable_save"}
	var folder := path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "error": "storage_unavailable"}
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".backup"):
		var names: Dictionary = {}
		for file: String in DirAccess.get_files_at(folder):
			var base := file.trim_suffix(".backup").trim_suffix(".tmp")
			if _filename(base):
				names[base] = true
		if names.size() >= MAX_TURNS:
			return {"ok": false, "error": "local_photo_history_full"}
	var store: RefCounted = _stores[scope]
	return {"ok": store.update_values({"turn_photo_scope": scope, "turn_photo_value": value.duplicate(true)})}

func erase_owner(owner: String) -> Dictionary:
	if not _matches(owner, "^[A-Za-z0-9_-]{22}$"):
		return {"ok": false, "error": "invalid_owner"}
	var folder := directory.path_join(owner.sha256_text())
	var all_removed := true
	if not DirAccess.dir_exists_absolute(folder):
		if FileAccess.file_exists(folder):
			return {"ok": false, "error": "storage_unavailable"}
		for scope: String in _stores.keys():
			if scope.begins_with("turn-photo-v1:" + owner + ":"):
				_stores.erase(scope)
		return {"ok": true}
	var listing := DirAccess.open(folder)
	if listing == null or listing.list_dir_begin() != OK:
		return {"ok": false, "error": "storage_unavailable"}
	# Enumerate only this deterministic owner directory; never follow a caller
	# supplied path or recursively remove an unrelated tree.
	var file := listing.get_next()
	while not file.is_empty():
		if listing.current_is_dir() or not _filename(file.trim_suffix(".backup").trim_suffix(".tmp")):
			all_removed = false
		elif DirAccess.remove_absolute(folder.path_join(file)) != OK:
			all_removed = false
		file = listing.get_next()
	listing.list_dir_end()
	for scope: String in _stores.keys():
		if scope.begins_with("turn-photo-v1:" + owner + ":"):
			_stores.erase(scope)
	return {"ok": all_removed}

func _path(scope: String) -> String:
	if not _matches(scope, "^turn-photo-v1:[A-Za-z0-9_-]{22}:[A-Za-z0-9_-]{22}:t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$"):
		return ""
	return directory.path_join(scope.split(":")[1].sha256_text()).path_join(scope.sha256_text() + ".json")

static func _matches(value: String, pattern: String) -> bool:
	var expression := RegEx.new()
	expression.compile(pattern)
	var found := expression.search(value)
	return found != null and found.get_string() == value

static func _filename(value: String) -> bool:
	return _matches(value, "^[a-f0-9]{64}\\.json$")

static func _generation(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 2147483647 and value == int(value)
