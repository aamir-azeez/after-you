extends RefCounted
## Light pieces: lamps, mirrors, selectors and receivers as journey pieces
## (core/beam_field.gd traces the light), so any journey level can carry light
## puzzles. A stage's "optical_field" is a BeamField field; what changes it
## while the stage plays comes from the stage itself, never from state of its
## own (the checkpoint keeps controls, levers and items as before):
## - A mirror control ("kind": "mirror", "values" ["slash", "backslash"])
##   turns the optical mirror of its id to its value (Conservatory's mirrors).
## - A selector control with "optics": {value: {optical id: {"orientation"?:
##   "slash"/"backslash", "enabled"?: bool}}} sets those optical entities while
##   it shows that value: a selector that steers a mirror, or switches a lamp
##   off at one value (sleeping-lighthouse@3's path selector).
## - The stage's "lit_when": {emitter id: when} lights a lamp only while its
##   when holds (Seven.predicate): a light pad ({"pad_id"}), a lens resting in
##   a cradle ({"item_id", "spot_id"}, rules 16's carried items), a lever. A
##   when never reads a signal (light never powers light), so one trace a tick
##   settles it.
## A receiver's signal opens a crossing through an ordinary gate
## ({"signal_id"}) and may light the goal (goal_policy "when"). The engine
## (core/journey/simulation.gd _refresh_optics), the level graph
## (tests/level_graph.gd), the design solver and the server
## (backend/src/v2/light-pieces.ts) read light through these rules alone.
## The journey world draws every optical mirror, lamp and receiver, a cable
## from a light pad or a lens cradle to its lamp, and the lens
## (presentation/journey_world.gd). Puzzle block: "light"
## (core/blocks/stage_blocks.gd). Pure and deterministic, no state.
const BeamField = preload("res://core/beam_field.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const ORIENTATIONS := ["slash", "backslash"]

## The light on `stage` with the pips at `players` and `mechanisms` as they
## stand: BeamField.evaluate's result ({"segments": [], "signals": {}} with no
## field). `open`: open controls, where a light pad holds for either pip.
static func optics(stage: Dictionary, players: Dictionary, mechanisms: Dictionary, open: bool) -> Dictionary:
	if not stage.has("optical_field"): return {"segments": [], "signals": {}}
	return BeamField.evaluate(stage.optical_field, overrides(stage, players, mechanisms, open))

## BeamField overrides for the stage as it stands: its steered mirrors and
## switched lamps (steered) and each lamp whose lit_when does not hold, off.
static func overrides(stage: Dictionary, players: Dictionary, mechanisms: Dictionary, open: bool) -> Dictionary:
	var result := steered(stage, mechanisms.get("controls", {}))
	var lit: Dictionary = stage.get("lit_when", {})
	for id: String in lit:
		if Seven.predicate(lit[id], stage, players, mechanisms, {}, open): continue
		if not result.has(id): result[id] = {}
		result[id]["enabled"] = false
	return result

## What the stage's controls set, from their values in `controls` (a control
## missing there shows its initial value): a mirror's orientation, a
## selector's optics at its value.
static func steered(stage: Dictionary, controls: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for control: Dictionary in stage.get("controls", []):
		var value := str(controls.get(str(control.id), control.get("initial", "")))
		if str(control.get("kind", "")) == "mirror":
			result[str(control.id)] = {"orientation": value}
			continue
		var sets: Variant = control.get("optics", {})
		if not sets is Dictionary or not sets.get(value) is Dictionary: continue
		for id: String in sets[value]:
			if not result.has(id): result[id] = {}
			result[id].merge(sets[value][id], true)
	return result

## Every optical mirror's orientation with `controls` as given: {id: "slash"
## or "backslash"}. The world turns the mirrors a selector steers by it.
static func orientations(stage: Dictionary, controls: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not stage.has("optical_field"): return result
	var set := steered(stage, controls)
	for mirror: Dictionary in stage.optical_field.get("mirrors", []):
		result[str(mirror.id)] = str(set.get(str(mirror.id), {}).get("orientation", mirror.orientation))
	return result

## Whether `stage` lights anything by these rules beyond plain mirrors: a
## lit_when or a selector with optics.
static func declared(stage: Dictionary) -> bool:
	if not stage.get("lit_when", {}).is_empty(): return true
	return stage.get("controls", []).any(func(control: Dictionary) -> bool: return control.has("optics"))

## Each receiver's signal as a when over the stage's controls and lamps: {id:
## {"any": [{"all": [...]}, ...]}}, one branch per setting of its mirrors and
## selectors and lamps lit that lights it (a receiver nothing can light is
## left out). Lighting a lamp never darkens a receiver (lamps do not block
## light), so a branch names only the lamps it needs, each by its lit_when.
## The level graph reads a signal through this when it lights beams exactly.
static func signal_whens(stage: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not stage.has("optical_field"): return result
	var steering: Array = stage.get("controls", []).filter(func(control: Dictionary) -> bool: return str(control.get("kind", "")) == "mirror" or control.has("optics"))
	var lamps: Array = stage.get("lit_when", {}).keys()
	var lit: Dictionary = stage.get("lit_when", {})
	var combos: Array = [[]]
	for control: Dictionary in steering:
		var next: Array = []
		for combo: Array in combos:
			for value: Variant in control.get("values", []): next.append(combo + [str(value)])
		combos = next
	for combo: Array in combos:
		var controls: Dictionary = {}
		var terms: Array = []
		for index in range(steering.size()):
			controls[str(steering[index].id)] = combo[index]
			terms.append({"control_id": str(steering[index].id), "value": combo[index]})
		for mask in range(1 << lamps.size()):
			var set := steered(stage, controls)
			var needs: Array = terms.duplicate(true)
			for index in range(lamps.size()):
				if mask & (1 << index): needs.append(lit[lamps[index]].duplicate(true))
				else:
					if not set.has(lamps[index]): set[lamps[index]] = {}
					set[lamps[index]]["enabled"] = false
			var signals: Dictionary = BeamField.evaluate(stage.optical_field, set).get("signals", {})
			for id: String in signals:
				if not bool(signals[id]): continue
				if not result.has(id): result[id] = {"any": []}
				result[id].any.append({"all": needs} if not needs.is_empty() else {})
	return result

## Shapes the engine relies on, by stage: a lit_when names a lamp of the
## stage's field and reads no signal, a selector's optics name entities of the
## field at its own values with orientations or enabled flags only, and only a
## stage with a field has either. [] when sound.
static func problems(level: Dictionary) -> Array:
	var found: Array = []
	for stage: Dictionary in level.get("stages", []):
		var field: Dictionary = stage.get("optical_field", {})
		var ids: Dictionary = {}
		for kind: String in ["emitters", "mirrors", "receivers", "blockers"]:
			for entity: Dictionary in field.get(kind, []): ids[str(entity.id)] = kind
		if (stage.has("lit_when") or declared(stage)) and field.is_empty(): found.append("%s: light without an optical_field" % stage.id)
		var lit: Variant = stage.get("lit_when", {})
		if not lit is Dictionary: found.append("%s: lit_when must map lamps to whens" % stage.id)
		else:
			for id: Variant in lit:
				if ids.get(str(id), "") != "emitters": found.append("%s: lit_when names %s, which is no lamp of its field" % [stage.id, id])
				if not lit[id] is Dictionary or _reads_signal(lit[id]): found.append("%s: lit_when %s must be a when that reads no signal" % [stage.id, id])
		for control: Dictionary in stage.get("controls", []):
			if not control.has("optics"): continue
			var sets: Variant = control.optics
			if str(control.get("kind", "")) != "selector" or not sets is Dictionary:
				found.append("%s: %s's optics must be a selector's {value: {id: state}}" % [stage.id, control.id])
				continue
			for value: Variant in sets:
				if not str(value) in control.get("values", []).map(func(v: Variant) -> String: return str(v)): found.append("%s: %s's optics name value %s it never shows" % [stage.id, control.id, value])
				if not sets[value] is Dictionary:
					found.append("%s: %s's optics at %s must map ids to states" % [stage.id, control.id, value])
					continue
				for id: Variant in sets[value]:
					var state: Variant = sets[value][id]
					if not ids.has(str(id)): found.append("%s: %s's optics name %s, which is not in its field" % [stage.id, control.id, id])
					if not state is Dictionary or state.is_empty() or state.keys().any(func(key: Variant) -> bool: return key not in ["orientation", "enabled"]):
						found.append("%s: %s's optics for %s set only orientation and enabled" % [stage.id, control.id, id])
					elif state.has("orientation") and (ids.get(str(id), "") != "mirrors" or str(state.orientation) not in ORIENTATIONS):
						found.append("%s: %s's optics turn %s, which is no mirror, or to no orientation" % [stage.id, control.id, id])
					elif state.has("enabled") and not state.enabled is bool:
						found.append("%s: %s's optics for %s: enabled must be true or false" % [stage.id, control.id, id])
	return found

static func _reads_signal(when: Dictionary) -> bool:
	if when.has("signal_id"): return true
	for key: String in ["all", "any"]:
		for child: Variant in when.get(key, []):
			if child is Dictionary and _reads_signal(child): return true
	return when.get("not") is Dictionary and _reads_signal(when["not"])
