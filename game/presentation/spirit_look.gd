extends RefCounted
## The spirits' look, in one place: palette, body proportions and the eight
## eye expressions. SpiritVisual builds its meshes from the proportions
## (spirit_meshes.gd) and paints the eyes on the head with spirit_face.gdshader
## from eye(); the flat art (empty_state_art.gd) draws the same contours from
## eye_contours(). Change a shape here and both follow.
##
## Face space: the head's own space, metres, origin at the head's centre, +X
## to the viewer's right when the spirit faces the camera, +Y up. Eye 0 is
## the one at -X (the viewer's left), eye 1 the one at +X.

const NORMAL := &"normal"
const HAPPY := &"happy"
const ANNOYED := &"annoyed"
const SAD := &"sad"
const ANGRY := &"angry"
const SURPRISED := &"surprised"
const SLEEPY := &"sleepy"
const SQUEEZE := &"squeeze"
const EXPRESSIONS: Array[StringName] = [NORMAL, HAPPY, ANNOYED, SAD, ANGRY, SURPRISED, SLEEPY, SQUEEZE]

## Player identities (unchanged) and the shared parts.
const PEACH := Color("f4c38d")
const MINT := Color("91d6c6")
## The outer eye: warm cream. The pupil and strokes: the kit's deep navy
## (kit/badges.gd OUTLINE), near black on screen.
const CREAM := Color("fff7e8")
const PUPIL := Color("102133")
const LEAF := Color("5e9e45")
## Feet are the body colour, a shade darker.
const FOOT_SHADE := 0.06

## A rounded box head: |x/a|^p + |y/b|^p + |z/c|^p = 1 around HEAD_CENTER.
const HEAD_CENTER := Vector3(0, 0.57, 0)
const HEAD_HALF := Vector3(0.345, 0.28, 0.31)
const HEAD_POWER := 3.0
## A small, shallow bowl under it; its top hides inside the head.
const TORSO_CENTER := Vector3(0, 0.25, 0)
const TORSO_HALF := Vector3(0.24, 0.15, 0.21)
const TORSO_POWER := 2.4
## Two tiny flat feet (ellipsoids) and where each rests.
const FOOT_HALF := Vector3(0.085, 0.05, 0.105)
const FOOT_REST := Vector3(0, 0.10, 0.055)
const FOOT_SPREAD := 0.145
## A compact rounded teardrop leaf, narrow at its stalk, leaning out from the
## head's upper corner on the viewer's left. Its pivot is the stalk, which
## sits on the head; it swings from there.
const LEAF_PIVOT := Vector3(-0.17, 0.835, -0.02)
const LEAF_LENGTH := 0.15
const LEAF_WIDTH := 0.10
const LEAF_THICKNESS := 0.055
## Rest lean (radians of roll, positive leans away from the head's middle),
## and how far the leaf tips back, built into its mesh, so its face also shows
## to the chapters' high cameras.
const LEAF_LEAN := 0.45
const LEAF_TIP_BACK := 0.35

## Where each open eye sits on the face, before gaze.
const EYE_X := 0.14
const EYE_Y := 0.005
## The least cream kept between pupil and outer eye, except along a cut.
const RIM := 0.007
## How far a gaze moves the pupil inside its eye (fraction of the gaze, metres).
const PUPIL_LOOK := Vector2(0.010, 0.006)

## The approved sad pupil (references/Approved-Sad-Pupil-Shape.png), fitted as
## a radius 1 + sum a_k cos(k angle + p_k) for k = 2..5, made plumper.
const BLOB_WAVE := Vector4(0.078, 0.092, 0.018, 0.005)
const BLOB_PHASE := Vector4(-1.248, 2.625, -1.181, 2.976)

const _NO_CUT := Vector4(0, 1, 9.0, 0)

## One eye of one expression as the shader's uniforms (face space, relative to
## the eye's anchor):
##   mode        0 a filled eye (cream with a pupil), 1 dark strokes only
##   outer       cream oval: radii x, y and centre offset x, y
##   outer_wave  outer_phase  the oval's radius harmonics (k = 2..5)
##   pupil, pupil_wave, pupil_phase  the dark pupil, the same way
##   cut         keep where dot(n, q) <= d: n.x, n.y, d, and how far inside
##               the cut the pupil stops (0: it reaches the cut)
##   tear        the cream tear lobe: centre x, y, radius (0: none)
##   tear_pupil  the dark lobe in it: centre x, y, radius, neck radius
##   stroke      strokes: a to b (x, y, x, y); stroke_end: c (x, y), half
##               width, 1 (strokes only, the shader's copy of mode)
static func eye(expression: StringName, index: int) -> Dictionary:
	var side := -1.0 if index == 0 else 1.0
	var e := {"mode": 0, "outer": Vector4(0.085, 0.097, 0, 0), "outer_wave": Vector4.ZERO, "outer_phase": Vector4.ZERO,
		"pupil": Vector4(0.066, 0.077, 0, 0), "pupil_wave": Vector4.ZERO, "pupil_phase": Vector4.ZERO,
		"cut": _NO_CUT, "tear": Vector4.ZERO, "tear_pupil": Vector4.ZERO, "stroke": Vector4.ZERO, "stroke_end": Vector4.ZERO}
	# u: outward from the face's middle, so the two eyes face each other.
	var at := func(u: float, y: float) -> Vector2: return Vector2(u * side, y)
	var calm_phase := Vector4(0.6, 2.1, 4.0, 0) if index == 0 else Vector4(2.4, 0.7, 1.3, 0)
	match expression:
		HAPPY:
			# A raised dome with a flat bottom; the pupil is a dome too, with
			# cream along its base.
			e.outer = Vector4(0.090, 0.100, 0, 0.010)
			e.cut = Vector4(0, -1, 0.030, 0.014)
			e.pupil = Vector4(0.072, 0.082, 0, 0.016)
			e.pupil_wave = Vector4(0.02, 0.015, 0, 0)
			e.pupil_phase = calm_phase
		ANNOYED:
			# Lower half eyes under a level cut; the pupil fills right up to it.
			e.outer = Vector4(0.090, 0.094, 0, -0.004)
			e.cut = Vector4(0, 1, 0.020, 0)
			e.pupil = Vector4(0.071, 0.074, 0, 0.006)
			e.pupil_wave = Vector4(0.02, 0.015, 0, 0)
			e.pupil_phase = calm_phase
		ANGRY:
			# The cut slopes down toward the face's middle; the pupil reaches it.
			var slope := 0.62
			var length := sqrt(slope * slope + 1.0)
			e.outer = Vector4(0.092, 0.090, 0, -0.004)
			e.cut = Vector4(-slope * side / length, 1.0 / length, 0.018 / length, 0)
			var p: Vector2 = at.call(-0.006, 0.004)
			e.pupil = Vector4(0.068, 0.070, p.x, p.y)
			e.pupil_wave = Vector4(0.02, 0.015, 0, 0)
			e.pupil_phase = calm_phase
		SAD:
			# Round cream eyes, strongly blobby pupils, and one tear lobe: the
			# viewer's right eye only, at its lower outer corner.
			e.outer = Vector4(0.089, 0.093, 0, 0)
			var p: Vector2 = at.call(-0.002, -0.002)
			e.pupil = Vector4(0.062, 0.063, p.x, p.y)
			e.pupil_wave = BLOB_WAVE if index == 0 else Vector4(0.070, 0.080, 0.024, 0.005)
			e.pupil_phase = BLOB_PHASE if index == 0 else _turned(BLOB_PHASE, 0.12)
			if index == 1:
				var tip: Vector2 = at.call(0.054, -0.077)
				var lobe := tip + tip.normalized() * 0.006
				e.tear = Vector4(lobe.x, lobe.y, 0.039, 0)
				e.tear_pupil = Vector4(tip.x, tip.y, 0.015, 0.0105)
		SURPRISED:
			# Wide round eyes with small centred pupils.
			e.outer = Vector4(0.100, 0.104, 0, 0.004)
			e.pupil = Vector4(0.030, 0.032, 0, 0.002)
			e.pupil_wave = Vector4(0.05, 0.03, 0, 0)
			e.pupil_phase = calm_phase
		SLEEPY:
			# Closed: one short dark dash, no cream.
			e.mode = 1
			var a: Vector2 = at.call(-0.064, -0.006)
			var b: Vector2 = at.call(0.064, -0.014)
			e.stroke = Vector4(a.x, a.y, b.x, b.y)
			e.stroke_end = Vector4(b.x, b.y, 0.017, 1)
		SQUEEZE:
			# Squeezed shut: > and < pointing at the face's middle, no cream.
			e.mode = 1
			var a: Vector2 = at.call(0.052, 0.046)
			var b: Vector2 = at.call(-0.046, 0.0)
			var c: Vector2 = at.call(0.052, -0.046)
			e.stroke = Vector4(a.x, a.y, b.x, b.y)
			e.stroke_end = Vector4(c.x, c.y, 0.016, 1)
		_:
			# Normal: a smooth cream oval and a mildly blobby pupil, the two
			# eyes a little different. Most of the eye is pupil.
			e.outer = Vector4(0.084, 0.098, 0, 0)
			e.outer_wave = Vector4(0.010, 0.006, 0.004, 0)
			e.outer_phase = calm_phase
			var p: Vector2 = at.call(-0.002, -0.004)
			e.pupil = Vector4(0.066, 0.078, p.x, p.y)
			e.pupil_wave = BLOB_WAVE * (Vector4(0.52, 0.5, 0.6, 0) if index == 0 else Vector4(0.42, 0.58, 0.5, 0))
			e.pupil_phase = BLOB_PHASE if index == 0 else _turned(BLOB_PHASE, -0.5)
	return e

## The leaf's half width along its length (t: 0 at the stalk, 1 at the tip),
## as a fraction of half LEAF_WIDTH: widest about two thirds up, a round top.
static func leaf_half_width(t: float) -> float:
	var widest := 0.62
	if t >= widest: return sqrt(maxf(0.0, 1.0 - pow((t - widest) / (1.0 - widest), 2.0)))
	return pow(sin(t / widest * PI * 0.5), 1.4) * 0.97 + 0.03 * t / widest

## Whether an expression has open eyes (cream and pupil) rather than strokes.
static func is_open(expression: StringName) -> bool:
	return expression != SLEEPY and expression != SQUEEZE

static func has(expression: StringName) -> bool:
	return expression in EXPRESSIONS

## The same shape turned by `angle` (radians, counter-clockwise).
static func _turned(phase: Vector4, angle: float) -> Vector4:
	return Vector4(phase.x - 2.0 * angle, phase.y - 3.0 * angle, phase.z - 4.0 * angle, phase.w - 5.0 * angle)

## The radius of a wavy oval at `angle`, as a fraction of its radii.
static func wave_radius(wave: Vector4, phase: Vector4, angle: float) -> float:
	return 1.0 + wave.x * cos(2.0 * angle + phase.x) + wave.y * cos(3.0 * angle + phase.y) + wave.z * cos(4.0 * angle + phase.z) + wave.w * cos(5.0 * angle + phase.w)

## One eye's outline polygons in face space (relative to its anchor), for flat
## drawing: {"outer": cream polygons, "pupil": dark polygons, "strokes": dark
## polylines, "width": stroke width}. Polygons are Arrays of PackedVector2Array.
## The shapes are the shader's, joined with plain unions where the shader blends.
static func eye_contours(expression: StringName, index: int, steps: int = 48) -> Dictionary:
	var key := "%s/%d/%d" % [expression, index, steps]
	if not _contours.has(key): _contours[key] = _eye_contours(expression, index, steps)
	return _contours[key]

static var _contours: Dictionary = {}

static func _eye_contours(expression: StringName, index: int, steps: int) -> Dictionary:
	var e := eye(expression, index)
	if e.mode == 1:
		var s: Vector4 = e.stroke
		var c: Vector4 = e.stroke_end
		var line := PackedVector2Array([Vector2(s.x, s.y), Vector2(s.z, s.w)])
		if not Vector2(c.x, c.y).is_equal_approx(Vector2(s.z, s.w)): line.append(Vector2(c.x, c.y))
		return {"outer": [], "pupil": [], "strokes": [line], "width": c.z * 2.0}
	var outer: Array = [_oval(e.outer, e.outer_wave, e.outer_phase, steps)]
	var pupil: Array = [_oval(e.pupil, e.pupil_wave, e.pupil_phase, steps)]
	var tear: Vector4 = e.tear
	if tear.z > 0.0:
		outer = _union(outer, _oval(Vector4(tear.z, tear.z, tear.x, tear.y), Vector4.ZERO, Vector4.ZERO, 20))
		var tp: Vector4 = e.tear_pupil
		var tip := Vector2(tp.x, tp.y)
		pupil = _union(pupil, _oval(Vector4(tp.z, tp.z, tp.x, tp.y), Vector4.ZERO, Vector4.ZERO, 16))
		pupil = _union(pupil, _capsule(tip * 0.6, tip, tp.w))
	# The pupil keeps a rim of cream, except where the cut trims both.
	var inner: Array = []
	for polygon: PackedVector2Array in outer:
		for shrunk: PackedVector2Array in Geometry2D.offset_polygon(polygon, -RIM): inner.append(shrunk)
	pupil = _intersect(pupil, inner)
	var cut: Vector4 = e.cut
	if cut.z < 1.0:
		outer = _intersect(outer, [_half_plane(Vector2(cut.x, cut.y), cut.z)])
		pupil = _intersect(pupil, [_half_plane(Vector2(cut.x, cut.y), cut.z - cut.w)])
	return {"outer": outer, "pupil": pupil, "strokes": [], "width": 0.0}

static func _oval(shape: Vector4, wave: Vector4, phase: Vector4, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in range(steps):
		var angle := TAU * float(step) / float(steps)
		var r := wave_radius(wave, phase, angle)
		points.append(Vector2(shape.z + cos(angle) * shape.x * r, shape.w + sin(angle) * shape.y * r))
	return points

static func _capsule(a: Vector2, b: Vector2, radius: float) -> PackedVector2Array:
	var dir := (b - a).normalized()
	var points := PackedVector2Array()
	for step in range(9): points.append(b + dir.rotated(-PI * 0.5 + PI * step / 8.0) * radius)
	for step in range(9): points.append(a + dir.rotated(PI * 0.5 + PI * step / 8.0) * radius)
	return points

static func _half_plane(normal: Vector2, d: float) -> PackedVector2Array:
	# A big square on the kept side of dot(normal, q) <= d.
	var n := normal.normalized()
	var base := n * d
	var along := n.orthogonal()
	return PackedVector2Array([base + along * 1.0, base + along * 1.0 - n * 2.0, base - along * 1.0 - n * 2.0, base - along * 1.0])

static func _union(polygons: Array, other: PackedVector2Array) -> Array:
	# The shapes always overlap, so each merge is one outline.
	var result := other
	for polygon: PackedVector2Array in polygons: result = _largest(Geometry2D.merge_polygons(polygon, result))
	return [result]

static func _intersect(polygons: Array, masks: Array) -> Array:
	var out: Array = []
	for polygon: PackedVector2Array in polygons:
		for mask: PackedVector2Array in masks:
			out.append_array(Geometry2D.intersect_polygons(polygon, mask))
	return out

static func _largest(polygons: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for polygon: PackedVector2Array in polygons:
		var area := 0.0
		for index in range(polygon.size()): area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
		if absf(area) > best_area:
			best_area = absf(area)
			best = polygon
	return best
