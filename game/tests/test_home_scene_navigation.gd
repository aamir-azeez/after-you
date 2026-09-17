extends SceneTree
## Use real scene changes without preloading Main or HomeStage: no test-held
## script reference may keep their session state alive across chapter scenes.
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _wait_for_scene(path: String) -> bool:
	for frame in range(30):
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			return true
	_check(false, "Scene navigation reaches " + path)
	return false

func _run() -> void:
	change_scene_to_file("res://main.tscn")
	if await _wait_for_scene("res://main.tscn"):
		await _test_round_trip()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		await process_frame
		await process_frame
	print("AFTER YOU HOME SCENE NAVIGATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_round_trip() -> void:
	var app: Node = current_scene
	var stage: Control = app.overlay.get_child(0)
	stage.set_process(false)
	var default_size: float = stage.DEFAULT_SIZE
	_check(stage.zoom_target == default_size and stage._exploration.pan == Vector2.ZERO,
		"A fresh app process starts with the authored home view")
	var center: Vector2 = stage._stage_rect().get_center()
	var left := center - Vector2(60, 0)
	var right := center + Vector2(60, 0)
	_touch(0, left, true)
	_touch(1, right, true)
	_drag(0, left, left + Vector2(10, 35))
	_drag(1, right, right + Vector2(70, 35))
	# Intentionally leave fingers down: navigation must retain framing alone.
	for frame in range(180): stage._process(1.0 / 60.0)
	var zoom: float = stage.zoom_target
	var pan: Vector2 = stage._exploration.pan
	var retained_frame: Transform3D = app.world.camera.global_transform
	var size: float = app.world.camera.size
	var offsets := Vector2(app.world.camera.h_offset, app.world.camera.v_offset)
	_check(zoom < default_size and not pan.is_zero_approx(),
		"Dispatched viewport gestures establish a non-default home view")
	var old_app: WeakRef = weakref(app)
	var old_world: WeakRef = weakref(app.world)
	var old_stage: WeakRef = weakref(stage)
	app._open_relay_preview()
	app = null
	stage = null
	if not await _wait_for_scene("res://relay_preview.tscn"): return
	_check(old_app.get_ref() == null and old_world.get_ref() == null and old_stage.get_ref() == null,
		"Opening the chapter frees the actual prior Main, World and HomeStage")
	var chapter: Node = current_scene
	_check(chapter.world.camera_exploration.pan == Vector2.ZERO and chapter.world.camera_exploration.zoom_ratio == 1.0
		and chapter.world.camera.h_offset == 0.0 and chapter.world.camera.v_offset == 0.0,
		"The chapter starts with its authored camera instead of inherited home exploration")
	var old_chapter: WeakRef = weakref(chapter)
	chapter._leave()
	chapter = null
	if not await _wait_for_scene("res://main.tscn"): return
	_check(old_chapter.get_ref() == null, "Returning home frees the chapter scene")
	app = current_scene
	stage = app.overlay.get_child(0)
	stage.set_process(false)
	stage._process(0.0)
	_check(is_equal_approx(stage.zoom_target, zoom) and stage._exploration.pan.is_equal_approx(pan)
		and stage._touches.is_empty(), "A newly loaded Main retains home framing without captured fingers")
	_check(app.world.camera.global_transform.is_equal_approx(retained_frame) and is_equal_approx(app.world.camera.size, size)
		and Vector2(app.world.camera.h_offset, app.world.camera.v_offset).is_equal_approx(offsets),
		"Chapter return composes retained exploration exactly once on the new authored camera")
	stage._reset.pressed.emit()
	for tick in range(180): stage._process(1.0 / 60.0)
	app._open_relay_preview()
	app = null
	stage = null
	if not await _wait_for_scene("res://relay_preview.tscn"): return
	current_scene._leave()
	if not await _wait_for_scene("res://main.tscn"): return
	stage = current_scene.overlay.get_child(0)
	_check(stage.zoom_target == default_size and stage._exploration.pan == Vector2.ZERO and not stage._reset.visible,
		"Reset view remains reset after another complete chapter round trip")

func _touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)

func _drag(index: int, before: Vector2, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = point - before
	root.push_input(event, true)
