extends SceneTree
## Home input and wandering use real controls/camera, without changing a save.
const Stage = preload("res://presentation/home_stage.gd")
const World = preload("res://presentation/island_world.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Stage._retained_view.clear()
	await _test_gestures_and_wander()
	Stage._retained_view.clear()
	await _test_real_menu()
	print("AFTER YOU HOME STAGE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _touch(stage: Control, index: int, point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	stage._input(event)

func _drag(stage: Control, index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	stage._input(event)

# These events enter through the viewport, exercising engine input dispatch and
# the actual menu hierarchy. Desktop dispatch does not execute Android's Java
# gesture filter; that boundary also requires the native multi-pointer check.
func _push_touch(viewport: SubViewport, index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	viewport.push_input(event,true)

func _push_drag(viewport: SubViewport, index: int, before: Vector2, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = point-before
	viewport.push_input(event,true)

func _wheel(stage: Control, point: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = point - stage.global_position
	event.button_index = button
	event.pressed = true
	stage._gui_input(event)

func _positions(world: Node3D) -> Dictionary:
	var result := {}
	for role: String in world.actors:
		result[role] = world.actors[role].position
	return result

func _test_gestures_and_wander() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var world := World.new()
	viewport.add_child(world)
	world.set_process(false)
	var definition: Dictionary = Levels.get_level("first-light")
	var definition_before := JSON.stringify(definition)
	world.load_level(definition)
	var original := _positions(world)
	var targets := world.actor_targets.duplicate()
	var camera_transform := world.camera.global_transform
	var camera_size := world.camera.size
	var camera_offsets := Vector2(world.camera.h_offset,world.camera.v_offset)
	var foreground := [true]
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(ui)
	var stage := Stage.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.configure(world,func() -> bool: return foreground[0])
	ui.add_child(stage)
	stage.set_process(false)
	await process_frame
	await process_frame
	stage._process(0.0)
	_check(stage._is_active() and world.home_presentation_owner==stage.get_instance_id(),"Only the active home stage owns home actor/camera presentation")
	var point := stage._stage_rect().get_center()
	_touch(stage,0,point-Vector2(60,0),true)
	_drag(stage,0,point-Vector2(20,0))
	_check(stage.zoom_target==Stage.DEFAULT_SIZE,"A single finger does not zoom or consume a menu action")
	_touch(stage,1,point+Vector2(60,0),true)
	_drag(stage,1,point+Vector2(140,0))
	_check(stage.zoom_target<Stage.DEFAULT_SIZE,"Spreading two fingers zooms toward the spirits")
	_touch(stage,2,point,true)
	var span: float = stage._pinch_span
	_touch(stage,2,point,false)
	_check(stage._touches.size()==2 and stage._pinch_span==span,"An ignored third finger cannot reset an active pinch")
	_touch(stage,0,point,false,true)
	var stopped: float = stage.zoom_target
	_drag(stage,0,point-Vector2(300,0))
	_drag(stage,1,point+Vector2(300,0))
	_check(stage.zoom_target==stopped,"Canceled or stale drags cannot continue a two-finger gesture")
	stage._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(stage._touches.is_empty() and stage._pinch_span==0.0,"Backgrounding clears all captured touch IDs")
	stage._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_drag(stage,1,point)
	_check(stage.zoom_target==stopped,"Returning foreground requires a new pinch instead of reusing old fingers")
	stage.zoom_target=Stage.DEFAULT_SIZE
	stage._cancel_gesture()
	_touch(stage,0,Vector2(180,180),true)
	_touch(stage,1,point,true)
	_drag(stage,1,point+Vector2(100,0))
	_wheel(stage,Vector2(180,180),MOUSE_BUTTON_WHEEL_UP)
	_check(stage.zoom_target==Stage.DEFAULT_SIZE and stage._touches.size()==1,"Menu-side touches and scrolling cannot zoom the scenery")
	stage._cancel_gesture()
	for frame in range(60): _wheel(stage,point,MOUSE_BUTTON_WHEEL_UP)
	_check(stage.zoom_target==Stage.MIN_SIZE,"Repeated wheel zoom is bounded at a readable close view")
	for frame in range(90): _wheel(stage,point,MOUSE_BUTTON_WHEEL_DOWN)
	_check(stage.zoom_target==Stage.MAX_SIZE,"Repeated wheel zoom cannot send the island out of view")
	stage._zoom(NAN)
	stage._zoom(INF)
	stage._zoom(-1)
	_check(stage.zoom_target==Stage.MAX_SIZE,"Malformed gesture factors cannot corrupt the camera")
	stage._layout()
	var reset_point: Vector2 = stage._reset.get_global_rect().get_center()
	_touch(stage,2,reset_point,true)
	_check(not stage._touches.has(2),"Reset-view button is excluded from pinch ownership")
	stage._reset.pressed.emit()
	_check(stage.zoom_target==Stage.DEFAULT_SIZE and stage._exploration.pan==Vector2.ZERO,"Reset view returns pan and zoom to the initial framing")
	_touch(stage,0,point-Vector2(60,0),true)
	_touch(stage,1,point+Vector2(60,0),true)
	_drag(stage,0,point-Vector2(60,0)+Vector2(30,50))
	_drag(stage,1,point+Vector2(60,0)+Vector2(30,50))
	_check(not stage._exploration.pan.is_zero_approx(),"Moving both eligible home fingers pans the shared camera")
	stage._reset_view()
	_check(stage._exploration.pan==Vector2.ZERO and stage._touches.is_empty(),"Reset view also releases the previous gesture")
	var total_movement := {"a":0.0,"b":0.0}
	var all_bounded := true
	var all_separate := true
	var all_slow := true
	var all_on_screen := true
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,960)]:
		viewport.size=size
		await process_frame
		await process_frame
		for zoom: float in [Stage.DEFAULT_SIZE,Stage.MIN_SIZE,Stage.MAX_SIZE]:
			stage.zoom_size=zoom
			stage.zoom_target=zoom
			for frame in range(360):
				var before := _positions(world)
				stage._process(1.0/60.0)
				for role: String in world.actors:
					var position: Vector3 = world.actors[role].position
					var moved: float = before[role].distance_to(position)
					total_movement[role]+=moved
					all_bounded=all_bounded and stage._floor.has_point(Vector2(position.x,position.z)) and position.y==0.0
					all_slow=all_slow and moved<=Stage.WALK_SPEED/60.0+0.00001
					all_on_screen=all_on_screen and stage._clear_position(role,position)
				all_separate=all_separate and world.actors.a.position.distance_to(world.actors.b.position)>=Stage.SEPARATION-0.00001
	_check(all_bounded,"Both spirits remain on the inset display island through varied sizes and zooms")
	_check(all_separate,"Wandering spirits never overlap one another")
	_check(all_slow,"Every wander step is bounded, with no route teleport or chase burst")
	_check(all_on_screen,"Spirits and their heads stay clear of the menu and screen edges")
	_check(total_movement.a>1.0 and total_movement.b>1.0,"Both spirits actually wander rather than remaining frozen behind a safety check")
	_check(JSON.stringify(definition)==definition_before and JSON.stringify(world.current_level)==definition_before,"Home wandering does not mutate authored gameplay data")
	world.reduced_motion=true
	var still := _positions(world)
	stage.zoom_target=Stage.MIN_SIZE
	for frame in range(120): stage._process(1.0/60.0)
	_check(_positions(world)==still and stage.zoom_size==Stage.MIN_SIZE,"Reduced motion disables automatic wandering and applies requested zoom without animation")
	world.reduced_motion=false
	foreground[0]=false
	for frame in range(120): stage._process(1.0/60.0)
	_check(_positions(world)==still and stage._touches.is_empty(),"A hidden or inactive owning screen cannot keep its background wandering or touch state alive")
	foreground[0]=true
	stage.free()
	_check(world.home_presentation_owner==0 and _positions(world)==original and world.actor_targets==targets,"Leaving home restores exact prior actor positions/targets and releases ownership")
	_check(world.camera.global_transform.is_equal_approx(camera_transform) and world.camera.size==camera_size and Vector2(world.camera.h_offset,world.camera.v_offset)==camera_offsets,"Leaving home restores camera transform and offsets for gameplay")
	var stale := Stage.new()
	stale.configure(world,func() -> bool: return true)
	ui.add_child(stale)
	stale.set_process(false)
	stale.zoom_size=Stage.MIN_SIZE
	stale._frame_camera()
	world.home_view=false
	world.load_level(Levels.get_level("rising-together"))
	var loaded := _positions(world)
	stale.free()
	_check(world.home_presentation_owner==0 and _positions(world)==loaded,"Late home teardown cannot move actors from a newly loaded level")
	_check(world.camera.global_transform.is_equal_approx(camera_transform) and Vector2(world.camera.h_offset,world.camera.v_offset)==camera_offsets,"Starting gameplay after close zoom cannot inherit home camera translation or vertical offset")
	viewport.free()
	await process_frame

func _test_real_menu() -> void:
	var path := "user://home-stage-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.handle_input_locally=true
	root.add_child(viewport)
	var app := Main.new()
	app.saves=Storage.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	await process_frame
	var stage: Control=app.overlay.get_child(0)
	_check(stage.get_script()==Stage and app.mode=="home","The actual app mounts the home stage below the menu controls")
	stage.set_process(false)
	var saved_before_dispatch := FileAccess.get_file_as_bytes(path)
	var center: Vector2 = stage._stage_rect().get_center()
	var left := center-Vector2(60,0)
	var right := center+Vector2(60,0)
	_push_touch(viewport,0,left,true)
	_push_touch(viewport,1,right,true)
	_check(stage._touches.size()==2,"Viewport touch dispatch admits both stage fingers without calling the home handler directly")
	stage._process(1.0/60.0)
	_check(stage.zoom_target==Stage.DEFAULT_SIZE and not stage._reset.visible,"Touch presses without forwarded drag events cannot fake a successful pinch")
	# Both fingers move equally about a fixed centroid, including small steps.
	# This is the native gesture that can be filtered before reaching Godot.
	for step in range(10):
		var next_left := left-Vector2(4,0)
		var next_right := right+Vector2(4,0)
		_push_drag(viewport,0,left,next_left)
		_push_drag(viewport,1,right,next_right)
		left=next_left
		right=next_right
	_check(stage.zoom_target<Stage.DEFAULT_SIZE and stage.zoom_target>=Stage.MIN_SIZE,"Viewport-dispatched symmetric small drags zoom the actual home scene")
	stage._process(1.0/60.0)
	_check(stage._reset.is_visible_in_tree() and app.world.camera.size<Stage.DEFAULT_SIZE,"Dispatched pinch changes the real camera and reveals Reset view")
	_push_touch(viewport,1,right,false)
	_push_touch(viewport,0,left,false)
	_check(stage._touches.is_empty() and stage._pinch_span==0.0,"Viewport releases clear both captured IDs before later menu input")
	var released_zoom: float=stage.zoom_target
	_push_drag(viewport,0,left,left-Vector2(40,0))
	_push_drag(viewport,1,right,right+Vector2(40,0))
	_check(stage.zoom_target==released_zoom,"Late viewport drags after release cannot continue a pinch")
	_check(FileAccess.get_file_as_bytes(path)==saved_before_dispatch,"Actual viewport touch and camera presentation leave saved data byte-for-byte unchanged")
	left=center-Vector2(60,0)
	right=center+Vector2(60,0)
	_push_touch(viewport,0,left,true)
	_push_touch(viewport,1,right,true)
	_push_drag(viewport,0,left,left+Vector2(32,40))
	_push_drag(viewport,1,right,right+Vector2(32,40))
	_push_touch(viewport,1,right+Vector2(32,40),false)
	_push_touch(viewport,0,left+Vector2(32,40),false)
	for frame in range(180): stage._process(1.0/60.0)
	released_zoom=stage.zoom_target
	var retained_pan: Vector2=stage._exploration.pan
	var retained_frame: Transform3D=app.world.camera.global_transform
	var retained_size: float=app.world.camera.size
	var retained_offsets := Vector2(app.world.camera.h_offset,app.world.camera.v_offset)
	_check(released_zoom<Stage.DEFAULT_SIZE and not retained_pan.is_zero_approx(),"Navigation regression starts with a real viewport pinch and pan")
	var settings: Button=_find_button(app.overlay,"Settings")
	_check(is_instance_valid(settings),"Settings remains present on the actual home menu")
	if is_instance_valid(settings):
		var point := settings.get_global_rect().get_center()
		_check(not stage._allowed(point),"The actual Settings hit area is outside home gesture ownership")
		var menu_point := Vector2(stage.global_position.x+12,point.y)
		_check(not stage._allowed(menu_point),"The menu margin remains outside the scene gesture area")
		_push_touch(viewport,0,menu_point,true)
		_push_touch(viewport,1,center,true)
		_push_drag(viewport,1,center,center+Vector2(40,0))
		_check(not stage._touches.has(0) and stage._touches.has(1) and stage.zoom_target==released_zoom,"A real menu-side touch cannot join a scene finger to zoom the home camera")
		_push_touch(viewport,1,center+Vector2(40,0),false)
		_push_touch(viewport,0,menu_point,false)
		var motion := InputEventMouseMotion.new()
		motion.position=point
		viewport.push_input(motion,true)
		for down: bool in [true,false]:
			var event := InputEventMouseButton.new()
			event.position=point
			event.button_index=MOUSE_BUTTON_LEFT
			event.pressed=down
			viewport.push_input(event,true)
		await process_frame
		_check(app.mode=="settings" and app.world.home_presentation_owner==0,"A real menu click opens Settings and disposes the home controller")
	app._show_home()
	await process_frame
	stage=app.overlay.get_child(0)
	stage.set_process(false)
	stage._process(0.0)
	_check(is_equal_approx(stage.zoom_target,released_zoom) and stage._exploration.pan.is_equal_approx(retained_pan) and stage._touches.is_empty(),"Returning from Settings keeps home pan and zoom without restoring captured fingers")
	_check(app.world.camera.global_transform.is_equal_approx(retained_frame) and is_equal_approx(app.world.camera.size,retained_size) and Vector2(app.world.camera.h_offset,app.world.camera.v_offset).is_equal_approx(retained_offsets),"Recreated home applies retained exploration once to the authored frame")
	for visit in range(3):
		app._show_settings()
		app._show_home()
		await process_frame
		stage=app.overlay.get_child(0)
		stage.set_process(false)
		stage._process(0.0)
	_check(app.world.camera.global_transform.is_equal_approx(retained_frame) and is_equal_approx(app.world.camera.size,retained_size),"Repeated menu navigation cannot accumulate retained camera offsets")
	stage._reset.pressed.emit()
	for frame in range(180): stage._process(1.0/60.0)
	app._show_settings()
	app._show_home()
	await process_frame
	stage=app.overlay.get_child(0)
	stage.set_process(false)
	_check(stage.zoom_target==Stage.DEFAULT_SIZE and stage._exploration.pan==Vector2.ZERO and not stage._reset.visible,"Reset view persists through later menu navigation")
	_check(FileAccess.get_file_as_bytes(path)==saved_before_dispatch,"Retaining and resetting home framing never changes gameplay saves")
	var save_before := FileAccess.get_file_as_bytes(path)
	stage._zoom(0.5)
	for frame in range(180): stage._process(1.0/60.0)
	_check(FileAccess.get_file_as_bytes(path)==save_before,"Home gestures and wandering do not write user saves")
	viewport.free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text==text: return node
	for child: Node in node.get_children():
		var found := _find_button(child,text)
		if found!=null: return found
	return null
