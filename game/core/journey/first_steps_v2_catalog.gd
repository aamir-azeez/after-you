extends RefCounted
## first-steps@2: First Steps on the shared journey rules, pinned to open turns
## with the new pieces (core/physical/pieces_rules.gd: 16, the tide rules with
## open controls and open turns, plus carried items and moving platforms), so
## a stage passes back and forth until both pips end a turn at its goal, up to
## its cap. first-steps@1 keeps its own engine (core/first_steps/) and replays
## unchanged. The same cottage garden in cm: the meadow shore, the plank loft
## 160 cm up and the little lift between them.
##   1 a-little-lift (orange first, the host's pip): the lift is a weight lift.
##     It stands at the loft while anyone stands on the power spot on the
##     shore or the winch spot on the loft, and at the shore otherwise, and
##     whoever stands on it rides. So one pip sends the other up from the
##     shore, and the one upstairs winds it back up for the other: both ring
##     the loft bell together. No seed yet: it is away (carried_items.gd),
##     so nothing shows that no one may take.
##   2 a-place-to-grow: the seed appears on the stone pedestal on the loft. The
##     pedestal is solid (core/solid_footprint.gd): pips walk round it and take
##     the seed from beside it, on any side. The garden lamp on the shore lights
##     once the seed rests in the garden planter beside it; both pips meet
##     there. The seed goes down either way: thrown from @1's marked edge of
##     the loft to the landing ring on the shore (a throw, carried_items.gd;
##     the other pip catches it there or it lands), or carried down the lift.
##     Both pips come down the same lift.
## Neither pip can do it alone (claude-20261011\first-steps-open\
## solver_first_steps.py; tests/test_level_checker.gd): one pip on a spot never
## rides, so each needs the other on the far spot.
## No player words here: the title and hints are the descriptor's copy and
## stage_copy, so changing them never changes the definition hash.
## The turn limits are development ones until the owner records runs
## (scripts/chapter_turn_limits.py).

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take: the first teaches the lift, ten; the ending, twenty.
const CAPS := {"a-little-lift": 10, "a-place-to-grow": 20}
const LOFT := 160
## The loft bell stands right of the pedestal, so its frame never hides the
## pedestal or the seed in the game camera's view, its ring clear of the
## pedestal's solid circle and the throw mark.
const BELL := [400, -40]
const LAMP := [-450, 130]

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "first-steps", "version": 2, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks":1800,"b_ticks":1800},
		"starts": {"p0": {"position_cm": [-420, -130], "height_cm": 0, "surface_id": "shore"}, "p1": {"position_cm": [-230, 0], "height_cm": 0, "surface_id": "shore"}},
		"props": [], "drops": [],
		# Away until the garden stage puts it on the pedestal.
		"items": [{"id": "seed", "at": "away"}],
		# The pedestal keeps @1's place and size: its drum (28 cm) is solid, and a
		# pip takes the seed from up to 20 cm off the drum's edge, on any side.
		"item_spots": [
			{"id": "seed-pedestal", "surface_id": "loft", "position_cm": [230, -90], "height_cm": LOFT, "radius_cm": 36, "solid": {"radius_cm": 28, "reach_cm": 20}},
			{"id": "garden", "surface_id": "shore", "position_cm": [-300, 130], "height_cm": 0, "radius_cm": 48},
			# The landing ring stands west of the planter, so its ticks clear it
			# (tests/test_level_checker.gd, pieces drawn into each other).
			{"id": "landing", "surface_id": "shore", "position_cm": [-370, -5], "height_cm": 0, "radius_cm": 66}],
		"islands": [{"id": "shore", "rect_cm": [-600, -240, -120, 240], "height_cm": 0}, {"id": "loft", "rect_cm": [80, -240, 500, 240], "height_cm": LOFT}],
		# The lift's two stops share @1's lift rectangle.
		"bridges": [{"id": "lift-low", "rect_cm": [-120, -90, 80, 90], "from_surface": "shore", "to_surface": "loft", "height_cm": 0},
			{"id": "lift-high", "rect_cm": [-120, -90, 80, 90], "from_surface": "shore", "to_surface": "loft", "height_cm": LOFT}],
		"stairs": [],
		"stages": [_lift(), _garden()]}

## Both start on the shore; the bell is on the loft.
static func _lift() -> Dictionary:
	var stage := _stage("a-little-lift", "p0", BELL)
	stage.blocks = [_weight_lift(), {"block": "ring_bell", "id": "loft-bell", "at": BELL, "surface": "loft", "owner": "p1", "height": LOFT, "radius": 36}]
	return stage

## Both start at the loft bell; the garden lamp is on the shore.
static func _garden() -> Dictionary:
	var stage := _stage("a-place-to-grow", "p1", LAMP)
	stage.item_starts = {"seed": "seed-pedestal"}
	# @1's throw: from the marked edge of the loft to the ring on the shore.
	stage.throws = [{"id": "seed-throw", "mark": {"position_cm": [140, -90], "surface_id": "loft", "height_cm": LOFT, "radius_cm": 30}, "to": "landing", "flight_ticks": 90, "catch_cm": 90}]
	stage.blocks = [_weight_lift(), {"block": "ring_bell", "id": "garden-lamp", "at": LAMP, "surface": "shore", "owner": "p1", "height": 0, "radius": 48,
		"when": {"item_id": "seed", "spot_id": "garden"}}]
	return stage

## The lift stands at the loft while a pip stands on either spot. Each spot
## is well away from the lift, so the pip holding it never rides.
static func _weight_lift() -> Dictionary:
	return {"block": "weight_lift", "id": "little-lift", "low": "lift-low", "high": "lift-high", "pads": [
		{"id": "lift-power", "at": [-300, -130], "surface": "shore", "owner": "p0", "height": 0, "radius": 36},
		{"id": "loft-winch", "at": [360, 110], "surface": "loft", "owner": "p0", "height": LOFT, "radius": 36}]}

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}
