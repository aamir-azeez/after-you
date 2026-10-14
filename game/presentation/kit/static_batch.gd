extends RefCounted
## Folds a built world's static geometry into one mesh per material, so the
## renderer draws a few batches instead of one draw call per box, sphere and
## cylinder (Home drew about 380 a frame). Draws the same pixels.
##
## Only plain leaves are folded: a MeshInstance3D with no script, no children,
## no metadata, visible, one-surface primitive mesh, an opaque untextured
## StandardMaterial3D override and no other material, and a rotation with a
## uniform scale relative to the root (SurfaceTool turns normals by the basis
## itself, which is exact only then). Anything the owners hold on to (any
## node in their script variables, or under one) and anything under a node
## with a script stays as it is: those are what move, fade, recolour, hide or
## are looked up later. Folding happens once per root; a rebuilt root (a new
## terrain) is folded again by its owner.
const FOLDED_META := "static_batch_folded"
const PRIMITIVES := ["BoxMesh", "SphereMesh", "CylinderMesh", "TorusMesh", "QuadMesh", "PlaneMesh", "PrismMesh", "CapsuleMesh"]
## Off only for comparing a folded and an unfolded frame in one process.
static var enabled := true
const SKIPPED_MATERIAL_PROPERTIES := ["resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id", "script"]

## Folds root's static leaves. owners: the objects whose variables name the
## nodes that change later. Returns {"folded": leaves, "batches": meshes}.
static func fold(root: Node3D, owners: Array) -> Dictionary:
	if not enabled or not is_instance_valid(root) or not root.is_inside_tree() or root.has_meta(FOLDED_META): return {"folded": 0, "batches": 0}
	root.set_meta(FOLDED_META, true)
	var held: Dictionary = {}
	for owner: Variant in owners:
		if owner is Object and is_instance_valid(owner): _collect_held(owner, held)
	var groups: Dictionary = {}
	var order: Array = []
	var to_root := root.global_transform.affine_inverse()
	_gather(root, root, held, to_root, groups, order)
	var folded := 0
	var batches := 0
	for key: String in order:
		var group: Dictionary = groups[key]
		if group.nodes.size() < 2: continue
		var tool := SurfaceTool.new()
		for entry: Array in group.nodes:
			var leaf: MeshInstance3D = entry[0]
			tool.append_from(leaf.mesh, 0, entry[1])
		var batch := MeshInstance3D.new()
		batch.name = "StaticBatch%d" % batches
		batch.mesh = tool.commit()
		var first: MeshInstance3D = group.nodes[0][0]
		batch.material_override = first.material_override
		batch.cast_shadow = first.cast_shadow
		batch.layers = first.layers
		batch.gi_mode = first.gi_mode
		root.add_child(batch)
		for entry: Array in group.nodes:
			var leaf: MeshInstance3D = entry[0]
			leaf.get_parent().remove_child(leaf)
			leaf.queue_free()
		folded += group.nodes.size()
		batches += 1
	return {"folded": folded, "batches": batches}

static func _gather(node: Node, root: Node3D, held: Dictionary, to_root: Transform3D, groups: Dictionary, order: Array) -> void:
	for child: Node in node.get_children():
		if held.has(child.get_instance_id()) or child.get_script() != null: continue
		if child is Node3D and not (child as Node3D).visible: continue
		if child.get_child_count() > 0:
			_gather(child, root, held, to_root, groups, order)
			continue
		if not child is MeshInstance3D: continue
		var leaf := child as MeshInstance3D
		var xform: Transform3D = to_root * leaf.global_transform
		var key := _key(leaf, xform)
		if key.is_empty(): continue
		if not groups.has(key):
			groups[key] = {"nodes": []}
			order.append(key)
		groups[key].nodes.append([leaf, xform])

## The batch a leaf can join, or "" when it must stay its own node.
static func _key(leaf: MeshInstance3D, xform: Transform3D) -> String:
	if leaf.mesh == null or leaf.mesh.get_class() not in PRIMITIVES or leaf.mesh.get_surface_count() != 1: return ""
	if not leaf.get_meta_list().is_empty() or leaf.material_overlay != null or leaf.get_surface_override_material(0) != null: return ""
	if leaf.transparency != 0.0 or leaf.sorting_offset != 0.0 or leaf.visibility_range_end != 0.0 or leaf.visibility_range_begin != 0.0: return ""
	var material := leaf.material_override as StandardMaterial3D
	if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_color.a < 1.0 or material.albedo_texture != null: return ""
	if material.next_pass != null: return ""
	if not _uniform(xform.basis): return ""
	var values: Array = [leaf.cast_shadow, leaf.layers, leaf.gi_mode]
	for property: Dictionary in material.get_property_list():
		if not int(property.usage) & PROPERTY_USAGE_STORAGE or property.name in SKIPPED_MATERIAL_PROPERTIES: continue
		values.append([property.name, material.get(property.name)])
	return var_to_bytes(values).hex_encode().sha256_text()

## A rotation times one scale for all axes.
static func _uniform(basis: Basis) -> bool:
	var x := basis.x.length()
	var y := basis.y.length()
	var z := basis.z.length()
	if x < 0.000001 or absf(x - y) > x * 0.0001 or absf(x - z) > x * 0.0001: return false
	var unit := basis.orthonormalized()
	return absf(unit.x.dot(unit.y)) < 0.0001 and absf(unit.y.dot(unit.z)) < 0.0001 and absf(unit.x.dot(unit.z)) < 0.0001 and basis.determinant() > 0.0

## Every node an owner's script variables refer to, through arrays and
## dictionaries (keys too), a few levels deep.
static func _collect_held(owner: Object, held: Dictionary) -> void:
	for property: Dictionary in owner.get_property_list():
		if not int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		_hold(owner.get(property.name), held, 0)

static func _hold(value: Variant, held: Dictionary, depth: int) -> void:
	if depth > 4: return
	if value is Node:
		if is_instance_valid(value): held[(value as Node).get_instance_id()] = true
	elif value is Array:
		for item: Variant in value: _hold(item, held, depth + 1)
	elif value is Dictionary:
		for item: Variant in value:
			_hold(item, held, depth + 1)
			_hold(value[item], held, depth + 1)
