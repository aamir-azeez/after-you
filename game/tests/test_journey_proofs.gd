extends SceneTree
## Opening a solo chapter reuses what this device already proved about the save.
## The remembered checkpoint, the stage-by-stage check of a save not yet
## remembered, and the live turn set up from the proven checkpoint must all be
## byte-identical (var_to_bytes, so int/float and key order count) to the full
## public chain check and the family's own reset. Changed bytes, a damaged
## proof file and a draft are never trusted.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://journey-proofs-test-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	Proofs.directory = directory.path_join("proofs")
	# [chapter, stage prefixes to open, roles]: both runtime families, and a
	# chain of earlier stages.
	var covered := 0
	# [completed stages, role]; a finished chapter (2, "a") proves its later
	# stage from the checkpoint built just before it.
	for spec: Array in [
		[Registry.WISHING_WELL, [[0, "a"], [0, "b"], [1, "b"], [2, "a"]]],
		# One Tide replay costs about a second; its first stage covers its family.
		[Registry.TURN_OF_THE_TIDE, [[0, "b"]]],
		[Registry.LONG_WAY_HOME_V2, [[1, "b"], [2, "a"]]],
	]:
		if not Registry.keys().has(str(spec[0])): continue
		var started := Time.get_ticks_msec()
		if _chapter(str(spec[0]), spec[1]): covered += 1
		print("%s: %d ms" % [spec[0], Time.get_ticks_msec() - started])
	_check(covered == 3, "Wishing Well, Turn of the Tide and Long Way Home @2 are covered (%d)" % covered)
	var started := Time.get_ticks_msec()
	_drafts_and_damage()
	_backup_shares_stages()
	_written_turns_are_remembered()
	print("drafts, damage and backups: %d ms" % (Time.get_ticks_msec() - started))
	print("JOURNEY PROOFS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(chapter: String, openings: Array) -> bool:
	for opening: Array in openings:
			var prefix: int = opening[0]
			var role: String = opening[1]
			var label := "%s stage %d %s" % [chapter, prefix + 1, role]
			var state := _state(chapter, prefix, role)
			if state.is_empty():
				_check(false, label + ": fixtures exist")
				return false
			var journey := Journey.new(_path(chapter, label), null, chapter)
			journey.load_data()
			# The full public chain check, as every open ran it before.
			var full: Dictionary = journey._validate_state(state)
			_check(full.get("valid", false), label + ": the fixtures pass the full chain check")
			if not full.get("valid", false): return false
			# The stage-by-stage check itself, with nothing remembered.
			_forget()
			var linear: Dictionary = Proofs._prove(journey, state)
			_check(not linear.is_empty() and _bytes(linear.get("checkpoint", {})) == _bytes(full.checkpoint), label + ": the stage-by-stage check builds the full check's checkpoint bytes")
			var path := _write(chapter, state)
			_forget()
			var cold := Journey.new(path, null, chapter)
			cold.load_data()
			_check(not cold.read_only and _bytes(cold._checkpoint) == _bytes(full.checkpoint), label + ": a save not yet remembered is checked stage by stage to the same checkpoint bytes")
			var anything: bool = not state.pairs.is_empty() or not state.a.is_empty()
			_check(Proofs.recall(cold, state).is_empty() != anything, label + (": that check is remembered" if anything else ": a journey with no saved turn has nothing to remember"))
			# A new process: only the file holds the proof.
			Proofs._chapters.clear()
			var warm := Journey.new(path, null, chapter)
			warm.load_data()
			_check(not warm.read_only and _bytes(warm._checkpoint) == _bytes(full.checkpoint) and _bytes(warm._state) == _bytes(cold._state), label + ": reopening reuses the remembered proof with the same bytes")
			# The refusals use the full reset and run once, on a later stage.
			if not warm.chapter_complete(): _live_equals_reset(warm, label, chapter == Registry.WISHING_WELL and prefix == 1 and role == "b")
	return true

## The live turn set up from the proven checkpoint equals the family's own
## reset: every script variable right after setup, and the whole next turn.
func _live_equals_reset(journey: RefCounted, label: String, refusals: bool) -> void:
	var job: Dictionary = journey.next_turn_job({}, true)
	_check(job.get("proven", false) == true, label + ": a journey's next turn is marked proven")
	var trusted: RefCounted = job.family.new()
	var public: RefCounted = job.family.new()
	var reset_ok: bool = Registry.reset_simulation(public, str(job.chapter), job.level, str(job.stage), job.checkpoint, job.prior, str(job.role), job.saved)
	_check(Proofs.reset_live(trusted, job) and reset_ok, label + ": both setups succeed")
	_check(_bytes(_dump(trusted)) == _bytes(_dump(public)), label + ": the setup from the proven checkpoint equals the full reset, variable for variable")
	var built: Dictionary = Journey.build_live(job)
	_check(built.get("ok", false) and _bytes(_dump(built.simulation)) == _bytes(_dump(public)), label + ": build_live uses it")
	var recording := _fixture(str(job.chapter), str(job.stage), str(job.role))
	for input: Dictionary in job.family.expand_recording_inputs(recording):
		trusted.step(input)
		public.step(input)
	_check(_bytes(trusted.export_recording()) == _bytes(public.export_recording()) and trusted.state_hash() == public.state_hash() and _bytes(_dump(trusted)) == _bytes(_dump(public)), label + ": the whole turn played on each ends identically")
	# Negative control: the comparison sees a setup that differs in one value.
	var wrong: RefCounted = job.family.new()
	Proofs.reset_live(wrong, job)
	wrong.simulation_version = int(wrong.simulation_version) + 100
	_check(_bytes(_dump(wrong)) != _bytes(_dump(public)), label + ": a setup that differs in one value is told apart")
	# Unproven jobs and refused inputs take the family's own reset (slow on
	# the long chapters, so checked on one).
	if not refusals: return
	if str(job.role) == "b":
		# The proven path really skips the partner turn's replay: a damaged
		# partner turn is refused by the full reset only.
		var damaged := job.duplicate(true)
		damaged.prior.final_state_hash = "0".repeat(64)
		var full_reset: RefCounted = job.family.new()
		var proven_reset: RefCounted = job.family.new()
		_check(not Registry.reset_simulation(full_reset, str(job.chapter), damaged.level, str(job.stage), damaged.checkpoint, damaged.prior, "b", damaged.saved) and Proofs.reset_live(proven_reset, damaged), label + ": the proven setup does not replay the partner turn again")
	var plain := job.duplicate(true)
	plain.erase("proven")
	var unproven: RefCounted = job.family.new()
	var fresh: RefCounted = job.family.new()
	Registry.reset_simulation(fresh, str(job.chapter), job.level, str(job.stage), job.checkpoint, job.prior, str(job.role), job.saved)
	_check(Proofs.reset_live(unproven, plain) and _bytes(_dump(unproven)) == _bytes(_dump(fresh)), label + ": an unproven job takes the full reset")
	var mismatched := job.duplicate(true)
	mismatched.stage = "no-such-stage"
	var refused: RefCounted = job.family.new()
	_check(not Proofs.reset_live(refused, mismatched) and not str(refused.error).is_empty(), label + ": a job for another stage is refused by the full reset")

## Drafts are replayed on every load; changed bytes and damaged proofs are
## checked in full, with the same verdict as before.
func _drafts_and_damage() -> void:
	var chapter := Registry.WISHING_WELL
	var level := Registry.definition(chapter)
	var label := "Wishing Well stage 1 b"
	var state := _state(chapter, 0, "b")
	var journey := Journey.new(_path(chapter, "damage"), null, chapter)
	journey.load_data()
	var full: Dictionary = journey._validate_state(state)
	# A draft is never part of what is remembered.
	var with_draft := state.duplicate(true)
	with_draft.draft = _fixture(chapter, str(level.stages[0].id), "b")
	var drafted: Dictionary = journey._validate_state(with_draft)
	_check(drafted.get("valid", false), label + ": a finished turn is a valid draft for the full check")
	_forget()
	var cold := Journey.new(_write(chapter, with_draft), null, chapter)
	cold.load_data()
	_check(not cold.read_only and _bytes(cold._checkpoint) == _bytes(full.checkpoint) and not cold.draft().is_empty(), label + ": a save with a draft opens with the same checkpoint")
	_check(Proofs.recall(cold, state).get("checkpoint", {}).size() > 0 and Proofs._key(cold, state) == Proofs._key(cold, with_draft), label + ": the draft is left out of what is remembered")
	var bad_draft := with_draft.duplicate(true)
	bad_draft.draft.final_state_hash = "0".repeat(64)
	var expected: Dictionary = journey._validate_state(bad_draft)
	var drafted_load := Journey.new(_write(chapter, bad_draft), null, chapter)
	drafted_load.load_data()
	_check(not expected.get("valid", true) and drafted_load.read_only and drafted_load.last_error.ends_with(str(expected.error)), label + ": a damaged draft is still refused when its turns are remembered (%s)" % drafted_load.last_error)
	# Changed accepted bytes: nothing remembered applies, the full verdict stands.
	var tampered := state.duplicate(true)
	tampered.a.final_state_hash = "0".repeat(64)
	var refused: Dictionary = journey._validate_state(tampered)
	_check(Proofs.recall(journey, tampered).is_empty(), label + ": a changed turn finds nothing remembered")
	var changed := Journey.new(_write(chapter, tampered), null, chapter)
	changed.load_data()
	_check(not refused.get("valid", true) and changed.read_only and changed.last_error.ends_with(str(refused.error)), label + ": a changed turn is refused as the full check refuses it (%s)" % changed.last_error)
	# A remembered checkpoint that no longer matches its digest is ignored.
	var path := _write(chapter, state)
	Proofs._mutex.lock()
	var entries: Array = Proofs._entries(chapter)
	Proofs._mutex.unlock()
	var found := false
	for entry: Array in entries:
		if entry[0] == Proofs._key(journey, state):
			found = true
			entry[2].stage_index = int(entry[2].stage_index) + 1
	_check(found and Proofs.recall(journey, state).is_empty(), label + ": a remembered checkpoint whose bytes changed is ignored")
	var rechecked := Journey.new(path, null, chapter)
	rechecked.load_data()
	_check(not rechecked.read_only and _bytes(rechecked._checkpoint) == _bytes(full.checkpoint), label + ": the save is then checked again and opens")
	# A damaged proof file is ignored as a whole.
	var file := FileAccess.open(Proofs._path(chapter), FileAccess.WRITE)
	file.store_buffer("not a proof file".to_utf8_buffer())
	file.close()
	Proofs._chapters.clear()
	_check(Proofs.recall(journey, state).is_empty(), label + ": a damaged proof file is ignored")
	var reopened := Journey.new(path, null, chapter)
	reopened.load_data()
	_check(not reopened.read_only and _bytes(reopened._checkpoint) == _bytes(full.checkpoint), label + ": the save still opens after a damaged proof file")
	Proofs._chapters.clear()
	_check(not Proofs.recall(journey, state).is_empty(), label + ": the proof file is rewritten by that open")
	# Another build's rules never inherit a proof.
	var other := Proofs._key(journey, state)
	var other_chapter := Journey.new(_path(Registry.HIGH_AND_LOW, "other"), null, Registry.HIGH_AND_LOW)
	_check(not other.is_empty() and Proofs._key(other_chapter, state) != other, label + ": a proof is bound to its chapter and rules")

## A save and its backup share their earlier stages: each stage is replayed
## once, and both generations get the full check's checkpoint bytes.
func _backup_shares_stages() -> void:
	var chapter := Registry.WISHING_WELL
	var label := "Wishing Well save and backup"
	var older := _state(chapter, 1, "a")
	var newer := _state(chapter, 1, "b")
	var checker := Journey.new(_path(chapter, "backup-check"), null, chapter)
	var expected_older: Dictionary = checker._validate_state(older)
	var expected_newer: Dictionary = checker._validate_state(newer)
	var path := _path(chapter, "backup")
	var writer := Journey.new(path, null, chapter)
	writer._storage.load_data()
	_check(writer._storage.update_values({"relay": older.duplicate(true)}) and writer._storage.update_values({"relay": newer.duplicate(true)}) and FileAccess.file_exists(path + ".backup"), label + ": a save with an older backup is written")
	_forget()
	var opened := Journey.new(path, null, chapter)
	opened.load_data()
	_check(not opened.read_only and _bytes(opened._checkpoint) == _bytes(expected_newer.checkpoint), label + ": the save opens with the full check's checkpoint")
	_check(Proofs._stages.size() == 1, label + ": their shared first stage was proved once (%d)" % Proofs._stages.size())
	var remembered_older: Dictionary = Proofs.recall(opened, older)
	_check(_bytes(remembered_older.get("checkpoint", {})) == _bytes(expected_older.checkpoint) and _bytes(Proofs.recall(opened, newer).get("checkpoint", {})) == _bytes(expected_newer.checkpoint), label + ": both generations are remembered with the full check's bytes")

## A turn this device saves is remembered at once, so the next open of that
## save replays nothing.
func _written_turns_are_remembered() -> void:
	var chapter := Registry.WISHING_WELL
	var level := Registry.definition(chapter)
	_forget()
	var journey := Journey.new(_path(chapter, "written"), null, chapter)
	journey.load_data()
	_check(journey.accept_recording(_fixture(chapter, str(level.stages[0].id), "a")), "Wishing Well: the first turn is saved")
	_check(not Proofs.recall(journey, journey._state).is_empty(), "Wishing Well: a saved first turn is remembered")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(journey._path))
	_check(not Proofs.recall(journey, raw.relay).is_empty(), "Wishing Well: the saved file's own bytes find that proof")

func _state(chapter: String, prefix: int, role: String) -> Dictionary:
	var level := Registry.definition(chapter)
	var journey := Journey.new(_path(chapter, "state"), null, chapter)
	var state: Dictionary = journey._empty_state()
	for index in range(prefix):
		var stage := str(level.stages[index].id)
		var first := _fixture(chapter, stage, "a")
		var second := _fixture(chapter, stage, "b")
		if first.is_empty() or second.is_empty(): return {}
		state.pairs.append({"a": first, "b": second})
	if role == "b":
		state.a = _fixture(chapter, str(level.stages[prefix].id), "a")
		if state.a.is_empty(): return {}
	return state

## A fresh journal holding state, written by the storage transport alone, so
## nothing is remembered on this write and there is no older generation.
func _write(chapter: String, state: Dictionary) -> String:
	var path := _path(chapter, "save-" + Crypto.new().generate_random_bytes(4).hex_encode())
	var journey := Journey.new(path, null, chapter)
	journey._storage.load_data()
	_check(journey._storage.update_values({"relay": state.duplicate(true)}), "A fixture save is written")
	return path

func _forget() -> void:
	Proofs._chapters.clear()
	Proofs._stages.clear()
	Proofs._last_remembered.clear()
	if not DirAccess.dir_exists_absolute(Proofs.directory): return
	for name: String in DirAccess.get_files_at(Proofs.directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs.directory.path_join(name)))

func _path(chapter: String, label: String) -> String:
	return directory.path_join((chapter + "-" + label).validate_filename() + ".json")

func _fixture(chapter: String, stage: String, role: String) -> Dictionary:
	var level := Registry.definition(chapter)
	var prefixes := [""]
	if int(level.get("version", 1)) > 1: prefixes.push_front("%s-v%d-" % [level.id, int(level.version)])
	for folder: String in ["cooperative", "journey"]:
		for prefix: String in prefixes:
			var path := "res://tests/fixtures/%s/%s%s-%s.json" % [folder, prefix, stage, role]
			if FileAccess.file_exists(path): return JSON.parse_string(FileAccess.get_file_as_string(path))
	return {}

## Every script variable, with a partner engine expanded in place.
static func _dump(object: Object, depth: int = 0) -> Dictionary:
	var result := {}
	for property: Dictionary in object.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0: continue
		var value: Variant = object.get(property.name)
		if value is Object: value = _dump(value, depth + 1) if is_instance_valid(value) and depth < 2 else null
		result[property.name] = value
	return result

static func _bytes(value: Variant) -> PackedByteArray:
	return var_to_bytes(value)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
