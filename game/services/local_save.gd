extends RefCounted
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Canonical = preload("res://core/v2/canonical.gd")
## Recoverable generations. Device credentials are never stored in this file.
const PATH := "user://journey.json"
## Each copy start_fresh_if_unreadable moves aside keeps its own name, then
## this, then its SHA-256 and ".json".
const UNREADABLE := ".unreadable-"
var data: Dictionary = defaults()
var path := PATH
var last_error := ""
var read_only := false
var loaded_from := ""
## Set by load_data when the file exists and every copy of it opened but none
## parses as JSON.
var _unreadable := false

func _init(save_path: String = PATH) -> void:
	path = save_path

static func defaults() -> Dictionary:
	return {"version": 1, "generation": 0, "settings": {"sound": true, "haptics": true, "reduced_motion": false, "assistance": true, "left_handed": false, "photo_prompts": true, "turn_notifications": false, "turn_request_notifications": false, "share_online_status": true, "graphics_quality": GraphicsPolicy.DEFAULT_QUALITY, "unlimited_frame_rate": false, "skip_waits": false}, "attempts": {}, "completed": {}, "replays": {}, "room": {}}

static func default_settings_envelope_valid(value: Variant) -> bool:
	# Chapter journals do not own UI preferences. Older envelopes may omit
	# defaults introduced later; supplied fields must remain known defaults.
	if not value is Dictionary:
		return false
	var expected: Dictionary = defaults().settings
	for key: Variant in value:
		if not expected.has(key) or typeof(value[key]) != typeof(expected[key]) or value[key] != expected[key]:
			return false
	return true

func load_data() -> void:
	data = defaults()
	last_error = ""
	read_only = false
	loaded_from = ""
	_unreadable = false
	var existing := 0
	var unparsed := 0
	var best_generation := -1
	for candidate: String in AtomicFile.read_candidates(path):
		if not FileAccess.file_exists(candidate):
			continue
		existing += 1
		var bytes: Variant = _copy_bytes(candidate)
		var parser := JSON.new()
		if not bytes is PackedByteArray or parser.parse(bytes.get_string_from_utf8()) != OK:
			if bytes is PackedByteArray:
				unparsed += 1
			continue
		var value: Variant = parser.data
		if candidate == path and _newer(value):
			read_only = true
			last_error = PlayerCopy.LOCAL_SAVE_59005ED74543
		if not _valid(value):
			continue
		var generation := int(value.get("generation", 0))
		if generation > best_generation:
			data = _with_defaults(value)
			loaded_from = candidate
			best_generation = generation
	if loaded_from != path and not loaded_from.is_empty() and not read_only:
		last_error = PlayerCopy.LOCAL_SAVE_27DCFA34F3AD
	elif loaded_from.is_empty() and FileAccess.file_exists(path) and not read_only:
		read_only = true
		last_error = PlayerCopy.LOCAL_SAVE_34FCC2945DC1
		_unreadable = unparsed == existing

## After load_data, for a save that may start over. When load_data found the
## file and every copy of it opened but none parses, renames each copy to
## `<copy>.unreadable-<SHA-256>.json`, which nothing reads, writes or removes,
## and continues with defaults as if no save existed. Each copy is read again
## just before its rename and moves only if those same bytes still do not
## parse. Nothing is written here: the first ordinary save writes the new file.
## last_error holds the note for the player.
## False when there was nothing to recover, or when a copy could not be
## confirmed or renamed and the save stays read-only. The primary file moves
## last, so after a failed rename the next load still finds it and tries again.
func start_fresh_if_unreadable() -> bool:
	if not _unreadable:
		return false
	var copies := AtomicFile.read_candidates(path)
	copies.reverse()
	for candidate: String in copies:
		if not FileAccess.file_exists(candidate):
			continue
		var bytes: Variant = _copy_bytes(candidate)
		if not bytes is PackedByteArray or _parses(bytes) or not AtomicFile.move_aside(candidate, candidate + UNREADABLE, _sha256(bytes)):
			return false
	load_data()
	if read_only or not loaded_from.is_empty():
		return false
	last_error = PlayerCopy.LOCAL_SAVE_STARTED_FRESH
	return true

func flush() -> bool:
	if read_only:
		return false
	var candidate := data.duplicate(true)
	candidate["generation"] = int(data.get("generation", 0)) + 1
	if not _valid(candidate):
		last_error = PlayerCopy.LOCAL_SAVE_D4B7ABA2BF24
		return false
	if candidate.get("settings") is Dictionary:
		candidate.settings.graphics_quality = GraphicsPolicy.normalize(candidate.settings.get("graphics_quality"))
		candidate.settings.unlimited_frame_rate = GraphicsPolicy.unlimited_frame_rate(candidate.settings)
	# Never replace a good backup with a corrupted primary file.
	var backup := AtomicFile.Backup.COPY if FileAccess.file_exists(path) and _valid(_read_json(path)) else AtomicFile.Backup.NONE
	# A failed write leaves no complete newer generation behind (unless it is the
	# only whole one left), or the refused change would load after a restart.
	match AtomicFile.replace(path, JSON.stringify(candidate).to_utf8_buffer(), backup):
		AtomicFile.Step.OPEN:
			last_error = PlayerCopy.LOCAL_SAVE_2F0F16A1F066
			return false
		AtomicFile.Step.VERIFY:
			last_error = PlayerCopy.LOCAL_SAVE_5A7DDFC3534D
			return false
		AtomicFile.Step.BACKUP:
			last_error = PlayerCopy.LOCAL_SAVE_F6541C60A66B
			return false
		AtomicFile.Step.RENAME:
			last_error = PlayerCopy.LOCAL_SAVE_4CB79AD2E17E
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

func replay(level_id: String) -> Dictionary:
	var removed: Variant = data.get("removed_replays", {})
	if not removed is Dictionary or not removed.get(level_id, {}) is Dictionary:
		last_error = "Failed to load replay removals. No changes to your saved data."
		return normalize_attempt({})
	var markers: Dictionary = removed.get(level_id, {})
	for value: Variant in [data.attempts.get(level_id, {}), data.replays.get(level_id, {})]:
		var saved := normalize_attempt(value)
		if saved.b.is_empty(): continue
		# Ordinary collection rendering never hashes a recording. Only levels
		# with a prior deletion need to compare their retained gameplay pair.
		if markers.is_empty() or not markers.has(_replay_hash(saved)): return saved
	return normalize_attempt({})

func remove_replay(level_id: String, expected: Dictionary) -> bool:
	var selected := replay(level_id)
	if selected.b.is_empty() or not Canonical.same(selected, normalize_attempt(expected)):
		if last_error.is_empty(): last_error = "Could not remove this replay. Please try again."
		return false
	var hash := _replay_hash(selected)
	var removed: Dictionary = data.get("removed_replays", {}).duplicate(true)
	var markers: Dictionary = removed.get(level_id, {}).duplicate(true)
	markers[hash] = true
	removed[level_id] = markers
	var replays: Dictionary = data.replays.duplicate(true)
	if replays.has(level_id) and _replay_hash(normalize_attempt(replays[level_id])) == hash: replays.erase(level_id)
	# A completed attempt also remains gameplay state. Suppress its exact pair
	# in the collection without changing progress, drafts or restart archives.
	return update_values({"replays": replays, "removed_replays": removed})

static func _replay_hash(value: Dictionary) -> String:
	return Canonical.digest({"a": value.a, "b": value.b})

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
	if not value is Dictionary:
		return false
	var version: Variant = value.get("version", 0)
	if not Typed.whole_number(version) or version != 1 or not Typed.valid_generation(value.get("generation", 0)):
		return false
	for key: String in ["settings", "attempts", "completed", "room"]:
		if value.has(key) and not value[key] is Dictionary:
			return false
	return true

## A save written by a newer version of the app. A numeric string counts too.
static func _newer(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var version: Variant = value.get("version", 0)
	return (version is int or version is float or version is String) and int(version) > 1

static func _read_json(file_path: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(file_path))==OK else null

## The bytes of one copy of the save, or null when the file cannot be opened.
func _copy_bytes(file_path: String) -> Variant:
	var bytes := FileAccess.get_file_as_bytes(file_path)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		return null
	return bytes

static func _parses(bytes: PackedByteArray) -> bool:
	return JSON.new().parse(bytes.get_string_from_utf8()) == OK

static func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		hashing.update(bytes)
	return hashing.finish().hex_encode()

## JSON reads every number as a float, so int and float count as one kind.
static func _same_kind(value: Variant, default: Variant) -> bool:
	if (value is int or value is float) and (default is int or default is float): return true
	return typeof(value) == typeof(default)

static func _with_defaults(value: Dictionary) -> Dictionary:
	var result := defaults()
	result.merge(value.duplicate(true), true)
	var settings: Dictionary = defaults().settings
	var saved: Dictionary = value.get("settings", {})
	# A known setting of the wrong type (a damaged save) keeps its default, so
	# every reader can trust bool settings to be bools.
	for key: Variant in saved:
		if not settings.has(key) or _same_kind(saved[key], settings[key]): settings[key] = saved[key]
	settings.graphics_quality = GraphicsPolicy.normalize(settings.get("graphics_quality"))
	settings.unlimited_frame_rate = GraphicsPolicy.unlimited_frame_rate(settings)
	result.settings = settings
	if not result.get("replays") is Dictionary:
		result.replays = {}
	return result
