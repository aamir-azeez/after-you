extends RefCounted
## Temporary presentation framing for a stable, token-owned Story passage.
## Native actor coordinates and simulation state never change here.
const EXPLORATION_FIELDS := ["manual", "auto_return", "zoom_ratio", "pan", "_idle", "_return_age", "_return_zoom", "_return_pan", "_returning", "_frame"]
const FOLLOW_FIELDS := ["_follow_center", "_view_center", "_view_size"]
var _token := -1
var _world: WeakRef
var _camera: WeakRef
var _exploration: WeakRef
var _saved: Dictionary = {}
var _exploration_saved: Dictionary = {}
var _follow_saved: Dictionary = {}
var _world_processing := false
var _exploration_processing := false
var _exploration_input := false

func begin(world: Node3D, token: int) -> bool:
	if _token >= 0 or not is_instance_valid(world) or token < 0: return false
	var camera: Variant = world.get("camera")
	if not camera is Camera3D or camera.projection != Camera3D.PROJECTION_ORTHOGONAL: return false
	_token = token
	_world = weakref(world)
	_camera = weakref(camera)
	_saved = {"transform":camera.global_transform,"local_transform":camera.transform,"parent_transform":camera.get_parent_node_3d().global_transform if camera.get_parent_node_3d() != null else Transform3D.IDENTITY,"size":camera.size,"keep_aspect":camera.keep_aspect,
		"h_offset":camera.h_offset,"v_offset":camera.v_offset,"projection":camera.projection,"fov":camera.fov}
	_world_processing = world.is_processing()
	_follow_saved = _capture_fields(world,FOLLOW_FIELDS)
	world.set_process(false)
	var exploration: Variant = world.get("camera_exploration")
	if is_instance_valid(exploration):
		_exploration = weakref(exploration)
		_exploration_saved = _capture_fields(exploration,EXPLORATION_FIELDS)
		_exploration_processing = exploration.is_processing()
		_exploration_input = exploration.is_processing_input()
		exploration.cancel_gesture()
		exploration.manual = true
		exploration.set_process(false)
		exploration.set_process_input(false)
	return true

func frame(token: int, panel_rect: Rect2, include_goal: bool, safe_rect: Rect2 = Rect2()) -> bool:
	if token != _token or _saved.is_empty(): return false
	var world: Variant = _world.get_ref()
	var camera: Variant = _camera.get_ref()
	if not is_instance_valid(world) or not is_instance_valid(camera): return false
	var viewport: Rect2 = world.get_viewport().get_visible_rect()
	var safe := safe_rect.intersection(viewport) if safe_rect.has_area() else viewport
	var visible := Rect2(safe.position+Vector2(24,24),Vector2(safe.size.x-48,maxf(0,panel_rect.position.y-safe.position.y-48)))
	if not panel_rect.has_area() or not visible.has_area() or visible.end.y >= panel_rect.position.y: return false
	_restore_camera(camera)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var points := _points(world,include_goal)
	if points.is_empty(): return false
	var bounds := _screen_bounds(camera,points)
	var ratio: float = maxf(1.0,maxf(bounds.size.x/visible.size.x,bounds.size.y/visible.size.y))
	camera.size *= ratio*1.06
	bounds = _screen_bounds(camera,points)
	var shift: Vector2 = bounds.get_center()-visible.get_center()
	var units: float = camera.size/maxf(viewport.size.y,1.0)
	camera.global_position += camera.global_basis.x*shift.x*units-camera.global_basis.y*shift.y*units
	return true

func restore(token: int) -> void:
	if token != _token: return
	# Retire before any resumed presentation callback can inspect ownership.
	_token = -1
	var world: Variant = _world.get_ref() if _world != null else null
	var camera: Variant = _camera.get_ref() if _camera != null else null
	var exploration: Variant = _exploration.get_ref() if _exploration != null else null
	if is_instance_valid(camera): _restore_camera(camera)
	if is_instance_valid(world):
		for field: String in _follow_saved: world.set(field,_copy(_follow_saved[field]))
		world.set_process(_world_processing)
	if is_instance_valid(exploration):
		for field: String in _exploration_saved: exploration.set(field,_copy(_exploration_saved[field]))
		exploration.cancel_gesture()
		exploration.set_process(_exploration_processing)
		exploration.set_process_input(_exploration_input)
	_world = null
	_camera = null
	_exploration = null
	_saved = {}
	_exploration_saved = {}
	_follow_saved = {}

func _restore_camera(camera: Camera3D) -> void:
	if not camera.is_inside_tree():
		camera.transform = _saved.local_transform
	else:
		var parent := camera.get_parent_node_3d()
		var parent_transform: Transform3D = parent.global_transform if parent != null else Transform3D.IDENTITY
		if parent_transform == _saved.parent_transform: camera.transform = _saved.local_transform
		else: camera.global_transform = _saved.transform
	camera.projection = int(_saved.projection)
	camera.keep_aspect = int(_saved.keep_aspect)
	camera.size = float(_saved.size)
	camera.fov = float(_saved.fov)
	camera.h_offset = float(_saved.h_offset)
	camera.v_offset = float(_saved.v_offset)

func _points(world: Node3D, include_goal: bool) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var actors: Variant = world.get("actors")
	if actors is Dictionary:
		for actor: Variant in actors.values():
			if not is_instance_valid(actor) or not actor is Node3D or not actor.visible: continue
			_append_box(points,actor,0.55,1.5)
	var garden: Variant = world.get("garden")
	if include_goal and is_instance_valid(garden) and garden is Node3D and garden.visible:
		_append_box(points,garden,1.35,1.8)
	return points

func _append_box(points: Array[Vector3], node: Node3D, radius: float, height: float) -> void:
	for x: float in [-radius,radius]:
		for z: float in [-radius,radius]:
			for y: float in [0.0,height]: points.append(node.to_global(Vector3(x,y,z)))

func _screen_bounds(camera: Camera3D, points: Array[Vector3]) -> Rect2:
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for point: Vector3 in points:
		var position := camera.unproject_position(point)
		minimum = minimum.min(position)
		maximum = maximum.max(position)
	return Rect2(minimum,maximum-minimum)

func _capture_fields(object: Object, names: Array) -> Dictionary:
	var fields := {}
	for property: Dictionary in object.get_property_list():
		var name: String = str(property.name)
		if name in names: fields[name] = _copy(object.get(name))
	return fields

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value
