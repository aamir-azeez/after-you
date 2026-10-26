extends RefCounted
## Gold leaf (leaf): the leaf a little bigger and gold, with three small
## sparkles and a soft glow beside it that twinkle at the idle rate. The
## sparkles and glow hang from the leaf, so they sway, turn and hide with it.
## Draw calls: the leaf's own, the sparkles and the glow.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

const GOLD := Color("e9a823")
const SPARKLE := Color("fff1b8")
const GLOW := Color("ffd36a")
const LEAF_SCALE := 1.12
## Upper body space: the sparkles' middle, each sparkle's [x, y, size] around
## it, and the glow.
const SPARKLES_AT := Vector3(-0.26, 0.98, 0.07)
const SPARKLES := [[-0.06, 0.02, 0.06], [0.095, 0.06, 0.044], [-0.04, -0.08, 0.032]]
const GLOW_AT := Vector3(-0.235, 0.93, 0.0)
const GLOW_SIZE := 0.3
const GLOW_STRENGTH := 0.55
## Seconds for one twinkle.
const TWINKLE := 1.6

static func wear(look: RefCounted) -> void:
	var leaf: MeshInstance3D = look.leaf()
	look.swap_mesh(leaf, Kit.cached_mesh("gold_leaf", func() -> Mesh: return Kit.scaled(Meshes.leaf(), LEAF_SCALE)))
	look.set_material(leaf, Primitives.shared_material(GOLD, 0.38, GOLD, 0.22))
	var follow: Node3D = look.attach(leaf, Kit.follow(look.leaf_rest()))
	var stars := Kit.stars("gold_leaf", SPARKLES, SPARKLE)
	stars.position = SPARKLES_AT
	look.attach(follow, stars)
	var glow := Kit.halo(GLOW_SIZE, GLOW, GLOW_STRENGTH)
	glow.position = GLOW_AT
	look.attach(follow, glow)
	var material: StandardMaterial3D = glow.material_override
	look.animate(func(seconds: float) -> void:
		var twinkle := 0.5 + 0.5 * sin(seconds * TAU / TWINKLE)
		stars.scale = Vector3.ONE * (0.85 + 0.3 * twinkle)
		material.albedo_color.a = GLOW_STRENGTH * (0.75 + 0.25 * twinkle))
