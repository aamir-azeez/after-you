extends RefCounted
## World kit: a world's moving water. Each body of water is one mesh of its
## surface and the outer faces of its sides, under a root that moves and
## stretches with the level, so the water always reaches down to the seabed.
## No face stands inside the water, where it would show through the surface as
## a band. The mesh depends only on the body's rectangles and its holes, so it
## is worked out once per definition and shared (kit/definition_geometry.gd).
##
## The kit is a helper the world holds, never a node: everything it builds sits
## under the world's terrain, and the world calls it from its own build,
## present and frame steps. A staged build gives the frame back through the
## world's _build_step.
const Primitives = preload("res://presentation/kit/primitives.gd")
const DefinitionGeometry = preload("res://presentation/kit/definition_geometry.gd")
## Water grid lines worked out between two build steps.
const LINES_PER_STEP := 8

## The world that holds the kit: its terrain and its _build_step.
var host: Node3D
## Water stops this many cm short of what holds it on the sides the camera
## sees (east and south).
var inset := 3

func _init(world: Node3D) -> void:
	host = world

## One body of water named `name` over `regions` ([x0, z0, x1, z1] cm), minus
## every rectangle of `holes` (islands, walled crossings, a basin of its own),
## coloured `color`, under the world's terrain. The sides that face the camera
## (east and south) stop `inset` short of each hole and of the end of the body:
## inside the wall that holds the water back, or behind the sea wall past it,
## and never on a wall's inner face, where the two would fight over the same
## pixels. Returns the body's root. Await it.
func build_body(name: String, regions: Array, holes: Array, color: Color) -> Node3D:
	var cut: Array = []
	for rect: Array in holes: cut.append([int(rect[0]) - inset, int(rect[1]) - inset, rect[2], rect[3]])
	var key := [&"water_surface", regions, cut, inset]
	if not DefinitionGeometry.has(key): DefinitionGeometry.keep(key, await _surface(regions, cut))
	var mesh: Mesh = DefinitionGeometry.kept(key)
	var root := Node3D.new()
	root.name = name
	host.terrain.add_child(root)
	if mesh != null:
		var surface := Primitives.fresh_material(color, 0.35)
		# Labels, faded floors and the spout draw over the water, never under it.
		surface.render_priority = -2
		var water := Primitives.mesh_node(mesh, surface, Vector3.ZERO, root)
		water.name = "Water"
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

## The mesh of a body's surface and outer sides (see build_body), or null when
## it has no face. A staged build gets the frame back between grid lines. Await it.
func _surface(regions: Array, holes: Array) -> Mesh:
	var xs: Array = []
	var zs: Array = []
	for rect: Array in regions + holes:
		for x: int in [rect[0], rect[2]]:
			if x not in xs: xs.append(x)
		for z: int in [rect[1], rect[3]]:
			if z not in zs: zs.append(z)
	for region: Array in regions:
		if int(region[2]) - inset not in xs: xs.append(int(region[2]) - inset)
		if int(region[3]) - inset not in zs: zs.append(int(region[3]) - inset)
	xs.sort()
	zs.sort()
	# wet[zi][xi]: whether the cell between those grid lines holds water. A cell
	# within `inset` of where the body ends to its east or south stays dry.
	var wet: Array = []
	for zi in range(zs.size() - 1):
		if zi % LINES_PER_STEP == 0: await host._build_step()
		var row: Array[bool] = []
		for xi in range(xs.size() - 1):
			var east := float(xs[xi + 1] + inset)
			var south := float(zs[zi + 1] + inset)
			var x := float(xs[xi] + xs[xi + 1]) * 0.5
			var z := float(zs[zi] + zs[zi + 1]) * 0.5
			row.append(_wet(x, z, regions, holes) and covered(east, z, regions) and covered(x, south, regions) and covered(east, south, regions))
		wet.append(row)
	var shape := SurfaceTool.new()
	shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	# The surface, one quad per run of wet cells along each row.
	for zi in range(wet.size()):
		if zi % LINES_PER_STEP == 0: await host._build_step()
		var start := -1
		for xi in range(xs.size()):
			var here: bool = xi < xs.size() - 1 and wet[zi][xi]
			if here and start < 0: start = xi
			if not here and start >= 0:
				var x0 := float(xs[start]) / 100.0
				var x1 := float(xs[xi]) / 100.0
				var z0 := float(zs[zi]) / 100.0
				var z1 := float(zs[zi + 1]) / 100.0
				_quad(shape, [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)], Vector3.UP)
				faces += 1
				start = -1
	# Sides only where water meets something else, merged along each grid line.
	for along_x: bool in [true, false]:
		var lines: Array = zs if along_x else xs
		var cells: Array = xs if along_x else zs
		for line in range(lines.size()):
			if line % LINES_PER_STEP == 0: await host._build_step()
			var start := 0
			var facing := 0
			for cell in range(cells.size()):
				var side := 0
				if cell < cells.size() - 1:
					var before: bool = line > 0 and (wet[line - 1][cell] if along_x else wet[cell][line - 1])
					var after: bool = line < lines.size() - 1 and (wet[line][cell] if along_x else wet[cell][line])
					side = 1 if before and not after else -1 if after and not before else 0
				if side == facing: continue
				if facing != 0:
					var at := float(lines[line]) / 100.0
					var a := float(cells[start]) / 100.0
					var b := float(cells[cell]) / 100.0
					if along_x: _quad(shape, [Vector3(a, -1, at), Vector3(b, -1, at), Vector3(b, 0, at), Vector3(a, 0, at)], Vector3(0, 0, facing))
					else: _quad(shape, [Vector3(at, -1, a), Vector3(at, -1, b), Vector3(at, 0, b), Vector3(at, 0, a)], Vector3(facing, 0, 0))
					faces += 1
				start = cell
				facing = side
	return shape.commit() if faces > 0 else null

## One flat quad of water, its corners in order round it, wound to face along
## `normal` (Godot draws a triangle a, b, c whose (a - c) x (a - b) faces the eye).
static func _quad(shape: SurfaceTool, corners: Array, normal: Vector3) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	if (a - c).cross(a - b).dot(normal) < 0.0: corners.reverse()
	for index: int in [0, 1, 2, 0, 2, 3]:
		shape.set_normal(normal)
		shape.add_vertex(corners[index])

## Whether a point (cm) lies in one of `regions`, edges included.
static func covered(x: float, z: float, regions: Array) -> bool:
	for region: Array in regions:
		if x >= region[0] and x <= region[2] and z >= region[1] and z <= region[3]: return true
	return false

static func _wet(x: float, z: float, regions: Array, holes: Array) -> bool:
	var inside := false
	for region: Array in regions:
		if x > region[0] and x < region[2] and z > region[1] and z < region[3]: inside = true
	if not inside: return false
	for hole: Array in holes:
		if x > hole[0] and x < hole[2] and z > hole[1] and z < hole[3]: return false
	return true
