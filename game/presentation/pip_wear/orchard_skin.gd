extends RefCounted
## Orchard skin (body): soft pink blossom petals resting on the pip, as the
## Orchard board draws it (Fruits board 4a), and petals falling round it like
## leaves from a tree. The pip keeps its own colour.
##
## The resting petals lie on the head's and the torso's surfaces (kit
## on_head, lie_on), clear of the eyes, and move with those parts.
##
## The falling petals are the kit's falling effect (kit/fall_effect.gd) with
## the petal shape in the resting petals' two pinks; its other numbers are the
## kit's defaults, which are this skin's fall. Draw calls: head petals, torso
## petals, the falling petals.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")
const FallEffect = preload("res://presentation/kit/fall_effect.gd")

const PETAL := Color("f5b8c9")
const PETAL_DEEP := Color("ee9fb6")
## A resting petal's half sizes: long, thick, wide. Big enough to read as a
## petal on a shop card.
const PETAL_SIZE := Vector3(0.072, 0.009, 0.046)
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

## The falling petals (kit/fall_effect.gd DEFAULTS for the rest).
const FALL := {"id": "orchard_skin", "shape": &"petal", "colors": [PETAL, PETAL_DEEP]}

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("orchard_skin:head", _head), Kit.vertex_material())
	look.mesh(look.torso(), Kit.cached_mesh("orchard_skin:torso", _torso), Kit.vertex_material())
	FallEffect.wear(look, FALL)

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

static func _colour(index: int) -> Color:
	return PETAL if index % 2 == 0 else PETAL_DEEP

## The petal's long side, turned `turn` from level, before it is laid on the surface.
static func _toward(turn: float) -> Vector3:
	return Vector3(cos(turn), sin(turn), 0.0)
