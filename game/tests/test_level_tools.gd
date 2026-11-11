extends SceneTree
## The level tools (tests/level_tools/) where they can be checked headless:
##  - the shared level graph's reach finds what a small layout hides behind
##    its own gate, by each family's rule, so the checker can fail;
##  - the flat map plan's data, from definitions alone: every control, the
##    pair tags' own letters and colours, gates on real crossings, for every
##    stage of every floor chapter and for a layout no chapter registers;
##  - the stage shots: a pip beside a control stands on its floor, a worked
##    control opens what its gates say;
##  - live reload redraws a world from an edited catalog and dressing read from
##    a folder outside the game, leaves the registry's definition, user:// and
##    the engine alone, keeps the world on a catalog with no stages, and
##    ships nowhere (every export leaves tests/ out; nothing outside tests/
##    names it).
const Registry = preload("res://services/chapter_registry.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Shots = preload("res://tests/level_tools/stage_shots.gd")
const Model = preload("res://tests/level_tools/map_plan_model.gd")
const LiveReload = preload("res://tests/level_tools/live_reload.gd")
const PairTags = preload("res://presentation/kit/pair_tags.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_graph()
	_maps()
	_shots()
	await _live()
	_ships_nowhere()
	print("LEVEL TOOLS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

# --- The graph ----------------------------------------------------------------------

## Three floors in a row; the second crossing's lever stands beyond it.
static func _small(journey: bool) -> Dictionary:
	var gate_b := {"route_id": "b-c", "when": {"lever_id": "far-lever"}} if journey else {"route_id": "b-c", "lever_id": "far-lever"}
	var gate_a := {"route_id": "a-b", "when": {"lever_id": "near-lever"}} if journey else {"route_id": "a-b", "lever_id": "near-lever"}
	return {"id": "small", "version": 1, "title": "Small",
		"starts": {"p0": [100, 100], "p1": [100, 150]},
		"islands": [{"id": "a", "rect_cm": [0, 0, 200, 200], "height_cm": 0}, {"id": "b", "rect_cm": [400, 0, 600, 200], "height_cm": 0}, {"id": "c", "rect_cm": [800, 0, 1000, 200], "height_cm": 0}],
		"bridges": [{"id": "a-b", "rect_cm": [200, 50, 400, 150], "from_surface": "a", "to_surface": "b", "height_cm": 0, "owner_slot": ""}, {"id": "b-c", "rect_cm": [600, 50, 800, 150], "from_surface": "b", "to_surface": "c", "height_cm": 0, "owner_slot": ""}],
		"stairs": [], "drops": [], "props": [],
		"stages": [{"id": "only", "version": 1, "first_player_slot": "p0",
			"levers": [{"id": "near-lever", "position_cm": [150, 40], "surface_id": "a", "radius_cm": 28, "owner_slot": "p0"}, {"id": "far-lever", "position_cm": [900, 100], "surface_id": "c", "radius_cm": 28, "owner_slot": "p1"}],
			"pressure_pads": [], "ball_pads": [], "gates": [gate_a, gate_b],
			"goal": {"id": "bell", "position_cm": [500, 100], "surface_id": "b", "radius_cm": 28, "owner_slot": "p1"}, "goal_policy": {"kind": "ring"}}]}

func _graph() -> void:
	for journey: bool in [false, true]:
		var level := _small(journey)
		var view := CooperativeCatalog.stage_definition(level, "only")
		var found: Dictionary = LevelGraph.new(level).reach(view, Stages.starts_checkpoint(level), journey)
		var family := "journey" if journey else "cooperative"
		_check(found.floors.p0.has("b") and found.floors.p1.has("b") and found.open.has("a-b"), "%s: a lever both can reach opens its crossing for both pips" % family)
		_check(not found.floors.p0.has("c") and not found.floors.p1.has("c") and not found.open.has("b-c"), "%s: a crossing whose lever stands beyond it never opens, and the floor past it is out of reach" % family)
		var graph: RefCounted = LevelGraph.new(level)
		graph.reach(view, Stages.starts_checkpoint(level), journey)
		_check(graph.can_stand_at(view.levers[0], "p0", found.open) and graph.can_stand_at(view.goal, "p1", found.open), "%s: a pip can stand at a lever and a goal on reached floors" % family)
	var moved := _small(false)
	moved.stages[0].levers[1].position_cm = [300, 40]
	moved.stages[0].levers[1].surface_id = "a"
	var view := CooperativeCatalog.stage_definition(moved, "only")
	_check(LevelGraph.new(moved).reach(view, Stages.starts_checkpoint(moved), false).floors.p0.has("c"), "Moving that lever to the near side lets both reach the far floor")

# --- The map plan -----------------------------------------------------------------

func _maps() -> void:
	var stages := 0
	for key: String in Registry.keys():
		if not Stages.floor_chapter(key): continue
		var level := Registry.definition(key)
		var digest := Canonical.digest(level)
		for item: Dictionary in Stages.stages(key, level):
			var view: Dictionary = item.view
			var plan := Model.build(level, view, item.checkpoint, Registry.is_journey(key))
			var where := "%s %s" % [key, view.stage_id]
			var wanted: Array = []
			for kind: String in ["controls", "levers", "pressure_pads", "ball_pads"]:
				for entity: Dictionary in view.get(kind, []): wanted.append(str(entity.id))
			_check(plan.controls.map(func(c: Dictionary) -> String: return c.id) == wanted, "%s: the plan shows every control once" % where)
			var pairs := PairTags.pairs_of(view)
			_check(plan.pairs.size() == pairs.size(), "%s: one plan pair per wired control (%d)" % [where, pairs.size()])
			var routes: Array = plan.crossings.map(func(c: Dictionary) -> String: return c.id)
			for index in range(mini(plan.pairs.size(), pairs.size())):
				var pair: Dictionary = plan.pairs[index]
				_check(pair.control == pairs[index].control and pair.letter == PairTags.letter_of(index) and pair.colour == PairTags.colour_of(index), "%s: %s keeps the game's letter and colour" % [where, pair.control])
				_check(pair.gates.all(func(g: Dictionary) -> bool: return g.route in routes), "%s: %s's gates are crossings on the plan" % [where, pair.control])
			_check(plan.floors.any(func(f: Dictionary) -> bool: return f.reached) and plan.starts.size() == 2, "%s: the plan marks reach and both starts" % where)
			stages += 1
		_check(Canonical.digest(level) == digest, "%s: drawing plans never changes the definition" % key)
	_check(stages >= 18, "Plans for every floor chapter's stages (%d)" % stages)
	var bare := _small(true)
	var plan := Model.build(bare, CooperativeCatalog.stage_definition(bare, "only"), Stages.starts_checkpoint(bare), true)
	var reached: Dictionary = {}
	for floor: Dictionary in plan.floors: reached[floor.id] = floor.reached
	_check(reached == {"a": true, "b": true, "c": false} and plan.pairs.size() == 2 and plan.goal.id == "bell", "A layout no chapter registers gets its plan, its reach and its pairs with no world")

# --- The stage shots --------------------------------------------------------------

func _shots() -> void:
	var key := "turn-of-the-tide@1"
	var level := Registry.definition(key)
	var item: Dictionary = Stages.stages(key, level)[0]
	var shots := Shots.new(key, level, str(item.stage.id), item.checkpoint)
	var base: Dictionary = shots.snapshot()
	_check(not base.is_empty() and base.has("players"), "The engine opens a stage for the shots")
	var spot: Dictionary = shots.spots().filter(func(s: Dictionary) -> bool: return s.id == "tide")[0]
	var near: Dictionary = shots.beside({}, spot.entity, spot.slot)
	var state: Dictionary = shots.snapshot(near)
	var pip: Dictionary = state.players[spot.slot]
	_check(state.active_slot == spot.slot and pip.surface_id == spot.entity.surface_id and Vector2(pip.x, pip.z).distance_to(Vector2(spot.entity.position_cm[0], spot.entity.position_cm[1])) <= PairTags.NEAR_CM, "A pip beside a selector is live, on its floor, near enough to show its pair")
	var half: Dictionary = shots.snapshot(shots.worked(near, spot, "half"))
	var high: Dictionary = shots.snapshot(shots.worked(near, spot, "high"))
	_check(half.controls.tide == "half" and bool(half.bridges.get("stones-1", false)) and not bool(half.bridges.get("jetty-1", false)), "The engine opens the half crossing only when the tide is turned to half")
	_check(bool(high.bridges.get("jetty-1", false)) and not bool(high.bridges.get("stones-1", false)), "And the high crossing only at high")
	# A ball pad's crossing stays shut until the ball is there; a beam's until the light lands.
	var rolling := Shots.new("rolling-home@1", Registry.definition("rolling-home@1"), "weight-of-a-friend", Registry.initial_checkpoint("rolling-home@1"))
	_check(not bool(rolling.snapshot().bridges.get("shore-middle", true)), "A ball pad's crossing stays shut while the ball is away")
	_check(Shots.goal_slot({"first_player_slot": "p1"}) == "p0", "The goal belongs to the pip who plays second")

# --- Live reload ------------------------------------------------------------------

func _live() -> void:
	var key := "high-and-low@1"
	var data: Dictionary = preload("res://content/chapters/index.gd").data(key)
	var catalog := str(data.definition[0])
	var dressing := str(data.dressing)
	var folder := OS.get_temp_dir().path_join("ay-live-reload-test-%d" % OS.get_process_id())
	_check(folder.is_absolute_path() and not folder.begins_with(OS.get_user_data_dir()), "The edits live in the system's temp folder, outside user://: %s" % folder)
	for path: String in [catalog, dressing]:
		DirAccess.make_dir_recursive_absolute(folder.path_join(path.trim_prefix("res://").get_base_dir()))
		_write(folder.path_join(path.trim_prefix("res://")), FileAccess.get_file_as_string(path))
	var user_before := _listing(OS.get_user_data_dir())
	var bundled := Canonical.digest(Registry.definition(key))
	var screen := _Screen.new()
	root.add_child(screen)
	var world: Node3D = Registry.world_script(key).new()
	screen.world = world
	screen.add_child(world)
	world.set_process(false)
	await world.load_level(Registry.definition(key))
	var live: Node = LiveReload.new()
	live.root_dir = folder
	live.screen = func() -> Node: return screen
	live.set_process(false)
	root.add_child(live)
	_check(not await live.poll(), "Nothing redraws before a file changes")
	# Move the garden 40 cm along and add a lantern to the dressing.
	var source := FileAccess.get_file_as_string(folder.path_join(catalog.trim_prefix("res://")))
	var edited := source.replace('_island("garden",[736,-176,1088,176],0)', '_island("garden",[776,-176,1128,176],0)')
	_check(edited != source, "The test's edit applies to the catalog")
	await _later(folder.path_join(catalog.trim_prefix("res://")), edited)
	var redrew: bool = await live.poll()
	var garden: Array = world.chapter_definition.islands.filter(func(i: Dictionary) -> bool: return i.id == "garden")
	_check(redrew and not garden.is_empty() and garden[0].rect_cm[0] == 776, "An edited layout redraws the world at once")
	_check(Canonical.digest(Registry.definition(key)) == bundled, "The registry keeps the bundled definition")
	var dressing_text := FileAccess.get_file_as_string(folder.path_join(dressing.trim_prefix("res://")))
	var props := RegEx.create_from_string(r'"props"\s*:\s*\{')
	var found := props.search(dressing_text)
	var marked := dressing_text if found == null else dressing_text.substr(0, found.get_end()) + "\"__live\": [], " + dressing_text.substr(found.get_end())
	_check(marked != dressing_text, "The test's edit applies to the dressing")
	await _later(folder.path_join(dressing.trim_prefix("res://")), marked)
	_check(await live.poll() and Dressing.for_key(key).get("props", {}).has("__live"), "An edited dressing redraws the world with it")
	# A half-made catalog (here one with no stages) changes nothing. One that
	# does not compile takes the same path, but its parse error would read as
	# a script error to the suite runners, so it is not written here.
	await _later(folder.path_join(catalog.trim_prefix("res://")), "extends RefCounted\nstatic func definition(_key: String = \"\") -> Dictionary:\n\treturn {}\n")
	_check(not await live.poll() and world.chapter_definition.islands.filter(func(i: Dictionary) -> bool: return i.id == "garden")[0].rect_cm[0] == 776, "A catalog that gives no stages leaves the world as it was")
	var user_after := _listing(OS.get_user_data_dir())
	_check(user_after == user_before, "Live reload writes nothing under user://: %s" % [user_after.filter(func(entry: String) -> bool: return entry not in user_before)])
	_check(live.applied.size() == 2, "It applied the layout and the dressing: %s" % [live.applied])
	# Put the bundled dressing back for the rest of the run.
	Dressing.FILES = Dressing._files()
	Dressing.RESOLVED = Dressing._resolve_files()
	live.queue_free()
	screen.queue_free()
	await process_frame
	for path: String in [catalog, dressing]: DirAccess.remove_absolute(folder.path_join(path.trim_prefix("res://")))
	for path: String in [catalog, dressing]:
		var dir := folder.path_join(path.trim_prefix("res://").get_base_dir())
		while dir.length() > folder.length():
			DirAccess.remove_absolute(dir)
			dir = dir.get_base_dir()
	DirAccess.remove_absolute(folder)

## A screen holding a world, as the chapter screens do.
class _Screen extends Node:
	var world: Node3D

## Writes `text` so its modified time moves on (file times count in
## seconds), giving up after about five seconds.
func _later(path: String, text: String) -> void:
	var before := FileAccess.get_modified_time(path)
	for _try in range(20):
		await create_timer(0.25).timeout
		_write(path, text)
		if FileAccess.get_modified_time(path) != before: return
	_check(false, "The test could not move %s's modified time" % path)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

## Every file under `dir` with its modified time, leaving out the engine's own
## running log (logs/), which Godot writes whatever the game does.
static func _listing(dir: String, top: bool = true) -> Array:
	var found: Array = []
	if not DirAccess.dir_exists_absolute(dir): return found
	for name: String in DirAccess.get_files_at(dir): found.append("%s|%d" % [name, FileAccess.get_modified_time(dir.path_join(name))])
	for name: String in DirAccess.get_directories_at(dir):
		if top and name == "logs": continue
		found.append_array(_listing(dir.path_join(name), false).map(func(entry: String) -> String: return name + "/" + entry))
	return found

# --- Ships nowhere ----------------------------------------------------------------

func _ships_nowhere() -> void:
	var presets := ConfigFile.new()
	_check(presets.load("res://export_presets.cfg") == OK, "The export presets load")
	var count := 0
	for section: String in presets.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"): continue
		count += 1
		_check("tests/*" in str(presets.get_value(section, "exclude_filter", "")).split(","), "%s leaves tests/ (the level tools) out" % section)
	_check(count >= 2, "Every export preset was read (%d)" % count)
	var named: Array[String] = []
	_scan("res://", named)
	_check(named.is_empty(), "Nothing outside tests/ names the level tools: %s" % [named])

func _scan(dir: String, named: Array[String]) -> void:
	for name: String in DirAccess.get_directories_at(dir):
		if name.begins_with(".") or (dir == "res://" and name in ["tests", "addons", "android", "assets"]): continue
		_scan(dir.path_join(name), named)
	for name: String in DirAccess.get_files_at(dir):
		if not (name.ends_with(".gd") or name.ends_with(".tscn") or name.ends_with(".godot")): continue
		if "tests/level_tools" in FileAccess.get_file_as_string(dir.path_join(name)): named.append(dir.path_join(name))
