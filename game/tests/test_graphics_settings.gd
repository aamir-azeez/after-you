extends SceneTree
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
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
	app._show_settings()
	await process_frame
	var graphics := _button(app,"Graphics")
	_check(graphics != null and viewport.get_visible_rect().encloses(graphics.get_global_rect()),"Graphics is reachable at the top of compact Settings")
	await _click(viewport,graphics)
	_check(app.mode == "graphics_settings" and _button(app,"Balanced").button_pressed,"The graphics page starts with the saved Balanced choice")
	for label: String in ["Low","High","Balanced","Low"]:
		var button := _button(app,label)
		_check(viewport.get_visible_rect().encloses(button.get_global_rect()),"Each quality choice fits the small display")
		await _click(viewport,button)
		var saved := Save.new(path)
		saved.load_data()
		_check(saved.data.settings.graphics_quality==label.to_lower() and button.button_pressed,"Actual quality tap persists and remains visibly selected")
		_check(viewport.scaling_3d_scale==(0.75 if label=="Low" else 1.0) and viewport.msaa_3d==(Viewport.MSAA_2X if label=="High" else Viewport.MSAA_DISABLED),"Main applies quality immediately to the 3D viewport")
		_check(app.world.sun.shadow_enabled==(label!="Low"),"Home and earlier-island world use the selected shadow setting")
		_check(app.world.sun.shadow_caster_mask==(0xFFFFFFFF if label=="Low" else 0) and is_equal_approx(app.world.sun.shadow_opacity,1.0 if label=="Low" else 0.0),"Balanced and High hide every shadow while Low keeps its authored values")
	app.saves.read_only = true
	await _click(viewport,_button(app,"High"))
	_check(_button(app,"Low").button_pressed and viewport.scaling_3d_scale==0.75,"A failed save restores the old visible selection and rendering quality")
	app.saves.read_only = false
	# Unlimited frame rate: off by default, saved, and applied at once.
	var frames: Node = root.get_node_or_null("FramePolicy")
	var unlimited := app.overlay.find_child("UnlimitedFrameRate", true, false) as CheckButton
	_check(unlimited != null and not unlimited.button_pressed and app.saves.data.settings.unlimited_frame_rate == false, "Unlimited frame rate starts off")
	_check(frames != null and not frames.unlimited, "Play is capped by default")
	_check(viewport.get_visible_rect().encloses(unlimited.get_global_rect()), "The frame rate switch fits the small display")
	await _click(viewport, unlimited)
	var reloaded := Save.new(path)
	reloaded.load_data()
	_check(unlimited.button_pressed and reloaded.data.settings.unlimited_frame_rate == true, "Turning it on is saved")
	_check(frames.unlimited, "Turning it on lifts the play cap at once")
	app.saves.read_only = true
	await _click(viewport, unlimited)
	_check(unlimited.button_pressed and frames.unlimited, "A failed save keeps it on, as saved")
	app.saves.read_only = false
	await _click(viewport, unlimited)
	reloaded = Save.new(path)
	reloaded.load_data()
	_check(not unlimited.button_pressed and reloaded.data.settings.unlimited_frame_rate == false and not frames.unlimited, "Turning it off is saved and caps play again")
	for invalid: Variant in [null, 1, "true", [], {}]:
		var settings: Dictionary = Save.defaults().settings
		settings.unlimited_frame_rate = invalid
		_check(not load("res://services/graphics_policy.gd").unlimited_frame_rate(settings), "A saved %s is read as off" % str(invalid))
	await _click(viewport,_button(app,"Back"))
	_check(app.mode=="settings","Back returns to Settings")
	await _click(viewport,_button(app,"Graphics"))
	_check(_button(app,"Low").button_pressed,"Reopening the submenu retains its chosen quality")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode=="settings","Android Back also returns to Settings")
	app._show_home()
	_check(not app.world.sun.shadow_enabled and viewport.scaling_3d_scale==0.75,"Returning Home preserves Low quality")
	viewport.queue_free()
	await process_frame
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("GRAPHICS SETTINGS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _button(app: Node, label: String) -> Button:
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.text==label: return button
	return null

func _click(viewport: SubViewport, button: Button) -> void:
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
