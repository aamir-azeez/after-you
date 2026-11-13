extends RefCounted
## Wood chime (bell sound): what it sounds like is the item (its descriptor's
## "sound", played once on the player's result screen). Nothing is worn: the
## little wooden chime beside the head shows only in the Wardrobe (its
## descriptor's "places"), where it stands for the sound, as the board's card
## draws it.
## One baked mesh with the kit's vertex colour material, on the pip's own
## node, which never turns.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const WOOD := Color("b58c63")
const PALE := Color("e8dabc")
## Where it hangs: beside the head on the viewer's right, a little forward.
const AT := Vector3(0.4, 0.0, 0.12)

static func wear(look: RefCounted) -> void:
	look.mesh(look.root(), Kit.cached_mesh("wood_chime", _chime), Kit.vertex_material(), Transform3D(Basis.IDENTITY, AT))

static func _chime() -> Mesh:
	var parts := Kit.Parts.new()
	parts.ring(WOOD, Vector3(0, 0.875, 0), 0.008, 0.016, Vector3.ONE, Vector3(PI * 0.5, 0, 0), 10, 4)
	parts.cylinder(WOOD, Vector3(0, 0.84, 0), 0.006, 0.03, -1.0, Vector3.ZERO, 6)
	parts.cylinder(WOOD, Vector3(0, 0.815, 0), 0.05, 0.026, 0.022, Vector3.ZERO, 12)
	for side: float in [-1.0, 1.0]:
		parts.rod(WOOD, Vector3(side * 0.024, 0.8, 0), Vector3(side * 0.024, 0.73, 0), 0.003, 4)
		parts.cylinder(PALE, Vector3(side * 0.024, 0.68 - (0.0 if side < 0.0 else 0.02), 0), 0.014, 0.1, -1.0, Vector3.ZERO, 8)
	return parts.commit()
