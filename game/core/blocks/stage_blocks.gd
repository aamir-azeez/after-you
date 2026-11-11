extends RefCounted
## Puzzle building blocks: the pieces chapters keep repeating, placed by name
## in a stage's "blocks" list and expanded into plain definition data (pads,
## levers, selectors, gates, drops, goals) before anything hashes it. A
## catalog returns expand(its source); the result is an ordinary definition,
## so the engines, the hashes and the recordings never see a block, and a
## stage written with blocks hashes the same as the same stage written by hand.
##
## Pure and deterministic: static functions on plain data, no state, no
## caches, nothing from presentation or services. Safe on any thread.
##
## A block is a Dictionary with "block" naming it. Pads, levers and selectors
## are given either as an id already placed (a String) or inline (a Dictionary
## with "id", "at" [x, z] cm, "surface", "owner" "p0"/"p1", optional "radius"
## and, on a journey, "height"); an inline one is placed where the block stands
## in the list. Each block appends to the stage's arrays (and the level's
## "drops" and "access_zones") in list order, after anything the stage already
## lists, so the order of blocks is the order of the published arrays.
##
## Blocks (C cooperative rules, schema 6; J journey rules, schema 7):
##   pad, lever          C J  place a pressure pad or a lever
##   selector              J  place a selector: "values", "initial"
##   open_route          C J  "routes" always open
##   hold_door           C J  "pad" holds "routes" open; with "lever", only
##                            while that lever is pulled too. "finish": hold
##                            ticks makes holding it the first turn's goal (C)
##   relay_lever         C J  "lever" opens "routes"; "second_lever" as well
##   selector_gate         J  "selector" opens each of "routes" {route: value
##                            or [values]} at its value
##   match_selectors       J  "routes" open while "selector" stands at the
##                            same value as "matches", one of "values"
##   weight_pad          C    a ball pad "id" for "ball" opens "routes"
##                            (optional "lever" too)
##   one_way_drop        C J  a drop "id", "rect", "from" surface "to" surface
##                            ("height", default 0), behind "lever" if given;
##                            "lip": {"id", "rect", "owner"} lets only that
##                            spirit onto its edge
##   ring_bell           C J  the stage's goal: a bell "id" at "at" for
##                            "owner"; "when" (J) holds it until then
##   raw                 C J  appends its own arrays as written: the escape
##                            hatch for one-off wiring between blocks

const COOPERATIVE := "cooperative"
const JOURNEY := "journey"
## Default reach of each placed thing, cm.
const RADIUS := {"pad": 32, "lever": 28, "selector": 28, "bell": 28, "ball_pad": 36}
## Level arrays a block may append to; everything else is the stage's.
const LEVEL_ARRAYS := ["drops", "access_zones"]
## What each block must name.
const NEEDS := {
	"pad": ["id", "at", "surface", "owner"], "lever": ["id", "at", "surface", "owner"],
	"selector": ["id", "at", "surface", "owner", "values", "initial"],
	"open_route": ["routes"], "hold_door": ["pad", "routes"], "relay_lever": ["lever", "routes"],
	"selector_gate": ["selector", "routes"], "match_selectors": ["selector", "matches", "values", "routes"],
	"weight_pad": ["id", "at", "surface", "ball", "routes"], "one_way_drop": ["id", "rect", "from", "to"],
	"ring_bell": ["id", "at", "surface", "owner"], "raw": [],
}
## Blocks each family's rules can play.
const FAMILY_BLOCKS := {
	COOPERATIVE: ["pad", "lever", "open_route", "hold_door", "relay_lever", "weight_pad", "one_way_drop", "ring_bell", "raw"],
	JOURNEY: ["pad", "lever", "selector", "open_route", "hold_door", "relay_lever", "selector_gate", "match_selectors", "one_way_drop", "ring_bell", "raw"],
}

## The definition with every stage's "blocks" expanded in place and removed.
## A block this family cannot play, or one missing what it needs, is left out;
## problems() names it.
static func expand(source: Dictionary) -> Dictionary:
	var level: Dictionary = source.duplicate(true)
	var family := family_of(level)
	for stage: Dictionary in level.get("stages", []):
		if not stage.has("blocks"): continue
		var blocks: Array = stage.blocks
		stage.erase("blocks")
		for block: Dictionary in blocks:
			if _missing(block, family).is_empty(): _emit(level, stage, block, family)
	return level

## "cooperative" for the schema-6 physical rules, "journey" for schema 7.
static func family_of(level: Dictionary) -> String:
	match int(level.get("schema_version", 0)):
		6: return COOPERATIVE
		7: return JOURNEY
	return ""

## Every block that would be left out or wired to nothing, as messages.
static func problems(source: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var family := family_of(source)
	if family.is_empty(): found.append("Blocks need a cooperative (schema 6) or journey (schema 7) definition")
	for stage: Dictionary in source.get("stages", []):
		for block: Dictionary in stage.get("blocks", []):
			for message: String in _missing(block, family): found.append("%s: %s" % [stage.get("id", "?"), message])
	if not found.is_empty(): return found
	var level := expand(source)
	var routes: Array = []
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []): routes.append(str(route.id))
	for stage: Dictionary in level.stages:
		var placed: Array = []
		for field: String in ["pressure_pads", "levers", "controls", "ball_pads"]:
			for item: Dictionary in stage.get(field, []):
				if str(item.id) in placed: found.append("%s: %s is placed twice" % [stage.id, item.id])
				placed.append(str(item.id))
		for gate: Dictionary in stage.get("gates", []):
			if str(gate.route_id) not in routes: found.append("%s: gate on a route the level lacks: %s" % [stage.id, gate.route_id])
			for id: String in _wired(gate, family):
				if id not in placed: found.append("%s: %s wires %s, which the stage does not place" % [stage.id, gate.route_id, id])
	for drop: Dictionary in level.get("drops", []):
		var lever := str(drop.get("requires_lever", ""))
		if not lever.is_empty() and not level.stages.any(func(stage: Dictionary) -> bool: return stage.get("levers", []).any(func(item: Dictionary) -> bool: return item.id == lever)):
			found.append("Drop %s waits on lever %s, which no stage places" % [drop.id, lever])
	return found

## What a block lacks for this family, as messages: anything expand() would
## otherwise trip on or write wrongly.
static func _missing(block: Dictionary, family: String) -> Array[String]:
	var kind := str(block.get("block", ""))
	var found: Array[String] = []
	if not FAMILY_BLOCKS.get(family, []).has(kind):
		found.append("block %s does not play in the %s rules" % [kind, family])
		return found
	var needs: Array = NEEDS[kind]
	for field: String in needs:
		if not block.has(field): found.append("block %s needs %s" % [kind, field])
	if not found.is_empty(): return found
	for field: String in ["pad", "lever", "second_lever"]:
		var given: Variant = block.get(field)
		if given is Dictionary: _need(found, kind, field, given, ["id", "at", "surface", "owner"])
	for field: String in ["selector", "matches"]:
		var given: Variant = block.get(field)
		if given is Dictionary: _need(found, kind, field, given, ["id", "at", "surface", "owner", "values", "initial"])
	if kind == "selector": _need(found, kind, "selector", block, ["values"])
	if kind == "selector_gate":
		if not block.routes is Dictionary: found.append("block selector_gate's routes must map each route to its value")
	elif block.has("routes") and not block.routes is Array: found.append("block %s's routes must be a list" % kind)
	if kind == "match_selectors" and not block.values is Array: found.append("block match_selectors's values must be a list")
	if block.get("lip") != null: _need(found, kind, "lip", block.lip, ["id", "rect", "owner"])
	for field: String in ["at", "rect"]:
		if block.has(field) and not block[field] is Array: found.append("block %s's %s must be a list" % [kind, field])
	if kind == "hold_door" and block.has("finish") and family != COOPERATIVE: found.append("block hold_door's finish is the cooperative hold rule")
	if kind == "raw":
		for field: String in block:
			if field != "block" and not block[field] is Array: found.append("block raw's %s must be a list" % field)
	return found

static func _need(found: Array[String], kind: String, field: String, given: Variant, parts: Array) -> void:
	if not given is Dictionary:
		found.append("block %s's %s must be a dictionary" % [kind, field])
		return
	for part: String in parts:
		if not given.has(part): found.append("block %s's %s needs %s" % [kind, field, part])
	for part: String in ["at", "rect"]:
		if given.has(part) and not given[part] is Array: found.append("block %s's %s %s must be a list" % [kind, field, part])
	if given.has("values") and not given.values is Array: found.append("block %s's %s values must be a list" % [kind, field])

static func _emit(level: Dictionary, stage: Dictionary, block: Dictionary, family: String) -> void:
	match str(block.block):
		"pad": _add(level, stage, "pressure_pads", _point(block, "pad", family))
		"lever": _add(level, stage, "levers", _point(block, "lever", family))
		"selector": _add(level, stage, "controls", _selector(block))
		"open_route":
			for route: String in block.routes: _add(level, stage, "gates", _gate(family, route, {}))
		"hold_door":
			var pad := _place(level, stage, block.pad, "pressure_pads", "pad", family)
			var lever := _place(level, stage, block.get("lever", ""), "levers", "lever", family)
			for route: String in block.routes: _add(level, stage, "gates", _gate(family, route, {"pad_id": pad, "lever_id": lever}))
			if block.has("finish"):
				stage["source_policy"] = {"kind": "hold_switch", "pad_id": pad, "lever_id": lever, "minimum_hold_ticks": int(block.finish)}
		"relay_lever":
			var lever := _place(level, stage, block.lever, "levers", "lever", family)
			var second := _place(level, stage, block.get("second_lever", ""), "levers", "lever", family)
			for route: String in block.routes: _add(level, stage, "gates", _gate(family, route, {"lever_id": lever, "second_lever_id": second}))
		"selector_gate":
			var control := _place(level, stage, block.selector, "controls", "selector", family)
			for route: String in block.routes:
				var values: Array = block.routes[route] if block.routes[route] is Array else [block.routes[route]]
				var when: Dictionary = _value(control, values[0]) if values.size() == 1 else {"any": values.map(func(value: Variant) -> Dictionary: return _value(control, value))}
				_add(level, stage, "gates", {"route_id": route, "when": when})
		"match_selectors":
			var control := _place(level, stage, block.selector, "controls", "selector", family)
			var matches := _place(level, stage, block.matches, "controls", "selector", family)
			for route: String in block.routes:
				var any: Array = []
				for value: Variant in block.values: any.append({"all": [_value(control, value), _value(matches, value)]})
				_add(level, stage, "gates", {"route_id": route, "when": {"any": any}})
		"weight_pad":
			_add(level, stage, "ball_pads", {"id": block.id, "position_cm": block.at.duplicate(), "surface_id": block.surface, "radius_cm": int(block.get("radius", RADIUS.ball_pad)), "prop_id": block.ball})
			var lever := _place(level, stage, block.get("lever", ""), "levers", "lever", family)
			for route: String in block.routes: _add(level, stage, "gates", _gate(family, route, {"ball_pad_id": block.id, "lever_id": lever}))
		"one_way_drop":
			var lever := _place(level, stage, block.get("lever", ""), "levers", "lever", family)
			var drop := {"id": block.id, "rect_cm": block.rect.duplicate(), "surface_id": block.from, "destination_surface": block.to, "height_cm": int(block.get("height", 0))}
			# The cooperative rules always name the lever ("" for none); journey drops name one only when they have it.
			if family == COOPERATIVE or not lever.is_empty(): drop["requires_lever"] = lever
			_add(level, stage, "drops", drop)
			if block.get("lip") is Dictionary:
				_add(level, stage, "access_zones", {"id": block.lip.id, "rect_cm": block.lip.rect.duplicate(), "surface_id": block.from, "owner_slot": block.lip.owner})
		"ring_bell":
			stage["goal"] = _point(block, "bell", family)
			stage["goal_policy"] = {"kind": "ring"}
			if block.has("when"): stage.goal_policy["when"] = block.when.duplicate(true)
		"raw":
			for field: String in block:
				if field == "block": continue
				# An empty list still writes the field: a stage lists "ball_pads": [] when it has none.
				var owner: Dictionary = level if field in LEVEL_ARRAYS else stage
				if not owner.has(field): owner[field] = []
				for item: Variant in block[field]: _add(level, stage, field, item.duplicate(true) if item is Dictionary else item)

## Appends to the stage's array, or the level's for a level array.
static func _add(level: Dictionary, stage: Dictionary, field: String, item: Variant) -> void:
	var owner: Dictionary = level if field in LEVEL_ARRAYS else stage
	if not owner.has(field): owner[field] = []
	owner[field].append(item)

## The id of a pad, lever or selector given by id, after placing it when it
## is given inline. "" stays "" (none).
static func _place(level: Dictionary, stage: Dictionary, given: Variant, field: String, kind: String, family: String) -> String:
	if not given is Dictionary: return str(given)
	_add(level, stage, field, _selector(given) if kind == "selector" else _point(given, kind, family))
	return str(given.id)

## A placed thing as each family's rules write it: cooperative points carry
## no height; journey points always do.
static func _point(spec: Dictionary, kind: String, family: String) -> Dictionary:
	var point := {"id": spec.id, "position_cm": spec.at.duplicate(), "surface_id": spec.surface, "radius_cm": int(spec.get("radius", RADIUS[kind])), "owner_slot": spec.owner}
	if family == JOURNEY: point["height_cm"] = int(spec.get("height", 0))
	return point

static func _selector(spec: Dictionary) -> Dictionary:
	var control := _point(spec, "selector", JOURNEY)
	control.merge({"kind": "selector", "values": spec.values.duplicate(), "initial": spec.initial})
	return control

static func _value(control: String, value: Variant) -> Dictionary:
	return {"control_id": control, "value": value}

## One gate in the family's own form. Cooperative gates list every condition,
## "" for none, and all must hold; journey gates hold a "when" tree.
static func _gate(family: String, route: String, needs: Dictionary) -> Dictionary:
	if family == COOPERATIVE:
		var gate := {"route_id": route, "pad_id": str(needs.get("pad_id", "")), "lever_id": str(needs.get("lever_id", "")), "ball_pad_id": str(needs.get("ball_pad_id", ""))}
		if not str(needs.get("second_lever_id", "")).is_empty(): gate["second_lever_id"] = needs.second_lever_id
		return gate
	var terms: Array = []
	for field: String in ["pad_id", "lever_id", "second_lever_id"]:
		var id := str(needs.get(field, ""))
		if not id.is_empty(): terms.append({("lever_id" if field == "second_lever_id" else field): id})
	if terms.is_empty(): return {"route_id": route}
	return {"route_id": route, "when": terms[0] if terms.size() == 1 else {"all": terms}}

## Ids a gate waits on, by the family's form.
static func _wired(gate: Dictionary, family: String) -> Array:
	var ids: Array = []
	if family == COOPERATIVE:
		for field: String in ["pad_id", "lever_id", "second_lever_id", "ball_pad_id"]:
			if not str(gate.get(field, "")).is_empty(): ids.append(str(gate[field]))
	else: _terms(gate.get("when", {}), ids)
	return ids

static func _terms(when: Dictionary, ids: Array) -> void:
	for child: Dictionary in when.get("all", []) + when.get("any", []): _terms(child, ids)
	for field: String in ["pad_id", "lever_id", "control_id"]:
		if when.has(field): ids.append(str(when[field]))
