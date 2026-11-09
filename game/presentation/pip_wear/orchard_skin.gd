extends RefCounted
## Orchard skin (body): soft pink blossom petals resting on the pip, as the
## Orchard board draws it (Fruits board 4a), and a slow blossom drift: three
## petals that circle the body below the face, turning slowly and rising and
## falling a little. The pip keeps its own colour.
##
## The resting petals lie on the head's and the torso's surfaces (kit
## on_head, lie_on), clear of the eyes, and move with those parts. The drift
## is one node on the upper body posed by look.animate(), so it steps at the
## idle card rate of the pip's own clock, holds still under Reduce motion,
## and runs only while the pip is shown and moving (a hidden pip is never
## advanced, and a step on a hidden drift returns at once). Meshes are baked
## once and shared. Draw calls: head petals, torso petals, the drift.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

const PETAL := Color("f5b8c9")
const PETAL_DEEP := Color("ee9fb6")
## A resting petal's half sizes: long, thick, wide. Big enough to read as a
## petal on a shop card.
const PETAL_SIZE := Vector3(0.072, 0.009, 0.046)
## A drifting petal's: as long, but narrower, since its width points out from
## the body and the drift stays inside the head's width.
const DRIFT_SIZE := Vector3(0.068, 0.008, 0.032)
const PETAL_SEGMENTS := 8
const GAP := 0.003
## Resting petals: [direction from the part's centre, turn (radians) of the
## petal's long side]. On the head they keep away from the eyes and the top,
## where a carried seed rests.
const HEAD_PETALS := [
	[Vector3(-0.3, -0.2, 0.22), 0.5],
	[Vector3(0.2, 0.2, 0.24), -0.3],
	[Vector3(0.33, -0.1, 0.05), 1.2],
	[Vector3(-0.15, 0.2, -0.2), 0.2],
]
const TORSO_PETALS := [
	[Vector3(0.35, -0.12, 0.9), -0.4],
	[Vector3(-0.45, -0.35, 0.85), 0.9],
	[Vector3(0.75, -0.35, 0.45), 0.3],
	[Vector3(-0.8, -0.15, -0.2), -0.6],
]
## The drift's petals, upper body space: [angle round the body, height,
## distance out, tilt]. All below the face, clear of the body and the feet,
## and no wider than the head, so every pip view keeps them in frame.
const DRIFT := [[0.4, 0.18, 0.3, 0.5], [2.5, 0.24, 0.31, -0.6], [4.4, 0.29, 0.31, 0.9]]
## Radians a second the drift turns, and its rise and fall (metres, radians a second).
const DRIFT_TURN := 0.35
const DRIFT_BOB := 0.025
const DRIFT_BOB_SPEED := 0.9

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("orchard_skin:head", _head), Kit.vertex_material())
	look.mesh(look.torso(), Kit.cached_mesh("orchard_skin:torso", _torso), Kit.vertex_material())
	var drift: MeshInstance3D = look.mesh(look.upper_body(), Kit.cached_mesh("orchard_skin:drift", _drift), Kit.vertex_material())
	drift.name = "Drift"
	look.animate(func(_worn: RefCounted, seconds: float) -> void:
		if not drift.is_visible_in_tree(): return
		drift.rotation.y = seconds * DRIFT_TURN
		drift.position.y = sin(seconds * DRIFT_BOB_SPEED) * DRIFT_BOB)

static func _head() -> Mesh:
	var parts := Kit.Parts.new()
	for index in range(HEAD_PETALS.size()):
		var petal: Array = HEAD_PETALS[index]
		parts.blob_at(_colour(index), Kit.on_head(petal[0], _toward(petal[1]), PETAL_SIZE, GAP), PETAL_SEGMENTS, 2)
	return parts.commit()

static func _torso() -> Mesh:
	var parts := Kit.Parts.new()
	for index in range(TORSO_PETALS.size()):
		var petal: Array = TORSO_PETALS[index]
		parts.blob_at(_colour(index + 1), Kit.lie_on(Meshes.torso_surface(petal[0]), _toward(petal[1]), PETAL_SIZE, GAP), PETAL_SEGMENTS, 2)
	return parts.commit()

static func _drift() -> Mesh:
	var parts := Kit.Parts.new()
	for index in range(DRIFT.size()):
		var petal: Array = DRIFT[index]
		var angle := float(petal[0])
		var at := Vector3(sin(angle) * float(petal[2]), float(petal[1]), cos(angle) * float(petal[2]))
		parts.blob(_colour(index), at, DRIFT_SIZE, Vector3(float(petal[3]), angle, float(petal[3]) * 0.5), PETAL_SEGMENTS, 2)
	return parts.commit()

static func _colour(index: int) -> Color:
	return PETAL if index % 2 == 0 else PETAL_DEEP

## The petal's long side, turned `turn` from level, before it is laid on the surface.
static func _toward(turn: float) -> Vector3:
	return Vector3(cos(turn), sin(turn), 0.0)
