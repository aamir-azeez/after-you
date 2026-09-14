extends RefCounted
## Separate bounded files using the existing recoverable LocalSave generations.
const Save = preload("res://services/local_save.gd")
const MAX_BYTES := 4194304
var directory := "user://relay-online"
var _stores: Dictionary = {}

func _init(root_path: String = "user://relay-online") -> void:
	directory = root_path

func load_scope(scope: String) -> Dictionary:
	if not _valid_scope(scope):
		return {"ok": false, "error": "invalid_scope"}
	var path := directory.path_join(scope.sha256_text() + ".json")
	var exists := false
	for suffix: String in ["", ".tmp", ".backup"]:
		var candidate := path + suffix
		if not FileAccess.file_exists(candidate):
			continue
		exists = true
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES:
			return {"ok": false, "error": "unreadable_save"}
		var raw: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		# A truncated generation may be recovered by LocalSave. A readable
		# unfamiliar generation must not be overwritten by an older backup.
		if raw is Dictionary and (raw.get("version") != 1 or not (raw.get("generation") is int or raw.get("generation") is float) or float(raw.get("generation", -1)) < 0 or float(raw.get("generation", -1)) != floor(float(raw.get("generation", -1))) or raw.get("relay_online_scope") != scope or not raw.get("relay_online_value") is Dictionary):
			return {"ok": false, "error": "unsupported_save"}
	var storage := Save.new(path)
	storage.load_data()
	if storage.read_only or (exists and storage.loaded_from.is_empty()):
		return {"ok": false, "error": "unreadable_save"}
	_stores[scope] = storage
	return {"ok": true, "found": exists, "value": storage.data.get("relay_online_value", {}).duplicate(true)}

func save_scope(scope: String, value: Dictionary) -> Dictionary:
	if not _valid_scope(scope) or JSON.stringify(value).to_utf8_buffer().size() > 3145728:
		return {"ok": false, "error": "invalid_save"}
	if not _stores.has(scope) and not load_scope(scope).get("ok", false):
		return {"ok": false, "error": "unreadable_save"}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "storage_unavailable"}
	var storage: RefCounted = _stores[scope]
	return {"ok": storage.update_values({"relay_online_scope": scope, "relay_online_value": value.duplicate(true)})}

static func _valid_scope(scope: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^relay-(room-v2:[A-Za-z0-9_-]{22}:[A-Za-z0-9_-]{22}|lobby-v2:[A-Za-z0-9_-]{22})$")
	return scope.length() <= 80 and pattern.search(scope) != null
