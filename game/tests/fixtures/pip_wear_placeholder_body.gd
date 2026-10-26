extends RefCounted
## A placeholder body cosmetic for tests (test_pip_outfit.gd): it swaps the
## torso's and the feet's meshes for others with the same pivots and adds a
## piece on the torso, the two ways a body item may change the body's shape.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Look = preload("res://presentation/spirit_look.gd")

static func wear(look: RefCounted) -> void:
	look.swap_mesh(look.torso(), Kit.cached_mesh("test:placeholder_torso", func() -> Mesh:
		var parts := Kit.Parts.new()
		parts.blob(Color.WHITE, Vector3.ZERO, Look.TORSO_HALF * 1.1)
		return parts.commit()))
	var foot := Kit.cached_mesh("test:placeholder_foot", func() -> Mesh:
		var parts := Kit.Parts.new()
		parts.blob(Color.WHITE, Vector3.ZERO, Look.FOOT_HALF * 1.2)
		return parts.commit())
	for each: Node3D in look.feet(): look.swap_mesh(look.foot_mesh(each), foot)
	look.mesh(look.torso(), Kit.cached_mesh("test:placeholder_fin", func() -> Mesh:
		var parts := Kit.Parts.new()
		parts.blob(Color.RED, Vector3(0, 0.05, -0.2), Vector3(0.03, 0.08, 0.05))
		return parts.commit()), Kit.vertex_material())
	# The head is never replaced: this call must be refused.
	look.swap_mesh(look.head(), foot)
