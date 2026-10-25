extends RefCounted
## World kit: mesh and material helpers shared by every chapter world.
##
## shared_material() returns one cached material per look (colour, roughness,
## glow), and every world's shape helpers (island_world.box, sphere, ...) use
## it, so a world makes one material per look rather than one per mesh: fewer
## resources to make, upload and fold. A cached material carries the
## SHARED_META flag and is never changed in place: code that recolours, glows
## or fades a mesh first takes the mesh's own copy with own_material(), which
## leaves a material of its own as it is. fresh_material() is a new material
## for a caller that sets it up itself. The shape helpers share meshes the
## same way (cached_shape). changed_shared_looks() names any cached material
## or shape changed in place since it was made (the tests check it).

const SessionRelease = preload("res://presentation/kit/session_release.gd")
const SHARED_META := &"kit_shared_material"
static var _materials: Dictionary = {}
## The instance ids of the cached materials, for is_cached().
static var _material_ids: Dictionary = {}
## Per cached material (by key): its stored values when it was made.
static var _material_prints: Dictionary = {}
## Stored property names per material class, read once (_material_print).
static var _print_names: Dictionary = {}
static var _meshes: Dictionary = {}
## cached_shape's meshes, by shape key, held weakly: a shape lives while a
## world draws it, or while it is one of the _kept_shapes.
static var _shapes: Dictionary = {}
const SHAPES_PRUNE_AT := 4096
## The last KEPT_SHAPES shapes cached_shape made (or found again while still
## drawn), also held for the session, oldest first, so a chapter opened again
## finds its one-off wall lengths still made instead of making and uploading
## each again: Turn of the Tide's repeat open made about 250 of them. Every
## offered chapter together makes about 600 (about 41,000 vertices), so the
## bound only matters in a very long session; past it the oldest go first.
static var _kept_shapes: Dictionary = {}
const KEPT_SHAPES := 1024

static func fresh_material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

## One cached material per colour, roughness and glow, for unchanging scenery.
static func shared_material(color: Color, roughness: float = 0.9, glow: Color = Color(0, 0, 0, 0), energy: float = 0.0) -> StandardMaterial3D:
	# The exact values (an Array hashes far faster than formatting a string;
	# a barely see-through colour is not the opaque look).
	var key := [color, roughness, glow, energy]
	var cached: StandardMaterial3D = _materials.get(key)
	if cached != null: return cached
	cached = fresh_material(color, roughness)
	if energy > 0.0:
		cached.emission_enabled = true
		cached.emission = glow
		cached.emission_energy_multiplier = energy
	cached.set_meta(SHARED_META, true)
	_materials[key] = cached
	_material_ids[cached.get_instance_id()] = true
	_material_prints[key] = _material_print(cached)
	# Kept looks go before the engine frees its material shaders, not when this script is freed.
	SessionRelease.on_exit(Callable(load("res://presentation/kit/primitives.gd"), "release_cached"))
	return cached

## Lets go of every kept look and mesh (SessionRelease calls this at shutdown).
static func release_cached() -> void:
	_materials.clear()
	_material_ids.clear()
	_material_prints.clear()
	_meshes.clear()
	_shapes.clear()
	_kept_shapes.clear()

## Whether mat is one of the cached looks themselves (a copy of one is not).
static func is_cached(mat: Material) -> bool:
	return mat != null and _material_ids.has(mat.get_instance_id())

## Every stored value of a material (its metadata aside), as bytes.
static func _material_print(mat: Material) -> PackedByteArray:
	var kind := mat.get_class()
	if not _print_names.has(kind):
		var names: Array[StringName] = []
		for property: Dictionary in mat.get_property_list():
			var name := str(property.name)
			if int(property.usage) & PROPERTY_USAGE_STORAGE and not name.begins_with("metadata/") and not name.begins_with("resource_"): names.append(StringName(name))
		_print_names[kind] = names
	var values: Array = []
	for name: StringName in _print_names[kind]: values.append(mat.get(name))
	return var_to_bytes(values)

## The keys of the cached looks changed in place since they were made: a
## material whose values changed (code changed it without own_material()),
## or a shared shape resized (code resized it instead of building its own).
## None, in a working build.
static func changed_shared_looks() -> Array[String]:
	var changed: Array[String] = []
	for key: Array in _materials:
		if _material_print(_materials[key]) != _material_prints[key]: changed.append(str(key))
	for key: Array in _shapes:
		var mesh: Variant = (_shapes[key] as WeakRef).get_ref()
		if mesh != null and _mesh_key(mesh) != key: changed.append(str(key))
	for key: Variant in _meshes:
		if key is Array and _mesh_key(_meshes[key]) != key: changed.append(str(key))
	return changed

static func is_shared(mat: Material) -> bool:
	return mat != null and mat.has_meta(SHARED_META)

## The node's own material: a shared one is replaced by a private copy first,
## so changing it never reaches other scenery.
static func own_material(node: GeometryInstance3D) -> StandardMaterial3D:
	var mat := node.material_override as StandardMaterial3D
	if mat != null and is_shared(mat):
		mat = mat.duplicate() as StandardMaterial3D
		mat.remove_meta(SHARED_META)
		node.material_override = mat
	return mat

## Every cached material, for tests that prove scenery colours never change.
static func shared_materials() -> Array:
	return _materials.values()

static func mesh_node(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node

static func box_mesh(size: Vector3) -> BoxMesh:
	var shape := BoxMesh.new()
	shape.size = size
	return shape

static func sphere_mesh(radius: float) -> SphereMesh:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 16
	shape.rings = 8
	return shape

static func cylinder_mesh(radius: float, height: float, top_radius: float = -1.0, segments: int = 24) -> CylinderMesh:
	var shape := CylinderMesh.new()
	shape.top_radius = radius if top_radius < 0.0 else top_radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = segments
	return shape

static func ring_mesh(radius: float) -> TorusMesh:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - 0.025
	shape.outer_radius = radius + 0.025
	shape.rings = 24
	shape.ring_segments = 8
	return shape

## Cached meshes for static scenery only; a shared mesh is never resized.
static func shared_mesh(kind: String, a: float, b: float = 0.0, c: float = 0.0) -> Mesh:
	var key := "%s|%.4f|%.4f|%.4f" % [kind, a, b, c]
	var cached: Mesh = _meshes.get(key)
	if cached != null: return cached
	match kind:
		"box": cached = box_mesh(Vector3(a, b, c))
		"sphere": cached = sphere_mesh(a)
		"cylinder": cached = cylinder_mesh(a, b, c, 12)
		"cone": cached = cylinder_mesh(a, b, 0.0, 10)
		"prism":
			var prism := PrismMesh.new()
			prism.size = Vector3(a, b, c)
			cached = prism
		_: cached = box_mesh(Vector3(a, b, c))
	_meshes[key] = cached
	return cached

## The one cached mesh of mesh's shape (a box, sphere, cylinder, ring or
## prism of the same parameters), mesh itself the first time. Shared by every
## mesh of that shape, so it is never resized in place: code that resizes a
## mesh builds it with its own (box_mesh and the like). Other meshes come back
## as they are.
static func cached_shape(mesh: Mesh) -> Mesh:
	var key := _mesh_key(mesh)
	if key.is_empty(): return mesh
	var found := _shape(key)
	if found != null: return found
	if _shapes.size() >= SHAPES_PRUNE_AT:
		for gone: Array in _shapes.keys().filter(func(shape: Array) -> bool: return (_shapes[shape] as WeakRef).get_ref() == null): _shapes.erase(gone)
	_shapes[key] = weakref(mesh)
	_keep_shape(key, mesh)
	return mesh

## cached_shape(box_mesh(size)), without making a box first when its shape is
## cached already: worlds ask for thousands of boxes an open, nearly all of
## them cached.
static func cached_box(size: Vector3) -> Mesh:
	var found := _shape([&"box", size, 0, 0, 0])
	return found if found != null else cached_shape(box_mesh(size))

## The cached mesh of a shape key, or null.
static func _shape(key: Array) -> Mesh:
	var kept: Mesh = _meshes.get(key)
	if kept == null: kept = _kept_shapes.get(key)
	if kept != null: return kept
	var ref: WeakRef = _shapes.get(key)
	var live: Mesh = ref.get_ref() if ref != null else null
	# Still drawn but no longer kept (past the bound): kept again.
	if live != null: _keep_shape(key, live)
	return live

static func _keep_shape(key: Array, mesh: Mesh) -> void:
	if _kept_shapes.size() >= KEPT_SHAPES: _kept_shapes.erase(_kept_shapes.keys()[0])
	_kept_shapes[key] = mesh
	# Kept shapes go before the renderer stops, not when this script is freed.
	SessionRelease.on_exit(Callable(load("res://presentation/kit/primitives.gd"), "release_cached"))

## Folds a finished static prop into the caches: each primitive mesh is swapped
## for one cached mesh of the same shape, and each plain material (colour and
## roughness only) for its shared_material(). Textured, glowing, billboard or
## unshaded materials keep their own. Only for props nothing recolours or resizes.
static func share_static(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var key := _mesh_key(instance.mesh)
		if not key.is_empty():
			var cached: Mesh = _meshes.get(key)
			if cached == null: _meshes[key] = instance.mesh
			else: instance.mesh = cached
		var mat := instance.material_override as StandardMaterial3D
		if mat != null and not is_shared(mat) and _plain(mat):
			instance.material_override = shared_material(mat.albedo_color, mat.roughness)

## A primitive mesh's shape as exact values ([] for any other mesh).
static func _mesh_key(mesh: Mesh) -> Array:
	if mesh is BoxMesh: return [&"box", mesh.size, mesh.subdivide_width, mesh.subdivide_height, mesh.subdivide_depth]
	if mesh is SphereMesh: return [&"sphere", mesh.radius, mesh.height, mesh.radial_segments, mesh.rings, mesh.is_hemisphere]
	if mesh is CylinderMesh: return [&"cylinder", mesh.top_radius, mesh.bottom_radius, mesh.height, mesh.radial_segments, mesh.rings, mesh.cap_top, mesh.cap_bottom]
	if mesh is TorusMesh: return [&"torus", mesh.inner_radius, mesh.outer_radius, mesh.rings, mesh.ring_segments]
	if mesh is PrismMesh: return [&"prism", mesh.size, mesh.left_to_right]
	return []

static func _plain(mat: StandardMaterial3D) -> bool:
	return mat.get_class() == "StandardMaterial3D" and mat.albedo_texture == null and not mat.emission_enabled \
		and mat.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL \
		and mat.metallic == 0.0 and mat.render_priority == 0 and not mat.no_depth_test \
		and mat.transparency == (BaseMaterial3D.TRANSPARENCY_ALPHA if mat.albedo_color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED)

## A bar of square section from one point to another, in parent space. Its box
## is the cached one of its size (cached_box): a bar is never resized.
static func bar_between(from: Vector3, to: Vector3, mesh_width: float, mat: Material, parent: Node3D) -> MeshInstance3D:
	var bar := mesh_node(cached_box(Vector3(mesh_width, mesh_width, from.distance_to(to))), mat, (from + to) / 2.0, parent)
	if bar.is_inside_tree(): bar.look_at(parent.to_global(to), Vector3.UP)
	else: bar.basis = Basis.looking_at(to - from, Vector3.UP)
	return bar

## A floor rectangle [x0, z0, x1, z1] with a rectangular hole cut out, as up to
## four non-empty rectangles. With no hole, the rectangle itself.
static func rect_minus_hole(rect: Array, hole: Array) -> Array:
	if hole.is_empty(): return [rect]
	var result: Array = []
	for cut: Array in [[rect[0], rect[1], hole[0], rect[3]], [hole[2], rect[1], rect[2], rect[3]], [hole[0], rect[1], hole[2], hole[1]], [hole[0], hole[3], hole[2], rect[3]]]:
		if cut[2] > cut[0] and cut[3] > cut[1]: result.append(cut)
	return result
