extends SceneTree
const Exploration = preload("res://presentation/camera_exploration.gd")
const World = preload("res://presentation/island_world.gd")
const Levels = preload("res://core/levels.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Lighthouse = preload("res://presentation/lighthouse_world.gd")
const LighthouseCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	await _test_gestures()
	await _test_worlds()
	print("AFTER YOU CAMERA EXPLORATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _event(rig: Node, index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	rig.handle_event(event)

func _drag(rig: Node, index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	rig.handle_event(event)

func _test_gestures() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var ui := Controls.new()
	ui.settings = {"left_handed": true}
	viewport.add_child(ui)
	ui.show_play()
	var photo := Panel.new()
	photo.position = Vector2(700, 220)
	photo.size = Vector2(72, 96)
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.set_meta("player_slot", "p0")
	ui.hud.add_child(photo)
	var rig := Exploration.new()
	rig.manual = true
	rig.allowed = func(point: Vector2) -> bool: return not Exploration.ui_blocks(ui, point)
	viewport.add_child(rig)
	await process_frame
	await process_frame
	for control: Control in [ui.stick, ui.action_button, ui.pause_button, photo]:
		rig.reset_view()
		_event(rig, 0, control.get_global_rect().get_center(), true)
		_event(rig, 1, Vector2(560, 350), true)
		_drag(rig, 1, Vector2(620, 400))
		_check(rig.touches.size() == 1 and rig.zoom_ratio == 1.0 and rig.pan == Vector2.ZERO, "UI-origin fingers never join a world gesture, including left-handed controls and photos")
	rig.reset_view()
	_event(rig, 0, Vector2(450, 350), true)
	_drag(rig, 0, Vector2(450, 400))
	_check(rig.pan == Vector2.ZERO, "A single touch never pans")
	_event(rig, 1, Vector2(550, 400), true)
	_drag(rig, 0, Vector2(450, 460))
	_drag(rig, 1, Vector2(550, 460))
	_check(rig.pan.y > 0.0, "Two eligible fingers pan together")
	var previous_zoom: float = rig.zoom_ratio
	_drag(rig, 1, Vector2(650, 460))
	_check(rig.zoom_ratio < previous_zoom, "Spreading eligible fingers zooms in")
	_event(rig, 9, Vector2(600, 400), true)
	_event(rig, 9, Vector2(600, 400), false)
	_check(rig.touches.size() == 2, "An ignored third finger cannot break the tracked pair")
	var pan_before: Vector2 = rig.pan
	var zoom_before: float = rig.zoom_ratio
	rig.advance(20.0, false)
	_check(rig.pan == pan_before and rig.zoom_ratio == zoom_before, "An active gesture cannot time out")
	_event(rig, 0, Vector2.ZERO, false)
	_event(rig, 1, Vector2.ZERO, false)
	rig.advance(4.9, false)
	_check(rig.pan == pan_before, "Return waits five full seconds after release")
	rig.advance(0.45, false)
	_check(rig.pan.length() > 0 and rig.pan.length() < pan_before.length(), "Return eases toward the authored view")
	rig.advance(0.36, false)
	_check(rig.pan.is_zero_approx() and is_equal_approx(rig.zoom_ratio, 1.0), "Return completes after seven tenths of a second")
	rig.pan_pixels(Vector2(100000, -100000))
	rig.zoom(0.00001)
	_check(rig.pan.abs() == rig.maximum_pan and rig.zoom_ratio == rig.minimum_zoom, "Pan and zoom are bounded")
	rig.advance(5.0, true)
	_check(rig.pan == Vector2.ZERO and rig.zoom_ratio == 1.0, "Reduced Motion returns without animated travel")
	rig.auto_return = false
	rig.pan_pixels(Vector2(80, 50))
	pan_before = rig.pan
	rig.advance(60.0, false)
	_check(rig.pan == pan_before, "Home-style exploration persists until Reset view")
	var mouse := InputEventMouseButton.new()
	mouse.position = Vector2(500, 400)
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	rig.handle_event(mouse)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(560, 430)
	rig.handle_event(motion)
	_check(rig.pan != pan_before, "Desktop drag pans")
	rig._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(rig.touches.is_empty() and rig._mouse_button == 0, "Focus loss cancels both input families")
	rig._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	rig.reset_view()
	mouse.button_index = MOUSE_BUTTON_WHEEL_UP
	mouse.device = -1
	rig.handle_event(mouse)
	_check(rig.zoom_ratio == 1.0, "Synthetic mouse input cannot duplicate a native touch gesture")
	ui.overlay.show()
	_check(Exploration.ui_blocks(ui, Vector2(500, 400)), "A modal overlay owns the whole view")
	viewport.free()
	await process_frame

func _test_worlds() -> void:
	var cases := [
		[World, Levels.get_level("first-light")],
		[Registry.world_script(Registry.FIRST_STEPS), Registry.definition(Registry.FIRST_STEPS)],
		[Registry.world_script(Registry.RELAY), Registry.definition(Registry.RELAY)],
		[Lighthouse, LighthouseCatalog.definition()],
		[Lighthouse, LighthouseCatalog.definition("a-welcome-left-on")]
	]
	for entry: Array in cases:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1600, 720)
		root.add_child(viewport)
		var world: Node3D = entry[0].new()
		viewport.add_child(world)
		world.home_view = false
		world.load_level(entry[1])
		var enabled := [true]
		world.configure_camera_exploration(func() -> bool: return enabled[0], func(_point: Vector2) -> bool: return true)
		world.set_process(false)
		var rig: Node = world.camera_exploration
		rig.set_process(false)
		world._process(0.0)
		var base_transform: Transform3D = world.camera.transform
		var base_size: float = world.camera.size
		var base_h: float = world.camera.h_offset
		var base_v: float = world.camera.v_offset
		var definition := JSON.stringify(world.current_level)
		rig.zoom(0.65)
		rig.pan_pixels(Vector2(100, 70))
		rig._process(0.0)
		var explored_transform: Transform3D = world.camera.transform
		var explored_size: float = world.camera.size
		_check(explored_transform.basis == base_transform.basis and explored_transform.origin != base_transform.origin, "Every world's exploration translates without rotating its authored camera")
		_check(is_equal_approx(explored_size, base_size * 0.65), "Zoom composes after the actual chapter frame")
		for _frame in range(120):
			world._process(0.0)
			rig._process(0.0)
		_check(world.camera.transform.is_equal_approx(explored_transform) and is_equal_approx(world.camera.size, explored_size), "Repeated presentation frames cannot accumulate camera drift")
		# This deliberately has no running simulation: completed worlds still return.
		for _frame in range(60):
			world._process(0.0)
			rig._process(0.1)
		_check(world.camera.transform.is_equal_approx(base_transform) and is_equal_approx(world.camera.size, base_size), "A frozen completed world still returns to its authored view")
		_check(world.camera.h_offset == base_h and world.camera.v_offset == base_v and JSON.stringify(world.current_level) == definition, "Authored offsets and definitions remain unchanged")
		rig.zoom(0.7)
		rig.pan_pixels(Vector2(-90, 40))
		rig._process(0.0)
		world.reset_camera_exploration()
		_check(world.camera.transform.is_equal_approx(base_transform) and rig.pan == Vector2.ZERO and rig.zoom_ratio == 1.0, "Transitions restore the base camera and discard gestures")
		_event(rig, 0, Vector2(450, 350), true)
		enabled[0] = false
		rig._process(0.0)
		_check(rig.touches.is_empty(), "Opening an owning dialog cancels tracked fingers")
		viewport.free()
		await process_frame
