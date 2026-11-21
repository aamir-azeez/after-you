extends RefCounted
## World kit: warm ground styles for a walkable island. The visible top is
## the island's drawn shape at the parent's height: its rectangle reaching
## past the walkable edge by what the drawn pip reaches over it
## (kit/walk_reach.gd), cut round its neighbours; trims run along that shape's
## outer edges and the rock stays under the walkable rectangle.
## Every piece but the rock is one of the kit's cached boxes (nothing resizes
## a floor), so a chapter opened again makes none of them again (while the
## kit keeps them, Primitives.KEPT_SHAPES).

const Primitives = preload("res://presentation/kit/primitives.gd")
const WalkReach = preload("res://presentation/kit/walk_reach.gd")

const STYLES := {
	# Meadow grass over a soil band and warm sandstone. A floating shell under
	# it (island_world.gd _island_shell) runs the band down into deeper soil, a
	# darker underside and roots.
	"grass": {"top": Color("7fa564"), "trim": Color("94b878"), "skirt": Color("62894f"), "band": Color("8a6b4e"), "rock": Color("b49a76"), "lines": "",
		"soil": Color("6f5440"), "underside": Color("533e2d"), "root": Color("4a3729")},
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
	# The Falls: mossy flagstones with a green lip, and pale river stone.
	"mossy_flags": {"top": Color("939c70"), "trim": Color("7d9460"), "skirt": Color("6f8456"), "band": Color("7c7a66"), "rock": Color("7f7d6c"), "lines": "xz", "line": Color("838d63"), "spacing": 0.5},
	"river_stone": {"top": Color("c4bea8"), "trim": Color("a9a48c"), "skirt": Color("9d987f"), "band": Color("8a8670"), "rock": Color("8a8670"), "lines": "xz", "line": Color("b0aa93"), "spacing": 0.9},
	# Fog Marsh: weathered boardwalk planks, every other one a shade darker,
	# with butt joints staggered along them ("alt", "joints"), and a reedy mud bank.
	"boardwalk": {"top": Color("c2a77f"), "trim": Color("8c7656"), "skirt": Color("7a6548"), "band": Color("5f4f3b"), "rock": Color("8a7d63"), "lines": "x", "line": Color("7f694b"), "spacing": 0.3,
		"alt": Color("b0956c"), "joints": 1.1},
	"reed_bank": {"top": Color("aaa27e"), "trim": Color("8f8a64"), "skirt": Color("7f7a58"), "band": Color("6f6548"), "rock": Color("7f7660"), "lines": ""},
}

static func has_style(name: String) -> bool:
	return STYLES.has(name)

## The style's soil for a floating shell (band, soil, underside and root
## colours); {} for a style with none.
static func soil(name: String) -> Dictionary:
	var style: Dictionary = STYLES.get(name, {})
	return style if style.has("soil") else {}

## Builds the island's floor in the named style under parent (whose origin is
## the island's height), as `shape`: the rectangles (cm) it is drawn as
## (WalkReach.pieces), its own rectangle when left empty. Node names match the
## plain shore: <id>Floor (the first piece's top) and <id>LowerRock.
static func build(island: Dictionary, style_name: String, parent: Node3D, with_rock: bool = true, shape: Array = []) -> void:
	var style: Dictionary = STYLES[style_name]
	if shape.is_empty(): shape = [island.rect_cm]
	var whole: Array = shape[0].duplicate()
	for piece: Array in shape:
		whole = [mini(whole[0], piece[0]), mini(whole[1], piece[1]), maxi(whole[2], piece[2]), maxi(whole[3], piece[3])]
	# Seams and planks line up across the pieces from the walkable
	# rectangle's corner, where the pieces laid on the floor are placed from.
	var origin := Vector2(float(island.rect_cm[0]), float(island.rect_cm[1])) / 100.0
	for index in range(shape.size()):
		var r: Array = shape[index]
		# Each side: on the whole shape's bounds (1), met by another piece (0),
		# or cut round a neighbour (-1).
		var outer := outer_sides(r, shape)
		var sides: Array = range(4).map(func(side: int) -> int: return (1 if r[side] == whole[side] else -1) if outer[side] else 0)
		# The top runs a centimetre into the next piece's (one look, so no
		# seam), so its side there never lies on what stands by the join.
		var low := Vector2(float(r[0]) / 100.0 - (0.01 if sides[0] == 0 else 0.0), float(r[1]) / 100.0 - (0.01 if sides[1] == 0 else 0.0))
		var high := Vector2(float(r[2]) / 100.0 + (0.01 if sides[2] == 0 else 0.0), float(r[3]) / 100.0 + (0.01 if sides[3] == 0 else 0.0))
		var floor := Primitives.mesh_node(Primitives.cached_box(Vector3(high.x - low.x, 0.20, high.y - low.y)), Primitives.shared_material(style.top), Vector3((low.x + high.x) * 0.5, -0.10, (low.y + high.y) * 0.5), parent)
		if index == 0: floor.name = str(island.id) + "Floor"
		# A soft lip just outside the shape, a little below the walking surface,
		# grown only past the piece's sides on the bounds. Where another piece
		# meets a side, the two would overlap in one plane; a cut side stays
		# clear of what stands there and of the wall a world stands a
		# centimetre in under it.
		# The skirt grows 5 cm; the band 1, short of a neighbour's cut round
		# this floor (WalkReach NOTCH_CLEAR_CM) and of the water marks round a
		# wall under it (1.5).
		_grown(r, sides, 0.05, 0.12, -0.085, style.skirt, parent)
		_grown(r, sides, 0.01, 0.12, -0.24, style.band, parent)
		var lines := str(style.lines)
		if lines.contains("x"): _seams(style, r, origin, true, parent)
		if lines == "x" and style.has("alt"): _planks(style, r, origin, parent)
		if lines.contains("z"): _seams(style, r, origin, false, parent)
	# Trims start at the walking surface, so their outer faces never share the
	# floor's sides (coplanar faces flicker as the camera moves), and stand a
	# centimetre in from the edge, clear of a deck, tread or lock wall there. They
	# run along the shape's outer edges only, each a centimetre short of its
	# ends, so an end never lies on the face of what stands at a corner (a
	# hatch's rim, a post, a frame).
	for edge: Array in joined(WalkReach.outline(shape)):
		var span: Array = edge[0]
		var length := (float(span[1]) - float(span[0])) / 100.0 - 0.02
		var middle := (float(span[0]) + float(span[1])) / 200.0
		var line := float(edge[1]) / 100.0 - float(edge[2]) * 0.03
		var along_x: bool = edge[3]
		Primitives.mesh_node(Primitives.cached_box(Vector3(length, TRIM_TOP, 0.04) if along_x else Vector3(0.04, TRIM_TOP, length)), Primitives.shared_material(style.trim), Vector3(middle, TRIM_TOP * 0.5, line) if along_x else Vector3(line, TRIM_TOP * 0.5, middle), parent)
	# The skirts of a rockless floor run under the whole drawn shape; the rock
	# stays under the walkable rectangle.
	if not with_rock or style.get("rockless", false):
		var span := Vector2(float(whole[2] - whole[0]), float(whole[3] - whole[1])) / 100.0
		var middle := Vector3(float(whole[0] + whole[2]) / 200.0, 0, float(whole[1] + whole[3]) / 200.0)
		# Half a centimetre off the whole centimetres the pieces and their lips end on.
		for z_side in [-1, 1]:
			Primitives.mesh_node(Primitives.cached_box(Vector3(span.x - 0.1, 0.16, 0.12)), Primitives.shared_material(style.skirt), middle + Vector3(0, -0.36, z_side * (span.y / 2.0 - 0.295)), parent)
		return
	# A floor round an opening names the rectangles its rock stands under ("rocks_cm").
	for a: Array in island.get("rocks_cm", [island.rect_cm]):
		var width := float(a[2] - a[0]) / 100.0
		var depth := float(a[3] - a[1]) / 100.0
		var center := Vector3(float(a[0] + a[2]) / 200.0, 0, float(a[1] + a[3]) / 200.0)
		var rock := lower_rock(center, width, depth, style.rock)
		if not parent.has_node(str(island.id) + "LowerRock"): rock.name = str(island.id) + "LowerRock"
		parent.add_child(rock)

## `edges` (WalkReach outline) with the stretches of one line that meet end
## to end joined into one.
static func joined(edges: Array) -> Array:
	var sorted := edges.duplicate(true)
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return [int(a[3]), float(a[1]), float(a[2]), float(a[0][0])] < [int(b[3]), float(b[1]), float(b[2]), float(b[0][0])])
	var found: Array = []
	for edge: Array in sorted:
		var last: Array = found[-1] if not found.is_empty() else []
		if not last.is_empty() and last[1] == edge[1] and last[2] == edge[2] and last[3] == edge[3] and float(last[0][1]) == float(edge[0][0]): last[0] = [last[0][0], edge[0][1]]
		else: found.append(edge)
	return found

## Which sides of `piece` (west, north, east, south) no other piece of
## `shape` meets.
static func outer_sides(piece: Array, shape: Array) -> Array:
	var outer := [true, true, true, true]
	for other: Array in shape:
		if other == piece: continue
		for side in range(4):
			var along := 1 - side % 2
			if other[(side + 2) % 4] == piece[side] and other[along] < piece[along + 2] and other[along + 2] > piece[along]: outer[side] = false
	return outer

## A box `tall` high centred `y` under `piece` (cm), grown `grow` (m) past
## each side `sides` marks 1, a centimetre short of each it marks 0 and two
## short of each it marks -1, so no face of it lies on the piece's own sides,
## on the next piece's lip or on a wall under a cut.
static func _grown(piece: Array, sides: Array, grow: float, tall: float, y: float, color: Color, parent: Node3D) -> void:
	var by: Array = sides.map(func(side: int) -> float: return grow if side == 1 else -0.01 if side == 0 else -0.02)
	var low := Vector2(float(piece[0]) / 100.0 - by[0], float(piece[1]) / 100.0 - by[1])
	var high := Vector2(float(piece[2]) / 100.0 + by[2], float(piece[3]) / 100.0 + by[3])
	# A sliver of a piece has no lip under it.
	if high.x - low.x < 0.01 or high.y - low.y < 0.01: return
	Primitives.mesh_node(Primitives.cached_box(Vector3(high.x - low.x, tall, high.y - low.y)), Primitives.shared_material(color), Vector3((low.x + high.x) * 0.5, y, (low.y + high.y) * 0.5), parent)

## The seam lines of an "x" (along_x: lines across x, every "spacing" along
## it) or "z" style over the piece `r` (cm), counted from `origin` (m), each
## short of the piece's edges.
static func _seams(style: Dictionary, r: Array, origin: Vector2, along_x: bool, parent: Node3D) -> void:
	var spacing := float(style.spacing)
	var low := Vector2(float(r[0]), float(r[1])) / 100.0
	var high := Vector2(float(r[2]), float(r[3])) / 100.0
	var axis := 0 if along_x else 1
	var at := origin[axis] + spacing * ceilf((low[axis] + 0.05 - origin[axis]) / spacing)
	if is_equal_approx(at, low[axis]): at += spacing
	while at < high[axis] - 0.05:
		var size := Vector3(0.012, 0.006, high.y - low.y - 0.06) if along_x else Vector3(high.x - low.x - 0.06, 0.006, 0.012)
		var center := Vector3(at, 0.003, (low.y + high.y) * 0.5) if along_x else Vector3((low.x + high.x) * 0.5, 0.003, at)
		Primitives.mesh_node(Primitives.cached_box(size), Primitives.shared_material(style.line), center, parent)
		at += spacing

## The trims' top over the floor (m), and the lowest a step laid over a
## floor's edge stands: clear of the trims by more than the depth buffer
## tells apart (test_dressing_lint min_gap).
const TRIM_TOP := 0.014
const DECAL_TOP := TRIM_TOP + 0.006

## Planks between the seams of an "x" style: every other one a shade darker
## (its top PLANK_TOP over the floor, clear of the seams' and the trims'
## tops), and a butt joint across each light plank every "joints" metres,
## staggered plank to plank, level with the seams. Each stops short of the
## seams and trims, so no face meets theirs. A joint over a dark plank would
## rise to the height of the pieces laid on the floor (a stand spot's disc).
const PLANK_TOP := 0.010
const JOINT_TOP := 0.006

static func _planks(style: Dictionary, r: Array, origin: Vector2, parent: Node3D) -> void:
	var spacing := float(style.spacing)
	var joints := float(style.get("joints", 0.0))
	var low := Vector2(float(r[0]), float(r[1])) / 100.0
	var high := Vector2(float(r[2]), float(r[3])) / 100.0
	var depth := high.y - low.y
	var middle_z := (low.y + high.y) * 0.5
	# Counted from the whole floor's corner, so the light and dark planks carry
	# on from piece to piece.
	var index := int(ceilf((low.x + 0.05 - origin.x) / spacing))
	var x := origin.x + spacing * float(index)
	if is_equal_approx(x, low.x):
		x += spacing
		index += 1
	index -= 1
	while x + spacing < high.x - 0.05:
		var middle := x + spacing * 0.5
		var dark := posmod(index, 2) == 1
		if dark: Primitives.mesh_node(Primitives.cached_box(Vector3(spacing - 0.03, PLANK_TOP, depth - 0.10)), Primitives.shared_material(style.alt), Vector3(middle, PLANK_TOP * 0.5, middle_z), parent)
		if joints > 0.0 and not dark:
			var top := JOINT_TOP
			var z := low.y + joints * (0.35 + 0.5 * float(posmod(index, 3)) / 2.0)
			while z < high.y - 0.15:
				Primitives.mesh_node(Primitives.cached_box(Vector3(spacing - 0.04, top, 0.012)), Primitives.shared_material(style.line), Vector3(middle, top * 0.5, z), parent)
				z += joints
		x += spacing
		index += 1

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
