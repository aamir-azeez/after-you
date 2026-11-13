extends RefCounted
## The soft caps (hat): Rain cap, Wool cap and Mushroom, as the hats board
## draws them. One art script serves the three, each descriptor naming it; the
## look is picked by the worn hat's id from CAPS.
##
## Each cap is a shell laid over the head's top: every point stands off the
## head's surface along its normal, highest at the crown (RISE) and coming
## down to EDGE_GAP at its edge, EDGE radians from straight up. A Rain cap adds
## a broad brim sloping out from that edge (BRIM: its reach and its drop) with
## a darker underside and a cream seam; a Wool cap draws its knit ridges as
## bands of colour and rolls a pale cuff at its edge; a Mushroom adds three
## big cream spots and a pale green rim.
##
## Beside the leaf the shell comes down to a low lip (kit/wear_fit.gd
## LIP_LIMIT) and a real notch is cut where a leaf of the cap's "notch" class
## could swing (WearFit.leaf_in_the_way), so the leaf pokes through
## ("pokes_through"). The larger leaves its descriptor's "leaf_max" names are
## checked against the real notch, leaf by leaf, by tests/test_wear_fit.gd.
## One baked mesh per cap, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")
const WearFit = preload("res://presentation/kit/wear_fit.gd")
const Look = preload("res://presentation/spirit_look.gd")

## Each cap by item id:
##   rise, edge_gap: metres off the head at the crown's top and at its edge;
##   edge: where the crown ends (radians from straight up); round: how full
##     the crown stays before it comes down (higher keeps it fuller);
##   crown, under, trim: its colours (the brim's underside, the seam or rim);
##   brim: [reach, drop] in metres, or [] for none;
##   bands: the ridges' colour and the rows they colour (Wool cap), or [];
##   rim: the last, thin row: "band" in the trim colour (a seam), "roll" a
##     rolled cuff in the trim colour, or "" the crown's colour;
##   spots: [direction from the head's centre, half size] for each spot;
##   notch: the leaf class its notch is cut around.
const CAPS := {
	"rain_cap": {"rise": 0.125, "edge_gap": 0.012, "edge": 1.06, "round": 2.2, "crown": Color("93c5d3"), "under": Color("547f91"), "trim": Color("e8e9d7"),
		"brim": [0.072, 0.04], "bands": [], "rim": "band", "spots": [], "notch": WearFit.SMALL},
	"wool_cap": {"rise": 0.16, "edge_gap": 0.016, "edge": 1.2, "round": 2.0, "crown": Color("82728e"), "under": Color("82728e"), "trim": Color("c5aeb8"),
		"brim": [], "bands": [Color("6f607b"), [2, 4]], "rim": "roll", "spots": [], "notch": WearFit.SMALL},
	"mushroom": {"rise": 0.155, "edge_gap": 0.03, "edge": 1.06, "round": 3.0, "crown": Color("728d5d"), "under": Color("eee9d4"), "trim": Color("a5b777"),
		"brim": [0.05, 0.035], "bands": [], "rim": "", "notch": WearFit.SMALL,
		"spots": [[Vector3(0.22, 0.85, 0.6), 0.07], [Vector3(0.75, 0.6, 0.4), 0.055], [Vector3(-0.2, 0.6, 0.85), 0.05]]},
}
## Where each row of the crown lies from its top (0) to its edge (1); the
## last row is thin (a cuff or a rim). And the columns round it.
const ROW_AT: Array[float] = [0.08, 0.28, 0.47, 0.64, 0.8, 0.92, 1.0]
const COLUMNS := 16
## The brim's thickness (its top and underside meet at its outer edge).
const BRIM_THICK := 0.012
## The lip beside the leaf, a little under the limit, and how far round the
## stalk the shell comes down to it, from LEAF_SECTOR out to this many times it.
const LIP := WearFit.LIP_LIMIT * 0.7
const DIP_OUT := 1.3
## The cream spots: flat discs of SPOT_SIDES sides standing off the crown by
## SPOT_LIFT.
const SPOT_LIFT := 0.01
const SPOT_SIDES := 7
## How much the cuff rolls out past the crown.
const CUFF_ROLL := 0.012
## How far from the notch the crown rises from the lip back to its full
## height (metres).
const NOTCH_RISE := 0.16

static func wear(look: RefCounted) -> void:
	var id := str(look.outfit.get("hat", ""))
	if not CAPS.has(id): return
	look.mesh(look.head(), Kit.cached_mesh(id, _build.bind(id)), Kit.vertex_material())

static func _build(id: String) -> Mesh:
	var cap: Dictionary = CAPS[id]
	var largest: String = cap.notch
	# The crown's grid, row by row from the top: where each point is on the
	# head, whether a leaf could swing through it even at the lip's height
	# (cut).
	var surfaces: Array = []
	var cut: Array[PackedByteArray] = []
	for along: float in ROW_AT:
		var on_row: Array = []
		var cut_row := PackedByteArray()
		var phi := float(cap.edge) * along
		for column in range(COLUMNS):
			var beta := TAU * float(column) / float(COLUMNS)
			var on: Array[Vector3] = Meshes.head_surface(Vector3(sin(phi) * sin(beta), cos(phi), sin(phi) * cos(beta)))
			on_row.append([on[0], on[1], _height(cap, phi, on[0])])
			cut_row.append(1 if WearFit.leaf_in_the_way(on[0] + on[1] * LIP, largest) else 0)
		surfaces.append(on_row)
		cut.append(cut_row)
	var notch := PackedVector3Array()
	for row in range(ROW_AT.size()):
		for column in range(COLUMNS):
			if cut[row][column] == 1: notch.append(surfaces[row][column][0])
	# Round the notch the crown comes down to the lip and rises back to its
	# full height NOTCH_RISE metres away, so the notch's edge is low and clean.
	var rows: Array[PackedVector3Array] = []
	for row in range(ROW_AT.size()):
		var points := PackedVector3Array()
		for column in range(COLUMNS):
			var here: Array = surfaces[row][column]
			var point := _lowered(here[0], here[1], float(here[2]), notch)
			# Risen into a leaf's way after all: back down to the lip.
			if cut[row][column] == 0 and WearFit.leaf_in_the_way(point, largest): point = here[0] + here[1] * LIP
			points.append(point)
		rows.append(points)
	var last := ROW_AT.size() - 1
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Meshes.head_surface(Vector3.UP)
	var pole := _lowered(top[0], top[1], _height(cap, 0.0, top[0]), notch)
	for column in range(COLUMNS):
		var next := (column + 1) % COLUMNS
		var corners := [pole, rows[0][column], rows[0][next]]
		if cut[0][column] == 0 and cut[0][next] == 0: _triangle(surface, corners, _colour(cap, 0), _middle(corners))
	for row in range(last):
		for column in range(COLUMNS):
			var next := (column + 1) % COLUMNS
			var quad := [rows[row][column], rows[row][next], rows[row + 1][next], rows[row + 1][column]]
			if cut[row][column] + cut[row][next] + cut[row + 1][column] + cut[row + 1][next] > 0 or _cut(quad, largest): continue
			var colour := _colour(cap, row + 1)
			_triangle(surface, [quad[0], quad[1], quad[2]], colour, _middle(quad))
			_triangle(surface, [quad[0], quad[2], quad[3]], colour, _middle(quad))
	if not (cap.brim as Array).is_empty(): _brim(surface, cap, rows[last], largest)
	surface.index()
	surface.generate_normals()
	var parts := Kit.Parts.new()
	parts.add_painted(surface.commit(), Transform3D.IDENTITY)
	for spot: Array in cap.spots:
		# Laid on the shell itself (its own slope, from points either side).
		var direction := (spot[0] as Vector3).normalized()
		var at := _shell_at(cap, direction, notch)
		var side := direction.cross(Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT).normalized()
		var rise := side.cross(direction).normalized()
		var normal := (_shell_at(cap, (direction + side * 0.02).normalized(), notch) - _shell_at(cap, (direction - side * 0.02).normalized(), notch)).cross(_shell_at(cap, (direction + rise * 0.02).normalized(), notch) - _shell_at(cap, (direction - rise * 0.02).normalized(), notch)).normalized()
		if normal.dot(direction) < 0.0: normal = -normal
		at += normal * SPOT_LIFT
		var size := float(spot[1])
		var across := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		var along := across.cross(normal).normalized()
		var disc := PackedVector3Array()
		for corner in range(SPOT_SIDES):
			var angle := TAU * float(corner) / float(SPOT_SIDES)
			var next := TAU * float(corner + 1) / float(SPOT_SIDES)
			disc.append_array(PackedVector3Array([at, at + (across * cos(angle) + along * sin(angle)) * size, at + (across * cos(next) + along * sin(next)) * size]))
		parts.facets(cap.under, disc, at - normal)
	return parts.commit()

## How far the shell stands off the head at angle `phi` from straight up,
## over head point `at`: full at the crown, down to the edge gap at the edge,
## and down to the lip beside the leaf.
static func _height(cap: Dictionary, phi: float, at: Vector3) -> float:
	var t := clampf(phi / float(cap.edge), 0.0, 1.0)
	var full := float(cap.edge_gap) + (float(cap.rise) - float(cap.edge_gap)) * (1.0 - pow(t, float(cap.round)))
	if cap.rim == "roll" and t > ROW_AT[ROW_AT.size() - 2] + 0.01: full += CUFF_ROLL
	var stalk := Vector2(at.x - Look.LEAF_PIVOT.x, at.z - Look.LEAF_PIVOT.z)
	var near := smoothstep(WearFit.LEAF_SECTOR, WearFit.LEAF_SECTOR * DIP_OUT, stalk.length())
	return minf(full, lerpf(LIP, full, near))

## The shell's point in `direction` from the head's centre.
static func _shell_at(cap: Dictionary, direction: Vector3, notch: PackedVector3Array) -> Vector3:
	var on: Array[Vector3] = Meshes.head_surface(direction)
	return _lowered(on[0], on[1], _height(cap, direction.angle_to(Vector3.UP), on[0]), notch)

## The crown's point over head point `at` (outward `normal`) of full height
## `full`, brought down toward the lip as it nears the notch's points.
static func _lowered(at: Vector3, normal: Vector3, full: float, notch: PackedVector3Array) -> Vector3:
	var nearest := INF
	for point: Vector3 in notch: nearest = minf(nearest, at.distance_to(point))
	return at + normal * lerpf(LIP, full, smoothstep(0.0, NOTCH_RISE, nearest))

## Row `row`'s colour (0 the top): its rim, a Wool cap's knit ridges in
## bands of colour, the crown's colour otherwise.
static func _colour(cap: Dictionary, row: int) -> Color:
	if not str(cap.rim).is_empty() and row == ROW_AT.size() - 1: return cap.trim
	var bands: Array = cap.bands
	if not bands.is_empty() and row in bands[1]: return bands[0]
	return cap.crown

## The brim from the crown's edge ring: a top sloping out and down in the
## crown's colour (a Mushroom's in its pale rim colour) and a darker underside
## tucked under the crown's edge, meeting at its outer edge.
static func _brim(surface: SurfaceTool, cap: Dictionary, edge: PackedVector3Array, largest: String) -> void:
	var reach := float(cap.brim[0])
	var drop := float(cap.brim[1])
	var top_colour: Color = cap.trim if (cap.spots as Array).size() > 0 else cap.crown
	var outer := PackedVector3Array()
	var under := PackedVector3Array()
	var inner_under := PackedVector3Array()
	for point: Vector3 in edge:
		var out := Vector3(point.x, 0.0, point.z).normalized()
		outer.append(point + out * reach + Vector3.DOWN * drop)
		under.append(point + out * reach + Vector3.DOWN * drop)
		inner_under.append(point + Vector3.DOWN * BRIM_THICK - out * 0.006)
	for column in range(COLUMNS):
		var next := (column + 1) % COLUMNS
		var top := [edge[column], edge[next], outer[next], outer[column]]
		if _cut(top, largest): continue
		_triangle(surface, [top[0], top[1], top[2]], top_colour, Vector3.UP)
		_triangle(surface, [top[0], top[2], top[3]], top_colour, Vector3.UP)
		_triangle(surface, [inner_under[column], inner_under[next], under[next]], cap.under, Vector3.DOWN)
		_triangle(surface, [inner_under[column], under[next], under[column]], cap.under, Vector3.DOWN)

## Whether any corner of a face is where a leaf the cap takes could swing.
static func _cut(corners: Array, largest: String) -> bool:
	var middle := Vector3.ZERO
	for corner: Vector3 in corners:
		if WearFit.leaf_in_the_way(corner, largest): return true
		middle += corner
	return WearFit.leaf_in_the_way(middle / float(corners.size()), largest)

## A face's middle: from the head's centre it points the way the face looks.
static func _middle(corners: Array) -> Vector3:
	var sum := Vector3.ZERO
	for corner: Vector3 in corners: sum += corner
	return sum / float(corners.size())

## One triangle in `colour`, wound to face the way `out` points.
static func _triangle(surface: SurfaceTool, corners: Array, colour: Color, out: Vector3) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	# Godot's front faces wind clockwise: the cross product points in.
	if (b - a).cross(c - a).dot(out) > 0.0:
		var swap := b
		b = c
		c = swap
	surface.set_color(colour)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
