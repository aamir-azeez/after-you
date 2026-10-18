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
const _SHAPE_KEYS: Array[String] = ["outer", "outer_wave", "outer_phase", "pupil", "pupil_wave", "pupil_phase", "cut", "tear", "tear_pupil", "stroke", "stroke_end"]

## Shader parameters per expression, both eyes, built on first use.
static var _shapes: Dictionary = {}

var material := ShaderMaterial.new()
## The expression drawn now, and the one asked for.
var shown: StringName = Look.NORMAL
var target: StringName = Look.NORMAL
var _swap_age := SWAP_DONE
var _eye_at := PackedVector4Array([Vector4.ZERO, Vector4.ZERO])
var _look_shift := Vector2.ZERO

func _init(body: Color) -> void:
	material.shader = SHADER
	material.set_shader_parameter("body_color", body)
	material.set_shader_parameter("cream_color", Look.CREAM)
	material.set_shader_parameter("pupil_color", Look.PUPIL)
	material.set_shader_parameter("eye_at", _eye_at)
	material.set_shader_parameter("look_shift", _look_shift)
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
	elif _swap_age > SWAP_CLOSE:
		# Reopening: close again from as far open as the eyes are now.
		_swap_age = SWAP_CLOSE * (1.0 - openness())

func advance(delta: float) -> void:
	if _swap_age >= SWAP_DONE: return
	var before := _swap_age
	_swap_age = minf(SWAP_DONE, _swap_age + maxf(delta, 0.0))
	if before < SWAP_CLOSE and _swap_age >= SWAP_CLOSE and shown != target:
		shown = target
		_upload(shown)

func swapping() -> bool:
	return _swap_age < SWAP_DONE

## 1 open, 0 shut, through a swap.
func openness() -> float:
	if _swap_age >= SWAP_DONE: return 1.0
	if _swap_age < SWAP_CLOSE: return 1.0 - smoothstep(0.0, SWAP_CLOSE, _swap_age)
	return smoothstep(SWAP_CLOSE, SWAP_DONE, _swap_age)

## Writes where the eyes are (each marker's x, y and its vertical scale, the
## blink) and the gaze, only when they changed.
func place_eyes(eyes: Array[Node3D], look: Vector2) -> void:
	var changed := false
	for index in range(2):
		var marker := eyes[index]
		var at := Vector4(marker.position.x, marker.position.y, marker.scale.y, 0.0)
		if at != _eye_at[index]:
			_eye_at[index] = at
			changed = true
	if changed: material.set_shader_parameter("eye_at", _eye_at)
	var shift := look * Look.PUPIL_LOOK
	if shift != _look_shift:
		_look_shift = shift
		material.set_shader_parameter("look_shift", _look_shift)

func _upload(expression: StringName) -> void:
	var shape: Dictionary = _shape(expression)
	for key: String in _SHAPE_KEYS: material.set_shader_parameter(key, shape[key])

static func _shape(expression: StringName) -> Dictionary:
	if not _shapes.has(expression):
		var left := Look.eye(expression, 0)
		var right := Look.eye(expression, 1)
		var shape := {}
		for key: String in _SHAPE_KEYS: shape[key] = PackedVector4Array([left[key], right[key]])
		_shapes[expression] = shape
	return _shapes[expression]
