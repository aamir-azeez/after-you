extends Node3D
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
var selected_online_chapter := ChapterRegistry.FIRST_STEPS

const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const World = preload("res://presentation/island_world.gd")
const HomeStage = preload("res://presentation/home_stage.gd")
const HomeKeepsakes = preload("res://services/home_keepsakes.gd")
const ChapterCompletion = preload("res://presentation/chapter_completion.gd")
const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")
const LocalSave = preload("res://services/local_save.gd")
const TurnState = preload("res://services/turn_state.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const RelayOnline = preload("res://services/relay_online_session.gd")
const RelayPreview = preload("res://relay_preview.gd")
const CampaignOwner = preload("res://services/campaign_online_session.gd")
const CampaignProtocol = preload("res://services/campaign_protocol.gd")
const CampaignStory = preload("res://services/campaign_story.gd")
const CampaignCatalog = preload("res://services/campaign_catalog.gd")
const CampaignFlow = preload("res://presentation/campaign_flow.gd")
const CampaignCanonical = preload("res://core/v2/canonical.gd")
const PaidThumbnails = preload("res://presentation/paid_level_thumbnails.gd")
const Purchases = preload("res://services/purchases.gd")
const TesterAccess = preload("res://services/tester_access.gd")
const Secrets = preload("res://services/secure_store.gd")
const RecoveryDetails = preload("res://services/recovery_details.gd")
const RoomReactions = preload("res://presentation/room_reactions.gd")
const Licenses = preload("res://services/licenses.gd")
const Soundscape = preload("res://services/soundscape.gd")
const RefreshClock = preload("res://services/refresh_schedule.gd")
const TurnNotifications = preload("res://services/turn_notifications.gd")
const FriendPresence = preload("res://services/friend_presence.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendsScreen = preload("res://presentation/friends_screen.gd")
const RedoClient = preload("res://services/redo_client.gd")
const RedoScreen = preload("res://presentation/redo_screen.gd")
const PresenceBadge = preload("res://presentation/friend_presence_badge.gd")
const NotificationBridge = preload("res://services/turn_notification_bridge.gd")
const ObjectivePanel = preload("res://presentation/objective_panel.gd")
const DeletedPhotos = preload("res://services/deleted_identity_photo_cleanup.gd")
const DeletedCaches = preload("res://services/deleted_identity_cache_cleanup.gd")
const DeletedAck = preload("res://services/deleted_identity_ack.gd")
const AuxiliaryContext = preload("res://services/campaign_auxiliary_context.gd")
const SharedReplays = preload("res://services/shared_replay_collection.gd")
const SharedReplayView = preload("res://presentation/shared_replay_view.gd")
const Safety = preload("res://services/safety_client.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const INK := Color("193d39")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("9dbeb4")
const GOLD := Color("f1c48a")
const RECOVERY_ID_PATTERN := "^[A-Za-z0-9_-]{22}$"
const RECOVERY_SECRET_PATTERN := "^[A-Za-z0-9_-]{43}$"
const RECOVERY_KEY_PATTERN := "^[A-Za-z0-9_-]{16,80}$"
const COMPLETION_MOMENT_SECONDS := 3.0
enum IdentityReadState { UNCHECKED, LOADING, MISSING, LOADED, FAILED, RECOVERY_PENDING }

var world: Node3D
var sim := Simulation.new()
var saves := LocalSave.new()
var home_keepsakes := HomeKeepsakes.new()
var home_stage_view: Control
var _keepsake_poll := 0.0
var _keepsake_identity: Dictionary = {}
var api: Node
var purchases: Node
var secrets: Node
var soundscape: Node
var config: Dictionary={}
var shared_replays: RefCounted
var friends_client: RefCounted
var friends_screen: CanvasLayer
var _friends_return_home := false
var friend_share_target: Dictionary = {}
var legacy_redo: RefCounted
var legacy_redo_restore_scope := ""
var legacy_redo_restore_ok := true
var redo_screen: CanvasLayer
var shared_replay_child: Node3D
var photo_transfer_child: Node
var shared_replay_room := ""
var _story_replay_return: Dictionary = {}
var ui: Control
var overlay: Control
var overlay_shade: ColorRect
var hud: Control
var stick: Control
var timer_label: Label
var objective_panel: PanelContainer
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
var _retry_cancel: Callable
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
var tester_access_factory: Callable
var tester_access: Node
var tester_loading := false
var tester_checked_context := ""
var tester_load_generation := 0
var tester_action_pending := false
var tester_store_manual := false
var store_configured := false
var restore_requested := false
var store_action_pending := false
var store_action_request := ""
var store_configure_request := ""
var store_owner := ""
var store_view_generation := 0
var store_restore_view := -1
var identity_restart_required := false
var application_backgrounded := false
var foreground_refresh_queued := false
var foreground_refresh_running := false
var foreground_schedule := RefreshClock.new()
var foreground_response: Dictionary = {}
var lifecycle_generation := 0
var submission_in_flight := false
var recovery_copy_busy := false
var recovery_acknowledged := false
var relay_session: RefCounted
var relay_child: Node3D
var relay_identity_epoch := 0
var relay_menu_generation := 0
# Default bundled content; callers may inject exact pairs or an empty catalog.
var campaign_catalog: Array = CampaignCatalog.bundled()
var campaign_owner: RefCounted
var campaign_flow: Node
var _campaign_generation := 0
var _campaign_action_busy := false
var _campaign_recovery_context: Dictionary = {}
var _campaign_choice := 0
var _story_access_return := false
var _story_store_return: Dictionary = {}
var room_reaction_notices: Dictionary = {}
var deleted_identity_owner := ""
var safety_screen: CanvasLayer
var safety_return := "settings"
var deletion_cleanup_busy := false
var deletion_photo_cleanup: Node
var deletion_cache_cleanup: RefCounted
var turn_notifications: Node
var notification_route_busy := false
var notification_route_retry_ms := 0
var notification_deferred_event := ""
var notification_hint: Label
var notification_offer: Button
var friend_presence: Node
var presence_hud: Label

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
	home_keepsakes.load_data()
	home_keepsakes.activate()
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
	# Keep presence independent of gameplay and alive across solo chapter scenes.
	# Offline/headless builds create no singleton or network work.
	if friend_presence == null and api.configured(): friend_presence = FriendPresence.shared(get_tree())
	if is_instance_valid(friend_presence):
		friend_presence.set_enabled(bool(saves.data.settings.get("share_online_status", true)))
	purchases=Purchases.new()
	add_child(purchases)
	purchases.completed.connect(_purchase_completed)
	purchases.failed.connect(_purchase_failed)
	purchases.customer_info_changed.connect(_customer_info_changed)
	secrets=Secrets.new()
	add_child(secrets)
	secrets.completed.connect(_secret_completed)
	secrets.failed.connect(_secret_failed)
	tester_access = tester_access_factory.call() if tester_access_factory.is_valid() else TesterAccess.new()
	add_child(tester_access)
	_setup_turn_notifications()
	world=World.new()
	add_child(world)
	world.footstep.connect(func():
		if running and mode in ["play","preview"]: soundscape.play_footstep())
	world.reunion.connect(func():
		if mode=="home" or (running and mode in ["play","preview"]): soundscape.play_reunion())
	world.load_level(current_level)
	sim.reset(current_level)
	world.present(sim.snapshot(),true)
	_build_theme()
	_build_ui()
	world.configure_camera_exploration(_camera_exploration_active, _camera_exploration_allowed)
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
	var menu_button := _action_button("pause",_pause)
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.position=Vector2(-168,24)
	menu_button.size=Vector2(132,54)
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
	objective_panel=ObjectivePanel.new()
	hud.add_child(objective_panel)
	objective_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	objective_panel.offset_left=-260
	objective_panel.offset_top=124
	objective_panel.offset_right=-36
	objective_panel.offset_bottom=124
	hint_label=_label("",22,CREAM)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position=Vector2(-370,-98)
	hint_label.size=Vector2(740,65)
	hint_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(hint_label)
	stick=Joystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position=Vector2(12,-210)
	stick.size=Vector2(Joystick.HIT_SIZE,Joystick.HIT_SIZE)
	hud.add_child(stick)
	interact_button=_button("Throw seed",_request_context_action)
	interact_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	interact_button.position=Vector2(-232,-168)
	interact_button.size=Vector2(195,72)
	hud.add_child(interact_button)
	finish_button=_action_button("finish",_finish_recording)
	finish_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	finish_button.position=Vector2(-247,-87)
	finish_button.size=Vector2(210,54)
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

func _action_button(action_id: String, callback: Callable) -> Button:
	var button := ActionButtons.create(action_id,callback)
	button.custom_minimum_size.y=54
	return button

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
	store_view_generation += 1
	if mode != "paywall": _story_store_return = {}
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
	var home_stage := HomeStage.new()
	home_stage_view = home_stage
	home_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home_keepsakes.reconcile_solo(saves.data.get("replays", {}))
	if shared_replays != null: home_keepsakes.reconcile_friend(shared_replays)
	var home_active := func() -> bool: return mode=="home" and not application_backgrounded and not is_instance_valid(relay_child)
	home_stage.configure(world,home_active,home_keepsakes.earned_descriptors())
	overlay.add_child(home_stage)
	var compact := ui.size.y < 640
	var stack := VBoxContainer.new()
	stack.position=Vector2(64,40 if compact else 72)
	stack.size=Vector2(385,570)
	stack.add_theme_constant_override("separation",10 if compact else 17)
	overlay.add_child(stack)
	stack.add_child(_label(PlayerCopy.MAIN_5DA48958135C,15,MINT))
	stack.add_child(_label("After\nYou",72 if compact else 88,CREAM,true))
	stack.add_child(_paragraph(PlayerCopy.MAIN_6A7ECC3FD1B9,385))
	var spacer := Control.new()
	spacer.custom_minimum_size.y=0 if compact else 12
	stack.add_child(spacer)
	stack.add_child(_button("Find your first island   →",_show_journey))
	# Keep all five actions in three rows, including within short cutout-safe
	# landscape areas. Horizontal groups retain full-size touch targets.
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation",10)
	stack.add_child(navigation)
	var friends := _button("Play with a friend",_show_rooms,false)
	friends.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	navigation.add_child(friends)
	navigation.add_child(_button("Settings",_show_settings,false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	stack.add_child(row)
	var collection := _button("Your replays",_show_collection,false)
	collection.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(collection)
	var shared := _button("Shared replays",_show_shared_replays,false)
	shared.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(shared)
	var caption := _label(PlayerCopy.MAIN_73EBEC98C7F5,17,MUTED)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	caption.position=Vector2(-470,-48)
	overlay.add_child(caption)
	var journey_offer := _button("Full Journey   →",_show_paywall,false)
	journey_offer.name = "HomeFullJourney"
	overlay.add_child(journey_offer)
	journey_offer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	journey_offer.offset_left = -238
	journey_offer.offset_right = -32
	journey_offer.offset_top = 32
	journey_offer.offset_bottom = 86
	journey_offer.visible = not _full_journey_access()
	var friends_shortcut := _button("Friends",_show_friends,false)
	friends_shortcut.name = "HomeFriends"
	overlay.add_child(friends_shortcut)
	friends_shortcut.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	friends_shortcut.offset_left = -382
	friends_shortcut.offset_right = -250
	friends_shortcut.offset_top = 32
	friends_shortcut.offset_bottom = 86
	home_stage.set_header_actions([journey_offer,friends_shortcut])

func _show_journey() -> void:
	running = false
	mode = "journey"
	var card := _card(820)
	card.add_child(_label(PlayerCopy.MAIN_1DB48306B203,34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_F88B3CEBD7BA,710))
	var chapters := _scroll_list(card)
	chapters.get_parent().custom_minimum_size.y = 340
	chapters.add_child(_free_chapter_row(_chapter_picker_row(ChapterRegistry.FIRST_STEPS,_open_first_steps)))
	var lighthouse_label := "Sleeping Lighthouse · Solo" + ("" if _full_journey_access() else " · Full Journey")
	var lighthouse_actions := VBoxContainer.new()
	var lighthouse_button := _list_button(lighthouse_label,_open_lighthouse_preview,false)
	lighthouse_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mark_chapter_button(lighthouse_button,"sleeping-lighthouse@1","solo")
	lighthouse_actions.add_child(lighthouse_button)
	chapters.add_child(PaidThumbnails.row("sleeping-lighthouse",lighthouse_actions,false))
	chapters.add_child(_free_chapter_row(_chapter_picker_row(ChapterRegistry.RELAY,_open_relay_preview)))
	for key: String in ChapterRegistry.keys():
		if not ChapterRegistry.is_cooperative(key): continue
		var item := ChapterRegistry.descriptor(key)
		var row := _chapter_picker_row(key,func(): _open_cooperative_preview(key))
		if item.premium:
			chapters.add_child(PaidThumbnails.row(str(item.level_id),row,false))
		else:
			chapters.add_child(_free_chapter_row(row))
	if _campaign_visible(): chapters.add_child(_list_button("Story",_show_story,false))
	chapters.add_child(_list_button("Earlier islands",_show_earlier_islands,false))
	card.add_child(_button("Back",_show_home,false))
	_refresh_chapter_marks()

func _chapter_picker_row(key: String, open_solo: Callable) -> HBoxContainer:
	var item := ChapterRegistry.descriptor(key)
	var row := HBoxContainer.new()
	row.set_meta("chapter_key",key)
	row.add_theme_constant_override("separation",14)
	var solo := _list_button(str(item.title)+" · Solo"+(" · Full Journey" if item.premium else ""),open_solo,false)
	solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mark_chapter_button(solo,key,"solo")
	row.add_child(solo)
	var together := _list_button("Together",func(): _show_relay_rooms(key),false)
	# Reserve the completed label's width too, so a tick never shifts its column.
	together.custom_minimum_size.x = 164
	_mark_chapter_button(together,key,"friend")
	row.add_child(together)
	return row

func _free_chapter_row(row: HBoxContainer) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left",10)
	margin.add_theme_constant_override("margin_right",10)
	margin.add_child(row)
	return margin

func _mark_chapter_button(button: Button, key: String, variant: String) -> void:
	button.set_meta("completion_chapter",key)
	button.set_meta("completion_variant",variant)
	button.set_meta("completion_label",button.text)

func _refresh_chapter_marks() -> void:
	if mode != "journey": return
	var marks := ChapterCompletion.chapters(home_keepsakes.earned_descriptors())
	var buttons := overlay.find_children("*","Button",true,false)
	var together_width := 164.0
	for button: Button in buttons:
		if button.get_meta("completion_variant","") != "friend": continue
		var completed_width := button.get_theme_font("font").get_string_size("Together  ✓",HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
		together_width = maxf(together_width,ceilf(completed_width+button.get_theme_stylebox("normal").get_minimum_size().x))
	for button: Button in buttons:
		if not button.has_meta("completion_chapter"): continue
		if button.get_meta("completion_variant")=="friend": button.custom_minimum_size.x=together_width
		var complete: bool = marks.get(button.get_meta("completion_chapter"),{}).get(button.get_meta("completion_variant"),false)
		button.text = str(button.get_meta("completion_label")) + ("  ✓" if complete else "")
		button.set_meta("chapter_complete",complete)
		if complete: button.add_theme_color_override("font_color",MINT)
		else: button.add_theme_color_override("font_color",CREAM)

func _open_first_steps() -> void:
	_open_chapter_preview("res://first_steps_preview.tscn")

func _show_earlier_islands() -> void:
	running=false
	mode="earlier_islands"
	var card := _card(800)
	card.add_child(_label("Earlier islands.",34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_042C89C38B20,710))
	var list := _scroll_list(card)
	list.get_parent().custom_minimum_size.y = 340
	for index in range(levels.size()):
		var level: Dictionary=levels[index]
		var locked: bool = index>=3 and not _full_journey_access()
		var complete: bool = saves.data.completed.has(level.id)
		var text := "%02d  %s%s%s" % [index+1,level.title,"  ·  Full Journey" if locked else "","  ✓" if complete else ""]
		var button := _button(text,func(): _start_practice(index),false)
		button.custom_minimum_size.y=65
		button.mouse_filter=Control.MOUSE_FILTER_PASS
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size",18)
		if index>=3:
			var actions := VBoxContainer.new()
			actions.add_child(button)
			list.add_child(PaidThumbnails.row("legacy-"+str(level.id),actions,false))
		else:
			list.add_child(button)
	card.add_child(_button("Back to chapters",_show_journey,false))

func _open_relay_preview() -> void:
	_open_chapter_preview("res://relay_preview.tscn")

func _open_lighthouse_preview() -> void:
	await _open_premium_chapter("res://lighthouse_preview.tscn")

func _open_cooperative_preview(key: String) -> void:
	var scene := ChapterRegistry.solo_scene(key)
	if not ChapterRegistry.is_cooperative(key) or scene.is_empty(): return
	if ChapterRegistry.descriptor(key).premium:
		await _open_premium_chapter(scene)
	else:
		_open_chapter_preview(scene)

func _open_premium_chapter(scene: String) -> void:
	if _tester_checks_enabled():
		var view := store_view_generation
		var lifecycle := lifecycle_generation
		var context := _tester_context()
		await _load_cached_tester()
		if application_backgrounded or view != store_view_generation or lifecycle != lifecycle_generation or context != _tester_context(): return
	if identity_restart_required or identity_loading or identity_busy:
		_toast(PlayerCopy.MAIN_FCB8424B7F88)
		return
	if _tester_active():
		_open_chapter_preview(scene)
		return
	if not purchases.has_entitlement():
		_show_paywall()
		return
	if not _store_identity_ready():
		# An offline SDK setup can fail after cached customer information arrives.
		# Re-enter the retryable store flow instead of waiting for a callback that
		# has already failed. This does not grant access from the cached label.
		_show_paywall()
		return
	_open_chapter_preview(scene)

func _open_chapter_preview(scene: String) -> void:
	if submission_in_flight or api.busy or foreground_refresh_running or identity_loading or identity_busy or (relay_session != null and relay_session.busy()):
		_toast(PlayerCopy.MAIN_A776CD47C8D9)
		return
	if not _campaign_depart_for_ordinary(): return
	if is_instance_valid(friend_presence): friend_presence.monitor_room("", "")
	if get_tree().change_scene_to_file(scene) != OK:
		_toast(PlayerCopy.MAIN_EB8856600899)

func _start_practice(index: int) -> void:
	if index >= 3 and _tester_checks_enabled():
		var view := store_view_generation
		var lifecycle := lifecycle_generation
		var context := _tester_context()
		await _load_cached_tester()
		if application_backgrounded or view != store_view_generation or lifecycle != lifecycle_generation or context != _tester_context(): return
	if submission_in_flight:
		_toast(PlayerCopy.MAIN_996946E90346)
		return
	if index<0 or index>=levels.size():
		return
	if index>=3 and not _full_journey_access():
		_show_paywall()
		return
	if not _campaign_depart_for_ordinary(): return
	room_play=false
	collection_preview=false
	level_index=index
	current_level=levels[index]
	attempt=saves.attempt(current_level.id)
	role="b" if not attempt.get("a",{}).is_empty() else "a"
	if not attempt.get("b",{}).is_empty():
		mode="completed_attempt"
		var card := _card()
		card.add_child(_label(PlayerCopy.MAIN_0984B81F14AB,34,CREAM,true))
		card.add_child(_paragraph(PlayerCopy.MAIN_CCB173FD54CF))
		card.add_child(_action_button("replay",func(): _preview(attempt.b,true)))
		card.add_child(_button("Start a fresh attempt",_confirm_restart_attempt,false))
		card.add_child(_action_button("back",_show_journey))
		return
	_prepare_turn()

func _prepare_turn() -> void:
	if submission_in_flight:
		_toast(PlayerCopy.MAIN_996946E90346)
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
	var ruleset := TurnState.simulation_version(attempt, role, active_room if room_play else {}, false)
	if not sim.reset(current_level,attempt.get("a",{}) if role=="b" else {},role,ruleset):
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
	card.add_child(_label("Leave a moment." if role=="a" else PlayerCopy.MAIN_408402D8E83C,34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.from_canonical(str(current_level.get("hint_"+role,"")))))
	card.add_child(_paragraph(PlayerCopy.MAIN_0141427332B8))
	var draft: Dictionary=attempt.get("draft",{})
	if draft.get("role","")==role and int(draft.get("duration_ticks",0))>0:
		card.add_child(_action_button("resume",func(): _resume_draft(draft)))
	card.add_child(_action_button("record",_begin_turn))
	card.add_child(_action_button("back",_show_rooms if room_play else _show_journey))

func _begin_turn() -> void:
	if application_backgrounded or submission_in_flight:
		return
	_close_overlay()
	mode="play"
	running=true
	action_pressed=false
	stick.release()
	_update_hud(sim.snapshot())

func _resume_draft(draft: Dictionary) -> void:
	var check: Dictionary=TurnState.review(current_level,draft,attempt,_room_simulation_version())
	if not check.valid or draft.get("role","")!=role:
		_toast(PlayerCopy.MAIN_EA192FA7B9B0+str(check.get("error","")))
		return
	sim.catch_assistance=bool(draft.get("catch_assistance",true))
	if not sim.reset(current_level,attempt.a if role=="b" else {},role,int(draft.simulation_version)):
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
	timer_label.text="%.1f" % (maxi(0,int(state.duration_ticks)-int(state.tick))/30.0)
	progress.max_value=int(state.duration_ticks)
	progress.value=state.tick
	objective_panel.show_objective(ObjectivePanel.legacy_progress(state,30.0))
	hint_label.text=PlayerCopy.from_canonical(str(state.message))
	var interactive := mode=="play" and running and not application_backgrounded
	finish_button.disabled=not interactive or not bool(state.get("can_commit",false))
	var action: Dictionary=state.get("context_action",{})
	interact_button.text=PlayerCopy.from_canonical(str(action.get("label","Interact")))
	interact_button.disabled=not interactive or not bool(action.get("enabled",false))
	interact_button.tooltip_text=PlayerCopy.from_canonical(str(action.get("reason","")))

func _request_context_action() -> void:
	if mode=="play" and running and not application_backgrounded and sim.context_action().get("enabled",false):
		action_pressed=true

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(redo_screen):
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			redo_screen.close()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(relay_child) or is_instance_valid(shared_replay_child):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_SPACE and mode=="play" and running:
			_request_context_action()
		if event.physical_keycode==KEY_ESCAPE:
			if mode == "story_lobby": _story_back()
			elif mode == "story_access": _draw_story_lobby()
			elif mode == "paywall" and not _story_store_return.is_empty(): _leave_store()
			elif mode in ["confirm_retry", "confirm_restart"]:
				if _retry_cancel.is_valid(): _retry_cancel.call()
			elif mode == "story_replay_chapters": _return_story_replay_lobby()
			elif mode == "shared_memories" and not _story_replay_return.is_empty(): _back_to_story_replay_chapters()
			else: _pause() if running or mode=="completion" else _show_home()

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
	var check: Dictionary=TurnState.review(current_level,review_recording,attempt,_room_simulation_version())
	var valid: bool=check.valid and check.can_commit
	var complete: bool = valid and bool(review_recording.get("completed",false))
	mode="collection" if collection_preview else "review"
	var card := _card()
	card.add_child(_label(PlayerCopy.MAIN_CBFD9EB78DBC if complete else (PlayerCopy.MAIN_6F96DCC47A05 if valid else "Another little try?"),32,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_32A4E00F108C if complete else (PlayerCopy.MAIN_92F966458583 if valid else PlayerCopy.MAIN_A01274C34177)))
	if not review_recording.is_empty():
		card.add_child(_action_button("replay" if collection_preview else "preview",func(): _preview(review_recording,collection_preview)))
	var already_saved := collection_preview
	if valid and not already_saved:
		card.add_child(_action_button("save",_commit_turn))
	if not already_saved:
		card.add_child(_action_button("retry",_retry_review))
	card.add_child(_action_button("back",_show_rooms if room_play else _show_journey))

func _retry_review() -> void:
	if mode != "review" or application_backgrounded or submission_in_flight: return
	var checked: Dictionary = TurnState.review(current_level,review_recording,attempt,_room_simulation_version())
	if not checked.valid or not checked.can_commit or not bool(review_recording.get("completed",false)):
		_prepare_turn()
		return
	var recording := review_recording.duplicate(true)
	var saved_attempt := attempt.duplicate(true)
	var room := active_room.duplicate(true)
	var was_room_play := room_play
	var recorded_role := role
	var level_id := str(current_level.id)
	var identity := _relay_identity()
	mode = "confirm_retry"
	var card := _card()
	card.add_child(_label(PlayerCopy.LIGHTHOUSE_PREVIEW_E1352BA6D9BA,32,CREAM,true))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_retry" and not application_backgrounded and not submission_in_flight and room_play == was_room_play and role == recorded_role and str(current_level.id) == level_id and review_recording == recording and attempt == saved_attempt and active_room == room and _relay_identity() == identity
	card.add_child(_action_button("retry",func():
		if current.call(): _prepare_turn()))
	_retry_cancel = func():
		if current.call(): _show_review()
	card.add_child(_action_button("cancel",_retry_cancel))

func _preview(recording: Dictionary, collection: bool=false) -> void:
	var check: Dictionary=TurnState.review(current_level,recording,attempt,_room_simulation_version())
	if not check.valid:
		_toast(PlayerCopy.MAIN_CD2F00E32FC5+str(check.get("error","")))
		return
	review_recording=recording.duplicate(true)
	role=str(recording.role)
	world.load_level(current_level)
	world.home_view=false
	sim.catch_assistance=bool(recording.get("catch_assistance",true))
	if not sim.reset(current_level,attempt.get("a",{}) if role=="b" else {},role,int(recording.simulation_version)):
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
	var check: Dictionary=TurnState.review(current_level,review_recording,attempt,_room_simulation_version())
	if not check.valid or not check.can_commit:
		_toast(PlayerCopy.MAIN_C4E0C9A50B65+str(check.get("error","")))
		return
	if room_play:
		await _commit_online()
		return
	var committed := attempt.duplicate(true)
	committed[role]=review_recording.duplicate(true)
	committed["draft"]={}
	if not saves.save_attempt(current_level.id,committed,role=="b"):
		_toast(PlayerCopy.MAIN_1A6455ED3E4B)
		return
	if role == "b": HomeKeepsakes.record_legacy_solo(current_level.id)
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
	card.add_child(_label(PlayerCopy.MAIN_754724C78F04,34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_A74DFEBB0414))
	if room_play:
		_add_room_reaction_summary(card, active_room)
	var row := HBoxContainer.new()
	for reaction in ["Beautiful!","We did it!","Again soon"]:
		row.add_child(_button(reaction,func(): _react(reaction),false))
	card.add_child(row)
	if level_index<7:
		card.add_child(_button("Next island",_next_island))
	card.add_child(_action_button("replay",func(): _preview(attempt.b,true)))
	card.add_child(_action_button("back",_show_home))

func _react(reaction: String) -> void:
	var code := RoomReactions.code_for_label(reaction)
	if code.is_empty():
		return
	if room_play:
		if not saves.data.get("pending_turn",{}).is_empty():
			_toast(PlayerCopy.MAIN_D808B160901A)
			return
		if api.busy:
			_toast(PlayerCopy.MAIN_D5C047A7C07E)
			return
		var identity := _relay_identity()
		if not identity.ready or active_room.get("active_role") != "complete":
			_toast(PlayerCopy.MAIN_5DD61CC297CD)
			return
		var context := {"identity": identity.duplicate(true), "room": active_room.duplicate(true), "mode": mode, "generation": lifecycle_generation}
		var path := "/v1/rooms/" + str(active_room.room_id)
		var body := {"base_revision": active_room.revision, "idempotency_key": RoomsApi.new_key(), "reaction": code}
		var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST, path + "/reactions", body)
		if not _reaction_response_current(context):
			return
		# Two friends may react from the same revision. Refresh once and retry only
		# while this is still the exact same completed island/attempt.
		if not response.ok and response.get("code") == "stale_revision":
			var latest: Dictionary = await api.request_json(HTTPClient.METHOD_GET, path)
			if not _reaction_response_current(context):
				return
			if not latest.ok or not latest.get("data") is Dictionary or not RoomReactions.same_completed_room(context.room, latest.data):
				_toast(PlayerCopy.MAIN_78DF8178BC2B)
				return
			body.base_revision = latest.data.revision
			body.idempotency_key = RoomsApi.new_key()
			response = await api.request_json(HTTPClient.METHOD_POST, path + "/reactions", body)
			if not _reaction_response_current(context):
				return
		if response.ok:
			var incoming: Variant = response.get("data")
			if not incoming is Dictionary or not RoomReactions.same_completed_room(context.room, incoming) or not incoming.get("reactions") is Dictionary or incoming.reactions.get(identity.player_id) != code:
				_toast(PlayerCopy.MAIN_B94C73E90E5B)
				return
			_accept_room(response)
			_toast("Reaction sent.")
		else:
			_toast(str(response.get("error", PlayerCopy.MAIN_B94C73E90E5B)))
		return
	saves.data["last_reaction"]=reaction
	saves.flush()
	_toast(reaction)

func _reaction_response_current(context: Dictionary) -> bool:
	return is_inside_tree() and mode == context.mode and lifecycle_generation == context.generation \
		and _relay_identity() == context.identity and RoomReactions.same_completed_room(context.room, active_room)

func _add_room_reaction_summary(card: VBoxContainer, room: Dictionary) -> void:
	for row: Dictionary in RoomReactions.rows(room, str(api.player_id)):
		var label := _paragraph(row.text)
		label.name = "YourRoomReaction" if row.own else "FriendRoomReaction"
		card.add_child(label)

func _notice_room_reactions(previous: Dictionary, incoming: Dictionary) -> void:
	var notice := RoomReactions.new_partner_notice(previous, incoming, str(api.player_id), room_reaction_notices)
	if not notice.is_empty():
		_toast(notice)

func _next_island() -> void:
	if room_play:
		await _advance_room()
	elif level_index+1>=3 and not _full_journey_access():
		_show_paywall()
	else:
		_start_practice(mini(level_index+1,7))

func _confirm_restart_attempt() -> void:
	if room_play or application_backgrounded or submission_in_flight: return
	var saved_attempt := attempt.duplicate(true)
	var index := level_index
	mode = "confirm_restart"
	var card := _card()
	card.add_child(_label(PlayerCopy.LIGHTHOUSE_PREVIEW_E1352BA6D9BA,32,CREAM,true))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_restart" and not application_backgrounded and not submission_in_flight and not room_play and level_index == index and attempt == saved_attempt and saves.attempt(str(current_level.id)) == saved_attempt
	card.add_child(_action_button("retry",func():
		if current.call(): _restart_attempt()))
	_retry_cancel = func():
		if current.call(): _start_practice(index)
	card.add_child(_action_button("cancel",_retry_cancel))

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
	soundscape.stop_reunion()
	var card := _card()
	card.add_child(_label("There’s no hurry.",36,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_1A19AF19EDB1 if previous_mode=="preview" else (PlayerCopy.MAIN_9E4FF2796D8F if draft_saved else PlayerCopy.MAIN_359B02B14B2E)))
	card.add_child(_action_button("resume",func(): mode=previous_mode; _close_overlay(); running=true))
	if previous_mode=="play":
		card.add_child(_action_button("retry",_prepare_turn))
	card.add_child(_action_button("back",_show_home))

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
		list.add_child(_paragraph(PlayerCopy.MAIN_43ADB38D37BC,580))
	card.add_child(_button("Back",_show_home,false))

func _show_shared_replays() -> void:
	_story_replay_return = {}
	running=false
	room_play=false
	mode="shared_replays"
	if not _relay_identity().ready:
		var held := _card(700)
		held.add_child(_label("Your shared replays",34,CREAM,true))
		held.add_child(_paragraph(PlayerCopy.MAIN_1E12325B0B49,600))
		held.add_child(_button("Account & recovery",_show_account))
		held.add_child(_button("Back",_show_home,false))
		return
	if shared_replays==null: shared_replays=SharedReplays.new(api,_relay_identity)
	shared_replays.configure_context_factory(_campaign_media_factory())
	shared_replays.load_saved(saves.data.get("room",{}))
	home_keepsakes.reconcile_friend(shared_replays)
	_draw_shared_replay_rooms()

func _draw_shared_replay_rooms(message: String="") -> void:
	mode="shared_replays"
	var card := _card(740)
	card.add_child(_label("Your shared replays",34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_529CFAE68DF1,630))
	var list := _scroll_list(card)
	var rooms: Array=shared_replays.rooms()
	for i in range(rooms.size()):
		var room: Dictionary=rooms[i]
		var key: String=SharedReplays._room_key(room)
		list.add_child(_list_button(str(room.title)+" · Shared room "+str(i+1),func(): _show_shared_replay_room(key),false))
	if rooms.is_empty(): list.add_child(_paragraph(PlayerCopy.MAIN_87534286A315,620))
	if not message.is_empty(): card.add_child(_paragraph(message,630))
	elif not shared_replays.last_error.is_empty(): card.add_child(_paragraph(shared_replays.last_error,630))
	var refresh := _button("Refresh shared rooms",_refresh_shared_replay_rooms,false)
	refresh.disabled=shared_replays.busy() or api.busy
	card.add_child(refresh)
	card.add_child(_button("Back",_show_home,false))

func _refresh_shared_replay_rooms() -> void:
	if shared_replays==null or shared_replays.busy() or api.busy or not _relay_identity().ready: return
	_draw_shared_replay_rooms(PlayerCopy.MAIN_2CEDB8F94036)
	var view := store_view_generation
	var owner := _relay_identity()
	var okay: bool=await shared_replays.refresh_rooms()
	if mode!="shared_replays" or view!=store_view_generation or owner!=_relay_identity(): return
	_draw_shared_replay_rooms(PlayerCopy.MAIN_A931AA250D92 if okay else shared_replays.last_error)

func _show_shared_replay_room(key: String) -> void:
	if shared_replays==null or not _relay_identity().ready or not _story_replay_memory_current(): return
	shared_replay_room=key
	_draw_shared_replay_memories(shared_replays.memories(key))

func _draw_shared_replay_memories(rows: Array, message: String="") -> void:
	mode="shared_memories"
	var card := _card(760)
	card.add_child(_label(PlayerCopy.MAIN_C8F7A8FDC485,32,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_4CACA12BCD58,650))
	var list := _scroll_list(card)
	for value: Dictionary in rows:
		var row: Dictionary=value.duplicate(true)
		var text: String=str(row.title)+(" · On this device" if row.get("cached",false) else " · Download replay")
		list.add_child(_list_button(text,func(): _open_shared_memory(shared_replay_room,row),false))
	if rows.is_empty(): list.add_child(_paragraph(PlayerCopy.MAIN_DE8FFD26387B,640))
	if not message.is_empty(): card.add_child(_paragraph(message,650))
	elif not shared_replays.last_error.is_empty(): card.add_child(_paragraph(shared_replays.last_error,650))
	var refresh := _button("Refresh memories",_refresh_shared_replay_memories,false)
	refresh.disabled=shared_replays.busy() or api.busy
	card.add_child(refresh)
	card.add_child(_button("Back",_back_to_story_replay_chapters,false) if not _story_replay_return.is_empty() else _button("Back to shared rooms",_show_shared_replays,false))

func _refresh_shared_replay_memories() -> void:
	if shared_replays==null or shared_replays.busy() or api.busy or not _relay_identity().ready or not _story_replay_memory_current(): return
	var key := shared_replay_room
	_draw_shared_replay_memories(shared_replays.memories(key),"Checking completed stages…")
	var view := store_view_generation
	var owner := _relay_identity()
	var rows: Array=await shared_replays.refresh_memories(key)
	if mode!="shared_memories" or view!=store_view_generation or owner!=_relay_identity() or key!=shared_replay_room or not _story_replay_memory_current(): return
	_draw_shared_replay_memories(rows)

func _open_shared_memory(key: String, row: Dictionary) -> void:
	if shared_replays==null or shared_replays.busy() or not _relay_identity().ready or is_instance_valid(shared_replay_child) or not _story_replay_memory_current(): return
	if api.busy and not row.get("cached",false): _toast(PlayerCopy.MAIN_6BB9D408ABAB); return
	var view := store_view_generation
	var owner := _relay_identity()
	var entry: Dictionary=await shared_replays.open_memory(key,str(row.id),row)
	if mode!="shared_memories" or view!=store_view_generation or owner!=_relay_identity() or key!=shared_replay_room or not _story_replay_memory_current(): return
	if entry.is_empty(): _toast(shared_replays.last_error); return
	lifecycle_generation+=1
	foreground_refresh_queued=false
	foreground_response={}
	mode="shared_replay"
	running=false
	world.visible=false
	ui.visible=false
	soundscape.set_backgrounded(true)
	shared_replay_child=SharedReplayView.new()
	shared_replay_child.entry=entry
	shared_replay_child.settings=saves.data.settings.duplicate(true)
	shared_replay_child.api=api
	shared_replay_child.identity=_relay_identity
	shared_replay_child.context_factory=_campaign_media_factory()
	shared_replay_child.closed.connect(_leave_shared_replay)
	add_child(shared_replay_child)

func _leave_shared_replay() -> void:
	var blocked: bool = is_instance_valid(shared_replay_child) and shared_replay_child.blocked_exit
	if is_instance_valid(shared_replay_child):
		remove_child(shared_replay_child)
		shared_replay_child.queue_free()
	shared_replay_child=null
	world.visible=true
	ui.visible=true
	soundscape.set_backgrounded(application_backgrounded)
	lifecycle_generation+=1
	if not _story_replay_return.is_empty() and (blocked or not _story_replay_memory_current()): _return_story_replay_lobby()
	elif blocked: _show_shared_replays()
	elif _relay_identity().ready: _show_shared_replay_room(shared_replay_room)
	else: _show_shared_replays()

func _open_photo_transfer() -> void:
	if not _relay_identity().ready:
		_toast(PlayerCopy.MAIN_2BCA37F28163)
		return
	if api.busy or submission_in_flight or foreground_refresh_running or (relay_session!=null and relay_session.busy()):
		_toast(PlayerCopy.MAIN_27C2299C47EE)
		return
	if is_instance_valid(photo_transfer_child): return
	var screen: Script=load("res://presentation/photo_transfer_screen.gd")
	if screen==null: _toast(PlayerCopy.MAIN_E595640A21FC); return
	lifecycle_generation+=1
	foreground_refresh_queued=false
	foreground_response={}
	mode="photo_transfer"
	running=false
	world.visible=false
	ui.visible=false
	soundscape.set_backgrounded(true)
	photo_transfer_child=screen.new(api,_relay_identity,_leave_photo_transfer)
	add_child(photo_transfer_child)

func _leave_photo_transfer() -> void:
	if is_instance_valid(photo_transfer_child):
		remove_child(photo_transfer_child)
		photo_transfer_child.queue_free()
	photo_transfer_child=null
	world.visible=true
	ui.visible=true
	soundscape.set_backgrounded(application_backgrounded)
	lifecycle_generation+=1
	_show_account()

func _show_settings() -> void:
	running=false
	mode="settings"
	var card := _card()
	card.add_theme_constant_override("separation", 10)
	card.add_child(_label(PlayerCopy.MAIN_0FEE4C6E23F4,34,CREAM,true))
	for entry in [["assistance","Forgiving catches"],["reduced_motion","Reduce motion"],["left_handed",PlayerCopy.MAIN_A1E007823FF0],["sound","Sound"],["haptics","Gentle haptics"],["photo_prompts",PlayerCopy.MAIN_289D745F1246],["share_online_status","Share online status"]]:
		var toggle := CheckButton.new()
		toggle.text=entry[1]
		toggle.button_pressed=bool(saves.data.settings.get(entry[0],true))
		toggle.toggled.connect(func(value: bool):
			var next: Dictionary = saves.data.settings.duplicate(true)
			next[entry[0]] = value
			if not saves.update_values({"settings": next}):
				toggle.set_pressed_no_signal(bool(saves.data.settings.get(entry[0], true)))
				_toast(PlayerCopy.MAIN_34B82590B663)
				return
			_apply_settings())
		card.add_child(toggle)
	for group: Array in [[["Account & recovery",_show_account],["Notifications",_show_notification_settings],["Tester code",_show_tester_access]],[["Community & privacy",_open_safety],["Licenses",_show_licenses],["Done",_story_settings_done]]]:
		var links := HBoxContainer.new()
		links.add_theme_constant_override("separation",10)
		card.add_child(links)
		for entry: Array in group:
			var link := _button(entry[0],entry[1],false)
			link.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			links.add_child(link)

func _save_photo_prompt_preference(enabled: bool) -> bool:
	var next: Dictionary = saves.data.settings.duplicate(true)
	next.photo_prompts = enabled
	return saves.update_values({"settings": next})

func _show_licenses() -> void:
	running=false
	mode="licenses"
	var card := _card(680)
	card.add_child(_label("Made with care.",34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_0A022EF54291,600))
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
	if is_instance_valid(friend_presence): friend_presence.set_enabled(bool(saves.data.settings.get("share_online_status", true)))
	soundscape.configure(saves.data.settings)
	world.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
	var left := bool(saves.data.settings.get("left_handed",false))
	stick.anchor_left=1.0 if left else 0.0
	stick.anchor_right=stick.anchor_left
	# Once parented, position is absolute in the HUD. Use anchor-relative
	# offsets so right-aligned controls remain inside the viewport on resize.
	stick.offset_left=-208 if left else 12
	stick.offset_right=stick.offset_left+Joystick.HIT_SIZE
	for button in [interact_button,finish_button]:
		var width := 210 if button==finish_button else 195
		button.anchor_left=0.0 if left else 1.0
		button.anchor_right=button.anchor_left
		button.offset_left=36 if left else -37-width
		button.offset_right=button.offset_left+width

func _show_paywall(manual_store: bool = false, story_return: Dictionary = {}) -> void:
	running=false
	mode="paywall"
	_story_store_return = story_return.duplicate(true)
	tester_store_manual = manual_store
	if _tester_checks_enabled():
		var loading := _card(680)
		loading.add_child(_label("Checking saved access…",30,CREAM,true))
		_add_store_back(loading)
		var view := store_view_generation
		await _load_cached_tester()
		if mode != "paywall" or view != store_view_generation: return
	if _tester_active() and not manual_store:
		_show_tester_active()
		return
	var card := _full_journey_card()
	if not _play_store_enabled():
		card.add_child(_button("Get it on Google Play",_open_google_play))
		card.add_child(_button("Tester code",_show_tester_access,false))
		_add_store_back(card)
		return
	var key := str(config.get("revenuecat_public_key",""))
	if key.is_empty() or not purchases.is_available():
		card.add_child(_paragraph(PlayerCopy.MAIN_FC1F8BAE026C,600))
	else:
		card.add_child(_paragraph(PlayerCopy.MAIN_DD823B20A782,600))
		_load_store()
	if not key.is_empty() and purchases.is_available():
		card.add_child(_button("Retry store",func(): _load_store(true),false))
		card.add_child(_button("Restore purchases",_restore_store,false))
	_add_store_back(card)

func _add_store_back(card: VBoxContainer, primary: bool = false) -> void:
	var view := store_view_generation
	card.add_child(_button("Return to Story" if not _story_store_return.is_empty() else "Back to chapters",func():
		if mode == "paywall" and view == store_view_generation: _leave_store(),primary))

func _leave_store() -> void:
	if mode != "paywall": return
	if _story_store_return.is_empty():
		_show_journey()
		return
	var current := _story_store_current()
	_story_store_return = {}
	if current: _draw_story_lobby()
	else: _show_home()

func _play_store_enabled() -> bool:
	return Purchases.store_enabled(config)

func _open_google_play() -> void:
	OS.shell_open("https://play.google.com/store/apps/details?id=com.aamirazeez.afteryou")

func _full_journey_card() -> VBoxContainer:
	var card := _card(800)
	card.add_child(_label("Full Journey",32,CREAM,true))
	card.add_child(PaidThumbnails.gallery(248))
	card.add_child(_paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,740))
	return card

func _show_store_offer() -> void:
	if not _play_store_enabled():
		_show_paywall(tester_store_manual,_story_store_return)
		return
	if _tester_active() and not tester_store_manual:
		_show_tester_active()
		return
	if purchases.has_entitlement():
		_show_full_journey_unlocked()
		return
	var card := _full_journey_card()
	card.add_child(_button("Unlock Full Journey · "+str(purchase_package.price),_buy_full_journey))
	card.add_child(_button("Restore purchases",_restore_store,false))
	_add_store_back(card)

func _show_full_journey_unlocked() -> void:
	if not _play_store_enabled():
		_show_paywall(tester_store_manual,_story_store_return)
		return
	var card := _card(680)
	card.add_child(_label("Full Journey unlocked.",34,CREAM,true))
	if _story_store_return.is_empty(): card.add_child(_button("Enter the Lighthouse",_open_lighthouse_preview))
	else: _add_store_back(card,true)
	card.add_child(_button("Restore purchases",_restore_store,false))
	if _story_store_return.is_empty(): _add_store_back(card)

func _buy_full_journey() -> void:
	if not _play_store_enabled(): return
	if store_action_pending or mode!="paywall" or purchase_package.is_empty(): return
	if not _store_identity_ready():
		_toast(PlayerCopy.MAIN_5FE98B59E6BA)
		return
	if purchases.has_entitlement():
		_show_full_journey_unlocked()
		return
	store_action_pending=true
	var card := _full_journey_card()
	card.add_child(_paragraph(PlayerCopy.MAIN_8A2FF5596F1C,600))
	store_action_request=purchases.purchase(str(purchase_package.offering_id),str(purchase_package.id))

func _store_identity_ready() -> bool:
	return store_configured and not store_owner.is_empty() and api.player_id==store_owner and not api.device_token.is_empty() and not identity_loading and not identity_busy and not identity_restart_required and pending_recovery.is_empty() and deleted_identity_owner.is_empty() and not saves.data.has(DeletedPhotos.MARKER_KEY)

func _load_store(force_refresh: bool = false) -> void:
	if not _play_store_enabled(): return
	if store_action_pending: return
	if not await _ensure_identity():
		return
	if mode!="paywall": return
	if store_configured:
		if _store_identity_ready():
			if force_refresh: purchases.refresh_customer_info_fresh()
			else: purchases.refresh_customer_info()
	else:
		_configure_purchases(tester_store_manual)

func _restore_store() -> void:
	if not _play_store_enabled(): return
	if store_action_pending: return
	store_action_pending=true
	var view := store_view_generation
	store_restore_view=view
	if not await _ensure_identity():
		store_action_pending=false
		return
	if view!=store_view_generation:
		store_action_pending=false
		return
	if store_configured:
		if not _store_identity_ready():
			store_action_pending=false
			return
		store_action_request=purchases.restore()
	else:
		restore_requested=true
		_configure_purchases(true)

func _purchase_completed(id: String, operation: String, payload: Dictionary) -> void:
	if not _play_store_enabled(): return
	if operation=="configure":
		if id!=store_configure_request or id.is_empty(): return
		store_configure_request=""
		if api.player_id!=store_owner or identity_restart_required: return
		store_configured=true
		if restore_requested:
			restore_requested=false
			if store_restore_view!=store_view_generation or not _store_identity_ready():
				store_action_pending=false
				return
			store_action_request=purchases.restore()
		elif mode=="paywall":
			if _store_identity_ready() and purchases.has_entitlement(): _show_full_journey_unlocked()
			else: purchases.fetch_offerings()
	elif operation=="get_offerings":
		if mode!="paywall" or store_action_pending or not _store_identity_ready():
			return
		if purchases.has_entitlement():
			_show_full_journey_unlocked()
			return
		purchase_package=Purchases.select_lifetime_offer(payload)
		if purchase_package.is_empty():
			_toast(PlayerCopy.MAIN_A986D201176A)
			return
		_show_store_offer()
	elif operation=="get_customer_info":
		if mode=="paywall" and not store_action_pending and _store_identity_ready():
			if purchases.has_entitlement(): _show_full_journey_unlocked()
			else: purchases.fetch_offerings()
	elif operation in ["purchase_package","restore_purchases"]:
		if id!=store_action_request or id.is_empty(): return
		store_action_request=""
		store_action_pending=false
		if not _store_identity_ready(): return
		_toast("Full Journey unlocked." if purchases.has_entitlement() else PlayerCopy.MAIN_FF5EB2A130CC)
		if mode=="paywall":
			if purchases.has_entitlement(): _show_full_journey_unlocked()
			elif not purchase_package.is_empty(): _show_store_offer()
			else: _show_paywall(tester_store_manual,_story_store_return)

func _purchase_failed(id: String,operation: String,_code: String,message: String,cancelled: bool) -> void:
	if operation=="configure":
		if id!=store_configure_request or id.is_empty(): return
		store_configure_request=""
		if not store_action_request.is_empty(): return
		store_action_pending=false
		restore_requested=false
	elif operation in ["purchase_package","restore_purchases"]:
		if id!=store_action_request or id.is_empty(): return
		store_action_request=""
		store_action_pending=false
	if operation in ["purchase_package","restore_purchases","configure"]:
		if mode=="paywall" and not purchase_package.is_empty() and _store_identity_ready(): _show_store_offer()
	_toast(PlayerCopy.MAIN_B621C76A2638 if cancelled else message)

func _customer_info_changed(_payload: Dictionary) -> void:
	# The store may finish loading after the grid opens. Refresh labels here;
	# button callbacks still check the current entitlement when pressed.
	if mode=="journey":
		_show_journey()
	elif mode=="earlier_islands":
		_show_earlier_islands()

func _load_saved_identity() -> void:
	if identity_loading or identity_busy or identity_restart_required:
		return
	_invalidate_relay_identity(false)
	identity_read_state=IdentityReadState.LOADING
	identity_loading=true
	# A saved rotation takes precedence over possibly revoked device credentials.
	recovery_read_request=secrets.get_secret("recovery_pending")

func _retry_saved_identity() -> void:
	_load_saved_identity()
	mode="account_loading"
	var card := _card()
	card.add_child(_label(PlayerCopy.MAIN_199D5695599E,30,CREAM,true))
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
				_toast(PlayerCopy.MAIN_B3B03D36065F)
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
				if saves.data.has(DeletedPhotos.MARKER_KEY):
					identity_restart_required=true
					deleted_identity_owner=DeletedPhotos.marker_owner(saves.data[DeletedPhotos.MARKER_KEY])
				_configure_purchases()
		if saves.data.has(DeletedPhotos.MARKER_KEY):
			identity_restart_required=true
			deleted_identity_owner=DeletedPhotos.marker_owner(saves.data[DeletedPhotos.MARKER_KEY])
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

func _configure_purchases(manual_store: bool = false) -> void:
	if purchases is Purchases and identity_read_state == IdentityReadState.LOADED and not identity_restart_required and not identity_loading and not identity_busy and pending_recovery.is_empty() and not saves.data.has(DeletedPhotos.MARKER_KEY):
		purchases.bind_session(api.player_id, api.device_token)
	if _tester_checks_enabled():
		var context := _tester_context()
		await _load_cached_tester()
		if context.is_empty() or context != _tester_context() or tester_loading: return
		if _tester_active() and not manual_store: return
	if not _play_store_enabled() or identity_restart_required or not store_configure_request.is_empty():
		return
	var key := str(config.get("revenuecat_public_key",""))
	if not key.is_empty() and not api.player_id.is_empty() and not store_configured:
		store_owner=api.player_id
		store_configure_request=purchases.configure_store(key,api.player_id,str(config.get("purchase_mode","")))

func _show_rooms() -> void:
	running=false
	mode="rooms"
	var frame := _card(700)
	frame.add_child(_label(PlayerCopy.MAIN_3A4A78824AC3,34,CREAM,true))
	var card := _scroll_list(frame)
	card.get_parent().custom_minimum_size.y=clampf(overlay.size.y-220,160,420)
	if not api.configured():
		card.add_child(_paragraph(PlayerCopy.MAIN_C372E9DBD93A))
		card.add_child(_list_button("Practice on your own",_show_journey))
	else:
		card.add_child(_paragraph(PlayerCopy.MAIN_F87B75B52317))
		var room_types := HBoxContainer.new()
		card.add_child(room_types)
		room_types.add_child(_list_button("Choose an online chapter",func(): _show_relay_rooms(ChapterRegistry.FIRST_STEPS)))
		room_types.add_child(_list_button("Earlier islands · online",_create_room,false))
		var field := LineEdit.new()
		field.placeholder_text="Invitation code"
		field.custom_minimum_size.y=52
		card.add_child(field)
		card.add_child(_paragraph(PlayerCopy.MAIN_E0448D410D86))
		var join_types := HBoxContainer.new()
		join_types.add_theme_constant_override("separation",12)
		card.add_child(join_types)
		join_types.add_child(_list_button("Join a chapter",func(): _join_chapter_room(field.text),false))
		join_types.add_child(_list_button("Join an earlier island",func(): _join_room(field.text),false))
		if not saves.data.get("room",{}).is_empty():
			card.add_child(_list_button("Return to your room",_refresh_room,false))
		var saved_places := HBoxContainer.new()
		saved_places.add_theme_constant_override("separation",12)
		card.add_child(saved_places)
		for entry: Array in [["Recent online rooms",_show_saved_rooms],["Friends",_show_friends]]:
			var button := _list_button(entry[0],entry[1],false)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			saved_places.add_child(button)
		if not saves.data.get("pending_turn",{}).is_empty():
			card.add_child(_list_button("Check saved submission",_reconcile_pending,false))
	frame.add_child(_button("Back",_show_home,false))

func _show_friends() -> void:
	var from_home := mode == "home"
	var view := store_view_generation
	if not _relay_available() or not await _ensure_identity(): return
	if view != store_view_generation or application_backgrounded or is_instance_valid(friends_screen): return
	_friends_return_home = from_home
	if friends_client == null: friends_client = FriendsClient.new(api,_relay_identity)
	var shareable := {}
	if friend_share_target.get("api_version") == 2 and relay_session != null and relay_session.coordinator != null:
		var room: Dictionary = relay_session.coordinator.snapshot()
		if not relay_session.coordinator.campaign_scoped() and room.get("host_id") == api.player_id and room.get("room_id") == friend_share_target.get("room_id"):
			shareable = friend_share_target.duplicate(true)
	elif friend_share_target.get("api_version") == 1 and active_room.get("host_id") == api.player_id and active_room.get("room_id") == friend_share_target.get("room_id"):
		shareable = friend_share_target.duplicate(true)
	running = false
	mode = "friends"
	_sync_presence()
	ui.visible = false
	friends_screen = FriendsScreen.new()
	friends_screen.client = friends_client
	friends_screen.shareable_room = shareable
	friends_screen.closed.connect(_leave_friends)
	friends_screen.join_requested.connect(_join_friend_room)
	add_child(friends_screen)

func _leave_friends() -> void:
	friends_screen = null
	if mode == "friends":
		ui.visible = true
		if _friends_return_home: _show_home()
		else: _show_rooms()

func _join_friend_room(descriptor: Dictionary) -> void:
	if mode != "friends" or application_backgrounded or not _relay_identity().ready: return
	# The screen closes after emitting. Set the destination first so its close
	# callback cannot replace a successful room join with the rooms menu.
	mode = "rooms"
	ui.visible = true
	if descriptor.get("api_version") == 2:
		_join_chapter_room(str(descriptor.get("invite_code","")))
	elif descriptor.get("api_version") == 1:
		_join_room(str(descriptor.get("invite_code","")))

func _relay_identity() -> Dictionary:
	return {"ready": api != null and not identity_loading and not identity_busy and not identity_restart_required and pending_recovery.is_empty() and identity_read_state==IdentityReadState.LOADED and not api.player_id.is_empty() and not api.device_token.is_empty(), "player_id": str(api.player_id) if api != null else "", "epoch": relay_identity_epoch}

func _new_relay_session() -> RefCounted:
	if shared_replays == null: shared_replays = SharedReplays.new(api,_relay_identity)
	var session := RelayOnline.new(api,_relay_identity)
	session.accepted_pair_cache = shared_replays.cache_accepted_receipt
	return session

func _invalidate_relay_identity(clear_notifications: bool = true) -> void:
	# A returning Main re-reads the same credentials before reusing its session.
	# Recovery/deletion clear authority; ordinary identity loading only holds it.
	Purchases.suspend_session(clear_notifications)
	_story_store_return = {}
	_campaign_generation += 1
	_campaign_action_busy = false
	if is_instance_valid(campaign_flow): campaign_flow.invalidate()
	if campaign_owner != null: campaign_owner.invalidate_identity()
	friend_share_target = {}
	legacy_redo_restore_scope = ""
	legacy_redo_restore_ok = true
	var had_redo_screen := is_instance_valid(redo_screen)
	if legacy_redo != null: legacy_redo.invalidate()
	if is_instance_valid(redo_screen):
		redo_screen.invalidate()
		redo_screen = null
		ui.visible = true
	_keepsake_identity.clear()
	if friends_client != null: friends_client.invalidate()
	if is_instance_valid(friends_screen):
		if mode == "friends": mode = "rooms"
		friends_screen.close()
		ui.visible = true
	if is_instance_valid(friend_presence): friend_presence.set_identity({})
	tester_load_generation += 1
	tester_loading = false
	tester_checked_context = ""
	if is_instance_valid(tester_access):
		tester_access.invalidate()
	if purchases is Purchases: purchases.invalidate_review_access()
	if clear_notifications and is_instance_valid(turn_notifications):
		turn_notifications.invalidate_identity()
	lifecycle_generation += 1
	foreground_response = {}
	relay_identity_epoch += 1
	relay_menu_generation += 1
	if relay_session != null:
		relay_session.invalidate_identity()
	if is_instance_valid(relay_child):
		relay_child.identity_invalidated()
	if is_instance_valid(safety_screen):
		safety_screen.client.invalidate()
		safety_screen.queue_free()
		safety_screen = null
		ui.visible = true
	if shared_replays!=null: shared_replays.invalidate_identity()
	if is_instance_valid(shared_replay_child): shared_replay_child.identity_invalidated()
	if is_instance_valid(photo_transfer_child):
		if photo_transfer_child.has_method("identity_invalidated"): photo_transfer_child.identity_invalidated()
		elif photo_transfer_child.has_method("invalidate"): photo_transfer_child.invalidate()
	if had_redo_screen and mode == "redo_requests": _show_rooms()

func _relay_available() -> bool:
	if submission_in_flight or api.busy or foreground_refresh_running or not saves.data.get("pending_turn",{}).is_empty():
		_toast(PlayerCopy.MAIN_8184DEB41266)
		return false
	return true

func _show_relay_rooms(chapter: String = "") -> void:
	if not chapter.is_empty():
		if ChapterRegistry.descriptor(chapter).is_empty():
			_toast(PlayerCopy.MAIN_ED8E80825350)
			return
		selected_online_chapter = chapter
	if not _relay_available() or not await _ensure_identity():
		return
	if not _campaign_depart_for_ordinary(): return
	if relay_session == null:
		relay_session = _new_relay_session()
	running = false
	mode = "relay_rooms"
	relay_menu_generation += 1
	var generation := relay_menu_generation
	_draw_relay_lobby(PlayerCopy.MAIN_07713E9CC81E, true)
	await relay_session.load_lobby()
	if generation != relay_menu_generation or mode != "relay_rooms":
		return
	_draw_relay_lobby(relay_session.last_error)

func _draw_relay_lobby(message: String = "", loading: bool = false) -> void:
	mode = "relay_rooms"
	var frame := _card(790)
	var chosen := ChapterRegistry.descriptor(selected_online_chapter)
	frame.add_child(_label(str(chosen.title) + ", together.",32,CREAM,true))
	var card := _scroll_list(frame)
	card.get_parent().custom_minimum_size.y = clampf(overlay.size.y - 240.0, 150.0, 420.0)
	card.add_child(_paragraph(str(chosen.summary) + PlayerCopy.MAIN_796084F78EB4,680))
	if chosen.get("premium", false): card.add_child(_paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,680))
	if not message.is_empty(): card.add_child(_paragraph(message,680))
	if loading:
		card.add_child(_paragraph(PlayerCopy.MAIN_6DC16645A479,680))
	else:
		var enabled: bool = relay_session.mutations_enabled()
		var choices := OptionButton.new()
		choices.custom_minimum_size.y = 48
		choices.mouse_filter = Control.MOUSE_FILTER_PASS
		for key: String in ChapterRegistry.keys():
			var item := ChapterRegistry.descriptor(key)
			var index := choices.item_count
			var available: bool = relay_session.supports_creation(key)
			choices.add_item(str(item.title) + ("" if available else " · unavailable online"))
			choices.set_item_metadata(index,key)
			if key == selected_online_chapter: choices.select(index)
		choices.item_selected.connect(func(index: int):
			selected_online_chapter = str(choices.get_item_metadata(index))
			_draw_relay_lobby())
		card.add_child(choices)
		if not relay_session.supports_creation(selected_online_chapter):
			card.add_child(_paragraph(PlayerCopy.MAIN_73FEF220EAF1,680))
		var pending: Dictionary = relay_session.pending_lobby()
		if not pending.is_empty():
			var retry := _list_button("Retry saved create / join request",func(): _relay_lobby_action("retry"))
			retry.disabled = not enabled
			card.add_child(retry)
		else:
			var row := HBoxContainer.new()
			card.add_child(row)
			var selected := selected_online_chapter
			var create := _list_button("Create this chapter",func(): _relay_lobby_action("create",selected))
			create.disabled = not relay_session.supports_creation(selected)
			row.add_child(create)
			var code := LineEdit.new()
			code.placeholder_text = "Chapter invitation code"
			code.max_length = 40
			code.custom_minimum_size = Vector2(255,50)
			row.add_child(code)
			var join := _list_button("Join",func(): _relay_lobby_action("join",code.text),false)
			join.disabled = not enabled
			row.add_child(join)
		var rooms: Array = relay_session.room_ids()
		if not rooms.is_empty():
			var list := VBoxContainer.new()
			list.add_theme_constant_override("separation",10)
			card.add_child(list)
			for index in range(rooms.size()):
				var room_id: String = rooms[index]
				list.add_child(_list_button("%s %d%s" % [relay_session.room_title(room_id),index+1," · last opened" if room_id==relay_session.last_room() else ""],func(): _relay_lobby_action("open",room_id),false))
		var pending_redo: String = relay_session.pending_redo_room()
		if not pending_redo.is_empty() and pending_redo not in rooms:
			card.add_child(_list_button("Retry request",func(): _relay_lobby_action("open",pending_redo),false))
		var options := HBoxContainer.new()
		options.add_theme_constant_override("separation",14)
		card.add_child(options)
		var refresh := _list_button("Refresh availability and rooms",_show_relay_rooms,false)
		refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.add_child(refresh)
		var practice := _list_button("Practice this chapter solo",_open_selected_chapter_solo,false)
		practice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.add_child(practice)
	frame.add_child(_button("Back",func(): relay_menu_generation+=1; _show_rooms(),false))

func _open_selected_chapter_solo() -> void:
	if selected_online_chapter == ChapterRegistry.FIRST_STEPS: _open_first_steps()
	elif selected_online_chapter == ChapterRegistry.RELAY: _open_relay_preview()
	elif ChapterRegistry.is_cooperative(selected_online_chapter): _open_cooperative_preview(selected_online_chapter)

func _relay_lobby_action(action: String, value: String = "") -> void:
	if relay_session == null or relay_session.busy() or not _relay_available() or not _relay_identity().ready:
		return
	if not _legacy_redo_navigation_ready(): return
	if not _campaign_depart_for_ordinary(): return
	relay_menu_generation += 1
	var generation := relay_menu_generation
	_draw_relay_lobby(PlayerCopy.MAIN_6734074E99D4,true)
	var room_id := ""
	match action:
		"create": room_id = await relay_session.create_room(value)
		"join": room_id = await relay_session.join_room(value)
		"retry": room_id = await relay_session.retry_lobby()
		"open":
			await relay_session.open_room(value)
			if relay_session.coordinator != null and relay_session.coordinator.snapshot().get("room_id", "") == value:
				room_id = value
	if generation != relay_menu_generation or mode != "relay_rooms" or not _relay_identity().ready:
		return
	if room_id.is_empty():
		_draw_relay_lobby(relay_session.last_error)
		return
	_enter_online_relay()

func _enter_online_relay() -> void:
	if not _legacy_redo_navigation_ready(): return
	if relay_session == null or relay_session.coordinator == null or relay_session.busy() or is_instance_valid(relay_child):
		return
	lifecycle_generation += 1
	foreground_refresh_queued = false
	foreground_response = {}
	running = false
	mode = "relay_online"
	friend_share_target = {"api_version":2,"room_id":relay_session.coordinator.snapshot().room_id}
	room_play = false
	world.visible = false
	ui.visible = false
	soundscape.set_backgrounded(true)
	relay_child = RelayPreview.new()
	relay_child.chapter_key = relay_session.chapter_key()
	relay_child.online_session = relay_session
	relay_child.friend_presence = friend_presence
	relay_child.settings = saves.data.settings.duplicate(true)
	relay_child.save_photo_prompt_preference = _save_photo_prompt_preference
	relay_child.turn_notification_status = _turn_notification_status
	relay_child.enable_turn_notifications = _enable_turn_notifications
	relay_child.closed.connect(_leave_online_relay)
	add_child(relay_child)
	_sync_presence()

func _replace_campaign_relay_child(source: Node, generation: int, target_room: String,
		target_index: int, flow: Node, owner: RefCounted, on_story_closed: Callable) -> Node:
	# Private composition seam: no public route calls this yet. No await may be
	# inserted from adoption through removal/attachment of the new native child.
	if application_backgrounded or mode != "relay_online" or relay_child != source or not is_instance_valid(source) or not source.is_inside_tree(): return null
	if relay_session == null or owner == null or not is_instance_valid(flow) or not on_story_closed.is_valid(): return null
	if source._story_hold != generation or not flow.handoff_matches(source,generation,target_room,target_index) or not owner.adoption_ready(): return null
	var target := _new_campaign_relay_child(target_index,flow,owner,on_story_closed)
	if target == null: return null
	if not owner.adopt_selected():
		target.free()
		return null
	# The child type/resources were preloaded. Adoption is now authoritative;
	# retire before _exit_tree and the new _ready can synchronously re-enter flow.
	flow.retire_for_replacement(source,generation)
	source.online_request_generation += 1
	source.running = false
	source.action_pressed = false
	source.set_process(false)
	source.set_physics_process(false)
	remove_child(source)
	source.queue_free()
	relay_child = target
	lifecycle_generation += 1
	foreground_refresh_queued = false
	foreground_response = {}
	add_child(target)
	_sync_presence()
	return target

func _leave_online_relay() -> void:
	if is_instance_valid(relay_child):
		remove_child(relay_child)
		relay_child.queue_free()
	relay_child = null
	world.visible = true
	ui.visible = true
	soundscape.set_backgrounded(application_backgrounded)
	lifecycle_generation += 1
	mode = "relay_rooms"
	_sync_presence()
	_draw_relay_lobby(relay_session.last_error if relay_session != null else "")

func _ensure_identity() -> bool:
	if saves.data.has(DeletedPhotos.MARKER_KEY) or not deleted_identity_owner.is_empty():
		_toast(PlayerCopy.MAIN_A9AD59F7E952)
		return false
	if not pending_recovery.is_empty():
		_toast(PlayerCopy.MAIN_0F8B4A22AEFC)
		return false
	if identity_restart_required:
		_toast(PlayerCopy.MAIN_5BC549F4B951)
		return false
	if identity_loading:
		var deadline := Time.get_ticks_msec()+10000
		while identity_loading and Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
		if identity_loading:
			_toast(PlayerCopy.MAIN_29B12DE56EEF)
			return false
	if not api.player_id.is_empty() and not api.device_token.is_empty():
		return true
	if identity_busy:
		_toast(PlayerCopy.MAIN_21155817127A)
		return false
	if not secrets.is_available():
		_toast(PlayerCopy.MAIN_3E8E7DA4CEE6)
		return false
	if identity_read_state!=IdentityReadState.MISSING:
		_toast(PlayerCopy.MAIN_F0A53024D858)
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
		_toast(PlayerCopy.MAIN_71B742112D9F)
		return false
	identity_read_state=IdentityReadState.LOADED
	identity_data=response.data.duplicate(true)
	api.player_id=str(response.data.player_id)
	api.device_token=str(response.data.device_token)
	_configure_purchases()
	return true

func _create_room() -> void:
	if not _relay_available() or not await _ensure_identity(): return
	if not _legacy_redo_navigation_ready(): return
	if relay_session == null: relay_session = _new_relay_session()
	if not relay_session.can_leave_for_legacy():
		_toast(relay_session.last_error)
		return
	if not _campaign_depart_for_ordinary(): return
	var context := _tester_context()
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms",{"idempotency_key":RoomsApi.new_key(),"simulation_version":Simulation.COMFORT_SIMULATION_VERSION})
	if context == _tester_context(): _accept_room(response)

func _room_simulation_version() -> int:
	return TurnState.simulation_version({},role,active_room) if room_play else 0

func _join_chapter_room(code: String) -> void:
	if code.strip_edges().is_empty() or not _relay_available() or not await _ensure_identity():
		return
	if not _legacy_redo_navigation_ready(): return
	# Both protocols use twenty hex characters, so the visible room-type choice
	# is authoritative. Never probe two mutating join endpoints with one code.
	var generation := relay_menu_generation+1
	await _show_relay_rooms()
	if generation != relay_menu_generation or mode != "relay_rooms" or relay_session == null:
		return
	await _relay_lobby_action("join",code)

func _join_room(code: String) -> void:
	if code.strip_edges().is_empty() or not _relay_available() or not await _ensure_identity():
		return
	if not _legacy_redo_navigation_ready(): return
	if not _campaign_depart_for_ordinary(): return
	if relay_session == null:
		relay_session=_new_relay_session()
	if not relay_session.can_leave_for_legacy():
		_toast(relay_session.last_error)
		return
	var context := _tester_context()
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/join",{"invite_code":code.strip_edges(),"simulation_version":Simulation.COMFORT_SIMULATION_VERSION})
	if context == _tester_context(): _accept_room(response)

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
	_restore_legacy_redo()
	if _legacy_redo_client().pending().get("action") == "accept":
		active_room = saves.data.room.duplicate(true)
		_show_room_detail()
	var context := _foreground_room_context(room_id)
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id)
	if context!=_foreground_room_context(room_id): return
	if not response.get("ok",false) and _legacy_redo_client().observe_room_failure(room_id,str(response.get("code",""))):
		_show_rooms()
		_toast(str(response.get("error",_legacy_redo_client().last_error)))
		return
	foreground_schedule.bind(context,Time.get_ticks_msec())
	_accept_room(response)

func _accept_room(response: Dictionary) -> void:
	if not response.ok:
		_toast(response.error)
		return
	var incoming: Variant=response.data.get("room",response.data)
	if not incoming is Dictionary or str(incoming.get("room_id","")).is_empty() or Levels.get_level(str(incoming.get("level_id",""))).is_empty():
		_toast(PlayerCopy.MAIN_22FBAEF49772)
		return
	if not _legacy_redo_navigation_ready(str(incoming.room_id)): return
	if relay_session != null and not relay_session.can_leave_for_legacy():
		_toast(relay_session.last_error)
		return
	if not _campaign_depart_for_ordinary(): return
	_notice_room_reactions(active_room,incoming)
	active_room=incoming.duplicate(true)
	if _relay_identity().ready: friend_share_target = {"api_version":1,"room_id":active_room.room_id}
	var erased: Array=[]
	if TurnState.pending_status(saves.data.get("pending_turn",{}),active_room)=="accepted":
		erased=["pending_turn","room_draft"]
	if not saves.update_values({"room":active_room},erased):
		_toast(saves.last_error)
	_show_room_detail()
	_refresh_legacy_redo()

func _show_room_detail() -> void:
	running=false
	mode="room"
	var frame := _card(700)
	frame.add_child(_label(PlayerCopy.MAIN_8046BBD776CA,34,CREAM,true))
	var card := _scroll_list(frame)
	card.get_parent().custom_minimum_size.y = clampf(overlay.size.y-230.0,180.0,390.0)
	if active_room.has("invite_code"):
		card.add_child(_paragraph("Invitation code: "+str(active_room.invite_code)))
		card.add_child(_list_button("Copy invitation code",func(): DisplayServer.clipboard_set(str(active_room.invite_code)); _toast("Invitation code copied."),false))
	var active_role := str(active_room.get("active_role","a"))
	var my_turn: bool = TurnState.my_turn(active_room,api.player_id)
	var redo: RefCounted = _legacy_redo_client()
	if not redo.busy: redo.bind_room("legacy",active_room)
	var redo_pending: bool = redo.pending().get("action") == "accept"
	if redo_pending: my_turn = false
	var pending: Dictionary=saves.data.get("pending_turn",{})
	card.add_child(_paragraph("Island %d of 8 · %s" % [int(active_room.get("level_index",0))+1,PlayerCopy.MAIN_1AAC5BE95E22 if my_turn else (PlayerCopy.MAIN_FAC85D5E6CA7 if active_role=="complete" else PlayerCopy.MAIN_BD6413254AB9)]))
	if is_instance_valid(friend_presence):
		_sync_presence()
		var badge := PresenceBadge.new()
		badge.configure(friend_presence, "v1", str(active_room.get("room_id", "")))
		card.add_child(badge)
	if not pending.is_empty():
		card.add_child(_paragraph(PlayerCopy.MAIN_52C04F6029F5))
		card.add_child(_list_button("Check saved submission",_reconcile_pending))
	if not my_turn and active_role != "complete" and pending.is_empty():
		_add_notification_offer(card)
	if my_turn and pending.is_empty():
		card.add_child(_list_button("Play your turn",_play_room_turn))
	if active_role=="complete":
		_add_room_reaction_summary(card, active_room)
		card.add_child(_list_button("Watch this island",_watch_room_replay,false))
		if int(active_room.get("level_index",0))<7 and pending.is_empty() and not redo_pending:
			card.add_child(_list_button("Next island",_advance_room))
		var reactions := HBoxContainer.new()
		for reaction: String in ["Beautiful!","We did it!","Again soon"]:
			reactions.add_child(_list_button(reaction,func(): room_play=true; _react(reaction),false))
		card.add_child(reactions)
	if active_room.get("guest_id") != null:
		card.add_child(_list_button("Report or block player",_room_safety,false))
	if pending.is_empty() and not redo_pending and not LocalSave.normalize_attempt(active_room.get("recordings",{})).a.is_empty():
		card.add_child(_list_button("Start a new attempt",_confirm_fork,false))
	if pending.is_empty(): _add_legacy_redo_action(card)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation",10)
	for entry: Array in [["Refresh",_refresh_room],["Home",_show_home]]:
		var action := _button(entry[0],entry[1],false)
		action.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		navigation.add_child(action)
	frame.add_child(navigation)

func _legacy_redo_client() -> RefCounted:
	if legacy_redo == null: legacy_redo = RedoClient.new(api,_relay_identity)
	return legacy_redo

func _restore_legacy_redo() -> bool:
	var context := _tester_context()
	# Cached room presentation has no authenticated redo scope until identity
	# is loaded. Network mutations separately require that identity.
	if context.is_empty(): return true
	var client := _legacy_redo_client()
	var saved: Dictionary = saves.data.get("room",{})
	var bound_id: String = client.bound_room_id("legacy")
	if not bound_id.is_empty() and (not client.pending().is_empty() or bound_id == saved.get("room_id")):
		return true
	# Notification safety is checked every frame. Restore this journal once per
	# identity and saved room, never once per safety check.
	var scope := context + ":" + str(saved.get("room_id",""))
	if scope == legacy_redo_restore_scope: return legacy_redo_restore_ok
	legacy_redo_restore_scope = scope
	legacy_redo_restore_ok = true
	if bound_id.is_empty(): client.invalidate()
	if not str(saved.get("room_id","")).is_empty() and api.player_id in [saved.get("host_id"),saved.get("guest_id")]:
		legacy_redo_restore_ok = client.bind_room("legacy",saved)
	return legacy_redo_restore_ok

func _legacy_redo_navigation_ready(target_room: String = "", reveal_recovery: bool = true) -> bool:
	var restored := _restore_legacy_redo()
	var client := _legacy_redo_client()
	var pending: Dictionary = client.pending()
	var saved: Dictionary = saves.data.get("room",{})
	var recover_room := str(pending.get("source",{}).get("room_id",saved.get("room_id","")))
	# Reading the current room is safe even after a lost acceptance reply or a
	# damaged local journal. It must not strand the route back to recovery.
	if not target_room.is_empty() and target_room == recover_room: return true
	if restored and pending.is_empty(): return true
	if reveal_recovery:
		var room: Dictionary = client.bound_room("legacy")
		if room.is_empty(): room = saved
		if not room.is_empty() and api.player_id in [room.get("host_id"),room.get("guest_id")]:
			active_room = room.duplicate(true)
			_show_room_detail()
		_toast(PlayerCopy.MAIN_8184DEB41266)
	return false

func _add_legacy_redo_action(card: VBoxContainer) -> void:
	var client: RefCounted = _legacy_redo_client()
	var source := RedoClient.source_for("legacy",active_room)
	if source.is_empty() and client.pending().is_empty(): return
	var label := "Redo requested" if client.can_accept() else "Ask for redo" if TurnState.my_turn(active_room,api.player_id) else "Turn requests"
	if not client.pending().is_empty(): label = "Retry request"
	card.add_child(_list_button(label,_open_legacy_redo,false))

func _open_legacy_redo() -> void:
	if not _relay_available() or application_backgrounded or running or is_instance_valid(redo_screen): return
	var client := _legacy_redo_client()
	if not client.bind_room("legacy",active_room): _toast(client.last_error); return
	var context := _tester_context()
	mode = "redo_requests"
	ui.visible = false
	redo_screen = RedoScreen.new()
	redo_screen.client = client
	redo_screen.closed.connect(func():
		redo_screen = null
		ui.visible = true
		if _tester_context() != context or mode != "redo_requests": return
		_show_room_detail()
		foreground_refresh_queued = true
		if not application_backgrounded and not api.busy: _refresh_room())
	add_child(redo_screen)

func _refresh_legacy_redo() -> void:
	if mode != "room" or application_backgrounded or not saves.data.get("pending_turn",{}).is_empty(): return
	var client := _legacy_redo_client()
	if client.busy: return
	if RedoClient.source_for("legacy",active_room).is_empty() and client.pending().is_empty(): return
	var context := _foreground_room_context(str(active_room.room_id))
	var before: Dictionary = client.view()
	if not client.bind_room("legacy",active_room): return
	await client.refresh()
	if context != _foreground_room_context(str(active_room.get("room_id",""))) or mode != "room" or application_backgrounded: return
	if before != client.view(): _show_room_detail()

func _play_room_turn() -> void:
	if not _restore_legacy_redo():
		_toast(PlayerCopy.MAIN_8184DEB41266)
		return
	if _legacy_redo_client().pending().get("action") == "accept":
		_show_room_detail()
		return
	if not _campaign_depart_for_ordinary(): return
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
		_toast(PlayerCopy.MAIN_2FB9511D4AA8)
		return
	pending={"room_id":active_room.room_id,"owner_player_id":api.player_id,"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key(),"recording":review_recording.duplicate(true)}
	if not saves.update_values({"pending_turn":pending}):
		_toast(PlayerCopy.MAIN_9F721149F702)
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
			_toast(PlayerCopy.MAIN_B701225FD961)
		_accept_room(response)
	else:
		if int(response.status)>=400 and int(response.status)<500 and int(response.status) not in [408,429]:
			pending["rejected"]=true
			pending["error"]=response.error
			saves.update_values({"pending_turn":pending})
		_toast(response.error+PlayerCopy.MAIN_F7B46601CBC3)

func _reconcile_pending() -> void:
	if api.busy or not await _ensure_identity():
		return
	var pending: Dictionary=saves.data.get("pending_turn",{})
	if pending.is_empty():
		return
	if pending.has("owner_player_id") and pending.owner_player_id!=api.player_id:
		_toast(PlayerCopy.MAIN_ECBD713D8F0C)
		return
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+str(pending.room_id))
	if not response.ok:
		if int(response.get("status",0)) in [404,410]:
			pending["rejected"]=true
			pending["error"]=PlayerCopy.MAIN_52480E5314F5
			active_room={}
			saves.update_values({"pending_turn":pending})
			_show_held_turn(pending)
			return
		_toast(response.error+PlayerCopy.MAIN_602A7BD28B67)
		return
	var room: Dictionary=response.data.get("room",response.data)
	var status := TurnState.pending_status(pending,room)
	if status=="accepted":
		_accept_room(response)
		_toast(PlayerCopy.MAIN_A917FC21E486)
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
	card.add_child(_label(PlayerCopy.MAIN_2A20737AA436,32,CREAM,true))
	card.add_child(_paragraph(str(pending.get("error",PlayerCopy.MAIN_6D127185ABF4))))
	card.add_child(_paragraph(PlayerCopy.MAIN_BCD95F847CF2))
	card.add_child(_button("Keep rehearsal & return",func(): _archive_held_turn(pending)))
	card.add_child(_button("Back",_show_rooms,false))

func _archive_held_turn(pending: Dictionary) -> void:
	var held: Array=saves.data.get("held_turns",[]).duplicate(true)
	held.append(pending.duplicate(true))
	var changes := {"held_turns":held,"room":active_room.duplicate(true)}
	if TurnState.my_turn(active_room,api.player_id) and pending.recording.level_id==active_room.level_id:
		var current_attempt := LocalSave.normalize_attempt(active_room.get("recordings",{}))
		if TurnState.review(Levels.get_level(active_room.level_id),pending.recording,current_attempt,TurnState.simulation_version({},str(pending.recording.get("role","")),active_room)).valid:
			current_attempt.draft=pending.recording.duplicate(true)
			changes["room_draft"]={"room_id":active_room.room_id,"revision":active_room.revision,"attempt":current_attempt}
	if not saves.update_values(changes,["pending_turn"]):
		_toast(saves.last_error)
		return
	_show_rooms() if active_room.is_empty() else _show_room_detail()

func _confirm_fork() -> void:
	if not _legacy_redo_navigation_ready(): return
	var card := _card()
	card.add_child(_label(PlayerCopy.MAIN_F817D954E490,34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_C9DD5A234C97))
	card.add_child(_button("Start a new attempt",_fork_room))
	card.add_child(_button("Keep this attempt",_show_room_detail,false))

func _fork_room() -> void:
	if not _relay_identity().ready or not _legacy_redo_navigation_ready(): return
	if not _campaign_depart_for_ordinary(): return
	if api.busy or not saves.data.get("pending_turn",{}).is_empty():
		return
	var context := _foreground_room_context(str(active_room.room_id))
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/"+str(active_room.room_id)+"/fork",{"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key()})
	if context == _foreground_room_context(str(active_room.get("room_id",""))): _accept_room(response)

func _advance_room() -> void:
	if not _relay_identity().ready or not _legacy_redo_navigation_ready(): return
	if not _campaign_depart_for_ordinary(): return
	if api.busy or not saves.data.get("pending_turn",{}).is_empty():
		return
	var context := _foreground_room_context(str(active_room.room_id))
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/"+str(active_room.room_id)+"/advance",{"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key()})
	if context == _foreground_room_context(str(active_room.get("room_id",""))): _accept_room(response)

func _show_account() -> void:
	running=false
	mode="account"
	if saves.data.has(DeletedPhotos.MARKER_KEY) or not deleted_identity_owner.is_empty():
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_EC79109D7607)
		return
	var card := _card()
	card.add_child(_label("Your little corner.",34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_F890477C65DE))
	if not pending_recovery.is_empty():
		card.add_child(_paragraph(PlayerCopy.MAIN_93BF3A28C6F9))
		card.add_child(_button("Finish identity recovery",_resume_pending_recovery))
	elif identity_restart_required:
		card.add_child(_paragraph(PlayerCopy.MAIN_5BC549F4B951))
		if not identity_data.is_empty():
			card.add_child(_button("Show my recovery details",_show_recovery_details,false))
		card.add_child(_button("Close After You",func(): get_tree().quit()))
	elif not api.player_id.is_empty():
		card.add_child(_button("Show my recovery details",_show_recovery_details,false))
		card.add_child(_button("Check hosting access",_check_hosting_access,false))
		if _play_store_enabled(): card.add_child(_button("Restore purchases",_restore_store,false))
		else: card.add_child(_button("Tester code",_show_tester_access,false))
		card.add_child(_button("Delete online identity…",_confirm_delete_identity,false))
		card.add_child(_button("Photo transfer",_open_photo_transfer,false))
		card.add_child(_button("Reports & blocked players",func(): _open_safety({},"account"),false))
	elif api.configured() and secrets.is_available():
		if identity_read_state==IdentityReadState.MISSING:
			card.add_child(_button("Create anonymous identity",func(): if await _ensure_identity(): _show_account()))
		else:
			card.add_child(_paragraph(PlayerCopy.MAIN_3E50EF2B7ECB))
			card.add_child(_button("Check saved identity",_retry_saved_identity,false))
	else:
		card.add_child(_paragraph(PlayerCopy.MAIN_570EC629872D))
	if api.configured() and secrets.is_available() and pending_recovery.is_empty() and not identity_restart_required:
		card.add_child(_button("Recover a previous identity",_show_recovery_form,false))
	card.add_child(_button("Back",_show_settings,false))

func _check_hosting_access() -> void:
	# Checking an existing purchase must not create or replace an identity.
	if identity_restart_required or identity_loading or identity_busy:
		_toast(PlayerCopy.MAIN_3A0D8776E06F)
		return
	if api.player_id.is_empty() or api.device_token.is_empty():
		_toast(PlayerCopy.MAIN_F64C9883094A)
		return
	if api.busy:
		_toast(PlayerCopy.MAIN_469D9ED22320)
		return
	running=false
	mode="hosting_access"
	var card := _card()
	card.add_child(_label("Checking hosting access…",32,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_65352AE6EE21))
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
		card.add_child(_paragraph(PlayerCopy.MAIN_632FFB4BA5D4))
	elif verified:
		card.add_child(_label("Introductory hosting",24,CREAM,true))
		if _play_store_enabled():
			card.add_child(_paragraph(PlayerCopy.MAIN_5DCCD071AE03))
		else:
			card.add_child(_button("Get it on Google Play",_open_google_play))
			card.add_child(_button("Tester code",_show_tester_access,false))
	else:
		card.add_child(_label(PlayerCopy.MAIN_618916283742,24,CREAM,true))
		card.add_child(_paragraph(PlayerCopy.MAIN_AA2B015D5D95))
	# Server verification describes hosting only. It never changes or clears
	# the separate RevenueCat SDK entitlement used for local solo play.
	card.add_child(_button("Check again",_check_hosting_access,false))
	card.add_child(_button("Back",_show_account,false))

func _show_recovery_details() -> void:
	mode="recovery_details"
	var card := _card(680)
	card.add_child(_label(PlayerCopy.MAIN_4E6353EBBDB9,32,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_B1B6CAA8087E,580))
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
		_toast(PlayerCopy.MAIN_6F5191162022)
		return
	recovery_copy_busy=true
	var result: Dictionary=await _await_secret(secrets.copy_recovery(player,code))
	recovery_copy_busy=false
	if result.get("ok",false) and result.get("payload",{}).get("copied")==true:
		_toast(PlayerCopy.MAIN_B3745871EB1C)
	else:
		_toast(PlayerCopy.MAIN_A77FFD68F5E6)

func _can_copy_acknowledged_recovery() -> bool:
	# If secure storage fails after the server confirms rotation, the new code
	# is already current. Let the player copy it from the recovery error screen.
	var request: Dictionary=pending_recovery.get("request",{})
	return recovery_acknowledged and not request.is_empty() and identity_data.get("player_id")==request.get("player_id") and identity_data.get("recovery_code")==request.get("next_recovery_code") and identity_data.get("device_token")==request.get("next_device_token")

func _show_recovery_form() -> void:
	mode="recovery_form"
	var card := _card()
	card.add_child(_label("Welcome back.",34,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_01C351256351))
	var player := LineEdit.new()
	player.name="RecoveryIdentity"
	player.placeholder_text="Identity"
	player.custom_minimum_size.y=48
	var code := LineEdit.new()
	code.name="RecoveryCode"
	code.placeholder_text="Recovery code"
	code.secret=true
	code.custom_minimum_size.y=48
	var status := _paragraph(PlayerCopy.MAIN_41C32AF5A224)
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
		status.text=PlayerCopy.MAIN_B3DD2F6125BC
		return
	player.text=details.player_id
	code.text=details.recovery_code
	player.release_focus()
	code.release_focus()
	status.text=PlayerCopy.MAIN_06D48BA3672C

func _recover_identity(player: String, code: String) -> void:
	if identity_loading:
		_toast(PlayerCopy.MAIN_45D3B02F91EE)
		return
	if api.busy or identity_busy or player.is_empty() or code.is_empty():
		return
	if not _recovery_field_matches(player,RECOVERY_ID_PATTERN) or not _recovery_field_matches(code,RECOVERY_SECRET_PATTERN):
		_toast(PlayerCopy.MAIN_C1B99419085A)
		return
	if not pending_recovery.is_empty():
		var old: Dictionary=pending_recovery.request
		if old.player_id==player and old.recovery_code==code:
			await _resume_pending_recovery()
			return
		if not recovery_replace_allowed:
			_show_pending_recovery(PlayerCopy.MAIN_0E6D79FAEEC9)
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
	_invalidate_relay_identity()
	identity_busy=true
	identity_restart_required=true
	identity_read_state=IdentityReadState.RECOVERY_PENDING
	mode="recovery"
	var card := _card()
	card.add_child(_label("Finishing your recovery…",32,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_B49D9361392F))
	var secured: Dictionary=await _await_secret(secrets.put_secret("recovery_pending",JSON.stringify(pending_recovery)))
	if not secured.ok or secured.get("payload",{}).get("stored")!=true:
		identity_busy=false
		_show_pending_recovery(PlayerCopy.MAIN_189E8206D026)
		return
	var request: Dictionary=pending_recovery.request.duplicate(true)
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/identity/recover",request)
	var data: Variant=response.get("data")
	if not response.get("ok",false) or not data is Dictionary or not data.get("recovered") is bool or data.recovered!=true or data.get("player_id")!=request.player_id:
		identity_busy=false
		recovery_replace_allowed=(response.get("status")==401 and response.get("code")=="invalid_recovery") or (response.get("status")==409 and response.get("code")=="recovery_request_mismatch")
		_show_pending_recovery(PlayerCopy.MAIN_BDE96F64E602 if recovery_replace_allowed else PlayerCopy.MAIN_3A8CB7C5D89F)
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
	# The server has acknowledged recovery. Remove only the old local binding,
	# before replacing its encrypted identity; a retry still has its exact key.
	if _tester_checks_enabled() and is_instance_valid(tester_access) and not api.player_id.is_empty() and not api.device_token.is_empty():
		var removed_tester: Dictionary = await tester_access.erase_binding(api.base_url, api.player_id, api.device_token)
		if not removed_tester.get("ok", false):
			identity_busy = false
			_show_recovery_storage_failure()
			return
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
	card.add_child(_label(PlayerCopy.MAIN_4156CE133C4E,30,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_2B7F40AEE179))
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
	card.add_child(_label(PlayerCopy.MAIN_983DDFD98433,32,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_C93C27D9AB17))
	card.add_child(_button("Show new recovery details",_show_recovery_details,false))
	card.add_child(_button("Close After You",func(): get_tree().quit()))

func _confirm_delete_identity() -> void:
	var card := _card()
	card.add_child(_label(PlayerCopy.MAIN_4335B260B3E1,30,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_6FD20F7D08FA))
	card.add_child(_button("Delete identity and shared rooms",_delete_identity))
	card.add_child(_button("Keep my identity",_show_account,false))

func _delete_identity() -> void:
	if identity_busy or api.busy or not await _ensure_identity():
		return
	_invalidate_relay_identity()
	identity_busy = true
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_DELETE,"/v1/identity")
	if not response.ok:
		identity_busy = false
		_toast(response.error)
		return
	# Only this positive response authorizes local deletion. A missing profile,
	# authentication failure, or ordinary identity recovery is not confirmation.
	deleted_identity_owner=api.player_id
	identity_restart_required=true
	await _clear_deleted_identity()
	identity_busy = false

func _clear_deleted_identity() -> void:
	if deletion_cleanup_busy:
		return
	var owner := deleted_identity_owner
	if saves.data.has(DeletedPhotos.MARKER_KEY):
		owner=DeletedPhotos.marker_owner(saves.data[DeletedPhotos.MARKER_KEY])
	if not DeletedPhotos.valid_owner(owner) or (not identity_data.is_empty() and identity_data.get("player_id")!=owner):
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_58F37D557118)
		return
	if identity_loading or identity_read_state not in [IdentityReadState.LOADED,IdentityReadState.MISSING]:
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_143D1D0DB2C5)
		return
	if not DeletedAck.permitted(saves, owner):
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_6D018CBB9D68)
		return
	deletion_cleanup_busy=true
	identity_restart_required=true
	deleted_identity_owner=owner
	# Owner-only tombstone survives a restart; credentials remain in Keystore.
	# Persist it before any destructive local action, including the native cache.
	if not saves.update_values({DeletedPhotos.MARKER_KEY:{"schema_version":1,"owner":owner}}):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_9C9B9DFD3CC2)
		return
	_show_deleted_identity_cleanup(PlayerCopy.MAIN_88E7AC6A1F3D,false)
	if not is_instance_valid(deletion_photo_cleanup):
		deletion_photo_cleanup=DeletedPhotos.new()
		if relay_session != null:
			deletion_photo_cleanup.store=relay_session.photo_store
		add_child(deletion_photo_cleanup)
	var photos: Dictionary=await deletion_photo_cleanup.clear_owner(owner)
	if not photos.get("ok",false):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_7EE42FB6B934)
		return
	if deletion_cache_cleanup == null: deletion_cache_cleanup = DeletedCaches.new()
	var caches: Dictionary = deletion_cache_cleanup.erase_owner(owner)
	if not caches.get("ok", false):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_35527882CDA5)
		return
	if not saves.update_values({"room":{}},["pending_turn","room_draft"]):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_949AD8CB8BF2)
		return
	if _tester_checks_enabled() and is_instance_valid(tester_access) and not str(identity_data.get("device_token", "")).is_empty():
		var tester_removed: Dictionary = await tester_access.erase_binding(api.base_url, owner, str(identity_data.device_token))
		if not tester_removed.get("ok", false):
			deletion_cleanup_busy=false
			_show_deleted_identity_cleanup(PlayerCopy.MAIN_B71C70F56731)
			return
	var acknowledged: Dictionary = await DeletedAck.finish(api, saves, owner)
	if not acknowledged.get("ok", false):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_BCC9D85CF2C1)
		return
	var result: Dictionary=await _await_secret(secrets.remove_secret("player_identity"))
	var removal: Variant=result.get("payload")
	if not result.get("ok",false) or not removal is Dictionary or removal.size()!=1 or not removal.get("removed") is bool or not removal.removed:
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_3820D398892A)
		return
	identity_data={}
	identity_read_state=IdentityReadState.MISSING
	api.player_id=""
	api.device_token=""
	identity_restart_required=true
	purchases.customer_info={}
	if not saves.update_values({},[DeletedPhotos.MARKER_KEY, DeletedAck.KEY]):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_32A0D82E6871)
		return
	deleted_identity_owner=""
	deletion_cleanup_busy=false
	var card := _card()
	card.add_child(_label(PlayerCopy.MAIN_5367370EB8BE,30,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_DB7ADD49F62D))
	card.add_child(_button("Close After You",func(): get_tree().quit()))

func _show_deleted_identity_cleanup(message: String, retry: bool=true) -> void:
	running=false
	mode="account_cleanup"
	var card := _card()
	card.add_child(_label("Finish device cleanup",30,CREAM,true))
	card.add_child(_paragraph(message))
	if retry:
		card.add_child(_button("Retry device cleanup",_clear_deleted_identity))
		if identity_read_state not in [IdentityReadState.LOADED,IdentityReadState.MISSING] and not identity_loading:
			card.add_child(_button("Check saved identity",_retry_deleted_identity_read,false))
		card.add_child(_button("Back",_show_settings,false))

func _retry_deleted_identity_read() -> void:
	if deletion_cleanup_busy or identity_loading:
		return
	# The durable marker still blocks online use while the ordinary encrypted
	# read retries. It cannot create an identity or authorize server deletion.
	identity_restart_required=false
	await _retry_saved_identity()

func _show_saved_rooms() -> void:
	if not _relay_available() or not await _ensure_identity():
		return
	if relay_session == null: relay_session = _new_relay_session()
	if relay_session.busy(): return
	running = false
	mode = "recent_rooms"
	var loading := _card(760)
	loading.add_child(_label("Recent online rooms",34,CREAM,true))
	loading.add_child(_paragraph(PlayerCopy.MAIN_07713E9CC81E,680))
	loading.add_child(_button("Back",_show_rooms,false))
	var view := store_view_generation
	var identity := _tester_context()
	var lifecycle := lifecycle_generation
	var chapters_ok: bool = await relay_session.load_lobby()
	if not _recent_rooms_current(view,identity,lifecycle): return
	var chapter_error: String = "" if chapters_ok else relay_session.last_error
	var chapters: Array[Dictionary] = []
	if chapters_ok: chapters.assign(relay_session.room_summaries())
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms")
	if not _recent_rooms_current(view,identity,lifecycle): return
	_draw_recent_rooms(response,chapters,chapter_error)

func _recent_rooms_current(view: int, identity: String, lifecycle: int) -> bool:
	return mode=="recent_rooms" and store_view_generation==view and not identity.is_empty() and identity==_tester_context() and lifecycle==lifecycle_generation and not application_backgrounded

func _draw_recent_rooms(response: Dictionary, chapters: Array[Dictionary], chapter_error: String) -> void:
	var card := _card(760)
	card.add_child(_label("Recent online rooms",34,CREAM,true))
	var list := _scroll_list(card)
	if not chapter_error.is_empty(): list.add_child(_paragraph(chapter_error,680))
	for chapter: Dictionary in chapters:
		var room_id: String = chapter.room_id
		var text := str(chapter.title)+" · "+("Hosted" if chapter.hosted else "Joined")
		if chapter.active_role=="complete": text += " · Ready to replay"
		if chapter.last_opened: text += " · last opened"
		var button := _list_button(text,func(): _relay_lobby_action("open",room_id),false)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.set_meta("recent_room_family","v2")
		button.set_meta("recent_room_id",room_id)
		list.add_child(button)
	var pending_redo: String = relay_session.pending_redo_room() if relay_session != null else ""
	if not pending_redo.is_empty() and not chapters.any(func(chapter: Dictionary) -> bool: return chapter.room_id == pending_redo):
		list.add_child(_list_button("Retry request",func(): _relay_lobby_action("open",pending_redo),false))
	var rows: Array = []
	if response.get("ok",false) and response.get("data",{}).get("rooms") is Array:
		rows = response.data.rooms
	else:
		list.add_child(_paragraph(str(response.get("error",PlayerCopy.MAIN_8184DEB41266)),680))
	for value: Variant in rows:
		if value is Dictionary:
			var room: Dictionary=value.duplicate(true)
			var definition: Dictionary=Levels.get_level(str(room.get("level_id","")))
			var button := _list_button(str(definition.get("title","Island"))+" · "+("Ready to replay" if room.get("active_role")=="complete" else "In progress"),func(): _accept_room({"ok":true,"data":room}),false)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.set_meta("recent_room_family","v1")
			button.set_meta("recent_room_id",str(room.get("room_id","")))
			list.add_child(button)
	if rows.is_empty() and chapters.is_empty() and chapter_error.is_empty() and response.get("ok",false):
		list.add_child(_paragraph("No recent rooms",680))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	card.add_child(actions)
	for entry: Array in [["Refresh",_show_saved_rooms],["Back",_show_rooms]]:
		var button := _button(entry[0],entry[1],false)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)

func _show_online_collection() -> void:
	_show_shared_replays()

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
	return not is_instance_valid(relay_child) and not application_backgrounded and not running and not submission_in_flight and mode in ["home","rooms","room","journey","collection","settings","saved"]

func _background_application() -> void:
	if application_backgrounded:
		return
	application_backgrounded=true
	if is_instance_valid(campaign_flow): campaign_flow.set_backgrounded(true)
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
	if is_instance_valid(campaign_flow): campaign_flow.set_backgrounded(false)
	_resume_purchase_access()
	if is_instance_valid(soundscape):
		soundscape.set_backgrounded(is_instance_valid(relay_child))
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
		if int(deferred.get("generation",-1))==lifecycle_generation and str(deferred.get("context",""))==_foreground_room_context(str(deferred.room_id)):
			_apply_foreground_response(deferred.response,str(deferred.room_id))
	if api==null or api.busy or identity_loading or identity_busy:
		return
	if not api.configured() or identity_restart_required or api.player_id.is_empty() or api.device_token.is_empty():
		foreground_refresh_queued=false
		return
	var pending: Dictionary=saves.data.get("pending_turn",{})
	var room_id := str(saves.data.get("room",{}).get("room_id",""))
	if not pending.is_empty() and (not pending.has("owner_player_id") or pending.owner_player_id==api.player_id):
		room_id=str(pending.get("room_id",""))
	if room_id.is_empty():
		foreground_refresh_queued=false
		foreground_schedule.bind("",Time.get_ticks_msec())
		return
	var now := Time.get_ticks_msec()
	var context := _foreground_room_context(room_id)
	foreground_schedule.bind(context,now)
	if foreground_refresh_queued:
		foreground_schedule.request_now(now)
		foreground_refresh_queued=false
	elif mode not in ["room","rooms"]:
		return
	var ticket: Dictionary=foreground_schedule.begin_if_due(now,true,api.busy)
	if ticket.is_empty():
		return
	foreground_refresh_running=true
	var generation := lifecycle_generation
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id)
	foreground_refresh_running=false
	var current := context==_foreground_room_context(room_id)
	foreground_schedule.complete(ticket,Time.get_ticks_msec(),response.get("ok",false),int(response.get("retry_after_ms",0)),response.get("status",0) in [401,403,404,410])
	if generation!=lifecycle_generation or not current:
		return
	if not _foreground_refresh_safe():
		foreground_response={"response":response,"room_id":room_id,"generation":generation,"context":context}
		return
	_apply_foreground_response(response,room_id)

func _foreground_room_context(room_id: String) -> String:
	return JSON.stringify([api.player_id,api.device_token.sha256_text(),relay_identity_epoch,lifecycle_generation,room_id])

func _apply_foreground_response(response: Dictionary, requested_room: String) -> void:
	if not response.get("ok",false):
		if mode in ["room","rooms"]:
			_toast(str(response.get("error",PlayerCopy.MAIN_076E60DB25EC)))
		return
	var incoming: Variant=response.get("data",{})
	if incoming is Dictionary:
		incoming=incoming.get("room",incoming)
	if not incoming is Dictionary or str(incoming.get("room_id",""))!=requested_room or Levels.get_level(str(incoming.get("level_id",""))).is_empty():
		return
	if not _legacy_redo_navigation_ready(requested_room,false): return
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
	if remembered and saves.data.room!=incoming:
		changes["room"]=incoming.duplicate(true)
	var erased: Array=["pending_turn","room_draft"] if confirmed else []
	if not changes.is_empty() or not erased.is_empty():
		if not saves.update_values(changes,erased):
			_toast(saves.last_error)
			return
	if displayed:
		var changed: bool=active_room!=incoming
		_notice_room_reactions(active_room,incoming)
		if not TurnState.my_turn(active_room,api.player_id) and TurnState.my_turn(incoming,api.player_id):
			_toast(PlayerCopy.MAIN_09164F93CEA2)
		active_room=incoming.duplicate(true)
		if mode=="room" and changed:
			_show_room_detail()
	if confirmed:
		_toast(PlayerCopy.MAIN_A917FC21E486)
	# An unmatched pending request stays queued for explicit reconciliation.
	# Returning to the app never starts or retries a POST automatically.
	if mode == "room": _refresh_legacy_redo()

func _toast(text: String) -> void:
	toast_label.text=text
	toast_label.visible=true
	toast_time=6.0

func _process(delta: float) -> void:
	_service_home_keepsakes(delta)
	_sync_presence()
	_advance_completion_moment(delta)
	_service_foreground_refresh()
	if is_instance_valid(turn_notifications):
		turn_notifications.service(Time.get_ticks_msec(), not application_backgrounded, not submission_in_flight and not foreground_refresh_running and not running and (relay_session == null or not relay_session.busy()))
		_service_notification_route()
	if toast_time>0:
		toast_time-=delta
		toast_label.visible=toast_time>0
	if not capture_path.is_empty():
		capture_frames+=1
		if capture_frames==90:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_path)
			get_tree().quit()

func _service_home_keepsakes(delta: float) -> void:
	if mode not in ["home","journey"] or application_backgrounded or is_instance_valid(relay_child): return
	_keepsake_poll += delta
	if _keepsake_poll < 0.15: return
	_keepsake_poll = 0.0
	var identity := _relay_identity()
	if identity.ready and identity != _keepsake_identity:
		_keepsake_identity = identity.duplicate()
		if shared_replays == null: shared_replays = SharedReplays.new(api,_relay_identity)
		# The cached index is enough here. Loading every saved room would replay
		# its full proof on the home thread; verification is queued by the service.
		home_keepsakes.reconcile_friend(shared_replays)
	if home_keepsakes.backfill_pending(): home_keepsakes.advance_backfill(1)
	if mode == "journey":
		_refresh_chapter_marks()
	elif is_instance_valid(home_stage_view):
		home_stage_view.set_keepsakes(home_keepsakes.earned_descriptors())
		var offer := overlay.get_node_or_null("HomeFullJourney") as Button
		if offer != null: offer.visible = not _full_journey_access()

func _notification(what: int) -> void:
	# The retained parent owns services, while the child owns its active draft,
	# input and Back/close behavior. Never let both screens process Back.
	if (is_instance_valid(relay_child) or is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen) or is_instance_valid(friends_screen) or is_instance_valid(redo_screen)) and what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]:
		return
	if what==NOTIFICATION_APPLICATION_PAUSED:
		_background_application()
	elif what==NOTIFICATION_APPLICATION_RESUMED:
		if is_instance_valid(turn_notifications): turn_notifications.queue_reconcile()
		_refresh_safe_area.call_deferred()
		_resume_application()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == "story_lobby": _story_back()
		elif mode == "story_access": _draw_story_lobby()
		elif mode == "paywall" and not _story_store_return.is_empty(): _leave_store()
		elif mode in ["confirm_retry", "confirm_restart"]:
			if _retry_cancel.is_valid(): _retry_cancel.call()
		elif mode == "story_replay_chapters": _return_story_replay_lobby()
		elif mode == "shared_memories" and not _story_replay_return.is_empty(): _back_to_story_replay_chapters()
		elif running or mode=="completion":
			_pause()
		elif mode=="license_text":
			_show_licenses()
		elif mode in ["licenses", "tester_access"]:
			_show_settings()
		elif mode=="recent_rooms":
			_show_rooms()
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not _save_draft():
			_pause()
			_toast(PlayerCopy.MAIN_A3FDAA4A9D35)
			return
		get_tree().quit()

func _setup_turn_notifications() -> void:
	var native := NotificationBridge.new()
	add_child(native)
	turn_notifications = TurnNotifications.new()
	turn_notifications.configure(api, native, _notification_identity, _read_notification_binding, _write_notification_binding, _notification_preference, _save_notification_preference)
	turn_notifications.changed.connect(_update_notification_offer)
	turn_notifications.foreground_hint.connect(_notification_foreground_hint)
	turn_notifications.route_available.connect(func():
		if is_instance_valid(toast_label): _toast(PlayerCopy.MAIN_6FE6B224FD24))
	add_child(turn_notifications)

func _notification_identity() -> Dictionary:
	return {"ready": _relay_identity().ready, "settled": not identity_loading and identity_read_state not in [IdentityReadState.UNCHECKED, IdentityReadState.LOADING], "owner": api.player_id if api != null else "", "credential_hash": api.device_token.sha256_text() if api != null and not api.device_token.is_empty() else ""}

func _notification_preference() -> bool:
	return saves.data.settings.get("turn_notifications", false) == true

func _save_notification_preference(value: bool) -> bool:
	var next: Dictionary = saves.data.settings.duplicate(true)
	next.turn_notifications = value
	return saves.update_values({"settings": next})

func _read_notification_binding() -> Dictionary:
	var result: Dictionary = await _await_secret(secrets.get_secret("notification_binding"))
	var payload: Variant = result.get("payload")
	if not result.get("ok", false) or not payload is Dictionary: return {"ok": false}
	if payload.get("found") == false and payload.get("value") == null: return {"ok": true, "value": {}}
	if payload.get("found") != true or not payload.get("value") is String: return {"ok": false}
	var value: Variant = _parse_json(payload.value)
	return {"ok": value is Dictionary, "value": value}

func _write_notification_binding(value: Dictionary) -> Dictionary:
	var result: Dictionary = await _await_secret(secrets.put_secret("notification_binding", JSON.stringify(value)))
	return {"ok": result.get("ok", false) and result.get("payload", {}).get("stored") == true}

func _turn_notification_status() -> Dictionary:
	return {"enabled": turn_notifications.enabled(), "registered": turn_notifications.registered(), "busy": turn_notifications.busy(), "message": turn_notifications.status_text}

func _enable_turn_notifications() -> void:
	turn_notifications.set_enabled(true)
	_update_notification_offer()

func _show_notification_settings() -> void:
	running = false
	mode = "notifications"
	turn_notifications.queue_reconcile()
	var card := _card(640)
	card.add_child(_label(PlayerCopy.MAIN_7EE625C6EC26, 30, CREAM, true))
	card.add_child(_paragraph(PlayerCopy.MAIN_EF43E19393E4, 560))
	_add_notification_offer(card)
	card.add_child(_button("Turn notifications off", func(): turn_notifications.set_enabled(false); _update_notification_offer(), false))
	card.add_child(_button("Back to settings", _show_settings, false))

func _add_notification_offer(card: VBoxContainer) -> void:
	notification_hint = _paragraph("", 480)
	notification_hint.name = "TurnNotificationStatus"
	card.add_child(notification_hint)
	notification_offer = _button(PlayerCopy.MAIN_C4B947AAAE59, _enable_turn_notifications, false)
	notification_offer.name = "EnableTurnNotifications"
	card.add_child(notification_offer)
	_update_notification_offer()

func _update_notification_offer() -> void:
	if not is_instance_valid(turn_notifications): return
	var state := _turn_notification_status()
	if is_instance_valid(notification_hint): notification_hint.text = state.message
	if is_instance_valid(notification_offer):
		notification_offer.visible = not state.registered
		notification_offer.disabled = state.busy
	if is_instance_valid(relay_child): relay_child.update_notification_offer()

func _notification_foreground_hint(route: Dictionary) -> void:
	if not turn_notifications.accepts(route): return
	if route.room_family == "relay" and is_instance_valid(relay_child):
		relay_child.notification_room_hint(route.room_id)
	elif route.room_family == "legacy" and str(saves.data.get("room", {}).get("room_id", "")) == route.room_id:
		foreground_refresh_queued = true
	# The ordinary refresh schedulers enforce mode, identity, busy and cooldown
	# guards. Receiving a hint never reconciles a POST or changes the open room.

func _notification_route_safe(route: Dictionary) -> bool:
	if not _campaign_notification_unbound(): return false
	if application_backgrounded or running or submission_in_flight or identity_loading or identity_busy or foreground_refresh_running or is_instance_valid(relay_child) or saves.read_only: return false
	if mode not in ["home", "rooms", "room", "journey", "earlier_islands", "collection", "saved", "relay_rooms"]: return false
	if not _relay_identity().ready or api.busy or not saves.data.get("pending_turn", {}).is_empty() or not saves.data.get("room_draft", {}).is_empty(): return false
	if not _legacy_redo_navigation_ready(str(route.room_id) if route.room_family == "legacy" else "",false): return false
	if relay_session != null:
		if relay_session.busy() or not relay_session.can_leave_for_legacy(): return false
		if relay_session.coordinator != null and not relay_session.coordinator.draft().is_empty(): return false
	return turn_notifications.accepts(route)

func _notification_route_context() -> String:
	return JSON.stringify([TurnNotifications.identity_key(_notification_identity()), relay_identity_epoch, lifecycle_generation, mode])

func _notification_route_current(route: Dictionary, context: String) -> bool:
	return context == _notification_route_context() and _notification_route_safe(route) and turn_notifications.pending_route().get("event_id") == route.event_id

func _service_notification_route() -> void:
	if notification_route_busy or Time.get_ticks_msec() < notification_route_retry_ms: return
	var route: Dictionary = turn_notifications.pending_route()
	if route.is_empty(): return
	if not _notification_route_safe(route):
		if not application_backgrounded and notification_deferred_event != route.event_id:
			notification_deferred_event = route.event_id
			var message := PlayerCopy.MAIN_55E41B8A33F9
			if is_instance_valid(relay_child): relay_child.notification_deferred(message)
			else: _toast(message)
		return
	notification_route_busy = true
	await _open_notification_route(route)
	notification_route_busy = false

func _open_notification_route(route: Dictionary) -> void:
	if not _notification_route_safe(route): return
	var context := _notification_route_context()
	var path := ("/v1/rooms/" if route.room_family == "legacy" else "/v2/rooms/") + str(route.room_id)
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_GET, path)
	# The user may tap a newer room notification while the network is waiting.
	# Check the native selection again before applying this older response.
	await turn_notifications.refresh_pending_route()
	if not _notification_route_current(route, context): return
	var room: Variant = response.get("data")
	if room is Dictionary: room = room.get("room", room)
	if not response.get("ok", false):
		notification_route_retry_ms = Time.get_ticks_msec() + maxi(5000, int(response.get("retry_after_ms", 0)))
		if int(response.get("status", 0)) in [401, 403, 404, 410]:
			turn_notifications.acknowledge_route(route.event_id)
		_toast(PlayerCopy.MAIN_15214ED7911C)
		return
	if not _notification_owned_room(room, route):
		turn_notifications.acknowledge_route(route.event_id)
		_toast(PlayerCopy.MAIN_310F42091578)
		return
	if route.room_family == "legacy":
		if Levels.get_level(str(room.get("level_id", ""))).is_empty():
			turn_notifications.acknowledge_route(route.event_id)
			_toast(PlayerCopy.MAIN_6DE42F59590C)
			return
		if not saves.update_values({"room": room.duplicate(true)}):
			notification_route_retry_ms = Time.get_ticks_msec() + 15000
			_toast(PlayerCopy.MAIN_22017C43B345)
			return
		active_room = room.duplicate(true)
		friend_share_target = {"api_version":1,"room_id":active_room.room_id}
		_show_room_detail()
	else:
		if room.get("api_version") != 2 or ChapterRegistry.resolve(room).is_empty():
			turn_notifications.acknowledge_route(route.event_id)
			_toast(PlayerCopy.MAIN_F4F6AF4420A6)
			return
		if relay_session == null: relay_session = _new_relay_session()
		if relay_session.capabilities.is_empty():
			var loaded: bool = await relay_session.load_lobby()
			if not _notification_route_current(route, context): return
			if not loaded:
				notification_route_retry_ms = Time.get_ticks_msec() + 15000
				_toast(PlayerCopy.MAIN_571E92F64ED1)
				return
		var opened: bool = await relay_session.open_room(route.room_id)
		await turn_notifications.refresh_pending_route()
		if not _notification_route_current(route, context): return
		if not opened:
			notification_route_retry_ms = Time.get_ticks_msec() + 15000
			_toast(PlayerCopy.MAIN_BE8E691311EE)
			return
		_enter_online_relay()
	turn_notifications.acknowledge_route(route.event_id)

func _notification_owned_room(room: Variant, route: Dictionary) -> bool:
	return room is Dictionary and room.get("room_id") == route.room_id and api.player_id in [room.get("host_id"), room.get("guest_id")] and TurnNotifications._integer(room.get("revision")) and int(room.revision) >= int(route.revision)

func _room_safety() -> void:
	if active_room.is_empty() or not _relay_identity().ready: return
	var peer: Variant = active_room.get("guest_id") if active_room.get("host_id") == api.player_id else active_room.get("host_id")
	if not Safety.Store.id(peer): return
	_open_safety({"room_family": "legacy", "room_id": active_room.room_id, "peer_id": peer}, "room")

func _open_safety(context: Dictionary = {}, return_to: String = "settings") -> void:
	if is_instance_valid(safety_screen): return
	if api.busy or submission_in_flight or foreground_refresh_running or (relay_session != null and relay_session.busy()):
		_toast(PlayerCopy.MAIN_8D6F750820DC)
		return
	lifecycle_generation += 1
	foreground_refresh_queued = false
	foreground_response = {}
	safety_return = return_to
	mode = "safety"
	running = false
	ui.visible = false
	safety_screen = SafetyScreen.new(Safety.new(api, _relay_identity, null, Callable(), _campaign_media_factory()), context, _close_safety, _blocked_safety)
	add_child(safety_screen)

func _close_safety() -> void:
	safety_screen = null
	ui.visible = true
	if safety_return == "room" and not active_room.is_empty(): _show_room_detail()
	elif safety_return == "account": _show_account()
	else: _show_settings()

func _blocked_safety() -> void:
	safety_screen = null
	ui.visible = true
	running = false
	_show_saved_rooms()


func _tester_checks_enabled() -> bool:
	return OS.get_name() == "Android" or tester_access_factory.is_valid()

func _tester_context() -> String:
	if not _relay_identity().ready: return ""
	return JSON.stringify([api.base_url, api.player_id, api.device_token.sha256_text(), relay_identity_epoch])

func _tester_active() -> bool:
	return _tester_checks_enabled() and is_instance_valid(tester_access) and not _tester_context().is_empty() and tester_access.active(api.base_url, api.player_id, api.device_token)

func _full_journey_access() -> bool:
	return _tester_active() or purchases.has_entitlement()

func _load_cached_tester() -> void:
	if not _tester_checks_enabled() or not is_instance_valid(tester_access): return
	var context := _tester_context()
	if context.is_empty() or context == tester_checked_context: return
	if tester_loading:
		var deadline := Time.get_ticks_msec() + 65000
		while tester_loading and context == _tester_context() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		return
	tester_loading = true
	tester_load_generation += 1
	var generation := tester_load_generation
	var result: Dictionary = await tester_access.load_cached(api.base_url, api.player_id)
	if generation != tester_load_generation: return
	tester_loading = false
	if context != _tester_context(): return
	if result.get("ok", false) and tester_access.cache_loaded_for(api.base_url, api.player_id, api.device_token):
		tester_checked_context = context

func _show_tester_access() -> void:
	running = false
	mode = "tester_access"
	var card := _card(700)
	card.add_child(_label("Tester access",32,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_BA73581A5C04,620))
	card.add_child(_button("Back to settings",_show_settings,false))
	var view := store_view_generation
	if not await _ensure_identity():
		if mode == "tester_access" and view == store_view_generation: _tester_form(PlayerCopy.MAIN_B39BBA0B04B0)
		return
	await _load_cached_tester()
	if mode != "tester_access" or view != store_view_generation: return
	if _tester_active(): _show_tester_active()
	else: _tester_form()

func _tester_form(message: String = "") -> void:
	mode = "tester_access"
	var card := _card(700)
	card.add_child(_label("Tester code",32,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_A44444872701,620))
	if not message.is_empty(): card.add_child(_paragraph(message,620))
	var field := LineEdit.new()
	field.name = "TesterCode"
	field.placeholder_text = "Tester code"
	field.secret = true
	field.max_length = 128
	field.custom_minimum_size.y = 52
	card.add_child(field)
	var submit := _button("Redeem tester code",func(): _submit_tester_code(field))
	submit.disabled = not _relay_identity().ready or tester_action_pending
	card.add_child(submit)
	var restore := _button("Restore tester access",_restore_tester_access,false)
	restore.disabled = not _relay_identity().ready or tester_action_pending
	card.add_child(restore)
	card.add_child(_paragraph(PlayerCopy.MAIN_2E2A18416368,620))
	card.add_child(_button("Back to settings",_show_settings,false))

func _show_tester_active() -> void:
	mode = "tester_access"
	var card := _card(700)
	card.add_child(_label("Tester access active",32,CREAM,true))
	card.add_child(_button("Back to chapters",_show_journey))
	if _play_store_enabled(): card.add_child(_button("Store purchases",func(): _show_paywall(true),false))
	else: card.add_child(_button("Get it on Google Play",_open_google_play,false))
	card.add_child(_button("Back to settings",_show_settings,false))

func _submit_tester_code(field: LineEdit) -> void:
	if tester_action_pending or not is_instance_valid(field) or not _relay_identity().ready: return
	var code := field.text
	field.clear()
	await _request_tester_access(code, false)

func _restore_tester_access() -> void:
	await _request_tester_access("", true)

func _request_tester_access(code: String, restoring: bool) -> void:
	if tester_action_pending or not _relay_identity().ready: return
	tester_action_pending = true
	var context := _tester_context()
	var card := _card(700)
	card.add_child(_label("Restoring tester access…" if restoring else "Checking tester code…",30,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_C7E8A28B2803,620))
	card.add_child(_button("Back to settings",_show_settings,false))
	var view := store_view_generation
	var result: Dictionary = await tester_access.restore(api.base_url, api.player_id) if restoring else await tester_access.redeem(api.base_url, api.player_id, code)
	code = ""
	tester_action_pending = false
	if context != _tester_context(): return
	if result.get("ok", false) and purchases is Purchases: purchases.invalidate_session_reads()
	if tester_access.cache_loaded_for(api.base_url, api.player_id, api.device_token): tester_checked_context = context
	if application_backgrounded or mode != "tester_access": return
	if view != store_view_generation:
		_refresh_tester_screen_if_idle()
		return
	if result.get("ok",false) and result.get("granted",false) and result.get("durable",false) and _tester_active():
		_show_tester_active()
	elif result.get("ok",false) and not result.get("granted",false):
		_tester_form(PlayerCopy.MAIN_B7C7E85171CD)
	else:
		_tester_form(PlayerCopy.MAIN_85B232C00485)

func _resume_purchase_access() -> void:
	if _tester_checks_enabled(): await _load_cached_tester()
	if application_backgrounded or tester_loading: return
	_refresh_tester_screen_if_idle()
	if _tester_active(): return
	if not store_configured:
		if _relay_identity().ready and not store_action_pending:
			_configure_purchases()
		return
	if purchases is Purchases and purchases.needs_review_verification() and _store_identity_ready():
		purchases.refresh_customer_info()

func _sync_presence() -> void:
	if not is_instance_valid(friend_presence): return
	var identity := _relay_identity()
	identity["base_url"] = api.base_url
	identity["device_token"] = api.device_token
	# A pending account deletion cannot republish an old credential.
	if saves.data.has(DeletedPhotos.MARKER_KEY) or not deleted_identity_owner.is_empty(): identity.ready = false
	friend_presence.set_identity(identity)
	var family := ""
	var room := ""
	if is_instance_valid(relay_child) and relay_session != null:
		family = "v2"
		room = relay_session.last_room()
	elif not active_room.is_empty() and (mode == "room" or (room_play and mode in ["ready", "play", "preview", "review", "paused", "saved", "completion"])):
		family = "v1"
		room = str(active_room.get("room_id", ""))
	if family == "v2":
		var factory := _campaign_media_factory()
		var context: RefCounted = factory.for_room(room,"presence")
		friend_presence.monitor_room(family,room,context,true)
	else:
		friend_presence.monitor_room(family,room)
	if is_instance_valid(presence_hud) and (presence_hud.room_id != room or presence_hud.family != family):
		presence_hud.queue_free()
		presence_hud = null
	if family == "v1" and not room.is_empty() and not is_instance_valid(presence_hud):
		presence_hud = PresenceBadge.new()
		presence_hud.configure(friend_presence, family, room)
		hud.add_child(presence_hud)
		presence_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		presence_hud.offset_left = -270
		presence_hud.offset_right = -36
		presence_hud.offset_top = 88
		presence_hud.offset_bottom = 112
		presence_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if is_instance_valid(presence_hud): presence_hud.visible = family == "v1" and room_play

func _refresh_tester_screen_if_idle() -> void:
	if mode != "tester_access" or tester_action_pending or application_backgrounded: return
	if _tester_active(): _show_tester_active()
	else: _tester_form()

func _exit_tree() -> void:
	_campaign_generation += 1
	if is_instance_valid(campaign_flow): campaign_flow.invalidate()
	home_keepsakes.deactivate()
	# The room view ends here; foreground presence continues in standalone scenes.
	if is_instance_valid(friend_presence): friend_presence.monitor_room("", "")

func _camera_exploration_active() -> bool:
	return not application_backgrounded and mode in ["play", "preview", "completion"] and not overlay.visible

func _camera_exploration_allowed(point: Vector2) -> bool:
	return not world.CameraExploration.ui_blocks(ui, point)


## Validate every explicitly supplied catalog, including an intentionally empty one.
func _campaign_pairs() -> Array:
	var pairs: Array = []
	var pins := {}
	for value: Variant in campaign_catalog:
		if not value is Dictionary or value.size() != 2 or not value.has("definition") or not value.has("story"): return []
		var story := CampaignStory.new()
		if not value.definition is Dictionary or not story.bind(value.story,value.definition): return []
		var key := CampaignCanonical.digest(CampaignProtocol.key(value.definition))
		if pins.has(key): return []
		pins[key] = true
		pairs.append(value.duplicate(true))
	return pairs

func _campaign_pair(key: Dictionary) -> Dictionary:
	for pair: Dictionary in _campaign_pairs():
		if CampaignCanonical.same(CampaignProtocol.key(pair.definition),key): return pair
	return {}

func _prepare_campaign_owner() -> bool:
	if not _relay_identity().ready: return false
	var pairs := _campaign_pairs()
	if pairs.size() != campaign_catalog.size(): return false
	if relay_session == null: relay_session = _new_relay_session()
	if campaign_owner == null:
		var definitions: Array = []
		for pair: Dictionary in pairs: definitions.append(pair.definition)
		campaign_owner = CampaignOwner.new(relay_session,_relay_identity,definitions,_campaign_leave_ready)
	var restored: bool = campaign_owner.restore_owner()
	if shared_replays != null:
		shared_replays.configure_context_factory(relay_session.auxiliary_context_factory())
	return restored

func _campaign_media_factory() -> RefCounted:
	if not _prepare_campaign_owner(): return AuxiliaryContext.new(null,null,{})
	var factory: RefCounted = relay_session.auxiliary_context_factory()
	return factory if factory != null else AuxiliaryContext.new(null,null,{})

func _campaign_leave_ready() -> bool:
	# Check local recovery before handing control to Story. Its own stable hold
	# is allowed, but an unresolved ordinary redo still owns its source room.
	if application_backgrounded or running or submission_in_flight or identity_busy or identity_loading or foreground_refresh_running: return false
	if not saves.data.get("pending_turn",{}).is_empty() or not saves.data.get("room_draft",{}).is_empty(): return false
	if is_instance_valid(redo_screen) or legacy_redo != null and legacy_redo.busy: return false
	if not _legacy_redo_navigation_ready("",false): return false
	if is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen): return false
	if is_instance_valid(relay_child):
		return relay_child.story_boundary_ready(true) or _cold_story_source_ready()
	return true

func _cold_story_source_ready() -> bool:
	# This allowance belongs only to the explicit cold selection below. Ordinary
	# departure still cannot turn an incomplete recovery scene into live input.
	if _campaign_recovery_context.is_empty() or not _campaign_action_busy or not _campaign_current(_campaign_recovery_context): return false
	if not CampaignCanonical.same(_campaign_recovery_context.owner_context,campaign_owner.classification_context()): return false
	var child := relay_child
	if child == null or child.mode != "campaign_recovery" or child.journey != _campaign_recovery_context.journey or child.journey != relay_session.coordinator: return false
	if child.backgrounded or child.running or child._leaving or child._story_context_lost or child._story_hold >= 0: return false
	if child.journey.read_only or child.journey.busy() or relay_session.busy() or relay_session.photo_request_busy(): return false
	if is_instance_valid(child._safety_screen) or is_instance_valid(child.reaction_photos) and child.reaction_photos.active: return false
	if is_instance_valid(campaign_flow) and campaign_flow.busy(): return false
	var observed: Dictionary = child.journey.observe_campaign_state()
	return not observed.is_empty() and observed.draft_ready and observed.pending.is_empty() and not observed.snapshot.is_empty() and CampaignCanonical.digest(observed) == _campaign_recovery_context.source_state

func _campaign_depart_for_ordinary() -> bool:
	if not _campaign_recovery_context.is_empty(): return false
	# Local solo remains available without an online identity. A previously loaded
	# owner, however, cannot be discarded merely because identity is now unsettled.
	if not _relay_identity().ready:
		return campaign_owner == null
	if not _prepare_campaign_owner():
		_toast(PlayerCopy.MAIN_6DE42F59590C if campaign_owner != null and campaign_owner.read_only else PlayerCopy.MAIN_52C04F6029F5)
		return false
	# With no campaign ownership or admission intent, ordinary Online owns its
	# existing same-room recovery and cross-room pending lock independently.
	var bound: Dictionary = campaign_owner.bound_campaign()
	var pending: Dictionary = campaign_owner.pending_lobby()
	if bound.is_empty() and pending.is_empty() and not campaign_owner.read_only: return true
	if not campaign_owner.release_for_ordinary():
		_toast(PlayerCopy.MAIN_6DE42F59590C if campaign_owner != null and campaign_owner.read_only else PlayerCopy.MAIN_52C04F6029F5)
		return false
	if is_instance_valid(campaign_flow): campaign_flow.invalidate()
	return true

func _campaign_notification_unbound() -> bool:
	# Automatic notification routing never releases a deliberate Story binding.
	if not _prepare_campaign_owner(): return false
	return campaign_owner.bound_campaign().is_empty() and campaign_owner.pending_lobby().is_empty() and campaign_owner.can_leave()

func _campaign_visible() -> bool:
	if not _campaign_pairs().is_empty(): return true
	if _relay_identity().ready: _prepare_campaign_owner()
	return campaign_owner != null and (campaign_owner.read_only or not campaign_owner.bound_campaign().is_empty() or not campaign_owner.pending_lobby().is_empty() or not campaign_owner.terminal_recovery().is_empty())

func _campaign_message() -> String:
	if campaign_owner == null: return PlayerCopy.MAIN_6DE42F59590C
	var code := str(campaign_owner.last_code)
	if code.is_empty() or code == "campaign_terminal_reconciliation_required": return ""
	if code == "campaign_terminal_retirement_pending": return PlayerCopy.MAIN_EC79109D7607
	if code == "campaign_storage_unavailable": return PlayerCopy.RELAY_ONLINE_SESSION_E491F4F0F93A
	if code in ["host_unlock_required","entitlement_unavailable"]: return PlayerCopy.COOPERATIVE_HOST_ACCESS
	if campaign_owner.read_only or code.begins_with("unsupported_") or code in ["bound_campaign_unavailable","campaign_unavailable"]: return PlayerCopy.MAIN_6DE42F59590C
	if code in ["previous_room_pending","campaign_pending","campaign_lobby_pending"]: return PlayerCopy.MAIN_52C04F6029F5
	return PlayerCopy.MAIN_571E92F64ED1

func _show_story() -> void:
	if application_backgrounded or is_instance_valid(relay_child) or _campaign_action_busy: return
	mode = "story_lobby"
	_campaign_generation += 1
	var generation := _campaign_generation
	_draw_story_lobby(true)
	if not await _ensure_identity():
		if generation == _campaign_generation and mode == "story_lobby": _draw_story_lobby()
		return
	if generation != _campaign_generation or mode != "story_lobby" or application_backgrounded: return
	if not _prepare_campaign_owner():
		_draw_story_lobby()
		return
	var context := _campaign_context()
	while campaign_owner.busy():
		await get_tree().process_frame
		if not _campaign_current(context): return
	await campaign_owner.load_campaign_lobby()
	if _campaign_current(context): _draw_story_lobby()

func _story_back() -> void:
	_campaign_recovery_context = {}
	_campaign_generation += 1
	_campaign_action_busy = false
	_story_access_return = false
	_show_journey()

func _draw_story_lobby(loading: bool = false) -> void:
	mode = "story_lobby"
	running = false
	var frame := _card(790)
	frame.add_child(_label("Story",32,CREAM,true))
	var body := _scroll_list(frame)
	body.get_parent().custom_minimum_size.y = clampf(overlay.size.y-230.0,150.0,420.0)
	var pairs := _campaign_pairs()
	var bound: Dictionary = campaign_owner.bound_campaign() if campaign_owner != null else {}
	var pair: Dictionary = pairs[clampi(_campaign_choice,0,pairs.size()-1)] if not pairs.is_empty() else {}
	if not pair.is_empty():
		body.add_child(_label(str(pair.story.title),25,CREAM,true))
		body.add_child(_paragraph(str(pair.story.summary),680))
	var message := _campaign_message()
	if not message.is_empty(): body.add_child(_paragraph(message,680))
	if loading or _campaign_action_busy:
		body.add_child(_label("Checking…",20,MUTED))
	elif campaign_owner == null or campaign_owner.read_only:
		body.add_child(_list_button("Retry",_show_story))
	else:
		var pending: Dictionary = campaign_owner.pending_lobby()
		var terminal: Dictionary = campaign_owner.terminal_recovery()
		if not terminal.is_empty():
			body.add_child(_label("Story removed",22,CREAM,true))
			body.add_child(_list_button("Finish recovery",func(): _story_lobby_action("terminal")))
		if not pending.is_empty():
			body.add_child(_label("Cancellation pending" if pending.get("cancel_requested",false) and pending.get("accepted_campaign",{}).is_empty() else "Saved request",22,CREAM,true))
			body.add_child(_list_button("Retry",func(): _story_lobby_action("retry")))
			if pending.get("accepted_campaign",{}).is_empty() and not pending.get("cancel_requested",false) and campaign_owner.has_method("cancel_lobby_request"):
				body.add_child(_list_button("Cancel",func(): _story_lobby_action("cancel"),false))
		if not bound.is_empty():
			var removed_bound: bool = campaign_owner.terminal_anchor_released(str(bound.get("campaign_room_id",""))) or terminal.get("campaign_room_id","") == bound.get("campaign_room_id","")
			var publication: Dictionary = campaign_owner.view()
			if not publication.is_empty():
				var pin: Dictionary = publication.chapters[int(publication.current_index)].chapter
				var chapter := ChapterRegistry.descriptor(ChapterRegistry.resolve(pin))
				body.add_child(_label(str(chapter.get("title","Story")),22,CREAM,true))
			var resume := _list_button("Resume",func(): _story_lobby_action("resume"))
			resume.disabled = not pending.is_empty() or removed_bound
			body.add_child(resume)
			if not removed_bound and not _story_replay_rows().is_empty():
				body.add_child(_list_button("Shared replays",_show_story_replays,false))
			if publication.get("invite_code") is String and not removed_bound:
				body.add_child(_label("Invitation: "+str(publication.invite_code),20,CREAM))
				body.add_child(_list_button("Copy invitation",func(): DisplayServer.clipboard_set(str(publication.invite_code)),false))
		if pending.is_empty() and not pair.is_empty():
			if pairs.size() > 1:
				var choice := OptionButton.new()
				choice.custom_minimum_size.y = 48
				choice.mouse_filter = Control.MOUSE_FILTER_PASS
				for item: Dictionary in pairs: choice.add_item(str(item.story.title))
				choice.select(clampi(_campaign_choice,0,pairs.size()-1))
				choice.item_selected.connect(func(index: int): _campaign_choice=index; _draw_story_lobby())
				body.add_child(choice)
			var key := CampaignProtocol.key(pairs[clampi(_campaign_choice,0,pairs.size()-1)].definition)
			var enabled: bool = campaign_owner.supports_campaign_creation(key) and terminal.is_empty()
			var start := _list_button("Start",func(): _story_lobby_action("create",key))
			start.disabled = not enabled
			body.add_child(start)
			var invitation := LineEdit.new()
			invitation.placeholder_text = "Invitation"
			invitation.max_length = 20
			invitation.custom_minimum_size.y = 48
			body.add_child(invitation)
			var join := _list_button("Join",func(): _story_lobby_action("join",key,invitation.text),false)
			join.disabled = not enabled
			body.add_child(join)
		for reference: Dictionary in campaign_owner.campaign_references():
			if CampaignCanonical.same(reference,bound) or campaign_owner.terminal_anchor_released(str(reference.get("campaign_room_id",""))): continue
			var saved := _campaign_pair(reference.campaign_key)
			var title := str(saved.get("story",{}).get("title","Saved story"))
			body.add_child(_list_button(title,func(): _story_lobby_action("open",reference),false))
		body.add_child(_list_button("Refresh",func(): _story_lobby_action("refresh"),false))
		if str(campaign_owner.last_code) in ["host_unlock_required","entitlement_unavailable"]:
			body.add_child(_list_button("Hosting access",_show_story_access,false))
	frame.add_child(_button("Back",_story_back,false))

# Read-only discovery is scoped to the already bound Story. No gameplay
# selection, control refresh or journal mutation belongs to this route.
func _story_replay_rows() -> Array:
	if campaign_owner == null or campaign_owner.read_only: return []
	var publication: Dictionary = campaign_owner.view()
	var definition: Dictionary = campaign_owner.definition()
	var identity := _relay_identity()
	if not identity.get("ready",false) or definition.get("chapters",[]).size() > 7 or not CampaignProtocol.view_valid(publication,definition,str(identity.get("player_id",""))) or publication.state == "deleting" or publication.guest_id == null or campaign_owner.terminal_anchor_released(publication.campaign_room_id): return []
	var rows: Array = []
	for index in range(int(publication.current_index)+1):
		if index == int(publication.current_index) and publication.activation != null: continue
		var entry: Dictionary = publication.chapters[index]
		var descriptor := ChapterRegistry.descriptor(ChapterRegistry.resolve(entry.chapter))
		rows.append({"index":index,"title":str(descriptor.title),"selection":{"room_id":entry.room_id,"chapter":entry.chapter.duplicate(true),"host_id":publication.host_id,"guest_id":publication.guest_id}})
	return rows

func _show_story_replays() -> void:
	if mode != "story_lobby" or _campaign_action_busy or application_backgrounded or is_instance_valid(relay_child) or campaign_owner == null or campaign_owner.busy() or _story_replay_rows().is_empty(): return
	# A dismissed request still owns the collection until it settles. Stay on
	# this usable lobby instead of creating a permanently disabled new chooser.
	if shared_replays != null and shared_replays.busy():
		_toast(PlayerCopy.MAIN_6BB9D408ABAB)
		return
	var factory: RefCounted = _campaign_media_factory()
	if factory == null or not factory.current(): return
	if shared_replays == null: shared_replays = SharedReplays.new(api,_relay_identity)
	shared_replays.configure_context_factory(factory)
	_story_replay_return = {"owner":weakref(campaign_owner),"identity":_relay_identity().duplicate(true),"reference":campaign_owner.bound_campaign(),"factory":factory}
	_draw_story_replay_chapters()

func _story_replay_current() -> bool:
	if _story_replay_return.is_empty() or application_backgrounded: return false
	var owner: RefCounted = _story_replay_return.owner.get_ref()
	if owner == null or owner != campaign_owner or owner.read_only or not CampaignCanonical.same(_story_replay_return.identity,_relay_identity()) or not _story_replay_return.factory.current(): return false
	return CampaignCanonical.same(_story_replay_return.reference,owner.bound_campaign()) and not _story_replay_rows().is_empty()

func _story_replay_selection_current(selection: Dictionary) -> bool:
	if not _story_replay_current(): return false
	for row: Dictionary in _story_replay_rows():
		if CampaignCanonical.same(row.selection,selection): return true
	return false

func _draw_story_replay_chapters(message: String = "") -> void:
	if not _story_replay_current():
		_return_story_replay_lobby()
		return
	mode = "story_replay_chapters"
	var card := _card(760)
	card.add_child(_label("Shared replays",32,CREAM,true))
	var list := _scroll_list(card)
	list.get_parent().custom_minimum_size.y = clampf(overlay.size.y-230.0,150.0,420.0)
	for row: Dictionary in _story_replay_rows():
		var selection: Dictionary = row.selection.duplicate(true)
		var button := _list_button(str(row.index+1)+" · "+row.title,func(): _open_story_replay_chapter(selection),false)
		button.disabled = shared_replays.busy() or api.busy
		list.add_child(button)
	if not message.is_empty(): card.add_child(_paragraph(message,650))
	card.add_child(_button("Back",_return_story_replay_lobby,false))
	if shared_replays.busy() or api.busy: _redraw_story_replay_after_idle(store_view_generation,shared_replays)

func _redraw_story_replay_after_idle(view: int, collection: RefCounted) -> void:
	# Back from a busy stage list may reveal this newer chooser. Repaint only
	# its own still-current generation; the old request cannot adopt its result.
	var identity := _relay_identity()
	while collection.busy() or api.busy or application_backgrounded:
		await get_tree().process_frame
		if mode != "story_replay_chapters" or store_view_generation != view or shared_replays != collection or not CampaignCanonical.same(identity,_relay_identity()): return
	if mode == "story_replay_chapters" and store_view_generation == view and shared_replays == collection and _story_replay_current(): _draw_story_replay_chapters()

func _open_story_replay_chapter(selection: Dictionary) -> void:
	if mode != "story_replay_chapters" or shared_replays == null or shared_replays.busy() or not _story_replay_selection_current(selection): return
	var key: String = shared_replays.cached_story_chapter(selection)
	if key.is_empty():
		if api.busy: return
		_draw_story_replay_chapters(PlayerCopy.MAIN_2CEDB8F94036)
		var view := store_view_generation
		key = await shared_replays.open_story_chapter(selection)
		if mode != "story_replay_chapters" or view != store_view_generation or not _story_replay_selection_current(selection): return
	if key.is_empty():
		_draw_story_replay_chapters(shared_replays.last_error)
		return
	_story_replay_return["selection"] = selection.duplicate(true)
	_show_shared_replay_room(key)

func _story_replay_memory_current() -> bool:
	return _story_replay_return.is_empty() or (_story_replay_return.has("selection") and _story_replay_selection_current(_story_replay_return.selection))

func _back_to_story_replay_chapters() -> void:
	if _story_replay_current():
		_story_replay_return.erase("selection")
		_draw_story_replay_chapters()
	else: _return_story_replay_lobby()

func _return_story_replay_lobby() -> void:
	var current := _story_replay_current()
	_story_replay_return = {}
	store_view_generation += 1
	if current: _draw_story_lobby()
	else: _show_home()


func _campaign_context() -> Dictionary:
	return {"generation":_campaign_generation,"identity":_relay_identity().duplicate(true),"owner":campaign_owner,"mode":mode,"child":weakref(relay_child) if is_instance_valid(relay_child) else null}

func _end_campaign_action(context: Dictionary) -> void:
	if context.generation == _campaign_generation: _campaign_action_busy = false

func _campaign_current(context: Dictionary) -> bool:
	if application_backgrounded or context.generation != _campaign_generation or context.owner != campaign_owner or context.mode != mode or not CampaignCanonical.same(context.identity,_relay_identity()): return false
	var child: Variant = context.child.get_ref() if context.child != null else null
	return child == relay_child and (child == null or is_instance_valid(child) and child.is_inside_tree())

func _story_lobby_action(action: String, value: Dictionary = {}, invitation: String = "") -> void:
	if mode != "story_lobby" or _campaign_action_busy or application_backgrounded or not _prepare_campaign_owner() or campaign_owner.busy(): return
	_campaign_action_busy = true
	_campaign_generation += 1
	var context := _campaign_context()
	_draw_story_lobby(true)
	var okay := false
	match action:
		"create": okay = not (await campaign_owner.create_campaign(value)).is_empty()
		"join": okay = not (await campaign_owner.join_campaign(value,invitation)).is_empty()
		"retry": okay = not (await campaign_owner.retry_lobby_request()).is_empty()
		"cancel":
			if campaign_owner.has_method("cancel_lobby_request"): okay = await campaign_owner.cancel_lobby_request()
		"refresh": okay = await campaign_owner.load_campaign_lobby()
		"terminal": okay = await campaign_owner.reconcile_terminal()
		"open": okay = campaign_owner.bind_campaign(str(value.get("campaign_room_id","")),value.get("campaign_key",{}))
		"resume", "current": okay = true
	if not _campaign_current(context):
		_end_campaign_action(context)
		return
	if okay and action in ["create","join","retry","open","resume","current"]:
		okay = await _story_open_bound(context,action != "current")
		if not _campaign_current(context):
			_end_campaign_action(context)
			return
	_campaign_action_busy = false
	_draw_story_lobby()

func _story_open_bound(context: Dictionary, restore_selected: bool = true) -> bool:
	if not _campaign_current(context) or campaign_owner.bound_campaign().is_empty() or not campaign_owner.pending_lobby().is_empty(): return false
	# A matching durable selection is restored before any refresh/adoption. The
	# service, not Main, determines whether it is historical recovery-only.
	var selected: String = campaign_owner.selected_room()
	if restore_selected and not selected.is_empty() and relay_session.last_room() == selected:
		if not campaign_owner.has_method("restore_selected_room") or not campaign_owner.restore_selected_room(): return false
		return _enter_story_child()
	var publication: Dictionary = campaign_owner.view()
	var okay := false
	if not campaign_owner.pending().is_empty(): okay = await campaign_owner.retry_continue()
	elif publication.get("activation") != null: okay = await campaign_owner.resume_activation()
	elif publication.get("state") == "continuing": okay = await campaign_owner.resume_continuation()
	else: okay = await campaign_owner.refresh()
	if not _campaign_current(context) or not okay: return false
	publication = campaign_owner.view()
	if publication.get("activation") != null or publication.get("state") in ["continuing","deleting"]: return false
	if not await campaign_owner.select_current(): return false
	if not _campaign_current(context) or not campaign_owner.adopt_selected(): return false
	return _enter_story_child()

func _enter_story_child() -> bool:
	if is_instance_valid(relay_child) or relay_session == null or relay_session.coordinator == null: return false
	var publication: Dictionary = campaign_owner.view()
	var selected: String = campaign_owner.selected_room()
	var index := -1
	for i in range(publication.get("chapters",[]).size()):
		if publication.chapters[i].room_id == selected: index = i
	if index < 0 or index > int(publication.current_index) or relay_session.coordinator.snapshot().get("room_id") != selected: return false
	var pair := _campaign_pair(publication.campaign_key)
	if pair.is_empty(): return false
	if not is_instance_valid(campaign_flow):
		campaign_flow = CampaignFlow.new()
		add_child(campaign_flow)
	if not campaign_flow.configure(campaign_owner,_relay_identity,pair.story): return false
	var child := RelayPreview.new()
	child.chapter_key = relay_session.chapter_key()
	child.online_session = relay_session
	child.friend_presence = friend_presence
	child.settings = saves.data.settings.duplicate(true)
	child.save_photo_prompt_preference = _save_photo_prompt_preference
	child.turn_notification_status = _turn_notification_status
	child.enable_turn_notifications = _enable_turn_notifications
	_configure_story_child(child,index)
	child.closed.connect(_leave_story_child)
	lifecycle_generation += 1
	foreground_refresh_queued = false
	foreground_response = {}
	running = false
	room_play = false
	mode = "relay_online"
	world.visible = false
	ui.visible = false
	soundscape.set_backgrounded(true)
	relay_child = child
	# All guarded service work has settled. The new synchronous _ready must
	# build usable recovery controls, rather than retaining this old busy token.
	_campaign_action_busy = false
	add_child(child)
	_sync_presence()
	return true

func _configure_story_child(child: Node, index: int) -> void:
	child.story_flow = campaign_flow
	child.story_chapter_index = index
	child.campaign_card_state = _story_child_state.bind(child)
	child.campaign_card_action = _story_child_action.bind(child)
	child.campaign_control_refresh = _story_refresh_control.bind(child)
	child.campaign_refresh_ready = _story_refresh_ready.bind(child)

func _story_refresh_ready(child: Node) -> bool:
	return child == relay_child and is_instance_valid(child) and relay_session != null and child.online_session == relay_session and child.journey == relay_session.coordinator and campaign_owner != null and not campaign_owner.busy() and not _campaign_action_busy and not application_backgrounded

func _story_refresh_control(child: Node) -> Dictionary:
	var result := {"current":false,"okay":false,"changed":false}
	if child != relay_child or not is_instance_valid(child) or application_backgrounded or campaign_owner == null: return result
	if relay_session == null or child.online_session != relay_session or child.journey != relay_session.coordinator: return result
	result.current = true
	if _campaign_action_busy or campaign_owner.busy(): return result
	var context := _campaign_context()
	var owner: RefCounted = campaign_owner
	var source: RefCounted = child.journey
	var bound: Dictionary = owner.bound_campaign()
	var before: Dictionary = owner.view()
	if bound.is_empty() or before.is_empty(): return result
	# Catch up only published authority. A refresh never selects or adopts a room,
	# resends Continue, or changes the saved gameplay recovery direction.
	var okay: bool = await owner.refresh()
	if not _campaign_current(context) or child != relay_child or child.journey != source or relay_session.coordinator != source: return {"current":false,"okay":false,"changed":false}
	if not CampaignCanonical.same(bound,owner.bound_campaign()): return {"current":false,"okay":false,"changed":false}
	result.okay = okay
	result.changed = not CampaignCanonical.same(before,owner.view())
	return result

func _leave_story_child() -> void:
	_campaign_recovery_context = {}
	_campaign_generation += 1
	_campaign_action_busy = false
	if is_instance_valid(campaign_flow): campaign_flow.invalidate()
	if is_instance_valid(relay_child):
		remove_child(relay_child)
		relay_child.queue_free()
	relay_child = null
	world.visible = true
	ui.visible = true
	soundscape.set_backgrounded(application_backgrounded)
	lifecycle_generation += 1
	_sync_presence()
	_draw_story_lobby()

func _story_child_state(child: Node) -> Dictionary:
	var result := {"recovery":true,"actions":[],"message":PlayerCopy.MAIN_6DE42F59590C}
	if child != relay_child or campaign_owner == null or not _relay_identity().ready or campaign_owner.read_only: return result
	var room: Dictionary = child.journey.snapshot()
	var publication: Dictionary = campaign_owner.view()
	if publication.is_empty() or room.is_empty(): return result
	var recovery: bool = child.journey.has_method("campaign_recovery_only") and child.journey.campaign_recovery_only()
	result.recovery = recovery
	result.message = _campaign_message()
	var enabled: bool = not _campaign_action_busy and not campaign_owner.busy() and not application_backgrounded and child.story_boundary_ready(true)
	if child.mode == "complete" and child.journey.chapter_complete() and publication.state == "complete" and int(publication.current_index) == child.story_chapter_index:
		if campaign_owner.pending().is_empty(): result.message = ""
		result.actions.append({"label":"Read story" if campaign_owner.pending().is_empty() else "Retry","action":"progress","enabled":enabled})
	elif child.mode == "complete" and child.journey.chapter_complete() and child.journey.pending().is_empty() and not campaign_owner.pending().is_empty():
		# A saved Continue keeps this source recovery-only. Its exact Retry still
		# takes precedence over the generic recovery label and never enables input.
		result.actions.append({"label":"Retry","action":"progress","enabled":enabled})
	elif recovery:
		result.message = PlayerCopy.MAIN_52C04F6029F5 if not child.journey.pending().is_empty() else PlayerCopy.MAIN_571E92F64ED1
		result.actions.append({"label":"Check saved turn" if not child.journey.pending().is_empty() else "Resume","action":"recover","enabled":not _campaign_action_busy and not child.journey.busy()})
	elif child.mode == "complete":
		var label := "Continue story" if int(publication.current_index)+1 < publication.chapters.size() else "Finish"
		if not campaign_owner.pending().is_empty(): label = "Retry"
		elif publication.get("activation") != null or publication.state == "continuing" or int(publication.current_index) != child.story_chapter_index: label = "Resume"
		elif publication.state == "complete": label = "Read story"
		result.actions.append({"label":label,"action":"progress","enabled":enabled})
	if is_instance_valid(campaign_flow) and not campaign_flow.history_entries(str(room.room_id)).is_empty(): result.actions.append({"label":"History","action":"history","enabled":enabled})
	if str(campaign_owner.last_code) in ["host_unlock_required","entitlement_unavailable"]: result.actions.append({"label":"Hosting access","action":"access","enabled":enabled})
	return result

func _story_child_action(action: String, child: Node) -> void:
	if is_instance_valid(campaign_flow) and campaign_flow.busy(): return
	if child != relay_child or _campaign_action_busy or application_backgrounded or campaign_owner == null or campaign_owner.busy(): return
	if action == "history":
		var room: Dictionary = child.journey.snapshot()
		if room.is_empty() or not is_instance_valid(campaign_flow): return
		var entries: Array = campaign_flow.history_entries(str(room.room_id))
		if entries.is_empty(): return
		child.show_story_history(entries,_story_history.bind(child))
		return
	if action == "access":
		_leave_story_child()
		_show_story_access()
		return
	if action not in ["progress","recover"]: return
	if action == "progress" and not child.story_boundary_ready(true): return
	_campaign_action_busy = true
	_campaign_generation += 1
	var context := _campaign_context()
	child.refresh_campaign_actions()
	var okay := true
	if action == "recover":
		var saved_gameplay_pending: Dictionary = child.journey.pending()
		okay = await campaign_owner.refresh()
		if not _campaign_current(context):
			_end_campaign_action(context)
			return
		if okay and not CampaignCanonical.same(saved_gameplay_pending,child.journey.pending()): okay = false
		if okay and not saved_gameplay_pending.is_empty():
			await child.journey.reconcile()
			if not _campaign_current(context):
				_end_campaign_action(context)
				return
		if not child.journey.pending().is_empty(): okay = false
		if okay:
			# A late B acceptance may be the first durable sight of completion.
			# Keep that source scene until its eligible completion is presented.
			child.refresh_campaign_card()
			var observed: Dictionary = campaign_owner.view()
			if not campaign_owner.pending().is_empty(): okay = await campaign_owner.retry_continue()
			elif observed.get("activation") != null: okay = await campaign_owner.resume_activation()
			elif observed.get("state") == "continuing": okay = await campaign_owner.resume_continuation()
	else:
		var publication: Dictionary = campaign_owner.view()
		if not campaign_owner.pending().is_empty(): okay = await campaign_owner.retry_continue()
		elif publication.get("activation") != null: okay = await campaign_owner.resume_activation()
		elif publication.state == "continuing": okay = await campaign_owner.resume_continuation()
		elif publication.state == "active" and int(publication.current_index) == child.story_chapter_index: okay = await campaign_owner.continue_current()
	if not _campaign_current(context):
		_end_campaign_action(context)
		return
	if okay:
		var publication: Dictionary = campaign_owner.view()
		if not _campaign_current(context):
			_end_campaign_action(context)
			return
		if publication.state == "complete" and int(publication.current_index) == child.story_chapter_index and child.journey.chapter_complete():
			_campaign_action_busy = false
			if campaign_owner.story_seen(child.story_chapter_index,"completion"):
				campaign_flow.present_history(child,child.story_chapter_index,"completion")
			elif not campaign_flow.present_finale(child,child.story_chapter_index): child.refresh_campaign_card()
			return
		if publication.state == "active" and publication.activation == null and int(publication.current_index) == child.story_chapter_index+1 and child.journey.chapter_complete():
			okay = await campaign_owner.select_current()
			if not _campaign_current(context):
				_end_campaign_action(context)
				return
			if okay:
				_campaign_action_busy = false
				if campaign_flow.present_handoff(child,child.story_chapter_index,_replace_campaign_relay_child.bind(campaign_owner,_leave_story_child)): return
		elif action == "recover" and publication.get("activation") == null and publication.get("state") in ["waiting","active","complete"]:
			# Adjacent completed sources use the warm passage above. More distant
			# sources, and a stale final cache, recover directly to a verified target.
			if int(publication.current_index) > child.story_chapter_index or not child.journey.chapter_complete():
				if await _recover_current_story_child(child,context,publication): return
				if not _campaign_current(context):
					_end_campaign_action(context)
					return

	_campaign_action_busy = false
	if child.mode == "complete": child.refresh_campaign_actions()
	else: child.refresh_campaign_card()

func _new_campaign_relay_child(target_index: int, flow: Node, owner: RefCounted, on_story_closed: Callable) -> Node:
	var campaign_definition: Dictionary = owner.definition()
	if target_index < 0 or target_index >= campaign_definition.get("chapters",[]).size(): return null
	var target_chapter := ChapterRegistry.resolve(campaign_definition.chapters[target_index])
	if target_chapter.is_empty() or ChapterRegistry.definition(target_chapter).is_empty(): return null
	var target := RelayPreview.new()
	target.chapter_key = target_chapter
	target.online_session = relay_session
	target.friend_presence = friend_presence
	target.settings = saves.data.settings.duplicate(true)
	target.save_photo_prompt_preference = _save_photo_prompt_preference
	target.turn_notification_status = _turn_notification_status
	target.enable_turn_notifications = _enable_turn_notifications
	target.story_flow = flow
	target.story_chapter_index = target_index
	if owner == campaign_owner and flow == campaign_flow: _configure_story_child(target,target_index)
	target.closed.connect(on_story_closed)
	return target

func _recover_current_story_child(source: Node, context: Dictionary, publication: Dictionary) -> bool:
	# Explicit cold recovery only. The existing bridge checks the exact native
	# target while the historical scene and its saved evidence remain attached.
	if not _campaign_current(context) or source != relay_child or not is_instance_valid(campaign_flow) or campaign_flow.busy(): return false
	if relay_session == null or source.journey != relay_session.coordinator or not source.journey.pending().is_empty(): return false
	var owner: RefCounted = campaign_owner
	if not owner.pending().is_empty() or not owner.pending_lobby().is_empty(): return false
	if publication.get("activation") != null or publication.get("state") not in ["waiting","active","complete"]: return false
	var target_index := int(publication.current_index)
	if target_index < source.story_chapter_index: return false
	var target_room: String = publication.chapters[target_index].room_id
	var source_journey: RefCounted = source.journey
	var recovery_context := context.duplicate()
	recovery_context["journey"] = source_journey
	recovery_context["owner_context"] = owner.classification_context()
	recovery_context["source_state"] = CampaignCanonical.digest(source_journey.observe_campaign_state())
	_campaign_recovery_context = recovery_context
	var recovered := await _select_recovered_story_child(source,context,publication,target_index,target_room,source_journey,owner)
	if _campaign_recovery_context.get("generation") == context.generation: _campaign_recovery_context = {}
	return recovered

func _select_recovered_story_child(source: Node, context: Dictionary, publication: Dictionary,
		target_index: int, target_room: String, source_journey: RefCounted, owner: RefCounted) -> bool:
	if not await owner.select_current(): return false
	if not _campaign_current(context) or source.journey != source_journey or relay_session.coordinator != source_journey: return false
	if not CampaignCanonical.same(publication,owner.view()) or owner.selected_room() != target_room: return false
	# select_current has now saved its own selection journal. Rebind the pure
	# observer only after the full publication and caller context still match.
	_campaign_recovery_context["owner_context"] = owner.classification_context()
	if not owner.adoption_ready(): return false
	var target := _new_campaign_relay_child(target_index,campaign_flow,owner,_leave_story_child)
	if target == null: return false
	# No await between authoritative adoption and synchronous child replacement.
	# A failed pointer save keeps both the old node and its coordinator in place.
	if not owner.adopt_selected():
		target.free()
		return false
	_campaign_recovery_context = {}
	campaign_flow.invalidate()
	source.online_request_generation += 1
	source.running = false
	source.action_pressed = false
	source.set_process(false)
	source.set_physics_process(false)
	remove_child(source)
	source.queue_free()
	relay_child = target
	lifecycle_generation += 1
	foreground_refresh_queued = false
	foreground_response = {}
	_campaign_action_busy = false
	add_child(target)
	_sync_presence()
	return true

func _story_history(index: int, phase: String, child: Node) -> void:
	if child != relay_child or not is_instance_valid(campaign_flow): return
	child.refresh_campaign_card()
	campaign_flow.present_history(child,index,phase)

func _show_story_access() -> void:
	_story_access_return = false
	if is_instance_valid(relay_child): return
	mode = "story_access"
	var frame := _card(750)
	frame.add_child(_label("Hosting access",30,CREAM,true))
	frame.add_child(_paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,660))
	if _play_store_enabled():
		var view := store_view_generation
		frame.add_child(_button("Store purchases",func():
			if mode == "story_access" and view == store_view_generation: _show_story_store()))
	frame.add_child(_button("Settings",func(): _story_access_return=true; _show_settings(),false))
	frame.add_child(_button("Back",_draw_story_lobby,false))

func _show_story_store() -> void:
	if mode != "story_access" or application_backgrounded or _campaign_action_busy or is_instance_valid(relay_child) or not _play_store_enabled(): return
	if campaign_owner == null or campaign_owner.busy() or relay_session == null: return
	var context := _campaign_context()
	if not context.identity.get("ready",false): return
	var return_context := {"owner":weakref(campaign_owner),"session":weakref(relay_session),
		"identity":context.identity,"generation":context.generation,"reference":campaign_owner.bound_campaign(),
		"selected_room":campaign_owner.selected_room(),"selection":relay_session.campaign_selection_generation(),"choice":_campaign_choice}
	_show_paywall(true,return_context)

func _story_store_current() -> bool:
	if _story_store_return.is_empty() or application_backgrounded: return false
	var owner: RefCounted = _story_store_return.owner.get_ref()
	var session: RefCounted = _story_store_return.session.get_ref()
	if owner == null or owner != campaign_owner or session == null or session != relay_session: return false
	if _story_store_return.generation != _campaign_generation or not CampaignCanonical.same(_story_store_return.identity,_relay_identity()): return false
	return CampaignCanonical.same(_story_store_return.reference,owner.bound_campaign()) and _story_store_return.selected_room == owner.selected_room() and _story_store_return.selection == session.campaign_selection_generation() and _story_store_return.choice == _campaign_choice

func _story_settings_done() -> void:
	if _story_access_return:
		_story_access_return = false
		_draw_story_lobby()
	else: _show_home()
