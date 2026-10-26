extends RefCounted
## Every Hard (leaf, earned): a little cap of snow on the leaf's tip, like the
## Hard mark's peak. It hangs from the leaf, so it sways and hides with it.
## One baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const SNOW := Color("f6f9ff")
## Leaf space (its origin is the stalk): the cap over the tip and a small drip
## below it.
const CAP_AT := Vector3(0, 0.124, -0.046)
const CAP_SIZE := Vector3(0.05, 0.036, 0.032)
const CAP_TURN := Vector3(-0.35, 0, 0)
const DRIP_AT := Vector3(0.02, 0.098, -0.03)
const DRIP_SIZE := Vector3(0.016, 0.022, 0.016)

static func wear(look: RefCounted) -> void:
	look.mesh(look.leaf(), Kit.cached_mesh("every_hard", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.blob(SNOW, CAP_AT, CAP_SIZE, CAP_TURN, 10, 5)
	parts.blob(SNOW, DRIP_AT, DRIP_SIZE, Vector3.ZERO, 6, 3)
	return parts.commit()
