extends RefCounted
## The spirit's body meshes, built once from spirit_look.gd's proportions and
## shared by every spirit: a rounded box head, a small bowl torso, a foot and
## the leaf. Light enough for many spirits on a phone (about 2,400 triangles
## for a whole spirit, fewer than the spheres it replaced), with smooth normals. Each mesh's origin is its part's
## pivot: the head's and torso's centres, the foot's centre, the leaf's stalk.

const Look = preload("res://presentation/spirit_look.gd")

static var _cache: Dictionary = {}

static func head() -> ArrayMesh:
	return _cached("head", func() -> ArrayMesh: return _superellipsoid(Look.HEAD_HALF, Look.HEAD_POWER, 20, 36))

static func torso() -> ArrayMesh:
	return _cached("torso", func() -> ArrayMesh: return _superellipsoid(Look.TORSO_HALF, Look.TORSO_POWER, 10, 20))

static func foot() -> ArrayMesh:
	return _cached("foot", func() -> ArrayMesh: return _superellipsoid(Look.FOOT_HALF, 2.0, 6, 12))

static func leaf() -> ArrayMesh:
	return _cached("leaf", _leaf)

static func _cached(key: String, build: Callable) -> ArrayMesh:
	if not _cache.has(key): _cache[key] = build.call()
	return _cache[key]

## |x/a|^p + |y/b|^p + |z/c|^p = 1: each direction of a UV sphere pushed out to
## the surface, with the surface's own normal.
static func _superellipsoid(half: Vector3, power: float, rings: int, segments: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(rings + 1):
		var lat := PI * float(ring) / float(rings)
		for segment in range(segments + 1):
			var lon := TAU * float(segment) / float(segments)
			var direction := Vector3(sin(lat) * sin(lon), cos(lat), sin(lat) * cos(lon))
			var point := direction * _reach(direction, half, power)
			surface.set_normal(_normal(point, half, power))
			surface.add_vertex(point)
	_grid(surface, rings, segments)
	return surface.commit()

static func _reach(direction: Vector3, half: Vector3, power: float) -> float:
	var sum := pow(absf(direction.x / half.x), power) + pow(absf(direction.y / half.y), power) + pow(absf(direction.z / half.z), power)
	return pow(sum, -1.0 / power)

static func _normal(point: Vector3, half: Vector3, power: float) -> Vector3:
	var gradient := Vector3(
		signf(point.x) * pow(absf(point.x / half.x), power - 1.0) / half.x,
		signf(point.y) * pow(absf(point.y / half.y), power - 1.0) / half.y,
		signf(point.z) * pow(absf(point.z / half.z), power - 1.0) / half.z)
	return gradient.normalized() if gradient.length_squared() > 0.0 else Vector3.UP

## Triangles over a (rings + 1) x (segments + 1) vertex grid, wound for
## Godot's clockwise front faces seen from outside.
static func _grid(surface: SurfaceTool, rings: int, segments: int) -> void:
	var row := segments + 1
	for ring in range(rings):
		for segment in range(segments):
			var a := ring * row + segment
			var b := a + row
			surface.add_index(a)
			surface.add_index(a + 1)
			surface.add_index(b)
			surface.add_index(a + 1)
			surface.add_index(b + 1)
			surface.add_index(b)

## A plump teardrop: narrow at the stalk (the origin), broad and round at the
## top, flat front to back. Cross sections are ellipses.
static func _leaf() -> ArrayMesh:
	var rings := 10
	var segments := 12
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	# The stalk starts a little inside the head so the leaf never floats.
	var base := -0.02
	for ring in range(rings + 1):
		var t := float(ring) / float(rings)
		var y := base + (Look.LEAF_LENGTH - base) * t
		var half_width := Look.leaf_half_width(t) * Look.LEAF_WIDTH * 0.5
		for segment in range(segments + 1):
			var angle := TAU * float(segment) / float(segments)
			var point := Vector3(cos(angle) * half_width, y, sin(angle) * half_width * Look.LEAF_THICKNESS / Look.LEAF_WIDTH)
			points.append(point.rotated(Vector3.RIGHT, -Look.LEAF_TIP_BACK))
	# Unindexed first, then joined; the generated normals are smooth.
	var row := segments + 1
	for ring in range(rings):
		for segment in range(segments):
			var a := ring * row + segment
			var b := a + row
			for corner: int in [a, a + 1, b, a + 1, b + 1, b]: surface.add_vertex(points[corner])
	surface.index()
	surface.generate_normals()
	return surface.commit()
