extends RefCounted
## a-house-for-two@2: a-house-for-two@1's definition as version 2 on open
## turns with the shared ball (core/physical/open_turns.gd pins a level with a
## ball to 17, runtime.gd _shared_ball), so it never shares a record with an
## earlier version, its controls carry no owner, either pip pushes the ball in
## any turn, live or as a memory, and a stage passes back and forth until both
## pips end a turn at its bell, up to its cap. Its turns are development
## limits, 120 seconds every turn, to explore while the owner records; the
## release step sets the owner's numbers (scripts/chapter_turn_limits.py). Its
## in-play hints are @1's own (the cooperative family's stage_hud is authored).
##
## The ball is still the idea; only what open play needs changed. Open the
## House: the ball still opens the way into the workshop and, on the stair
## weight, the loft stairs, but the stairs now need a pip on the workshop step
## (away from them) where they needed the workshop lever, so one holds them
## while the other climbs, and a lever at the top of the stairs lets the
## holder up. The Room Below: the passage to the lower hall now opens for a
## pip on the hall step (away from it) where it opened with the loft lever,
## which still opens the hatch, so one drops into the hall and holds the
## passage while the other rolls the ball through to the sunroom weight. The
## hand-off mark is gone (no offer or claim on the shared ball).
const Earlier = preload("res://core/cooperative/house_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
## No crossing is kept owned: no stage can be finished by one pip whatever it reaches.
const OWNED := []
## Turns a stage may take: ten each, as each stage teaches one idea.
const CAPS := {"open-the-house": 10, "the-room-below": 10}
const WORKSHOP_STEP := {"id": "workshop-step", "position_cm": [-64, 208], "surface_id": "workshop", "radius_cm": 32}
const STAIR_LEVER := {"id": "stair-top-lever", "position_cm": [432, -208], "surface_id": "loft", "radius_cm": 28}
const HALL_STEP := {"id": "hall-step", "position_cm": [640, -192], "surface_id": "lower-hall", "radius_cm": 32}

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition().duplicate(true)
	level.version = 2
	OpenTurns.pin(level, CAPS)
	level.turn_limits = {"a_ticks": 3600, "b_ticks": 3600}
	OpenControls.open_crossings(level, OWNED)
	var house: Dictionary = level.stages[0]
	house.pressure_pads = [WORKSHOP_STEP.duplicate(true)]
	house.levers.append(STAIR_LEVER.duplicate(true))
	for gate: Dictionary in house.gates:
		if gate.route_id == "loft-stairs":
			gate.lever_id = ""
			gate.pad_id = WORKSHOP_STEP.id
	house.gates.append({"route_id": "loft-stairs", "pad_id": "", "ball_pad_id": "", "lever_id": STAIR_LEVER.id})
	house.source_policy = {"kind": "hold_switch", "pad_id": WORKSHOP_STEP.id, "prop_id": "house-ball", "minimum_hold_ticks": 15}
	var below: Dictionary = level.stages[1]
	below.erase("handoff")
	below.pressure_pads = [HALL_STEP.duplicate(true)]
	for gate: Dictionary in below.gates:
		if gate.route_id == "lower-hall-passage":
			gate.lever_id = ""
			gate.pad_id = HALL_STEP.id
	below.source_policy = {"kind": "hold_switch", "pad_id": HALL_STEP.id, "prop_id": "house-ball", "minimum_hold_ticks": 15}
	return level
