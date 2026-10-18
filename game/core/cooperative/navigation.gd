extends RefCounted
## Integer support queries shared by walkers and pushable props. Height changes
## require an authored stair or drop; overlapping islands never act as ladders.
##
## A level's islands, bridges and stairs can be looked up through an index: a
## grid of CELL_CM squares, each holding the islands, the bridges and the
## stairs whose rect touches it, each list in the level's own order. A point
## tests only its own cell's lists, in the same order as the whole level's
## (islands, then bridges, then stairs), and the first match wins as before, so
## the answer is the same as testing every surface. An engine fetches the index
## once per definition (index_for, keyed by its digest; shared by every engine
## and thread, never changed once built) and passes it to at().

## The index grid's square size (cm).
const CELL_CM := 64
## Cells either way of the origin a cell number covers (about 21 km).
const CELL_OFFSET := 16384
## A level with fewer surfaces than this is tested whole: its first island
## usually matches at once, and the lookup costs more than it saves.
const INDEX_FROM_SURFACES := 10
## How many definitions' indexes are kept.
const MAX_INDEXES := 16
static var _indexes: Dictionary = {}
static var _indexes_lock := Mutex.new()

## cells: the level's index_for(); {} tests every surface.
static func at(level: Dictionary, routes: Dictionary, levers: Dictionary, previous: Dictionary, x: int, z: int, slot: String, radius: int, allow_drop: bool = true, cells: Dictionary = {}) -> Dictionary:
	var point := Vector2i(x, z)
	var surface := _support(level, routes, point, slot, previous, 2, cells)
	if surface.is_empty(): return {}
	var samples := [Vector2i(-radius,0),Vector2i(radius,0),Vector2i(0,-radius),Vector2i(0,radius)]
	var diagonal := int(ceil(float(radius) * 0.707107))
	samples.append_array([Vector2i(-diagonal,-diagonal),Vector2i(diagonal,-diagonal),Vector2i(-diagonal,diagonal),Vector2i(diagonal,diagonal)])
	for offset: Vector2i in samples:
		if _support(level, routes, point + offset, slot, surface, radius + 1, cells).is_empty(): return {}
	for obstacle: Dictionary in level.get("obstacles", []):
		if obstacle.surface_id == surface.surface_id and _circle_rect(point, radius, obstacle.rect_cm): return {}
	for zone: Dictionary in level.get("access_zones", []):
		if zone.surface_id == surface.surface_id and zone.owner_slot != slot and _circle_rect(point, radius, zone.rect_cm): return {}
	if allow_drop:
		for drop: Dictionary in level.get("drops", []):
			var enabled := str(drop.get("requires_lever", "")).is_empty() or bool(levers.get(drop.requires_lever, false))
			if drop.surface_id == surface.surface_id and enabled and inside(point, drop.rect_cm):
				var landing := {"x":x,"z":z,"height":int(drop.height_cm),"surface_id":str(drop.destination_surface)}
				return at(level, routes, levers, landing, x, z, slot, radius, false, cells)
	surface["x"] = x
	surface["z"] = z
	return surface

static func _support(level: Dictionary, routes: Dictionary, point: Vector2i, slot: String, previous: Dictionary, tolerance: int = 2, cells: Dictionary = {}) -> Dictionary:
	var old_height := int(previous.get("height", 0))
	# The first island, open bridge or open stair under the point within
	# tolerance of the height it comes from, in that order: of the point's own
	# cell when there is an index, else of the whole level.
	var lists: Variant = [level.islands, level.get("bridges", []), level.get("stairs", [])] if cells.is_empty() else cells.get(_cell(point))
	if lists == null: return {}
	for island: Dictionary in lists[0]:
		if inside(point, island.rect_cm) and absi(int(island.height_cm) - old_height) <= tolerance:
			return {"surface_id":str(island.id),"height":int(island.height_cm)}
	for bridge: Dictionary in lists[1]:
		if bool(routes.get(bridge.id, false)) and _owns(bridge, slot) and inside(point, bridge.rect_cm) and absi(int(bridge.height_cm) - old_height) <= tolerance:
			return {"surface_id":str(bridge.id),"height":int(bridge.height_cm)}
	for stair: Dictionary in lists[2]:
		if not bool(routes.get(stair.id, false)) or not _owns(stair, slot) or not inside(point, stair.rect_cm): continue
		var height := stair_height(stair, point)
		if absi(height - old_height) <= tolerance:
			return {"surface_id":str(stair.id),"height":height}
	return {}

## The level's index (cell -> [islands, bridges, stairs], each in the level's
## order), built on first use for this key; {} (test every surface) for a level
## with fewer than INDEX_FROM_SURFACES. Safe to read from any thread once
## returned.
static func index_for(level: Dictionary, key: String) -> Dictionary:
	_indexes_lock.lock()
	var found: Variant = _indexes.get(key)
	if found == null:
		var count: int = level.get("islands", []).size() + level.get("bridges", []).size() + level.get("stairs", []).size()
		found = _build_index(level) if count >= INDEX_FROM_SURFACES else {}
		if _indexes.size() >= MAX_INDEXES: _indexes.clear()
		_indexes[key] = found
	_indexes_lock.unlock()
	return found

static func _build_index(level: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	var kinds := [level.get("islands", []), level.get("bridges", []), level.get("stairs", [])]
	for kind in range(kinds.size()):
		for surface: Dictionary in kinds[kind]:
			var r: Array = surface.rect_cm
			var low := _cell(Vector2i(int(r[0]), int(r[1])))
			var high := _cell(Vector2i(int(r[2]), int(r[3])))
			for cx in range(low >> 16, (high >> 16) + 1):
				for cz in range(_low16(low), _low16(high) + 1):
					var key := (cx << 16) + cz
					if not cells.has(key): cells[key] = [[], [], []]
					cells[key][kind].append(surface)
	return cells

## The cell holding a point; a rect's corners give the cells it touches
## (inside() counts its edges, so a point on an edge is in a listed cell).
## A cell is one int: its column times 65536 plus its row, each offset to stay
## positive (CELL_OFFSET cells either way of the origin).
static func _cell(point: Vector2i) -> int:
	return ((floori(float(point.x) / CELL_CM) + CELL_OFFSET) << 16) + floori(float(point.y) / CELL_CM) + CELL_OFFSET

static func _low16(cell: int) -> int:
	return cell & 0xFFFF

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
