extends RefCounted
## Apple leaf (leaf): the pip's leaf becomes a big apple leaf, as the Orchard
## board draws it (Fruits board 4a): a long blade pointed at both ends in a
## fresh apple green, gently folded along a darker rib, on a short stalk.
## It grows from the leaf's own stalk and leans out the way the leaf does, so
## it sways, turns and hides with it, rises through a hat's brim with it, and
## leans clear of a carried seed. One baked mesh drawn in the leaf's place: no
## extra draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const GREEN := Color("a2cf72")
const RIB := Color("6f9a48")
## The blade: its length, its widest half width, how far its middle stands
## forward of its edges (the fold), and its rings along the length.
const LENGTH := 0.32
const HALF_WIDTH := 0.075
const FOLD := 0.012
const RINGS := 10
## Where the blade starts on the stalk, and the stalk's reach below it (it
## starts a little inside the head, as the leaf's does).
const BLADE_FROM := 0.025
const STALK_FROM := -0.02
const STALK_RADIUS := 0.011
const RIB_RADIUS := 0.0055
## How much further out than the plain leaf it leans (radians, away from the
## head's middle) and how far its tip tips back.
const LEAN_MORE := 0.3
const TIP_BACK := 0.18

static func wear(look: RefCounted) -> void:
	var leaf: MeshInstance3D = look.leaf()
	look.swap_mesh(leaf, Kit.cached_mesh("apple_leaf", _build))
	look.set_material(leaf, Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.push(Transform3D(Basis(Vector3.BACK, LEAN_MORE) * Basis(Vector3.RIGHT, -TIP_BACK), Vector3.ZERO))
	parts.rod(RIB, Vector3(0, STALK_FROM, 0), Vector3(0, BLADE_FROM + 0.02, 0), STALK_RADIUS)
	parts.add(_blade(), GREEN, Transform3D.IDENTITY)
	parts.rod(RIB, Vector3(0, BLADE_FROM + LENGTH * 0.04, FOLD + RIB_RADIUS * 0.4), Vector3(0, BLADE_FROM + LENGTH * 0.86, FOLD * 0.3 + RIB_RADIUS * 0.4), RIB_RADIUS, 5)
	parts.pop()
	return parts.commit()

## The blade's half width at `t` along it (0 at the stalk, 1 at the tip):
## pointed at both ends, widest a little below the middle.
static func half_width(t: float) -> float:
	return HALF_WIDTH * pow(sin(PI * pow(t, 0.85)), 0.9)

## The blade, both faces: across in x, along in y, its front facing +z.
static func _blade() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var slope := atan2(FOLD, HALF_WIDTH)
	for face: float in [1.0, -1.0]:
		var first := vertices.size()
		for ring in range(RINGS + 1):
			var t := float(ring) / float(RINGS)
			var y := BLADE_FROM + LENGTH * t
			var w := half_width(t)
			# The fold flattens toward the tip.
			var fold := FOLD * (1.0 - 0.7 * t) * face
			for side: float in [-1.0, 0.0, 1.0]:
				vertices.append(Vector3(side * w, y, fold if side == 0.0 else 0.0))
				normals.append(Vector3(side * sin(slope), 0.0, cos(slope)) * face)
		for ring in range(RINGS):
			for strip in range(2):
				var a := first + ring * 3 + strip
				var b := a + 3
				# Clockwise seen from the face's own side.
				if face > 0.0: indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
				else: indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return made
