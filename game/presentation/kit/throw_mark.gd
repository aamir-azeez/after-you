extends RefCounted
## World kit: the throw mark, the spot a pip throws a carried thing from
## (core/physical/carried_items.gd throws; an island family's throw pad). A
## cream ring lying on the floor with the throw icon lying flat in its middle,
## so it never reads as a pad to press: a seed, a dotted arc and an arrowhead,
## the arc pointing where the throw lands. A mark wholly inside a pad (the
## pad is the throw spot, LevelLayout.mark_pad) draws no ring: its icon lies
## on the pad's top instead and sinks with it (on_pad()). Every world draws
## throw marks and throw pads only through here (tests/test_throw_look.gd
## checks every throw has its icon).
##
## Cost: one cached mesh for every icon, in the ring's shared cream look; on
## the floor it is a plain leaf the static fold batches with the ring
## (kit/static_batch.gd, MODEL_MESH_META), so no new material or draw.
const Primitives = preload("res://presentation/kit/primitives.gd")
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
## Every icon's name starts with this.
const ICON := "ThrowIcon"
## How high over the floor the icon lies, and over a pad's top (m).
const LIFT := 0.012
const PAD_LIFT := 0.004
## The icon in a mark of radius 1 (scaled by the mark's radius): the seed's
## middle and radius, the arc's ends and the height of its bow, its stroke's
## half width, its dashes (start, end as shares of the arc) and the
## arrowhead's length and half width. Lying along +x, its bow toward -z.
const SEED := Vector2(-0.4, 0.12)
const SEED_RADIUS := 0.1
const ARC_FROM := Vector2(-0.24, 0.04)
const ARC_TO := Vector2(0.36, 0.1)
const ARC_BOW := 0.6
const STROKE := 0.07
const DASHES := [[0.0, 0.22], [0.34, 0.56], [0.68, 0.8]]
const HEAD_LENGTH := 0.24
const HEAD_HALF := 0.15

static var _mesh: ArrayMesh

## A throw mark of `radius` (m) at `at` under `parent`: the cream ring and,
## beside it, the icon pointing at `toward` (parent space). Returns the ring.
static func mark(radius: float, at: Vector3, toward: Vector3, parent: Node3D, id: String) -> MeshInstance3D:
	var ring := Primitives.mesh_node(Primitives.cached_shape(Primitives.ring_mesh(radius)), Primitives.shared_material(Parts.CREAM), at + Vector3(0, 0.03, 0), parent)
	ring.name = "ThrowMark_" + id
	icon(radius, at, toward, parent, id)
	return ring

## The icon alone, `radius` (m) the mark's, lying on the floor at `at`
## (parent space) and pointing at `toward`.
static func icon(radius: float, at: Vector3, toward: Vector3, parent: Node3D, id: String) -> MeshInstance3D:
	var node := Primitives.mesh_node(icon_mesh(), Primitives.shared_material(Parts.CREAM), at + Vector3(0, LIFT, 0), parent)
	node.name = ICON + "_" + id
	node.scale = Vector3.ONE * radius
	node.rotation.y = _heading(toward - at)
	return node

## The icon on pad piece `pad` (kit/pieces/pad.gd), the throw spot: on top of
## the part that sinks, so it sinks with it, pointing at `toward` (the pad's
## parent's space).
static func on_pad(pad: RefCounted, toward: Vector3, id: String) -> MeshInstance3D:
	var sinks: Node3D = pad.rim.get_parent()
	var node := icon(pad.radius, Vector3.ZERO, Vector3.ZERO, sinks, id)
	node.position = Vector3(0, pad.top() - sinks.position.y + PAD_LIFT, 0)
	node.rotation.y = _heading(toward - pad.at)
	return node

## The turn about y that lays the icon's +x along `way` (flat).
static func _heading(way: Vector3) -> float:
	return atan2(-way.z, way.x) if Vector2(way.x, way.z).length() > 0.001 else 0.0

## The icon's one mesh, built once: flat, face up, in a mark of radius 1.
static func icon_mesh() -> ArrayMesh:
	if _mesh != null: return _mesh
	var vertices := PackedVector3Array()
	# The seed: a round disc.
	var sides := 14
	for side in range(sides):
		var a := TAU * side / sides
		var b := TAU * (side + 1) / sides
		_tri(vertices, SEED, SEED + Vector2(cos(a), sin(a)) * SEED_RADIUS, SEED + Vector2(cos(b), sin(b)) * SEED_RADIUS)
	# The arc's dashes: a bow (a quadratic curve) cut into strokes.
	var bend := (ARC_FROM + ARC_TO) / 2.0 + Vector2(0, -ARC_BOW)
	for dash: Array in DASHES:
		var steps := 4
		for step in range(steps):
			var t0 := lerpf(float(dash[0]), float(dash[1]), float(step) / steps)
			var t1 := lerpf(float(dash[0]), float(dash[1]), float(step + 1) / steps)
			var p0 := _bow(t0, bend)
			var p1 := _bow(t1, bend)
			var n0 := _side(t0, bend) * STROKE
			var n1 := _side(t1, bend) * STROKE
			_tri(vertices, p0 - n0, p0 + n0, p1 + n1)
			_tri(vertices, p0 - n0, p1 + n1, p1 - n1)
	# The arrowhead at the arc's end, along its last stretch.
	var tip_dir := (ARC_TO - _bow(0.9, bend)).normalized()
	var across := Vector2(-tip_dir.y, tip_dir.x)
	var base := ARC_TO - tip_dir * HEAD_LENGTH * 0.35
	_tri(vertices, base + tip_dir * HEAD_LENGTH, base + across * HEAD_HALF, base - across * HEAD_HALF)
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	for vertex: Vector3 in vertices:
		normals.append(Vector3.UP)
		tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		uvs.append(Vector2(vertex.x, vertex.z) * 0.5 + Vector2(0.5, 0.5))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Folds like a model mesh (one surface, a fixed shape).
	_mesh.set_meta(StaticBatch.MODEL_MESH_META, "throw_mark#icon")
	SessionRelease.on_exit(Callable(load("res://presentation/kit/throw_mark.gd"), "release_cached"))
	return _mesh

## Lets go of the icon's mesh (SessionRelease calls this at shutdown).
static func release_cached() -> void:
	_mesh = null

## A point on the bow at `t` (0 to 1).
static func _bow(t: float, bend: Vector2) -> Vector2:
	return ARC_FROM.lerp(bend, t).lerp(bend.lerp(ARC_TO, t), t)

## The bow's unit side at `t` (left of its way).
static func _side(t: float, bend: Vector2) -> Vector2:
	var way := (bend - ARC_FROM).lerp(ARC_TO - bend, t).normalized()
	return Vector2(-way.y, way.x)

## A triangle of flat points (x, z) facing up: clockwise seen from above, the
## front face.
static func _tri(into: PackedVector3Array, a: Vector2, b: Vector2, c: Vector2) -> void:
	var pa := Vector3(a.x, 0, a.y)
	var pb := Vector3(b.x, 0, b.y)
	var pc := Vector3(c.x, 0, c.y)
	if (pb - pa).cross(pc - pa).y > 0.0: into.append_array(PackedVector3Array([pa, pc, pb]))
	else: into.append_array(PackedVector3Array([pa, pb, pc]))
