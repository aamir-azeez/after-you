extends RefCounted
## relay-isles@3: the Relay Isles on the shared journey rules, pinned to open
## turns with the new pieces (core/physical/pieces_rules.gd: 16), so a stage
## passes back and forth until both pips end a turn at its goal, up to its cap.
## relay-isles@2 keeps its own engine (core/v2/) and replays unchanged. The
## same three isles in cm: the west shore, the plank relay isle in the middle
## and the east garden, with @2's bridges between them. Either pip holds a
## plate, takes, carries, throws, catches and places the seed; nothing is one
## pip's own.
##   1 relay (orange first, the host's pip): the seed waits on a stone pedestal
##     on the west shore, so someone collects it first. The west bridge stands
##     while anyone stands on a plate: one on the shore, one on the relay isle,
##     each well away from the bridge, so the pip on a plate never crosses.
##     The relay isle's bell lights once the seed rests in the nest; both pips
##     meet there. The seed goes over either way: carried across the bridge, or
##     thrown from the shore's mark to @2's landing ring (a throw,
##     carried_items.gd: the other pip catches it there or it lands). The nest
##     is solid (core/solid_footprint.gd): pips walk round it and place the
##     seed from beside it, on any side.
##   2 garden: the bridge to the garden is a rope bridge (a crank bridge, held
##     while anyone stands on a crank board at either end). It needs both
##     hands, so the seed never goes over in a pip's arms: it is thrown from the
##     relay isle's mark to @2's landing ring on the garden isle, caught or
##     picked up there and planted. Each pip holds the rope for the other. The
##     garden lamp beside the planter lights once the seed is planted; both
##     pips meet there.
## Neither pip can do either stage alone (tests/test_level_checker.gd; the
## design solver claude-20261011\relay-isles-open\solver_relay_isles.py):
## every plate and crank board stands far enough from its crossing that a pip
## stepping off it never reaches the far side before the crossing shuts.
## No player words here: the title and hints are the descriptor's copy and
## stage_copy, so changing them never changes the definition hash.

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take: the first teaches the plates, ten; the ending, twenty.
const CAPS := {"relay": 10, "garden": 20}
## Each stage's goal: the relay isle's bell, the garden's lamp.
const BELL := [-60, 110]
const LAMP := [720, 40]

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "relay-isles", "version": 3, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks":1800,"b_ticks":1800},
		"starts": {"p0": {"position_cm": [-480, 100], "height_cm": 0, "surface_id": "west"}, "p1": {"position_cm": [-320, -120], "height_cm": 0, "surface_id": "west"}},
		"props": [], "drops": [],
		"items": [{"id": "seed", "at": "seed-pedestal"}],
		# The pedestal and the nest are solid: a pip takes or places from up to
		# 20 cm off the drum's edge, on any side. The landings keep @2's rings.
		"item_spots": [
			{"id": "seed-pedestal", "surface_id": "west", "position_cm": [-620, 40], "height_cm": 0, "radius_cm": 36, "solid": {"radius_cm": 28, "reach_cm": 20}},
			{"id": "relay-socket", "surface_id": "relay", "position_cm": [40, 0], "height_cm": 0, "radius_cm": 30, "solid": {"radius_cm": 22, "reach_cm": 20}},
			{"id": "relay-landing", "surface_id": "relay", "position_cm": [-10, 0], "height_cm": 0, "radius_cm": 66},
			{"id": "garden", "surface_id": "east", "position_cm": [620, 120], "height_cm": 0, "radius_cm": 55},
			{"id": "garden-landing", "surface_id": "east", "position_cm": [420, 0], "height_cm": 0, "radius_cm": 66}],
		"islands": [{"id": "west", "rect_cm": [-720, -220, -260, 220], "height_cm": 0},
			{"id": "relay", "rect_cm": [-140, -180, 220, 180], "height_cm": 0},
			{"id": "east", "rect_cm": [340, -220, 780, 220], "height_cm": 0}],
		"bridges": [{"id": "west-relay", "rect_cm": [-260, -65, -140, 65], "from_surface": "west", "to_surface": "relay", "height_cm": 0},
			{"id": "relay-east", "rect_cm": [220, -65, 340, 65], "from_surface": "relay", "to_surface": "east", "height_cm": 0}],
		"stairs": [],
		"stages": [_relay(), _garden()]}

## Both start on the west shore with the seed on its pedestal; the bell is on
## the relay isle.
static func _relay() -> Dictionary:
	var stage := _stage("relay", "p0", BELL)
	stage.throws = [{"id": "relay-throw", "mark": {"position_cm": [-360, 110], "surface_id": "west", "height_cm": 0, "radius_cm": 30}, "to": "relay-landing", "flight_ticks": 90, "catch_cm": 100}]
	stage.blocks = [
		{"block": "hold_door", "pad": _plate("west-plate", [-500, -60], "west"), "routes": ["west-relay"]},
		{"block": "hold_door", "pad": _plate("relay-plate", [140, -60], "relay"), "routes": ["west-relay"]},
		{"block": "ring_bell", "id": "relay-bell", "at": BELL, "surface": "relay", "owner": "p1", "height": 0, "radius": 40, "style": "bell",
			"when": {"item_id": "seed", "spot_id": "relay-socket"}}]
	return stage

## Both start at the relay bell with the seed in the nest; the lamp is in the
## garden.
static func _garden() -> Dictionary:
	var stage := _stage("garden", "p1", LAMP)
	stage.throws = [{"id": "garden-throw", "mark": {"position_cm": [150, 100], "surface_id": "relay", "height_cm": 0, "radius_cm": 30}, "to": "garden-landing", "flight_ticks": 120, "catch_cm": 100}]
	stage.blocks = [
		{"block": "crank_bridge", "pads": [
			{"id": "relay-crank", "at": [-60, -100], "surface": "relay", "owner": "p0", "height": 0, "radius": 32},
			{"id": "garden-crank", "at": [640, -60], "surface": "east", "owner": "p0", "height": 0, "radius": 32}], "routes": ["relay-east"]},
		{"block": "ring_bell", "id": "garden-lamp", "at": LAMP, "surface": "east", "owner": "p1", "height": 0, "radius": 48, "style": "crest",
			"when": {"item_id": "seed", "spot_id": "garden"}}]
	return stage

## A plate @2's way: a pad either pip holds the bridge from.
static func _plate(id: String, at: Array, surface: String) -> Dictionary:
	return {"id": id, "at": at, "surface": surface, "owner": "p0", "height": 0, "radius": 32}

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}
