extends SceneTree
## Open controls (core/physical/open_controls.gd): the rules numbers, the
## versions pinned to them, and the rules themselves, played with real inputs
## where a real run can reach the spot:
## - 12 and 13 are their own rules (18 and 19 add open turns, which the three
##   open versions pin); every published chapter keeps its own, and
##   its controls keep their owners;
## - a pad holds for either pip, and either pip works a lever or selector;
## - in the second turn of open turns the friend's replay presses a control on
##   the tick it pressed it, in the one world, turning it on from whatever the
##   live pip left; on a tick both press, p0's lands first and p1's turns it on
##   from there; owner rules still copy the memory's controls every tick;
## - a live turn on a control the replay used replays exactly.
## (A live toggle that drowns the friend's replay: test_open_turns_memories.gd.)
## The open levels' turns are recorded again from the fixtures' inputs on
## today's rules (_first).
const Registry = preload("res://services/chapter_registry.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Cooperative = preload("res://core/cooperative/simulation.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const HOME := "long-way-home@3"
const HOME_PUBLISHED := "long-way-home@2"
const TIDE := "turn-of-the-tide@3"
const PATH := "the-path-you-leave"
## The memory's one press in Long Way Home's first stage: path-selector, home to friend.
const MEMORY_TURN_TICK := 91
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_numbers()
	_pads()
	_live_turns_a_memory_control()
	_memory_toggle_ticks()
	_same_tick()
	_owner_rules_unchanged()
	_levers()
	print("OPEN CONTROLS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _numbers() -> void:
	_check(OpenControls.OPEN_RULES == [12, 13, 18, 19, 20, 21] and OpenControls.TIDE_RULES == [10, 13, 19, 20] and OpenControls.OPEN_TURNS_RULES == [18, 19, 20, 21] and 11 not in OpenControls.OPEN_RULES, "Open controls are 12 and 13, 18 and 19 with open turns, 20 with the new pieces too, 21 with the shared ball; 11 stays the Lighthouse room's")
	_check(OpenControls.rules_for(9) == 12 and OpenControls.rules_for(7) == 12 and OpenControls.rules_for(10) == 13 and OpenControls.rules_for(19) == 19, "The open rules keep the earlier rules: tide (10) becomes 13, the rest 12, and open turns stay")
	_check(Registry.supported_rules(HOME) == [18] and Registry.supported_rules(TIDE) == [19] and Registry.supported_rules("conservatory@2") == [18], "Each new version plays only its open rules, with open turns")
	_check(Simulation._record_version({"simulation_version": 18.0}) == 18 and Simulation._record_version({"simulation_version": 19}) == 19, "A record names its open turns rules, JSON floats included")
	_check(Registry.supported_rules(HOME_PUBLISHED) == [9] and Registry.supported_rules("turn-of-the-tide@2") == [10] and Registry.supported_rules("conservatory@1") == [7, 8], "Published versions keep their rules")
	_check(not Simulation.rules_allowed(Registry.definition(HOME), 9) and not Simulation.rules_allowed(Registry.definition(HOME_PUBLISHED), 12) and not Cooperative.rules_allowed(Registry.definition("the-wishing-well@1"), 12), "No published chapter plays the open rules, and no open chapter plays the old ones")
	_check(Simulation._record_version({"simulation_version": 12.0}) == 12 and Simulation._record_version({"simulation_version": 13}) == 13 and Cooperative._record_version({"simulation_version": 12.0}) == 12, "A record names its open rules, JSON floats included")
	for key: String in [HOME, TIDE, "conservatory@2"]:
		var owned := 0
		for stage: Dictionary in Registry.definition(key).stages:
			for kind: String in OpenControls.KINDS:
				for item: Dictionary in stage.get(kind, []): owned += 1 if item.has("owner_slot") else 0
		_check(owned == 0, "%s: no control names an owner" % key)
	var published_owned := 0
	for stage: Dictionary in Registry.definition(HOME_PUBLISHED).stages:
		for item: Dictionary in stage.get("controls", []): published_owned += 1 if item.has("owner_slot") else 0
	_check(published_owned > 0, "Long Way Home@2's controls keep their owners")

## Seven: a pad with no owner holds for either pip under open controls.
func _pads() -> void:
	var pad := {"id": "seat", "position_cm": [0, 0], "surface_id": "floor", "height_cm": 0, "radius_cm": 30}
	var on := {"x": 0, "z": 0, "height": 0, "surface_id": "floor"}
	var off := {"x": 400, "z": 0, "height": 0, "surface_id": "floor"}
	_check(Seven.held({"p0": on, "p1": off}, pad, true) and Seven.held({"p0": off, "p1": on}, pad, true) and not Seven.held({"p0": off, "p1": off}, pad, true), "An open pad holds for either pip, and for no one off it")
	var owned := pad.duplicate()
	owned["owner_slot"] = "p1"
	_check(not Seven.held({"p0": on, "p1": off}, owned, false) and Seven.held({"p0": off, "p1": on}, owned, false), "Owner rules: only the owner holds its pad")
	var stage := {"pressure_pads": [pad], "source_policy": {"branches": [{"id": "near", "pad_id": "seat"}]}}
	_check(Seven.choice(stage, {"p0": off, "p1": on}, true).get("id") == "near" and Seven.predicate({"pad_id": "seat"}, stage, {"p0": on, "p1": off}, {}, {}, true), "Choices and gates read the open pad the same way")

## The second pip walks to the replay's selector and turns it back; the turn
## replays exactly, and the replay never takes it back.
func _live_turns_a_memory_control() -> void:
	var level := Registry.definition(HOME)
	var b := _receiver(HOME)
	if b == null: return
	var frames: Array = Simulation.expand_recording_inputs(_fixture("long-way-home-v3-%s-b.json" % PATH))
	# Its own press (return selector to garden) is frame 148.
	for tick in range(149): b.step(_input(frames[tick]))
	_check(str(b._mechanisms.controls["path-selector"]) == "friend", "The replay turned the path selector to friend")
	_walk(b, [64, 64])
	var action: Dictionary = b.context_action()
	_check(action.id == "selector" and action.target_id == "path-selector" and action.enabled, "The second pip may turn the replay's path selector (%s)" % str(action))
	b.step({})
	b.step({"interact": true})
	var turned_at := int(b.tick)
	for tick in range(60): b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "home", "The live turn holds: the replay does not take it back (turned at tick %d)" % turned_at)
	# Open turns: the first turn's part is not asked again at the end; the
	# stage ends only with both pips at the goal.
	_check(b._source_holds(), "On open turns undoing the replay's part does not by itself block the finish")
	_walk(b, [640, 224])
	if b.context_action().id == "ring": b.step({"interact": true})
	for tick in range(400): b.step({})
	_check(not b._objective and not b.complete, "At the window alone, with the replay waiting in the garden, the stage does not complete")
	var record: Dictionary = b.export_recording()
	var initial := Registry.initial_checkpoint(HOME)
	var first := _first(HOME, PATH, "long-way-home-v3-%s-a.json" % PATH)
	_check(Simulation.verify_recording(level, _json(record), _json(initial), _json(first)).valid, "The turn replays exactly (Retry and Preview see the same)")
	var again := _receiver(HOME)
	for frame: Dictionary in Simulation.expand_recording_inputs(record): again.step(_input(frame))
	_check(again.state_hash() == b.state_hash(), "Played again from its inputs it ends in the same state")

## A live value stays until the replay presses; its press turns the control
## on from the live value, in the one world. Owner rules copy it every tick.
func _memory_toggle_ticks() -> void:
	var b := _receiver(HOME)
	if b == null: return
	# As if the live pip had turned both: the replay's selector and its own.
	b._mechanisms.controls["return-selector"] = "garden"
	b._mechanisms.controls["path-selector"] = "friend"
	for tick in range(MEMORY_TURN_TICK): b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "friend" and str(b._mechanisms.controls["return-selector"]) == "garden", "Before the replay's press the live values stay, on its control and on the live pip's")
	b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "home" and b._events.has("selector:path-selector"), "The replay's press turns it on from the live value (tick %d)" % MEMORY_TURN_TICK)
	for tick in range(30): b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "home", "After it, the value stays")
	var owner := _receiver(HOME_PUBLISHED)
	if owner == null: return
	owner._mechanisms.controls["path-selector"] = "friend"
	owner.step({})
	_check(str(owner._mechanisms.controls["path-selector"]) == "home", "Owner rules: the memory's control is copied every tick")

## On the tick the replay (p0) turns its selector, the live pip (p1) presses
## it too: p0 first (home to friend), then p1 (friend to home).
func _same_tick() -> void:
	var b := _receiver(HOME)
	if b == null: return
	for tick in range(MEMORY_TURN_TICK - 1): b.step({})
	var selector := _entity(b.stage.controls, "path-selector")
	b._players.p1 = {"x": int(selector.position_cm[0]), "z": int(selector.position_cm[1]), "height": int(selector.height_cm), "surface_id": str(selector.surface_id)}
	b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "home", "The tick before, nothing has turned")
	b.step({"interact": true})
	_check(str(b._mechanisms.controls["path-selector"]) == "home" and b._events.count("selector:path-selector") == 2, "Both on one tick: p0's press lands, then p1's turns it on")

## Owner rules: the second pip still cannot work the memory's selector.
func _owner_rules_unchanged() -> void:
	var b := _receiver(HOME_PUBLISHED)
	if b == null: return
	var selector := _entity(b.stage.controls, "path-selector")
	b._players.p1 = {"x": int(selector.position_cm[0]), "z": int(selector.position_cm[1]), "height": int(selector.height_cm), "surface_id": str(selector.surface_id)}
	_check(b.context_action().id != "selector", "Owner rules: the memory's selector is not the second pip's to turn")

## Levers follow the same rule as selectors (runtime.gd): in Set the Tide the
## replay pulls a lever; a live value held opposite stays until that tick, and
## the replay's pull turns it from there; the live pip may pull it too.
func _levers() -> void:
	var level := Registry.definition(TIDE)
	var first := _first(TIDE, "set-the-tide", "turn-of-the-tide-v3-set-the-tide-a.json")
	var idle := Simulation.new()
	idle.reset(level, "set-the-tide", Registry.initial_checkpoint(TIDE), first, "b")
	var pulled_at := -1
	var lever_id := ""
	var before: Dictionary = idle._mechanisms.levers.duplicate()
	while not idle.finished and int(idle.tick) < int(first.duration_ticks):
		idle.step({})
		if idle._events.has("lever"):
			pulled_at = int(idle.tick) - 1
			for id: String in idle._mechanisms.levers:
				if bool(idle._mechanisms.levers[id]) != bool(before.get(id, false)): lever_id = id
			break
		before = idle._mechanisms.levers.duplicate()
	_check(pulled_at >= 0 and not lever_id.is_empty(), "The replay pulls a lever in Set the Tide")
	if pulled_at < 0 or lever_id.is_empty(): return
	var pulled: bool = bool(idle._mechanisms.levers[lever_id])
	var b := Simulation.new()
	b.reset(level, "set-the-tide", Registry.initial_checkpoint(TIDE), first, "b")
	b._mechanisms.levers[lever_id] = pulled
	for tick in range(pulled_at): b.step({})
	_check(bool(b._mechanisms.levers[lever_id]) == pulled, "Before the replay's pull the live lever stays (%s)" % lever_id)
	b.step({})
	_check(bool(b._mechanisms.levers[lever_id]) == (not pulled), "The replay's pull turns it from the live value (tick %d)" % pulled_at)
	var lever := _entity(b.stage.levers, lever_id)
	b._players.p1 = {"x": int(lever.position_cm[0]), "z": int(lever.position_cm[1]), "height": int(lever.get("height_cm", b._players.p1.height)), "surface_id": str(lever.surface_id)}
	var action: Dictionary = b.context_action()
	_check(action.id == "lever" and action.target_id == lever_id, "The live pip may pull the replay's lever (%s)" % str(action))

func _receiver(key: String) -> Simulation:
	var level := Registry.definition(key)
	var stem := "long-way-home-v3" if key == HOME else "long-way-home-v2"
	var b := Simulation.new()
	var name := "%s-%s-a.json" % [stem, PATH]
	var first := _first(key, PATH, name) if key == HOME else _fixture(name)
	var ok := b.reset(level, PATH, Registry.initial_checkpoint(key), first, "b")
	_check(ok, "%s: the second turn starts (%s)" % [key, b.error])
	return b if ok else null

## Walks the live pip to `to` (cm), one axis after the other.
static func _walk(sim: Simulation, to: Array) -> void:
	for axis in range(2):
		var key := "x" if axis == 0 else "z"
		for tick in range(300):
			var gap := int(to[axis]) - int(sim._players[sim.active_slot][key])
			if absi(gap) <= 1 or sim.finished: break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + key] = clampf(float(gap) / 8.0, -1.0, 1.0)
			sim.step(input)

## An open level's first turn recorded again from fixture `name`'s inputs on
## today's rules, once per run.
var _firsts: Dictionary = {}
func _first(key: String, stage_id: String, name: String) -> Dictionary:
	if not _firsts.has(name):
		var one := Simulation.new()
		one.reset(Registry.definition(key), stage_id, Registry.initial_checkpoint(key), {}, "a")
		for frame: Dictionary in Simulation.expand_recording_inputs(_fixture(name)): one.step(frame)
		_firsts[name] = _json(one.export_recording())
	return _firsts[name]

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/" + name))

static func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

static func _input(frame: Dictionary) -> Dictionary:
	return frame

static func _entity(items: Array, id: String) -> Dictionary:
	for item: Dictionary in items:
		if str(item.id) == id: return item
	return {}

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
		print("FAIL: " + label)
