extends Node
signal frame_applied
## Presentation-only pan/zoom. Owners provide the authored frame and UI policy.
const RETURN_DELAY := 5.0
const RETURN_DURATION := 0.7
const SYNTHETIC_MOUSE := -1
var camera: Camera3D
var active: Callable
var allowed: Callable
var reduced_motion: Callable
var manual := false
var auto_return := true
var minimum_zoom := 0.52
var maximum_zoom := 1.18
var maximum_pan := Vector2(0.38, 0.30)
var zoom_ratio := 1.0
var pan := Vector2.ZERO
var touches: Dictionary = {}
var pinch_span := 0.0
var _centroid := Vector2.ZERO
var _mouse_button := 0
var _mouse_position := Vector2.ZERO
var _idle := 0.0
var _return_age := 0.0
var _return_zoom := 1.0
var _return_pan := Vector2.ZERO
var _returning := false
var _foreground := true
var _frame: Dictionary = {}

func _ready() -> void:
	# Worlds finish their authored framing before this child composes offsets.
	process_priority = 100

func is_active() -> bool:
	return _foreground and active.is_valid() and active.call() == true

func _input(event: InputEvent) -> void:
	if manual: return
	if not is_active():
		cancel_gesture()
		return
	if handle_event(event): get_viewport().set_input_as_handled()

func handle_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			if touches.has(event.index):
				touches.erase(event.index)
				_rebase_touches()
				_activity()
		elif touches.size() < 2 and _allowed(event.position):
			touches[event.index] = event.position
			_rebase_touches()
			_activity()
		return false # A first finger never consumes a UI action.
	if event is InputEventScreenDrag and touches.has(event.index):
		touches[event.index] = event.position
		if touches.size() != 2: return false
		var points := touches.values()
		var next_center: Vector2 = (Vector2(points[0]) + Vector2(points[1])) * 0.5
		var next_span := Vector2(points[0]).distance_to(Vector2(points[1]))
		if next_span > 12.0 and pinch_span > 12.0:
			zoom(pinch_span / next_span)
		pan_pixels(next_center - _centroid)
		_centroid = next_center
		pinch_span = next_span
		_activity()
		return true
	if event is InputEventMouse and (event.device == SYNTHETIC_MOUSE or not touches.is_empty()):
		return false
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index == _mouse_button:
			_mouse_button = 0
			_activity()
			return true
		if event.pressed and _allowed(event.position):
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				zoom(0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88)
				return true
			if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
				_mouse_button = event.button_index
				_mouse_position = event.position
				_activity()
				return true
	if event is InputEventMouseMotion and _mouse_button != 0:
		pan_pixels(event.position - _mouse_position)
		_mouse_position = event.position
		return true
	if event is InputEventMagnifyGesture and touches.size() < 2 and _allowed(event.position) and event.factor > 0.0:
		zoom(1.0 / event.factor)
		return true
	return false

func _allowed(point: Vector2) -> bool:
	return point.is_finite() and allowed.is_valid() and allowed.call(point) == true

func _rebase_touches() -> void:
	pinch_span = 0.0
	if touches.size() == 2:
		var points := touches.values()
		pinch_span = Vector2(points[0]).distance_to(Vector2(points[1]))
		_centroid = (Vector2(points[0]) + Vector2(points[1])) * 0.5

func _activity() -> void:
	_idle = 0.0
	_returning = false

func zoom(factor: float) -> void:
	if not is_finite(factor) or factor <= 0.0: return
	zoom_ratio = clampf(zoom_ratio * factor, minimum_zoom, maximum_zoom)
	_activity()

func pan_pixels(displacement: Vector2) -> void:
	if not displacement.is_finite(): return
	var height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	# Normalized camera-plane offsets keep bounds stable across aspect ratios.
	pan += Vector2(-displacement.x, displacement.y) * zoom_ratio / height
	pan = pan.clamp(-maximum_pan, maximum_pan)
	_activity()

func cancel_gesture() -> void:
	touches.clear()
	pinch_span = 0.0
	_mouse_button = 0

func reset_view() -> void:
	restore_frame()
	cancel_gesture()
	zoom_ratio = 1.0
	pan = Vector2.ZERO
	_activity()

func advance(delta: float, reduce_motion: bool) -> void:
	if not auto_return or touches.size() == 2 or _mouse_button != 0: return
	var step := maxf(0.0, delta) if is_finite(delta) else 0.0
	_idle += step
	if _idle < RETURN_DELAY: return
	if not _returning:
		_returning = true
		_return_age = maxf(0.0, _idle - RETURN_DELAY)
		_return_zoom = zoom_ratio
		_return_pan = pan
	else:
		_return_age += step
	var fraction := 1.0 if reduce_motion else clampf(_return_age / RETURN_DURATION, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, fraction)
	zoom_ratio = lerpf(_return_zoom, 1.0, eased)
	pan = _return_pan.lerp(Vector2.ZERO, eased)

func restore_frame() -> void:
	if is_instance_valid(camera) and not _frame.is_empty():
		camera.transform = _frame.transform
		camera.size = _frame.size
		camera.h_offset = _frame.h_offset
		camera.v_offset = _frame.v_offset
	_frame.clear()

func apply_frame() -> void:
	if not is_instance_valid(camera): return
	restore_frame()
	_frame = {"transform": camera.transform, "size": camera.size, "h_offset": camera.h_offset, "v_offset": camera.v_offset}
	var authored_size := camera.size
	camera.size = authored_size * zoom_ratio
	apply_pan(camera, authored_size)
	frame_applied.emit()

func apply_pan(target: Camera3D, authored_size: float) -> void:
	# Translation in the camera plane never changes walking orientation.
	target.position += target.basis.x * pan.x * authored_size + target.basis.y * pan.y * authored_size

func _process(delta: float) -> void:
	if manual: return
	if not is_active():
		cancel_gesture()
		return
	advance(delta, reduced_motion.is_valid() and reduced_motion.call() == true)
	apply_frame()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_foreground = false
		cancel_gesture()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_foreground = true

func _exit_tree() -> void:
	restore_frame()
	cancel_gesture()

static func ui_blocks(node: Node, point: Vector2) -> bool:
	if not is_instance_valid(node): return false
	if node is CanvasLayer and not node.visible: return false
	if node is CanvasItem and not node.is_visible_in_tree(): return false
	if node is Control and node.get_global_rect().has_point(point):
		if node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.has_meta("player_slot"):
			return true
	for child: Node in node.get_children():
		if ui_blocks(child, point): return true
	return false
