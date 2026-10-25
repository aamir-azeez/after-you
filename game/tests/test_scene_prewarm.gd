extends SceneTree
## services/scene_prewarm.gd loads, while Home is idle, the scene of a chapter
## whose screen script is not loaded yet, so the chapter's first open finds it
## loaded.
## - Never while not idle, while a finger rests on the screen, or while the
##   app is in the background.
## - One scene load a visit, the first of chapters() still cold: a scene whose
##   script is loaded already is passed over, and the next visit loads the next.
## - An open of the same scene while the worker loads it gets the scene; Home
##   leaving mid-load holds nothing and leaves no worker behind.
## - Its held scenes go with SessionRelease's release.
const ScenePrewarm = preload("res://services/scene_prewarm.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const FIRST := "first-steps@1"
const WELL := "the-wishing-well@1"
const RELAY_SCRIPT := "res://relay_preview.gd"
const SHARED_SCRIPT := "res://cooperative_preview.gd"

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var first_scene := Registry.solo_scene(FIRST)
	var well_scene := Registry.solo_scene(WELL)
	var both: Array[String] = [FIRST, WELL]
	_check(not ResourceLoader.has_cached(RELAY_SCRIPT) and not ResourceLoader.has_cached(SHARED_SCRIPT), "Neither screen script is loaded at the start")
	_check(ScenePrewarm.cold(first_scene) and ScenePrewarm.cold(well_scene), "Both scenes are cold")
	var home := Node.new()
	root.add_child(home)
	# Not idle, then idle with a finger resting: nothing loads.
	var idle := [false]
	var visit := _prewarm(func() -> bool: return idle[0], both)
	home.add_child(visit)
	var started := false
	for i in range(60):
		await process_frame
		started = started or visit.running()
	_check(not started and ScenePrewarm.held().is_empty(), "Nothing loads while Home is not idle")
	idle[0] = true
	_press(true)
	for i in range(60):
		await process_frame
		started = started or visit.running()
	_check(not started and ScenePrewarm.held().is_empty(), "Nothing loads while a finger rests on the screen")
	_press(false)
	visit.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	for i in range(60):
		await process_frame
		started = started or visit.running()
	_check(not started and ScenePrewarm.held().is_empty(), "Nothing loads while the app is in the background")
	visit.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	# One load this visit: the first chapter's scene, and nothing more.
	await _until(func() -> bool: return ScenePrewarm.held().has(first_scene))
	var after_first := false
	for i in range(120):
		await process_frame
		after_first = after_first or visit.running()
	_check(ScenePrewarm.held() == [first_scene] and not after_first, "One idle visit loads the most likely chapter's scene only (%s)" % [ScenePrewarm.held()])
	_check(ResourceLoader.has_cached(RELAY_SCRIPT) and not ResourceLoader.has_cached(SHARED_SCRIPT), "...which loads its screen script and no other")
	_check(not ScenePrewarm.cold(first_scene) and ScenePrewarm.cold(well_scene), "Its scene is warm now, the other still cold")
	visit.queue_free()
	await process_frame
	# The next visit loads the next scene; an open of it meanwhile gets it,
	# and Home leaving mid-load holds nothing.
	var next := _prewarm(func() -> bool: return true, both)
	home.add_child(next)
	await _until(func() -> bool: return next.running())
	_check(next.running() and next._loading == well_scene, "The next visit loads the next chapter's scene")
	_check(ResourceLoader.load_threaded_request(well_scene) == OK, "An open of the same scene meanwhile asks for it")
	root.remove_child(home)
	home.free()
	var status := ResourceLoader.THREAD_LOAD_IN_PROGRESS
	var guard := 0
	while guard < 3000 and status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await process_frame
		guard += 1
		status = ResourceLoader.load_threaded_get_status(well_scene)
	var opened := ResourceLoader.load_threaded_get(well_scene) as PackedScene
	_check(opened != null and opened.can_instantiate(), "...and gets it (%d frames)" % guard)
	guard = 0
	while guard < 600 and Reaper.pending_count() > 0:
		await process_frame
		guard += 1
	_check(Reaper.pending_count() == 0 and not ScenePrewarm.held().has(well_scene), "Home leaving mid-load holds nothing and leaves no worker (%d frames)" % guard)
	_check(ResourceLoader.has_cached(SHARED_SCRIPT) and not ScenePrewarm.cold(well_scene), "The open loaded its script: the scene is warm")
	# Everything warm: a visit loads nothing.
	var home2 := Node.new()
	root.add_child(home2)
	var warm := _prewarm(func() -> bool: return true, both)
	home2.add_child(warm)
	var any := false
	for i in range(90):
		await process_frame
		any = any or warm.running()
	_check(not any and ScenePrewarm.held() == [first_scene], "With every scene warm a visit loads nothing")
	home2.queue_free()
	ScenePrewarm.release()
	_check(ScenePrewarm.held().is_empty(), "release() lets every held scene go")
	opened = null
	await process_frame
	await process_frame
	print("SCENE PREWARM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _prewarm(idle: Callable, keys: Array[String]) -> Node:
	var prewarm: Node = ScenePrewarm.new()
	prewarm.enabled = true
	prewarm.idle_seconds = 0.0
	prewarm.idle = idle
	prewarm.chapters = func() -> Array[String]: return keys
	return prewarm

func _until(done: Callable) -> void:
	var guard := 0
	while guard < 3000 and not done.call():
		await process_frame
		guard += 1

func _press(pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(200, 400)
	touch.pressed = pressed
	root.push_input(touch)

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)
	return value
