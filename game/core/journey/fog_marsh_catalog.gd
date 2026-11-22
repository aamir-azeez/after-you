extends RefCounted
## Fog Marsh: three stages on the new pieces (rules 20, core/physical/pieces_rules.gd:
## the tide rules with open controls and open turns, plus carried items,
## currents, platforms, one way stairs and "not" gates), written with the
## stage blocks (core/blocks/stage_blocks.gd). The designs are
## claude-20261011\pipsport-concepts\solver\levels.py (marsh_1 to marsh_3):
## Teal is p1, Gold is p0, and Gold (the host's pip) plays first in stage 1.
## A journey is one map: each stage starts with both pips where the stage
## before ended (its goal), so each stage opens its own way in from there.
## The floors stand far apart over open water (the marsh runs about 115 m)
## so each stage runs well past the screen under the close follow camera and
## the fog has room to hide what is ahead.
##   1 where-the-stream-went (all at 0 cm): each lever lowers a boardwalk for
##     the other side (the east lever on the path the low boards, the west
##     lever by the boat steps the west boards), the high lever on the middle
##     boards lowers the high boards from the path to the jetty, and the fog
##     lantern's pump floods the low boards and drains the reed stones while
##     it burns. The rope wheel on the jetty pulls the raft over from the boat
##     steps. The goal on the jetty wants the lantern lit.
##   2 catch-the-pipsport (all at 0 cm): both come over from the jetty to the
##     west dock; the plank to the east bank is down while someone stands on
##     the plank board on the dock, away from it, so one holds and the other
##     crosses (the design started the two apart). The current wheel sends
##     the pipsport north to the bend, then south: on to the landing while the
##     water gate board on the reed island is held, else onto the reed island.
##     The stair from the landing is let down from the dock, the north boards
##     from the landing; the lantern on the north bank floods the swirl stones
##     and drains the bend boards. The goal wants it lit and the pipsport resting
##     on the pedestal in front of it (a goal that needs an item carried gets one,
##     core/blocks/stage_blocks.gd goal_pedestals).
##   3 carry-it-home: both come back down the stair from the north bank and
##     over to the lift's landing (0 cm).
##     The weight lift rises to the stilts (192 cm) while something heavy is in
##     its bottom pan (a pip, the pipsport, or the lantern's water) and none in
##     its top pan; the rope ladder only goes up and needs both hands; the post
##     office door is held from the step outside. The goal on the jetty wants
##     the pipsport on the stamp desk and the lantern lit.
## No player words here: the title and hints are the descriptor's copy and
## stage_copy, so changing them never changes the definition hash.
## The turn limits are the fallback until the owner plays it: twice the
## longest played carry-over turn of the witness routes, rounded up to whole
## 5 s, so 105 s every turn (scripts/chapter_turn_limits.py --suggested).

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take: 10, or 20 on a hard stage (the owner's call).
const CAPS := {"where-the-stream-went": 10, "catch-the-pipsport": 10, "carry-it-home": 10}

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "fog-marsh", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks":3150,"b_ticks":3150},
		"starts": {"p0": {"position_cm": [225, -70], "height_cm": 0, "surface_id": "path"}, "p1": {"position_cm": [2175, 504], "height_cm": 0, "surface_id": "boat-steps"}},
		"props": [], "drops": [],
		# Stage 1 has no pipsport: it bobs out in the channel until stage 2.
		"items": [{"id": "pipsport", "at": "channel"}],
		"item_spots": [
			_spot("channel", "", [6300, 56], 0), _spot("bend", "bend", [6750, 70], 0), _spot("landing", "landing", [7910, -574], 0), _spot("reeds", "reeds", [8740, 266], 0),
			_spot("pan", "landing-3", [8560, -126], 0), _spot("top-pan", "stilts", [9990, -126], 192), _desk()],
		"islands": [
			_island("path", [0, -630, 450, 210], 0), _island("middle", [1950, -280, 2400, 140], 0), _island("boat-steps", [1950, 350, 2400, 630], 0), _island("jetty", [3900, -630, 4350, 210], 0),
			_island("dock", [5350, -630, 5950, 630], 0), _island("north", [6450, -630, 7050, -280], 0), _island("bend", [6525, -70, 6975, 140], 0), _island("landing", [7550, -630, 8000, -210], 0),
			_island("bank", [7550, 210, 8000, 630], 0), _island("reeds", [8650, 210, 9100, 630], 0),
			_island("landing-3", [8500, -630, 9175, -70], 0), _island("stilts", [9375, -630, 10050, -70], 192), _island("jetty-3", [11050, -630, 11500, -70], 192), _island("office", [11050, 210, 11500, 630], 192)],
		"bridges": [
			_bridge("west-boards", [450, -205, 1950, -109], 0, "path", "middle"), _bridge("reed-stones", [450, -9, 1950, 87], 0, "path", "middle"),
			_bridge("high-boards", [450, -569, 3900, -473], 0, "path", "jetty"), _bridge("low-boards", [2124, 140, 2220, 350], 0, "middle", "boat-steps"),
			_bridge("middle-jetty", [2400, -121, 3900, -25], 0, "middle", "jetty"),
			_bridge("raft-boat", [2400, 420, 2520, 532], 0, "boat-steps", "jetty"), _bridge("raft-jetty", [4050, 210, 4170, 322], 0, "boat-steps", "jetty"),
			_bridge("over-to-dock", [4350, -51, 5350, 45], 0, "jetty", "dock"), _bridge("plank", [5950, 439, 7550, 535], 0, "dock", "bank"),
			_bridge("north-boards", [5950, -560, 6450, -426], 0, "dock", "north"), _bridge("stair", [7050, -560, 7550, -426], 0, "north", "landing"),
			_bridge("bank-landing", [7724, -210, 7820, 210], 0, "landing", "bank"), _bridge("swirl-stones", [8000, 369, 8650, 465], 0, "bank", "reeds"),
			_bridge("bend-boards", [6699, -280, 6795, -70], 0, "north", "bend"), _bridge("over-to-landing", [8000, -560, 8500, -426], 0, "landing", "landing-3"),
			_bridge("lift-low", [9175, -540, 9375, -440], 0, "landing-3", "stilts"), _bridge("lift-high", [9175, -540, 9375, -440], 192, "landing-3", "stilts"),
			_bridge("stilts-jetty", [10050, -541, 11050, -445], 192, "stilts", "jetty-3"), _bridge("door", [11224, -70, 11320, 210], 192, "jetty-3", "office")],
		"stairs": [_stair("rope-ladder", [9175, -236, 9375, -156], "x", "landing-3", "stilts", 0, 192, true)],
		"stages": [_stream(), _catch(), _home()]}

## Stage 1: Gold on the path, Teal on the boat steps; no pipsport yet.
static func _stream() -> Dictionary:
	var stage := _stage("where-the-stream-went", "p0", [4125, -420])
	stage.blocks = [
		{"block": "open_route", "routes": ["middle-jetty"]},
		{"block": "lever", "id": "east", "at": [90, 126], "surface": "path", "owner": "p0", "height": 0},
		{"block": "relay_lever", "lever": _thing("west", [2010, 588], "boat-steps", 0), "routes": ["west-boards"]},
		{"block": "relay_lever", "lever": _thing("high", [2040, -224], "middle", 0), "routes": ["high-boards"]},
		{"block": "fog_lantern", "lever": _thing("lantern", [2310, -224], "middle", 0), "floods": {"low-boards": {"lever_id": "east"}}, "drains": {"reed-stones": {}}},
		{"block": "rope_raft", "id": "raft", "selector": {"id": "rope", "at": [4260, 126], "surface": "jetty", "owner": "p0", "height": 0, "values": ["BOAT", "JETTY"], "initial": "BOAT"},
			"stops": {"BOAT": "raft-boat", "JETTY": "raft-jetty"}},
		_goal("stream-goal", [4125, -420], "jetty", 0, {"lever_id": "lantern"})]
	return stage

## Stage 2: both come over to the dock; the pipsport bobs in the channel.
static func _catch() -> Dictionary:
	var stage := _stage("catch-the-pipsport", "p1", [6750, -490])
	stage.item_starts = {"pipsport": "channel"}
	var held := {"pad_id": "water-gate"}
	stage.current_legs = [
		{"from": "channel", "to": "bend", "control_id": "current", "value": "NORTH"},
		{"from": "bend", "to": "landing", "control_id": "current", "value": "SOUTH", "when": held},
		{"from": "bend", "to": "reeds", "control_id": "current", "value": "SOUTH", "stop": held}]
	stage.blocks = [
		{"block": "open_route", "routes": ["over-to-dock", "bank-landing"]},
		{"block": "selector", "id": "current", "at": [5440, 560], "surface": "dock", "owner": "p0", "height": 0, "values": ["SOUTH", "NORTH"], "initial": "SOUTH"},
		{"block": "hold_door", "pad": _thing("plank-board", [5725, -210], "dock", 0), "routes": ["plank"]},
		{"block": "relay_lever", "lever": _thing("stair-lever", [5440, -560], "dock", 0), "routes": ["stair"]},
		{"block": "relay_lever", "lever": _thing("boards-lever", [7910, -280], "landing", 0), "routes": ["north-boards"]},
		{"block": "pad", "id": "water-gate", "at": [9010, 560], "surface": "reeds", "owner": "p0", "height": 0, "style": "board"},
		{"block": "fog_lantern", "lever": _thing("north-lantern", [6990, -336], "north", 0), "floods": {"swirl-stones": {}}, "drains": {"bend-boards": {}}},
		_goal("catch-goal", [6750, -490], "north", 0, {"all": [{"lever_id": "north-lantern"}, {"item_id": "pipsport", "carried": true}]})]
	return stage

## Stage 3: both come down the stair and over to the lift's landing; Teal holds the pipsport.
static func _home() -> Dictionary:
	var stage := _stage("carry-it-home", "p1", [11140, -420])
	stage.item_starts = {"pipsport": "p1"}
	stage.blocks = [
		{"block": "open_route", "routes": ["stair", "over-to-landing", "stilts-jetty"]},
		{"block": "lever", "id": "home-lantern", "at": [11440, 574], "surface": "office", "owner": "p0", "height": 192},
		{"block": "weight_lift", "id": "lift", "low": "lift-low", "high": "lift-high",
			"pads": [_thing("pan", [8560, -126], "landing-3", 0)], "top_pads": [_thing("top-pan", [9990, -126], "stilts", 192)],
			"items": ["pipsport"], "also": {"lever_id": "home-lantern"}},
		{"block": "rope_ladder", "stairs": ["rope-ladder"]},
		{"block": "hold_door", "pad": _thing("step", [11440, -574], "jetty-3", 192), "routes": ["door"]},
		_goal("home-goal", [11140, -420], "jetty-3", 192, {"all": [{"item_id": "pipsport", "spot_id": "desk"}, {"lever_id": "home-lantern"}]})]
	return stage

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}

static func _goal(id: String, at: Array, surface: String, height: int, when: Dictionary) -> Dictionary:
	return {"block": "ring_bell", "id": id, "at": at, "surface": surface, "owner": "p1", "height": height, "radius": 60, "plate": true, "when": when}

static func _thing(id: String, at: Array, surface: String, height: int) -> Dictionary:
	return {"id": id, "at": at, "surface": surface, "owner": "p0", "height": height}

## The stamp desk the post office keeps in its middle: solid, so a pip walks
## round it and sets the pipsport down from beside it (its look is the dressing's
## stamp desk prop at this spot, the ring round it the "desk" item spot style).
static func _desk() -> Dictionary:
	return {"id": "desk", "surface_id": "office", "position_cm": [11160, 540], "height_cm": 192, "radius_cm": 68, "solid": {"radius_cm": 36, "reach_cm": 20}}

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

