extends SceneTree
## Open controls (core/physical/open_controls.gd): the rules numbers, the
## versions pinned to them, and the rules themselves, played with real inputs
## where a real run can reach the spot:
## - 12 and 13 are their own rules; every published chapter keeps its own, and
##   its controls keep their owners;
## - a pad holds for either pip, and either pip works a lever or selector;
## - in the second turn a control takes the memory's value only on the tick the
##   memory turned it, and keeps the live pip's otherwise; on a tick both turn
##   it, the memory's lands first and the live press turns it on from there;
##   owner rules still copy the memory's controls every tick;
## - a live turn on a control the memory used replays exactly;
## - the drowning path is the tide rules' own: a live toggle that shuts the
##   crossing under the memory ends the turn with DROWNED_FRIEND.
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
	_live_toggle_drowns_memory()
	print("OPEN CONTROLS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _numbers() -> void:
	_check(OpenControls.OPEN_RULES == [12, 13] and OpenControls.TIDE_RULES == [10, 13] and 11 not in OpenControls.OPEN_RULES, "Open controls are 12 and 13; 11 stays the Lighthouse room's")
	_check(OpenControls.rules_for(9) == 12 and OpenControls.rules_for(7) == 12 and OpenControls.rules_for(10) == 13, "The open rules keep the earlier rules: tide (10) becomes 13, the rest 12")
	_check(Registry.supported_rules(HOME) == [12] and Registry.supported_rules(TIDE) == [13] and Registry.supported_rules("conservatory@2") == [12], "Each new version plays only its open rules")
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

## The second pip walks to the memory's selector and turns it back; the turn
## replays exactly, and the memory never takes it back.
func _live_turns_a_memory_control() -> void:
	var level := Registry.definition(HOME)
	var b := _receiver(HOME)
	if b == null: return
	var frames: Array = Simulation.expand_recording_inputs(_fixture("long-way-home-v3-%s-b.json" % PATH))
	for tick in range(148): b.step(_input(frames[tick]))
	_check(str(b._mechanisms.controls["path-selector"]) == "friend", "The memory turned the path selector to friend")
	_walk(b, [64, 64])
	var action: Dictionary = b.context_action()
	_check(action.id == "selector" and action.target_id == "path-selector" and action.enabled, "The second pip may turn the memory's path selector (%s)" % str(action))
	b.step({})
	b.step({"interact": true})
	var turned_at := int(b.tick)
	for tick in range(60): b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "home", "The live turn holds: the memory does not take it back (turned at tick %d)" % turned_at)
	var record: Dictionary = b.export_recording()
	var initial := Registry.initial_checkpoint(HOME)
	var first := _fixture("long-way-home-v3-%s-a.json" % PATH)
	_check(Simulation.verify_recording(level, _json(record), _json(initial), _json(first)).valid, "The turn replays exactly (Retry and Preview see the same)")
	var again := _receiver(HOME)
	for frame: Dictionary in Simulation.expand_recording_inputs(record): again.step(_input(frame))
	_check(again.state_hash() == b.state_hash(), "Played again from its inputs it ends in the same state")

## A live value the memory did not touch this tick stays; on the memory's own
## turn the memory's value lands. Owner rules copy it every tick.
func _memory_toggle_ticks() -> void:
	var b := _receiver(HOME)
	if b == null: return
	# As if the live pip had turned both: the memory's selector and its own.
	b._mechanisms.controls["return-selector"] = "garden"
	b._mechanisms.controls["path-selector"] = "friend"
	for tick in range(MEMORY_TURN_TICK): b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "friend" and str(b._mechanisms.controls["return-selector"]) == "garden", "Before the memory's turn the live values stay, on its control and on the live pip's")
	b._mechanisms.controls["path-selector"] = "home"
	b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "friend" and b._source_toggles.controls.has("path-selector"), "On the memory's turn its value lands (tick %d)" % MEMORY_TURN_TICK)
	b._mechanisms.controls["path-selector"] = "home"
	for tick in range(30): b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "home", "After it, the live value stays again")
	var owner := _receiver(HOME_PUBLISHED)
	if owner == null: return
	owner._mechanisms.controls["path-selector"] = "friend"
	owner.step({})
	_check(str(owner._mechanisms.controls["path-selector"]) == "home", "Owner rules: the memory's control is copied every tick")

## On the tick the memory turns its selector, the live pip presses it too:
## memory first (home to friend), then the live press (friend to home).
func _same_tick() -> void:
	var b := _receiver(HOME)
	if b == null: return
	for tick in range(MEMORY_TURN_TICK - 1): b.step({})
	var selector := _entity(b.stage.controls, "path-selector")
	b._players.p1 = {"x": int(selector.position_cm[0]), "z": int(selector.position_cm[1]), "height": int(selector.height_cm), "surface_id": str(selector.surface_id)}
	b.step({})
	_check(str(b._mechanisms.controls["path-selector"]) == "home", "The tick before, nothing has turned")
	b.step({"interact": true})
	_check(str(b._mechanisms.controls["path-selector"]) == "home" and b._source_toggles.controls.has("path-selector") and b._events.has("selector:path-selector"), "Both on one tick: the memory's turn lands, then the live press turns it on")

## Owner rules: the second pip still cannot work the memory's selector.
func _owner_rules_unchanged() -> void:
	var b := _receiver(HOME_PUBLISHED)
	if b == null: return
	var selector := _entity(b.stage.controls, "path-selector")
	b._players.p1 = {"x": int(selector.position_cm[0]), "z": int(selector.position_cm[1]), "height": int(selector.height_cm), "surface_id": str(selector.surface_id)}
	_check(b.context_action().id != "selector", "Owner rules: the memory's selector is not the second pip's to turn")

## Slack Water on the open tide rules: the memory ends its turn on the gate
## post, which holds while the basin stands at low. The live pip turns the
## basin, the memory's own wheel under owner rules: the post closes, and 45
## ticks later the memory drowns and the turn ends.
func _live_toggle_drowns_memory() -> void:
	var level := Registry.definition(TIDE)
	var checkpoint := _fixture("turn-of-the-tide-v3-set-the-tide-checkpoint.json")
	var first := _fixture("turn-of-the-tide-v3-slack-water-a.json")
	var b := Simulation.new()
	_check(b.reset(level, "slack-water", checkpoint, first, "b"), "Slack Water's second turn starts beside the memory")
	# The live pip plays its own recorded part until the memory's turn has ended.
	var frames: Array = Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-slack-water-b.json"))
	while not b.finished and int(b.tick) < mini(int(first.duration_ticks), frames.size()): b.step(_input(frames[b.tick]))
	_check(str(b._players.p1.surface_id) == "gate-post" and str(b._mechanisms.controls.basin) == "low", "The memory stands on the gate post at a low basin")
	var basin := _entity(b.stage.controls, "basin")
	b._players.p0 = {"x": int(basin.position_cm[0]), "z": int(basin.position_cm[1]), "height": int(basin.height_cm), "surface_id": str(basin.surface_id)}
	var action: Dictionary = b.context_action()
	_check(action.id == "selector" and action.target_id == "basin", "The live pip may turn the memory's basin wheel (%s)" % str(action))
	b.step({"interact": true})
	var turned := int(b.tick) - 1
	while not b.finished: b.step({})
	var drowned: Dictionary = b.snapshot().drowned
	_check(drowned.get("slot") == "p1" and drowned.get("route") == "gate-post" and int(drowned.tick) == turned + int(level.closing_ticks), "The gate post shuts under the memory and it drowns (%s, turned at %d)" % [str(drowned), turned])
	_check(b.commit_reason() == Simulation.DROWNED_FRIEND and not b.can_commit() and not b.keeps_draft(), "The turn ends with DROWNED_FRIEND, cannot be saved and keeps no draft")

func _receiver(key: String) -> Simulation:
	var level := Registry.definition(key)
	var stem := "long-way-home-v3" if key == HOME else "long-way-home-v2"
	var b := Simulation.new()
	var ok := b.reset(level, PATH, Registry.initial_checkpoint(key), _fixture("%s-%s-a.json" % [stem, PATH]), "b")
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
