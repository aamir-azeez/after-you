extends RefCounted
## The swinging bucket, a generic journey hazard under the pieces rules (20,
## core/physical/pieces_rules.gd). It plays only where a stage declares it, so
## a rules 20 level without one plays exactly as before.
##
## A stage's "swings": [{"id", "pivot_cm": [x, z] (where its crane or hook
## stands, for the look only), "lane":
## {"surface_id", "rect_cm": [x0, z0, x1, z1]}, "period_ticks", "sweep_ticks",
## "warn_ticks", "offset_ticks", "brake": a when (optional), "outcome"}].
## Something hung from a pivot (an old crane's bucket, a lantern on a chain)
## swings across its lane on a steady beat of period_ticks. Each beat ends with
## sweep_ticks across the lane, after warn_ticks of warning (it draws back and
## creaks, its shadow grows on the lane); the rest of the beat it hangs back,
## out of the lane. A pip whose centre is in the lane, on the lane's floor or
## crossing, on a sweep tick is knocked off: "drowned" into the water beside it
## (the tide rules' drown, simulation.gd _check_hazards). Nothing in a swing
## names a level; its look is the "swing" piece slot.
##
## Timing is the simulation tick only. Each swing keeps one beat counter, in
## the world (runtime.gd save_world, so a carry-over turn starts from it) and
## in the state hash; it starts at 0 when the stage starts and the beat's
## phase is (counter + offset_ticks) % period_ticks. The counter goes up every
## tick unless the brake holds while the swing hangs back: then it waits there,
## so a brake held mid-swing stops it the next time it swings back, a parked
## swing is out of the lane (holding it never hurts anyone), and letting go
## always gives the full warning before the next sweep. The live pip, the
## friend's replay, the proof and the checks all count the same ticks.
##
## The level tools treat the lane as walkable (a pip may always wait for the
## beat) and the brake as a helper, so a swing never makes a stage two-pip.
## Pure static code shared by the engine, the catalogs, the blocks and the
## level tools; it preloads nothing.

## What a hit does: knocked into the water ("drowned"). A ledge's fall waits
## for the tide rules' fall outcome.
const OUTCOMES := ["drowned"]
const FIELDS := ["id", "pivot_cm", "lane", "period_ticks", "sweep_ticks", "warn_ticks", "offset_ticks", "outcome"]

## Whether `stage` declares swings.
static func declared(stage: Dictionary) -> bool:
	return not stage.get("swings", []).is_empty()

## Where in its beat `swing` is after `count` counted ticks.
static func phase(swing: Dictionary, count: int) -> int:
	return (count + int(swing.offset_ticks)) % int(swing.period_ticks)

## Whether `swing` is across its lane at `count`.
static func sweeping(swing: Dictionary, count: int) -> bool:
	return phase(swing, count) >= int(swing.period_ticks) - int(swing.sweep_ticks)

## Whether `swing` is drawing back to swing (creaking) at `count`.
static func warning(swing: Dictionary, count: int) -> bool:
	var at := phase(swing, count)
	var sweep_from := int(swing.period_ticks) - int(swing.sweep_ticks)
	return at < sweep_from and at >= sweep_from - int(swing.warn_ticks)

## Whether `swing` hangs back, out of its lane, at `count`.
static func resting(swing: Dictionary, count: int) -> bool:
	return phase(swing, count) < int(swing.period_ticks) - int(swing.sweep_ticks) - int(swing.warn_ticks)

## The counter after one more tick: it waits while braked and hanging back.
static func next_count(swing: Dictionary, count: int, braked: bool) -> int:
	return count if braked and resting(swing, count) else count + 1

## Whether `player` (x, z, surface_id) stands in `swing`'s lane.
static func in_lane(swing: Dictionary, player: Dictionary) -> bool:
	var lane: Dictionary = swing.lane
	var r: Array = lane.rect_cm
	return str(player.get("surface_id", "")) == str(lane.surface_id) and int(player.x) >= int(r[0]) and int(player.x) <= int(r[2]) and int(player.z) >= int(r[1]) and int(player.z) <= int(r[3])

## What the screen reads: {"phase", "held"} for `count`, held while braked and
## hanging back.
static func view(swing: Dictionary, count: int, braked: bool) -> Dictionary:
	return {"phase": phase(swing, count), "held": braked and resting(swing, count)}

## Every stage's swings that a level uses, as found messages ([] when none).
static func uses(level: Dictionary) -> Array:
	var found: Array = []
	for stage: Dictionary in level.get("stages", []):
		if declared(stage): found.append("swings on %s" % stage.id)
	return found

## Shapes the engine relies on: every swing names each field, its lane lies on
## a floor or crossing of the level, its beat has some time hanging back and
## its outcome is known. [] when sound.
static func problems(level: Dictionary) -> Array:
	var found: Array = []
	var floors: Dictionary = {}
	for kind: String in ["islands", "bridges", "stairs"]:
		for floor_: Dictionary in level.get(kind, []): floors[str(floor_.id)] = true
	for stage: Dictionary in level.get("stages", []):
		var seen: Dictionary = {}
		for swing: Variant in stage.get("swings", []):
			if not swing is Dictionary:
				found.append("%s: a swing must be a dictionary" % stage.id)
				continue
			var missing := FIELDS.filter(func(field: String) -> bool: return not swing.has(field))
			if not missing.is_empty():
				found.append("%s: swing %s needs %s" % [stage.id, swing.get("id", "?"), ", ".join(missing)])
				continue
			var id := str(swing.id)
			if seen.has(id): found.append("%s: swing %s is listed twice" % [stage.id, id])
			seen[id] = true
			var lane: Variant = swing.lane
			if not lane is Dictionary or not floors.has(str(lane.get("surface_id", ""))) or not lane.get("rect_cm") is Array or lane.rect_cm.size() != 4 or int(lane.rect_cm[2]) <= int(lane.rect_cm[0]) or int(lane.rect_cm[3]) <= int(lane.rect_cm[1]):
				found.append("%s: swing %s needs a lane rect on a floor or crossing of the level" % [stage.id, id])
			if not swing.pivot_cm is Array or swing.pivot_cm.size() != 2:
				found.append("%s: swing %s needs a pivot [x, z]" % [stage.id, id])
			var period := int(swing.period_ticks)
			var sweep := int(swing.sweep_ticks)
			var warn := int(swing.warn_ticks)
			if sweep < 1 or warn < 0 or period - sweep - warn < 1 or int(swing.offset_ticks) < 0:
				found.append("%s: swing %s needs a sweep, a warning and some time hanging back in its beat" % [stage.id, id])
			if str(swing.outcome) not in OUTCOMES: found.append("%s: swing %s has an unknown outcome %s" % [stage.id, id, swing.outcome])
			if swing.has("brake") and not swing.brake is Dictionary: found.append("%s: swing %s's brake must be a when" % [stage.id, id])
	return found
