extends SceneTree
## Home's idle warm-ups (services/world_prewarm.gd, services/gl_warmup.gd)
## wait while a finger rests on the screen: a held Explore stick or a pinch
## held still sends no new events, and the player is not idle. Before, a
## warm-up started a second later and hitched the walk.
const WorldPrewarm = preload("res://services/world_prewarm.gd")
const GlWarmup = preload("res://services/gl_warmup.gd")
const KEY := "turn-of-the-tide@2"

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var home := Node.new()
	root.add_child(home)
	var prewarm: Node = WorldPrewarm.new()
	prewarm.enabled = true
	prewarm.idle_seconds = 0.0
	prewarm.idle = func() -> bool: return true
	prewarm.chapters = func() -> Array[String]: return [KEY]
	prewarm.settings = func() -> Dictionary: return {"graphics_quality": "balanced"}
	var gl: Node = GlWarmup.new()
	gl.enabled = true
	gl.idle_seconds = 0.0
	gl.idle = func() -> bool: return true
	gl.settings = func() -> Dictionary: return {"graphics_quality": "balanced"}
	GlWarmup.stamp_path = "user://held-touch-gl-" + Crypto.new().generate_random_bytes(6).hex_encode() + ".json"
	home.add_child(prewarm)
	home.add_child(gl)
	_press(true)
	var started := false
	for frame in range(120):
		await process_frame
		started = started or prewarm.running() or gl.running()
	_check(not started, "Nothing warms while a finger rests on the screen (world %s, GL %s)" % [prewarm.running(), gl.running()])
	_press(false)
	var world_started := false
	var gl_started := false
	for frame in range(600):
		await process_frame
		world_started = world_started or prewarm.running() or not WorldPrewarm.warmed().is_empty()
		gl_started = gl_started or gl.running()
		if world_started and gl_started: break
	_check(world_started and gl_started, "Once it lifts, both warm up as before (world %s, GL %s)" % [world_started, gl_started])
	home.queue_free()
	await process_frame
	await process_frame
	if FileAccess.file_exists(GlWarmup.stamp_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(GlWarmup.stamp_path))
	print("HOME WARMUP HELD TOUCH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _press(pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(200, 400)
	touch.pressed = pressed
	root.push_input(touch)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
