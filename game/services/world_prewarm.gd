extends Node
## Builds a heavy chapter's world once, unseen, while the player is idle at
## Home, so that opening the chapter later finds the geometry worked out from
## its definition (kit/definition_geometry.gd) and its folded batches
## (kit/static_batch.gd) already made, and builds none of it again. The first
## open of Turn of the Tide in a session built both behind its card, and
## folded the rest over many frames of its ready card.
##
## - Only chapters whose descriptor sets "prewarm_world", that the owner's
##   chapters() offers (unlocked), and only once per chapter and stage a run.
##   The stage is the one the solo save opens on, read on a worker (never
##   written); an unreadable save warms the first stage.
## - At most one chapter a visit to Home: the first of chapters() (the one
##   most likely opened next first) whose stage is not warm yet. A stage warm
##   already, or a world let go unfinished (away), does not count. So Home's
##   idle work stays one world's build and fold a visit.
## - Starts once idle() has held with no touch, click or key for IDLE_SECONDS.
##   It builds a slice of BUILD_SLICE_USEC each frame, then folds the same way:
##   any input, a busy or backgrounded app or a chapter opening pauses it
##   between slices, and a later idle Home goes on where it stopped. Once
##   away() holds (a room or a shared replay opens under Home, which stays),
##   a world still unfinished is let go, so it never stays beside one; a later
##   idle Home starts it again. A chapter built for real counts as warm
##   (note_built).
## - The world stands in a SubViewport of its own that never draws, so its
##   camera, light and environment touch nothing on screen. Once folded it
##   leaves the tree and is freed a slice a frame (services/screen_switch.gd).
##   Leaving Home frees a world still being built the same way, with the
##   screen: its build waits on the world's own build_tick
##   (island_world._build_step), so it is never resumed.
## - Presentation only, and only caches that are exact by key: a chapter
##   built after a warm-up is the same, node for node, as one built cold
##   (tests/test_world_prewarm.gd). No simulation, save or replay reads it.
##   Headless runs (tests, tools) never warm unless a test enables it.
const Registry = preload("res://services/chapter_registry.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const ScreenSwitch = preload("res://services/screen_switch.gd")
const ProofWarmup = preload("res://services/journey_proof_warmup.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const HeldPresses = preload("res://services/held_presses.gd")

const IDLE_SECONDS := 1.5
## The wall time each idle frame gives the build, and then the fold.
const BUILD_SLICE_USEC := 2500
const FOLD_SLICE_USEC := 2500
const VIEW_SIZE := Vector2i(16, 16)

## Chapter and stage warmed this run ("key|stage id").
static var _warmed: Dictionary = {}

## True while the player is idle at Home; set by the owner.
var idle: Callable
## The saved settings now, for the graphics quality the chapter builds with.
var settings: Callable
## True once the player has gone somewhere that keeps Home alive beneath it
## (a room, a shared replay); set by the owner.
var away: Callable
## The registry keys the player can open now, most likely first; set by the owner.
var chapters: Callable
## Whether a chapter's world is warmed at all; its descriptor's
## "prewarm_world" (flagged) unless a test sets another.
var wants: Callable = flagged
var enabled := DisplayServer.get_name() != "headless"
var idle_seconds := IDLE_SECONDS

var _idle_for := 0.0
var _presses := HeldPresses.new()
var _backgrounded := false
## The chapter being warmed, its definition and stage once read, and the
## worker reading them.
var _key := ""
var _definition: Dictionary = {}
var _stage: Dictionary = {}
var _reader: Thread
var _view: SubViewport
var _world: Node3D
var _building := false
var _fold: Dictionary = {}
## Chapters looked at on this visit to Home (this node lives as long as
## it), those still to look at, and whether none is left.
var _looked: Dictionary = {}
var _candidates: Array[String] = []
var _asked := false
var _visit_done := false

## Whether key's descriptor asks for the warm-up ("prewarm_world").
static func flagged(key: String) -> bool:
	return bool(ChapterIndex.data(key).get("prewarm_world", false))

## Chapter and stage pairs warmed this run, for tests.
static func warmed() -> Array:
	return _warmed.keys()

## A chapter screen built stage_id of key itself: its caches are as warm.
static func note_built(key: String, stage_id: String) -> void:
	if not key.is_empty() and not stage_id.is_empty(): _warmed["%s|%s" % [key, stage_id]] = true

## Forgets what this run warmed (tests).
static func forget() -> void:
	_warmed.clear()

## True while a chapter's world is being built or folded here.
func running() -> bool:
	return is_instance_valid(_world)

## Whether the world being warmed is still building.
func building() -> bool:
	return _building

## Pauses now; a later idle Home goes on where it stopped.
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
	# Never wait here: a reader still running is joined by the reaper. A
	# world still here leaves with this node's tree (the screen's disposal).
	if _reader != null:
		Reaper.adopt(_reader)
		_reader = null

func _process(delta: float) -> void:
	if _reader != null and not _reader.is_alive(): _take_stage()
	var gone: bool = away.is_valid() and away.call()
	if is_instance_valid(_view) and gone: _drop()
	# A finger held still (an Explore stick, a pinch) is not idle either.
	if not enabled or _visit_done or _backgrounded or gone or _presses.any() or not idle.is_valid() or not idle.call():
		_idle_for = 0.0
		return
	_idle_for += delta
	if _idle_for < idle_seconds: return
	if _key.is_empty():
		# One look a frame: the reader runs between them.
		_choose()
		return
	if _stage.is_empty() or _reader != null: return
	if not is_instance_valid(_world):
		_open()
		return
	if _building:
		_world.build_tick.emit()
		return
	if _fold.is_empty():
		_start_fold()
		return
	if StaticBatch.step(_fold, FOLD_SLICE_USEC): _close()

## The next chapter offered on this visit that has a world to warm, and a
## worker reading the stage its save opens on. The offered chapters are asked
## once a visit; with none left this visit does nothing more.
func _choose() -> void:
	if not _asked and chapters.is_valid():
		_asked = true
		for key: String in chapters.call():
			if bool(wants.call(key)) and not _candidates.has(key): _candidates.append(key)
	while not _candidates.is_empty():
		var key: String = _candidates.pop_front()
		if _looked.has(key): continue
		_looked[key] = true
		var path := str(ChapterIndex.data(key).get("local_path", ""))
		var reader := Thread.new()
		Reaper.ensure()
		# A static function and copies of the key and path: no node crosses to
		# the worker. It works out the chapter's definition there too.
		if reader.start(Callable(get_script(), "_read").bind(key, path)) != OK: return
		_key = key
		_reader = reader
		return
	_visit_done = true

## Joins the reader and picks the stage; a stage warmed already ends here.
func _take_stage() -> void:
	var read: Variant = _reader.wait_to_finish()
	_reader = null
	_definition = read.get("definition", {}) if read is Dictionary else {}
	var pairs: int = int(read.get("pairs", 0)) if read is Dictionary else 0
	var stages: Array = _definition.get("stages", [])
	var stage: Dictionary = stages[clampi(pairs, 0, stages.size() - 1)] if not stages.is_empty() else {}
	if stage.is_empty() or _warmed.has(_warmed_key(_key, stage)):
		if not stage.is_empty(): _warmed[_warmed_key(_key, stage)] = true
		_key = ""
		_definition = {}
		return
	_stage = stage

## The chapter's definition and its save's played pairs (_saved_pairs).
## Runs on the reader.
static func _read(key: String, path: String) -> Dictionary:
	return {"definition": Registry.definition(key), "pairs": _saved_pairs(path)}

## Turns of the save at path that are both played (one per finished stage),
## or 0 when there is none or it cannot be read.
static func _saved_pairs(path: String) -> int:
	if path.is_empty(): return 0
	var relay: Variant = ProofWarmup._read(path)
	if not relay is Dictionary: return 0
	var pairs: Variant = (relay as Dictionary).get("pairs")
	return (pairs as Array).size() if pairs is Array else 0

static func _warmed_key(key: String, stage: Dictionary) -> String:
	return "%s|%s" % [key, str(stage.get("id", ""))]

## Makes the hidden view and starts the world's build, paced by this node.
func _open() -> void:
	_view = SubViewport.new()
	_view.name = "WorldPrewarm"
	_view.size = VIEW_SIZE
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	_world = Registry.world_script(_key).new()
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_world.visible = false
	_view.add_child(_world)
	var saved: Variant = settings.call() if settings.is_valid() else {}
	if _world.has_method("apply_graphics_quality"): _world.apply_graphics_quality(GraphicsPolicy.normalize(saved.get("graphics_quality") if saved is Dictionary else null))
	_world.paced_build = true
	_building = true
	_build(_world, _definition, str(_stage.get("id", "")))

func _build(world: Node3D, definition: Dictionary, stage_id: String) -> void:
	await world.build_staged(definition, BUILD_SLICE_USEC, stage_id)
	# Only the build this node still waits for: a freed world never gets here.
	if world == _world: _building = false

## Folds the built terrain as a chapter screen would (island_world's own
## options), a slice an idle frame.
func _start_fold() -> void:
	var terrain: Variant = _world.get("terrain")
	if bool(ChapterIndex.data(_key).get("fold_static", false)) and is_instance_valid(terrain) and (terrain as Node3D).is_inside_tree():
		_fold = StaticBatch.start(terrain, [_world], _world._fold_options())
	if _fold.is_empty(): _close()

## Done: this chapter and stage are warm, and the world goes, a slice a frame.
## That is this visit's one chapter.
func _close() -> void:
	_warmed[_warmed_key(_key, _stage)] = true
	_visit_done = true
	_let_go()

## Lets an unfinished world go (see away); this chapter is looked at again.
func _drop() -> void:
	_looked.erase(_key)
	if not _candidates.has(_key): _candidates.push_front(_key)
	_visit_done = false
	_let_go()

## The world goes, a slice a frame (services/screen_switch.gd).
func _let_go() -> void:
	_building = false
	_key = ""
	_definition = {}
	_stage = {}
	_fold = {}
	_world = null
	if is_instance_valid(_view):
		var bin := Node.new()
		remove_child(_view)
		bin.add_child(_view)
		ScreenSwitch.release(bin)
		bin.free()
	_view = null
