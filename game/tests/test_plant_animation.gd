extends SceneTree
## The planting beat (presentation/plant_animation.gd) in every world that
## plants a seed: First Steps, Relay and the Earlier Islands. Each world is
## driven by its published fixture recordings up to the real planting tick.
const Registry = preload("res://services/chapter_registry.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const PlantAnimation = preload("res://presentation/plant_animation.gd")
const DELTA := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _fixture(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + path + ".json"))

func _run() -> void:
	await _world_case("First Steps", func() -> Array: return _chapter(Registry.FIRST_STEPS, "first_steps/lift-checkpoint", "first_steps/a-place-to-grow-a", "first_steps/a-place-to-grow-b"))
	await _world_case("Relay", func() -> Array: return _chapter(Registry.RELAY, "v2/relay-checkpoint", "v2/garden-a", "v2/garden-b"))
	await _world_case("Earlier Islands", _islands)
	_check(preload("res://presentation/kit/primitives.gd").changed_shared_materials().is_empty(), "Every kit look shared between meshes is as it was made; code that changes a mesh's material takes its own copy (Primitives.own_material): %s" % [preload("res://presentation/kit/primitives.gd").changed_shared_materials()])
	print("AFTER YOU PLANT ANIMATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## [world, b_start, held_before_planting, planted] from a real recording.
func _chapter(key: String, checkpoint_path: String, a_path: String, b_path: String) -> Array:
	var level := Registry.definition(key)
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	world.set_process(false)
	world.load_level(level)
	var a := _fixture(a_path)
	var b := _fixture(b_path)
	var engine: Script = Registry.simulation_script(key)
	var sim: RefCounted = engine.new()
	sim.catch_assistance = bool(b.get("catch_assistance", true))
	Registry.reset_simulation(sim, key, level, str(b.stage_id), _fixture(checkpoint_path), a, str(b.role), b)
	world.show_stage(engine.stage_by_id(level, str(b.stage_id)))
	return _until_planted(world, sim, engine.expand_recording_inputs(b))

func _islands() -> Array:
	var world := IslandWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.home_view = false
	var level := Levels.get_level(0)
	world.load_level(level)
	var a := _fixture("first-light-a")
	var b := _fixture("first-light-b")
	var sim := LegacySimulation.new()
	sim.reset(level, a, "b", int(b.simulation_version))
	return _until_planted(world, sim, LegacySimulation.expand_recording_inputs(b))

func _until_planted(world: Node3D, sim: RefCounted, inputs: Array) -> Array:
	var start: Dictionary = sim.snapshot().duplicate(true)
	world.present(start, true)
	var before: Dictionary = start
	for input: Dictionary in inputs:
		var state: Dictionary = sim.step(input).duplicate(true)
		if str(state.seed.status) == "planted":
			return [world, start, before, state]
		world.present(state)
		before = state
	return [world, start, before, {}]

func _host(world: Node3D) -> Node3D:
	return world.get("terrain")

func _count(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		if not child.is_queued_for_deletion(): total += _count(child)
	return total

func _seed_pose(world: Node3D) -> String:
	var seed: MeshInstance3D = world.seed
	var mat := seed.material_override as StandardMaterial3D
	return "%s|%s|%s|%s" % [seed.visible, seed.global_transform, mat.albedo_color, mat.emission]

func _world_case(label: String, build: Callable) -> void:
	var made: Array = build.call()
	var world: Node3D = made[0]
	var start: Dictionary = made[1]
	var held: Dictionary = made[2]
	var planted: Dictionary = made[3]
	_check(not planted.is_empty() and str(held.seed.status) != "planted", label + ": the recording reaches a real planting tick")
	if planted.is_empty():
		world.free()
		return
	var host := _host(world)
	# A chapter world folds its static scenery on its first frame; count after.
	world._fold_static_scenery()
	var baseline := _count(host)
	var enabled := PlantAnimation.ENABLED
	var camera: Camera3D = world.camera
	_check(camera.current, label + ": the world's camera is on screen before planting")
	var camera_pose := "%s|%s|%s|%s" % [camera.global_transform, camera.size, camera.h_offset, camera.v_offset]
	# 1. A real held -> planted transition starts exactly one beat.
	world.present(planted.duplicate(true))
	var running := PlantAnimation.running(host)
	if enabled:
		_check(running.size() == 1, label + ": the planting transition starts one beat")
	else:
		_check(running.is_empty(), label + ": a switched-off beat never starts")
	_check(not world.seed.visible, label + ": the real seed is hidden at planted, as before")
	if running.size() == 1:
		var anim: PlantAnimation = running[0]
		_check(anim.process_priority > 100, label + ": the beat composes after the world and its camera exploration")
		var view := anim.view_camera()
		_check(view != null and view.current and not camera.current, label + ": the beat looks through its own camera")
		var fruit := anim.get_node_or_null("PlantFruit") as Node3D
		var ground := PlantAnimation.soil(world, host, planted.seed, world.seed.global_position)
		var soil_y: float = ground.center.y
		_check(fruit != null and fruit.get_node("PlantFruitBody").visible and not fruit.get_node("PlantFruitBody").has_meta("seed_visual"), label + ": the fruit copy shows before the split and is not a second seed")
		_check(fruit.global_position.y > soil_y + 0.8, label + ": the fruit opens above the spirit's head, where it was carried")
		_check(world.bloomed and is_equal_approx(world.garden_bloom_age, -PlantAnimation.BLOOM_START), label + ": the bloom is held from the planting present itself")
		var paused_age: float = world.garden_bloom_age
		anim._process(0.5)
		_check(is_equal_approx(anim.elapsed(), 0.0) and world.garden_bloom_age == paused_age, label + ": a world that is not processing (backgrounded) holds the beat and its bloom")
		anim.advance(0.2)
		_check(world.bloomed and is_equal_approx(world.garden_bloom_age, 0.2 - PlantAnimation.BLOOM_START), label + ": the bloom waits for the seed")
		# Re-presenting the same planted state (replay ticks) never restarts it.
		world.present(planted.duplicate(true))
		_check(PlantAnimation.running(host).size() == 1 and PlantAnimation.running(host)[0] == anim and is_equal_approx(anim.elapsed(), 0.2), label + ": later planted ticks keep the same beat running")
		anim.advance(PlantAnimation.ZOOM_IN + 0.01 - anim.elapsed())
		_check(view.size < camera.size * 0.6, label + ": the view has eased in on the planter")
		anim.advance(PlantAnimation.SPLIT + 0.08 - anim.elapsed())
		var small := anim.get_node_or_null("PlantSeed") as Node3D
		_check(small != null and small.visible and not fruit.get_node("PlantFruitBody").visible, label + ": after the split the small seed is out of the fruit")
		_check(small.global_position.y > soil_y + 0.8, label + ": the small seed pops out above the head")
		anim.advance(PlantAnimation.LAND + 0.02 - anim.elapsed())
		var offset := Vector2(small.global_position.x - ground.center.x, small.global_position.z - ground.center.z).length()
		_check(absf(small.global_position.y - soil_y) < 0.08 and offset <= float(ground.radius) and (anim.get_node("PlantPuff0") as Node3D).visible, label + ": the seed lands in the planter soil with a puff")
		var planted_y := float(planted.seed.get("height", 0)) / 100.0
		_check(soil_y > planted_y - 0.4 and soil_y < planted_y + 0.2 and float(ground.radius) > 0.25, label + ": the soil is the planted socket's, not the ground")
		_check(world.garden_bloom_age <= 0.0, label + ": the bloom is still closed when the seed lands")
		anim.advance(PlantAnimation.BLOOM_START + 0.05 - anim.elapsed())
		_check(PlantAnimation.BLOOM_START - PlantAnimation.LAND <= 0.3, label + ": the bloom follows the landing after only a short beat")
		_check(is_equal_approx(world.garden_bloom_age, 0.05), label + ": the bloom starts on the beat's clock, even if the world was not processing")
		world._advance_garden_bloom(0.3)
		anim.advance(0.0)
		_check(world.garden_bloom_age > 0.3, label + ": after the landing the bloom grows")
		anim.advance(PlantAnimation.DURATION)
		_check(anim.is_queued_for_deletion() and PlantAnimation.running(host).is_empty(), label + ": the beat ends after its duration")
		_check(camera.current and not view.current, label + ": the world's camera is back on screen after the beat")
		_check(_count(host) == baseline, label + ": no temporary node outlives the beat")
		await process_frame
		_check(not is_instance_valid(anim), label + ": the finished beat is freed")
	_check("%s|%s|%s|%s" % [camera.global_transform, camera.size, camera.h_offset, camera.v_offset] == camera_pose, label + ": the world's camera is never moved")
	# The real seed ends exactly as an immediate present leaves it.
	var animated_pose := _seed_pose(world)
	world.present(held.duplicate(true), true)
	world.present(planted.duplicate(true), true)
	_check(_seed_pose(world) == animated_pose, label + ": the real seed is untouched by the beat")
	# 2. An immediate present (load, scrub, resume) shows the end state directly.
	_check(PlantAnimation.running(host).is_empty() and _count(host) == baseline, label + ": immediate=true never plays the beat")
	# A jump to planted while the carrier is nowhere near the planter (a seek
	# from someone else's carry) shows the end state.
	world.present(held.duplicate(true), true)
	var slot := str(world._seed_holder)
	_check(not slot.is_empty(), label + ": the tick before planting has a carrier")
	var far := planted.duplicate(true)
	far.players[slot].x = int(far.players[slot].x) + (900 if int(far.players[slot].x) < 0 else -900)
	world.present(far)
	_check(PlantAnimation.running(host).is_empty(), label + ": a jump to planted with the carrier far from the planter does not play the beat")
	# 3. Reduced motion skips it.
	world.present(held.duplicate(true), true)
	world.reduced_motion = true
	world.present(planted.duplicate(true))
	_check(PlantAnimation.running(host).is_empty(), label + ": reduced motion skips the beat")
	world.reduced_motion = false
	# Reduced motion switched on mid-beat ends it on the next frame.
	world.present(held.duplicate(true), true)
	world.present(planted.duplicate(true))
	if enabled:
		var anim: PlantAnimation = PlantAnimation.running(host)[0]
		world.reduced_motion = true
		anim.advance(DELTA)
		_check(PlantAnimation.running(host).is_empty() and camera.current, label + ": reduced motion mid-beat ends it and restores the view")
		world.reduced_motion = false
	# 4. A reset or retry mid-beat clears it at once.
	world.present(held.duplicate(true), true)
	world.present(planted.duplicate(true))
	world.present(start.duplicate(true), true)
	_check(PlantAnimation.running(host).is_empty() and _count(host) == baseline, label + ": a reset mid-beat clears every temporary node")
	_check(camera.current, label + ": a reset mid-beat gives the screen back to the world's camera")
	world.present(held.duplicate(true), true)
	world.present(planted.duplicate(true))
	world.present(held.duplicate(true))
	_check(PlantAnimation.running(host).is_empty(), label + ": a non-planted state mid-beat clears it")
	# 5. A scene change (load_level) mid-beat takes it with the old terrain.
	world.present(held.duplicate(true), true)
	world.present(planted.duplicate(true))
	var leftover: Array = PlantAnimation.running(host)
	_check(leftover.size() == (1 if enabled else 0), label + ": a beat is running before the scene change")
	world.load_level(world.current_level)
	await process_frame
	for index in range(leftover.size()): _check(not is_instance_valid(leftover[index]), label + ": load_level frees a running beat")
	_check(PlantAnimation.running(_host(world)).is_empty(), label + ": the new scene starts with no beat")
	_check(camera.current, label + ": a scene change mid-beat gives the screen back to the world's camera")
	world.free()
	await process_frame
