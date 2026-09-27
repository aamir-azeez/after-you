extends SceneTree
## Explicit local checkpoint-zero restart upgrades rules only after archiving
## the complete retained evidence. Shared rooms have a separate fork API.
const Journey = preload("res://services/relay_journey.gd")
const Storage = preload("res://services/local_save.gd")
const Archive = preload("res://services/attempt_archive.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var checks := 0
var failures := 0
var directory := ""
var fixture_hashes: Dictionary = {}

class FailingStorage extends "res://services/local_save.gd":
	var reject_write := false
	func update_values(values: Dictionary, erase_keys: Array = []) -> bool:
		if reject_write:
			last_error = "Injected restart write failure."
			return false
		return super.update_values(values, erase_keys)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://comfort-restart-" + Crypto.new().generate_random_bytes(8).hex_encode()
	if not _check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create isolated real-file journals"):
		_finish()
		return
	for spec: Dictionary in [
		{"chapter":Registry.RELAY, "folder":"v2", "rules":2},
		{"chapter":Registry.ROLLING_HOME, "folder":"cooperative", "rules":6},
		{"chapter":Registry.CONSERVATORY, "folder":"journey", "rules":7},
	]:
		var state := _completed_state(str(spec.chapter), str(spec.folder), int(spec.rules))
		_full_restart(str(spec.chapter), state)
		_later_checkpoint(str(spec.chapter), state)
		_empty_restart(str(spec.chapter), state)
		for kind: String in ["draft_a", "accepted_a", "draft_b"]:
			_unfinished_restart(str(spec.chapter), state, kind)
		if spec.chapter == Registry.RELAY:
			_write_failure(str(spec.chapter), state)
	_first_steps_unfinished()
	_eligibility_holds()
	for path: String in fixture_hashes:
		_check(FileAccess.get_sha256(path) == fixture_hashes[path], "Published fixture bytes remain untouched: " + path.get_file())
	_finish()

func _completed_state(chapter: String, folder: String, rules: int) -> Dictionary:
	var level := Registry.definition(chapter)
	var pairs: Array = []
	for stage: Dictionary in level.stages:
		pairs.append({"a":_fixture(folder, str(stage.id)+"-a"), "b":_fixture(folder, str(stage.id)+"-b")})
	return {"schema_version":level.schema_version, "simulation_version":rules,
		"level_id":level.id, "level_version":level.version, "definition_hash":Canonical.digest(level),
		"pairs":pairs, "a":{}, "draft":{}}

func _full_restart(chapter: String, retained: Dictionary) -> void:
	var path := directory + "/" + chapter.validate_filename() + "-full.json"
	if not _seed(path, retained): return
	var old_bytes := FileAccess.get_file_as_string(path)
	var journey := Journey.new(path, null, chapter)
	journey.load_data()
	if not _check(not journey.read_only and journey.chapter_complete(), chapter + " verifies the complete published old chain"):
		return
	_check(FileAccess.get_file_as_string(path) == old_bytes, "Opening old completion does not migrate any saved bytes")
	if not _check(journey.fork_from_stage(0), chapter + " accepts explicit full restart"):
		return
	var id := Canonical.digest(retained)
	var archive_path := path + ".attempt-" + id + ".json"
	var archive_hash := FileAccess.get_sha256(archive_path)
	_check(Canonical.same(Archive.load_attempt(path, "relay", id, Journey.MAX_SAVE_BYTES), retained), "Full restart archives every original recording and rule pin")
	_check(Canonical.same(journey.archived_pairs(id), retained.pairs), "Archived old chain still passes native semantic replay after upgrade")
	_check(journey._state.simulation_version == 8 and journey.pairs().is_empty() and journey.prior_recording().is_empty() and journey.draft().is_empty(), "Only the new empty active chapter adopts rules8")
	_check(journey.stage_id() == Registry.definition(chapter).stages[0].id and journey.role() == "a", "Full restart returns to actual first source stage")
	var simulation: RefCounted = journey.create_live_simulation(false)
	if not _check(simulation != null, "New active chapter produces a real native engine"): return
	_check(simulation.simulation_version == 8, "Real new engine uses8 rather than only relabeling the journal")
	_step_prefix(simulation, chapter, retained.pairs[0].a)
	if not _check(journey.save_live_draft(simulation), "New8 rehearsal persists through the ordinary live save API"): return
	var draft: Dictionary = simulation.export_recording()
	var cold := Journey.new(path, null, chapter)
	cold.load_data()
	if not _check(not cold.read_only and Canonical.same(cold.draft(), draft), "New8 draft and old backup survive real JSON cold restore"): return
	_check(cold.can_restart() and not cold.restart_upgrades_rules(), "Already-fresh8 saved progress never advertises the old-rules upgrade")
	var resumed: RefCounted = cold.create_live_simulation(true)
	_replay_draft(resumed, chapter, draft)
	_check(resumed != null and Canonical.same(resumed.export_recording(), draft), "Resumed new8 native replay retains exact draft evidence")
	_check(FileAccess.get_sha256(archive_path) == archive_hash, "New rehearsal and cold restore never rewrite the immutable old archive")

func _later_checkpoint(chapter: String, retained: Dictionary) -> void:
	var path := directory + "/" + chapter.validate_filename() + "-later.json"
	if not _seed(path, retained): return
	var journey := Journey.new(path, null, chapter)
	journey.load_data()
	if not _check(not journey.read_only and journey.fork_from_stage(1), chapter + " can retry its retained later checkpoint"): return
	_check(journey._state.simulation_version == retained.simulation_version and Canonical.same(journey.pairs(), [retained.pairs[0]]), "Later checkpoint keeps both old rule pin and exact accepted prefix")
	var simulation: RefCounted = journey.create_live_simulation(false)
	if not _check(simulation != null, "Retained later checkpoint creates real source engine"): return
	_check(simulation.simulation_version == retained.simulation_version, "Fresh source rehearsal at later checkpoint retains old rules")
	_step_prefix(simulation, chapter, retained.pairs[1].a)
	if not _check(journey.save_live_draft(simulation), "Old source rehearsal remains saveable"): return
	var source_draft: Dictionary = simulation.export_recording()
	var cold := Journey.new(path, null, chapter)
	cold.load_data()
	if not _check(not cold.read_only and Canonical.same(cold.draft(), source_draft), "Cold Resume keeps exact old source draft"): return
	var resumed: RefCounted = cold.create_live_simulation(true)
	_replay_draft(resumed, chapter, source_draft)
	_check(resumed != null and Canonical.same(resumed.export_recording(), source_draft), "Native Resume neither upgrades nor truncates the old source")
	var retried: RefCounted = cold.create_live_simulation(false)
	_check(retried != null and retried.simulation_version == retained.simulation_version, "Current-stage Retry without checkpoint-zero action stays on retained rules")
	if not _check(cold.accept_recording(retained.pairs[1].a), "Original second source is still accepted against retained first pair"): return
	var receiver: RefCounted = cold.create_live_simulation(false)
	if not _check(receiver != null, "Accepted old source creates a real matching receiver"): return
	_check(receiver.simulation_version == retained.simulation_version, "B follows exact old accepted A despite preferred8")
	_step_prefix(receiver, chapter, retained.pairs[1].b)
	if not _check(cold.save_live_draft(receiver), "Retained receiver rehearsal remains saveable"): return
	var receiver_draft: Dictionary = receiver.export_recording()
	var receiver_cold := Journey.new(path, null, chapter)
	receiver_cold.load_data()
	if not _check(not receiver_cold.read_only and receiver_cold.role() == "b" and Canonical.same(receiver_cold.prior_recording(), retained.pairs[1].a), "Cold receiver retains its exact accepted source"): return
	var receiver_resume: RefCounted = receiver_cold.create_live_simulation(true)
	_replay_draft(receiver_resume, chapter, receiver_draft)
	_check(receiver_resume != null and Canonical.same(receiver_resume.export_recording(), receiver_draft), "Cold receiver native replay preserves old draft and source pin")
	_check(Canonical.same(receiver_cold.pairs(), [retained.pairs[0]]), "Neither current-stage Retry nor A/B Resume changes historical recording bytes")

func _empty_restart(chapter: String, retained: Dictionary) -> void:
	var empty := retained.duplicate(true)
	empty.pairs = []
	var path := directory + "/" + chapter.validate_filename() + "-empty.json"
	if not _seed(path, empty): return
	var before := FileAccess.get_file_as_string(path)
	var journey := Journey.new(path, null, chapter)
	journey.load_data()
	if not _check(not journey.read_only and journey.can_restart() and journey.restart_upgrades_rules(), "Retained empty old metadata offers a deliberate full restart"): return
	var old: RefCounted = journey.create_live_simulation(false)
	_check(old != null and old.simulation_version == retained.simulation_version and FileAccess.get_file_as_string(path) == before, "Opening empty old metadata keeps its pin and does not write")
	if not _check(journey.fork_from_stage(0), "Explicit empty-old restart upgrades without inventing recording evidence"): return
	_check(Canonical.same(Archive.load_attempt(path, "relay", Canonical.digest(empty), Journey.MAX_SAVE_BYTES), empty), "Empty old metadata is safely archived through the same bounded path")
	var fresh: RefCounted = journey.create_live_simulation(false)
	_check(fresh != null and fresh.simulation_version == 8 and not journey.can_restart(), "Empty new8 attempt no longer offers another empty restart")

func _unfinished_restart(chapter: String, retained: Dictionary, kind: String) -> void:
	var source: Dictionary = retained.pairs[0].a
	var old_rules := int(source.simulation_version)
	var path := directory + "/" + chapter.validate_filename() + "-" + str(old_rules) + "-" + kind + ".json"
	var empty := retained.duplicate(true)
	empty.pairs = []
	empty.a = {}
	empty.draft = {}
	if not _seed(path, empty): return
	var journey := Journey.new(path, null, chapter)
	var untouched := FileAccess.get_file_as_string(path)
	_check(not journey.can_restart() and journey.simulation_version() == -1 and not journey.restart_upgrades_rules(), "Unloaded eligibility observers do not restore or grant restart")
	_check(FileAccess.get_file_as_string(path) == untouched, "Unloaded queries leave retained bytes alone")
	journey.load_data()
	if not _check(not journey.read_only, "Valid old empty journal loads before receiving saved progress"): return
	if chapter == Registry.FIRST_STEPS:
		_check(not journey.can_restart() and not journey.restart_upgrades_rules() and not journey.fork_from_stage(0), "Empty First Steps already chooses fresh A and offers no empty restart")
	else:
		_check(journey.can_restart() and journey.restart_upgrades_rules(), "Old empty metadata needs explicit action rather than automatic migration")
	_check(FileAccess.get_file_as_string(path) == untouched, "Eligibility alone never manufactures an archive or upgrades saved metadata")
	if kind == "draft_a":
		var engine: Script = Registry.simulation_script(chapter)
		var source_simulation: RefCounted = engine.new()
		if not _check(Registry.reset_simulation(source_simulation, chapter, Registry.definition(chapter), journey.stage_id(), journey.checkpoint(), {}, "a", source), "Produce old source draft with actual native engine"): return
		_step_prefix(source_simulation, chapter, source)
		if not _check(journey.save_draft(source_simulation.export_recording()), "Persist actual unfinished old source recording"): return
	else:
		if not _check(journey.accept_recording(source), "Persist old accepted source before its receiver exists"): return
		_check(journey.can_restart() and journey.restart_upgrades_rules(), "An accepted old A alone enables explicit full restart")
		if kind == "draft_b":
			var receiver: RefCounted = journey.create_live_simulation(false)
			if not _check(receiver != null and receiver.simulation_version == old_rules, "Old accepted A still starts old B"): return
			_step_prefix(receiver, chapter, retained.pairs[0].b)
			if not _check(journey.save_live_draft(receiver), "Persist actual unfinished receiver without altering accepted A"): return
	var original := journey._state.duplicate(true)
	var before := FileAccess.get_file_as_string(path)
	var storage := FailingStorage.new(path)
	var cold := Journey.new(path, storage, chapter)
	cold.load_data()
	if not _check(not cold.read_only and Canonical.same(cold._state, original), "Cold unfinished old journal restores all exact A/draft evidence"): return
	_check(cold.can_restart() and cold.restart_upgrades_rules() and cold.pairs().is_empty(), "Saved unfinished old progress enables a deliberate upgrade with no completed pairs")
	var resumed: RefCounted = cold.create_live_simulation(true)
	if not _check(resumed != null and resumed.simulation_version == old_rules, "Mere opening or Resume never chooses8 for an unfinished old turn"): return
	if not original.draft.is_empty():
		_replay_draft(resumed, chapter, original.draft)
		_check(Canonical.same(resumed.export_recording(), original.draft), "Cold native Resume reconstructs the original unfinished recording exactly")
	_check(FileAccess.get_file_as_string(path) == before and Canonical.same(cold._state, original), "Eligibility/Resume without confirmation preserves exact active journal bytes")
	_check(not cold.fork_from_stage(1), "Zero-pair progress cannot claim a later checkpoint")
	storage.reject_write = true
	_check(not cold.fork_from_stage(0) and Canonical.same(cold._state, original) and FileAccess.get_file_as_string(path) == before, "Failed unfinished restart keeps saved and live A/draft intact")
	var id := Canonical.digest(original)
	var archive_path := path + ".attempt-" + id + ".json"
	_check(Canonical.same(Archive.load_attempt(path, "relay", id, Journey.MAX_SAVE_BYTES), original), "Archive retains old accepted A and/or draft even with zero complete pairs")
	var archive_hash := FileAccess.get_sha256(archive_path)
	storage.reject_write = false
	if not _check(cold.fork_from_stage(0), "Explicit storage retry commits the unfinished full restart"): return
	_check(cold.pairs().is_empty() and cold.prior_recording().is_empty() and cold.draft().is_empty() and not cold.can_restart(), "Only successful restart clears active unfinished evidence")
	_check(FileAccess.get_sha256(archive_path) == archive_hash, "Successful retry reuses the exact old unfinished archive")
	var fresh: RefCounted = cold.create_live_simulation(false)
	_check(fresh != null and fresh.simulation_version == 8 and cold.role() == "a", "Explicit unfinished restart creates a real new8 source engine")
	_check(not cold.restart_upgrades_rules(), "Already-fresh attempt no longer offers the rules upgrade")
	_check(cold.simulation_version() == (4 if chapter == Registry.FIRST_STEPS else 8), "First Steps retains its historical envelope convention; other journals pin8")

func _first_steps_unfinished() -> void:
	var retained := _completed_state(Registry.FIRST_STEPS, "first_steps", 4)
	for kind: String in ["draft_a", "accepted_a", "draft_b"]:
		_unfinished_restart(Registry.FIRST_STEPS, retained, kind)
	var five := retained.duplicate(true)
	five.pairs[0] = {"a":_fixture("first_steps", "cumulative-lift-a"), "b":_fixture("first_steps", "cumulative-lift-b")}
	for kind: String in ["draft_a", "accepted_a", "draft_b"]:
		_unfinished_restart(Registry.FIRST_STEPS, five, kind)
	var prefix := five.duplicate(true)
	prefix.pairs = [five.pairs[0]]
	var path := directory + "/first-prefix-fresh.json"
	if not _seed(path, prefix): return
	var journey := Journey.new(path, null, Registry.FIRST_STEPS)
	journey.load_data()
	if not _check(not journey.read_only and journey.can_restart() and not journey.restart_upgrades_rules(), "Old First Steps prefix with an already-fresh A needs no rules upgrade"): return
	var fresh: RefCounted = journey.create_live_simulation(false)
	if not _check(fresh != null and fresh.simulation_version == 8, "First Steps next pair independently chooses8 despite envelope4"): return
	_step_prefix(fresh, Registry.FIRST_STEPS, retained.pairs[1].a)
	_check(journey.save_live_draft(fresh) and not journey.restart_upgrades_rules(), "Saved fresh8 A with old prefix does not expose an old-rules restart action")

func _eligibility_holds() -> void:
	var path := directory + "/future.json"
	var future := _completed_state(Registry.RELAY, "v2", 2)
	future.simulation_version = 999
	if not _seed(path, future): return
	var before := FileAccess.get_file_as_string(path)
	var journey := Journey.new(path)
	journey.load_data()
	_check(journey.read_only and not journey.can_restart() and not journey.restart_upgrades_rules() and journey.simulation_version() == -1, "Unsupported journal never grants restart eligibility")
	_check(not journey.fork_from_stage(0) and FileAccess.get_file_as_string(path) == before, "Read-only restart refusal preserves exact future evidence")

func _write_failure(chapter: String, retained: Dictionary) -> void:
	var path := directory + "/write-failure.json"
	if not _seed(path, retained): return
	var storage := FailingStorage.new(path)
	var journey := Journey.new(path, storage, chapter)
	journey.load_data()
	var before := FileAccess.get_file_as_string(path)
	storage.reject_write = true
	_check(not journey.fork_from_stage(0) and journey.chapter_complete() and Canonical.same(journey._state, retained), "Failed new active save keeps old complete in-memory journal and pin")
	_check(FileAccess.get_file_as_string(path) == before, "Failed full restart cannot discard original active bytes")
	var id := Canonical.digest(retained)
	var archive_path := path + ".attempt-" + id + ".json"
	_check(Canonical.same(Archive.load_attempt(path, "relay", id, Journey.MAX_SAVE_BYTES), retained), "Failed active write still retains the verified old archive")
	var archive_hash := FileAccess.get_sha256(archive_path)
	storage.reject_write = false
	_check(journey.fork_from_stage(0) and journey._state.simulation_version == 8, "Explicit retry after storage recovery commits new8 chapter")
	_check(FileAccess.get_sha256(archive_path) == archive_hash and journey.archived_attempts().size() == 1, "Retry reuses identical original archive without duplication or overwrite")

func _replay_draft(simulation: RefCounted, chapter: String, recording: Dictionary) -> void:
	if simulation == null: return
	# Preview._resume_draft owns replay after the journal chooses the engine.
	simulation.catch_assistance = bool(recording.catch_assistance)
	var engine: Script = Registry.simulation_script(chapter)
	for input: Dictionary in engine.expand_recording_inputs(recording):
		simulation.step(input)

func _step_prefix(simulation: RefCounted, chapter: String, recording: Dictionary) -> void:
	var engine: Script = Registry.simulation_script(chapter)
	var inputs: Array = engine.expand_recording_inputs(recording)
	for index in range(mini(12, inputs.size())):
		simulation.step(inputs[index])
	_check(simulation.export_recording().duration_ticks > 0, "Rehearsal uses actual retained route input rather than fabricated draft fields")

func _fixture(folder: String, name: String) -> Dictionary:
	var path := "res://tests/fixtures/" + folder + "/" + name + ".json"
	fixture_hashes[path] = FileAccess.get_sha256(path)
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(value is Dictionary, "Read frozen native fixture " + name)
	return value if value is Dictionary else {}

func _seed(path: String, state: Dictionary) -> bool:
	var envelope := Storage.defaults()
	envelope["relay"] = state.duplicate(true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "Create isolated retained journal"): return false
	file.store_string(JSON.stringify(envelope))
	file.close()
	return true

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error("COMFORT RESTART: " + message)
	return value

func _finish() -> void:
	# Only this test's freshly generated directory can contain these files.
	var own := DirAccess.open(directory)
	if own != null:
		for filename: String in own.get_files():
			DirAccess.remove_absolute(directory.path_join(filename))
		DirAccess.remove_absolute(directory)
	print("AFTER YOU COMFORT RESTART: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
