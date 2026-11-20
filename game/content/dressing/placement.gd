extends RefCounted
## Self-placing scenery: a dressing prop placed by a floor's edge instead of by
## centimetres, on the stage's plan (stage_view(): services/level_layout.gd).
##
## A prop that names "floor" and "edge" ("back", "front", "left" or "right";
## the camera looks from the front right) is placed from that floor's
## rectangle on every stage the floor is on:
##   - A bank lies just outside the edge, "depth" cm deep and "gap" cm off the
##     floor, along the whole edge or "span" [from, to] (fractions of it). A
##     back or front bank reaches over the corner onto a side bank of the same
##     floor. It is cut around every crossing, floor, control and start it
##     would stand in, MARGIN clear of a crossing (kit/prop_rules.gd).
##   - Any other prop stands on the bank of its edge when it has one (along
##     the bank's middle, on its top: Props.bank_top()), else just outside the
##     edge, or "out" cm from it. "along" is where on the edge (0 to 1).
##   - With "spacing" (cm) it repeats along every free stretch of that bank or
##     edge, one in the middle of every spacing; a line kind (fence, hedge,
##     wall) runs along each free stretch, "inset" cm short of its ends.
##     Repeated and line props are left out where they would stand on a
##     walking space, over a control, hide one from the camera or stand in
##     another prop: the dressing lint's own rules.
##   - Trim is laid at PropRules.TRIM_SIZE. A prop on a front edge given no
##     size is laid at most the size that keeps it under Props.LOW.
## A theme's "edging" lists such props per edge with no floor; a dressing
## grows them along the floors it names in "edged" ({floor id or "*":
## [edges]}), and its own "edging" replaces the theme's edge by edge. In a
## placed dressing, a prop given no "y" whose spot is on a bank stands on the
## bank's top. content/dressing/catalog.gd resolve() runs this per stage, so
## every reader gets plain kit specs.
const ChapterIndex = preload("res://content/chapters/index.gd")
const Solid = preload("res://core/solid_footprint.gd")
const LevelLayout = preload("res://services/level_layout.gd")
const Props = preload("res://presentation/kit/props.gd")
const PropRules = preload("res://presentation/kit/prop_rules.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
## The Lighthouse room's dressing key: its stages come from its own catalog.
const LIGHTHOUSE := "sleeping-lighthouse@1"
const LIGHTHOUSE_ROOM := "sleeping-lighthouse@2"
const EDGES := ["back", "front", "left", "right"]
## Fields that say where a prop goes; never passed on to the kit.
const FIELDS := ["floor", "edge", "along", "spacing", "out", "inset", "span", "gap"]
## Bank defaults (cm) and the shortest stretch worth growing anything on.
const BANK_DEPTH := 60.0
const SHORTEST := 40.0
## How far a placed prop keeps off the floor's edge with no bank (cm).
const CLEARANCE := 2.0
## A line's default inset from each end of its stretch (cm).
const INSET := 20.0

# --- The stage layout -----------------------------------------------------------
# Each stage's plan comes from the chapter family's layout function
# (services/level_layout.gd), fed the chapter's own definition (its
# descriptor's "definition"), never through the chapter registry: the
# registry loads every world, and the worlds load the dressing catalog.

## The chapter whose plans a dressing key's stages are: the unregistered
## Lighthouse @1 dresses the six stages the room chapter (@2) lays out.
static func layout_key(key: String) -> String:
	return LIGHTHOUSE_ROOM if key == LIGHTHOUSE else key

## A chapter's definition, as Registry.definition(key) gives it.
static func definition(key: String) -> Dictionary:
	var source: Array = ChapterIndex.data(layout_key(key)).get("definition", [])
	if source.is_empty(): return {}
	return Solid.with_hands(load(str(source[0])).callv(str(source[1]), source.slice(2)))

## A chapter's stage ids, in order (`level`: its definition, if at hand).
static func stage_ids(key: String, level: Dictionary = {}) -> Array:
	return LevelLayout.stage_ids(level if not level.is_empty() else definition(key))

## One stage's plan: floors (islands), crossings, stairs and every spot.
static func stage_view(key: String, stage_id: String, level: Dictionary = {}) -> Dictionary:
	var view: Dictionary = LevelLayout.plan(LevelLayout.family_of(layout_key(key)), level if not level.is_empty() else definition(key), stage_id)
	# A level that stands its camera elsewhere (its follow data's "from") is
	# judged from there (PropRules.sweep).
	var from: Vector3 = load("res://presentation/kit/view_fit.gd").camera_from(load("res://content/dressing/catalog.gd").raw(key))
	if from != load("res://presentation/kit/view_fit.gd").CAMERA_FROM: view["camera_from"] = from
	return view

# --- Placing --------------------------------------------------------------------

## True when the dressing places anything by a floor's edge.
static func used(data: Dictionary) -> bool:
	if not data.get("edged", {}).is_empty(): return true
	for stage: String in data.get("props", {}):
		for spec: Dictionary in data.props[stage]:
			if spec.has("edge"): return true
	return false

## What placing would have to leave out or cannot read, as messages.
static func problems(data: Dictionary, rules: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for floor_id: String in data.get("edged", {}):
		for edge: Variant in data.edged[floor_id]:
			if str(edge) not in EDGES: found.append("Unknown edge %s for %s" % [edge, floor_id])
	for edge: String in rules:
		if edge not in EDGES: found.append("Edging for an unknown edge: " + edge)
	for stage: String in data.get("props", {}):
		for spec: Dictionary in data.props[stage]:
			if not spec.has("edge"): continue
			if str(spec.edge) not in EDGES or str(spec.get("floor", "")).is_empty(): found.append("A placed prop needs a floor and one of %s: %s" % [EDGES, spec])
			if spec.has("at") or spec.has("from") or spec.has("rect"): found.append("A placed prop gives its own spot too: %s" % spec)
	return found

## The props `edged` grows on this stage's floors from `rules` ({edge: [props
## with no floor]}), in floor, edge and rule order.
static func grown(edged: Dictionary, rules: Dictionary, view: Dictionary) -> Array:
	var result: Array = []
	for island: Dictionary in view.get("islands", []):
		var edges: Array = edged.get(str(island.id), edged.get("*", []))
		for edge: String in EDGES:
			if edge not in edges: continue
			for rule: Dictionary in rules.get(edge, []):
				var spec: Dictionary = rule.duplicate(true)
				spec["floor"] = str(island.id)
				spec["edge"] = edge
				result.append(spec)
	return result

## `plain` (kit specs placed by hand) and every prop of `edged` (styled specs
## naming a floor and an edge) placed on this stage, as plain kit specs.
static func lay(plain: Array, edged: Array, view: Dictionary) -> Array:
	var stage := PropRules.scene(view)
	var floors: Dictionary = {}
	for island: Dictionary in view.get("islands", []): floors[str(island.id)] = island.rect_cm
	var result: Array = plain.duplicate()
	var banks: Dictionary = {}
	var taken: Array = []
	for spec: Dictionary in Props.expand(plain): taken.append(PropRules.solid(spec, stage.heights))
	# Banks first, so every prop on an edge knows the bank it stands on.
	var bank_specs: Array = edged.filter(func(spec: Dictionary) -> bool: return str(spec.get("kind", "")) == "bank" and floors.has(str(spec.get("floor", ""))))
	for spec: Dictionary in bank_specs:
		var made := _bank(spec, floors, bank_specs, stage)
		banks[_where(spec)] = made
		result.append_array(made.map(func(item: Dictionary) -> Dictionary: return item.spec))
	# Props at one spot before repeated ones, which keep out of their way.
	for repeated in [false, true]:
		for spec: Dictionary in edged:
			if str(spec.get("kind", "")) == "bank" or not floors.has(str(spec.get("floor", ""))): continue
			if (spec.has("spacing") or str(spec.kind) in Styles.LINE_KINDS) != repeated: continue
			for made: Dictionary in _prop(spec, floors, banks.get(_where(spec), []), stage, taken):
				taken.append(PropRules.solid(made, stage.heights))
				result.append(made)
	return _on_banks(result)

static func _where(spec: Dictionary) -> String:
	return "%s/%s" % [spec.floor, spec.edge]

## {start, dir, out, length} of a floor edge, in cm: a point `t` along it and
## `d` out from it is start + dir * t + out * d.
static func _edge(r: Array, edge: String) -> Dictionary:
	var x0 := float(r[0])
	var z0 := float(r[1])
	var x1 := float(r[2])
	var z1 := float(r[3])
	match edge:
		"back": return {"start": Vector2(x0, z0), "dir": Vector2(1, 0), "out": Vector2(0, -1), "length": x1 - x0}
		"front": return {"start": Vector2(x0, z1), "dir": Vector2(1, 0), "out": Vector2(0, 1), "length": x1 - x0}
		"left": return {"start": Vector2(x0, z0), "dir": Vector2(0, 1), "out": Vector2(-1, 0), "length": z1 - z0}
	return {"start": Vector2(x1, z0), "dir": Vector2(0, 1), "out": Vector2(1, 0), "length": z1 - z0}

static func _point(edge: Dictionary, t: float, d: float) -> Vector2:
	return (edge.start as Vector2) + (edge.dir as Vector2) * t + (edge.out as Vector2) * d

## The cm rectangle [x0, z0, x1, z1] from a to b along the edge, d0 to d1 out.
static func _strip(edge: Dictionary, a: float, b: float, d0: float, d1: float) -> Array:
	var one := _point(edge, a, d0)
	var two := _point(edge, b, d1)
	return [roundi(minf(one.x, two.x)), roundi(minf(one.y, two.y)), roundi(maxf(one.x, two.x)), roundi(maxf(one.y, two.y))]

## A metre rectangle's reach along the edge, in cm from the edge's start.
static func _along(edge: Dictionary, area: Rect2) -> Array:
	var axis := 0 if (edge.dir as Vector2).x != 0.0 else 1
	var start: float = (edge.start as Vector2)[axis]
	return [area.position[axis] * 100.0 - start, area.end[axis] * 100.0 - start]

## The stretches of [a, b] along the edge that a prop standing `d0` to `d1`
## out, from `low` to `high` metres above its floor, may stand on: cut around
## every walking space it would share (MARGIN clear) and every control,
## start and drop it would cover (CLEAR clear), as the lint judges it.
static func _free(edge: Dictionary, a: float, b: float, d0: float, d1: float, low: float, high: float, flat: bool, ground: float, stage: Dictionary) -> Array:
	var area := PropRules.rect(_strip(edge, a, b, d0, d1))
	var foot := {"rect": area, "inner": area.grow(-0.01), "base": ground + low, "top": ground + high, "ground": ground, "flat": flat, "wall": false}
	var cuts: Array = []
	for space: Dictionary in stage.spaces:
		if PropRules.on_walkable(foot, space): cuts.append(_along(edge, (space.rect as Rect2).grow(PropRules.MARGIN)))
	for place: Dictionary in stage.places:
		if PropRules.covers(foot, place): cuts.append(_along(edge, (place.rect as Rect2).grow(PropRules.CLEAR)))
	var stretches: Array = [[a, b]]
	for cut: Array in cuts:
		var kept: Array = []
		for stretch: Array in stretches:
			if float(cut[1]) <= float(stretch[0]) or float(cut[0]) >= float(stretch[1]):
				kept.append(stretch)
				continue
			if float(cut[0]) > float(stretch[0]): kept.append([stretch[0], float(cut[0])])
			if float(cut[1]) < float(stretch[1]): kept.append([float(cut[1]), stretch[1]])
		stretches = kept
	return stretches.filter(func(stretch: Array) -> bool: return float(stretch[1]) - float(stretch[0]) >= SHORTEST)

static func _span(spec: Dictionary, length: float) -> Array:
	var span: Array = spec.get("span", [0.0, 1.0])
	return [float(span[0]) * length, float(span[1]) * length]

## A bank along its edge: [{spec, edge, stretch: [a, b], out: middle cm}].
static func _bank(spec: Dictionary, floors: Dictionary, banks: Array, stage: Dictionary) -> Array:
	var edge := _edge(floors[str(spec.floor)], str(spec.edge))
	var gap := float(spec.get("gap", 0))
	var depth := float(spec.get("depth", BANK_DEPTH))
	var reach := _span(spec, float(edge.length))
	# A back or front bank reaches over the corner onto a side bank.
	if str(spec.edge) in ["back", "front"]:
		for side: Dictionary in banks:
			if str(side.floor) != str(spec.floor): continue
			var over := float(side.get("gap", 0)) + float(side.get("depth", BANK_DEPTH))
			if str(side.edge) == "left" and float(reach[0]) <= 0.0: reach[0] = -over
			if str(side.edge) == "right" and float(reach[1]) >= float(edge.length): reach[1] = float(edge.length) + over
	var height := float(spec.get("height", 12)) / 100.0
	var ground := float(stage.heights.get(str(spec.get("surface", spec.floor)), 0.0))
	var result: Array = []
	for stretch: Array in _free(edge, reach[0], reach[1], gap, gap + depth, float(spec.get("y", 0)) / 100.0 - 0.3, float(spec.get("y", 0)) / 100.0 + height, false, ground, stage):
		var made := _plain(spec)
		made.erase("depth")
		made["surface"] = str(spec.get("surface", spec.floor))
		made["rect"] = _strip(edge, stretch[0], stretch[1], gap, gap + depth)
		result.append({"spec": made, "edge": edge, "stretch": stretch, "out": gap + depth * 0.5, "half": depth * 0.5})
	return result

## A prop at one spot, a row of them or a line along its edge.
static func _prop(spec: Dictionary, floors: Dictionary, banks: Array, stage: Dictionary, taken: Array) -> Array:
	var edge := _edge(floors[str(spec.floor)], str(spec.edge))
	var made := _plain(spec)
	made["surface"] = str(spec.get("surface", spec.floor))
	if str(spec.get("slot", "")) == "trim" and not spec.has("size"): made["size"] = PropRules.TRIM_SIZE
	var line := str(made.kind) in Styles.LINE_KINDS
	var probe: Dictionary = made.duplicate()
	if line:
		probe["from"] = [0, 0]
		probe["to"] = [100, 0]
	else: probe["at"] = [0, 0]
	var extent := Props.extent(probe)
	var across: float = ((extent.rect as Rect2).size.y if line or str(spec.edge) in ["back", "front"] else (extent.rect as Rect2).size.x) * 100.0
	# On the edge's bank (its middle, or anywhere across it with "out"), or
	# just outside the edge.
	var length := float(edge.length)
	var single := not spec.has("spacing") and not line
	var t := float(spec.get("along", 0.5)) * length
	var reach: Array = [t, t] if single else _span(spec, length)
	var under: Array = banks.filter(func(bank: Dictionary) -> bool: return float(bank.stretch[0]) <= float(reach[1]) and float(bank.stretch[1]) >= float(reach[0]))
	var out := float(spec.get("out", float(under[0].out) if not under.is_empty() else across * 0.5 + CLEARANCE))
	# A prop tall enough to hide a pip stands back far enough that its view
	# shadow (PropRules.hides) never reaches its own floor.
	if not spec.has("out"):
		var lifted := made.merged({"y": Props.bank_top(under[0].spec)} if not under.is_empty() else {})
		out = maxf(out, _clear_of_floor(lifted, probe, str(spec.edge), across))
	var on: Array = under.filter(func(bank: Dictionary) -> bool: return absf(out - float(bank.out)) <= float(bank.half))
	if not on.is_empty() and not spec.has("y"): made["y"] = Props.bank_top(on[0].spec)
	if str(spec.edge) == "front" and not spec.has("size"): made["size"] = minf(float(made.get("size", 1.0)), _low_size(made))
	extent = Props.extent(probe.merged({"size": made.get("size", 1.0), "y": made.get("y", 0)}, true))
	if single:
		made["at"] = _cm(_point(edge, t, out))
		return [made]
	var ground := float(stage.heights.get(made.surface, 0.0))
	var low := float(extent.base)
	var stretches: Array = []
	if not on.is_empty():
		for bank: Dictionary in on:
			var a := maxf(float(bank.stretch[0]), float(reach[0]))
			var b := minf(float(bank.stretch[1]), float(reach[1]))
			if b - a >= SHORTEST: stretches.append([a, b])
	else:
		stretches = [reach]
	var result: Array = []
	var index := 0
	for stretch: Array in stretches:
		for free: Array in _free(edge, stretch[0], stretch[1], out - across * 0.5, out + across * 0.5, low, low + float(extent.height), bool(extent.flat), ground, stage):
			if line:
				var inset := float(spec.get("inset", INSET))
				if float(free[1]) - float(free[0]) - inset * 2.0 < SHORTEST: continue
				var piece := made.duplicate()
				piece["from"] = _cm(_point(edge, float(free[0]) + inset, out))
				piece["to"] = _cm(_point(edge, float(free[1]) - inset, out))
				if PropRules.faults(piece, stage).is_empty(): result.append(piece)
				continue
			var count := maxi(1, floori((float(free[1]) - float(free[0])) / float(spec.spacing)))
			var step := (float(free[1]) - float(free[0])) / float(count)
			for slot in range(count):
				var item := made.duplicate()
				item["at"] = _cm(_point(edge, float(free[0]) + step * (float(slot) + 0.5), out))
				if bool(spec.get("vary", false)): Props.vary(item, index, float(item.at[0]))
				index += 1
				if not PropRules.faults(item, stage).is_empty(): continue
				var solid := PropRules.solid(item, stage.heights)
				if taken.any(func(other: Dictionary) -> bool: return PropRules.clash(solid, other)): continue
				result.append(item)
	return result

## How far out (cm) a prop must stand for its camera shadow to keep MARGIN
## off its floor: half its footprint, the margin, and on a front or right edge
## the shadow's reach back over the floor (PropRules.VIEW per metre of height).
static func _clear_of_floor(made: Dictionary, probe: Dictionary, edge: String, across: float) -> float:
	var extent := Props.extent(probe.merged({"size": made.get("size", 1.0), "y": made.get("y", 0)}, true))
	var height := float(extent.base) + float(extent.height)
	if height <= Props.LOW: return 0.0
	var back := {"front": -PropRules.VIEW.y, "right": -PropRules.VIEW.x}.get(edge, 0.0) as float
	return across * 0.5 + PropRules.MARGIN * 100.0 + 1.0 + back * height * 100.0

## The largest size up to the prop's own that keeps it under Props.LOW.
static func _low_size(spec: Dictionary) -> float:
	var unit: Dictionary = spec.duplicate()
	unit["size"] = 1.0
	unit["at"] = [0, 0]
	unit.erase("y")
	var extent := Props.extent(unit)
	var height := float(extent.height) + float(extent.base)
	var lip := float(spec.get("y", 0)) / 100.0
	if height <= 0.0: return 1.0
	return maxf(0.1, (Props.LOW - lip) / height)

## The styled spec with its placing fields taken off.
static func _plain(spec: Dictionary) -> Dictionary:
	var made: Dictionary = spec.duplicate(true)
	for field: String in FIELDS + ["vary"]: made.erase(field)
	return made

static func _cm(point: Vector2) -> Array:
	return [roundi(point.x), roundi(point.y)]

## Props given no "y" whose spot is on a bank of their surface stand on its top.
static func _on_banks(specs: Array) -> Array:
	var banks: Array = specs.filter(func(spec: Dictionary) -> bool: return str(spec.get("kind", "")) == "bank")
	var result: Array = []
	for spec: Dictionary in specs:
		if spec.has("y") or not spec.has("at") or str(spec.get("kind", "")) == "bank":
			result.append(spec)
			continue
		var made := spec
		for bank: Dictionary in banks:
			if str(bank.get("surface", "")) != str(spec.get("surface", "")): continue
			if PropRules.rect(bank.rect).has_point(Vector2(float(spec.at[0]), float(spec.at[1])) / 100.0):
				made = spec.duplicate()
				made["y"] = Props.bank_top(bank)
				break
		result.append(made)
	return result
