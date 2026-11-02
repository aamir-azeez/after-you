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
## going round `solids` grown by `clearance`, off the ground under `overhead`
## (parts hanging too low to hop beneath: a pip standing under one first
## leaves by its nearest open side) and only where `walkable` (Vector2 in this
## frame -> bool) lets the pip stand. Empty when there is no way round (or
## `from` stands nearer a solid than `clearance`, or `to` in a solid's room,
## under an overhead part or off the ground).
static func route(from: Vector3, to: Vector3, solids: Array[Rect2], clearance: float, walkable: Callable, overhead: Array[Rect2] = []) -> Array[Vector3]:
	var start := Vector2(from.x, from.z)
	var goal := Vector2(to.x, to.z)
	for rect: Rect2 in overhead:
		if rect.has_point(start): return _out_from_under(from, to, rect.grow(TURN_OUT), solids, clearance, walkable, overhead)
	var blocked: Array[Rect2] = solids.duplicate()
	for rect: Rect2 in overhead: blocked.append(rect.grow(-clearance))
	# A leg may graze the pip's room round a solid, never cut into it.
	var rooms: Array[Rect2] = []
	for rect: Rect2 in blocked: rooms.append(rect.grow(clearance - 0.01))
	if _inside(goal, rooms) or not walkable.call(goal): return []
	# A pip may stand in a room's square corner, as far from the solid as it may
	# walk: its first leg then keeps that far from the solid.
	var leaving: Array[Rect2] = []
	var near: Array[Rect2] = []
	for index in range(blocked.size()):
		if not rooms[index].has_point(start): leaving.append(rooms[index])
		elif _distance(blocked[index], start) < clearance - 0.01: return []
		else: near.append(blocked[index])
	var nodes: Array[Vector2] = [start, goal]
	for rect: Rect2 in blocked:
		var out := rect.grow(clearance + TURN_OUT)
		for corner: Vector2 in [out.position, Vector2(out.end.x, out.position.y), out.end, Vector2(out.position.x, out.end.y)]:
			if not _inside(corner, rooms) and walkable.call(corner): nodes.append(corner)
	# The shortest way clear of the solids, its legs then checked for ground (the
	# costly part, so only along a way that might be taken); a leg off the
	# ground is struck out and the next shortest tried.
	var off := {}
	var clear := {}
	var grounded := {}
	var way := PackedInt32Array()
	while way.is_empty():
		way = _shortest(nodes, rooms, leaving, near, clearance - 0.01, off, clear)
		if way.is_empty(): return []
		for index in range(1, way.size()):
			var leg := Vector2i(mini(way[index - 1], way[index]), maxi(way[index - 1], way[index]))
			if not grounded.has(leg): grounded[leg] = _grounded(nodes[leg.x], nodes[leg.y], walkable)
			if grounded[leg]: continue
			off[leg] = true
			way = PackedInt32Array()
			break
	var result: Array[Vector3] = [from]
	for index in range(1, way.size()):
		var a: Vector2 = nodes[way[index - 1]]
		var b: Vector2 = nodes[way[index]]
		var hops := maxi(1, ceili(a.distance_to(b) / STRIDE))
		for hop in range(1, hops + 1):
			var at := a.lerp(b, float(hop) / hops)
			result.append(Vector3(at.x, 0.0, at.y))
	return result

## From under an overhead part (`out` is its ground grown by TURN_OUT): out by
## the nearest side with a way out and a way on, then round as from anywhere.
static func _out_from_under(from: Vector3, to: Vector3, out: Rect2, solids: Array[Rect2], clearance: float, walkable: Callable, overhead: Array[Rect2]) -> Array[Vector3]:
	var exits: Array[Vector3] = [Vector3(out.position.x, 0, from.z), Vector3(out.end.x, 0, from.z), Vector3(from.x, 0, out.position.y), Vector3(from.x, 0, out.end.y)]
	exits.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(from) < b.distance_squared_to(from))
	for exit: Vector3 in exits:
		var way := route(from, exit, solids, clearance, walkable)
		if way.is_empty(): continue
		var on := route(exit, to, solids, clearance, walkable, overhead)
		if on.is_empty(): continue
		way.append_array(on.slice(1))
		return way
	return []

## The node indices from 0 (the start) to 1 (the goal) by the shortest legs
## that cut no room and are not `off` (Vector2i(low, high) -> true), the first
## keeping out of `leaving` and `gap` from each of `near`, or empty; `clear`
## remembers which legs cut nothing for the next try. A handful of corners, so
## a plain Dijkstra.
static func _shortest(nodes: Array[Vector2], rooms: Array[Rect2], leaving: Array[Rect2], near: Array[Rect2], gap: float, off: Dictionary, clear: Dictionary) -> PackedInt32Array:
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
			var leg := Vector2i(mini(at, next), maxi(at, next))
			if best[at] + length >= best[next] or off.has(leg): continue
			if not clear.has(leg): clear[leg] = _clear(nodes[at], nodes[next], rooms) if at != 0 else _keeps(nodes[at], nodes[next], near, gap) and _clear(nodes[at], nodes[next], leaving)
			if clear[leg]:
				best[next] = best[at] + length
				back[next] = at
	var way := PackedInt32Array([1])
	while way[0] != 0: way.insert(0, back[way[0]])
	return way

## How far `point` is outside `rect` (0 inside).
static func _distance(rect: Rect2, point: Vector2) -> float:
	return point.distance_to(Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y)))

static func _inside(point: Vector2, rooms: Array[Rect2]) -> bool:
	for room: Rect2 in rooms:
		if room.has_point(point): return true
	return false

## Whether a leg cuts no solid's room.
static func _clear(a: Vector2, b: Vector2, rooms: Array[Rect2]) -> bool:
	for room: Rect2 in rooms:
		if _cuts(a, b, room): return false
	return true

## Whether a leg has ground all along.
static func _grounded(a: Vector2, b: Vector2, walkable: Callable) -> bool:
	var samples := ceili(a.distance_to(b) / SAMPLE)
	for sample in range(1, samples):
		if not walkable.call(a.lerp(b, float(sample) / samples)): return false
	return true

## Whether the segment from `a` to `b` stays `gap` from every rect of `near`.
static func _keeps(a: Vector2, b: Vector2, near: Array[Rect2], gap: float) -> bool:
	for rect: Rect2 in near:
		if _cuts(a, b, rect) or minf(_distance(rect, a), _distance(rect, b)) < gap: return false
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			if corner.distance_to(Geometry2D.get_closest_point_to_segment(corner, a, b)) < gap: return false
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
