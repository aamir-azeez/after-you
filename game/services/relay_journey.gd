class_name RelayJourney
extends RefCounted
## Local v2 progression. The v1 journey and Android identity vault are untouched.

const Storage = preload("res://services/local_save.gd")
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
var _level: Dictionary = Catalog.relay_isles()
var _state: Dictionary = {}
var _checkpoint: Dictionary = {}
var _loaded := false
var _path := PATH
var _live_simulation: WeakRef
var _draft_replay_verified := true


func _init(save_path: String = PATH, storage: RefCounted = null) -> void:
	_path = save_path
	_storage = Storage.new(save_path) if storage == null else storage


func load_data() -> void:
	_loaded = true
	_live_simulation = null
	_draft_replay_verified = true
	last_error = ""
	read_only = false
	_state = _empty_state()
	_checkpoint = Catalog.initial_checkpoint(_level)
	if ProjectSettings.globalize_path(_path).simplify_path() == ProjectSettings.globalize_path(Storage.PATH).simplify_path():
		_hold("The new chapter must use its separate save file. The original journey was not opened.")
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
			_hold("The chapter save cannot be safely read. It has been preserved.")
			return
		var json := JSON.new()
		var parsed := json.parse(file.get_as_text())
		file.close()
		if parsed != OK:
			unreadable.append(candidate)
			continue
		if not json.data is Dictionary:
			_hold("The chapter save has an unsupported structure. It has been preserved.")
			return
		var raw: Dictionary = json.data
		if not _envelope_valid(raw):
			_hold("This chapter save has an unsupported format. It has been kept unchanged.")
			return
		var state_digest := Canonical.digest(raw.relay)
		var validation: Dictionary = verified_generations.get(state_digest, {})
		if validation.is_empty():
			validation = _validate_state(raw.relay)
		if not validation.valid:
			_hold("A chapter save could not be verified: " + str(validation.error))
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
		_hold("The saved chapter could not be verified: " + str(checked.error))
		return
	for candidate: String in unreadable:
		if not _preserve_unreadable(candidate):
			_hold("Recovered chapter data is readable, but its damaged generation could not be preserved. No progress has been overwritten.")
			return
	_state = _storage.data.relay.duplicate(true)
	_checkpoint = checked.checkpoint.duplicate(true)
	last_error = str(_storage.last_error)
	if not unreadable.is_empty():
		last_error = "Recovered verified chapter progress. Damaged generations were preserved beside the save."


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
			_hold("The saved rehearsal could not be verified: " + str(checked.error))
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
		last_error = "This chapter is already complete. Its recordings have been kept."
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
		last_error = "This chapter cannot start another live rehearsal."
		return null
	var simulation := Simulation.new()
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
	if simulation == null or _live_simulation == null or _live_simulation.get_ref() != simulation or simulation.get_script() != Simulation:
		last_error = "Only this chapter's active rehearsal can use live autosave."
		return false
	# Compare whole dictionaries so mutating an object while keeping its old
	# hash cannot reuse a trusted context. These references never leave local
	# application code; all values are copied before they reach storage.
	if not str(simulation.get("error")).is_empty() or simulation.get("role") != role() or not Canonical.same(simulation.get("level"), _level) or not Canonical.same(simulation.get("stage"), Simulation.stage_by_id(_level, stage_id())) or not Canonical.same(simulation.get("_checkpoint"), _checkpoint) or not Canonical.same(simulation.get("_prior"), _state.a):
		last_error = "The active rehearsal's source, stage or controls changed."
		return false
	var recording: Dictionary = simulation.export_recording()
	var reason := Simulation.recording_error(_level, recording, _checkpoint)
	var expected_source := str(_state.a.get("recording_hash", ""))
	if not reason.is_empty() or recording.get("role") != role() or recording.get("source_recording_hash") != expected_source:
		last_error = reason if not reason.is_empty() else "The live rehearsal does not match its earlier contribution."
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
		last_error = "This chapter is already complete. Its recordings have been kept."
		return false
	var checked := _verify_current(recording)
	if not checked.valid:
		last_error = str(checked.error)
		return false
	if not checked.snapshot.get("can_commit", false):
		last_error = "This rehearsal has not completed the required contribution. Try this stage again."
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
		return {"valid": false, "error": "This recording belongs to a different role or stage."}
	return Simulation.verify_recording(_level, recording, _checkpoint, _state.a)


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
		return _invalid("Unknown chapter state fields.")
	if value.schema_version != 2 or value.simulation_version != 2 or value.level_id != _level.id or value.level_version != _level.version or value.definition_hash != Canonical.digest(_level):
		return _invalid("Unsupported chapter or simulation version.")
	if not value.pairs is Array or value.pairs.size() > _level.stages.size() or not value.a is Dictionary or not value.draft is Dictionary:
		return _invalid("Malformed stage history.")
	var derived := Catalog.initial_checkpoint(_level)
	for pair: Variant in value.pairs:
		if not pair is Dictionary or not _exact_keys(pair, ["a", "b"]) or not pair.a is Dictionary or not pair.b is Dictionary:
			return _invalid("Malformed completed pair.")
		var checked := Simulation.derive_checkpoint(_level, derived, pair.a, pair.b)
		if not checked.valid:
			return _invalid(str(checked.error))
		derived = checked.checkpoint
	if str(derived.next_stage_id).is_empty():
		if not value.a.is_empty() or not value.draft.is_empty():
			return _invalid("A completed chapter cannot contain another turn.")
		return {"valid": true, "error": "", "checkpoint": derived}
	if not value.a.is_empty():
		var first := Simulation.verify_recording(_level, value.a, derived)
		if value.a.get("role") != "a" or not first.valid or not first.get("snapshot", {}).get("can_commit", false):
			return _invalid("The saved earlier contribution cannot be verified.")
	if not value.draft.is_empty():
		var expected_role := "a" if value.a.is_empty() else "b"
		if value.draft.get("role") != expected_role:
			return _invalid("The rehearsal has the wrong role.")
		var rehearsal := Simulation.verify_recording(_level, value.draft, derived, value.a)
		if not rehearsal.valid:
			return _invalid("The rehearsal does not match its saved source: " + str(rehearsal.error))
	return {"valid": true, "error": "", "checkpoint": derived}


func _empty_state() -> Dictionary:
	return {"schema_version": 2, "simulation_version": 2, "level_id": _level.id, "level_version": _level.version,
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
	return not value.has("settings") or Canonical.same(value.settings, Storage.defaults().settings)


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
