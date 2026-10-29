extends RefCounted
## A spirit's face: the head's material, which paints the eyes
## (spirit_face.gdshader), and the expression it shows. A change of expression
## closes the eyes, swaps the shape while they are shut and opens them again;
## a placement or Reduce motion swaps at once. The face keeps its own small
## clock, advanced only by the spirit, so a replay shows the same face at the
## same moment.

const Look = preload("res://presentation/spirit_look.gd")
const SHADER = preload("res://presentation/spirit_face.gdshader")
const SWAP_CLOSE := 0.07
const SWAP_OPEN := 0.11
const SWAP_DONE := SWAP_CLOSE + SWAP_OPEN
## The shader parameters each expression sets (spirit_look.gd eye()).
const SHAPE_KEYS: Array[String] = ["outer", "outer_wave", "outer_phase", "pupil", "pupil_wave", "pupil_phase", "cut", "tear", "tear_pupil", "stroke", "stroke_end", "blush", "eye_shape", "tear_stream", "tear_stream_end"]

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
	_upload(shown)

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

func advance(delta: float) -> void:
	if _swap_age >= SWAP_DONE: return
	_swap_age = minf(SWAP_DONE, _swap_age + maxf(delta, 0.0))
	# Shut (or past it) with the wrong shape: swap now.
	if _swap_age >= SWAP_CLOSE and shown != target:
		shown = target
		_upload(shown)

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

func _upload(expression: StringName) -> void:
	var shape: Dictionary = _shape(expression)
	for key: String in SHAPE_KEYS: material.set_shader_parameter(key, shape[key])

static func _shape(expression: StringName) -> Dictionary:
	if not _shapes.has(expression):
		var left := Look.eye(expression, 0)
		var right := Look.eye(expression, 1)
		var shape := {}
		for key: String in SHAPE_KEYS: shape[key] = PackedVector4Array([left[key], right[key]])
		_shapes[expression] = shape
	return _shapes[expression]
