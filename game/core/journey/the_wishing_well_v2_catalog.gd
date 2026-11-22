extends RefCounted
## the-wishing-well@2: the Wishing Well on the shared journey rules, pinned to
## open turns with the new pieces (core/physical/pieces_rules.gd: 20), so a
## stage passes back and forth until both pips end a turn at its bell, up to
## its cap, and thrown and carried items play. the-wishing-well@1 keeps the
## cooperative engine and replays unchanged. Same well, rope and story in
## shorter walks: the west end is 7.2 m further in (the cliff steps, the gate
## step and the starts move with it), the tower ends just past the winch, and
## the garden has a stream with a plank over it.
##   1 go-on-ahead (the host's pip first): a step in the garden holds the cliff
##     steps, the bucket rope at the bottom of the well holds the long stair,
##     and the ladder step beside the lookout bell lowers the rope ladder out of
##     the well and the rope-walks back; whoever holds it steps across to the
##     bell once the other is over the ropes (under the bell itself the step and
##     the bell would draw into each other, tests/test_level_checker.gd). An old crane at the cliff edge swings its bucket across the
##     garden plank on a steady beat (core/physical/swings.gd): a pip on the
##     plank as it swings is knocked into the stream. The brake board on the
##     cliff path above parks it the next time it swings back, while someone
##     stands there; else the one in the garden dodges on the beat.
##   2 back-for-you: the winch has lost its handle, which lies at the bottom of
##     the well. One hops in and holds the rope (the rope-walks come down),
##     picks the handle up and throws it from the mark to the landing by the
##     winch (carried_items.gd throws); the other catches it or picks it up
##     and fits it in the winch, which then holds the rope ladder and the
##     rope-walks down. The ladder and the rope-walks need both hands, so the
##     handle only goes up by the throw.
## Neither pip can do either stage alone (tests/test_level_checker.gd; the
## design solver claude-20261011\wishing-well-redesign\solve.py). No player
## words here: the title and hints are the descriptor's copy and stage_copy.

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take.
const CAPS := {"go-on-ahead": 10, "back-for-you": 10}
const CLIFF := 160
## The lookout bell, and the ladder step a metre west of it, so the step's
## board and the bell's frame stand clear of each other.
const LOOKOUT := [1160, -96]
const LADDER_STEP := [1060, -96]
const REUNION := [1616, 16]
## The garden plank over the stream, which the crane's bucket sweeps.
const PLANK := [150, 188, 250, 252]

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "the-wishing-well", "version": 2, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks":1800,"b_ticks":1800},
		"starts": {"p0": _at([-496, 200], "garden", 0), "p1": _at([-448, 232], "garden", 0)},
		"props": [],
		"items": [{"id": "handle", "at": "well-bottom"}],
		"item_spots": [
			{"id": "well-bottom", "surface_id": "well-floor", "position_cm": [1180, 28], "height_cm": 0, "radius_cm": 24},
			{"id": "winch-landing", "surface_id": "tower", "position_cm": [2060, -40], "height_cm": CLIFF, "radius_cm": 66},
			# The winch is solid: a pip fits the handle from beside it, on any side.
			{"id": "winch", "surface_id": "tower", "position_cm": [2140, -144], "height_cm": CLIFF, "radius_cm": 30, "solid": {"radius_cm": 22, "reach_cm": 20}}],
		"islands": [
			_island("garden", [-560, 144, 150, 288], 0),
			_island("garden-east", [250, 144, 1040, 288], 0),
			_island("cliff", [-560, -208, 1232, -16], CLIFF),
			_island("well-floor", [1120, -48, 1200, 48], 0),
			_island("rope-rock", [1376, -192, 1424, -96], CLIFF),
			_island("tower", [1568, -208, 2240, 48], CLIFF)],
		"bridges": [
			{"id": "garden-plank", "rect_cm": PLANK, "from_surface": "garden", "to_surface": "garden-east", "height_cm": 0},
			_rope("rope-walk-west", [1232, -176, 1376, -112], "cliff", "rope-rock"),
			_rope("rope-walk-east", [1424, -176, 1568, -112], "rope-rock", "tower")],
		"stairs": [
			_stair("cliff-steps", [-528, -16, -464, 144], "z", "cliff", "garden", CLIFF, 0),
			_stair("long-stair", [944, -16, 1008, 144], "z", "cliff", "garden-east", CLIFF, 0),
			# The rope ladder out of the well needs both hands.
			_stair("well-ladder", [1200, -8, 1568, 40], "x", "well-floor", "tower", 0, CLIFF).merged({"hands": true})],
		# Every centre inside the mouth lands fully on the well floor below.
		"drops": [{"id": "well-mouth", "rect_cm": [1132, -36, 1188, -28], "surface_id": "cliff", "destination_surface": "well-floor", "height_cm": 0}],
		"obstacles": [
			{"id": "standing-stone-4", "rect_cm": [704, -208, 768, -88], "surface_id": "cliff"},
			{"id": "garden-bed-4", "rect_cm": [576, 208, 640, 288], "surface_id": "garden-east"},
			{"id": "rope-drum-1", "rect_cm": [1920, -208, 1984, -64], "surface_id": "tower"}],
		"stages": [_go_on_ahead(), _back_for_you()]}

## Both start in the garden; the lookout bell is on the cliff over the well.
static func _go_on_ahead() -> Dictionary:
	var stage := _stage("go-on-ahead", "p0", LOOKOUT)
	stage.blocks = [
		{"block": "hold_door", "pad": _step("gate-step", [-384, 192], "garden", 0, 32), "routes": ["cliff-steps"]},
		# The whole well floor lies inside the rope's reach, wherever the pip stands.
		{"block": "hold_door", "pad": _step("bucket-rope", [1160, 0], "well-floor", 0, 48), "routes": ["long-stair"]},
		{"block": "hold_door", "pad": _step("ladder-step", LADDER_STEP, "cliff", CLIFF, 32), "routes": ["well-ladder", "rope-walk-west", "rope-walk-east"]},
		{"block": "open_route", "routes": ["garden-plank"]},
		# The crane stands in the gap below the cliff edge, its bucket over the plank.
		{"block": "swinging_bucket", "id": "well-crane", "pivot": [200, 40], "lane": {"surface": "garden-plank", "rect": PLANK},
			"brake": _step("brake-board", [200, -72], "cliff", CLIFF, 32)},
		{"block": "ring_bell", "id": "lookout-bell", "at": LOOKOUT, "surface": "cliff", "owner": "p1", "height": CLIFF, "radius": 28}]
	return stage

## Both start at the lookout bell; the reunion bell is on the tower.
static func _back_for_you() -> Dictionary:
	var stage := _stage("back-for-you", "p1", REUNION)
	stage.item_starts = {"handle": "well-bottom"}
	stage.throws = [{"id": "handle-throw", "mark": {"position_cm": [1148, -12], "surface_id": "well-floor", "height_cm": 0, "radius_cm": 30}, "to": "winch-landing", "flight_ticks": 120, "catch_cm": 100}]
	var fitted := {"item_id": "handle", "spot_id": "winch"}
	stage.blocks = [
		# The rope at the bottom of the well, as yesterday: the pip still holding it.
		{"block": "pad", "id": "still-holding", "at": [1160, 0], "surface": "well-floor", "owner": "p0", "height": 0, "radius": 48},
		{"block": "raw", "gates": [
			{"route_id": "rope-walk-west", "when": {"any": [{"pad_id": "still-holding"}, fitted]}},
			{"route_id": "rope-walk-east", "when": {"any": [{"pad_id": "still-holding"}, fitted]}},
			{"route_id": "well-ladder", "when": fitted}]},
		{"block": "ring_bell", "id": "reunion-bell", "at": REUNION, "surface": "tower", "owner": "p0", "height": CLIFF, "radius": 28}]
	return stage

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}

static func _at(position: Array, surface: String, height: int) -> Dictionary:
	return {"position_cm": position, "height_cm": height, "surface_id": surface}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id": id, "rect_cm": rect, "height_cm": height}

## A rope-walk at the cliff's height: both hands on the ropes.
static func _rope(id: String, rect: Array, from: String, to: String) -> Dictionary:
	return {"id": id, "rect_cm": rect, "from_surface": from, "to_surface": to, "height_cm": CLIFF, "hands": true}

static func _stair(id: String, rect: Array, axis: String, from: String, to: String, from_height: int, to_height: int) -> Dictionary:
	return {"id": id, "rect_cm": rect, "axis": axis, "from_surface": from, "to_surface": to, "from_height_cm": from_height, "to_height_cm": to_height}

static func _step(id: String, at: Array, surface: String, height: int, radius: int) -> Dictionary:
	return {"id": id, "at": at, "surface": surface, "owner": "p0", "height": height, "radius": radius}
