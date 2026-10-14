extends SceneTree
## kit/static_batch.gd folds a world's plain static leaves into one mesh per
## material and leaves everything that can change as its own node.
## - Plain leaves of one material become one batch whose vertices are the
##   leaves' vertices in the root's space, in order.
## - Held nodes (owner variables) and what is under them, scripted nodes,
##   hidden, see-through, textured, meta-tagged and non-uniformly scaled
##   leaves stay; a root is folded once.
## - On Home the bridge planks with their posts, the plate, the keepsakes and
##   the actors stay; the island's static leaves are folded.
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")

var checks := 0
var failures := 0

class Owner:
	extends RefCounted
	var held: Array = []
	var by_name: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)

func _leaf(parent: Node, mesh: Mesh, color: Color, at: Vector3) -> MeshInstance3D:
	var leaf := MeshInstance3D.new()
	leaf.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	leaf.material_override = material
	leaf.position = at
	parent.add_child(leaf)
	return leaf

func _run() -> void:
	var root := Node3D.new()
	root.position = Vector3(1, 2, 3)
	get_root().add_child(root)
	var group := Node3D.new()
	group.rotation = Vector3(0, 0.7, 0)
	group.scale = Vector3(2, 2, 2)
	root.add_child(group)
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.2, 0.6)
	var sphere := SphereMesh.new()
	var plain: Array[MeshInstance3D] = []
	for i in range(3): plain.append(_leaf(group, box, Color("c4b090"), Vector3(i, 0, 0)))
	plain.append(_leaf(root, sphere, Color("c4b090"), Vector3(0, 1, 0)))
	var other := _leaf(root, box, Color("8b7964"), Vector3(0, 0, 2))
	var other2 := _leaf(root, box, Color("8b7964"), Vector3(0, 0, 3))
	var held := _leaf(root, box, Color("c4b090"), Vector3(5, 0, 0))
	var held_parent := _leaf(root, box, Color("c4b090"), Vector3(6, 0, 0))
	var under_held := _leaf(held_parent, box, Color("c4b090"), Vector3(0, 1, 0))
	var by_name := _leaf(root, box, Color("c4b090"), Vector3(7, 0, 0))
	var scripted := Node3D.new()
	var behaviour := GDScript.new()
	behaviour.source_code = "extends Node3D
"
	behaviour.reload()
	scripted.set_script(behaviour)
	root.add_child(scripted)
	var under_script := _leaf(scripted, box, Color("c4b090"), Vector3(8, 0, 0))
	var hidden := _leaf(root, box, Color("c4b090"), Vector3(9, 0, 0))
	hidden.visible = false
	var see_through := _leaf(root, box, Color(1, 1, 1, 0.5), Vector3(10, 0, 0))
	(see_through.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tagged := _leaf(root, box, Color("c4b090"), Vector3(11, 0, 0))
	tagged.set_meta("celebration_clear_point", Vector2.ZERO)
	var stretched := _leaf(root, box, Color("c4b090"), Vector3(12, 0, 0))
	stretched.scale = Vector3(1, 2, 1)
	var owner := Owner.new()
	owner.held = [held, held_parent]
	owner.by_name = {"x": by_name}
	# The vertices the plain leaves draw, in the root's space.
	var expected := PackedVector3Array()
	for leaf: MeshInstance3D in plain:
		var arrays := leaf.mesh.surface_get_arrays(0)
		var xform: Transform3D = root.global_transform.affine_inverse() * leaf.global_transform
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in indices: expected.append(xform * vertices[index])
	await process_frame
	var result: Dictionary = StaticBatch.fold(root, [owner])
	await process_frame
	_check(result.folded == 6 and result.batches == 2, "Six plain leaves of two materials fold into two batches (%s)" % str(result))
	var batches: Array = root.find_children("StaticBatch*", "MeshInstance3D", false, false)
	_check(batches.size() == 2, "Two batch meshes under the root")
	var first: MeshInstance3D = batches[0] if batches.size() > 0 else null
	if first != null:
		var arrays := first.mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var drawn := PackedVector3Array()
		if indices.is_empty(): drawn = vertices
		else:
			for index in indices: drawn.append(vertices[index])
		var same := drawn.size() == expected.size()
		for i in range(mini(drawn.size(), expected.size())):
			if not drawn[i].is_equal_approx(expected[i]): same = false
		_check(same, "The batch draws the leaves' triangles, in the root's space and order (%d vertices)" % drawn.size())
		_check((first.material_override as StandardMaterial3D).albedo_color == Color("c4b090"), "The batch keeps its leaves' material")
	for leaf: MeshInstance3D in plain: _check(not is_instance_valid(leaf) or not leaf.is_inside_tree(), "A folded leaf leaves the tree")
	_check((not is_instance_valid(other) or not other.is_inside_tree()) and (not is_instance_valid(other2) or not other2.is_inside_tree()), "Leaves of another material fold into their own batch")
	for kept: Node in [held, held_parent, under_held, by_name, under_script, hidden, see_through, tagged, stretched]:
		_check(is_instance_valid(kept) and kept.is_inside_tree(), "Stays its own node: " + str(kept.position))
	_check(StaticBatch.fold(root, [owner]).folded == 0, "A root is folded once")
	root.queue_free()
	await _home()
	print("STATIC BATCH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _home() -> void:
	change_scene_to_file("res://main.tscn")
	var guard := 0
	while (current_scene == null or current_scene.get("mode") != "home") and guard < 600:
		await process_frame
		guard += 1
	for i in range(5): await process_frame
	var app: Node = current_scene
	var world: Node3D = app.world
	var terrain: Node3D = world.terrain
	_check(terrain.has_meta(StaticBatch.FOLDED_META), "Home folds its island")
	_check(not terrain.find_children("StaticBatch*", "MeshInstance3D", false, false).is_empty(), "Home has batches")
	var planks_ok: bool = world.bridge_parts.size() == 9
	for plank: Node in world.bridge_parts: planks_ok = planks_ok and is_instance_valid(plank) and plank.is_inside_tree() and plank.get_child_count() == 2
	_check(planks_ok, "Every bridge plank stays with both its posts")
	_check(is_instance_valid(world.plate) and world.plate.is_inside_tree(), "The plate stays")
	var actors_ok: bool = true
	for role: String in world.actors: actors_ok = actors_ok and is_instance_valid(world.actors[role]) and world.actors[role].is_inside_tree()
	_check(actors_ok, "The spirits stay")
	var display: Node = app.home_stage_view._keepsake_display
	_check(is_instance_valid(display) and display.is_inside_tree() and display.find_children("StaticBatch*", "", true, false).is_empty(), "The keepsakes stay their own nodes")
	app.queue_free()
	for i in range(3): await process_frame
	await create_timer(0.15).timeout
