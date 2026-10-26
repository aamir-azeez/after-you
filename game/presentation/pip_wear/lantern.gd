extends RefCounted
## Lantern (hat): a stalk that grows out of the head beside the leaf, arcs
## forward and over, and holds a paper lantern on a short string with a hook
## at its tip, beside the head, clear of the eyes and a carried seed. It sits
## on the upper body (not the leaf). The glow is the paper's emission plus one
## small sprite on the lantern's outer side, away from the head. Draw calls:
## stalk, string and trim; paper; glow.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const GREEN := Color("5e9e45")
const PAPER := Color("f7a24e")
const PAPER_GLOW := Color("f08a32")
const PAPER_ENERGY := 1.0
const RIB := Color("d9893e")
const CAP := Color("c4573f")
const STRING := Color("6b4c31")
const GLOW := Color("ffb85c")
## The stalk's points, upper body space: it starts inside the head, so it
## grows out of the skin, and its tip sits above the lantern.
const STALK: Array[Vector3] = [Vector3(-0.135, 0.79, 0.07), Vector3(-0.16, 0.9, 0.11), Vector3(-0.2, 0.955, 0.145), Vector3(-0.27, 0.975, 0.17), Vector3(-0.33, 0.95, 0.18), Vector3(-0.35, 0.91, 0.18)]
const STALK_RADIUS := 0.018
## How far each stalk piece runs past its ends, so the joints close.
const STALK_OVERLAP := 0.008
const POD_AT := Vector3(-0.35, 0.782, 0.18)
const POD_SCALE := 1.15
const POD_SIZE := Vector3(0.058, 0.05, 0.058)
## The string from the stalk's tip down to the cap, and the hook at the tip.
const STRING_FROM := Vector3(-0.35, 0.914, 0.18)
const STRING_TO := Vector3(-0.35, 0.846, 0.18)
const STRING_RADIUS := 0.0065
const HOOK_AT := Vector3(-0.35, 0.912, 0.18)
## The glow sprite: its size, strength, and how far it sits out from the pod
## (away from the head).
const GLOW_SIZE := 0.17
const GLOW_STRENGTH := 0.55
const GLOW_OUT := Vector3(-0.02, 0.0, 0.025)

static func wear(look: RefCounted) -> void:
	var body: Node3D = look.upper_body()
	look.mesh(body, Kit.cached_mesh("lantern", _build), Kit.vertex_material())
	look.mesh(body, Kit.cached_mesh("lantern:paper", _paper), Kit.glow_material(PAPER, PAPER_GLOW, PAPER_ENERGY))
	var glow := Kit.halo(GLOW_SIZE, GLOW, GLOW_STRENGTH)
	glow.position = POD_AT + GLOW_OUT
	look.attach(body, glow)

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	for index in range(STALK.size() - 1):
		var along := (STALK[index + 1] - STALK[index]).normalized() * STALK_OVERLAP
		parts.rod(GREEN, STALK[index] - along, STALK[index + 1] + along, STALK_RADIUS)
	parts.rod(STRING, STRING_FROM, STRING_TO, STRING_RADIUS, 5)
	parts.ring(STRING, HOOK_AT, 0.008, 0.014, Vector3.ONE, Vector3(PI / 2.0, 0, 0), 8, 3)
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
