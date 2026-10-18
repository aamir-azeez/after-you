extends SceneTree
## Settings > Graphics: Quality (Low, Balanced, High) and Frame rate (30 fps,
## 60 fps, Unlimited) as segmented choices, each saved and applied at once,
## and a labelled Reset graphics in the title row that is greyed at Balanced
## and 60 fps and asks before it resets. Checked at a small 960x540 display.
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Flow = preload("res://presentation/settings_flow.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "user://graphics-settings-%d.json" % Time.get_ticks_usec()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,540)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.settings_flow.show_settings()
	await process_frame
	await process_frame
	var graphics := app.overlay.find_child("category_graphics",true,false) as Button
	_check(graphics != null and viewport.get_visible_rect().encloses(graphics.get_global_rect()),"Graphics is reachable at the top of compact Settings")
	await _click(viewport,graphics)
	await process_frame
	_check(app.settings_flow.showing(Flow.GRAPHICS) and _button(app,"Balanced").button_pressed,"The graphics page starts with the saved Balanced choice")
	var reset := app.overlay.find_child("ResetGraphics",true,false) as Button
	_check(reset != null and reset.visible and reset.text == "Reset graphics" and reset.icon != null,"Graphics has a labelled Reset graphics in its title row")
	_check(reset != null and reset.disabled,"Reset graphics is greyed at Balanced and 60 fps")
	# Low draws at Balanced's scale and only leaves effects out, so its motes tell it apart.
	var authored := _visible_motes(app)
	var low_motes := ceili(authored * 0.25)
	_check(authored > low_motes,"Home has motes for Low to thin out")
	for label: String in ["Low","High","Balanced","Low"]:
		var button := _button(app,label)
		await _reveal(button)
		_check(viewport.get_visible_rect().encloses(button.get_global_rect()),"Each quality choice fits the small display")
		await _click(viewport,button)
		var saved := Save.new(path)
		saved.load_data()
		_check(saved.data.settings.graphics_quality==label.to_lower() and button.button_pressed,"Actual quality tap persists and remains visibly selected")
		_check(_button(app,"Low").button_pressed == (label == "Low") and _button(app,"High").button_pressed == (label == "High"),"Only the chosen quality looks selected")
		_check(viewport.scaling_3d_scale==1.0 and viewport.msaa_3d==(Viewport.MSAA_2X if label=="High" else Viewport.MSAA_DISABLED),"Main applies quality immediately to the 3D viewport, every quality at full scale here")
		_check(_visible_motes(app)==(low_motes if label=="Low" else authored),"Main applies quality immediately to the world's effects (%s)" % label)
		_check(not app.world.sun.shadow_enabled,"No quality runs the sun's shadow pass on Home")
		_check(reset.disabled == (label == "Balanced"),"Reset graphics is offered whenever Graphics is off its defaults (%s)" % label)
	app.saves.read_only = true
	await _click(viewport,_button(app,"High"))
	_check(_button(app,"Low").button_pressed and not _button(app,"High").button_pressed and viewport.msaa_3d==Viewport.MSAA_DISABLED and _visible_motes(app)==low_motes,"A failed save restores the old visible selection and rendering quality")
	app.saves.read_only = false
	# Frame rate: 60 by default, saved, and applied to play at once.
	var frames: Node = root.get_node_or_null("FramePolicy")
	_check(_button(app,"60 fps").button_pressed and app.saves.data.settings.frame_rate == "60" and app.saves.data.settings.unlimited_frame_rate == false, "Frame rate starts at 60 fps")
	_check(frames != null and frames.play_fps == 60, "Play is capped at 60 by default")
	_check(app.overlay.find_child("UnlimitedFrameRate",true,false) == null,"The old Unlimited switch is gone")
	for row: Array in [["30 fps","30",30],["Unlimited","unlimited",0],["60 fps","60",60],["Unlimited","unlimited",0]]:
		var option := _button(app,row[0])
		await _reveal(option)
		_check(viewport.get_visible_rect().encloses(option.get_global_rect()),"The frame rate choice fits the small display: "+row[0])
		await _click(viewport,option)
		var reloaded := Save.new(path)
		reloaded.load_data()
		_check(option.button_pressed and reloaded.data.settings.frame_rate == row[1] and reloaded.data.settings.unlimited_frame_rate == (row[1] == "unlimited"), "Choosing %s is saved, with the older builds' switch to match" % row[0])
		_check(frames.play_fps == row[2], "Choosing %s sets play's rate at once" % row[0])
	app.saves.read_only = true
	await _click(viewport,_button(app,"30 fps"))
	_check(_button(app,"Unlimited").button_pressed and not _button(app,"30 fps").button_pressed and frames.play_fps == 0, "A failed save keeps Unlimited, as saved")
	app.saves.read_only = false
	for invalid: Variant in [null, 1, "true", [], {}]:
		var settings: Dictionary = Save.defaults().settings
		settings.frame_rate = invalid
		_check(load("res://services/graphics_policy.gd").frame_rate(settings) == "60", "A saved %s is read as 60" % str(invalid))
	# Reset graphics asks first; Cancel keeps the choices, Reset puts back Balanced and 60.
	_check(not reset.disabled,"Low and Unlimited can be reset")
	await _reveal(reset)
	await _click(viewport,reset)
	var confirm := app.ui.find_child("ResetConfirm",true,false)
	_check(confirm != null and _label_in(confirm,PlayerCopy.SETTINGS_RESET_GRAPHICS_CONFIRM),"Reset graphics asks: Reset graphics to default?")
	_check(confirm != null and _button_in(confirm,"Cancel") != null and _button_in(confirm,"Reset") != null,"with Cancel and Reset")
	if confirm != null: _button_in(confirm,"Cancel").pressed.emit()
	await process_frame
	_check(app.saves.data.settings.graphics_quality == "low" and app.saves.data.settings.frame_rate == "unlimited","Cancel keeps the choices")
	await _click(viewport,reset)
	confirm = app.ui.find_child("ResetConfirm",true,false)
	if confirm != null: _button_in(confirm,"Reset").pressed.emit()
	await process_frame
	var after := Save.new(path)
	after.load_data()
	_check(after.data.settings.graphics_quality == "balanced" and after.data.settings.frame_rate == "60" and not after.data.settings.unlimited_frame_rate,"Reset puts back Balanced and 60 fps, saved")
	_check(_button(app,"Balanced").button_pressed and _button(app,"60 fps").button_pressed and not _button(app,"Low").button_pressed and frames.play_fps == 60 and viewport.scaling_3d_scale == 1.0 and _visible_motes(app) == authored,"and shows and applies them at once")
	_check(reset.disabled and (confirm == null or not is_instance_valid(confirm) or confirm.is_queued_for_deletion()),"Reset closes its card and greys again")
	await _click(viewport,reset)
	_check(app.ui.find_child("ResetConfirm",true,false) == null,"A greyed Reset asks nothing")
	await _click(viewport,_button(app,"Low"))
	app.settings_flow.show_settings(Flow.EVERYDAY)
	await process_frame
	await _click(viewport,app.overlay.find_child("category_graphics",true,false))
	_check(_button(app,"Low").button_pressed,"Reopening Graphics retains its chosen quality")
	app.settings_flow.show_graphics_settings()
	_check(app.settings_flow.showing(Flow.GRAPHICS) and _button(app,"Low").button_pressed,"The Graphics entry point opens on Graphics")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode=="home","Android Back from Graphics goes where Done goes: Home")
	_check(viewport.scaling_3d_scale==1.0 and _visible_motes(app)==low_motes,"Returning Home preserves Low quality")
	viewport.queue_free()
	await process_frame
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("GRAPHICS SETTINGS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _visible_motes(app: Node) -> int:
	return app.world.motes.filter(func(mote: MeshInstance3D) -> bool: return mote.visible).size()

func _button(app: Node, label: String) -> Button:
	return _button_in(app.overlay,label)

func _button_in(node: Node, label: String) -> Button:
	for button: Button in node.find_children("*","Button",true,false):
		if button.text==label: return button
	return null

func _label_in(node: Node, text: String) -> bool:
	return node.find_children("*","Label",true,false).any(func(label: Label) -> bool: return label.text == text)

func _reveal(control: Control) -> void:
	if control == null: return
	var parent: Node = control.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer:
		(parent as ScrollContainer).ensure_control_visible(control)
		await process_frame

func _click(viewport: SubViewport, button: Control) -> void:
	if button == null: return
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event,true)
	await process_frame

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
