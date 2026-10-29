extends RefCounted
## Shared pieces for Home's keepsakes (presentation/keepsakes/*.gd): the
## palette, shape helpers on the world kit's cached meshes and looks, the
## upgrade pieces every keepsake shares (the Hard plinth, gold balls and vines),
## and the started outline: the keepsake as one merged mesh with one shared
## see-through look, and a dot per stage.
##
## Every mesh and look is cached for the session and never changed in place:
## lighting a lamp swaps a mesh to another cached look. Caches this file keeps
## (tori, outlines) register with SessionRelease.
##
## A keepsake's own frame: +z faces the Home camera, +x is screen right, y up,
## one unit about a spirit's height.
const Primitives = preload("res://presentation/kit/primitives.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")

const WOOD := Color("a17d60")
const WOOD_LIGHT := Color("c4a47f")
const CREAM := Color("eee4c7")
const STONE := Color("a99d8b")
const STONE_LIGHT := Color("cbbfa8")
const WATER := Color("4b7480")
const TIDE := Color("6aa6ab")
const LAMP := Color("ffd27a")
const LAMP_OFF := Color("d9d0b4")
const PEACH := Color("f4c38d")
const CORAL := Color("e59a86")
const ROOF := Color("d98a74")
const MINT := Color("91d6c6")
const MINT_DEEP := Color("5fae9c")
const SLATE := Color("71818b")
const SLATE_DARK := Color("536979")
const SNOW := Color("fff7e8")
const GOLD := Color("efba73")
const GOLD_DEEP := Color("e9a823")
const LEAF := Color("6f9e68")
const POT := Color("ba8770")
const GLASS := Color("bfe6dc")
## The started and next outline's veil.
const GHOST := Color(0.29, 0.48, 0.43, 0.42)
## A stage's dot: done solo, done with a friend, not done.
const DOT_SOLO := PEACH
const DOT_FRIEND := MINT
const DOT_DIM := Color("dfe6d6")
const STEP := Color("efe6c9")
const PLANK := Color("c4b090")
const POST := Color("8b7964")
## A Hard plinth's height: a keepsake on one stands this much higher.
const PLINTH_TOP := 0.24

static var _tori: Dictionary = {}
static var _outlines: Dictionary = {}
static var _ghost: StandardMaterial3D

# --- looks ---------------------------------------------------------------------

static func mat(color: Color) -> Material:
	return Primitives.shared_material(color)

## A lit look (a lamp on, a gold piece): the colour glowing at `energy`.
static func glow(color: Color, energy: float) -> Material:
	return Primitives.shared_material(color, 0.6, color, energy)

## A see-through look (glass, a beam): plain alpha, a key the warm-up draws.
static func clear(color: Color, alpha: float, energy: float = 0.0) -> Material:
	return Primitives.shared_material(Color(color, alpha), 0.2, color if energy > 0.0 else Color(0, 0, 0, 0), energy)

static func ghost() -> StandardMaterial3D:
	if _ghost == null:
		_ghost = StandardMaterial3D.new()
		_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# A depth pre-pass keeps each outline one even veil where its parts overlap.
		_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_ghost.albedo_color = GHOST
		SessionRelease.on_exit(Callable(load("res://presentation/keepsakes/keepsake_parts.gd"), "release_cached"))
	return _ghost

## Lets go of the cached tori, outlines and the veil (SessionRelease calls this).
static func release_cached() -> void:
	_tori.clear()
	_outlines.clear()
	_ghost = null

# --- shapes ----------------------------------------------------------------------

static func node(parent: Node3D, mesh: Mesh, look: Material, at: Vector3, rot: Vector3 = Vector3.ZERO, size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var part := Primitives.mesh_node(mesh, look, at, parent)
	part.rotation = rot
	part.scale = size
	return part

static func box(parent: Node3D, size: Vector3, color: Color, at: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return node(parent, Primitives.shared_mesh("box", size.x, size.y, size.z), mat(color), at, rot)

static func cyl(parent: Node3D, radius: float, height: float, color: Color, at: Vector3, top: float = -1.0) -> MeshInstance3D:
	return node(parent, Primitives.shared_mesh("cylinder", radius, height, radius if top < 0.0 else top), mat(color), at)

## A low sphere. A squashed or stretched one is baked into its mesh (round in
## x and z, the middle of the two), so it never carries a scale that keeps it
## out of Home's shared batches.
static func sph(parent: Node3D, radius: float, color: Color, at: Vector3, size: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return node(parent, low_sphere(radius * (size.x + size.z) * 0.5, radius * 2.0 * size.y), mat(color), at, rot)

static func cone(parent: Node3D, radius: float, height: float, color: Color, at: Vector3) -> MeshInstance3D:
	return node(parent, Primitives.shared_mesh("cone", radius, height), mat(color), at)

static func prism(parent: Node3D, size: Vector3, color: Color, at: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return node(parent, Primitives.shared_mesh("prism", size.x, size.y, size.z), mat(color), at, rot)

static func ring(parent: Node3D, radius: float, thick: float, color: Color, at: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return node(parent, torus(radius, thick), mat(color), at, rot)

## A square bar from one point to another, in parent space.
static func bar(parent: Node3D, from: Vector3, to: Vector3, width: float, color: Color) -> MeshInstance3D:
	var part := Primitives.mesh_node(Primitives.cached_box(Vector3(width, width, from.distance_to(to))), mat(color), (from + to) * 0.5, parent)
	part.basis = Basis.looking_at(to - from, Vector3.UP)
	return part

## An empty node that moves, under `parent` at `at`.
static func pivot(parent: Node3D, at: Vector3, label: String) -> Node3D:
	var part := Node3D.new()
	part.name = label
	part.position = at
	parent.add_child(part)
	return part

## A sphere with fewer faces than the kit's, for small round parts; `height`
## stretches it (its diameter when left out).
static func low_sphere(radius: float, height: float = -1.0) -> Mesh:
	if height < 0.0: height = radius * 2.0
	var key := "sphere|%.4f|%.4f" % [radius, height]
	var cached: Mesh = _tori.get(key)
	if cached != null: return cached
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = height
	shape.radial_segments = 10
	shape.rings = 5
	_keep(key, shape)
	return shape

static func torus(radius: float, thick: float) -> Mesh:
	var key := "ring|%.4f|%.4f" % [radius, thick]
	var cached: Mesh = _tori.get(key)
	if cached != null: return cached
	var shape := TorusMesh.new()
	shape.inner_radius = radius - thick * 0.5
	shape.outer_radius = radius + thick * 0.5
	shape.rings = 16
	shape.ring_segments = 6
	_keep(key, shape)
	return shape

## Boxes ([size, middle] each) merged into one mesh, made once per `key`: see-
## through parts that would each be a draw of their own.
static func merged_boxes(key: String, boxes: Array) -> Mesh:
	var cached: Mesh = _tori.get("merged|" + key)
	if cached != null: return cached
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for item: Array in boxes: tool.append_from(Primitives.box_mesh(item[0]), 0, Transform3D(Basis.IDENTITY, item[1]))
	var mesh := tool.commit()
	_keep("merged|" + key, mesh)
	return mesh

static func _keep(key: String, mesh: Mesh) -> void:
	_tori[key] = mesh
	SessionRelease.on_exit(Callable(load("res://presentation/keepsakes/keepsake_parts.gd"), "release_cached"))

# --- the upgrade pieces --------------------------------------------------------------

## A Hard plinth, `width` by `depth` round `at`: two slate steps with the snowy
## Hard peak on the front, PLINTH_TOP high.
static func plinth(root: Node3D, width: float, depth: float, at: Vector3 = Vector3.ZERO) -> Node3D:
	var base := pivot(root, at, "Footing")
	box(base, Vector3(width, 0.14, depth), SLATE_DARK, Vector3(0, 0.07, 0))
	box(base, Vector3(width - 0.14, 0.1, depth - 0.14), SLATE, Vector3(0, 0.19, 0))
	prism(base, Vector3(0.3, 0.15, 0.03), SLATE, Vector3(0, 0.075, depth * 0.5 + 0.015))
	prism(base, Vector3(0.13, 0.065, 0.034), SNOW, Vector3(0, 0.115, depth * 0.5 + 0.017))
	return base

## A gold piece's look: glowing softly at rest, brightly while it plays.
static func gold(bright: bool = false) -> Material:
	return glow(GOLD_DEEP, 1.6 if bright else 0.45)

## A small gold ball (the Together Hard pieces' crown sparkle).
static func gold_ball(parent: Node3D, at: Vector3, radius: float) -> MeshInstance3D:
	return node(parent, low_sphere(radius), gold(), at)

## A gold vine from one point to another with `leaves` leaves.
static func gold_vine(parent: Node3D, from: Vector3, to: Vector3, leaves: int) -> void:
	bar(parent, from, to, 0.025, GOLD_DEEP)
	for index in range(leaves):
		var at := from.lerp(to, (index + 0.5) / leaves)
		var side := 1.0 if index % 2 == 0 else -1.0
		node(parent, low_sphere(0.057, 0.06), gold(), at + Vector3(0.05 * side, 0, 0.03), Vector3(0, 0, 0.6 * side))

## A node `size` times larger, for a keepsake drawn bigger than its pieces.
static func grown(parent: Node3D, size: float) -> Node3D:
	var part := pivot(parent, Vector3.ZERO, "Grown")
	part.scale = Vector3.ONE * size
	return part

# --- the started outline --------------------------------------------------------------

## The keepsake's base look (`state`, usually {}) merged into one mesh, built
## once per `key`.
static func outline_mesh(builder: RefCounted, key: String, state: Dictionary = {}) -> ArrayMesh:
	var cached: ArrayMesh = _outlines.get(key)
	if cached != null: return cached
	var model := Node3D.new()
	builder.build(model, state)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for found: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := found as MeshInstance3D
		var shape := part.mesh as PrimitiveMesh
		if shape == null: continue
		var relative := part.transform
		var parent := part.get_parent()
		while parent != model:
			relative = (parent as Node3D).transform * relative
			parent = parent.get_parent()
		var arrays := shape.get_mesh_arrays()
		var start := vertices.size()
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]: vertices.append(relative * vertex)
		var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if order.is_empty(): order = PackedInt32Array(range((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))
		for index: int in order: indices.append(start + index)
	model.free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	cached = ArrayMesh.new()
	if not vertices.is_empty(): cached.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_outlines[key] = cached
	SessionRelease.on_exit(Callable(load("res://presentation/keepsakes/keepsake_parts.gd"), "release_cached"))
	return cached

## The started or next look: the outline, and in front one dot per stage, lit
## peach for a stage done solo and mint for one done with a friend.
static func outline(root: Node3D, builder: RefCounted, key: String, stages: Array, state: Dictionary = {}) -> MeshInstance3D:
	var veil := Primitives.mesh_node(outline_mesh(builder, key, state), ghost(), Vector3.ZERO, root)
	veil.name = "Outline"
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for index in range(stages.size()):
		var stage: Array = stages[index]
		var color := DOT_FRIEND if stage[1] else (DOT_SOLO if stage[0] else DOT_DIM)
		var x := (index - (stages.size() - 1) * 0.5) * 0.17
		cyl(root, 0.055, 0.02, color, Vector3(x, 0.012, 0.6)).name = "StageDot"
	return veil
