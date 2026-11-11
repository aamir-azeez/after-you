extends SceneTree
## Puzzle building blocks (core/blocks/stage_blocks.gd). Published stages are
## written again here with blocks in place of their pads, levers, selectors,
## gates, drops and goals, and each expanded level must be byte for byte the
## published definition fixture, hash to the published definition hash, and
## verify the published final checkpoint through the real engine. Between them
## the rewrites use every block in both rules families. Nothing published
## changes: the catalogs never see these rewrites.
const Blocks = preload("res://core/blocks/stage_blocks.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Cooperative = preload("res://core/cooperative/stage_catalog.gd")
const CooperativeSim = preload("res://core/cooperative/simulation.gd")
const Journey = preload("res://core/journey/stage_catalog.gd")
const JourneySim = preload("res://core/journey/simulation.gd")
const FIXTURES := "res://tests/fixtures/"
## Fields the blocks write; a rewrite drops them from the published stage first.
const MECHANICS := ["pressure_pads", "levers", "controls", "ball_pads", "gates", "goal", "goal_policy"]

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	_prove("high-and-low", Cooperative.definition("high-and-low@1"), _high_and_low(), "cooperative", CooperativeSim)
	_prove("a-house-for-two", Cooperative.definition("a-house-for-two@1"), _house(), "cooperative", CooperativeSim)
	_prove("turn-of-the-tide", Journey.definition("turn-of-the-tide@1"), _tide(), "journey", JourneySim)
	_prove("long-way-home", Journey.definition("long-way-home@1"), _long_way_home(), "journey", JourneySim)
	_prove("long-way-home-v2", Journey.definition("long-way-home@2"), _long_way_home_v2(), "journey", JourneySim)
	_prove("conservatory", Journey.definition("conservatory@1"), _conservatory(), "journey", JourneySim)
	_check_coverage()
	_check_rules()
	print("STAGE BLOCKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _prove(name: String, published: Dictionary, source: Dictionary, folder: String, engine: Script) -> void:
	_check(Blocks.problems(source).is_empty(), "%s with blocks has no problems: %s" % [name, Blocks.problems(source)])
	var built := Blocks.expand(source)
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "%s/%s-definition.json" % [folder, name]))
	_check(fixture is Dictionary and Canonical.same(fixture, published), "%s fixture is the published definition" % name)
	_check(JSON.stringify(Canonical.normalized(built)) == JSON.stringify(Canonical.normalized(fixture)), "%s written with blocks expands to the published definition byte for byte" % name)
	var initial: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "%s/%s-initial-checkpoint.json" % [folder, name]))
	_check(initial is Dictionary and Canonical.digest(built) == str(initial.get("definition_hash", "")), "%s written with blocks hashes to the published definition hash" % name)
	var final: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "%s/%s-final-checkpoint.json" % [folder, name]))
	_check(final is Dictionary and engine.verify_checkpoint(built, final).valid, "%s written with blocks plays the published turns to the published end" % name)
	_check(not JSON.stringify(built).contains("\"blocks\""), "%s keeps no block list after expanding" % name)
	_check(Canonical.same(Blocks.expand(source), built) and Canonical.same(source, _copy(source)), "%s expands the same every time and leaves its source alone" % name)

## Every block is used by some rewrite in every family that plays it.
func _check_coverage() -> void:
	var used := {"cooperative": {}, "journey": {}}
	for source: Dictionary in [_high_and_low(), _house(), _tide(), _long_way_home(), _long_way_home_v2(), _conservatory()]:
		for stage: Dictionary in source.stages:
			for block: Dictionary in stage.get("blocks", []): used[Blocks.family_of(source)][str(block.block)] = true
	for family: String in Blocks.FAMILY_BLOCKS:
		for block: String in Blocks.FAMILY_BLOCKS[family]:
			if family == "cooperative" and block in ["pad", "lever", "open_route"]: continue
			_check(used[family].has(block), "A published rewrite proves the %s block in the %s rules" % [block, family])
	# The cooperative pad, lever and open route have no published stage to match: their form, checked by hand.
	var made := Blocks.expand({"schema_version": 6, "bridges": [{"id": "r"}], "stages": [{"id": "s", "blocks": [
		{"block": "pad", "id": "p", "at": [0, 0], "surface": "a", "owner": "p0"},
		{"block": "lever", "id": "l", "at": [10, 0], "surface": "a", "owner": "p1"},
		{"block": "open_route", "routes": ["r"]}]}]})
	var stage: Dictionary = made.stages[0]
	_check(stage.pressure_pads == [{"id": "p", "position_cm": [0, 0], "surface_id": "a", "radius_cm": 32, "owner_slot": "p0"}], "A cooperative pad is written as the cooperative catalogs write one")
	_check(stage.levers == [{"id": "l", "position_cm": [10, 0], "surface_id": "a", "radius_cm": 28, "owner_slot": "p1"}], "A cooperative lever is written as the cooperative catalogs write one")
	_check(stage.gates == [{"route_id": "r", "pad_id": "", "lever_id": "", "ball_pad_id": ""}], "A cooperative open route is a gate that waits on nothing")

func _check_rules() -> void:
	var wrong := {"schema_version": 6, "stages": [{"id": "s", "blocks": [{"block": "selector_gate", "selector": "x", "routes": {}}, {"block": "hold_door", "routes": ["r"]}, {"block": "teleport"}]}]}
	_check(Blocks.problems(wrong).size() == 3, "A block the rules cannot play, one missing a field and an unknown block are each named")
	_check(Blocks.expand(wrong).stages[0].keys() == ["id"], "Blocks with problems are left out")
	var dangling := {"schema_version": 7, "bridges": [{"id": "r"}], "stages": [{"id": "s", "blocks": [{"block": "relay_lever", "lever": "nowhere", "routes": ["r", "gone"]}]}]}
	var found := Blocks.problems(dangling)
	_check(found.size() == 3 and found.any(func(line: String) -> bool: return line.contains("nowhere")) and found.any(func(line: String) -> bool: return line.contains("gone")), "A gate on a missing route or wired to nothing placed is named: %s" % [found])
	var broken := {"schema_version": 7, "bridges": [{"id": "r"}], "stages": [{"id": "s", "blocks": [
		{"block": "raw", "source_policy": {"kind": "ring"}},
		{"block": "selector_gate", "selector": {"id": "x", "at": [0, 0], "surface": "a", "owner": "p0"}, "routes": ["r"]},
		{"block": "match_selectors", "selector": "x", "matches": {"id": "y", "at": [0, 0], "surface": "a", "owner": "p0", "values": ["a"]}, "values": ["a"], "routes": ["r"]},
		{"block": "one_way_drop", "id": "d", "rect": [0, 0, 1, 1], "from": "a", "to": "b", "lip": {"id": "l"}},
		{"block": "hold_door", "pad": "p", "routes": ["r"], "finish": 15}]}]}
	var named := Blocks.problems(broken)
	for part: String in ["raw's source_policy", "selector_gate's routes", "selector needs values", "matches needs initial", "lip needs rect", "finish is the cooperative"]:
		_check(named.any(func(line: String) -> bool: return line.contains(part)), "A malformed block is named, not crashed on (%s): %s" % [part, named])
	_check(Blocks.expand(broken).stages[0].keys() == ["id"], "Malformed blocks are all left out")
	var twice := {"schema_version": 7, "bridges": [{"id": "r"}], "stages": [{"id": "s", "blocks": [
		{"block": "pad", "id": "p", "at": [0, 0], "surface": "a", "owner": "p0"}, {"block": "hold_door", "pad": {"id": "p", "at": [5, 0], "surface": "a", "owner": "p0"}, "routes": ["r"]}]}]}
	_check(Blocks.problems(twice).any(func(line: String) -> bool: return line.contains("placed twice")), "One id placed twice is named")
	_check(Blocks.family_of({"schema_version": 4}).is_empty() and not Blocks.problems({"schema_version": 4, "stages": []}).is_empty(), "Blocks refuse rules they do not know")

## The published stage without what the blocks write, with the blocks added.
func _rewrite(stage: Dictionary, blocks: Array, also_drop: Array = []) -> Dictionary:
	var result: Dictionary = stage.duplicate(true)
	for field: String in MECHANICS + also_drop: result.erase(field)
	result["blocks"] = blocks
	return result

func _copy(value: Dictionary) -> Dictionary:
	return value.duplicate(true)

func _high_and_low() -> Dictionary:
	var level := Cooperative.definition("high-and-low@1")
	level.erase("drops")
	level.stages[0] = _rewrite(level.stages[0], [
		{"block": "hold_door", "pad": {"id": "lower-switch", "at": [-448, -128], "surface": "shore", "owner": "p0"},
			"lever": {"id": "shore-lever", "at": [-544, 112], "surface": "shore", "owner": "p0"}, "routes": ["blue-stair"], "finish": 15},
		{"block": "ring_bell", "id": "loft-bell", "at": [160, -128], "surface": "loft", "owner": "p1"}], ["source_policy"])
	level.stages[1] = _rewrite(level.stages[1], [
		{"block": "hold_door", "pad": {"id": "lower-ledge-switch", "at": [448, 48], "surface": "lower-ledge", "owner": "p1"},
			"lever": {"id": "loft-lever", "at": [240, -128], "surface": "loft", "owner": "p1"}, "routes": ["lower-causeway", "red-passage"], "finish": 15},
		{"block": "one_way_drop", "id": "loft-hole", "rect": [216, 24, 264, 72], "from": "loft", "to": "lower-ledge", "lever": "loft-lever"},
		{"block": "ring_bell", "id": "garden-bell", "at": [912, 0], "surface": "garden", "owner": "p0"}], ["source_policy"])
	level.stages[1].blocks.push_front({"block": "raw", "ball_pads": []})
	level.stages[0].blocks.push_front({"block": "raw", "ball_pads": []})
	return level

func _house() -> Dictionary:
	var level := Cooperative.definition("a-house-for-two@1")
	level.erase("drops")
	level.stages[0] = _rewrite(level.stages[0], [
		{"block": "raw", "pressure_pads": []},
		{"block": "weight_pad", "id": "entry-weight", "at": [-288, 112], "surface": "foyer", "ball": "house-ball", "routes": ["workshop-entry"]},
		{"block": "relay_lever", "lever": {"id": "workshop-lever", "at": [32, 144], "surface": "workshop", "owner": "p0"}, "routes": ["workshop-entry", "workshop-return"]},
		{"block": "weight_pad", "id": "stair-weight", "at": [-352, -112], "surface": "foyer", "ball": "house-ball", "routes": ["loft-stairs"], "lever": "workshop-lever"},
		{"block": "ring_bell", "id": "loft-bell", "at": [576, -128], "surface": "loft", "owner": "p1"}])
	level.stages[1] = _rewrite(level.stages[1], [
		{"block": "raw", "pressure_pads": []},
		{"block": "relay_lever", "lever": {"id": "loft-lever", "at": [560, 80], "surface": "loft", "owner": "p1"}, "routes": ["lower-hall-passage"]},
		{"block": "weight_pad", "id": "sunroom-weight", "at": [592, 0], "surface": "lower-hall", "ball": "house-ball", "routes": ["sunroom-entry"]},
		{"block": "one_way_drop", "id": "loft-hatch", "rect": [464, 64, 528, 128], "from": "loft", "to": "lower-hall", "lever": "loft-lever"},
		{"block": "ring_bell", "id": "sunroom-bell", "at": [960, 112], "surface": "sunroom", "owner": "p0"}])
	return level

func _tide() -> Dictionary:
	var level := Journey.definition("turn-of-the-tide@1")
	level.erase("drops")
	level.erase("access_zones")
	var gates: Array = level.stages[0].gates
	level.stages[0] = _rewrite(level.stages[0], [
		{"block": "raw", "ball_pads": []},
		{"block": "selector", "id": "tide", "at": [192, -352], "surface": "m-quay", "height": 96, "owner": "p0", "values": ["low", "half", "high"], "initial": "low"},
		{"block": "selector", "id": "winch", "at": [624, -448], "surface": "e-quay", "height": 96, "owner": "p0", "values": ["stowed", "slip"], "initial": "stowed"},
		{"block": "selector", "id": "lock", "at": [880, 48], "surface": "lock-chamber", "height": 48, "owner": "p1", "values": ["west", "east"], "initial": "west"},
		{"block": "lever", "id": "sluice", "at": [704, 96], "surface": "e-terrace-west", "height": 48, "owner": "p0"},
		{"block": "lever", "id": "line", "at": [1088, -448], "surface": "e-quay", "height": 96, "owner": "p0"},
		{"block": "lever", "id": "gangway", "at": [1104, -352], "surface": "e-quay", "height": 96, "owner": "p1"},
		{"block": "pad", "id": "wheel-step-pad", "at": [192, -512], "surface": "wheel-step", "height": 96, "owner": "p0", "radius": 20},
		{"block": "pad", "id": "quay-step-pad", "at": [64, -512], "surface": "quay-step", "height": 96, "owner": "p0", "radius": 20},
		{"block": "pad", "id": "bollard-pad", "at": [320, -512], "surface": "bollard-step", "height": 96, "owner": "p0", "radius": 20},
		{"block": "open_route", "routes": ["w-steps-low", "w-steps-high", "mill-steps", "mill-ladder", "east-steps", "boathouse-steps", "rock-steps-low", "rock-steps-high"]},
		{"block": "selector_gate", "selector": "tide", "routes": {"sand-1": "low", "stones-1": "half", "jetty-1": "high", "stones-2": "half", "jetty-2": "high"}},
		{"block": "raw", "gates": gates.slice(13, 16)},
		{"block": "selector_gate", "selector": "lock", "routes": {"lock-west": "west", "lock-east": "east"}},
		{"block": "raw", "gates": gates.slice(18)},
		{"block": "one_way_drop", "id": "spout", "rect": [600, 268, 648, 308], "from": "aq-span", "to": "e-beach", "lever": "sluice",
			"lip": {"id": "spout-lip", "rect": [552, 256, 672, 320], "owner": "p1"}},
		{"block": "ring_bell", "id": "harbour-bell", "at": [1440, 0], "surface": "r-terrace", "height": 48, "owner": "p1"}])
	return level

## Long Way Home's homecoming: windows that hold crossings open, one only
## with the porch shutter down too. Its first stage's drop rides along.
func _long_way_home() -> Dictionary:
	var level := Journey.definition("long-way-home@1")
	level.erase("drops")
	level.stages[1] = _rewrite(level.stages[1], [
		{"block": "raw", "controls": [], "ball_pads": []},
		{"block": "open_route", "routes": ["service-up", "service-down"]},
		{"block": "hold_door", "pad": {"id": "near-window", "at": [1200, 32], "surface": "home-room", "owner": "p1", "radius": 36}, "routes": ["near-crossing"]},
		{"block": "hold_door", "pad": "near-window", "lever": {"id": "porch-shutter", "at": [960, 224], "surface": "near-porch", "owner": "p0"}, "routes": ["porch-door"]},
		{"block": "hold_door", "pad": {"id": "garden-window", "at": [1200, 144], "surface": "home-room", "owner": "p1", "radius": 36}, "routes": ["garden-arch", "garden-door"]},
		{"block": "one_way_drop", "id": "garden-descent", "rect": [536, -264, 584, -216], "from": "upper-lane", "to": "drop-landing"},
		{"block": "ring_bell", "id": "second-window", "at": [1408, 96], "surface": "home-room", "owner": "p0"}])
	return level

## Version 2's homecoming: a lamp that opens the arch at either colour and a
## gate that opens the door only at the lamp's colour.
func _long_way_home_v2() -> Dictionary:
	var level := Journey.definition("long-way-home@2")
	level.erase("drops")
	var stage: Dictionary = level.stages[1]
	var code := {"any": [{"all": [{"control_id": "hall-lamp", "value": "rose"}, {"control_id": "walk-gate", "value": "rose"}]}, {"all": [{"control_id": "hall-lamp", "value": "moss"}, {"control_id": "walk-gate", "value": "moss"}]}]}
	level.stages[1] = _rewrite(stage, [
		{"block": "selector", "id": "hall-lamp", "at": [944, -96], "surface": "service-landing", "height": 96, "owner": "p1", "values": ["off", "rose", "moss"], "initial": "off"},
		{"block": "selector", "id": "porch-shutter", "at": [960, 224], "surface": "near-porch", "owner": "p0", "values": ["up", "down"], "initial": "up"},
		{"block": "selector", "id": "walk-gate", "at": [800, 448], "surface": "garden-walk", "owner": "p0", "values": ["shut", "rose", "moss"], "initial": "shut"},
		{"block": "pad", "id": "near-window", "at": [1200, 32], "surface": "home-room", "owner": "p1", "radius": 36},
		{"block": "pad", "id": "garden-window", "at": [1200, 144], "surface": "home-room", "owner": "p1", "radius": 36},
		{"block": "raw", "levers": [], "ball_pads": []},
		{"block": "open_route", "routes": ["service-up", "service-down"]},
		{"block": "hold_door", "pad": "near-window", "routes": ["near-crossing"]},
		{"block": "raw", "gates": [stage.gates[3]]},
		{"block": "selector_gate", "selector": "hall-lamp", "routes": {"garden-arch": ["rose", "moss"]}},
		{"block": "match_selectors", "selector": "hall-lamp", "matches": "walk-gate", "values": ["rose", "moss"], "routes": ["garden-door"]},
		{"block": "one_way_drop", "id": "garden-descent", "rect": [536, -264, 584, -216], "from": "upper-lane", "to": "drop-landing"},
		{"block": "ring_bell", "id": "second-window", "at": [1408, 96], "surface": "home-room", "owner": "p0",
			"when": {"any": [{"all": [{"pad_id": "near-window"}, {"control_id": "porch-shutter", "value": "up"}]}, code]}}])
	return level

## Conservatory's return: the shutter lever opens both ways back.
func _conservatory() -> Dictionary:
	var level := Journey.definition("conservatory@1")
	level.erase("drops")
	var stage: Dictionary = level.stages[1]
	level.stages[1] = _rewrite(stage, [
		{"block": "raw", "controls": stage.controls, "pressure_pads": [], "ball_pads": []},
		{"block": "raw", "gates": [stage.gates[0]]},
		{"block": "relay_lever", "lever": {"id": "return-shutter", "at": [352, 64], "surface": "lower-room", "owner": "p0"}, "routes": ["court-return", "room-return"]},
		{"block": "one_way_drop", "id": "gallery-hatch", "rect": [392, -264, 440, -216], "from": "gallery", "to": "lower-room"},
		{"block": "ring_bell", "id": "two-lights", "at": [752, 64], "surface": "garden", "owner": "p0", "when": stage.goal_policy.when}])
	return level
