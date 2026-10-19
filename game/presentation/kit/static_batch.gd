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
## are looked up later. Scripted nodes under the root count as owners too.
## Folding happens once per root; a rebuilt root (a new terrain) is folded
## again by its owner.
##
## With the "containers" option, a held plain container (a Node3D or a mesh
## without a script) is not skipped whole: its own plain leaves are folded into
## batches under it, in its space, so moving, hiding or fading the container
## still moves, hides or fades them (kit/cutaway.gd fades a batch like any
## mesh). Containers whose children are looked up or walked one by one (a
## planter whose cylinders give the soil height, a beam whose parts are read
## by index) go in "keep": they and everything under them stay as they are.
##
## A held node in "still" is held only to be found (a floor that markers are
## built on): it never moves, hides, fades or recolours. Its plain leaves fold
## into the batches around it, like any unheld container's, so floors with a
## few pieces each share one batch per material instead of one batch each.
## The node itself, and anything under it that is held, kept or scripted,
## stays as it is. A held floor that does move or fade is not still.
##
## fold() does it all at once. start() and step() do the same work a few
## milliseconds at a time, so a big world folds over several frames without a
## hitch; every batch replaces its leaves in one go, so a half-folded world
## draws the same pixels too.
const FOLDED_META := "static_batch_folded"
## On a batch: [transform in the batch's space, mesh box] per folded leaf, for
## code that measures scenery piece by piece (part_boxes()).
const PARTS_META := "static_batch_parts"
const PRIMITIVES := ["BoxMesh", "SphereMesh", "CylinderMesh", "TorusMesh", "QuadMesh", "PlaneMesh", "PrismMesh", "CapsuleMesh"]
## Off only for comparing a folded and an unfolded frame in one process.
static var enabled := true
const SKIPPED_MATERIAL_PROPERTIES := ["resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id", "script"]
## Stored property names per material class, read once: asking every material
## for its whole property list costs far more than reading the values.
static var _material_properties: Dictionary = {}

## Folds root's static leaves. owners: the objects whose variables name the
## nodes that change later. options: "containers" (bool), "keep" and "still"
## (Arrays of nodes), see above. Returns {"folded": leaves, "batches": meshes}.
static func fold(root: Node3D, owners: Array, options: Dictionary = {}) -> Dictionary:
	var job := start(root, owners, options)
	if job.is_empty(): return {"folded": 0, "batches": 0}
	step(job, 0)
	return {"folded": job.folded, "batches": job.batches}

## Marks root folded. Returns the job for step(), or {} when there is nothing
## to fold.
static func start(root: Node3D, owners: Array, options: Dictionary = {}) -> Dictionary:
	if not enabled or not is_instance_valid(root) or not root.is_inside_tree() or root.has_meta(FOLDED_META): return {}
	root.set_meta(FOLDED_META, true)
	var kept := _ids(options.get("keep", []))
	# Only what is there now can fold. A node made while the job runs over
	# frames (a Lighthouse beam made by present(), say) was made to change.
	var existing: Dictionary = {}
	for node: Node in root.find_children("*", "", true, false): existing[node.get_instance_id()] = true
	var job := {"root": root, "root_id": root.get_instance_id(), "owners": owners.duplicate(), "owner_list": owners.duplicate(), "held": {}, "kept": kept, "still": _ids(options.get("still", [])), "containers": bool(options.get("containers", false)),
		"existing": existing, "scripted": [], "holding": [], "rechecked": false,
		"materials": {}, "bases": [], "scan": [[root, 0]], "walk": [], "seen": {}, "base_index": 0, "key_index": 0, "entry_index": 0, "tool": null, "folded": 0, "batches": 0, "done": false}
	job.walk.append([root, _base(root, job), 0])
	return job

## The leaves fold() would fold, each with the node its batch would go under,
## as [leaf, container]; nothing is changed (root is not even marked folded).
## For checking that nothing folded is ever changed afterwards.
static func plan(root: Node3D, owners: Array, options: Dictionary = {}) -> Array:
	var job := start(root, owners, options)
	if job.is_empty(): return []
	root.remove_meta(FOLDED_META)
	job["plan_only"] = true
	step(job, 0)
	var leaves: Array = []
	for base: Dictionary in job.bases:
		for key: String in base.order:
			var group: Array = base.groups[key]
			if group.size() < 2 or not _group_folds(group, base.node, job): continue
			for entry: Array in group: leaves.append([entry[0], base.node])
	return leaves

static func _ids(nodes: Array) -> Dictionary:
	var ids: Dictionary = {}
	for node: Variant in nodes:
		if is_instance_valid(node) and node is Node: ids[(node as Node).get_instance_id()] = true
	return ids

## Does up to budget_usec of the job's work (all of it for 0 or less): what
## the owners hold, then what scripted nodes under the root hold, a few values
## at a time, then the leaves, then one batch at a time. Returns true once the
## job is finished, or the root has gone.
static func step(job: Dictionary, budget_usec: int) -> bool:
	if job.done: return true
	var root: Variant = job.root
	if not is_instance_valid(root) or not (root as Node3D).is_inside_tree():
		job.done = true
		return true
	# Every step does at least one piece of work, so a busy device that is
	# already past the budget when the step begins still moves the fold on.
	var until := Time.get_ticks_usec() + budget_usec if budget_usec > 0 else -1
	var worked := false
	while not job.owners.is_empty():
		if worked and until >= 0 and Time.get_ticks_usec() >= until: return false
		worked = true
		var owner: Variant = job.owners.pop_front()
		if is_instance_valid(owner) and owner is Object: _queue_held(owner, job.held, job)
	while not job.scan.is_empty():
		if worked and until >= 0 and Time.get_ticks_usec() >= until: return false
		worked = true
		_scan(job)
	while not job.holding.is_empty():
		if worked and until >= 0 and Time.get_ticks_usec() >= until: return false
		worked = true
		_hold_some(job)
	while not job.walk.is_empty():
		if worked and until >= 0 and Time.get_ticks_usec() >= until: return false
		worked = true
		_walk(job)
	if not job.rechecked:
		if worked and until >= 0 and Time.get_ticks_usec() >= until: return false
		worked = true
		_recheck(job)
	while not job.holding.is_empty():
		if worked and until >= 0 and Time.get_ticks_usec() >= until: return false
		worked = true
		_hold_some(job)
	if job.get("plan_only", false):
		job.done = true
		return true
	while job.base_index < job.bases.size():
		if worked and until >= 0 and Time.get_ticks_usec() >= until: return false
		worked = true
		_build(job)
	job.done = true
	return true

## Scripted nodes under the root (spirits, trails, bubbles) may name other
## nodes there; what they name stays too.
static func _scan(job: Dictionary) -> void:
	var top: Array = job.scan.back()
	# Between frames a part of the tree can be freed: check before typing it.
	var found: Variant = top[0]
	var index: int = top[1]
	if not is_instance_valid(found) or index >= (found as Node).get_child_count():
		job.scan.pop_back()
		return
	top[1] = index + 1
	var child := (found as Node).get_child(index)
	if child.is_queued_for_deletion(): return
	if child.get_script() != null:
		_queue_held(child, job.held, job)
		job.scripted.append(child)
	if child.get_child_count() > 0: job.scan.append([child, 0])

## Looks at the next child on the walk.
static func _walk(job: Dictionary) -> void:
	var top: Array = job.walk.back()
	# Between frames a part of the tree can be freed: check before typing it.
	var found: Variant = top[0]
	var index: int = top[2]
	if not is_instance_valid(found) or index >= (found as Node).get_child_count():
		job.walk.pop_back()
		return
	top[2] = index + 1
	var base: Dictionary = top[1]
	var child := (found as Node).get_child(index)
	if child.is_queued_for_deletion(): return
	var id := child.get_instance_id()
	# A rebuilt part can also shift its siblings: see each node once.
	if job.seen.has(id): return
	job.seen[id] = true
	if not job.existing.has(id): return
	if child.get_script() != null or job.kept.has(id): return
	if job.still.has(id) and child.get_child_count() > 0 and (child.get_class() == "Node3D" or child is MeshInstance3D):
		# Held only to be found: its plain leaves join the batches around it.
		if (child as Node3D).visible: job.walk.append([child, base, 0])
		return
	if job.held.has(id):
		# A held container keeps its own node; its plain leaves batch under it.
		if job.containers and child.get_child_count() > 0 and (child.get_class() == "Node3D" or child is MeshInstance3D):
			job.walk.append([child, _base(child as Node3D, job), 0])
		return
	if child is Node3D and not (child as Node3D).visible: return
	if child.get_child_count() > 0:
		job.walk.append([child, base, 0])
		return
	if not child is MeshInstance3D: return
	var leaf := child as MeshInstance3D
	# The container may have moved since its base was made: measure now.
	var xform: Transform3D = (base.node as Node3D).global_transform.affine_inverse() * leaf.global_transform
	var key := _key(leaf, xform, job.materials)
	if key.is_empty(): return
	if not base.groups.has(key):
		base.groups[key] = []
		base.order.append(key)
	base.groups[key].append([leaf, xform])

## Appends the next leaf of the current group, or finishes the group.
static func _build(job: Dictionary) -> void:
	var base: Dictionary = job.bases[job.base_index]
	if job.key_index >= base.order.size():
		job.base_index += 1
		job.key_index = 0
		return
	var group: Array = base.groups[base.order[job.key_index]]
	if group.size() < 2:
		job.key_index += 1
		return
	if job.tool == null: job.tool = SurfaceTool.new()
	if job.entry_index < group.size():
		var entry: Array = group[job.entry_index]
		job.entry_index += 1
		if is_instance_valid(entry[0]): (job.tool as SurfaceTool).append_from((entry[0] as MeshInstance3D).mesh, 0, entry[1])
		return
	var tool: SurfaceTool = job.tool
	job.tool = null
	job.entry_index = 0
	job.key_index += 1
	# Over several frames, a leaf or its container may have gone with a rebuild:
	# then the whole group stays as it is.
	var container: Variant = base.node
	if not _group_folds(group, container, job): return
	var parts: Array = []
	for entry: Array in group: parts.append([entry[1], (entry[0] as MeshInstance3D).get_aabb()])
	var batch := MeshInstance3D.new()
	batch.name = "StaticBatch%d" % job.batches
	batch.mesh = tool.commit()
	var first: MeshInstance3D = group[0][0]
	batch.material_override = first.material_override
	batch.cast_shadow = first.cast_shadow
	batch.layers = first.layers
	batch.gi_mode = first.gi_mode
	batch.set_meta(PARTS_META, parts)
	(container as Node3D).add_child(batch)
	for entry: Array in group:
		var leaf := entry[0] as MeshInstance3D
		leaf.get_parent().remove_child(leaf)
		leaf.queue_free()
	job.folded += group.size()
	job.batches += 1

## Whether a group still folds now, as a whole: its container and every leaf
## still in the tree, no leaf (or anything between it and the container) held,
## kept or scripted, and every leaf where it was found. fold() and plan() both
## ask this, so a plan names exactly what a fold folds.
static func _group_folds(group: Array, container: Variant, job: Dictionary) -> bool:
	if not is_instance_valid(container) or not (container as Node3D).is_inside_tree(): return false
	var to_base := (container as Node3D).global_transform.affine_inverse()
	for entry: Array in group:
		if not is_instance_valid(entry[0]) or not (entry[0] as Node).is_inside_tree() or (entry[0] as Node).is_queued_for_deletion(): return false
		if _guarded(entry[0], container, job) or not (to_base * (entry[0] as Node3D).global_transform).is_equal_approx(entry[1]): return false
	return true

## The world boxes a mesh draws: one per folded leaf for a batch (each as the
## leaf's own transformed box), else the mesh's own.
static func part_boxes(mesh: MeshInstance3D) -> Array[AABB]:
	var boxes: Array[AABB] = []
	if not mesh.has_meta(PARTS_META):
		boxes.append(mesh.global_transform * mesh.get_aabb())
		return boxes
	for part: Array in mesh.get_meta(PARTS_META):
		boxes.append((mesh.global_transform * (part[0] as Transform3D)) * (part[1] as AABB))
	return boxes

## Collects again what the owners and the scripted nodes hold, before the
## first batch replaces anything: a job over frames may have started before a
## screen or world named some of its nodes. Over frames this look takes a few
## frames itself, a node named meanwhile in a value it has passed is missed,
## as one named after it and before a later batch always was; _group_folds
## still checks every leaf where it was found.
static func _recheck(job: Dictionary) -> void:
	job.rechecked = true
	var held: Dictionary = {}
	job["held_now"] = held
	for owner: Variant in job.owner_list + job.scripted:
		if is_instance_valid(owner) and owner is Object: _queue_held(owner, held, job)

## Whether a leaf or anything between it and its batch's container is named
## by an owner (at the start or now), kept, or carries a script.
static func _guarded(leaf: Node, container: Node, job: Dictionary) -> bool:
	var held_now: Dictionary = job.get("held_now", {})
	var node := leaf
	while node != null and node != container:
		var id := node.get_instance_id()
		if job.kept.has(id) or node.get_script() != null: return true
		# A still node may stand between a leaf and its batch; the leaf itself never.
		if (job.held.has(id) or held_now.has(id)) and (node == leaf or not job.still.has(id)): return true
		node = node.get_parent()
	return false

static func _base(node: Node3D, job: Dictionary) -> Dictionary:
	var base := {"node": node, "to_base": node.global_transform.affine_inverse(), "groups": {}, "order": []}
	job.bases.append(base)
	return base

## The batch a leaf can join, or "" when it must stay its own node.
static func _key(leaf: MeshInstance3D, xform: Transform3D, materials: Dictionary) -> String:
	if leaf.mesh == null or leaf.mesh.get_class() not in PRIMITIVES or leaf.mesh.get_surface_count() != 1: return ""
	if not leaf.get_meta_list().is_empty() or leaf.material_overlay != null or leaf.get_surface_override_material(0) != null: return ""
	if leaf.transparency != 0.0 or leaf.sorting_offset != 0.0 or leaf.visibility_range_end != 0.0 or leaf.visibility_range_begin != 0.0: return ""
	var material := leaf.material_override as StandardMaterial3D
	if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_color.a < 1.0 or material.albedo_texture != null: return ""
	if material.next_pass != null: return ""
	if not _uniform(xform.basis): return ""
	return "%d|%d|%d|%s" % [leaf.cast_shadow, leaf.layers, leaf.gi_mode, _material_key(material, materials)]

## Every stored value of a material, hashed once per material in a fold.
static func _material_key(material: StandardMaterial3D, materials: Dictionary) -> String:
	var id := material.get_instance_id()
	if materials.has(id): return materials[id]
	var kind := material.get_class()
	if not _material_properties.has(kind):
		var names: Array[StringName] = []
		for property: Dictionary in material.get_property_list():
			var name := str(property.name)
			if int(property.usage) & PROPERTY_USAGE_STORAGE and not name in SKIPPED_MATERIAL_PROPERTIES and not name.begins_with("metadata/"): names.append(StringName(name))
		_material_properties[kind] = names
	var values: Array = []
	for name: StringName in _material_properties[kind]: values.append(material.get(name))
	for name: StringName in material.get_meta_list(): values.append([name, material.get_meta(name)])
	var key := var_to_bytes(values).hex_encode().sha256_text()
	materials[id] = key
	return key

## A rotation times one scale for all axes.
static func _uniform(basis: Basis) -> bool:
	var x := basis.x.length()
	var y := basis.y.length()
	var z := basis.z.length()
	if x < 0.000001 or absf(x - y) > x * 0.0001 or absf(x - z) > x * 0.0001: return false
	var unit := basis.orthonormalized()
	return absf(unit.x.dot(unit.y)) < 0.0001 and absf(unit.y.dot(unit.z)) < 0.0001 and absf(unit.x.dot(unit.z)) < 0.0001 and basis.determinant() > 0.0

## Every node an owner's script variables refer to, through arrays and
## dictionaries (keys too), a few levels deep, goes into held: the variables'
## values are queued here and looked through by _hold_some, a few at a time,
## since a world or a screen can name thousands of values. The job itself (a
## world keeps its fold's job in a variable) is never looked through: its own
## queue grows while it is read.
static func _queue_held(owner: Object, held: Dictionary, job: Dictionary) -> void:
	for property: Dictionary in owner.get_property_list():
		if not int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		_queue_value(owner.get(property.name), 0, held, job)

## Every node owner's script variables refer to, all at once.
static func _collect_held(owner: Object, held: Dictionary) -> void:
	var job := {"holding": []}
	_queue_held(owner, held, job)
	while not job.holding.is_empty(): _hold_some(job)

## Values one piece of the fold looks through.
const HOLD_PIECE := 64
const HOLD_DEPTH := 4

static func _queue_value(value: Variant, depth: int, held: Dictionary, job: Dictionary) -> void:
	if depth > HOLD_DEPTH: return
	var kind := typeof(value)
	if kind == TYPE_DICTIONARY and is_same(value, job): return
	if kind == TYPE_OBJECT or kind == TYPE_ARRAY or kind == TYPE_DICTIONARY: (job.holding as Array).append([value, depth, held])

static func _hold_some(job: Dictionary) -> void:
	var holding: Array = job.holding
	for _piece in range(HOLD_PIECE):
		if holding.is_empty(): return
		var item: Array = holding.pop_back()
		var value: Variant = item[0]
		var depth: int = item[1]
		var held: Dictionary = item[2]
		match typeof(value):
			TYPE_OBJECT:
				# A variable can still name a node that has since been freed.
				if is_instance_valid(value) and value is Node: held[(value as Node).get_instance_id()] = true
			TYPE_ARRAY:
				for inner: Variant in value: _queue_value(inner, depth + 1, held, job)
			TYPE_DICTIONARY:
				for inner: Variant in value:
					_queue_value(inner, depth + 1, held, job)
					_queue_value(value[inner], depth + 1, held, job)
