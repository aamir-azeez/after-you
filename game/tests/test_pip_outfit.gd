extends SceneTree
## Outfits on a pip (SpiritVisual.wear, presentation/pip_outfit.gd and the art
## in presentation/pip_wear/):
## - the default look adds nothing and changes nothing;
## - each item stays within the board's budget (draw calls, triangles) and
##   comes off exactly, alone and in every combination of the three slots;
## - leaf items hang from the leaf; the Straw hat lifts it; each fruit hood
##   hides the plain leaf, and a worn leaf item grows out of its top without
##   cutting into it at any sway;
## - placement: no item covers the eyes or reaches into a carried seed, the
##   daisy sits outside the head, and a glow sprite sits outside it too; the
##   Orchard skin's resting petals sink into neither the head nor the body,
##   and its falling petals, through their whole loop and seen from every
##   side, stay out of the head, the body and the feet, clear of a carried
##   seed and inside every pip view, and loop perfectly;
## - a body item may swap the torso and feet meshes and add pieces, never the
##   head, and every gameplay value stays identical;
## - a tall cap lifts a carried seed, a big leaf lifts it with the leaf's
##   own lift, and off again the seed sits where it did;
## - moving parts step at the idle card rate of the pip's own clock and hold
##   still under Reduce motion; the Orchard skin's falling petals are one draw
##   call placed by their shader from the pip's clock, shown only while it
##   runs, and see-through on the race ghost;
## - shared meshes and materials are released at shutdown.
const Spirit = preload("res://presentation/spirit_visual.gd")
const PipOutfit = preload("res://presentation/pip_outfit.gd")
const SpiritFace = preload("res://presentation/spirit_face.gd")
const Outfit = preload("res://services/outfit.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Idle = preload("res://presentation/spirit_idle.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const Stage = preload("res://presentation/kit/pip_stage.gd")
const Preview = preload("res://presentation/kit/spirit_preview.gd")
const Orchard = preload("res://presentation/pip_wear/orchard_skin.gd")
const RaceGhost = preload("res://presentation/race_ghost_view.gd")
const PLACEHOLDER_BODY = preload("res://tests/fixtures/pip_wear_placeholder_body.gd")

## The board's budget per item.
const MAX_DRAWS := 4
const MAX_TRIANGLES := 640
## Nothing solid comes nearer the eyes' anchors than this (the open eye's outer
## radius is up to about 0.10).
const EYE_CLEAR := 0.11
## How far a glance moves each eye (spirit_visual.gd: the eye markers' gaze).
const GLANCE := Vector2(0.018, 0.009)
const FACE_PARAMS := ["body_color", "cream_color", "pupil_color", "blush_color", "blush_strength", "blush_soft", "eye_xy", "eye_squash", "look_shift", "pupil_rim", "tear_neck_root"]
const DT := 1.0 / 60.0
## Hats seated on the head's surface: no part of them is inside the head.
const SEATED := ["daisy", "top_ten_ribbon", "blossom_crown", "apple_hood", "blueberry_hood"]
## The fruit hoods (presentation/pip_wear/fruit_hood.gd).
const HOODS := ["apple_hood", "blueberry_hood"]
const HOOD = preload("res://presentation/pip_wear/fruit_hood.gd")
## How far from its stalk a leaf may still be inside a fruit hood.
const STALK_TUCK := 0.045
## The pip views' control sizes (Settings, the name page, the Friends chip).
const VIEWS := [Vector2(72, 100), Vector2(180, 236), Vector2(42, 56)]
## Parts drawn on top that are not solid (a glow, a beam, sparkles), and the
## Orchard skin's falling petals, which the shader places (checked through
## Orchard.fall_petal instead).
const NOT_SOLID := ["Halo", "Beam", "Stars", Orchard.FALL_NAME]
## Facings the falling petals are checked from: the shop's rest turn, front,
## both sides, back and between.
const FALL_YAWS := [Preview.REST_YAW, 0.0, PI * 0.5, -PI * 0.5, PI, 1.0, -1.0, 2.4]
## A falling petal fainter than this is not drawn as anything.
const FALL_SHOWN := 0.02

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	# The items are not released yet; these suites wear them all.
	Outfit.show_unreleased = true
	_default_look()
	_each_item()
	_combinations()
	_leaf()
	_hood_leaf()
	_hood_clears_body()
	_petals_clear()
	_fall_path()
	_placement()
	_in_frame()
	_body_shape()
	_animation()
	_seed_lift()
	_released()
	for child: Node in root.get_children():
		if child is Spirit: child.free()
	print("PIP OUTFIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _spirit(color: Color = Look.PEACH) -> Node3D:
	var spirit: Node3D = Spirit.new(color)
	root.add_child(spirit)
	spirit.advance_motion(Vector3.ZERO, 0.001, false)
	return spirit

## Every node under the pip with its transform, visibility, mesh and material,
## and the face's shader and parameters.
func _state(spirit: Node3D) -> Dictionary:
	var rows: Array = []
	_walk(spirit, spirit, rows)
	var face: ShaderMaterial = spirit.face_art.material
	var params := {}
	for key: String in FACE_PARAMS + Array(SpiritFace.SHAPE_KEYS): params[key] = face.get_shader_parameter(key)
	return {"rows": rows, "shader": face.shader, "params": params, "head": spirit.head.material_override}

func _walk(node: Node, top: Node, rows: Array) -> void:
	var row: Array = [str(top.get_path_to(node)), node.get_class()]
	if node is Node3D: row.append_array([node.transform, node.visible])
	if node is MeshInstance3D: row.append_array([node.mesh, node.material_override])
	rows.append(row)
	for child: Node in node.get_children(): _walk(child, top, rows)

## Every mesh among the nodes and under them, once each.
func _meshes(nodes: Array) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node: Node in nodes:
		var here: Array[Node] = [node]
		here.append_array(node.find_children("*", "MeshInstance3D", true, false))
		for each: Node in here:
			if each is MeshInstance3D and not found.has(each): found.append(each)
	return found

func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		total += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total

func _default_look() -> void:
	var spirit := _spirit()
	var before := _state(spirit)
	var count := spirit.find_children("*", "", true, false).size()
	spirit.wear({})
	spirit.wear(Outfit.EMPTY)
	spirit.wear({"hat": "nothing", "badge": "daisy"})
	_check(spirit._wearing == null and spirit.outfit().is_empty(), "The default look wears nothing")
	Outfit.show_unreleased = false
	spirit.wear({"hat": "daisy", "body": "tide"})
	_check(spirit._wearing == null, "A pip never wears an item that is not released, whatever its outfit says")
	Outfit.show_unreleased = true
	_check(spirit.find_children("*", "", true, false).size() == count and _state(spirit) == before, "and adds no node and changes nothing")
	spirit.advance_motion(Vector3.ZERO, DT, false)
	var plain := _spirit()
	plain.advance_motion(Vector3.ZERO, DT, false)
	_check(spirit.sprout.position == plain.sprout.position, "The leaf rests where it always did")
	spirit.free()
	plain.free()

func _each_item() -> void:
	var spirit := _spirit()
	var before := _state(spirit)
	for id: String in Catalog.ids():
		var outfit := Outfit.of(id, true)
		if Catalog.art(id).is_empty():
			spirit.wear(outfit)
			_check(spirit._wearing == null or spirit._wearing.nodes().is_empty(), "%s has no art yet and draws nothing" % id)
			spirit.wear({})
			continue
		spirit.wear(outfit)
		_check(spirit.outfit() == outfit, "%s is worn" % id)
		var meshes := _meshes(spirit._wearing.nodes())
		var triangles := 0
		for mesh: MeshInstance3D in meshes: triangles += _triangles(mesh.mesh)
		_check(meshes.size() <= MAX_DRAWS, "%s adds at most %d draw calls: %d" % [id, MAX_DRAWS, meshes.size()])
		_check(triangles <= MAX_TRIANGLES, "%s stays within about 600 triangles: %d" % [id, triangles])
		print("ITEM %s: %d draws, %d triangles" % [id, meshes.size(), triangles])
		for node: Node in spirit._wearing.nodes():
			_check(not node is CollisionObject3D and node.find_children("*", "CollisionObject3D", true, false).is_empty() and node.find_children("*", "CollisionShape3D", true, false).is_empty(), "%s adds nothing physical" % id)
		spirit.wear({})
		_check(_state(spirit) == before, "%s comes off exactly" % id)
	spirit.free()

## Every combination of the three slots, worn one after another on one pip.
func _combinations() -> void:
	var by_slot: Dictionary = {}
	for slot: String in Catalog.slots(): by_slot[slot] = [""]
	for id: String in Catalog.ids():
		if not Catalog.slot(id).is_empty(): by_slot[Catalog.slot(id)].append(id)
	var spirit := _spirit()
	var before := _state(spirit)
	var worn := 0
	var all_worn := true
	var leaf_ok := true
	for hat: String in by_slot.hat:
		for body: String in by_slot.body:
			for leaf: String in by_slot.leaf:
				var raw := {}
				if not hat.is_empty(): raw.hat = hat
				if not body.is_empty(): raw.body = body
				if not leaf.is_empty(): raw.leaf = leaf
				spirit.wear(raw)
				spirit.advance_motion(Vector3.ZERO, DT, false)
				all_worn = all_worn and spirit.outfit() == Outfit.from(raw, true)
				if spirit._wearing != null and not leaf.is_empty():
					leaf_ok = leaf_ok and spirit.sprout.visible
				worn += 1
	_check(worn >= 36 and all_worn, "Every combination of the slots is worn: %d" % worn)
	_check(leaf_ok, "The leaf shows with every hat and leaf item")
	spirit.wear({})
	spirit.reset_motion()
	var fresh := _spirit()
	fresh.reset_motion()
	_check(_state(spirit).params == before.params and _state(spirit).shader == before.shader and _state(spirit).head == before.head, "After them all the face is the plain face")
	_check(_state(spirit).rows.size() == before.rows.size(), "and no node is left behind")
	spirit.free()
	fresh.free()

func _leaf() -> void:
	var spirit := _spirit()
	spirit.wear(Outfit.of("gold_leaf", true))
	for node: Node in spirit._wearing.nodes():
		_check(spirit.sprout.is_ancestor_of(node), "Gold leaf's %s hangs from the leaf, so it sways and hides with it" % node.name)
	_check(spirit.sprout.material_override != Spirit._body_material(Look.LEAF), "The leaf turns gold")
	spirit.sprout.visible = false
	var hidden := true
	for node: Node in spirit._wearing.nodes(): hidden = hidden and not (node as Node3D).is_visible_in_tree()
	_check(hidden, "A hidden leaf hides the sparkles and glow with it")
	spirit.sprout.visible = true
	spirit.wear({})
	_check(spirit.sprout.material_override == Spirit._body_material(Look.LEAF) and spirit.sprout.mesh == load("res://presentation/spirit_meshes.gd").leaf(), "Off again, the leaf is the plain leaf")
	var straw := _spirit()
	var plain := _spirit()
	straw.wear(Outfit.from({"hat": "straw_hat", "leaf": "gold_leaf"}, true))
	for spirit_each: Node3D in [straw, plain]:
		for frame in range(30): spirit_each.advance_motion(Vector3.ZERO, DT, false)
	_check(is_equal_approx(straw.sprout.position.y - plain.sprout.position.y, 0.075), "The Straw hat lifts the leaf 7.5 cm, gold or not: %.4f" % (straw.sprout.position.y - plain.sprout.position.y))
	straw.wear({})
	straw.advance_motion(Vector3.ZERO, DT, false)
	plain.advance_motion(Vector3.ZERO, DT, false)
	_check(straw.sprout.position == plain.sprout.position, "Off again, the leaf goes back down")
	spirit.free()
	straw.free()
	plain.free()

## Each fruit hood's top stands in for the pip's leaf: the plain leaf hides
## under it and comes back with it off. A worn leaf item shows, its stalk
## tucked under the hood's top, and no part of it farther than STALK_TUCK
## from the stalk is under the hood, idle or walking. So does the plain leaf
## shown on purpose (show_leaf(), the leaderboard celebration's gold leaf).
func _hood_leaf() -> void:
	for hood: String in HOODS:
		var spirit := _spirit()
		spirit.wear(Outfit.of(hood, true))
		_check(not spirit.sprout.visible, "The %s hides the plain leaf" % hood)
		spirit.show_leaf()
		_check(spirit.sprout.visible, "show_leaf() brings it back under the %s" % hood)
		_leaf_clears_hood(spirit, "The plain leaf shown under the %s" % hood)
		spirit.wear({})
		_check(spirit.sprout.visible, "Off again, the leaf shows")
		spirit.wear(Outfit.of(hood, true))
		_check(not spirit.sprout.visible, "and the %s worn again hides it again" % hood)
		spirit.free()
		for leaf: String in Catalog.ids():
			if Catalog.slot(leaf) != "leaf": continue
			var capped := _spirit()
			capped.wear(Outfit.from({"hat": hood, "leaf": leaf}, true))
			_check(capped.sprout.visible, "With %s the leaf shows under the %s" % [leaf, hood])
			_leaf_clears_hood(capped, "%s under the %s" % [leaf, hood])
			capped.free()

func _leaf_clears_hood(capped: Node3D, label: String) -> void:
	var under := 0
	var tucked := true
	var lowest := INF
	for frame in range(240):
		capped.advance_motion(Vector3(0.02, 0, 0) if frame >= 150 else Vector3.ZERO, DT, false)
		if frame % 6 != 0: continue
		var to_head: Transform3D = capped.head.global_transform.affine_inverse()
		var stalk: Vector3 = to_head * capped.sprout.global_position
		tucked = tucked and stalk.y < HOOD.top_height(stalk)
		var leaf_parts: Array[MeshInstance3D] = [capped.sprout]
		for node: Node in capped.sprout.find_children("*", "MeshInstance3D", true, false):
			if not node.name in NOT_SOLID: leaf_parts.append(node as MeshInstance3D)
		for point: Vector3 in _points_in_head(capped, leaf_parts):
			var top: float = HOOD.top_height(point)
			if point.distance_to(stalk) > STALK_TUCK and point.y < top:
				under += 1
				lowest = minf(lowest, point.y - top)
	_check(tucked, "%s: its stalk starts under the hood" % label)
	_check(under == 0, "%s grows out of the hood and never cuts into it: %d points (deepest %.3f)" % [label, under, lowest])

## Each fruit hood reaches round under to the jaw: idle, walking or dozing, it
## never sinks into the body, which moves apart from the head. Its face
## opening stays clear of the eyes even at their farthest glance (GLANCE).
func _hood_clears_body() -> void:
	for hood: String in HOODS:
		var spirit := _spirit()
		spirit.wear(Outfit.of(hood, true))
		var near_eye := 0
		for point: Vector3 in _solid_points(spirit):
			for side: float in [-1.0, 1.0]:
				for up: float in [-1.0, 1.0]:
					if point.z > 0.0 and Vector2(point.x - side * (Look.EYE_X + GLANCE.x), point.y - Look.EYE_Y - up * GLANCE.y).length() < EYE_CLEAR: near_eye += 1
		_check(near_eye == 0, "The %s stays clear of the eyes at their farthest glance: %d points" % [hood, near_eye])
		var in_body := 0
		for frame in range(360):
			if frame == 240: spirit.set_pose(&"doze")
			spirit.advance_motion(Vector3(0.03, 0, 0.01) if frame >= 120 and frame < 240 else Vector3.ZERO, DT, false)
			if frame % 6 != 0: continue
			var to_torso: Transform3D = spirit.torso.global_transform.affine_inverse() * spirit.head.global_transform
			for point: Vector3 in _solid_points(spirit):
				var body: Vector3 = to_torso * point
				if pow(absf(body.x / Look.TORSO_HALF.x), Look.TORSO_POWER) + pow(absf(body.y / Look.TORSO_HALF.y), Look.TORSO_POWER) + pow(absf(body.z / Look.TORSO_HALF.z), Look.TORSO_POWER) < 1.0: in_body += 1
		_check(in_body == 0, "The %s never sinks into the body: %d points" % [hood, in_body])
		spirit.free()

## The Orchard skin's resting petals never sink into the head or the body.
func _petals_clear() -> void:
	var spirit := _spirit()
	spirit.wear(Outfit.of("orchard_skin", true))
	var in_head := 0
	var in_body := 0
	# Through the idle's own movement.
	for frame in range(480):
		spirit.advance_motion(Vector3.ZERO, DT, false)
		if frame % 12 != 0: continue
		var to_torso: Transform3D = spirit.torso.global_transform.affine_inverse() * spirit.head.global_transform
		for point: Vector3 in _solid_points(spirit):
			var body: Vector3 = to_torso * point
			if _inside_head(point) < 1.0: in_head += 1
			if pow(absf(body.x / Look.TORSO_HALF.x), Look.TORSO_POWER) + pow(absf(body.y / Look.TORSO_HALF.y), Look.TORSO_POWER) + pow(absf(body.z / Look.TORSO_HALF.z), Look.TORSO_POWER) < 1.0: in_body += 1
	_check(in_head == 0 and in_body == 0, "The Orchard skin's petals stay on the head and body, never in them: %d in the head, %d in the body" % [in_head, in_body])
	spirit.free()

## The Orchard skin's falling petals, every fall of every petal for two pip
## seeds plus falls drawn at the ends of every range, from top to bottom,
## from every facing while the pip idles (and in the narrowest view again
## while it dozes, its head sunk on its body), placed by Orchard.fall_place as
## the shader places them: every point of a shown petal inside each pip view,
## and of every petal outside the head, the torso and the feet and clear of a
## carried seed (the usual one and the Lighthouse's lens). Petals may cross
## the face. Then: the loop is seamless, the hash is the shader's, and falls
## differ.
func _fall_path() -> void:
	var shape: PackedVector3Array = _fall_shapes()[0]
	var falls: Array[PackedFloat32Array] = []
	for key: int in [Orchard.pip_seed(1), Orchard.pip_seed(2)]:
		for index in range(Orchard.FALL_PETALS):
			for fall in range(Orchard.FALL_SLOTS.x if index % 2 == 0 else Orchard.FALL_SLOTS.y): falls.append(Orchard.fall_draws(index, fall, key))
	var noise := RandomNumberGenerator.new()
	noise.seed = 77
	for corner in range(16):
		var draws := PackedFloat32Array()
		for at in range(Orchard.FALL_DRAWS): draws.append(0.0 if noise.randf() < 0.5 else 0.99999)
		falls.append(draws)
	var heights := 61
	for size: Vector2 in VIEWS:
		var narrowest: bool = size == VIEWS[0]
		var steps := heights * (2 if narrowest else 1)
		var outside := 0
		var in_head := 0
		var in_body := 0
		var in_feet := 0
		var in_seed := 0
		var shown := 0
		for yaw: float in (FALL_YAWS if narrowest else FALL_YAWS.slice(0, 4)):
			var view := SubViewport.new()
			view.size = Vector2i(size * 2.0)
			view.own_world_3d = true
			root.add_child(view)
			var outfit := Outfit.of("orchard_skin", true)
			var pip := Stage.pip(Look.PEACH, outfit)
			pip.facing_target = yaw
			pip.facing.rotation.y = yaw
			var camera := Stage.build(view, pip, outfit)
			pip.carrying_seed = true
			pip.advance_motion(Vector3.ZERO, 0.001, false)
			var fall: MeshInstance3D = pip.find_child(Orchard.FALL_NAME, true, false)
			for step in range(steps):
				var u := float(step % heights) / (heights - 1) * 0.9999
				var dozing := step >= heights
				if step == heights: pip.set_pose(Idle.DOZE, {"toward": Vector3(1.6, 0, 0.4)})
				for frame in range(5): pip.advance_motion(Vector3.ZERO, DT, false)
				var from_fall := fall.global_transform
				var to_head := pip.head.global_transform.affine_inverse()
				var to_torso := pip.torso.global_transform.affine_inverse()
				var feet: Array[Transform3D] = []
				for foot: Node3D in pip.feet: feet.append(foot.global_transform.affine_inverse())
				var seeing := from_fall.affine_inverse() * camera.global_position
				var seeds: Array[Vector3] = []
				for radius: float in [0.13, 0.25]:
					pip.carried_radius = radius
					seeds.append(pip.global_transform * pip.carry_anchor_position())
				pip.carried_radius = 0.13
				for draws: PackedFloat32Array in falls:
					var placed: Dictionary = Orchard.fall_place(draws, u, seeing)
					var alpha := float(placed.alpha)
					if alpha > FALL_SHOWN: shown += 1
					for vertex: Vector3 in shape:
						var point: Vector3 = from_fall * ((placed.frame as Transform3D) * vertex)
						if narrowest:
							if _inside_head(to_head * point) < 1.0: in_head += 1
							var body: Vector3 = to_torso * point
							if pow(absf(body.x / Look.TORSO_HALF.x), Look.TORSO_POWER) + pow(absf(body.y / Look.TORSO_HALF.y), Look.TORSO_POWER) + pow(absf(body.z / Look.TORSO_HALF.z), Look.TORSO_POWER) < 1.0: in_body += 1
							for foot: Transform3D in feet:
								if ((foot * point) / Look.FOOT_HALF).length() < 1.0: in_feet += 1
							if point.distance_to(seeds[0]) < 0.13 or point.distance_to(seeds[1]) < 0.25: in_seed += 1
						if alpha > FALL_SHOWN and not dozing and not camera.is_position_in_frustum(point): outside += 1
			view.free()
		_check(shown > 0, "The Orchard skin's falling petals show in the %dx%d view" % [size.x, size.y])
		_check(outside == 0, "and stay inside it through every fall, from every side: %d points outside" % outside)
		if narrowest:
			_check(in_head == 0 and in_body == 0 and in_feet == 0, "never passing through the pip: %d points in the head, %d in the body, %d in the feet" % [in_head, in_body, in_feet])
			_check(in_seed == 0, "and clear of a carried seed: %d points" % in_seed)
	var seam := 0
	var camera := Vector3(0.6, 0.7, 2.3)
	for key: int in [Orchard.pip_seed(1), Orchard.pip_seed(5)]:
		for index in range(Orchard.FALL_PETALS):
			for at: float in [0.0, 0.37, 4.99, 5.01, 11.3, 17.9, 29.95]:
				var now: Dictionary = Orchard.fall_petal(index, at, key, camera)
				var later: Dictionary = Orchard.fall_petal(index, at + Orchard.FALL_LOOP, key, camera)
				if not (now.frame as Transform3D).is_equal_approx(later.frame) or absf(float(now.alpha) - float(later.alpha)) > 0.001: seam += 1
	_check(seam == 0, "The fall loops perfectly: a loop later every petal is where it was (%d differ)" % seam)
	_check(Orchard._mix(1) == 1753845952 and Orchard._mix(123456789) == 2834422664 and Orchard._mix(0xFFFFFFFF) == 1734902346, "Its hash is lowbias32 on 32 bit words, as the shader's uint computes it")
	var first := Orchard.fall_draws(3, 0, Orchard.pip_seed(1))
	var inside := true
	for value: float in first: inside = inside and value >= 0.0 and value < 1.0
	_check(inside and first != Orchard.fall_draws(3, 1, Orchard.pip_seed(1)) and first != Orchard.fall_draws(4, 0, Orchard.pip_seed(1)) and first != Orchard.fall_draws(3, 0, Orchard.pip_seed(2)), "Each fall draws its own look, another petal or another pip's another")

## Each falling petal's own points, by its index (UV.x), as the mesh holds them.
func _fall_shapes() -> Array:
	var spirit := _spirit()
	spirit.wear(Outfit.of("orchard_skin", true))
	var fall: MeshInstance3D = spirit.find_child(Orchard.FALL_NAME, true, false)
	var arrays := fall.mesh.surface_get_arrays(0)
	var shapes := []
	for index in range(Orchard.FALL_PETALS): shapes.append(PackedVector3Array())
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for at in range(vertices.size()): shapes[roundi(uvs[at].x)].append(vertices[at])
	spirit.free()
	return shapes

## Solid parts only (no glow sprite, beam or sparkles), in head space: the
## outfit's, and with `leaf` the pip's own leaf (an item may lift or swap it).
func _solid_points(spirit: Node3D, leaf: bool = false) -> PackedVector3Array:
	var meshes := _meshes(spirit._wearing.nodes())
	if leaf and spirit.sprout.visible: meshes.append(spirit.sprout)
	return _points_in_head(spirit, meshes.filter(func(mesh: MeshInstance3D) -> bool: return not mesh.name in NOT_SOLID))

## Every vertex of `meshes`, in the spirit's head space.
func _points_in_head(spirit: Node3D, meshes: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	var to_head: Transform3D = spirit.head.global_transform.affine_inverse()
	for mesh: MeshInstance3D in meshes:
		var place := to_head * mesh.global_transform
		for surface in range(mesh.mesh.get_surface_count()):
			for vertex: Vector3 in (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array): points.append(place * vertex)
	return points

func _inside_head(point: Vector3) -> float:
	return pow(absf(point.x / Look.HEAD_HALF.x), Look.HEAD_POWER) + pow(absf(point.y / Look.HEAD_HALF.y), Look.HEAD_POWER) + pow(absf(point.z / Look.HEAD_HALF.z), Look.HEAD_POWER)

## Each item alone (a body item's petals keep off the eyes too), and each
## lifting hat with each leaf item.
func _placed_outfits() -> Array[Dictionary]:
	var outfits: Array[Dictionary] = []
	for id: String in Catalog.ids():
		outfits.append(Outfit.of(id, true))
		if Catalog.slot(id) == "leaf":
			for hat: String in ["straw_hat", "apple_hood", "blueberry_hood"]: outfits.append(Outfit.from({"hat": hat, "leaf": id}, true))
	return outfits

func _placement() -> void:
	for outfit: Dictionary in _placed_outfits():
		var label := Outfit.digest(outfit)
		var spirit := _spirit()
		spirit.carrying_seed = true
		spirit.wear(outfit)
		spirit.advance_motion(Vector3.ZERO, 0.001, true)
		var points := _solid_points(spirit)
		var near_eye := 0
		for point: Vector3 in points:
			for side: float in [-1.0, 1.0]:
				if point.z > 0.0 and Vector2(point.x - side * Look.EYE_X, point.y - Look.EYE_Y).length() < EYE_CLEAR: near_eye += 1
		_check(not points.is_empty() or not outfit.has("hat"), "%s has solid parts to check" % label)
		_check(near_eye == 0, "%s never covers the eyes: %d points" % [label, near_eye])
		# The usual seed and the Lighthouse's wider lens (lighthouse_world.gd).
		var to_global: Transform3D = spirit.head.global_transform
		var with_leaf := _solid_points(spirit, true)
		for radius: float in [0.13, 0.25]:
			spirit.carried_radius = radius
			var seed: Vector3 = spirit.carry_anchor_position()
			var in_seed := 0
			for point: Vector3 in with_leaf:
				if (to_global * point - spirit.global_position).distance_to(seed) < radius: in_seed += 1
			_check(in_seed == 0, "%s and the leaf stay under a carried seed of radius %.2f: %d points" % [label, radius, in_seed])
		if outfit.get("hat") in SEATED:
			var inside := 0
			for point: Vector3 in points: if _inside_head(point) < 1.0: inside += 1
			_check(inside == 0, "%s sits on the head's curve, never in it: %d points inside" % [label, inside])
		if outfit.has("hat") and not outfit.has("leaf"):
			for halo: Node in spirit.find_children("Halo", "MeshInstance3D", true, false):
				var centre: Vector3 = spirit.head.global_transform.affine_inverse() * (halo as Node3D).global_position
				_check(_inside_head(centre) > 1.0, "%s's glow sits outside the head, on the lamp" % label)
				_check(((halo as MeshInstance3D).mesh as QuadMesh).size.x <= 0.25, "%s's glow is small enough not to wash over the head" % label)
		spirit.free()

## Every item's solid parts and sparkles stay inside every pip view, pulled
## back or not (kit/pip_stage.gd). A glow sprite and a beam may run out.
func _in_frame() -> void:
	for id: String in Catalog.ids():
		var outfit := Outfit.of(id, true)
		for size: Vector2 in VIEWS:
			var view := SubViewport.new()
			view.size = Vector2i(size * 2.0)
			view.own_world_3d = true
			root.add_child(view)
			var pip := Stage.pip(Look.PEACH, outfit)
			pip.facing_target = Preview.REST_YAW
			pip.facing.rotation.y = Preview.REST_YAW
			var camera := Stage.build(view, pip, outfit)
			pip.advance_motion(Vector3.ZERO, 0.001, true)
			var outside := 0
			var points: Array[Vector3] = []
			if pip._wearing != null:
				var from_head: Transform3D = pip.head.global_transform
				for point: Vector3 in _solid_points(pip, true): points.append(from_head * point)
				for stars: Node in pip.find_children("Stars", "MeshInstance3D", true, false): points.append((stars as Node3D).global_position)
			for point: Vector3 in points:
				if not camera.is_position_in_frustum(point): outside += 1
			_check(outside == 0, "%s stays inside the %dx%d view: %d points outside" % [id, size.x, size.y, outside])
			view.free()

## A body item may change the body's shape: the same pose, carry point and
## steps as a plain pip, and the head never replaced.
func _body_shape() -> void:
	var plain := _spirit()
	var dressed := _spirit()
	dressed.wear(Outfit.from({"hat": "lighthouse_lamp", "body": "tide", "leaf": "gold_leaf"}, true))
	var head_mesh: Mesh = dressed.head.mesh
	var face_shader: Shader = dressed.face_art.material.shader
	var torso_mesh: Mesh = dressed.torso.mesh
	var foot_mesh: Mesh = (dressed.feet[0].get_child(0) as MeshInstance3D).mesh
	var placeholder: RefCounted = PipOutfit.new(dressed, {})
	placeholder.apply_art(PLACEHOLDER_BODY)
	_check(dressed.torso.mesh != torso_mesh and (dressed.feet[0].get_child(0) as MeshInstance3D).mesh != foot_mesh, "A body item swaps the torso and feet meshes")
	_check(dressed.head.mesh == head_mesh and dressed.face_art.material.shader == face_shader, "and never the head or its face")
	var steps := [0, 0]
	plain.stepped.connect(func() -> void: steps[0] += 1)
	dressed.stepped.connect(func() -> void: steps[1] += 1)
	var same := true
	var partner := Vector3(1.6, 0, 0.4)
	for frame in range(240):
		var move := Vector3(0.03, 0, 0.01) if frame < 80 else Vector3.ZERO
		if frame == 90:
			for each: Node3D in [plain, dressed]: each.play_throw()
		if frame == 130:
			for each: Node3D in [plain, dressed]: each.set_pose(Idle.DOZE, {"toward": partner})
		if frame == 190:
			for each: Node3D in [plain, dressed]: each.play_wake(false)
		for each: Node3D in [plain, dressed]:
			each.carrying_seed = frame > 40
			each.set_partner_offset(partner, true)
			each.advance_motion(move, DT, false)
		same = same and _pose(plain) == _pose(dressed)
	_check(same, "Walking, throwing, dozing and waking, every pose, carry point and photo height is the plain pip's")
	_check(steps[0] == steps[1] and steps[0] > 0, "and every footstep too: %d and %d" % steps)
	placeholder.undress()
	_check(dressed.torso.mesh == torso_mesh and (dressed.feet[0].get_child(0) as MeshInstance3D).mesh == foot_mesh, "Off again, the torso and feet are as they were")
	dressed.wear({})
	_check(dressed.torso.material_override == Spirit._body_material(Look.PEACH) and dressed.face_art.material.shader == SpiritFace.SHADER, "and the Tide colours go too")
	var core_files := _scripts("res://core")
	var mentions: Array[String] = []
	for path: String in core_files:
		var text := FileAccess.get_file_as_string(path)
		if text.contains("cosmetic") or text.contains("outfit") or text.contains("pip_wear"): mentions.append(path)
	_check(not core_files.is_empty() and mentions.is_empty(), "No simulation, recording or hash code reads cosmetics: %s" % [mentions])
	plain.free()
	dressed.free()

func _pose(spirit: Node3D) -> Array:
	var parts: Array = [spirit.facing.transform, spirit.upper_body.transform, spirit.head.transform, spirit.face.transform, spirit.torso.transform, spirit.sprout.transform, spirit.carry_anchor_position(), spirit.photo_anchor_height(), spirit.expression_target()]
	for foot: Node3D in spirit.feet: parts.append(foot.transform)
	for eye: Node3D in spirit.eyes: parts.append(eye.transform)
	return parts

func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"): found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir): found.append_array(_scripts(dir.path_join(sub)))
	return found

func _animation() -> void:
	_check(PipOutfit.ANIMATION_HZ == IslandWorld.IDLE_CARD_HZ, "Moving parts step at the idle card rate")
	var lamp := _spirit()
	lamp.wear(Outfit.of("lighthouse_lamp", true))
	var glass: StandardMaterial3D = null
	for mesh: MeshInstance3D in _meshes(lamp._wearing.nodes()):
		if mesh.material_override is StandardMaterial3D and (mesh.material_override as StandardMaterial3D).emission_enabled: glass = mesh.material_override
	_check(glass != null, "The lamp's glass glows")
	if glass == null: return
	var changes := 0
	var last := glass.emission_energy_multiplier
	for frame in range(60):
		lamp.advance_motion(Vector3.ZERO, DT, false)
		if glass.emission_energy_multiplier != last: changes += 1
		last = glass.emission_energy_multiplier
	_check(changes >= 10 and changes <= 12, "The lamp brightens and dims at the idle rate: %d steps in 1 s" % changes)
	var other := _spirit()
	other.wear(Outfit.of("lighthouse_lamp", true))
	var other_glass: StandardMaterial3D = null
	for mesh: MeshInstance3D in _meshes(other._wearing.nodes()):
		if mesh.material_override is StandardMaterial3D and (mesh.material_override as StandardMaterial3D).emission_enabled: other_glass = mesh.material_override
	for frame in range(30): other.advance_motion(Vector3.ZERO, 2.0 * DT, false)
	_check(other_glass != glass and is_equal_approx(other_glass.emission_energy_multiplier, glass.emission_energy_multiplier), "The same moment of the pip's clock shows the same light at any frame rate, and each pip has its own")
	var held := glass.emission_energy_multiplier
	changes = 0
	for frame in range(60):
		lamp.advance_motion(Vector3.ZERO, DT, true)
		if frame > 0 and glass.emission_energy_multiplier != held: changes += 1
		held = glass.emission_energy_multiplier
	_check(changes == 0, "Under Reduce motion it holds still")
	var tide := _spirit(Look.MINT)
	tide.wear(Outfit.of("tide", true))
	_check(tide.face_art.material.shader == load("res://presentation/spirit_face_tide.gdshader"), "Tide draws the head with its face variant")
	var phase: Variant = tide.face_art.material.get_shader_parameter("skin_phase")
	for frame in range(6): tide.advance_motion(Vector3.ZERO, DT, false)
	_check(tide.face_art.material.get_shader_parameter("skin_phase") != phase, "and its waves move")
	_check(tide.face_art.material.get_shader_parameter("body_color") == Look.MINT and tide.face_art.material.get_shader_parameter("eye_xy") == tide.face_art._eye_xy, "with the pip's own colour and its eyes where they were")
	var orchard := _spirit()
	orchard.wear(Outfit.of("orchard_skin", true))
	var fall: MeshInstance3D = orchard.find_child(Orchard.FALL_NAME, true, false)
	_check(fall != null and orchard.upper_body.is_ancestor_of(fall), "The Orchard skin's petals fall round the body")
	if fall != null:
		_check(fall.mesh.get_surface_count() == 1 and fall.material_override is ShaderMaterial and fall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "as one draw call with its shader, casting no shadow")
		_check(fall.custom_aabb.size.y >= Orchard.FALL_TOP.y and fall.custom_aabb.has_point(Vector3(0, Orchard.FALL_BOTTOM, 0)), "and bounds covering the whole fall, so they are never culled mid-fall")
		var material: ShaderMaterial = fall.material_override
		_check(is_equal_approx(float(material.get_shader_parameter(&"loop")), Orchard.FALL_LOOP) and material.get_shader_parameter(&"slots") == Vector2(Orchard.FALL_SLOTS) and material.get_shader_parameter(&"top") == Orchard.FALL_TOP and material.shader.code.contains("2146121005u"), "and the shader takes its path and hash from the skin's own numbers")
		_check(not fall.visible, "A still pip shows the resting petals alone")
		for frame in range(12): orchard.advance_motion(Vector3.ZERO, DT, false)
		_check(fall.visible, "and a moving one shows them falling")
		var moved := 0
		var posed := fall.transform
		for frame in range(60):
			orchard.advance_motion(Vector3.ZERO, DT, false)
			if fall.transform != posed: moved += 1
		_check(moved == 0, "moved by the shader alone: the node never moves")
		_check(not material.shader.code.contains("TIME"), "on the pip's own clock, never TIME, so a calm screen still draws only on change")
		var ticks := 0
		var clock: Variant = fall.get_instance_shader_parameter(&"fall_clock")
		for frame in range(60):
			orchard.advance_motion(Vector3.ZERO, DT, false)
			if fall.get_instance_shader_parameter(&"fall_clock") != clock: ticks += 1
			clock = fall.get_instance_shader_parameter(&"fall_clock")
		_check(ticks >= 10 and ticks <= 12, "which steps at the idle rate: %d steps in 1 s" % ticks)
		for frame in range(30): orchard.advance_motion(Vector3.ZERO, DT, true)
		_check(not fall.visible and orchard.torso.find_children("*", "MeshInstance3D", true, false).size() > 0, "Under Reduce motion only the resting petals show")
		for frame in range(30): orchard.advance_motion(Vector3.ZERO, DT, false)
		_check(fall.visible, "and they fall again when it is off")
		var second := _spirit()
		second.wear(Outfit.of("orchard_skin", true))
		var second_fall: MeshInstance3D = second.find_child(Orchard.FALL_NAME, true, false)
		_check(second_fall.material_override == fall.material_override and second_fall.mesh == fall.mesh, "Two pips share the falling petals' mesh and material")
		_check(Orchard.VEIL_META == RaceGhost.VEIL_UNIFORM and fall.get_meta(Orchard.VEIL_META) == &"veil" and material.shader.code.contains("instance uniform float veil"), "and the race ghost fades them through their own shader")
		RaceGhost._veil(second, Look.PEACH)
		_check(second_fall.material_override == fall.material_override and is_equal_approx(float(second_fall.get_instance_shader_parameter(&"veil")), RaceGhost.VEIL), "so a ghost wearing the skin keeps its petals falling, see-through")
		_check(not is_equal_approx(float(second_fall.get_instance_shader_parameter(&"fall_seed")), float(fall.get_instance_shader_parameter(&"fall_seed"))), "and each falls with its own seed")
		second.free()
	lamp.free()
	other.free()
	tide.free()
	orchard.free()

func _seed_lift() -> void:
	var plain := _spirit()
	var capped := _spirit()
	var leafy := _spirit()
	var straw_leafy := _spirit()
	capped.wear(Outfit.of("apple_hood", true))
	leafy.wear(Outfit.of("apple_leaf", true))
	straw_leafy.wear(Outfit.from({"hat": "straw_hat", "leaf": "apple_leaf"}, true))
	var spirits: Array[Node3D] = [plain, capped, leafy, straw_leafy]
	for each: Node3D in spirits:
		each.carrying_seed = true
		each.advance_motion(Vector3.ZERO, 0.001, true)
	var base: float = plain.carry_anchor_position().y
	_check(is_equal_approx(capped.carry_anchor_position().y - base, float(HOOD.LOOKS.apple_hood.seed_lift)), "The Apple hood lifts a carried seed clear of its stem: %.3f" % (capped.carry_anchor_position().y - base))
	_check(is_equal_approx(leafy.carry_anchor_position().y, base), "The Apple leaf alone leaves the seed where it was")
	_check(is_equal_approx(straw_leafy.carry_anchor_position().y - base, 0.075), "and lifts it with the leaf through the Straw hat's brim: %.3f" % (straw_leafy.carry_anchor_position().y - base))
	capped.wear({})
	capped.advance_motion(Vector3.ZERO, 0.001, true)
	_check(is_equal_approx(capped.carry_anchor_position().y, base), "Off again, the seed sits where it did")
	var leaf_triangles := _triangles(leafy.sprout.mesh)
	_check(leaf_triangles <= MAX_TRIANGLES, "The Apple leaf stays within about 600 triangles: %d" % leaf_triangles)
	for each: Node3D in spirits: each.free()

func _released() -> void:
	var spirit := _spirit()
	for id: String in Catalog.ids():
		if not Catalog.art(id).is_empty(): spirit.wear(Outfit.of(id, true))
	spirit.free()
	_check(Kit.cached_count() > 0, "Item meshes are kept and shared")
	var release := Callable(load(Kit.SCRIPT_PATH), "release_cached")
	_check(SessionRelease._releases.has(release), "and released at shutdown")
	var a := _spirit()
	var b := _spirit()
	a.wear(Outfit.of("daisy", true))
	b.wear(Outfit.of("daisy", true))
	_check(_meshes(a._wearing.nodes())[0].mesh == _meshes(b._wearing.nodes())[0].mesh, "Two pips wearing an item share its mesh")
	a.free()
	b.free()
