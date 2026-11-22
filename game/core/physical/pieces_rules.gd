extends RefCounted
## The new pieces of The Falls and Fog Marsh (rules 20, open_controls.gd
## PIECES_RULES_VERSION): the tide rules with open controls and open turns
## (19) plus these, all read from the stage or its crossings, none adding state
## of its own (the server's checkpoint keeps its four mechanisms):
## - "not" in a gate's `when` (core/journey/seven_mechanisms.gd), so a lit fog
##   lantern's pump can flood a low path.
## - Moving platforms, the stage's "platforms": [{"id", "stops": [bridge ids]}].
##   Each stop is a crossing of one size opened by its own gate; the platform
##   stands at the stop whose gate holds (where it stood when none or several
##   do). When it moves, whoever stands on the old stop rides to the same spot
##   on the new one, the live pip and the friend's replay alike (both walk one
##   world, runtime.gd). A carried item put
##   down on the stop a platform stands at rides the same way, and is picked
##   up again at whichever stop it reaches (carried_items.gd). Stops never
##   close slowly. The weight lift and the raft on a rope wheel are platforms
##   (core/blocks/stage_blocks.gd). The deck itself travels to its stop at
##   its own pace (deck_ticks), from wherever it is when it turns; a pip steps
##   between a deck and anything else only while the deck stands within a
##   step (Navigation.STEP_CM) of where the pip steps from or to, so riders
##   stay on until it gets there and nobody boards a deck still a storey up.
## - Sinking stones, the stage's "sinking": [bridge ids]: a stone holds one
##   pip; the second to step on pushes it under and the turn ends drowned.
## - One way stairs, a stair with "one_way": "up" (the pull-up rope ladder
##   and the wheel ride; core/cooperative/navigation.gd): a pip may climb one
##   but never go down it.
## The carried pipsport (train/new-pieces-carry) adds to these same rules, and
## so does the swinging bucket (core/physical/swings.gd), the one piece with a
## state of its own: a beat counter kept in the world, never in a checkpoint.
## Shared by the engine, the catalogs, the blocks and the level tools; it
## preloads only open_turns.gd, so a catalog may preload it.
const OpenTurns = preload("res://core/physical/open_turns.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const Swings = preload("res://core/physical/swings.gd")
const RULES := [OpenControls.PIECES_RULES_VERSION]
## How fast a deck travels, cm a second: a lift (its stops share a rectangle)
## and a raft. The world draws its decks at the same pace (kit/new_pieces.gd).
const LIFT_CM_A_SECOND := 80
const RAFT_CM_A_SECOND := 160
## The simulation's ticks a second (runtime.gd TICK_RATE).
const TICKS_A_SECOND := 30

## Whether rules `version` play the new pieces.
static func on(version: int) -> bool:
	return version in RULES

## Whether `definition` pins the new pieces.
static func pinned(definition: Dictionary) -> bool:
	var declared: Variant = definition.get("simulation_version")
	return (declared is int or declared is float) and on(int(declared))

## `level` on open turns (OpenTurns.pin, caps per stage) with the new pieces.
## Changes and returns `level`.
static func pin(level: Dictionary, caps: Dictionary) -> Dictionary:
	OpenTurns.pin(level, caps)
	level.simulation_version = OpenControls.PIECES_RULES_VERSION
	return level

## What in `level` needs the new pieces: each stage's platforms and sinking
## stones, a one way stair, a "not" in any gate or goal. [] when none.
static func uses(level: Dictionary) -> Array:
	var found: Array = []
	for stair: Dictionary in level.get("stairs", []):
		if stair.has("one_way"): found.append("one way stair %s" % stair.id)
	found.append_array(Swings.uses(level))
	for stage: Dictionary in level.get("stages", []):
		for key: String in ["platforms", "sinking"]:
			if not stage.get(key, []).is_empty(): found.append("%s on %s" % [key, stage.id])
		var trees: Array = [stage.get("goal_policy", {}).get("when", {})]
		for gate: Dictionary in stage.get("gates", []): trees.append(gate.get("when", {}))
		for tree: Variant in trees:
			if tree is Dictionary and _has_not(tree):
				found.append("not on %s" % stage.id)
				break
	return found

## Shapes the engine relies on, by stage: every platform's stops are distinct
## bridges of one size each opened by a gate, every sinking stone is a bridge,
## every one way stair says "up". [] when sound.
static func problems(level: Dictionary) -> Array:
	var found: Array = []
	var bridges: Dictionary = {}
	for bridge: Dictionary in level.get("bridges", []): bridges[bridge.id] = bridge
	for stair: Dictionary in level.get("stairs", []):
		if stair.has("one_way") and str(stair.one_way) != "up": found.append("stair %s: one_way must be \"up\"" % stair.id)
	for stage: Dictionary in level.get("stages", []):
		var gated: Dictionary = {}
		for gate: Dictionary in stage.get("gates", []): gated[str(gate.get("route_id", ""))] = true
		var seen: Dictionary = {}
		for platform: Variant in stage.get("platforms", []):
			if not platform is Dictionary or not platform.get("stops") is Array or platform.stops.size() < 2:
				found.append("%s: a platform needs an id and two stops or more" % stage.id)
				continue
			var size: Variant = null
			for stop: Variant in platform.stops:
				var id := str(stop)
				if not bridges.has(id): found.append("%s: platform %s stop %s is not a bridge" % [stage.id, platform.get("id", ""), id])
				elif seen.has(id): found.append("%s: stop %s is in two platforms or twice" % [stage.id, id])
				elif not gated.has(id): found.append("%s: platform %s stop %s has no gate" % [stage.id, platform.get("id", ""), id])
				else:
					var rect: Array = bridges[id].rect_cm
					var span := Vector2i(int(rect[2]) - int(rect[0]), int(rect[3]) - int(rect[1]))
					if size == null: size = span
					elif span != size: found.append("%s: platform %s stops differ in size" % [stage.id, platform.get("id", "")])
				seen[id] = true
		for stone: Variant in stage.get("sinking", []):
			if not bridges.has(str(stone)): found.append("%s: sinking stone %s is not a bridge" % [stage.id, stone])
	found.append_array(Swings.problems(level))
	return found

## Ticks a deck takes from `from` to `to` ([x, z, height] cm, a stop's
## corner), at least one when they differ.
static func deck_ticks(from: Array, to: Array, lift: bool) -> int:
	var x := int(to[0]) - int(from[0])
	var z := int(to[1]) - int(from[1])
	var y := int(to[2]) - int(from[2])
	var length := sqrt(float(x * x + z * z + y * y))
	return ceili(length * TICKS_A_SECOND / (LIFT_CM_A_SECOND if lift else RAFT_CM_A_SECOND))

## Where a deck travelling `done` of `ticks` from `from` to `to` stands now.
static func deck_at(from: Array, to: Array, done: int, ticks: int) -> Array:
	if done >= ticks: return to.duplicate()
	var at: Array = []
	for axis in range(3): at.append(int(from[axis]) + (int(to[axis]) - int(from[axis])) * done / ticks)
	return at

## The platform `route` is a stop of on `stage`, or {}.
static func platform_of(stage: Dictionary, route: String) -> Dictionary:
	for platform: Dictionary in stage.get("platforms", []):
		if route in platform.get("stops", []): return platform
	return {}

static func _has_not(tree: Dictionary) -> bool:
	if tree.has("not"): return true
	for key: String in ["all", "any"]:
		for child: Variant in tree.get(key, []):
			if child is Dictionary and _has_not(child): return true
	return false
