extends RefCounted
## PROTOTYPE ONLY (train/falls-rethink-proto, never lands). Spreads a journey
## map so each stage runs past the screen under the close follow camera, and
## lifts each stage onto its own tier. Along x, one monotonic map stretches the
## open water between floors by `gap` and the floors themselves only by
## `grow`; across, everything stretches by kz. Because one map moves every
## point, floors that touched still touch and every solution stays the same.
## A crossing keeps its width (only its length stretches). Heights become
## kh * height + the floor's tier base.
##   tiers    [[from_x_cm, base_cm], ...]: a floor whose centre lies east of
##            from_x stands on that tier (last match wins)
static func apply(src: Dictionary, gap: float, grow: float, kz: float, kh: float, tiers: Array = []) -> Dictionary:
	var out: Dictionary = src.duplicate(true)
	var base := {}
	var spans: Array = []
	var rects := {}
	for island: Dictionary in out.islands:
		var r: Array = island.rect_cm
		rects[island.id] = r.duplicate()
		base[island.id] = _tier((float(r[0]) + float(r[2])) * 0.5, tiers)
		spans.append([float(r[0]), float(r[2])])
	var map := {"knots": _knots(spans, gap, grow), "kz": kz}
	for island: Dictionary in out.islands:
		island.rect_cm = _rect(map, island.rect_cm)
		island.height_cm = _h(island.get("height_cm", 0), kh, base[island.id])
	for bridge: Dictionary in out.get("bridges", []):
		bridge.rect_cm = _crossing(map, bridge.rect_cm, _along_x(rects, str(bridge.from_surface), str(bridge.to_surface), bridge.rect_cm))
		bridge.height_cm = _h(bridge.get("height_cm", 0), kh, base.get(bridge.from_surface, 0))
	for stair: Dictionary in out.get("stairs", []):
		stair.rect_cm = _crossing(map, stair.rect_cm, str(stair.axis) == "x")
		stair.from_height_cm = _h(stair.from_height_cm, kh, base.get(stair.from_surface, 0))
		stair.to_height_cm = _h(stair.to_height_cm, kh, base.get(stair.to_surface, 0))
	for slot: String in out.get("starts", {}):
		_point(map, out.starts[slot], "position_cm", "height_cm", "surface_id", kh, base, tiers)
	for spot: Dictionary in out.get("item_spots", []):
		_point(map, spot, "position_cm", "height_cm", "surface_id", kh, base, tiers)
	for stage: Dictionary in out.stages:
		var route: Array = []
		for at: Array in stage.get("receiver_route_cm", []): route.append([roundi(_x(map, float(at[0]))), roundi(float(at[1]) * kz)])
		stage.receiver_route_cm = route
		_walk(map, stage.get("blocks", []), kh, base, tiers)
	return out

## The x map's knots [[x, x'], ...]: slope `grow` where any floor lies,
## `gap` over open water.
static func _knots(spans: Array, gap: float, grow: float) -> Array:
	var edges: Array = []
	for span: Array in spans: edges.append_array(span)
	edges.sort()
	var knots: Array = [[float(edges[0]), float(edges[0]) * gap]]
	for index in range(1, edges.size()):
		var a := float(edges[index - 1])
		var b := float(edges[index])
		if b <= a: continue
		var covered := spans.any(func(span: Array) -> bool: return span[0] <= a and span[1] >= b)
		knots.append([b, float(knots.back()[1]) + (b - a) * (grow if covered else gap)])
	return knots

static func _x(map: Dictionary, x: float) -> float:
	var knots: Array = map.knots
	if x <= float(knots[0][0]): return float(knots[0][1]) + (x - float(knots[0][0])) * 2.0
	for index in range(1, knots.size()):
		if x <= float(knots[index][0]):
			var a: Array = knots[index - 1]
			var b: Array = knots[index]
			return lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(knots.back()[1]) + (x - float(knots.back()[0])) * 2.0

static func _rect(map: Dictionary, r: Array) -> Array:
	return [roundi(_x(map, float(r[0]))), roundi(float(r[1]) * map.kz), roundi(_x(map, float(r[2]))), roundi(float(r[3]) * map.kz)]

## A crossing stretches along its length; across, it keeps its width and only
## its centre moves. A square stop or stone stretches whole.
static func _crossing(map: Dictionary, r: Array, along_x: bool) -> Array:
	var out := _rect(map, r)
	var w := float(r[2]) - float(r[0])
	var d := float(r[3]) - float(r[1])
	if maxf(w, d) < 1.5 * minf(w, d): return out
	if along_x:
		var mid := (float(r[1]) + float(r[3])) * 0.5 * float(map.kz)
		out[1] = roundi(mid - d * 0.5)
		out[3] = roundi(mid + d * 0.5)
	else:
		var mid := _x(map, (float(r[0]) + float(r[2])) * 0.5)
		out[0] = roundi(mid - w * 0.5)
		out[2] = roundi(mid + w * 0.5)
	return out

static func _walk(map: Dictionary, value: Variant, kh: float, base: Dictionary, tiers: Array) -> void:
	if value is Array:
		for item: Variant in value: _walk(map, item, kh, base, tiers)
	elif value is Dictionary:
		var spot: Dictionary = value
		if spot.has("at") and spot.has("surface"):
			_point(map, spot, "at", "height", "surface", kh, base, tiers)
		for key: Variant in spot:
			if key != "at": _walk(map, spot[key], kh, base, tiers)

static func _point(map: Dictionary, spot: Dictionary, at_key: String, height_key: String, surface_key: String, kh: float, base: Dictionary, tiers: Array) -> void:
	var at: Array = spot[at_key]
	var surface := str(spot.get(surface_key, ""))
	var lift: int = base[surface] if base.has(surface) else _tier(float(at[0]), tiers)
	spot[at_key] = [roundi(_x(map, float(at[0]))), roundi(float(at[1]) * float(map.kz))]
	spot[height_key] = _h(spot.get(height_key, 0), kh, lift)

static func _h(height: Variant, kh: float, lift: int) -> int:
	return roundi(float(height) * kh) + lift

static func _along_x(rects: Dictionary, from: String, to: String, r: Array) -> bool:
	if rects.has(from) and rects.has(to):
		var a: Array = rects[from]
		var b: Array = rects[to]
		var gap_x := maxf(float(b[0]) - float(a[2]), float(a[0]) - float(b[2]))
		var gap_z := maxf(float(b[1]) - float(a[3]), float(a[1]) - float(b[3]))
		return gap_x >= gap_z
	return float(r[2]) - float(r[0]) >= float(r[3]) - float(r[1])

static func _tier(x: float, tiers: Array) -> int:
	var found := 0
	for tier: Array in tiers:
		if x >= float(tier[0]): found = int(tier[1])
	return found