extends RefCounted
## Seashell (hat): a scallop on the head's upper corner beside the leaf, five
## ribs over a hinge. One baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const RIB := Color("ea8a76")
const RIB_LIGHT := Color("f3a690")
const HINGE := Color("d66b58")
const AT := Vector3(-0.305, 0.155, 0.185)
const TURN := Vector3(-0.15, -0.65, 0.35)
const SIZE := 0.14
const RIBS := 5

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("seashell", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.push(Kit.Parts.place(AT, TURN))
	for index in range(RIBS):
		var a := lerpf(-0.78, 0.78, float(index) / float(RIBS - 1))
		parts.blob(RIB if index % 2 == 0 else RIB_LIGHT, Vector3(sin(a) * SIZE * 0.45, cos(a) * SIZE * 0.45, -absf(a) * SIZE * 0.12), Vector3(SIZE * 0.2, SIZE * 0.5, SIZE * 0.1), Vector3(absf(a) * 0.35, 0.0, -a))
	parts.blob(HINGE, Vector3(0, -SIZE * 0.02, 0.01), Vector3(SIZE * 0.16, SIZE * 0.14, SIZE * 0.1))
	for side: float in [-1.0, 1.0]:
		parts.blob(HINGE, Vector3(SIZE * 0.17 * side, -SIZE * 0.04, 0.0), Vector3(SIZE * 0.13, SIZE * 0.07, SIZE * 0.07), Vector3.ZERO, 6, 3)
	parts.pop()
	return parts.commit()
