extends SceneTree
## The close follow camera a level asks for in its dressing
## ("camera": {"follow": {...}}, island_world._follow_data). For every chapter
## with it, a later turn is replayed through the engine over its memory, with
## the live pip waiting (show_memory_wait) so the camera follows the memory's
## pip: on the stage where that pip climbs highest, the view keeps the level's
## angle (camera_from) every frame, rises with the pip as the data's "lift"
## says, follows it across and in depth, and settles on it. A scrolling chapter
## without the field keeps the game's own angle and sizes.
const Registry = preload("res://services/chapter_registry.gd")
const ChapterWitness = preload("res://tests/chapter_witness.gd")
const ViewFit = preload("res://presentation/kit/view_fit.gd")
const DressingCatalog = preload("res://content/dressing/catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var followed := 0
	var plain := 0
	for key: String in Registry.keys():
		var probe: Node3D = Registry.world_script(key).new()
		var scrolls: bool = probe._uses_scrolling_camera()
		probe.free()
		if not scrolls: continue
		var data: Dictionary = _follow_data(key)
		if data.is_empty():
			if plain == 0: await _plain(key)
			plain += 1
			continue
		followed += 1
		await _replay(key, data)
	_check(followed > 0 and plain > 0, "There are chapters with and without follow data to check (%d, %d)" % [followed, plain])
	print("FOLLOW CAMERA: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _follow_data(key: String) -> Dictionary:
	var camera: Variant = DressingCatalog.for_key(key).get("camera", {})
	return camera.get("follow", {}) if camera is Dictionary else {}

func _world(key: String) -> Node3D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2400, 1080)
	root.add_child(viewport)
	var world: Node3D = Registry.world_script(key).new()
	viewport.add_child(world)
	world.set_process(false)
	world.camera_exploration.set_process(false)
	world.configure_camera_exploration(func(): return true, func(_point): return true)
	world.load_level(Registry.definition(key))
	return world

## A chapter without the field: the game's own angle and sizes.
func _plain(key: String) -> void:
	var world := _world(key)
	var level := Registry.definition(key)
	var sim: RefCounted = Registry.simulation_script(key).new()
	Registry.reset_simulation(sim, key, level, str(level.stages[0].id), Registry.initial_checkpoint(key), {}, "a")
	world.present(sim.snapshot(), true)
	_check(world.camera_from() == ViewFit.CAMERA_FROM and world._scroll_size() == world.SCROLL_SIZE and world._scroll_done_size() == world.SCROLL_DONE_SIZE, "%s keeps the game's own angle and sizes" % key)
	_check((world.camera.position - world._follow_center).is_equal_approx(ViewFit.CAMERA_FROM), "%s looks from the game's own angle" % key)
	world.get_parent().free()
	await process_frame

func _replay(key: String, data: Dictionary) -> void:
	var evidence := ChapterWitness.play(key, ChapterWitness.routes(key))
	_check(evidence.error.is_empty(), "%s: its witness plays: %s" % [key, evidence.error])
	if not evidence.error.is_empty(): return
	var level: Dictionary = evidence.definition
	# The stage whose second turn's memory climbs most (the engine alone).
	var best := -1
	var best_rise := 0
	for index in range(level.stages.size()):
		var rise := _memory_rise(key, level, index, evidence, Callable())
		if rise > best_rise:
			best_rise = rise
			best = index
	_check(best >= 0 and best_rise >= 100, "%s: some stage's memory climbs a tier (%d cm)" % [key, best_rise])
	if best < 0: return
	var world := _world(key)
	var lift := clampf(float(data.get("lift", 0.0)), 0.0, 1.0)
	var from: Vector3 = world.camera_from()
	_check(from == ViewFit.camera_from(world.dressing) and from != ViewFit.CAMERA_FROM, "%s: the level's own angle" % key)
	var seen := {"angle": true, "low": INF, "high": -INF, "left": INF, "right": -INF, "lag": 0.0}
	var memory := str(level.stages[best].first_player_slot)
	_memory_rise(key, level, best, evidence, func(state: Dictionary, live: String) -> void:
		world.present(state)
		world.show_memory_wait(live, memory)
		for _frame in range(2):
			world._process(1.0 / 60.0)
			world.camera_exploration._process(1.0 / 60.0)
			seen.angle = seen.angle and (world.camera.position - world._follow_center).is_equal_approx(from)
			var center: Vector3 = world._follow_center
			seen.low = minf(seen.low, center.y)
			seen.high = maxf(seen.high, center.y)
			seen.left = minf(seen.left, center.x)
			seen.right = maxf(seen.right, center.x))
	for _frame in range(120):
		world._process(1.0 / 60.0)
		world.camera_exploration._process(1.0 / 60.0)
	var stage_id := str(level.stages[best].id)
	var pip: Vector3 = world.actors[memory].position
	var limits: Array = world._follow_limits()
	var expected := Vector3(clampf(pip.x, limits[0].x, limits[1].x), pip.y * lift, clampf(pip.z, limits[0].y, limits[1].y))
	_check(seen.angle, "%s/%s: every frame looks from the level's angle" % [key, stage_id])
	_check(world.camera_focus == memory, "%s/%s: the camera follows the memory's pip while the live pip waits" % [key, stage_id])
	_check(world._follow_center.distance_to(expected) < 0.02, "%s/%s: the view settles on the memory's pip (%s, wants %s)" % [key, stage_id, world._follow_center, expected])
	_check(seen.high - seen.low >= 0.8 * lift * float(best_rise) / 100.0, "%s/%s: the view climbs with the pip (%.2f m for a %d cm climb)" % [key, stage_id, seen.high - seen.low, best_rise])
	_check(seen.right - seen.left >= 2.0, "%s/%s: the view follows the pip across (%.2f m)" % [key, stage_id, seen.right - seen.left])
	world.get_parent().free()
	await process_frame

## Replays stage `index`'s second turn over its first as the memory, calling
## `each` (snapshot, live slot) every tick; returns how far (cm) the memory's
## pip climbs above where it starts.
func _memory_rise(key: String, level: Dictionary, index: int, evidence: Dictionary, each: Callable) -> int:
	var turns: Array = evidence.pairs[index].turns
	if turns.size() < 2: return 0
	var stage: Dictionary = level.stages[index]
	var memory := str(stage.first_player_slot)
	var live := "p1" if memory == "p0" else "p0"
	var sim: RefCounted = Registry.simulation_script(key).new()
	if not Registry.reset_simulation(sim, key, level, str(stage.id), evidence.checkpoints[index], turns[0], "b", turns[1]): return 0
	var start := int(sim.snapshot().players[memory].height)
	var top := start
	for input: Dictionary in sim.expand_recording_inputs(turns[1]):
		var state: Dictionary = sim.step(input)
		top = maxi(top, int(state.players[memory].height))
		if each.is_valid(): each.call(state, live)
	return top - start

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
