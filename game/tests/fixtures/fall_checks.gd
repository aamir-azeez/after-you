extends RefCounted
## The checks every falling wear effect (presentation/kit/fall_effect.gd) gets,
## whatever its shape or numbers: test_pip_outfit.gd runs them on the Orchard
## skin, test_fall_effect.gd on every shape and every sample recipe. A new
## falling skin calls path() and node() with its recipe and is covered.
##
## Each takes the suite's SceneTree and its check(value: bool, message: String).
const FallEffect = preload("res://presentation/kit/fall_effect.gd")
const PipOutfit = preload("res://presentation/pip_outfit.gd")
const Spirit = preload("res://presentation/spirit_visual.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Idle = preload("res://presentation/spirit_idle.gd")
const Stage = preload("res://presentation/kit/pip_stage.gd")
const Preview = preload("res://presentation/kit/spirit_preview.gd")
const RaceGhost = preload("res://presentation/race_ghost_view.gd")

## The pip views' control sizes (Settings, the name page, the Friends chip);
## the first is the narrowest.
const VIEWS := [Vector2(72, 100), Vector2(180, 236), Vector2(42, 56)]
## Facings checked from: the shop's rest turn, front, both sides, back and between.
const YAWS := [Preview.REST_YAW, 0.0, PI * 0.5, -PI * 0.5, PI, 1.0, -1.0, 2.4]
## A falling shape fainter than this is not drawn as anything.
const SHOWN := 0.02
const DT := 1.0 / 60.0

## Puts `recipe` on `spirit` as a worn item would, for a recipe no catalog
## item wears: through its own PipOutfit, so the pip's clock drives it.
static func dress(spirit: Node3D, recipe: Dictionary) -> MeshInstance3D:
	var look: RefCounted = PipOutfit.dress(spirit, {})
	spirit._wearing = look
	return FallEffect.wear(look, recipe)

## The falling effects `pip` wears.
static func falls(pip: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node: Node in pip.find_children("*", "MeshInstance3D", true, false):
		if node.has_meta(FallEffect.RECIPE_META): found.append(node)
	return found

## Each falling shape's own points, by its index (UV.x), as the mesh holds them.
static func shapes(recipe: Dictionary) -> Array[PackedVector3Array]:
	var arrays := FallEffect.mesh(recipe).surface_get_arrays(0)
	var found: Array[PackedVector3Array] = []
	for index in range(int(recipe.count)): found.append(PackedVector3Array())
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for at in range(vertices.size()): found[roundi(uvs[at].x)].append(vertices[at])
	return found

## The path: every fall of every shape for one pip seed (two with `dense`)
## plus falls drawn at the ends of every range, from top to bottom, from
## every facing while the pip idles (and in the narrowest view again while it
## dozes, its head sunk on its body), placed by FallEffect.fall_place as the
## shader places them: every point of a shown shape inside each pip view and
## of every shape inside the recipe's bounds, outside the head, the torso and
## the feet and clear of a carried seed (the usual one and the Lighthouse's
## lens). Shapes may cross the face. Then the loop is seamless. `make(color)`
## gives a pip wearing the fall, not yet in a tree; `outfit` frames the camera.
static func path(tree: SceneTree, check: Callable, label: String, recipe: Dictionary, make: Callable, outfit: Dictionary, dense: bool) -> void:
	var shape: PackedVector3Array = shapes(recipe)[0]
	var bounds: AABB = (recipe.bounds as AABB).grow(0.0001)
	var slots: Vector2i = recipe.slots
	var falls_drawn: Array[PackedFloat32Array] = []
	for key: int in ([FallEffect.pip_seed(1), FallEffect.pip_seed(2)] if dense else [FallEffect.pip_seed(1)]):
		for index in range(int(recipe.count)):
			for fall in range(slots.x if index % 2 == 0 else slots.y): falls_drawn.append(FallEffect.fall_draws(index, fall, key))
	var noise := RandomNumberGenerator.new()
	noise.seed = 77
	for corner in range(16):
		var draws := PackedFloat32Array()
		for at in range(FallEffect.DRAWS): draws.append(0.0 if noise.randf() < 0.5 else 0.99999)
		falls_drawn.append(draws)
	var heights := 61 if dense else 31
	for size: Vector2 in VIEWS:
		var narrowest: bool = size == VIEWS[0]
		var steps := heights * (2 if narrowest else 1)
		var outside := 0
		var unbounded := 0
		var in_head := 0
		var in_body := 0
		var in_feet := 0
		var in_seed := 0
		var shown := 0
		for yaw: float in (YAWS if narrowest else YAWS.slice(0, 4)):
			var view := SubViewport.new()
			view.size = Vector2i(size * 2.0)
			view.own_world_3d = true
			tree.root.add_child(view)
			var pip: Node3D = make.call(Look.PEACH)
			pip.facing_target = yaw
			pip.facing.rotation.y = yaw
			var camera := Stage.build(view, pip, outfit)
			pip.carrying_seed = true
			pip.advance_motion(Vector3.ZERO, 0.001, false)
			var fall: MeshInstance3D = falls(pip)[0]
			for step in range(steps):
				var u := float(step % heights) / (heights - 1) * 0.9999
				var dozing := step >= heights
				if step == heights: pip.set_pose(Idle.DOZE, {"toward": Vector3(1.6, 0, 0.4)})
				for frame in range(5): pip.advance_motion(Vector3.ZERO, DT, false)
				var from_fall := fall.global_transform
				var to_head: Transform3D = pip.head.global_transform.affine_inverse()
				var to_torso: Transform3D = pip.torso.global_transform.affine_inverse()
				var feet: Array[Transform3D] = []
				for foot: Node3D in pip.feet: feet.append(foot.global_transform.affine_inverse())
				var seeing := from_fall.affine_inverse() * camera.global_position
				var seeds: Array[Vector3] = []
				for radius: float in [0.13, 0.25]:
					pip.carried_radius = radius
					seeds.append(pip.global_transform * pip.carry_anchor_position())
				pip.carried_radius = 0.13
				for draws: PackedFloat32Array in falls_drawn:
					var placed: Dictionary = FallEffect.fall_place(recipe, draws, u, seeing)
					var alpha := float(placed.alpha)
					if alpha > SHOWN: shown += 1
					var frame: Transform3D = placed.frame
					for vertex: Vector3 in shape:
						var local := frame * vertex
						var point: Vector3 = from_fall * local
						if narrowest:
							if not bounds.has_point(local): unbounded += 1
							if _inside(to_head * point, Look.HEAD_HALF, Look.HEAD_POWER) < 1.0: in_head += 1
							if _inside(to_torso * point, Look.TORSO_HALF, Look.TORSO_POWER) < 1.0: in_body += 1
							for foot: Transform3D in feet:
								if ((foot * point) / Look.FOOT_HALF).length() < 1.0: in_feet += 1
							if point.distance_to(seeds[0]) < 0.13 or point.distance_to(seeds[1]) < 0.25: in_seed += 1
						if alpha > SHOWN and not dozing and not camera.is_position_in_frustum(point): outside += 1
			view.free()
		check.call(shown > 0, "%s: the falling shapes show in the %dx%d view" % [label, size.x, size.y])
		check.call(outside == 0, "%s: and stay inside it through every fall, from every side: %d points outside" % [label, outside])
		if narrowest:
			check.call(unbounded == 0, "%s: every point stays inside the fall's bounds, so it is never culled mid-fall: %d outside" % [label, unbounded])
			check.call(in_head == 0 and in_body == 0 and in_feet == 0, "%s: never passing through the pip: %d points in the head, %d in the body, %d in the feet" % [label, in_head, in_body, in_feet])
			check.call(in_seed == 0, "%s: and clear of a carried seed: %d points" % [label, in_seed])
	var seam := 0
	var seeing := Vector3(0.6, 0.7, 2.3)
	var loop: float = recipe.loop
	for key: int in [FallEffect.pip_seed(1), FallEffect.pip_seed(5)]:
		for index in range(int(recipe.count)):
			var turn := loop / (slots.x if index % 2 == 0 else slots.y)
			for at: float in [0.0, 0.37, turn - 0.01, turn + 0.01, loop * 0.377, loop * 0.597, loop - 0.05]:
				var now := FallEffect.fall_shape(recipe, index, at, key, seeing)
				var later := FallEffect.fall_shape(recipe, index, at + loop, key, seeing)
				if not (now.frame as Transform3D).is_equal_approx(later.frame) or absf(float(now.alpha) - float(later.alpha)) > 0.001: seam += 1
	check.call(seam == 0, "%s: the fall loops perfectly: a loop later every shape is where it was (%d differ)" % [label, seam])

## The worn node: one draw call with the kit's shared shader and the recipe's
## values, round the upper body, no shadow, shown only while the pip's clock
## runs (never still, hidden under Reduce motion) and moved by the shader
## alone at the idle rate; shared by two pips, each with its own seed; and
## see-through on the race ghost. `make()` gives a pip in the tree wearing it.
static func node(check: Callable, label: String, recipe: Dictionary, make: Callable) -> void:
	var pip: Node3D = make.call()
	var found := falls(pip)
	if not check.call(found.size() == 1, "%s: the pip wears one fall: %d" % [label, found.size()]):
		pip.free()
		return
	var fall := found[0]
	check.call(pip.upper_body.is_ancestor_of(fall) and fall.name == FallEffect.NODE_NAME, "%s: it falls round the body" % label)
	check.call(fall.mesh.get_surface_count() == 1 and fall.material_override is ShaderMaterial and fall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: as one draw call with its shader, casting no shadow" % label)
	var material: ShaderMaterial = fall.material_override
	var values := FallEffect.uniforms(FallEffect.recipe(recipe))
	var differ: Array[String] = []
	for key: StringName in values:
		if material.get_shader_parameter(key) != values[key]: differ.append(str(key))
	check.call(material.shader == FallEffect.SHADER and differ.is_empty() and fall.custom_aabb == recipe.bounds, "%s: the kit's shader with the recipe's values and bounds (%s differ)" % [label, differ])
	check.call(not fall.visible, "%s: a still pip shows no falling shapes" % label)
	for frame in range(12): pip.advance_motion(Vector3.ZERO, DT, false)
	check.call(fall.visible, "%s: and a moving one shows them falling" % label)
	var moved := 0
	var posed := fall.transform
	for frame in range(60):
		pip.advance_motion(Vector3.ZERO, DT, false)
		if fall.transform != posed: moved += 1
	check.call(moved == 0, "%s: moved by the shader alone: the node never moves" % label)
	var ticks := 0
	var clock: Variant = fall.get_instance_shader_parameter(FallEffect.CLOCK)
	for frame in range(60):
		pip.advance_motion(Vector3.ZERO, DT, false)
		if fall.get_instance_shader_parameter(FallEffect.CLOCK) != clock: ticks += 1
		clock = fall.get_instance_shader_parameter(FallEffect.CLOCK)
	check.call(ticks >= 10 and ticks <= 12, "%s: on the pip's own clock at the idle rate: %d steps in 1 s" % [label, ticks])
	for frame in range(30): pip.advance_motion(Vector3.ZERO, DT, true)
	check.call(not fall.visible, "%s: under Reduce motion none fall" % label)
	for frame in range(30): pip.advance_motion(Vector3.ZERO, DT, false)
	check.call(fall.visible, "%s: and they fall again when it is off" % label)
	var second: Node3D = make.call()
	var second_fall: MeshInstance3D = falls(second)[0]
	check.call(second_fall.material_override == fall.material_override and second_fall.mesh == fall.mesh, "%s: two pips share its mesh and material" % label)
	check.call(not is_equal_approx(float(second_fall.get_instance_shader_parameter(FallEffect.SEED)), float(fall.get_instance_shader_parameter(FallEffect.SEED))), "%s: and each falls with its own seed" % label)
	check.call(FallEffect.VEIL_META == RaceGhost.VEIL_UNIFORM and fall.get_meta(FallEffect.VEIL_META) == FallEffect.VEIL, "%s: the race ghost fades it through its own shader" % label)
	RaceGhost._veil(second, Look.PEACH)
	check.call(second_fall.material_override == fall.material_override and is_equal_approx(float(second_fall.get_instance_shader_parameter(FallEffect.VEIL)), RaceGhost.VEIL), "%s: so a ghost wearing it keeps it falling, see-through" % label)
	second.free()
	pip.free()

## Below 1 inside the rounded box of `half` and `power` round the origin.
static func _inside(point: Vector3, half: Vector3, power: float) -> float:
	return pow(absf(point.x / half.x), power) + pow(absf(point.y / half.y), power) + pow(absf(point.z / half.z), power)
