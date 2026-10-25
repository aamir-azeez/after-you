extends Node
## Loads a chapter screen's scene on a worker while the player is idle at
## Home, so that the first open in a session finds the screen's script loaded.
## Every chapter but First Steps and Relay opens on cooperative_preview.gd, a
## script Home never loads, and the open loaded it behind its card first
## (chapter_loading_card.gd prepare()): about a quarter of a second of the
## first open of each session on a desktop, none on later opens.
##
## - At most one scene load a visit to Home (this node lives as long as Home):
##   the scene of the first of chapters() (the one most likely opened next
##   first) that still needs something loaded (cold()). Scenes whose scripts
##   are loaded already cost nothing and are passed over, so once the shared
##   script is loaded every later visit does nothing.
## - Starts once idle() has held with no touch, click or key for IDLE_SECONDS,
##   and never while the app is in the background. A load already started
##   runs to its end on the worker; it is the visit's one load either way.
## - The loaded scene is held for the session (released through
##   SessionRelease), so its script stays loaded until the chapter opens.
##   Leaving Home while the worker still loads hands the worker to the reaper
##   and holds nothing; an open of the same scene meanwhile waits on the same
##   load. A later idle Home loads it again if it is still needed.
## - Presentation only: nothing it loads is changed or run. Headless runs
##   (tests, tools) never load unless a test enables it.
const Registry = preload("res://services/chapter_registry.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const HeldPresses = preload("res://services/held_presses.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const SCRIPT_PATH := "res://services/scene_prewarm.gd"
const IDLE_SECONDS := 1.5

## Scenes loaded this session, by path.
static var _held: Dictionary = {}

## True while the player is idle at Home; set by the owner.
var idle: Callable
## The registry keys the player can open now, most likely first; set by the owner.
var chapters: Callable
var enabled := DisplayServer.get_name() != "headless"
var idle_seconds := IDLE_SECONDS

var _idle_for := 0.0
var _presses := HeldPresses.new()
var _backgrounded := false
var _loader: Thread
var _loading := ""
var _visit_done := false

## Whether a resource the scene at path names (its screen script) is not
## loaded yet, so an open of it would load that first. The scene file itself
## is a quick read and does not count.
static func cold(path: String) -> bool:
	if path.is_empty() or _held.has(path) or not ResourceLoader.exists(path): return false
	for dependency: String in ResourceLoader.get_dependencies(path):
		# An entry may carry its uid and type before the path ("...::path").
		var parts := dependency.split("::")
		if not ResourceLoader.has_cached(parts[parts.size() - 1]): return true
	return false

## The scenes held this session, for tests.
static func held() -> Array:
	return _held.keys()

## Lets go of every held scene (SessionRelease at shutdown; tests).
static func release() -> void:
	_held.clear()

## True while the worker loads a scene.
func running() -> bool:
	return _loader != null

## Pauses now; a later idle frame goes on.
func stop() -> void:
	_idle_for = 0.0

## Any touch, click or key: the player is not idle.
func _input(event: InputEvent) -> void:
	_presses.track(event)
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask == 0: return
	_idle_for = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_backgrounded = true
		_presses.clear()
		stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_backgrounded = false

func _exit_tree() -> void:
	# Never wait here: the reaper joins a worker still loading.
	if _loader != null:
		Reaper.adopt(_loader)
		_loader = null

func _process(delta: float) -> void:
	if _loader != null:
		if not _loader.is_alive(): _take()
		return
	if not enabled or _visit_done or _backgrounded or _presses.any() or not idle.is_valid() or not idle.call():
		_idle_for = 0.0
		return
	_idle_for += delta
	if _idle_for < idle_seconds: return
	_visit_done = true
	var scene := _next_scene()
	if scene.is_empty(): return
	var loader := Thread.new()
	Reaper.ensure()
	# A static function and a copy of the path: no node crosses to the worker.
	if loader.start(Callable(get_script(), "_load").bind(scene)) != OK: return
	_loader = loader
	_loading = scene

## The scene of the first chapter offered that is still cold, or "".
func _next_scene() -> String:
	if not chapters.is_valid(): return ""
	for key: String in chapters.call():
		var scene := Registry.solo_scene(key)
		if cold(scene): return scene
	return ""

## Runs on the worker.
static func _load(path: String) -> Resource:
	return ResourceLoader.load(path)

## Joins the worker and holds what it loaded.
func _take() -> void:
	var loaded: Variant = _loader.wait_to_finish()
	_loader = null
	if loaded is PackedScene:
		_held[_loading] = loaded
		SessionRelease.on_exit(Callable(load(SCRIPT_PATH), "release"))
	_loading = ""
