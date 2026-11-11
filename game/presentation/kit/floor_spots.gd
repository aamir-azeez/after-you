extends RefCounted
## World kit: finding a clear spot on a stage's floor for something small and
## flat, shared by the pair tags (kit/pair_tags.gd) and the ownership marks
## (kit/owner_mark.gd), so both keep clear of each other and of the stage the
## same way.
##
## find() tries a spot's preferred places in order (its ends), and around
## each the nearest offsets first, rings of STEP outward; it takes the first
## spot that lies wholly on a floor of its own (islands at its height, a
## crossing only when asked and only the one under its place, or the floors
## its surfaces name) and keeps `gap` from every thing to avoid and every
## spot already taken. With no clear spot it returns the one that clashes
## least, with what it runs into, so callers and tests can name the clash.
##
## Things to avoid and taken spots are plain data: {rect} or {centre, radius},
## an optional y (only things within 0.3 m of a spot's floor count) and `what`
## (named in a clash). Presentation only: nothing here feeds the simulation.

## A floor's edge trims and strips run this far in from its rectangle.
const FLOOR_INSET := 0.045
## Things this much higher or lower than a spot's floor never meet it.
const SAME_FLOOR := 0.3

## Every floor of `view`: islands, and crossings (marked "crossing"), at their heights.
static func floors_of(view: Dictionary) -> Array:
	var found: Array = []
	for island: Dictionary in view.get("islands", []): found.append({"rect": rect_of(island.rect_cm), "y": float(island.get("height_cm", 0)) / 100.0, "id": str(island.id), "crossing": false})
	for route: Dictionary in view.get("bridges", []): found.append({"rect": rect_of(route.rect_cm), "y": float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0, "id": str(route.id), "crossing": true})
	return found

## The stage's own fixed things a spot keeps clear of: stairs (and their
## steps), obstacles and drops, with heights where the stage gives them.
static func stage_things(view: Dictionary) -> Array:
	var found: Array = []
	var heights: Dictionary = {}
	for island: Dictionary in view.get("islands", []): heights[str(island.id)] = float(island.get("height_cm", 0)) / 100.0
	for stair: Dictionary in view.get("stairs", []): found.append({"rect": rect_of(stair.rect_cm), "what": "stair " + str(stair.id)})
	for key: String in ["obstacles", "drops"]:
		for thing: Dictionary in view.get(key, []):
			var entry := {"rect": rect_of(thing.rect_cm), "what": "%s %s" % [key.trim_suffix("s"), thing.get("id", "")]}
			if heights.has(str(thing.get("surface_id", ""))): entry["y"] = heights[str(thing.surface_id)]
			found.append(entry)
	return found

## Radius of a handoff's ring, where the two spirits meet.
const HANDOFF_RADIUS := 0.6

## Everything on a stage a small flat thing keeps clear of: its stage_things,
## each control's disc (a pad its own radius, a light receiver 0.3 m, any
## other control 0.2 m), the goal's disc, the handoff ring `handoff_reach`
## past its radius and the world's own scenery (_pair_keep_clear). Each disc
## names what it belongs to as "owner", so a marker of that thing may come
## closer to it.
static func scenery(view: Dictionary, world: Object, handoff_reach: float) -> Array:
	var found := stage_things(view)
	var pads: Array = view.get("pressure_pads", []) + view.get("ball_pads", [])
	var receivers: Array = view.get("optics", {}).get("receivers", view.get("optical_field", {}).get("receivers", []))
	var entities: Dictionary = {}
	for entity: Dictionary in pads + view.get("levers", []) + view.get("controls", []) + receivers:
		if entity.has("id") and entity.has("position_cm"): entities[str(entity.id)] = entity
	var ids_of := func(list: Array) -> Array: return list.map(func(entity: Dictionary) -> String: return str(entity.get("id", "")))
	var levers: Array = ids_of.call(view.get("levers", []))
	var pad_ids: Array = ids_of.call(pads)
	var receiver_ids: Array = ids_of.call(receivers)
	for id: String in entities:
		var entity: Dictionary = entities[id]
		var at: Vector3 = world.call(&"_pair_control_anchor", entity)
		var radius := 0.2
		if id in levers: radius = 0.2
		elif id in pad_ids: radius = float(entity.get("radius_cm", 20)) / 100.0
		elif id in receiver_ids: radius = 0.3
		found.append({"centre": flat(at), "radius": radius, "y": at.y, "what": "control " + id, "owner": id})
	var goal: Dictionary = view.get("goal", {})
	if goal.has("position_cm"): found.append({"centre": Vector2(float(goal.position_cm[0]), float(goal.position_cm[1])) / 100.0, "radius": float(goal.get("radius_cm", 40)) / 100.0, "what": "the goal", "owner": str(goal.get("id", "goal"))})
	var handoff: Variant = view.get("handoff")
	if handoff is Dictionary and handoff.has("position_cm"): found.append({"centre": Vector2(float(handoff.position_cm[0]), float(handoff.position_cm[1])) / 100.0, "radius": HANDOFF_RADIUS + handoff_reach, "what": "the handoff", "owner": "handoff"})
	found.append_array(world.call(&"_pair_keep_clear"))
	return found

## The nearest clear spot `size` across (x and z) to the first of
## `spec.ends` that has one. spec: {size: Vector2, ends: Array of Vector3,
## surfaces: Array of floor ids also allowed, on_crossing: bool (the crossing
## under a place may hold it), gap, step, rings, fine (sixteen directions, not eight)}. Returns {at (floor point of
## its centre), rect, clash (Array of what it runs into; empty when clear)}.
static func find(spec: Dictionary, floors: Array, things: Array, taken: Array) -> Dictionary:
	var size: Vector2 = spec.size
	var gap := float(spec.get("gap", 0.05))
	var step := float(spec.get("step", 0.12))
	var rings := int(spec.get("rings", 10))
	var surfaces: Array = spec.get("surfaces", [])
	var best := {"cost": INF}
	var ends: Array = spec.ends
	for end in range(ends.size()):
		var at: Vector3 = ends[end]
		# Only what lies within reach of this place can meet a spot found from it.
		var reach := maxf(size.x, size.y) + step * float(rings) + 0.6
		var close := things.filter(func(thing: Dictionary) -> bool: return near(thing, flat(at), reach))
		var close_taken := taken.filter(func(thing: Dictionary) -> bool: return near(thing, flat(at), reach))
		# Islands at its height, and a crossing only when asked and its place is
		# on it: a spot never lies on a crossing that may not be there.
		var home := floors.filter(func(f: Dictionary) -> bool: return absf(float(f.y) - at.y) < 0.06 and (f.rect as Rect2).grow(reach).has_point(flat(at)) and (not f.crossing or (bool(spec.get("on_crossing", false)) and (f.rect as Rect2).grow(0.05).has_point(flat(at)))))
		for id: String in surfaces:
			for f: Dictionary in floors:
				if f.id == id and not f.crossing and f not in home: home.append(f)
		for offset: Vector2 in offsets(step, rings, bool(spec.get("fine", false))):
			var centre := flat(at) + offset
			var rect := Rect2(centre - size * 0.5, size)
			var y := at.y
			for f: Dictionary in home:
				if (f.rect as Rect2).has_point(centre): y = float(f.y)
			var standing := home.filter(func(f: Dictionary) -> bool: return absf(float(f.y) - y) < 0.06)
			var found := clash(rect, y, standing, close, close_taken, gap)
			var cost := float(found.size()) * 100.0 + offset.length() + float(end) * 10.0
			if cost < float(best.cost): best = {"cost": cost, "at": Vector3(centre.x, y, centre.y), "rect": rect, "clash": found}
			if found.is_empty(): break
		if (best.clash as Array).is_empty(): break
	return {"at": best.at, "rect": best.rect, "clash": best.clash}

## What `rect` at height `y` runs into: its floor's edge, a thing to avoid,
## a spot already taken.
static func clash(rect: Rect2, y: float, home: Array, things: Array, taken: Array, gap: float) -> Array:
	var found: Array = []
	var inside := not home.is_empty()
	for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]:
		if not home.any(func(f: Dictionary) -> bool: return (f.rect as Rect2).grow(-FLOOR_INSET).has_point(corner)): inside = false
	if not inside: found.append("off its floor" if not home.is_empty() else "off its floor (no floor at %.2f m here)" % y)
	var wide := rect.grow(gap)
	for thing: Dictionary in things + taken:
		if thing.has("y") and absf(float(thing.y) - y) > SAME_FLOOR: continue
		if hits(wide, thing): found.append(str(thing.what))
	return found

## Whether `rect` meets `thing` ({rect} or {centre, radius}).
static func hits(rect: Rect2, thing: Dictionary) -> bool:
	if thing.has("rect"): return rect.intersects(thing.rect)
	var centre: Vector2 = thing.centre
	var nearest := Vector2(clampf(centre.x, rect.position.x, rect.end.x), clampf(centre.y, rect.position.y, rect.end.y))
	return nearest.distance_to(centre) < float(thing.radius)

## Whether `thing` lies within `reach` of `at`.
static func near(thing: Dictionary, at: Vector2, reach: float) -> bool:
	if thing.has("rect"): return (thing.rect as Rect2).grow(reach).has_point(at)
	return (thing.centre as Vector2).distance_to(at) <= reach + float(thing.radius)

## Its place, then rings of `step` in eight directions, nearest first.
## With `fine`, eight more directions between those, a ring's own distance
## out, and every offset in order of its true distance.
static func offsets(step: float, rings: int, fine: bool = false) -> Array[Vector2]:
	var found: Array[Vector2] = [Vector2.ZERO]
	for ring in range(1, rings + 1):
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, -1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			found.append(direction * step * float(ring))
		if fine:
			for direction: Vector2 in [Vector2(2, 1), Vector2(-2, 1), Vector2(2, -1), Vector2(-2, -1), Vector2(1, 2), Vector2(-1, 2), Vector2(1, -2), Vector2(-1, -2)]:
				found.append(direction.normalized() * step * float(ring))
	if not fine: return found
	# Truly nearest first (a diagonal lies farther out than its ring), ties in list order.
	var order := range(found.size())
	order.sort_custom(func(a: int, b: int) -> bool: return found[a].length() < found[b].length() - 0.000001 or (absf(found[a].length() - found[b].length()) <= 0.000001 and a < b))
	var sorted: Array[Vector2] = []
	for index: int in order: sorted.append(found[index])
	return sorted

static func flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)

static func rect_of(r: Array) -> Rect2:
	return Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)
