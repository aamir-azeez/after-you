extends Control
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Home-only presentation. No simulation, recordings, persistence or account I/O.
const CameraExploration = preload("res://presentation/camera_exploration.gd")
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
var _exploration := CameraExploration.new()
var _touches: Dictionary:
	get: return _exploration.touches
var _pinch_span: float:
	get: return _exploration.pinch_span
var _foreground := true
var _random := RandomNumberGenerator.new()
var _reset: Button
var _hint: Label

func configure(world: Node3D, active: Callable) -> void:
	_world = world
	_active = active

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_exploration.manual = true
	_exploration.auto_return = false
	_exploration.minimum_zoom = MIN_SIZE / DEFAULT_SIZE
	_exploration.maximum_zoom = MAX_SIZE / DEFAULT_SIZE
	_exploration.maximum_pan = Vector2(0.20, 0.18)
	_exploration.allowed = _allowed
	add_child(_exploration)
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
	_reset.pressed.connect(_reset_view)
	add_child(_reset)
	_hint = Label.new()
	_hint.text = PlayerCopy.HOME_STAGE_88876AC2DD42 if OS.has_feature("android") else PlayerCopy.HOME_STAGE_CA9AEFEB7961
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
	_hint.position = rect.position-global_position+Vector2(12,rect.size.y-32)
	_hint.size = Vector2(rect.size.x-24,48)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reset.visible = not is_equal_approx(zoom_target,DEFAULT_SIZE) or not _exploration.pan.is_zero_approx()

func _is_active() -> bool:
	return is_inside_tree() and is_visible_in_tree() and _foreground and is_instance_valid(_world) and _world.visible and _world.home_view and _world.terrain==_terrain and _world.home_presentation_owner==get_instance_id() and _active.is_valid() and _active.call()

func _allowed(point: Vector2) -> bool:
	return _stage_rect().has_point(point) and not (is_instance_valid(_reset) and _reset.visible and _reset.get_global_rect().has_point(point))

func _input(event: InputEvent) -> void:
	if not _is_active():
		_cancel_gesture()
		return
	_exploration.zoom_ratio = zoom_target / DEFAULT_SIZE
	if _exploration.handle_event(event): get_viewport().set_input_as_handled()
	_sync_zoom()

func _gui_input(event: InputEvent) -> void:
	if not _is_active(): return
	# GUI events use local positions; the shared controller takes viewport ones.
	if event is InputEventMouse or event is InputEventGesture:
		var screen_event := event.duplicate()
		screen_event.position += global_position
		_exploration.zoom_ratio = zoom_target / DEFAULT_SIZE
		if _exploration.handle_event(screen_event): accept_event()
		_sync_zoom()

func _sync_zoom() -> void:
	zoom_target = clampf(_exploration.zoom_ratio * DEFAULT_SIZE, MIN_SIZE, MAX_SIZE)
	if is_equal_approx(zoom_target, MIN_SIZE): zoom_target = MIN_SIZE
	if is_equal_approx(zoom_target, MAX_SIZE): zoom_target = MAX_SIZE

func _zoom(factor: float) -> void:
	_exploration.zoom_ratio = zoom_target / DEFAULT_SIZE
	_exploration.zoom(factor)
	_sync_zoom()

func _cancel_gesture() -> void:
	_exploration.cancel_gesture()

func _reset_view() -> void:
	_exploration.reset_view()
	zoom_target = DEFAULT_SIZE

func _process(delta: float) -> void:
	if not _is_active():
		_cancel_gesture()
		return
	var step := clampf(delta,0.0,0.05)
	_layout()
	zoom_size = zoom_target if _world.reduced_motion else lerpf(zoom_size,zoom_target,1.0-exp(-12.0*step))
	_frame_camera()
	_world.update_spirit_attention()
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
	_exploration.apply_pan(camera, DEFAULT_SIZE)

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
