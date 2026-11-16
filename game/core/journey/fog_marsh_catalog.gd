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
##   3 carry-it-home: both come over from the north bank to the landing (0 cm).
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
		"starts": {"p0": {"position_cm": [150, 150], "height_cm": 0, "surface_id": "path"}, "p1": {"position_cm": [750, 760], "height_cm": 0, "surface_id": "boat-steps"}},
		"props": [], "drops": [],
		# Stage 1 has no pipsport: it bobs out in the channel until stage 2.
		"items": [{"id": "pipsport", "at": "channel"}],
		"item_spots": [
			_spot("channel", "", [2300, -120], 0), _spot("bend", "bend", [2760, -660], 0), _spot("landing", "landing", [2640, -240], 0), _spot("reeds", "reeds", [2960, 140], 0),
			_spot("pan", "landing-3", [2140, -1460], 0), _spot("top-pan", "stilts", [2860, -1460], 96), _spot("desk", "office", [3140, -1840], 96)],
		"islands": [
			_island("path", [0, -300, 300, 300], 0), _island("middle", [600, 0, 900, 300], 0), _island("boat-steps", [600, 600, 900, 900], 0), _island("jetty", [1200, -300, 1500, 300], 0),
			_island("dock", [1700, -300, 2200, 300], 0), _island("north", [2100, -900, 2500, -600], 0), _island("landing", [2400, -300, 2700, 0], 0), _island("bank", [2400, 100, 2700, 400], 0),
			_island("reeds", [2900, 100, 3200, 400], 0), _island("bend", [2700, -900, 3000, -600], 0),
			_island("landing-3", [2100, -1500, 2400, -1200], 0), _island("stilts", [2600, -1500, 2900, -1200], 96), _island("jetty-3", [3100, -1500, 3400, -1200], 96), _island("office", [3100, -1900, 3400, -1600], 96)],
		"bridges": [
			_bridge("west-boards", [300, 40, 600, 136], 0, "path", "middle"), _bridge("reed-stones", [300, 180, 600, 276], 0, "path", "middle"),
			_bridge("high-boards", [300, -220, 1200, -124], 0, "path", "jetty"), _bridge("low-boards", [700, 300, 796, 600], 0, "middle", "boat-steps"),
			_bridge("middle-jetty", [900, 100, 1200, 196], 0, "middle", "jetty"),
			_bridge("raft-boat", [900, 700, 980, 780], 0, "boat-steps", "jetty"), _bridge("raft-jetty", [1300, 300, 1380, 380], 0, "boat-steps", "jetty"),
			_bridge("over-to-dock", [1500, -250, 1700, -154], 0, "jetty", "dock"), _bridge("plank", [2200, 200, 2400, 296], 0, "dock", "bank"),
			_bridge("north-boards", [2104, -600, 2200, -300], 0, "north", "dock"), _bridge("stair", [2404, -600, 2500, -300], 0, "north", "landing"),
			_bridge("bank-landing", [2500, 0, 2596, 100], 0, "landing", "bank"), _bridge("swirl-stones", [2700, 200, 2900, 296], 0, "bank", "reeds"),
			_bridge("bend-boards", [2500, -800, 2700, -704], 0, "north", "bend"), _bridge("over-to-landing", [2200, -1200, 2296, -900], 0, "landing-3", "north"),
			_bridge("lift-low", [2400, -1460, 2600, -1360], 0, "landing-3", "stilts"), _bridge("lift-high", [2400, -1460, 2600, -1360], 96, "landing-3", "stilts"),
			_bridge("stilts-jetty", [2900, -1400, 3100, -1304], 96, "stilts", "jetty-3"), _bridge("door", [3200, -1600, 3296, -1500], 96, "office", "jetty-3")],
		"stairs": [_stair("rope-ladder", [2400, -1290, 2600, -1210], "x", "landing-3", "stilts", 0, 96, true)],
		"stages": [_stream(), _catch(), _home()]}

## Stage 1: Gold on the path, Teal on the boat steps; no pipsport yet.
static func _stream() -> Dictionary:
	var stage := _stage("where-the-stream-went", "p0", [1350, -100])
	stage.blocks = [
		{"block": "open_route", "routes": ["middle-jetty"]},
		{"block": "lever", "id": "east", "at": [60, 240], "surface": "path", "owner": "p0"},
		{"block": "relay_lever", "lever": _thing("west", [640, 840], "boat-steps", 0), "routes": ["west-boards"]},
		{"block": "relay_lever", "lever": _thing("high", [660, 60], "middle", 0), "routes": ["high-boards"]},
		{"block": "fog_lantern", "lever": _thing("lantern", [840, 60], "middle", 0), "floods": {"low-boards": {"lever_id": "east"}}, "drains": {"reed-stones": {}}},
		{"block": "rope_raft", "id": "raft", "selector": {"id": "rope", "at": [1440, 240], "surface": "jetty", "owner": "p0", "height": 0, "values": ["BOAT", "JETTY"], "initial": "BOAT"},
			"stops": {"BOAT": "raft-boat", "JETTY": "raft-jetty"}},
		_goal("stream-goal", [1350, -100], "jetty", 0, {"lever_id": "lantern"})]
	return stage

## Stage 2: both come over to the dock; the pipsport bobs in the channel.
static func _catch() -> Dictionary:
	var stage := _stage("catch-the-pipsport", "p1", [2300, -750])
	stage.item_starts = {"pipsport": "channel"}
	var held := {"pad_id": "water-gate"}
	stage.current_legs = [
		{"from": "channel", "to": "bend", "control_id": "current", "value": "NORTH"},
		{"from": "bend", "to": "landing", "control_id": "current", "value": "SOUTH", "when": held},
		{"from": "bend", "to": "reeds", "control_id": "current", "value": "SOUTH", "stop": held}]
	stage.blocks = [
		{"block": "open_route", "routes": ["over-to-dock", "bank-landing"]},
		{"block": "selector", "id": "current", "at": [1760, 240], "surface": "dock", "owner": "p0", "height": 0, "values": ["SOUTH", "NORTH"], "initial": "SOUTH"},
		{"block": "hold_door", "pad": _thing("plank-board", [1900, -240], "dock", 0), "routes": ["plank"]},
		{"block": "relay_lever", "lever": _thing("stair-lever", [1760, -240], "dock", 0), "routes": ["stair"]},
		{"block": "relay_lever", "lever": _thing("boards-lever", [2640, -60], "landing", 0), "routes": ["north-boards"]},
		{"block": "pad", "id": "water-gate", "at": [3140, 340], "surface": "reeds", "owner": "p0", "style": "board"},
		{"block": "fog_lantern", "lever": _thing("north-lantern", [2440, -840], "north", 0), "floods": {"swirl-stones": {}}, "drains": {"bend-boards": {}}},
		_goal("catch-goal", [2300, -750], "north", 0, {"all": [{"lever_id": "north-lantern"}, {"item_id": "pipsport", "carried": true}]})]
	return stage

## Stage 3: both come over to the landing; Teal holds the pipsport.
static func _home() -> Dictionary:
	var stage := _stage("carry-it-home", "p1", [3160, -1260])
	stage.item_starts = {"pipsport": "p1"}
	stage.blocks = [
		{"block": "open_route", "routes": ["over-to-landing", "stilts-jetty"]},
		{"block": "lever", "id": "home-lantern", "at": [3360, -1840], "surface": "office", "owner": "p0", "height": 96},
		{"block": "weight_lift", "id": "lift", "low": "lift-low", "high": "lift-high",
			"pads": [_thing("pan", [2140, -1460], "landing-3", 0)], "top_pads": [_thing("top-pan", [2860, -1460], "stilts", 96)],
			"items": ["pipsport"], "also": {"lever_id": "home-lantern"}},
		{"block": "rope_ladder", "stairs": ["rope-ladder"]},
		{"block": "hold_door", "pad": _thing("step", [3360, -1240], "jetty-3", 96), "routes": ["door"]},
		_goal("home-goal", [3160, -1260], "jetty-3", 96, {"all": [{"item_id": "pipsport", "spot_id": "desk"}, {"lever_id": "home-lantern"}]})]
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
