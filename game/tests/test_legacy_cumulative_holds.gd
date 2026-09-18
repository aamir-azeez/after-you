extends SceneTree

const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const TurnState = preload("res://services/turn_state.gd")
const LocalSave = preload("res://services/local_save.gd")
const Main = preload("res://main.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_test_historical_records()
	_test_interrupted_charge()
	_test_version_selection_and_storage()
	await _test_retry_and_resume()
	print("LEGACY CUMULATIVE HOLDS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_historical_records() -> void:
	for id: String in ["first-light", "after-you"]:
		var definition: Dictionary = Levels.get_level(id)
		var a: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + id + "-a.json"))
		var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + id + "-b.json"))
		_check(Simulation.verify_recording(definition, a).valid, "Historical source hashes remain exact: " + id)
		_check(Simulation.verify_recording(definition, b, a).valid, "Historical paired hashes remain exact: " + id)

func _test_interrupted_charge() -> void:
	var definition: Dictionary = Levels.get_level("lantern-crossing")
	var original_definition := JSON.stringify(definition)
	var current := Simulation.new()
	var historical := Simulation.new()
	_check(current.reset(definition, {}, "a", 6) and historical.reset(definition), "Both supported rulesets start against the unchanged authored level")
	for simulation: AfterYouSimulation in [current, historical]:
		_walk(simulation, definition.plate)
		for i in range(12): simulation.step({})
		_walk(simulation, definition.starts.a)
	var retained: int = current.snapshot().bridge_charge
	_check(retained > 0 and retained < int(definition.bridge_charge_ticks), "Interrupted new charge retains a partial total")
	_check(historical.snapshot().bridge_charge == 0, "Historical charge still resets when leaving the plate")
	_check(not current.snapshot().bridge_open, "Retaining charge does not keep an unoccupied ordinary bridge open")
	current.step({"interact": true})
	_check(not current.snapshot().outcome.threw_seed, "Retained charge does not permit throwing away from the plate")
	current.step({})
	var draft: Dictionary = current.export_recording()
	_check(draft.simulation_version == 6 and Simulation.verify_recording(definition, draft).valid, "Interrupted draft records and verifies its cumulative ruleset")
	var resumed := Simulation.new()
	resumed.reset(definition, {}, "a", int(draft.simulation_version))
	for frame: Dictionary in Simulation.expand_recording_inputs(draft): resumed.step(frame)
	_check(resumed.state_hash() == current.state_hash() and resumed.snapshot().bridge_charge == retained, "Resuming a draft reconstructs the retained total exactly")
	_walk(current, definition.plate)
	while not current.snapshot().bridge_open and not current.finished: current.step({})
	_check(current.snapshot().bridge_charge == int(definition.bridge_charge_ticks), "Separated visits can finish the required total")
	current.step({"interact": true})
	while not current.finished: current.step({})
	var a: Dictionary = current.export_recording()
	_check(current.can_commit() and Simulation.verify_recording(definition, a).valid, "An interrupted cumulative source can finish and pass full replay verification")
	var b := Simulation.new()
	_check(b.reset(definition, a, "b"), "The partner inherits its source ruleset")
	_walk(b, [int(definition.starts.b[0]), int(definition.bridge.z)])
	while not b.snapshot().bridge_open and not b.finished: b.step({})
	_walk(b, [int(definition.landing[0]), int(definition.bridge.z)])
	_walk(b, definition.landing)
	while b.snapshot().seed.status != "held_b" and not b.finished: b.step({})
	_walk(b, definition.goal)
	b.step({"interact": true})
	var paired: Dictionary = b.export_recording()
	_check(b.complete and paired.simulation_version == 6 and Simulation.verify_recording(definition, paired, a).valid, "Cumulative source and partner complete a matching combined replay")
	_check(not Simulation.new().reset(definition, a, "b", 1), "A cumulative source cannot be played under an explicitly historical room")
	var changed := a.duplicate(true)
	changed.simulation_version = 1
	_check(not Simulation.verify_recording(definition, changed).valid, "Changing the version cannot reinterpret new hashes as historical rules")
	var retry := Simulation.new()
	retry.reset(definition, {}, "a", 6)
	_check(retry.snapshot().bridge_charge == 0, "Retry starts a new attempt without carrying over charge")
	_check(JSON.stringify(definition) == original_definition, "Version selection never mutates canonical level definitions")

func _test_version_selection_and_storage() -> void:
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	_check(TurnState.simulation_version({}, "a") == 6, "Fresh local attempts select cumulative rules")
	_check(TurnState.simulation_version({"draft": old}, "a") == 1, "Historical drafts retain their own rules")
	_check(TurnState.simulation_version({"draft": old}, "a", {}, false) == 6, "Starting a fresh local source does not inherit a resumable historical draft")
	_check(TurnState.simulation_version({"draft": old}, "a", {"room_id": "old"}, false) == 1, "Retry still respects a historical online room's pinned rules")
	_check(TurnState.simulation_version({"a": old}, "b") == 1, "Historical partner turns follow the saved source")
	_check(TurnState.simulation_version({}, "a", {"room_id": "existing"}) == 1, "A room without new metadata remains historical before its first turn")
	_check(TurnState.simulation_version({}, "a", {"simulation_version": 6}) == 6, "A new room pins cumulative rules before its first turn")
	_check(TurnState.simulation_version({}, "a", {"simulation_version": 6.5}) == -1, "Malformed pinned versions cannot silently fall back")
	_check(not TurnState.review(Levels.get_level("first-light"), old, {}, 6).valid, "A draft from different room rules is held before review")
	var path := "user://legacy-cumulative-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var save := LocalSave.new(path)
	_check(save.save_attempt("first-light", {"a": old}), "Historical source saves without migration")
	var restored := LocalSave.new(path)
	restored.load_data()
	_check(TurnState.same_recording(restored.attempt("first-light").a, old), "Saved historical recordings survive a new client unchanged")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _test_retry_and_resume() -> void:
	var path := "user://legacy-retry-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var historical := Simulation.new()
	historical.reset(Levels.get_level("first-light"))
	for i in range(12): historical.step({"move_x": 1.0})
	var draft: Dictionary = historical.export_recording()
	var save := LocalSave.new(path)
	save.data.settings.sound = false
	_check(save.save_attempt("first-light", {"draft": draft}), "A resumable historical draft is saved before the app opens")
	var app := Main.new()
	app.saves = save
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	app._start_practice(0)
	app.sim.step({})
	_check(app.sim.export_recording().simulation_version == 6, "Record from a ready local source starts current cumulative rules")
	_check(TurnState.same_recording(save.attempt("first-light").draft, draft), "Offering a new recording does not alter the saved historical draft")
	app._resume_draft(draft)
	_check(app.mode == "play" and app.sim.state_hash() == draft.final_state_hash and app.sim.export_recording().simulation_version == 1, "Resume reconstructs the historical draft under its original rules")
	app._prepare_turn()
	_check(app.sim.tick == 0, "Retry clears elapsed progress")
	app.sim.step({})
	_check(app.sim.export_recording().simulation_version == 6, "Retry after resuming an old local source starts the current rules")
	app.running = false
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _walk(simulation: AfterYouSimulation, target: Array) -> void:
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		while not simulation.finished:
			var position: Dictionary = simulation.snapshot().players[simulation.role]
			var distance := int(target[index]) - int(position[axis])
			if absi(distance) <= 1: break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + axis] = clampf(float(distance) / Simulation.MOVE_PER_TICK, -1, 1)
			simulation.step(input)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
