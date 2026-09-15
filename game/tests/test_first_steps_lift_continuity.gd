extends SceneTree

const Simulation = preload("res://core/first_steps/simulation.gd")
const Catalog = preload("res://core/first_steps/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := Catalog.definition()
	var initial := Catalog.initial_checkpoint()
	_check(Simulation.verify_checkpoint(level, _fixture("final-checkpoint")).valid, "All four frozen golden recordings and their exact nested checkpoint still verify")
	var a := Simulation.new()
	_check(a.reset(level, "a-little-lift", initial), "Actual platform source initializes")
	for input: Dictionary in Simulation.expand_recording_inputs(_fixture("a-little-lift-a")): a.step(input)
	while not a.finished: a.step({})
	var first := a.export_recording()
	_check(a.can_commit() and a.tick == 600 and not a.walkable_at(-20, 0, "p0"), "A can hold power for a long recording but cannot enter B's movable platform")
	var b := Simulation.new()
	_check(b.reset(level, "a-little-lift", initial, first, "b"), "B consumes the real long source")
	for input: Dictionary in Simulation.expand_recording_inputs(_fixture("a-little-lift-b")): b.step(input)
	_check(b.snapshot().outcome.reached_loft and not b.finished, "B actually rings the bell while the earlier recording still has time left")
	_walk(b, [-20, 0])
	_check(b.snapshot().players.p1.surface_id == "little-lift" and b.snapshot().players.p1.height == 160, "B legitimately returns to the raised lift before the source ends")
	while not b.finished: b.step({})
	var second := b.export_recording()
	var pair := Simulation.derive_checkpoint(level, initial, first, second)
	_check(b.complete and pair.valid, "The real completed pair accepts its exact upper-lift endpoint")
	if not pair.valid:
		_finish()
		return
	var checkpoint: Dictionary = pair.checkpoint
	_check(checkpoint.players.p1.x == -20 and checkpoint.players.p1.z == 0 and checkpoint.players.p1.surface_id == "little-lift", "Checkpoint keeps the actual endpoint without teleporting to the bell")
	var before := Canonical.digest(checkpoint)
	var source := Simulation.new()
	_check(source.reset(level, "a-place-to-grow", checkpoint), "Role-swapped source starts from the verified upper-lift checkpoint")
	_check(source.active_slot == "p1" and source.snapshot().players.p1.height == 160, "The same physical player remains at the same elevated position")
	source.step({})
	_check(source.snapshot().players.p1.surface_id == "little-lift", "A neutral step preserves the valid fixed-lift surface after role reversal")
	var can_leave := source.walkable_at(-12, 0)
	_check(can_leave, "Stage-two source can walk off its permanently raised lift")
	if not can_leave:
		_finish()
		return
	_walk(source, [230, -90])
	_check(source.context_action().id == "take" and source.context_action().enabled and source.snapshot().players.p1.surface_id == "loft", "Real movement crosses onto the loft and reaches the pedestal action")
	source.step({"interact": true})
	_walk(source, [140, -90])
	source.step({"interact": true})
	_walk(source, [360, 110])
	_check(source.can_commit() and source.snapshot().outcome.activated_garden, "The continued source performs the full take, throw and activation route")
	var later := Simulation.new()
	var source_record := source.export_recording()
	_check(later.reset(level, "a-place-to-grow", checkpoint, source_record, "b"), "Receiver replays the legitimate source that began on the fixed lift")
	_walk(later, [-340, 0])
	while not later.finished and not later.snapshot().outcome.caught_seed: later.step({})
	_walk(later, [-300, 130])
	later.step({"interact": true})
	while not later.finished: later.step({})
	_check(later.complete, "Receiver catches and plants beside that actual source replay")
	_check(Simulation.derive_checkpoint(level, checkpoint, source_record, later.export_recording()).valid, "The complete nested proof verifies after the lift endpoint continuation")
	_check(Canonical.digest(checkpoint) == before, "Continuing the chapter never rewrites the accepted prior checkpoint")
	_finish()

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/" + name + ".json"))

func _walk(simulation: AfterYouFirstStepsSimulation, target: Array) -> void:
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		for _step in range(600):
			if simulation.finished or not simulation.error.is_empty(): return
			var current: Dictionary = simulation.snapshot().players[simulation.active_slot]
			var distance := int(target[index]) - int(current[axis])
			if absi(distance) <= 1: break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + axis] = clampf(float(distance) / Simulation.MOVE_PER_TICK, -1.0, 1.0)
			simulation.step(input)

func _finish() -> void:
	print("FIRST STEPS LIFT CONTINUITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
