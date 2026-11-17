extends RefCounted
## Which crossings a world with moving water draws as ramps, and whether each
## lies down, from the chapter definition, the shown stage, the chapter's water
## block (content/water/) and a snapshot alone. The world that draws them
## (presentation/tide_world.gd) and the shared sound map
## (services/chapter_sound_map.gd) both ask here, so a ramp sounds whenever it
## is seen to move: live, as the memory, on a retry and in a replay.
##
## A crossing is a ramp when a gate on it, in any stage, needs a water value
## and another selector's value: it lies flat at that value and stands up out
## of the water otherwise. Its selector lowers it whatever the water. A ramp
## whose gate on the shown stage also needs a pad held stays raised over dry
## ground until someone stands on that pad, so a lowered ramp out of the water
## is always a way across; while the water stands over its deck nobody can
## hold that pad (the step's own gate needs the water low), so it lies down
## under the water, plainly no way across.
const WaterBodies = preload("res://presentation/kit/water_bodies.gd")
const NONE := {}

## Ramps by chapter key, worked out once per key (learn(); the definition
## never changes while the game runs): {definition, water, ramps}.
static var _by_key: Dictionary = {}

## Crossing id -> [selector id, value, water selector id], in the definition's
## stage and gate order.
static func ramps(definition: Dictionary, water: Dictionary) -> Dictionary:
	var water_selectors: Array = water.get("bodies", []).map(func(body: Dictionary) -> String: return str(body.selector))
	var found := {}
	for stage: Dictionary in definition.get("stages", []):
		for gate: Dictionary in stage.get("gates", []):
			var route := route_of(definition, str(gate.route_id))
			if route.is_empty() or route.has("axis") or WaterBodies.is_stub(route) or found.has(str(route.id)): continue
			var when: Dictionary = gate.get("when", {})
			var wet := ""
			var other: Array = []
			for term: Dictionary in [when] + when.get("all", []):
				var control := str(term.get("control_id", ""))
				if control.is_empty(): continue
				if control in water_selectors: wet = control
				elif other.is_empty(): other = [control, str(term.get("value", ""))]
			if not wet.is_empty() and not other.is_empty(): found[str(route.id)] = other + [wet]
	return found

## Whether ramp `id` (one of ramps()) lies down on `stage` at the snapshot's
## controls and held pads.
static func lowered(id: String, ramp: Array, definition: Dictionary, stage: Dictionary, water: Dictionary, controls: Dictionary, held: Dictionary) -> bool:
	if str(controls.get(str(ramp[0]), "")) != str(ramp[1]): return false
	return pads_held(stage, id, held) or under_water(route_of(definition, id), str(ramp[2]), water, controls)

## Whether every pad the stage's gate on `id` names is held.
static func pads_held(stage: Dictionary, id: String, held: Dictionary) -> bool:
	var when: Dictionary = WaterBodies.gate_for_stage(stage, id).get("when", {})
	for term: Dictionary in [when] + when.get("all", []):
		if term.has("pad_id") and not bool(held.get(str(term.pad_id), false)): return false
	return true

## Whether the water `selector` moves stands over the route's deck at the
## snapshot's value of that selector.
static func under_water(route: Dictionary, selector: String, water: Dictionary, controls: Dictionary) -> bool:
	for body: Dictionary in water.get("bodies", []):
		if str(body.selector) != selector: continue
		var levels: Dictionary = body.get("levels", {})
		var value := str(controls.get(selector, body.get("rest", "")))
		return levels.has(value) and float(levels[value]) > float(route.get("height_cm", 0)) / 100.0
	return false

static func route_of(definition: Dictionary, id: String) -> Dictionary:
	for route: Dictionary in definition.get("bridges", []) + definition.get("stairs", []):
		if route.id == id: return route
	return NONE

## Whether chapter `key`'s ramps are known (learn()).
static func knows(key: String) -> bool:
	return _by_key.has(key)

## Works out chapter `key`'s ramps once, from its definition and water block
## ({} for a chapter with no water).
static func learn(key: String, definition: Dictionary, water: Dictionary) -> void:
	_by_key[key] = {"definition": definition, "water": water, "ramps": ramps(definition, water) if not water.is_empty() else NONE}

## Each ramp of the snapshot's stage in learned chapter `key` -> whether it
## lies down; {} for a chapter with no ramps.
static func poses(key: String, state: Dictionary) -> Dictionary:
	var known: Dictionary = _by_key.get(key, NONE)
	if known.get("ramps", NONE).is_empty(): return NONE
	var stage := NONE
	for candidate: Dictionary in known.definition.get("stages", []):
		if str(candidate.get("id", "")) == str(state.get("stage_id", "")): stage = candidate
	var controls: Dictionary = state.get("controls", NONE)
	var held: Dictionary = state.get("hold_pads", NONE)
	var result := {}
	for id: String in known.ramps: result[id] = lowered(id, known.ramps[id], known.definition, stage, known.water, controls, held)
	return result
