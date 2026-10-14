extends SceneTree
## kit/static_batch.gd folds a world's plain static leaves into one mesh per
## material and leaves everything that can change as its own node.
## - Plain leaves of one material become one batch whose vertices are the
##   leaves' vertices in the root's space, in order.
## - Held nodes (owner variables) and what is under them, scripted nodes,
##   hidden, see-through, textured, meta-tagged and non-uniformly scaled
##   leaves stay; a root is folded once. A scripted node under the root holds
##   what its own variables name; a freed node in a variable is skipped.
## - With "containers", a held plain container's leaves batch under it, in
##   its space, so moving or hiding the container moves or hides them; a
##   "keep" container stays whole. A batch reports its leaves' boxes.
## - start() and step() over many small budgets fold exactly what fold()
##   does; a group whose leaf went meanwhile stays as it was.
## - On Home the bridge planks with their posts, the plate, the keepsakes and
##   the actors stay; the island's static leaves are folded.
## - Chapter worlds fold their terrain on their first frame (over several
##   frames on a chapter screen) and keep what they change later; Turn of the
##   Tide does not fold yet. A faded raised floor fades its batches, and a
##   journey's bubbles weigh the same scenery once it is folded.
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Registry = preload("res://services/chapter_registry.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")

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
	await _containers()
	await _scripted_and_freed()
	await _steps()
	await _home()
	await _chapters()
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

## The triangles a mesh draws, as vertices in the given space.
func _drawn(mesh: Mesh, xform: Transform3D) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var drawn := PackedVector3Array()
	if indices.is_empty():
		for vertex in vertices: drawn.append(xform * vertex)
	else:
		for index in indices: drawn.append(xform * vertices[index])
	return drawn

func _same(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size(): return false
	for i in range(a.size()):
		if not a[i].is_equal_approx(b[i]): return false
	return true

func _batches(node: Node) -> Array:
	return node.find_children("StaticBatch*", "MeshInstance3D", false, false)

func _containers() -> void:
	var root := Node3D.new()
	root.position = Vector3(-1, 0.5, 2)
	get_root().add_child(root)
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.2, 0.5)
	var held := Node3D.new()
	held.position = Vector3(2, 1, 0)
	held.rotation = Vector3(0, 0.4, 0)
	root.add_child(held)
	var inside: Array[MeshInstance3D] = []
	for i in range(3): inside.append(_leaf(held, box, Color("c4b090"), Vector3(i, 0, 0)))
	var lone := _leaf(held, box, Color("8b7964"), Vector3(0, 0, 1))
	var nested := Node3D.new()
	nested.position = Vector3(0, 0.5, 0)
	held.add_child(nested)
	for i in range(2): _leaf(nested, box, Color("c4b090"), Vector3(0, 0, -i))
	var kept := Node3D.new()
	root.add_child(kept)
	var kept_leaves: Array[MeshInstance3D] = []
	for i in range(2): kept_leaves.append(_leaf(kept, box, Color("c4b090"), Vector3(5, 0, i)))
	var owner := Owner.new()
	owner.held = [held, nested, kept]
	# The vertices the held container's leaves draw, in its own space.
	var expected := PackedVector3Array()
	for leaf: MeshInstance3D in inside: expected.append_array(_drawn(leaf.mesh, held.global_transform.affine_inverse() * leaf.global_transform))
	var boxes: Array = []
	for leaf: MeshInstance3D in inside: boxes.append(leaf.global_transform * leaf.get_aabb())
	await process_frame
	var plain: Dictionary = StaticBatch.fold(root, [owner])
	_check(plain.folded == 0 and _batches(held).is_empty(), "Without the containers option a held container stays whole (%s)" % str(plain))
	root.remove_meta(StaticBatch.FOLDED_META)
	var result: Dictionary = StaticBatch.fold(root, [owner], {"containers": true, "keep": [kept]})
	_check(result.folded == 5 and result.batches == 2, "A held container's leaves and its nested container's leaves batch (%s)" % str(result))
	var under: Array = _batches(held)
	_check(under.size() == 1 and _batches(nested).size() == 1 and _batches(root).is_empty(), "Each held container gets its own batch, none at the root")
	if under.size() == 1:
		var batch: MeshInstance3D = under[0]
		_check(batch.transform == Transform3D.IDENTITY and _same(_drawn(batch.mesh, Transform3D.IDENTITY), expected), "The batch draws the leaves' triangles in the container's space")
		var parts: Array[AABB] = StaticBatch.part_boxes(batch)
		var matched := parts.size() == boxes.size()
		for i in range(mini(parts.size(), boxes.size())): matched = matched and parts[i].position.is_equal_approx(boxes[i].position) and parts[i].size.is_equal_approx(boxes[i].size)
		_check(matched, "The batch reports each folded leaf's own box (%d)" % parts.size())
		var before: Vector3 = batch.global_position
		held.position += Vector3(0, 0, 3)
		_check(batch.global_position.is_equal_approx(before + Vector3(0, 0, 3)), "Moving the container moves its batch")
		held.visible = false
		_check(not batch.is_visible_in_tree(), "Hiding the container hides its batch")
	_check(is_instance_valid(lone) and lone.is_inside_tree(), "A leaf with no partner stays")
	for leaf: MeshInstance3D in kept_leaves: _check(is_instance_valid(leaf) and leaf.is_inside_tree() and leaf.get_parent() == kept, "A kept container's leaves stay")
	var plain_mesh := MeshInstance3D.new()
	plain_mesh.mesh = box
	plain_mesh.material_override = StandardMaterial3D.new()
	root.add_child(plain_mesh)
	var own: Array[AABB] = StaticBatch.part_boxes(plain_mesh)
	_check(own.size() == 1 and own[0] == plain_mesh.global_transform * plain_mesh.get_aabb(), "A plain mesh reports its own box")
	root.queue_free()
	await process_frame

func _scripted_and_freed() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var box := BoxMesh.new()
	var named: Array[MeshInstance3D] = []
	for i in range(3): named.append(_leaf(root, box, Color("c4b090"), Vector3(i, 0, 0)))
	var keeper := Node3D.new()
	var behaviour := GDScript.new()
	behaviour.source_code = "extends Node3D\nvar watched: Node3D\n"
	behaviour.reload()
	keeper.set_script(behaviour)
	root.add_child(keeper)
	keeper.set("watched", named[0])
	var gone := Node3D.new()
	root.add_child(gone)
	var owner := Owner.new()
	owner.held = [gone]
	gone.free()
	await process_frame
	var result: Dictionary = StaticBatch.fold(root, [owner])
	_check(result.folded == 2 and result.batches == 1, "A freed node in a variable is skipped and the fold goes on (%s)" % str(result))
	_check(is_instance_valid(named[0]) and named[0].is_inside_tree(), "A leaf a scripted node under the root names stays")
	root.queue_free()
	await process_frame

func _tree() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, 1, 0)
	get_root().add_child(root)
	var box := BoxMesh.new()
	var sphere := SphereMesh.new()
	for i in range(30):
		var parent: Node3D = root
		if i % 3 == 0:
			parent = Node3D.new()
			parent.position = Vector3(0, i * 0.1, 0)
			root.add_child(parent)
		_leaf(parent, sphere if i % 2 == 0 else box, Color("c4b090") if i % 4 < 2 else Color("8b7964"), Vector3(i * 0.3, 0, 0))
	return root

func _steps() -> void:
	var whole := _tree()
	var stepped := _tree()
	await process_frame
	var expected: Dictionary = StaticBatch.fold(whole, [])
	var job := StaticBatch.start(stepped, [])
	var calls := 0
	while not StaticBatch.step(job, 1) and calls < 10000: calls += 1
	_check(calls > 1, "A tiny budget spreads the fold over many steps (%d)" % calls)
	_check(job.folded == expected.folded and job.batches == expected.batches, "Stepped, the fold folds what fold() does (%d leaves, %d batches)" % [job.folded, job.batches])
	var a: Array = _batches(whole)
	var b: Array = _batches(stepped)
	var same := a.size() == b.size() and not a.is_empty()
	for i in range(mini(a.size(), b.size())): same = same and _same(_drawn(a[i].mesh, Transform3D.IDENTITY), _drawn(b[i].mesh, Transform3D.IDENTITY))
	_check(same, "Stepped, every batch draws the same triangles")
	whole.queue_free()
	stepped.queue_free()
	# A leaf that goes while the job waits keeps its group as it was.
	var root := Node3D.new()
	get_root().add_child(root)
	var box := BoxMesh.new()
	var first: Array[MeshInstance3D] = []
	for i in range(3): first.append(_leaf(root, box, Color("c4b090"), Vector3(i, 0, 0)))
	for i in range(2): _leaf(root, box, Color("8b7964"), Vector3(i, 0, 2))
	await process_frame
	var waiting := StaticBatch.start(root, [])
	while not waiting.walk.is_empty() or not waiting.owners.is_empty() or not waiting.scan.is_empty(): StaticBatch.step(waiting, 1)
	root.remove_child(first[2])
	first[2].queue_free()
	StaticBatch.step(waiting, 0)
	_check(waiting.done and waiting.folded == 2 and waiting.batches == 1, "Only the group whose leaves all remain is folded (%d leaves)" % waiting.folded)
	_check(first[0].is_inside_tree() and first[1].is_inside_tree(), "The broken group's other leaves stay")
	root.queue_free()
	await process_frame
	# A root that goes ends its job.
	var lost := _tree()
	await process_frame
	var orphan := StaticBatch.start(lost, [])
	lost.queue_free()
	await process_frame
	_check(StaticBatch.step(orphan, 0), "A job whose root has gone ends")

func _world(key: String) -> Node3D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	get_root().add_child(viewport)
	var world: Node3D = Registry.world_script(key).new()
	viewport.add_child(world)
	GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
	world.load_level(Registry.definition(key))
	return world

func _chapters() -> void:
	for key: String in [Registry.WISHING_WELL, Registry.FIRST_STEPS, Registry.LIGHTHOUSE_V2]:
		var world := _world(key)
		var terrain: Node3D = world.terrain
		var held: Dictionary = {}
		StaticBatch._collect_held(world, held)
		var meshes := terrain.find_children("*", "MeshInstance3D", true, false).size()
		await process_frame
		_check(terrain.has_meta(StaticBatch.FOLDED_META) and not world.scenery_folding(), key + ": the world folds its terrain on its first frame")
		var batches := terrain.find_children("StaticBatch*", "MeshInstance3D", true, false).size()
		var after := terrain.find_children("*", "MeshInstance3D", true, false).size()
		_check(batches > 10 and after < meshes, "%s: %d meshes become %d (%d batches)" % [key, meshes, after, batches])
		var kept := true
		for id: int in held:
			var node := instance_from_id(id) as Node
			if node != null and not node.is_queued_for_deletion() and not node.is_inside_tree(): kept = false
		_check(kept, key + ": every node the world names stays in the tree")
		world.get_parent().queue_free()
		await process_frame
	# A chapter screen folds over several frames, to the same batches.
	var direct := _world(Registry.WISHING_WELL)
	await process_frame
	var expected: int = direct.terrain.find_children("StaticBatch*", "MeshInstance3D", true, false).size()
	direct.get_parent().queue_free()
	var spread := _world(Registry.WISHING_WELL)
	spread.fold_over_frames = true
	var frames := 0
	while (spread.scenery_folding() or frames == 0) and frames < 600:
		await process_frame
		frames += 1
	_check(frames > 1 and spread.terrain.find_children("StaticBatch*", "MeshInstance3D", true, false).size() == expected, "A chapter screen's world folds over %d frames to the same %d batches" % [frames, expected])
	spread.get_parent().queue_free()
	# Turn of the Tide is not folded yet.
	var tide := _world(Registry.TURN_OF_THE_TIDE)
	for i in range(3): await process_frame
	_check(not tide.terrain.has_meta(StaticBatch.FOLDED_META) and tide.terrain.find_children("StaticBatch*", "", true, false).is_empty(), "Turn of the Tide keeps its terrain unfolded")
	tide.get_parent().queue_free()
	# A raised floor fades and returns with its batches (kit/cutaway.gd).
	var house := _world(Registry.HOUSE)
	await process_frame
	var raised: Node3D = house._upper_islands[0] if not house._upper_islands.is_empty() else null
	var faded: Array = _batches(raised) if raised != null else []
	_check(not faded.is_empty(), "A raised floor's leaves batch under it")
	if raised != null:
		house._set_cutaway(raised, true)
		var see_through := true
		for batch: MeshInstance3D in faded: see_through = see_through and (batch.material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		_check(see_through, "Fading the raised floor fades its batches")
		house._set_cutaway(raised, false)
		var opaque := true
		for batch: MeshInstance3D in faded: opaque = opaque and (batch.material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		_check(opaque, "and brings them back")
	house.get_parent().queue_free()
	# A journey's bubbles weigh the same scenery boxes folded and unfolded.
	StaticBatch.enabled = false
	var journey := _world(Registry.LONG_WAY_HOME_V2)
	await process_frame
	journey._gather_scenery()
	var unfolded: Dictionary = journey._sceneries.duplicate()
	journey._sceneries.clear()
	StaticBatch.enabled = true
	journey._fold_static_scenery()
	_check(journey.terrain.has_meta(StaticBatch.FOLDED_META), "The journey world folded")
	journey._gather_scenery()
	var described := func(box: AABB) -> String: return "%.3f %.3f %.3f %.3f %.3f %.3f" % [box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z]
	var matched: bool = unfolded.size() == journey._sceneries.size() and unfolded.size() > 1
	for bubble: Variant in unfolded:
		var old: Array = unfolded[bubble]
		var now: Array = journey._sceneries.get(bubble, [])
		var left: Array = old.map(described)
		var right: Array = now.map(described)
		left.sort()
		right.sort()
		matched = matched and left == right
	_check(matched, "Bubbles weigh the same scenery boxes once the world is folded (%d bubbles)" % unfolded.size())
	journey.get_parent().queue_free()
	await process_frame
