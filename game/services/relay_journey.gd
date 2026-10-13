class_name RelayJourney
extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Local v2 progression. The v1 journey and Android identity vault are untouched.

const Storage = preload("res://services/local_save.gd")
const Archive = preload("res://services/attempt_archive.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const PATH := "user://relay-journey-v2.json"
const MAX_SAVE_BYTES := 1048576
const MAX_ARCHIVED_ATTEMPTS := 32
const STATE_KEYS := ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "pairs", "a", "draft"]
const ENVELOPE_KEYS := ["version", "generation", "settings", "attempts", "completed", "replays", "room", "relay"]
## Definitions a chapter's journal may still carry from an unreleased build at
## the same level version. Such a journal cannot replay under the current
## definition, so load_data moves it aside whole and the chapter starts fresh.
const RETIRED_DEFINITIONS := {
	"turn-of-the-tide@1": ["cbeb3d7753ac621ef30f99100af15149d15d8f5918df90b6996e4ce4b52d5ce7", "dfa00916f4022cbd3c5d677c5f6a61fcacb2256251ce62953404232a871d279a",
		"338e5b4a8b156734ab1b4237dd343fa3d7e95088d62fb61810bc793bd9e28560", "ed891de13f452b91a502414864910228a6513accef53f90160013bb393193f68"],
}

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
## Successful turn checks against this journey's own proven checkpoint, so the
## review and the Save that follows replay a turn once. Keyed by the exact
## checkpoint, partner turn and recording; a failed check is never kept.
const VERIFIED_TURNS := 4
var _verified_turns: Dictionary = {}
var _family_statics: Dictionary = {}
## How long the last replay-backed check and next-turn setup took here, so a
## screen can tell the player before a wait it can expect.
var _last_check_usec := 0
var _last_setup_usec := 0


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
	_verified_turns.clear()
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
	var retired: Array[String] = []
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
		if _retired(raw.relay):
			retired.append(candidate)
			continue
		var state_digest := Canonical.digest(raw.relay)
		var validation: Dictionary = verified_generations.get(state_digest, {})
		if validation.is_empty():
			validation = Proofs.validate(self, raw.relay)
		if not validation.valid:
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_9E86081E1033 + str(validation.error))
			return
		verified_generations[state_digest] = validation.duplicate(true)
	if not retired.is_empty():
		if not _move_aside_retired(retired):
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_44A358EB95E9)
			return
		any_existing = false
		for suffix: String in ["", ".tmp", ".backup"]:
			any_existing = any_existing or FileAccess.file_exists(_path + suffix)
	_storage.load_data()
	if _storage.read_only:
		_hold(str(_storage.last_error))
		return
	if not any_existing:
		return
	var selected: Variant = _storage.data.get("relay")
	var checked: Dictionary = verified_generations.get(Canonical.digest(selected), {})
	if checked.is_empty():
		checked = Proofs.validate(self, selected)
	if not checked.valid:
		_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_194A9F56B459 + str(checked.error))
		return
	for candidate: String in unreadable:
		if not _preserve_unreadable(candidate):
			_hold(PlayerCopy.LIGHTHOUSE_JOURNEY_44A358EB95E9)
			return
	_state = _storage.data.relay.duplicate(true)
	_checkpoint = checked.checkpoint.duplicate(true)
	Proofs.loaded(self)
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


## Whether a draft is saved, without checking it; draft() checks it.
func has_draft() -> bool:
	_ensure_loaded()
	return not read_only and not _state.draft.is_empty()


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


func create_live_simulation(resume_draft: bool = false) -> RefCounted:
	## This is the only producer accepted by save_live_draft. The UI owns its
	## controls; imported dictionaries still go through save_draft/replay.
	_ensure_loaded()
	if read_only or chapter_complete():
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_A50E1C712793
		return null
	var saved: Dictionary = draft() if resume_draft else {}
	if read_only: return null
	var job := next_turn_job({}, false)
	if not saved.is_empty(): job.saved = saved
	var built := build_live(job)
	_last_setup_usec = int(built.usec)
	if not built.ok:
		last_error = str(built.error)
		return null
	_live_simulation = weakref(built.simulation)
	last_error = ""
	return built.simulation


## Everything a fresh turn's setup reads. With first_turn, the turn that
## follows Save turn of that first turn: B on this same stage, replaying it.
## private gives deep copies a worker can own. create_live_simulation and a
## background prefetch both build from this, so the two cannot drift apart.
func next_turn_job(first_turn: Dictionary = {}, private: bool = true) -> Dictionary:
	_ensure_loaded()
	if read_only or chapter_complete(): return {}
	if not first_turn.is_empty() and role() != "a": return {}
	var prior: Dictionary = _state.a if first_turn.is_empty() else first_turn
	var job := {"chapter": _chapter_key, "family": _simulation, "level": _level, "stage": stage_id(), "checkpoint": _checkpoint, "prior": prior,
		"role": role() if first_turn.is_empty() else "b", "saved": {} if _chapter_key == Registry.FIRST_STEPS else {"simulation_version": int(_state.simulation_version)}, "proven": true}
	if private:
		for key: String in ["level", "checkpoint", "prior", "saved"]: job[key] = job[key].duplicate(true)
	return job


## Sets up a fresh live turn from next_turn_job. Static and free of journey
## state, so it also runs on a worker thread; it only reads the job.
static func build_live(job: Dictionary) -> Dictionary:
	var simulation: RefCounted = job.family.new()
	var started := Time.get_ticks_usec()
	var reset := Proofs.reset_live(simulation, job)
	return {"ok": reset, "simulation": simulation if reset else null, "error": "" if reset else str(simulation.error), "usec": Time.get_ticks_usec() - started}


## Takes a turn that build_live set up off the main thread from
## next_turn_job(first_turn), once Save turn has accepted that first turn. It is
## used only when its job equals what a fresh setup would read now and the
## engine is untouched; otherwise null, and the caller sets the turn up here.
func adopt_live_simulation(job: Dictionary, built: Dictionary) -> RefCounted:
	_ensure_loaded()
	if read_only or chapter_complete() or job.is_empty() or not built.get("ok", false): return null
	var simulation: RefCounted = built.get("simulation")
	var now := next_turn_job({}, false)
	if simulation == null or simulation.get_script() != _simulation or job.get("family") != _simulation or now.is_empty(): return null
	for key: String in ["chapter", "stage", "role"]:
		if str(job.get(key)) != str(now[key]): return null
	for key: String in ["level", "checkpoint", "prior", "saved"]:
		if not job.get(key) is Dictionary or not Canonical.same(job[key], now[key]): return null
	if int(simulation.get("tick")) != 0 or not str(simulation.get("error")).is_empty() or simulation.get("role") != now.role or not Canonical.same(simulation.get("_checkpoint"), _checkpoint) or not Canonical.same(simulation.get("_prior"), _state.a):
		return null
	_last_setup_usec = int(built.get("usec", 0))
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
	if _chapter_key != Registry.FIRST_STEPS and recording.get("simulation_version") != _state.simulation_version:
		last_error = "Unsupported recording version."
		return false
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
	var derived := _checkpoint
	if role() == "a":
		next.a = recording.duplicate(true)
	else:
		next.pairs.append({"a": next.a.duplicate(true), "b": recording.duplicate(true)})
		next.a = {}
		# The finished pair's checkpoint comes from the check just made, the
		# same replay the full derivation would run again.
		var built := _next_checkpoint(next.pairs[-1].a, next.pairs[-1].b, checked)
		if not built.get("valid", false):
			last_error = str(built.get("error", ""))
			return false
		derived = built.checkpoint
	next.draft = {}
	# Earlier pairs and the current checkpoint were proven when they were
	# loaded or accepted; every structural and version rule still runs.
	var verdict := _validate_state(next, {"pairs": next.pairs.size(), "checkpoint": derived, "a_verified": role() == "a"})
	if not verdict.valid:
		last_error = str(verdict.error)
		return false
	var saved := _write_verified_state(next, verdict.checkpoint)
	if saved:
		_live_simulation = null
		_draft_replay_verified = true
	return saved


## The review's check of a finished turn. Shares its result with the Save that
## follows, so the turn is replayed once.
func verify_turn(recording: Dictionary) -> Dictionary:
	_ensure_loaded()
	if read_only:
		return _invalid(last_error)
	return _verify_current(recording)


func _verify_current(recording: Dictionary) -> Dictionary:
	if _chapter_key != Registry.FIRST_STEPS and recording.get("simulation_version") != _state.simulation_version:
		return _invalid("Unsupported recording version.")
	if recording.get("role") != role() or recording.get("stage_id") != stage_id():
		return {"valid": false, "error": PlayerCopy.LIGHTHOUSE_JOURNEY_1E2666F7F555}
	var key := "|".join(PackedStringArray([_chapter_key, str(_state.simulation_version), str(_checkpoint.get("checkpoint_hash", "")), Canonical.digest(_state.a), Canonical.digest(recording)]))
	if _verified_turns.has(key):
		return _verified_turns[key].duplicate(true)
	var started := Time.get_ticks_usec()
	var checked := _verify_on_checkpoint(recording)
	_last_check_usec = Time.get_ticks_usec() - started
	if checked.get("valid", false):
		_verified_turns[key] = checked.duplicate(true)
		while _verified_turns.size() > VERIFIED_TURNS:
			_verified_turns.erase(_verified_turns.keys()[0])
	return checked


## The family's replay check of one turn from this journey's checkpoint. Load
## and accept already proved that checkpoint and its chain of earlier pairs,
## so only that chain is skipped; the recording and its partner turn are
## replayed exactly as the public verify_recording replays them.
## True while simulation is the live engine this journey last set up; any
## accepted turn, saved draft, restart or reload releases it.
func is_live_simulation(simulation: RefCounted) -> bool:
	return simulation != null and _live_simulation != null and _live_simulation.get_ref() == simulation


## The longer of the last turn check and next-turn setup, in microseconds.
func expected_wait_usec() -> int:
	return maxi(_last_check_usec, _last_setup_usec)


func _verify_on_checkpoint(recording: Dictionary) -> Dictionary:
	if _has_static("_verify_raw"):
		return _simulation._verify_raw(_level, recording, _checkpoint, _state.a)
	if _has_static("_proof") and _has_static("_record_version"):
		return _simulation._proof(_simulation._record_version(recording))._verify_raw(_level, recording, _checkpoint, _state.a)
	return _simulation.verify_recording(_level, recording, _checkpoint, _state.a)


## The checkpoint after a finished pair, built from the B check already made
## from this journey's checkpoint, as derive_checkpoint builds it.
func _next_checkpoint(first: Dictionary, second: Dictionary, checked: Dictionary) -> Dictionary:
	if first.get("role") != "a" or second.get("role") != "b" or not checked.get("snapshot", {}).get("complete", false):
		return _simulation.derive_checkpoint(_level, _checkpoint, first, second)
	if _has_static("_build_checkpoint"):
		return {"valid": true, "error": "", "checkpoint": _simulation._build_checkpoint(_level, _checkpoint, first, second, checked.snapshot)}
	if _has_static("_proof") and _has_static("_record_version"):
		return {"valid": true, "error": "", "checkpoint": _simulation._proof(_simulation._record_version(first))._build_checkpoint(_level, _checkpoint, first, second, checked.snapshot)}
	return _simulation.derive_checkpoint(_level, _checkpoint, first, second)


func _has_static(method: String) -> bool:
	if _family_statics.is_empty():
		_family_statics[""] = true
		for entry: Dictionary in _simulation.get_script_method_list():
			_family_statics[str(entry.name)] = true
	return _family_statics.has(method)


func can_restart() -> bool:
	# UI eligibility only: observing a confirmation must never load or write.
	if not _loaded or read_only: return false
	return not _state.pairs.is_empty() or not _state.a.is_empty() or not _state.draft.is_empty() or _restart_rules_version() != Registry.preferred_rules(_chapter_key)

func simulation_version() -> int:
	return int(_state.simulation_version) if _loaded and not read_only else -1

func restart_upgrades_rules() -> bool:
	return can_restart() and _restart_rules_version() != Registry.preferred_rules(_chapter_key)

func _restart_rules_version() -> int:
	var preferred := Registry.preferred_rules(_chapter_key)
	var current := simulation_version()
	if _chapter_key == Registry.FIRST_STEPS:
		# First Steps intentionally keeps its authored envelope while each new
		# pair chooses fresh rules. Only an active old A/draft needs an escape.
		var active: Dictionary = _state.a if not _state.a.is_empty() else _state.draft
		current = int(active.get("simulation_version", preferred))
	return current

func fork_from_stage(index: int) -> bool:
	_ensure_loaded()
	if read_only: return false
	if index < 0 or index >= _level.stages.size() or (index == 0 and not can_restart()) or (index > 0 and index >= _state.pairs.size()):
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_66C3BEF32753
		return false
	var next := _state.duplicate(true)
	next.pairs = _state.pairs.slice(0, index).duplicate(true)
	next.a = {}
	next.draft = {}
	# Only a deliberate whole-chapter restart can change its rules. A later
	# checkpoint must keep the retained prefix's pin; First Steps already
	# chooses fresh rules per pair without changing its historical envelope.
	if index == 0 and _chapter_key != Registry.FIRST_STEPS:
		next.simulation_version = Registry.preferred_rules(_chapter_key)
	var checked := _validate_state(next)
	if not checked.valid:
		last_error = str(checked.error)
		return false
	last_error = Archive.save(_path, "relay", _state, MAX_SAVE_BYTES, MAX_ARCHIVED_ATTEMPTS)
	if not last_error.is_empty(): return false
	if not _write_verified_state(next, checked.checkpoint): return false
	_live_simulation = null
	_draft_replay_verified = true
	return true

## Solo "Redo my previous turn": what one step back would take back, for the
## offer only. Like can_restart it never loads or writes. "first_turn" clears
## this stage's accepted first turn; "stage" reopens the last saved stage at
## its second turn, with its first turn restored. {} before any turn is saved.
## The remaining fields let redo_previous refuse an offer that went stale.
## A stage is not offered while the archive has no room for the attempt it
## would keep.
func redo_plan() -> Dictionary:
	if not _loaded or read_only: return {}
	var count: int = _state.pairs.size()
	var first_turn: bool = not _state.a.is_empty()
	if not first_turn and count == 0: return {}
	if not first_turn and Archive.full(_path, _state, MAX_ARCHIVED_ATTEMPTS): return {}
	var taken: Dictionary = _state.a if first_turn else _state.pairs[-1].b
	return {"kind": "first_turn" if first_turn else "stage", "stage_index": count if first_turn else count - 1, "pairs": count,
		"checkpoint": str(_checkpoint.get("checkpoint_hash", "")), "turn": str(taken.get("recording_hash", "")), "drops_draft": not _state.draft.is_empty()}

## Takes back exactly the turn redo_plan() named, and only while it still names
## it. Rules, earlier pairs and keepsakes stay as they are. Reopening a stage
## keeps the attempt it replaces as an archive first, as a checkpoint retry
## does; a failed check, archive or write leaves the journey as it was.
func redo_previous(expected: Dictionary) -> bool:
	_ensure_loaded()
	if read_only: return false
	var plan := redo_plan()
	if plan.is_empty() or plan != expected:
		last_error = PlayerCopy.LIGHTHOUSE_JOURNEY_66C3BEF32753
		return false
	var next := _state.duplicate(true)
	next.draft = {}
	var checked: Dictionary
	if plan.kind == "first_turn":
		next.a = {}
		# The kept pairs and checkpoint are already proven; nothing is replayed.
		checked = _validate_state(next, {"pairs": next.pairs.size(), "checkpoint": _checkpoint})
	else:
		next.a = next.pairs.pop_back().a
		# This exact state was proven when its first turn was saved; the
		# kept chain and the restored first turn replay in full only when
		# that proof is no longer remembered or does not hold.
		var trusted := Proofs.recall(self, next)
		if not trusted.is_empty(): checked = _validate_state(next, trusted)
		if not checked.get("valid", false): checked = _validate_state(next)
	if not checked.valid:
		last_error = str(checked.error)
		return false
	if plan.kind == "stage":
		last_error = Archive.save(_path, "relay", _state, MAX_SAVE_BYTES, MAX_ARCHIVED_ATTEMPTS)
		if not last_error.is_empty(): return false
	if not _write_verified_state(next, checked.checkpoint): return false
	_live_simulation = null
	_draft_replay_verified = true
	return true

func archived_attempts() -> Array[Dictionary]:
	_ensure_loaded()
	if read_only: return []
	var retired: Array = RETIRED_DEFINITIONS.get(_chapter_key, [])
	return Archive.list_attempts(_path, "relay", MAX_SAVE_BYTES).filter(func(attempt: Dictionary) -> bool: return str(attempt.get("definition_hash", "")) not in retired)

func archived_pairs(id: String) -> Array:
	_ensure_loaded()
	if read_only: return []
	var state := Archive.load_attempt(_path, "relay", id, MAX_SAVE_BYTES)
	var checked := _validate_state(state)
	if not checked.valid:
		last_error = str(checked.error)
		return []
	last_error = ""
	return state.pairs.duplicate(true)


func _write_verified_state(next: Dictionary, derived_checkpoint: Dictionary) -> bool:
	# The accepted role/checkpoint changes only after the recoverable transport
	# succeeds. A failed write leaves the current A/draft and checkpoint intact.
	if not _storage.update_values({"relay": next.duplicate(true)}):
		last_error = str(_storage.last_error)
		return false
	_state = next.duplicate(true)
	_checkpoint = derived_checkpoint.duplicate(true)
	last_error = ""
	Keepsakes.record_solo_prefix(_chapter_key, _state.pairs.size())
	Proofs.remember(self, _state, _checkpoint)
	return true


## With trusted, its checkpoint stands for every listed pair and an A already
## checked from it is not replayed again; all structural and version rules
## still run. Only accept passes it, for pairs it has just proven.
func _validate_state(value: Variant, trusted: Dictionary = {}) -> Dictionary:
	if not value is Dictionary or not _exact_keys(value, STATE_KEYS):
		return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_E45D0DDEDD2F)
	if value.schema_version != _level.schema_version or not Registry._integer(value.simulation_version) or int(value.simulation_version) not in Registry.supported_rules(_chapter_key) or value.level_id != _level.id or value.level_version != _level.version or value.definition_hash != Canonical.digest(_level):
		return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_3277AC1A21BD)
	if not value.pairs is Array or value.pairs.size() > _level.stages.size() or not value.a is Dictionary or not value.draft is Dictionary:
		return _invalid("Malformed stage history.")
	var derived := Registry.initial_checkpoint(_chapter_key)
	var proven: bool = not trusted.is_empty() and int(trusted.get("pairs", -1)) == value.pairs.size()
	for pair: Variant in value.pairs:
		if not pair is Dictionary or not _exact_keys(pair, ["a", "b"]) or not pair.a is Dictionary or not pair.b is Dictionary:
			return _invalid("Malformed completed pair.")
		if _chapter_key != Registry.FIRST_STEPS and (pair.a.get("simulation_version") != value.simulation_version or pair.b.get("simulation_version") != value.simulation_version): return _invalid("Unsupported recording version.")
		if proven: continue
		var checked: Dictionary = _simulation.derive_checkpoint(_level, derived, pair.a, pair.b)
		if not checked.valid:
			return _invalid(str(checked.error))
		derived = checked.checkpoint
	if proven:
		derived = trusted.checkpoint
	if str(derived.next_stage_id).is_empty():
		if not value.a.is_empty() or not value.draft.is_empty():
			return _invalid(PlayerCopy.RELAY_JOURNEY_0B5E838FD37D)
		return {"valid": true, "error": "", "checkpoint": derived}
	if not value.a.is_empty():
		if _chapter_key != Registry.FIRST_STEPS and value.a.get("simulation_version") != value.simulation_version: return _invalid("Unsupported recording version.")
		var first: Dictionary = {"valid": true, "snapshot": {"can_commit": true}} if proven and trusted.get("a_verified", false) else _simulation.verify_recording(_level, value.a, derived)
		if value.a.get("role") != "a" or not first.valid or not first.get("snapshot", {}).get("can_commit", false):
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_1393CFB1623B)
	if not value.draft.is_empty():
		if _chapter_key != Registry.FIRST_STEPS and value.draft.get("simulation_version") != value.simulation_version: return _invalid("Unsupported recording version.")
		var expected_role := "a" if value.a.is_empty() else "b"
		if value.draft.get("role") != expected_role:
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_2A6C3206C0FC)
		var rehearsal: Dictionary = Proofs.rehearse(self, value.draft, derived, value.a) if proven else _simulation.verify_recording(_level, value.draft, derived, value.a)
		if not rehearsal.valid:
			return _invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_3E836B83D99B + str(rehearsal.error))
	return {"valid": true, "error": "", "checkpoint": derived}


func _empty_state() -> Dictionary:
	return {"schema_version": _level.schema_version, "simulation_version": _level.simulation_version if _chapter_key == Registry.FIRST_STEPS else Registry.preferred_rules(_chapter_key), "level_id": _level.id, "level_version": _level.version,
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


func _retired(value: Variant) -> bool:
	return value is Dictionary and value.get("level_id") == _level.id and value.get("level_version") == _level.version and str(value.get("definition_hash", "")) in RETIRED_DEFINITIONS.get(_chapter_key, [])


## Renames each retired generation, and every archived attempt of a retired
## definition, to a recovery name nothing reads. Nothing is overwritten or
## deleted unread; a rename that cannot be confirmed holds the journey.
func _move_aside_retired(generations: Array[String]) -> bool:
	for candidate: String in generations:
		if not _rename_aside(candidate, candidate + ".retired-"):
			return false
	var prefix := _path.get_file() + ".attempt-"
	for filename: String in DirAccess.get_files_at(_path.get_base_dir()):
		if not filename.begins_with(prefix) or not filename.ends_with(".json"): continue
		var id := filename.trim_prefix(prefix).trim_suffix(".json")
		if not _retired(Archive.load_attempt(_path, "relay", id, MAX_SAVE_BYTES)): continue
		if not _rename_aside(_path.get_base_dir().path_join(filename), _path + ".retired-attempt-"):
			return false
	return true

func _rename_aside(source: String, stem: String) -> bool:
	var digest := FileAccess.get_sha256(source)
	if digest.is_empty():
		return false
	var aside := stem + digest + ".json"
	if FileAccess.file_exists(aside):
		return FileAccess.get_sha256(aside) == digest and DirAccess.remove_absolute(source) == OK
	return DirAccess.rename_absolute(source, aside) == OK and FileAccess.get_sha256(aside) == digest


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
