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
	viewport.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU SETTINGS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
