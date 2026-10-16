extends RefCounted

const AtomicFile = preload("res://services/atomic_file.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Typed = preload("res://services/typed_values.gd")

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
	var count := attempt_count(path)
	if count < 0: return PlayerCopy.LIGHTHOUSE_JOURNEY_B8C082157F62
	if count >= maximum_attempts: return PlayerCopy.LIGHTHOUSE_JOURNEY_28364B9E3ABB
	match AtomicFile.replace(archive, body.to_utf8_buffer()):
		AtomicFile.Step.DONE: return ""
		AtomicFile.Step.OPEN: return PlayerCopy.LIGHTHOUSE_JOURNEY_F9F9CF94573D
		AtomicFile.Step.VERIFY: return PlayerCopy.LIGHTHOUSE_JOURNEY_5FB9D060E51B
	return PlayerCopy.LIGHTHOUSE_JOURNEY_550B2AF9D241

## Archived attempts kept beside `path`, or -1 when its folder cannot be read.
static func attempt_count(path: String) -> int:
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null: return -1
	var count := 0
	for filename: String in directory.get_files():
		if filename.begins_with(path.get_file() + ".attempt-") and filename.ends_with(".json"):
			count += 1
	return count

## True when save() would refuse `state` for want of room: no copy of it is
## kept yet and the device already holds maximum_attempts. Reads no attempt.
static func full(path: String, state: Dictionary, maximum_attempts: int) -> bool:
	if attempt_count(path) < maximum_attempts: return false
	return not FileAccess.file_exists(path + ".attempt-" + Canonical.digest(state) + ".json")

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
		result.append({"id": id, "stage_count": state.pairs.size(), "modified": FileAccess.get_modified_time(path + ".attempt-" + id + ".json"), "definition_hash": str(state.get("definition_hash", ""))})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.modified) > int(b.modified) if a.modified != b.modified else str(a.id) < str(b.id))
	return result

static func load_attempt(path: String, field: String, id: String, maximum_bytes: int) -> Dictionary:
	if id.length() != 64 or not id.is_valid_hex_number(false): return {}
	var file := FileAccess.open(path + ".attempt-" + id + ".json", FileAccess.READ)
	if file == null or file.get_length() > maximum_bytes: return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return {}
	var value: Variant = json.data
	if not value is Dictionary or value.size() != 2 or not Typed.equal(value.get("archive_version"), 1) or not value.get(field) is Dictionary:
		return {}
	var state: Dictionary = value[field]
	return state.duplicate(true) if Canonical.digest(state) == id else {}
