extends RefCounted
## Lantern (hat): a stalk and a paper lantern hanging beside the leaf, under
## the leaf so it sways with it, clear of the eyes and a carried seed. The
## glow is the paper's emission plus one small sprite on the lantern's outer
## side, away from the head. Draw calls: stalk and trim, paper, glow.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const GREEN := Color("5e9e45")
const PAPER := Color("f7a24e")
const PAPER_GLOW := Color("f08a32")
const PAPER_ENERGY := 1.0
const RIB := Color("d9893e")
const CAP := Color("c4573f")
const GLOW := Color("ffb85c")
## The stalk's points, upper body space.
const STALK: Array[Vector3] = [Vector3(-0.2, 0.83, 0.04), Vector3(-0.255, 0.91, 0.08), Vector3(-0.315, 0.93, 0.11), Vector3(-0.345, 0.9, 0.125), Vector3(-0.35, 0.85, 0.125)]
const POD_AT := Vector3(-0.35, 0.782, 0.125)
const POD_SCALE := 1.15
const POD_SIZE := Vector3(0.058, 0.05, 0.058)
## The glow sprite: its size, strength, and how far it sits out from the pod
## (away from the head).
const GLOW_SIZE := 0.2
const GLOW_STRENGTH := 0.7
const GLOW_OUT := Vector3(-0.035, -0.005, 0.03)

static func wear(look: RefCounted) -> void:
	var follow: Node3D = look.attach(look.leaf(), Kit.follow(look.leaf_rest()))
	look.mesh(follow, Kit.cached_mesh("lantern", _build), Kit.vertex_material())
	look.mesh(follow, Kit.cached_mesh("lantern:paper", _paper), Kit.glow_material(PAPER, PAPER_GLOW, PAPER_ENERGY))
	var glow := Kit.halo(GLOW_SIZE, GLOW, GLOW_STRENGTH)
	glow.position = POD_AT + GLOW_OUT
	look.attach(follow, glow)

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	for index in range(STALK.size() - 1):
		parts.rod(GREEN, STALK[index], STALK[index + 1], 0.0105)
	parts.push(Kit.Parts.place(POD_AT, Vector3.ZERO, Vector3.ONE * POD_SCALE))
	for y: float in [-0.022, 0.0, 0.022]:
		var radius := POD_SIZE.x * sqrt(1.0 - pow(y / POD_SIZE.y, 2.0))
		parts.ring(RIB, Vector3(0, y, 0), radius - 0.004, radius + 0.001, Vector3.ONE, Vector3.ZERO, 12, 3)
	parts.cylinder(CAP, Vector3(0, 0.05, 0), 0.026, 0.016, -1.0, Vector3.ZERO, 10)
	parts.cylinder(CAP, Vector3(0, -0.05, 0), 0.026, 0.016, -1.0, Vector3.ZERO, 10)
	parts.cylinder(CAP, Vector3(0, -0.072, 0), 0.004, 0.03, -1.0, Vector3.ZERO, 6)
	parts.pop()
	return parts.commit()

static func _paper() -> Mesh:
	var parts := Kit.Parts.new()
	parts.blob(PAPER, POD_AT, POD_SIZE * POD_SCALE, Vector3.ZERO, 10, 5)
	return parts.commit()
