class_name LighthouseJourney
extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Durable Lighthouse practice with replay-verified checkpoints and immutable turns.

const Storage = preload("res://services/local_save.gd")
const Archive = preload("res://services/attempt_archive.gd")
const Catalog = preload("res://core/lighthouse/stage_catalog.gd")
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PATH := "user://lighthouse-journey-v3.json"
const MAX_SAVE_BYTES := 2097152
const MAX_ARCHIVED_ATTEMPTS := 32
const TOTAL_STAGES := 6
const STATE_KEYS := ["schema_version", "simulation_version", "level_id", "level_version", "pairs", "a", "draft"]
const ENVELOPE_KEYS := ["version", "generation", "settings", "attempts", "completed", "replays", "room", "lighthouse"]

var last_error := ""
var read_only := false
var _storage: RefCounted
var _level: Dictionary = Catalog.definition()
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
	_checkpoint = Simulation.initial_checkpoint()
	if ProjectSettings.globalize_path(_path).simplify_path() in [ProjectSettings.globalize_path(Storage.PATH).simplify_path(), ProjectSettings.globalize_path("user://relay-journey-v2.json").simplify_path()]:
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
		var state_digest := Canonical.digest(raw.lighthouse)
		var validation: Dictionary = verified_generations.get(state_digest, {})
		if validation.is_empty():
			validation = _validate_state(raw.lighthouse)
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
	var selected: Variant = _storage.data.get("lighthouse")
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
	_state = _storage.data.lighthouse.duplicate(true)
	_checkpoint = checked.checkpoint.duplicate(true)
	last_error = str(_storage.last_error)
	if not unreadable.is_empty():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_02EA99BBE9D2


func checkpoint() -> Dictionary:
	_ensure_loaded()
	return {} if read_only else _checkpoint.duplicate(true)


func stage_id() -> String:
	_ensure_loaded()
	var index := int(_checkpoint.get("stage_index", 0))
	return "" if read_only or index >= Catalog.STAGE_IDS.size() else str(Catalog.STAGE_IDS[index])


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
	return not read_only and _state.pairs.size() == TOTAL_STAGES


func save_draft(recording: Dictionary) -> bool:
	_ensure_loaded()
	if read_only:
		return false
	if stage_id().is_empty():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_81D432A610F3
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


func create_live_simulation(resume_draft: bool = false) -> RefCounted:
	## This is the only producer accepted by save_live_draft. The UI owns its
	## controls; imported dictionaries still go through save_draft/replay.
	_ensure_loaded()
	if read_only or stage_id().is_empty():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_A50E1C712793
		return null
	var simulation := Simulation.new()
	var saved: Dictionary = draft() if resume_draft else {}
	if read_only: return null
	var rules := int(saved.get("simulation_version", Simulation.CURRENT_SIMULATION_VERSION))
	if not simulation.reset(role(), _state.a, _state.pairs, rules):
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
	if read_only or stage_id().is_empty():
		return false
	if simulation == null or _live_simulation == null or _live_simulation.get_ref() != simulation or simulation.get_script() != Simulation:
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_39CF13FECD8C
		return false
	# Compare whole dictionaries so mutating an object while keeping its old
	# hash cannot reuse a trusted context. These references never leave local
	# application code; all values are copied before they reach storage.
	if not str(simulation.get("error")).is_empty() or simulation.get("role") != role() or not Canonical.same(simulation.get("_level"), Catalog.definition(stage_id())) or not Canonical.same(simulation.get("_checkpoint"), _checkpoint) or not Canonical.same(simulation.get("_prior"), _state.a):
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_A3F995624F41
		return false
	var recording: Dictionary = simulation.export_recording()
	var reason: String = Simulation._record_error(recording)
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
	if stage_id().is_empty():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_81D432A610F3
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
	return Simulation.verify_recording(recording, _state.a, _state.pairs)


func fork_from_stage(index: int) -> bool:
	## Keep a complete immutable local copy before changing dependent turns.
	## Accepted stages before index survive byte-for-byte; only the new active
	## attempt starts again. A failed archive or active write advances nothing.
	_ensure_loaded()
	if read_only:
		return false
	if index < 0 or index > _state.pairs.size() or index >= Catalog.STAGE_IDS.size():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_66C3BEF32753
		return false
	if index == _state.pairs.size() and _state.a.is_empty() and _state.draft.is_empty():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_2AAC2AD4BB93
		return false
	var next := _state.duplicate(true)
	next.pairs = _state.pairs.slice(0, index).duplicate(true)
	next.a = {}
	next.draft = {}
	var checked := _validate_state(next)
	if not checked.valid:
		last_error = str(checked.error)
		return false
	if not _archive_current_attempt():
		return false
	if not _write_verified_state(next, checked.checkpoint):
		return false
	_live_simulation = null
	_draft_replay_verified = true
	return true


func _archive_current_attempt() -> bool:
	last_error = Archive.save(_path, "lighthouse", _state, MAX_SAVE_BYTES, MAX_ARCHIVED_ATTEMPTS)
	return last_error.is_empty()

func archived_attempts() -> Array[Dictionary]:
	_ensure_loaded()
	return [] if read_only else Archive.list_attempts(_path, "lighthouse", MAX_SAVE_BYTES)

func archived_pairs(id: String) -> Array:
	_ensure_loaded()
	if read_only: return []
	var state := Archive.load_attempt(_path, "lighthouse", id, MAX_SAVE_BYTES)
	var checked := _validate_state(state)
	if not checked.valid:
		last_error = str(checked.error)
		return []
	last_error = ""
	return state.pairs.duplicate(true)


func _persist(next: Dictionary) -> bool:
	var checked := _validate_state(next)
	if not checked.valid:
		last_error = str(checked.error)
		return false
	return _write_verified_state(next, checked.checkpoint)


func _write_verified_state(next: Dictionary, derived_checkpoint: Dictionary) -> bool:
	# The accepted role/checkpoint changes only after the recoverable transport
	# succeeds. A failed write leaves the current A/draft and checkpoint intact.
	if not _storage.update_values({"lighthouse": next.duplicate(true)}):
		last_error = str(_storage.last_error)
		return false
	_state = next.duplicate(true)
	_checkpoint = derived_checkpoint.duplicate(true)
	last_error = ""
	return true


func _validate_state(value: Variant) -> Dictionary:
	if not value is Dictionary or not _exact_keys(value, STATE_KEYS):
		return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_E45D0DDEDD2F)
	if value.schema_version != 3 or value.simulation_version != 3 or value.level_id != _level.id or value.level_version != _level.version:
		return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_3277AC1A21BD)
	if not value.pairs is Array or value.pairs.size() > TOTAL_STAGES or not value.a is Dictionary or not value.draft is Dictionary:
		return _invalid("Malformed stage history.")
	var history := Simulation.checkpoint_from_pairs(value.pairs)
	if not history.valid:
		return _invalid(str(history.error))
	var derived: Dictionary = history.checkpoint
	if int(derived.stage_index) >= Catalog.STAGE_IDS.size():
		if not value.a.is_empty() or not value.draft.is_empty():
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_D30A68DD22C9)
		return {"valid": true, "error": "", "checkpoint": derived}
	if not value.a.is_empty():
		var first := Simulation.verify_recording(value.a, {}, value.pairs)
		if value.a.get("role") != "a" or not first.valid or not first.get("snapshot", {}).get("can_commit", false):
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_1393CFB1623B)
	if not value.draft.is_empty():
		var expected_role := "a" if value.a.is_empty() else "b"
		if value.draft.get("role") != expected_role:
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_2A6C3206C0FC)
		var rehearsal := Simulation.verify_recording(value.draft, value.a, value.pairs)
		if not rehearsal.valid:
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_3E836B83D99B + str(rehearsal.error))
	return {"valid": true, "error": "", "checkpoint": derived}


func _empty_state() -> Dictionary:
	return {"schema_version": 3, "simulation_version": 3, "level_id": _level.id, "level_version": _level.version,
		 "pairs": [], "a": {}, "draft": {}}


func _envelope_valid(value: Dictionary) -> bool:
	for key: Variant in value:
		if key not in ENVELOPE_KEYS:
			return false
	if value.get("version") != 1 or not value.has("lighthouse"):
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
