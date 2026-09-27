extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Levels = preload("res://core/levels.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const Joystick = preload("res://presentation/joystick.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _joystick_target()
	await _successful_retry()
	print("GAMEPLAY COMFORT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _fixture(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/"+path))

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

func _successful_retry() -> void:
	root.size=Vector2i(1280,720)
	var path := "user://comfort-retry-"+str(Time.get_ticks_usec())+".json"
	var save := Storage.new(path)
	save.data.settings.sound=false
	save.data.settings.haptics=false
	_check(save.flush(),"Use a muted isolated retry save")
	var app := Main.new()
	app.saves=save
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var first := _fixture("first-light-a.json")
	var second := _fixture("first-light-b.json")
	app.current_level=Levels.get_level(0)
	app.attempt={"a":first,"b":{},"draft":second}
	app.role="b"
	app._prepare_turn()
	app._resume_draft(second)
	_check(app.mode=="review" and app.sim.complete,"Actual completed native B reaches review")
	var tick: int=app.sim.tick
	var original := FileAccess.get_file_as_bytes(path)
	var recording: Dictionary=app.review_recording.duplicate(true)
	await _tap(app.overlay,"Retry")
	_check(app.mode=="confirm_retry" and app.sim.tick==tick,"Retry first asks and leaves the successful simulation intact")
	var stale: Callable = _button(app.overlay,"Retry").get_signal_connection_list("pressed")[0].callable
	await _tap(app.overlay,"Cancel")
	_check(app.mode=="review" and app.review_recording==recording and FileAccess.get_file_as_bytes(path)==original,"Cancel preserves completed rehearsal and disk bytes")
	stale.call()
	_check(app.mode=="review" and app.sim.tick==tick,"Retired confirmation cannot reset the restored review")
	_press(app.overlay,"Retry")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode=="review" and app.sim.tick==tick and app.review_recording==recording,"Native Back cancels confirmation without dropping the successful turn")
	_press(app.overlay,"Retry")
	app.relay_identity_epoch += 1
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode=="confirm_retry" and app.sim.tick==tick,"A late native Back cannot revive Save under a replaced identity context")
	app.relay_identity_epoch -= 1
	_press(app.overlay,"Cancel")
	_press(app.overlay,"Retry")
	_press(app.overlay,"Retry")
	_check(app.mode=="ready" and app.sim.tick==0 and FileAccess.get_file_as_bytes(path)==original,"Only explicit confirmation starts the new unsaved attempt")
	# Already accepted legacy attempts keep their separate replay/archive flow.
	_check(save.save_attempt("first-light",{"a":first,"b":second,"draft":{}},true),"Save a completed legacy pair for restart protection")
	app._start_practice(0)
	var completed := FileAccess.get_file_as_bytes(path)
	_press(app.overlay,"Start a fresh attempt")
	_check(app.mode=="confirm_restart" and FileAccess.get_file_as_bytes(path)==completed,"A completed saved island also asks before restarting")
	_press(app.overlay,"Cancel")
	_check(FileAccess.get_file_as_bytes(path)==completed and not app.attempt.b.is_empty(),"Cancelling saved restart preserves accepted evidence")
	_press(app.overlay,"Start a fresh attempt")
	_press(app.overlay,"Retry")
	_check(app.mode=="ready" and app.attempt.a.is_empty() and save.data.replays["first-light"].b==second and save.data.attempt_archive.size()==1,"Confirmed restart archives the attempt and keeps its completed replay")
	app.queue_free()
	await _settle()
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)

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

func _button(node: Node, text: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and child.text==text: return child
		var found := _button(child,text)
		if found != null: return found
	return null

func _press(node: Node, text: String) -> void:
	var button := _button(node,text)
	_check(button!=null,"Action is present: "+text)
	if button != null: button.pressed.emit()

func _tap(node: Node, text: String) -> void:
	await _settle()
	var button := _button(node,text)
	_check(button!=null and button.is_visible_in_tree(),"Actual viewport action is visible: "+text)
	if button == null: return
	var point := button.get_global_rect().get_center()
	_pointer(root,point,true)
	_pointer(root,point,false)
	await _settle()

func _settle() -> void:
	await process_frame
	await process_frame

func _check(okay: bool, label: String) -> void:
	checks+=1
	if not okay:
		failures+=1
		push_error(label)
