extends RefCounted
## Fruit cap (hat): a plush Fruit hood, as a pet's fruit costume hood is made:
## a soft round shell in the Fruit's rose that wraps the whole head (its top,
## sides and back, down to the jaw) with a round opening for the face, quilted
## in diamonds, and the Fruit's green on top: a collar, the stem and its leaf,
## and two short leaves. The rose and the green are the Fruit's own
## (kit/fruit_mark.gd).
##
## The shell is a rounded box puffier than the head all round, so no part of it
## is inside the head (test_pip_outfit checks). The face opening cuts it from
## just over the eyes down past the cheeks, and the jaw line cuts it below; a
## rolled rim runs along that cut and tucks in against the head, so no gap
## shows. The quilting costs no triangles: the shell's grid is split along its
## diagonals into diamonds, each puffed a little and shaded on its own, its
## seams a touch darker.
##
## The collar stands where a carried seed rests, so the hood lifts the seed
## (pip_outfit.gd lift_seed). Its stem and leaf stand in for the pip's own
## leaf, which hides while it is worn. A worn leaf item still shows, raised by
## the descriptor's "leaf_lift" so its stalk starts under the hood's top and
## its blade grows out clear of it. One baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const FruitMark = preload("res://presentation/kit/fruit_mark.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

## The shell's rose: this far from the Fruit's light rose toward its deep one.
## The rim is a little lighter, the seams and the collar a little deeper.
const ROSE_DEPTH := 0.45
const RIM_LIGHT := 0.2
const SEAM_SHADE := 0.12
const COLLAR_SHADE := 0.12
const GREEN := FruitMark.GREEN
## The shell, in head space: a rounded box (POWER) of these half sizes about
## CENTER, a little higher than the head's middle so it is fullest on top.
const CENTER := Vector3(0.0, 0.02, -0.005)
const HALF := Vector3(0.395, 0.335, 0.365)
const POWER := 2.5
## The face opening seen from the front: a rounded oblong (FACE_POWER) of half
## size FACE_HALF about height FACE_Y. Its top is just over the eyes and its
## sides past the cheeks, clear of the eyes even at their farthest glance;
## below, it runs open into the jaw line.
const FACE_HALF := Vector2(0.325, 0.31)
const FACE_Y := -0.115
const FACE_POWER := 3.0
## The jaw line: the hood's lower edge at the sides (x) and at the back (y).
const JAW := Vector2(-0.2, -0.215)
## The shell's columns, in degrees round from the front (the other side
## mirrors them): close together at the face's corners, so the opening's
## sides run straight down. An even count, so the diamonds meet round the back.
const COLUMNS: Array[float] = [0.0, 15.0, 28.0, 37.0, 44.0, 50.0, 56.0, 66.0, 80.0, 96.0, 115.0, 135.0, 157.0, 180.0]
## Rows from under the collar down to the cut, and where the shell starts:
## this many radians from straight up, inside the collar.
const ROWS := 7
const TOP_ANGLE := 0.21
## The quilting: each diamond's middle stands out this far, its seams sink in
## this far.
const PUFF := 0.008
const PINCH := 0.003
## The rolled rim: from the cut it bows out past it by ROLL and comes back in
## to just off the head (TUCK), in ROLL_STEPS steps.
const ROLL := 0.025
const TUCK := 0.004
const ROLL_STEPS := 2
## The collar, a short green cuff narrowing to its top, over the shell's top.
const COLLAR_AT := Vector3(0.0, 0.37, -0.005)
const COLLAR_RADIUS := Vector2(0.1, 0.084)
const COLLAR_HEIGHT := 0.08
## The stem, from inside the collar up and a little to the right, and the
## leaf off its tip, its broad side turned toward the front.
const STEM: Array[Vector3] = [Vector3(0.0, 0.4, -0.008), Vector3(0.008, 0.442, -0.01), Vector3(0.028, 0.472, -0.013)]
const STEM_RADIUS := 0.017
const LEAF_AT := Vector3(0.1, 0.486, -0.015)
const LEAF_SIZE := Vector3(0.082, 0.014, 0.048)
const LEAF_TURN := Vector3(0.9, 0.25, 0.42)
## Two short leaves from the collar, leaning out to the front and the back,
## clear of a worn leaf at the top left: [middle, half size, turn].
const SEPALS: Array = [
	[Vector3(-0.045, 0.43, 0.05), Vector3(0.03, 0.062, 0.012), Vector3(0.8, 0.0, 0.35)],
	[Vector3(0.035, 0.43, -0.06), Vector3(0.03, 0.062, 0.012), Vector3(-0.8, 0.0, -0.3)],
]
## Metres a carried seed sits higher, so it clears the collar, stem and leaf.
const SEED_LIFT := 0.165

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("fruit_cap", _build), Kit.vertex_material())
	if not look.outfit.has("leaf"): look.hide_leaf()
	look.lift_seed(SEED_LIFT)

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.cylinder(GREEN.darkened(COLLAR_SHADE), COLLAR_AT, COLLAR_RADIUS.x, COLLAR_HEIGHT, COLLAR_RADIUS.y, Vector3.ZERO, 10)
	for index in range(STEM.size() - 1): parts.rod(GREEN, STEM[index], STEM[index + 1], STEM_RADIUS)
	parts.blob(GREEN, LEAF_AT, LEAF_SIZE, LEAF_TURN, 8, 3)
	for sepal: Array in SEPALS: parts.blob(GREEN, sepal[0], sepal[1], sepal[2], 5, 1)
	var surface := SurfaceTool.new()
	surface.append_from(_shell(), 0, Transform3D.IDENTITY)
	surface.append_from(parts.commit(), 0, Transform3D.IDENTITY)
	return surface.commit()

## The shell's outer height over head-space `point` (its x and z), on its top
## half and with the quilting's puff, or -INF past it (tests check a worn leaf
## grows out of the hood and never cuts into it).
static func top_height(point: Vector3) -> float:
	var left := 1.0 - pow(absf((point.x - CENTER.x) / HALF.x), POWER) - pow(absf((point.z - CENTER.z) / HALF.z), POWER)
	if left <= 0.0: return -INF
	return CENTER.y + HALF.y * pow(left, 1.0 / POWER) + PUFF

## The shell's surface at `lon` round from the front and `lat` down from the
## top (radians, about CENTER).
static func _point(lon: float, lat: float) -> Vector3:
	var direction := Vector3(sin(lat) * sin(lon), cos(lat), sin(lat) * cos(lon))
	var sum := pow(absf(direction.x / HALF.x), POWER) + pow(absf(direction.y / HALF.y), POWER) + pow(absf(direction.z / HALF.z), POWER)
	return CENTER + direction * pow(sum, -1.0 / POWER)

static func _normal(point: Vector3) -> Vector3:
	var from := point - CENTER
	return Vector3(
		signf(from.x) * pow(absf(from.x / HALF.x), POWER - 1.0) / HALF.x,
		signf(from.y) * pow(absf(from.y / HALF.y), POWER - 1.0) / HALF.y,
		signf(from.z) * pow(absf(from.z / HALF.z), POWER - 1.0) / HALF.z).normalized()

## How far into the face opening `point` is (below 1 inside), or INF behind
## the face.
static func _face(point: Vector3) -> float:
	if point.z <= 0.0: return INF
	return pow(absf(point.x / FACE_HALF.x), FACE_POWER) + pow(absf((point.y - FACE_Y) / FACE_HALF.y), FACE_POWER)

static func _jaw(lon: float) -> float:
	return lerpf(JAW.x, JAW.y, (1.0 - cos(lon)) * 0.5)

static func _is_open(lon: float, lat: float) -> bool:
	var point := _point(lon, lat)
	return point.y < _jaw(lon) or _face(point) < 1.0

## Where the column at `lon` meets the cut: the first latitude from the top
## that is open (the face or below the jaw).
static func _cut(lon: float) -> float:
	var step := 0.02
	var lat := TOP_ANGLE
	while lat < PI and not _is_open(lon, lat + step): lat += step
	var high := minf(lat + step, PI)
	for index in range(24):
		var middle := (lat + high) * 0.5
		if _is_open(lon, middle): high = middle
		else: lat = middle
	return lat

## Every column's longitude, round from the front, the far side mirrored.
static func _longitudes() -> PackedFloat32Array:
	var made := PackedFloat32Array()
	for degrees: float in COLUMNS: made.append(deg_to_rad(degrees))
	for index in range(COLUMNS.size() - 2, 0, -1): made.append(TAU - deg_to_rad(COLUMNS[index]))
	return made

## The rim at a cut point `at`, on the column at `lon` cut at `cut`: from it,
## bowing out past the cut (into the face opening, or down under the jaw),
## back in to just off the head.
static func _roll(at: Vector3, lon: float, cut: float) -> PackedVector3Array:
	var head := Meshes.head_surface(at)
	var tucked: Vector3 = head[0] + head[1] * TUCK
	var normal := _normal(at)
	var out := Vector3.DOWN
	if _point(lon, cut + 0.01).y >= _jaw(lon):
		# Cut by the face: toward the opening's middle, against its outline.
		out = -Vector3(signf(at.x) * pow(absf(at.x / FACE_HALF.x), FACE_POWER - 1.0) / FACE_HALF.x, signf(at.y - FACE_Y) * pow(absf((at.y - FACE_Y) / FACE_HALF.y), FACE_POWER - 1.0) / FACE_HALF.y, 0.0)
	out = (out - normal * out.dot(normal)).normalized()
	var middle := (at + tucked) * 0.5
	var reach := at - middle
	var made := PackedVector3Array()
	for step in range(ROLL_STEPS + 1):
		var angle := PI * float(step) / float(ROLL_STEPS)
		made.append(middle + reach * cos(angle) + out * ROLL * sin(angle))
	return made

## The shell and its rim. The shell's grid (columns round, rows down) is split
## along the diagonals between its even corners (column + row even), so each
## odd point is the middle of a diamond whose corners are its four even
## neighbours: the middles puff out, the corners sink in, and each diamond is
## shaded on its own (its own smooth group) with darker corners, so the seams
## show as soft creases. Wound for Godot's clockwise front faces from outside.
static func _shell() -> ArrayMesh:
	var lons := _longitudes()
	var count := lons.size()
	var grid: Array[PackedVector3Array] = []
	var rims: Array[PackedVector3Array] = []
	for column in range(count):
		var lon := lons[column]
		var cut := _cut(lon)
		var points := PackedVector3Array()
		for row in range(ROWS + 1):
			var point := _point(lon, lerpf(TOP_ANGLE, cut, float(row) / float(ROWS)))
			if row > 0 and row < ROWS: point += _normal(point) * (PUFF if (column + row) % 2 == 1 else -PINCH)
			points.append(point)
		grid.append(points)
		rims.append(_roll(points[ROWS], lon, cut))
	var rose := FruitMark.ROSE_LIGHT.lerp(FruitMark.ROSE_DEEP, ROSE_DEPTH)
	var seam := rose.darkened(SEAM_SHADE)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(ROWS):
		for column in range(count):
			var next := (column + 1) % count
			var corners: Array[Vector2i]
			if (column + row) % 2 == 0:
				corners = [Vector2i(column, row), Vector2i(next, row), Vector2i(next, row + 1), Vector2i(column, row), Vector2i(next, row + 1), Vector2i(column, row + 1)]
			else:
				corners = [Vector2i(column, row), Vector2i(next, row), Vector2i(column, row + 1), Vector2i(next, row), Vector2i(next, row + 1), Vector2i(column, row + 1)]
			for triangle in range(2):
				var three := corners.slice(triangle * 3, triangle * 3 + 3)
				var middle: Vector2i = three.filter(func(at: Vector2i) -> bool: return (at.x + at.y) % 2 == 1)[0]
				surface.set_smooth_group(1 + middle.y * count + middle.x)
				for at: Vector2i in three:
					surface.set_color(rose if at == middle else seam)
					surface.add_vertex(grid[at.x][at.y])
	surface.set_smooth_group(0)
	surface.set_color(FruitMark.ROSE_LIGHT.lerp(rose, 1.0 - RIM_LIGHT))
	for step in range(ROLL_STEPS):
		for column in range(count):
			var next := (column + 1) % count
			for at: Vector2i in [Vector2i(column, step), Vector2i(next, step), Vector2i(column, step + 1), Vector2i(next, step), Vector2i(next, step + 1), Vector2i(column, step + 1)]:
				surface.add_vertex(rims[at.x][at.y])
	surface.generate_normals()
	return surface.commit()
