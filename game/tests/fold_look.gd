extends RefCounted
## Test support: how a chapter world looks wherever its scenery fold could make
## a difference, so a folded world can be compared with an unfolded one.
## - Every node the world's variables name (under its terrain): where it is and
##   whether it shows, its plain children the same way, and, unless it is held
##   only to be found (the world's _fold_options "still", whose pieces fold
##   with the scenery around it), every piece drawn under it.
## - Every piece the whole terrain draws, whatever node draws it.
## A piece is one mesh's world box with its colour, glow and see-through, and
## a batch counts as the pieces it draws (StaticBatch.part_boxes). Engine-
## numbered names (and their copies' names) differ between worlds, so their
## numbers are dropped.
const StaticBatch = preload("res://presentation/kit/static_batch.gd")

static func look(world: Node3D) -> Array:
	var terrain: Node3D = world.terrain
	var held: Dictionary = {}
	StaticBatch._collect_held(world, held)
	var still: Dictionary = {}
	for node: Variant in world._fold_options().get("still", []):
		if is_instance_valid(node): still[(node as Node).get_instance_id()] = true
	var numbered := RegEx.create_from_string("[@_]([A-Z][A-Za-z0-9]+)[@_][0-9]+")
	var rows: Array = []
	for id: int in held:
		var node := instance_from_id(id) as Node3D
		if node == null or not is_instance_valid(terrain) or not terrain.is_ancestor_of(node): continue
		var path := numbered.sub(str(terrain.get_path_to(node)), "@$1", true)
		rows.append("%s %s %s" % [path, _snap(node.global_transform), str(node.is_visible_in_tree())])
		for child: Node in node.find_children("*", "Node3D", true, false):
			if child is MeshInstance3D: continue
			rows.append("%s/%s %s %s" % [path, numbered.sub(str(node.get_path_to(child)), "@$1", true), _snap((child as Node3D).global_transform), str((child as Node3D).is_visible_in_tree())])
		if not still.has(id): rows.append("%s pieces %s" % [path, "; ".join(pieces(node))])
	rows.sort()
	rows.append("drawn %s" % "; ".join(pieces(terrain)))
	return rows

## Every piece drawn at or under node, sorted.
static func pieces(node: Node) -> Array:
	var found: Array = []
	for child: Node in [node] + node.find_children("*", "MeshInstance3D", true, false):
		if not child is MeshInstance3D: continue
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var tone := _material(mesh)
		for box: AABB in StaticBatch.part_boxes(mesh): found.append("%s %s" % [_snap_box(box), tone])
	found.sort()
	return found

static func _material(mesh: MeshInstance3D) -> String:
	if not mesh.material_override is StandardMaterial3D: return "-"
	var material := mesh.material_override as StandardMaterial3D
	return "%s %s %s %s %d" % [str(material.albedo_color), str(material.emission_enabled), str(material.emission), str(snappedf(material.emission_energy_multiplier, 0.001)), material.transparency]

static func _snap(value: Transform3D) -> String:
	return "%s %s %s %s" % [_snap_vector(value.basis.x), _snap_vector(value.basis.y), _snap_vector(value.basis.z), _snap_vector(value.origin)]

static func _snap_box(box: AABB) -> String:
	return "%s %s" % [_snap_vector(box.position), _snap_vector(box.end)]

static func _snap_vector(value: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [snappedf(value.x, 0.001) + 0.0, snappedf(value.y, 0.001) + 0.0, snappedf(value.z, 0.001) + 0.0]
