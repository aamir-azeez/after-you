extends RefCounted
## Straw hat (hat): a flat straw sun hat with a coral band and a ribbon tail.
## The leaf pokes up through the brim (its descriptor's "leaf_lift"). One
## baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const STRAW := Color("e9cd8c")
const STRAW_RIM := Color("dcbc76")
const STRAW_CROWN := Color("efd597")
const BAND := Color("e57668")
const TAIL := Color("e48f84")
const AT := Vector3(0.045, 0.262, -0.035)
const TURN := Vector3(-0.07, 0.0, -0.1)

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("straw_hat", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.push(Kit.Parts.place(AT, TURN))
	parts.cylinder(STRAW, Vector3.ZERO, 0.335, 0.022, 0.34, Vector3.ZERO, 24)
	parts.ring(STRAW_RIM, Vector3.ZERO, 0.32, 0.35, Vector3(1, 0.5, 1), Vector3.ZERO, 24, 4)
	parts.cylinder(STRAW_CROWN, Vector3(0, 0.036, 0), 0.19, 0.066, 0.18, Vector3.ZERO, 16)
	parts.cylinder(BAND, Vector3(0, 0.03, 0), 0.197, 0.042, -1.0, Vector3.ZERO, 16)
	parts.blob(TAIL, Vector3(0.12, 0.02, 0.15), Vector3(0.035, 0.012, 0.06), Vector3(0.3, 0.5, 0.4))
	parts.pop()
	return parts.commit()
