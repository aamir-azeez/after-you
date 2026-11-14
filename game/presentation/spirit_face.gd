extends RefCounted
## A spirit's face: the head's material, which paints the eyes
## (spirit_face.gdshader), and the expression it shows. A change of expression
## closes the eyes, swaps the shape while they are shut and opens them again;
## a placement or Reduce motion swaps at once. The face keeps its own small
## clock, advanced only by the spirit, so a replay shows the same face at the
## same moment.
##
## A moving face (spirit_look.gd ANIMATED) runs on face_time, which starts at 0
## each time the face is put on and moves only with the spirit's own steps, so
## live play, the memory and a replay show the same frame at the same moment.
## Under Reduce motion it holds its first frame. While it moves, a step writes
## only the uniforms that face changes (spirit_look.gd MOTION_KEYS) and only
## when they changed; a still face writes nothing per step.
##
## A resting face (spirit_look.gd REST_FACES, worn in the "rest_face" slot)
## stands in for NORMAL: `shown` and `target` stay NORMAL, so every caller
## that asks for the everyday face gets it, and drawn() names what is painted.

const Look = preload("res://presentation/spirit_look.gd")
const SHADER = preload("res://presentation/spirit_face.gdshader")
const SWAP_CLOSE := 0.07
const SWAP_OPEN := 0.11
const SWAP_DONE := SWAP_CLOSE + SWAP_OPEN
## The shader parameters each expression sets (spirit_look.gd eye()).
const SHAPE_KEYS: Array[String] = ["outer", "outer_wave", "outer_phase", "pupil", "pupil_wave", "pupil_phase", "cut", "tear", "tear_pupil", "stroke", "stroke_end", "blush", "eye_shape", "tear_stream", "tear_stream_end", "shine", "shine_size", "mark", "mark_spin"]

## Shader parameters per expression, both eyes, built on first use.
static var _shapes: Dictionary = {}

var material := ShaderMaterial.new()
## The expression drawn now, and the one asked for.
var shown: StringName = Look.NORMAL
var target: StringName = Look.NORMAL
var _swap_age := SWAP_DONE
var _eye_xy := Vector4.ZERO
var _eye_squash := Vector2.ONE
var _look_shift := Vector2.ZERO
## The resting face painted for NORMAL (NORMAL itself is Classic).
var rest: StringName = Look.NORMAL
## Seconds the moving face has shown, on the spirit's clock (0 for a still face).
var face_time := 0.0
## Whether the face painted now moves, and the motion uniforms last written.
var _moving := false
var _written: Dictionary = {}
## How many motion uniforms the moving faces have written (tests read it).
var motion_writes := 0

## The body colour the face is drawn in.
var body: Color

func _init(body_color: Color) -> void:
	body = body_color
	material.shader = SHADER
	_upload_all()

## Draws the face with `shader` (SHADER, or a body cosmetic's variant of it,
## which takes the same parameters) and sends every parameter again, so the
## eyes stand exactly as they did. extra: the variant's own parameters.
func set_shader(shader: Shader, extra: Dictionary = {}) -> void:
	material.shader = shader
	_upload_all()
	for key: String in extra: material.set_shader_parameter(key, extra[key])

func _upload_all() -> void:
	material.set_shader_parameter("body_color", body)
	material.set_shader_parameter("cream_color", Look.CREAM)
	material.set_shader_parameter("pupil_color", Look.PUPIL)
	material.set_shader_parameter(&"blush_color", Look.BLUSH)
	material.set_shader_parameter(&"blush_strength", Look.BLUSH_STRENGTH)
	material.set_shader_parameter(&"blush_soft", Look.BLUSH_SOFT)
	material.set_shader_parameter(&"heart_color", Look.HEART_RED)
	material.set_shader_parameter(&"heart_middle", Look.HEART_MIDDLE)
	material.set_shader_parameter(&"star_round", Look.STAR_ROUND)
	material.set_shader_parameter(&"eye_xy", _eye_xy)
	material.set_shader_parameter(&"eye_squash", _eye_squash)
	material.set_shader_parameter(&"look_shift", _look_shift)
	material.set_shader_parameter(&"pupil_rim", Look.RIM)
	material.set_shader_parameter(&"tear_neck_root", Look.TEAR_NECK_ROOT)
	material.set_shader_parameter(&"leaf_color", Look.LEAF)
	material.set_shader_parameter(&"spark_color", Look.SPARK)
	# A new shader keeps the moving face where its clock is.
	_upload(shown, false)

## Wears `expression` as the resting face (spirit_look.gd REST_FACES); any
## other value, "" among them, is Classic (NORMAL). Shown at once if the pip
## rests now.
func set_rest(expression: StringName) -> void:
	var face := expression if Look.is_rest_face(expression) else Look.NORMAL
	if face == rest: return
	rest = face
	if shown == Look.NORMAL: _upload(shown)

## The expression painted now: `shown`, with the resting face for NORMAL.
func drawn() -> StringName:
	return rest if shown == Look.NORMAL else shown

## Whether the face painted now moves on its own clock.
func moving() -> bool:
	return _moving

## Asks for `expression`. With `immediate` it is drawn at once; otherwise the
## eyes close, swap and reopen. Asking again for the target does nothing.
func request(expression: StringName, immediate: bool) -> void:
	if immediate:
		target = expression
		_swap_age = SWAP_DONE
		if shown != target:
			shown = target
			_upload(shown)
		return
	if expression == target: return
	target = expression
	if _swap_age >= SWAP_DONE:
		if shown != target: _swap_age = 0.0
	elif _swap_age >= SWAP_CLOSE:
		# Reopening: close again from as far open as the eyes are now.
		_swap_age = SWAP_CLOSE * (1.0 - openness())

## One step of the spirit's clock: the swap, then a moving face's frame.
## `reduced` (Reduce motion) holds a moving face on its first frame.
func advance(delta: float, reduced: bool = false) -> void:
	if _swap_age < SWAP_DONE:
		_swap_age = minf(SWAP_DONE, _swap_age + maxf(delta, 0.0))
		# Shut (or past it) with the wrong shape: swap now.
		if _swap_age >= SWAP_CLOSE and shown != target:
			shown = target
			_upload(shown)
	if not _moving: return
	if reduced:
		if face_time == 0.0: return
		face_time = 0.0
	else: face_time += maxf(delta, 0.0)
	_animate()

func swapping() -> bool:
	return _swap_age < SWAP_DONE

## 1 open, 0 shut, through a swap.
func openness() -> float:
	if _swap_age >= SWAP_DONE: return 1.0
	# Closing is linear, so an interrupted reopen closes from where it is.
	if _swap_age < SWAP_CLOSE: return 1.0 - _swap_age / SWAP_CLOSE
	return smoothstep(SWAP_CLOSE, SWAP_DONE, _swap_age)

## Writes where the eyes are (each marker's x, y and its vertical scale, the
## blink) and the gaze, only when they changed. Plain values: nothing is
## allocated per frame.
func place_eyes(eyes: Array[Node3D], look: Vector2) -> void:
	var xy := Vector4(eyes[0].position.x, eyes[0].position.y, eyes[1].position.x, eyes[1].position.y)
	if xy != _eye_xy:
		_eye_xy = xy
		material.set_shader_parameter(&"eye_xy", _eye_xy)
	var squash := Vector2(eyes[0].scale.y, eyes[1].scale.y)
	if squash != _eye_squash:
		_eye_squash = squash
		material.set_shader_parameter(&"eye_squash", _eye_squash)
	var shift := look * Look.PUPIL_LOOK
	if shift != _look_shift:
		_look_shift = shift
		material.set_shader_parameter(&"look_shift", _look_shift)

## Paints `expression` (the resting face for NORMAL). `restart` starts a
## moving face's clock again; a shader change keeps it.
func _upload(expression: StringName, restart: bool = true) -> void:
	var face := rest if expression == Look.NORMAL else expression
	var shape: Dictionary = _shape(face)
	for key: String in SHAPE_KEYS: material.set_shader_parameter(key, shape[key])
	_moving = Look.is_animated(face)
	_written.clear()
	if restart or not _moving: face_time = 0.0
	if not _moving: return
	for key: String in Look.MOTION_KEYS[face]: _written[key] = shape[key]
	if face_time > 0.0: _animate()

## Writes the moving face's frame at face_time: only its motion uniforms, and
## only those that changed.
func _animate() -> void:
	var face := drawn()
	var left := Look.eye_at(face, 0, face_time)
	var right := Look.eye_at(face, 1, face_time)
	for key: String in Look.MOTION_KEYS[face]:
		var value := PackedVector4Array([left[key], right[key]])
		if value == _written.get(key): continue
		_written[key] = value
		material.set_shader_parameter(key, value)
		motion_writes += 1

## Both eyes' uniforms for an expression at rest (a moving face's first
## frame), worked out once.
static func _shape(expression: StringName) -> Dictionary:
	if not _shapes.has(expression):
		var left := Look.still(expression, 0)
		var right := Look.still(expression, 1)
		var shape := {}
		for key: String in SHAPE_KEYS: shape[key] = PackedVector4Array([left[key], right[key]])
		_shapes[expression] = shape
	return _shapes[expression]
