extends RefCounted
## Fruit cap (hat): half a ripe Fruit worn as a cap, as the Orchard board
## draws it (Fruits board 4a): a tall rose dome a little narrower than the
## head, sitting on it with its front just above the eyes, a cream band round
## its rim, and the Fruit's stem and leaf on top. The rose and the green are
## the Fruit's own (kit/fruit_mark.gd).
##
## The rim follows the head's curve: low at the front and back, where the cap
## reaches past the head, and higher at the sides, where it rests on the
## head's rounded top, so the cap sits on the head and never sinks into it.
## The stem stands where a carried seed rests, so the cap lifts the seed
## (pip_outfit.gd lift_seed). The cap's stem and leaf stand in for the pip's
## own leaf, which hides while it is worn. A worn leaf item still shows,
## raised by the descriptor's "leaf_lift" so its stalk starts just under the
## dome's shoulder and its blade grows out clear of the dome. One baked mesh,
## one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const FruitMark = preload("res://presentation/kit/fruit_mark.gd")
const Look = preload("res://presentation/spirit_look.gd")

## The dome's rose: this far from the Fruit's light rose toward its deep one.
const ROSE_DEPTH := 0.45
const BAND := Color("f2dfcf")
const GREEN := FruitMark.GREEN
## Head space: the rim's lowest height (just above the eyes), the dome's
## half width and half depth across its rim, and its top.
const RIM_Y := 0.145
const HALF := Vector2(0.27, 0.345)
const TOP := 0.44
## The dome's roundness. Up its side (PROFILE): near 2 it rounds over like a
## Fruit's half. Across (ACROSS): above 2 it fills out toward the head's
## rounded corners, so none of the head shows through it.
const PROFILE := 2.2
const ACROSS := 2.8
const SEGMENTS := 24
const RINGS := 7
## The band round the rim: how far it stands out from the dome, and its
## reach below and above the rim.
const BAND_OUT := 1.05
const BAND_BELOW := 0.022
const BAND_ABOVE := 0.03
## How much higher the rim sits at the sides, and how its rise is shaped
## round the head, so the band runs in one smooth curve.
const SIDE_RISE := 0.095
const RISE_SHAPE := 1.5
## The stem, from inside the dome's top up and a little to the right, and
## the leaf off its tip, its broad side turned toward the front.
const STEM: Array[Vector3] = [Vector3(0.0, 0.425, -0.01), Vector3(0.008, 0.47, -0.012), Vector3(0.028, 0.503, -0.015)]
const STEM_RADIUS := 0.017
const LEAF_AT := Vector3(0.1, 0.517, -0.015)
const LEAF_SIZE := Vector3(0.082, 0.014, 0.048)
const LEAF_TURN := Vector3(0.9, 0.25, 0.42)
## Metres a carried seed sits higher, so it clears the stem and the leaf.
const SEED_LIFT := 0.175

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("fruit_cap", _build), Kit.vertex_material())
	if not look.outfit.has("leaf"): look.hide_leaf()
	look.lift_seed(SEED_LIFT)

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.add(_dome(), FruitMark.ROSE_LIGHT.lerp(FruitMark.ROSE_DEEP, ROSE_DEPTH), Transform3D.IDENTITY)
	parts.add(_band(), BAND, Transform3D.IDENTITY)
	for index in range(STEM.size() - 1): parts.rod(GREEN, STEM[index], STEM[index + 1], STEM_RADIUS)
	parts.blob(GREEN, LEAF_AT, LEAF_SIZE, LEAF_TURN, 8, 3)
	return parts.commit()

## The dome's height over head-space `point` (its x and z), or -INF past its
## rim (tests check a worn leaf grows out of the dome and never cuts into it).
static func dome_height(point: Vector3) -> float:
	var lon := atan2(point.x, point.z)
	var rim := _across(lon)
	var out := Vector2(point.x, point.z).length() / Vector2(rim.x, rim.z).length()
	if out >= 1.0: return -INF
	return lerpf(_rim_y(lon), TOP, pow(1.0 - pow(out, PROFILE), 1.0 / PROFILE))

## The rim's shape across at `lon` (0 is the front): a rounded oval (ACROSS)
## of the dome's half width and depth, in head space at height 0.
static func _across(lon: float) -> Vector3:
	var direction := Vector3(sin(lon), 0.0, cos(lon))
	var reach := pow(pow(absf(direction.x), ACROSS) + pow(absf(direction.z), ACROSS), -1.0 / ACROSS)
	var point := direction * reach
	return Vector3(point.x * HALF.x, 0.0, point.z * HALF.y)

## The rim's height at `lon`: a smooth rise from RIM_Y at the front and back
## to SIDE_RISE higher at the sides, and never under where the band,
## standing out BAND_OUT, meets the head (with room for the band below it).
static func _rim_y(lon: float) -> float:
	var band := _across(lon) * BAND_OUT
	var half := Look.HEAD_HALF
	var left := 1.0 - pow(absf(band.x / half.x), Look.HEAD_POWER) - pow(absf(band.z / half.z), Look.HEAD_POWER)
	var surface := half.y * pow(left, 1.0 / Look.HEAD_POWER) if left > 0.0 else 0.0
	return maxf(RIM_Y + SIDE_RISE * pow(absf(sin(lon)), RISE_SHAPE), surface + BAND_BELOW)

## The dome, open below: each level the rim's shape, shrinking up the side's
## profile (PROFILE) from the rim to the top.
static func _dome() -> ArrayMesh:
	var points := PackedVector3Array()
	for ring in range(RINGS + 1):
		var lat := PI * 0.5 * float(ring) / float(RINGS)
		# Out from the middle and up, on the profile |out|^p + |up|^p = 1.
		var reach := pow(pow(sin(lat), PROFILE) + pow(cos(lat), PROFILE), -1.0 / PROFILE)
		var out := sin(lat) * reach
		var up := cos(lat) * reach
		for segment in range(SEGMENTS + 1):
			var lon := TAU * float(segment) / float(SEGMENTS)
			var rim := _rim_y(lon)
			points.append(_across(lon) * out + Vector3.UP * lerpf(rim, TOP, up))
	return _grid(points, RINGS)

## The band: a short wall round the rim, a little out from the dome, and its
## underside, so it shows as a cream edge from below too.
static func _band() -> ArrayMesh:
	var points := PackedVector3Array()
	# Rows top to bottom: the wall's top, its bottom, then the underside's inner edge.
	for row: Array in [[BAND_ABOVE, BAND_OUT], [-BAND_BELOW, BAND_OUT], [-BAND_BELOW, 0.95]]:
		for segment in range(SEGMENTS + 1):
			var lon := TAU * float(segment) / float(SEGMENTS)
			points.append(_across(lon) * float(row[1]) + Vector3.UP * (_rim_y(lon) + float(row[0])))
	return _grid(points, 2)

## Triangles over a (rows + 1) by (SEGMENTS + 1) grid, its first row the
## highest, wound for Godot's clockwise front faces seen from outside, with
## smooth normals.
static func _grid(points: PackedVector3Array, rows: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var row := SEGMENTS + 1
	for ring in range(rows):
		for segment in range(SEGMENTS):
			var a := ring * row + segment
			var b := a + row
			for corner: int in [a, a + 1, b, a + 1, b + 1, b]: surface.add_vertex(points[corner])
	surface.index()
	surface.generate_normals()
	return surface.commit()
