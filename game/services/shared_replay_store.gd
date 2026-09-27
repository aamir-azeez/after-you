extends RefCounted
## Read-only memories have separate recoverable files, never gameplay journals.
const Save = preload("res://services/local_save.gd")
const MAX_BYTES := 16777216
var directory := "user://shared-replays"

func _init(root_path: String = "user://shared-replays") -> void: directory = root_path

func capture_scope(scope: String) -> Dictionary:
	# The home backfill captures bytes once. Decoding and recovery selection run
	# in its worker; this path never calls LocalSave or repairs a cache file.
	if not _scope_valid(scope): return {"ok": false}
	var path := directory.path_join(scope.sha256_text() + ".json")
	var raw: Array = []
	for suffix: String in ["", ".tmp", ".backup"]:
		if not FileAccess.file_exists(path + suffix): continue
		var file := FileAccess.open(path + suffix, FileAccess.READ)
		if file == null: return {"ok": false}
		var size := file.get_length()
		if size > MAX_BYTES:
			file.close()
			return {"ok": false}
		var bytes := file.get_buffer(size)
		file.close()
		if bytes.size() != size: return {"ok": false}
		raw.append(bytes)
	return {"ok": true, "found": not raw.is_empty(), "scope": scope, "raw": raw}

static func decode_scope(snapshot: Dictionary) -> Dictionary:
	# Worker-only, bounded immutable input. Preserve the ordinary store's rule:
	# a readable foreign/future envelope holds the whole scope; malformed bytes
	# may fall back to a valid generation. No filesystem or shared-instance use.
	if not snapshot.get("ok", false) or not _scope_valid(str(snapshot.get("scope", ""))) or not snapshot.get("raw") is Array or snapshot.raw.size() > 3: return {"ok": false}
	var selected: Dictionary = {}
	var best_generation := -1
	for raw: Variant in snapshot.raw:
		if not raw is PackedByteArray or raw.size() > MAX_BYTES: return {"ok": false}
		var parser := JSON.new()
		if parser.parse(raw.get_string_from_utf8()) != OK: continue
		var value: Variant = parser.data
		if value is Dictionary and (value.get("version") != 1 or value.get("shared_replay_scope") != snapshot.scope or not value.get("shared_replay_value") is Dictionary or value.shared_replay_value.get("schema_version") != 1): return {"ok": false}
		if not Save._valid(value): continue
		var generation: Variant = value.get("generation", 0)
		if not (generation is int or generation is float) or not is_finite(float(generation)) or generation < 0 or floor(float(generation)) != float(generation): return {"ok": false}
		if int(generation) > best_generation:
			best_generation = int(generation)
			selected = value.shared_replay_value
	if not snapshot.raw.is_empty() and best_generation < 0: return {"ok": false}
	return {"ok": true, "found": not snapshot.raw.is_empty(), "value": selected}

func load_scope(scope: String) -> Dictionary:
	if not _scope_valid(scope): return {"ok": false}
	var path := directory.path_join(scope.sha256_text() + ".json")
	var found := false
	for suffix: String in ["", ".backup", ".tmp"]:
		if not FileAccess.file_exists(path + suffix): continue
		found = true
		var file := FileAccess.open(path + suffix, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES: return {"ok": false}
		var value: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if value is Dictionary and (value.get("version") != 1 or value.get("shared_replay_scope") != scope or not value.get("shared_replay_value") is Dictionary or value.shared_replay_value.get("schema_version") != 1):
			return {"ok": false}
	var save := Save.new(path)
	save.load_data()
	if save.read_only or (found and save.loaded_from.is_empty()): return {"ok": false}
	return {"ok": true, "found": found, "value": save.data.get("shared_replay_value", {}).duplicate(true)}

func save_scope(scope: String, value: Dictionary) -> bool:
	if not _scope_valid(scope) or value.get("schema_version") != 1 or JSON.stringify(value).to_utf8_buffer().size() > MAX_BYTES - 4096: return false
	if not load_scope(scope).ok: return false
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return false
	var save := Save.new(directory.path_join(scope.sha256_text() + ".json"))
	save.load_data()
	return save.update_values({"shared_replay_scope": scope, "shared_replay_value": value.duplicate(true)})

static func _scope_valid(scope: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^shared-replays:[A-Za-z0-9_-]{22}:(index|legacy:[A-Za-z0-9_-]{22}|chapter:[A-Za-z0-9_-]{22})$")
	return pattern.search(scope) != null
