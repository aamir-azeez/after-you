extends RefCounted
## the-wishing-well@2: the-wishing-well@1's definition as version 2, pinned to
## open turns (core/physical/open_turns.gd: 14 after the comfort alias 9), so
## it never shares a record with an earlier version, its controls carry no
## owner, and a stage passes back and forth until both pips end a turn at its
## bell, up to its cap. Its turn limits are the development ones
## (content/chapters/index.gd DEVELOPMENT_TURN_LIMITS, the same for every
## turn) until play sets them (scripts/chapter_turn_limits.py). A cooperative
## chapter's in-play hints are its stages' own (the family's stage_hud is
## authored), so they stay in the definition.
##
## What open turns change, and why (ADDING-A-CHAPTER, Designing for open turns):
## - No crossing or zone is owned. The well lip is open to both, so either pip
##   may hop down.
## - Go On Ahead: both pips now end at the lookout, so the one who held the
##   bucket rope climbs back out. The garden gate is a step held in the garden,
##   away from the cliff steps, so the one holding it cannot climb too (it was
##   a lever only the first pip worked, on steps only the first pip used). Up on
##   the cliff a ladder step lowers the rope ladder and the rope-walks while it
##   is held, so the one in the well climbs out to the tower and walks back
##   over the ropes. It is a step, not a winch, so nothing it opens stays open
##   into Back for You (a stage keeps the crossings open at its end).
## - Back for You: both start at the lookout, so one hops down again and holds
##   the rope while the other crosses to the winch. The tower step is gone: it
##   only marked where the first turn waited, and open turns have no such wait.
const Earlier = preload("res://core/cooperative/wishing_well_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
## No crossing is kept owned: a stage ends with both pips at its bell, so no
## pip finishes alone whatever it can reach (tests/test_level_checker.gd).
const OWNED := []
## Turns a stage may take: the first stage, ten; the ending, twenty.
const CAPS := {"go-on-ahead": 10, "back-for-you": 20}
const GATE_STEP := {"id": "gate-step", "position_cm": [-1104, 192], "surface_id": "garden", "radius_cm": 32}
const LADDER_STEP := {"id": "ladder-step", "position_cm": [1040, -176], "surface_id": "cliff", "radius_cm": 32}

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition().duplicate(true)
	level.version = 2
	OpenTurns.pin(level, CAPS)
	level.turn_limits = {"a_ticks":2730,"b_ticks":2730}
	OpenControls.open_crossings(level, OWNED)
	level.erase("access_zones")
	var ahead: Dictionary = level.stages[0]
	ahead.levers = []
	ahead.pressure_pads.append(GATE_STEP.duplicate(true))
	ahead.pressure_pads.append(LADDER_STEP.duplicate(true))
	ahead.gates = [_gate("cliff-steps", GATE_STEP.id), _gate("long-stair", "bucket-rope"),
		_gate("well-ladder", LADDER_STEP.id), _gate("rope-walk-west", LADDER_STEP.id), _gate("rope-walk-east", LADDER_STEP.id)]
	ahead.source_policy.lever_id = ""
	var back: Dictionary = level.stages[1]
	back.pressure_pads = back.pressure_pads.filter(func(pad: Dictionary) -> bool: return pad.id != "tower-step")
	back.source_policy.pad_id = "still-holding"
	return level

static func _gate(route: String, pad: String) -> Dictionary:
	return {"route_id": route, "pad_id": pad, "lever_id": "", "ball_pad_id": ""}
