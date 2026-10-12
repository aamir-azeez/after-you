extends RefCounted
## World kit: mesh and material helpers shared by every chapter world.
##
## fresh_material() gives each mesh its own material, which presentation code
## may recolour, glow or fade in place. shared_material() returns one cached
## material per look for static scenery that nothing ever changes; it carries
## the SHARED_META flag, and anything that must change it first takes a copy
## (see own_material()). Never pass a shared material to code that mutates.

const SHARED_META := &"kit_shared_material"
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}

static func fresh_material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

## One cached material per colour, roughness and glow, for unchanging scenery.
static func shared_material(color: Color, roughness: float = 0.9, glow: Color = Color(0, 0, 0, 0), energy: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.3f|%s|%.3f" % [color.to_html(), roughness, glow.to_html(), energy]
	var cached: StandardMaterial3D = _materials.get(key)
	if cached != null: return cached
	cached = fresh_material(color, roughness)
	if energy > 0.0:
		cached.emission_enabled = true
		cached.emission = glow
		cached.emission_energy_multiplier = energy
	cached.set_meta(SHARED_META, true)
	_materials[key] = cached
	return cached

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

## A bar of square section from one point to another, in parent space.
static func bar_between(from: Vector3, to: Vector3, mesh_width: float, mat: Material, parent: Node3D) -> MeshInstance3D:
	var bar := mesh_node(box_mesh(Vector3(mesh_width, mesh_width, from.distance_to(to))), mat, (from + to) / 2.0, parent)
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
