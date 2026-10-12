extends SceneTree
## The thrown seed tumbles while it flies and stands upright otherwise. The spin
## is presentation only: it follows the flown distance, so two presentations of
## the same recording pose the seed identically, and reduced motion keeps it still.
const Registry = preload("res://services/chapter_registry.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const DELTA := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _fixture(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + path + ".json"))
	return parsed if parsed is Dictionary else {}

func _run() -> void:
	var cases := [
		{"label": "First Steps", "key": Registry.FIRST_STEPS, "stage": "a-place-to-grow", "checkpoint": _fixture("first_steps/lift-checkpoint"), "record": _fixture("first_steps/a-place-to-grow-a")},
		{"label": "Relay", "key": Registry.RELAY, "stage": "relay", "checkpoint": Registry.initial_checkpoint(Registry.RELAY), "record": _fixture("v2/relay-a")},
		{"label": "Earlier Islands", "key": "", "record": _fixture("first-light-a")},
	]
	for case: Dictionary in cases:
		_check(not case.record.is_empty(), case.label + " fixture recording is present")
		if case.record.is_empty(): continue
		var first := _present(case, false)
		var second := _present(case, false)
		var still := _present(case, true)
		_check(first.flying > 4 and first.max_angle > 0.6, case.label + ": the thrown seed turns while it flies (%d flying frames, %.2f rad)" % [first.flying, first.max_angle])
		_check(first.upright_ok and first.settled > 0, case.label + ": held, waiting and planted seeds stand upright (%d frames)" % first.settled)
		_check(first.glow_ok, case.label + ": the billboard glow keeps an unrotated transform while the seed spins")
		_check(first.leaves_follow, case.label + ": stem and leaf turn with the body")
		_check(first.poses == second.poses and not first.poses.is_empty(), case.label + ": two presentations of the same throw pose the seed identically")
		_check(still.flying == first.flying and is_zero_approx(still.max_angle), case.label + ": reduced motion keeps the flying seed upright")
	print("AFTER YOU SEED SPIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _present(case: Dictionary, reduced: bool) -> Dictionary:
	var world: Node3D
	var sim: RefCounted
	var inputs: Array
	if str(case.key).is_empty():
		var island := IslandWorld.new()
		island.home_view = false
		world = island
		root.add_child(world)
		world.set_process(false)
		var level := Levels.get_level(0)
		world.load_level(level)
		sim = LegacySimulation.new()
		sim.reset(level, {}, "a", int(case.record.simulation_version))
		inputs = LegacySimulation.expand_recording_inputs(case.record)
	else:
		var level := Registry.definition(case.key)
		world = Registry.world_script(case.key).new()
		root.add_child(world)
		world.set_process(false)
		world.load_level(level)
		for item: Dictionary in level.stages:
			if item.id == case.stage: world.show_stage(item)
		sim = Registry.simulation_script(case.key).new()
		Registry.reset_simulation(sim, case.key, level, case.stage, case.checkpoint, {}, "a", case.record)
		inputs = sim.expand_recording_inputs(case.record)
	world.reduced_motion = reduced
	world.present(sim.snapshot(), true)
	var result := {"flying": 0, "settled": 0, "max_angle": 0.0, "upright_ok": true, "glow_ok": true, "leaves_follow": true, "poses": []}
	var seed: Node3D = world.seed
	var glow := seed.get_node("SeedGlow") as Node3D
	var leaf := seed.get_node("SeedLeaf0") as Node3D
	for input: Dictionary in inputs:
		var state: Dictionary = sim.step(input)
		world.present(state)
		for frame in range(2):
			world._process(DELTA)
			var status := str(state.seed.status)
			var turn: Quaternion = seed.quaternion
			var angle := turn.get_angle()
			result.poses.append([status, snappedf(turn.x, 0.0001), snappedf(turn.y, 0.0001), snappedf(turn.z, 0.0001), snappedf(turn.w, 0.0001)])
			if status == "flying":
				result.flying += 1
				result.max_angle = maxf(result.max_angle, angle)
				var parent_turn: Quaternion = seed.get_parent().global_basis.get_rotation_quaternion()
				result.glow_ok = result.glow_ok and glow.global_basis.get_rotation_quaternion().is_equal_approx(parent_turn)
				result.leaves_follow = result.leaves_follow and leaf.get_parent() == seed and (leaf.global_position - seed.global_position).is_equal_approx(seed.global_basis * leaf.position)
			elif status in ["held", "waiting", "planted"] or status.begins_with("held_"):
				result.settled += 1
				result.upright_ok = result.upright_ok and turn.is_equal_approx(Quaternion.IDENTITY) and glow.quaternion.is_equal_approx(Quaternion.IDENTITY)
	world.free()
	return result

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
