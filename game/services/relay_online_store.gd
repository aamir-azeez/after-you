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
var _mutex := Mutex.new()

func _init(root_path: String = "user://relay-online") -> void:
	directory = root_path

func capture_scope(scope: String) -> Dictionary:
	_mutex.lock()
	var result := _capture_scope_locked(scope)
	_mutex.unlock()
	return result

func _capture_scope_locked(scope: String) -> Dictionary:
	# Capture bounded immutable bytes for a read-only worker. Never install a
	# LocalSave instance or repair generations while inspecting replay history.
	if not _valid_scope(scope): return {"ok": false, "error": "invalid_scope"}
	var path := directory.path_join(scope.sha256_text() + ".json")
	var raw: Array = []
	for suffix: String in ["", ".tmp", ".backup"]:
		if not FileAccess.file_exists(path + suffix): continue
		var file := FileAccess.open(path + suffix, FileAccess.READ)
		if file == null: return {"ok": false, "error": "unreadable_save"}
		var size := file.get_length()
		if size > _file_limit(scope):
			file.close()
			return {"ok": false, "error": "unreadable_save"}
		var bytes := file.get_buffer(size)
		file.close()
		if bytes.size() != size: return {"ok": false, "error": "unreadable_save"}
		raw.append(bytes)
	return {"ok": true, "found": not raw.is_empty(), "scope": scope, "raw": raw}

static func decode_scope(snapshot: Dictionary) -> Dictionary:
	# Match load_scope's recovery and future-envelope rules without filesystem
	# access or shared mutable store state. Input is a frozen capture_scope result.
	var scope := str(snapshot.get("scope", ""))
	if not snapshot.get("ok", false) or not _valid_scope(scope) or not snapshot.get("raw") is Array or snapshot.raw.size() > 3:
		return {"ok": false, "error": "invalid_scope"}
	var selected: Dictionary = {}
	var best_generation := -1
	for raw: Variant in snapshot.raw:
		if not raw is PackedByteArray or raw.size() > _file_limit(scope): return {"ok": false, "error": "unreadable_save"}
		var parser := JSON.new()
		if parser.parse(raw.get_string_from_utf8()) != OK: continue
		var value: Variant = parser.data
		if value is Dictionary and (value.get("version") != 1 or not (value.get("generation") is int or value.get("generation") is float) or float(value.get("generation", -1)) < 0 or float(value.get("generation", -1)) != floor(float(value.get("generation", -1))) or value.get("relay_online_scope") != scope or not value.get("relay_online_value") is Dictionary):
			return {"ok": false, "error": "unsupported_save"}
		if not Save._valid(value): continue
		var generation := int(value.get("generation", 0))
		if generation > best_generation:
			best_generation = generation
			selected = value.relay_online_value
	if not snapshot.raw.is_empty() and best_generation < 0: return {"ok": false, "error": "unreadable_save"}
	return {"ok": true, "found": not snapshot.raw.is_empty(), "value": selected}

func load_scope(scope: String) -> Dictionary:
	_mutex.lock()
	var result := _load_scope_locked(scope)
	_mutex.unlock()
	return result

func _load_scope_locked(scope: String) -> Dictionary:
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
	# A periodic room-draft writer may call this off the main thread. Reads,
	# writes and generation caches share one transaction lock per store.
	_mutex.lock()
	var result := _save_scope_locked(scope, value)
	_mutex.unlock()
	return result

func _save_scope_locked(scope: String, value: Dictionary) -> Dictionary:
	if not _valid_scope(scope) or JSON.stringify(value).to_utf8_buffer().size() > _value_limit(scope):
		return {"ok": false, "error": "invalid_save"}
	if not _stores.has(scope) and not _load_scope_locked(scope).get("ok", false):
		return {"ok": false, "error": "unreadable_save"}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "storage_unavailable"}
	var storage: RefCounted = _stores[scope]
	return {"ok": storage.update_values({"relay_online_scope": scope, "relay_online_value": value.duplicate(true)})}

static func _valid_scope(scope: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^relay-((room-v2|campaign-v1|campaign-redo-v1|redo-(legacy|relay)-v1):[A-Za-z0-9_-]{22}:[A-Za-z0-9_-]{22}|(lobby-v2|campaign-lobby-v1|campaign-terminal-v1|campaign-admission-terminal-v1):[A-Za-z0-9_-]{22})$")
	return scope.length() <= 80 and pattern.search(scope) != null

static func _file_limit(scope: String) -> int:
	if scope.begins_with("relay-campaign-admission-terminal-v1:"): return TERMINAL_ADMISSION_MAX_BYTES
	return CAMPAIGN_MAX_BYTES if scope.begins_with("relay-campaign-") or scope.begins_with("relay-redo-") else MAX_BYTES

static func _value_limit(scope: String) -> int:
	if scope.begins_with("relay-campaign-admission-terminal-v1:"): return TERMINAL_ADMISSION_VALUE_BYTES
	# Campaign journals hold small control references, never recording proofs.
	if scope.begins_with("relay-redo-") or scope.begins_with("relay-campaign-redo-"): return 8192
	return CAMPAIGN_VALUE_BYTES if scope.begins_with("relay-campaign-") else 3145728
