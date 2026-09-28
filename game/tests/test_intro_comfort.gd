extends SceneTree

const Legacy = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const Lift = preload("res://core/first_steps/simulation.gd")
const Catalog = preload("res://core/first_steps/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Journey = preload("res://services/relay_journey.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Objective = preload("res://presentation/objective_panel.gd")
var checks := 0
var failures := 0
var comfort_lift: Dictionary = {}
var comfort_garden: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_legacy_handoffs()
	_late_lift()
	_retained_stage_boundaries()
	if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args():
		var path := "res://tests/fixtures/comfort8/first-steps.json"
		_check(not FileAccess.file_exists(path), "New evidence must not overwrite retained fixture bytes")
		if not FileAccess.file_exists(path):
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file := FileAccess.open(path, FileAccess.WRITE)
			_check(file != null, "New fixture destination is writable")
			if file != null: file.store_string(JSON.stringify({"pairs": [comfort_lift, comfort_garden]}, "\t") + "\n")
	print("INTRO COMFORT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _legacy_handoffs() -> void:
	for definition: Dictionary in Levels.all_levels():
		for late: bool in [false, true]:
			var a := Legacy.new()
			_check(a.reset(definition, {}, "a", 8), "New earlier-island source starts: " + definition.id)
			_walk(a, definition.plate)
			while not a.snapshot().bridge_open or not a.snapshot().lift_ready:
				if a.finished: break
				a.step({})
			if late: _wait_until(a, 550)
			a.step({"interact": true})
			a.step({})
			if definition.has("gate"): _walk(a, definition.gate.plate)
			_wait_until(a, 600)
			var source := a.export_recording()
			_check(a.tick == 600 and source.simulation_version == 8, "Source uses the full unchanged first-player clock")
			_check(a.can_commit() and Legacy.verify_recording(definition, source).valid, "Source is replayable after an actual late/early throw: %s/%s" % [definition.id, late])
			var b := Legacy.new()
			if not b.reset(definition, source, "b"):
				_check(false, "Receiver accepts verified source: " + definition.id)
				continue
			_wait_until(b, 650)
			_check(not b.finished and b.snapshot().duration_ticks == 900, "Receiver still has time after the former deadline: " + definition.id)
			_check(b.snapshot().seed.status in ["waiting", "flying"], "Unclaimed seed stays available through the receiver's turn: " + definition.id)
			_walk(b, [int(definition.starts.b[0]), int(definition.bridge.z)])
			_walk(b, [int(definition.landing[0]), int(definition.bridge.z)])
			_walk(b, definition.landing)
			while b.snapshot().seed.status != "held_b" and not b.finished: b.step({})
			_walk(b, definition.goal)
			b.step({"interact": true})
			_check(b.complete and b.tick < 900, "Real delayed receiver route completes: %s/%s at%d" % [definition.id, late, b.tick])
			_check(Legacy.verify_recording(definition, b.export_recording(), source).valid, "Long receiver recording verifies exactly: " + definition.id)
			_check(Canonical.same(source, a.export_recording()), "Receiver does not alter source evidence")
	var lift := Legacy.new()
	lift.reset(Levels.get_level("rising-together"), {}, "a", 8)
	_walk(lift, lift.level.plate)
	var meter := Objective.legacy_progress(lift.snapshot(), Legacy.TICK_RATE)
	_check(meter.get("unit") == "seconds" and meter.required == 85.0 / 30.0, "Earlier lift exposes its actual hold requirement")

func _late_lift() -> void:
	var definition := Catalog.definition()
	var initial := Catalog.initial_checkpoint()
	var a := Lift.new()
	a.reset(definition, "a-little-lift", initial, {}, "a", 8)
	_walk(a, [-300, -130])
	for _i in range(12): a.step({})
	_walk(a, [-430, -130])
	var credited: int = a._power_ticks
	_check(credited > 0 and not a.snapshot().controls["lift-power"], "The source really leaves the pad before the late return")
	_wait_until(a, 574)
	_check(a._power_ticks == credited, "Time away pauses accumulated power")
	_walk(a, [-300, -130])
	_check(a.tick >= 590 and a.tick < 600 and a.snapshot().controls["lift-power"], "The return uses real late movement onto the pad")
	_wait_until(a, 600)
	_check(a.tick == 600 and a._power_ticks > credited and a.can_commit(), "Stepping off and returning near the end retains usable power")
	var source := a.export_recording()
	_check(Lift.verify_recording(definition, source, initial).valid, "Late interrupted source replays exactly")
	var b := Lift.new()
	if not b.reset(definition, "a-little-lift", initial, source, "b"):
		_check(false, "Late source admits receiver")
		return
	# Give a human three seconds after the source has finished its late return.
	_wait_until(b, 690)
	_check(b.tick - a.tick == 90 and not b.finished, "Receiver actually spends the three-second response margin before moving")
	_walk(b, [-20, 0])
	while b.snapshot().mechanisms.lift.phase != "upper" and not b.finished: b.step({})
	_walk(b, [230, 0])
	b.step({"interact": true})
	_check(b.complete and b.tick <= 810, "Late lift source still leaves a real ride, crossing and three-second response margin: %d" % b.tick)
	var pair := Lift.derive_checkpoint(definition, initial, source, b.export_recording())
	_check(pair.valid, "Extended lift receiver produces a verified checkpoint")
	if pair.valid:
		comfort_lift = {"a": source, "b": b.export_recording(), "checkpoint": pair.checkpoint}
		comfort_garden = _garden_pair(pair.checkpoint, true)

func _retained_stage_boundaries() -> void:
	for version: int in [4, 5]:
		var prefix := "a-little-lift" if version == 4 else "cumulative-lift"
		var old_a := _fixture(prefix + "-a.json")
		var old_b := _fixture(prefix + "-b.json")
		var source_digest := Canonical.digest(old_a)
		var receiver_digest := Canonical.digest(old_b)
		var path := "user://intro-comfort-%d-%d.json" % [version, Time.get_ticks_usec()]
		var journal := Journey.new(path, null, Registry.FIRST_STEPS)
		journal.load_data()
		_check(journal.accept_recording(old_a) and journal.accept_recording(old_b), "Retained%d lift is accepted without rewriting it" % version)
		var reopened := Journey.new(path, null, Registry.FIRST_STEPS)
		reopened.load_data()
		var fresh: RefCounted = reopened.create_live_simulation()
		_check(fresh != null and fresh.simulation_version == 8, "Fresh next-stage rehearsal opts into current rules after retained%d" % version)
		if fresh != null:
			fresh.step({})
			_check(reopened.save_live_draft(fresh), "New stage saves over its retained prefix")
			var resumed := Journey.new(path, null, Registry.FIRST_STEPS)
			resumed.load_data()
			var exact: RefCounted = resumed.create_live_simulation(true)
			if exact != null:
				for frame: Dictionary in Lift.expand_recording_inputs(resumed.draft()): exact.step(frame)
			_check(exact != null and Canonical.same(exact.export_recording(), fresh.export_recording()), "Cold resume preserves the exact new draft and old prefix")
			var garden := _garden_pair(resumed.checkpoint(), false)
			if not garden.is_empty():
				_check(resumed.accept_recording(garden.a) and resumed.accept_recording(garden.b) and resumed.chapter_complete(), "Mixed historical/current pairs complete the local journal")
				var final := Journey.new(path, null, Registry.FIRST_STEPS)
				final.load_data()
				_check(final.chapter_complete() and Lift.verify_checkpoint(Catalog.definition(), final.checkpoint()).valid, "Cold completed mixed proof verifies both stages")
				var pairs: Array = final.pairs()
				_check(pairs.size() == 2 and Canonical.digest(pairs[0].a) == source_digest and Canonical.digest(pairs[0].b) == receiver_digest, "Historical pair canonical evidence remains unchanged")
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _garden_pair(checkpoint: Dictionary, late: bool) -> Dictionary:
	var definition := Catalog.definition()
	var a := Lift.new()
	if not a.reset(definition, "a-place-to-grow", checkpoint, {}, "a", 8):
		_check(false, "New garden source accepts exact previous checkpoint")
		return {}
	_walk(a, [230, -90])
	a.step({"interact": true})
	_walk(a, [140, -90])
	a.step({})
	if late: _wait_until(a, 540)
	a.step({"interact": true})
	_walk(a, [360, 110])
	_check(a.can_commit(), "Actual seed take/throw/control route is a viable source")
	if late: _check(a.tick >= 590 and a.tick <= 600 and a._activation_tick >= 580, "Late garden handoff includes the actual trip from throw mark to activation pad")
	var source := a.export_recording()
	var b := Lift.new()
	if not b.reset(definition, "a-place-to-grow", checkpoint, source, "b"):
		_check(false, "Garden receiver admits exact source")
		return {}
	_wait_until(b, 690)
	_check(not b.finished and b.snapshot().seed.status == "waiting", "Seed remains available beyond the old turn deadline")
	if late:
		_check(b.tick - a.tick >= 90, "Receiver actually hesitates for at least three seconds after the late source ends")
	else:
		_check(b.tick - b._land_tick > int(definition.seed_wait_ticks), "Early seed remains available beyond the old independent catch timer")
	_walk(b, [-340, 0])
	while not b.snapshot().outcome.caught_seed and not b.finished: b.step({})
	_walk(b, [-300, 130])
	b.step({"interact": true})
	_check(b.complete and b.tick <= 810, "Garden receiver can hesitate for three seconds after late handoff and still finish: %d" % b.tick)
	var receiver := b.export_recording()
	var completed := Lift.derive_checkpoint(definition, checkpoint, source, receiver)
	_check(completed.valid and Lift.verify_checkpoint(definition, completed.get("checkpoint", {})).valid, "Full nested checkpoint verifies both actual pairs")
	return {"a": source, "b": receiver, "checkpoint": completed.checkpoint} if completed.valid else {}

func _wait_until(simulation: RefCounted, target: int) -> void:
	while simulation.tick < target and not simulation.finished: simulation.step({})

func _walk(simulation: RefCounted, target: Array) -> void:
	for axis: String in ["x", "z"]:
		for _i in range(950):
			if simulation.finished: break
			var slot: String = simulation.role if simulation is Legacy else simulation.active_slot
			var position: Dictionary = simulation.snapshot().players[slot]
			var distance := int(target[0 if axis == "x" else 1]) - int(position[axis])
			if absi(distance) <= 1: break
			var frame := {"move_x": 0.0, "move_z": 0.0}
			frame["move_" + axis] = clampf(float(distance) / 8.0, -1, 1)
			simulation.step(frame)
	var final_slot: String = simulation.role if simulation is Legacy else simulation.active_slot
	var final_position: Dictionary = simulation.snapshot().players[final_slot]
	_check(absi(int(final_position.x) - int(target[0])) <= 1 and absi(int(final_position.z) - int(target[1])) <= 1,
		"Native route reaches its actual waypoint (%s,%s), tick%d" % [target[0], target[1], simulation.tick])

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/" + name))

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)
