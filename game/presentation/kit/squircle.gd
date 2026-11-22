extends RefCounted
## World kit: the squircle (a superellipse, |x/a|^N + |z/b|^N = 1, N about 4,
## a soft rounded square) the goal's base, plate and ring are drawn in
## (kit/pieces/goal.gd). One outline and one hit test serve every surface, so
## what is drawn and what counts a pip are the same shape.
##
## Meshes are built once per size and shared (Primitives.cached_built), like
## the kit's other primitives; none is ever resized in place. Every mesh lies
## flat on y = 0 and rises `height`; a half is the squircle cut down its middle
## (x = 0): `side` -1 the west half, 1 the east, its inner edge straight.
const Primitives = preload("res://presentation/kit/primitives.gd")
const EXPONENT := 4.0
## Points round the whole outline (each half takes half of them, plus its
## straight edge).
const SEGMENTS := 48

## Whether the offset (x, z) from a squircle's centre, half extents `half`,
## lies inside it (`slack` m past the edge counts as inside).
static func inside(offset: Vector2, half: Vector2, slack: float = 0.0) -> bool:
	var a := half.x + slack
	var b := half.y + slack
	return pow(absf(offset.x) / a, EXPONENT) + pow(absf(offset.y) / b, EXPONENT) <= 1.0

## Whether `offset` lies inside the `side` half of the squircle (its straight
## edge down x = 0 counts, `slack` m past every edge counts).
static func inside_half(offset: Vector2, half: Vector2, side: int, slack: float = 0.0) -> bool:
	if float(side) * offset.x < -slack: return false
	return inside(offset, half, slack)

## The outline of the squircle of half extents `half` (x, z), clockwise seen
## from above, from the west of the squircle's middle round to it again.
static func outline(half: Vector2, count: int = SEGMENTS) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(count):
		points.append(_at(half, TAU * float(index) / float(count)))
	return points

## The `side` half's outline: its curve from one end of its straight edge to
## the other (the closing segment is that edge), clockwise from above.
static func half_outline(half: Vector2, side: int, count: int = SEGMENTS / 2) -> PackedVector2Array:
	var points := PackedVector2Array()
	# East: from the north end of the middle line (angle -PI/2) round through
	# +x to the south end (+PI/2); west: the same turned half a circle.
	var start := -PI * 0.5 if side > 0 else PI * 0.5
	for index in range(count + 1):
		points.append(_at(half, start + PI * float(index) / float(count)))
	return points

static func _at(half: Vector2, angle: float) -> Vector2:
	var c := cos(angle)
	var s := sin(angle)
	var power := 2.0 / EXPONENT
	return Vector2(half.x * signf(c) * pow(absf(c), power), half.y * signf(s) * pow(absf(s), power))

## The slab of the whole squircle `half` across, `height` tall: one mesh.
static func slab(half: Vector2, height: float) -> Mesh:
	return Primitives.cached_built("squircle_slab|%.4f|%.4f|%.4f" % [half.x, half.y, height], func() -> Mesh: return _slab(outline(half), Vector2.ZERO, height))

## The slab of its `side` half.
static func half_slab(half: Vector2, height: float, side: int) -> Mesh:
	return Primitives.cached_built("squircle_half_slab|%.4f|%.4f|%.4f|%d" % [half.x, half.y, height, side], func() -> Mesh: return _slab(half_outline(half, side), Vector2(half.x * 0.4 * float(side), 0), height))

## A frame `bar` wide round the whole squircle's edge (inside it), `height` tall.
static func frame(half: Vector2, bar: float, height: float) -> Mesh:
	return Primitives.cached_built("squircle_frame|%.4f|%.4f|%.4f|%.4f" % [half.x, half.y, bar, height], func() -> Mesh: return _band(outline(half), outline(half - Vector2.ONE * bar), height))

## A frame `bar` wide round the `side` half's edge, straight edge included.
static func half_frame(half: Vector2, bar: float, height: float, side: int) -> Mesh:
	return Primitives.cached_built("squircle_half_frame|%.4f|%.4f|%.4f|%.4f|%d" % [half.x, half.y, bar, height, side], func() -> Mesh: return _band(half_outline(half, side), _inset_half(half, bar, side), height))

## The half's outline pulled in `bar` on every side (its straight edge too),
## point for point with half_outline.
static func _inset_half(half: Vector2, bar: float, side: int) -> PackedVector2Array:
	var inner := PackedVector2Array()
	for point: Vector2 in half_outline(half, side):
		inner.append(Vector2(float(side) * bar + point.x * (half.x - 2.0 * bar) / half.x, point.y * (half.y - bar) / half.y))
	return inner

## A flat slab over `loop`, a fan from `centre`.
static func _slab(loop: PackedVector2Array, centre: Vector2, height: float) -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := loop.size()
	for index in range(count):
		var here := loop[index]
		var next := loop[(index + 1) % count]
		_tri(tool, Vector3(centre.x, height, centre.y), Vector3(here.x, height, here.y), Vector3(next.x, height, next.y))
		_wall(tool, here, next, 0.0, height)
	tool.generate_normals()
	return tool.commit()

## A band between two loops of the same size (outer first), `height` tall:
## its top and both its walls.
static func _band(outer: PackedVector2Array, inner: PackedVector2Array, height: float) -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := outer.size()
	for index in range(count):
		var next := (index + 1) % count
		var o0 := Vector3(outer[index].x, height, outer[index].y)
		var o1 := Vector3(outer[next].x, height, outer[next].y)
		var i0 := Vector3(inner[index].x, height, inner[index].y)
		var i1 := Vector3(inner[next].x, height, inner[next].y)
		_tri(tool, o0, o1, i1)
		_tri(tool, o0, i1, i0)
		_wall(tool, outer[index], outer[next], 0.0, height)
		_wall(tool, inner[next], inner[index], 0.0, height)
	tool.generate_normals()
	return tool.commit()

## One upright quad over the edge here -> next (clockwise from above, so it
## faces outward), from y `low` to `high`.
static func _wall(tool: SurfaceTool, here: Vector2, next: Vector2, low: float, high: float) -> void:
	var a := Vector3(here.x, low, here.y)
	var b := Vector3(next.x, low, next.y)
	var c := Vector3(next.x, high, next.y)
	var d := Vector3(here.x, high, here.y)
	_tri(tool, c, d, a)
	_tri(tool, c, a, b)

static func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
