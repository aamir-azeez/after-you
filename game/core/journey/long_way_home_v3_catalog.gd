extends RefCounted
## long-way-home@3: long-way-home@2's definition as version 3, pinned to open
## controls and open turns (core/physical/open_turns.gd: 14), so it never
## shares a record with an earlier version, its controls carry no owner, and a
## stage passes back and forth until both pips end a turn at its window, up to its cap.
## Its words are the descriptor's copy and stage_copy, never the
## definition's. Its turns are the fallback until the owner plays it: twice the longest carry-over witness turn, at least 60 s
## (60 s every turn; scripts/chapter_turn_limits.py --suggested).
const Earlier = preload("res://core/journey/long_way_home_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const WORDS := ["title", "subtitle", "hint_a", "hint_b"]
## No crossing is kept owned: a stage ends with both pips at its goal, so no
## pip finishes alone whatever it can reach (tests/test_level_checker.gd).
const OWNED := []
## Turns a stage may take: the first stage teaches the path, ten; the ending's
## two windows and the porch take more arguing, twenty.
const CAPS := {"the-path-you-leave": 10, "a-place-beside-you": 20}
## Both pips work a control on every stage (the owner, 2026-11-16; the
## checker's "presses alone" probe, tests/test_level_checker.gd). The Path
## You Leave: the friend's crossing has a gate at the bank end too, worked by
## a lever on the bank, so the first pip turns the path selector on the
## landing and the second opens its own gate. A second way off the bank, the
## bank steps across the water to the court, opens with the same bank gate and
## a gate lever on the court: more ways to meet, still one key from each side.
## A Place Beside You: the window
## lights only with the porch shutter down as well as the lamp and the gate
## matching, and the porch is reached only while someone stands at the near
## window inside, so one pip holds the window while the other lowers the
## shutter.
const BANK_GATE := {"id": "bank-gate", "position_cm": [-320, 336], "radius_cm": 28, "surface_id": "partner-bank", "height_cm": 0}
const BANK_STEPS := {"id": "bank-steps", "rect_cm": [-544, 160, -448, 224], "from_surface": "source-court", "to_surface": "partner-bank", "height_cm": 0}
const COURT_GATE := {"id": "court-gate", "position_cm": [-400, 112], "radius_cm": 28, "surface_id": "source-court", "height_cm": 0}
const MATCHED := {"any": [{"all": [{"control_id": "hall-lamp", "value": "rose"}, {"control_id": "walk-gate", "value": "rose"}]}, {"all": [{"control_id": "hall-lamp", "value": "moss"}, {"control_id": "walk-gate", "value": "moss"}]}]}

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition_v2().duplicate(true)
	level.version = 3
	OpenTurns.pin(level, CAPS)
	level.turn_limits = {"a_ticks":1800,"b_ticks":1800}
	OpenControls.open_crossings(level, OWNED)
	for field: String in WORDS:
		level.erase(field)
		for stage: Dictionary in level.stages: stage.erase(field)
	level.bridges.append(BANK_STEPS.duplicate(true))
	var path: Dictionary = level.stages[0]
	path.levers.append(BANK_GATE.duplicate(true))
	path.levers.append(COURT_GATE.duplicate(true))
	path.gates.append({"route_id": BANK_STEPS.id, "when": {"all": [{"lever_id": COURT_GATE.id}, {"lever_id": BANK_GATE.id}]}})
	for gate: Dictionary in path.gates:
		if gate.route_id == "friend-crossing": gate.when.all.append({"lever_id": BANK_GATE.id})
	level.stages[1].goal_policy.when = {"all": [{"control_id": "porch-shutter", "value": "down"}, MATCHED.duplicate(true)]}
	return level
