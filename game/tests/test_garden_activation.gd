extends SceneTree

const World = preload("res://presentation/island_world.gd")
const RelayWorld = preload("res://presentation/relay_world.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const HomeLayout = preload("res://presentation/home_layout.gd")
const RelaySimulation = preload("res://core/v2/simulation_v2.gd")
const RelayCatalog = preload("res://core/v2/stage_catalog.gd")
const LighthouseCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_plain_garden_and_replacement()
	await _test_relay_socket_readiness()
	await _test_lighthouse_has_no_garden()
	print("AFTER YOU GARDEN ACTIVATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every flower, blossom and leaf-bed mesh of the garden's bloom.
func _bloom_meshes(world: Node3D) -> int:
	var count := 0
	for root_node: Node3D in world.flowers + world._garden_cover: count += _count(root_node, "MeshInstance3D")
	return count

## Those of them drawn now.
func _drawn_bloom(world: Node3D) -> int:
	var count := 0
	for root_node: Node3D in world.flowers + world._garden_cover:
		for mesh: Node in root_node.find_children("*", "MeshInstance3D", true, false):
			if (mesh as Node3D).is_visible_in_tree(): count += 1
	return count

func _test_plain_garden_and_replacement() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.load_level(HomeLayout.LEVEL)
	var old_activation: Node3D = world.garden_activation
	var old_blossom_mesh: WeakRef = weakref(_first_blossom_petal(world).mesh)
	var level: Dictionary = HomeLayout.LEVEL
	world.load_level(level)
	_check(_first_blossom_petal(world).mesh != old_blossom_mesh.get_ref(),
		"Replacing a garden creates geometry with its own lifetime")
	var state: Dictionary = HomeLayout.opening()
	world.present(state, true)
	_check(state.gate_open and state.lift_ready and world.garden_state == "ready",
		"A garden with no gate or lift is ready from its opening state")
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
	# Petals of one colour share the kit's look; a petal recoloured takes its
	# own copy first (Primitives.own_material), as every world's code does.
	var neighbor_material := neighbor.material_override as StandardMaterial3D
	var other_material := other_petal.material_override as StandardMaterial3D
	var neighbor_color := neighbor_material.albedo_color
	var other_color := other_material.albedo_color
	var petal_material := Primitives.own_material(petal)
	petal_material.albedo_color = Color.MAGENTA
	_check(petal.material_override == petal_material and neighbor_material.albedo_color == neighbor_color and other_material.albedo_color == other_color and Primitives.changed_shared_looks().is_empty(),
		"Changing one blossom petal's own material leaves neighboring petals, other worlds and the shared look unchanged")
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
