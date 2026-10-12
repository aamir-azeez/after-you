extends RefCounted
## World kit: warm ground styles for a walkable island. The visible top is
## exactly the authored rectangle at the parent's height; trims and the rock
## below stay outside or under it, so nothing new looks walkable.

const Primitives = preload("res://presentation/kit/primitives.gd")

const STYLES := {
	# Meadow grass over a soil band and warm sandstone.
	"grass": {"top": Color("7fa564"), "trim": Color("94b878"), "skirt": Color("62894f"), "band": Color("8a6b4e"), "rock": Color("b49a76"), "lines": ""},
	# A raised plank deck on beams, with no rock below: supports come from posts.
	"deck": {"top": Color("a07a55"), "trim": Color("8a6b4e"), "skirt": Color("7a5c40"), "band": Color("6b5038"), "rock": Color("a88f6c"), "lines": "x", "line": Color("8f6d4d"), "spacing": 0.36, "rockless": true},
	# Plank decking.
	"timber": {"top": Color("a8835c"), "trim": Color("8a6b4e"), "skirt": Color("7a5c40"), "band": Color("6b5038"), "rock": Color("a88f6c"), "lines": "x", "line": Color("8f6d4d"), "spacing": 0.36},
	# Cream and terracotta tiles.
	"tile": {"top": Color("d6bb98"), "trim": Color("c08a62"), "skirt": Color("b07a55"), "band": Color("9c7a5a"), "rock": Color("b49a76"), "lines": "xz", "line": Color("f0e2c8"), "spacing": 0.64},
	# Warm sandstone flags.
	"sandstone": {"top": Color("d3bc94"), "trim": Color("e2d0ad"), "skirt": Color("b39a74"), "band": Color("9c835f"), "rock": Color("a68d69"), "lines": "xz", "line": Color("bba27c"), "spacing": 0.9},
	# Harbour stone with a mossy lip, for the Lighthouse at dusk.
	"harbour": {"top": Color("a89f8e"), "trim": Color("8fa56c"), "skirt": Color("7d9460"), "band": Color("8c7b63"), "rock": Color("8f7f68"), "lines": "xz", "line": Color("9c8d74"), "spacing": 1.1},
	# Pale harbour sand with a darker wet edge.
	"sand": {"top": Color("e6d6ac"), "trim": Color("ad9870"), "skirt": Color("b39d74"), "band": Color("9c835f"), "rock": Color("a68d69"), "lines": ""},
	# Terracotta flags with a brick coping.
	"terracotta": {"top": Color("d39c74"), "trim": Color("a5553a"), "skirt": Color("b87a58"), "band": Color("9a5f45"), "rock": Color("a68d69"), "lines": "xz", "line": Color("c08560"), "spacing": 0.6},
	# Warm honey granite cobbles with a timber edge.
	"honey_cobble": {"top": Color("a77b45"), "trim": Color("6b4f37"), "skirt": Color("8a6638"), "band": Color("7a5a35"), "rock": Color("8f7f68"), "lines": "xz", "line": Color("8e6636"), "spacing": 0.32},
}

static func has_style(name: String) -> bool:
	return STYLES.has(name)

## Builds the island's floor in the named style under parent (whose origin is
## the island's height). Node names match the plain shore: <id>Floor and
## <id>LowerRock.
static func build(island: Dictionary, style_name: String, parent: Node3D, with_rock: bool = true) -> void:
	var style: Dictionary = STYLES[style_name]
	var r: Array = island.rect_cm
	var width := float(r[2] - r[0]) / 100.0
	var depth := float(r[3] - r[1]) / 100.0
	var center := Vector3(float(r[0] + r[2]) / 200.0, 0, float(r[1] + r[3]) / 200.0)
	var floor := Primitives.mesh_node(Primitives.box_mesh(Vector3(width, 0.20, depth)), Primitives.shared_material(style.top), center + Vector3(0, -0.10, 0), parent)
	floor.name = str(island.id) + "Floor"
	# A soft lip just outside the rectangle, a little below the walking surface.
	Primitives.mesh_node(Primitives.box_mesh(Vector3(width + 0.10, 0.12, depth + 0.10)), Primitives.shared_material(style.skirt), center + Vector3(0, -0.085, 0), parent)
	Primitives.mesh_node(Primitives.box_mesh(Vector3(width + 0.04, 0.12, depth + 0.04)), Primitives.shared_material(style.band), center + Vector3(0, -0.24, 0), parent)
	# Trims start at the walking surface, so their outer faces never share the
	# floor's sides (coplanar faces flicker as the camera moves).
	for side in [-1, 1]:
		Primitives.mesh_node(Primitives.box_mesh(Vector3(width, 0.014, 0.04)), Primitives.shared_material(style.trim), center + Vector3(0, 0.007, side * (depth / 2.0 - 0.02)), parent)
		Primitives.mesh_node(Primitives.box_mesh(Vector3(0.04, 0.014, depth)), Primitives.shared_material(style.trim), center + Vector3(side * (width / 2.0 - 0.02), 0.007, 0), parent)
	var lines := str(style.lines)
	if lines.contains("x"):
		var spacing := float(style.spacing)
		var x := -width / 2.0 + spacing
		while x < width / 2.0 - 0.05:
			Primitives.mesh_node(Primitives.box_mesh(Vector3(0.012, 0.006, depth - 0.06)), Primitives.shared_material(style.line), center + Vector3(x, 0.003, 0), parent)
			x += spacing
	if lines.contains("z"):
		var spacing := float(style.spacing)
		var z := -depth / 2.0 + spacing
		while z < depth / 2.0 - 0.05:
			Primitives.mesh_node(Primitives.box_mesh(Vector3(width - 0.06, 0.006, 0.012)), Primitives.shared_material(style.line), center + Vector3(0, 0.003, z), parent)
			z += spacing
	if not with_rock or style.get("rockless", false):
		for z_side in [-1, 1]:
			Primitives.mesh_node(Primitives.box_mesh(Vector3(width - 0.1, 0.16, 0.12)), Primitives.shared_material(style.skirt), center + Vector3(0, -0.36, z_side * (depth / 2.0 - 0.3)), parent)
		return
	var rock := lower_rock(center, width, depth, style.rock)
	rock.name = str(island.id) + "LowerRock"
	parent.add_child(rock)

## The tapered floating rock under an island, shaded per face.
static func lower_rock(center: Vector3, width: float, depth: float, color: Color) -> MeshInstance3D:
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for corner: Vector2 in corners:
		top.append(center + Vector3(corner.x * width * 0.49, -0.30, corner.y * depth * 0.49))
		bottom.append(center + Vector3(corner.x * width * 0.22, -1.45, corner.y * depth * 0.24))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for index in range(4):
		var next := (index + 1) % 4
		_triangle(surface, top[index], bottom[index], bottom[next], color.darkened(0.12 + 0.035 * index))
		_triangle(surface, top[index], bottom[next], top[next], color.darkened(0.12 + 0.035 * index))
		_triangle(surface, bottom[index], center + Vector3(0, -1.62, 0), bottom[next], color.darkened(0.3))
	surface.generate_normals()
	var mat := Primitives.fresh_material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	node.material_override = mat
	return node

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
