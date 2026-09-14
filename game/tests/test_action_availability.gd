extends SceneTree

const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const Canonical = preload("res://core/v2/canonical.gd")

class HudHarness:
	extends "res://main.gd"
	func _close_overlay() -> void:
		pass

class TestStick:
	extends Control
	func release() -> void:
		pass

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_current_throw_gates()
	_test_manual_catch_and_plant()
	_test_saved_recordings_unchanged()
	_test_hud_and_inputs()
	print("ACTION AVAILABILITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_current_throw_gates() -> void:
	var simulation := Simulation.new()
	_check(not simulation.context_action().enabled, "Uninitialized turns have no action")
	var level: Dictionary = Levels.get_level("first-light")
	simulation.reset(level)
	_check(simulation.context_action().id == "throw" and not simulation.context_action().enabled, "A distant plate does not make Throw available")
	var unchanged := simulation.state_hash()
	for _index in range(5):
		var result: Dictionary = simulation.context_action()
		result.enabled = true
	_check(simulation.tick == 0 and simulation.state_hash() == unchanged and simulation.export_recording().is_empty(), "Availability inspection and returned-value mutation neither predict nor record a turn")
	_walk(simulation, level.plate)
	_check(simulation.context_action().enabled, "An actually occupied ready plate enables Throw")
	simulation.step({"interact": true})
	_check(simulation.snapshot().outcome.threw_seed and not simulation.context_action().enabled, "The enabled throw works once and becomes unavailable afterward")
	for id: String in ["lantern-crossing", "rising-together"]:
		level = Levels.get_level(id)
		simulation.reset(level)
		_walk(simulation, level.plate)
		_check(not simulation.context_action().enabled, "Charging or rising is unavailable before it actually finishes: " + id)
		var before_tick: int = simulation.tick
		for _index in range(10): simulation.context_action()
		_check(simulation.tick == before_tick and not simulation.context_action().enabled, "Queries cannot complete a mechanism early: " + id)
		while not simulation.context_action().enabled and not simulation.finished:
			simulation.step({})
		_check(simulation.context_action().enabled, "Current completed mechanism enables Throw: " + id)
		simulation.step({"interact": true})
		_check(simulation.snapshot().outcome.threw_seed, "The availability query agrees with the unchanged throw gate: " + id)
	simulation.error = "Unavailable version"
	_check(not simulation.context_action().enabled, "An invalidated simulation cannot advertise an action")

func _test_manual_catch_and_plant() -> void:
	var level: Dictionary = Levels.get_level("first-light")
	var first := _fixture("first-light-a")
	var simulation := Simulation.new()
	simulation.catch_assistance = false
	_check(simulation.reset(level, first, "b"), "Manual receiver starts from the saved verified source")
	_check(simulation.context_action().id == "catch" and not simulation.context_action().enabled, "A not-yet-thrown seed is unavailable")
	_walk(simulation, [level.starts.b[0], level.bridge.z])
	while not simulation.snapshot().bridge_open and not simulation.finished: simulation.step({})
	_walk(simulation, [level.landing[0], level.bridge.z])
	_walk(simulation, level.landing)
	while simulation.snapshot().seed.status == "flying" and not simulation.finished: simulation.step({})
	_check(simulation.snapshot().seed.status == "waiting" and simulation.context_action().enabled, "A arrived seed within actual catch range enables manual Catch")
	simulation.step({"interact": true})
	_check(simulation.snapshot().seed.status == "held_b" and simulation.context_action().id == "plant", "Catching changes the contextual action to Plant")
	_check(not simulation.context_action().enabled, "Carrying away from the garden does not enable Plant")
	simulation.step({})
	_walk(simulation, level.goal)
	_check(simulation.context_action().enabled, "Carrying at the open garden enables Plant")
	# Exercise the independent guard without simulating a future opening. This
	# seam is also checked against the actual unchanged planting implementation.
	simulation._gate_open = false
	_check(not simulation.context_action().enabled, "Closed garden disables Plant even at its exact destination")
	simulation.step({"interact": true})
	_check(not simulation.complete, "The unchanged planting gate rejects that same closed garden")
	simulation._gate_open = true
	simulation.step({})
	_check(simulation.context_action().enabled, "Releasing input at the reopened garden enables the next Plant")
	simulation.step({"interact": true})
	_check(simulation.complete and not simulation.context_action().enabled, "Plant completes the island and all further actions are unavailable")
	var missed := Simulation.new()
	missed.catch_assistance = false
	missed.reset(level, first, "b")
	while missed.snapshot().seed.status != "missed" and not missed.finished: missed.step({})
	_check(not missed.context_action().enabled, "A faded seed never enables Catch")

func _test_saved_recordings_unchanged() -> void:
	for id: String in ["first-light", "after-you"]:
		var level: Dictionary = Levels.get_level(id)
		var first := _fixture(id + "-a")
		for role: String in ["a", "b"]:
			var path := "res://tests/fixtures/" + id + "-" + role + ".json"
			var bytes_hash := FileAccess.get_sha256(path)
			var record := _fixture(id + "-" + role)
			var simulation := Simulation.new()
			simulation.catch_assistance = bool(record.get("catch_assistance", true))
			var source := first if role == "b" else {}
			_check(simulation.reset(level, source, role), "Historical fixture still resets: " + id + role)
			for input: Dictionary in Simulation.expand_recording_inputs(record):
				simulation.context_action()
				simulation.step(input)
				simulation.context_action()
			_check(Canonical.same(simulation.export_recording(), record), "Availability queries preserve every historical recording field and checkpoint hash: " + id + role)
			_check(FileAccess.get_sha256(path) == bytes_hash and Simulation.verify_recording(level, record, source).valid, "Original fixture bytes and independent replay proof remain unchanged: " + id + role)

func _test_hud_and_inputs() -> void:
	# No scene entry, native services, account, sound or filesystem writes. These
	# are the real Main HUD/input methods with ordinary owned Control instances.
	var app := HudHarness.new()
	app.timer_label = Label.new()
	app.hint_label = Label.new()
	app.progress = ProgressBar.new()
	app.interact_button = Button.new()
	app.finish_button = Button.new()
	app.stick = TestStick.new()
	for control: Node in [app.timer_label, app.hint_label, app.progress, app.interact_button, app.finish_button, app.stick]: app.add_child(control)
	app.sim.reset(Levels.get_level("first-light"))
	app.interact_button.disabled = false
	app._begin_turn()
	_check(app.interact_button.disabled and app.finish_button.disabled, "Begin updates action and Finish availability immediately before the first tick")
	app._request_context_action()
	_check(not app.action_pressed, "A disabled button callback cannot queue a hidden action")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	app._unhandled_key_input(key)
	_check(not app.action_pressed, "Space uses the same availability guard as touch")
	_walk(app.sim, app.sim.level.plate)
	app._update_hud(app.sim.snapshot())
	_check(not app.interact_button.disabled and app.interact_button.text == "Throw seed", "HUD enables the actual reachable context action")
	app._unhandled_key_input(key)
	_check(app.action_pressed, "An available keyboard action is accepted")
	app.sim.step({"interact": app.action_pressed})
	app.action_pressed = false
	app._update_hud(app.sim.snapshot())
	_check(app.interact_button.disabled and not app.finish_button.disabled, "After a successful throw, action grays out while Finish becomes available")
	app.running = false
	app.mode = "paused"
	app._update_hud(app.sim.snapshot())
	_check(app.finish_button.disabled, "A paused turn does not leave a clickable Finish action")
	app._request_context_action()
	_check(not app.action_pressed, "A paused callback does not record an action")
	app.free()

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))

func _walk(simulation: RefCounted, target: Array) -> void:
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		for _guard in range(Simulation.MAX_TICKS):
			if simulation.finished: return
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
