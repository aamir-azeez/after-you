extends RefCounted
## turn-of-the-tide@3: turn-of-the-tide@2's definition as version 3, pinned to open
## controls and open turns after the tide rules (core/physical/open_turns.gd:
## 15), so it never shares a record with an earlier version, its controls carry
## no owner, and a stage passes back and forth until both pips end a turn at its goal,
## up to its cap. Its words are the descriptor's copy and stage_copy, never the
## definition's. It keeps turn-of-the-tide@2's turn limits: the open rules need no more.
const Earlier = preload("res://core/journey/turn_of_the_tide_v2_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const WORDS := ["title", "subtitle", "hint_a", "hint_b"]
## No crossing is kept owned: a stage ends with both pips at its goal, so no
## pip finishes alone whatever it can reach (tests/test_level_checker.gd).
const OWNED := []
## Turns a stage may take: Set the Tide, ten; Slack Water, the ending, with
## its closing crossings and three ways over, twenty.
const CAPS := {"set-the-tide": 10, "slack-water": 20}
## Both pips work a control on every stage (the owner, 2026-11-16; the
## checker's "presses alone" probe, tests/test_level_checker.gd): the first
## one over is let across by the other, then lets the other across from the
## far side. Set the Tide: the slipway holds only while someone stands on the
## wheel step, as the gangway does for the bollard, and the last stepping
## stones are barred from the rock side (the stone bar, a bolt on the rock
## terrace beside them). Slack Water: the boom and the punt hold only while
## someone stands on their posts, and the sea key hangs on the mole, beside
## the gate it unlocks, so the first one over opens the sea gate for the other.
const STONE_BAR := {"id": "stone-bar", "position_cm": [1400, 88], "radius_cm": 28, "surface_id": "r-terrace", "height_cm": 48}
const HELD := {"set-the-tide": {"slipway": "wheel-step-pad"}, "slack-water": {"boom-jetty": "boom-post-pad", "punt-ferry": "punt-post-pad"}}
const SEA_KEY := {"position_cm": [-768, 80], "surface_id": "mole-terrace", "height_cm": 48}
## The bollard line stands two flags west of @2's spot, so the gangway lever
## and its lamp in front no longer draw over the line's housing on screen
## (tests/test_level_checker.gd, controls drawn into each other).
const LINE := {"position_cm": [1024, -448]}
## The basin valve stands 80 cm east of @2's spot, so its dial no longer
## stands over the gate bar and its lamp on the catwalk behind it.
const BASIN := {"position_cm": [-232, -64]}

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition().duplicate(true)
	level.version = 3
	OpenTurns.pin(level, CAPS)
	OpenControls.open_crossings(level, OWNED)
	for field: String in WORDS:
		level.erase(field)
		for stage: Dictionary in level.stages: stage.erase(field)
	for stage: Dictionary in level.stages:
		var held: Dictionary = HELD[stage.id]
		for gate: Dictionary in stage.gates:
			if held.has(gate.route_id): gate.when.all.append({"pad_id": held[gate.route_id]})
	var first: Dictionary = level.stages[0]
	first.levers.append(STONE_BAR.duplicate(true))
	for gate: Dictionary in first.gates:
		if gate.route_id == "stones-3": gate.when.all.append({"lever_id": STONE_BAR.id})
	for lever: Dictionary in first.levers:
		if lever.id == "line": lever.merge(LINE, true)
	for lever: Dictionary in level.stages[1].levers:
		if lever.id == "sea-key": lever.merge(SEA_KEY, true)
	for control: Dictionary in level.stages[1].controls:
		if control.id == "basin": control.merge(BASIN, true)
	return level
