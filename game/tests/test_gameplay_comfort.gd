extends SceneTree

const Controls = preload("res://presentation/chapter_controls.gd")
const Joystick = preload("res://presentation/joystick.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _joystick_target()
	print("GAMEPLAY COMFORT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _joystick_target() -> void:
	for left: bool in [false,true]:
		var viewport := SubViewport.new()
		viewport.size=Vector2i(960,540)
		viewport.handle_input_locally=true
		root.add_child(viewport)
		var controls := Controls.new()
		controls.settings={"left_handed":left}
		viewport.add_child(controls)
		controls.show_play()
		await _settle()
		var rect := controls.stick.get_global_rect()
		var center := rect.get_center()
		_check(rect.size==Vector2(192,192) and Rect2(0,0,960,540).encloses(rect),"Enlarged invisible target stays in the viewport for either hand")
		_check(center.is_equal_approx(Vector2(856 if left else 104,418)),"The larger target preserves the familiar stick center")
		var point := center+Vector2(-86,0)
		_pointer(viewport,point,true)
		_check(controls.stick.dragging and controls.stick.value==Vector2.LEFT,"A real press outside the old hitbox and visible art starts movement")
		_pointer(viewport,Vector2(480,270),false)
		_check(controls.stick.value==Vector2.ZERO and not controls.stick.dragging,"Captured release outside the target stops movement")
		_touch(viewport,point,40,true)
		_touch(viewport,center+Vector2(86,0),41,true)
		_touch(viewport,center+Vector2(86,0),41,false)
		_check(controls.stick.touch_id==40 and controls.stick.value==Vector2.LEFT,"A second finger cannot steal or release the captured movement contact")
		_touch(viewport,Vector2(480,270),40,false)
		_check(controls.stick.touch_id==-1 and controls.stick.value==Vector2.ZERO,"The original touch releases outside the control")
		var before := {"finish":0}
		controls.finish_requested.connect(func(): before.finish += 1)
		_pointer(viewport,controls.finish_button.get_global_rect().get_center(),true)
		_pointer(viewport,controls.finish_button.get_global_rect().get_center(),false)
		_check(before.finish==1 and controls.stick.value==Vector2.ZERO,"Invisible movement area does not steal the Finish action")
		controls.card("Pause","")
		_pointer(viewport,point,true)
		_pointer(viewport,point,false)
		_check(controls.stick.value==Vector2.ZERO,"A modal never sends touches through to the enlarged stick")
		viewport.queue_free()
		await _settle()

func _pointer(viewport: Viewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=point
	event.global_position=point
	event.button_index=MOUSE_BUTTON_LEFT
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed=pressed
	viewport.push_input(event,true)

func _touch(viewport: SubViewport, point: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position=point
	event.index=index
	event.pressed=pressed
	viewport.push_input(event,true)

func _settle() -> void:
	await process_frame
	await process_frame

func _check(okay: bool, label: String) -> void:
	checks+=1
	if not okay:
		failures+=1
		push_error(label)
