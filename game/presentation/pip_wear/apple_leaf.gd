extends RefCounted
## Apple leaf (leaf): the pip's own leaf drawn larger in a fresh apple green,
## with a darker fold down its middle, as the Orchard board draws it (Fruits
## board 4a). The leaf's own mesh scaled about its stalk, baked once with
## vertex colours and shared by every pip wearing it; it sways, turns and
## hides as the leaf does. No extra draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")
const Look = preload("res://presentation/spirit_look.gd")

const GREEN := Color("8cc152")
const RIB := Color("5f9a3a")
## How much the middle of each face takes the rib's colour.
const RIB_STRENGTH := 0.55
const SCALE := 1.4
## Points this close to the leaf's middle line (across its width) are the rib.
const RIB_REACH := 0.002

static func wear(look: RefCounted) -> void:
	var leaf: MeshInstance3D = look.leaf()
	look.swap_mesh(leaf, Kit.cached_mesh("apple_leaf", _build))
	look.set_material(leaf, Kit.vertex_material())

static func _build() -> Mesh:
	var arrays: Array = Meshes.leaf().surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours := PackedColorArray()
	for index in range(vertices.size()):
		var point := vertices[index]
		# The middle of a face, not the pinched tip or stalk where the whole ring meets.
		var flat := point.rotated(Vector3.RIGHT, Look.LEAF_TIP_BACK)
		var rib := absf(flat.x) < RIB_REACH and absf(flat.z) > RIB_REACH
		colours.append(GREEN.lerp(RIB, RIB_STRENGTH) if rib else GREEN)
		vertices[index] = point * SCALE
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return made
