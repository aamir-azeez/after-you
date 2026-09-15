extends Control
## Home-only presentation. No simulation, recordings, persistence or account I/O.
const DEFAULT_SIZE := 15.7
const MIN_SIZE := 8.0
const MAX_SIZE := 18.5
const WALK_SPEED := 0.52
const SEPARATION := 0.92
var zoom_target := DEFAULT_SIZE
var zoom_size := DEFAULT_SIZE
var _world: Node3D
var _active: Callable
var _terrain: Node3D
var _camera: Camera3D
var _actors: Dictionary = {}
var _saved: Dictionary = {}
var _goals: Dictionary = {}
var _rests: Dictionary = {}
var _floor := Rect2()
var _camera_transform := Transform3D.IDENTITY
var _camera_size := DEFAULT_SIZE
var _camera_offsets := Vector2.ZERO
var _touches: Dictionary = {}
var _pinch_span := 0.0
var _foreground := true
var _random := RandomNumberGenerator.new()
var _reset: Button
var _hint: Label

func configure(world: Node3D, active: Callable) -> void:
	_world = world
	_active = active

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not is_instance_valid(_world) or not is_instance_valid(_world.camera):
		return
	_terrain = _world.terrain
	_camera = _world.camera
	_camera_transform = _world.camera.global_transform
	_camera_size = _world.camera.size
	_camera_offsets = Vector2(_world.camera.h_offset,_world.camera.v_offset)
	_random.seed = 64107
	var bounds: Array = _world.current_level.get("bounds",[-560,-290,560,290])
	var gap: Array = _world.current_level.get("gap",[-100,100])
	_floor = Rect2(float(bounds[0])/100.0+0.65,float(bounds[1])/100.0+0.85,
		float(gap[0]-bounds[0])/100.0-1.3,float(bounds[3]-bounds[1])/100.0-1.7)
	if _floor.size.x<2.0 or _floor.size.y<2.0:
		return
	for role: String in _world.actors:
		var actor: Node3D = _world.actors[role]
		_actors[role] = actor
		_saved[role] = {"position":actor.position,"target":_world.actor_targets[role],"visible":actor.visible}
		var center := _floor.get_center()
		var offset := Vector2(-0.68,0.42) if _actors.size()==1 else Vector2(0.68,-0.42)
		actor.position = Vector3(center.x+offset.x,0,center.y+offset.y)
		actor.visible = true
		actor.reset_motion()
		_world.actor_targets[role] = actor.position
		_goals[role] = actor.position
		_rests[role] = 0.7 if _actors.size()==1 else 1.4
	_world.home_presentation_owner = get_instance_id()
	_reset = Button.new()
	_reset.text = "Reset view"
	_reset.custom_minimum_size = Vector2(116,36)
	_reset.add_theme_font_size_override("font_size",16)
	_reset.pressed.connect(func(): zoom_target = DEFAULT_SIZE)
	add_child(_reset)
	_hint = Label.new()
	_hint.text = "Pinch to look closer" if OS.has_feature("android") else "Scroll to look closer"
	_hint.add_theme_font_size_override("font_size",16)
	_hint.add_theme_color_override("font_color",Color("a6c6b8"))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_layout()
	_frame_camera()

func _stage_rect() -> Rect2:
	var rect := get_global_rect()
	var left := minf(470.0,rect.size.x*0.52)
	return Rect2(rect.position+Vector2(left,40),Vector2(maxf(100,rect.size.x-left-24),maxf(100,rect.size.y-138)))

func _layout() -> void:
	if not is_instance_valid(_reset): return
	var rect := _stage_rect()
	_reset.position = rect.position-global_position+Vector2(rect.size.x-116,0)
	_reset.size = Vector2(116,36)
	_hint.position = rect.position-global_position+Vector2(12,rect.size.y-20)
	_reset.visible = not is_equal_approx(zoom_target,DEFAULT_SIZE)

func _is_active() -> bool:
	return is_inside_tree() and is_visible_in_tree() and _foreground and is_instance_valid(_world) and _world.visible and _world.home_view and _world.terrain==_terrain and _world.home_presentation_owner==get_instance_id() and _active.is_valid() and _active.call()

func _allowed(point: Vector2) -> bool:
	return _stage_rect().has_point(point) and not (is_instance_valid(_reset) and _reset.visible and _reset.get_global_rect().has_point(point))

func _input(event: InputEvent) -> void:
	if not _is_active():
		_cancel_gesture()
		return
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			if _touches.has(event.index):
				_touches.erase(event.index)
				_pinch_span = 0.0
		elif _touches.size()<2 and _allowed(event.position):
			_touches[event.index] = event.position
			_pinch_span = _span()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		var span := _span()
		if span>12.0 and _pinch_span>12.0:
			_zoom(_pinch_span/span)
			get_viewport().set_input_as_handled()
		_pinch_span = span

func _gui_input(event: InputEvent) -> void:
	if not _is_active(): return
	if event is InputEventMouseButton and event.pressed and _allowed(global_position+event.position):
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom(0.88 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/0.88)
			accept_event()
	elif event is InputEventMagnifyGesture and _touches.size()<2 and _allowed(global_position+event.position) and event.factor>0.0:
		_zoom(1.0/event.factor)
		accept_event()

func _zoom(factor: float) -> void:
	if is_finite(factor) and factor>0.0:
		zoom_target = clampf(zoom_target*factor,MIN_SIZE,MAX_SIZE)

func _span() -> float:
	if _touches.size()!=2: return 0.0
	var values := _touches.values()
	return Vector2(values[0]).distance_to(Vector2(values[1]))

func _cancel_gesture() -> void:
	_touches.clear()
	_pinch_span = 0.0

func _process(delta: float) -> void:
	if not _is_active():
		_cancel_gesture()
		return
	var step := clampf(delta,0.0,0.05)
	_layout()
	zoom_size = zoom_target if _world.reduced_motion else lerpf(zoom_size,zoom_target,1.0-exp(-12.0*step))
	_frame_camera()
	for role: String in _actors:
		var actor: Node3D = _actors[role]
		var previous := actor.position
		if not _world.reduced_motion:
			if float(_rests[role])>0:
				_rests[role] = maxf(0,float(_rests[role])-step)
			elif actor.position.distance_to(_goals[role])<0.025:
				_choose_goal(role)
			else:
				var candidate := actor.position.move_toward(_goals[role],WALK_SPEED*step)
				if _clear_position(role,candidate):
					actor.position = candidate
				else:
					_choose_goal(role)
		_world.actor_targets[role] = actor.position
		actor.advance_motion(actor.position-previous,step,_world.reduced_motion)

func _frame_camera() -> void:
	var camera: Camera3D = _world.camera
	var viewport := get_viewport_rect()
	var rect := _stage_rect()
	var zoom := clampf((DEFAULT_SIZE-zoom_size)/(DEFAULT_SIZE-MIN_SIZE),0,1)
	var center := _floor.get_center()
	var focus := Vector3.ZERO.lerp(Vector3(center.x,0.35,center.y),zoom)
	camera.global_transform = _camera_transform
	camera.global_position += _world.global_basis*focus
	camera.size = zoom_size
	# KEEP_HEIGHT is the existing orthographic camera mode. Offsets place the
	# world in the clear right-side stage at every supported landscape width.
	var units_per_pixel := zoom_size/maxf(viewport.size.y,1)
	var offset := rect.get_center()-viewport.get_center()
	camera.h_offset = -offset.x*units_per_pixel
	camera.v_offset = offset.y*units_per_pixel

func _clear_position(role: String, candidate: Vector3) -> bool:
	if not _floor.has_point(Vector2(candidate.x,candidate.z)): return false
	for other: String in _actors:
		if other!=role and candidate.distance_to(_actors[other].position)<SEPARATION:
			return false
	var safe := _stage_rect().grow(-42)
	return safe.has_point(_world.camera.unproject_position(_world.to_global(candidate))) and safe.has_point(_world.camera.unproject_position(_world.to_global(candidate+Vector3(0,1.15,0))))

func _choose_goal(role: String) -> void:
	var actor: Node3D = _actors[role]
	for attempt in range(12):
		var candidate := Vector3(_random.randf_range(_floor.position.x,_floor.end.x),0,_random.randf_range(_floor.position.y,_floor.end.y))
		if actor.position.distance_to(candidate)>0.65 and _clear_position(role,candidate):
			_goals[role] = candidate
			_rests[role] = _random.randf_range(0.6,1.6)
			return
	_goals[role] = actor.position
	_rests[role] = 0.8

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		_foreground = false
		_cancel_gesture()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]:
		_foreground = true

func _exit_tree() -> void:
	_cancel_gesture()
	if not is_instance_valid(_world) or _world.home_presentation_owner!=get_instance_id(): return
	_world.home_presentation_owner = 0
	# Gameplay can set home_view=false before removing the menu. Its static
	# camera still needs the home-only focus translation and offsets restored.
	if is_instance_valid(_camera) and _world.camera==_camera:
		_camera.global_transform = _camera_transform
		_camera.size = _camera_size
		_camera.h_offset = _camera_offsets.x
		_camera.v_offset = _camera_offsets.y
	if not _world.home_view or _world.terrain!=_terrain: return
	for role: String in _saved:
		if is_instance_valid(_actors[role]) and _world.actors.get(role)==_actors[role]:
			_actors[role].position = _saved[role].position
			_actors[role].visible = _saved[role].visible
			_actors[role].reset_motion()
			_world.actor_targets[role] = _saved[role].target
