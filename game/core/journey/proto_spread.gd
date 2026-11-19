extends RefCounted
## PROTOTYPE ONLY (train/falls-rethink-proto, never lands). Spreads a journey
## map so each stage runs past the screen under the close follow camera, and
## lifts each stage onto its own tier. Floors move apart by k (their centres)
## but grow only by s, so the space between them (water, longer crossings)
## grows most. Every point on a floor moves with its floor; each end of a
## crossing moves with the floor it meets, so floors that a crossing joined
## are still joined and every solution stays the same. A crossing keeps its
## width. Heights become kh * height + the floor's tier base.
##   k  [kx, kz]  how far floor centres move apart
##   s  [sx, sz]  how much each floor grows
##   tiers    [[from_x_cm, base_cm], ...]: a floor whose centre lies east of
##            from_x stands on that tier (last match wins)

static func apply(src: Dictionary, k: Vector2, s: Vector2, kh: float, tiers: Array = []) -> Dictionary:
	var out: Dictionary = src.duplicate(true)
	var base := {}
	var rects := {}
	for island: Dictionary in out.islands:
		var r: Array = island.rect_cm
		rects[island.id] = r.duplicate()
		base[island.id] = _tier((float(r[0]) + float(r[2])) * 0.5, tiers)
	var map := {"k": k, "s": s, "rects": rects}
	for island: Dictionary in out.islands:
		var r: Array = island.rect_cm
		var a := _on(map, str(island.id), Vector2(float(r[0]), float(r[1])))
		var b := _on(map, str(island.id), Vector2(float(r[2]), float(r[3])))
		island.rect_cm = [roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y)]
		island.height_cm = _h(island.get("height_cm", 0), kh, base[island.id])
	for bridge: Dictionary in out.get("bridges", []):
		bridge.rect_cm = _crossing(map, bridge.rect_cm, str(bridge.from_surface), str(bridge.to_surface))
		bridge.height_cm = _h(bridge.get("height_cm", 0), kh, base.get(bridge.from_surface, 0))
	for stair: Dictionary in out.get("stairs", []):
		stair.rect_cm = _crossing(map, stair.rect_cm, str(stair.from_surface), str(stair.to_surface))
		stair.from_height_cm = _h(stair.from_height_cm, kh, base.get(stair.from_surface, 0))
		stair.to_height_cm = _h(stair.to_height_cm, kh, base.get(stair.to_surface, 0))
	for slot: String in out.get("starts", {}):
		_point(map, out.starts[slot], "position_cm", "height_cm", "surface_id", kh, base, tiers)
	for spot: Dictionary in out.get("item_spots", []):
		_point(map, spot, "position_cm", "height_cm", "surface_id", kh, base, tiers)
	for stage: Dictionary in out.stages:
		var route: Array = []
		for at: Array in stage.get("receiver_route_cm", []):
			var p := _on(map, _nearest(map, Vector2(float(at[0]), float(at[1]))), Vector2(float(at[0]), float(at[1])))
			route.append([roundi(p.x), roundi(p.y)])
		stage.receiver_route_cm = route
		_walk(map, stage.get("blocks", []), kh, base, tiers)
	return out

## Where plan point `p` goes when it moves with floor `id` (or with the whole
## map when there is no such floor).
static func _on(map: Dictionary, id: String, p: Vector2) -> Vector2:
	if not map.rects.has(id): return p * Vector2(map.k)
	var r: Array = map.rects[id]
	var c := Vector2(float(r[0]) + float(r[2]), float(r[1]) + float(r[3])) * 0.5
	return c * Vector2(map.k) + (p - c) * Vector2(map.s)

static func _nearest(map: Dictionary, p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id: String in map.rects:
		var d := _distance(map.rects[id], p)
		if d < best_d:
			best_d = d
			best = id
	return best

static func _distance(r: Array, p: Vector2) -> float:
	var dx := maxf(maxf(float(r[0]) - p.x, p.x - float(r[2])), 0.0)
	var dz := maxf(maxf(float(r[1]) - p.y, p.y - float(r[3])), 0.0)
	return sqrt(dx * dx + dz * dz)

## A crossing: each end of its length moves with the floor (of the two it
## joins) nearest that end; across, its centre moves with the nearer floor and
## it keeps its width.
static func _crossing(map: Dictionary, r: Array, from: String, to: String) -> Array:
	var x0 := float(r[0])
	var z0 := float(r[1])
	var x1 := float(r[2])
	var z1 := float(r[3])
	var mid := Vector2(x0 + x1, z0 + z1) * 0.5
	var along_x := _along_x(map.rects, from, to, r)
	var ends: Array = [Vector2(x0, mid.y), Vector2(x1, mid.y)] if along_x else [Vector2(mid.x, z0), Vector2(mid.x, z1)]
	var moved: Array = []
	for end: Vector2 in ends: moved.append(_on(map, _closer(map, from, to, end), end))
	var centre := _on(map, _closer(map, from, to, mid), mid)
	if along_x:
		var half := (z1 - z0) * 0.5
		return [roundi(moved[0].x), roundi(centre.y - half), roundi(moved[1].x), roundi(centre.y + half)]
	var half_x := (x1 - x0) * 0.5
	return [roundi(centre.x - half_x), roundi(moved[0].y), roundi(centre.x + half_x), roundi(moved[1].y)]

static func _closer(map: Dictionary, from: String, to: String, p: Vector2) -> String:
	if not map.rects.has(to): return from
	if not map.rects.has(from): return to
	return from if _distance(map.rects[from], p) <= _distance(map.rects[to], p) else to

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
	var p := Vector2(float(at[0]), float(at[1]))
	var surface := str(spot.get(surface_key, ""))
	var lift: int = base[surface] if base.has(surface) else _tier(p.x, tiers)
	var moved := _on(map, surface if map.rects.has(surface) else _nearest(map, p), p)
	spot[at_key] = [roundi(moved.x), roundi(moved.y)]
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
