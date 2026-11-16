extends RefCounted
## The Falls: four stages on the new pieces (rules 16, core/physical/pieces_rules.gd:
## the tide rules with open controls and open turns, plus carried items,
## currents, platforms, sinking stones, one way stairs and "not" gates),
## written with the stage blocks (core/blocks/stage_blocks.gd). The designs are
## claude-20261011\pipsport-concepts\solver\levels.py (falls_1 to falls_4):
## Teal is p1, Gold is p0, and Gold (the host's pip) plays first in stage 1.
## A journey is one map: each stage starts with both pips where the stage
## before ended (its goal), so each stage opens one stair from that goal down
## into its own start (stage 2 starts both on the bank, 3 on the west ledge, 4
## on the lookout). Heights in cm; stage 4 is all at 96 cm.
##   1 foot-of-the-falls: the mill wheel sets the pool (LOW shows the stepping
##     stones, HIGH winds the bucket up to the ledge); the footbridge from the
##     mill is down while its pan on the island is weighed (a pip or the
##     pipsport); the island ladder needs both hands.
##   2 the-old-mill: the water gate board turns the big wheel (ride it up to
##     the loft, both hands), floods the mill steps and dries the old
##     riverbed; the sack lift carries the hook up while the gate board or the
##     loft's winding board is held; the attic ladder is bolted from the loft.
##   3 behind-the-falls: the rope bridge is tight while a crank board at either
##     end is held, and the west one winds the basket line across; the water
##     gate lever on the east top dries the path behind the falls.
##   4 the-last-stones: the stream wheel shows the floating log (HIGH), the
##     middle steps (MID) or the sinking stones (LOW); the lookout crank board
##     keeps the rope bridge tight; the leap needs both hands; the far gate is
##     held by its board outside or by the bar pulled inside.
## No player words here: the title and hints are the descriptor's copy and
## stage_copy, so changing them never changes the definition hash.
## The turn limits are development ones (120 s every turn, what the 1 MiB
## solo save fits today) until play sets them (scripts/chapter_turn_limits.py).

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take: 10, or 20 on a hard stage (the owner's call).
const CAPS := {"foot-of-the-falls": 10, "the-old-mill": 10, "behind-the-falls": 10, "the-last-stones": 10}
const CARRIED := {"item_id": "pipsport", "carried": true}

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "the-falls", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks": 3600, "b_ticks": 3600},
		"starts": {"p0": {"position_cm": [150, 50], "height_cm": 48, "surface_id": "mill"}, "p1": {"position_cm": [150, 450], "height_cm": 0, "surface_id": "beach"}},
		"props": [], "drops": [],
		"items": [{"id": "pipsport", "at": "post"}],
		"item_spots": [
			_spot("post", "isle", [440, 560], 0), _spot("pan", "isle", [760, 560], 0), _spot("bucket", "isle", [760, 340], 0), _spot("bucket-top", "ledge", [740, -40], 48),
			_spot("hook", "yard", [1340, -140], 48), _spot("sack-top", "loft", [1340, -560], 96),
			_spot("basket", "wtop", [2440, -1260], 144), _spot("basket-end", "etop", [2960, -1260], 144)],
		"islands": [
			_island("mill", [0, -100, 300, 200], 48), _island("ledge", [400, -100, 800, 200], 48), _island("isle", [400, 300, 800, 600], 0), _island("beach", [0, 300, 300, 600], 0),
			_island("bank", [900, -300, 1200, 300], 0), _island("yard", [1300, -400, 1600, -100], 48), _island("deck", [1700, -400, 2000, 100], 48), _island("loft", [1300, -800, 2000, -500], 96),
			_island("wledge", [2100, -800, 2400, -400], 48), _island("wtop", [2100, -1300, 2500, -1000], 144), _island("etop", [2900, -1300, 3300, -1000], 144), _island("eledge", [2900, -800, 3300, -400], 48),
			_island("look", [3400, -1300, 3700, -900], 96), _island("ledge-4", [3400, -700, 3700, -400], 96), _island("rock", [3860, -1300, 3960, -1120], 96), _island("big", [4060, -1300, 4400, -400], 96),
			_island("far", [4500, -1300, 4800, -900], 96)],
		"bridges": [
			_bridge("footbridge", [300, 0, 400, 96], 48, "mill", "ledge"), _bridge("stones", [300, 400, 400, 496], 0, "beach", "isle"),
			_bridge("walkway", [1600, -300, 1700, -204], 48, "yard", "deck"),
			_bridge("rope-bridge", [2500, -1200, 2900, -1104], 144, "wtop", "etop", true), _bridge("behind", [2400, -700, 2900, -604], 48, "wledge", "eledge"),
			_bridge("log", [3500, -900, 3596, -700], 96, "look", "ledge-4"), _bridge("s1", [3700, -1250, 3780, -1170], 96, "look", "rock"), _bridge("s2", [3780, -1250, 3860, -1170], 96, "look", "rock"),
			_bridge("leap", [3960, -1250, 4060, -1170], 96, "rock", "big", true), _bridge("rope-span", [3700, -690, 4060, -594], 96, "ledge-4", "big", true),
			_bridge("middle-steps", [3700, -520, 4060, -424], 96, "ledge-4", "big"), _bridge("far-gate", [4400, -1150, 4500, -1054], 96, "big", "far")],
		"stairs": [
			_stair("ladder", [560, 200, 656, 300], "z", "ledge", "isle", 48, 0, true), _stair("down-to-bank", [800, 0, 900, 96], "x", "ledge", "bank", 48, 0),
			_stair("mill-steps", [1200, -250, 1300, -154], "x", "bank", "yard", 0, 48), _stair("riverbed", [1200, 0, 1700, 96], "x", "bank", "deck", 0, 48),
			_stair("wheel", [1850, -500, 1946, -400], "z", "loft", "deck", 96, 48, true), _stair("attic-ladder", [1450, -500, 1546, -400], "z", "loft", "yard", 96, 48, true),
			_stair("down-to-ledge", [2000, -700, 2100, -604], "x", "loft", "wledge", 96, 48),
			_stair("west-ladder", [2200, -1000, 2296, -800], "z", "wtop", "wledge", 144, 48, true), _stair("spray-steps", [3100, -1000, 3196, -800], "z", "etop", "eledge", 144, 48),
			_stair("down-to-lookout", [3300, -1200, 3400, -1104], "x", "etop", "look", 144, 96)],
		"stages": [_foot(), _mill(), _behind(), _stones()]}

## Stage 1: Gold on the mill with the pool wheel, Teal on the beach; the
## pipsport in the post box on the island.
static func _foot() -> Dictionary:
	var stage := _stage("foot-of-the-falls", "p0", [480, -40])
	stage.item_starts = {"pipsport": "post"}
	stage.current_legs = [{"from": "bucket", "to": "bucket-top", "control_id": "pool", "value": "HIGH"}]
	stage.blocks = [
		{"block": "selector", "id": "pool", "at": [80, -40], "surface": "mill", "owner": "p0", "height": 48, "values": ["HIGH", "LOW"], "initial": "HIGH"},
		{"block": "selector_gate", "selector": "pool", "routes": {"stones": "LOW"}},
		{"block": "weight_pan", "pad": _pad("pan", [760, 560], "isle", 0), "items": ["pipsport"], "routes": ["footbridge"]},
		{"block": "open_route", "routes": ["ladder"]},
		_goal("foot-goal", [480, -40], "ledge", 48, CARRIED)]
	return stage

## Stage 2: both come down the stair to the bank; Teal holds the pipsport.
static func _mill() -> Dictionary:
	var stage := _stage("the-old-mill", "p1", [1700, -700])
	stage.item_starts = {"pipsport": "p1"}
	var gate := {"pad_id": "gate-board"}
	stage.current_legs = [{"from": "hook", "to": "sack-top", "when": {"any": [gate, {"pad_id": "winding-board"}]}}]
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-bank", "walkway"]},
		{"block": "pad", "id": "gate-board", "at": [1940, 40], "surface": "deck", "owner": "p0", "height": 48, "style": "board"},
		{"block": "pad", "id": "winding-board", "at": [1900, -760], "surface": "loft", "owner": "p0", "height": 96, "style": "board"},
		{"block": "raw", "gates": [{"route_id": "mill-steps", "when": {"not": gate}}, {"route_id": "riverbed", "when": gate}]},
		{"block": "wheel_ride", "stairs": ["wheel"], "when": gate},
		{"block": "relay_lever", "lever": {"id": "hatch", "at": [1620, -600], "surface": "loft", "owner": "p0", "height": 96}, "routes": ["attic-ladder"]},
		_goal("mill-goal", [1700, -700], "loft", 96, CARRIED)]
	return stage

## Stage 3: both come down to the west ledge; Teal holds the pipsport.
static func _behind() -> Dictionary:
	var stage := _stage("behind-the-falls", "p1", [3100, -1150])
	stage.item_starts = {"pipsport": "p1"}
	stage.current_legs = [{"from": "basket", "to": "basket-end", "when": {"pad_id": "crank"}}]
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-ledge", "west-ladder", "spray-steps"]},
		{"block": "crank_bridge", "pads": [_pad("crank", [2140, -1260], "wtop", 144), _pad("east-crank", [3260, -1260], "etop", 144)], "routes": ["rope-bridge"]},
		{"block": "falls_path", "lever": {"id": "water-gate", "at": [3260, -1040], "surface": "etop", "owner": "p0", "height": 144}, "routes": ["behind"]},
		_goal("behind-goal", [3100, -1150], "etop", 144, CARRIED)]
	return stage

## Stage 4: both come down to the lookout; Gold holds the pipsport.
static func _stones() -> Dictionary:
	var stage := _stage("the-last-stones", "p1", [4650, -1000])
	stage.item_starts = {"pipsport": "p0"}
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-lookout", "leap"]},
		{"block": "selector", "id": "stream", "at": [3460, -960], "surface": "look", "owner": "p0", "height": 96, "values": ["HIGH", "MID", "LOW"], "initial": "HIGH"},
		{"block": "selector_gate", "selector": "stream", "routes": {"log": "HIGH", "middle-steps": "MID"}},
		{"block": "sinking_stones", "stones": ["s1", "s2"], "when": {"control_id": "stream", "value": "LOW"}},
		{"block": "crank_bridge", "pads": [_pad("look-crank", [3640, -960], "look", 96)], "routes": ["rope-span"]},
		{"block": "pad", "id": "gate-step", "at": [4140, -480], "surface": "big", "owner": "p0", "height": 96, "style": "board"},
		{"block": "lever", "id": "bar", "at": [4740, -1240], "surface": "far", "owner": "p0", "height": 96},
		{"block": "raw", "gates": [{"route_id": "far-gate", "when": {"any": [{"pad_id": "gate-step"}, {"lever_id": "bar"}]}}]},
		_goal("stones-goal", [4650, -1000], "far", 96, CARRIED)]
	return stage

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}

static func _goal(id: String, at: Array, surface: String, height: int, when: Dictionary) -> Dictionary:
	return {"block": "ring_bell", "id": id, "at": at, "surface": surface, "owner": "p1", "height": height, "radius": 48, "when": when}

static func _pad(id: String, at: Array, surface: String, height: int) -> Dictionary:
	return {"id": id, "at": at, "surface": surface, "owner": "p0", "height": height}

static func _spot(id: String, surface: String, at: Array, height: int) -> Dictionary:
	return {"id": id, "surface_id": surface, "position_cm": at, "height_cm": height}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id": id, "rect_cm": rect, "height_cm": height}

static func _bridge(id: String, rect: Array, height: int, from: String, to: String, hands: bool = false) -> Dictionary:
	var bridge := {"id": id, "rect_cm": rect, "from_surface": from, "to_surface": to, "height_cm": height}
	if hands: bridge["hands"] = true
	return bridge

static func _stair(id: String, rect: Array, axis: String, from: String, to: String, low: int, high: int, hands: bool = false) -> Dictionary:
	var stair := {"id": id, "rect_cm": rect, "axis": axis, "from_surface": from, "to_surface": to, "from_height_cm": low, "to_height_cm": high}
	if hands: stair["hands"] = true
	return stair
