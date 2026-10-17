extends RefCounted
## turn-of-the-tide@2: turn-of-the-tide@1's definition as version 2, pinned to
## rules 9, with a settled source (simulation.gd _settled): the second spirit's
## levers, wheels and crossings answer at once, against the harbour the first
## spirit left, and it waits for the memory only at the bell or the lantern.
const Earlier = preload("res://core/journey/turn_of_the_tide_catalog.gd")

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition()
	level.version = 2
	level.simulation_version = 9
	level["settled_source"] = true
	return level
