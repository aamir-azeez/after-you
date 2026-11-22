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
## The new pieces (J, rules 16, core/physical/pieces_rules.gd; the level pins
## them with PiecesRules.pin):
##   fog_lantern           J  "lever" lights the lantern; its pump floods each
##                            of "floods" and drains each of "drains" ({route:
##                            when or {}}): a flooded route holds only while its
##                            when does and the lantern is out, a drained one
##                            only while its when does and the lantern burns.
##                            (A pan it fills is the weight_lift's "also".)
##   crank_bridge          J  "lever" (a crank) or "pads" (crank boards, any one
##                            held) lays each of "routes" across
##   weight_pan            J  "pad" (a pan: a pip, or one of "items" resting in
##                            it) holds each of "routes" open
##   platform              J  a moving platform "id" whose "stops" {route:
##                            when} it stands at while that when holds
##   weight_lift           J  platform "id" at "high" while something heavy
##                            sits in one of "pads" (a pip, or one of "items")
##                            or "also" holds, and none in "top_pads"; at "low"
##                            otherwise
##   rope_raft             J  platform "id" at the stop "stops" {value: route}
##                            names for its rope wheel "selector"'s value
##   sinking_stones        J  "stones" that hold one pip each, open while
##                            "when" holds (always without one)
##   rope_ladder           J  "stairs" climbed up only, always hung
## Ladders, the wheel ride and rope bridges also say "hands": true (both
## hands needed: a pip carrying an item never steps on).
##   wheel_ride            J  "stairs" ridden up only, on a big wheel that
##                            turns while "when" holds
##   falls_path            J  "routes" behind a waterfall, dry while "lever"
##                            (its water gate) is on
##   swinging_bucket       J  swing "id" hung from a crane at "pivot" [x, z]
##                            sweeps "lane" {"surface", "rect"}
##                            on a steady beat (core/physical/swings.gd):
##                            "period", "sweep", "warn", "offset" ticks
##                            (90, 30, 30, 0), "outcome" ("drowned"). "brake"
##                            (a pad, inline or by id, or any when) parks it
##                            the next time it swings back, while it holds
## An item term ("items", carried items on train/new-pieces-carry) is
## {"item_id", "spot_id"} with the pan's own id as its spot.

const Solid = preload("res://core/solid_footprint.gd")
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
	"fog_lantern": ["lever"], "crank_bridge": ["routes"], "weight_pan": ["pad", "routes"],
	"platform": ["id", "stops"], "weight_lift": ["id", "low", "high", "pads"],
	"rope_raft": ["id", "selector", "stops"], "sinking_stones": ["stones"], "rope_ladder": ["stairs"],
	"wheel_ride": ["stairs", "when"], "falls_path": ["lever", "routes"],
	"swinging_bucket": ["id", "pivot", "lane"],
}
## A swinging bucket's beat when the block gives none (ticks): a 3 s beat,
## 1 s across the lane after 1 s of warning.
const SWING_BEAT := {"period": 90, "sweep": 30, "warn": 30, "offset": 0}
## The new pieces' blocks (rules 16).
const PIECE_BLOCKS := ["fog_lantern", "crank_bridge", "weight_pan", "platform", "weight_lift", "rope_raft", "sinking_stones", "rope_ladder", "wheel_ride", "falls_path", "swinging_bucket"]
## Blocks each family's rules can play.
const FAMILY_BLOCKS := {
	COOPERATIVE: ["pad", "lever", "open_route", "hold_door", "relay_lever", "weight_pad", "one_way_drop", "ring_bell", "raw"],
	JOURNEY: ["pad", "lever", "selector", "open_route", "hold_door", "relay_lever", "selector_gate", "match_selectors", "one_way_drop", "ring_bell", "raw"] + PIECE_BLOCKS,
}

## The definition with every stage's "blocks" expanded in place and removed.
## A block this family cannot play, or one missing what it needs, is left out;
## problems() names it. Hand controls get the one solid rule the chapter
## catalogs apply (core/solid_footprint.gd with_hands), so a stage written
## with blocks is the same definition as the stage written by hand.
static func expand(source: Dictionary) -> Dictionary:
	var level: Dictionary = source.duplicate(true)
	var family := family_of(level)
	for stage: Dictionary in level.get("stages", []):
		if not stage.has("blocks"): continue
		var blocks: Array = stage.blocks
		stage.erase("blocks")
		for block: Dictionary in blocks:
			if _missing(block, family).is_empty(): _emit(level, stage, block, family)
	return Solid.with_hands(level)

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
		for swing: Dictionary in stage.get("swings", []):
			var ids: Array = []
			_terms(swing.get("brake", {}), ids)
			for id: String in ids:
				if id not in placed: found.append("%s: swing %s brakes on %s, which the stage does not place" % [stage.id, swing.id, id])
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
	_piece_missing(found, kind, block)
	if kind == "match_selectors" and not block.values is Array: found.append("block match_selectors's values must be a list")
	if block.get("lip") != null: _need(found, kind, "lip", block.lip, ["id", "rect", "owner"])
	for field: String in ["at", "rect"]:
		if block.has(field) and not block[field] is Array: found.append("block %s's %s must be a list" % [kind, field])
	if kind == "hold_door" and block.has("finish") and family != COOPERATIVE: found.append("block hold_door's finish is the cooperative hold rule")
	if kind == "raw":
		for field: String in block:
			if field != "block" and not block[field] is Array: found.append("block raw's %s must be a list" % field)
	return found

## The new pieces' own shapes (rules 16).
static func _piece_missing(found: Array[String], kind: String, block: Dictionary) -> void:
	match kind:
		"fog_lantern":
			for field: String in ["floods", "drains"]:
				if block.has(field) and (not block[field] is Dictionary or block[field].values().any(func(when: Variant) -> bool: return not when is Dictionary)): found.append("block fog_lantern's %s must map each route to a when ({} for none)" % field)
		"crank_bridge":
			if block.has("lever") == block.has("pads"): found.append("block crank_bridge needs a lever (a crank) or pads (crank boards), not both")
			if block.has("pads"): _pads_missing(found, kind, block, "pads")
		"weight_pan":
			if block.has("items") and not block.items is Array: found.append("block weight_pan's items must be a list")
		"wheel_ride", "rope_ladder":
			if not block.stairs is Array: found.append("block %s's stairs must be a list" % kind)
			if kind == "wheel_ride" and not block.when is Dictionary: found.append("block wheel_ride's when must be a when")
		"platform":
			if not block.stops is Dictionary or block.stops.size() < 2 or block.stops.values().any(func(when: Variant) -> bool: return not when is Dictionary): found.append("block platform's stops must map two routes or more to their whens")
		"weight_lift":
			for field: String in ["pads", "top_pads"]:
				if block.has(field): _pads_missing(found, kind, block, field)
			if block.has("also") and not block.also is Dictionary: found.append("block weight_lift's also must be a when")
			if block.has("items") and not block.items is Array: found.append("block weight_lift's items must be a list")
		"rope_raft":
			if not block.stops is Dictionary or block.stops.size() < 2: found.append("block rope_raft's stops must map two values or more to routes")
		"swinging_bucket":
			_need(found, kind, "lane", block.lane, ["surface", "rect"])
			if not block.pivot is Array: found.append("block swinging_bucket's pivot must be a list")
			if block.get("brake") is Dictionary and block.brake.has("at"): _need(found, kind, "brake", block.brake, ["id", "at", "surface", "owner"])
		"sinking_stones":
			if not block.stones is Array: found.append("block sinking_stones's stones must be a list")
			if block.has("when") and not block.when is Dictionary: found.append("block sinking_stones's when must be a when")

static func _pads_missing(found: Array[String], kind: String, block: Dictionary, field: String) -> void:
	if not block[field] is Array or block[field].is_empty():
		found.append("block %s's %s must be a list of pads" % [kind, field])
		return
	for pad: Variant in block[field]:
		if pad is Dictionary: _need(found, kind, field, pad, ["id", "at", "surface", "owner"])

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
		"fog_lantern":
			var lantern := _place(level, stage, block.lever, "levers", "lever", family)
			var lit := {"lever_id": lantern}
			for field: String in ["floods", "drains"]:
				var needs: Dictionary = {"not": lit} if field == "floods" else lit
				for route: String in block.get(field, {}):
					var when: Dictionary = block[field][route]
					_add(level, stage, "gates", {"route_id": route, "when": needs.duplicate(true) if when.is_empty() else {"all": [when.duplicate(true), needs.duplicate(true)]}})
		"crank_bridge":
			var held: Array = []
			if block.has("lever"): held.append({"lever_id": _place(level, stage, block.lever, "levers", "lever", family)})
			for pad: Variant in block.get("pads", []): held.append({"pad_id": _place(level, stage, pad, "pressure_pads", "pad", family)})
			for route: String in block.routes:
				_add(level, stage, "gates", {"route_id": route, "when": _any_of(held)})
				_needs_hands(level, route)
		"weight_pan":
			var heavy := _pan(level, stage, block.pad, block.get("items", []), family)
			for route: String in block.routes: _add(level, stage, "gates", {"route_id": route, "when": heavy.duplicate(true)})
		"platform":
			_platform(level, stage, str(block.id), block.stops)
		"weight_lift":
			var heavy: Array = []
			for pad: Variant in block.pads: heavy.append(_pan(level, stage, pad, block.get("items", []), family))
			if block.has("also"): heavy.append(block.also.duplicate(true))
			var up := _any_of(heavy)
			if block.has("top_pads"):
				var top: Array = []
				for pad: Variant in block.top_pads: top.append(_pan(level, stage, pad, block.get("items", []), family))
				up = {"all": [up, {"not": _any_of(top)}]}
			_platform(level, stage, str(block.id), {str(block.low): {"not": up}, str(block.high): up})
		"rope_raft":
			var rope := _place(level, stage, block.selector, "controls", "selector", family)
			var stops: Dictionary = {}
			for value: Variant in block.stops: stops[str(block.stops[value])] = _value(rope, value)
			_platform(level, stage, str(block.id), stops)
		"sinking_stones":
			for stone: Variant in block.stones:
				var gate := {"route_id": str(stone)}
				if not block.get("when", {}).is_empty(): gate["when"] = block.when.duplicate(true)
				_add(level, stage, "gates", gate)
				_add(level, stage, "sinking", str(stone))
		"rope_ladder", "wheel_ride":
			for id: Variant in block.stairs:
				for stair: Dictionary in level.get("stairs", []):
					if stair.id == str(id):
						stair["one_way"] = "up"
						stair["hands"] = true
				_add(level, stage, "gates", {"route_id": str(id), "when": block.when.duplicate(true)} if block.has("when") and not block.when.is_empty() else {"route_id": str(id)})
		"swinging_bucket":
			var swing := {"id": str(block.id), "pivot_cm": block.pivot.duplicate(),
				"lane": {"surface_id": str(block.lane.surface), "rect_cm": block.lane.rect.duplicate()}}
			for field: String in SWING_BEAT: swing[field + "_ticks"] = int(block.get(field, SWING_BEAT[field]))
			swing["outcome"] = str(block.get("outcome", "drowned"))
			# A brake given as a pad (by id, or inline with "at") is that pad held; any other when as written.
			var brake: Variant = block.get("brake")
			if brake is String or (brake is Dictionary and brake.has("at")): swing["brake"] = {"pad_id": _place(level, stage, brake, "pressure_pads", "pad", family)}
			elif brake is Dictionary and not brake.is_empty(): swing["brake"] = brake.duplicate(true)
			_add(level, stage, "swings", swing)
		"falls_path":
			var water_gate := _place(level, stage, block.lever, "levers", "lever", family)
			for route: String in block.routes: _add(level, stage, "gates", {"route_id": route, "when": {"lever_id": water_gate}})
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

static func _any_of(terms: Array) -> Dictionary:
	return terms[0] if terms.size() == 1 else {"any": terms}

## A rope bridge needs both hands (carried items: a pip holding something
## never steps onto a "hands" crossing).
static func _needs_hands(level: Dictionary, route: String) -> void:
	for bridge: Dictionary in level.get("bridges", []):
		if bridge.id == route: bridge["hands"] = true

## A pan (rules 16): the pad held by a pip, or any of `items` resting at the
## spot of the pan's own id. Places an inline pad.
static func _pan(level: Dictionary, stage: Dictionary, pad: Variant, items: Array, family: String) -> Dictionary:
	var id := _place(level, stage, pad, "pressure_pads", "pad", family)
	var terms: Array = [{"pad_id": id}]
	for item: Variant in items: terms.append({"item_id": str(item), "spot_id": id})
	return _any_of(terms)

## A moving platform (rules 16): a gate for each stop, in order, and the
## stage's "platforms" entry naming them.
static func _platform(level: Dictionary, stage: Dictionary, id: String, stops: Dictionary) -> void:
	for route: String in stops:
		var when: Dictionary = stops[route]
		_add(level, stage, "gates", {"route_id": route, "when": when.duplicate(true)} if not when.is_empty() else {"route_id": route})
	_add(level, stage, "platforms", {"id": id, "stops": stops.keys()})

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
	if when.get("not") is Dictionary: _terms(when["not"], ids)
	for field: String in ["pad_id", "lever_id", "control_id"]:
		if when.has(field): ids.append(str(when[field]))
