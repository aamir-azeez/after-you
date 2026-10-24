extends "res://tests/test_world_fingerprint.gd"
## services/world_prewarm.gd builds a heavy chapter's world unseen while Home
## is idle, so the chapter's first open finds its geometry and batches made.
## - A chapter built after a warm-up is the same, node for node, as one built
##   cold (the world fingerprint of its first view), and makes no batch or
##   definition geometry again: every one is the warm-up's.
## - The warm-up's world stands in a view of its own that never draws: the
##   screen's camera is unchanged, and once done nothing of it is left.
## - Only while idle: a paused warm-up builds nothing more, and a warm-up
##   freed mid-build (Home leaving) never builds on and leaves nothing. Away
##   (a room open under Home) it lets an unfinished world go and starts it
##   again later. A stage a chapter screen built counts as warm.
## - Its batches leave room in the kept batches for Home's island, for every
##   chapter whose descriptor asks for the warm-up.
## - At most one chapter a visit: the first of chapters() not warm yet. A
##   stage warm already does not use up the visit; the next visit warms the
##   next chapter.
## - The stage is the one the solo save opens on.
const WorldPrewarm = preload("res://services/world_prewarm.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const DefinitionGeometry = preload("res://presentation/kit/definition_geometry.gd")
const ScreenSwitch = preload("res://services/screen_switch.gd")
const KEY := "turn-of-the-tide@2"

func _suite() -> String:
	return "world_prewarm"

func _run() -> void:
	await process_frame
	var stages := _snapshots(KEY)
	if not _check(stages.size() == 2, "Turn of the Tide has its two fixture stages"):
		quit(1)
		return
	_saved_stage()
	# Cold: nothing kept.
	_forget_caches()
	var cold := _first_view(stages[0])
	_check(cold.batches > 0 and cold.geometry > 0, "A cold build makes its batches and geometry (%d, %d)" % [cold.batches, cold.geometry])
	_forget_caches()
	# The warm-up, idle at once, under a node that stands for Home.
	var home := Node.new()
	root.add_child(home)
	var camera := Camera3D.new()
	var stage3d := Node3D.new()
	root.add_child(stage3d)
	stage3d.add_child(camera)
	camera.current = true
	var prewarm := _prewarm(func() -> bool: return true)
	home.add_child(prewarm)
	var frames := 0
	var seen_world := false
	var camera_kept := true
	while frames < 5000 and not WorldPrewarm.warmed().has(KEY + "|set-the-tide"):
		await process_frame
		frames += 1
		seen_world = seen_world or prewarm.running()
		camera_kept = camera_kept and root.get_camera_3d() == camera
	_check(WorldPrewarm.warmed().has(KEY + "|set-the-tide"), "The warm-up builds and folds the first stage while idle (%d frames)" % frames)
	_check(seen_world and camera_kept, "Its world never takes the screen's camera")
	var guard := 0
	while guard < 600 and ScreenSwitch.pending_count() > 0:
		await process_frame
		guard += 1
	_check(not prewarm.running() and prewarm.get_child_count() == 0 and ScreenSwitch.pending_count() == 0, "Once done, nothing of its world is left (%d frames)" % guard)
	var kept_batches := StaticBatch._kept_batches.size()
	var kept_geometry := DefinitionGeometry._kept.size()
	_check(kept_batches > 0 and kept_geometry > 0, "It leaves batches and geometry kept (%d, %d)" % [kept_batches, kept_geometry])
	_check(StaticBatch._kept_vertices * 2 < StaticBatch.KEPT_VERTICES, "Its batches take under half of the kept vertices, leaving Home's island kept (%d of %d)" % [StaticBatch._kept_vertices, StaticBatch.KEPT_VERTICES])
	# The chapter's first view after the warm-up.
	var warm := _first_view(stages[0])
	_check(warm.print.hash == cold.print.hash and warm.print.nodes == cold.print.nodes, "A world built after the warm-up is the same as one built cold (%s, %s)" % [str(warm.print.hash).substr(0, 12), str(cold.print.hash).substr(0, 12)])
	_check(StaticBatch._kept_batches.size() == kept_batches and DefinitionGeometry._kept.size() == kept_geometry, "...and makes no batch or geometry again (%d -> %d, %d -> %d)" % [kept_batches, StaticBatch._kept_batches.size(), kept_geometry, DefinitionGeometry._kept.size()])
	_check(Primitives.changed_shared_looks().is_empty(), "The warm-up changes no shared look: %s" % [Primitives.changed_shared_looks()])
	# A second visit finds the stage warm and builds nothing.
	prewarm.queue_free()
	var again := _prewarm(func() -> bool: return true)
	home.add_child(again)
	for i in range(30):
		await process_frame
		_check(not again.running(), "A stage warmed this run is not built again")
	again.queue_free()
	WorldPrewarm.forget()
	WorldPrewarm.note_built(KEY, "set-the-tide")
	var built := _prewarm(func() -> bool: return true)
	home.add_child(built)
	for i in range(30):
		await process_frame
		_check(not built.running(), "A stage a chapter screen built is not warmed again")
	built.queue_free()
	await _paused_and_left()
	await _away()
	await _one_a_visit()
	await _flagged_budgets()
	stage3d.queue_free()
	home.queue_free()
	await process_frame
	print("%s: %d checks, %d failures" % [_suite().to_upper().replace("_", " "), checks, failures])
	quit(1 if failures else 0)

## Paused, a warm-up builds nothing more; freed mid-build with its screen
## (Home's nodes handed to the screen switch), it never builds on.
func _paused_and_left() -> void:
	WorldPrewarm.forget()
	_forget_caches()
	var idle := [true]
	var home := Node.new()
	root.add_child(home)
	var prewarm := _prewarm(func() -> bool: return idle[0])
	home.add_child(prewarm)
	var guard := 0
	while guard < 2000 and not (prewarm.building() and _world_nodes(prewarm) > 200):
		await process_frame
		guard += 1
	_check(prewarm.building(), "A warm-up is caught mid-build (%d nodes)" % _world_nodes(prewarm))
	idle[0] = false
	var held := _world_nodes(prewarm)
	for i in range(20): await process_frame
	_check(prewarm.building() and _world_nodes(prewarm) == held, "Paused, it builds nothing more (%d, %d)" % [held, _world_nodes(prewarm)])
	idle[0] = true
	for i in range(5): await process_frame
	_check(_world_nodes(prewarm) > held, "Idle again, it goes on where it stopped")
	var world: Node3D = prewarm._world
	var built := _world_nodes(prewarm)
	# Home leaves: its nodes go to the screen switch, freed over frames.
	root.remove_child(home)
	var bin := Node.new()
	bin.add_child(home)
	ScreenSwitch.release(bin)
	bin.free()
	_check(is_instance_valid(world) and _count(world) >= built, "Leaving, the world is not built on in that frame")
	guard = 0
	while guard < 600 and (is_instance_valid(world) or is_instance_valid(prewarm)):
		await process_frame
		guard += 1
	_check(not is_instance_valid(world) and not is_instance_valid(prewarm), "...and is freed with Home over the next frames (%d)" % guard)
	_check(not WorldPrewarm.warmed().has(KEY + "|set-the-tide"), "A warm-up that never finished warms nothing")

## Away (a room opened under Home), an unfinished world is let go at once and
## nothing counts as warm; back at Home the warm-up starts it again.
func _away() -> void:
	WorldPrewarm.forget()
	_forget_caches()
	var away := [false]
	var home := Node.new()
	root.add_child(home)
	var prewarm := _prewarm(func() -> bool: return not away[0])
	prewarm.away = func() -> bool: return away[0]
	home.add_child(prewarm)
	var guard := 0
	while guard < 2000 and not (prewarm.building() and _world_nodes(prewarm) > 200):
		await process_frame
		guard += 1
	var world: Node3D = prewarm._world
	away[0] = true
	await process_frame
	_check(not prewarm.running() and not prewarm.building(), "Away, the unfinished world is let go")
	guard = 0
	while guard < 600 and is_instance_valid(world):
		await process_frame
		guard += 1
	_check(not is_instance_valid(world) and prewarm.get_child_count() == 0 and not WorldPrewarm.warmed().has(KEY + "|set-the-tide"), "...freed over the next frames, warming nothing (%d)" % guard)
	away[0] = false
	guard = 0
	while guard < 2000 and not WorldPrewarm.warmed().has(KEY + "|set-the-tide"):
		await process_frame
		guard += 1
	_check(WorldPrewarm.warmed().has(KEY + "|set-the-tide"), "Back at Home it builds that stage again and finishes (%d frames)" % guard)
	home.queue_free()
	for i in range(3): await process_frame

## Two chapters to warm, the first most likely next: one idle visit warms
## the first only and starts nothing more; the next visit warms the second. A
## stage a chapter screen built already does not use up a visit.
func _one_a_visit() -> void:
	var first := "first-steps@1"
	var first_warm := first + "|" + str(Registry.definition(first).stages[0].id)
	var tide_warm := KEY + "|set-the-tide"
	var both: Array[String] = [first, KEY]
	WorldPrewarm.forget()
	_forget_caches()
	var home := Node.new()
	root.add_child(home)
	var visit := _prewarm(func() -> bool: return true, both)
	home.add_child(visit)
	await _until_warm(first_warm)
	var started := false
	for i in range(300):
		await process_frame
		started = started or visit.running()
	_check(WorldPrewarm.warmed() == [first_warm] and not started, "One idle visit warms the most likely chapter only, and starts no other (%s)" % [WorldPrewarm.warmed()])
	visit.queue_free()
	var next := _prewarm(func() -> bool: return true, both)
	home.add_child(next)
	await _until_warm(tide_warm)
	_check(WorldPrewarm.warmed().has(tide_warm), "The next visit warms the next chapter")
	next.queue_free()
	WorldPrewarm.forget()
	_forget_caches()
	WorldPrewarm.note_built(first, first_warm.get_slice("|", 1))
	var built := _prewarm(func() -> bool: return true, both)
	home.add_child(built)
	await _until_warm(tide_warm)
	_check(WorldPrewarm.warmed().has(tide_warm), "A chapter warm already does not use up the visit: the next one warms")
	home.queue_free()
	for i in range(3): await process_frame

## Every offered chapter whose descriptor asks for the warm-up (Turn of the
## Tide, checked above, aside): warmed alone, its batches take under half of
## the kept vertices, leaving Home's island kept.
func _flagged_budgets() -> void:
	_check(WorldPrewarm.flagged(KEY), "Turn of the Tide asks for the warm-up")
	for key: String in Registry.offered_keys():
		if key == KEY or not WorldPrewarm.flagged(key): continue
		WorldPrewarm.forget()
		_forget_caches()
		var home := Node.new()
		root.add_child(home)
		var only: Array[String] = [key]
		home.add_child(_prewarm(func() -> bool: return true, only))
		var warm := key + "|" + str(Registry.definition(key).stages[0].id)
		await _until_warm(warm)
		_check(WorldPrewarm.warmed().has(warm), "%s warms" % key)
		_check(StaticBatch._kept_vertices * 2 < StaticBatch.KEPT_VERTICES, "%s's batches take under half of the kept vertices (%d of %d)" % [key, StaticBatch._kept_vertices, StaticBatch.KEPT_VERTICES])
		home.queue_free()
		for i in range(3): await process_frame

func _until_warm(pair: String) -> void:
	var guard := 0
	while guard < 5000 and not WorldPrewarm.warmed().has(pair):
		await process_frame
		guard += 1

## The stage the solo save opens on: one played pair per finished stage.
func _saved_stage() -> void:
	var path := "user://world-prewarm-test.json"
	_check(WorldPrewarm._saved_pairs(path) == 0, "No save warms the first stage")
	for pairs: int in [1, 2]:
		var relay := {"pairs": []}
		for i in range(pairs): relay.pairs.append({"a": {}, "b": {}})
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"relay": relay}))
		file.close()
		_check(WorldPrewarm._saved_pairs(path) == pairs, "A save with %d finished stages reads %d" % [pairs, pairs])
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{")
	broken.close()
	_check(WorldPrewarm._saved_pairs(path) == 0, "An unreadable save warms the first stage")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _prewarm(idle: Callable, keys: Array[String] = [KEY]) -> Node:
	var prewarm: Node = WorldPrewarm.new()
	prewarm.enabled = true
	prewarm.idle_seconds = 0.0
	prewarm.idle = idle
	prewarm.chapters = func() -> Array[String]: return keys
	prewarm.wants = func(key: String) -> bool: return key in keys
	prewarm.settings = func() -> Dictionary: return {"graphics_quality": "balanced"}
	return prewarm

func _world_nodes(prewarm: Node) -> int:
	var world: Variant = prewarm.get("_world")
	return _count(world) if is_instance_valid(world) else -1

func _count(node: Node) -> int:
	return node.find_children("*", "", true, false).size()

func _forget_caches() -> void:
	DefinitionGeometry.release()
	StaticBatch.release_kept()

## The chapter's first view as a chapter screen shows it (history, the first
## turn's start, its frames, which fold the scenery), fingerprinted, with how
## many batches and geometry values are kept after it.
func _first_view(entry: Dictionary) -> Dictionary:
	var viewport := _viewport()
	var world: Node3D = Registry.world_script(KEY).new()
	_mount(viewport, world, false)
	world.load_level(Registry.definition(KEY))
	_history(world, entry.stage, entry.checkpoint)
	world.present(entry.a_start.duplicate(true), true)
	_frames(world, 30)
	var result := {"print": _fingerprint(world, KEY, false, "prewarm"), "batches": StaticBatch._kept_batches.size(), "geometry": DefinitionGeometry._kept.size()}
	viewport.free()
	return result
