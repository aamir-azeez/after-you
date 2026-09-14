extends SceneTree

const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_test_authored_islands()
	_test_repeatable_replay()
	_test_pause_and_immutable_source()
	_test_miss_and_context_actions()
	_test_recording_integrity()
	_test_conflicting_prior_and_fork()
	_test_explicit_catch_mode()
	_test_mechanics_are_authoritative()
	print("AFTER YOU SIMULATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_authored_islands() -> void:
	var levels: Array = Levels.all_levels()
	_check(levels.size() == 8, "Eight authored islands")
	_check(levels.filter(func(item: Dictionary) -> bool: return not item.premium).size() == 3, "Three free introductory islands")
	var seen: Dictionary = {}
	for definition: Dictionary in levels:
		_check(not seen.has(definition.id), "Unique island ID: " + definition.id)
		seen[definition.id] = true
		var first := _solve_a(definition)
		_check(first.can_commit(), definition.id + " first-player contribution is valid")
		var track: Dictionary = first.export_recording()
		_check(Simulation.verify_recording(definition, track).valid, definition.id + " A recording verifies")
		var second := _solve_b(definition, track)
		_check(second.complete, definition.id + " full cooperative solution")
		var replay: Dictionary = Simulation.verify_recording(definition, second.export_recording(), track)
		_check(replay.valid, definition.id + " combined replay verifies: " + str(replay.get("error", "")))
		_check(second.snapshot().seed.status == "planted", definition.id + " final seed planted")
		if OS.get_cmdline_user_args().has("--write-fixtures") and definition.id in ["first-light", "after-you"]:
			_write_fixture(definition.id + "-a", track)
			_write_fixture(definition.id + "-b", second.export_recording())

func _test_repeatable_replay() -> void:
	var definition: Dictionary = Levels.get_level("first-light")
	var original := _solve_a(definition)
	var track: Dictionary = original.export_recording()
	var frames: Array = Simulation.expand_actions(track.actions)
	# Simulated render schedules differ; fixed simulation inputs/ticks do not.
	for batch_size: int in [1, 2, 5, 13]:
		var replay := Simulation.new()
		replay.reset(definition)
		var cursor := 0
		while cursor < frames.size():
			for _step: int in range(batch_size):
				if cursor >= frames.size():
					break
				var frame: Dictionary = frames[cursor]
				replay.step({"move_x": float(frame.x) / 100, "move_z": float(frame.z) / 100, "interact": frame.action})
				cursor += 1
		_check(replay.state_hash() == original.state_hash(), "Render schedule batch %d gives identical result" % batch_size)
	var encoded: String = JSON.stringify(track)
	var roundtrip: Dictionary = JSON.parse_string(encoded)
	_check(Simulation.verify_recording(definition, roundtrip).valid, "JSON float/integer roundtrip preserves replay")
	_check(track.actions.size() < 40, "Idle and held input RLE keeps recording small")
	var convenience := Simulation.new()
	convenience.reset(definition)
	for input: Dictionary in Simulation.expand_recording_inputs(track):
		convenience.step(input)
	_check(convenience.state_hash() == track.final_state_hash, "Step-ready replay/resume helper preserves input semantics")

func _test_pause_and_immutable_source() -> void:
	var definition: Dictionary = Levels.get_level(0)
	var first := _solve_a(definition)
	var track: Dictionary = first.export_recording()
	var second := Simulation.new()
	second.reset(definition, track, "b")
	second.step({"move_x": 1})
	var before: String = second.state_hash()
	var before_tick: int = second.tick
	for _frame: int in range(120):
		second.snapshot()
	_check(second.state_hash() == before and second.tick == before_tick, "Pause and rendering do not advance simulation")
	var original_run: Dictionary = second._prior.actions[0].duplicate(true)
	track.actions[0].x = -100
	_check(second._prior.actions[0] == original_run, "Caller cannot mutate copied prior recording")
	var exported := first.export_recording()
	exported.actions[0].z = -100
	_check(first.export_recording().actions[0].z != -100, "Exported recording cannot mutate live actions")

func _test_miss_and_context_actions() -> void:
	var definition: Dictionary = Levels.get_level(0)
	var first := Simulation.new()
	first.reset(definition)
	first.step({"interact": true})
	_check(not first.can_commit() and first.snapshot().seed.status == "held_a", "Throw away from plate does not produce valid contribution")
	first.step({})
	_walk(first, definition.plate)
	first.step({"interact": true})
	for _i: int in range(10):
		first.step({"interact": true})
	_check(first.snapshot().outcome.threw_seed, "Held interaction throws once without duplicate side effects")
	var track: Dictionary = first.export_recording()
	var second := Simulation.new()
	_check(second.reset(definition, track, "b"), "Partial valid A turn replays with final position held")
	for _i: int in range(Simulation.MAX_TICKS):
		second.step({})
	_check(second.snapshot().seed.status == "missed" and not second.can_commit(), "Missed catch is an incomplete turn")
	var stopped_hash: String = second.state_hash()
	second.step({"move_x": 1, "interact": true})
	_check(second.state_hash() == stopped_hash, "Time limit prevents extra actions")
	var bridge_test := Simulation.new()
	bridge_test.reset(definition, track, "b")
	# The bridge is closed until A reaches the plate. B cannot walk off its bank.
	bridge_test._b = Vector2i(-120, 0)
	bridge_test.step({"move_x": 1})
	_check(bridge_test.snapshot().players.b.x <= -112, "Closed bridge blocks crossing")

func _test_recording_integrity() -> void:
	var definition: Dictionary = Levels.get_level(0)
	var track: Dictionary = _solve_a(definition).export_recording()
	var changed := track.duplicate(true)
	changed.simulation_version = 77
	_check(not Simulation.verify_recording(definition, changed).valid, "Unknown simulation version held")
	changed = track.duplicate(true)
	changed.level_version = 99
	_check(not Simulation.verify_recording(definition, changed).valid, "Unknown level version held")
	changed = track.duplicate(true)
	changed.actions[0].x = 101
	_check(not Simulation.verify_recording(definition, changed).valid, "Out-of-range movement rejected")
	changed = track.duplicate(true)
	changed.actions[0].ticks += 1
	_check(not Simulation.verify_recording(definition, changed).valid, "Duration mismatch rejected")
	changed = track.duplicate(true)
	changed.outcome.planted_seed = true
	_check(not Simulation.verify_recording(definition, changed).valid, "Invented completion outcome rejected")
	changed = track.duplicate(true)
	changed.checkpoints[0].state_hash = "0".repeat(64)
	_check(not Simulation.verify_recording(definition, changed).valid, "Altered checkpoint rejected")
	changed = track.duplicate(true)
	changed.actions[0].x = -int(changed.actions[0].x)
	_check(not Simulation.verify_recording(definition, changed).valid, "Changed action rejected by semantic replay")
	_check(not Simulation.new().reset(definition, changed, "b"), "B rejects semantically altered A before playing")
	changed = track.duplicate(true)
	changed.duration_ticks = 600.2
	_check(not Simulation.verify_recording(definition, changed).valid, "Fractional recording header rejected")
	_check(Simulation.quantize_input({"move_x": INF, "move_z": "ignore", "interact": false}).x == 0, "Invalid input cannot enter integer simulation")

func _test_conflicting_prior_and_fork() -> void:
	var definition: Dictionary = Levels.get_level(0)
	var first: Dictionary = _solve_a(definition).export_recording()
	var second: Dictionary = _solve_b(definition, first).export_recording()
	var other := first.duplicate(true)
	other.final_state_hash = "a".repeat(64)
	_check(not Simulation.verify_recording(definition, second, other).valid, "Different earlier contribution invalidates B replay")
	var fork: Dictionary = Simulation.fork_recordings(first)
	_check(fork.a == first and fork.b.is_empty() and not fork.completed, "Fork retains chosen A and clears dependent B")
	_check(not Simulation.new().reset(definition, {}, "b"), "B cannot start with missing A")

func _test_explicit_catch_mode() -> void:
	var definition: Dictionary = Levels.get_level(0)
	var first: Dictionary = _solve_a(definition).export_recording()
	var second := Simulation.new()
	second.catch_assistance = false
	second.reset(definition, first, "b")
	_receiver_route(second, definition)
	while second.snapshot().seed.status == "flying" and not second.finished:
		second.step({})
	_check(second.snapshot().seed.status == "waiting", "Assistance off requires explicit catch")
	second.step({"interact": true})
	_check(second.snapshot().seed.status == "held_b", "Explicit catch works with assistance off")
	second.step({})
	_walk(second, definition.goal)
	second.step({"interact": true})
	_check(second.complete, "Explicit catch mode completes")
	_check(Simulation.verify_recording(definition, second.export_recording(), first).valid, "Catch mode is preserved in replay")

func _test_mechanics_are_authoritative() -> void:
	var gate_level: Dictionary = Levels.get_level("across-the-blue")
	var gated := Simulation.new()
	gated.reset(gate_level)
	_walk(gated, gate_level.plate)
	gated.step({"interact": true})
	_check(gated.snapshot().outcome.threw_seed and not gated.can_commit(), "Throw alone cannot commit an unopened garden")
	_check(not Simulation.new().reset(gate_level, gated.export_recording(), "b"), "Receiver cannot start an incomplete garden contribution")
	gated.step({})
	_walk(gated, gate_level.gate.plate)
	_check(gated.snapshot().gate_open and gated.snapshot().bridge_open and gated.can_commit(), "Second plate opens garden and preserves the bridge")
	var lift_level: Dictionary = Levels.get_level("rising-together")
	var lifting := Simulation.new()
	lifting.reset(lift_level)
	_walk(lifting, lift_level.plate)
	lifting.step({"interact": true})
	_check(not lifting.snapshot().outcome.threw_seed and not lifting.snapshot().lift_ready, "Unraised lift prevents early throw")
	lifting.step({})
	while not lifting.snapshot().lift_ready:
		lifting.step({})
	_check(lifting.snapshot().lift_height == int(lift_level.lift.height), "Lift reaches authored physical height")
	lifting.step({"interact": true})
	_check(lifting.can_commit(), "Lift-ready contribution can commit")
	var charged_level: Dictionary = Levels.get_level("lantern-crossing")
	var charged := Simulation.new()
	charged.reset(charged_level)
	_walk(charged, charged_level.plate)
	_check(not charged.snapshot().bridge_open, "Charge duration affects bridge collision state")
	charged.step({"interact": true})
	_check(not charged.can_commit(), "Uncharged plate cannot throw")
	charged.step({})
	while not charged.snapshot().bridge_open:
		charged.step({})
	charged.step({"interact": true})
	_check(charged.can_commit(), "Charged plate opens bridge and allows throw")
	# Leaving an ordinary non-latching plate also makes a contribution incomplete.
	var ordinary_level: Dictionary = Levels.get_level(0)
	var ordinary := Simulation.new()
	ordinary.reset(ordinary_level)
	_walk(ordinary, ordinary_level.plate)
	ordinary.step({"interact": true})
	ordinary.step({})
	_walk(ordinary, ordinary_level.starts.a)
	_check(not ordinary.can_commit(), "A cannot commit after leaving an ordinary bridge closed")

func _write_fixture(name: String, recording: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/fixtures")
	var file := FileAccess.open("res://tests/fixtures/" + name + ".json", FileAccess.WRITE)
	if file == null:
		_check(false, "Could not write fixture " + name)
		return
	file.store_string(JSON.stringify(recording, "\t") + "\n")

func _solve_a(definition: Dictionary) -> AfterYouSimulation:
	var simulation := Simulation.new()
	simulation.reset(definition)
	_walk(simulation, definition.plate)
	while (not simulation.snapshot().bridge_open or not simulation.snapshot().lift_ready) and not simulation.finished:
		simulation.step({})
	simulation.step({"interact": true})
	simulation.step({})
	if definition.has("gate"):
		_walk(simulation, definition.gate.plate)
	while not simulation.finished:
		simulation.step({})
	return simulation

func _solve_b(definition: Dictionary, first: Dictionary) -> AfterYouSimulation:
	var simulation := Simulation.new()
	simulation.reset(definition, first, "b")
	_receiver_route(simulation, definition)
	while simulation.snapshot().seed.status != "held_b" and not simulation.finished:
		simulation.step({})
	_walk(simulation, definition.goal)
	while not simulation.snapshot().gate_open and not simulation.finished:
		simulation.step({})
	simulation.step({"interact": true})
	return simulation

func _receiver_route(simulation: AfterYouSimulation, definition: Dictionary) -> void:
	_walk(simulation, [int(definition.starts.b[0]), int(definition.bridge.z)])
	while not simulation.snapshot().bridge_open and not simulation.finished:
		simulation.step({})
	_walk(simulation, [int(definition.landing[0]), int(definition.bridge.z)])
	_walk(simulation, definition.landing)

func _walk(simulation: AfterYouSimulation, target: Array) -> void:
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		var attempts := 0
		while not simulation.finished:
			var position: Dictionary = simulation.snapshot().players[simulation.role]
			var distance := int(target[index]) - int(position[axis])
			if absi(distance) <= 1:
				break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + axis] = clampf(float(distance) / Simulation.MOVE_PER_TICK, -1, 1)
			simulation.step(input)
			attempts += 1
			if attempts > Simulation.MAX_TICKS:
				break

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
