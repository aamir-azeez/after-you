extends RefCounted
## Top 10 ribbon (hat, earned): a small blue prize rosette with a gold middle
## and two tails, pinned at the head's front corner across from the leaf,
## clear of the eyes. One baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const BLUE := Color("4f7fc4")
const BLUE_LIGHT := Color("6b95d3")
const GOLD := Color("e9b949")
## Head space: where the rosette is pinned (the upper front corner, inside the
## head's outline in every view) and how it faces: mostly forward,
## so the three-quarter views see its face.
const AT := Vector3(0.235, 0.205, 0.215)
const TURN := Vector3(-0.35, 0.4, -0.15)
const FOLDS := 10
const FOLD_REACH := 0.042
const FOLD_SIZE := Vector3(0.026, 0.017, 0.012)

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("top_ten_ribbon", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.push(Kit.Parts.place(AT, TURN))
	for index in range(FOLDS):
		var a := TAU * float(index) / float(FOLDS)
		parts.blob(BLUE if index % 2 == 0 else BLUE_LIGHT, Vector3(cos(a), sin(a), 0) * FOLD_REACH, FOLD_SIZE, Vector3(0, 0, a), 6, 2)
	parts.blob(GOLD, Vector3(0, 0, 0.01), Vector3(0.027, 0.027, 0.014), Vector3.ZERO, 8, 4)
	for side: float in [-1.0, 1.0]:
		parts.blob(BLUE, Vector3(0.022 * side, -0.075, -0.004), Vector3(0.016, 0.042, 0.007), Vector3(0, 0, 0.25 * side), 5, 2)
	parts.pop()
	return parts.commit()
