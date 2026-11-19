extends RefCounted
## Pieces modelled in Blender: a GLB under res://assets/models/ whose mesh
## nodes ("parts") have one surface per material slot, the slot named by its
## material ("ay_wood" is the slot "wood"). A model carries no colours: the
## piece that places it paints every slot from its own palette or theme, so a
## theme recolours a model like any code-built piece. Made with the private
## Blender kit (tools/blender, see the agent docs); never edit a GLB by hand.
##
## Two ways to place a part:
## - still(): a plain container holding one plain leaf per slot, the cached
##   slot mesh drawn with Primitives.shared_material(colour). The leaves fold
##   into the scenery batches like any box (kit/static_batch.gd), so a model
##   costs no draw call of its own and a slot's colour is free.
## - moving(): one MeshInstance3D whose cached mesh has each slot's colour on
##   its vertices, drawn with the palette look: one draw call for a part that
##   turns, slides, hides or recolours (list it in the piece's moving_parts()).
## A model is read once and kept until SessionRelease; a moving part's painted
## mesh is kept once per colour set.
##
## A slot's colour is a Color, or {"color", "roughness", "glow", "energy"} for
## a slot that glows (still parts only: a glow cannot ride on vertex colours).
## A slot with no colour is drawn magenta and pushes an error.
const Primitives = preload("res://presentation/kit/primitives.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
## A slot material's name is this prefix and the slot.
const SLOT_PREFIX := "ay_"
const MISSING := Color.MAGENTA

## path -> {part: {"xform": Transform3D in the model's space, "slots": {slot: ArrayMesh}}}
static var _models: Dictionary = {}
## [path, part, colour key] -> painted ArrayMesh
static var _painted: Dictionary = {}

## A part's resting transform in the model (where Blender placed its origin).
static func transform(path: String, part: String) -> Transform3D:
	return _part(path, part).get("xform", Transform3D.IDENTITY)

## Every part a model has, sorted.
static func parts(path: String) -> Array[String]:
	var names: Array[String] = []
	names.assign(_model(path).keys())
	names.sort()
	return names

## The slots a part paints, in the model's order.
static func slots(path: String, part: String) -> Array[String]:
	var names: Array[String] = []
	names.assign((_part(path, part).get("slots", {}) as Dictionary).keys())
	return names

## A still part under parent: a plain Node3D named part, at its model
## transform (keep) or at the parent's origin, with one plain leaf per slot.
## Hold the container (not the leaves) if the piece moves it whole.
static func still(path: String, part: String, colors: Dictionary, parent: Node3D, keep := true) -> Node3D:
	var found := _part(path, part)
	var node := Node3D.new()
	node.name = part
	if keep: node.transform = found.get("xform", Transform3D.IDENTITY)
	var slot_meshes: Dictionary = found.get("slots", {})
	for slot: String in slot_meshes:
		var leaf := MeshInstance3D.new()
		leaf.name = slot
		leaf.mesh = slot_meshes[slot]
		leaf.material_override = _look(colors, slot, path, part)
		node.add_child(leaf)
	parent.add_child(node)
	return node

## A moving part under parent: one mesh, every slot's colour on its vertices.
static func moving(path: String, part: String, colors: Dictionary, parent: Node3D, keep := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = part
	node.mesh = painted(path, part, colors)
	node.material_override = Primitives.palette_material(Primitives.shared_material(Color.WHITE))
	if keep: node.transform = transform(path, part)
	parent.add_child(node)
	return node

## A part as one mesh with each slot's colour on its vertices (cached per colours).
static func painted(path: String, part: String, colors: Dictionary) -> ArrayMesh:
	var slot_meshes: Dictionary = _part(path, part).get("slots", {})
	var tints: Array = []
	for slot: String in slot_meshes: tints.append(_color(colors, slot, path, part, true))
	var key := [path, part, tints]
	var kept: ArrayMesh = _painted.get(key)
	if kept != null: return kept
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index := 0
	for slot: String in slot_meshes:
		var arrays := (slot_meshes[slot] as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tint: Color = tints[index]
		index += 1
		for i: int in arrays[Mesh.ARRAY_INDEX]:
			tool.set_color(tint)
			tool.set_normal(normals[i])
			tool.add_vertex(verts[i])
	tool.index()
	var mesh := tool.commit()
	_painted[key] = mesh
	SessionRelease.on_exit(Callable(load("res://presentation/kit/models.gd"), "release_cached"))
	return mesh

## Lets go of every kept model and painted mesh (SessionRelease calls this).
static func release_cached() -> void:
	_models.clear()
	_painted.clear()

static func _look(colors: Dictionary, slot: String, path: String, part: String) -> StandardMaterial3D:
	var value: Variant = colors.get(slot)
	if value is Dictionary:
		var look: Dictionary = value
		return Primitives.shared_material(look.get("color", MISSING), look.get("roughness", 0.9), look.get("glow", Color(0, 0, 0, 0)), look.get("energy", 0.0))
	return Primitives.shared_material(_color(colors, slot, path, part, false))

static func _color(colors: Dictionary, slot: String, path: String, part: String, plain_only: bool) -> Color:
	var value: Variant = colors.get(slot)
	if value is Color: return value
	if value is Dictionary and not plain_only: return (value as Dictionary).get("color", MISSING)
	if value is Dictionary: push_error("Models: %s %s slot %s glows; a moving part takes plain colours only" % [path, part, slot])
	else: push_error("Models: no colour for %s %s slot %s" % [path, part, slot])
	return MISSING

static func _part(path: String, part: String) -> Dictionary:
	var model := _model(path)
	if not model.has(part):
		push_error("Models: %s has no part %s" % [path, part])
		return {}
	return model[part]

static func _model(path: String) -> Dictionary:
	if _models.has(path): return _models[path]
	var model: Dictionary = {}
	_models[path] = model
	SessionRelease.on_exit(Callable(load("res://presentation/kit/models.gd"), "release_cached"))
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Models: cannot load %s" % path)
		return model
	var root := scene.instantiate()
	var walk: Array[Node] = [root]
	while not walk.is_empty():
		var node: Node = walk.pop_back()
		walk.append_array(node.get_children())
		if not node is MeshInstance3D or (node as MeshInstance3D).mesh == null: continue
		var source := (node as MeshInstance3D).mesh
		var xform := Transform3D.IDENTITY
		var up: Node = node
		while up != root and up is Node3D:
			xform = (up as Node3D).transform * xform
			up = up.get_parent()
		var slot_meshes: Dictionary = {}
		for surface in range(source.get_surface_count()):
			var material := source.surface_get_material(surface)
			var slot := str(material.resource_name if material != null else "").trim_prefix(SLOT_PREFIX)
			var arrays := source.surface_get_arrays(surface)
			var lean := []
			lean.resize(Mesh.ARRAY_MAX)
			lean[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
			lean[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
			lean[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lean)
			mesh.resource_name = "%s:%s" % [node.name, slot]
			mesh.set_meta(StaticBatch.MODEL_MESH_META, "%s#%s#%s" % [path, node.name, slot])
			slot_meshes[slot] = mesh
		model[str(node.name)] = {"xform": xform, "slots": slot_meshes}
	root.free()
	return model
