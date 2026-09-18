extends RefCounted

const Canonical = preload("res://core/v2/canonical.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

static func save(path: String, field: String, state: Dictionary, maximum_bytes: int, maximum_attempts: int) -> String:
	var body := JSON.stringify(Canonical.normalized({"archive_version": 1, field: state}))
	if body.to_utf8_buffer().size() > maximum_bytes:
		return PlayerCopy.LIGHTHOUSE_JOURNEY_35FB35AD71CE
	var archive := path + ".attempt-" + Canonical.digest(state) + ".json"
	if FileAccess.file_exists(archive):
		var existing := FileAccess.open(archive, FileAccess.READ)
		if existing != null and existing.get_length() <= maximum_bytes and existing.get_as_text() == body:
			return ""
		return PlayerCopy.LIGHTHOUSE_JOURNEY_C0B7631108D8
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null: return PlayerCopy.LIGHTHOUSE_JOURNEY_B8C082157F62
	var count := 0
	for filename: String in directory.get_files():
		if filename.begins_with(path.get_file() + ".attempt-") and filename.ends_with(".json"):
			count += 1
	if count >= maximum_attempts: return PlayerCopy.LIGHTHOUSE_JOURNEY_28364B9E3ABB
	var file := FileAccess.open(archive + ".tmp", FileAccess.WRITE)
	if file == null: return PlayerCopy.LIGHTHOUSE_JOURNEY_F9F9CF94573D
	file.store_string(body)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(archive + ".tmp") != body:
		return PlayerCopy.LIGHTHOUSE_JOURNEY_5FB9D060E51B
	if FileAccess.file_exists(archive): return PlayerCopy.LIGHTHOUSE_JOURNEY_E47B298B77E2
	if DirAccess.rename_absolute(archive + ".tmp", archive) != OK:
		return PlayerCopy.LIGHTHOUSE_JOURNEY_550B2AF9D241
	return ""

static func list_attempts(path: String, field: String, maximum_bytes: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null: return result
	var prefix := path.get_file() + ".attempt-"
	for filename: String in directory.get_files():
		if not filename.begins_with(prefix) or not filename.ends_with(".json"): continue
		var id := filename.trim_prefix(prefix).trim_suffix(".json")
		var state := load_attempt(path, field, id, maximum_bytes)
		if not state.get("pairs") is Array or state.pairs.is_empty(): continue
		result.append({"id": id, "stage_count": state.pairs.size(), "modified": FileAccess.get_modified_time(path + ".attempt-" + id + ".json")})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.modified) > int(b.modified) if a.modified != b.modified else str(a.id) < str(b.id))
	return result

static func load_attempt(path: String, field: String, id: String, maximum_bytes: int) -> Dictionary:
	if id.length() != 64 or not id.is_valid_hex_number(false): return {}
	var file := FileAccess.open(path + ".attempt-" + id + ".json", FileAccess.READ)
	if file == null or file.get_length() > maximum_bytes: return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return {}
	var value: Variant = json.data
	if not value is Dictionary or value.size() != 2 or value.get("archive_version") != 1 or not value.get(field) is Dictionary:
		return {}
	var state: Dictionary = value[field]
	return state.duplicate(true) if Canonical.digest(state) == id else {}
