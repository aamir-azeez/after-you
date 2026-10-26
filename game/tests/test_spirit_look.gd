extends SceneTree
## The spirits' shared look (presentation/spirit_look.gd) and the faces that
## show it: the ten eye shapes' rules, the body's proportions, and which
## moments change the face.

const Look = preload("res://presentation/spirit_look.gd")
const Spirit = preload("res://presentation/spirit_visual.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")
const Idle = preload("res://presentation/spirit_idle.gd")
const Art = preload("res://presentation/empty_state_art.gd")
const Faces = preload("res://services/reaction_catalog.gd")
const Icon = preload("res://presentation/friend_play_icon.gd")
## The flat outlines of the nine looks the icons draw (eye_contours()), as on
## origin/main 1ee75731 before Joy: picker cells, the Play with your friend
## icon, empty states and badges must keep exactly these faces.
const ICON_FACES_MD5 := "42db19ac3ea69aa2400c60d8c002ed69"

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_table()
	_test_open_eyes()
	_test_sad_tear()
	_test_cuts()
	_test_strokes()
	_test_knocked_out()
	_test_joy()
	_test_icon_faces_pinned()
	_test_body()
	_test_triggers()
	_test_api_and_placement()
	_test_knocked_out_swaps()
	print("AFTER YOU SPIRIT LOOK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func _area(polygons: Array) -> float:
	var total := 0.0
	for polygon: PackedVector2Array in polygons:
		var area := 0.0
		for index in range(polygon.size()): area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
		total += absf(area) * 0.5
	return total

func _points(polygons: Array) -> PackedVector2Array:
	var all := PackedVector2Array()
	for polygon: PackedVector2Array in polygons: all.append_array(polygon)
	return all

func _anchor(index: int) -> Vector2:
	return Vector2(-Look.EYE_X if index == 0 else Look.EYE_X, Look.EYE_Y)

func _test_table() -> void:
	_check(Look.EXPRESSIONS.size() == 10 and Look.EXPRESSIONS.has(Look.NORMAL) and Look.EXPRESSIONS.has(Look.SQUEEZE) and Look.EXPRESSIONS.has(Look.KNOCKED_OUT) and Look.KNOCKED_OUT == &"knocked_out" and Look.EXPRESSIONS.has(Look.JOY) and Look.JOY == &"joy", "Ten expressions, knocked_out and joy among them")
	var complete := true
	for expression: StringName in Look.EXPRESSIONS:
		for index in range(2):
			var eye := Look.eye(expression, index)
			for key: String in ["outer", "outer_wave", "outer_phase", "pupil", "pupil_wave", "pupil_phase", "cut", "tear", "tear_pupil", "stroke", "stroke_end", "blush"]:
				complete = complete and eye.get(key) is Vector4
			# The shader reads the mode from stroke_end.w.
			complete = complete and (eye.stroke_end.w > 0.5) == (eye.mode == 1) and (eye.mode == 1) == (not Look.is_open(expression))
	_check(complete, "Every expression gives both eyes every shader parameter, with the mode in step")

func _test_open_eyes() -> void:
	# Normal: most of the eye is pupil; the pupil is hand-shaped but milder than Sad's.
	for index in range(2):
		var shape := Look.eye_contours(Look.NORMAL, index)
		var ratio := _area(shape.pupil) / _area(shape.outer)
		_check(ratio > 0.55 and ratio < 0.82, "Normal eye %d: the pupil fills most of the eye (%.2f)" % [index, ratio])
	var normal_wave: Vector4 = Look.eye(Look.NORMAL, 0).pupil_wave
	var sad_wave: Vector4 = Look.eye(Look.SAD, 0).pupil_wave
	_check(normal_wave.length() > 0.02 and normal_wave.length() < sad_wave.length() * 0.6, "Normal pupils are blobby, but much less than Sad's")
	_check(Look.eye(Look.NORMAL, 0).outer_wave.length() < normal_wave.length(), "The cream oval is smoother than the pupil")
	var left := Look.eye(Look.NORMAL, 0)
	var right := Look.eye(Look.NORMAL, 1)
	_check(left.pupil_wave != right.pupil_wave or left.pupil_phase != right.pupil_phase, "The two Normal eyes are not copies of each other")
	# Sad: a smooth round cream eye around the approved blob.
	for index in range(2):
		var sad := Look.eye(Look.SAD, index)
		_check(sad.outer_wave == Vector4.ZERO and absf(sad.outer.x - sad.outer.y) < 0.01, "Sad eye %d: the main cream outline is smooth and round" % index)
		_check(sad.pupil_wave.length() > 0.1, "Sad eye %d: the pupil is strongly blobby" % index)
	_check(Look.eye(Look.SAD, 0).pupil_wave == Look.BLOB_WAVE and Look.eye(Look.SAD, 0).pupil_phase != Look.eye(Look.SAD, 1).pupil_phase, "Sad's pupil is the approved blob, turned differently in each eye")
	# Surprised: small pupils.
	for index in range(2):
		var shape := Look.eye_contours(Look.SURPRISED, index)
		_check(_area(shape.pupil) / _area(shape.outer) < 0.15, "Surprised eye %d has a small pupil" % index)
	# Happy: a dome with a flat base, cream along the base under the pupil.
	var happy := Look.eye(Look.HAPPY, 0)
	_check(happy.cut.y < 0.0 and happy.cut.w > 0.005, "Happy is a raised dome with cream along its flat base")
	# The face's colours: cream, a near black navy, no white glint anywhere.
	_check(Look.PUPIL.get_luminance() < 0.15 and Look.CREAM.get_luminance() > 0.85 and Look.CREAM != Color.WHITE, "Cream eyes, near black pupils")

func _test_sad_tear() -> void:
	var tears := 0
	for index in range(2):
		if Look.eye(Look.SAD, index).tear.z > 0.0: tears += 1
	_check(tears == 1 and Look.eye(Look.SAD, 1).tear.z > 0.0, "Sad has exactly one tear tip, on the viewer's right eye")
	var sad := Look.eye(Look.SAD, 1)
	var tear: Vector4 = sad.tear
	var dark: Vector4 = sad.tear_pupil
	_check(dark.z > 0.0 and dark.w > 0.0, "The pupil runs into the tip as a connected dark lobe")
	var tip := Vector2(tear.x, tear.y)
	var drop := Vector2(dark.x, dark.y)
	var cream_round_drop := tear.z - (tip.distance_to(drop) + dark.z)
	var tip_dark := pow(dark.z / tear.z, 2.0)
	var main_dark := pow(sad.pupil.x / sad.outer.x, 2.0)
	_check(cream_round_drop > Look.RIM * 2.0 and tip_dark < main_dark * 0.5, "The tip is mostly cream round its dark lobe (%.2f dark against %.2f in the eye)" % [tip_dark, main_dark])
	_check(tip.x > 0.0 and tip.y < -0.05, "The tip hangs at the eye's lower outer corner")
	# The whole tip stays on the face: well inside the head's outline, on its front.
	var shape := Look.eye_contours(Look.SAD, 1)
	var on_face := true
	for point: Vector2 in _points(shape.outer):
		var at := point + _anchor(1)
		var reach := pow(absf(at.x / Look.HEAD_HALF.x), Look.HEAD_POWER) + pow(absf(at.y / Look.HEAD_HALF.y), Look.HEAD_POWER)
		on_face = on_face and reach < 0.75
	_check(on_face, "The whole Sad eye and its tip stay on the face, with face colour all round")
	_check(shape.pupil.size() == 1, "The tip's dark lobe joins the pupil")

func _test_cuts() -> void:
	for expression: StringName in [Look.ANNOYED, Look.ANGRY]:
		for index in range(2):
			var eye := Look.eye(expression, index)
			var cut: Vector4 = eye.cut
			var normal := Vector2(cut.x, cut.y)
			_check(cut.w == 0.0 and normal.y > 0.5, "%s eye %d: the cut is on top and the pupil is not held back from it" % [expression, index])
			# Along the cut, the pupil spans most of the eye: no cream strip on top.
			var shape := Look.eye_contours(expression, index, 96)
			var along := normal.orthogonal()
			var pupil_span := _span_on_line(_points(shape.pupil), normal, cut.z, along)
			var outer_span := _span_on_line(_points(shape.outer), normal, cut.z, along)
			_check(pupil_span > outer_span * 0.6, "%s eye %d: the pupil reaches the cut along %.0f%% of it" % [expression, index, 100.0 * pupil_span / maxf(outer_span, 0.0001)])
	# Angry slopes down toward the middle of the face on both eyes.
	_check(Look.eye(Look.ANGRY, 0).cut.x > 0.0 and Look.eye(Look.ANGRY, 1).cut.x < 0.0, "Angry cuts fall toward the face's middle")

## Width of the points lying on the line dot(normal, q) = d.
func _span_on_line(points: PackedVector2Array, normal: Vector2, d: float, along: Vector2) -> float:
	var low := INF
	var high := -INF
	for point: Vector2 in points:
		if absf(point.dot(normal) - d) < 0.0015:
			low = minf(low, point.dot(along))
			high = maxf(high, point.dot(along))
	return 0.0 if low == INF else high - low

func _test_strokes() -> void:
	for expression: StringName in [Look.SLEEPY, Look.SQUEEZE]:
		for index in range(2):
			var shape := Look.eye_contours(expression, index)
			_check(shape.outer.is_empty() and shape.pupil.is_empty() and shape.strokes.size() == 1, "%s eye %d: dark strokes only, no cream" % [expression, index])
	# Squeeze: > on the viewer's left eye, < on the right, both pointing in.
	for index in range(2):
		var line: PackedVector2Array = Look.eye_contours(Look.SQUEEZE, index).strokes[0]
		var inward := 1.0 if index == 0 else -1.0
		_check(line.size() == 3 and (line[1].x - line[0].x) * inward > 0.0 and (line[1].x - line[2].x) * inward > 0.0, "Squeeze eye %d points at the face's middle" % index)

## The shader's stroke distance (spirit_face.gdshaderinc), for one eye's uniforms.
func _stroke_distance(eye: Dictionary, q: Vector2) -> float:
	var s: Vector4 = eye.stroke
	var c: Vector4 = eye.stroke_end
	if c.w > 2.5:
		# The arc: the shader's sdArc, mirrored about the arc's own vertical.
		var p := q - Vector2(s.x, s.y)
		p.x = absf(p.x)
		var sc := Vector2(sin(s.w), cos(s.w))
		return (p.distance_to(sc * s.z) if sc.y * p.x > sc.x * p.y else absf(p.length() - s.z)) - c.z
	var a := Vector2(s.x, s.y)
	var b := Vector2(s.z, s.w)
	var end := Vector2(c.x, c.y)
	var from := a + b - end if c.w > 1.5 else b
	return minf(q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)), q.distance_to(Geometry2D.get_closest_point_to_segment(q, from, end))) - c.z

func _test_knocked_out() -> void:
	_check(not Look.is_open(Look.KNOCKED_OUT), "Knocked out has no open eyes, so it never blinks")
	var squeeze_width: float = Look.eye_contours(Look.SQUEEZE, 0).width
	for index in range(2):
		var eye := Look.eye(Look.KNOCKED_OUT, index)
		var shape := Look.eye_contours(Look.KNOCKED_OUT, index)
		_check(eye.mode == 1 and eye.stroke_end.w == 2.0 and shape.outer.is_empty() and shape.pupil.is_empty() and eye.tear.z == 0.0, "Knocked out eye %d: dark strokes only, no cream" % index)
		_check(shape.strokes.size() == 2 and shape.strokes[0].size() == 2 and shape.strokes[1].size() == 2, "Knocked out eye %d: two separate strokes" % index)
		if shape.strokes.size() != 2: continue
		var one: PackedVector2Array = shape.strokes[0]
		var two: PackedVector2Array = shape.strokes[1]
		var crossing: Variant = Geometry2D.segment_intersects_segment(one[0], one[1], two[0], two[1])
		_check(crossing != null and (crossing as Vector2).length() < 0.005, "Knocked out eye %d: the strokes cross at the eye's anchor" % index)
		var along_one := (one[1] - one[0]).normalized()
		var along_two := (two[1] - two[0]).normalized()
		_check(absf(along_one.dot(along_two)) < 0.1 and absf(one[0].distance_to(one[1]) - two[0].distance_to(two[1])) < 0.002 and absf(along_one.x) > 0.6 and absf(along_one.y) > 0.6, "Knocked out eye %d: an upright X, two equal arms at right angles" % index)
		var reach := 0.0
		for line: PackedVector2Array in shape.strokes:
			for point: Vector2 in line: reach = maxf(reach, maxf(absf(point.x), absf(point.y)))
		reach += shape.width * 0.5
		var normal_reach: float = Look.eye(Look.NORMAL, index).outer.x
		_check(reach > normal_reach * 0.85 and reach < normal_reach * 1.25, "Knocked out eye %d: about as big as an open eye (%.3f against %.3f)" % [index, reach, normal_reach])
		_check(shape.width > squeeze_width * 1.2, "Knocked out eye %d: bolder strokes than Squeeze" % index)
		# The shader's own rule draws an X: dark at the middle and the four tips,
		# face colour between the arms.
		var r := absf(one[0].x)
		var dark := true
		for point: Vector2 in [Vector2.ZERO, Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]: dark = dark and _stroke_distance(eye, point) < 0.0
		var clear := true
		for point: Vector2 in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]: clear = clear and _stroke_distance(eye, point) > 0.0
		_check(dark and clear, "Knocked out eye %d: the shader's strokes draw a crossed X" % index)
	# The two eyes mirror each other.
	var mirrored := true
	var left: Array = Look.eye_contours(Look.KNOCKED_OUT, 0).strokes
	var right: Array = Look.eye_contours(Look.KNOCKED_OUT, 1).strokes
	for line: PackedVector2Array in left:
		for point: Vector2 in line:
			var found := false
			for other: PackedVector2Array in right:
				for candidate: Vector2 in other: found = found or candidate.is_equal_approx(Vector2(-point.x, point.y))
			mirrored = mirrored and found
	_check(mirrored, "The two X eyes mirror each other")
	# The other strokes still draw as before: one line each.
	_check(Look.eye(Look.SLEEPY, 0).stroke_end.w == 1.0 and Look.eye(Look.SQUEEZE, 1).stroke_end.w == 1.0, "Sleepy and Squeeze stay single lines")
	var code: String = load("res://presentation/spirit_face.gdshaderinc").code
	_check(code.contains("stroke_end[i].w > 1.5") and code.contains("stroke[i].xy + stroke[i].zw - stroke_end[i].xy"), "The face shader draws the cross kind as the look describes it")

## Joy, the face a spirit makes as it sends the heart: closed ^ ^ arcs bowed
## upward, no cream, and a soft pink cheek under each.
func _test_joy() -> void:
	_check(not Look.is_open(Look.JOY) and Look.JOY in Look.STROKED, "Joy's eyes are closed arcs, so they never blink")
	var normal_reach: float = Look.eye(Look.NORMAL, 0).outer.x
	for index in range(2):
		var eye := Look.eye(Look.JOY, index)
		var shape := Look.eye_contours(Look.JOY, index)
		_check(eye.mode == 1 and eye.stroke_end.w == 3.0 and shape.outer.is_empty() and shape.pupil.is_empty() and shape.strokes.size() == 1, "Joy eye %d: one dark arc, no cream" % index)
		if shape.strokes.size() != 1: continue
		var line: PackedVector2Array = shape.strokes[0]
		var top := -INF
		for point: Vector2 in line: top = maxf(top, point.y)
		var middle := line[line.size() >> 1]
		_check(line.size() >= 9 and absf(middle.y - top) < 0.001 and top - line[0].y > 0.03 and top - line[line.size() - 1].y > 0.03, "Joy eye %d bows upward: highest in the middle, both ends well below" % index)
		_check(absf(line[0].x + line[line.size() - 1].x) < 0.001 and absf(line[0].y - line[line.size() - 1].y) < 0.001, "Joy eye %d is an even arc, its ends level" % index)
		var reach: float = absf(line[0].x) + shape.width * 0.5
		_check(reach > normal_reach * 0.75 and reach < normal_reach * 1.25 and shape.width > Look.eye_contours(Look.SQUEEZE, index).width, "Joy eye %d: about as wide as an open eye, a bold stroke (%.3f against %.3f)" % [index, reach, normal_reach])
		# The shader's own rule: dark along the arc's top and at its ends, face
		# colour inside it, above it and below it.
		var arc: Vector4 = eye.stroke
		var centre := Vector2(arc.x, arc.y)
		var dark := _stroke_distance(eye, centre + Vector2(0, arc.z)) < 0.0 and _stroke_distance(eye, line[0]) < 0.0
		var clear := _stroke_distance(eye, centre) > 0.0 and _stroke_distance(eye, centre + Vector2(0, arc.z + eye.stroke_end.z * 2.0)) > 0.0 and _stroke_distance(eye, centre + Vector2(0, -arc.z)) > 0.0
		_check(dark and clear, "Joy eye %d: the shader draws the same arc" % index)
		# The cheek: below the arc, toward the face's edge, and on the face.
		var cheek: Vector4 = eye.blush
		var outward := -1.0 if index == 0 else 1.0
		var lowest: float = minf(line[0].y, line[line.size() - 1].y) - shape.width * 0.5
		_check(cheek.x > 0.0 and cheek.y > 0.0 and cheek.w + cheek.y < lowest and cheek.z * outward > 0.0, "Joy eye %d: a cheek sits under the arc, a little toward the face's edge" % index)
		var blush: Array = shape.get("blush", [])
		_check(blush.size() == 1 and absf(_area(blush) - PI * cheek.x * cheek.y) < PI * cheek.x * cheek.y * 0.05, "Joy eye %d: its outline lists the same cheek" % index)
		var on_face := true
		for point: Vector2 in _points(blush):
			var at := point + _anchor(index)
			on_face = on_face and pow(absf(at.x / Look.HEAD_HALF.x), Look.HEAD_POWER) + pow(absf(at.y / Look.HEAD_HALF.y), Look.HEAD_POWER) < 0.75
		_check(on_face, "Joy eye %d: the cheek stays on the face" % index)
	var left := Look.eye(Look.JOY, 0)
	var right := Look.eye(Look.JOY, 1)
	_check(left.blush == Vector4(right.blush.x, right.blush.y, -right.blush.z, right.blush.w) and left.stroke == right.stroke, "The two Joy eyes and cheeks mirror each other")
	_check(Look.BLUSH.r > Look.BLUSH.g + 0.15 and Look.BLUSH.r > Look.BLUSH.b + 0.15 and Look.BLUSH.get_luminance() > 0.55 and Look.BLUSH_STRENGTH > 0.5 and Look.BLUSH_SOFT > 0.0, "The cheeks are a soft light pink")
	var only_joy := true
	for expression: StringName in Look.EXPRESSIONS:
		if expression == Look.JOY: continue
		for index in range(2): only_joy = only_joy and Look.eye(expression, index).blush == Vector4.ZERO and not Look.eye_contours(expression, index).has("blush")
	_check(only_joy, "Only Joy has cheeks")
	var code: String = load("res://presentation/spirit_face.gdshaderinc").code
	_check(code.contains("stroke_end[i].w > 2.5") and code.contains("blush[i].x > 0.0"), "The face shader draws the arc kind and the cheeks as the look describes them")
	# On a spirit: Joy uploads its arcs and cheeks, and a change of face clears
	# the cheeks.
	var spirit := Spirit.new(Look.MINT)
	root.add_child(spirit)
	spirit.set_expression(Look.JOY, true)
	var cheeks: PackedVector4Array = spirit.face_art.material.get_shader_parameter(&"blush")
	var kinds: PackedVector4Array = spirit.face_art.material.get_shader_parameter(&"stroke_end")
	_check(cheeks.size() == 2 and cheeks[0].x > 0.0 and cheeks[1].x > 0.0 and kinds[0].w == 3.0 and kinds[1].w == 3.0 and spirit.face_art.material.get_shader_parameter(&"blush_color") == Look.BLUSH, "A joyful spirit draws both arcs and both cheeks")
	spirit.set_expression(Look.HAPPY, true)
	cheeks = spirit.face_art.material.get_shader_parameter(&"blush")
	kinds = spirit.face_art.material.get_shader_parameter(&"stroke_end")
	_check(cheeks[0] == Vector4.ZERO and cheeks[1] == Vector4.ZERO and kinds[0].w == 0.0, "Happy, after it, has open eyes and no cheeks")
	spirit.free()

## One line per look and eye: what its flat outline draws, rounded so the
## same shapes give the same text on any machine.
func _icon_faces() -> String:
	var lines: PackedStringArray = []
	for expression: StringName in [Look.NORMAL, Look.HAPPY, Look.ANNOYED, Look.SAD, Look.ANGRY, Look.SURPRISED, Look.SLEEPY, Look.SQUEEZE, Look.KNOCKED_OUT]:
		for index in range(2):
			var shape := Look.eye_contours(expression, index)
			var keys: Array = shape.keys()
			keys.sort()
			var row := "%s/%d %s w%s" % [expression, index, ",".join(PackedStringArray(keys)), _n(shape.width)]
			for part: String in ["outer", "pupil"]:
				var box := Rect2()
				var count := 0
				for polygon: PackedVector2Array in shape[part]:
					for point: Vector2 in polygon:
						box = Rect2(point, Vector2.ZERO) if count == 0 else box.expand(point)
						count += 1
				row += " %s %d a%s [%s %s %s %s]" % [part, shape[part].size(), _n(_area(shape[part]), 5), _n(box.position.x), _n(box.position.y), _n(box.end.x), _n(box.end.y)]
			for line: PackedVector2Array in shape.strokes:
				row += " line"
				for point: Vector2 in line: row += " %s,%s" % [_n(point.x), _n(point.y)]
			lines.append(row)
	return "\n".join(lines)

## A number rounded to `digits` places, with no "-0" for a value that rounds
## to zero, so tiny differences between machines print the same.
func _n(value: float, digits: int = 4) -> String:
	var text := String.num(value, digits)
	return "0" if float(text) == 0.0 else text

## The icons keep their faces: Joy is the 3D heart face only.
func _test_icon_faces_pinned() -> void:
	var faces := _icon_faces()
	_check(faces.md5_text() == ICON_FACES_MD5, "The nine flat faces the icons draw are unchanged (md5 %s)" % faces.md5_text())
	if faces.md5_text() != ICON_FACES_MD5: print(faces)
	_check(Look.is_open(Look.HAPPY) and Look.eye(Look.HAPPY, 0).mode == 0 and Look.eye(Look.HAPPY, 0).blush == Vector4.ZERO, "Happy keeps its open eyes, with no cheeks")
	# No icon draws Joy: the picker's faces, the flat art's eye names and scenes.
	_check(not Faces.EXPRESSIONS.values().has(Look.JOY) and Faces.expression(Faces.HEART) == &"", "The picker never draws Joy: the heart there is its icon")
	var drawn_joy := Art.EYES.values().has(Look.JOY)
	for scene: String in Art.SCENES:
		for row: Array in Art.SCENES[scene]:
			if row.size() > 2 and row[2] is Dictionary: drawn_joy = drawn_joy or StringName(str(row[2].get("eyes", ""))) == Look.JOY
	_check(not drawn_joy, "No empty state or icon scene draws Joy")
	var icon_code: String = (Icon as Script).source_code
	_check(icon_code.contains("Look.SQUEEZE if squeezed else Look.HAPPY") and not icon_code.contains("JOY"), "The Play with your friend icon is still Happy at rest and Squeeze when pressed")

func _test_body() -> void:
	var leaf_hue := Look.LEAF.h * 360.0
	_check(leaf_hue > 80.0 and leaf_hue < 150.0 and Look.LEAF.s > 0.35, "The leaf is green")
	var height := Look.HEAD_HALF.y * 2.0
	_check(Look.LEAF_LENGTH / height > 0.2 and Look.LEAF_LENGTH / height < 0.33 and absf(Look.LEAF_WIDTH / Look.LEAF_LENGTH - 0.67) < 0.1, "A compact leaf: about a quarter of the head's height, two thirds as wide as long")
	var peach := Spirit.new(Look.PEACH)
	var mint := Spirit.new(Look.MINT)
	root.add_child(peach)
	root.add_child(mint)
	_check((peach.sprout.material_override as StandardMaterial3D).albedo_color == Look.LEAF and (mint.sprout.material_override as StandardMaterial3D).albedo_color == Look.LEAF, "Both spirits wear the same green leaf")
	_check(peach.head.mesh == mint.head.mesh and peach.torso.mesh == mint.torso.mesh and peach.sprout.mesh == mint.sprout.mesh, "Every spirit shares one set of body meshes")
	var triangles := 0
	for node: Node in peach.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh is ArrayMesh and node.get_parent().name != "ReunionSparkles":
			for surface in range(mesh.get_surface_count()):
				var indices: PackedInt32Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
				triangles += (indices.size() if not indices.is_empty() else mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()) / 3
	_check(triangles < 2600, "A whole spirit is light (%d triangles in its own meshes)" % triangles)
	# The head is wider than tall, with a small torso under it, and stays inside
	# the old head's reach so carried things and badges still clear it.
	_check(Look.HEAD_HALF.x > Look.HEAD_HALF.y and Look.TORSO_HALF.x < Look.HEAD_HALF.x * 0.75, "A wide rounded box head over a smaller bowl")
	_check(Look.HEAD_CENTER.y + Look.HEAD_HALF.y < 0.925 - 0.05, "A carried seed (from 0.925 m up) still sits clear above the head")
	var low := INF
	for foot: Node3D in peach.feet: low = minf(low, foot.position.y - Look.FOOT_HALF.y)
	_check(low > 0.03 and low < 0.07, "The feet still meet the ground where they did")
	peach.free()
	mint.free()

func _step(spirit: Node3D, seconds: float, reduced: bool = false) -> void:
	for _frame in range(roundi(seconds * 60.0)): spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, reduced)

func _test_triggers() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.set_expression_role("a")
	_step(spirit, 1.0)
	_check(spirit.expression() == Look.NORMAL, "A resting spirit shows Normal")
	# Doze: Sleepy while it lasts.
	spirit.set_pose(Idle.DOZE, {})
	_step(spirit, 1.5)
	_check(spirit.expression() == Look.SLEEPY, "A dozing spirit shows Sleepy")
	# The wake is not a Surprised face: the owner chose no automatic Surprised.
	spirit.play_wake(false)
	var surprised := false
	for _frame in range(60):
		spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
		surprised = surprised or spirit.expression_target() == Look.SURPRISED
	_check(not surprised and spirit.expression() == Look.NORMAL, "Waking from a doze goes back to Normal, never Surprised")
	# Reunion: Happy.
	spirit.set_partner_offset(Vector3(3, 0, 0), true)
	_step(spirit, 0.05)
	spirit.set_partner_offset(Vector3(1, 0, 0), true)
	_step(spirit, 0.3)
	_check(spirit.expression() == Look.HAPPY, "A reunion shows Happy")
	_step(spirit, Spirit.HAPPY_REUNION_DURATION + 0.3)
	_check(spirit.expression() == Look.NORMAL, "After the reunion the face is Normal again")
	# A finished chapter: Happy for the celebration.
	spirit.set_celebration(true)
	_step(spirit, 0.3)
	_check(spirit.expression() == Look.HAPPY, "A finished chapter shows Happy")
	spirit.free()
	# Reduce motion: the doze shows Sleepy at once.
	var still := Spirit.new()
	root.add_child(still)
	still.set_pose(Idle.DOZE, {})
	still.advance_motion(Vector3.ZERO, 1.0 / 60.0, true)
	_check(still.expression() == Look.SLEEPY and not still.face_art.swapping(), "Under Reduce motion the face changes without a swap")
	still.free()

func _test_api_and_placement() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.set_expression(Look.ANGRY)
	_step(spirit, 0.1)
	_check(spirit.expression() == Look.ANGRY, "set_expression holds an expression")
	spirit.show_expression(Look.SURPRISED, 0.5)
	_step(spirit, 0.3)
	_check(spirit.expression() == Look.SURPRISED, "show_expression shows one for a while")
	_step(spirit, 0.6)
	_check(spirit.expression() == Look.ANGRY, "and then the held expression comes back")
	# A seek places the face: no swap in progress, eyes fully open.
	spirit.show_expression(Look.SAD, 2.0)
	spirit.reset_motion()
	_check(spirit.expression() == Look.ANGRY and not spirit.face_art.swapping() and spirit.eyes[0].scale.y == 1.0, "A seek places the face at once")
	# The same seconds give the same face, eye for eye, however they are split.
	var twins: Array = []
	for split: Array in [[1.0 / 60.0], [1.0 / 30.0, 1.0 / 120.0, 1.0 / 120.0]]:
		var twin := Spirit.new()
		root.add_child(twin)
		twin.set_expression_role("b")
		twin.show_expression(Look.SAD, 1.0)
		var t := 0.0
		var index := 0
		while t < 1.5 - 0.0000001:
			var step: float = split[index % split.size()]
			twin.advance_motion(Vector3.ZERO, step, false)
			t += step
			index += 1
		twins.append(twin)
	var a: Node3D = twins[0]
	var b: Node3D = twins[1]
	_check(a.expression() == b.expression() and a.expression() == Look.NORMAL and not a.face_art.swapping() and not b.face_art.swapping(), "The same seconds give the same face at any frame rate")
	_check((a.face_art.material.get_shader_parameter(&"eye_squash") as Vector2).is_equal_approx(b.face_art.material.get_shader_parameter(&"eye_squash")) and (a.face_art.material.get_shader_parameter(&"eye_xy") as Vector4).is_equal_approx(b.face_art.material.get_shader_parameter(&"eye_xy")), "and the same eyes")
	for twin: Node in twins: twin.free()
	# A swap that lands exactly on the shut moment still finishes.
	var exact := Spirit.new()
	root.add_child(exact)
	exact.set_expression(Look.ANGRY)
	exact.advance_motion(Vector3.ZERO, exact.face_art.SWAP_CLOSE, false)
	exact.set_expression(Look.SAD)
	for _frame in range(30): exact.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	_check(exact.expression() == Look.SAD and not exact.face_art.swapping(), "A new expression asked for at the shut moment still shows")
	exact.free()
	# The shader declares every parameter the look sets.
	var names: Array = []
	for uniform: Dictionary in spirit.face_art.material.shader.get_shader_uniform_list(): names.append(str(uniform.name))
	var declared := true
	for key: String in spirit.face_art.SHAPE_KEYS + ["eye_xy", "eye_squash", "look_shift", "pupil_rim", "tear_neck_root", "body_color"]: declared = declared and names.has(key)
	_check(declared, "The face shader declares every parameter the look writes")
	spirit.free()

func _test_knocked_out_swaps() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.set_expression_role("a")
	_step(spirit, 0.5)
	# A swap closes, swaps and reopens onto the X.
	spirit.set_expression(Look.KNOCKED_OUT)
	_check(spirit.expression_target() == Look.KNOCKED_OUT and spirit.face_art.swapping(), "Knocked out arrives through the usual swap")
	_step(spirit, spirit.face_art.SWAP_DONE + 0.05)
	_check(spirit.expression() == Look.KNOCKED_OUT and not spirit.face_art.swapping(), "set_expression holds Knocked out")
	# Both eyes get the cross, with the stroke width.
	var ends: PackedVector4Array = spirit.face_art.material.get_shader_parameter(&"stroke_end")
	_check(ends.size() == 2 and ends[0].w == 2.0 and ends[1].w == 2.0 and ends[0].z > 0.0 and ends[1].z > 0.0, "Both eyes draw the X")
	# No blink through a whole blink cycle: the X stays at full height.
	var still := true
	for _frame in range(330):
		spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
		still = still and spirit.eyes[0].scale.y == 1.0 and spirit.eyes[1].scale.y == 1.0
	_check(still, "The X never blinks")
	# A timed X, then back to the held face.
	spirit.set_expression(Look.NORMAL, true)
	_check(spirit.expression() == Look.NORMAL and not spirit.face_art.swapping(), "An immediate change swaps at once")
	spirit.show_expression(Look.KNOCKED_OUT, 0.6)
	_step(spirit, 0.4)
	_check(spirit.expression() == Look.KNOCKED_OUT, "show_expression shows Knocked out for a while")
	_step(spirit, 0.6)
	_check(spirit.expression() == Look.NORMAL, "and then the held face comes back")
	# Immediate: drawn at once.
	spirit.set_expression(Look.KNOCKED_OUT, true)
	_check(spirit.expression() == Look.KNOCKED_OUT and not spirit.face_art.swapping() and spirit.eyes[0].scale.y == 1.0, "An immediate Knocked out is drawn at once")
	# A seek in the middle of a swap places the held X at once.
	spirit.set_expression(Look.NORMAL, true)
	spirit.set_expression(Look.KNOCKED_OUT)
	_step(spirit, 0.03)
	spirit.reset_motion()
	_check(spirit.expression() == Look.KNOCKED_OUT and not spirit.face_art.swapping() and spirit.eyes[0].scale.y == 1.0, "A seek mid swap places Knocked out at once")
	spirit.free()
	# Reduce motion: the X shows with no swap.
	var reduced := Spirit.new()
	root.add_child(reduced)
	reduced.advance_motion(Vector3.ZERO, 1.0 / 60.0, true)
	reduced.show_expression(Look.KNOCKED_OUT, 1.0)
	_check(reduced.expression() == Look.KNOCKED_OUT and not reduced.face_art.swapping(), "Under Reduce motion Knocked out shows without a swap")
	reduced.advance_motion(Vector3.ZERO, 1.2, true)
	_check(reduced.expression() == Look.NORMAL and not reduced.face_art.swapping(), "and goes back without one")
	reduced.free()
