extends SceneTree
## Water lock bakes (presentation/kit/water_locks.gd): every stage of every
## chapter whose world places water locks has a committed bake in
## content/water_locks/, made from that stage's plan by the same find_runs(),
## and a world opening the stage the way the game does uses it rather than
## working placement out. A stale or missing bake, or a drift in the bake's
## name or the plan between baking and opening, fails here.
## To rewrite the bakes after an intended change, set AFTER_YOU_WRITE_BAKE to
## the absolute path of game/content/water_locks (or to 1 for res://) and run
## this suite; a write run compares nothing and prints each file it wrote.
const WaterLocks = preload("res://presentation/kit/water_locks.gd")
const Registry = preload("res://services/chapter_registry.gd")
const WRITE_ENV := "AFTER_YOU_WRITE_BAKE"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _run() -> void:
	var target := OS.get_environment(WRITE_ENV)
	var baked := 0
	for key: String in Registry.keys():
		var level := Registry.definition(key)
		var world: Node3D = Registry.world_script(key).new()
		if not world.has_method("_water_plan"):
			world.free()
			continue
		root.add_child(world)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		# Nothing cached: each stage opens as on a fresh launch.
		WaterLocks._found.clear()
		WaterLocks._unbaked.clear()
		world.load_level(level)
		for stage: Dictionary in level.stages:
			await world.show_stage(stage)
			var fell_back: bool = not WaterLocks._unbaked.is_empty()
			var built: Array = world._locks.runs if is_instance_valid(world._locks) else []
			var plan: Dictionary = world._water_plan()
			var path := WaterLocks.bake_path(key, str(stage.id))
			# Worked out afresh, never from a cache or the bake itself.
			WaterLocks._found.clear()
			var text := JSON.stringify(WaterLocks.bake(plan), "\t", true) + "\n"
			baked += 1
			if not target.is_empty():
				var file := (target.path_join(path.get_file())) if target != "1" else path
				DirAccess.make_dir_recursive_absolute(file.get_base_dir())
				var out := FileAccess.open(file, FileAccess.WRITE)
				out.store_string(text)
				out.close()
				print("WROTE ", file)
				continue
			_check(FileAccess.file_exists(path), "A water lock stage has its bake: " + path)
			# A Windows checkout may turn the file's line ends into CRLF.
			var committed := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
			_check(committed == text, "The bake matches the stage's plan and placement (rewrite it with %s): %s" % [WRITE_ENV, path])
			# Opening the stage built its locks from the bake: no fallback, and the
			# runs it built are the committed ones.
			_check(not fell_back and JSON.stringify(built, "", true) == JSON.stringify(JSON.parse_string(committed).runs, "", true), "Opening the stage builds its locks from the bake: " + path)
			WaterLocks._found.clear()
			WaterLocks._unbaked.clear()
		world.free()
	_check(baked > 0, "At least one chapter places water locks")
	print("WATER LOCKS BAKE: %d checks, %d failures, %d stages" % [checks, failures, baked])
	quit(1 if failures else 0)
