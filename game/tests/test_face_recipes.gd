extends SceneTree
## The face cosmetics' recipes (faces concept boards, approved 2026-11-13): every
## single reaction face and resting face in the face shader and the flat art,
## the moving faces on the face's own clock (the same frame at the same second,
## held still under Reduce motion, started again by a new face, writing only
## what moves), and a resting face standing in for Normal.

const Look = preload("res://presentation/spirit_look.gd")
const SpiritFace = preload("res://presentation/spirit_face.gd")
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const Outfit = preload("res://services/outfit.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
		print("FAIL: ", message)

func _run() -> void:
	_table()
	_flat_parts()
	_motion()
	_clock()
	_rest_face()
	_blink()
	print("FACE RECIPES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _area(polygons: Array) -> float:
	var total := 0.0
	for polygon: PackedVector2Array in polygons:
		var area := 0.0
		for index in range(polygon.size()): area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
		total += absf(area) * 0.5
	return total

func _table() -> void:
	_check(Look.REACTION_FACES.size() == 16 and Look.REST_FACES.size() == 5, "Sixteen reaction faces and five resting faces (Classic is Normal)")
	var ids: Array[String] = ["aww", "shy", "huh", "please", "touched", "lucky", "giggle", "curious", "nervous", "drowsy", "gasp", "peekaboo", "yay", "smitten", "starry", "flower"]
	_check(Look.REACTION_FACES.map(func(face: StringName) -> String: return str(face)) == ids, "The reaction faces keep their reaction ids, in shop order")
	_check(Look.REST_FACES == [&"rest_button", &"rest_bean", &"rest_round", &"rest_wide", &"rest_sprout"], "The resting faces keep their item ids")
	for face: StringName in Look.REACTION_FACES + Look.REST_FACES:
		_check(Look.has(face), "%s is an expression" % face)
		var shape: Dictionary = SpiritFace._shape(face)
		_check(SpiritFace.SHAPE_KEYS.all(func(key: String) -> bool: return shape.has(key) and (shape[key] as PackedVector4Array).size() == 2), "%s sets every face shader parameter for both eyes" % face)
		for index in range(2):
			var flat := Look.eye_contours(face, index)
			_check(_area(flat.outer) + _area(flat.pupil) > 0.0 or not (flat.strokes as Array).is_empty(), "%s eye %d draws flat" % [face, index])
	for face: StringName in Look.REST_FACES: _check(Look.is_open(face) and not Look.is_animated(face), "%s is an open, still face, so it blinks and looks around" % face)
	for face: StringName in Look.ANIMATED:
		_check(face in Look.REACTION_FACES and Look.MOTION_LOOP.has(face) and Look.MOTION_KEYS.has(face), "%s moves with a loop and the uniforms it moves" % face)
		for key: String in Look.MOTION_KEYS[face]: _check(key in SpiritFace.SHAPE_KEYS, "%s moves %s, a face shader parameter" % [face, key])
	# The shader declares every parameter the look writes.
	var names: Array = []
	for uniform: Dictionary in (SpiritFace.SHADER as Shader).get_shader_uniform_list(): names.append(str(uniform.name))
	for key: String in SpiritFace.SHAPE_KEYS + ["leaf_color", "spark_color"]: _check(names.has(key), "The face shader declares %s" % key)

func _flat_parts() -> void:
	var please := Look.eye_contours(Look.PLEASE, 0)
	_check((please.get("shines", []) as Array).size() == 2 and _area(please.shines) < _area(please.pupil) * 0.3, "Please: two cream shines inside the pupil")
	var starry := Look.eye_contours(Look.STARRY, 1)
	_check((starry.get("shines", []) as Array).size() == 3, "Starry: three sparkles in the pupil")
	var lucky := Look.eye_contours(Look.LUCKY, 0)
	_check(lucky.get("pupil_color") == Look.LEAF and _area(lucky.pupil) > 0.0 and _area(lucky.pupil) < _area(lucky.outer), "Lucky: a leaf green clover inside the cream")
	var flower := Look.eye_contours(Look.FLOWER, 0)
	_check(flower.get("pupil_color") == Look.HEART_RED and (flower.get("shines", []) as Array).size() == 1, "Flower: a red flower pupil with a cream middle")
	_check(Look.eye_contours(Look.REST_SPROUT, 1).get("pupil_color") == Look.LEAF, "Sprout: leaf green pupils")
	_check(not Look.eye_contours(Look.REST_BEAN, 0).has("pupil_color") and not Look.eye_contours(Look.NORMAL, 0).has("shines"), "Bean and Classic keep the navy pupil, no shine")
	for index in range(2):
		var yay := Look.eye_contours(Look.YAY, index)
		_check((yay.get("marks", []) as Array).size() == 1 and yay.get("mark_color") == Look.SPARK and not yay.has("blush") and (yay.strokes as Array).size() == 1, "Yay eye %d: a happy arc and a gold sparkle, no cheeks (Joy has those)" % index)
		# The sparkle sits off the eye's outer side, never over the eye like a brow.
		var mark: Vector4 = Look.eye(Look.YAY, index).mark
		var outward := mark.x * (-1.0 if index == 0 else 1.0)
		_check(outward > 0.07, "Yay eye %d: the sparkle is out past the eye's outer edge" % index)
	_check(Look.eye_contours(Look.SMITTEN, 1).get("pupil_color") == Look.HEART_RED and not (Look.eye_contours(Look.SMITTEN, 0).strokes as Array).is_empty(), "Smitten: one heart eye and one shut in an arc")
	_check((Look.eye_contours(Look.TOUCHED, 0).get("shines", []) as Array).size() == 1 and Look.eye_contours(Look.TOUCHED, 0).has("blush"), "Touched: a shine, a tear and cheeks")
	_check(Look.eye_contours(Look.NERVOUS, 1).has("streams") and not Look.eye_contours(Look.NERVOUS, 0).has("streams"), "Nervous: one drop at the temple")

func _motion() -> void:
	for face: StringName in Look.ANIMATED:
		var loop: float = Look.MOTION_LOOP[face]
		var moved := false
		var outside_still := true
		for index in range(2):
			var rest := Look.still(face, index)
			_check(Look.eye_at(face, index, 0.0) == rest, "%s eye %d: the still face is its first frame" % [face, index])
			for step in range(40):
				var t := loop * float(step) / 40.0 + 0.013
				var frame := Look.eye_at(face, index, t)
				if step % 10 == 0: _check(frame == Look.eye_at(face, index, t), "%s eye %d is the same at %.3f s every time" % [face, index, t])
				for key: String in SpiritFace.SHAPE_KEYS:
					if frame[key] == rest[key]: continue
					if key in Look.MOTION_KEYS[face]: moved = true
					else: outside_still = false
		_check(moved, "%s moves along its loop" % face)
		_check(outside_still, "%s moves only the uniforms it lists" % face)
	for face: StringName in Look.REACTION_FACES:
		if face in Look.ANIMATED: continue
		_check(Look.eye_at(face, 0, 1.7) == Look.eye(face, 0), "%s holds still" % face)

func _clock() -> void:
	var face := SpiritFace.new(Look.PEACH)
	face.request(Look.GIGGLE, true)
	_check(face.moving() and face.face_time == 0.0, "A moving face starts its clock at 0")
	face.advance(0.25)
	_check(is_equal_approx(face.face_time, 0.25), "Only the spirit's steps move it")
	var expected := PackedVector4Array([Look.eye_at(Look.GIGGLE, 0, 0.25).stroke, Look.eye_at(Look.GIGGLE, 1, 0.25).stroke])
	_check(face.material.get_shader_parameter(&"stroke") == expected, "The shader shows the frame at the clock's second")
	# The same seconds at another frame rate give the same frame.
	var twin := SpiritFace.new(Look.PEACH)
	twin.request(Look.GIGGLE, true)
	for i in range(15): twin.advance(1.0 / 60.0)
	twin.advance(0.0)
	var other := SpiritFace.new(Look.PEACH)
	other.request(Look.GIGGLE, true)
	for i in range(5): other.advance(0.05)
	var a: PackedVector4Array = twin.material.get_shader_parameter(&"stroke")
	var b: PackedVector4Array = other.material.get_shader_parameter(&"stroke")
	_check(a[0].is_equal_approx(b[0]) and a[1].is_equal_approx(b[1]), "Live play, the memory and a replay match at the same second, whatever the frame rate")
	# Reduce motion holds the first frame.
	face.advance(0.1, true)
	_check(face.face_time == 0.0 and face.material.get_shader_parameter(&"stroke") == SpiritFace._shape(Look.GIGGLE).stroke, "Reduce motion holds the first frame")
	var held := face.motion_writes
	for i in range(10): face.advance(0.1, true)
	_check(face.motion_writes == held, "and writes nothing more while it holds")
	# A new face starts the clock again.
	face.advance(0.4)
	face.request(Look.STARRY, true)
	_check(face.face_time == 0.0 and face.moving(), "A new moving face starts at 0")
	face.request(Look.HAPPY, true)
	_check(not face.moving() and face.face_time == 0.0, "A still face has no clock")
	var still_writes := face.motion_writes
	for i in range(30): face.advance(1.0 / 30.0)
	_check(face.motion_writes == still_writes, "A still face writes no uniform on a step")
	# Peekaboo writes only when its peek opens or closes.
	face.request(Look.PEEKABOO, true)
	var before := face.motion_writes
	for i in range(20): face.advance(0.04)
	_check(face.motion_writes == before, "Peekaboo writes nothing while it stays shut")
	for i in range(10): face.advance(0.04)
	_check(face.motion_writes > before, "and writes once its eye opens")
	# A swap through the usual close and open restarts it once the new face shows.
	face.request(Look.FLOWER, false)
	for i in range(20): face.advance(1.0 / 60.0)
	_check(face.shown == Look.FLOWER and face.moving() and face.face_time < 0.34, "A swapped in moving face counts from when it shows")
	# A body cosmetic's shader keeps the clock where it is.
	var at := face.face_time
	face.set_shader(SpiritFace.SHADER)
	_check(is_equal_approx(face.face_time, at) and face.moving(), "A new shader keeps the moving face's clock")

func _rest_face() -> void:
	var face := SpiritFace.new(Look.MINT)
	face.set_rest(Look.REST_BUTTON)
	_check(face.shown == Look.NORMAL and face.drawn() == Look.REST_BUTTON, "A resting face shows in place of Normal")
	_check(face.material.get_shader_parameter(&"outer") == SpiritFace._shape(Look.REST_BUTTON).outer and face.material.get_shader_parameter(&"shine") == SpiritFace._shape(Look.REST_BUTTON).shine, "and the shader draws it")
	face.set_shader(SpiritFace.SHADER)
	_check(face.material.get_shader_parameter(&"outer") == SpiritFace._shape(Look.REST_BUTTON).outer, "A body cosmetic's shader keeps the resting face")
	face.request(Look.SAD, true)
	_check(face.drawn() == Look.SAD, "A reaction shows over it")
	face.request(Look.NORMAL, true)
	_check(face.drawn() == Look.REST_BUTTON, "and it comes back after")
	face.set_rest(&"rest_rosy")
	_check(face.rest == Look.NORMAL and face.drawn() == Look.NORMAL, "An unknown resting face is Classic")
	face.set_rest(Look.HAPPY)
	_check(face.rest == Look.NORMAL, "A reaction face is never a resting face")
	# Worn through the outfit, as every pip on every screen is dressed.
	if "rest_face" in Catalog.slots() and Catalog.has("rest_bean"):
		Outfit.show_unreleased = true
		var pip := SpiritVisual.new(Look.PEACH)
		root.add_child(pip)
		pip.wear({"rest_face": "rest_bean"})
		_check(pip.face_art.drawn() == Look.REST_BEAN and pip.expression() == Look.NORMAL, "Wearing a resting face puts it on the pip")
		pip.wear({})
		_check(pip.face_art.drawn() == Look.NORMAL, "Taking it off goes back to Classic")
		pip.free()
		Outfit.show_unreleased = false

func _blink() -> void:
	# Classic keeps today's blink exactly: shut most at 3.89 s, open outside 3.8 to 3.98 s.
	_check(Look.blink(Look.NORMAL, 3.7, 0.0) == Vector2.ONE and Look.blink(Look.NORMAL, 4.0, 0.0) == Vector2.ONE, "Classic is open outside its blink")
	var deep := Look.blink(Look.NORMAL, 3.89, 0.0)
	_check(is_equal_approx(deep.x, 1.0 - 0.94) and deep.x == deep.y, "Classic shuts both eyes together, as today")
	for face: StringName in [Look.REST_BEAN, Look.REST_WIDE, Look.REST_SPROUT]: _check(Look.blink(face, 3.89, 0.0) == deep, "%s blinks as today" % face)
	_check(Look.blink(Look.REST_BUTTON, 3.85, 0.0).x < 0.2 and Look.blink(Look.REST_BUTTON, 3.92, 0.0) == Vector2.ONE, "Button blinks quickly")
	var first := Look.blink(Look.REST_ROUND, 3.89, 0.0)
	var second := Look.blink(Look.REST_ROUND, 4.11, 0.0)
	_check(first.x < 0.2 and first.y == 1.0 and second.x == 1.0 and second.y < 0.2, "Round blinks one eye, then the other")
