class_name RelayJourney
extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Local v2 progression. The v1 journey and Android identity vault are untouched.

const Storage = preload("res://services/local_save.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PATH := "user://relay-journey-v2.json"
const MAX_SAVE_BYTES := 1048576
const STATE_KEYS := ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "pairs", "a", "draft"]
const ENVELOPE_KEYS := ["version", "generation", "settings", "attempts", "completed", "replays", "room", "relay"]

var last_error := ""
var read_only := false
var _storage: RefCounted
var _chapter_key := Registry.RELAY
var _level: Dictionary = {}
var _simulation: Script
var _state: Dictionary = {}
var _checkpoint: Dictionary = {}
var _loaded := false
var _path := PATH
var _live_simulation: WeakRef
var _draft_replay_verified := true


func _init(save_path: String = "", storage: RefCounted = null, chapter: String = Registry.RELAY) -> void:
	_chapter_key = chapter
	_level = Registry.definition(chapter)
	_simulation = Registry.simulation_script(chapter)
	_path = save_path if not save_path.is_empty() else str(Registry.descriptor(chapter).get("local_path", ""))
	_storage = Storage.new(_path) if storage == null else storage

func chapter_key() -> String:
	return _chapter_key

func _wrong_path() -> bool:
	var absolute := ProjectSettings.globalize_path(_path).simplify_path()
	for key: String in Registry.keys():
		if key != _chapter_key and absolute == ProjectSettings.globalize_path(Registry.descriptor(key).local_path).simplify_path():
			return true
	return absolute == ProjectSettings.globalize_path(Storage.PATH).simplify_path()


func load_data() -> void:
	_loaded = true
	_live_simulation = null
	_draft_replay_verified = true
	last_error = ""
	read_only = false
	if _level.is_empty() or _simulation == null or _path.is_empty():
		_hold(PlayerCopy.RELAY_JOURNEY_AAD38006E9E9)
		return
	_state = _empty_state()
	_checkpoint = Registry.initial_checkpoint(_chapter_key)
	if _wrong_path():
		_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_4C9D52BC9431)
		return
	# Check unfamiliar semantic envelopes before the transport chooses the
	# newest generation. A future/current file must not be erased just because
	# an older backup is readable. Valid interrupted generations still use the
	# established LocalSave selection/recovery behavior.
	var any_existing := false
	var unreadable: Array[String] = []
	# Cache only successful full-state checks within this one disk read. The
	# key covers all evidence, not the checkpoint's user-supplied hash.
	var verified_generations: Dictionary = {}
	for suffix: String in ["", ".tmp", ".backup"]:
		var candidate := _path + suffix
		if not FileAccess.file_exists(candidate):
			continue
		any_existing = true
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > MAX_SAVE_BYTES:
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_11E2E859ADF5)
			return
		var json := JSON.new()
		var parsed := json.parse(file.get_as_text())
		file.close()
		if parsed != OK:
			unreadable.append(candidate)
			continue
		if not json.data is Dictionary:
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_EE42C27D88E0)
			return
		var raw: Dictionary = json.data
		if not _envelope_valid(raw):
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_D2BF9FC4AD99)
			return
		var state_digest := Canonical.digest(raw.relay)
		var validation: Dictionary = verified_generations.get(state_digest, {})
		if validation.is_empty():
			validation = _validate_state(raw.relay)
		if not validation.valid:
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_9E86081E1033 + str(validation.error))
			return
		verified_generations[state_digest] = validation.duplicate(true)
	_storage.load_data()
	if _storage.read_only:
		_hold(str(_storage.last_error))
		return
	if not any_existing:
		return
	var selected: Variant = _storage.data.get("relay")
	var checked: Dictionary = verified_generations.get(Canonical.digest(selected), {})
	if checked.is_empty():
		checked = _validate_state(selected)
	if not checked.valid:
		_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_194A9F56B459 + str(checked.error))
		return
	for candidate: String in unreadable:
		if not _preserve_unreadable(candidate):
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_44A358EB95E9)
			return
	_state = _storage.data.relay.duplicate(true)
	_checkpoint = checked.checkpoint.duplicate(true)
	last_error = str(_storage.last_error)
	if not unreadable.is_empty():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_02EA99BBE9D2


func checkpoint() -> Dictionary:
	_ensure_loaded()
	return {} if read_only else _checkpoint.duplicate(true)


func stage_id() -> String:
	_ensure_loaded()
	return "" if read_only else str(_checkpoint.next_stage_id)


func role() -> String:
	_ensure_loaded()
	return "b" if not read_only and not _state.a.is_empty() else "a"


func prior_recording() -> Dictionary:
	_ensure_loaded()
	return {} if read_only else _state.a.duplicate(true)


func draft() -> Dictionary:
	_ensure_loaded()
	# Live autosave writes an internal engine export without replaying the
	# entire chapter on every frame. Before exposing it for a later rehearsal,
	# perform the same replay verification used for arbitrary incoming data.
	if not read_only and not _draft_replay_verified:
		var checked := _verify_current(_state.draft)
		if not checked.valid:
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_BA7ED957F6B2 + str(checked.error))
		else:
			_draft_replay_verified = true
	return {} if read_only else _state.draft.duplicate(true)


func pairs() -> Array:
	_ensure_loaded()
	return [] if read_only else _state.pairs.duplicate(true)


func chapter_complete() -> bool:
	_ensure_loaded()
	return not read_only and str(_checkpoint.next_stage_id).is_empty() and _state.pairs.size() == _level.stages.size()


func save_draft(recording: Dictionary) -> bool:
	_ensure_loaded()
	if read_only:
		return false
	if chapter_complete():
		last_error = PlayerCopy.RELAY_JOURNEY_2AF0FCE9863E
		return false
	if not recording.is_empty():
		var checked := _verify_current(recording)
		if not checked.valid:
			last_error = str(checked.error)
			return false
	var next := _state.duplicate(true)
	next.draft = recording.duplicate(true)
	# Accepted evidence and checkpoint are unchanged and already verified.
	# Avoid replaying the same candidate twice inside a single explicit save.
	var saved := _write_verified_state(next, _checkpoint)
	if saved:
		_draft_replay_verified = true
		_live_simulation = null
	return saved


func create_live_simulation() -> RefCounted:
	## This is the only producer accepted by save_live_draft. The UI owns its
	## controls; imported dictionaries still go through save_draft/replay.
	_ensure_loaded()
	if read_only or chapter_complete():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_A50E1C712793
		return null
	var simulation: RefCounted = _simulation.new()
	if not simulation.reset(_level, stage_id(), _checkpoint, _state.a, role()):
		last_error = str(simulation.error)
		return null
	_live_simulation = weakref(simulation)
	last_error = ""
	return simulation


func save_live_draft(simulation: RefCounted) -> bool:
	## Draft-only durability from the registered internal engine. No accepted
	## role, pair or checkpoint advances here. Full replay is mandatory when
	## loading/resuming this draft and when explicitly accepting a turn.
	_ensure_loaded()
	if read_only or chapter_complete():
		return false
	if simulation == null or _live_simulation == null or _live_simulation.get_ref() != simulation or simulation.get_script() != _simulation:
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_39CF13FECD8C
		return false
	# Compare whole dictionaries so mutating an object while keeping its old
	# hash cannot reuse a trusted context. These references never leave local
	# application code; all values are copied before they reach storage.
	if not str(simulation.get("error")).is_empty() or simulation.get("role") != role() or not Canonical.same(simulation.get("level"), _level) or not Canonical.same(simulation.get("stage"), _simulation.stage_by_id(_level, stage_id())) or not Canonical.same(simulation.get("_checkpoint"), _checkpoint) or not Canonical.same(simulation.get("_prior"), _state.a):
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_A3F995624F41
		return false
	var recording: Dictionary = simulation.export_recording()
	var reason: String = _simulation.recording_error(_level, recording, _checkpoint)
	var expected_source := str(_state.a.get("recording_hash", ""))
	if not reason.is_empty() or recording.get("role") != role() or recording.get("source_recording_hash") != expected_source:
		last_error = reason if not reason.is_empty() else PlayerCopy.LIGHTHOUSE_JOURNEY_7D1ED48EEACE
		return false
	var next := _state.duplicate(true)
	next.draft = recording.duplicate(true)
	var saved := _write_verified_state(next, _checkpoint)
	if saved:
		_draft_replay_verified = false
	return saved


func accept_recording(recording: Dictionary) -> bool:
	_ensure_loaded()
	if read_only:
		return false
	if chapter_complete():
		last_error = PlayerCopy.RELAY_JOURNEY_2AF0FCE9863E
		return false
	var checked := _verify_current(recording)
	if not checked.valid:
		last_error = str(checked.error)
		return false
	if not checked.snapshot.get("can_commit", false):
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_E16BEB3ABB12
		return false
	var next := _state.duplicate(true)
	if role() == "a":
		next.a = recording.duplicate(true)
	else:
		next.pairs.append({"a": next.a.duplicate(true), "b": recording.duplicate(true)})
		next.a = {}
	next.draft = {}
	var saved := _persist(next)
	if saved:
		_live_simulation = null
		_draft_replay_verified = true
	return saved


func _verify_current(recording: Dictionary) -> Dictionary:
	if recording.get("role") != role() or recording.get("stage_id") != stage_id():
		return {"valid": false, "error": PlayerCopy.LIGHTHOUSE_JOURNEY_1E2666F7F555}
	return _simulation.verify_recording(_level, recording, _checkpoint, _state.a)


func _persist(next: Dictionary) -> bool:
	var checked := _validate_state(next)
	if not checked.valid:
		last_error = str(checked.error)
		return false
	return _write_verified_state(next, checked.checkpoint)


func _write_verified_state(next: Dictionary, derived_checkpoint: Dictionary) -> bool:
	# The accepted role/checkpoint changes only after the recoverable transport
	# succeeds. A failed write leaves the current A/draft and checkpoint intact.
	if not _storage.update_values({"relay": next.duplicate(true)}):
		last_error = str(_storage.last_error)
		return false
	_state = next.duplicate(true)
	_checkpoint = derived_checkpoint.duplicate(true)
	last_error = ""
	return true


func _validate_state(value: Variant) -> Dictionary:
	if not value is Dictionary or not _exact_keys(value, STATE_KEYS):
		return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_E45D0DDEDD2F)
	if value.schema_version != _level.schema_version or value.simulation_version != _level.simulation_version or value.level_id != _level.id or value.level_version != _level.version or value.definition_hash != Canonical.digest(_level):
		return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_3277AC1A21BD)
	if not value.pairs is Array or value.pairs.size() > _level.stages.size() or not value.a is Dictionary or not value.draft is Dictionary:
		return _invalid("Malformed stage history.")
	var derived := Registry.initial_checkpoint(_chapter_key)
	for pair: Variant in value.pairs:
		if not pair is Dictionary or not _exact_keys(pair, ["a", "b"]) or not pair.a is Dictionary or not pair.b is Dictionary:
			return _invalid("Malformed completed pair.")
		var checked: Dictionary = _simulation.derive_checkpoint(_level, derived, pair.a, pair.b)
		if not checked.valid:
			return _invalid(str(checked.error))
		derived = checked.checkpoint
	if str(derived.next_stage_id).is_empty():
		if not value.a.is_empty() or not value.draft.is_empty():
			return _invalid(PlayerCopy.RELAY_JOURNEY_0B5E838FD37D)
		return {"valid": true, "error": "", "checkpoint": derived}
	if not value.a.is_empty():
		var first: Dictionary = _simulation.verify_recording(_level, value.a, derived)
		if value.a.get("role") != "a" or not first.valid or not first.get("snapshot", {}).get("can_commit", false):
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_1393CFB1623B)
	if not value.draft.is_empty():
		var expected_role := "a" if value.a.is_empty() else "b"
		if value.draft.get("role") != expected_role:
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_2A6C3206C0FC)
		var rehearsal: Dictionary = _simulation.verify_recording(_level, value.draft, derived, value.a)
		if not rehearsal.valid:
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_3E836B83D99B + str(rehearsal.error))
	return {"valid": true, "error": "", "checkpoint": derived}


func _empty_state() -> Dictionary:
	return {"schema_version": _level.schema_version, "simulation_version": _level.simulation_version, "level_id": _level.id, "level_version": _level.version,
		"definition_hash": Canonical.digest(_level), "pairs": [], "a": {}, "draft": {}}


func _envelope_valid(value: Dictionary) -> bool:
	for key: Variant in value:
		if key not in ENVELOPE_KEYS:
			return false
	if value.get("version") != 1 or not value.has("relay"):
		return false
	var generation: Variant = value.get("generation", 0)
	if not (generation is int or generation is float) or not is_finite(float(generation)) or float(generation) != floor(float(generation)) or generation < 0:
		return false
	for reserved: String in ["attempts", "completed", "replays", "room"]:
		if value.has(reserved) and (not value[reserved] is Dictionary or not value[reserved].is_empty()):
			return false
	return not value.has("settings") or Storage.default_settings_envelope_valid(value.settings)


func _preserve_unreadable(candidate: String) -> bool:
	var digest := FileAccess.get_sha256(candidate)
	if digest.is_empty():
		return false
	var archive := candidate + ".unreadable-" + digest + ".json"
	# No existing recovery artifact is overwritten. A repeated recovery can
	# reuse only an artifact whose bytes still match the damaged generation.
	if FileAccess.file_exists(archive):
		return FileAccess.get_sha256(archive) == digest
	return DirAccess.copy_absolute(candidate, archive) == OK and FileAccess.get_sha256(archive) == digest


func _ensure_loaded() -> void:
	if not _loaded:
		load_data()


func _hold(reason: String) -> void:
	read_only = true
	last_error = reason
	_checkpoint = {}


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if key not in expected:
			return false
	return true


static func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "error": reason}
