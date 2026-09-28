extends SceneTree

const World = preload("res://presentation/island_world.gd")
const RelayWorld = preload("res://presentation/relay_world.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const RelaySimulation = preload("res://core/v2/simulation_v2.gd")
const RelayCatalog = preload("res://core/v2/stage_catalog.gd")
const LighthouseCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_legacy_gate_lift_replay()
	await _test_plain_garden_and_replacement()
	await _test_relay_socket_readiness()
	await _test_lighthouse_has_no_garden()
	print("AFTER YOU GARDEN ACTIVATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_legacy_gate_lift_replay() -> void:
	var level: Dictionary = Levels.get_level("after-you")
	var first: Dictionary = _fixture("after-you-a")
	var second: Dictionary = _fixture("after-you-b")
	var untouched_records := Canonical.digest([first, second, level])
	_check(Simulation.verify_recording(level, first).valid and Simulation.verify_recording(level, second, first).valid,
		"Existing immutable A/B fixtures verify before their presentation is changed")
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.home_view = false
	world.load_level(level)
	var source := Simulation.new()
	_check(source.reset(level), "The authored gate-and-lift island initializes")
	var initial: Dictionary = source.snapshot()
	world.present(initial, true)
	var closed_pose := _pose(world)
	var closed_reach := _petal_reach(world)
	_check(world.garden_state == "closed" and not world.goal_ring.visible,
		"The initially unavailable garden has folded leaves and an incomplete ring")
	_check(_emission(world) == 0.0 and not world.bloomed, "Unavailable garden has no ready emission or flowers")
	_check(world.garden_activation.get_parent() == world.garden and world.goal_ring.get_parent() == world.garden,
		"Activation leaves and ring share the planter's moving root")
	_check(_count(world.garden_activation, "MeshInstance3D") == 4, "Only four small cue meshes are added")
	_check(_count(world, "OmniLight3D") == 0 and _count(world, "CollisionObject3D") == 0,
		"The garden cue introduces no point light or gameplay collision")
	world.load_level(level)
	world.present(initial, true)
	_check(_pose(world) == closed_pose,
		"Rebuilding the same closed garden restores every flower, blossom and leaf-bed pose")
	var cue_positions := _global_positions(world.garden_activation)
	var snapshots_untouched := true
	var accurate_readiness := true
	var saw_raised_closed := false
	var saw_ready := false
	var lift_translation_exact := false
	for input: Dictionary in Simulation.expand_recording_inputs(first):
		var state: Dictionary = source.step(input)
		var before := Canonical.digest(state)
		world.present(state, true)
		snapshots_untouched = snapshots_untouched and Canonical.digest(state) == before
		var expected_ready: bool = bool(state.gate_open) and bool(state.lift_ready)
		accurate_readiness = accurate_readiness and world.garden_state == ("ready" if expected_ready else "closed")
		if state.lift_ready and not state.gate_open:
			saw_raised_closed = true
			lift_translation_exact = _translated(cue_positions, _global_positions(world.garden_activation), float(state.lift_height) / 100.0)
		if expected_ready:
			saw_ready = true
	_check(accurate_readiness and saw_raised_closed and saw_ready,
		"Real recorded controls keep the raised garden closed until the separate garden plate opens it")
	_check(lift_translation_exact, "Every folded cue child travels by the exact simulation lift delta")
	_check(world.garden_state == "ready" and world.goal_ring.visible and _emission(world) > 0.0,
		"Gate and lift readiness produce the full warm ring immediately")
	_check(_pose(world) != closed_pose and _petal_reach(world) > closed_reach,
		"Ready leaves open out geometrically instead of communicating only by color")
	_check(_flowers_at(world, 0.001), "Readiness does not pretend that a seed was already planted")
	var ready_pose := _pose(world)
	var receiver := Simulation.new()
	_check(receiver.reset(level, first, "b"), "Combined replay starts from the exact accepted earlier recording")
	for input: Dictionary in Simulation.expand_recording_inputs(second):
		var state: Dictionary = receiver.step(input)
		var before := Canonical.digest(state)
		world.present(state, true)
		snapshots_untouched = snapshots_untouched and Canonical.digest(state) == before
	_check(receiver.complete and receiver.state_hash() == second.final_state_hash,
		"Garden presentation retains the original completed replay outcome")
	_check(world.garden_state == "completed" and world.bloomed and _flowers_at(world, 1.0),
		"Seeking directly to completed replay shows the whole bloom immediately")
	_check(_pose(world) != ready_pose and world.goal_ring.visible and _emission(world) > 0.0,
		"Completed flowers and flatter leaves remain distinct from the ready planter")
	_check(is_equal_approx(world.garden.global_position.y, float(level.lift.height) / 100.0),
		"Completed planter, ring, leaves and flowers remain at the raised goal height")
	world.present(initial, true)
	_check(_pose(world) == closed_pose and _flowers_at(world, 0.001),
		"Backward replay seek restores the original closed pose without a stale bloom")
	var completed: Dictionary = receiver.snapshot()
	var completed_before := Canonical.digest(completed)
	world.present(completed, false)
	world._process(0.25)
	var growing_pose := _pose(world)
	var early_height: float = world.flowers[0].scale.y
	world.present(completed, false)
	world._process(0.25)
	_check(early_height > 0.001 and early_height < 1.0 and world.flowers[0].scale.y > early_height,
		"Ordinary playback after rewind grows the flowers across repeated completed snapshots")
	world.reduced_motion = true
	world.present(completed, false)
	var reduced_pose := _pose(world)
	_check(_flowers_at(world, 1.0), "Enabling reduced motion during growth immediately settles the completed garden")
	world._process(1.0 / 30.0)
	world._process(0.7)
	_check(_pose(world) == reduced_pose, "Reduced-motion garden pose has no pulse, sway or delayed opening")
	world.reduced_motion = false
	world.present(completed, false)
	world._process(0.7)
	_check(_pose(world) == reduced_pose, "Disabling reduced motion does not restart an already settled bloom")
	world.present(initial, true)
	world.present(completed, false)
	world._process(0.25)
	_check(_pose(world) == growing_pose,
		"Rewinding the settled garden allows the same visible bloom to play again")
	_check(snapshots_untouched and Canonical.digest(completed) == completed_before and Canonical.digest([first, second, level]) == untouched_records,
		"Repeated presentation never mutates a snapshot, definition or either committed recording")
	world.queue_free()
	await process_frame

func _test_plain_garden_and_replacement() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.load_level(Levels.get_level("after-you"))
	var old_activation: Node3D = world.garden_activation
	var old_blossom_mesh: WeakRef = weakref(_first_blossom_petal(world).mesh)
	var level: Dictionary = Levels.get_level("first-light")
	world.load_level(level)
	_check(_first_blossom_petal(world).mesh != old_blossom_mesh.get_ref(),
		"Replacing a garden creates geometry with its own lifetime")
	var simulation := Simulation.new()
	simulation.reset(level)
	var state: Dictionary = simulation.snapshot()
	world.present(state, true)
	_check(state.gate_open and state.lift_ready and world.garden_state == "ready",
		"A garden with no gate or lift is ready from its actual initial simulation state")
	_check(is_zero_approx(world.garden.position.y) and world.garden_petals.size() == 4,
		"Changing levels creates one fresh grounded cue without retaining lift state")
	await process_frame
	_check(not is_instance_valid(old_activation), "Replaced garden meshes are released with the old terrain")
	_check(old_blossom_mesh.get_ref() == null, "Replacing the terrain releases its blossom geometry")
	var other_world := World.new()
	root.add_child(other_world)
	other_world.set_process(false)
	other_world.load_level(level)
	var petal := _first_blossom_petal(world)
	var neighbor := petal.get_parent().get_child(1) as MeshInstance3D
	var other_petal := _first_blossom_petal(other_world)
	_check(petal.mesh != other_petal.mesh, "Separate worlds keep independent blossom geometry")
	var petal_material := petal.material_override as StandardMaterial3D
	var neighbor_material := neighbor.material_override as StandardMaterial3D
	var other_material := other_petal.material_override as StandardMaterial3D
	var neighbor_color := neighbor_material.albedo_color
	var other_color := other_material.albedo_color
	petal_material.albedo_color = Color.MAGENTA
	_check(neighbor_material.albedo_color == neighbor_color and other_material.albedo_color == other_color,
		"Changing one blossom petal's material leaves neighboring petals and other worlds unchanged")
	other_world.queue_free()
	# Presentation-boundary truth table is deliberately separate from valid replay evidence.
	for flags: Array in [[false, true], [true, false], [false, false], [true, true]]:
		var boundary := state.duplicate(true)
		boundary.gate_open = flags[0]
		boundary.lift_ready = flags[1]
		var before := Canonical.digest(boundary)
		world.present(boundary, true)
		_check((world.garden_state == "ready") == (flags[0] and flags[1]) and Canonical.digest(boundary) == before,
			"Presentation requires both supplied readiness flags and leaves its input untouched: %s" % [flags])
	world.queue_free()
	await process_frame

func _test_relay_socket_readiness() -> void:
	var level := RelayCatalog.relay_isles()
	var world := RelayWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.load_level(level)
	var initial: Dictionary = _fixture("v2/initial-checkpoint")
	var simulation := RelaySimulation.new()
	_check(simulation.reset(level, "relay", initial), "Relay starts from its existing exact checkpoint")
	var state: Dictionary = simulation.snapshot()
	var before := Canonical.digest(state)
	world.present(state, true)
	_check(world.garden_state == "ready" and world.goal_ring.visible and not state.bridges["relay-east"],
		"Relay's ungated socket is ready even when its separate approach bridge is closed")
	_check(not state.has("gate_open") and not state.has("lift_ready") and Canonical.digest(state) == before,
		"Relay readiness does not invent or add legacy gate and lift fields")
	var first_complete: Dictionary = RelaySimulation.verify_recording(level, _fixture("v2/relay-b"), initial, _fixture("v2/relay-a"))
	_check(first_complete.valid, "Existing first Relay pair still verifies")
	if first_complete.valid:
		world.present(first_complete.snapshot, true)
		_check(world.garden_state == "ready" and not world.bloomed and _flowers_at(world, 0.001),
			"Completing the relay socket does not falsely bloom the final garden")
	var final_complete: Dictionary = RelaySimulation.verify_recording(level, _fixture("v2/garden-b"), _fixture("v2/relay-checkpoint"), _fixture("v2/garden-a"))
	_check(final_complete.valid, "Existing final Relay pair still verifies")
	if final_complete.valid:
		var final_before := Canonical.digest(final_complete.snapshot)
		world.present(final_complete.snapshot, true)
		_check(world.garden_state == "completed" and _flowers_at(world, 1.0) and Canonical.digest(final_complete.snapshot) == final_before,
			"Only the actual final Relay completion blooms the garden, without changing its proof")
	world.load_level(level)
	world.present(state, true)
	_check(world.garden_petals.size() == 4 and world.garden_state == "ready" and _flowers_at(world, 0.001),
		"Reopening Relay replaces the old completed cue and keeps one clean ready planter")
	world.queue_free()
	await process_frame

func _test_lighthouse_has_no_garden() -> void:
	var world := LighthouseWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.load_level(LighthouseCatalog.definition())
	_check(world.garden == null and world.garden_activation == null and world.garden_petals.is_empty() and world.flowers.is_empty(),
		"Lighthouse creates no garden, activation leaves or flowers through its base-class helpers")
	_check(world.find_children("GardenActivation", "", true, false).is_empty(),
		"No phantom planter or activation geometry appears in the Lighthouse scene")
	world.queue_free()
	await process_frame

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))

func _first_blossom_petal(world: Node3D) -> MeshInstance3D:
	return world.flowers[0].get_node("FlowerGeometry/Blossom").get_child(0) as MeshInstance3D

func _emission(world: Node3D) -> float:
	var material: StandardMaterial3D = world.goal_ring.material_override
	return material.emission_energy_multiplier if material.emission_enabled else 0.0

func _pose(world: Node3D) -> Array:
	var result: Array = [world.garden_state, world.goal_ring.visible, _emission(world), world.garden.transform]
	for petal: Node3D in world.garden_petals:
		result.append(petal.transform)
	for flower: Node3D in world.flowers:
		result.append(flower.transform)
		var geometry := flower.get_node("FlowerGeometry") as Node3D
		result.append(geometry.basis)
		result.append((geometry.get_node("Blossom") as Node3D).transform)
	for child: Node in world.garden.get_children():
		if child is Node3D and str(child.name).begins_with("GardenLeafBed"):
			result.append((child as Node3D).transform)
	return result

func _petal_reach(world: Node3D) -> float:
	var reach := 0.0
	for petal: Node3D in world.garden_petals:
		var leaf := petal.get_node("Leaf") as MeshInstance3D
		var point: Vector3 = world.garden.to_local(leaf.global_position)
		reach = maxf(reach, Vector2(point.x, point.z).length())
	return reach

func _flowers_at(world: Node3D, size: float) -> bool:
	if world.flowers.is_empty(): return false
	for flower: Node3D in world.flowers:
		if not flower.scale.is_equal_approx(Vector3.ONE * size): return false
	return true

func _global_positions(node: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = [node.global_position]
	for child: Node in node.get_children():
		if child is Node3D: result.append_array(_global_positions(child))
	return result

func _translated(before: Array[Vector3], after: Array[Vector3], delta_y: float) -> bool:
	if before.size() != after.size(): return false
	for index in range(before.size()):
		if not after[index].is_equal_approx(before[index] + Vector3(0, delta_y, 0)): return false
	return true

func _count(node: Node, type_name: String) -> int:
	var count := 1 if node.is_class(type_name) else 0
	for child: Node in node.get_children(): count += _count(child, type_name)
	return count

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
