extends SceneTree

const Main=preload("res://main.gd")
const Storage=preload("res://services/local_save.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _run() -> void:
	var path := "user://settings-test-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves=Storage.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app._show_settings()
	await process_frame
	var toggles := app.overlay.find_children("*","CheckButton",true,false)
	var keys := ["assistance","reduced_motion","left_handed","sound","haptics","photo_prompts","share_online_status"]
	_check(toggles.size()==keys.size(),"Every saved setting has one reachable switch")
	for index: int in range(toggles.size()):
		var toggle: CheckButton=toggles[index]
		var parent: Node = toggle.get_parent()
		while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
		if parent is ScrollContainer:
			parent.ensure_control_visible(toggle)
			await process_frame
		for cycle in range(4):
			var before := toggle.button_pressed
			var motion := InputEventMouseMotion.new()
			motion.position=toggle.get_global_rect().get_center()
			viewport.push_input(motion,true)
			for pressed: bool in [true,false]:
				var event := InputEventMouseButton.new()
				event.position=motion.position
				event.button_index=MOUSE_BUTTON_LEFT
				event.pressed=pressed
				viewport.push_input(event,true)
			await process_frame
			_check(toggle.button_pressed!=before,"Repeated click changes the setting: "+keys[index])
			_check(toggle.get_draw_mode()==(BaseButton.DRAW_HOVER_PRESSED if toggle.button_pressed else BaseButton.DRAW_HOVER),"Pointer remains over the checked/unchecked switch")
			for state: String in ["normal","hover","pressed","hover_pressed"]:
				var style := toggle.get_theme_stylebox(state)
				_check(style is StyleBoxFlat and style.bg_color.a>0.9,"Switch background remains opaque in "+state)
			var loaded := Storage.new(path)
			loaded.load_data()
			_check(loaded.data.settings[keys[index]]==toggle.button_pressed,"Changed setting survives a fresh file read: "+keys[index])
			_check(app.saves.data.settings[keys[index]]==toggle.button_pressed,"Runtime setting matches the visible switch")
	app._show_home()
	app._show_settings()
	await process_frame
	toggles=app.overlay.find_children("*","CheckButton",true,false)
	for index: int in range(toggles.size()):
		_check(toggles[index].button_pressed==app.saves.data.settings[keys[index]],"Reopening Settings preserves the chosen state")
	await _redo_request_option(app,path)
	viewport.queue_free()
	await _damaged_setting_types()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU SETTINGS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _redo_request_option(app: Node, path: String) -> void:
	app._show_notification_settings()
	await process_frame
	var toggle: CheckButton = app.overlay.find_child("TurnRequestNotifications", true, false)
	var hint: Control = app.overlay.find_child("TurnRequestNotificationsHint", true, false)
	_check(toggle != null and hint != null, "Notifications has a redo request switch")
	if toggle == null or hint == null: return
	_check(toggle.disabled and hint.visible and not toggle.button_pressed, "The redo request switch starts off and waits for notifications")
	_check(toggle.autowrap_mode != TextServer.AUTOWRAP_OFF and toggle.custom_minimum_size.x >= 480 and toggle.text.begins_with("Also "), "The redo request switch wraps to the hint's width and reads as an extra")
	_check(app.turn_notifications.set_enabled(true), "Turn notifications can be switched on for the redo request check")
	app._update_notification_offer()
	_check(not toggle.disabled and not hint.visible, "Turning notifications on makes the redo request switch available")
	toggle.button_pressed = true
	var loaded := Storage.new(path)
	loaded.load_data()
	_check(loaded.data.settings.turn_request_notifications == true and app.turn_notifications.requests_enabled(), "The redo request choice survives a fresh file read")
	app._show_notification_settings()
	await process_frame
	toggle = app.overlay.find_child("TurnRequestNotifications", true, false)
	_check(toggle != null and toggle.button_pressed, "Reopening Notifications keeps the redo request choice")
	if toggle == null: return
	app.turn_notifications.set_enabled(false)
	app._update_notification_offer()
	_check(toggle.disabled and toggle.button_pressed and not app.turn_notifications.requests_enabled(), "Turning notifications off pauses redo request alerts and keeps the choice")

## A save whose settings hold the wrong types (a damaged file) still opens
## Settings with every switch, and the wrong values fall back to defaults.
func _damaged_setting_types() -> void:
	var path := "user://settings-types-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var damaged := Storage.defaults()
	damaged.settings = {"sound":"yes","haptics":1,"reduced_motion":null,"left_handed":"no","assistance":0.5,"photo_prompts":[],"share_online_status":{},"graphics_quality":42,"unlimited_frame_rate":"x","left_over":"kept"}
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(damaged))
	file.close()
	var loaded := Storage.new(path)
	loaded.load_data()
	var defaults: Dictionary = Storage.defaults().settings
	for key: String in defaults:
		_check(typeof(loaded.data.settings[key])==typeof(defaults[key]) and loaded.data.settings[key]==defaults[key],"A wrong-typed setting loads as its default: "+key)
	_check(loaded.data.settings.get("left_over")=="kept","An unknown setting is kept as saved")
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves=Storage.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app._show_settings()
	await process_frame
	_check(app.overlay.find_children("*","CheckButton",true,false).size()==7 and app.overlay.find_children("*","Button",true,false).any(func(b: Button) -> bool: return b.text=="Done"),"Settings from a damaged save shows every switch and Done")
	viewport.queue_free()
	await process_frame
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
