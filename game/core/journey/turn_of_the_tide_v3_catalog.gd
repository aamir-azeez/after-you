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

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition().duplicate(true)
	level.version = 3
	OpenTurns.pin(level, CAPS)
	OpenControls.open_crossings(level, OWNED)
	for field: String in WORDS:
		level.erase(field)
		for stage: Dictionary in level.stages: stage.erase(field)
	return level
