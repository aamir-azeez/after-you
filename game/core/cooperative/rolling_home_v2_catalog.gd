extends RefCounted
## rolling-home@2: rolling-home@1's definition as version 2 on open turns with
## the shared ball (core/physical/open_turns.gd pins a level with a ball to 17,
## runtime.gd _shared_ball), so it never shares a record with an earlier
## version, its controls carry no owner, either pip pushes the ball in any
## turn, live or as a memory, and a stage passes back and forth until it ends:
## both pips at the far bell, then the ball in its cradle with both pips home.
## Its turns are the fallback until the owner plays it: twice the longest
## carry-over witness turn, at least 60 s (60 s every turn;
## scripts/chapter_turn_limits.py --suggested). Its in-play hints are @1's own (the
## cooperative family's stage_hud is authored).
##
## The ball is still the idea; only what open play needs changed. Weight of a
## Friend: the shore bridge lowers for a pip on the shore step, away from it,
## so one holds it while the other rolls the ball over onto the heavy pad,
## which now sits across on the middle island and holds the bridge for the
## one left behind (and with the lever, the far bridge, as before). Bring It
## Home: the home bridge lowers for a pip on the far step, away from it, so one
## holds it while the other rolls the ball over onto the home pad, which holds
## it for the one left behind; then the ball goes in its cradle. The two
## levers that opened the home bridge are gone (either pip could pull both),
## and so are the far bank's two pip lanes (hidden per-pip ownership) and the
## hand-off mark (no offer or claim on the shared ball).
## The family catalog preloads this one, so @1's definition is loaded here, not preloaded.
const EARLIER := "res://core/cooperative/stage_catalog.gd"
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
## No crossing is kept owned: no stage can be finished by one pip whatever it reaches.
const OWNED := []
## Turns a stage may take: ten each, as each stage teaches one idea.
const CAPS := {"weight-of-a-friend": 10, "bring-it-home": 10}
const SHORE_STEP := {"id": "shore-step", "position_cm": [-560, -128], "surface_id": "shore", "radius_cm": 32}
const HEAVY_PAD := {"id": "heavy-pad", "position_cm": [16, 0], "surface_id": "middle", "radius_cm": 36, "prop_id": "round-ball"}
const FAR_STEP := {"id": "far-step", "position_cm": [608, 160], "surface_id": "far-bank", "radius_cm": 32}
const HOME_PAD := {"id": "home-pad", "position_cm": [1232, 128], "surface_id": "home", "radius_cm": 36, "prop_id": "round-ball"}

static func definition() -> Dictionary:
	var level: Dictionary = load(EARLIER).definition("rolling-home@1").duplicate(true)
	level.version = 2
	OpenTurns.pin(level, CAPS)
	level.turn_limits = {"a_ticks":1800,"b_ticks":1800}
	OpenControls.open_crossings(level, OWNED)
	level.access_zones = []
	var friend: Dictionary = level.stages[0]
	friend.pressure_pads = [SHORE_STEP.duplicate(true)]
	friend.ball_pads = [HEAVY_PAD.duplicate(true)]
	friend.gates.append(_gate("shore-middle", SHORE_STEP.id))
	friend.source_policy = {"kind": "hold_switch", "pad_id": SHORE_STEP.id, "prop_id": "round-ball", "minimum_hold_ticks": 15}
	var home: Dictionary = level.stages[1]
	home.erase("handoff")
	home.levers = []
	home.pressure_pads = [FAR_STEP.duplicate(true)]
	home.ball_pads = [HOME_PAD.duplicate(true)]
	home.gates = [_gate("far-home", FAR_STEP.id), _gate("far-home", "", HOME_PAD.id)]
	home.source_policy = {"kind": "hold_switch", "pad_id": FAR_STEP.id, "prop_id": "round-ball", "minimum_hold_ticks": 15}
	return level

static func _gate(route: String, pad: String, ball_pad: String = "") -> Dictionary:
	return {"route_id": route, "pad_id": pad, "lever_id": "", "ball_pad_id": ball_pad}
