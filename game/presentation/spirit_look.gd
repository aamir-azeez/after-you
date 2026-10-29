extends RefCounted
## The spirits' look, in one place: palette, body proportions and the eye
## expressions. SpiritVisual builds its meshes from the proportions
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
## X X eyes: knocked out, or scared stiff.
const KNOCKED_OUT := &"knocked_out"
## ^ ^ closed smiling eyes with pink cheeks: the face a spirit makes as it
## sends the heart reaction (services/reaction_catalog.gd HEART_EXPRESSION).
## The 3D face; no reaction icon draws it.
const JOY := &"joy"
## The reaction packs' faces (services/reaction_catalog.gd PACKS, approved on
## board 6b). Garden faces: a cream heart with a red heart inside, eyes shut
## in arcs bowed down with Joy's cheeks, and one eye shut in a wink. Big
## feelings: a star for each pupil, squeezed shut with tear streams, and a
## spiral in each eye.
const HEART_EYES := &"heart_eyes"
const PROUD := &"proud"
const WINK := &"wink"
const WOW := &"wow"
const CRYING := &"crying"
const DIZZY := &"dizzy"
const EXPRESSIONS: Array[StringName] = [NORMAL, HAPPY, ANNOYED, SAD, ANGRY, SURPRISED, SLEEPY, SQUEEZE, KNOCKED_OUT, JOY, HEART_EYES, PROUD, WINK, WOW, CRYING, DIZZY]
## The expressions that never blink: those drawn as dark strokes only, with no
## cream, and Wink, which holds one eye shut.
const STROKED: Array[StringName] = [SLEEPY, SQUEEZE, KNOCKED_OUT, JOY, PROUD, WINK, CRYING, DIZZY]
## Heart eyes' inner heart: the heart reaction's coral a step deeper, so it
## holds on the cream.
const HEART_RED := Color("e2626b")
## An open eye's outlines (eye()'s eye_shape): x the pupil's, 0 a wavy oval,
## 1 a heart (pupil.x its size), 2 a five point star (pupil.x its radius,
## pupil.y its inner radius as a fraction of it); y the cream's, 0 a wavy oval,
## 1 a heart (outer.x its size). A heart pupil is drawn in HEART_RED.
const SHAPE_OVAL := 0.0
const SHAPE_HEART := 1.0
const SHAPE_STAR := 2.0
## A star's corners are rounded this much (metres).
const STAR_ROUND := 0.008
## Where the heart's own middle sits in its unit outline (tip at 0, top 1.10).
const HEART_MIDDLE := 0.55

## Player identities (unchanged) and the shared parts.
const PEACH := Color("f4c38d")
const MINT := Color("91d6c6")
## Each slot's spirit by colour name (empty_state_art.gd SPIRITS): the host,
## p0, is peach; the guest, p1, is mint.
const SLOT_COLOR_NAMES := {"p0": "peach", "p1": "mint"}
## The outer eye: warm cream. The pupil and strokes: the kit's deep navy
## (kit/badges.gd OUTLINE), near black on screen.
const CREAM := Color("fff7e8")
const PUPIL := Color("102133")
const LEAF := Color("5e9e45")
## Joy's cheeks: a soft pink, mixed over the body (peach or mint) this much,
## with a soft edge this wide (metres).
const BLUSH := Color("f38e9b")
const BLUSH_STRENGTH := 0.85
const BLUSH_SOFT := 0.010
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
## Where the tear's dark neck starts, as a fraction of the way from the eye's
## anchor to the dark tip.
const TEAR_NECK_ROOT := 0.6
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
##               width, and the stroke kind the shader reads (mode is 1 for
##               all): 0 none, 1 a line a, b, c, 2 a cross: a to b, and c
##               through the middle of a to b out to c's mirror, 3 an arc
##               bowed upward: stroke is its centre x, y, radius and half
##               sweep (radians either side of straight up); c is unused,
##               4 a spiral from its centre out: stroke is the centre x, y,
##               how far it reaches and its turns (negative turns the other
##               way), 5 an arc bowed downward: kind 3 mirrored about its centre
##   blush       a soft pink cheek: radii x, y and centre offset x, y (0: none)
##   eye_shape   an open eye's outlines: x the pupil's, y the cream's
##               (SHAPE_OVAL, SHAPE_HEART, SHAPE_STAR)
##   tear_stream tear_stream_end  a cream stream falling from under the eye:
##               its top x, y and radius, then its bottom x, y and radius
##               (0: none)
static func eye(expression: StringName, index: int) -> Dictionary:
	var side := -1.0 if index == 0 else 1.0
	var e := {"mode": 0, "outer": Vector4(0.085, 0.097, 0, 0), "outer_wave": Vector4.ZERO, "outer_phase": Vector4.ZERO,
		"pupil": Vector4(0.066, 0.077, 0, 0), "pupil_wave": Vector4.ZERO, "pupil_phase": Vector4.ZERO,
		"cut": _NO_CUT, "tear": Vector4.ZERO, "tear_pupil": Vector4.ZERO, "stroke": Vector4.ZERO, "stroke_end": Vector4.ZERO,
		"blush": Vector4.ZERO, "eye_shape": Vector4.ZERO, "tear_stream": Vector4.ZERO, "tear_stream_end": Vector4.ZERO}
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
			# The plain eye's blob is turned about 30 degrees, so it is no copy of
			# the tear eye's.
			e.pupil_phase = _turned(BLOB_PHASE, -0.5) if index == 0 else _turned(BLOB_PHASE, 0.12)
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
		KNOCKED_OUT:
			# Knocked out: a bold X, two crossed strokes, no cream.
			e.mode = 1
			var reach := 0.068
			e.stroke = Vector4(-reach, reach, reach, -reach)
			e.stroke_end = Vector4(-reach, -reach, 0.024, 2)
		JOY:
			# ^ ^: a bold arc bowed upward, no cream, and a soft pink cheek
			# under each, a little toward the face's edge.
			e.mode = 1
			e.stroke = Vector4(0, -0.034, 0.062, 1.2)
			e.stroke_end = Vector4(0, 0, 0.019, 3)
			var cheek: Vector2 = at.call(0.050, -0.088)
			e.blush = Vector4(0.050, 0.032, cheek.x, cheek.y)
		HEART_EYES:
			# A cream heart with a red heart inside: the open eye's
			# outline and pupil, heart shaped.
			e.eye_shape = Vector4(SHAPE_HEART, SHAPE_HEART, 0, 0)
			e.outer = Vector4(0.180, 0, 0, 0.006)
			e.pupil = Vector4(0.152, 0, 0, 0.002)
		PROUD:
			# Shut and pleased: an arc bowed downward, chin up, with
			# Joy's pink cheeks.
			e.mode = 1
			e.stroke = Vector4(0, 0.050, 0.064, 1.12)
			e.stroke_end = Vector4(0, 0, 0.019, 5)
			var cheek: Vector2 = at.call(0.050, -0.084)
			e.blush = Vector4(0.050, 0.032, cheek.x, cheek.y)
		WINK:
			# The viewer's left eye open as Normal; the right one shut
			# in Joy's arc, no cheeks.
			if index == 0: return eye(NORMAL, 0)
			e.mode = 1
			e.stroke = Vector4(0, -0.034, 0.064, 1.2)
			e.stroke_end = Vector4(0, 0, 0.019, 3)
		WOW:
			# Wide cream eyes, as Surprised, with a big five point star
			# for a pupil.
			e.eye_shape = Vector4(SHAPE_STAR, SHAPE_OVAL, 0, 0)
			e.outer = Vector4(0.100, 0.104, 0, 0.004)
			e.pupil = Vector4(0.083, 0.50, 0, 0.0)
		CRYING:
			# Squeezed shut as Squeeze, with a cream tear stream running
			# from under each eye, widening as it falls.
			e.mode = 1
			var a: Vector2 = at.call(0.050, 0.044)
			var b: Vector2 = at.call(-0.044, 0.0)
			var c: Vector2 = at.call(0.050, -0.044)
			e.stroke = Vector4(a.x, a.y, b.x, b.y)
			e.stroke_end = Vector4(c.x, c.y, 0.016, 1)
			var top: Vector2 = at.call(0.014, -0.056)
			var bottom: Vector2 = at.call(0.030, -0.180)
			e.tear_stream = Vector4(top.x, top.y, 0.022, 0)
			e.tear_stream_end = Vector4(bottom.x, bottom.y, 0.042, 0)
		DIZZY:
			# A spiral in each eye, turning opposite ways.
			e.mode = 1
			e.stroke = Vector4(0, 0, 0.078, 1.6 * side)
			e.stroke_end = Vector4(0, 0, 0.0145, 4)
		_:
			# Normal: a smooth cream oval and a mildly blobby pupil, the two
			# eyes a little different. Most of the eye is pupil.
			e.outer = Vector4(0.084, 0.098, 0, 0)
			e.outer_wave = Vector4(0.010, 0.006, 0.004, 0)
			e.outer_phase = calm_phase
			var p: Vector2 = at.call(-0.002, -0.004)
			e.pupil = Vector4(0.066, 0.078, p.x, p.y)
			e.pupil_wave = BLOB_WAVE * (Vector4(0.39, 0.375, 0.45, 0) if index == 0 else Vector4(0.315, 0.435, 0.375, 0))
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
	return not expression in STROKED

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
## polylines, "width": stroke width}, and "blush" (pink cheek polygons) only
## for a look with cheeks. Polygons are Arrays of PackedVector2Array.
## The shapes are the shader's, joined with plain unions where the shader blends.
static func eye_contours(expression: StringName, index: int, steps: int = 48) -> Dictionary:
	var key := "%s/%d/%d" % [expression, index, steps]
	if not _contours.has(key): _contours[key] = _eye_contours(expression, index, steps)
	return _contours[key]

static var _contours: Dictionary = {}

static func _eye_contours(expression: StringName, index: int, steps: int) -> Dictionary:
	var e := eye(expression, index)
	var result := _eye_contours_base(e, steps)
	# Cheeks on any look that has them (the flat art draws them too), and cream tear streams.
	var bl: Vector4 = e.blush
	if bl.x > 0.0 and not result.has("blush"): result.blush = [_oval(bl, Vector4.ZERO, Vector4.ZERO, 32)]
	var ts: Vector4 = e.tear_stream
	if ts.z > 0.0:
		var te: Vector4 = e.tear_stream_end
		var hull := PackedVector2Array()
		hull.append_array(_oval(Vector4(ts.z, ts.z, ts.x, ts.y), Vector4.ZERO, Vector4.ZERO, 24))
		hull.append_array(_oval(Vector4(te.z, te.z, te.x, te.y), Vector4.ZERO, Vector4.ZERO, 32))
		result.streams = [Geometry2D.convex_hull(hull)]
	if e.eye_shape.x == SHAPE_HEART: result.pupil_color = HEART_RED
	return result

static func _eye_contours_base(e: Dictionary, steps: int) -> Dictionary:
	if e.mode == 1 and e.stroke_end.w > 4.5:
		# Kind 5: an arc bowed downward.
		var down := _arc(e.stroke, 16)
		var centre := Vector2(e.stroke.x, e.stroke.y)
		for i in range(down.size()): down[i] = Vector2(down[i].x, 2.0 * centre.y - down[i].y)
		return {"outer": [], "pupil": [], "strokes": [down], "width": e.stroke_end.z * 2.0}
	if e.mode == 1 and e.stroke_end.w > 3.5:
		# Kind 4: a spiral from the middle out.
		return {"outer": [], "pupil": [], "strokes": [_spiral(e.stroke, 72)], "width": e.stroke_end.z * 2.0}
	if e.mode == 0 and (e.eye_shape.x > 0.0 or e.eye_shape.y > 0.0):
		return _shaped_contours(e, steps)
	if e.mode == 1:
		var s: Vector4 = e.stroke
		var c: Vector4 = e.stroke_end
		var a := Vector2(s.x, s.y)
		var b := Vector2(s.z, s.w)
		var end := Vector2(c.x, c.y)
		if c.w > 2.5:
			var bl: Vector4 = e.blush
			var arc := {"outer": [], "pupil": [], "strokes": [_arc(s, 16)], "width": c.z * 2.0}
			if bl.x > 0.0: arc.blush = [_oval(bl, Vector4.ZERO, Vector4.ZERO, 32)]
			return arc
		if c.w > 1.5: return {"outer": [], "pupil": [], "strokes": [PackedVector2Array([a, b]), PackedVector2Array([end, a + b - end])], "width": c.z * 2.0}
		var line := PackedVector2Array([a, b])
		if not end.is_equal_approx(b): line.append(end)
		return {"outer": [], "pupil": [], "strokes": [line], "width": c.z * 2.0}
	var outer: Array = [_oval(e.outer, e.outer_wave, e.outer_phase, steps)]
	var pupil: Array = [_oval(e.pupil, e.pupil_wave, e.pupil_phase, steps)]
	var tear: Vector4 = e.tear
	if tear.z > 0.0:
		outer = _union(outer, _oval(Vector4(tear.z, tear.z, tear.x, tear.y), Vector4.ZERO, Vector4.ZERO, 20))
		var tp: Vector4 = e.tear_pupil
		var tip := Vector2(tp.x, tp.y)
		pupil = _union(pupil, _oval(Vector4(tp.z, tp.z, tp.x, tp.y), Vector4.ZERO, Vector4.ZERO, 16))
		pupil = _union(pupil, _capsule(tip * TEAR_NECK_ROOT, tip, tp.w))
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

## An open eye whose cream or pupil is a heart or a star.
static func _shaped_contours(e: Dictionary, steps: int) -> Dictionary:
	var outer: Array = [_heart(e.outer) if e.eye_shape.y == SHAPE_HEART else _oval(e.outer, e.outer_wave, e.outer_phase, steps)]
	var pupil_shape: PackedVector2Array
	if e.eye_shape.x == SHAPE_HEART: pupil_shape = _heart(e.pupil)
	elif e.eye_shape.x == SHAPE_STAR: pupil_shape = _star(e.pupil)
	else: pupil_shape = _oval(e.pupil, e.pupil_wave, e.pupil_phase, steps)
	var inner: Array = []
	for polygon: PackedVector2Array in outer:
		for shrunk: PackedVector2Array in Geometry2D.offset_polygon(polygon, -RIM): inner.append(shrunk)
	return {"outer": outer, "pupil": _intersect([pupil_shape], inner), "strokes": [], "width": 0.0}

## The heart the shader draws (Inigo Quilez's sdHeart): two straight
## sides from the tip and a round lobe each, `shape.x` big, its middle at
## shape.z, shape.w.
static func _heart(shape: Vector4) -> PackedVector2Array:
	var size := shape.x
	var origin := Vector2(shape.z, shape.w - HEART_MIDDLE * size)
	var right := PackedVector2Array([Vector2.ZERO])
	var lobe := Vector2(0.25, 0.75)
	var radius := sqrt(2.0) / 4.0
	for step in range(25):
		var angle := -PI * 0.25 + PI * float(step) / 24.0
		right.append(lobe + Vector2(cos(angle), sin(angle)) * radius)
	var points := PackedVector2Array()
	for p: Vector2 in right: points.append(origin + p * size)
	for i in range(right.size() - 2, 0, -1): points.append(origin + Vector2(-right[i].x, right[i].y) * size)
	return points

## A five point star, point up, radius shape.x, inner radius shape.y
## of it, round at the corners (the shader's rounded sdStar5).
static func _star(shape: Vector4) -> PackedVector2Array:
	var reach := shape.x - STAR_ROUND
	var points := PackedVector2Array()
	for step in range(10):
		var angle := PI * 0.5 + TAU * float(step) / 10.0
		var r := reach if step % 2 == 0 else reach * shape.y
		points.append(Vector2(shape.z, shape.w) + Vector2(cos(angle), sin(angle)) * r)
	var grown := Geometry2D.offset_polygon(points, STAR_ROUND, Geometry2D.JOIN_ROUND)
	return grown[0] if not grown.is_empty() else points

## An Archimedean spiral around stroke.xy reaching stroke.z after
## |stroke.w| turns; a negative count turns the other way.
static func _spiral(stroke: Vector4, steps: int) -> PackedVector2Array:
	var turns := absf(stroke.w)
	var flip := -1.0 if stroke.w < 0.0 else 1.0
	var points := PackedVector2Array()
	for step in range(steps + 1):
		var t := TAU * turns * float(step) / float(steps)
		var r := stroke.z * t / (TAU * turns)
		points.append(Vector2(stroke.x + cos(t) * r * flip, stroke.y + sin(t) * r))
	return points

static func _oval(shape: Vector4, wave: Vector4, phase: Vector4, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in range(steps):
		var angle := TAU * float(step) / float(steps)
		var r := wave_radius(wave, phase, angle)
		points.append(Vector2(shape.z + cos(angle) * shape.x * r, shape.w + sin(angle) * shape.y * r))
	return points

## An arc bowed upward (stroke kind 3): centre x, y, radius, half sweep.
static func _arc(arc: Vector4, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in range(steps + 1):
		var angle := PI * 0.5 + arc.w - 2.0 * arc.w * float(step) / float(steps)
		points.append(Vector2(arc.x, arc.y) + Vector2(cos(angle), sin(angle)) * arc.z)
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
