extends SceneTree
## long-way-home@2 world: the lamp, gate, arch and shutter follow the native
## snapshot during real input playback; the garden grows outdoors and the
## second window sits in a wall. The @1 world is left as it was.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/long_way_home_v2_witness.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HomeWorld = preload("res://presentation/long_way_home_world.gd")
const HomeV2World = preload("res://presentation/long_way_home_v2_world.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := Catalog.definition(Witness.KEY)
	var start := _fixture("long-way-home-v2-the-path-you-leave-checkpoint")
	_check(Simulation.verify_checkpoint(level, start).valid, "The @2 stage one fixture verifies")
	for way: String in ["w1", "w2-rose", "w2-wrong"]:
		await _play(level, start, way)
	await _versions(level, start)
	print("LONG WAY HOME V2 WORLD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _play(level: Dictionary, start: Dictionary, way: String) -> void:
	var routes: Array = Witness.WAYS[way]
	var first: Dictionary = Witness.source(level, Witness.PLACE, start, Witness.A_WAYS[routes[0]], 9).export_recording()
	var record: Dictionary = Witness.receiver(level, Witness.PLACE, start, first, Witness.B_WAYS[routes[1]], 9).export_recording()
	var sim := Simulation.new()
	_check(sim.reset(level, Witness.PLACE, start, first, "b", 9), "Native turn opens before presentation: " + way)
	var world := _world(HomeV2World, level, start)
	var before := Canonical.digest(level)
	var matched := true
	for frame: Dictionary in Simulation.expand_recording_inputs(record):
		sim.step(frame)
		var state := sim.snapshot()
		world.present(state, true)
		var controls: Dictionary = state.controls
		matched = matched and world._lamps["hall-lamp"].get_meta("value") == controls["hall-lamp"] and world._arch_lantern.get_meta("value") == controls["hall-lamp"]
		matched = matched and world._lamps["walk-gate"].get_meta("value") == controls["walk-gate"] and world._shutter.get_meta("down") == (controls["porch-shutter"] == "down")
	_check(matched, "Lamp, arch lantern, gate lantern and shutter follow every frame: " + way)
	var final := sim.snapshot()
	_check(sim.complete and world._greeting_window.pane.get_meta("lit", false) and world._arrival_window.pane.get_meta("lit", false), "Both house windows are lit at the end: " + way)
	if final.controls["hall-lamp"] in ["rose", "moss"]:
		var plate: MeshInstance3D = world._journey_switches["hall-lamp"].labels[world._journey_switches["hall-lamp"].values.find(final.controls["hall-lamp"])].get_meta("backing")
		_check((plate.material_override as StandardMaterial3D).albedo_color == HomeV2World.LAMP_COLORS[final.controls["hall-lamp"]], "The lamp's chosen plate shows its colour: " + way)
	var home: Array = level.islands.filter(func(island: Dictionary) -> bool: return island.id == "home-room")[0].rect_cm
	_check(world.garden.position.z * 100.0 > float(home[3]) and world.garden_state == "completed", "The garden grows outside the house: " + way)
	_check(Canonical.digest(level) == before and Canonical.digest(world.chapter_definition) == before, "Presentation does not change the definition: " + way)
	_check_bubbles(world, way)
	world.queue_free()
	await process_frame

func _versions(level: Dictionary, start: Dictionary) -> void:
	var old := Catalog.definition("long-way-home@1")
	var old_world := _world(HomeWorld, old, _fixture("the-path-you-leave-checkpoint"))
	var new_world := _world(HomeV2World, level, start)
	var old_cradle: Node = old_world.find_child("ArrivalWindowGoal", true, false)
	var new_cradle: Node = new_world.find_child("ArrivalWindowGoal", true, false)
	_check(old_world.find_child("ArchLantern", true, false) == null and not old_world.has_method("_lamp_post"), "The @1 world has none of the @2 props")
	_check(new_cradle.get_child_count() == old_cradle.get_child_count() and old_cradle.get_child_count() > 8, "Both versions stand the second window in a wall")
	_check(old_world.garden.position.is_equal_approx(Vector3(13.65, 0, 4.00)) and old_world.garden.position == new_world.garden.position, "Both versions grow the garden outdoors in the front planter")
	old_world.queue_free()
	new_world.queue_free()
	var opening := _world(HomeV2World, level, Catalog.initial_checkpoint(level), 0)
	_check(opening.find_child("ArchLantern", true, false) == null and opening._lamps.is_empty(), "Stage one of @2 has no finale props")
	opening.queue_free()
	await process_frame

## Every name bubble's tail lands on its own lever or pad: its anchor stands
## on that control's centre, and on screen the tail's tip sits straight above
## (or on) the anchor, even while the bubble rises clear of a spirit.
func _check_bubbles(world: Node3D, way: String) -> void:
	_check(world._bubbles.size() == 5, "The house has three switch bubbles and two pad bubbles: " + way)
	var camera: Camera3D = world.camera
	for bubble: Node3D in world._bubbles:
		var name: String = bubble.labels[0].text
		var on_control := false
		for id: String in world._physical_levers:
			if bubble.anchor.distance_to(world._knob_top(id)) < 0.001: on_control = true
		for node: Node3D in world._physical_pads.values():
			var at: Vector3 = world.terrain.to_local(node.global_position)
			if Vector2(at.x - bubble.anchor.x, at.z - bubble.anchor.z).length() < 0.01: on_control = true
		_check(on_control, "A bubble's tail is anchored on its own lever's knob top or pad's centre: %s %s" % [name, way])
		var tip: Vector2 = bubble.tail_tip(camera)
		var target := camera.unproject_position(world.terrain.to_global(bubble.anchor))
		_check(absf(tip.x - target.x) < 3.0 and tip.y < target.y + 3.0 and (bubble.lift > 0.0 or absf(tip.y - target.y) < 3.0), "On screen the tail points straight down at its control: %s %s tip %s target %s" % [name, way, tip, target])
func _world(script: Script, level: Dictionary, previous: Dictionary, index: int = 1) -> Node3D:
	var world: Node3D = script.new()
	root.add_child(world)
	world.reduced_motion = true
	world.load_level(level)
	world.show_stage(level.stages[index])
	world.present_history(previous)
	world.set_process(false)
	return world

func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/" + name + ".json"))
	return parsed if parsed is Dictionary else {}

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
