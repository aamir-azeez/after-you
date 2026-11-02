extends RefCounted
## The way round a keepsake to where its ride starts, for an Explore action
## pressed beside or behind it (keepsake_builder.gd ride_start()): the shortest
## line on the grass round the keepsake's solids that stays where the pip may
## walk, cut into hops. The layer (presentation/home_keepsake_layer.gd) hops the
## pip along it before the ride's beats. Static, in the keepsake's own frame (x
## and z), and run once per press, never per frame.

## How far past the pip's walking room a turn keeps from a solid's corner.
const TURN_OUT := 0.03
## The longest hop, how long each takes and how high it bounces.
const STRIDE := 0.4
const HOP_TIME := 0.16
const HOP_HEIGHT := 0.1
## How often a leg is checked for ground.
const SAMPLE := 0.15

## Points from `from` to `to`, `from` first and no two more than STRIDE apart,
## going round `solids` grown by `clearance` and only where `walkable` (Vector2
## in this frame -> bool) lets the pip stand. Empty when there is no way round
## (or `from` stands in a solid's room, or `to` off the ground).
static func route(from: Vector3, to: Vector3, solids: Array[Rect2], clearance: float, walkable: Callable) -> Array[Vector3]:
	var start := Vector2(from.x, from.z)
	var goal := Vector2(to.x, to.z)
	# A leg may graze the pip's room round a solid, never cut into it.
	var rooms: Array[Rect2] = []
	for rect: Rect2 in solids: rooms.append(rect.grow(clearance - 0.01))
	if _inside(start, rooms) or _inside(goal, rooms) or not walkable.call(goal): return []
	var nodes: Array[Vector2] = [start, goal]
	for rect: Rect2 in solids:
		var out := rect.grow(clearance + TURN_OUT)
		for corner: Vector2 in [out.position, Vector2(out.end.x, out.position.y), out.end, Vector2(out.position.x, out.end.y)]:
			if not _inside(corner, rooms) and walkable.call(corner): nodes.append(corner)
	var way := _shortest(nodes, rooms, walkable)
	if way.is_empty(): return []
	var result: Array[Vector3] = [from]
	for index in range(1, way.size()):
		var a: Vector2 = nodes[way[index - 1]]
		var b: Vector2 = nodes[way[index]]
		var hops := maxi(1, ceili(a.distance_to(b) / STRIDE))
		for hop in range(1, hops + 1):
			var at := a.lerp(b, float(hop) / hops)
			result.append(Vector3(at.x, 0.0, at.y))
	return result

## The node indices from 0 (the start) to 1 (the goal) by the shortest clear
## legs, or empty. A handful of corners, so a plain Dijkstra.
static func _shortest(nodes: Array[Vector2], rooms: Array[Rect2], walkable: Callable) -> PackedInt32Array:
	var count := nodes.size()
	var best := PackedFloat32Array()
	best.resize(count)
	best.fill(INF)
	var back := PackedInt32Array()
	back.resize(count)
	back.fill(-1)
	var done := PackedByteArray()
	done.resize(count)
	best[0] = 0.0
	while true:
		var at := -1
		for index in range(count):
			if done[index] == 0 and best[index] < INF and (at < 0 or best[index] < best[at]): at = index
		if at < 0: return PackedInt32Array()
		if at == 1: break
		done[at] = 1
		for next in range(count):
			if done[next] == 1 or next == at: continue
			var length := nodes[at].distance_to(nodes[next])
			if best[at] + length < best[next] and _clear(nodes[at], nodes[next], rooms, walkable):
				best[next] = best[at] + length
				back[next] = at
	var way := PackedInt32Array([1])
	while way[0] != 0: way.insert(0, back[way[0]])
	return way

static func _inside(point: Vector2, rooms: Array[Rect2]) -> bool:
	for room: Rect2 in rooms:
		if room.has_point(point): return true
	return false

## Whether a leg cuts no solid's room and has ground all along.
static func _clear(a: Vector2, b: Vector2, rooms: Array[Rect2], walkable: Callable) -> bool:
	for room: Rect2 in rooms:
		if _cuts(a, b, room): return false
	var samples := ceili(a.distance_to(b) / SAMPLE)
	for sample in range(1, samples):
		if not walkable.call(a.lerp(b, float(sample) / samples)): return false
	return true

## Whether the segment from `a` to `b` passes through the inside of `room`
## (touching an edge or a corner is fine).
static func _cuts(a: Vector2, b: Vector2, room: Rect2) -> bool:
	var enter := 0.0
	var leave := 1.0
	var along := b - a
	for axis in range(2):
		var low: float = room.position[axis]
		var high: float = room.end[axis]
		if is_zero_approx(along[axis]):
			if a[axis] <= low or a[axis] >= high: return false
			continue
		var first: float = (low - a[axis]) / along[axis]
		var second: float = (high - a[axis]) / along[axis]
		enter = maxf(enter, minf(first, second))
		leave = minf(leave, maxf(first, second))
		if enter >= leave: return false
	return true
