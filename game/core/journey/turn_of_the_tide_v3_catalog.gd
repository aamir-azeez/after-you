extends RefCounted
## turn-of-the-tide@3: turn-of-the-tide@2's definition as version 3, pinned to the open
## controls (core/physical/open_controls.gd: 13 after the tide rules, else 12),
## so it never shares a record with an earlier version, and its controls carry
## no owner. Its words are the descriptor's copy and stage_copy, never the
## definition's. It keeps turn-of-the-tide@2's turn limits: the open rules need no more.
const Earlier = preload("res://core/journey/turn_of_the_tide_v2_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const WORDS := ["title", "subtitle", "hint_a", "hint_b"]
## The crossings kept owned: open, the mill ladder would let the second pip
## climb to the mill terrace and finish Set the Tide alone, and the gate and
## quay catwalks would let it reach the first pip's part of Slack Water and
## finish it alone. Every other crossing opens to both pips.
const OWNED := ["mill-ladder", "gate-catwalk", "quay-catwalk"]

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition().duplicate(true)
	level.version = 3
	OpenControls.pin(level)
	OpenControls.open_crossings(level, OWNED)
	for field: String in WORDS:
		level.erase(field)
		for stage: Dictionary in level.stages: stage.erase(field)
	return level
