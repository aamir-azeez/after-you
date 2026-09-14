extends Node3D

const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const World = preload("res://presentation/island_world.gd")
const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const LocalSave = preload("res://services/local_save.gd")
const TurnState = preload("res://services/turn_state.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const Purchases = preload("res://services/purchases.gd")
const Secrets = preload("res://services/secure_store.gd")
const RecoveryDetails = preload("res://services/recovery_details.gd")
const Licenses = preload("res://services/licenses.gd")
const Soundscape = preload("res://services/soundscape.gd")
const INK := Color("193d39")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("9dbeb4")
const GOLD := Color("f1c48a")
const RECOVERY_ID_PATTERN := "^[A-Za-z0-9_-]{22}$"
const RECOVERY_SECRET_PATTERN := "^[A-Za-z0-9_-]{43}$"
const RECOVERY_KEY_PATTERN := "^[A-Za-z0-9_-]{16,80}$"
const COMPLETION_MOMENT_SECONDS := 1.5
enum IdentityReadState { UNCHECKED, LOADING, MISSING, LOADED, FAILED, RECOVERY_PENDING }

var world: Node3D
var sim := Simulation.new()
var saves := LocalSave.new()
var api: Node
var purchases: Node
var secrets: Node
var soundscape: Node
var config: Dictionary={}
var ui: Control
var overlay: Control
var overlay_shade: ColorRect
var hud: Control
var stick: Control
var timer_label: Label
var hint_label: Label
var role_label: Label
var progress: ProgressBar
var interact_button: Button
var finish_button: Button
var toast_label: Label
var title_font: Font=preload("res://assets/fonts/fredoka.ttf")
var body_font: Font=preload("res://assets/fonts/nunito.ttf")
var levels: Array=[]
var level_index := 0
var current_level: Dictionary={}
var attempt: Dictionary={}
var role := "a"
var completion_time_left := 0.0
var mode := "home":
	set(value):
		if mode=="completion" and value!="completion":
			completion_time_left=0.0
		mode=value
var running := false
var action_pressed := false
var replay_frames: Array=[]
var replay_index := 0
var review_recording: Dictionary={}
var active_room: Dictionary={}
var room_play := false
var purchase_package: Dictionary={}
var identity_request := ""
var recovery_read_request := ""
var pending_recovery: Dictionary = {}
var recovery_replace_allowed := false
var toast_time := 0.0
var capture_path := ""
var capture_frames := 0
var ui_theme: Theme
var frame_times: Array[float]=[]
var collection_preview := false
var identity_loading := false
var identity_read_state := IdentityReadState.UNCHECKED
var identity_busy := false
var identity_data: Dictionary = {}
var secret_results: Dictionary = {}
var store_configured := false
var restore_requested := false
var identity_restart_required := false
var application_backgrounded := false
var foreground_refresh_queued := false
var foreground_refresh_running := false
var foreground_response: Dictionary = {}
var lifecycle_generation := 0
var submission_in_flight := false
var recovery_copy_busy := false
var recovery_acknowledged := false

func _ready() -> void:
	var heading := FontVariation.new()
	heading.base_font=title_font
	heading.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	title_font=heading
	var body := FontVariation.new()
	body.base_font=body_font
	body.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	body_font=body
	saves.load_data()
	if soundscape==null:
		soundscape=Soundscape.new()
	# Configure before entering the tree: saved mute must also mute startup.
	soundscape.configure(saves.data.settings)
	add_child(soundscape)
	levels=Levels.all_levels()
	current_level=levels[0]
	var loaded_config: Variant=_parse_json(FileAccess.get_file_as_string("res://app_config.json"))
	config=loaded_config if loaded_config is Dictionary else {}
	api=RoomsApi.new()
	api.base_url=str(config.get("api_base_url",""))
	add_child(api)
	purchases=Purchases.new()
	add_child(purchases)
	purchases.completed.connect(_purchase_completed)
	purchases.failed.connect(_purchase_failed)
	purchases.customer_info_changed.connect(_customer_info_changed)
	secrets=Secrets.new()
	add_child(secrets)
	secrets.completed.connect(_secret_completed)
	secrets.failed.connect(_secret_failed)
	world=World.new()
	add_child(world)
	world.load_level(current_level)
	sim.reset(current_level)
	world.present(sim.snapshot(),true)
	_build_theme()
	_build_ui()
	get_viewport().size_changed.connect(_refresh_safe_area)
	_refresh_safe_area()
	_refresh_safe_area.call_deferred()
	_apply_settings()
	_show_home()
	if not saves.last_error.is_empty():
		_toast(saves.last_error)
	if secrets.is_available():
		_load_saved_identity()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path=arg.trim_prefix("--capture=")
		if arg=="--preview-island":
			_start_practice(0)
			_close_overlay()
			running=false
	get_tree().auto_accept_quit=false

func _build_theme() -> void:
	ui_theme=Theme.new()
	ui_theme.default_font=body_font
	ui_theme.default_font_size=20
	ui_theme.set_color("font_color","Label",CREAM)
	ui_theme.set_color("font_color","Button",INK)
	ui_theme.set_color("font_hover_color","Button",INK)
	ui_theme.set_color("font_pressed_color","Button",INK)
	ui_theme.set_color("font_hover_pressed_color","Button",INK)
	ui_theme.set_color("font_disabled_color","Button",Color("71867b"))
	ui_theme.set_stylebox("normal","Button",_style(CREAM,16))
	ui_theme.set_stylebox("hover","Button",_style(Color("ffffff"),16))
	ui_theme.set_stylebox("pressed","Button",_style(MINT,16))
	ui_theme.set_stylebox("hover_pressed","Button",_style(MINT.lightened(0.08),16))
	ui_theme.set_stylebox("disabled","Button",_style(Color("3e5e55"),16))
	ui_theme.set_stylebox("focus","Button",_style(Color(0,0,0,0),16,MINT))
	ui_theme.set_stylebox("normal","LineEdit",_style(Color("254b45"),12,Color("4e7064")))
	ui_theme.set_color("font_color","LineEdit",CREAM)
	ui_theme.set_color("font_placeholder_color","LineEdit",MUTED)

func _style(color: Color, radius: int=16, border: Color=Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1 if border.a>0 else 0)
	style.border_color=border
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=12
	style.content_margin_bottom=12
	return style

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui=Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=ui_theme
	layer.add_child(ui)
	hud=Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	var top := _label("AFTER YOU",22,CREAM,true)
	top.position=Vector2(36,26)
	hud.add_child(top)
	role_label=_label("",18,MUTED)
	role_label.position=Vector2(36,61)
	hud.add_child(role_label)
	var menu_button := _button("Pause",_pause,false)
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.position=Vector2(-146,24)
	menu_button.size=Vector2(110,48)
	hud.add_child(menu_button)
	timer_label=_label("20.0",24,CREAM,true)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer_label.position=Vector2(-45,26)
	timer_label.size=Vector2(90,40)
	timer_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(timer_label)
	progress=ProgressBar.new()
	progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	progress.position=Vector2(-160,76)
	progress.size=Vector2(320,5)
	progress.show_percentage=false
	progress.max_value=600
	progress.add_theme_stylebox_override("background",_style(Color("35584f"),3))
	progress.add_theme_stylebox_override("fill",_style(GOLD,3))
	hud.add_child(progress)
	hint_label=_label("",22,CREAM)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position=Vector2(-370,-98)
	hint_label.size=Vector2(740,65)
	hint_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(hint_label)
	stick=Joystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position=Vector2(32,-190)
	stick.size=Vector2(152,152)
	hud.add_child(stick)
	interact_button=_button("Throw seed",func(): action_pressed=true)
	interact_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	interact_button.position=Vector2(-232,-168)
	interact_button.size=Vector2(195,72)
	hud.add_child(interact_button)
	finish_button=_button("Finish recording",_finish_recording,false)
	finish_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	finish_button.position=Vector2(-232,-87)
	finish_button.size=Vector2(195,47)
	hud.add_child(finish_button)
	overlay=Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)
	toast_label=_label("",18,INK)
	toast_label.add_theme_stylebox_override("normal",_style(CREAM,12))
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_label.position=Vector2(-350,112)
	toast_label.size=Vector2(700,60)
	toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	toast_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	toast_label.visible=false
	ui.add_child(toast_label)

func _refresh_safe_area() -> void:
	if not is_instance_valid(ui):
		return
	var viewport := get_viewport().get_visible_rect()
	var safe := viewport
	if OS.has_feature("android"):
		safe=SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()),get_viewport().get_screen_transform(),viewport)
	_apply_safe_area(safe)

func _apply_safe_area(safe: Rect2) -> void:
	var viewport := get_viewport().get_visible_rect()
	ui.offset_left=safe.position.x-viewport.position.x
	ui.offset_top=safe.position.y-viewport.position.y
	ui.offset_right=safe.end.x-viewport.end.x
	ui.offset_bottom=safe.end.y-viewport.end.y
	_update_shade_bounds()

func _update_shade_bounds() -> void:
	# The world and dialog backdrop fill the screen; only interactive UI is inset.
	if is_instance_valid(overlay_shade):
		overlay_shade.offset_left=-ui.offset_left
		overlay_shade.offset_top=-ui.offset_top
		overlay_shade.offset_right=-ui.offset_right
		overlay_shade.offset_bottom=-ui.offset_bottom

func _label(text: String, font_size: int=20, color: Color=CREAM, title: bool=false) -> Label:
	var label := Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	if title:
		label.add_theme_font_override("font",title_font)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, callback: Callable, primary: bool=true) -> Button:
	var button := Button.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,54)
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	if not primary:
		button.add_theme_stylebox_override("normal",_style(Color("254b45"),14,Color("54766a")))
		button.add_theme_color_override("font_color",CREAM)
	button.focus_mode=Control.FOCUS_ALL
	return button

func _list_button(text: String, callback: Callable, primary: bool=true) -> Button:
	var button := _button(text,callback,primary)
	# Let the scroll container receive a drag that starts on a row. Its built-in
	# scroll notification cancels the pending tap once the gesture starts moving.
	button.mouse_filter=Control.MOUSE_FILTER_PASS
	return button

func _clear_overlay() -> void:
	overlay_shade=null
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible=true

func _close_overlay() -> void:
	_clear_overlay()
	overlay.visible=false

func _card(width: float=560.0) -> VBoxContainer:
	_clear_overlay()
	var shade := ColorRect.new()
	shade.color=Color(0.025,0.10,0.10,0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	overlay_shade=shade
	_update_shade_bounds()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size=Vector2(width,0)
	panel.add_theme_stylebox_override("panel",_style(Color("163c36"),24,Color("51786a")))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side,14)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",14)
	margin.add_child(stack)
	return stack

func _paragraph(text: String, width: float=480) -> Label:
	var result := _label(text,19,MUTED)
	result.custom_minimum_size.x=width
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return result

func _show_home() -> void:
	running=false
	mode="home"
	room_play=false
	hud.visible=false
	world.home_view=true
	_clear_overlay()
	var stack := VBoxContainer.new()
	stack.position=Vector2(64,72)
	stack.size=Vector2(385,570)
	stack.add_theme_constant_override("separation",17)
	overlay.add_child(stack)
	stack.add_child(_label("A LITTLE WORLD. TWO DIFFERENT TIMES.",15,MINT))
	stack.add_child(_label("After\nYou",88,CREAM,true))
	stack.add_child(_paragraph("Catch something your friend\nthrew yesterday.",385))
	var spacer := Control.new()
	spacer.custom_minimum_size.y=12
	stack.add_child(spacer)
	stack.add_child(_button("Find your first island   →",_show_journey))
	stack.add_child(_button("Play with a friend",_show_rooms,false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	stack.add_child(row)
	var collection := _button("Your replays",_show_collection,false)
	collection.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(collection)
	var settings := _button("Settings",_show_settings,false)
	settings.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(settings)
	var caption := _label("Record a moment. Leave it for someone.",17,MUTED)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	caption.position=Vector2(-470,-48)
	overlay.add_child(caption)

func _show_journey() -> void:
	running=false
	mode="journey"
	var card := _card(800)
	card.add_child(_label("Eight islands. One shared journey.",34,CREAM,true))
	card.add_child(_paragraph("Practice both parts on your own, or bring a friend when you’re ready.",710))
	card.add_child(_button("Try the new Relay Isles · solo preview", _open_relay_preview))
	var grid := GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",14)
	grid.add_theme_constant_override("v_separation",12)
	card.add_child(grid)
	for index in range(levels.size()):
		var level: Dictionary=levels[index]
		var locked: bool = index>=3 and not purchases.has_entitlement()
		var complete: bool = saves.data.completed.has(level.id)
		var text := "%02d  %s%s" % [index+1,level.title,"  ·  Full Journey" if locked else ("  ✓" if complete else "")]
		var button := _button(text,func(): _start_practice(index),false)
		button.custom_minimum_size=Vector2(350,65)
		button.add_theme_font_size_override("font_size",18)
		grid.add_child(button)
	card.add_child(_button("Back",_show_home,false))

func _open_relay_preview() -> void:
	if submission_in_flight:
		_toast("Wait for the saved turn's receipt before beginning another rehearsal.")
		return
	get_tree().change_scene_to_file("res://relay_preview.tscn")

func _start_practice(index: int) -> void:
	if submission_in_flight:
		_toast("Wait for the saved turn's receipt before beginning another rehearsal.")
		return
	if index<0 or index>=levels.size():
		return
	if index>=3 and not purchases.has_entitlement():
		_show_paywall()
		return
	room_play=false
	collection_preview=false
	level_index=index
	current_level=levels[index]
	attempt=saves.attempt(current_level.id)
	role="b" if not attempt.get("a",{}).is_empty() else "a"
	if not attempt.get("b",{}).is_empty():
		var card := _card()
		card.add_child(_label("A little moment, kept.",34,CREAM,true))
		card.add_child(_paragraph("You completed this island. Watch both turns together, or start a fresh attempt."))
		card.add_child(_button("Watch your replay",func(): _preview(attempt.b,true)))
		card.add_child(_button("Start a fresh attempt",_restart_attempt,false))
		card.add_child(_button("Back",_show_journey,false))
		return
	_prepare_turn()

func _prepare_turn() -> void:
	if submission_in_flight:
		_toast("Wait for the saved turn's receipt before beginning another rehearsal.")
		return
	running=false
	mode="ready"
	collection_preview=false
	review_recording={}
	action_pressed=false
	stick.release()
	attempt=LocalSave.normalize_attempt(attempt)
	world.home_view=false
	world.load_level(current_level)
	if not sim.reset(current_level,attempt.get("a",{}) if role=="b" else {},role):
		_toast(sim.error)
		_show_journey()
		return
	sim.catch_assistance=bool(saves.data.settings.get("assistance",true))
	world.present(sim.snapshot(),true)
	hud.visible=true
	role_label.text="%02d / %s  ·  %s" % [level_index+1,current_level.title,"Your first turn" if role=="a" else "Alongside a ghost"]
	interact_button.text="Throw seed" if role=="a" else "Plant seed"
	finish_button.visible=role=="a"
	stick.visible=true
	interact_button.visible=true
	_update_hud(sim.snapshot())
	var card := _card()
	card.add_child(_label("Leave a moment." if role=="a" else "Pick up where they left off.",34,CREAM,true))
	card.add_child(_paragraph(str(current_level.get("hint_"+role,""))))
	card.add_child(_paragraph("Move with the thumbstick. Tap the action button when you’re in place. You can rehearse as often as you like."))
	var draft: Dictionary=attempt.get("draft",{})
	if draft.get("role","")==role and int(draft.get("duration_ticks",0))>0:
		card.add_child(_button("Resume saved rehearsal",func(): _resume_draft(draft)))
	card.add_child(_button("Begin this turn",_begin_turn))
	card.add_child(_button("Back",_show_rooms if room_play else _show_journey,false))

func _begin_turn() -> void:
	if application_backgrounded or submission_in_flight:
		return
	_close_overlay()
	mode="play"
	running=true
	action_pressed=false
	stick.release()

func _resume_draft(draft: Dictionary) -> void:
	var check: Dictionary=TurnState.review(current_level,draft,attempt)
	if not check.valid or draft.get("role","")!=role:
		_toast("This rehearsal could not be resumed. "+str(check.get("error","")))
		return
	sim.catch_assistance=bool(draft.get("catch_assistance",true))
	if not sim.reset(current_level,attempt.a if role=="b" else {},role):
		_toast(sim.error)
		return
	for input in Simulation.expand_recording_inputs(draft):
		sim.step(input)
	world.present(sim.snapshot(),true)
	if sim.finished:
		review_recording=draft.duplicate(true)
		_show_review()
		return
	_begin_turn()

func _physics_process(_delta: float) -> void:
	if not running:
		return
	var input: Dictionary={}
	if mode=="preview":
		if replay_index>=replay_frames.size():
			running=false
			_show_review()
			return
		input=replay_frames[replay_index]
		replay_index+=1
	else:
		var movement: Vector2=stick.value
		var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if keyboard.length()>0:
			movement=keyboard.limit_length()
		# Screen-relative input follows the fixed camera's horizontal axes.
		var right: Vector3=world.camera.global_basis.x
		var forward: Vector3=world.camera.global_basis.z
		var world_move := (Vector3(right.x,0,right.z).normalized()*movement.x + Vector3(forward.x,0,forward.z).normalized()*movement.y).limit_length()
		input={"move_x":world_move.x,"move_z":world_move.z,"interact":action_pressed}
		action_pressed=false
	var previous_tick: int=sim.tick
	var state: Dictionary=sim.step(input)
	if int(state.tick)!=previous_tick:
		soundscape.consume_events(state.events,mode=="play")
	world.present(state)
	_update_hud(state)
	if mode=="play" and sim.tick%30==0 and not state.finished:
		if not _save_draft():
			_toast(saves.last_error)
	if state.finished:
		running=false
		var draft_saved := true
		if mode=="play":
			review_recording=sim.export_recording()
			draft_saved=_save_draft()
			if not draft_saved:
				_toast(saves.last_error)
		if state.complete and draft_saved:
			_begin_completion_moment()
		else:
			_show_review()

func _begin_completion_moment() -> void:
	# The live draft is already durable; replay leaves its saved source untouched.
	# Keep presentation alive without another simulation step or delayed callback.
	running=false
	mode="completion"
	completion_time_left=COMPLETION_MOMENT_SECONDS
	action_pressed=false
	stick.release()
	stick.visible=false
	interact_button.visible=false
	finish_button.visible=false
	_close_overlay()

func _advance_completion_moment(delta: float) -> void:
	if mode!="completion" or application_backgrounded:
		return
	completion_time_left=maxf(0.0,completion_time_left-delta)
	if completion_time_left<=0.0:
		_show_review()

func _update_hud(state: Dictionary) -> void:
	timer_label.text="%.1f" % ((600-int(state.tick))/30.0)
	progress.value=state.tick
	hint_label.text=str(state.message)
	finish_button.disabled=not state.can_commit
	if role=="b":
		interact_button.text="Plant seed" if state.seed.status=="held_b" else "Catch seed"

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_SPACE and mode=="play" and running:
			action_pressed=true
		if event.physical_keycode==KEY_ESCAPE:
			_pause() if running or mode=="completion" else _show_home()

func _save_draft() -> bool:
	if mode!="play" or sim.tick==0:
		return true
	attempt["draft"]=sim.export_recording()
	if room_play:
		return saves.update_values({"room_draft":{"room_id":active_room.get("room_id",""),"revision":active_room.get("revision",-1),"attempt":attempt.duplicate(true)}})
	return saves.save_attempt(current_level.id,attempt)

func _finish_recording() -> void:
	if mode!="play" or not running or not sim.can_commit():
		return
	running=false
	review_recording=sim.export_recording()
	_save_draft()
	_show_review()

func _show_review() -> void:
	running=false
	stick.release()
	var check: Dictionary=TurnState.review(current_level,review_recording,attempt)
	var valid: bool=check.valid and check.can_commit
	var complete: bool = valid and bool(review_recording.get("completed",false))
	mode="collection" if collection_preview else "review"
	var card := _card()
	card.add_child(_label("Look what you made together." if complete else ("A moment worth leaving." if valid else "Another little try?"),32,CREAM,true))
	card.add_child(_paragraph("Your combined replay is ready to keep." if complete else ("Preview your recording before you commit it. It won’t change until you start a new attempt." if valid else "The seed needs a complete handoff. Your earlier committed recording is safe.")))
	if not review_recording.is_empty():
		card.add_child(_button("Watch replay",func(): _preview(review_recording,collection_preview)))
	var already_saved := collection_preview
	if valid and not already_saved:
		card.add_child(_button("Commit turn" if room_play else ("Keep this island" if complete else "Save & play the other part"),_commit_turn))
	if not already_saved:
		card.add_child(_button("Rehearse again",_prepare_turn,false))
	card.add_child(_button("Back to rooms" if room_play else "Back to islands",_show_rooms if room_play else _show_journey,false))

func _preview(recording: Dictionary, collection: bool=false) -> void:
	var check: Dictionary=TurnState.review(current_level,recording,attempt)
	if not check.valid:
		_toast("This recording cannot be replayed. "+str(check.get("error","")))
		return
	review_recording=recording.duplicate(true)
	role=str(recording.role)
	world.load_level(current_level)
	world.home_view=false
	sim.catch_assistance=bool(recording.get("catch_assistance",true))
	if not sim.reset(current_level,attempt.get("a",{}) if role=="b" else {},role):
		_toast(sim.error)
		return
	replay_frames=Simulation.expand_recording_inputs(recording)
	replay_index=0
	mode="preview"
	collection_preview=collection
	_close_overlay()
	hud.visible=true
	stick.visible=false
	interact_button.visible=false
	finish_button.visible=false
	role_label.text=current_level.title+"  ·  Your shared replay"
	running=true

func _commit_turn() -> void:
	if mode!="review" or collection_preview:
		return
	var check: Dictionary=TurnState.review(current_level,review_recording,attempt)
	if not check.valid or not check.can_commit:
		_toast("This turn is not ready to commit. "+str(check.get("error","")))
		return
	if room_play:
		await _commit_online()
		return
	var committed := attempt.duplicate(true)
	committed[role]=review_recording.duplicate(true)
	committed["draft"]={}
	if not saves.save_attempt(current_level.id,committed,role=="b"):
		_toast("Unable to save on this device. Your recording is still open.")
		return
	attempt=committed
	mode="saved"
	if role=="a":
		role="b"
		_prepare_turn()
	else:
		_show_celebration()

func _show_celebration() -> void:
	mode="saved"
	var card := _card()
	card.add_child(_label("After you, a little more life.",34,CREAM,true))
	card.add_child(_paragraph("This island is now part of your collection. Your two moments will always play together."))
	var row := HBoxContainer.new()
	for reaction in ["Beautiful!","We did it!","Again soon"]:
		row.add_child(_button(reaction,func(): _react(reaction),false))
	card.add_child(row)
	if level_index<7:
		card.add_child(_button("Next island",_next_island))
	card.add_child(_button("Watch together",func(): _preview(attempt.b,true)))
	card.add_child(_button("Home",_show_home,false))

func _react(reaction: String) -> void:
	if room_play:
		if api.busy or not saves.data.get("pending_turn",{}).is_empty():
			_toast("Finish checking your saved turn before sending a reaction.")
			return
		var codes := {"Beautiful!":"love","We did it!":"sparkles","Again soon":"again"}
		var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/"+str(active_room.room_id)+"/reactions",{"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key(),"reaction":codes[reaction]})
		if response.ok:
			_accept_room(response)
			_toast("Reaction sent.")
		else:
			_toast(response.error)
		return
	saves.data["last_reaction"]=reaction
	saves.flush()
	_toast(reaction)

func _next_island() -> void:
	if room_play:
		await _advance_room()
	elif level_index+1>=3 and not purchases.has_entitlement():
		_show_paywall()
	else:
		_start_practice(mini(level_index+1,7))

func _restart_attempt() -> void:
	if room_play:
		await _fork_room()
		return
	var old_data: Dictionary=saves.data.duplicate(true)
	if not attempt.get("a",{}).is_empty():
		var archive: Array=saves.data.get("attempt_archive",[])
		archive.append({"level_id":current_level.id,"attempt":attempt.duplicate(true)})
		saves.data["attempt_archive"]=archive
	var fresh := {"a":{},"b":{},"draft":{}}
	if not saves.save_attempt(current_level.id,fresh):
		saves.data=old_data
		_toast(saves.last_error)
		return
	attempt=fresh
	role="a"
	_prepare_turn()

func _pause() -> void:
	if mode=="completion":
		_show_review()
		return
	if mode not in ["play","preview"] or not running:
		return
	var previous_mode := mode
	running=false
	stick.release()
	action_pressed=false
	var draft_saved := _save_draft()
	mode="paused"
	var card := _card()
	card.add_child(_label("There’s no hurry.",36,CREAM,true))
	card.add_child(_paragraph("Your replay is paused." if previous_mode=="preview" else ("Your rehearsal is saved on this device. The clock waits for you." if draft_saved else "The rehearsal is still in memory, but this device could not save it. Continue and try saving again before closing.")))
	card.add_child(_button("Continue",func(): mode=previous_mode; _close_overlay(); running=true))
	if previous_mode=="play":
		card.add_child(_button("Restart this rehearsal",_prepare_turn,false))
	card.add_child(_button("Home",_show_home,false))

func _show_collection() -> void:
	running=false
	room_play=false
	mode="collection"
	var card := _card(700)
	card.add_child(_label("Little moments, kept.",36,CREAM,true))
	var list := _scroll_list(card)
	var count := 0
	for i in range(levels.size()):
		var saved: Dictionary=saves.attempt(levels[i].id)
		if saved.b.is_empty():
			saved=LocalSave.normalize_attempt(saves.data.replays.get(levels[i].id,{}))
		if not saved.get("b",{}).is_empty():
			count+=1
			list.add_child(_list_button(levels[i].title,func(): level_index=i; current_level=levels[i]; attempt=saved; _preview(saved.b,true),false))
	if count==0:
		list.add_child(_paragraph("Complete your first island to keep a replay of both contributions here.",580))
	if api.configured() and not saves.data.get("room",{}).is_empty():
		card.add_child(_button("Replays from your online room",_show_online_collection,false))
	card.add_child(_button("Back",_show_home,false))

func _show_settings() -> void:
	running=false
	mode="settings"
	var card := _card()
	card.add_child(_label("Make yourself at home.",34,CREAM,true))
	for entry in [["assistance","Forgiving catches"],["reduced_motion","Reduce motion"],["left_handed","Action button on the left"],["sound","Sound"],["haptics","Gentle haptics"]]:
		var toggle := CheckButton.new()
		toggle.text=entry[1]
		toggle.button_pressed=bool(saves.data.settings.get(entry[0],true))
		toggle.toggled.connect(func(value: bool): saves.data.settings[entry[0]]=value; saves.flush(); _apply_settings())
		card.add_child(toggle)
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation",10)
	card.add_child(links)
	for entry: Array in [["Account & recovery",_show_account],["Licenses",_show_licenses]]:
		var link := _button(entry[0],entry[1],false)
		link.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		links.add_child(link)
	card.add_child(_button("Done",_show_home))

func _show_licenses() -> void:
	running=false
	mode="licenses"
	var card := _card(680)
	card.add_child(_label("Made with care.",34,CREAM,true))
	card.add_child(_paragraph("Open-source tools and typefaces that help bring After You to life.",600))
	var list := _scroll_list(card)
	for entry: Dictionary in Licenses.entries():
		list.add_child(_list_button(str(entry.title),func(): _show_license(entry),false))
	card.add_child(_button("Back to settings",_show_settings,false))

func _show_license(entry: Dictionary) -> void:
	mode="license_text"
	var card := _card(920)
	card.add_child(_label(str(entry.title),30,CREAM,true))
	var text := RichTextLabel.new()
	text.name="LicenseText"
	text.bbcode_enabled=false
	text.selection_enabled=true
	text.scroll_active=true
	text.custom_minimum_size=Vector2(840,390)
	text.add_theme_font_size_override("normal_font_size",18)
	text.add_theme_color_override("default_color",CREAM)
	text.text=str(entry.text)
	card.add_child(text)
	card.add_child(_button("Back to licenses",_show_licenses,false))

func _apply_settings() -> void:
	soundscape.configure(saves.data.settings)
	world.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
	var left := bool(saves.data.settings.get("left_handed",false))
	stick.anchor_left=1.0 if left else 0.0
	stick.anchor_right=stick.anchor_left
	# Once parented, position is absolute in the HUD. Use anchor-relative
	# offsets so right-aligned controls remain inside the viewport on resize.
	stick.offset_left=-188 if left else 32
	stick.offset_right=stick.offset_left+152
	for button in [interact_button,finish_button]:
		button.anchor_left=0.0 if left else 1.0
		button.anchor_right=button.anchor_left
		button.offset_left=36 if left else -232
		button.offset_right=button.offset_left+195

func _show_paywall() -> void:
	running=false
	mode="paywall"
	var card := _card()
	card.add_child(_label("The rest of your journey.",34,CREAM,true))
	card.add_child(_paragraph("Five more islands. More ways to leave a moment for someone. One purchase unlocks your journey; friends can join your hosted islands for free."))
	var key := str(config.get("revenuecat_public_key",""))
	if key.is_empty() or not purchases.is_available():
		card.add_child(_paragraph("Purchases are not connected in this build. The three introductory islands remain playable."))
	else:
		card.add_child(_paragraph("Loading the store’s current offer…"))
		_load_store()
	if not key.is_empty() and purchases.is_available():
		card.add_child(_button("Restore purchases",_restore_store,false))
	card.add_child(_button("Back to islands",_show_journey,false))

func _load_store() -> void:
	if not await _ensure_identity():
		return
	if store_configured:
		purchases.fetch_offerings()
	else:
		_configure_purchases()

func _restore_store() -> void:
	if not await _ensure_identity():
		return
	if store_configured:
		purchases.restore()
	else:
		restore_requested=true
		_configure_purchases()

func _purchase_completed(_id: String, operation: String, payload: Dictionary) -> void:
	if operation=="configure":
		store_configured=true
		if restore_requested:
			restore_requested=false
			purchases.restore()
		elif mode=="paywall":
			purchases.fetch_offerings()
	elif operation=="get_offerings":
		if mode!="paywall":
			return
		purchase_package=Purchases.select_lifetime_offer(payload)
		if purchase_package.is_empty():
			_toast("No offer is available from the store yet.")
			return
		var card := _card()
		card.add_child(_label("Your Full Journey",36,CREAM,true))
		card.add_child(_paragraph("Unlock all eight islands. Your invited friend plays your hosted islands free. One purchase, no subscription."))
		if str(payload.get("mode",""))=="test_store":
			card.add_child(_paragraph("RevenueCat Test Store · This build uses test checkout, not a real-money store purchase."))
		card.add_child(_button("Unlock · "+str(purchase_package.price),func(): purchases.purchase(str(purchase_package.offering_id),str(purchase_package.id))))
		card.add_child(_button("Restore purchases",_restore_store,false))
		card.add_child(_button("Back",_show_journey,false))
	elif operation in ["purchase_package","restore_purchases"]:
		_toast("Full Journey unlocked." if purchases.has_entitlement() else "No active Full Journey purchase was found.")
		_show_journey()

func _purchase_failed(_id: String,_operation: String,_code: String,message: String,cancelled: bool) -> void:
	_toast("Purchase cancelled. Nothing changed." if cancelled else message)

func _customer_info_changed(_payload: Dictionary) -> void:
	# The store may finish loading after the grid opens. Refresh labels here;
	# button callbacks still check the current entitlement when pressed.
	if mode=="journey":
		_show_journey()

func _load_saved_identity() -> void:
	if identity_loading or identity_busy or identity_restart_required:
		return
	identity_read_state=IdentityReadState.LOADING
	identity_loading=true
	# A saved rotation takes precedence over possibly revoked device credentials.
	recovery_read_request=secrets.get_secret("recovery_pending")

func _retry_saved_identity() -> void:
	_load_saved_identity()
	mode="account_loading"
	var card := _card()
	card.add_child(_label("Checking your saved identity…",30,CREAM,true))
	card.add_child(_button("Back",_show_account,false))
	var deadline := Time.get_ticks_msec()+10000
	while identity_loading and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	if mode=="account_loading":
		_show_account()

func _secret_completed(id: String, operation: String, payload: Dictionary) -> void:
	secret_results[id]={"ok":true,"payload":payload}
	if id==recovery_read_request and operation=="get":
		secret_results.erase(id)
		if payload.get("found") is bool and payload.found==false and payload.get("value")==null:
			identity_request=secrets.get_secret("player_identity")
			return
		identity_loading=false
		identity_read_state=IdentityReadState.FAILED
		if payload.get("found") is bool and payload.found==true and payload.get("value") is String:
			var saved: Variant=_parse_json(payload.value)
			if _valid_pending_recovery(saved):
				pending_recovery=saved
				identity_read_state=IdentityReadState.RECOVERY_PENDING
				identity_restart_required=true
				_toast("An identity recovery is saved. Finish it in Settings → Account & recovery.")
	elif id==identity_request and operation=="get":
		identity_loading=false
		# Only an explicit not-found response permits a new identity. Failed
		# decryption or malformed stored data must never become a fresh install.
		identity_read_state=IdentityReadState.FAILED
		if payload.get("found") is bool and payload.found==false and payload.get("value")==null:
			identity_read_state=IdentityReadState.MISSING
		elif payload.get("found") is bool and payload.found==true and payload.get("value") is String:
			var identity: Variant=_parse_json(payload.value)
			if identity is Dictionary and identity.get("player_id") is String and identity.get("device_token") is String and not identity.player_id.is_empty() and not identity.device_token.is_empty():
				identity_read_state=IdentityReadState.LOADED
				identity_data=identity
				api.player_id=identity.player_id
				api.device_token=identity.device_token
				_configure_purchases()
		secret_results.erase(id)

func _secret_failed(id: String, _operation: String, code: String) -> void:
	secret_results[id]={"ok":false,"code":code}
	if id==identity_request or id==recovery_read_request:
		identity_loading=false
		identity_read_state=IdentityReadState.FAILED
		secret_results.erase(id)

func _await_secret(id: String) -> Dictionary:
	var deadline := Time.get_ticks_msec()+10000
	while not secret_results.has(id) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	var result: Dictionary=secret_results.get(id,{"ok":false,"code":"storage_timeout"})
	secret_results.erase(id)
	return result

func _configure_purchases() -> void:
	if identity_restart_required:
		return
	var key := str(config.get("revenuecat_public_key",""))
	if not key.is_empty() and not api.player_id.is_empty() and not store_configured:
		purchases.configure_store(key,api.player_id,str(config.get("purchase_mode","test_store")))

func _show_rooms() -> void:
	running=false
	mode="rooms"
	var card := _card()
	card.add_child(_label("Same island. Your own time.",34,CREAM,true))
	if not api.configured():
		card.add_child(_paragraph("Online rooms are not connected in this build yet. Your solo recordings are saved locally."))
		card.add_child(_button("Practice on your own",_show_journey))
	else:
		card.add_child(_paragraph("Invite a friend with a room code. Both of you install After You; neither needs to wait online."))
		card.add_child(_button("Create an island room",_create_room))
		var field := LineEdit.new()
		field.placeholder_text="Invitation code"
		field.custom_minimum_size.y=52
		card.add_child(field)
		card.add_child(_button("Join your friend",func(): _join_room(field.text),false))
		if not saves.data.get("room",{}).is_empty():
			card.add_child(_button("Return to your room",_refresh_room,false))
		card.add_child(_button("Your online rooms",_show_saved_rooms,false))
		if not saves.data.get("pending_turn",{}).is_empty():
			card.add_child(_button("Check saved submission",_reconcile_pending,false))
	card.add_child(_button("Back",_show_home,false))

func _ensure_identity() -> bool:
	if not pending_recovery.is_empty():
		_toast("Finish your saved identity recovery in Settings → Account & recovery.")
		return false
	if identity_restart_required:
		_toast("Close and reopen After You to finish changing your identity.")
		return false
	if identity_loading:
		var deadline := Time.get_ticks_msec()+10000
		while identity_loading and Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
		if identity_loading:
			_toast("Your saved identity is still loading. Please try again shortly.")
			return false
	if not api.player_id.is_empty() and not api.device_token.is_empty():
		return true
	if identity_busy:
		_toast("Your identity is being prepared. Please wait a moment.")
		return false
	if not secrets.is_available():
		_toast("Online identity storage requires the Android app.")
		return false
	if identity_read_state!=IdentityReadState.MISSING:
		_toast("Your saved identity could not be checked. Use Settings → Account & recovery to retry or recover it. Nothing has been replaced.")
		return false
	identity_busy=true
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/identity")
	if not response.ok:
		identity_busy=false
		_toast(response.error)
		return false
	var persisted: Dictionary=await _await_secret(secrets.put_secret("player_identity",JSON.stringify(response.data)))
	identity_busy=false
	if not persisted.ok:
		identity_read_state=IdentityReadState.FAILED
		_toast("The online identity could not be secured on this device. Online play has not started.")
		return false
	identity_read_state=IdentityReadState.LOADED
	identity_data=response.data.duplicate(true)
	api.player_id=str(response.data.player_id)
	api.device_token=str(response.data.device_token)
	_configure_purchases()
	return true

func _create_room() -> void:
	if not await _ensure_identity():
		return
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms",{"idempotency_key":RoomsApi.new_key()})
	_accept_room(response)

func _join_room(code: String) -> void:
	if code.strip_edges().is_empty() or not await _ensure_identity():
		return
	_accept_room(await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/join",{"invite_code":code.strip_edges()}))

func _refresh_room() -> void:
	if api.busy:
		return
	# An explicit refresh supersedes any older automatically fetched snapshot.
	foreground_refresh_queued=false
	foreground_response={}
	lifecycle_generation+=1
	if not await _ensure_identity():
		return
	var room_id := str(saves.data.get("room",{}).get("room_id",""))
	if room_id.is_empty():
		_show_rooms()
		return
	_accept_room(await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id))

func _accept_room(response: Dictionary) -> void:
	if not response.ok:
		_toast(response.error)
		return
	var incoming: Variant=response.data.get("room",response.data)
	if not incoming is Dictionary or str(incoming.get("room_id","")).is_empty() or Levels.get_level(str(incoming.get("level_id",""))).is_empty():
		_toast("The room response was incomplete. Your saved turn is unchanged.")
		return
	active_room=incoming.duplicate(true)
	var erased: Array=[]
	if TurnState.pending_status(saves.data.get("pending_turn",{}),active_room)=="accepted":
		erased=["pending_turn","room_draft"]
	if not saves.update_values({"room":active_room},erased):
		_toast(saves.last_error)
	_show_room_detail()

func _show_room_detail() -> void:
	running=false
	mode="room"
	var card := _card()
	card.add_child(_label("A place for the two of you.",34,CREAM,true))
	if active_room.has("invite_code"):
		card.add_child(_paragraph("Invitation code: "+str(active_room.invite_code)))
		card.add_child(_button("Copy invitation code",func(): DisplayServer.clipboard_set(str(active_room.invite_code)); _toast("Invitation code copied."),false))
	var active_role := str(active_room.get("active_role","a"))
	var my_turn: bool = TurnState.my_turn(active_room,api.player_id)
	var pending: Dictionary=saves.data.get("pending_turn",{})
	card.add_child(_paragraph("Island %d of 8 · %s" % [int(active_room.get("level_index",0))+1,"Your turn is ready." if my_turn else ("You made it bloom." if active_role=="complete" else "Your friend’s turn. Come back whenever you like.")]))
	if not pending.is_empty():
		card.add_child(_paragraph("A saved submission still needs its receipt checked before another turn can be sent."))
		card.add_child(_button("Check saved submission",_reconcile_pending))
	if my_turn and pending.is_empty():
		card.add_child(_button("Play your turn",_play_room_turn))
	if active_role=="complete":
		card.add_child(_button("Watch this island",_watch_room_replay,false))
		if int(active_room.get("level_index",0))<7 and pending.is_empty():
			card.add_child(_button("Next island",_advance_room))
		var reactions := HBoxContainer.new()
		for reaction: String in ["Beautiful!","We did it!","Again soon"]:
			reactions.add_child(_button(reaction,func(): room_play=true; _react(reaction),false))
		card.add_child(reactions)
	card.add_child(_button("Refresh",_refresh_room,false))
	if pending.is_empty() and not LocalSave.normalize_attempt(active_room.get("recordings",{})).a.is_empty():
		card.add_child(_button("Start a new attempt",_confirm_fork,false))
	card.add_child(_button("Home",_show_home,false))

func _play_room_turn() -> void:
	if not TurnState.my_turn(active_room,api.player_id) or not saves.data.get("pending_turn",{}).is_empty():
		_show_room_detail()
		return
	room_play=true
	level_index=int(active_room.level_index)
	current_level=Levels.get_level(str(active_room.level_id))
	role=str(active_room.active_role)
	attempt=LocalSave.normalize_attempt(active_room.get("recordings",{}))
	var local: Dictionary=saves.data.get("room_draft",{})
	if local.get("room_id","")==active_room.room_id and int(local.get("revision",-1))==int(active_room.revision):
		attempt.draft=local.get("attempt",{}).get("draft",{})
	_prepare_turn()

func _watch_room_replay() -> void:
	room_play=true
	level_index=int(active_room.level_index)
	current_level=Levels.get_level(str(active_room.level_id))
	attempt=LocalSave.normalize_attempt(active_room.get("recordings",{}))
	_preview(attempt.b,true)

func _commit_online() -> void:
	if api.busy:
		return
	var pending: Dictionary=saves.data.get("pending_turn",{})
	if not pending.is_empty():
		await _reconcile_pending()
		return
	if not TurnState.my_turn(active_room,api.player_id):
		_toast("Refresh the room before committing this rehearsal.")
		return
	pending={"room_id":active_room.room_id,"owner_player_id":api.player_id,"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key(),"recording":review_recording.duplicate(true)}
	if not saves.update_values({"pending_turn":pending}):
		_toast("The submission could not be saved safely. Nothing was sent.")
		return
	await _send_pending(pending)

func _send_pending(pending: Dictionary) -> void:
	submission_in_flight=true
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/"+str(pending.room_id)+"/turns",{"base_revision":pending.base_revision,"idempotency_key":pending.idempotency_key,"recording":pending.recording})
	submission_in_flight=false
	if response.ok:
		# The exact idempotency key returning success is the receipt, even if the
		# room has advanced and the API returns its latest snapshot.
		if not saves.update_values({},["pending_turn","room_draft"]):
			_toast("The server saved your turn; this device still needs to save its receipt.")
		_accept_room(response)
	else:
		if int(response.status)>=400 and int(response.status)<500 and int(response.status) not in [408,429]:
			pending["rejected"]=true
			pending["error"]=response.error
			saves.update_values({"pending_turn":pending})
		_toast(response.error+" Refresh before trying again.")

func _reconcile_pending() -> void:
	if api.busy or not await _ensure_identity():
		return
	var pending: Dictionary=saves.data.get("pending_turn",{})
	if pending.is_empty():
		return
	if pending.has("owner_player_id") and pending.owner_player_id!=api.player_id:
		_toast("This saved submission belongs to your earlier identity. Recover that identity to check its receipt.")
		return
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+str(pending.room_id))
	if not response.ok:
		if int(response.get("status",0)) in [404,410]:
			pending["rejected"]=true
			pending["error"]="This room is no longer available to this identity. Keep the rehearsal locally; it will not be submitted again."
			active_room={}
			saves.update_values({"pending_turn":pending})
			_show_held_turn(pending)
			return
		_toast(response.error+" The saved submission remains held.")
		return
	var room: Dictionary=response.data.get("room",response.data)
	var status := TurnState.pending_status(pending,room)
	if status=="accepted":
		_accept_room(response)
		_toast("Your saved turn is confirmed in the room.")
		return
	active_room=room.duplicate(true)
	if bool(pending.get("rejected",false)):
		_show_held_turn(pending)
		return
	# Retry once with exactly the same saved body/key. The server deduplicates
	# before revision checks, so an earlier success cannot become a second turn.
	await _send_pending(pending)
	var still_pending: Dictionary=saves.data.get("pending_turn",{})
	if bool(still_pending.get("rejected",false)):
		_show_held_turn(still_pending)

func _show_held_turn(pending: Dictionary) -> void:
	running=false
	mode="held"
	var card := _card()
	card.add_child(_label("Your rehearsal is still here.",32,CREAM,true))
	card.add_child(_paragraph(str(pending.get("error","The room changed before this turn could be saved."))))
	card.add_child(_paragraph("Keep this recording locally and return to the current room. It will not be submitted again automatically."))
	card.add_child(_button("Keep rehearsal & return",func(): _archive_held_turn(pending)))
	card.add_child(_button("Back",_show_rooms,false))

func _archive_held_turn(pending: Dictionary) -> void:
	var held: Array=saves.data.get("held_turns",[]).duplicate(true)
	held.append(pending.duplicate(true))
	var changes := {"held_turns":held,"room":active_room.duplicate(true)}
	if TurnState.my_turn(active_room,api.player_id) and pending.recording.level_id==active_room.level_id:
		var current_attempt := LocalSave.normalize_attempt(active_room.get("recordings",{}))
		if TurnState.review(Levels.get_level(active_room.level_id),pending.recording,current_attempt).valid:
			current_attempt.draft=pending.recording.duplicate(true)
			changes["room_draft"]={"room_id":active_room.room_id,"revision":active_room.revision,"attempt":current_attempt}
	if not saves.update_values(changes,["pending_turn"]):
		_toast(saves.last_error)
		return
	_show_rooms() if active_room.is_empty() else _show_room_detail()

func _confirm_fork() -> void:
	var card := _card()
	card.add_child(_label("Start a new attempt?",34,CREAM,true))
	card.add_child(_paragraph("The current first turn and its dependent second turn will be replaced. Both players will see the new attempt."))
	card.add_child(_button("Start a new attempt",_fork_room))
	card.add_child(_button("Keep this attempt",_show_room_detail,false))

func _fork_room() -> void:
	if api.busy or not saves.data.get("pending_turn",{}).is_empty():
		return
	_accept_room(await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/"+str(active_room.room_id)+"/fork",{"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key()}))

func _advance_room() -> void:
	if api.busy or not saves.data.get("pending_turn",{}).is_empty():
		return
	_accept_room(await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/"+str(active_room.room_id)+"/advance",{"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key()}))

func _show_account() -> void:
	running=false
	mode="account"
	var card := _card()
	card.add_child(_label("Your little corner.",34,CREAM,true))
	card.add_child(_paragraph("Your identity is anonymous. Device credentials stay in Android’s encrypted storage. Your recovery code gives access to your online identity; keep it private."))
	if not pending_recovery.is_empty():
		card.add_child(_paragraph("An identity recovery is saved on this device. Finish the same request before using online rooms."))
		card.add_child(_button("Finish identity recovery",_resume_pending_recovery))
	elif identity_restart_required:
		card.add_child(_paragraph("Close and reopen After You to finish changing your identity."))
		if not identity_data.is_empty():
			card.add_child(_button("Show my recovery details",_show_recovery_details,false))
		card.add_child(_button("Close After You",func(): get_tree().quit()))
	elif not api.player_id.is_empty():
		card.add_child(_button("Show my recovery details",_show_recovery_details,false))
		card.add_child(_button("Check hosting access",_check_hosting_access,false))
		card.add_child(_button("Restore purchases",_restore_store,false))
		card.add_child(_button("Delete online identity…",_confirm_delete_identity,false))
	elif api.configured() and secrets.is_available():
		if identity_read_state==IdentityReadState.MISSING:
			card.add_child(_button("Create anonymous identity",func(): if await _ensure_identity(): _show_account()))
		else:
			card.add_child(_paragraph("Your saved identity has not been read successfully. We will keep it intact. Check it again, or use your recovery code below."))
			card.add_child(_button("Check saved identity",_retry_saved_identity,false))
	else:
		card.add_child(_paragraph("Online identity and recovery require an Android build with the service connected."))
	if api.configured() and secrets.is_available() and pending_recovery.is_empty() and not identity_restart_required:
		card.add_child(_button("Recover a previous identity",_show_recovery_form,false))
	card.add_child(_button("Back",_show_settings,false))

func _check_hosting_access() -> void:
	# Checking an existing purchase must not create or replace an identity.
	if identity_restart_required or identity_loading or identity_busy:
		_toast("Finish loading or recovering your identity before checking hosting access.")
		return
	if api.player_id.is_empty() or api.device_token.is_empty():
		_toast("Create or recover your identity in Account & recovery before checking hosting access.")
		return
	if api.busy:
		_toast("Wait for the current online request to finish, then check again.")
		return
	running=false
	mode="hosting_access"
	var card := _card()
	card.add_child(_label("Checking hosting access…",32,CREAM,true))
	card.add_child(_paragraph("Checking this identity’s Full Journey purchase with the server."))
	card.add_child(_button("Back",_show_account,false))
	var player_id: String=api.player_id
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/entitlement")
	# A late response must not pull the player out of another screen or apply
	# the previous identity's purchase result after account recovery.
	if mode!="hosting_access" or player_id!=api.player_id or identity_restart_required:
		return
	_show_hosting_access(response)

func _show_hosting_access(response: Dictionary) -> void:
	var card := _card()
	card.add_child(_label("Hosting access",34,CREAM,true))
	var data: Variant=response.get("data")
	var verified: bool=response.get("ok",false)==true and data is Dictionary and data.get("status")=="verified" and data.get("full_journey") is bool
	if verified and data.full_journey:
		card.add_child(_label("Full Journey confirmed",24,CREAM,true))
		card.add_child(_paragraph("You can host all eight islands. Your invited friend can join your hosted islands without purchasing."))
	elif verified:
		card.add_child(_label("Introductory hosting",24,CREAM,true))
		card.add_child(_paragraph("The server has not found an active Full Journey unlock for this identity. You can host the three introductory islands. If you just purchased or restored, wait a moment and check again."))
	else:
		card.add_child(_label("Hosting access not checked",24,CREAM,true))
		card.add_child(_paragraph("We could not verify hosting access right now. This does not mean your purchase is missing. Try again in a moment."))
	# Server verification describes hosting only. It never changes or clears
	# the separate RevenueCat SDK entitlement used for local solo play.
	card.add_child(_button("Check again",_check_hosting_access,false))
	card.add_child(_button("Back",_show_account,false))

func _show_recovery_details() -> void:
	mode="recovery_details"
	var card := _card(680)
	card.add_child(_label("Keep this somewhere safe.",32,CREAM,true))
	card.add_child(_paragraph("Anyone with these details can recover your online identity. Recovery rotates the code and signs out the old device.",580))
	for entry: Array in [["Identity",str(identity_data.get("player_id",""))],["Recovery code",str(identity_data.get("recovery_code",""))]]:
		card.add_child(_label(entry[0],18,MUTED))
		var field := LineEdit.new()
		field.text=entry[1]
		field.editable=false
		field.custom_minimum_size=Vector2(580,48)
		card.add_child(field)
	var player := str(identity_data.get("player_id",""))
	var code := str(identity_data.get("recovery_code",""))
	var copy := _button("Copy recovery details",func(): _copy_recovery_details(player,code))
	copy.disabled=not _recovery_field_matches(player,RECOVERY_ID_PATTERN) or not _recovery_field_matches(code,RECOVERY_SECRET_PATTERN)
	card.add_child(copy)
	card.add_child(_button("Back",_show_account,false))

func _copy_recovery_details(player: String, code: String) -> void:
	if recovery_copy_busy:
		return
	if identity_busy or (not pending_recovery.is_empty() and not _can_copy_acknowledged_recovery()) or player!=identity_data.get("player_id","") or code!=identity_data.get("recovery_code","") or not _recovery_field_matches(player,RECOVERY_ID_PATTERN) or not _recovery_field_matches(code,RECOVERY_SECRET_PATTERN):
		_toast("Open your current recovery details after identity recovery finishes.")
		return
	recovery_copy_busy=true
	var result: Dictionary=await _await_secret(secrets.copy_recovery(player,code))
	recovery_copy_busy=false
	if result.get("ok",false) and result.get("payload",{}).get("copied")==true:
		_toast("Recovery details copied. Keep them somewhere private.")
	else:
		_toast("Could not copy recovery details. You can still select the fields above.")

func _can_copy_acknowledged_recovery() -> bool:
	# If secure storage fails after the server confirms rotation, the new code
	# is already current. Let the player copy it from the recovery error screen.
	var request: Dictionary=pending_recovery.get("request",{})
	return recovery_acknowledged and not request.is_empty() and identity_data.get("player_id")==request.get("player_id") and identity_data.get("recovery_code")==request.get("next_recovery_code") and identity_data.get("device_token")==request.get("next_device_token")

func _show_recovery_form() -> void:
	mode="recovery_form"
	var card := _card()
	card.add_child(_label("Welcome back.",34,CREAM,true))
	card.add_child(_paragraph("Paste your saved recovery details, or enter the two fields below. Recovering signs out the old device and gives you a new code."))
	var player := LineEdit.new()
	player.name="RecoveryIdentity"
	player.placeholder_text="Identity"
	player.custom_minimum_size.y=48
	var code := LineEdit.new()
	code.name="RecoveryCode"
	code.placeholder_text="Recovery code"
	code.secret=true
	code.custom_minimum_size.y=48
	var status := _paragraph("Paste fills the fields. Nothing is sent until you tap Recover identity.")
	status.name="RecoveryImportStatus"
	card.add_child(_button("Paste recovery details",func(): _import_recovery_details(DisplayServer.clipboard_get(),player,code,status),false))
	card.add_child(player)
	card.add_child(code)
	# Also accept the system Paste action in either field. Android may flatten
	# line breaks in a LineEdit; the local parser accepts that copied format.
	for field: LineEdit in [player,code]:
		field.text_changed.connect(func(text: String):
			if not RecoveryDetails.parse(text).is_empty():
				_import_recovery_details(text,player,code,status)
		)
	card.add_child(status)
	card.add_child(_button("Recover identity",func(): _recover_identity(player.text.strip_edges(),code.text.strip_edges())))
	card.add_child(_button("Cancel",_show_account,false))

func _import_recovery_details(text: String, player: LineEdit, code: LineEdit, status: Label) -> void:
	var details: Dictionary=RecoveryDetails.parse(text)
	if details.is_empty():
		status.text="Could not read those details. Copy the complete saved block, or enter the two fields separately."
		return
	player.text=details.player_id
	code.text=details.recovery_code
	player.release_focus()
	code.release_focus()
	status.text="Both fields are ready. Tap Recover identity when you want to continue."

func _recover_identity(player: String, code: String) -> void:
	if identity_loading:
		_toast("Wait for the saved identity check to finish before recovering another identity.")
		return
	if api.busy or identity_busy or player.is_empty() or code.is_empty():
		return
	if not _recovery_field_matches(player,RECOVERY_ID_PATTERN) or not _recovery_field_matches(code,RECOVERY_SECRET_PATTERN):
		_toast("Check the full identity and recovery code. The identity has 22 characters and the code has 43, using letters, numbers, - or _. Nothing has been sent.")
		return
	if not pending_recovery.is_empty():
		var old: Dictionary=pending_recovery.request
		if old.player_id==player and old.recovery_code==code:
			await _resume_pending_recovery()
			return
		if not recovery_replace_allowed:
			_show_pending_recovery("Finish the saved request before starting another recovery.")
			return
	# The next credentials are generated locally, and their full proposal must
	# be secured before the server can invalidate the previous credentials.
	recovery_acknowledged=false
	pending_recovery={"schema_version":1,"request":{"player_id":player,"recovery_code":code,"idempotency_key":RoomsApi.new_key(),"next_device_token":_new_recovery_secret(),"next_recovery_code":_new_recovery_secret()}}
	recovery_replace_allowed=false
	await _resume_pending_recovery()

static func _new_recovery_secret() -> String:
	return Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32)).replace("+","-").replace("/","_").trim_suffix("=")

static func _recovery_field_matches(value: Variant, pattern: String) -> bool:
	return value is String and RegEx.create_from_string(pattern).search(value)!=null

static func _valid_pending_recovery(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema_version")!=1 or not value.get("request") is Dictionary:
		return false
	var request: Dictionary=value.request
	if request.size()!=5:
		return false
	return _recovery_field_matches(request.get("player_id"),RECOVERY_ID_PATTERN) and _recovery_field_matches(request.get("recovery_code"),RECOVERY_SECRET_PATTERN) and _recovery_field_matches(request.get("idempotency_key"),RECOVERY_KEY_PATTERN) and _recovery_field_matches(request.get("next_device_token"),RECOVERY_SECRET_PATTERN) and _recovery_field_matches(request.get("next_recovery_code"),RECOVERY_SECRET_PATTERN) and request.next_device_token!=request.next_recovery_code and request.next_device_token!=request.recovery_code and request.next_recovery_code!=request.recovery_code

func _resume_pending_recovery() -> void:
	if identity_loading or identity_busy or api.busy or not _valid_pending_recovery(pending_recovery):
		return
	identity_busy=true
	identity_restart_required=true
	identity_read_state=IdentityReadState.RECOVERY_PENDING
	mode="recovery"
	var card := _card()
	card.add_child(_label("Finishing your recovery…",32,CREAM,true))
	card.add_child(_paragraph("Your recovery request will be kept securely on this device if the connection is interrupted."))
	var secured: Dictionary=await _await_secret(secrets.put_secret("recovery_pending",JSON.stringify(pending_recovery)))
	if not secured.ok or secured.get("payload",{}).get("stored")!=true:
		identity_busy=false
		_show_pending_recovery("The request could not be saved securely, so it has not been sent. Keep this window open and retry storage.")
		return
	var request: Dictionary=pending_recovery.request.duplicate(true)
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/identity/recover",request)
	var data: Variant=response.get("data")
	if not response.get("ok",false) or not data is Dictionary or not data.get("recovered") is bool or data.recovered!=true or data.get("player_id")!=request.player_id:
		identity_busy=false
		recovery_replace_allowed=(response.get("status")==401 and response.get("code")=="invalid_recovery") or (response.get("status")==409 and response.get("code")=="recovery_request_mismatch")
		_show_pending_recovery("The recovery code is no longer valid. Use a current recovery code, or retry the saved request." if recovery_replace_allowed else "We could not confirm recovery yet. Retry the same saved request; its new credentials are kept safely on this device.")
		return
	recovery_acknowledged=true
	identity_data={"player_id":request.player_id,"device_token":request.next_device_token,"recovery_code":request.next_recovery_code}
	purchases.customer_info={}
	await _persist_recovered_identity()

func _show_pending_recovery(message: String) -> void:
	mode="recovery"
	var card := _card()
	card.add_child(_label("Recovery is waiting.",32,CREAM,true))
	card.add_child(_paragraph(message))
	card.add_child(_button("Retry saved recovery",_resume_pending_recovery))
	if recovery_replace_allowed:
		card.add_child(_button("Use a different recovery code",_show_recovery_form,false))
	card.add_child(_button("Back to account",_show_account,false))

func _persist_recovered_identity() -> void:
	var persisted: Dictionary=await _await_secret(secrets.put_secret("player_identity",JSON.stringify(identity_data)))
	if not persisted.ok or persisted.get("payload",{}).get("stored")!=true:
		identity_busy=false
		_show_recovery_storage_failure()
		return
	var removed: Dictionary=await _await_secret(secrets.remove_secret("recovery_pending"))
	identity_busy=false
	if not removed.ok or removed.get("payload",{}).get("removed")!=true:
		_show_recovery_storage_failure()
		return
	pending_recovery={}
	recovery_replace_allowed=false
	_finish_identity_change()

func _show_recovery_storage_failure() -> void:
	var card := _card()
	card.add_child(_label("Keep this recovery window open.",30,CREAM,true))
	card.add_child(_paragraph("The server recovered your identity, but this device has not finished saving the new credentials and clearing the pending request. Retry storage or copy the new recovery details before closing."))
	card.add_child(_button("Retry secure storage",_retry_identity_storage))
	card.add_child(_button("Show new recovery details",_show_recovery_details,false))

func _retry_identity_storage() -> void:
	if identity_busy or identity_data.is_empty():
		return
	identity_busy=true
	await _persist_recovered_identity()

func _finish_identity_change() -> void:
	identity_read_state=IdentityReadState.LOADED
	identity_restart_required=true
	purchases.customer_info={}
	# Recovery is not proof of a pending turn's receipt. Keep its body/key so
	# reopening the same identity can reconcile it against the shared room.
	saves.update_values({"room":{}})
	var card := _card()
	card.add_child(_label("Your identity is recovered.",32,CREAM,true))
	card.add_child(_paragraph("Close and reopen After You to use it. Your new recovery details are securely stored on this device."))
	card.add_child(_button("Show new recovery details",_show_recovery_details,false))
	card.add_child(_button("Close After You",func(): get_tree().quit()))

func _confirm_delete_identity() -> void:
	var card := _card()
	card.add_child(_label("Delete your online identity?",30,CREAM,true))
	card.add_child(_paragraph("This permanently deletes your online identity and every shared room associated with it, including recordings and replays for both players. Your friend's copy of those rooms will disappear too. Local solo progress is kept."))
	card.add_child(_button("Delete identity and shared rooms",_delete_identity))
	card.add_child(_button("Keep my identity",_show_account,false))

func _delete_identity() -> void:
	if api.busy or not await _ensure_identity():
		return
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_DELETE,"/v1/identity")
	if not response.ok:
		_toast(response.error)
		return
	await _clear_deleted_identity()

func _clear_deleted_identity() -> void:
	var result: Dictionary=await _await_secret(secrets.remove_secret("player_identity"))
	var card := _card()
	card.add_child(_label("Your online identity is deleted.",30,CREAM,true))
	if not result.ok:
		card.add_child(_paragraph("The server deletion completed. This device still needs to clear its old encrypted credentials."))
		card.add_child(_button("Retry device cleanup",_clear_deleted_identity))
		return
	identity_data={}
	identity_read_state=IdentityReadState.MISSING
	api.player_id=""
	api.device_token=""
	identity_restart_required=true
	purchases.customer_info={}
	saves.update_values({"room":{}},["pending_turn","room_draft"])
	card.add_child(_paragraph("Your solo progress remains here. Close and reopen the app before creating another online identity."))
	card.add_child(_button("Close After You",func(): get_tree().quit()))

func _show_saved_rooms() -> void:
	if api.busy or not await _ensure_identity():
		return
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms")
	if not response.ok:
		_toast(response.error)
		return
	var card := _card(700)
	card.add_child(_label("Your shared places.",34,CREAM,true))
	var rows: Array=response.data.get("rooms",[])
	var list := _scroll_list(card)
	for value: Variant in rows:
		if value is Dictionary:
			var room: Dictionary=value.duplicate(true)
			var definition: Dictionary=Levels.get_level(str(room.get("level_id","")))
			list.add_child(_list_button(str(definition.get("title","Island"))+" · "+("Ready to replay" if room.get("active_role")=="complete" else "In progress"),func(): _accept_room({"ok":true,"data":room}),false))
	if rows.is_empty():
		list.add_child(_paragraph("Create an island room or join a friend's invitation to begin.",580))
	card.add_child(_button("Back",_show_rooms,false))

func _show_online_collection() -> void:
	if api.busy or not await _ensure_identity():
		return
	var room_id := str(saves.data.get("room",{}).get("room_id",""))
	if room_id.is_empty():
		return
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id+"/collection")
	if not response.ok:
		_toast(response.error)
		return
	var card := _card(700)
	card.add_child(_label("Moments from your shared journey.",30,CREAM,true))
	var rows: Array=response.data.get("islands",[])
	var list := _scroll_list(card)
	for value: Variant in rows:
		if value is Dictionary:
			var room: Dictionary=value.duplicate(true)
			var definition: Dictionary=Levels.get_level(str(room.get("level_id","")))
			list.add_child(_list_button(str(definition.get("title","Island")),func(): active_room=room; _watch_room_replay(),false))
	if rows.is_empty():
		list.add_child(_paragraph("Complete a shared island to keep its replay here.",580))
	card.add_child(_button("Back",_show_collection,false))

func _scroll_list(card: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(600,270)
	card.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",10)
	scroll.add_child(list)
	return list

static func _parse_json(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text)==OK else null

func _foreground_refresh_safe() -> bool:
	# A paused rehearsal is still active work. Do not swap its source recording,
	# revision or review screen behind the player's back.
	return not application_backgrounded and not running and not submission_in_flight and mode in ["home","rooms","room","journey","collection","settings","saved"]

func _background_application() -> void:
	if application_backgrounded:
		return
	application_backgrounded=true
	if is_instance_valid(soundscape):
		soundscape.set_backgrounded(true)
	lifecycle_generation+=1
	foreground_response={}
	action_pressed=false
	if is_instance_valid(stick):
		stick.release()
	if running:
		_pause()
	else:
		# Covers the narrow interval between finishing a live turn and presenting
		# review. Preview and menu modes do not create or overwrite drafts.
		_save_draft()

func _resume_application() -> void:
	# Android may deliver more than one resume/focus notification. A single
	# background-to-foreground transition schedules only one refresh.
	if not application_backgrounded:
		return
	application_backgrounded=false
	if is_instance_valid(soundscape):
		soundscape.set_backgrounded(false)
	lifecycle_generation+=1
	foreground_response={}
	foreground_refresh_queued=true
	# Do not resume the simulation automatically. The player explicitly presses
	# Continue on the pause card, keeping the recording clock under their control.

func _service_foreground_refresh() -> void:
	if not _foreground_refresh_safe() or foreground_refresh_running:
		return
	if not foreground_response.is_empty():
		var deferred := foreground_response
		foreground_response={}
		if int(deferred.get("generation",-1))==lifecycle_generation:
			_apply_foreground_response(deferred.response,str(deferred.room_id))
	if not foreground_refresh_queued or api==null or api.busy or identity_loading or identity_busy:
		return
	if not api.configured() or identity_restart_required or api.player_id.is_empty() or api.device_token.is_empty():
		foreground_refresh_queued=false
		return
	var pending: Dictionary=saves.data.get("pending_turn",{})
	var room_id := str(saves.data.get("room",{}).get("room_id",""))
	if not pending.is_empty() and (not pending.has("owner_player_id") or pending.owner_player_id==api.player_id):
		room_id=str(pending.get("room_id",""))
	foreground_refresh_queued=false
	if room_id.is_empty():
		return
	foreground_refresh_running=true
	var generation := lifecycle_generation
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id)
	foreground_refresh_running=false
	if generation!=lifecycle_generation:
		return
	if not _foreground_refresh_safe():
		foreground_response={"response":response,"room_id":room_id,"generation":generation}
		return
	_apply_foreground_response(response,room_id)

func _apply_foreground_response(response: Dictionary, requested_room: String) -> void:
	if not response.get("ok",false):
		if mode in ["room","rooms"]:
			_toast(str(response.get("error","The room could not refresh. Your saved rehearsal is unchanged.")))
		return
	var incoming: Variant=response.get("data",{})
	if incoming is Dictionary:
		incoming=incoming.get("room",incoming)
	if not incoming is Dictionary or str(incoming.get("room_id",""))!=requested_room or Levels.get_level(str(incoming.get("level_id",""))).is_empty():
		return
	var displayed: bool=str(active_room.get("room_id",""))==requested_room
	var remembered: bool=str(saves.data.get("room",{}).get("room_id",""))==requested_room
	var pending: Dictionary=saves.data.get("pending_turn",{})
	var confirmed: bool=TurnState.pending_status(pending,incoming)=="accepted"
	if not displayed and not remembered and not confirmed:
		return
	var known_revision := -1
	if displayed:
		known_revision=maxi(known_revision,int(active_room.get("revision",-1)))
	if remembered:
		known_revision=maxi(known_revision,int(saves.data.room.get("revision",-1)))
	if int(incoming.get("revision",-1))<known_revision:
		return
	var changes: Dictionary={}
	if remembered:
		changes["room"]=incoming.duplicate(true)
	var erased: Array=["pending_turn","room_draft"] if confirmed else []
	if not changes.is_empty() or not erased.is_empty():
		if not saves.update_values(changes,erased):
			_toast(saves.last_error)
			return
	if displayed:
		active_room=incoming.duplicate(true)
		if mode=="room":
			_show_room_detail()
	if confirmed:
		_toast("Your saved turn is confirmed in the room.")
	# An unmatched pending request stays queued for explicit reconciliation.
	# Returning to the app never starts or retries a POST automatically.

func _toast(text: String) -> void:
	toast_label.text=text
	toast_label.visible=true
	toast_time=6.0

func _process(delta: float) -> void:
	_advance_completion_moment(delta)
	_service_foreground_refresh()
	if toast_time>0:
		toast_time-=delta
		toast_label.visible=toast_time>0
	if not capture_path.is_empty():
		capture_frames+=1
		if capture_frames==90:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_path)
			get_tree().quit()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_PAUSED:
		_background_application()
	elif what==NOTIFICATION_APPLICATION_RESUMED:
		_refresh_safe_area.call_deferred()
		_resume_application()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if running or mode=="completion":
			_pause()
		elif mode=="license_text":
			_show_licenses()
		elif mode=="licenses":
			_show_settings()
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not _save_draft():
			_pause()
			_toast("The rehearsal could not be saved. Keep the app open and retry.")
			return
		get_tree().quit()
