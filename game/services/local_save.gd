extends RefCounted
## Recoverable generations. Device credentials are never stored in this file.
const PATH := "user://journey.json"
var data: Dictionary = defaults()
var path := PATH
var last_error := ""
var read_only := false
var loaded_from := ""

func _init(save_path: String = PATH) -> void:
	path = save_path

static func defaults() -> Dictionary:
	return {"version": 1, "generation": 0, "settings": {"sound": true, "haptics": true, "reduced_motion": false, "assistance": true, "left_handed": false}, "attempts": {}, "completed": {}, "replays": {}, "room": {}}

func load_data() -> void:
	data = defaults()
	last_error = ""
	read_only = false
	loaded_from = ""
	var best_generation := -1
	for candidate: String in [path, path + ".tmp", path + ".backup"]:
		if not FileAccess.file_exists(candidate):
			continue
		var value: Variant = _read_json(candidate)
		if candidate == path and value is Dictionary and int(value.get("version", 0)) > 1:
			read_only = true
			last_error = "This save belongs to a newer app version. It has been kept unchanged."
		if not _valid(value):
			continue
		var generation := int(value.get("generation", 0))
		if generation > best_generation:
			data = _with_defaults(value)
			loaded_from = candidate
			best_generation = generation
	if loaded_from != path and not loaded_from.is_empty() and not read_only:
		last_error = "Recovered your latest saved progress after an interrupted write."
	elif loaded_from.is_empty() and FileAccess.file_exists(path) and not read_only:
		read_only = true
		last_error = "The existing save could not be read. It is preserved for recovery."

func flush() -> bool:
	if read_only:
		return false
	var candidate := data.duplicate(true)
	candidate["generation"] = int(data.get("generation", 0)) + 1
	if not _valid(candidate):
		last_error = "The progress could not be saved because its format is invalid."
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Could not write progress on this device."
		return false
	file.store_string(JSON.stringify(candidate))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not _valid(_read_json(path + ".tmp")):
		last_error = "The progress write was interrupted. Your previous save is still available."
		return false
	# Never replace a good backup with a corrupted primary file.
	if FileAccess.file_exists(path) and _valid(_read_json(path)):
		if DirAccess.copy_absolute(path, path + ".backup") != OK:
			last_error = "Could not preserve the previous save."
			return false
	var replaced := DirAccess.rename_absolute(path + ".tmp", path)
	if replaced != OK and FileAccess.file_exists(path):
		# A complete new generation and prior valid backup already exist.
		if DirAccess.remove_absolute(path) == OK:
			replaced = DirAccess.rename_absolute(path + ".tmp", path)
	if replaced != OK:
		last_error = "The new save is recoverable, but could not become the active save."
		return false
	data = candidate
	last_error = ""
	return true

func update_values(changes: Dictionary, erase_keys: Array = []) -> bool:
	var previous := data.duplicate(true)
	data.merge(changes.duplicate(true), true)
	for key: String in erase_keys:
		data.erase(key)
	if flush():
		return true
	data = previous
	return false

func attempt(level_id: String) -> Dictionary:
	return normalize_attempt(data.attempts.get(level_id, {}))

func save_attempt(level_id: String, value: Dictionary, completed: bool = false) -> bool:
	var attempts: Dictionary = data.attempts.duplicate(true)
	attempts[level_id] = normalize_attempt(value)
	var changes := {"attempts": attempts}
	if completed:
		var marks: Dictionary = data.completed.duplicate(true)
		marks[level_id] = true
		var replays: Dictionary = data.replays.duplicate(true)
		replays[level_id] = normalize_attempt(value)
		changes.merge({"completed": marks, "replays": replays})
	return update_values(changes)

func clear_draft(level_id: String) -> bool:
	var value := attempt(level_id)
	value.draft = {}
	return save_attempt(level_id, value)

static func normalize_attempt(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	var result := {"a": {}, "b": {}, "draft": {}}
	for key: String in result:
		if source.get(key) is Dictionary:
			result[key] = source[key].duplicate(true)
	return result

static func _valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version", 0) != 1:
		return false
	for key: String in ["settings", "attempts", "completed", "room"]:
		if value.has(key) and not value[key] is Dictionary:
			return false
	return true

static func _read_json(file_path: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(file_path))==OK else null

static func _with_defaults(value: Dictionary) -> Dictionary:
	var result := defaults()
	result.merge(value.duplicate(true), true)
	var settings: Dictionary = defaults().settings
	settings.merge(value.get("settings", {}), true)
	result.settings = settings
	if not result.get("replays") is Dictionary:
		result.replays = {}
	return result
