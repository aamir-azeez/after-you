extends RefCounted
## conservatory@2: conservatory@1's definition as version 2, pinned to the open
## controls (core/physical/open_controls.gd: 13 after the tide rules, else 12),
## so it never shares a record with an earlier version, and its controls carry
## no owner. Its words are the descriptor's copy and stage_copy, never the
## definition's. It keeps conservatory@1's turn limits: the open rules need no more.
##
## A Light Above: with open controls the second spirit could turn the court's
## two forks itself, light the top steps and finish alone. So the forks stand
## on a balcony over the court's west side, at the gallery's height, that only
## the first spirit reaches: it starts up there, and its one way down is a
## hatch on the balcony's west side, clear of the walk between the forks. The
## forks keep their places on the light's plane, so the light runs as before.
## The first turn ends at the court-wait spot, on the court just east of the
## balcony, as @1's ended on the court below the second fork. The second
## spirit walks under the balcony as it walks under the gallery. The second
## stage is @1's.
const Earlier = preload("res://core/journey/conservatory_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const WORDS := ["title", "subtitle", "hint_a", "hint_b"]
const BALCONY := "fork-balcony"
const BALCONY_HEIGHT := 160
## Over the court, around both forks (each 28 cm in radius).
const BALCONY_RECT := [-512, -400, -368, 176]
const FORKS := ["court-fork", "high-return"]
const START := [-416, -224]
const HATCH := {"id": "balcony-hatch", "rect_cm": [-504, -24, -464, 24], "surface_id": BALCONY, "destination_surface": "court", "height_cm": 0}
const WAIT := {"id": "court-wait", "position_cm": [-336, -352], "surface_id": "court", "height_cm": 0, "owner_slot": "p0", "radius_cm": 40}

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition().duplicate(true)
	level.version = 2
	OpenControls.pin(level)
	for field: String in WORDS:
		level.erase(field)
		for stage: Dictionary in level.stages: stage.erase(field)
	level.islands.append({"id": BALCONY, "rect_cm": BALCONY_RECT.duplicate(), "height_cm": BALCONY_HEIGHT})
	level.drops.append(HATCH.duplicate(true))
	level.starts.p0 = {"position_cm": START.duplicate(), "height_cm": BALCONY_HEIGHT, "surface_id": BALCONY}
	var first: Dictionary = level.stages[0]
	for control: Dictionary in first.controls:
		if control.id in FORKS:
			control.surface_id = BALCONY
			control.height_cm = BALCONY_HEIGHT
	first.source_policy["endpoint"] = WAIT.duplicate(true)
	return level
