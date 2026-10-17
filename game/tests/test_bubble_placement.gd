extends SceneTree
## Journey speech bubbles are placed only after something placement reads has
## changed (a snapshot, a stage, a history), never again on idle frames, and
## land exactly where placing them on every frame puts them. For every journey
## chapter with bubbles and each of its stages, from the chapter's own fixture
## recordings: one world places as shipped, a twin is made to place on every
## frame, and both are shown the same snapshots of the second turn with a few
## real frames after each.
const Registry = preload("res://services/chapter_registry.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Golden = preload("res://tests/golden_support.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
## Ticks of the second turn between snapshots shown.
const STRIDE := 30
const IDLE_FRAMES := 30
var checks := 0
var failures := 0
var _always: Array[Node3D] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _chain(key: String) -> Array:
	for name: String in ReplayGolden.CHAINS.get(key, {}):
		var spec: Dictionary = ReplayGolden.CHAINS[key][name]
		if spec.has("stages"): return spec.stages
	return []

func _world(key: String) -> Node3D:
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
	world.configure_camera_exploration(func() -> bool: return false, func(_point: Vector2) -> bool: return false)
	world.load_level(Registry.definition(key))
	return world

## Where every bubble stands: its lift and lean, and a world's own scenery climb.
func _placed(world: Node3D) -> Array:
	var rows: Array = []
	for bubble: Node in world._bubbles:
		if is_instance_valid(bubble): rows.append([snappedf(bubble.lift, 0.0001), snappedf(bubble.lean, 0.0001)])
	if "scenery_backstop" in world: rows.append(snappedf(world.scenery_backstop, 0.0001))
	return rows

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _run() -> void:
	# The twin places on every frame, before any node processes.
	process_frame.connect(func() -> void:
		for world: Node3D in _always:
			if is_instance_valid(world): world._placement_due = true)
	var tested := 0
	for key: String in Registry.offered_keys():
		if not Registry.is_journey(key): continue
		var stages := _chain(key)
		if stages.is_empty(): continue
		var level := Registry.definition(key)
		var engine: Script = Registry.simulation_script(key)
		var checkpoint := Registry.initial_checkpoint(key)
		var shipped := _world(key)
		var always := _world(key)
		_always = [always]
		for index in range(stages.size()):
			var files: Array = stages[index]
			var a: Dictionary = files[0] if files[0] is Dictionary else Golden.fixture(files[0])
			var b: Dictionary = files[1] if files[1] is Dictionary else Golden.fixture(files[1])
			var sim: RefCounted = engine.new()
			sim.catch_assistance = bool(b.get("catch_assistance", true))
			if not Registry.reset_simulation(sim, key, level, str(b.stage_id), checkpoint, a, str(b.role), b):
				_check(false, "%s stage %d: the fixture resets" % [key, index + 1])
				break
			var name := "%s stage %d" % [key, index + 1]
			for world: Node3D in [shipped, always]:
				world.show_stage(engine.stage_by_id(level, str(b.stage_id)))
				world.present_history(checkpoint)
				world.present(sim.snapshot(), true)
			if shipped._bubbles.is_empty():
				# A journey without selectors (the Conservatory) places nothing.
				checkpoint = files[2] if files[2] is Dictionary else Golden.fixture(files[2])
				continue
			await _frames(3)
			var inputs: Array = engine.expand_recording_inputs(b)
			var tick := 0
			var same := true
			var idle_free := true
			var once := true
			while true:
				# Standing still: no placement work at all.
				var before: int = shipped.placement_passes
				await _frames(IDLE_FRAMES)
				idle_free = idle_free and shipped.placement_passes == before
				same = same and _placed(shipped) == _placed(always)
				if tick >= inputs.size(): break
				var target := mini(tick + STRIDE, inputs.size())
				while tick < target:
					sim.step(inputs[tick])
					tick += 1
				var state: Dictionary = sim.snapshot()
				for world: Node3D in [shipped, always]: world.present(state.duplicate(true))
				before = shipped.placement_passes
				await _frames(2)
				# A new snapshot is placed once, on the next frame.
				once = once and shipped.placement_passes == before + 1
				same = same and _placed(shipped) == _placed(always)
			_check(idle_free, "%s: idle frames run no placement pass" % name)
			_check(once, "%s: each new snapshot is placed exactly once" % name)
			_check(same, "%s: bubbles stand where placing on every frame puts them, across %d ticks" % [name, tick])
			tested += 1
			checkpoint = files[2] if files[2] is Dictionary else Golden.fixture(files[2])
		_always = []
		shipped.queue_free()
		always.queue_free()
		await _frames(2)
	_check(tested >= 4, "Every journey chapter's stages were placed (%d stages)" % tested)
	print("BUBBLE PLACEMENT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
