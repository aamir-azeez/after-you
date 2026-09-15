extends RefCounted
## Read-only memories have separate recoverable files, never gameplay journals.
const Save = preload("res://services/local_save.gd")
const MAX_BYTES := 16777216
var directory := "user://shared-replays"

func _init(root_path: String = "user://shared-replays") -> void: directory = root_path

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
