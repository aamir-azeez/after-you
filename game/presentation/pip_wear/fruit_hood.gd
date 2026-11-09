extends RefCounted
## The Orchard's fruit hoods (hat): a soft round plush hood shaped like a
## fruit that wraps the whole head (its top, sides and back, and under the
## chin down to just above the body) with an oval opening for the face, and
## the fruit's own top: the Apple hood's curved brown stem and leaf, the
## Blueberry hood's little star crown. One art script serves both, each
## descriptor naming it; the look is picked by the worn hat's id (as sprig.gd
## picks a colour).
##
## The shell is a round ball a little bigger than the head all round, so no
## part of it is inside the head (test_pip_outfit checks). It is laid out in
## rings round the face: each of its RAYS starts at the face opening's edge,
## runs over the head and ends at the jaw line, its points evenly spaced along
## the way. So the face opening and the hood's outline seen from the front are
## each one smooth ring. At both ends the edge rolls in to just off the head,
## so no gap shows. Every point takes the shell's own smooth normal.
##
## The fruit's top stands where a carried seed rests, so the hood lifts the
## seed (pip_outfit.gd lift_seed). It stands in for the pip's own leaf, which
## hides while it is worn. A worn leaf item still shows, raised by the
## descriptor's "leaf_lift" so its stalk starts under the hood's top and its
## blade grows out clear of it. One baked mesh per hood, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

## Each hood's look by item id: the shell's colour, a soft dusty bloom mixed
## in toward its top (none for the apple), its top ("apple" or "blueberry"),
## and the metres a carried seed sits higher to clear that top.
const LOOKS := {
	"apple_hood": {"shell": Color("d9483f"), "bloom": Color("e8735f"), "bloom_amount": 0.25, "top": "apple", "seed_lift": 0.14},
	"blueberry_hood": {"shell": Color("3c4795"), "bloom": Color("98a2cf"), "bloom_amount": 0.42, "top": "blueberry", "seed_lift": 0.1},
}
## The shell, in head space: a round, slightly boxy ball (POWER) of these half
## sizes about CENTER.
const CENTER := Vector3(0.0, 0.0, -0.005)
const HALF := Vector3(0.395, 0.35, 0.365)
const POWER := 2.2
## The face opening seen from the front: a round oval (FACE_POWER) of half
## size FACE_HALF about height FACE_Y, just big enough for the eyes and the
## face round them, clear of the eyes even at their farthest glance.
const FACE_HALF := Vector2(0.325, 0.19)
const FACE_Y := 0.02
const FACE_POWER := 2.2
## The hood's lower edge, under the chin (x) and at the back (y): round under
## the jaw to just above where the head meets the body, so only the face shows.
const JAW := Vector2(-0.232, -0.238)
## Where the rays start (the face) and end (under the jaw), as directions from
## CENTER, and how many there are and how many steps each takes. The rays
## crowd toward the long ones over the top (RAY_CROWD) and thin out toward the
## short ones under the chin, so the hood's outline stays round.
const FACE_AT := Vector3(0.0, -0.02, 1.0)
const NECK_AT := Vector3(0.0, -1.0, -0.3)
const RAYS := 24
const ROWS := 8
const RAY_CROWD := 0.5
## The rolled face edge bows out past the cut by ROLL and comes back in to
## just off the head (TUCK); the jaw edge turns in under to the head, aimed
## UNDER below the cut.
const ROLL := 0.016
const TUCK := 0.004
const UNDER := 0.012
## How finely each ray is searched for its two cuts and measured.
const SAMPLES := 240

## The Apple hood's stem: a curved brown tube through these points, from
## inside the shell up and over to the right, and its leaf off the stem near
## its top: [base, direction (its length), side (its half width)], with a fold
## along its middle rib and a droop toward its tip.
const STEM_BROWN := Color("7a5032")
const STEM: Array[Vector3] = [Vector3(0.0, 0.31, -0.01), Vector3(0.002, 0.375, -0.01), Vector3(0.012, 0.425, -0.012), Vector3(0.034, 0.455, -0.014)]
const STEM_RADIUS := 0.017
const STEM_SIDES := 5
const LEAF_GREEN := Color("7dbb52")
const LEAF_BASE := Vector3(0.012, 0.41, -0.012)
const LEAF_ALONG := Vector3(0.135, 0.05, 0.015)
const LEAF_SIDE := Vector3(-0.014, 0.04, 0.036)
const LEAF_FOLD := 0.01
const LEAF_DROOP := 0.02
const LEAF_STEPS := 4
const LEAF_ACROSS := 3
## The Blueberry hood's crown: a five-pointed star round a dark dimple on the
## hood's top, its points standing up a little, in the dusty bloom. Radii of
## the dimple, of the star's valleys and its points, and of where it meets
## the shell.
const CROWN_DUST := 0.35
const DIMPLE_DARK := 0.45
const CROWN_POINTS := 5
const CROWN_RADII := Vector4(0.026, 0.058, 0.1, 0.07)
const CROWN_HEIGHTS := Vector3(0.012, 0.022, 0.042)
const DIMPLE_DEPTH := 0.006

static func wear(look: RefCounted) -> void:
	var id := str(look.outfit.get("hat", ""))
	if not LOOKS.has(id): return
	look.mesh(look.head(), Kit.cached_mesh(id, _build.bind(id)), Kit.vertex_material())
	if not look.outfit.has("leaf"): look.hide_leaf()
	look.lift_seed(float(LOOKS[id].seed_lift))

static func _build(id: String) -> Mesh:
	var made: Dictionary = LOOKS[id]
	var surface := SurfaceTool.new()
	surface.append_from(_shell(made), 0, Transform3D.IDENTITY)
	surface.append_from(_apple_top() if made.top == "apple" else _blueberry_top(made), 0, Transform3D.IDENTITY)
	return surface.commit()

## The shell's outer height over head-space `point` (its x and z), on its top
## half, or -INF past it (tests check a worn leaf grows out of the hood and
## never cuts into it).
static func top_height(point: Vector3) -> float:
	var left := 1.0 - pow(absf((point.x - CENTER.x) / HALF.x), POWER) - pow(absf((point.z - CENTER.z) / HALF.z), POWER)
	if left <= 0.0: return -INF
	return CENTER.y + HALF.y * pow(left, 1.0 / POWER)

## The shell's surface in `direction` from CENTER.
static func _on_shell(direction: Vector3) -> Vector3:
	var sum := pow(absf(direction.x / HALF.x), POWER) + pow(absf(direction.y / HALF.y), POWER) + pow(absf(direction.z / HALF.z), POWER)
	return CENTER + direction * pow(sum, -1.0 / POWER)

static func _normal(point: Vector3) -> Vector3:
	var from := point - CENTER
	return Vector3(
		signf(from.x) * pow(absf(from.x / HALF.x), POWER - 1.0) / HALF.x,
		signf(from.y) * pow(absf(from.y / HALF.y), POWER - 1.0) / HALF.y,
		signf(from.z) * pow(absf(from.z / HALF.z), POWER - 1.0) / HALF.z).normalized()

## How far into the face opening `point` is (below 1 inside), or INF behind
## the face, and the way into it from there (toward its middle).
static func _face(point: Vector3) -> float:
	if point.z <= 0.0: return INF
	return pow(absf(point.x / FACE_HALF.x), FACE_POWER) + pow(absf((point.y - FACE_Y) / FACE_HALF.y), FACE_POWER)

static func _into_face(point: Vector3) -> Vector3:
	return -Vector3(signf(point.x) * pow(absf(point.x / FACE_HALF.x), FACE_POWER - 1.0) / FACE_HALF.x, signf(point.y - FACE_Y) * pow(absf((point.y - FACE_Y) / FACE_HALF.y), FACE_POWER - 1.0) / FACE_HALF.y, 0.0)

static func _below_jaw(point: Vector3) -> bool:
	var round_back := (1.0 - cos(atan2(point.x, point.z))) * 0.5
	return point.y < lerpf(JAW.x, JAW.y, round_back)

## The rays are circles on the sphere of directions from the face's middle to
## the point under the jaw: seen from that point (a stereographic view), each
## is a straight line out from the face's middle, so a ray is that line
## turned back onto the sphere.
static func _direction(flat: Vector3, neck: Vector3) -> Vector3:
	var square := flat.length_squared()
	return (flat * 2.0 + neck * (square - 1.0)) / (square + 1.0)

static func _flat(direction: Vector3, neck: Vector3) -> Vector3:
	return (direction - neck * direction.dot(neck)) / (1.0 - direction.dot(neck))

## One ray's points from the face cut to the jaw cut, evenly spaced along the
## shell (ROWS + 1 of them).
static func _ray(start: Vector3, way: Vector3, neck: Vector3) -> PackedVector3Array:
	var lengths := PackedFloat32Array()
	var reaches := PackedFloat32Array()
	var points := PackedVector3Array()
	var face_cut := -1
	var jaw_cut := -1
	var walked := 0.0
	for index in range(SAMPLES + 1):
		# Out from the face's middle on a growing scale: the far end is the point under the jaw.
		var reach := 0.002 * pow(20000.0, float(index) / float(SAMPLES))
		var point := _on_shell(_direction(start + way * reach, neck))
		if not points.is_empty(): walked += point.distance_to(points[points.size() - 1])
		reaches.append(reach)
		points.append(point)
		lengths.append(walked)
		if face_cut < 0 and _face(point) >= 1.0: face_cut = index
		if face_cut >= 0 and jaw_cut < 0 and _below_jaw(point):
			jaw_cut = index - 1
			break
	var from := _cut(lengths, reaches, points, face_cut, start, way, neck, false)
	var to := _cut(lengths, reaches, points, jaw_cut, start, way, neck, true)
	var made := PackedVector3Array()
	for row in range(ROWS + 1):
		var along := lerpf(from, to, float(row) / float(ROWS))
		var index := lengths.bsearch(along)
		index = clampi(index, 1, lengths.size() - 1)
		var part := inverse_lerp(lengths[index - 1], lengths[index], along)
		made.append(_on_shell(_direction(start + way * lerpf(reaches[index - 1], reaches[index], part), neck)))
	return made

## The length along a ray where it crosses a cut, near sample `at`: past the
## face opening (`jaw` false) or onto the jaw line (`jaw` true).
static func _cut(lengths: PackedFloat32Array, reaches: PackedFloat32Array, points: PackedVector3Array, at: int, start: Vector3, way: Vector3, neck: Vector3, jaw: bool) -> float:
	var low := reaches[maxi(at - 1, 0)] if not jaw else reaches[at]
	var high := reaches[at] if not jaw else reaches[mini(at + 1, reaches.size() - 1)]
	for step in range(20):
		var middle := (low + high) * 0.5
		var point := _on_shell(_direction(start + way * middle, neck))
		var past := _below_jaw(point) if jaw else _face(point) >= 1.0
		if past: high = middle
		else: low = middle
	var cut := high if not jaw else low
	# The length there, from the samples on either side.
	var index := clampi(reaches.bsearch(cut), 1, reaches.size() - 1)
	return lerpf(lengths[index - 1], lengths[index], inverse_lerp(reaches[index - 1], reaches[index], cut))

## A rolled edge at cut point `at`: bowing out past the cut along `out`, then
## in to just off the head behind it. Returns [middle of the roll, tucked
## point] with their normals: [point, normal, point, normal].
static func _roll(at: Vector3, out: Vector3) -> Array[Vector3]:
	var normal := _normal(at)
	out = (out - normal * out.dot(normal)).normalized()
	var head := Meshes.head_surface(at - normal * 0.06)
	var tucked: Vector3 = head[0] + head[1] * TUCK
	var middle := (at + tucked) * 0.5 + out * ROLL
	return [middle, out, tucked, (out - normal).normalized()]

## The jaw edge at cut point `at`: turned in under to just off the head,
## aimed UNDER below the cut so it always runs inward and down. Returns
## [tucked point, its normal].
static func _hem(at: Vector3) -> Array[Vector3]:
	var head := Meshes.head_surface(at + Vector3.DOWN * UNDER)
	var normal := _normal(at)
	return [head[0] + head[1] * TUCK, (normal + Vector3.DOWN).normalized()]

## The shell with its edges, one smooth strip per ray: the face roll's tucked
## point, its middle, the ray's points to the jaw, and the jaw edge's tucked
## point.
static func _shell(look: Dictionary) -> ArrayMesh:
	var neck := NECK_AT.normalized()
	var start := _flat(FACE_AT.normalized(), neck)
	var across := Vector3.RIGHT
	var up := neck.cross(across).normalized()
	var points: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for ray in range(RAYS):
		var turn := float(ray) / float(RAYS)
		var angle := TAU * turn - RAY_CROWD * cos(TAU * turn)
		var row := _ray(start, across * cos(angle) + up * sin(angle), neck)
		var face := _roll(row[0], _into_face(row[0]))
		var jaw := _hem(row[ROWS])
		var line := PackedVector3Array([face[2], face[0]])
		var facing := PackedVector3Array([face[3], face[1]])
		for point: Vector3 in row:
			line.append(point)
			facing.append(_normal(point))
		line.append(jaw[0])
		facing.append(jaw[1])
		points.append(line)
		normals.append(facing)
	var shell: Color = look.shell
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := points[0].size()
	# Wound so the first quad faces out (Godot's front faces are clockwise).
	var a := points[0][3]
	var flip := (points[1][3] - a).cross(points[0][4] - a).dot(normals[0][3]) > 0.0
	for ray in range(RAYS):
		var next := (ray + 1) % RAYS
		for step in range(count - 1):
			var quad := [Vector2i(ray, step), Vector2i(next, step), Vector2i(ray, step + 1), Vector2i(next, step), Vector2i(next, step + 1), Vector2i(ray, step + 1)]
			if flip: quad = [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]]
			for corner: Vector2i in quad:
				var normal := normals[corner.x][corner.y]
				surface.set_normal(normal)
				surface.set_color(shell.lerp(look.bloom, float(look.bloom_amount) * clampf(0.5 + 0.5 * normal.y, 0.0, 1.0)))
				surface.add_vertex(points[corner.x][corner.y])
	return surface.commit()

## The apple's top: the curved stem, a smooth tube capped at its tip, and the
## leaf.
static func _apple_top() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(STEM_BROWN)
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	for index in range(STEM.size()):
		var along := (STEM[mini(index + 1, STEM.size() - 1)] - STEM[maxi(index - 1, 0)]).normalized()
		var side := along.cross(Vector3.BACK).normalized()
		var other := along.cross(side)
		var ring := PackedVector3Array()
		var facing := PackedVector3Array()
		var radius := STEM_RADIUS * (1.0 - 0.18 * float(index) / float(STEM.size() - 1))
		for corner in range(STEM_SIDES):
			var angle := TAU * float(corner) / float(STEM_SIDES)
			var out := side * cos(angle) + other * sin(angle)
			ring.append(STEM[index] + out * radius)
			facing.append(out)
		rings.append(ring)
		ring_normals.append(facing)
	var tip := STEM[STEM.size() - 1]
	var tip_up := (tip - STEM[STEM.size() - 2]).normalized()
	for index in range(STEM.size() - 1):
		for corner in range(STEM_SIDES):
			var next := (corner + 1) % STEM_SIDES
			_triangle(surface, [rings[index][corner], rings[index + 1][corner], rings[index][next]], [ring_normals[index][corner], ring_normals[index + 1][corner], ring_normals[index][next]], ring_normals[index][corner])
			_triangle(surface, [rings[index][next], rings[index + 1][corner], rings[index + 1][next]], [ring_normals[index][next], ring_normals[index + 1][corner], ring_normals[index + 1][next]], ring_normals[index][next])
	var last := rings[rings.size() - 1]
	for corner in range(STEM_SIDES):
		_triangle(surface, [tip + tip_up * STEM_RADIUS * 0.4, last[corner], last[(corner + 1) % STEM_SIDES]], [tip_up, tip_up, tip_up], tip_up)
	surface.append_from(_leaf(), 0, Transform3D.IDENTITY)
	return surface.commit()

## Adds one triangle wound to face `outward`, with its corners' normals.
static func _triangle(surface: SurfaceTool, corners: Array, facing: Array, outward: Vector3) -> void:
	var order := [0, 1, 2]
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(outward) > 0.0: order = [0, 2, 1]
	for index: int in order:
		surface.set_normal(facing[index])
		surface.add_vertex(corners[index])

## The apple's leaf: pointed at its tip, broadest a little before its middle,
## folded along its rib and drooping toward its tip, both faces drawn.
static func _leaf() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(LEAF_GREEN)
	var up := LEAF_ALONG.cross(LEAF_SIDE).normalized()
	if up.y < 0.0: up = -up
	var grid: Array[PackedVector3Array] = []
	for step in range(LEAF_STEPS + 1):
		var t := float(step) / float(LEAF_STEPS)
		var width := sin(PI * pow(t, 0.8))
		var row := PackedVector3Array()
		for across in range(LEAF_ACROSS + 1):
			var u := lerpf(-1.0, 1.0, float(across) / float(LEAF_ACROSS))
			row.append(LEAF_BASE + LEAF_ALONG * t + LEAF_SIDE * width * u + up * (LEAF_FOLD * width * absf(u) - LEAF_DROOP * t * t))
		grid.append(row)
	for side: float in [1.0, -1.0]:
		surface.set_smooth_group(1 if side > 0.0 else 2)
		for step in range(LEAF_STEPS):
			for across in range(LEAF_ACROSS):
				var corners := [grid[step][across], grid[step + 1][across], grid[step][across + 1], grid[step + 1][across + 1]]
				for triangle: Array in [[0, 1, 2], [2, 1, 3]]:
					var three := [corners[triangle[0]], corners[triangle[1]], corners[triangle[2]]]
					var facing: Vector3 = (three[1] - three[0]).cross(three[2] - three[0])
					if facing.dot(up) * side > 0.0: three = [three[0], three[2], three[1]]
					for point: Vector3 in three: surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()

## The blueberry's top: a star of CROWN_POINTS points standing up round a dark
## dimple a little above the hood's top, its outside running down into the
## shell.
static func _blueberry_top(look: Dictionary) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(CENTER.x, top_height(CENTER), CENTER.z)
	var shell: Color = look.shell
	var crown := shell.lerp(look.bloom, CROWN_DUST)
	var dimple := shell.darkened(DIMPLE_DARK)
	var inner := PackedVector3Array()
	var star := PackedVector3Array()
	var base := PackedVector3Array()
	var corners := CROWN_POINTS * 2
	for corner in range(corners):
		var angle := TAU * float(corner) / float(corners)
		var way := Vector3(sin(angle), 0.0, cos(angle))
		var point := corner % 2 == 0
		inner.append(top + way * CROWN_RADII.x + Vector3.UP * CROWN_HEIGHTS.x)
		star.append(top + way * (CROWN_RADII.z if point else CROWN_RADII.y) + Vector3.UP * (CROWN_HEIGHTS.z if point else CROWN_HEIGHTS.y))
		var under := Vector3(top.x, 0.0, top.z) + way * CROWN_RADII.w
		base.append(Vector3(under.x, top_height(under) - 0.01, under.z))
	surface.set_smooth_group(1)
	for corner in range(corners):
		var next := (corner + 1) % corners
		surface.set_color(dimple)
		_flat_triangle(surface, [top + Vector3.UP * (CROWN_HEIGHTS.x - DIMPLE_DEPTH), inner[corner], inner[next]])
		surface.set_color(crown)
		_flat_triangle(surface, [inner[corner], star[corner], inner[next]])
		_flat_triangle(surface, [inner[next], star[corner], star[next]])
		_flat_triangle(surface, [star[corner], base[corner], star[next]])
		_flat_triangle(surface, [star[next], base[corner], base[next]])
	surface.generate_normals()
	return surface.commit()

## Adds a triangle wound to face up and out from the hood's top.
static func _flat_triangle(surface: SurfaceTool, three: Array) -> void:
	var middle: Vector3 = (three[0] + three[1] + three[2]) / 3.0
	var outward := (middle - CENTER).normalized() + Vector3.UP
	if (three[1] - three[0]).cross(three[2] - three[0]).dot(outward) > 0.0: three = [three[0], three[2], three[1]]
	for point: Vector3 in three: surface.add_vertex(point)
