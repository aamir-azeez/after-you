extends RefCounted
## Separate bounded files using the existing recoverable LocalSave generations.
const Save = preload("res://services/local_save.gd")
const MAX_BYTES := 4194304
const CAMPAIGN_MAX_BYTES := 65536
const CAMPAIGN_VALUE_BYTES := 49152
const TERMINAL_ADMISSION_MAX_BYTES := 262144
const TERMINAL_ADMISSION_VALUE_BYTES := 196608
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
		if file == null or file.get_length() > _file_limit(scope):
			return {"ok": false, "error": "unreadable_save"}
		var parser := JSON.new()
		var raw: Variant = parser.data if parser.parse(file.get_as_text()) == OK else null
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
	if not _valid_scope(scope) or JSON.stringify(value).to_utf8_buffer().size() > _value_limit(scope):
		return {"ok": false, "error": "invalid_save"}
	if not _stores.has(scope) and not load_scope(scope).get("ok", false):
		return {"ok": false, "error": "unreadable_save"}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "storage_unavailable"}
	var storage: RefCounted = _stores[scope]
	return {"ok": storage.update_values({"relay_online_scope": scope, "relay_online_value": value.duplicate(true)})}

static func _valid_scope(scope: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^relay-((room-v2|campaign-v1|redo-(legacy|relay)-v1):[A-Za-z0-9_-]{22}:[A-Za-z0-9_-]{22}|(lobby-v2|campaign-lobby-v1|campaign-terminal-v1|campaign-admission-terminal-v1):[A-Za-z0-9_-]{22})$")
	return scope.length() <= 80 and pattern.search(scope) != null

static func _file_limit(scope: String) -> int:
	if scope.begins_with("relay-campaign-admission-terminal-v1:"): return TERMINAL_ADMISSION_MAX_BYTES
	return CAMPAIGN_MAX_BYTES if scope.begins_with("relay-campaign-") or scope.begins_with("relay-redo-") else MAX_BYTES

static func _value_limit(scope: String) -> int:
	if scope.begins_with("relay-campaign-admission-terminal-v1:"): return TERMINAL_ADMISSION_VALUE_BYTES
	# Campaign journals hold small control references, never recording proofs.
	if scope.begins_with("relay-redo-"): return 8192
	return CAMPAIGN_VALUE_BYTES if scope.begins_with("relay-campaign-") else 3145728
