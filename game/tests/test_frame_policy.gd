extends SceneTree
## services/frame_policy.gd caps how often the app draws by what the current
## scene asks for, and never touches the simulation.
## - The table: play 60, calm screens 30 drawn only on change, a chapter
##   build uncapped, an unfocused phone 10; waking always gives full rate.
## - Headless (every suite) the autoload is inert and leaves no cap.
## - Enabled: it follows the scene's frame_demand(); input and a change of
##   demand wake it to full rate; a finger held down keeps it awake.
## - Main and the chapter screen answer by their own state.
## - Physics stays at 30 ticks a second.
const Frames = preload("res://services/frame_policy.gd")
const Preview = preload("res://relay_preview.gd")
var checks := 0
var failures := 0

class Screen extends Node3D:
	var demand := "calm"
	func frame_demand() -> String: return demand

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _run() -> void:
	# The table.
	_check(Frames.target(Frames.ACTIVE, false) == {"fps": 60, "low": false}, "Play draws 60 a second")
	_check(Frames.target(Frames.CALM, false) == {"fps": 30, "low": true}, "A calm screen draws at most 30, only on change")
	_check(Frames.target(Frames.CALM, true) == {"fps": 60, "low": false}, "Waking a calm screen gives full rate")
	_check(Frames.target(Frames.LOADING, false) == {"fps": 0, "low": false}, "A chapter build is not capped")
	_check(Frames.target("anything else", false) == {"fps": 60, "low": false}, "An unknown demand is treated as play")
	_check(Frames.target(Frames.ACTIVE, false, false, true) == {"fps": 10, "low": true}, "An unfocused phone draws 10 a second")
	_check(Frames.target(Frames.ACTIVE, false, false, false) == {"fps": 60, "low": false}, "Desktop focus does not change the rate")
	# Headless: inert.
	var autoload: Node = root.get_node_or_null("FramePolicy")
	_check(autoload != null and not autoload.enabled, "The autoload is present and inert headless")
	await _frames(3)
	_check(Engine.max_fps == 0 and not OS.low_processor_usage_mode, "Headless runs keep no cap")
	# Enabled, against a stand-in scene.
	var screen := Screen.new()
	root.add_child(screen)
	current_scene = screen
	var policy: Node = Frames.new()
	policy.enabled = true
	root.add_child(policy)
	await _frames(2)
	_check(Engine.max_fps == 60 and not OS.low_processor_usage_mode, "A new demand first wakes to full rate")
	policy._wake_until = 0
	await _frames(2)
	_check(Engine.max_fps == 30 and OS.low_processor_usage_mode, "A calm screen settles to 30, drawn on change")
	_check(policy.current().demand == Frames.CALM, "current() reports the demand")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(10, 10)
	Input.parse_input_event(touch)
	await _frames(2)
	_check(Engine.max_fps == 60 and not OS.low_processor_usage_mode, "A touch wakes it at once")
	policy._wake_until = 0
	await _frames(2)
	_check(Engine.max_fps == 60, "A finger held down keeps full rate")
	touch = touch.duplicate()
	touch.pressed = false
	Input.parse_input_event(touch)
	await _frames(1)
	policy._wake_until = 0
	await _frames(2)
	_check(Engine.max_fps == 30, "Lifting the finger lets it settle again")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	_check(Engine.max_fps == 60 and policy._wake_until > Time.get_ticks_msec() + Frames.INPUT_WAKE_MSEC - 500, "A key wakes it for the input moment")
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	policy._wake_until = 0
	await _frames(2)
	screen.demand = Frames.LOADING
	await _frames(2)
	_check(Engine.max_fps == 0 and not OS.low_processor_usage_mode, "A chapter build runs uncapped")
	screen.demand = Frames.ACTIVE
	await _frames(2)
	_check(Engine.max_fps == 60, "Play runs at 60")
	policy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	policy._mobile = true
	await _frames(2)
	_check(Engine.max_fps == 10 and OS.low_processor_usage_mode, "An unfocused phone drops to 10")
	policy._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(2)
	_check(Engine.max_fps == 60 and not OS.low_processor_usage_mode, "Focus back restores play's rate")
	policy._mobile = false
	current_scene = null
	await _frames(2)
	_check(Engine.max_fps == 60, "No scene counts as play")
	policy.free()
	screen.free()
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	_check(ProjectSettings.get_setting("physics/common/physics_ticks_per_second") == 30 and Engine.physics_ticks_per_second == 30, "Physics stays at 30 ticks a second")
	_check(not ProjectSettings.has_setting("application/run/max_fps") or int(ProjectSettings.get_setting("application/run/max_fps")) == 0, "No project-wide cap (it would also slow headless runs)")
	# The chapter screen's answers, by its own state.
	var preview: Node = Preview.new()
	preview.mode = "loading"
	_check(preview.frame_demand() == Frames.LOADING, "A chapter loading is not capped")
	for name: String in ["play", "replay", "bloom", "moment"]:
		preview.mode = name
		_check(preview.frame_demand() == Frames.ACTIVE, "Chapter %s is full rate" % name)
	for name: String in ["ready", "review", "online_waiting", "turn_wait", "paused", "complete", "replay_collection", "error"]:
		preview.mode = name
		_check(preview.frame_demand() == Frames.CALM, "Chapter card %s is calm" % name)
	preview.mode = "paused"
	preview._story_hold = 3
	_check(preview.frame_demand() == Frames.ACTIVE, "A story camera move is full rate")
	preview.free()
	# Main's answers.
	change_scene_to_file("res://main.tscn")
	var guard := 0
	while (current_scene == null or current_scene.get("mode") != "home") and guard < 600:
		await process_frame
		guard += 1
	var app: Node = current_scene
	_check(app != null and app.frame_demand() == Frames.CALM, "Home is calm")
	app._show_journey()
	await _frames(2)
	_check(app.frame_demand() == Frames.CALM, "A page is calm")
	app._show_home()
	app.running = true
	_check(app.frame_demand() == Frames.ACTIVE, "Main's own play is full rate")
	app.running = false
	app.capture_path = "user://unused.png"
	_check(app.frame_demand() == Frames.ACTIVE, "A capture run draws every frame")
	app.capture_path = ""
	var opening := CanvasLayer.new()
	app._chapter_opening = opening
	_check(app.frame_demand() == Frames.LOADING, "Opening a chapter is not capped")
	app._chapter_opening = null
	opening.free()
	var child := Screen.new()
	child.demand = Frames.ACTIVE
	app.relay_child = child
	_check(app.frame_demand() == Frames.ACTIVE, "A room chapter answers for itself")
	app.relay_child = null
	child.free()
	await _frames(2)
	_check(Engine.max_fps == 0, "The suite ends with no cap")
	print("FRAME POLICY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
