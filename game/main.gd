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
const ControlTheme = preload("res://presentation/control_theme.gd")
const LocalSave = preload("res://services/local_save.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
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
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const RoomHubScreen = preload("res://presentation/room_hub_screen.gd")
const RoomInboxClient = preload("res://services/room_inbox_client.gd")
const FriendRoomEventsClient = preload("res://services/friend_room_events_client.gd")
const ChapterThumbnailCatalog = preload("res://services/chapter_thumbnail_catalog.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const REDO_REQUEST_BODY := "Your friend requested to redo your turn. Check the request to accept or reject it."
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
const SoloReplayCollection = preload("res://services/solo_replay_collection.gd")
const SoloReplayVisibility = preload("res://services/solo_replay_visibility.gd")
# Optional hook so a friend-nickname lookup (which lives in the C client) can
# supply a saved partner's display name. Default playback shows a neutral label.
var replay_partner_label: Callable = Callable()
const ReplayLoadingBar = preload("res://presentation/replay_loading_bar.gd")
const ReplayLoadProgress = preload("res://services/replay_load_progress.gd")
var _shared_replay_loading_bar: VBoxContainer
var _collection_replay_worker: Thread
var _collection_replay_job: Dictionary = {}
var _collection_replay_worker_job: Dictionary = {}
var _collection_replay_loading_bar: VBoxContainer
var _bounded_card_scroll: ScrollContainer
var _redo_request_modal: Control
var _announced_redo_requests: Dictionary = {}
## Holds the scroll area of a bounded card; controls added after it stay fixed below the list.
var _bounded_card_footer: VBoxContainer
var _bounded_card_stack: VBoxContainer
var _replay_library_header: VBoxContainer
const Safety = preload("res://services/safety_client.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const INK := Color("193d39")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("9dbeb4")
const GOLD := Color("f1c48a")
## Replay library shows the row list beside a fixed preview card once the safe
## width reaches this; narrower screens stack the preview under the list.
const REPLAY_SPLIT_MIN_WIDTH := 1000.0
const RECOVERY_ID_PATTERN := "^[A-Za-z0-9_-]{22}$"
const RECOVERY_SECRET_PATTERN := "^[A-Za-z0-9_-]{43}$"
const RECOVERY_KEY_PATTERN := "^[A-Za-z0-9_-]{16,80}$"
const COMPLETION_MOMENT_SECONDS := 3.0
const EMPTY_SOLO_COLLECTION := "Finish your first island to see your solo replays here."
const SOLO_COLLECTION_SCANNING := "Looking for more saved replays…"
enum IdentityReadState { UNCHECKED, LOADING, MISSING, LOADED, FAILED, RECOVERY_PENDING }

var world: Node3D
var _suspended_world_id := 0
var _world_was_processing := false
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
var solo_replays: RefCounted
var solo_replay_visibility: RefCounted = SoloReplayVisibility.new()
var _selected_solo_attempt: Dictionary = {}
var _solo_collection_message := ""
var _solo_collection_started := false
## Which saved shared memory is shown in the Together preview card.
var _shared_preview_id := ""
var friends_client: RefCounted
var friend_nicknames: RefCounted = FriendNicknames.new()
var friends_screen: CanvasLayer
var room_hub_screen: CanvasLayer
var room_inbox: RefCounted
var friend_room_events: RefCounted
var room_hub_host_visibility := "friends"
var _friends_return_home := false
var _friends_hosting := false
var friend_share_target: Dictionary = {}
var _room_share_busy := false
var legacy_redo: RefCounted
var legacy_redo_restore_scope := ""
var legacy_redo_restore_ok := true
var redo_screen: CanvasLayer
var shared_replay_child: Node3D
var photo_transfer_child: Node
var shared_replay_room := ""
var _shared_photo_sync := false
var _shared_archive_sync := false
var _shared_archive_attempts: Dictionary = {}
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
		if mode=="collection" and value!="collection":
			_cancel_solo_collection_scan()
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
var store_read_request := ""
var store_read_views: Dictionary = {}
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
# Retained Story helpers cannot make content available in this release.
var campaign_catalog: Array = []
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
	_sync_world_processing()
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
	_layout_hint()
	_update_shade_bounds()
	_layout_bounded_card.call_deferred()

func _layout_hint() -> void:
	var bounds := ControlTheme.hint_bounds(ui.size.x, bool(saves.data.settings.get("left_handed",false)))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.offset_left=bounds.position.x
	hint_label.offset_top=bounds.position.y
	hint_label.offset_right=bounds.end.x
	hint_label.offset_bottom=bounds.end.y

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
	if text == "Back" or text.begins_with("Back to "):
		ControlTheme.danger(button,preload("res://assets/ui/back.svg"))
	elif text == "Delete":
		ControlTheme.danger(button,preload("res://assets/ui/social/trash.svg"))
	elif not primary:
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

func _fit_icon_button(button: Button) -> void:
	# Text-button padding would squeeze a 48px icon target down to a few pixels.
	for state: String in ["normal","hover","pressed","disabled"]:
		var source := button.get_theme_stylebox(state) if button.has_theme_stylebox_override(state) else ui.theme.get_stylebox(state,"Button")
		var style := source.duplicate() as StyleBox
		for edge: String in ["left","top","right","bottom"]: style.set("content_margin_"+edge,8)
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("icon_normal_color",CREAM)
	button.add_theme_color_override("icon_hover_color",INK)
	button.add_theme_color_override("icon_pressed_color",INK)
	button.add_theme_color_override("icon_disabled_color",MUTED)

func _clear_overlay() -> void:
	_cancel_collection_replay()
	store_view_generation += 1
	_bounded_card_scroll=null
	_bounded_card_footer=null
	_bounded_card_stack=null
	if mode != "paywall": _story_store_return = {}
	overlay_shade=null
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible=true

func _close_overlay() -> void:
	_clear_overlay()
	overlay.visible=false

func _card(width: float=560.0, bounded: bool=false) -> VBoxContainer:
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
	if bounded:
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation",14)
		margin.add_child(outer)
		_bounded_card_footer=outer
		_bounded_card_scroll=ScrollContainer.new()
		_bounded_card_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		_bounded_card_scroll.follow_focus=true
		outer.add_child(_bounded_card_scroll)
		_bounded_card_scroll.add_child(stack)
		stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_bounded_card_stack=stack
		stack.minimum_size_changed.connect(_layout_bounded_card.call_deferred)
		_layout_bounded_card.call_deferred()
	else:
		margin.add_child(stack)
	return stack

func _layout_bounded_card() -> void:
	if not is_instance_valid(_bounded_card_scroll) or not is_instance_valid(_bounded_card_stack): return
	# Leave room for the panel padding and an inset from the safe screen edges.
	_bounded_card_scroll.custom_minimum_size.y=minf(_bounded_card_stack.get_combined_minimum_size().y,maxf(0.0,ui.size.y-100.0-float(_bounded_card_scroll.get_meta("footer_reserve",0.0))))

func _paragraph(text: String, width: float=480) -> Label:
	var result := _label(text,19,MUTED)
	result.custom_minimum_size.x=width
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return result

func _show_home() -> void:
	_friends_hosting = false
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
	# Keep all six actions in three rows, including within short cutout-safe
	# landscape areas. Horizontal groups retain full-size touch targets.
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation",10)
	stack.add_child(navigation)
	var friends := _button("Play with a friend",_show_rooms,false)
	friends.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	navigation.add_child(friends)
	var friends_shortcut := _button("",_show_friends,false)
	friends_shortcut.name = "HomeFriends"
	friends_shortcut.icon = preload("res://assets/ui/social/users.svg")
	friends_shortcut.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	friends_shortcut.expand_icon = true
	friends_shortcut.custom_minimum_size = Vector2(54,54)
	friends_shortcut.add_theme_constant_override("icon_max_width",28)
	friends_shortcut.tooltip_text = "Friends"
	friends_shortcut.accessibility_name = "Friends"
	friends_shortcut.add_theme_color_override("icon_normal_color",CREAM)
	friends_shortcut.add_theme_color_override("icon_focus_color",CREAM)
	for state: String in ["hover","pressed","hover_pressed"]:
		friends_shortcut.add_theme_color_override("icon_"+state+"_color",INK)
	friends_shortcut.add_theme_color_override("icon_disabled_color",MUTED)
	navigation.add_child(friends_shortcut)
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var icon_style := friends_shortcut.get_theme_stylebox(state).duplicate() as StyleBox
		icon_style.content_margin_left = 8
		icon_style.content_margin_right = 8
		icon_style.content_margin_top = 8
		icon_style.content_margin_bottom = 8
		friends_shortcut.add_theme_stylebox_override(state,icon_style)
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
	home_stage.set_header_actions([journey_offer])

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

func _open_premium_chapter(scene: String, replay_context: Dictionary = {}) -> void:
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
		_open_chapter_preview(scene,replay_context)
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
	_open_chapter_preview(scene,replay_context)

func _open_chapter_preview(scene: String, replay_context: Dictionary = {}) -> void:
	if submission_in_flight or api.busy or foreground_refresh_running or identity_loading or identity_busy or (relay_session != null and relay_session.busy()):
		_toast(PlayerCopy.MAIN_A776CD47C8D9)
		return
	if CampaignCatalog.PRODUCTION_ENABLED and not _campaign_depart_for_ordinary(): return
	if is_instance_valid(friend_presence): friend_presence.monitor_room("", "")
	if not replay_context.is_empty() and not _write_solo_replay_context(replay_context):
		_toast("Replay could not be opened. Please try again.")
		return
	if get_tree().change_scene_to_file(scene) != OK:
		if not replay_context.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://solo-replay-playback.json"))
		_toast(PlayerCopy.MAIN_EB8856600899)

static func _write_solo_replay_context(context: Dictionary) -> bool:
	var path := "user://solo-replay-playback.json"
	var bytes := JSON.stringify(context).to_utf8_buffer()
	if bytes.is_empty() or bytes.size()>2097152: return false
	var temporary := path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.flush()
	var okay := file.get_error()==OK
	file.close()
	if not okay: return false
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path))!=OK: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))==OK

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
	if CampaignCatalog.PRODUCTION_ENABLED and not _campaign_depart_for_ordinary(): return
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
			if mode == "identity_deleting" or deletion_cleanup_busy:
				get_viewport().set_input_as_handled()
				return
			if mode == "collection_loading": _show_collection()
			elif mode == "story_lobby": _story_back()
			elif mode == "story_access": _draw_story_lobby()
			elif mode == "paywall" and not _story_store_return.is_empty(): _leave_store()
			elif mode in ["confirm_retry", "confirm_restart", "confirm_delete_replay"]:
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
	var description := PlayerCopy.MAIN_32A4E00F108C if complete else (PlayerCopy.MAIN_92F966458583 if valid else PlayerCopy.MAIN_A01274C34177)
	if complete and collection_preview:
		description=PlayerCopy.SHARED_REPLAY_VIEW_8432676D063D
	card.add_child(_paragraph(description))
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
	if collection and not room_play:
		_begin_collection_replay(recording)
		return
	var check: Dictionary=TurnState.review(current_level,recording,attempt,_room_simulation_version())
	if not check.valid:
		_toast(PlayerCopy.MAIN_CD2F00E32FC5+str(check.get("error","")))
		return
	_activate_preview(recording,collection)

func _activate_preview(recording: Dictionary, collection: bool, prepared: Dictionary = {}) -> void:
	review_recording=recording.duplicate(true)
	role=str(recording.role)
	world.load_level(current_level)
	world.home_view=false
	if prepared.is_empty():
		sim.catch_assistance=bool(recording.get("catch_assistance",true))
		if not sim.reset(current_level,attempt.get("a",{}) if role=="b" else {},role,int(recording.simulation_version)):
			_toast(sim.error)
			return
		replay_frames=Simulation.expand_recording_inputs(recording)
	else:
		sim=prepared.simulation
		replay_frames=prepared.frames
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

func _begin_collection_replay(recording: Dictionary) -> void:
	running=false
	mode="collection_loading"
	var card := _card(700,true)
	card.add_child(_label("Your replay",32,CREAM,true))
	var progress := ReplayLoadProgress.new()
	_collection_replay_loading_bar=ReplayLoadingBar.new()
	_collection_replay_loading_bar.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
	card.add_child(_collection_replay_loading_bar)
	_collection_replay_loading_bar.update_progress(progress.snapshot())
	card.add_child(_button("Back to Your replays",_show_collection,false))
	_collection_replay_job={"view":store_view_generation,"definition":current_level.duplicate(true),"attempt":attempt.duplicate(true),"recording":recording.duplicate(true),"version":_room_simulation_version(),"progress":progress,"storage":saves}
	_service_collection_replay()

func _cancel_collection_replay() -> void:
	if not _collection_replay_job.is_empty(): _collection_replay_job.progress.cancel()
	if not _collection_replay_worker_job.is_empty(): _collection_replay_worker_job.progress.cancel()
	_collection_replay_job={}
	_collection_replay_loading_bar=null

func _collection_replay_current(job: Dictionary) -> bool:
	return not job.is_empty() and mode == "collection_loading" and job.view == store_view_generation and not room_play and job.storage == saves and current_level == job.definition and attempt == job.attempt

func _service_collection_replay() -> void:
	if application_backgrounded: return
	if is_instance_valid(_collection_replay_loading_bar) and not _collection_replay_job.is_empty():
		_collection_replay_loading_bar.update_progress(_collection_replay_job.progress.snapshot())
	if _collection_replay_worker != null:
		if _collection_replay_worker.is_alive(): return
		var result: Dictionary = _collection_replay_worker.wait_to_finish()
		var finished := _collection_replay_worker_job
		_collection_replay_worker=null
		_collection_replay_worker_job={}
		if _collection_replay_current(finished) and not finished.progress.cancelled():
			_collection_replay_job={}
			if not result.get("ok",false):
				_show_collection(PlayerCopy.MAIN_CD2F00E32FC5+str(result.get("error","")))
				return
			_activate_preview(finished.recording,true,result)
			return
	if _collection_replay_job.is_empty(): return
	if not _collection_replay_current(_collection_replay_job):
		_cancel_collection_replay()
		return
	_collection_replay_worker_job=_collection_replay_job
	_collection_replay_worker=Thread.new()
	# Only private immutable values and a mutex-backed progress tracker cross
	# this boundary. The worker never sees the live save or any scene node.
	var job := {"definition":_collection_replay_job.definition,"attempt":_collection_replay_job.attempt,"recording":_collection_replay_job.recording,"version":_collection_replay_job.version}
	if _collection_replay_worker.start(Callable(get_script(),"_prepare_collection_replay").bind(job,_collection_replay_job.progress)) != OK:
		_collection_replay_worker=null
		_collection_replay_worker_job={}
		_show_collection("Could not load this replay. Please try again.")

static func _prepare_collection_replay(job: Dictionary, progress: RefCounted) -> Dictionary:
	var recording: Dictionary=job.recording
	var prior: Dictionary=LocalSave.normalize_attempt(job.attempt).a if recording.get("role") == "b" else {}
	var ticks := clampi(int(recording.duration_ticks),0,Simulation.RECEIVER_TICKS) if Simulation._is_integer(recording.get("duration_ticks")) else 0
	var prior_ticks := clampi(int(prior.duration_ticks),0,Simulation.RECEIVER_TICKS) if Simulation._is_integer(prior.get("duration_ticks")) else 0
	progress.set_total(ticks+2*prior_ticks+2)
	progress.set_phase("checking")
	if progress.cancelled(): return {"ok":false}
	var check: Dictionary=TurnState.review(job.definition,recording,job.attempt,int(job.version),progress)
	if not check.valid: return {"ok":false,"error":check.get("error","")}
	progress.advance()
	progress.set_phase("preparing")
	var prepared := Simulation.new()
	prepared.catch_assistance=bool(recording.get("catch_assistance",true))
	if not prepared.reset(job.definition,prior,str(recording.role),int(recording.simulation_version),progress): return {"ok":false,"error":prepared.error}
	if progress.cancelled(): return {"ok":false}
	var frames := Simulation.expand_recording_inputs(recording)
	progress.advance()
	progress.set_phase("ready")
	return {"ok":true,"simulation":prepared,"frames":frames}

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

func _show_collection(message: String="") -> void:
	running=false
	room_play=false
	mode="collection"
	_solo_collection_message=message
	if solo_replays == null: solo_replays=SoloReplayCollection.new()
	if not _solo_collection_started:
		_solo_collection_started=solo_replays.begin_scan()
	var scanning: bool=solo_replays.scan_pending()
	var entries := _solo_collection_entries()
	_select_solo_entry(entries)
	var shell := _begin_replay_split("solo")
	var wide: bool=shell.wide
	var left: VBoxContainer=shell.left
	left.add_child(_label("Your recordings",24,CREAM,true))
	left.add_child(_label("Completed turns",17,MUTED))
	for entry: Dictionary in entries:
		var selected: bool=wide and str(entry.get("key",""))==str(_selected_solo_attempt.get("key",""))
		left.add_child(_solo_collection_row(entry,selected,wide))
	if entries.is_empty():
		left.add_child(_paragraph(EMPTY_SOLO_COLLECTION,620))
	elif scanning:
		left.add_child(_paragraph(SOLO_COLLECTION_SCANNING,620))
	if not scanning and not solo_replays.last_error.is_empty(): left.add_child(_paragraph(solo_replays.last_error,620))
	if not _solo_collection_message.is_empty(): left.add_child(_paragraph(_solo_collection_message,620))
	if not wide:
		var refresh := _button("Refresh saved replays",func(): _solo_collection_started=false; _show_collection(),false)
		refresh.disabled=scanning
		left.add_child(refresh)
	if wide and not entries.is_empty() and not _selected_solo_attempt.is_empty():
		_fill_solo_preview(shell.right)
	else:
		shell.preview_panel.visible=false

func _solo_collection_entries() -> Array:
	# Flat, ordered list of saved solo recordings: the legacy per-level copies
	# first (in level order), then every discovered chapter attempt grouped by
	# its stages. Each entry carries a stable key so the preview selection can
	# survive a redraw.
	var entries: Array=[]
	for i in range(levels.size()):
		var saved: Dictionary=saves.replay(levels[i].id)
		if saved.get("b",{}).is_empty(): continue
		entries.append({"family":"legacy","key":"legacy:%d" % i,"level_index":i,"attempt":saved.duplicate(true),"title":str(levels[i].title),"chapter_key":"legacy-"+str(levels[i].id),"parts":1})
	if not solo_replays.scan_pending():
		var groups: Dictionary={}
		for row: Dictionary in solo_replays.items():
			if solo_replay_visibility.is_hidden(row): continue
			var group_key := str(row.get("chapter_key",""))+":"+str(row.get("attempt_id",row.get("source_id","")))
			if not groups.has(group_key): groups[group_key]=[]
			groups[group_key].append(row)
		var ordered_groups: Array=[]
		for group_key: String in groups: ordered_groups.append({"key":group_key,"rows":groups[group_key]})
		ordered_groups.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.key)<str(b.key))
		var attempt_numbers: Dictionary={}
		for item: Dictionary in ordered_groups:
			var rows: Array=item.rows
			rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.stage_index)<int(b.stage_index))
			var chapter_key := str(rows[0].chapter_key)
			attempt_numbers[chapter_key]=int(attempt_numbers.get(chapter_key,0))+1
			entries.append({"family":"chapter","key":"chapter:"+str(item.key),"rows":rows.duplicate(true),"title":"%s · Attempt %d" % [str(rows[0].chapter_title),int(attempt_numbers[chapter_key])],"chapter_key":chapter_key,"parts":rows.size()})
	return entries

func _select_solo_entry(entries: Array) -> void:
	# Keep the previewed recording selected across redraws; default to the first
	# entry and clamp the chosen part if the attempt changed under us.
	if entries.is_empty():
		_selected_solo_attempt={}
		return
	var current := str(_selected_solo_attempt.get("key",""))
	for entry: Dictionary in entries:
		if str(entry.get("key",""))==current:
			var part: int=clampi(int(_selected_solo_attempt.get("part",0)),0,maxi(0,int(entry.get("parts",1))-1))
			_selected_solo_attempt=entry.duplicate(true)
			_selected_solo_attempt["part"]=part
			return
	_selected_solo_attempt=entries[0].duplicate(true)
	_selected_solo_attempt["part"]=0

func _solo_part_subtitle(parts: int) -> String:
	return "%d %s · Saved offline" % [parts,"part" if parts==1 else "parts"]

func _begin_replay_split(selected: String, back_text: String="Back", back_callback: Callable=Callable()) -> Dictionary:
	# Shared full-screen Replays shell for Solo and Together. A fixed header
	# (Back + title + Solo/Together tabs) sits above one bounded scroller that
	# holds the row list beside a steady preview card on wide screens, or the
	# list with the preview stacked beneath it on narrow ones. Keeping a single
	# scroller means the list and its primary actions scroll together and never
	# clip, matching the safe-area rules.
	_clear_overlay()
	var shade := ColorRect.new()
	shade.color=Color(0.025,0.10,0.10,0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	overlay_shade=shade
	_update_shade_bounds()
	var wide: bool=ui.size.x>=REPLAY_SPLIT_MIN_WIDTH
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side,22)
	overlay.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation",12)
	margin.add_child(outer)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	var back := _button(back_text,back_callback if back_callback.is_valid() else _show_home,false)
	back.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	header.add_child(back)
	header.add_child(_label("Replays",34,CREAM,true))
	outer.add_child(header)
	_add_replay_library_tabs(outer,selected)
	_replay_library_header=outer
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var body := BoxContainer.new()
	body.vertical=not wide
	body.add_theme_constant_override("separation",18)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var list_column := VBoxContainer.new()
	list_column.add_theme_constant_override("separation",10)
	list_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if wide: list_column.size_flags_stretch_ratio=1.15
	body.add_child(list_column)
	var preview_panel := PanelContainer.new()
	preview_panel.add_theme_stylebox_override("panel",_style(Color("12332f"),20,Color("3f6b61")))
	preview_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	body.add_child(preview_panel)
	var preview_margin := MarginContainer.new()
	for side in ["left","top","right","bottom"]:
		preview_margin.add_theme_constant_override("margin_"+side,16)
	preview_panel.add_child(preview_margin)
	var preview := VBoxContainer.new()
	preview.add_theme_constant_override("separation",12)
	preview_margin.add_child(preview)
	_bounded_card_scroll=scroll
	_bounded_card_stack=null
	return {"outer":outer,"scroll":scroll,"body":body,"left":list_column,"right":preview,"preview_panel":preview_panel,"wide":wide}

func _replay_preview_thumb(key: String, min_size: Vector2, radius: int) -> Control:
	# A steady framed thumbnail that keeps a full 16:9/2:1 cover crop instead of
	# a thin sliver, matching the concept preview and row art.
	var frame := PanelContainer.new()
	frame.custom_minimum_size=min_size
	frame.clip_contents=true
	if min_size.x > 0: frame.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel",_style(Color("0d2a27"),radius))
	var tex := ChapterThumbnailCatalog.texture(key)
	if tex!=null:
		var picture := TextureRect.new()
		picture.texture=tex
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
		frame.add_child(picture)
	return frame

func _part_chip(label: String, selected: bool, callback: Callable) -> Button:
	var chip := _button(label,callback,false)
	chip.custom_minimum_size=Vector2(0,44)
	chip.disabled=selected
	if selected: _selected_look(chip)
	return chip

func _selected_look(button: Button) -> void:
	## The current tab or part can't be pressed again, but it should read as
	## selected rather than unavailable.
	button.add_theme_stylebox_override("disabled",_style(CREAM,14))
	button.add_theme_color_override("font_disabled_color",INK)
	button.add_theme_color_override("icon_disabled_color",INK)

func _solo_collection_row(entry: Dictionary, selected: bool, wide: bool) -> Control:
	# One saved-recording row: real chapter art, a human title, a short "N parts
	# · Saved offline" caption and a quick Play. On wide screens the title selects
	# the row for the preview card; on narrow screens it opens the part preview.
	var panel := PanelContainer.new()
	panel.mouse_filter=Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel",_style(Color("27564e") if selected else Color("1b443e"),16,Color("6fb39d") if selected else Color.TRANSPARENT))
	var pad := MarginContainer.new()
	for side in ["left","top","right","bottom"]: pad.add_theme_constant_override("margin_"+side,8)
	pad.mouse_filter=Control.MOUSE_FILTER_PASS
	panel.add_child(pad)
	var rowbox := HBoxContainer.new()
	rowbox.add_theme_constant_override("separation",12)
	rowbox.mouse_filter=Control.MOUSE_FILTER_PASS
	pad.add_child(rowbox)
	rowbox.add_child(_replay_preview_thumb(str(entry.get("chapter_key","")),Vector2(112,63),10))
	var textcol := VBoxContainer.new()
	textcol.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	textcol.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	textcol.add_theme_constant_override("separation",0)
	textcol.mouse_filter=Control.MOUSE_FILTER_PASS
	var open := func():
		_selected_solo_attempt=entry.duplicate(true)
		_selected_solo_attempt["part"]=0
		if wide: _show_collection()
		else: _show_solo_replay_attempt()
	var title := _list_button(str(entry.get("title","Replay")),open,false)
	title.set_meta("replay_row",true)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.alignment=HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text=true
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.y=52
	title.add_theme_stylebox_override("normal",_style(Color.TRANSPARENT,10))
	textcol.add_child(title)
	var caption := _paragraph(_solo_part_subtitle(int(entry.get("parts",1))),500)
	caption.add_theme_font_size_override("font_size",15)
	textcol.add_child(caption)
	rowbox.add_child(textcol)
	var play := _list_button("Play",func(): _play_solo_entry(entry,0),false)
	play.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	rowbox.add_child(play)
	if not wide and entry.get("family")=="legacy":
		rowbox.add_child(_collection_delete_button(func(): _confirm_delete_collection_replay(int(entry.get("level_index",-1)),entry.get("attempt",{})),str(entry.get("title",""))))
	return panel

func _fill_solo_preview(preview: VBoxContainer) -> void:
	var entry := _selected_solo_attempt
	var parts: int=int(entry.get("parts",1))
	var part: int=clampi(int(entry.get("part",0)),0,maxi(0,parts-1))
	preview.add_child(_replay_preview_thumb(str(entry.get("chapter_key","")),Vector2(0,220),16))
	preview.add_child(_label(str(entry.get("title","Replay")),28,CREAM,true))
	if entry.get("family")=="chapter" and parts>1:
		preview.add_child(_label("Choose a part",17,MUTED))
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation",8)
		for index in range(parts):
			chips.add_child(_part_chip("Part %d" % (index+1),index==part,func(selected_index=index): _selected_solo_attempt["part"]=selected_index; _show_collection()))
		preview.add_child(chips)
	else:
		preview.add_child(_label("Part %d / %d" % [part+1,parts],17,MUTED))
	preview.add_child(_button("Watch replay",func(): _play_solo_entry(entry,part),true))
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation",10)
	if parts>1:
		var watch_all := _button("Watch all parts",func(): _play_solo_entry(entry,parts-1),false)
		watch_all.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		secondary.add_child(watch_all)
	var options := _button("Options",_open_solo_options,false)
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	secondary.add_child(options)
	if entry.get("family")=="legacy":
		secondary.add_child(_collection_delete_button(func(): _confirm_delete_collection_replay(int(entry.get("level_index",-1)),entry.get("attempt",{})),str(entry.get("title",""))))
	else:
		var rows: Array=entry.get("rows",[])
		if part<rows.size():
			secondary.add_child(_collection_delete_button(func(): _confirm_remove_solo_part(rows[part]),_part_title(rows[part])))
	preview.add_child(secondary)

func _play_solo_entry(entry: Dictionary, part: int) -> void:
	if entry.get("family")=="legacy":
		var index := int(entry.get("level_index",-1))
		if index<0 or index>=levels.size(): return
		var selected: Dictionary=entry.get("attempt",{}).duplicate(true)
		if selected.get("b",{}).is_empty(): return
		level_index=index
		current_level=levels[index]
		attempt=selected.duplicate(true)
		_preview(selected.b,true)
	else:
		var rows: Array=entry.get("rows",[])
		if rows.is_empty(): return
		var chosen := clampi(part,0,rows.size()-1)
		_selected_solo_attempt=entry.duplicate(true)
		_selected_solo_attempt["part"]=chosen
		_launch_modern_solo_replay(rows[chosen])

func _open_solo_options() -> void:
	var modal := InGameModal.open(ui,"SoloReplayOptions","Options")
	var refresh: Button = modal.add_actions("Refresh saved replays",func():
		modal.close()
		_solo_collection_started=false
		_show_collection())
	refresh.disabled=solo_replays!=null and solo_replays.scan_pending()

func _open_together_replays() -> void:
	_show_shared_replays()

func _cancel_solo_collection_scan() -> void:
	if solo_replays != null and solo_replays.has_method("cancel_scan") and solo_replays.scan_pending():
		solo_replays.cancel_scan()
		_solo_collection_started=false

func _service_solo_collection() -> void:
	if mode != "collection" or solo_replays == null or not solo_replays.scan_pending(): return
	if not solo_replays.advance_scan():
		_solo_collection_started=true
		_show_collection(_solo_collection_message)

func _show_solo_replay_attempt() -> void:
	if mode != "collection" or _selected_solo_attempt.is_empty(): return
	mode="solo_replay_attempt"
	var card := _card(740,true)
	var legacy: bool = _selected_solo_attempt.get("family")=="legacy"
	var rows: Array=_selected_solo_attempt.get("rows",[])
	var title := str(levels[int(_selected_solo_attempt.get("level_index",0))].title) if legacy else str(rows[0].get("chapter_title","Your replay"))
	card.add_child(_label(title,34,CREAM,true))
	var list := _scroll_list(card,false)
	if legacy:
		var legacy_index := int(_selected_solo_attempt.level_index)
		var selected: Dictionary=_selected_solo_attempt.attempt.duplicate(true)
		list.add_child(_paragraph("Solo · Accepted part",600))
		list.add_child(_button("Watch replay",func():
			level_index=legacy_index
			current_level=levels[legacy_index]
			attempt=selected.duplicate(true)
			_preview(selected.b,true),true))
		list.add_child(_button("Remove from this device",func(): _confirm_delete_collection_replay(legacy_index,selected),false))
	else:
		for row: Dictionary in rows:
			var frozen := row.duplicate(true)
			var part_index := int(row.get("stage_index",0))
			var action_row := HBoxContainer.new()
			var watch := _list_button("Part %d · %s" % [part_index+1,_part_title(row)],func(): _launch_modern_solo_replay(frozen),true)
			watch.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			action_row.add_child(watch)
			action_row.add_child(_collection_delete_button(func(): _confirm_remove_solo_part(frozen),_part_title(row)))
			list.add_child(action_row)
		if rows.is_empty(): list.add_child(_paragraph("This replay can't be found anymore.",600))
	card.add_child(_button("Back to Solo replays",_show_collection,false))

static func _solo_replay_context_from_rows(chapter_key: String, rows: Array, selected: Dictionary) -> Dictionary:
	# Build the replay-only playback context from the accepted prefix of a
	# discovered attempt. Pure (no scene or disk side effects) so the exact
	# bytes the preview scene later consumes can be verified end to end.
	if ChapterRegistry.descriptor(chapter_key).is_empty(): return {}
	var ordered := rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.stage_index)<int(b.stage_index))
	var index := int(selected.get("stage_index",-1))
	if index<0 or index>=ordered.size() or ordered[index].get("id")!=selected.get("id"): return {}
	var accepted_pairs: Array=[]
	for row_index in range(index+1): accepted_pairs.append(ordered[row_index].pair.duplicate(true))
	return {"schema_version":1,"chapter_key":chapter_key,"selected_stage_index":index,"accepted_pairs":accepted_pairs,"visibility_key":str(selected.get("visibility_key",""))}

func _part_title(row: Dictionary) -> String:
	## Older saves name a part by its stage id; show it as words instead.
	var title := str(row.get("title","")).strip_edges()
	if title.is_empty(): return "Saved turn"
	if title == title.to_lower() and not title.contains(" "): return title.replace("-"," ").replace("_"," ").capitalize()
	return title

func _launch_modern_solo_replay(selected: Dictionary) -> void:
	if mode not in ["collection","solo_replay_attempt"] or _selected_solo_attempt.get("family")!="chapter": return
	var chapter_key := str(selected.get("chapter_key",""))
	var context := _solo_replay_context_from_rows(chapter_key,_selected_solo_attempt.get("rows",[]),selected)
	if context.is_empty(): return
	var scene := ChapterRegistry.solo_scene(chapter_key)
	if scene.is_empty(): return
	if ChapterRegistry.descriptor(chapter_key).premium:
		await _open_premium_chapter(scene,context)
	else:
		_open_chapter_preview(scene,context)

func _confirm_remove_solo_part(row: Dictionary) -> void:
	if mode!="solo_replay_attempt" or solo_replay_visibility.is_hidden(row): return
	mode="confirm_delete_replay"
	var card := _card(700)
	card.add_child(_label("Remove this replay?",32,CREAM,true))
	card.add_child(_paragraph(str(row.get("chapter_title","Replay"))+" · "+_part_title(row),590))
	card.add_child(_paragraph("This will hide the replay on this device only.",590))
	card.add_child(_button("Remove",func():
		if mode!="confirm_delete_replay" or application_backgrounded: return
		var okay: bool=solo_replay_visibility.hide(row)
		_show_collection("Replay removed" if okay else solo_replay_visibility.last_error),false))
	card.add_child(_button("Cancel",func(): _show_solo_replay_attempt(),false))

func _collection_delete_button(callback: Callable, title: String) -> Button:
	var remove := _list_button("",callback,false)
	remove.icon=preload("res://assets/ui/social/trash.svg")
	remove.expand_icon=true
	remove.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	remove.custom_minimum_size=Vector2(48,48)
	remove.add_theme_constant_override("icon_max_width",22)
	_fit_icon_button(remove)
	ControlTheme.danger(remove,remove.icon)
	remove.tooltip_text="Delete replay: "+title
	remove.accessibility_name=remove.tooltip_text
	remove.disabled=saves.read_only or application_backgrounded or submission_in_flight
	return remove

func _confirm_delete_collection_replay(index: int, expected: Dictionary) -> void:
	if mode not in ["collection","solo_replay_attempt"] or application_backgrounded or submission_in_flight or index < 0 or index >= levels.size(): return
	var level_id := str(levels[index].id)
	if expected.get("b",{}).is_empty() or not CampaignCanonical.same(saves.replay(level_id),expected): return
	var storage: RefCounted = saves
	var selected := expected.duplicate(true)
	mode="confirm_delete_replay"
	var card := _card(700)
	card.add_child(_label("Delete replay?",32,CREAM,true))
	card.add_child(_paragraph(str(levels[index].title),590))
	card.add_child(_paragraph("Remove this replay from Your replays on this phone? Progress, unfinished attempts and keepsakes will stay.",590))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_delete_replay" and saves == storage
	card.add_child(_button("Delete",func():
		if not current.call() or application_backgrounded or submission_in_flight: return
		var removed: bool = storage.remove_replay(level_id,selected)
		_show_collection("Replay deleted" if removed else (storage.last_error if not storage.last_error.is_empty() else "Could not remove this replay. Please try again.")),false))
	_retry_cancel = func():
		if current.call(): _show_collection()
	card.add_child(_button("Cancel",_retry_cancel))

func _show_shared_replays() -> void:
	# The Together tab opens straight into the parts/preview screen for the most
	# recent room (or the one last viewed this session). "Choose another room"
	# switches rooms from inside that view, so there is no separate room-list
	# entry point. The empty, loading, offline and unsupported states still show
	# here, and Back leaves to Home like Solo's Back.
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
	_open_default_shared_room()
	shared_replays.begin_local_load(saves.data.get("room",{}))
	_open_default_shared_room()

func _listed_shared_rooms() -> Array:
	# Rooms whose local verification still retains at least one saved replay and
	# that the player is allowed to open here.
	if shared_replays == null: return []
	return shared_replays.rooms().filter(func(room: Dictionary): return not shared_replays.memories(SharedReplays._room_key(room),true).is_empty()).filter(_production_replay_room_allowed)

func _default_shared_replay_key() -> String:
	# Prefer the room viewed earlier this session; otherwise the first listed
	# room. Returns "" when nothing can be shown yet (still loading or empty).
	var rooms := _listed_shared_rooms()
	if rooms.is_empty(): return ""
	for room: Dictionary in rooms:
		if SharedReplays._room_key(room) == shared_replay_room: return shared_replay_room
	return SharedReplays._room_key(rooms[0])

func _open_default_shared_room() -> void:
	var key := _default_shared_replay_key()
	if key.is_empty():
		_draw_shared_replay_empty()
		return
	_show_shared_replay_room(key)

func _service_shared_replays() -> void:
	if shared_replays == null or mode not in ["shared_replays", "shared_memories"] or not shared_replays.local_loading(): return
	if not shared_replays.advance_local_load():
		if is_instance_valid(_shared_replay_loading_bar): _shared_replay_loading_bar.update_progress(shared_replays.local_progress())
		return
	if mode == "shared_replays": _open_default_shared_room()
	else: _draw_shared_replay_memories(shared_replays.memories(shared_replay_room, true))

func _add_shared_replay_loading_bar(card: VBoxContainer) -> void:
	_shared_replay_loading_bar=null
	if not shared_replays.local_loading(): return
	_shared_replay_loading_bar=ReplayLoadingBar.new()
	_shared_replay_loading_bar.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
	card.add_child(_shared_replay_loading_bar)
	_shared_replay_loading_bar.update_progress(shared_replays.local_progress())

func _production_replay_room_allowed(room: Dictionary) -> bool:
	if CampaignCatalog.PRODUCTION_ENABLED or room.get("family") == "legacy": return true
	if room.get("family") != "chapter": return false
	if campaign_owner == null and not _prepare_campaign_owner(): return false
	var room_id := str(room.get("room_id",""))
	var classified: Dictionary = campaign_owner.classify_room(room_id)
	if not classified.get("ok",false) or classified.get("campaign",true): return false
	if classified.get("complete",false): return true
	if relay_session == null: return false
	relay_session.last_room() # Load the existing index before consulting its proof.
	return relay_session.standalone_room_proven(room_id)

func _production_replay_key_allowed(key: String) -> bool:
	if CampaignCatalog.PRODUCTION_ENABLED: return true
	if shared_replays == null: return false
	for room: Dictionary in shared_replays.rooms():
		if SharedReplays._room_key(room) == key: return _production_replay_room_allowed(room)
	return false

func _current_shared_room() -> Dictionary:
	if shared_replays == null: return {}
	for room: Dictionary in shared_replays.rooms():
		if SharedReplays._room_key(room) == shared_replay_room: return room
	return {}

func _replay_partner_name() -> String:
	# "With <partner>" uses the saved partner's display name when a nickname
	# lookup (which lives in the C client) is wired in through the Callable; it
	# otherwise falls back to a neutral label.
	return _room_partner_name(_current_shared_room())

func _room_partner_name(room: Dictionary) -> String:
	if room.is_empty(): return ""
	var owner := str(_relay_identity().player_id)
	var friend := str(room.get("guest_id","")) if str(room.get("host_id",""))==owner else str(room.get("host_id",""))
	if replay_partner_label.is_valid():
		var resolved := str(replay_partner_label.call(friend))
		if not resolved.is_empty(): return resolved
	var shown := _friend_display_name(friend)
	return shown if not shown.is_empty() else "a friend"

func _draw_shared_replay_empty(message: String="") -> void:
	# Shown only when there is no room to open yet: still loading, nothing saved,
	# or offline. Keeps the Together shell, loading bar, offline/error text and a
	# refresh, with Back leaving to Home like Solo's Back.
	var shell := _begin_replay_split("together","Back",_show_home)
	mode="shared_replays"
	var left: VBoxContainer=shell.left
	left.add_child(_label("Together",24,MINT,true))
	left.add_child(_paragraph(PlayerCopy.MAIN_529CFAE68DF1,630))
	_add_shared_replay_loading_bar(left)
	if not shared_replays.local_loading():
		left.add_child(_paragraph(PlayerCopy.MAIN_87534286A315,620))
	if not message.is_empty(): left.add_child(_paragraph(message,630))
	elif not shared_replays.last_error.is_empty(): left.add_child(_paragraph(shared_replays.last_error,630))
	var refresh := _button("Refresh shared rooms",_refresh_shared_replay_rooms,false)
	refresh.disabled=shared_replays.busy() or api.busy
	left.add_child(refresh)
	shell.preview_panel.visible=false

func _refresh_shared_replay_rooms() -> void:
	if shared_replays==null or shared_replays.busy() or api.busy or not _relay_identity().ready: return
	if mode=="shared_replays": _draw_shared_replay_empty(PlayerCopy.MAIN_2CEDB8F94036)
	var view := store_view_generation
	var owner := _relay_identity()
	var okay: bool=await shared_replays.refresh_rooms()
	if mode not in ["shared_replays","shared_memories"] or view!=store_view_generation or owner!=_relay_identity(): return
	if _default_shared_replay_key().is_empty():
		_draw_shared_replay_empty(PlayerCopy.MAIN_A931AA250D92 if okay else shared_replays.last_error)
		return
	_open_default_shared_room()

func _show_shared_replay_room(key: String) -> void:
	if shared_replays==null or not _relay_identity().ready or not _story_replay_memory_current() or not _production_replay_key_allowed(key): return
	if key!=shared_replay_room: _shared_preview_id=""
	shared_replay_room=key
	_draw_shared_replay_memories(shared_replays.memories(key, shared_replays.local_loading()))

func open_shared_replay_room(room_id: String) -> void:
	# Public entry for the room hub: open the Together library with one room
	# already selected. Falls back to the default view when that room can no
	# longer be shown here (signed out, no saved replays, or access not proven).
	_show_shared_replays()
	if mode not in ["shared_replays","shared_memories"] or shared_replays==null or room_id.is_empty(): return
	var key := _shared_replay_key_for_room(room_id)
	if key.is_empty(): return
	_show_shared_replay_room(key)

func _shared_replay_key_for_room(room_id: String) -> String:
	if shared_replays==null or room_id.is_empty(): return ""
	for room: Dictionary in shared_replays.rooms():
		if str(room.get("room_id",""))!=room_id: continue
		var key: String=SharedReplays._room_key(room)
		if not shared_replays.memories(key,true).is_empty() and _production_replay_room_allowed(room): return key
	return ""

func _draw_shared_replay_memories(rows: Array, message: String="") -> void:
	if not _production_replay_key_allowed(shared_replay_room): return
	var back_text := "Back"
	var back_callback := _back_to_story_replay_chapters if not _story_replay_return.is_empty() else _show_home
	var shell := _begin_replay_split("together",back_text,back_callback)
	mode="shared_memories"
	var wide: bool=shell.wide
	var left: VBoxContainer=shell.left
	var room := _current_shared_room()
	left.add_child(_label(str(room.get("title",PlayerCopy.MAIN_C8F7A8FDC485)) if not room.is_empty() else PlayerCopy.MAIN_C8F7A8FDC485,24,CREAM,true))
	var partner := _replay_partner_name()
	if not partner.is_empty(): left.add_child(_label("With "+partner,17,MUTED))
	_add_shared_room_selector(left)
	_add_shared_replay_loading_bar(left)
	_select_shared_memory(rows)
	for index in range(rows.size()):
		var row: Dictionary=rows[index].duplicate(true)
		var selected: bool=wide and str(row.get("id",""))==_shared_preview_id
		left.add_child(_shared_memory_row(row,index+1,selected,wide))
	if rows.is_empty(): left.add_child(_paragraph(PlayerCopy.MAIN_DE8FFD26387B,640))
	if not message.is_empty(): left.add_child(_paragraph(message,650))
	elif not shared_replays.last_error.is_empty(): left.add_child(_paragraph(shared_replays.last_error,650))
	left.add_child(_paragraph(PlayerCopy.MAIN_4CACA12BCD58,650))
	var has_preview: bool=wide and not rows.is_empty() and not _shared_preview_id.is_empty()
	if not has_preview:
		left.add_child(_button("Options",_open_shared_options,false))
	if has_preview:
		_fill_shared_preview(shell.right,rows)
	else:
		shell.preview_panel.visible=false

func _add_shared_room_selector(left: VBoxContainer) -> void:
	# "Choose another room" lists every shared room that still has a saved
	# replay by chapter title and partner, so switching stays on this view.
	var rooms: Array=_listed_shared_rooms()
	if rooms.size()<=1: return
	var option := OptionButton.new()
	option.custom_minimum_size.y=48
	option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	option.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	var current := 0
	for i in range(rooms.size()):
		var room: Dictionary=rooms[i]
		var key: String=SharedReplays._room_key(room)
		var partner := _room_partner_name(room)
		option.add_item(str(room.get("title","Shared room"))+(" · With "+partner if not partner.is_empty() else ""))
		option.set_item_metadata(i,key)
		if key==shared_replay_room: current=i
	option.select(current)
	option.item_selected.connect(func(index: int):
		var key := str(option.get_item_metadata(index))
		if not key.is_empty() and key!=shared_replay_room: _show_shared_replay_room(key))
	left.add_child(option)

func _shared_room_thumb_key(row: Dictionary = {}) -> String:
	var room := _current_shared_room()
	var key := str(room.get("chapter_key","")) if not room.is_empty() else ""
	if not key.is_empty() and ChapterThumbnailCatalog.texture(key) != null: return key
	# Earlier-island rooms: match the part to its island for a real picture.
	var title := str(row.get("title",""))
	for level: Dictionary in levels:
		if str(level.get("title","")) == title: return "legacy-"+str(level.get("id",""))
	return key

func _select_shared_memory(rows: Array) -> void:
	if rows.is_empty():
		_shared_preview_id=""
		return
	for row: Dictionary in rows:
		if str(row.get("id",""))==_shared_preview_id: return
	_shared_preview_id=str(rows[0].get("id",""))

func _shared_memory_row(row: Dictionary, part: int, selected: bool, wide: bool) -> Control:
	var key := shared_replay_room
	var panel := PanelContainer.new()
	panel.mouse_filter=Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel",_style(Color("27564e") if selected else Color("1b443e"),16,Color("6fb39d") if selected else Color.TRANSPARENT))
	var pad := MarginContainer.new()
	for side in ["left","top","right","bottom"]: pad.add_theme_constant_override("margin_"+side,8)
	pad.mouse_filter=Control.MOUSE_FILTER_PASS
	panel.add_child(pad)
	var rowbox := HBoxContainer.new()
	rowbox.add_theme_constant_override("separation",12)
	rowbox.mouse_filter=Control.MOUSE_FILTER_PASS
	pad.add_child(rowbox)
	rowbox.add_child(_replay_preview_thumb(_shared_room_thumb_key(row),Vector2(112,63),10))
	var textcol := VBoxContainer.new()
	textcol.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	textcol.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	textcol.add_theme_constant_override("separation",0)
	textcol.mouse_filter=Control.MOUSE_FILTER_PASS
	var open := func():
		if wide:
			_shared_preview_id=str(row.get("id",""))
			_draw_shared_replay_memories(shared_replays.memories(key,true))
		else:
			_open_shared_memory(key,row)
	var title := _list_button(str(row.get("title","Replay")),open,false)
	title.set_meta("replay_row",true)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.alignment=HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text=true
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.y=52
	title.add_theme_stylebox_override("normal",_style(Color.TRANSPARENT,10))
	textcol.add_child(title)
	var caption := _paragraph("Part %d · %s" % [part,"Saved offline" if row.get("cached",false) else "Download replay"],500)
	caption.add_theme_font_size_override("font_size",15)
	textcol.add_child(caption)
	rowbox.add_child(textcol)
	rowbox.add_child(_list_button("Play",func(): _open_shared_memory(key,row),false))
	if not wide and row.get("cached",false):
		var remove := _collection_delete_button(func(): _confirm_delete_shared_memory(key,row),str(row.get("title","")))
		remove.disabled=not _can_delete_shared_memory(key)
		rowbox.add_child(remove)
	return panel

func _fill_shared_preview(preview: VBoxContainer, rows: Array) -> void:
	var key := shared_replay_room
	var part := 0
	var current: Dictionary={}
	for index in range(rows.size()):
		if str(rows[index].get("id",""))==_shared_preview_id:
			current=rows[index].duplicate(true)
			part=index
			break
	if current.is_empty(): return
	preview.add_child(_replay_preview_thumb(_shared_room_thumb_key(current),Vector2(0,220),16))
	preview.add_child(_label(str(current.get("title","Replay")),28,CREAM,true))
	preview.add_child(_label("Part %d / %d" % [part+1,rows.size()],17,MUTED))
	preview.add_child(_button("Watch replay",func(): _open_shared_memory(key,current),true))
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation",10)
	var sequence: Array=shared_replays.local_sequence(key)
	if not sequence.is_empty():
		var watch_all := _button("Watch all parts",func(): _play_shared_entries(sequence),false)
		watch_all.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		secondary.add_child(watch_all)
	var options := _button("Options",_open_shared_options,false)
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	secondary.add_child(options)
	if current.get("cached",false):
		var remove := _collection_delete_button(func(): _confirm_delete_shared_memory(key,current),str(current.get("title","")))
		remove.disabled=not _can_delete_shared_memory(key)
		secondary.add_child(remove)
	preview.add_child(secondary)

func _open_shared_options() -> void:
	if shared_replays==null: return
	var modal := InGameModal.open(ui,"SharedReplayOptions","Options")
	var busy: bool=shared_replays.busy() or api.busy or _shared_photo_sync or _shared_archive_sync
	var refresh := _button("Refresh memories",func(): modal.close(); _refresh_shared_replay_memories(),false)
	refresh.disabled=busy
	modal.content.add_child(refresh)
	if _story_replay_return.is_empty():
		# Keep server room discovery reachable now that Together opens straight
		# into a room instead of a list; it refreshes the "Choose another room"
		# set and stays on the current room when it is still present.
		var rooms := _button("Find more rooms",func(): modal.close(); _refresh_shared_replay_rooms(),false)
		rooms.disabled=busy
		modal.content.add_child(rooms)
	var photos := _button("Sync photos",func(): modal.close(); _sync_shared_photos(),false)
	photos.disabled=busy or shared_replays.local_entries(shared_replay_room).is_empty()
	modal.content.add_child(photos)
	if shared_replay_room.begins_with("chapter:") and _story_replay_return.is_empty():
		var offline := _button("Save all replays offline",func(): modal.close(); _sync_shared_archive(),false)
		offline.disabled=busy or (relay_session!=null and relay_session.busy())
		modal.content.add_child(offline)

func _add_replay_library_tabs(parent: VBoxContainer, selected: String) -> void:
	var row := HBoxContainer.new()
	var solo := _button("Solo",_show_collection,false)
	var together := _button("Together",_show_shared_replays,false)
	solo.disabled=selected=="solo"
	together.disabled=selected=="together"
	_selected_look(solo if selected=="solo" else together)
	row.add_child(solo)
	row.add_child(together)
	parent.add_child(row)

func _can_delete_shared_memory(key: String) -> bool:
	return shared_replays != null and not shared_replays.busy() and not api.busy and not _shared_photo_sync and not _shared_archive_sync and (relay_session == null or not relay_session.busy()) and not application_backgrounded and _relay_identity().ready and key == shared_replay_room and _story_replay_memory_current() and _production_replay_key_allowed(key)

func _confirm_delete_shared_memory(key: String, row: Dictionary) -> void:
	if mode != "shared_memories" or not row.get("cached",false) or not _can_delete_shared_memory(key): return
	var expected: Dictionary = {}
	for entry: Dictionary in shared_replays.local_entries(key):
		if SharedReplays.summary(entry) == row:
			expected=entry
			break
	if expected.is_empty(): return
	var owner := _relay_identity()
	mode="confirm_delete_replay"
	var card := _card(700)
	card.add_child(_label("Delete replay?",32,CREAM,true))
	card.add_child(_paragraph(str(row.title),590))
	card.add_child(_paragraph(PlayerCopy.SHARED_REPLAY_DELETE_CONFIRM,590))
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_delete_replay"
	card.add_child(_button("Delete",func():
		if not current.call() or owner != _relay_identity() or not _can_delete_shared_memory(key): return
		var removed: bool = shared_replays.remove_memory(key,str(row.id),expected)
		_draw_shared_replay_memories(shared_replays.memories(key,true),"Replay deleted" if removed else shared_replays.last_error),false))
	_retry_cancel = func():
		if not current.call(): return
		if owner == _relay_identity() and _relay_identity().ready and _story_replay_memory_current() and _production_replay_key_allowed(key): _show_shared_replay_room(key)
		else: _show_shared_replays()
	card.add_child(_button("Cancel",_retry_cancel))

func _refresh_shared_replay_memories() -> void:
	if shared_replays==null or shared_replays.busy() or api.busy or not _relay_identity().ready or not _story_replay_memory_current() or not _production_replay_key_allowed(shared_replay_room): return
	var key := shared_replay_room
	_draw_shared_replay_memories(shared_replays.memories(key),"Checking completed stages…")
	var view := store_view_generation
	var owner := _relay_identity()
	var rows: Array=await shared_replays.refresh_memories(key)
	if mode!="shared_memories" or view!=store_view_generation or owner!=_relay_identity() or key!=shared_replay_room or not _story_replay_memory_current(): return
	_draw_shared_replay_memories(rows)

func _sync_shared_photos() -> void:
	if _shared_photo_sync or _shared_archive_sync or shared_replays == null or shared_replays.busy() or api.busy or not _relay_identity().ready or not _story_replay_memory_current() or not _production_replay_key_allowed(shared_replay_room): return
	var key := shared_replay_room
	var owner := _relay_identity()
	var session := SharedReplayView.ReadSession.new(api, _relay_identity)
	session.local_replay_only = false
	session.photo_context_factory = _campaign_media_factory()
	var targets: Array = []
	for entry: Dictionary in shared_replays.local_entries(key):
		for target: Dictionary in SharedReplays._verified_photo_turns(entry, owner.player_id):
			if not targets.has(target): targets.append(target)
	session.photo_targets = targets
	var controller: RefCounted = session.create_photo_controller(Callable())
	_shared_photo_sync = true
	_draw_shared_replay_memories(shared_replays.memories(key, true), "Syncing photos…")
	var view := store_view_generation
	for target: Dictionary in targets:
		await controller.read_shared(target.room_id, target.turn_id, target.recording_hash)
		if mode != "shared_memories" or view != store_view_generation or owner != _relay_identity() or key != shared_replay_room or not _story_replay_memory_current(): break
	session.invalidate_identity()
	_shared_photo_sync = false
	if mode == "shared_memories" and view == store_view_generation and owner == _relay_identity() and key == shared_replay_room:
		_draw_shared_replay_memories(shared_replays.memories(key, true), controller.last_error)

func _sync_shared_archive() -> void:
	if _shared_archive_sync or _shared_photo_sync or shared_replays == null or shared_replays.busy() or api.busy or relay_session == null or relay_session.busy() or not _relay_identity().ready or not _story_replay_return.is_empty() or not shared_replay_room.begins_with("chapter:") or not _production_replay_key_allowed(shared_replay_room): return
	var key := shared_replay_room
	var owner := _relay_identity()
	var session := relay_session
	_shared_archive_sync = true
	_draw_shared_replay_memories(shared_replays.memories(key, true), "Saving replays…")
	var view := store_view_generation
	var result := {"ok": false}
	if await session.load_capabilities():
		if owner == _relay_identity() and mode == "shared_memories" and key == shared_replay_room and view == store_view_generation:
			result = await session.sync_complete_replay(key.substr(8))
	_shared_archive_sync = false
	if owner == _relay_identity() and mode == "shared_memories" and key == shared_replay_room and view == store_view_generation:
		_draw_shared_replay_memories(shared_replays.memories(key, true), "Saved offline" if result.get("ok", false) else "Could not save replays")

func _open_shared_memory(key: String, row: Dictionary) -> void:
	if shared_replays==null or (shared_replays.busy() and not row.get("cached",false)) or not _relay_identity().ready or is_instance_valid(shared_replay_child) or not _story_replay_memory_current() or not _production_replay_key_allowed(key): return
	if api.busy and not row.get("cached",false): _toast(PlayerCopy.MAIN_6BB9D408ABAB); return
	var view := store_view_generation
	var owner := _relay_identity()
	var entry: Dictionary=await shared_replays.open_memory(key,str(row.id),row)
	if mode!="shared_memories" or view!=store_view_generation or owner!=_relay_identity() or key!=shared_replay_room or not _story_replay_memory_current() or not _production_replay_key_allowed(key): return
	if entry.is_empty(): _toast(shared_replays.last_error); return
	_play_shared_entries([entry])

func _play_shared_entries(entries: Array) -> void:
	if entries.is_empty() or mode != "shared_memories" or not _relay_identity().ready or is_instance_valid(shared_replay_child) or not _story_replay_memory_current() or not _production_replay_key_allowed(shared_replay_room): return
	lifecycle_generation+=1
	foreground_refresh_queued=false
	foreground_response={}
	mode="shared_replay"
	running=false
	_set_world_visible(false)
	ui.visible=false
	soundscape.set_backgrounded(true)
	shared_replay_child=SharedReplayView.new()
	shared_replay_child.entry=entries[0]
	shared_replay_child.sequence=entries
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
	_set_world_visible(true)
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
	_set_world_visible(false)
	ui.visible=false
	soundscape.set_backgrounded(true)
	photo_transfer_child=screen.new(api,_relay_identity,_leave_photo_transfer)
	add_child(photo_transfer_child)

func _leave_photo_transfer() -> void:
	if is_instance_valid(photo_transfer_child):
		remove_child(photo_transfer_child)
		photo_transfer_child.queue_free()
	photo_transfer_child=null
	_set_world_visible(true)
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
	var settings_list := _scroll_list(card)
	settings_list.get_parent().custom_minimum_size.y = clampf(overlay.size.y-220.0,180.0,420.0)
	var display_links := HBoxContainer.new()
	display_links.add_theme_constant_override("separation",10)
	settings_list.add_child(display_links)
	for entry: Array in [["Graphics",_show_graphics_settings],["Notifications",_show_notification_settings]]:
		var link := _list_button(entry[0],entry[1],false)
		link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		display_links.add_child(link)
	for entry in [["assistance","Forgiving catches"],["reduced_motion","Reduce motion"],["left_handed",PlayerCopy.MAIN_A1E007823FF0],["sound","Sound"],["haptics","Gentle haptics"],["photo_prompts",PlayerCopy.MAIN_289D745F1246],["share_online_status","Share online status"]]:
		var toggle := CheckButton.new()
		toggle.text=entry[1]
		toggle.mouse_filter = Control.MOUSE_FILTER_PASS
		toggle.button_pressed=bool(saves.data.settings.get(entry[0],true))
		toggle.toggled.connect(func(value: bool):
			var next: Dictionary = saves.data.settings.duplicate(true)
			next[entry[0]] = value
			if not saves.update_values({"settings": next}):
				toggle.set_pressed_no_signal(bool(saves.data.settings.get(entry[0], true)))
				_toast(PlayerCopy.MAIN_34B82590B663)
				return
			_apply_settings())
		settings_list.add_child(toggle)
	for group: Array in [[["Account & recovery",_show_account],["Tester code",_show_tester_access]],[["Community & privacy",_open_safety],["Licenses",_show_licenses]]]:
		var links := HBoxContainer.new()
		links.add_theme_constant_override("separation",10)
		settings_list.add_child(links)
		for entry: Array in group:
			var link := _button(entry[0],entry[1],false)
			link.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			links.add_child(link)
	card.add_child(_button("Done",_story_settings_done,false))

func _show_graphics_settings() -> void:
	running = false
	mode = "graphics_settings"
	var card := _card()
	card.add_child(_label("Graphics",34,CREAM,true))
	var selected := GraphicsPolicy.normalize(saves.data.settings.get("graphics_quality"))
	var group := ButtonGroup.new()
	for quality: String in GraphicsPolicy.QUALITIES:
		var option := _button(quality.capitalize(),func(): _set_graphics_quality(quality),false)
		option.toggle_mode = true
		option.button_group = group
		option.button_pressed = quality == selected
		option.set_meta("graphics_quality",quality)
		card.add_child(option)
	card.add_child(_button("Back",_show_settings,false))

func _set_graphics_quality(quality: String) -> void:
	if mode != "graphics_settings" or quality not in GraphicsPolicy.QUALITIES: return
	var next: Dictionary = saves.data.settings.duplicate(true)
	next.graphics_quality = quality
	if not saves.update_values({"settings":next}):
		_toast(PlayerCopy.MAIN_34B82590B663)
		_show_graphics_settings()
		return
	_apply_settings()

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
	GraphicsPolicy.apply(world,saves.data.settings)
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
	_layout_hint()

func _show_paywall(manual_store: bool = false, story_return: Dictionary = {}) -> void:
	running=false
	mode="paywall"
	_story_store_return = story_return.duplicate(true) if CampaignCatalog.PRODUCTION_ENABLED else {}
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
		_load_store.call_deferred()
	if not key.is_empty() and purchases.is_available():
		card.add_child(_button("Retry store",func(): _load_store(true),false))
		card.add_child(_button("Restore purchases",_restore_store,false))
	_add_store_back(card)

func _add_store_back(card: VBoxContainer, primary: bool = false) -> void:
	var view := store_view_generation
	card.add_child(_button("Return to Story" if CampaignCatalog.PRODUCTION_ENABLED and not _story_store_return.is_empty() else "Back to chapters",func():
		if mode == "paywall" and view == store_view_generation: _leave_store(),primary))

func _leave_store() -> void:
	if mode != "paywall": return
	if not CampaignCatalog.PRODUCTION_ENABLED: _story_store_return = {}
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
	if config.get("purchase_mode") == "test_store":
		card.add_child(_paragraph(PlayerCopy.MAIN_38EAC523F08C,740))
	return card

func _hosting_entitled() -> bool:
	# A tester code grants cooperative hosting in every build. In the GitHub Test
	# Store build the one-time purchase only unlocks solo play, so hosting still
	# needs a code there; a real Google Play purchase grants hosting too. Reads
	# cached entitlement only, never a per-screen store query.
	if _tester_active(): return true
	if str(config.get("purchase_mode","")) == "test_store": return false
	return purchases.has_entitlement()

func _show_hosting_locked(chapter_key: String) -> void:
	running = false
	mode = "paywall"
	var descriptor := ChapterRegistry.descriptor(chapter_key)
	var card := _card(760)
	card.name = "HostingLocked"
	var hero := TextureRect.new()
	hero.name = "HostingLockedHero"
	hero.custom_minimum_size = Vector2(0,220)
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hero.texture = ChapterThumbnailCatalog.texture(chapter_key)
	card.add_child(hero)
	card.add_child(_label(str(descriptor.get("title",chapter_key)),32,CREAM,true))
	card.add_child(_label("Full Journey",24,CREAM,true))
	card.add_child(_label("One-time purchase",18,MUTED))
	# "Full Journey is only required for the host. A friend may join by invitation."
	card.add_child(_paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,700))
	if str(config.get("purchase_mode","")) == "test_store":
		# This build's purchase cannot unlock hosting, so point to tester access
		# instead of offering a checkout that would not grant it.
		card.add_child(_paragraph(PlayerCopy.MAIN_FAD34E850ED9,700))
		var code := _button("Tester code",_show_tester_access)
		code.name = "HostingLockedTester"
		card.add_child(code)
	else:
		var unlock: Button
		if _play_store_enabled() and purchases.is_available() and not purchase_package.is_empty():
			# Show the real store price only when the store actually provided one.
			unlock = _button("Unlock Full Journey · "+str(purchase_package.price),_buy_full_journey)
		else:
			unlock = _button("Unlock Full Journey",_show_paywall)
		unlock.name = "HostingLockedUnlock"
		card.add_child(unlock)
		card.add_child(_button("Restore purchases",_restore_store,false))
	card.add_child(_button("Back",_show_rooms,false))

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
	if not CampaignCatalog.PRODUCTION_ENABLED: _story_store_return = {}
	if not _play_store_enabled():
		_show_paywall(tester_store_manual,_story_store_return)
		return
	var card := _card(680)
	card.add_child(_label("Full Journey unlocked.",34,CREAM,true))
	if config.get("purchase_mode") == "test_store":
		card.add_child(_paragraph(PlayerCopy.MAIN_FAD34E850ED9,620))
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
	if store_action_pending or mode != "paywall": return
	_show_store_status(PlayerCopy.MAIN_DD823B20A782)
	store_read_request=""
	var view := store_view_generation
	if not await _ensure_identity():
		if mode == "paywall" and view == store_view_generation:
			_show_store_problem(PlayerCopy.MAIN_5FE98B59E6BA)
		return
	if mode != "paywall" or view != store_view_generation: return
	if store_configured:
		if _store_identity_ready():
			_track_store_read(purchases.refresh_customer_info_fresh() if force_refresh else purchases.refresh_customer_info())
		else: _show_store_problem(PlayerCopy.MAIN_5FE98B59E6BA)
	else:
		_configure_purchases(tester_store_manual)

func _track_store_read(id: String) -> void:
	store_read_request=id
	store_read_views[id]=store_view_generation

func _accept_store_read(id: String) -> bool:
	# Other customer refreshes retain their existing authoritative UI updates.
	if not store_read_views.has(id): return true
	var view: int=store_read_views[id]
	store_read_views.erase(id)
	if id != store_read_request: return false
	store_read_request=""
	return mode == "paywall" and view == store_view_generation and not store_action_pending

func _show_store_status(message: String) -> void:
	var card := _full_journey_card()
	card.add_child(_paragraph(message,600))
	card.add_child(_button("Retry store",func(): _load_store(true),false))
	card.add_child(_button("Restore purchases",_restore_store,false))
	_add_store_back(card)

func _show_store_problem(message: String) -> void:
	if mode != "paywall": return
	_show_store_status(message if not message.is_empty() else "Store unavailable")

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
	if operation in ["get_customer_info","get_offerings"] and not _accept_store_read(id): return
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
			else: _track_store_read(purchases.fetch_offerings())
	elif operation=="get_offerings":
		if mode!="paywall" or store_action_pending or not _store_identity_ready():
			return
		if purchases.has_entitlement():
			_show_full_journey_unlocked()
			return
		purchase_package=Purchases.select_lifetime_offer(payload)
		if purchase_package.is_empty():
			_show_store_problem(PlayerCopy.MAIN_A986D201176A)
			return
		_show_store_offer()
	elif operation=="get_customer_info":
		if mode=="paywall" and not store_action_pending and _store_identity_ready():
			if purchases.has_entitlement(): _show_full_journey_unlocked()
			else: _track_store_read(purchases.fetch_offerings())
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
	if operation in ["get_customer_info","get_offerings"] and not _accept_store_read(id): return
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
	if mode == "paywall" and not store_action_pending and (operation in ["configure","get_customer_info","get_offerings"] or purchase_package.is_empty()):
		_show_store_problem(PlayerCopy.MAIN_B621C76A2638 if cancelled else message)
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
	_friends_hosting = false
	if not api.configured():
		running=false
		mode="rooms"
		var frame := _card(700)
		frame.add_child(_label(PlayerCopy.MAIN_3A4A78824AC3,34,CREAM,true))
		frame.add_child(_paragraph(PlayerCopy.MAIN_C372E9DBD93A))
		frame.add_child(_list_button("Practice on your own",_show_journey))
		frame.add_child(_button("Back",_show_home,false))
		return
	if is_instance_valid(room_hub_screen): return
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available() or not await _ensure_identity(): return
	if view != store_view_generation or lifecycle != lifecycle_generation or application_backgrounded: return
	if not await _prepare_ordinary_navigation(): return
	running=false
	mode="rooms"
	ui.visible=false
	room_inbox = RoomInboxClient.new(api,_relay_identity)
	room_inbox.local = _hub_local_history
	room_hub_screen = RoomHubScreen.new()
	room_hub_screen.client = room_inbox
	var choices: Array[Dictionary] = []
	for key: String in ChapterRegistry.keys():
		var descriptor: Dictionary = ChapterRegistry.descriptor(key)
		choices.append({"key":key,"title":str(descriptor.get("title",key)),"stage_count":int(descriptor.get("stage_count",1))})
	room_hub_screen.set_chapters(choices)
	room_hub_screen.display_name = func(member: String) -> String:
		if member == str(api.player_id): return ""
		return _friend_display_name(member)
	room_hub_screen.thumbnail_for = func(key: String) -> String: return ChapterThumbnailCatalog.path(key)
	room_hub_screen.closed.connect(_close_room_hub)
	room_hub_screen.friends_requested.connect(_open_friends_from_room_hub)
	room_hub_screen.room_open_requested.connect(_open_room_from_hub)
	room_hub_screen.host_requested.connect(_host_from_room_hub)
	room_hub_screen.join_code_requested.connect(_join_from_room_hub)
	add_child(room_hub_screen)
	room_hub_screen.refresh()

func _hub_local_history() -> Array:
	# Hosted and joined rooms the player already reached this session, mapped
	# into the inbox room shape so the hub lists them even while the inbox
	# endpoint is unavailable. Turn state is unknown without the inbox, so a
	# live room is shown as openable without claiming it is the player's turn.
	var rooms: Array = []
	if relay_session == null or not _relay_identity().ready: return rooms
	var me := str(api.player_id)
	for summary: Dictionary in relay_session.room_summaries():
		var role := str(summary.get("active_role",""))
		rooms.append({
			"api_version": 2,
			"room_id": str(summary.get("room_id","")),
			"chapter_key": _hub_history_chapter(summary),
			"chapter_title": str(summary.get("title","Saved chapter")),
			"member_ids": [me],
			"status": "completed" if role == "complete" else "waiting_for_their_turn",
			"revision": 0,
			"remote_activity_sequence": 0,
			"activity_at": 0,
			"family": "relay",
		})
	return rooms

func _hub_history_chapter(summary: Dictionary) -> String:
	var title := str(summary.get("title",""))
	for key: String in ChapterRegistry.keys():
		if str(ChapterRegistry.descriptor(key).get("title","")) == title: return key
	return "unknown"

func _friend_display_name(friend: String) -> String:
	## One place to turn a friend's player id into the name shown on screen:
	## their local nickname when set, otherwise the short friend code.
	if friend.is_empty(): return ""
	var fallback := friend.substr(0,8)
	if friend_nicknames == null: return fallback
	return friend_nicknames.display_name(str(api.base_url),str(api.player_id),friend,fallback)

func _close_room_hub() -> void:
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true
	_show_home()

func _open_friends_from_room_hub() -> void:
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	# The Friends screen returns to this hub because mode remains "rooms".
	_show_friends()

func _open_room_from_hub(room: Dictionary) -> void:
	if mode != "rooms" or not _relay_identity().ready: return
	var version := int(room.get("api_version",0))
	var room_id := str(room.get("room_id",""))
	if room_id.is_empty(): return
	var inbox: RefCounted = room_inbox
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	ui.visible = true
	if room.get("status") == "completed":
		# Completed rooms open their exact shared replay.
		open_shared_replay_room(room_id)
		return
	if version == 2:
		await _relay_lobby_action("open",room_id)
		if mode == "relay_online" and relay_session != null and relay_session.coordinator != null and relay_session.coordinator.snapshot().get("room_id") == room_id:
			if inbox != null: inbox.confirm_room_rendered(2,room_id)
	elif version == 1:
		await _open_friend_legacy(room_id)
		if mode == "room" and active_room.get("room_id") == room_id:
			if inbox != null: inbox.confirm_room_rendered(1,room_id)
	else:
		_toast("This room can't be opened on this version of After You.")

func _host_from_room_hub(chapter_key: String, visibility: String) -> void:
	if mode != "rooms" or not _relay_identity().ready: return
	if ChapterRegistry.descriptor(chapter_key).get("premium",false) and not _hosting_entitled():
		# Hosting a paid island needs the Full Journey; show how to unlock it
		# before entering the lobby. Never auto-create a room afterwards.
		if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
		room_hub_screen = null
		room_inbox = null
		ui.visible = true
		_show_hosting_locked(chapter_key)
		return
	selected_online_chapter = chapter_key
	room_hub_host_visibility = visibility
	_friends_hosting = false
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true
	await _show_relay_rooms(chapter_key)
	if mode != "relay_rooms" or relay_session == null: return
	if relay_session.supports_creation(chapter_key):
		await _relay_lobby_action("create",chapter_key)
	else:
		# The existing lobby explains whether this is an access or server limitation.
		_draw_relay_lobby(relay_session.last_error)

func _join_from_room_hub(code: String) -> void:
	if mode != "rooms" or not _relay_identity().ready: return
	if api.busy or not await _prepare_ordinary_navigation(): return
	var context := _friends_route_context()
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST,"/v1/invitations/resolve",{"invite_code":code})
	if not _friends_route_current(context): return
	if not response.get("ok",false):
		if int(response.get("status",0)) in [0,404,405,501]:
			# The resolver is not deployed yet. Fall back to the existing modern
			# join; the visible invitation field remains a single mutating call.
			if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
			room_hub_screen = null
			room_inbox = null
			ui.visible = true
			await _join_chapter_room(code)
			return
		_toast(str(response.get("error","Invitation unavailable")))
		return
	var data: Variant = response.get("data")
	if not data is Dictionary or data.size() != 3 or data.get("schema_version") != 1 or data.get("family") not in ["legacy","relay"] or data.get("api_version") not in [1,2]:
		_toast("Invitation unavailable")
		return
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true
	if data.api_version == 2:
		await _join_chapter_room(code)
	else:
		await _join_room(code)

func _show_friends() -> void:
	var from_home := mode == "home"
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available() or not await _ensure_identity(): return
	if view != store_view_generation or lifecycle != lifecycle_generation or application_backgrounded or is_instance_valid(friends_screen): return
	_friends_hosting = false
	_friends_return_home = from_home
	# Friends is a full-screen takeover. Release the room hub so it cannot sit
	# behind the Friends layer and intercept input while Friends is open.
	if is_instance_valid(room_hub_screen):
		room_hub_screen.queue_free()
		room_hub_screen = null
		room_inbox = null
	if friends_client == null: friends_client = FriendsClient.new(api,_relay_identity)
	if friend_room_events == null: friend_room_events = FriendRoomEventsClient.new(api,_relay_identity)
	var shareable := {}
	var current := _friend_current_room()
	var title := ""
	if current.get("api_version") == 2:
		var room: Dictionary = relay_session.coordinator.snapshot()
		title = str(ChapterRegistry.descriptor(relay_session.chapter_key()).get("title","Current room"))
		if room.get("host_id") == api.player_id: shareable = current.duplicate(true)
	elif current.get("api_version") == 1:
		title = str(Levels.get_level(str(active_room.get("level_id",""))).get("title","Current room"))
		if active_room.get("host_id") == api.player_id: shareable = current.duplicate(true)
	running = false
	mode = "friends"
	_sync_presence()
	ui.visible = false
	friends_screen = FriendsScreen.new()
	friends_screen.client = friends_client
	friends_screen.event_client = friend_room_events
	friends_screen.nickname_store = friend_nicknames
	friends_screen.shareable_room = shareable
	friends_screen.room_title = title
	if not current.is_empty():
		var snapshot: Dictionary = relay_session.coordinator.snapshot() if current.get("api_version") == 2 else active_room
		friends_screen.room_status = "Waiting for friend" if snapshot.get("guest_id") == null else "Friend joined"
	friends_screen.openable_room = not current.is_empty()
	friends_screen.closed.connect(_leave_friends)
	friends_screen.host_requested.connect(_host_friend_room)
	friends_screen.open_requested.connect(_return_to_friend_room)
	friends_screen.join_requested.connect(_join_friend_room)
	add_child(friends_screen)

func _friend_current_room() -> Dictionary:
	if not _relay_identity().ready: return {}
	var room := {}
	if friend_share_target.get("api_version") == 2 and relay_session != null and relay_session.coordinator != null:
		if relay_session.coordinator.campaign_scoped() or relay_session.coordinator.campaign_recovery_only(): return {}
		room = relay_session.coordinator.snapshot()
	elif friend_share_target.get("api_version") == 1:
		room = active_room
	if room.get("room_id") != friend_share_target.get("room_id") or api.player_id not in [room.get("host_id"),room.get("guest_id")]: return {}
	return friend_share_target.duplicate(true)

func _current_room_share_allowed(target: Dictionary) -> bool:
	if application_backgrounded or not _relay_identity().ready or not FriendsClient._room(target): return false
	var room := {}
	if target.api_version == 2:
		if mode != "relay_online" or not is_instance_valid(relay_child) or relay_session == null or relay_session.coordinator == null or relay_child.journey != relay_session.coordinator: return false
		if relay_session.coordinator.campaign_scoped() or relay_session.coordinator.campaign_recovery_only(): return false
		room = relay_session.coordinator.snapshot()
	elif target.api_version == 1:
		if mode != "room": return false
		room = active_room
	return room.get("room_id") == target.room_id and room.get("host_id") == api.player_id

func _share_current_room(target: Dictionary) -> Dictionary:
	if _room_share_busy or api.busy or not _current_room_share_allowed(target): return {"ok": false, "message": "Room unavailable"}
	if friends_client == null: friends_client = FriendsClient.new(api,_relay_identity)
	if friends_client.busy: return {"ok": false, "message": "Friends unavailable"}
	var context := _friends_route_context()
	_room_share_busy = true
	var okay: bool = await friends_client.share_room(target)
	_room_share_busy = false
	if not _friends_route_current(context) or not _current_room_share_allowed(target): return {"ok": false, "ignored": true}
	return {"ok": okay, "message": "Shared with friends" if okay else friends_client.last_error}

func _add_current_room_share(card: VBoxContainer) -> void:
	var target := {"api_version": 1, "room_id": active_room.get("room_id", "")}
	if not _current_room_share_allowed(target): return
	var status := _label("All friends",17)
	var button := _list_button("Share current room",func(): _share_room_from_card(target, card, status),false)
	button.name = "ShareCurrentRoom"
	button.disabled = _room_share_busy or api.busy
	card.add_child(button)
	card.add_child(status)

func _share_room_from_card(target: Dictionary, card: VBoxContainer, status: Label) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree(): return
	var button: Button = card.get_node("ShareCurrentRoom")
	button.disabled = true
	var result := await _share_current_room(target)
	if not is_instance_valid(card) or not card.is_inside_tree() or not _current_room_share_allowed(target) or result.get("ignored", false): return
	button.disabled = false
	status.text = str(result.get("message", "Friends unavailable"))

func _friends_route_context() -> Dictionary:
	return {"view":store_view_generation,"lifecycle":lifecycle_generation,"identity":_tester_context(),"mode":mode}

func _friends_route_current(context: Dictionary) -> bool:
	return not application_backgrounded and _relay_identity().ready and context == _friends_route_context()

func _host_friend_room() -> void:
	if mode != "friends" or application_backgrounded or not _relay_identity().ready: return
	mode = "rooms"
	ui.visible = true
	_show_rooms()

func _return_to_friend_room() -> void:
	if mode != "friends" or application_backgrounded: return
	var target := _friend_current_room()
	if target.is_empty(): return
	mode = "rooms"
	ui.visible = true
	if target.api_version == 2: _relay_lobby_action("open",target.room_id)
	else: _open_friend_legacy(target.room_id)

func _back_from_friend_host() -> void:
	relay_menu_generation += 1
	_friends_hosting = false
	_show_friends()

func _open_friend_legacy(room_id: String) -> void:
	if not _relay_available() or not _legacy_redo_navigation_ready(room_id): return
	if not await _prepare_ordinary_navigation(): return
	if relay_session != null and not relay_session.can_leave_for_legacy(): return
	var context := _friends_route_context()
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id)
	if _friends_route_current(context): _accept_room(response)

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
		var room_id := str(descriptor.get("room_id",""))
		if relay_session != null and (room_id in relay_session.room_ids() or (relay_session.coordinator != null and relay_session.coordinator.snapshot().get("room_id") == room_id)):
			_relay_lobby_action("open",room_id)
		else:
			var generation := relay_menu_generation+1
			var lifecycle := lifecycle_generation
			var identity := _tester_context()
			await _show_relay_rooms()
			if generation != relay_menu_generation or mode != "relay_rooms" or lifecycle != lifecycle_generation or application_backgrounded or identity != _tester_context() or relay_session == null: return
			if room_id in relay_session.room_ids(): _relay_lobby_action("open",room_id)
			else: _relay_lobby_action("join",str(descriptor.get("invite_code","")))
	elif descriptor.get("api_version") == 1:
		var room_id := str(descriptor.get("room_id",""))
		var saved: Dictionary = saves.data.get("room",{})
		if saved.get("room_id") == room_id and api.player_id in [saved.get("host_id"),saved.get("guest_id")]: _open_friend_legacy(room_id)
		else: _join_room(str(descriptor.get("invite_code","")))

func _relay_identity() -> Dictionary:
	return {"ready": api != null and not identity_loading and not identity_busy and not identity_restart_required and pending_recovery.is_empty() and identity_read_state==IdentityReadState.LOADED and not api.player_id.is_empty() and not api.device_token.is_empty(), "player_id": str(api.player_id) if api != null else "", "epoch": relay_identity_epoch}

func _new_relay_session() -> RefCounted:
	if shared_replays == null: shared_replays = SharedReplays.new(api,_relay_identity)
	var session := RelayOnline.new(api,_relay_identity)
	session.accepted_pair_cache = shared_replays.cache_accepted_receipt
	session.replay_archive_cache = shared_replays.cache_transferred_entries
	return session

func _invalidate_relay_identity(clear_notifications: bool = true) -> void:
	_shared_archive_attempts.clear()
	# A returning Main re-reads the same credentials before reusing its session.
	# Recovery/deletion clear authority; ordinary identity loading only holds it.
	Purchases.suspend_session(clear_notifications)
	_story_store_return = {}
	_campaign_generation += 1
	_campaign_action_busy = false
	if is_instance_valid(campaign_flow): campaign_flow.invalidate()
	if campaign_owner != null: campaign_owner.invalidate_identity()
	friend_share_target = {}
	_friends_hosting = false
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
	if friend_room_events != null: friend_room_events.invalidate()
	if is_instance_valid(room_hub_screen):
		room_hub_screen.queue_free()
		room_hub_screen = null
		room_inbox = null
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
	# The room hub needs a ready identity, so a stale redo panel returns Home.
	if had_redo_screen and mode == "redo_requests": _show_home()

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
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available() or not await _ensure_identity():
		return
	if view != store_view_generation or lifecycle != lifecycle_generation or application_backgrounded: return
	if not await _prepare_ordinary_navigation(): return
	if relay_session == null:
		relay_session = _new_relay_session()
	running = false
	mode = "relay_rooms"
	relay_menu_generation += 1
	var generation := relay_menu_generation
	_draw_relay_lobby(PlayerCopy.MAIN_07713E9CC81E, true)
	var context := _friends_route_context()
	await relay_session.load_lobby()
	if generation != relay_menu_generation or not _friends_route_current(context):
		return
	_draw_relay_lobby(relay_session.last_error)

func _draw_relay_lobby(message: String = "", loading: bool = false) -> void:
	mode = "relay_rooms"
	var frame := _card(minf(1040.0,maxf(280.0,ui.size.x-48.0)),true)
	frame.name = "RelayLobbyLayout"
	var chosen := ChapterRegistry.descriptor(selected_online_chapter)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",16)
	frame.add_child(header)
	var heading := _label("Host a room" if _friends_hosting else "Play together",36,CREAM,true)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var refresh := _list_button("",_show_relay_rooms,false)
	refresh.icon = preload("res://assets/ui/social/arrows-clockwise.svg")
	refresh.expand_icon = true
	refresh.custom_minimum_size = Vector2(48,48)
	refresh.add_theme_constant_override("icon_max_width",24)
	refresh.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fit_icon_button(refresh)
	refresh.add_theme_color_override("icon_normal_color",CREAM)
	refresh.tooltip_text = "Refresh availability and rooms"
	refresh.accessibility_name = refresh.tooltip_text
	refresh.disabled = loading
	header.add_child(refresh)
	if not message.is_empty(): frame.add_child(_paragraph(message,0))
	var columns := BoxContainer.new()
	columns.name = "RelayLobbyColumns"
	columns.add_theme_constant_override("separation",18)
	frame.add_child(columns)
	var chapter := _relay_lobby_section(columns,true)
	chapter.get_parent().size_flags_stretch_ratio = 1.12
	chapter.add_child(_label("YOUR NEXT CHAPTER",17,MUTED))
	if loading:
		chapter.add_child(_paragraph(PlayerCopy.MAIN_6DC16645A479,0))
	else:
		var enabled: bool = relay_session.mutations_enabled()
		var choices := OptionButton.new()
		choices.custom_minimum_size.y = 48
		choices.fit_to_longest_item = false
		choices.clip_text = true
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
		chapter.add_child(choices)
		var chapter_title := _label(str(chosen.title) + ", together.",30,CREAM,true)
		chapter_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		chapter.add_child(chapter_title)
		chapter.add_child(_paragraph(str(chosen.summary),0))
		if chosen.get("premium", false): chapter.add_child(_paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,0))
		if not relay_session.supports_creation(selected_online_chapter):
			chapter.add_child(_paragraph(PlayerCopy.MAIN_73FEF220EAF1,0))
		var room_actions := _relay_lobby_section(columns)
		room_actions.add_child(_label("HAVE AN INVITATION?",17,MUTED))
		var pending: Dictionary = relay_session.pending_lobby()
		if not pending.is_empty():
			var retry := _list_button("Retry saved create / join request",func(): _relay_lobby_action("retry"))
			retry.add_theme_font_size_override("font_size",18)
			retry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			retry.tooltip_text = retry.text
			retry.disabled = not enabled
			chapter.add_child(retry)
			room_actions.add_child(_paragraph("Complete the saved request before entering another room.",0))
		else:
			var selected := selected_online_chapter
			var create := _list_button("Create this chapter",func(): _relay_lobby_action("create",selected))
			create.disabled = not relay_session.supports_creation(selected)
			chapter.add_child(create)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation",10)
			room_actions.add_child(row)
			var code := LineEdit.new()
			code.placeholder_text = "Chapter invitation code"
			code.max_length = 40
			code.custom_minimum_size = Vector2(120,50)
			code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			code.add_theme_font_size_override("font_size",18)
			row.add_child(code)
			var join := _list_button("Join",func(): _relay_lobby_action("join",code.text),false)
			join.custom_minimum_size.x = 82
			join.disabled = not enabled
			row.add_child(join)
		var practice := _list_button("Practice this chapter solo",_open_selected_chapter_solo,false)
		practice.add_theme_font_size_override("font_size",18)
		chapter.add_child(practice)
		if _friends_hosting:
			var earlier := _list_button("Host an earlier island",_create_room,false)
			earlier.add_theme_font_size_override("font_size",18)
			chapter.add_child(earlier)
		var rooms: Array = relay_session.room_ids()
		if not rooms.is_empty():
			room_actions.add_child(_label("RECENT ROOMS",17,MUTED))
			var list := VBoxContainer.new()
			list.add_theme_constant_override("separation",8)
			room_actions.add_child(list)
			for index in range(rooms.size()):
				var room_id: String = rooms[index]
				var saved := _list_button("%s %d%s" % [relay_session.room_title(room_id),index+1," · last opened" if room_id==relay_session.last_room() else ""],func(): _relay_lobby_action("open",room_id),false)
				saved.add_theme_font_size_override("font_size",18)
				saved.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				saved.tooltip_text = saved.text
				list.add_child(saved)
		var pending_redo: String = relay_session.pending_redo_room()
		if not pending_redo.is_empty() and pending_redo not in rooms:
			room_actions.add_child(_list_button("Retry request",func(): _relay_lobby_action("open",pending_redo),false))
	var footer := HBoxContainer.new()
	# Keep navigation available even when a long room list needs scrolling.
	var scroll := frame.get_parent() as ScrollContainer
	var margin := scroll.get_parent()
	margin.remove_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",14)
	margin.add_child(body)
	body.add_child(scroll)
	body.add_child(footer)
	scroll.set_meta("footer_reserve",70.0)
	var back: Button
	if _friends_hosting: back = _button("Back",_back_from_friend_host,false)
	else: back = _button("Back",func(): relay_menu_generation+=1; _show_rooms(),false)
	back.custom_minimum_size.x = 128
	footer.add_child(back)
	var layout := func(): _layout_relay_lobby(frame,columns)
	overlay.resized.connect(layout)
	frame.tree_exiting.connect(func():
		if overlay.resized.is_connected(layout): overlay.resized.disconnect(layout))
	layout.call()

func _relay_lobby_section(parent: Node, prominent: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := _style(Color("1c4941") if prominent else Color("143832"),18,Color("51786a") if prominent else Color("3c6257"))
	for edge: String in ["left","top","right","bottom"]: style.set("content_margin_"+edge,20)
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",14)
	panel.add_child(stack)
	return stack

func _layout_relay_lobby(frame: VBoxContainer, columns: BoxContainer) -> void:
	if not is_instance_valid(frame) or not frame.is_inside_tree(): return
	var panel: Control = frame.get_parent()
	while not panel is PanelContainer: panel = panel.get_parent()
	panel.custom_minimum_size.x = minf(1040.0,maxf(280.0,ui.size.x-48.0))
	columns.vertical = ui.size.x < 840.0
	_layout_bounded_card.call_deferred()

func _open_selected_chapter_solo() -> void:
	_friends_hosting = false
	if selected_online_chapter == ChapterRegistry.FIRST_STEPS: _open_first_steps()
	elif selected_online_chapter == ChapterRegistry.RELAY: _open_relay_preview()
	elif ChapterRegistry.is_cooperative(selected_online_chapter): _open_cooperative_preview(selected_online_chapter)

func _relay_lobby_action(action: String, value: String = "") -> void:
	if relay_session == null or relay_session.busy() or not _relay_available() or not _relay_identity().ready:
		return
	if not _legacy_redo_navigation_ready(): return
	if not await _prepare_ordinary_navigation(): return
	relay_menu_generation += 1
	var generation := relay_menu_generation
	var hosting_create: bool = _friends_hosting and (action == "create" or (action == "retry" and relay_session.pending_lobby().get("path") == "/v2/rooms"))
	_draw_relay_lobby(PlayerCopy.MAIN_6734074E99D4,true)
	var context := _friends_route_context()
	var room_id := ""
	match action:
		"create": room_id = await relay_session.create_room(value)
		"join": room_id = await relay_session.join_room(value)
		"retry": room_id = await relay_session.retry_lobby()
		"open":
			await relay_session.open_room(value)
			if relay_session.coordinator != null and relay_session.coordinator.snapshot().get("room_id", "") == value:
				room_id = value
	if generation != relay_menu_generation or not _friends_route_current(context):
		return
	if room_id.is_empty():
		_draw_relay_lobby(relay_session.last_error)
		return
	if action == "create" and room_hub_host_visibility == "friends":
		_publish_room_availability.call_deferred({"api_version":2,"room_id":room_id})
	if hosting_create:
		friend_share_target = {"api_version":2,"room_id":room_id}
		await _show_friends()
		return
	_friends_hosting = false
	_enter_online_relay()

func _publish_room_availability(room: Dictionary) -> void:
	if not _relay_identity().ready or not FriendRoomEventsClient.valid_room(room): return
	if friend_room_events == null: friend_room_events = FriendRoomEventsClient.new(api,_relay_identity)
	# A delivery failure must never undo or delay the successful room creation.
	var deadline := Time.get_ticks_msec() + 5000
	while api.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _relay_identity().ready: return
	await friend_room_events.publish(room)

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
	_set_world_visible(false)
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
	relay_child.share_current_room = _share_current_room
	relay_child.closed.connect(_leave_online_relay)
	add_child(relay_child)
	_sync_presence()

func _replace_campaign_relay_child(source: Node, generation: int, target_room: String,
		target_index: int, flow: Node, owner: RefCounted, on_story_closed: Callable) -> Node:
	if not CampaignCatalog.PRODUCTION_ENABLED: return null
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
	_set_world_visible(true)
	ui.visible = true
	soundscape.set_backgrounded(application_backgrounded)
	lifecycle_generation += 1
	mode = "relay_rooms"
	_sync_presence()
	_draw_relay_lobby(relay_session.last_error if relay_session != null else "")
	_deliver_completed_replay.call_deferred()

func _deliver_completed_replay() -> void:
	# One transfer attempt after leaving completed play, never a playback/tick
	# poll. A user can retry explicitly from Shared Replays after an interruption.
	if _shared_archive_sync or relay_session == null or relay_session.coordinator == null or not _relay_identity().ready or mode != "relay_rooms" or application_backgrounded: return
	var session := relay_session
	var owner := _relay_identity()
	var room: Dictionary = session.coordinator.snapshot()
	if room.get("active_role") != "complete" or session.capabilities.get("replay_transfer_version") != 1 or not session.standalone_room_proven(str(room.get("room_id", ""))): return
	var key := str(owner.player_id) + ":" + str(room.room_id) + ":" + str(room.revision)
	if _shared_archive_attempts.has(key): return
	var deadline := Time.get_ticks_msec() + 2000
	while (api.busy or session.busy()) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
		if owner != _relay_identity() or mode != "relay_rooms" or application_backgrounded: return
	if owner != _relay_identity() or session != relay_session or session.coordinator == null or not session.coordinator.pending().is_empty() or not SharedReplays.Canonical.same(session.coordinator.snapshot(), room) or api.busy or session.busy(): return
	_shared_archive_attempts[key] = true
	_shared_archive_sync = true
	await session.sync_complete_replay(str(room.room_id))
	_shared_archive_sync = false

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
	var navigation := _friends_route_context()
	if not _relay_available() or not await _ensure_identity(): return
	if navigation.view != store_view_generation or navigation.lifecycle != lifecycle_generation or application_backgrounded: return
	if not _legacy_redo_navigation_ready(): return
	if not await _prepare_ordinary_navigation(): return
	if not relay_session.can_leave_for_legacy():
		_toast(relay_session.last_error)
		return
	var context := _friends_route_context()
	var return_to_friends := _friends_hosting
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms",{"idempotency_key":RoomsApi.new_key(),"simulation_version":Simulation.COMFORT_SIMULATION_VERSION})
	if not _friends_route_current(context): return
	_accept_room(response,return_to_friends)

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
	var navigation := _friends_route_context()
	if code.strip_edges().is_empty() or not _relay_available() or not await _ensure_identity():
		return
	if navigation.view != store_view_generation or navigation.lifecycle != lifecycle_generation or application_backgrounded: return
	if not _legacy_redo_navigation_ready(): return
	if not await _prepare_ordinary_navigation(): return
	if relay_session == null:
		relay_session=_new_relay_session()
	if not relay_session.can_leave_for_legacy():
		_toast(relay_session.last_error)
		return
	var context := _friends_route_context()
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/join",{"invite_code":code.strip_edges(),"simulation_version":Simulation.COMFORT_SIMULATION_VERSION})
	if _friends_route_current(context): _accept_room(response)

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

func _accept_room(response: Dictionary, return_to_friends: bool = false) -> void:
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
	if return_to_friends:
		_show_friends()
		return
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
	if _relay_identity().ready and active_room.get("host_id") == api.player_id:
		var friend_status := _label("Waiting for friend" if active_room.get("guest_id") == null else "Friend joined",20)
		friend_status.name = "RoomFriendStatus"
		card.add_child(friend_status)
	_add_current_room_share(card)
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
	if client.can_accept(): _announce_redo_request.call_deferred(client,str(active_room.get("room_id","")),_open_legacy_redo)

func _announce_redo_request(client: RefCounted, room_id: String, review: Callable) -> void:
	## A friend's redo request is easy to miss as a button label, so show it once
	## per request in the shared pop-up. Not now leaves the request waiting.
	if not is_inside_tree() or running or is_instance_valid(_redo_request_modal) or not client.can_accept(): return
	var request: Variant = client.view().get("request")
	if not request is Dictionary: return
	var key := room_id + ":" + str(request.get("request_id",JSON.stringify(request)))
	if _announced_redo_requests.has(key): return
	_announced_redo_requests[key] = true
	_redo_request_modal = InGameModal.open(ui,"RedoRequestModal","Redo requested")
	_redo_request_modal.label(REDO_REQUEST_BODY)
	var open: Button = _redo_request_modal.add_actions("Review request",func():
		if is_instance_valid(_redo_request_modal): _redo_request_modal.close(false)
		_redo_request_modal = null
		review.call(),"Not now")
	open.grab_focus()

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
	var card := _card(560.0,true)
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
	_bounded_card_scroll.set_meta("footer_reserve",70.0)
	_bounded_card_footer.add_child(_button("Back",_show_settings,false))

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
		if config.get("purchase_mode") == "test_store":
			card.add_child(_paragraph(PlayerCopy.MAIN_FAD34E850ED9))
			card.add_child(_button("Tester code",_show_tester_access,false))
		elif _play_store_enabled():
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

func _confirm_delete_identity(message: String="") -> void:
	if identity_busy or deletion_cleanup_busy: return
	running=false
	mode="account"
	var card := _card()
	card.add_child(_label(PlayerCopy.MAIN_4335B260B3E1,30,CREAM,true))
	card.add_child(_paragraph(PlayerCopy.MAIN_6FD20F7D08FA))
	if not message.is_empty(): card.add_child(_paragraph(message))
	card.add_child(_button("Delete identity and shared rooms",_delete_identity))
	card.add_child(_button("Keep my identity",_show_account,false))

func _delete_identity() -> void:
	if identity_busy or api.busy or not await _ensure_identity():
		return
	_invalidate_relay_identity()
	identity_busy = true
	running=false
	mode="identity_deleting"
	var card := _card()
	card.add_child(_label("Deleting online identity…",30,CREAM,true))
	var activity := ProgressBar.new()
	activity.name="IdentityDeletionActivity"
	activity.custom_minimum_size.y=14
	activity.show_percentage=false
	activity.indeterminate=not bool(saves.data.settings.get("reduced_motion",false))
	card.add_child(activity)
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_DELETE,"/v1/identity")
	if not response.ok:
		identity_busy = false
		_confirm_delete_identity(str(response.error))
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
	friend_nicknames.clear_owner(owner, api.base_url)
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
	if not await _prepare_ordinary_navigation(): return
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

func _scroll_list(card: VBoxContainer, scrolling: bool=true) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",10)
	if scrolling:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size=Vector2(600,270)
		card.add_child(scroll)
		scroll.add_child(list)
	else:
		card.add_child(list)
	return list

static func _parse_json(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text)==OK else null

func _set_world_visible(value: bool) -> void:
	if is_instance_valid(world):
		world.visible = value
	_sync_world_processing()

func _sync_world_processing() -> void:
	if not is_instance_valid(world):
		_suspended_world_id = 0
		return
	var world_id := world.get_instance_id()
	if application_backgrounded or not world.visible:
		if _suspended_world_id != world_id:
			_suspended_world_id = world_id
			_world_was_processing = world.is_processing()
		world.set_process(false)
	elif _suspended_world_id == world_id:
		world.set_process(_world_was_processing)
		_suspended_world_id = 0
	else:
		_suspended_world_id = 0

func _foreground_refresh_safe() -> bool:
	# A paused rehearsal is still active work. Do not swap its source recording,
	# revision or review screen behind the player's back.
	return not is_instance_valid(relay_child) and not application_backgrounded and not running and not submission_in_flight and mode in ["home","rooms","room","journey","collection","settings","saved"]

func _background_application() -> void:
	if application_backgrounded:
		return
	application_backgrounded=true
	_sync_world_processing()
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
	_sync_world_processing()
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
	_service_collection_replay()
	_service_solo_collection()
	_service_shared_replays()
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
		if mode == "identity_deleting" or deletion_cleanup_busy: return
		if mode == "collection_loading": _show_collection()
		elif mode == "story_lobby": _story_back()
		elif mode == "story_access": _draw_story_lobby()
		elif mode == "paywall" and not _story_store_return.is_empty(): _leave_store()
		elif mode in ["confirm_retry", "confirm_restart", "confirm_delete_replay"]:
			if _retry_cancel.is_valid(): _retry_cancel.call()
		elif mode == "story_replay_chapters": _return_story_replay_lobby()
		elif mode == "shared_memories" and not _story_replay_return.is_empty(): _back_to_story_replay_chapters()
		elif running or mode=="completion":
			_pause()
		elif mode=="license_text":
			_show_licenses()
		elif mode in ["licenses", "tester_access", "graphics_settings"]:
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
	_cancel_collection_replay()
	if _collection_replay_worker != null and _collection_replay_worker.is_started():
		_collection_replay_worker.wait_to_finish()
		_collection_replay_worker=null
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return []
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
	if relay_session == null: relay_session = _new_relay_session()
	if campaign_owner == null:
		var definitions: Array = []
		if CampaignCatalog.PRODUCTION_ENABLED:
			var pairs := _campaign_pairs()
			if pairs.size() != campaign_catalog.size(): return false
			for pair: Dictionary in pairs: definitions.append(pair.definition)
		else:
			definitions = CampaignCatalog.compatibility_definitions()
			if definitions.is_empty(): return false
		campaign_owner = CampaignOwner.new(relay_session,_relay_identity,definitions,_campaign_leave_ready)
	if not CampaignCatalog.PRODUCTION_ENABLED: campaign_owner.archive_story_runtime()
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
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

func _prepare_ordinary_navigation() -> bool:
	if not _campaign_depart_for_ordinary() or relay_session == null: return false
	var session: RefCounted = relay_session
	var context := {"view":store_view_generation,"lifecycle":lifecycle_generation,"identity":_tester_context(),"mode":mode}
	var prepared: bool = await session.prepare_archived_navigation()
	if relay_session != session or application_backgrounded or not _relay_identity().ready or context != {"view":store_view_generation,"lifecycle":lifecycle_generation,"identity":_tester_context(),"mode":mode}: return false
	if not prepared: _toast(session.last_error)
	return prepared

func _campaign_depart_for_ordinary() -> bool:
	if not _campaign_recovery_context.is_empty(): return false
	# Local solo remains available without an online identity. A previously loaded
	# owner, however, cannot be discarded merely because identity is now unsettled.
	if not _relay_identity().ready:
		return campaign_owner == null
	if not _prepare_campaign_owner():
		_toast(PlayerCopy.MAIN_6DE42F59590C if campaign_owner != null and campaign_owner.read_only else PlayerCopy.MAIN_52C04F6029F5)
		return false
	if not CampaignCatalog.PRODUCTION_ENABLED: return campaign_owner.ordinary_entry_allowed()
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return campaign_owner.ordinary_entry_allowed()
	return campaign_owner.bound_campaign().is_empty() and campaign_owner.pending_lobby().is_empty() and campaign_owner.can_leave()

func _campaign_visible() -> bool:
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return []
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
	# Back from a busy stage list may reveal this newer chooser. Repaint only
	# its own still-current generation; the old request cannot adopt its result.
	var identity := _relay_identity()
	while collection.busy() or api.busy or application_backgrounded:
		await get_tree().process_frame
		if mode != "story_replay_chapters" or store_view_generation != view or shared_replays != collection or not CampaignCanonical.same(identity,_relay_identity()): return
	if mode == "story_replay_chapters" and store_view_generation == view and shared_replays == collection and _story_replay_current(): _draw_story_replay_chapters()

func _open_story_replay_chapter(selection: Dictionary) -> void:
	if not CampaignCatalog.PRODUCTION_ENABLED: return
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return _story_replay_return.is_empty()
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
	if application_backgrounded or context.generation != _campaign_generation or context.owner != campaign_owner or context.mode != mode or not CampaignCanonical.same(context.identity,_relay_identity()): return false
	var child: Variant = context.child.get_ref() if context.child != null else null
	return child == relay_child and (child == null or is_instance_valid(child) and child.is_inside_tree())

func _story_lobby_action(action: String, value: Dictionary = {}, invitation: String = "") -> void:
	if not CampaignCatalog.PRODUCTION_ENABLED: return
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
	child.story_flow = campaign_flow
	child.story_chapter_index = index
	child.campaign_card_state = _story_child_state.bind(child)
	child.campaign_card_action = _story_child_action.bind(child)
	child.campaign_control_refresh = _story_refresh_control.bind(child)
	child.campaign_refresh_ready = _story_refresh_ready.bind(child)
	child.campaign_redo_client = campaign_owner.redo_client

func _story_refresh_ready(child: Node) -> bool:
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
	return child == relay_child and is_instance_valid(child) and relay_session != null and child.online_session == relay_session and child.journey == relay_session.coordinator and campaign_owner != null and not campaign_owner.busy() and not _campaign_action_busy and not application_backgrounded

func _story_refresh_control(child: Node) -> Dictionary:
	var result := {"current":false,"okay":false,"changed":false}
	if not CampaignCatalog.PRODUCTION_ENABLED: return result
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

func _story_child_handoff_confirmed(child: Node, room: Dictionary, publication: Dictionary) -> bool:
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
	if relay_session == null or child.online_session != relay_session or child.journey != relay_session.coordinator or not is_instance_valid(campaign_flow): return false
	if not campaign_owner.last_code.is_empty() or not child.journey.last_error.is_empty() or not campaign_owner.pending().is_empty() or not child.journey.pending().is_empty(): return false
	var index: int = child.story_chapter_index
	if index < 0 or publication.get("state") != "active" or publication.get("activation") != null or int(publication.get("current_index",-1)) != index+1: return false
	if not campaign_flow._completed_source(child,room,publication.chapters[index]): return false
	# The same validated scoped source can await a deliberate Resume without
	# implying a service failure. This observation grants no handoff or input.
	var playback: Dictionary = child.journey.playback_context()
	return playback.get("kind") == "campaign" and playback.get("authority",{}).get("publication") == CampaignCanonical.digest(publication)

func _story_child_state(child: Node) -> Dictionary:
	var result := {"recovery":true,"actions":[],"message":PlayerCopy.MAIN_6DE42F59590C}
	if not CampaignCatalog.PRODUCTION_ENABLED: return result
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
		if not child.journey.pending().is_empty(): result.message = PlayerCopy.MAIN_52C04F6029F5
		else: result.message = "" if _story_child_handoff_confirmed(child,room,publication) else PlayerCopy.MAIN_571E92F64ED1
		result.actions.append({"label":"Check saved turn" if not child.journey.pending().is_empty() else "Resume","action":"recover","enabled":not _campaign_action_busy and not child.journey.busy() and (not child.journey.pending().is_empty() or not campaign_owner._redo_hold())})
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
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
	if action == "recover" and child.journey.pending().is_empty() and campaign_owner._redo_hold(): return
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return null
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
	if child != relay_child or not is_instance_valid(campaign_flow): return
	child.refresh_campaign_card()
	campaign_flow.present_history(child,index,phase)

func _show_story_access() -> void:
	if not CampaignCatalog.PRODUCTION_ENABLED: return
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
	if not CampaignCatalog.PRODUCTION_ENABLED: return
	if mode != "story_access" or application_backgrounded or _campaign_action_busy or is_instance_valid(relay_child) or not _play_store_enabled(): return
	if campaign_owner == null or campaign_owner.busy() or relay_session == null: return
	var context := _campaign_context()
	if not context.identity.get("ready",false): return
	var return_context := {"owner":weakref(campaign_owner),"session":weakref(relay_session),
		"identity":context.identity,"generation":context.generation,"reference":campaign_owner.bound_campaign(),
		"selected_room":campaign_owner.selected_room(),"selection":relay_session.campaign_selection_generation(),"choice":_campaign_choice}
	_show_paywall(true,return_context)

func _story_store_current() -> bool:
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
	if _story_store_return.is_empty() or application_backgrounded: return false
	var owner: RefCounted = _story_store_return.owner.get_ref()
	var session: RefCounted = _story_store_return.session.get_ref()
	if owner == null or owner != campaign_owner or session == null or session != relay_session: return false
	if _story_store_return.generation != _campaign_generation or not CampaignCanonical.same(_story_store_return.identity,_relay_identity()): return false
	return CampaignCanonical.same(_story_store_return.reference,owner.bound_campaign()) and _story_store_return.selected_room == owner.selected_room() and _story_store_return.selection == session.campaign_selection_generation() and _story_store_return.choice == _campaign_choice

func _story_settings_done() -> void:
	if CampaignCatalog.PRODUCTION_ENABLED and _story_access_return:
		_story_access_return = false
		_draw_story_lobby()
	else: _show_home()
