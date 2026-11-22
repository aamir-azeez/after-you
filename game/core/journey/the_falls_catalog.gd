extends RefCounted
## The Falls: four stages on the new pieces (rules 20, core/physical/pieces_rules.gd:
## the tide rules with open controls and open turns, plus carried items,
## currents, platforms, sinking stones, one way stairs and "not" gates),
## written with the stage blocks (core/blocks/stage_blocks.gd). The designs are
## claude-20261011\pipsport-concepts\solver\levels.py (falls_1 to falls_4):
## Teal is p1, Gold is p0, and Gold (the host's pip) plays first in stage 1.
## A journey is one map: each stage starts with both pips where the stage
## before ended (its goal), so each stage opens one stair from that goal up
## into its own start (stage 2 starts both on the bank, 3 on the west ledge, 4
## on the lookout). The map is one climb up a gorge: each stage stands on its
## own tier (the mill pool's floors at 0 to 120 cm, the mill at 200 to 440,
## the cliff at 570 to 810, the lip at 940), with open water between the
## floors wide enough that a stage runs about two to three phone screens
## under the close follow camera (the dressing's "camera"). The last puzzle's
## sinking stones are one row of four from the lookout to the rock (the slip
## row). Heights in cm.
##   1 foot-of-the-falls: the mill wheel sets the pool (LOW shows the stepping
##     stones; either pip turns it); the footbridge from the mill is down while
##     its pan on the island is weighed (a pip or the pipsport); the island
##     ladder needs both hands; the bucket on the island winds up to the ledge
##     while a pip stands on the crank board beside its top.
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
## The turn limits are the fallback until the owner plays it: twice the
## longest carry-over witness turn on the climb, at least 60 s (95 s every turn;
## scripts/chapter_turn_limits.py --suggested).

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take: 10, or 20 on a hard stage (the owner's call).
const CAPS := {"foot-of-the-falls": 10, "the-old-mill": 10, "behind-the-falls": 10, "the-last-stones": 10}
## Every goal needs the pipsport: the blocks give each goal a pedestal in front of it and
## ask for the pipsport resting there (stage_blocks.gd goal_pedestals).
const CARRIED := {"item_id": "pipsport", "carried": true}

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "the-falls", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks":2850,"b_ticks":2850},
		"starts": {"p0": {"position_cm": [390, -280], "height_cm": 120, "surface_id": "mill"}, "p1": {"position_cm": [390, 280], "height_cm": 0, "surface_id": "beach"}},
		"props": [], "drops": [],
		"items": [{"id": "pipsport", "at": "post"}],
		"item_spots": [
			_spot("post", "isle", [1584, 434], 0), _spot("pan", "isle", [2416, 434], 0), _spot("bucket", "isle", [2416, 126], 0), _spot("bucket-top", "ledge", [2364, -406], 120),
			_spot("hook", "yard", [4400, 154], 320), _spot("sack-top", "loft", [4400, -574], 440),
			_spot("basket", "wtop", [7320, -574], 810), _spot("basket-end", "etop", [9440, -574], 810)],
		"islands": [
			_island("mill", [0, -490, 780, -70], 120), _island("ledge", [1480, -490, 2520, -70], 120), _island("isle", [1480, 70, 2520, 490], 0), _island("beach", [0, 70, 780, 490], 0),
			_island("bank", [3120, -350, 3720, 630], 200), _island("yard", [4320, -210, 4920, 210], 320), _island("deck", [5120, -210, 5720, 630], 320), _island("loft", [4320, -630, 5720, -350], 440),
			_island("wledge", [6220, -630, 6670, 630], 570), _island("wtop", [6930, -630, 7380, -210], 810), _island("etop", [9380, -630, 9830, -210], 810), _island("eledge", [9380, 210, 9830, 630], 570),
			_island("look", [10330, -630, 10780, -70], 940), _island("ledge-4", [10330, 210, 10780, 630], 940), _island("rock", [11500, -630, 11650, -238], 940), _island("big", [11790, -630, 12300, 630], 940),
			_island("far", [12800, -630, 13250, 0], 940)],
		"bridges": [
			_bridge("footbridge", [780, -350, 1480, -216], 120, "mill", "ledge"), _bridge("stones", [780, 210, 1480, 344], 0, "beach", "isle"),
			_bridge("walkway", [4920, -70, 5120, 64], 320, "yard", "deck"),
			_bridge("rope-bridge", [7380, -471, 9380, -375], 810, "wtop", "etop", true), _bridge("behind", [6670, 369, 9380, 465], 570, "wledge", "eledge"),
			_bridge("log", [10504, -70, 10600, 210], 940, "look", "ledge-4"), _bridge("s1", [10780, -490, 10960, -378], 940, "look", "rock"), _bridge("s2", [10960, -490, 11140, -378], 940, "look", "rock"),
			_bridge("s3", [11140, -490, 11320, -378], 940, "look", "rock"), _bridge("s4", [11320, -490, 11500, -378], 940, "look", "rock"),
			_bridge("leap", [11650, -490, 11790, -378], 940, "rock", "big", true), _bridge("rope-span", [10780, 299, 11790, 395], 940, "ledge-4", "big", true),
			_bridge("middle-steps", [10780, 509, 11790, 605], 940, "ledge-4", "big"), _bridge("far-gate", [12300, -420, 12800, -286], 940, "big", "far")],
		"stairs": [
			_stair("ladder", [1896, -70, 2146, 70], "z", "ledge", "isle", 120, 0, true), _stair("down-to-bank", [2520, -350, 3120, -216], "x", "ledge", "bank", 120, 200),
			_stair("mill-steps", [3720, -140, 4320, -6], "x", "bank", "yard", 200, 320), _stair("riverbed", [3720, 439, 5120, 535], "x", "bank", "deck", 200, 320),
			_stair("wheel", [5420, -350, 5612, -210], "z", "loft", "deck", 440, 320, true), _stair("attic-ladder", [4620, -350, 4812, -210], "z", "loft", "yard", 440, 320, true),
			_stair("down-to-ledge", [5720, -560, 6220, -426], "x", "loft", "wledge", 440, 570),
			_stair("west-ladder", [6670, -490, 6930, -356], "x", "wledge", "wtop", 570, 810, true), _stair("spray-steps", [9554, -210, 9650, 210], "z", "etop", "eledge", 810, 570),
			_stair("down-to-lookout", [9830, -490, 10330, -356], "x", "etop", "look", 810, 940)],
		"stages": [_foot(), _mill(), _behind(), _stones()]}

## Stage 1: Gold on the mill with the pool wheel, Teal on the beach; the
## pipsport in the post box on the island. The bucket line is wound by a pip
## on the winch crank board on the ledge (owner, 2026-11-22), as stage 3's
## basket line is; the pool wheel only shows or hides the stepping stones.
static func _foot() -> Dictionary:
	var stage := _stage("foot-of-the-falls", "p0", [1688, -406])
	stage.item_starts = {"pipsport": "post"}
	stage.current_legs = [{"from": "bucket", "to": "bucket-top", "when": {"pad_id": "winch"}}]
	stage.blocks = [
		{"block": "selector", "id": "pool", "at": [208, -406], "surface": "mill", "owner": "p0", "height": 120, "values": ["HIGH", "LOW"], "initial": "HIGH"},
		{"block": "pad", "id": "winch", "at": [2380, -250], "surface": "ledge", "owner": "p0", "height": 120, "style": "crank_board"},
		{"block": "selector_gate", "selector": "pool", "routes": {"stones": "LOW"}},
		{"block": "weight_pan", "pad": _pad("pan", [2416, 434], "isle", 0), "items": ["pipsport"], "routes": ["footbridge"]},
		{"block": "open_route", "routes": ["ladder"]},
		_goal("foot-goal", [1688, -406], "ledge", 120, CARRIED)]
	return stage

## Stage 2: both come down the stair to the bank; Teal holds the pipsport.
static func _mill() -> Dictionary:
	var stage := _stage("the-old-mill", "p1", [5120, -490])
	stage.item_starts = {"pipsport": "p1"}
	var gate := {"pad_id": "gate-board"}
	stage.current_legs = [{"from": "hook", "to": "sack-top", "when": {"any": [gate, {"pad_id": "winding-board"}]}}]
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-bank", "walkway"]},
		{"block": "pad", "id": "gate-board", "at": [5600, 560], "surface": "deck", "owner": "p0", "height": 320, "style": "board"},
		{"block": "pad", "id": "winding-board", "at": [5560, -574], "surface": "loft", "owner": "p0", "height": 440, "style": "board"},
		{"block": "raw", "gates": [{"route_id": "mill-steps", "when": {"not": gate}}, {"route_id": "riverbed", "when": gate}]},
		{"block": "wheel_ride", "stairs": ["wheel"], "when": gate},
		{"block": "relay_lever", "lever": {"id": "hatch", "at": [4880, -574], "surface": "loft", "owner": "p0", "height": 440}, "routes": ["attic-ladder"]},
		_goal("mill-goal", [5120, -490], "loft", 440, CARRIED)]
	return stage

## Stage 3: both come down to the west ledge; Teal holds the pipsport.
static func _behind() -> Dictionary:
	var stage := _stage("behind-the-falls", "p1", [9590, -420])
	stage.item_starts = {"pipsport": "p1"}
	stage.current_legs = [{"from": "basket", "to": "basket-end", "when": {"pad_id": "crank"}}]
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-ledge", "west-ladder", "spray-steps"]},
		{"block": "crank_bridge", "pads": [_pad("crank", [6990, -280], "wtop", 810), _pad("east-crank", [9770, -574], "etop", 810)], "routes": ["rope-bridge"]},
		{"block": "falls_path", "lever": {"id": "water-gate", "at": [9770, -280], "surface": "etop", "owner": "p0", "height": 810}, "routes": ["behind"]},
		_goal("behind-goal", [9590, -420], "etop", 810, CARRIED)]
	return stage

## Stage 4: both come down to the lookout; Gold holds the pipsport.
static func _stones() -> Dictionary:
	var stage := _stage("the-last-stones", "p1", [13025, -210])
	stage.item_starts = {"pipsport": "p0"}
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-lookout", "leap"]},
		{"block": "selector", "id": "stream", "at": [10420, -140], "surface": "look", "owner": "p0", "height": 940, "values": ["HIGH", "MID", "LOW"], "initial": "HIGH"},
		{"block": "selector_gate", "selector": "stream", "routes": {"log": "HIGH", "middle-steps": "MID"}},
		{"block": "sinking_stones", "stones": ["s1", "s2", "s3", "s4"], "when": {"control_id": "stream", "value": "LOW"}},
		{"block": "crank_bridge", "pads": [_pad("look-crank", [10720, -140], "look", 940)], "routes": ["rope-span"]},
		{"block": "pad", "id": "gate-step", "at": [12240, 560], "surface": "big", "owner": "p0", "height": 940, "style": "board"},
		{"block": "lever", "id": "bar", "at": [13160, -574], "surface": "far", "owner": "p0", "height": 940},
		{"block": "raw", "gates": [{"route_id": "far-gate", "when": {"any": [{"pad_id": "gate-step"}, {"lever_id": "bar"}]}}]},
		_goal("stones-goal", [13025, -210], "far", 940, CARRIED)]
	return stage

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}

static func _goal(id: String, at: Array, surface: String, height: int, when: Dictionary) -> Dictionary:
	return {"block": "ring_bell", "id": id, "at": at, "surface": surface, "owner": "p1", "height": height, "radius": 60, "plate": true, "when": when}

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
