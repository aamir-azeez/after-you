extends RefCounted
## conservatory@2: conservatory@1's definition as version 2, pinned to open
## controls and open turns (core/physical/open_turns.gd: 14), so it never
## shares a record with an earlier version, its controls carry no owner, and a
## stage passes back and forth until both pips end a turn in its lit garden, up to its cap.
## Its words are the descriptor's copy and stage_copy, never the
## definition's. Its turns are the fallback until the owner plays it: twice the longest carry-over witness turn, at least 60 s
## (60 s every turn; scripts/chapter_turn_limits.py --suggested).
##
## A Light Above: with open controls the second spirit could turn the court's
## two forks itself, light the top steps and finish alone. So the forks stand
## on a balcony over the court's west side, at the gallery's height, that only
## the first spirit reaches: it starts up there, and its one way down is a
## hatch on the balcony's west side, clear of the walk between the forks. The
## forks keep their places on the light's plane, so the light runs as before.
## The hatch is bolted from below (the owner, 2026-11-16: both pips work a
## control on every stage): a bolt lever on the court, west of the balcony,
## opens it, so the second spirit lets the first one down. The first turn ends
## at the hatch-wait spot on the balcony, beside the hatch. The second spirit
## walks under the balcony as it walks under the gallery.
##
## The Way Light Returns is @1's but for its return shutter: a pad in the
## lower room rather than a lever, so the shutter stays up only while someone
## stands on it, away from both returns: it holds the room return, and a
## second plate on the court holds the court return. One spirit holds a plate
## while the other turns the final mirror and comes back, by either door.
const Earlier = preload("res://core/journey/conservatory_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const WORDS := ["title", "subtitle", "hint_a", "hint_b"]
const BALCONY := "fork-balcony"
const BALCONY_HEIGHT := 160
## Over the court, around both forks (each 28 cm in radius).
const BALCONY_RECT := [-512, -400, -368, 176]
const FORKS := ["court-fork", "high-return"]
const START := [-416, -224]
const BOLT := {"id": "hatch-bolt", "position_cm": [-584, -48], "radius_cm": 28, "surface_id": "court", "height_cm": 0}
const HATCH := {"id": "balcony-hatch", "rect_cm": [-504, -24, -464, 24], "surface_id": BALCONY, "destination_surface": "court", "height_cm": 0, "requires_lever": "hatch-bolt"}
const SHUTTER := {"id": "return-shutter", "position_cm": [400, 224], "radius_cm": 28, "surface_id": "lower-room", "height_cm": 0}
const COURT_SHUTTER := {"id": "court-shutter", "position_cm": [-304, 272], "radius_cm": 28, "surface_id": "court", "height_cm": 0}
## No crossing is kept owned: a stage ends with both pips at its goal, so no
## pip finishes alone whatever it can reach (tests/test_level_checker.gd).
const OWNED := []
## Turns a stage may take: A Light Above, ten; the ending's two lights, twenty.
const CAPS := {"a-light-above": 10, "the-way-light-returns": 20}
## The balcony's timber posts, solid (Navigation obstacles on the court), 12 cm
## square: a pip walks round them, never through. Just inside its corners and
## halfway along, clear of the court's floor seams.
const POSTS := [[-496, -404], [-397, -404], [-496, -112], [-397, -112], [-496, 166], [-397, 166]]
const POST_CM := 12
const WAIT := {"id": "hatch-wait", "position_cm": [-432, -64], "surface_id": BALCONY, "height_cm": BALCONY_HEIGHT, "owner_slot": "p0", "radius_cm": 40}

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition().duplicate(true)
	level.version = 2
	OpenTurns.pin(level, CAPS)
	level.turn_limits = {"a_ticks":1800,"b_ticks":1800}
	OpenControls.open_crossings(level, OWNED)
	for field: String in WORDS:
		level.erase(field)
		for stage: Dictionary in level.stages: stage.erase(field)
	level.islands.append({"id": BALCONY, "rect_cm": BALCONY_RECT.duplicate(), "height_cm": BALCONY_HEIGHT})
	level.drops.append(HATCH.duplicate(true))
	var obstacles: Array = level.get_or_add("obstacles", [])
	for index in range(POSTS.size()):
		var at: Array = POSTS[index]
		var half := POST_CM / 2
		obstacles.append({"id": "balcony-post-%d" % (index + 1), "rect_cm": [at[0] - half, at[1] - half, at[0] + half, at[1] + half], "surface_id": "court"})
	level.starts.p0 = {"position_cm": START.duplicate(), "height_cm": BALCONY_HEIGHT, "surface_id": BALCONY}
	var first: Dictionary = level.stages[0]
	for control: Dictionary in first.controls:
		if control.id in FORKS:
			control.surface_id = BALCONY
			control.height_cm = BALCONY_HEIGHT
	first.levers.append(BOLT.duplicate(true))
	first.source_policy["endpoint"] = WAIT.duplicate(true)
	var returns: Dictionary = level.stages[1]
	returns.levers = returns.levers.filter(func(lever: Dictionary) -> bool: return lever.id != SHUTTER.id)
	returns.pressure_pads.append(SHUTTER.duplicate(true))
	returns.pressure_pads.append(COURT_SHUTTER.duplicate(true))
	for gate: Dictionary in returns.gates:
		if gate.get("when", {}) == {"lever_id": SHUTTER.id}: gate.when = {"pad_id": COURT_SHUTTER.id if gate.route_id == "court-return" else SHUTTER.id}
	return level
