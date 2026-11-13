extends RefCounted
## Pocket pebble (carry): one pale smooth pebble resting at the pip's side
## against its lower body, with a soft darker spot, no hands (the board's
## little extras). It hides whenever the pip carries a real object (a seed,
## the Lighthouse lens), so it never crowds or looks like one, and it sits low
## and to the side, far from where a carried object rides. One baked mesh with
## the kit's vertex colour material, on the torso so it moves with the body.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

const PEBBLE := Color("e8dabc")
const SPOT := Color("b9ad94")
## Where it rests: toward the viewer's right and a little forward, low on the
## torso; its half sizes (long, thick, wide): 0.2 by 0.16 pip widths.
const REST := Vector3(0.85, -0.35, 0.45)
const SIZE := Vector3(0.069, 0.04, 0.055)

static func wear(look: RefCounted) -> void:
	var node: MeshInstance3D = look.mesh(look.torso(), Kit.cached_mesh("pocket_pebble", _pebble), Kit.vertex_material())
	look.hide_while_carrying(node)

static func _pebble() -> Mesh:
	var parts := Kit.Parts.new()
	var frame := Kit.lie_on(Meshes.torso_surface(REST), Vector3(0.3, 1.0, 0.2), SIZE, -0.012)
	parts.blob_at(PEBBLE, frame, 7, 3)
	parts.push(frame)
	parts.blob(SPOT, Vector3(0.35, 0.72, 0.15), Vector3(0.32, 0.3, 0.3), Vector3.ZERO, 4, 2)
	return parts.commit()
