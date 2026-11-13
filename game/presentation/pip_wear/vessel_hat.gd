extends RefCounted
## The vessel hats (hat): the Flower pot and the Tea cup, as the hats board
## draws them. One art script serves both, each descriptor naming it; the look
## is picked by the worn hat's id from VESSELS.
##
## Each is a turned shape (kit Parts.lathe) from its outline, sat on the
## head's top toward the side away from the leaf and leaning away from it, so
## the leaf grows clear beside it ("pokes_through"). The Flower pot stands
## upside down, a pale rim on the head and a dark matte opening under it; the
## Tea cup stands on its foot with a clay rim, a mint band and one broad
## handle loop. One baked mesh each, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const POT := Color("c68160")
const POT_RIM := Color("e7b58c")
const INK := Color("193d39")
const CUP := Color("eee9d4")
const CUP_INSIDE := Color("e2d9bf")
const CLAY := Color("b6967a")
const MINT := Color("95c0b7")

## Each vessel by item id: its outline from bottom to top ([radius, height,
## colour], kit Parts.lathe), how many sides it turns with, where its bottom
## sits on the head, its turn (head space) and size, and its handle ([centre,
## radius, thickness] in the vessel's own space) or [].
const VESSELS := {
	"flower_pot": {
		"profile": [[0.0, 0.004, INK], [0.135, 0.0, POT_RIM], [0.176, 0.0, POT_RIM], [0.18, 0.052, POT_RIM], [0.152, 0.056, POT], [0.118, 0.215, POT], [0.0, 0.222, POT]],
		"sides": 10, "at": Vector3(0.15, 0.228, -0.02), "turn": Vector3(0.0, 0.25, -0.3), "scale": 1.15, "handle": []},
	"tea_cup": {
		"profile": [[0.0, 0.0, CUP], [0.075, 0.0, CUP], [0.08, 0.022, CUP], [0.088, 0.03, CUP], [0.122, 0.098, MINT], [0.128, 0.12, CUP], [0.142, 0.165, CLAY], [0.146, 0.176, CLAY], [0.13, 0.176, CUP_INSIDE], [0.1, 0.085, CUP_INSIDE], [0.0, 0.08, CUP_INSIDE]],
		"sides": 10, "at": Vector3(0.13, 0.262, -0.01), "turn": Vector3(0.12, 0.0, -0.2), "scale": 1.12, "handle": [Vector3(0.152, 0.095, 0.0), 0.045, 0.014]},
}

static func wear(look: RefCounted) -> void:
	var id := str(look.outfit.get("hat", ""))
	if not VESSELS.has(id): return
	look.mesh(look.head(), Kit.cached_mesh(id, _build.bind(id)), Kit.vertex_material())

static func _build(id: String) -> Mesh:
	var vessel: Dictionary = VESSELS[id]
	var parts := Kit.Parts.new()
	parts.push(Kit.Parts.place(vessel.at, vessel.turn, Vector3.ONE * float(vessel.scale)))
	parts.lathe(vessel.profile, int(vessel.sides))
	var handle: Array = vessel.handle
	if not handle.is_empty():
		# One broad loop standing on its edge beside the cup.
		parts.ring(CUP, handle[0], float(handle[1]) - float(handle[2]), float(handle[1]) + float(handle[2]), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0), 8, 4)
	parts.pop()
	return parts.commit()
