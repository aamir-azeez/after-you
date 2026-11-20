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
##     edge, or "out" cm from it. "along" is where on the edge (0 to 1). Its
##     foot always rests whole on its bank or the floor's lip, squeezed smaller
##     to fit if need be; a pole with only water there stands in it to the bed.
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
## bank's top. content/dressing/catalog.gd resolve() runs this per stage, then
## settle() on every dressing (placed by hand too), so every reader gets plain
## kit specs that rest on ground.
const ChapterIndex = preload("res://content/chapters/index.gd")
const LevelLayout = preload("res://services/level_layout.gd")
const Props = preload("res://presentation/kit/props.gd")
const PropRules = preload("res://presentation/kit/prop_rules.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const FloorSpots = preload("res://presentation/kit/floor_spots.gd")
## The Lighthouse room's dressing key: its stages come from its own catalog.
const LIGHTHOUSE := "sleeping-lighthouse@1"
const LIGHTHOUSE_ROOM := "sleeping-lighthouse@2"
const EDGES := ["back", "front", "left", "right"]
## Fields that say where a prop goes; never passed on to the kit.
const FIELDS := ["floor", "edge", "along", "spacing", "out", "inset", "span", "gap", "slot"]
## A prop squeezed onto the ground it rests on keeps at least this share of its size.
const LEAST_SIZE := 0.5
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
	return load(str(source[0])).callv(str(source[1]), source.slice(2))

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
	# Its water (the descriptor's water block), so a prop by an edge with no
	# ground under it may stand in the water down to its bed.
	var water := str(ChapterIndex.data(layout_key(key)).get("water", ""))
	if not water.is_empty():
		view["water"] = load(water).DATA
		view["grounds"] = view.water.get("grounds", [])
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
	stage["view"] = view
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
	return settle(_on_banks(result), view)

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
		result.append({"spec": made, "edge": edge, "stretch": stretch, "out": gap + depth * 0.5, "half": depth * 0.5, "near": gap, "far": gap + depth})
	return result

## The cm band out from the edge a prop's foot may rest in: across the bank
## under it (from the floor's lip when the bank starts there), else on the
## lip (PropRules.LIP); a flat prop may lie on the floor too, every other
## kind keeps off it (the walking rule).
static func _rest_band(under: Array, flat: bool) -> Array:
	var grace := PropRules.EDGE_GRACE * 100.0
	var lip := PropRules.LIP * 100.0
	var low := -INF if flat else -grace
	if under.is_empty(): return [low, lip]
	if float(under[0].near) <= lip + grace: return [low, float(under[0].far)]
	return [float(under[0].near), float(under[0].far)]

## Half the cm a prop's foot reaches across its edge: a line's width, any
## other kind's footprint cut to what rests on the ground (Props.FOOT_SHARE).
static func _foot_half(made: Dictionary, probe: Dictionary, edge: String, line: bool) -> float:
	var area: Rect2 = Props.extent(probe.merged({"size": made.get("size", 1.0)}, true)).rect
	var across := (area.size.y if line or edge in ["back", "front"] else area.size.x) * 100.0
	return across * 0.5 * (1.0 if line else float(Props.FOOT_SHARE.get(str(made.kind), 1.0)))

## The cm a pole at plan point `at` (cm), its base `base` m high, reaches down
## to the bed of the water under it; 0 over no water or no deeper bed.
static func _wade(view: Dictionary, at: Vector2, base: float) -> int:
	var block: Dictionary = view.get("water", {})
	if block.is_empty(): return 0
	var Waters = load("res://presentation/kit/water_bodies.gd")
	if str(Waters.body_in(block, at)).is_empty(): return 0
	return maxi(0, roundi((base - float(Waters.bed_in(block, at))) * 100.0))

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
	# Whole on its ground: across its bank, else on the floor's lip, squeezed
	# smaller to fit (at least LEAST_SIZE). A pole that cannot rest stands in
	# the water there down to its bed (Props.WADERS); a boat floats. Anything
	# else that cannot rest is not laid; a line is laid where it is asked and
	# settle() gives it a footing.
	var wade := 0
	# A line off its edge with no bank is given a footing when it settles.
	if str(made.kind) not in Props.FLOATS and not (line and under.is_empty()):
		var band := _rest_band(under, bool(extent.flat))
		var half := _foot_half(made, probe, str(spec.edge), line)
		if float(band[1]) - float(band[0]) < half * 2.0:
			var fit := (float(band[1]) - float(band[0])) / (half * 2.0)
			if fit >= LEAST_SIZE and not line:
				made["size"] = float(made.get("size", 1.0)) * fit
				half *= fit
			elif single and str(made.kind) in Props.WADERS:
				out = maxf(out, PropRules.WATER_RIM * 100.0 + half + CLEARANCE)
				wade = _wade(stage.view, _point(edge, t, out), float(stage.heights.get(made.surface, 0.0)) + float(made.get("y", 0)) / 100.0)
				if wade == 0: return []
			else: return []
		if wade == 0: out = clampf(out, float(band[0]) + half, float(band[1]) - half)
	var on: Array = under.filter(func(bank: Dictionary) -> bool: return out >= float(bank.near) and out <= float(bank.far))
	if not on.is_empty() and not spec.has("y"): made["y"] = Props.bank_top(on[0].spec)
	if str(spec.edge) == "front" and not spec.has("size"): made["size"] = minf(float(made.get("size", 1.0)), _low_size(made))
	extent = Props.extent(probe.merged({"size": made.get("size", 1.0), "y": made.get("y", 0)}, true))
	if single:
		made["at"] = _cm(_point(edge, t, out))
		if wade > 0: made["wade"] = wade
		# Pulled back onto its ground, a prop that would hide a pip is laid low.
		elif PropRules.faults(made, stage).any(func(fault: Dictionary) -> bool: return fault.rule == "hides"):
			made["size"] = minf(float(made.get("size", 1.0)), _low_size(made))
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
				if bool(spec.get("vary", false)): Props.vary(item, index, float(item.at[0]), (edge.dir as Vector2) * step)
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

# --- Settling -------------------------------------------------------------------

## Every prop of one stage's dressing on ground (PropRules.rests()), breaking
## no lint rule (PropRules.faults()) and clear of every prop before it
## (PropRules.meet()), as plain kit specs with rows laid out:
##   - a bank BANK_REACH or nearer its floor is stretched to meet it;
##   - a support post (a "post" under a floor) stands from the ground under it
##     to the floor's underside, else from the water's bed, else is left out;
##   - a pole (Props.WADERS) with water under it and no ground stands in the
##     water down to its bed ("wade"); anything else put out in open water
##     stands as put; a boat with no water lies on ground or is left out; a
##     kind set into what the world builds (Props.FIXTURES) stands as put;
##   - any other prop that floats or stands in another moves to the nearest
##     spot, in rings of SETTLE_STEP cm out to SETTLE_REACH, where it rests,
##     squeezed down to LEAST_SIZE if need be (a line slides across itself,
##     then gives way at its ends; a line standing off its floor's edge with
##     nothing under it gets a footing: a low bank of the stage's own look from
##     the edge out under it); what still cannot stand is left out. A prop
##     given no "y" whose spot is on a bank stands on its top.
## catalog.gd settles every dressing this way stage by stage, placed by an
## edge or by hand, so nothing a reader builds floats or cuts into the stage.
static func settle(specs: Array, view: Dictionary) -> Array:
	var stage := PropRules.scene(view)
	stage["view"] = view
	stage["floors"] = PropRules.grounds(view)
	var all := Props.expand(specs)
	var banks: Dictionary = {}
	var laid: Array = []
	for index in range(all.size()):
		if str(all[index].get("kind", "")) != "bank": continue
		banks[index] = _bank_to_floor(all[index], stage)
		laid.append_array(banks[index])
	stage["banks"] = laid
	var grounds := PropRules.grounds(view, laid.map(func(bank: Dictionary) -> Dictionary: return PropRules.bank_ground(bank, stage.heights)))
	var result: Array = []
	var taken: Array = []
	for index in range(all.size()):
		if banks.has(index):
			result.append_array(banks[index])
			continue
		var made := _settle_one(all[index], stage, grounds, taken)
		if made.is_empty(): continue
		# A line given a footing: the bank first, ground for what follows.
		if made.has("footing"):
			grounds.append(PropRules.bank_ground(made.footing, stage.heights).merged({"name": "bank"}))
			result.append(made.footing)
			made.erase("footing")
		taken.append(PropRules.solid(made, stage.heights))
		result.append(made)
	return result

## Rings of this many cm a settling prop looks out in, to this far.
const SETTLE_STEP := 2.0
const SETTLE_REACH := 40.0
## The sizes a settling prop tries: a low one (under Props.LOW) down to
## LEAST_SIZE, any other the first two.
const SETTLE_SIZES := [1.0, 0.85, 0.7, LEAST_SIZE]
## A bank this near its floor (cm) is stretched to meet it.
const BANK_REACH := 100.0
## A support post stops this far (m) under the walking top of the floor it holds.
const UNDERSIDE := 0.21

static func _settle_one(spec: Dictionary, stage: Dictionary, all_grounds: Array, taken: Array) -> Dictionary:
	var kind := str(spec.get("kind", ""))
	var view: Dictionary = stage.view
	if kind in Props.HUNG or kind in Props.FIXTURES or bool(spec.get("wall", false)): return spec
	spec = _on_bank(spec, stage)
	# Only ground within reach of it can hold it.
	var spot := _spot(spec) / 100.0
	var reach := (SETTLE_REACH + 200.0) / 100.0 if not spec.has("from") else 1000.0
	var grounds: Array = all_grounds.filter(func(ground: Dictionary) -> bool: return (ground.rect as Rect2).grow(reach).has_point(spot))
	if kind == "post" and spec.has("at"):
		var post := _stand_post(spec, stage, grounds)
		if post.is_empty() or post.has("wade_bed"):
			post.erase("wade_bed")
			return post
		spec = post
	# It stays where it was put if it rests there, stands clear and breaks no lint rule.
	if _rests_clear(spec, stage, grounds, taken) and PropRules.faults(spec, stage).is_empty(): return spec
	if spec.has("from") and spec.has("to"): return _settle_line(spec, stage, grounds, taken)
	if not spec.has("at"): return spec
	# Out in open water a pole wades to the bed (a boat floats). A boat with no
	# water under it lies on ground or is left out.
	var wet := not _water_at(view, _spot(spec)).is_empty() and not _centre_on_ground(spec, stage, grounds)
	if wet and Props.WADERS.has(kind):
		var waded := _clear_of_rim(spec, view)
		var wade := _wade(view, _spot(waded), _base(waded, stage))
		if wade > 0: return waded.merged({"wade": wade}, true)
	# Anything else put out in open water stands whole in it, clear of every
	# prop before it, down to its bed: where it was put, else the nearest such
	# spot (rings of WET_STEP cm out to WET_REACH); else it is left out.
	if wet:
		for offset: Vector2 in [Vector2.ZERO] + WET_OFFSETS:
			var moved: Dictionary = spec.merged({"at": _cm(_spot(spec) + offset)}, true) if offset != Vector2.ZERO else spec
			if not _in_water(moved, stage): continue
			var sunk := moved if kind in Props.FLOATS else _to_bed(moved, stage)
			var solid := PropRules.solid(sunk, stage.heights)
			if taken.any(func(other: Dictionary) -> bool: return PropRules.meet(solid, other)) or not PropRules.faults(sunk, stage).is_empty(): continue
			return sunk
		return {}
	if kind in Props.FLOATS: return {}
	var origin := Vector2(float(spec.at[0]), float(spec.at[1]))
	var low := float(Props.extent(spec).height) <= Props.LOW
	for share: float in (SETTLE_SIZES if low else SETTLE_SIZES.slice(0, 2)):
		var sized: Dictionary = spec.duplicate()
		sized["size"] = float(spec.get("size", 1.0)) * share
		for offset: Vector2 in OFFSETS:
			var moved: Dictionary = sized.duplicate()
			moved["at"] = _cm(origin + offset)
			if _rests_clear(moved, stage, grounds, taken) and PropRules.faults(moved, stage).is_empty(): return moved
	return {}

## The rings a settling prop looks out in (cm), nearest first.
static var OFFSETS: Array[Vector2] = FloorSpots.offsets(SETTLE_STEP, int(SETTLE_REACH / SETTLE_STEP))

## Rests on `grounds` and stands in no prop of `taken`.
static func _rests_clear(spec: Dictionary, stage: Dictionary, grounds: Array, taken: Array) -> bool:
	if not PropRules.rests(spec, stage.heights, grounds): return false
	var solid := PropRules.solid(spec, stage.heights)
	return not taken.any(func(other: Dictionary) -> bool: return PropRules.meet(solid, other))

## A prop given no "y" whose spot is on a bank of its surface, on the bank's top.
static func _on_bank(spec: Dictionary, stage: Dictionary) -> Dictionary:
	if spec.has("y") or not spec.has("at"): return spec
	for bank: Dictionary in stage.get("banks", []):
		if str(bank.get("surface", "")) == str(spec.get("surface", "")) and PropRules.rect(bank.rect).has_point(_spot(spec) / 100.0): return spec.merged({"y": Props.bank_top(bank)})
	return spec

## Rings a prop out in open water looks out in for a spot whole in the water.
const WET_STEP := 10.0
const WET_REACH := 150.0
static var WET_OFFSETS: Array[Vector2] = FloorSpots.offsets(WET_STEP, int(WET_REACH / WET_STEP)).slice(1)

## Every foot point of the prop over water, none on a floor.
static func _in_water(spec: Dictionary, stage: Dictionary) -> bool:
	for point: Vector2 in PropRules.foot_points(spec):
		if _water_at(stage.view, point * 100.0).is_empty() or stage.floors.any(func(ground: Dictionary) -> bool: return (ground.rect as Rect2).has_point(point)): return false
	return true

## The prop lowered until it reaches the water's bed, if it stops short.
static func _to_bed(spec: Dictionary, stage: Dictionary) -> Dictionary:
	var bottom := float(stage.heights.get(str(spec.get("surface", "")), 0.0)) + float(Props.extent(spec).base)
	var bed := float(load("res://presentation/kit/water_bodies.gd").bed_in(stage.view.water, _spot(spec)))
	if bottom <= bed + PropRules.BED_GRACE: return spec
	return spec.merged({"y": roundi(float(spec.get("y", 0)) - (bottom - bed) * 100.0)}, true)

## Its spot on ground.
static func _centre_on_ground(spec: Dictionary, stage: Dictionary, grounds: Array) -> bool:
	var base := _base(spec, stage)
	return grounds.any(func(ground: Dictionary) -> bool: return PropRules.rests_on(_spot(spec) / 100.0, base, ground))

## A wading pole moved out past its floor's rim (PropRules.WATER_RIM), so it
## stands in open water clear of the fender or parapet.
static func _clear_of_rim(spec: Dictionary, view: Dictionary) -> Dictionary:
	var r: Array = []
	for island: Dictionary in view.get("islands", []):
		if str(island.id) == str(spec.get("surface", "")): r = island.rect_cm
	if r.is_empty(): return spec
	var at := _spot(spec)
	var need := PropRules.WATER_RIM * 100.0 + float(Props.WADERS[str(spec.kind)]) * float(spec.get("size", 1.0)) * 50.0 + CLEARANCE
	var moved := at
	if at.y < float(r[1]) and float(r[1]) - at.y < need: moved.y = float(r[1]) - need
	elif at.y > float(r[3]) and at.y - float(r[3]) < need: moved.y = float(r[3]) + need
	if at.x < float(r[0]) and float(r[0]) - at.x < need: moved.x = float(r[0]) - need
	elif at.x > float(r[2]) and at.x - float(r[2]) < need: moved.x = float(r[2]) + need
	return spec if moved == at else spec.merged({"at": _cm(moved)}, true)

static func _base(spec: Dictionary, stage: Dictionary) -> float:
	return float(stage.heights.get(str(spec.get("surface", "")), 0.0)) + float(spec.get("y", 0)) / 100.0

static func _spot(spec: Dictionary) -> Vector2:
	var at: Array = spec.get("at", spec.get("from", [0, 0]))
	return Vector2(float(at[0]), float(at[1]))

## The body of water at plan point `at` (cm), or "".
static func _water_at(view: Dictionary, at: Vector2) -> String:
	var block: Dictionary = view.get("water", {})
	return "" if block.is_empty() else str(load("res://presentation/kit/water_bodies.gd").body_in(block, at))

## A bank its floor's lip does not reach, stretched over the gap to the floor
## (BANK_REACH at most): a bank never stands apart from the floor it edges.
## The bank stays as it is and the gap is filled with bank, cut along the
## edge around any control, start or drop it would cover and any walking
## space it would share (pieces under SHORTEST cm left out). The banks it
## comes to, in order.
static func _bank_to_floor(spec: Dictionary, stage: Dictionary) -> Array:
	var floor_rect: Array = []
	for island: Dictionary in stage.view.get("islands", []):
		if str(island.id) == str(spec.get("surface", "")): floor_rect = island.rect_cm
	if floor_rect.is_empty() or not spec.has("rect"): return [spec]
	var r: Array = spec.rect
	var lip := PropRules.LIP * 100.0
	var across_x := float(r[0]) < float(floor_rect[2]) and float(r[2]) > float(floor_rect[0])
	var across_z := float(r[1]) < float(floor_rect[3]) and float(r[3]) > float(floor_rect[1])
	var mid := Vector2(float(r[0] + r[2]) * 0.5, float(r[1] + r[3]) * 0.5)
	var made: Array = r.duplicate()
	if across_x and float(r[1]) > float(floor_rect[3]) + lip:
		var rim := _rim(stage.view, Vector2(mid.x, float(floor_rect[3]) + lip))
		if float(r[1]) > float(floor_rect[3]) + (rim + 1.0 if rim > 0.0 else lip) and float(r[1]) - float(floor_rect[3]) <= BANK_REACH: made[1] = roundi(float(floor_rect[3]) + rim)
	elif across_x and float(r[3]) < float(floor_rect[1]) - lip:
		var rim := _rim(stage.view, Vector2(mid.x, float(floor_rect[1]) - lip))
		if float(r[3]) < float(floor_rect[1]) - (rim + 1.0 if rim > 0.0 else lip) and float(floor_rect[1]) - float(r[3]) <= BANK_REACH: made[3] = roundi(float(floor_rect[1]) - rim)
	elif across_z and float(r[0]) > float(floor_rect[2]) + lip:
		var rim := _rim(stage.view, Vector2(float(floor_rect[2]) + lip, mid.y))
		if float(r[0]) > float(floor_rect[2]) + (rim + 1.0 if rim > 0.0 else lip) and float(r[0]) - float(floor_rect[2]) <= BANK_REACH: made[0] = roundi(float(floor_rect[2]) + rim)
	elif across_z and float(r[2]) < float(floor_rect[0]) - lip:
		var rim := _rim(stage.view, Vector2(float(floor_rect[0]) - lip, mid.y))
		if float(r[2]) < float(floor_rect[0]) - (rim + 1.0 if rim > 0.0 else lip) and float(floor_rect[0]) - float(r[2]) <= BANK_REACH: made[2] = roundi(float(floor_rect[0]) - rim)
	if made == r: return [spec]
	# The gap between the bank and its floor, filled by pieces of bank cut
	# around what they would cover, along the edge they reach.
	var axis := 0 if made[1] != r[1] or made[3] != r[3] else 1
	var gap: Array = made.duplicate()
	for side: int in ([1, 3] if axis == 0 else [0, 2]):
		if made[side] == r[side]: gap[side] = r[(side + 2) % 4]
	var stretched: Dictionary = spec.merged({"rect": gap}, true)
	var pieces: Array = [[float(made[axis]), float(made[axis + 2])]]
	var foot := PropRules.footing(stretched, stage.heights)
	var keep_clear: Array = []
	for space: Dictionary in stage.spaces:
		if PropRules.on_walkable(foot, space): keep_clear.append((space.rect as Rect2).grow(PropRules.MARGIN))
	for place: Dictionary in stage.places:
		if PropRules.covers(foot, place): keep_clear.append((place.rect as Rect2).grow(PropRules.CLEAR))
	for area: Rect2 in keep_clear:
		var cut := [area.position[axis] * 100.0, area.end[axis] * 100.0]
		var kept: Array = []
		for piece: Array in pieces:
			if float(cut[1]) <= float(piece[0]) or float(cut[0]) >= float(piece[1]):
				kept.append(piece)
				continue
			if float(cut[0]) > float(piece[0]): kept.append([piece[0], float(cut[0])])
			if float(cut[1]) < float(piece[1]): kept.append([float(cut[1]), piece[1]])
		pieces = kept
	var result: Array = [spec]
	for piece: Array in pieces:
		if float(piece[1]) - float(piece[0]) < SHORTEST: continue
		var rect: Array = gap.duplicate()
		rect[axis] = roundi(float(piece[0]))
		rect[axis + 2] = roundi(float(piece[1]))
		result.append(spec.merged({"rect": rect}, true))
	return result

## How deep (cm) a floor's edge reaches out at plan point `at` just past it:
## a fender or parapet over water (PropRules.WATER_RIM), else nothing more.
static func _rim(view: Dictionary, at: Vector2) -> float:
	return PropRules.WATER_RIM * 100.0 if not _water_at(view, at).is_empty() else 0.0

## A support post under a floor: from the highest ground under it (else the
## water's bed) up to UNDERSIDE below that floor's walking top. A post with
## no floor over it is any other prop (spec unchanged); {} when it can stand
## on nothing. A post standing on the water's bed comes back marked
## "wade_bed" (taken off before it is laid).
static func _stand_post(spec: Dictionary, stage: Dictionary, grounds: Array) -> Dictionary:
	var at := _spot(spec) / 100.0
	var base := _base(spec, stage)
	var top := base + float(spec.get("height", 100)) / 100.0
	var over := INF
	for island: Dictionary in stage.view.get("islands", []):
		var height := float(island.get("height_cm", 0)) / 100.0
		if PropRules.rect(island.rect_cm).has_point(at) and height > base + 0.3 and absf(height - top) < 0.5: over = minf(over, height - UNDERSIDE)
	if over == INF: return spec
	var floor_y := -INF
	for ground: Dictionary in grounds:
		if (ground.rect as Rect2).has_point(at) and float(ground.top) < over - 0.3: floor_y = maxf(floor_y, float(ground.top))
	var surface := float(stage.heights.get(str(spec.get("surface", "")), 0.0))
	var made: Dictionary = spec.duplicate()
	if floor_y == -INF:
		if _water_at(stage.view, _spot(spec)).is_empty(): return {}
		floor_y = float(load("res://presentation/kit/water_bodies.gd").bed_in(stage.view.water, _spot(spec)))
		made["wade_bed"] = roundi(floor_y * 100.0)
	made["y"] = roundi((floor_y - surface) * 100.0)
	made["height"] = roundi((over - floor_y) * 100.0)
	return made

## A line that floats or stands in a prop slid across itself to the nearest
## place it rests (SETTLE_REACH at most), then cut back from its ends while
## it stands in a prop; {} when it can stand nowhere near.
static func _settle_line(spec: Dictionary, stage: Dictionary, grounds: Array, taken: Array) -> Dictionary:
	var from := Vector2(float(spec.from[0]), float(spec.from[1]))
	var to := Vector2(float(spec.to[0]), float(spec.to[1]))
	var across := (to - from).orthogonal().normalized()
	var along := (to - from).normalized()
	for step in range(int(SETTLE_REACH) + 1):
		for side: float in ([1.0, -1.0] if step > 0 else [1.0]):
			var moved: Dictionary = spec.duplicate()
			moved["from"] = _cm(from + across * float(step) * side)
			moved["to"] = _cm(to + across * float(step) * side)
			if not PropRules.rests(moved, stage.heights, grounds) or not PropRules.faults(moved, stage).is_empty(): continue
			var length := from.distance_to(to)
			var cut := 0.0
			while length - cut >= SHORTEST:
				# Both ends, the start, or the end cut back by "cut" cm.
				for end: int in ([0] if cut == 0.0 else [1, 2, 0]):
					var trimmed: Dictionary = moved.duplicate()
					var a := from + across * float(step) * side + along * (cut if end == 1 else cut * 0.5 if end == 0 else 0.0)
					var b := to + across * float(step) * side - along * (cut if end == 2 else cut * 0.5 if end == 0 else 0.0)
					trimmed["from"] = _cm(a)
					trimmed["to"] = _cm(b)
					var solid := PropRules.solid(trimmed, stage.heights)
					if not taken.any(func(other: Dictionary) -> bool: return PropRules.meet(solid, other)): return trimmed
				cut += 5.0
	# Standing off its floor's edge with nothing under it: a footing.
	var footing := _footing(spec, stage)
	if footing.is_empty(): return {}
	var raised: Dictionary = spec.merged({"y": Props.bank_top(footing)}, true)
	raised["footing"] = footing
	return raised

## A line's footing cm past it, how high a footing stands (cm), and the
## farthest (cm) off its floor's edge a line is given one.
const FOOTING_PAD := 6.0
const FOOTING_HEIGHT := 6
const FOOTING_REACH := 60.0

## A low bank under a line that stands off its floor's edge, parallel to it:
## from the edge out to FOOTING_PAD past the line, along its length, in the
## look of a bank on the same floor (else the plain bank); {} when the line
## runs along no edge of its floor within FOOTING_REACH, or the bank would
## break a lint rule.
static func _footing(spec: Dictionary, stage: Dictionary) -> Dictionary:
	var surface := str(spec.get("surface", ""))
	var r: Array = []
	for island: Dictionary in stage.view.get("islands", []):
		if str(island.id) == surface: r = island.rect_cm
	if r.is_empty(): return {}
	var from := Vector2(float(spec.from[0]), float(spec.from[1]))
	var to := Vector2(float(spec.to[0]), float(spec.to[1]))
	var area: Rect2 = Props.extent(spec).rect
	var half := minf(area.size.x, area.size.y) * 50.0
	var rect: Array = []
	if absf(from.y - to.y) < 1.0:
		var z := from.y
		var x0 := minf(from.x, to.x) - half
		var x1 := maxf(from.x, to.x) + half
		if z < float(r[1]) and float(r[1]) - z <= FOOTING_REACH: rect = [x0, z - half - FOOTING_PAD, x1, float(r[1])]
		elif z > float(r[3]) and z - float(r[3]) <= FOOTING_REACH: rect = [x0, float(r[3]), x1, z + half + FOOTING_PAD]
	elif absf(from.x - to.x) < 1.0:
		var x := from.x
		var z0 := minf(from.y, to.y) - half
		var z1 := maxf(from.y, to.y) + half
		if x < float(r[0]) and float(r[0]) - x <= FOOTING_REACH: rect = [x - half - FOOTING_PAD, z0, float(r[0]), z1]
		elif x > float(r[2]) and x - float(r[2]) <= FOOTING_REACH: rect = [float(r[2]), z0, x + half + FOOTING_PAD, z1]
	if rect.is_empty(): return {}
	var bank := {"kind": "bank", "rect": rect.map(func(value: float) -> int: return roundi(value)), "surface": surface, "height": FOOTING_HEIGHT}
	for other: Dictionary in stage.get("banks", []):
		if str(other.get("surface", "")) != surface: continue
		for field: String in ["side", "top"]:
			if other.has(field): bank[field] = other[field]
		break
	return bank if PropRules.faults(bank, stage).is_empty() else {}
