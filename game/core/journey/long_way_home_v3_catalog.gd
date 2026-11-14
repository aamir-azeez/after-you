extends RefCounted
## long-way-home@3: long-way-home@2's definition as version 3, pinned to open
## controls and open turns (core/physical/open_turns.gd: 14), so it never
## shares a record with an earlier version, its controls carry no owner, and a
## stage passes back and forth until its window is lit, up to its cap. Its words are the descriptor's copy and stage_copy, never the
## definition's. It keeps long-way-home@2's turn limits: the open rules need no more.
const Earlier = preload("res://core/journey/long_way_home_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const WORDS := ["title", "subtitle", "hint_a", "hint_b"]
## The one crossing kept owned: open, the service stair would let the pip who
## plays second climb to the service landing and finish A Place Beside You alone,
## on any of its turns (tests/test_level_checker.gd, both pips).
const OWNED := ["service-up"]
## Turns a stage may take: the first stage teaches the path, ten; the ending's
## two windows and the porch take more arguing, twenty.
const CAPS := {"the-path-you-leave": 10, "a-place-beside-you": 20}

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition_v2().duplicate(true)
	level.version = 3
	OpenTurns.pin(level, CAPS)
	OpenControls.open_crossings(level, OWNED)
	for field: String in WORDS:
		level.erase(field)
		for stage: Dictionary in level.stages: stage.erase(field)
	return level
