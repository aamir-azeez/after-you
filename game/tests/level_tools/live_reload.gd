extends Node
## Live reload for building a level: edit a chapter's catalog (its layout) or
## its dressing file and the running game redraws the chapter's world at once,
## on the stage it shows, without a restart or a new recording. Development
## only: it lives under tests/, which no export includes, and runs only when
## live_game.gd starts the game in an editor build. Presentation only too:
## the edited layout goes to the world alone (load_level, show_stage); the
## engine, the registry, every save and the server keep the bundled
## definition, and nothing here writes a file or opens a connection.
##
## What it watches is read from the shown chapter's descriptor: its
## "definition" catalog and its "dressing" file, both read from `root_dir` (the
## worktree's game folder, so a TEMP copy of the game can run while the
## worktree is edited). A catalog is compiled from its text afresh, never
## through the resource cache; a script it preloads (Turn of the Tide @2 reads
## @1's catalog) keeps its bundled version. Pips keep walking the bundled
## layout until the game restarts, so a moved floor shows at once but walks
## the old way. A file that does not compile, or gives no stages, is reported
## and the world keeps what it shows.
const Index = preload("res://content/chapters/index.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
## How often the files are checked (seconds).
const POLL := 0.5

## The game folder the edited files are read from (absolute).
var root_dir := ProjectSettings.globalize_path("res://")
## The node holding the shown world (its `world`); the current scene by default.
var screen: Callable = func() -> Node: return get_tree().current_scene if is_inside_tree() else null
## What changed and was applied, for the log and tests.
var applied: Array[String] = []
var _wait := 0.0
var _times: Dictionary = {}
## The world last drawn live, the stage it showed and the live layout.
var _world: WeakRef = weakref(null)
var _stage := ""
var _level: Dictionary = {}
var _busy := false

func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0: return
	_wait = POLL
	poll()

## Checks the shown chapter's files once and redraws its world when one
## changed, or when a live layout is shown and the world moved to a new stage.
## Await it; returns whether it redrew. One check runs at a time.
func poll() -> bool:
	if _busy: return false
	_busy = true
	var redrew := await _poll()
	_busy = false
	return redrew

func _poll() -> bool:
	var holder: Node = screen.call()
	var world: Node3D = holder.get("world") if holder != null and "world" in holder else null
	if world == null or not world.has_method("load_level") or not world.has_method("_chapter_key"): return false
	var key: String = world._chapter_key()
	var data := Index.data(key)
	if data.is_empty(): return false
	if _world.get_ref() != world:
		_world = weakref(world)
		_level = {}
		_times.clear()
	var changed := false
	var source: Array = data.get("definition", [])
	if not source.is_empty() and _changed(str(source[0])):
		var level := _compile_level(source)
		if not level.is_empty():
			_level = level
			changed = true
	var dressing := str(data.get("dressing", ""))
	if not dressing.is_empty() and _changed(dressing) and _swap_dressing(key, dressing): changed = true
	if not changed and (_level.is_empty() or str(world.displayed_stage_id) == _stage): return false
	await _redraw(world, key)
	return true

## Whether a watched file changed since last looked at (the first look
## records it and counts as no change).
func _changed(path: String) -> bool:
	var time := FileAccess.get_modified_time(_on_disk(path))
	var known: Variant = _times.get(path)
	_times[path] = time
	return known != null and time != int(known)

func _on_disk(path: String) -> String:
	return root_dir.path_join(path.trim_prefix("res://"))

## The edited catalog's definition, compiled from its text alone; {} when it
## does not compile or gives no stages.
func _compile_level(source: Array) -> Dictionary:
	var script := _compile(str(source[0]))
	if script == null or not script.has_method(str(source[1])): return {}
	var level: Variant = script.callv(str(source[1]), source.slice(2))
	if not level is Dictionary or (level as Dictionary).get("stages", []).is_empty():
		push_warning("Live reload: %s gives no stages; the world keeps what it shows" % source[0])
		return {}
	applied.append("layout %s" % source[0])
	return level

## The dressing file compiled afresh and put in place of the bundled one for
## this chapter, resolved as the catalog resolves its own (dressing is
## presentation only: no engine reads it).
func _swap_dressing(key: String, path: String) -> bool:
	var script := _compile(path)
	if script == null or not script.get_script_constant_map().has("DATA"): return false
	var files: Dictionary = Dressing.FILES.duplicate()
	files[key] = script
	files.make_read_only()
	Dressing.FILES = files
	# Readers take the resolved dressing (theme, picks and slot props applied),
	# locked like the catalog's own: resolve the edited data the same way.
	var data: Dictionary = Dressing.resolve(script.get_script_constant_map().DATA)
	if not data.is_read_only(): data.make_read_only()
	var resolved: Dictionary = Dressing.RESOLVED.duplicate()
	resolved[key] = data
	resolved.make_read_only()
	Dressing.RESOLVED = resolved
	applied.append("dressing %s" % path)
	return true

func _compile(path: String) -> GDScript:
	var text := FileAccess.get_file_as_string(_on_disk(path))
	if text.is_empty(): return null
	var script := GDScript.new()
	script.source_code = text
	if script.reload() != OK:
		push_warning("Live reload: %s does not compile; the world keeps what it shows" % path)
		return null
	return script

## Rebuilds the world from the live layout (else its own) on the stage it shows.
func _redraw(world: Node3D, key: String) -> void:
	var level: Dictionary = _level if not _level.is_empty() else world.chapter_definition
	var stage_id := str(world.displayed_stage_id)
	await world.load_level(level)
	for stage: Dictionary in level.get("stages", []):
		if str(stage.id) == stage_id: await world.show_stage(stage)
	_stage = str(world.displayed_stage_id)
	print("LIVE RELOAD: %s redrawn on %s" % [key, _stage])
