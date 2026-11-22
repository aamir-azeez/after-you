extends RefCounted
## high-and-low@2: high-and-low@1's definition as version 2, pinned to open
## controls and open turns (core/physical/open_turns.gd: 14), so it never
## shares a record with an earlier version, its controls carry no owner, and a
## stage passes back and forth until both pips end a turn at its bell, up to
## its cap. Its turns are the fallback until the owner plays it: twice the
## longest carry-over witness turn, at least 60 s (60 s every turn;
## scripts/chapter_turn_limits.py --suggested). Its in-play hints are @1's own (the
## cooperative family's stage_hud is authored).
##
## Both pips finish at the bell, so each stage's one way across needs a way
## back for the pip that held it open. Upper Path: the blue stair still opens
## for a pip on the shore switch with the shore lever on, and a lever at the
## top of the stair opens it from the loft too, so whoever climbs first lets
## the other one up. Down and Around: the red passage still opens for a pip on
## the ledge switch with the loft lever on, and a lever in the garden opens it
## from the far side, so whoever crosses first lets the other one through.
## Each pip works a lever only it can reach (the checker's "presses alone",
## tests/test_level_checker.gd).
## The family catalog preloads this one, so @1's definition is loaded here, not preloaded.
const EARLIER := "res://core/cooperative/stage_catalog.gd"
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
## No crossing is kept owned: a stage ends with both pips at its bell, so no
## pip finishes alone whatever it can reach.
const OWNED := []
## Turns a stage may take: ten each, as both stages teach one idea.
const CAPS := {"upper-path": 10, "down-and-around": 10}
const STAIR_LEVER := {"id": "stair-top-lever", "position_cm": [-16, -128], "surface_id": "loft", "radius_cm": 28}
const GARDEN_LEVER := {"id": "garden-lever", "position_cm": [800, -112], "surface_id": "garden", "radius_cm": 28}

static func definition() -> Dictionary:
	var level: Dictionary = load(EARLIER).definition("high-and-low@1").duplicate(true)
	level.version = 2
	OpenTurns.pin(level, CAPS)
	level.turn_limits = {"a_ticks":1800,"b_ticks":1800}
	OpenControls.open_crossings(level, OWNED)
	var upper: Dictionary = level.stages[0]
	upper.levers.append(STAIR_LEVER.duplicate(true))
	upper.gates.append({"route_id": "blue-stair", "pad_id": "", "lever_id": STAIR_LEVER.id, "ball_pad_id": ""})
	var down: Dictionary = level.stages[1]
	down.levers.append(GARDEN_LEVER.duplicate(true))
	down.gates.append({"route_id": "red-passage", "pad_id": "", "lever_id": GARDEN_LEVER.id, "ball_pad_id": ""})
	return level
