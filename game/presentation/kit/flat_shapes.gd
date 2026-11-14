extends RefCounted
## Small flat shapes, each a few triangles round its own middle, lying flat
## (face up, +y) within its half sizes: the falling effect's (kit/fall_effect.gd)
## and the trails' (kit/trail_kit.gd) one shape library. Built once per use and
## baked into their meshes; no node or GPU resource here.
##
## Most lie long along x; a drop and a seed lie along z, the end that falls
## first at +z once a fall leans them up. The trail board's silhouettes
## (art/trail-shapes): leaf, raindrop, a four point sparkle, an eight arm snow
## mark, a three lobed fluff puff and a pair of joined notes.
const Look = preload("res://presentation/spirit_look.gd")

## A shape's edge shade, a bar's shade, and how far out (share of the way
## from the middle to the edge) with_edge()'s band starts.
const RIM_SHADE := 0.62
const BAR_SHADE := 0.81
const EDGE_FROM := 0.72
const NAMES: Array[StringName] = [&"petal", &"leaf", &"snowflake", &"star", &"raindrop", &"seed_fluff", &"sparkle", &"snow_mark", &"puff", &"notes"]

## One shape within `size` (x to size.x, z to size.z, y to size.y): {"vertices",
## "normals", "indices"}, and "shades" for the shapes built from fans, discs
## and bars: each vertex's shade, 1 in the middle and RIM_SHADE round the
## edge (bars a flat BAR_SHADE). with_edge() keeps the middle at full colour
## and darkens only a thin outer band, so a mark reads against a floor of its
## own colour. An unknown name is a petal.
## `one` (a shape) with a darker outer band: each triangle from a middle
## (shade 1) to two edge points is split at EDGE_FROM into a full colour
## middle and a band shaded down to the edge. Other triangles stay as they are.
static func with_edge(one: Dictionary) -> Dictionary:
	var shades: PackedFloat32Array = one.get("shades", PackedFloat32Array())
	var vertices: PackedVector3Array = (one.vertices as PackedVector3Array).duplicate()
	var normals: PackedVector3Array = (one.normals as PackedVector3Array).duplicate()
	if shades.size() != vertices.size(): return one
	var out_shades := shades.duplicate()
	var indices := PackedInt32Array()
	var inner := {}
	var source: PackedInt32Array = one.indices
	for at in range(0, source.size(), 3):
		var corners := [source[at], source[at + 1], source[at + 2]]
		var middle := -1
		for k in range(3):
			if shades[corners[k]] >= 1.0 and shades[corners[(k + 1) % 3]] < 1.0 and shades[corners[(k + 2) % 3]] < 1.0: middle = k
		if middle < 0:
			indices.append_array(PackedInt32Array(corners))
			continue
		var c: int = corners[middle]
		var a: int = corners[(middle + 1) % 3]
		var b: int = corners[(middle + 2) % 3]
		var ia := _inner(inner, c, a, vertices, normals, out_shades)
		var ib := _inner(inner, c, b, vertices, normals, out_shades)
		indices.append_array(PackedInt32Array([c, ia, ib, ia, a, b, ia, b, ib]))
	return {"vertices": vertices, "normals": normals, "indices": indices, "shades": out_shades}

## The full colour point EDGE_FROM of the way from middle `c` to edge point
## `e`, made once per pair.
static func _inner(made: Dictionary, c: int, e: int, vertices: PackedVector3Array, normals: PackedVector3Array, shades: PackedFloat32Array) -> int:
	var key := Vector2i(c, e)
	if made.has(key): return made[key]
	vertices.append(vertices[c].lerp(vertices[e], EDGE_FROM))
	normals.append(normals[e])
	shades.append(1.0)
	made[key] = vertices.size() - 1
	return made[key]

static func shape(name: StringName, size: Vector3) -> Dictionary:
	match name:
		&"leaf": return _leaf(size)
		&"snowflake": return _spiky(size, 6, 0.28)
		&"star": return _spiky(size, 5, 0.45)
		&"raindrop": return _raindrop(size)
		&"seed_fluff": return _seed_fluff(size)
		&"sparkle": return _spiky(size, 4, 0.38)
		&"snow_mark": return _spokes(size, 4, 0.13)
		&"puff": return _puff(size)
		&"notes": return _notes(size)
	return _petal(size)

## A middle raised by `lift` and a rim (each rim point's normal tilted out
## along `outward`), joined as a fan, clockwise seen from above (the front face).
static func _fan(lift: float, rim: PackedVector3Array, outward: PackedVector2Array) -> Dictionary:
	var vertices := PackedVector3Array([Vector3(0, lift, 0)])
	var normals := PackedVector3Array([Vector3.UP])
	var shades := PackedFloat32Array([1.0])
	var indices := PackedInt32Array()
	for point in range(rim.size()):
		vertices.append(rim[point])
		normals.append(Vector3(outward[point].x * 0.2, 1.0, outward[point].y * 0.2).normalized())
		shades.append(RIM_SHADE)
		indices.append_array(PackedInt32Array([0, 1 + point, 1 + (point + 1) % rim.size()]))
	return {"vertices": vertices, "normals": normals, "indices": indices, "shades": shades}

## A blossom petal: flat and a little cupped, narrowing to its tip.
static func _petal(size: Vector3) -> Dictionary:
	var rim := PackedVector3Array()
	var outward := PackedVector2Array()
	for point in range(8):
		var angle := TAU * point / 8
		rim.append(Vector3(cos(angle) * size.x, 0, sin(angle) * size.z * (1.0 - 0.25 * cos(angle))))
		outward.append(Vector2(cos(angle), sin(angle)))
	return _fan(size.y, rim, outward)

## The pip's own leaf outline (spirit_look.gd leaf_half_width): narrow at the
## stalk, broad and round at the top, cupped along its middle.
static func _leaf(size: Vector3) -> Dictionary:
	var rim := PackedVector3Array()
	var steps := 6
	for side: float in [-1.0, 1.0]:
		for step in range(steps):
			var t := float(step) / steps if side < 0.0 else 1.0 - float(step) / steps
			rim.append(Vector3(lerpf(-size.x, size.x, t), 0, side * Look.leaf_half_width(t) * size.z))
	return _fan(size.y, rim, _outward(rim))

## A flat star of `points` points, its inner corners `inner` of the way out.
static func _spiky(size: Vector3, points: int, inner: float) -> Dictionary:
	var rim := PackedVector3Array()
	for corner in range(points * 2):
		var angle := TAU * corner / (points * 2)
		var reach := 1.0 if corner % 2 == 0 else inner
		rim.append(Vector3(cos(angle) * size.x * reach, 0, sin(angle) * size.z * reach))
	return _fan(size.y, rim, _outward(rim))

## A drop, long along z (size.z): round at +z (the end that falls first once
## it leans up) and drawn to a point at -z, at most 0.6 of size.x wide.
static func _raindrop(size: Vector3) -> Dictionary:
	var rim := PackedVector3Array()
	for point in range(10):
		var angle := TAU * point / 10
		var round_end := 0.5 + 0.5 * sin(angle)
		rim.append(Vector3(cos(angle) * size.x * 0.6 * pow(round_end, 0.8), 0, sin(angle) * size.z))
	return _fan(size.y, rim, _outward(rim))

## A dandelion seed: a fan of thin hairs over a short stalk with its seed (the
## stalk at +z, the end that falls first once it leans up).
static func _seed_fluff(size: Vector3) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var hub := Vector3(0, size.y, 0.1 * size.z)
	var hairs := 9
	for hair in range(hairs):
		# Spread over the top half, away from the stalk.
		var angle := PI + PI * (hair + 0.5) / hairs
		var along := Vector3(cos(angle) * size.x, 0, sin(angle) * size.z * 0.9)
		var across := Vector3(-sin(angle), 0, cos(angle)) * 0.004
		var first := vertices.size()
		vertices.append_array(PackedVector3Array([hub - across, hub + along, hub + across]))
		for corner in range(3): normals.append(Vector3.UP)
		indices.append_array(PackedInt32Array([first, first + 1, first + 2]))
	var base := vertices.size()
	var stalk := Vector3(0.003, 0, 0)
	var foot := Vector3(0, 0, size.z * 0.75)
	vertices.append_array(PackedVector3Array([hub - stalk, hub + stalk, foot + stalk, foot - stalk]))
	var kernel := Vector3(0, 0, size.z)
	vertices.append_array(PackedVector3Array([foot + stalk * 2.0, kernel + stalk * 1.5, kernel - stalk * 1.5, foot - stalk * 2.0]))
	for corner in range(8): normals.append(Vector3.UP)
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3, base + 4, base + 5, base + 6, base + 4, base + 6, base + 7]))
	return {"vertices": vertices, "normals": normals, "indices": indices}

## Each rim point's direction from the middle, flat.
static func _outward(rim: PackedVector3Array) -> PackedVector2Array:
	var outward := PackedVector2Array()
	for point: Vector3 in rim: outward.append(Vector2(point.x, point.z).normalized())
	return outward

## `bars` thin rounded bars crossing at the middle, evenly turned (an eight
## arm mark from four), each `thick` of size.x wide.
static func _spokes(size: Vector3, bars: int, thick: float) -> Dictionary:
	var parts := _Parts.new()
	for bar in range(bars):
		var angle := PI * bar / bars
		var along := Vector3(cos(angle) * size.x, 0, sin(angle) * size.z)
		var across := Vector3(-sin(angle) * size.z, 0, cos(angle) * size.x).normalized() * size.x * thick * 0.5
		parts.quad(-along - across, -along + across, along + across, along - across, size.y)
	return parts.done()

## The fluff puff: three round lobes, one big in the middle and two smaller
## up on either side (the board's three circles).
static func _puff(size: Vector3) -> Dictionary:
	var parts := _Parts.new()
	var unit := Vector2(size.x, size.z) / 12.0
	for lobe: Vector3 in [Vector3(0, 0, 7), Vector3(-5, -5, 5), Vector3(5, -4, 5)]:
		parts.disc(Vector3(lobe.x * unit.x, 0, lobe.y * unit.y), Vector2(lobe.z * unit.x, lobe.z * unit.y), 10, size.y)
	return parts.done()

## Two notes joined by a beam (the board's Little tune): two round heads on
## their stems, the stems tied at the top by a slanted bar.
static func _notes(size: Vector3) -> Dictionary:
	var parts := _Parts.new()
	var unit := Vector2(size.x, size.z) / 16.0
	var at := func(x: float, z: float) -> Vector3: return Vector3(x * unit.x, 0, z * unit.y)
	var stem := 1.6 * unit.x
	parts.disc(at.call(-7.0, 12.0), Vector2(5.0 * unit.x, 4.0 * unit.y), 10, size.y)
	parts.disc(at.call(8.0, 9.0), Vector2(5.0 * unit.x, 4.0 * unit.y), 10, size.y)
	var left_top: Vector3 = at.call(-2.0, -11.0)
	var left_foot: Vector3 = at.call(-2.0, 11.0)
	var right_top: Vector3 = at.call(13.0, -16.0)
	var right_foot: Vector3 = at.call(13.0, 8.0)
	parts.quad(left_top - Vector3(stem, 0, 0), left_top + Vector3(stem, 0, 0), left_foot + Vector3(stem, 0, 0), left_foot - Vector3(stem, 0, 0), size.y)
	parts.quad(right_top - Vector3(stem, 0, 0), right_top + Vector3(stem, 0, 0), right_foot + Vector3(stem, 0, 0), right_foot - Vector3(stem, 0, 0), size.y)
	var beam := Vector3(0, 0, 4.0 * unit.y)
	parts.quad(left_top - Vector3(stem, 0, 0), right_top + Vector3(stem, 0, 0), right_top + Vector3(stem, 0, 0) + beam, left_top - Vector3(stem, 0, 0) + beam, size.y)
	return parts.done()

## Flat pieces gathered into one shape: discs and quads, all facing up.
class _Parts:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var shades := PackedFloat32Array()
	var indices := PackedInt32Array()

	## An oval of `radii` round `centre`, as a fan of `sides` triangles.
	func disc(centre: Vector3, radii: Vector2, sides: int, lift: float) -> void:
		var first := vertices.size()
		vertices.append(centre + Vector3(0, lift, 0))
		normals.append(Vector3.UP)
		shades.append(1.0)
		for side in range(sides):
			var angle := TAU * side / sides
			vertices.append(centre + Vector3(cos(angle) * radii.x, 0, sin(angle) * radii.y))
			normals.append(Vector3.UP)
			shades.append(RIM_SHADE)
		for side in range(sides):
			indices.append_array(PackedInt32Array([first, first + 1 + side, first + 1 + (side + 1) % sides]))

	## A quad a, b, c, d (in turn round it), two triangles.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, lift: float) -> void:
		var first := vertices.size()
		for corner: Vector3 in [a, b, c, d]:
			vertices.append(corner + Vector3(0, lift * 0.5, 0))
			normals.append(Vector3.UP)
			shades.append(BAR_SHADE)
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))

	func done() -> Dictionary:
		return {"vertices": vertices, "normals": normals, "indices": indices, "shades": shades}
