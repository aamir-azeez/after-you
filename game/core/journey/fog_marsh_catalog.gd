extends RefCounted
## Fog Marsh: three stages on the new pieces (rules 16, core/physical/pieces_rules.gd:
## the tide rules with open controls and open turns, plus carried items,
## currents, platforms, one way stairs and "not" gates), written with the
## stage blocks (core/blocks/stage_blocks.gd). The designs are
## claude-20261011\pipsport-concepts\solver\levels.py (marsh_1 to marsh_3):
## Teal is p1, Gold is p0, and Gold (the host's pip) plays first in stage 1.
## A journey is one map: each stage starts with both pips where the stage
## before ended (its goal), so each stage opens its own way in from there.
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
##     and drains the bend boards. The goal wants it lit and the pipsport carried.
##   3 carry-it-home: both come back down the stair from the north bank and
##     over to the lift's landing (0 cm).
##     The weight lift rises to the stilts (96 cm) while something heavy is in
##     its bottom pan (a pip, the pipsport, or the lantern's water) and none in
##     its top pan; the rope ladder only goes up and needs both hands; the post
##     office door is held from the step outside. The goal on the jetty wants
##     the pipsport on the stamp desk and the lantern lit.
## No player words here: the title and hints are the descriptor's copy and
## stage_copy, so changing them never changes the definition hash.
## The turn limits are development ones (120 s every turn, what the 1 MiB
## solo save fits today) until play sets them (scripts/chapter_turn_limits.py).

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take: 10, or 20 on a hard stage (the owner's call).
const CAPS := {"where-the-stream-went": 10, "catch-the-pipsport": 10, "carry-it-home": 10}

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "fog-marsh", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks": 3600, "b_ticks": 3600},
		"starts": {"p0": {"position_cm": [150, -50], "height_cm": 0, "surface_id": "path"}, "p1": {"position_cm": [750, 360], "height_cm": 0, "surface_id": "boat-steps"}},
		"props": [], "drops": [],
		# Stage 1 has no pipsport: it bobs out in the channel until stage 2.
		"items": [{"id": "pipsport", "at": "channel"}],
		"item_spots": [
			_spot("channel", "", [2170, 40], 0), _spot("bend", "bend", [2400, 50], 0), _spot("landing", "landing", [2940, -410], 0), _spot("reeds", "reeds", [3260, 190], 0),
			_spot("pan", "landing-3", [3140, -90], 0), _spot("top-pan", "stilts", [3860, -90], 96), _spot("desk", "office", [4140, 410], 96)],
		"islands": [
			_island("path", [0, -450, 300, 150], 0), _island("middle", [600, -200, 900, 100], 0), _island("boat-steps", [600, 250, 900, 450], 0), _island("jetty", [1200, -450, 1500, 150], 0),
			_island("dock", [1700, -450, 2100, 450], 0), _island("north", [2200, -450, 2600, -200], 0), _island("bend", [2250, -50, 2550, 100], 0), _island("landing", [2700, -450, 3000, -150], 0),
			_island("bank", [2700, 150, 3000, 450], 0), _island("reeds", [3200, 150, 3500, 450], 0),
			_island("landing-3", [3100, -450, 3400, -50], 0), _island("stilts", [3600, -450, 3900, -50], 96), _island("jetty-3", [4100, -450, 4400, -50], 96), _island("office", [4100, 150, 4400, 450], 96)],
		"bridges": [
			_bridge("west-boards", [300, -160, 600, -64], 0, "path", "middle"), _bridge("reed-stones", [300, -20, 600, 76], 0, "path", "middle"),
			_bridge("high-boards", [300, -420, 1200, -324], 0, "path", "jetty"), _bridge("low-boards", [700, 100, 796, 250], 0, "middle", "boat-steps"),
			_bridge("middle-jetty", [900, -100, 1200, -4], 0, "middle", "jetty"),
			_bridge("raft-boat", [900, 300, 980, 380], 0, "boat-steps", "jetty"), _bridge("raft-jetty", [1300, 150, 1380, 230], 0, "boat-steps", "jetty"),
			_bridge("over-to-dock", [1500, -50, 1700, 46], 0, "jetty", "dock"), _bridge("plank", [2100, 300, 2700, 396], 0, "dock", "bank"),
			_bridge("north-boards", [2100, -400, 2200, -304], 0, "dock", "north"), _bridge("stair", [2600, -400, 2700, -304], 0, "north", "landing"),
			_bridge("bank-landing", [2800, -150, 2896, 150], 0, "landing", "bank"), _bridge("swirl-stones", [3000, 250, 3200, 346], 0, "bank", "reeds"),
			_bridge("bend-boards", [2350, -200, 2446, -50], 0, "north", "bend"), _bridge("over-to-landing", [3000, -400, 3100, -304], 0, "landing", "landing-3"),
			_bridge("lift-low", [3400, -400, 3600, -300], 0, "landing-3", "stilts"), _bridge("lift-high", [3400, -400, 3600, -300], 96, "landing-3", "stilts"),
			_bridge("stilts-jetty", [3900, -400, 4100, -304], 96, "stilts", "jetty-3"), _bridge("door", [4200, -50, 4296, 150], 96, "jetty-3", "office")],
		"stairs": [_stair("rope-ladder", [3400, -180, 3600, -100], "x", "landing-3", "stilts", 0, 96, true)],
		"stages": [_stream(), _catch(), _home()]}

## Stage 1: Gold on the path, Teal on the boat steps; no pipsport yet.
static func _stream() -> Dictionary:
	var stage := _stage("where-the-stream-went", "p0", [1350, -300])
	stage.blocks = [
		{"block": "open_route", "routes": ["middle-jetty"]},
		{"block": "lever", "id": "east", "at": [60, 90], "surface": "path", "owner": "p0"},
		{"block": "relay_lever", "lever": _thing("west", [640, 420], "boat-steps", 0), "routes": ["west-boards"]},
		{"block": "relay_lever", "lever": _thing("high", [660, -160], "middle", 0), "routes": ["high-boards"]},
		{"block": "fog_lantern", "lever": _thing("lantern", [840, -160], "middle", 0), "floods": {"low-boards": {"lever_id": "east"}}, "drains": {"reed-stones": {}}},
		{"block": "rope_raft", "id": "raft", "selector": {"id": "rope", "at": [1440, 90], "surface": "jetty", "owner": "p0", "height": 0, "values": ["BOAT", "JETTY"], "initial": "BOAT"},
			"stops": {"BOAT": "raft-boat", "JETTY": "raft-jetty"}},
		_goal("stream-goal", [1350, -300], "jetty", 0, {"lever_id": "lantern"})]
	return stage

## Stage 2: both come over to the dock; the pipsport bobs in the channel.
static func _catch() -> Dictionary:
	var stage := _stage("catch-the-pipsport", "p1", [2400, -350])
	stage.item_starts = {"pipsport": "channel"}
	var held := {"pad_id": "water-gate"}
	stage.current_legs = [
		{"from": "channel", "to": "bend", "control_id": "current", "value": "NORTH"},
		{"from": "bend", "to": "landing", "control_id": "current", "value": "SOUTH", "when": held},
		{"from": "bend", "to": "reeds", "control_id": "current", "value": "SOUTH", "stop": held}]
	stage.blocks = [
		{"block": "open_route", "routes": ["over-to-dock", "bank-landing"]},
		{"block": "selector", "id": "current", "at": [1760, 400], "surface": "dock", "owner": "p0", "height": 0, "values": ["SOUTH", "NORTH"], "initial": "SOUTH"},
		{"block": "hold_door", "pad": _thing("plank-board", [1950, -150], "dock", 0), "routes": ["plank"]},
		{"block": "relay_lever", "lever": _thing("stair-lever", [1760, -400], "dock", 0), "routes": ["stair"]},
		{"block": "relay_lever", "lever": _thing("boards-lever", [2940, -200], "landing", 0), "routes": ["north-boards"]},
		{"block": "pad", "id": "water-gate", "at": [3440, 400], "surface": "reeds", "owner": "p0", "style": "board"},
		{"block": "fog_lantern", "lever": _thing("north-lantern", [2560, -240], "north", 0), "floods": {"swirl-stones": {}}, "drains": {"bend-boards": {}}},
		_goal("catch-goal", [2400, -350], "north", 0, {"all": [{"lever_id": "north-lantern"}, {"item_id": "pipsport", "carried": true}]})]
	return stage

## Stage 3: both come down the stair and over to the lift's landing; Teal holds the pipsport.
static func _home() -> Dictionary:
	var stage := _stage("carry-it-home", "p1", [4160, -300])
	stage.item_starts = {"pipsport": "p1"}
	stage.blocks = [
		{"block": "open_route", "routes": ["stair", "over-to-landing", "stilts-jetty"]},
		{"block": "lever", "id": "home-lantern", "at": [4360, 410], "surface": "office", "owner": "p0", "height": 96},
		{"block": "weight_lift", "id": "lift", "low": "lift-low", "high": "lift-high",
			"pads": [_thing("pan", [3140, -90], "landing-3", 0)], "top_pads": [_thing("top-pan", [3860, -90], "stilts", 96)],
			"items": ["pipsport"], "also": {"lever_id": "home-lantern"}},
		{"block": "rope_ladder", "stairs": ["rope-ladder"]},
		{"block": "hold_door", "pad": _thing("step", [4360, -410], "jetty-3", 96), "routes": ["door"]},
		_goal("home-goal", [4160, -300], "jetty-3", 96, {"all": [{"item_id": "pipsport", "spot_id": "desk"}, {"lever_id": "home-lantern"}]})]
	return stage

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}

static func _goal(id: String, at: Array, surface: String, height: int, when: Dictionary) -> Dictionary:
	return {"block": "ring_bell", "id": id, "at": at, "surface": surface, "owner": "p1", "height": height, "radius": 48, "when": when}

static func _thing(id: String, at: Array, surface: String, height: int) -> Dictionary:
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
