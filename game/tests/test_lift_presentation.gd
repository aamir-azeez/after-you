extends SceneTree

const World = preload("res://presentation/island_world.gd")
const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for level_id in ["rising-together", "after-you"]:
		await _test_lift(level_id)
	await _test_level_replacement()
	print("AFTER YOU LIFT PRESENTATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_lift(level_id: String) -> void:
	var level: Dictionary = Levels.get_level(level_id)
	var first: Dictionary
	var second: Dictionary
	if level_id == "after-you":
		first = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/after-you-a.json"))
		second = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/after-you-b.json"))
	else:
		first = _solve_a(level).export_recording()
		second = _solve_b(level, first).export_recording()
	_check(Simulation.verify_recording(level, first).valid, level_id + " first turn has authoritative simulation validity")
	_check(Simulation.verify_recording(level, second, first).valid, level_id + " second turn has authoritative simulation validity")
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.home_view = false
	world.load_level(level)
	var fresh := Simulation.new()
	fresh.reset(level, first, "b")
	world.present(fresh.snapshot(), true)
	var deck := world.lift as Node3D
	var guides := world.terrain.get_node("GuideMechanism") as Node3D
	var zone: Array = level.lift.zone
	var start := Vector2(float(zone[0]), float(zone[1])) / 100.0
	var end := Vector2(float(zone[2]), float(zone[3])) / 100.0
	var base := deck.get_node("DeckBase") as MeshInstance3D
	var base_bounds: AABB = base.global_transform * base.get_aabb()
	_check(Vector2(base_bounds.position.x, base_bounds.position.z).is_equal_approx(start) and Vector2(base_bounds.end.x, base_bounds.end.z).is_equal_approx(end), level_id + " deck covers the exact authored rectangular footprint")
	var structural_meshes := _meshes(deck) + _meshes(guides)
	_check(structural_meshes.size() <= 32, level_id + " lift and support mechanism keep a bounded mesh budget")
	_check(_has_no_collision(world), level_id + " presentation adds no physics or collision objects")
	_check(world.garden.get_node("Planter").get_parent() == world.garden and world.garden.get_node("Soil").get_parent() == world.garden and world.goal_ring.get_parent() == world.garden, level_id + " soil, planter and goal marker share the flower movement root")
	var moving := _spatials(world.garden) + _spatials(world.landing_marker)
	var initial_positions: Array[Vector3] = []
	for node: Node3D in moving:
		initial_positions.append(node.global_position)
	var all_translated := true
	var structure_within_footprint := true
	var clear_surface := true
	var guides_anchored := true
	var max_height := float(level.lift.height) / 100.0
	for height: float in [0.0, max_height / 2.0, max_height, 0.0]:
		var state := fresh.snapshot()
		state.lift_height = roundi(height * 100.0)
		world.present(state, true)
		for index in range(moving.size()):
			all_translated = all_translated and moving[index].global_position.is_equal_approx(initial_positions[index] + Vector3(0, height, 0))
		for node: MeshInstance3D in structural_meshes:
			var bounds: AABB = node.global_transform * node.get_aabb()
			structure_within_footprint = structure_within_footprint and bounds.position.x >= start.x - 0.0001 and bounds.position.z >= start.y - 0.0001 and bounds.end.x <= end.x + 0.0001 and bounds.end.z <= end.y + 0.0001
			if node.visible:
				clear_surface = clear_surface and bounds.end.y <= height + 0.0001
		for node: MeshInstance3D in _meshes(deck.get_node("Planks")):
			var bounds: AABB = node.global_transform * node.get_aabb()
			clear_surface = clear_surface and is_equal_approx(bounds.end.y, height)
		for node: MeshInstance3D in world.lift_guides:
			var bounds: AABB = node.global_transform * node.get_aabb()
			guides_anchored = guides_anchored and is_equal_approx(bounds.position.y, -0.015) and node.visible == (height > 0.165)
	_check(all_translated, level_id + " every planter, flower and landing-marker child travels by the full rise and returns without drift")
	_check(structure_within_footprint, level_id + " deck, supports and guides stay within the authored horizontal footprint at every height")
	_check(clear_surface, level_id + " all planks align with the simulation walking surface and structure never blocks above it")
	_check(guides_anchored, level_id + " guide feet stay grounded as the shaft extends below the moving platform")
	_check(is_zero_approx(world.actors.a.position.y), level_id + " the earlier ghost stays on its original ground route")
	world.reduced_motion = true
	var untouched := true
	var original_first := JSON.stringify(first)
	var original_second := JSON.stringify(second)
	for input: Dictionary in Simulation.expand_recording_inputs(second):
		var state := fresh.step(input)
		var original_state := JSON.stringify(state)
		world.present(state, true)
		world._process(1.0 / 30.0)
		untouched = untouched and JSON.stringify(state) == original_state
	_check(fresh.complete and fresh.state_hash() == second.final_state_hash, level_id + " complete lift replay retains its exact recorded outcome")
	_check(untouched and JSON.stringify(first) == original_first and JSON.stringify(second) == original_second, level_id + " presentation never mutates snapshots or either recording")
	_check(world.bloomed and is_equal_approx(world.garden.position.y, max_height) and is_equal_approx(world.actors.b.position.y, max_height), level_id + " successful planting, receiver and entire garden share the raised surface")
	_check(world.reduced_motion and world.actors.b.motion_blend == 0.0, level_id + " lift presentation preserves reduced-motion behavior")
	world.queue_free()
	await process_frame

func _test_level_replacement() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.load_level(Levels.get_level("after-you"))
	var prior_terrain := world.terrain
	var prior_lift := world.lift
	var prior_guides: Array = world.lift_guides.duplicate()
	var ground: Dictionary = Levels.get_level("first-light")
	world.load_level(ground)
	_check(world.lift == null and world.lift_guides.is_empty() and prior_terrain.get_parent() == null, "Loading a ground island detaches the old lift terrain and clears its references")
	var simulation := Simulation.new()
	simulation.reset(ground)
	var snapshot := simulation.snapshot()
	snapshot.lift_height = 999
	world.present(snapshot, true)
	_check(is_zero_approx(world.garden.position.y) and is_zero_approx(world.landing_marker.position.y), "A non-lift island keeps its full garden and landing markers grounded")
	await process_frame
	_check(not is_instance_valid(prior_lift) and not is_instance_valid(prior_guides[0]), "Replaced lift meshes and guide shafts are released after the queued frame")
	world.load_level(Levels.get_level("rising-together"))
	_check(world.lift_guides.size() == 4 and is_zero_approx(world.lift.position.y), "Loading a different lift starts with one fresh mechanism at ground height")
	world.queue_free()
	await process_frame

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_meshes(child))
	return result

func _spatials(node: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if node is Node3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_spatials(child))
	return result

func _has_no_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		return false
	for child in node.get_children():
		if not _has_no_collision(child):
			return false
	return true

func _solve_a(level: Dictionary) -> AfterYouSimulation:
	var simulation := Simulation.new()
	simulation.reset(level)
	_walk(simulation, level.plate)
	while (not simulation.snapshot().bridge_open or not simulation.snapshot().lift_ready) and not simulation.finished:
		simulation.step({})
	simulation.step({"interact": true})
	simulation.step({})
	if level.has("gate"):
		_walk(simulation, level.gate.plate)
	while not simulation.finished:
		simulation.step({})
	return simulation

func _solve_b(level: Dictionary, first: Dictionary) -> AfterYouSimulation:
	var simulation := Simulation.new()
	simulation.reset(level, first, "b")
	_walk(simulation, [int(level.starts.b[0]), int(level.bridge.z)])
	while not simulation.snapshot().bridge_open and not simulation.finished:
		simulation.step({})
	_walk(simulation, [int(level.landing[0]), int(level.bridge.z)])
	_walk(simulation, level.landing)
	while simulation.snapshot().seed.status != "held_b" and not simulation.finished:
		simulation.step({})
	_walk(simulation, level.goal)
	while not simulation.snapshot().gate_open and not simulation.finished:
		simulation.step({})
	simulation.step({"interact": true})
	return simulation

func _walk(simulation: AfterYouSimulation, target: Array) -> void:
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		while not simulation.finished:
			var position: Dictionary = simulation.snapshot().players[simulation.role]
			var distance := int(target[index]) - int(position[axis])
			if absi(distance) <= 1:
				break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + axis] = clampf(float(distance) / Simulation.MOVE_PER_TICK, -1, 1)
			simulation.step(input)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
