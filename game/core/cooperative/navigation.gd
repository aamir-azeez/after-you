extends RefCounted
## Integer support queries shared by walkers and pushable props. Height changes
## require an authored stair or drop; overlapping islands never act as ladders.

static func at(level: Dictionary, routes: Dictionary, levers: Dictionary, previous: Dictionary, x: int, z: int, slot: String, radius: int, allow_drop: bool = true) -> Dictionary:
	var point := Vector2i(x, z)
	var surface := _support(level, routes, point, slot, previous)
	if surface.is_empty(): return {}
	var samples := [Vector2i(-radius,0),Vector2i(radius,0),Vector2i(0,-radius),Vector2i(0,radius)]
	var diagonal := int(ceil(float(radius) * 0.707107))
	samples.append_array([Vector2i(-diagonal,-diagonal),Vector2i(diagonal,-diagonal),Vector2i(-diagonal,diagonal),Vector2i(diagonal,diagonal)])
	for offset: Vector2i in samples:
		if _support(level, routes, point + offset, slot, surface, radius + 1).is_empty(): return {}
	for obstacle: Dictionary in level.get("obstacles", []):
		if obstacle.surface_id == surface.surface_id and _circle_rect(point, radius, obstacle.rect_cm): return {}
	for zone: Dictionary in level.get("access_zones", []):
		if zone.surface_id == surface.surface_id and zone.owner_slot != slot and _circle_rect(point, radius, zone.rect_cm): return {}
	if allow_drop:
		for drop: Dictionary in level.get("drops", []):
			var enabled := str(drop.get("requires_lever", "")).is_empty() or bool(levers.get(drop.requires_lever, false))
			if drop.surface_id == surface.surface_id and enabled and inside(point, drop.rect_cm):
				var landing := {"x":x,"z":z,"height":int(drop.height_cm),"surface_id":str(drop.destination_surface)}
				return at(level, routes, levers, landing, x, z, slot, radius, false)
	surface["x"] = x
	surface["z"] = z
	return surface

static func _support(level: Dictionary, routes: Dictionary, point: Vector2i, slot: String, previous: Dictionary, tolerance: int = 2) -> Dictionary:
	var old_height := int(previous.get("height", 0))
	for island: Dictionary in level.islands:
		if inside(point, island.rect_cm) and absi(int(island.height_cm) - old_height) <= tolerance:
			return {"surface_id":str(island.id),"height":int(island.height_cm)}
	for bridge: Dictionary in level.get("bridges", []):
		if bool(routes.get(bridge.id, false)) and _owns(bridge, slot) and inside(point, bridge.rect_cm) and absi(int(bridge.height_cm) - old_height) <= tolerance:
			return {"surface_id":str(bridge.id),"height":int(bridge.height_cm)}
	for stair: Dictionary in level.get("stairs", []):
		if not bool(routes.get(stair.id, false)) or not _owns(stair, slot) or not inside(point, stair.rect_cm): continue
		var height := stair_height(stair, point)
		if absi(height - old_height) <= tolerance:
			return {"surface_id":str(stair.id),"height":height}
	return {}

static func stair_height(stair: Dictionary, point: Vector2i) -> int:
	var axis := 0 if stair.axis == "x" else 1
	var coordinate := point.x if axis == 0 else point.y
	var fraction := clampf(float(coordinate - int(stair.rect_cm[axis])) / float(int(stair.rect_cm[axis + 2]) - int(stair.rect_cm[axis])), 0.0, 1.0)
	return roundi(lerpf(float(stair.from_height_cm), float(stair.to_height_cm), fraction))

static func inside(point: Vector2i, rect: Array) -> bool:
	return point.x >= int(rect[0]) and point.y >= int(rect[1]) and point.x <= int(rect[2]) and point.y <= int(rect[3])

static func _owns(route: Dictionary, slot: String) -> bool:
	return str(route.get("owner_slot", "")).is_empty() or route.owner_slot == slot

static func _circle_rect(point: Vector2i, radius: int, rect: Array) -> bool:
	var closest := Vector2i(clampi(point.x, int(rect[0]), int(rect[2])), clampi(point.y, int(rect[1]), int(rect[3])))
	return point.distance_squared_to(closest) < radius * radius
