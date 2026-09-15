extends SceneTree

const Simulation = preload("res://core/first_steps/simulation.gd")
const Catalog = preload("res://core/first_steps/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var definition := Catalog.definition()
var initial := Catalog.initial_checkpoint()
var first_a: Dictionary = {}
var first_b: Dictionary = {}
var checkpoint: Dictionary = {}
var second_a: Dictionary = {}
var second_b: Dictionary = {}
var final_checkpoint: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_catalog_and_platform()
	_test_first_pair()
	if not checkpoint.is_empty():
		_test_second_pair()
		_test_seed_failures()
	_test_source_viability()
	_test_handoff_grace()
	_test_integrity_and_resume()
	_check(not final_checkpoint.is_empty(), "Both actual stages reach a verified final checkpoint")
	if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args(): _write_fixtures()
	print("AFTER YOU FIRST STEPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_catalog_and_platform() -> void:
	_check(Canonical.digest(definition) == "72ddc480e0f493c983fb012ce7bfa20a9cb1984ef7263d236c11509a527df85b", "Godot catalog hash matches backend-shared canonical JSON")
	_check(initial.checkpoint_hash == Catalog.checkpoint_hash(initial) and initial.checkpoint_hash == "b12ac49480a223783c2d276f7b44e7dcfadcbc5deb86b1483a0e9df1e218fbbd", "Initial checkpoint hash matches backend-shared JSON")
	_check(definition.stages.size() == 2 and not definition.premium, "Exactly two free introductory stages are authored")
	var source := Simulation.new()
	_check(source.reset(definition, "a-little-lift", initial), "Exact initial definition/checkpoint initializes")
	_check(source.snapshot().seed.status == "pedestal" and not source.context_action().enabled, "A visible pedestal seed is not a stage-one action")
	for _index in range(90): source.step({"move_x": 1.0, "interact": true})
	_check(source.snapshot().players.p0.x <= -132 and source.snapshot().players.p0.height == 0, "Source cannot step from fixed shore onto the later-controlled lift")
	_check(not source.snapshot().outcome.threw_seed and not source.snapshot().outcome.took_seed, "Repeated stage-one interaction does not fabricate seed events")
	_check(not Simulation.new().reset(definition, "a-little-lift", initial, {}, "b"), "B cannot play without a verified earlier source")
	var altered := definition.duplicate(true)
	altered.lift.top_height_cm = 1
	_check(not Simulation.new().reset(altered, "a-little-lift", initial), "Unsupported vertical definition is held instead of reinterpreted")

func _test_first_pair() -> void:
	var a := _source_lift()
	first_a = a.export_recording()
	_check(a.can_commit() and a.tick < 60, "A can record short real power without filling twenty seconds")
	_check(a.snapshot().outcome.supplied_power and not a.snapshot().outcome.threw_seed, "The platform source uses actual power outcome, not a fake throw")
	_check(a.snapshot().mechanisms.lift.phase == "lower", "A alone never moves the later player's lift")
	_check(Simulation.verify_recording(definition, first_a, initial).valid, "First source verifies by deterministic replay")
	var b := Simulation.new()
	_check(b.reset(definition, "a-little-lift", initial, first_a, "b"), "Later player starts beside the exact source recording")
	for _index in range(70): b.step({})
	_check(b.snapshot().mechanisms.lift.phase == "lower" and b.snapshot().mechanisms.lift.height_cm == 0, "Powered lift waits on the ground until B actually boards")
	_check(not b.context_action().enabled, "Bell action is unavailable from the lower shore")
	b.step({"interact": true})
	_check(not b.complete and not b.snapshot().outcome.reached_loft, "Pressing an action cannot fabricate a ride or crossing")
	_walk(b, [-20, 0])
	var riding := b.snapshot()
	_check(riding.outcome.boarded_lift and riding.mechanisms.lift.phase == "rising" and riding.players.p1.height > 0, "Actual occupancy triggers a rising platform and passenger height")
	_check(not b.walkable_at(-200, 0) and not b.walkable_at(200, 0), "Passenger cannot step onto either island at a mismatched height")
	var paused_record := b.export_recording()
	var resumed := _resume(paused_record, initial, first_a)
	_check(Canonical.same(resumed.snapshot(), b.snapshot()), "A mid-rise draft resumes exact position, height, mechanism and source context")
	for _index in range(60):
		if b.snapshot().mechanisms.lift.phase == "upper": break
		b.step({})
	_check(b.snapshot().players.p1.height == 160 and b.snapshot().mechanisms.lift.progress_ticks == 60, "Lift reaches exact authored height with bounded fixed ticks")
	_walk(b, [230, 0])
	_check(b.context_action().enabled and b.snapshot().players.p1.surface_id == "loft", "Actual upper crossing makes the bell available")
	b.step({"interact": true})
	first_b = b.export_recording()
	_check(b.complete and b.snapshot().mechanisms.loft_open, "B rings the upper bell after boarding and opens the loft")
	_check(b.snapshot().seed.status == "pedestal" and not b.snapshot().outcome.caught_seed and not b.snapshot().outcome.planted_seed, "Platform stage completes without touching or inventing a seed goal")
	_check(b.snapshot().players.p0.x == a.snapshot().players.p0.x and b.snapshot().players.p0.height == 0, "B's ride cannot move the recorded source actor or its height")
	var derived := Simulation.derive_checkpoint(definition, initial, first_a, first_b)
	_check(derived.valid, "The exact first A/B pair derives its completed checkpoint")
	if derived.valid:
		checkpoint = derived.checkpoint
		_check(checkpoint.players.p1.height == 160 and checkpoint.players.p0.height == 0 and checkpoint.next_stage_id == "a-place-to-grow", "Checkpoint preserves both exact physical elevations and advances one stage")
		_check(Canonical.same(checkpoint.seed, initial.seed), "Seed pedestal state is preserved across the platform stage")
		_check(Simulation.verify_checkpoint(definition, _json(checkpoint)).valid, "First checkpoint proof survives a real JSON roundtrip")

func _test_second_pair() -> void:
	var a := _source_seed(checkpoint)
	second_a = a.export_recording()
	_check(a.can_commit() and a.active_slot == "p1", "Upper receiver becomes the next source and can commit its distinct seed route")
	_check(a.snapshot().outcome.took_seed and a.snapshot().outcome.threw_seed and a.snapshot().outcome.activated_garden, "A must actually take, throw and activate the garden")
	_check(not a.snapshot().outcome.supplied_power and not a.snapshot().outcome.reached_loft, "New turn outcomes are stage-specific rather than copied from the previous stage")
	var b := Simulation.new()
	_check(b.reset(definition, "a-place-to-grow", checkpoint, second_a, "b"), "Second receiver uses the verified first-pair checkpoint and new source")
	var start := b.snapshot()
	_check(start.active_slot == "p0" and start.players.p0.x == checkpoint.players.p0.x and start.players.p1.x == checkpoint.players.p1.x and start.players.p1.height == checkpoint.players.p1.height, "Role reversal never teleports or exchanges physical slots")
	_check(not start.mechanisms.garden_open and start.seed.status == "pedestal", "Stage-two garden starts closed and seed remains at the upstairs pedestal")
	var prior_bytes := Canonical.digest(second_a)
	_walk(b, [-340, 0])
	var saw_air := false
	for _index in range(300):
		var state := b.snapshot()
		saw_air = saw_air or state.seed.status == "flying"
		if state.seed.status == "held" and state.seed.owner == "p0": break
		b.step({})
	_check(saw_air and b.snapshot().outcome.caught_seed, "The later player catches the source's scripted upper-to-lower throw")
	_walk(b, [-300, 130])
	_check(b.context_action().enabled and b.snapshot().mechanisms.garden_open, "Actual garden activation and carried seed make planting available")
	b.step({"interact": true})
	while not b.finished: b.step({})
	second_b = b.export_recording()
	_check(b.complete and b.snapshot().seed.status == "planted", "The second pair completes by planting, not by arbitrary finish")
	_check(Canonical.digest(second_a) == prior_bytes and b.snapshot().players.p1.x == a.snapshot().players.p1.x, "Later seed ownership never rewrites or displaces the source contribution")
	var derived := Simulation.derive_checkpoint(definition, checkpoint, second_a, second_b)
	_check(derived.valid, "Second pair derives a verified final checkpoint")
	if derived.valid:
		final_checkpoint = derived.checkpoint
		_check(final_checkpoint.stage_index == 2 and final_checkpoint.next_stage_id.is_empty(), "Exactly two completed stages finish this chapter")
		_check(Simulation.verify_checkpoint(definition, _json(final_checkpoint)).valid, "Final nested proof verifies all actual prior stages")
		_check(final_checkpoint.players.p1.height == 160 and final_checkpoint.players.p0.height == 0 and final_checkpoint.mechanisms.garden_open, "Final proof retains exact heights, raised lift and activated garden")

func _test_seed_failures() -> void:
	var a := Simulation.new()
	a.reset(definition, "a-place-to-grow", checkpoint)
	_walk(a, [360, 110])
	_check(not a.snapshot().mechanisms.garden_open and not a.snapshot().outcome.activated_garden, "Visiting the garden control before throwing does not fabricate activation")
	_walk(a, [230, -90])
	a.step({"interact": true})
	a.step({"interact": true})
	_check(a.snapshot().outcome.took_seed and not a.snapshot().outcome.threw_seed, "Holding interaction at the pedestal takes once and cannot throw remotely")
	_walk(a, [140, -90])
	a.step({})
	a.step({"interact": true})
	_check(a.snapshot().outcome.threw_seed and not a.can_commit(), "A throw alone is not a valid source until the garden is activated")
	var b := Simulation.new()
	b.reset(definition, "a-place-to-grow", checkpoint, second_a, "b")
	b.catch_assistance = false
	_walk(b, [-340, 0])
	while not b.context_action().enabled and not b.finished: b.step({})
	_check(b.context_action().enabled and not b.snapshot().outcome.caught_seed, "Manual catch remains a real available action with assistance disabled")
	b.step({"interact": true})
	_check(b.snapshot().outcome.caught_seed, "Explicit catch accepts the actual seed within its height and radius window")
	var missed := Simulation.new()
	missed.reset(definition, "a-place-to-grow", checkpoint, second_a, "b")
	_walk(missed, [-540, 180])
	while not missed.finished: missed.step({})
	_check(missed.snapshot().seed.status == "missed" and not missed.can_commit(), "A real missed catch stays incomplete without deleting the earlier source")
	var lower := Simulation.new()
	lower.reset(definition, "a-place-to-grow", checkpoint, second_a, "b")
	for _index in range(80): lower.step({"move_x": 1.0})
	_check(lower.snapshot().players.p0.x <= -132 and lower.snapshot().players.p0.height == 0, "Lower receiver cannot walk onto the already raised lift to steal the upstairs seed")

func _test_source_viability() -> void:
	var interrupted := _source_lift()
	_walk(interrupted, [-430, -130])
	_walk(interrupted, [-300, -130])
	for _index in range(6): interrupted.step({})
	_check(not interrupted.can_commit() and interrupted.commit_reason().contains("released"), "Leaving and returning to the power pad permanently rejects that interrupted source")
	var late := Simulation.new()
	late.reset(definition, "a-little-lift", initial)
	for _index in range(560): late.step({})
	_walk(late, [-300, -130])
	while not late.finished: late.step({})
	_check(not late.can_commit(), "Late power leaves insufficient ride/crossing time and cannot be committed")
	_check(not Simulation.new().reset(definition, "a-little-lift", initial, late.export_recording(), "b"), "A structurally valid but nonviable late source cannot initialize B")
	if not checkpoint.is_empty():
		var late_seed := Simulation.new()
		late_seed.reset(definition, "a-place-to-grow", checkpoint)
		_walk(late_seed, [230, -90])
		late_seed.step({"interact": true})
		_walk(late_seed, [140, -90])
		while late_seed.tick < 599: late_seed.step({})
		late_seed.step({"interact": true})
		_check(not late_seed.snapshot().outcome.threw_seed and not late_seed.can_commit(), "Tick599 throw is rejected instead of producing an impossible receiver turn")

func _test_integrity_and_resume() -> void:
	var bad := initial.duplicate(true)
	bad.players.p1.height = 160
	bad.checkpoint_hash = Catalog.checkpoint_hash(bad)
	_check(not Simulation.verify_checkpoint(definition, bad).valid, "Rehashing an invented starting height does not produce a valid checkpoint")
	if first_a.is_empty(): return
	for key: String in ["schema_version", "simulation_version", "level_version", "stage_version"]:
		bad = first_a.duplicate(true)
		bad[key] += 1
		bad.recording_hash = Simulation.recording_hash(bad)
		_check(not Simulation.verify_recording(definition, bad, initial).valid, "Unsupported recorded version is rejected: " + key)
	bad = first_a.duplicate(true)
	bad.outcome.threw_seed = true
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(definition, bad, initial).valid, "Rehashed fabricated throw outcome is rejected by physical replay")
	bad = first_a.duplicate(true)
	bad.actions[0].x = -100
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(definition, bad, initial).valid, "Rehashed input tamper cannot retain the old checkpoints")
	bad = first_a.duplicate(true)
	bad["unknown"] = true
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(definition, bad, initial).valid, "Unknown recording fields fail closed")
	if not first_b.is_empty():
		bad = first_b.duplicate(true)
		bad.source_recording_hash = "0".repeat(64)
		bad.recording_hash = Simulation.recording_hash(bad)
		_check(not Simulation.verify_recording(definition, bad, initial, first_a).valid, "B must bind the exact full earlier recording hash")
	for batch: int in [1, 3, 11]:
		var resumed := Simulation.new()
		resumed.reset(definition, "a-little-lift", initial)
		var frames := Simulation.expand_recording_inputs(first_a)
		var cursor := 0
		while cursor < frames.size():
			for _index in range(batch):
				if cursor >= frames.size(): break
				resumed.step(frames[cursor])
				cursor += 1
		_check(Canonical.same(resumed.export_recording(), first_a), "Different render batch sizes preserve exact fixed-tick record: %d" % batch)
	var paused := _resume(first_a, initial)
	var before := Canonical.digest(paused.export_recording())
	for _index in range(90): paused.snapshot()
	_check(Canonical.digest(paused.export_recording()) == before, "Rendering or background pause alone never advances a turn")
	paused.step({"fabricated_action": true})
	_check(not paused.error.is_empty() and not paused.can_commit(), "Unsupported input cannot enter a committable simulation")
	if not checkpoint.is_empty():
		bad = checkpoint.duplicate(true)
		bad.mechanisms.lift.height_cm = 0
		bad.checkpoint_hash = Catalog.checkpoint_hash(bad)
		_check(not Simulation.verify_checkpoint(definition, bad).valid, "Rehashed completed lift state is rejected against exact prior pair proof")
		_check(not Simulation.new().reset(definition, "a-little-lift", checkpoint), "Stale stage cannot reuse an advanced checkpoint")
	if not final_checkpoint.is_empty():
		bad = final_checkpoint.duplicate(true)
		bad.proof.checkpoint = initial.duplicate(true)
		bad.checkpoint_hash = Catalog.checkpoint_hash(bad)
		_check(not Simulation.verify_checkpoint(definition, bad).valid, "Final proof cannot skip its first completed pair")
		_check(not Simulation.new().reset(definition, "a-place-to-grow", final_checkpoint), "Completed chapter is not silently reset into another active turn")

func _test_handoff_grace() -> void:
	_check(definition.handoff_grace_ticks == 60, "The immutable chapter reserves two seconds of optional human response time")
	for late: bool in [false, true]:
		var power := Simulation.new()
		power.reset(definition, "a-little-lift", initial)
		_walk(power, [-337, -130])
		var cutoff: int = Simulation.MAX_TICKS - power._lift_finish_budget()
		while power.tick < cutoff + (1 if late else 0): power.step({})
		power.step({"move_x": 0.125})
		for _index in range(5): power.step({})
		_check(power.snapshot().outcome.supplied_power and power.can_commit() == not late,
			"Actual lift-power eligibility includes the full route and response grace at its boundary: late=%s" % late)
		if late: _check(power.commit_reason().contains("earlier"), "Late powered source explains the timing failure truthfully")
	if checkpoint.is_empty(): return
	for late: bool in [false, true]:
		var throwing := _seed_at_throw_mark()
		var cutoff: int = Simulation.MAX_TICKS - throwing._seed_finish_budget()
		while throwing.tick < cutoff + (1 if late else 0): throwing.step({})
		throwing.step({"interact": true})
		_check(throwing.snapshot().outcome.threw_seed == not late,
			"Throw control reserves flight, delivery and two-second response grace: late=%s" % late)
		if not late:
			_walk(throwing, [360, 110])
			_check(throwing.can_commit(), "A boundary-valid throw still has time for its actual activation route")
	for activation_tick: int in [540, 541]:
		var activation := _seed_at_throw_mark()
		activation.step({"interact": true})
		_walk(activation, [360, 73])
		_check(not activation.snapshot().mechanisms.garden_open, "Approach stops just outside the actual garden activation radius")
		while activation.tick < activation_tick: activation.step({})
		activation.step({"move_z": 0.125})
		_check(activation.snapshot().mechanisms.garden_open and activation._activation_tick == activation_tick,
			"Garden activation timestamp derives from real movement at tick%d" % activation_tick)
		_check(activation.can_commit() == (activation_tick == 540), "Tick540 leaves two seconds; tick541 is too late for an acceptable source")
		if activation_tick == 541: _check(activation.commit_reason().contains("two seconds"), "A too-late activation explains the remaining response-time requirement")
	_check(int(first_a.duration_ticks) == 21 and int(first_b.duration_ticks) == 179 and int(second_a.duration_ticks) == 80 and int(second_b.duration_ticks) == 126,
		"Adding available human grace does not force the normal actual routes to wait longer")

func _seed_at_throw_mark() -> AfterYouFirstStepsSimulation:
	var simulation := Simulation.new()
	simulation.reset(definition, "a-place-to-grow", checkpoint)
	_walk(simulation, [230, -90])
	simulation.step({"interact": true})
	_walk(simulation, [140, -90])
	simulation.step({})
	return simulation

func _source_lift() -> AfterYouFirstStepsSimulation:
	var simulation := Simulation.new()
	simulation.reset(definition, "a-little-lift", initial)
	_walk(simulation, [-300, -130])
	for _index in range(6): simulation.step({})
	return simulation

func _source_seed(previous: Dictionary) -> AfterYouFirstStepsSimulation:
	var simulation := Simulation.new()
	simulation.reset(definition, "a-place-to-grow", previous)
	_walk(simulation, [230, -90])
	simulation.step({"interact": true})
	_walk(simulation, [140, -90])
	simulation.step({"interact": true})
	_walk(simulation, [360, 110])
	simulation.step({})
	return simulation

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

func _resume(record: Dictionary, previous: Dictionary, prior: Dictionary = {}) -> AfterYouFirstStepsSimulation:
	var simulation := Simulation.new()
	simulation.catch_assistance = record.catch_assistance
	simulation.reset(definition, record.stage_id, previous, prior, record.role)
	for input: Dictionary in Simulation.expand_recording_inputs(record): simulation.step(input)
	return simulation

func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _write_fixtures() -> void:
	var documents := {"a-little-lift-a": first_a, "a-little-lift-b": first_b, "lift-checkpoint": checkpoint,
		"a-place-to-grow-a": second_a, "a-place-to-grow-b": second_b, "final-checkpoint": final_checkpoint}
	for name: String in documents:
		var path := "res://tests/fixtures/first_steps/" + name + ".json"
		if FileAccess.file_exists(path):
			push_error("Refusing to overwrite fixture: " + name)
			failures += 1
			return
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(documents[name], "\t"))
		file.close()
	print("FIRST STEPS REAL CONTROL FIXTURES WRITTEN")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
