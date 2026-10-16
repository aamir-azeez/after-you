extends Node3D
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const Frames = preload("res://services/frame_policy.gd")
const SoloReplayLaunch = preload("res://services/solo_replay_launch.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
## The chapter last chosen or hosted in Play with a friend. Every rebuilt hub
## starts from it, so leaving for Friends or a room keeps the choice; First
## Steps is only the default before the first choice.
var selected_online_chapter := ChapterRegistry.FIRST_STEPS

const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const World = preload("res://presentation/island_world.gd")
const HomeStage = preload("res://presentation/home_stage.gd")
const HomeKeepsakes = preload("res://services/home_keepsakes.gd")
const ChapterCompletion = preload("res://presentation/chapter_completion.gd")
const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
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
const StoreFlow = preload("res://presentation/store_flow.gd")
const AccountFlow = preload("res://presentation/account_flow.gd")
const ReplaysFlow = preload("res://presentation/replays_flow.gd")
const NotificationFlow = preload("res://presentation/notification_flow.gd")
const RecoveryDetails = preload("res://services/recovery_details.gd")
const Secrets = preload("res://services/secure_store.gd")
const RoomReactions = preload("res://presentation/room_reactions.gd")
const Licenses = preload("res://services/licenses.gd")
const Soundscape = preload("res://services/soundscape.gd")
const RefreshClock = preload("res://services/refresh_schedule.gd")
const TurnNotifications = preload("res://services/turn_notifications.gd")
const HostingNotificationPreferences = preload("res://services/hosting_notification_preferences.gd")
const FriendPresence = preload("res://services/friend_presence.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendsScreen = preload("res://presentation/friends_screen.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const RoomHubScreen = preload("res://presentation/room_hub_screen.gd")
const RoomInboxClient = preload("res://services/room_inbox_client.gd")
const FriendRoomEventsClient = preload("res://services/friend_room_events_client.gd")
const ChapterThumbnailCatalog = preload("res://services/chapter_thumbnail_catalog.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
## Meta on the control that leaves a screen (see _mark_screen_back).
const SCREEN_BACK := &"screen_back"
const Changelog = preload("res://services/changelog.gd")
const WhatsNewCard = preload("res://presentation/whats_new_card.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const REDO_REQUEST_BODY := "Your friend requested to redo your turn. Check the request to accept or reject it."
const RedoClient = preload("res://services/redo_client.gd")
const RedoScreen = preload("res://presentation/redo_screen.gd")
const PresenceBadge = preload("res://presentation/friend_presence_badge.gd")
const NotificationBridge = preload("res://services/turn_notification_bridge.gd")
const InviteLinkBridge = preload("res://services/invite_link_bridge.gd")
const InviteShare = preload("res://services/invite_share.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const AppStatus = preload("res://services/app_status.gd")
const ClientIdentity = preload("res://services/client_identity.gd")
const UpdateGate = preload("res://presentation/update_gate_screen.gd")
## An invite link waits at most this long for a safe moment and a ready identity.
const INVITE_LINK_TTL_MS := 600000
const INVITE_LINK_RETRY_MS := 15000
const INVITE_LINK_ATTEMPTS := 3
# Invite links open Friends by themselves only from these modes, and only when idle.
const INVITE_LINK_MODES := ["home", "rooms", "friends"]
## Screens a tapped notification may leave to open its room (Friends too, for a hosting alert).
const NOTIFICATION_ROUTE_MODES := ["home", "rooms", "room", "journey", "earlier_islands", ReplaysFlow.MODE_COLLECTION, "saved", "relay_rooms"]
const ObjectivePanel = preload("res://presentation/objective_panel.gd")
const SeedTimerBar = preload("res://presentation/seed_timer_bar.gd")
const DeletedPhotos = preload("res://services/deleted_identity_photo_cleanup.gd")
const PhotoResumePrompt = preload("res://presentation/photo_resume_prompt.gd")
const NativeFiles = preload("res://services/native_files.gd")
const HistoryStore = preload("res://services/history_store.gd")
const BackupPlan = preload("res://services/backup_plan.gd")
const AuxiliaryContext = preload("res://services/campaign_auxiliary_context.gd")
const SharedReplays = preload("res://services/shared_replay_collection.gd")
const LighthouseMigration = preload("res://services/lighthouse_migration.gd")
const ChapterLoadingCard = preload("res://presentation/chapter_loading_card.gd")
const ProofWarmup = preload("res://services/journey_proof_warmup.gd")
## What's new: this version's notes have not been opened since an update.
var _whats_new_unseen := false
var _whats_new_card: Control
var _whats_new_card_mode := ""
## Tests set this to see a link instead of opening the browser.
var external_link_opener: Callable
var _bounded_card_scroll: ScrollContainer
var _redo_request_modal: Control
var _announced_redo_requests: Dictionary = {}
## Holds the scroll area of a bounded card; controls added after it stay fixed below the list.
var _bounded_card_footer: VBoxContainer
var _bounded_card_stack: VBoxContainer
var _journey_picker: ChapterPicker
## Full Journey access the open chapter grid was drawn with.
var _grid_access_drawn := false
## The card an open of a chapter waits behind; one open at a time.
var _chapter_opening: CanvasLayer
## Proves saved solo journeys on a worker while Home is idle.
var _proof_warmup: Node
const Safety = preload("res://services/safety_client.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const INK := Color("193d39")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("9dbeb4")
const GOLD := Color("f1c48a")
const COMPLETION_MOMENT_SECONDS := 3.0
enum IdentityReadState { UNCHECKED, LOADING, MISSING, LOADED, FAILED, RECOVERY_PENDING }

var world: Node3D
var _suspended_world_id := 0
## True while Friends or the room hub covers the whole screen: the Home world
## behind them is neither drawn nor run (_service_world_cover).
var _world_covered := false
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
var friends_client: RefCounted
var friend_nicknames: RefCounted = FriendNicknames.new()
var friends_screen: CanvasLayer
var room_hub_screen: CanvasLayer
var room_inbox: RefCounted
var friend_room_events: RefCounted
var room_hub_host_visibility := "friends"
var _friends_return_home := false
var friend_share_target: Dictionary = {}
var _room_share_busy := false
## A failed hosting alert for a shared room retries quietly after these delays.
var owed_alert_retry_s: Array[float] = [5.0, 20.0, 60.0]
## Share replies that mean the room can no longer be shared: its alert is dropped.
const ROOM_GONE_CODES := ["room_not_found", "friend_room_unavailable", "friend_not_joinable", "room_full"]
var _owed_alert_retrying := ""
var legacy_redo: RefCounted
var legacy_redo_restore_scope := ""
var legacy_redo_restore_ok := true
var redo_screen: CanvasLayer
var shared_replay_child: Node3D
var photo_transfer_child: Node
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
var progress: SeedTimerBar
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
		if mode==ReplaysFlow.MODE_COLLECTION and value!=ReplaysFlow.MODE_COLLECTION:
			replays_flow.cancel_solo_collection_scan()
		mode=value
var running := false
var action_pressed := false
var replay_frames: Array=[]
var replay_index := 0
var review_recording: Dictionary={}
var _retry_cancel: Callable
var active_room: Dictionary={}
var room_play := false
var identity_request := ""
var recovery_read_request := ""
var pending_recovery: Dictionary = {}
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
## The store, paywall, purchase, restore and tester-code flow, with its state.
## Built with Main itself, so harnesses that replace _ready still have it.
var store_flow: StoreFlow = _host_store_flow()
## Account & recovery, identity recovery and deleted-identity cleanup, with their state.
var account_flow: AccountFlow = _host_account_flow()
## Your replays, Shared replays, replay launches and finished-room replay saves, with their state.
var replays_flow: ReplaysFlow = _host_replays_flow()
## Notification settings, alerts while the app is open and opening a tapped alert, with their state.
var notification_flow: NotificationFlow = _host_notification_flow()
var store_view_generation := 0
var identity_restart_required := false
var application_backgrounded := false
var foreground_refresh_queued := false
var foreground_refresh_running := false
var foreground_schedule := RefreshClock.new()
var foreground_response: Dictionary = {}
var lifecycle_generation := 0
var submission_in_flight := false
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
var room_reaction_notices: Dictionary = {}
var deleted_identity_owner := ""
var safety_screen: CanvasLayer
var safety_return := "settings"
## Home prompt for a turn photo that After You closed under (photo_resume_prompt.gd).
var photo_resume_prompt: Node
var _photo_resume_checked := false
var turn_notifications: Node
var hosting_notification_preferences := HostingNotificationPreferences.new()
var friend_presence: Node
var presence_hud: Label
var invite_link_bridge: Node
## Native inbox override for tests; production uses the native plugin.
var invite_link_native: Object
## In-memory only: one validated friend ID from an invite link, never persisted or auto-added.
var invite_link_pending := ""
var invite_link_expires_ms := 0
var invite_link_retry_ms := 0
var invite_link_attempts := 0
var invite_link_busy := false
var invite_link_notice := false
## Home invite share outputs; empty uses the system share sheet and clipboard fallback.
var invite_share_text: Callable
var invite_clipboard_copy: Callable
## Required-update check (services/app_status.gd). Its answer is kept in memory only.
var app_status: Node
## "Play Solo" on the update screen: Home stops showing it for this session, while
## online features still do.
var update_gate_dismissed := false
## Opens the Update button's store page; empty uses OS.shell_open. Tests replace it.
var update_gate_open_url: Callable

func _ready() -> void:
	var heading := FontVariation.new()
	heading.base_font=title_font
	heading.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	title_font=heading
	var body := FontVariation.new()
	body.base_font=body_font
	body.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	body_font=body
	# A replay open that never reached its chapter leaves nothing behind.
	SoloReplayLaunch.discard()
	saves.load_data()
	_decide_whats_new()
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
	# Only a phone with the synced native write that passes its startup check tells
	# the server it keeps room attempts; every other build keeps today's behaviour.
	if NativeFiles.durable_available(): RoomsApi.history_supported = HistoryStore.new().self_test()
	# Keep presence independent of gameplay and alive across solo chapter scenes.
	# Offline/headless builds create no singleton or network work.
	if friend_presence == null and api.configured(): friend_presence = FriendPresence.shared(get_tree())
	if is_instance_valid(friend_presence):
		friend_presence.set_enabled(bool(saves.data.settings.get("share_online_status", true)))
	purchases=Purchases.new()
	add_child(purchases)
	purchases.completed.connect(store_flow.purchase_completed)
	purchases.failed.connect(store_flow.purchase_failed)
	purchases.customer_info_changed.connect(_customer_info_changed)
	secrets=Secrets.new()
	add_child(secrets)
	secrets.completed.connect(_secret_completed)
	secrets.failed.connect(_secret_failed)
	tester_access = tester_access_factory.call() if tester_access_factory.is_valid() else TesterAccess.new()
	add_child(tester_access)
	_setup_turn_notifications()
	_setup_invite_links()
	_proof_warmup = ProofWarmup.new()
	_proof_warmup.idle = func() -> bool: return mode == "home" and not application_backgrounded and not is_instance_valid(relay_child) and not is_instance_valid(_chapter_opening)
	add_child(_proof_warmup)
	world=World.new()
	add_child(world)
	_sync_world_processing()
	world.footstep.connect(func(spirit: String):
		if mode=="home" or (running and mode in ["play","preview"]): soundscape.play_footstep(spirit))
	world.reunion.connect(func():
		if mode=="home" or (running and mode in ["play","preview"]): soundscape.play_reunion())
	soundscape.listen_to(world,"home")
	world.load_level(current_level)
	sim.reset(current_level)
	world.present(sim.snapshot(),true)
	_build_theme()
	# Before any list exists: lists wait for a finger's slop before scrolling.
	TouchInput.install(get_viewport())
	_build_ui()
	world.configure_camera_exploration(_camera_exploration_active, _camera_exploration_allowed)
	get_viewport().size_changed.connect(_refresh_safe_area)
	_refresh_safe_area()
	_refresh_safe_area.call_deferred()
	_apply_settings()
	_show_home()
	# Home shows at once; the update screen replaces it if the answer says so.
	app_status = AppStatus.new()
	app_status.base_url = api.base_url
	app_status.configured = api.configured()
	add_child(app_status)
	if api.has_signal("update_required"): api.update_required.connect(_on_update_required)
	_check_app_status()
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
	# The same seed timer as every chapter HUD; it owns the remaining-seconds number.
	progress=SeedTimerBar.new()
	hud.add_child(progress)
	progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	progress.offset_left=-160
	progress.offset_top=24
	progress.offset_right=160
	progress.offset_bottom=24+SeedTimerBar.MIN_SIZE.y
	timer_label=progress.label
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
	TouchInput.install(get_viewport())
	var viewport := get_viewport().get_visible_rect()
	var safe := viewport
	if SafeArea.applies():
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

## Marks the control that leaves the current screen. Android Back presses it
## on a screen with no rule of its own, so Back and the on-screen control agree.
static func _mark_screen_back(button: Button) -> Button:
	button.set_meta(SCREEN_BACK, true)
	return button

## A button that leaves the current screen, marked for Android Back.
func _back_button(text: String, callback: Callable, primary: bool=true) -> Button:
	return _mark_screen_back(_button(text,callback,primary))

## Android Back where no screen rule applies: the screen's own marked way back
## is pressed. A screen with none (Home) stays as it is, and a chapter being
## opened keeps its loading card.
func _back_on_screen() -> void:
	if is_instance_valid(_chapter_opening): return
	for node: Node in overlay.find_children("*","Button",true,false):
		var button := node as Button
		if button.has_meta(SCREEN_BACK) and button.is_visible_in_tree() and not button.disabled and not button.is_queued_for_deletion():
			button.pressed.emit()
			return

## Closes the topmost card Main opened over a screen (InGameModal), if any.
func _close_top_modal() -> bool:
	for index in range(ui.get_child_count()-1,-1,-1):
		var child := ui.get_child(index)
		if child.get_script() == InGameModal and not child.is_queued_for_deletion():
			child.close()
			return true
	return false

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
	_release_room_hub()
	replays_flow.cancel_collection_replay()
	store_view_generation += 1
	_bounded_card_scroll=null
	_bounded_card_footer=null
	_bounded_card_stack=null
	store_flow.overlay_cleared()
	overlay_shade=null
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible=true

## The hub is a layer above the overlay; any other screen replaces it, or the
## hub would cover that screen and take its taps.
func _release_room_hub() -> void:
	if not is_instance_valid(room_hub_screen): return
	room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true

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
		# Card buttons pass drags to the scroller, like _list_button rows.
		ControlTheme.touch_scroll(_bounded_card_scroll)
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
	running=false
	mode="home"
	# Home meetups are not recorded, so their chime stays random.
	soundscape.clear_turn()
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
	# Friend-first column, vertically centred in the safe area: as much space above
	# the eyebrow as below the last button. Short screens tighten the spacing.
	var stack := VBoxContainer.new()
	stack.name = "HomeMenu"
	stack.add_theme_constant_override("separation",14 if compact else 24)
	overlay.add_child(stack)
	stack.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	stack.offset_left = 64
	stack.offset_right = 64+385
	stack.offset_top = 0
	stack.offset_bottom = 0
	stack.grow_vertical = Control.GROW_DIRECTION_BOTH
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation",2 if compact else 6)
	stack.add_child(heading)
	heading.add_child(_label(PlayerCopy.MAIN_5DA48958135C,15,MINT))
	var title := _label("After\nYou",64 if compact else 84,CREAM,true)
	title.add_theme_constant_override("line_spacing",-14 if compact else -20)
	heading.add_child(title)
	heading.add_child(_paragraph(PlayerCopy.MAIN_6A7ECC3FD1B9,385))
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation",10 if compact else 14)
	stack.add_child(actions)
	actions.add_child(_button("Play with your friend",_show_rooms))
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation",10)
	actions.add_child(pair)
	_home_action(pair,"Play Solo",preload("res://assets/ui/social/user.svg"),_show_journey)
	var friends := _home_action(pair,"Friends",preload("res://assets/ui/social/users.svg"),_show_friends)
	friends.name = "HomeFriends"
	friends.tooltip_text = "Friends"
	friends.accessibility_name = "Friends"
	_home_action(actions,"Replays",preload("res://assets/ui/play-circle.svg"),replays_flow.show_collection)
	var invite := _home_action(actions,PlayerCopy.HOME_INVITE,preload("res://assets/ui/social/share-network.svg"),_share_invite_from_home)
	invite.name = "HomeInvite"
	invite.tooltip_text = PlayerCopy.INVITE_LINK_SHARE
	var journey_offer := _button("Full Journey   →",store_flow.show_paywall,false)
	journey_offer.name = "HomeFullJourney"
	overlay.add_child(journey_offer)
	journey_offer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	journey_offer.offset_left = -238
	journey_offer.offset_right = -32
	journey_offer.offset_top = 32
	journey_offer.offset_bottom = 86
	journey_offer.visible = not _full_journey_access()
	# Settings is a square cog beside the offer, or in its corner once owned.
	var settings := _button("",_show_settings,false)
	settings.name = "HomeSettings"
	settings.icon = preload("res://assets/ui/social/gear.svg")
	settings.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings.expand_icon = true
	settings.tooltip_text = "Settings"
	settings.accessibility_name = "Settings"
	settings.add_theme_constant_override("icon_max_width",28)
	_home_icon_colors(settings)
	overlay.add_child(settings)
	_fit_icon_button(settings)
	settings.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# What's new sits left of the cog, with a dot and a tip until this version's card is opened.
	var whats_new := _button(PlayerCopy.WHATS_NEW,_open_whats_new_from_home,false)
	whats_new.name = "HomeWhatsNew"
	whats_new.icon = preload("res://assets/ui/whats_new/gift.svg")
	whats_new.add_theme_constant_override("icon_max_width",24)
	whats_new.add_theme_constant_override("h_separation",10)
	_home_icon_colors(whats_new)
	overlay.add_child(whats_new)
	whats_new.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	if _whats_new_unseen: WhatsNewCard.mark_unseen(whats_new,Changelog.current_version())
	_place_home_settings()
	journey_offer.visibility_changed.connect(_place_home_settings)
	home_stage.set_header_actions([journey_offer,settings,whats_new])

## Secondary Home action: outlined, full touch height, icon centred with its label.
func _home_action(parent: Container, text: String, icon: Texture2D, action: Callable) -> Button:
	var button := _button(text,action,false)
	button.icon = icon
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_constant_override("icon_max_width",22)
	button.add_theme_constant_override("h_separation",10)
	_home_icon_colors(button)
	parent.add_child(button)
	ControlTheme.inset_button(button)
	ControlTheme.center_icon_label(button)
	return button

func _home_icon_colors(button: Button) -> void:
	button.add_theme_color_override("icon_normal_color",CREAM)
	button.add_theme_color_override("icon_focus_color",CREAM)
	for state: String in ["hover","pressed","hover_pressed"]:
		button.add_theme_color_override("icon_"+state+"_color",INK)
	button.add_theme_color_override("icon_disabled_color",MUTED)

func _place_home_settings() -> void:
	if not is_instance_valid(overlay): return
	var settings := overlay.get_node_or_null("HomeSettings") as Control
	var offer := overlay.get_node_or_null("HomeFullJourney") as Control
	if settings == null or offer == null: return
	# Immediately left of the Full Journey offer (same top, 10 apart) while it shows;
	# in the offer's top-right corner once the Full Journey is owned.
	var right: float = offer.offset_left-10.0 if offer.visible else offer.offset_right
	settings.offset_right = right
	settings.offset_left = right-54.0
	settings.offset_top = offer.offset_top
	settings.offset_bottom = offer.offset_top+54.0
	var whats_new := overlay.get_node_or_null("HomeWhatsNew") as Control
	if whats_new == null: return
	var width := ceilf(whats_new.get_combined_minimum_size().x)
	whats_new.offset_right = settings.offset_left-16.0
	whats_new.offset_left = whats_new.offset_right-width
	whats_new.offset_top = settings.offset_top
	whats_new.offset_bottom = settings.offset_bottom

func _share_invite_from_home() -> void:
	if mode != "home" or application_backgrounded: return
	if _online_gated(): return
	# A ready identity's player ID is the friend code. Otherwise the Friends entry
	# creates or checks the identity and shows its existing message, never a dead tap.
	# A short name (friend-aamir) from the loaded Friends page replaces the long code.
	var alias: String = friends_client.friend_alias() if friends_client != null else ""
	if _relay_identity().ready and InviteShare.share(alias if not alias.is_empty() else str(api.player_id),invite_share_text,invite_clipboard_copy): return
	await _show_friends()

func _screen_shell(title: String, back_callback: Callable) -> Dictionary:
	## Full-screen page with the Replays header: a labelled coral Back beside
	## the page title. The caller fills the rest of `outer`. The backdrop is a
	## little denser than a dialog's so the home island cannot show between
	## picture cards and read as part of them.
	_clear_overlay()
	var shade := ColorRect.new()
	shade.color=Color(0.025,0.10,0.10,0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	overlay_shade=shade
	_update_shade_bounds()
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
	var back := _back_button("Back",back_callback,false)
	back.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	header.add_child(back)
	var heading := _label(title,34,CREAM,true)
	heading.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	header.add_child(heading)
	outer.add_child(header)
	return {"margin":margin,"outer":outer,"header":header}

## Locked Full Journey art is dimmed and desaturated by the shared chapter picker.
const LOCKED_PICTURE_TINT := ChapterPicker.LOCKED_PICTURE_TINT

func _show_journey() -> void:
	running = false
	mode = "journey"
	var shell := _screen_shell("Your journey",_show_home)
	var outer: VBoxContainer = shell.outer
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",10)
	var chapters_tab := _button("Chapters",_show_journey,false)
	chapters_tab.disabled = true
	ControlTheme.selected_tab(chapters_tab)
	tabs.add_child(chapters_tab)
	var earlier := _button("Earlier islands",_show_earlier_islands,false)
	ControlTheme.plain_tab(earlier)
	tabs.add_child(earlier)
	outer.add_child(tabs)
	var picker := ChapterPicker.new()
	picker.heading_font = title_font
	picker.available_width = func() -> float: return ui.size.x-44.0
	outer.add_child(picker)
	shell.margin.resized.connect(picker.refit)
	# The solo-only Lighthouse leads the Full Journey chapters; the picker puts
	# every free chapter first in registry order.
	var lighthouse := {"key": ChapterThumbnailCatalog.SLEEPING_LIGHTHOUSE, "title": "Sleeping Lighthouse", "premium": true,
		"level_key": ChapterThumbnailCatalog.SLEEPING_LIGHTHOUSE, "mark": "sleeping-lighthouse@1"}
	var entries: Array[Dictionary] = [lighthouse]
	for key: String in ChapterRegistry.offered_keys():
		if _own_solo_card(key): entries.append(ChapterPicker.entry(key))
	var owned := _full_journey_access()
	_grid_access_drawn = owned
	for item: Dictionary in entries: item.locked = item.premium and not owned
	picker.set_entries(entries,ChapterPicker.picture_for(ui.size.x))
	picker.chosen.connect(_open_solo_chapter)
	_journey_picker = picker
	_refresh_chapter_marks()

## Runs a Play Solo card's play button: the chapter's solo scene, through the
## premium gate when the chapter is premium.
func _open_solo_chapter(key: String) -> void:
	if key == ChapterThumbnailCatalog.SLEEPING_LIGHTHOUSE:
		_open_lighthouse()
		return
	if not _own_solo_card(key): return
	if ChapterRegistry.descriptor(key).premium: _open_premium_chapter(ChapterRegistry.solo_scene(key))
	else: _open_chapter_preview(ChapterRegistry.solo_scene(key))

## Every chapter has its own Solo card except the Lighthouse's, which the
## Lighthouse card opens (lighthouse_scene()).
static func _own_solo_card(key: String) -> bool:
	return not ChapterRegistry.is_lighthouse(key) and not ChapterRegistry.solo_scene(key).is_empty()

func _chapter_marks() -> Dictionary:
	return ChapterCompletion.chapters(home_keepsakes.earned_descriptors())

func _refresh_chapter_marks() -> void:
	if mode != "journey" or not is_instance_valid(_journey_picker): return
	_journey_picker.refresh_marks(_chapter_marks())

func _show_earlier_islands() -> void:
	running=false
	mode="earlier_islands"
	_grid_access_drawn = _full_journey_access()
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
	card.add_child(_back_button("Back to chapters",_show_journey,false))

const LIGHTHOUSE_SCENE := "res://lighthouse_preview.tscn"

## The Lighthouse card plays sleeping-lighthouse@2 once it is offered. An
## unfinished @1 journey that could not be carried over continues in @1.
func _open_lighthouse() -> void:
	await _open_premium_chapter(lighthouse_scene())

static func lighthouse_scene() -> String:
	if ChapterRegistry.LIGHTHOUSE_V2 in ChapterRegistry.offered_keys() and LighthouseMigration.plan() != "v1":
		return ChapterRegistry.solo_scene(ChapterRegistry.LIGHTHOUSE_V2)
	return LIGHTHOUSE_SCENE

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
		store_flow.show_paywall()
		return
	if not store_flow.identity_ready():
		# An offline SDK setup can fail after cached customer information arrives.
		# Re-enter the retryable store flow instead of waiting for a callback that
		# has already failed. This does not grant access from the cached label.
		store_flow.show_paywall()
		return
	_open_chapter_preview(scene,replay_context)

func _open_chapter_preview(scene: String, replay_context: Dictionary = {}) -> void:
	if is_instance_valid(_chapter_opening): return
	# The chapter's own open proves what the warm-up has not reached yet.
	if is_instance_valid(_proof_warmup): _proof_warmup.stop()
	if _chapter_open_busy():
		_toast(PlayerCopy.MAIN_A776CD47C8D9)
		return
	# Home's keepsake check stops after its current stage, so it does not
	# compete with the build; Home checks that source again later.
	home_keepsakes.stop_worker()
	# The chapter builds in one frame after the scene change; its card is
	# drawn first. Nothing changes until it is up.
	var opening := ChapterLoadingCard.new()
	_chapter_opening = opening
	var view := mode
	opening.start(get_tree(), scene, bool(saves.data.settings.get("reduced_motion", false)))
	await opening.drawn()
	# Never waits for Home's keepsake check: leaving Home hands it to the reaper.
	await opening.prepare(scene, replay_context.is_empty(), self)
	if not is_inside_tree() or mode != view or _chapter_open_busy():
		opening.cancel()
		return
	if CampaignCatalog.PRODUCTION_ENABLED and not _campaign_depart_for_ordinary():
		opening.cancel()
		return
	if is_instance_valid(friend_presence): friend_presence.monitor_room("", "")
	if not replay_context.is_empty() and not _write_solo_replay_context(replay_context):
		opening.cancel()
		_toast("Replay could not be opened. Please try again.")
		return
	RelayPreview.request_staged_build(scene)
	if opening.change_scene(scene) != OK:
		RelayPreview.request_staged_build("")
		opening.cancel()
		if not replay_context.is_empty(): SoloReplayLaunch.discard()
		_toast(PlayerCopy.MAIN_EB8856600899)
		return
	opening.follow_scene_change(self)

func _chapter_open_busy() -> bool:
	return submission_in_flight or foreground_refresh_running or identity_loading or identity_busy or (relay_session != null and relay_session.busy())

static func _write_solo_replay_context(context: Dictionary) -> bool:
	return SoloReplayLaunch.write(context)

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
		store_flow.show_paywall()
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
	_begin_sound_turn()
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

## The simulation is back at tick zero: its cues restart their identities.
func _begin_sound_turn() -> void:
	soundscape.begin_turn(Soundscape.ISLANDS_CHAPTER,str(current_level.get("id","")))

func _sound_sources(state: Dictionary) -> Array:
	var sources: Array=[]
	for event: Variant in state.get("events",[]): sources.append(Soundscape.event_source(str(event),role))
	return sources

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
	_begin_sound_turn()
	for input in Simulation.expand_recording_inputs(draft):
		var state: Dictionary=sim.step(input)
		soundscape.note_turn_events(state.events,_sound_sources(state))
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
		soundscape.consume_turn_events(state.events,_sound_sources(state),mode=="play")
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
	progress.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
	progress.set_remaining(maxi(0,int(state.duration_ticks)-int(state.tick))/30.0,int(state.duration_ticks)/30.0)
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
			if account_flow.holds_back() or mode == "update_gate":
				get_viewport().set_input_as_handled()
				return
			if mode == ReplaysFlow.MODE_COLLECTION_LOADING: replays_flow.show_collection()
			elif mode == "story_lobby": _story_back()
			elif mode == "story_access": _draw_story_lobby()
			elif store_flow.handle_back(): pass
			elif mode in ["confirm_retry", "confirm_restart", ReplaysFlow.MODE_CONFIRM_DELETE]:
				if _retry_cancel.is_valid(): _retry_cancel.call()
			elif mode == "story_replay_chapters": _return_story_replay_lobby()
			elif mode == ReplaysFlow.MODE_SHARED_MEMORIES and not _story_replay_return.is_empty(): _back_to_story_replay_chapters()
			elif mode == "relay_rooms": _return_to_room_hub()
			elif mode == "rooms" and is_instance_valid(room_hub_screen): room_hub_screen.go_back()
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
	mode=ReplaysFlow.MODE_COLLECTION if collection_preview else "review"
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

## Plays an earlier island's saved attempt from Your replays.
func preview_saved_attempt(index: int, saved: Dictionary) -> void:
	level_index=index
	current_level=levels[index]
	attempt=saved.duplicate(true)
	_preview(saved.b,true)

func _preview(recording: Dictionary, collection: bool=false) -> void:
	if collection and not room_play:
		replays_flow.begin_collection_replay(recording)
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
	_begin_sound_turn()
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
		await _one_room_write(_send_reaction.bind(code))
		return
	saves.data["last_reaction"]=reaction
	saves.flush()
	_toast(reaction)

func _send_reaction(code: String) -> void:
	if not saves.data.get("pending_turn",{}).is_empty():
		_toast(PlayerCopy.MAIN_D808B160901A)
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
		store_flow.show_paywall()
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

func _replay_preview_thumb(key: String, min_size: Vector2, radius: int) -> Control:
	# One framed picture for every chapter view; the chapter picker owns it.
	return ChapterPicker.thumbnail(key,min_size,radius)

func _open_photo_transfer() -> void:
	if _online_gated(): return
	if not _relay_identity().ready:
		_toast(PlayerCopy.MAIN_2BCA37F28163)
		return
	if submission_in_flight or foreground_refresh_running or (relay_session!=null and relay_session.busy()):
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
	account_flow.show_account()

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
	var display_entries: Array = [["Graphics",_show_graphics_settings],["Notifications",notification_flow.show_settings]]
	# Subscribers reach Manage subscription and Restore here once Home hides the offer.
	if _play_store_enabled(): display_entries.append(["Full Journey",store_flow.show_store_from_settings])
	for entry: Array in display_entries:
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
	var account_group: Array = [["Account & recovery",account_flow.show_account]]
	if PlatformSupport.tester_code_offered(): account_group.append(["Tester code",store_flow.show_tester_access])
	for group: Array in [account_group,[["Community & privacy",_open_safety],[PlayerCopy.WHATS_NEW,func(): _open_whats_new_card()],["Licenses",_show_licenses]]]:
		var links := HBoxContainer.new()
		links.add_theme_constant_override("separation",10)
		settings_list.add_child(links)
		for entry: Array in group:
			var link := _button(entry[0],entry[1],false)
			link.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			links.add_child(link)
	card.add_child(_back_button("Done",_story_settings_done,false))

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
	var unlimited := CheckButton.new()
	unlimited.name = "UnlimitedFrameRate"
	unlimited.text = "Unlimited frame rate"
	unlimited.mouse_filter = Control.MOUSE_FILTER_PASS
	unlimited.button_pressed = GraphicsPolicy.unlimited_frame_rate(saves.data.settings)
	unlimited.toggled.connect(func(value: bool): _set_unlimited_frame_rate(value, unlimited))
	card.add_child(unlimited)
	card.add_child(_paragraph("Plays at your screen's full refresh rate. Uses more battery and can warm your phone.",500))
	card.add_child(_back_button("Back",_show_settings,false))

func _set_graphics_quality(quality: String) -> void:
	if mode != "graphics_settings" or quality not in GraphicsPolicy.QUALITIES: return
	var next: Dictionary = saves.data.settings.duplicate(true)
	next.graphics_quality = quality
	if not saves.update_values({"settings":next}):
		_toast(PlayerCopy.MAIN_34B82590B663)
		_show_graphics_settings()
		return
	_apply_settings()

func _set_unlimited_frame_rate(value: bool, toggle: CheckButton) -> void:
	if mode != "graphics_settings": return
	var next: Dictionary = saves.data.settings.duplicate(true)
	next.unlimited_frame_rate = value
	if not saves.update_values({"settings":next}):
		toggle.set_pressed_no_signal(GraphicsPolicy.unlimited_frame_rate(saves.data.settings))
		_toast(PlayerCopy.MAIN_34B82590B663)
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
	card.add_child(_back_button("Back to settings",_show_settings,false))

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
	card.add_child(_back_button("Back to licenses",_show_licenses,false))

## At launch, before anything writes the save: after an update this version's
## notes wait to be opened; a fresh install or a downgrade only records the
## version, in memory, so the next ordinary save keeps it.
func _decide_whats_new() -> void:
	var current := Changelog.current_version()
	var decision := Changelog.decide(saves.data.get(Changelog.SAVE_KEY), not saves.loaded_from.is_empty(), saves.read_only, current)
	if decision.remember: saves.data[Changelog.SAVE_KEY] = current
	_whats_new_unseen = decision.unseen

## True after an update until the player opens this version's notes.
func whats_new_unseen() -> bool:
	return _whats_new_unseen

## Opening the card or the full page counts as seeing this version's notes.
func _remember_whats_new() -> void:
	_whats_new_unseen = false
	var current := Changelog.current_version()
	if saves.read_only or saves.data.get(Changelog.SAVE_KEY) == current: return
	saves.update_values({Changelog.SAVE_KEY: current})

## A notification or link that changes the screen takes an open card away with it.
func _service_whats_new() -> void:
	if is_instance_valid(_whats_new_card) and mode != _whats_new_card_mode: _whats_new_card.close(false)

## This version's card, opened from the Home button or the Settings row. It never
## opens on its own.
func _open_whats_new_card(opener: Control = null) -> void:
	if mode not in ["home", "settings"] or is_instance_valid(_whats_new_card): return
	var entries := Changelog.load_entries(Changelog.channel(config))
	if entries.is_empty() or entries[0].version != Changelog.current_version(): return
	_remember_whats_new()
	if is_instance_valid(overlay): WhatsNewCard.clear_unseen(overlay.get_node_or_null("HomeWhatsNew"))
	var see_all: Callable = _open_release_notes if Changelog.releases_link_offered() else Callable()
	_whats_new_card = WhatsNewCard.open(ui,entries[0],see_all,opener)
	_whats_new_card_mode = mode

func _open_whats_new_from_home() -> void:
	_open_whats_new_card(overlay.get_node_or_null("HomeWhatsNew") as Control)

## Every release's full notes, on GitHub.
func _open_release_notes() -> void:
	if is_instance_valid(_whats_new_card): _whats_new_card.close(false)
	_open_external_link(Changelog.RELEASES_URL)

func _open_external_link(url: String) -> void:
	if external_link_opener.is_valid(): external_link_opener.call(url)
	else: OS.shell_open(url)

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

## An internal child: it leaves Main's own child order alone.
func _host_store_flow() -> StoreFlow:
	var flow := StoreFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.settings_requested.connect(_show_settings)
	flow.chapters_requested.connect(_show_journey)
	flow.rooms_requested.connect(_show_rooms)
	flow.lighthouse_requested.connect(_open_lighthouse)
	flow.google_play_requested.connect(_open_google_play)
	flow.story_return_requested.connect(_leave_store_for_story)
	return flow

## An internal child, like StoreFlow.
func _host_account_flow() -> AccountFlow:
	var flow := AccountFlow.new(self)
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.settings_requested.connect(_show_settings)
	flow.photo_transfer_requested.connect(_open_photo_transfer)
	flow.safety_requested.connect(func(): _open_safety({},"account"))
	return flow

## An internal child, like StoreFlow.
func _host_replays_flow() -> ReplaysFlow:
	var flow := _new_replays_flow()
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.home_requested.connect(_show_home)
	flow.account_requested.connect(func(): account_flow.show_account())
	flow.story_chapters_requested.connect(_back_to_story_replay_chapters)
	flow.story_lobby_requested.connect(_return_story_replay_lobby)
	return flow

## The flow Main hosts and wires; a subclass may return its own ReplaysFlow.
func _new_replays_flow() -> ReplaysFlow:
	return ReplaysFlow.new(self)

## An internal child, like StoreFlow.
func _host_notification_flow() -> NotificationFlow:
	var flow := _new_notification_flow()
	add_child(flow,false,Node.INTERNAL_MODE_BACK)
	flow.settings_requested.connect(_show_settings)
	return flow

## The flow Main hosts and wires; a subclass may return its own NotificationFlow.
func _new_notification_flow() -> NotificationFlow:
	return NotificationFlow.new(self)

func _play_store_enabled() -> bool:
	return Purchases.store_enabled(config)

func _open_google_play() -> void:
	OS.shell_open(UpdateGate.PLAY_LISTING_URL)

func _hosting_entitled() -> bool:
	return _hosting_lock_reason().is_empty()

## Why hosting a Full Journey chapter is locked, from the one shared rule: a
## tester code opens it in every build; in the GitHub Test Store build a
## purchase opens solo only, so hosting waits for a code; a Google Play purchase
## opens hosting too. Reads cached entitlement only, never a per-screen store query.
func _hosting_lock_reason() -> String:
	return Purchases.hosting_lock_reason(config,purchases.has_entitlement(),_tester_active())

## The identity half of the store's readiness: a saved identity that no load,
## recovery, restart or deletion holds.
func _store_identity_settled() -> bool:
	return not api.device_token.is_empty() and not identity_loading and not identity_busy and not identity_restart_required and pending_recovery.is_empty() and deleted_identity_owner.is_empty() and not saves.data.has(DeletedPhotos.MARKER_KEY)

## A loaded identity that purchases may bind their session to.
func _purchase_session_identity() -> bool:
	return identity_read_state == IdentityReadState.LOADED and not identity_restart_required and not identity_loading and not identity_busy and pending_recovery.is_empty() and not saves.data.has(DeletedPhotos.MARKER_KEY)

## Leaving a store opened from Story goes back to that Story only while it is current.
func _leave_store_for_story(story_return: Dictionary) -> void:
	if _story_store_current(story_return): _draw_story_lobby()
	else: _show_home()

func _customer_info_changed(_payload: Dictionary) -> void:
	# The store may finish loading after the grid opens. Refresh the locks here;
	# button callbacks still check the current entitlement when pressed. The
	# store reports on every launch and resume, mostly with nothing new, and a
	# redraw frees the card under a finger, so only a change in access redraws,
	# after any tap in progress.
	if mode in ["journey","earlier_islands"]:
		if _full_journey_access() == _grid_access_drawn: return
		await TouchInput.redraw_when_released(overlay,func() -> bool: return mode in ["journey","earlier_islands"] and _full_journey_access() != _grid_access_drawn,
			func() -> void:
				if mode=="journey": _show_journey()
				else: _show_earlier_islands())
	elif mode=="rooms" and is_instance_valid(room_hub_screen):
		room_hub_screen.set_chapters(_together_chapters())

func _load_saved_identity() -> void:
	if identity_loading or identity_busy or identity_restart_required:
		return
	_invalidate_relay_identity(false)
	identity_read_state=IdentityReadState.LOADING
	identity_loading=true
	# A saved rotation takes precedence over possibly revoked device credentials.
	recovery_read_request=secrets.get_secret("recovery_pending")

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
			if RecoveryDetails.valid_pending(saved):
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
				store_flow.configure_purchases()
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

func _show_rooms() -> void:
	if _online_gated(): return
	if not api.configured():
		running=false
		mode="rooms"
		var frame := _card(700)
		frame.add_child(_label(PlayerCopy.MAIN_3A4A78824AC3,34,CREAM,true))
		frame.add_child(_paragraph(PlayerCopy.MAIN_C372E9DBD93A))
		frame.add_child(_list_button("Practice on your own",_show_journey))
		frame.add_child(_back_button("Back",_show_home,false))
		return
	if is_instance_valid(room_hub_screen): return
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available() or not await _ensure_identity(): return
	if view != store_view_generation or lifecycle != lifecycle_generation or application_backgrounded: return
	if not await _prepare_ordinary_navigation(): return
	_open_room_hub()

## Builds the hub without the entry checks of _show_rooms; every room flow
## returns here. A notice, such as why a room could not be opened, shows above
## the room list.
func _open_room_hub(notice: String = "", refresh: bool = true) -> void:
	if is_instance_valid(room_hub_screen):
		room_hub_screen.show_notice(notice)
		return
	running=false
	mode="rooms"
	ui.visible=false
	room_inbox = RoomInboxClient.new(api,_relay_identity)
	room_inbox.local = _hub_local_history
	room_inbox.finished = _hub_saved_replay_rooms
	room_hub_screen = RoomHubScreen.new()
	room_hub_screen.client = room_inbox
	room_hub_screen.restore_choice(selected_online_chapter,room_hub_host_visibility)
	room_hub_screen.set_chapters(_together_chapters())
	room_hub_screen.completion_marks = _chapter_marks()
	room_hub_screen.display_name = _hub_member_name
	room_hub_screen.thumbnail_for = func(key: String) -> String: return ChapterThumbnailCatalog.path(key)
	room_hub_screen.closed.connect(_close_room_hub)
	room_hub_screen.friends_requested.connect(_open_friends_from_room_hub)
	room_hub_screen.chapter_picked.connect(func(key: String): selected_online_chapter = key)
	room_hub_screen.visibility_picked.connect(func(value: String): room_hub_host_visibility = value)
	room_hub_screen.room_open_requested.connect(_open_room_from_hub)
	room_hub_screen.cards_redrawn.connect(_follow_hub_tap)
	room_hub_screen.host_requested.connect(_host_from_room_hub)
	room_hub_screen.tester_code_requested.connect(_open_tester_code_from_hub)
	room_hub_screen.join_code_requested.connect(_join_from_room_hub)
	room_hub_screen.retry_requested.connect(_retry_from_room_hub)
	room_hub_screen.room_remove_requested.connect(_remove_room_from_hub)
	room_hub_screen.set_held_request(_held_room_request())
	add_child(room_hub_screen)
	room_hub_screen.show_notice(notice)
	_refresh_together_locks(room_hub_screen)
	if refresh: _refresh_room_hub_when_idle(room_hub_screen)

## The hub can open before the saved tester code is read; once it is, the
## hosting locks are drawn again so a tester never keeps a stale lock.
func _refresh_together_locks(hub: Node) -> void:
	if not _tester_checks_enabled() or (is_instance_valid(tester_access) and tester_access.cache_checked_context == _tester_context()): return
	await _load_cached_tester()
	if is_instance_valid(hub) and hub == room_hub_screen and mode == "rooms": hub.set_chapters(_together_chapters())

## Leaving a room or a failed room request lands on the hub. When the hub
## cannot open (no service or identity), Home is the safe place instead.
func _return_to_room_hub(notice: String = "", refresh: bool = true) -> void:
	relay_menu_generation += 1
	if not api.configured() or not _relay_identity().ready:
		_show_home()
		if not notice.is_empty(): _toast(notice)
		return
	_open_room_hub(notice,refresh)

func _refresh_room_hub_when_idle(hub: CanvasLayer) -> void:
	# The hub's read takes its turn after a room save or replay delivery still
	# out, and keeps its saved list meanwhile.
	if not is_instance_valid(hub) or hub != room_hub_screen: return
	await hub.refresh()
	if is_instance_valid(hub) and hub == room_hub_screen: hub.set_held_request(_held_room_request())

## After the hub's confirm step: "close" ends a room still in play for both
## members (DELETE), "leave" drops a room the other member closed, and "hide"
## takes a finished room off this device's list without a request. The other
## member's inbox then shows a closed room as closed.
func _remove_room_from_hub(room: Dictionary, action: String) -> void:
	var version := int(room.get("api_version",0))
	var room_id := str(room.get("room_id",""))
	if mode != "rooms" or not is_instance_valid(room_hub_screen) or room_inbox == null or not _relay_identity().ready or room_id.is_empty(): return
	var hub := room_hub_screen
	var inbox: RefCounted = room_inbox
	if action == "hide":
		inbox.hide(room)
		hub.show_notice("")
		return
	if version not in [1,2]: return
	var identity := _tester_context()
	var path := "/v%d/rooms/%s" % [version,room_id]
	hub.set_removing(true)
	var response: Dictionary
	if action == "close":
		response = await api.request_json(HTTPClient.METHOD_DELETE,path)
		# Already closed by the other member: the room is gone, so only the link remains.
		if not response.get("ok",false) and str(response.get("code","")) == "room_not_found" and identity == _tester_context():
			response = await api.request_json(HTTPClient.METHOD_POST,path+"/leave",{"schema_version":1})
	else:
		response = await api.request_json(HTTPClient.METHOD_POST,path+"/leave",{"schema_version":1})
	# The server has acted even if the player has moved on; keep this device in step.
	if response.get("ok",false) and identity == _tester_context():
		inbox.forget(version,room_id)
		if friend_room_events != null: friend_room_events.forget({"api_version":version,"room_id":room_id})
		if friend_share_target.get("api_version") == version and friend_share_target.get("room_id") == room_id: friend_share_target = {}
		var saved: Dictionary = saves.data.get("room",{})
		if version == 1 and saved.get("room_id") == room_id and saves.data.get("pending_turn",{}).is_empty() and saves.data.get("room_draft",{}).is_empty():
			saves.update_values({"room":{}})
			if active_room.get("room_id") == room_id: active_room = {}
	if not is_instance_valid(hub) or hub != room_hub_screen: return
	hub.set_removing(false)
	if response.get("ok",false): hub.show_notice("")
	else:
		hub.show_notice(str(response.get("error",PlayerCopy.ROOMS_API_1C556A121773)))
		_refresh_room_hub_when_idle(hub)

## A create or join request saved before its reply arrived, or a room with an
## unfinished redo request. Either blocks other rooms until it is retried.
func _held_room_request() -> String:
	if relay_session == null: return ""
	if not relay_session.pending_lobby().is_empty(): return "lobby"
	return "redo" if not relay_session.pending_redo_room().is_empty() else ""

func _retry_from_room_hub(kind: String) -> void:
	if mode != "rooms" or relay_session == null or not _relay_identity().ready: return
	var pending_redo: String = relay_session.pending_redo_room()
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true
	# A retry needs the service's chapters, which a fresh start has not read yet.
	var generation := relay_menu_generation + 1
	await _show_relay_rooms()
	if generation != relay_menu_generation or mode != "relay_rooms" or relay_session == null: return
	if kind == "lobby": await _relay_lobby_action("retry")
	elif not pending_redo.is_empty(): await _relay_lobby_action("open",pending_redo)
	else: _return_to_room_hub()

## Chapter picker entries for Play with a friend. The hub lists offered chapters
## and hosts through hosting_key; once the server's chapters are known, a
## chapter it cannot create at any version is tagged unavailable online.
## Locks follow hosting access, which a Test Store purchase alone does not give.
func _together_chapters() -> Array[Dictionary]:
	var reason := _hosting_lock_reason()
	var known: bool = relay_session != null and not relay_session.capabilities.is_empty()
	var result: Array[Dictionary] = []
	for offered: String in ChapterRegistry.offered_keys():
		var tag := ""
		if known and not relay_session.supports_creation(ChapterRegistry.hosting_key(offered,relay_session.supports_creation)): tag = " · unavailable online"
		var item := ChapterPicker.entry(offered)
		item.locked = item.premium and not reason.is_empty()
		item.tag = tag
		if item.locked:
			item.lock_reason = reason
			# Owned through the Test Store: the card says the code is what is missing.
			if reason == Purchases.HOSTING_NEEDS_TESTER_CODE: item.note = PlayerCopy.HOSTING_NEEDS_TESTER_CODE
		result.append(item)
	return result

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

## Rooms whose replay this phone saved, in the inbox room shape. Once both
## players save a finished room's replay the server keeps only a compact record,
## so this names such a room when the inbox cannot.
func _hub_saved_replay_rooms() -> Array:
	var rooms: Array = []
	if not _relay_identity().ready: return rooms
	if shared_replays == null: shared_replays = SharedReplays.new(api,_relay_identity)
	for room: Dictionary in shared_replays.rooms():
		if room.get("family") != "chapter": continue
		var members: Array[String] = []
		for member: Variant in [room.get("host_id"),room.get("guest_id")]:
			if member is String: members.append(member)
		rooms.append({
			"api_version": 2,
			"room_id": str(room.get("room_id","")),
			"chapter_key": str(room.get("chapter_key","")),
			"chapter_title": str(room.get("title","")),
			"member_ids": members,
			"status": "completed",
			"revision": 0,
			"remote_activity_sequence": 0,
			"activity_at": 0,
			"family": "relay",
		})
	return rooms

func _hub_history_chapter(summary: Dictionary) -> String:
	# Two versions of a chapter share a title, so match the room's own key.
	var key: String = relay_session.room_chapter(str(summary.get("room_id","")))
	return key if not key.is_empty() else "unknown"

func _friend_display_name(friend: String) -> String:
	## One place to turn a friend's player id into the name shown on screen:
	## their local nickname when set, otherwise "a friend". Never the raw id.
	if friend.is_empty(): return ""
	if friend_nicknames == null: return FriendNicknames.FALLBACK
	return friend_nicknames.display_name(str(api.base_url),str(api.player_id),friend)

## A Your rooms card's member line: the friend's name opens the line, and the
## player is left out.
func _hub_member_name(member: String) -> String:
	if member == str(api.player_id): return ""
	return FriendNicknames.sentence_start(_friend_display_name(member))

func _close_room_hub() -> void:
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true
	_show_home()

func _open_friends_from_room_hub(source: Control = null) -> void:
	if mode != "rooms": return
	# The hub stays up until Friends opens (_show_friends releases it then), so
	# a refused open reports its reason on the hub.
	await _hub_tap(source, PlayerCopy.HUB_OPENING, _online_flow_idle, PlayerCopy.HUB_FRIENDS_WAIT_EXPIRED, _show_friends.bind(_hub_message))

## The hub's taps (Continue, Open, Host, Join, Friends) go through one busy-tap
## gate (presentation/busy_tap_gate.gd): a tap made while earlier work its flow
## would refuse during is still running waits, with the tapped control saying
## so; a later tap replaces it; it runs only while this hub is still up.
## Requests themselves wait their turn in the API's request queue.
var _hub_gate: BusyTapGate
var _hub_tap_room := ""
func _hub_tap(source: Control, label: String, ready: Callable, expired: String, run: Callable, room_id: String = "") -> void:
	_hub_tap_room = room_id
	var hub := room_hub_screen
	if not is_instance_valid(hub):
		await run.call() # No hub: nothing on screen to label or wait for.
		return
	# A new tap clears the last one's reason.
	hub.show_notice("")
	if _hub_gate == null or _hub_gate.area() != hub: _hub_gate = BusyTapGate.new(hub)
	await _hub_gate.tap(source, label, ready, run,
		func() -> bool: return mode == "rooms" and is_instance_valid(hub) and hub == room_hub_screen,
		func() -> void: _hub_message(expired))

## A refresh that rebuilt the room cards while a room's tap waits: the new card's button carries its label.
func _follow_hub_tap() -> void:
	if _hub_gate != null and _hub_gate.waiting() and not _hub_tap_room.is_empty() and is_instance_valid(room_hub_screen):
		_hub_gate.follow(room_hub_screen.room_action(_hub_tap_room))

## What a tap waits for: work its online flow refuses during (_relay_available).
func _online_flow_idle() -> bool:
	return not submission_in_flight and not foreground_refresh_running

## ... plus the room session, for taps that open or make a chapter room. A saved
## legacy turn is not transient; the room flow reports it as before.
func _room_session_idle() -> bool:
	return _online_flow_idle() and (relay_session == null or not relay_session.busy())

## A reason the hub tap stopped, on the hub when it is up, or on Home's toast
## after the room flow settles back to the hub.
func _hub_message(text: String) -> void:
	if mode == "rooms" and is_instance_valid(room_hub_screen):
		room_hub_screen.show_notice(text)
		return
	if not text.is_empty(): _toast(text)
	_settle_room_flow()

func _open_room_from_hub(room: Dictionary, source: Control = null) -> void:
	if mode != "rooms" or not _relay_identity().ready: return
	var version := int(room.get("api_version",0))
	var room_id := str(room.get("room_id",""))
	if room_id.is_empty(): return
	# Watch replay on a finished room opens the Together page at once; it handles
	# a save still in progress itself. A room in play waits for its flow.
	var waits_for := Callable() if room.get("status") == "completed" else _room_session_idle if version == 2 else _online_flow_idle
	await _hub_tap(source, PlayerCopy.HUB_OPENING_ROOM, waits_for, PlayerCopy.MAIN_8184DEB41266, _open_hub_room.bind(room), room_id)

func _open_hub_room(room: Dictionary) -> void:
	var version := int(room.get("api_version",0))
	var room_id := str(room.get("room_id",""))
	var inbox: RefCounted = room_inbox
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	ui.visible = true
	if room.get("status") == "completed":
		# Completed rooms open their exact shared replay, which also counts as
		# seeing the room's latest activity.
		if inbox != null: inbox.confirm_room_rendered(version,room_id)
		replays_flow.open_shared_replay_room(room_id)
		return
	if version == 2:
		await _relay_lobby_action("open",room_id)
		if mode == "relay_online" and relay_session != null and relay_session.coordinator != null and relay_session.coordinator.snapshot().get("room_id") == room_id:
			if inbox != null: inbox.confirm_room_rendered(2,room_id)
	elif version == 1:
		await _open_friend_legacy(room_id)
		if mode == "room" and active_room.get("room_id") == room_id:
			if inbox != null: inbox.confirm_room_rendered(1,room_id)
		else: _settle_room_flow()
	else:
		_return_to_room_hub("This room can't be opened on this version of After You.")

func _host_from_room_hub(chapter_key: String, visibility: String, source: Control = null) -> void:
	if mode != "rooms" or not _relay_identity().ready: return
	var reason := _hosting_lock_reason()
	if ChapterRegistry.descriptor(chapter_key).get("premium",false) and not reason.is_empty():
		if reason == Purchases.HOSTING_NEEDS_TESTER_CODE:
			_open_tester_code_from_hub()
			return
		# Hosting a paid island needs the Full Journey; show how to unlock it
		# before entering the lobby. Never auto-create a room afterwards.
		if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
		room_hub_screen = null
		room_inbox = null
		ui.visible = true
		store_flow.show_hosting_locked(chapter_key)
		return
	selected_online_chapter = chapter_key
	room_hub_host_visibility = visibility
	await _hub_tap(source, PlayerCopy.HUB_OPENING_ROOM, _room_session_idle, PlayerCopy.MAIN_8184DEB41266, _host_hub_room.bind(chapter_key))

func _host_hub_room(chapter_key: String) -> void:
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true
	await _show_relay_rooms(chapter_key)
	if mode != "relay_rooms" or relay_session == null: return
	var host_key := ChapterRegistry.hosting_key(ChapterRegistry.offered_key(chapter_key),relay_session.supports_creation)
	if relay_session.supports_creation(host_key):
		await _relay_lobby_action("create",host_key)
	else:
		_return_to_room_hub(relay_session.last_error if not relay_session.last_error.is_empty() else PlayerCopy.MAIN_73FEF220EAF1)

## A chapter the player owns through the Test Store waits only for a tester
## code to host, so its card and the host button go straight to that screen.
func _open_tester_code_from_hub() -> void:
	if mode != "rooms": return
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true
	store_flow.show_tester_access()

func _join_from_room_hub(code: String, source: Control = null) -> void:
	if mode != "rooms" or not _relay_identity().ready: return
	# Accept room-<code> and legacy input; a friend code gets a clear local error.
	var parsed := ShareCodes.parse(code,ShareCodes.ROOM)
	if not parsed.ok:
		_hub_message(ShareCodes.error_message(parsed,PlayerCopy.ROOMS_API_57B8AA801916))
		return
	await _hub_tap(source, PlayerCopy.HUB_JOINING, _room_session_idle, PlayerCopy.HUB_JOIN_WAIT_EXPIRED, _join_hub_code.bind(str(parsed.id)))

func _join_hub_code(code: String) -> void:
	# A refusal reports its reason on the hub.
	if not await _prepare_ordinary_navigation(_hub_message) or mode != "rooms": return
	var context := _friends_route_context()
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST,"/v1/invitations/resolve",{"invite_code":code},_friends_route_current.bind(context))
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
		_hub_message(str(response.get("error","Invitation unavailable")))
		return
	var data: Variant = response.get("data")
	if not data is Dictionary or data.size() != 3 or data.get("schema_version") != 1 or data.get("family") not in ["legacy","relay"] or RoomsApi.json_int(data.get("api_version")) not in [1,2]:
		_hub_message("Invitation unavailable")
		return
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	room_inbox = null
	ui.visible = true
	if data.api_version == 2:
		await _join_chapter_room(code)
	else:
		await _join_room(code)

func _show_friends(report: Callable = Callable()) -> void:
	if _online_gated(): return
	var from_home := mode == "home"
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available(report) or not await _ensure_identity(report): return
	if view != store_view_generation or lifecycle != lifecycle_generation or application_backgrounded or is_instance_valid(friends_screen): return
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
		title = RoomChapterTitle.for_room(room,"Current room")
		if room.get("host_id") == api.player_id: shareable = current.duplicate(true)
	elif current.get("api_version") == 1:
		title = RoomChapterTitle.legacy_title(active_room.get("level_id"),"Current room")
		if active_room.get("host_id") == api.player_id: shareable = current.duplicate(true)
	running = false
	mode = "friends"
	_sync_presence()
	ui.visible = false
	friends_screen = FriendsScreen.new()
	friends_screen.client = friends_client
	friends_screen.event_client = friend_room_events
	friends_screen.nickname_store = friend_nicknames
	friends_screen.notification_transport = turn_notifications
	friends_screen.hosting_view_ready.connect(notification_flow.hosting_view_ready)
	friends_screen.room_shared.connect(_friends_room_shared)
	friends_screen.shareable_room = shareable
	friends_screen.room_title = title
	friends_screen.shared_room_title = _shared_room_title
	if not current.is_empty():
		var snapshot: Dictionary = relay_session.coordinator.snapshot() if current.get("api_version") == 2 else active_room
		friends_screen.room_status = "Waiting for friend" if snapshot.get("guest_id") == null else "Friend joined"
	friends_screen.openable_room = not current.is_empty()
	friends_screen.closed.connect(_leave_friends)
	friends_screen.host_requested.connect(_host_friend_room)
	friends_screen.open_requested.connect(_return_to_friend_room)
	friends_screen.join_requested.connect(_join_friend_room)
	add_child(friends_screen)

## The chapter of a room shared with friends, from that room's own record on
## this phone; "" when the phone does not have it.
func _shared_room_title(room: Dictionary) -> String:
	var room_id := str(room.get("room_id",""))
	if room.get("api_version") == 2 and relay_session != null:
		return RoomChapterTitle.title(relay_session.room_chapter(room_id),"")
	if room.get("api_version") == 1:
		for saved: Variant in [active_room,saves.data.get("room",{})]:
			if saved is Dictionary and saved.get("room_id") == room_id: return RoomChapterTitle.legacy_title(saved.get("level_id"),"")
	return ""

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

## Shares the hosted room with all friends, or stops sharing it. The server
## refuses a hosting alert for a room that is not shared, so a room that still
## owes its alert sends it here, once, right after the share is confirmed.
func _share_current_room(target: Dictionary, shared: bool = true) -> Dictionary:
	if _room_share_busy or not _current_room_share_allowed(target): return {"ok": false, "message": "Room unavailable"}
	if friends_client == null: friends_client = FriendsClient.new(api,_relay_identity)
	var context := _friends_route_context()
	_room_share_busy = true
	_room_share_changed(target)
	var okay := false
	var attempted := false
	if await _friends_api_idle(context, friends_client) and _current_room_share_allowed(target):
		attempted = true
		okay = await friends_client.share_room(target if shared else null)
	if okay and shared and _friends_route_current(context) and _current_room_share_allowed(target): await _send_owed_alert(target)
	elif attempted and not okay and shared and friends_client.last_code in ROOM_GONE_CODES: _friend_events().forget(target)
	_room_share_busy = false
	if not _friends_route_current(context) or not _current_room_share_allowed(target): return {"ok": false, "ignored": true}
	_room_share_changed(target)
	var error: String = friends_client.last_error if not friends_client.last_error.is_empty() else "Friends unavailable"
	if not okay: return {"ok": false, "message": error}
	return {"ok": true, "message": "Shared with friends" if shared else ""}

## Whether the room is the one shared with friends, and whether a change is in flight.
func _room_share_view(target: Dictionary) -> Dictionary:
	var shared: Variant = friends_client.shared_room() if friends_client != null else null
	return {"shared": FriendsClient.same_room(shared, target), "busy": _room_share_busy}

func _room_share_changed(target: Dictionary) -> void:
	if target.get("api_version") == 2 and is_instance_valid(relay_child) and relay_child.has_method("update_share_controls"): relay_child.update_share_controls()

static func _room_share_key(room: Dictionary) -> String:
	return "%d:%s" % [int(room.get("api_version", 0)), str(room.get("room_id", ""))]

## The Friends client sends one of its own requests at a time; wait briefly for one in flight.
func _friends_api_idle(context: Dictionary, client: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while client.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _friends_route_current(context): return false
	return not client.busy and _friends_route_current(context)

func _add_current_room_share(card: VBoxContainer) -> void:
	var target := {"api_version": 1, "room_id": active_room.get("room_id", "")}
	if not _current_room_share_allowed(target): return
	var status := _label("All friends",17)
	var button := _list_button("Share current room",func(): _share_room_from_card(target, card, status),false)
	button.name = "ShareCurrentRoom"
	button.disabled = _room_share_busy
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
	_wire_shared_history()
	var session := RelayOnline.new(api,_relay_identity)
	session.accepted_pair_cache = shared_replays.cache_accepted_receipt
	session.replay_archive_cache = shared_replays.cache_transferred_entries
	session.replay_history_cache = shared_replays.cache_history_pairs
	return session

## Android backs up when the phone is idle; the list it follows is refreshed whenever
## the app goes to the background, so it names the files saved since.
func _write_backup_plan() -> void:
	if OS.get_name() == "Android": BackupPlan.write()

## Replays plays a part the server let go from this phone's copy of its attempt.
func _wire_shared_history() -> void:
	shared_replays.history_pair = _history_pair
	shared_replays.ask_for_attempt = _ask_for_attempt

func _history_pair(room_id: String, chapter_key: String, pair_id: String) -> Dictionary:
	ensure_relay_session()
	return relay_session.history_pair(room_id, chapter_key, pair_id)

func _ask_for_attempt(room_id: String, position: int) -> void:
	ensure_relay_session()
	if relay_session.capabilities.is_empty(): await relay_session.load_capabilities()
	await relay_session.want_room_attempt(room_id, position)

func _invalidate_relay_identity(clear_notifications: bool = true) -> void:
	replays_flow.invalidate_identity()
	# A returning Main re-reads the same credentials before reusing its session.
	# Recovery/deletion clear authority; ordinary identity loading only holds it.
	Purchases.suspend_session(clear_notifications)
	store_flow.invalidate_identity()
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
	if is_instance_valid(tester_access):
		tester_access.forget_cache_check()
		tester_access.invalidate()
	if purchases is Purchases: purchases.invalidate_review_access()
	if clear_notifications and is_instance_valid(turn_notifications):
		turn_notifications.invalidate_identity()
	# Recovery or deletion drops an unopened invite link with the old account.
	if clear_notifications: invite_link_pending = ""
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

func _relay_available(report: Callable = Callable()) -> bool:
	if submission_in_flight or foreground_refresh_running or not saves.data.get("pending_turn",{}).is_empty():
		_report(report,PlayerCopy.MAIN_8184DEB41266)
		return false
	return true

func _show_relay_rooms(chapter: String = "") -> void:
	if _online_gated(): return
	if not chapter.is_empty():
		if ChapterRegistry.descriptor(chapter).is_empty():
			_toast(PlayerCopy.MAIN_ED8E80825350)
			_settle_room_flow()
			return
		selected_online_chapter = chapter
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available() or not await _ensure_identity() or view != store_view_generation or lifecycle != lifecycle_generation or application_backgrounded or not await _prepare_ordinary_navigation():
		_settle_room_flow()
		return
	if relay_session == null:
		relay_session = _new_relay_session()
	running = false
	relay_menu_generation += 1
	var generation := relay_menu_generation
	_draw_room_progress(PlayerCopy.MAIN_07713E9CC81E)
	var context := _friends_route_context()
	var loaded: bool = await relay_session.load_lobby()
	if generation != relay_menu_generation or not _friends_route_current(context):
		return
	# The caller continues from this progress card; a failed check returns to the hub.
	if not loaded: _return_to_room_hub(relay_session.last_error)

## The short wait while a room is checked, created, joined or opened. Back,
## Escape and Android Back return to the hub, as the old lobby's Back did.
func _draw_room_progress(message: String) -> void:
	mode = "relay_rooms"
	var card := _card(minf(700.0,maxf(280.0,ui.size.x-48.0)))
	card.name = "RoomProgress"
	card.add_child(_label("Play with a friend",34,CREAM,true))
	card.add_child(_paragraph(message,minf(640.0,maxf(240.0,ui.size.x-88.0))))
	var back := _back_button("Back",_return_to_room_hub,false)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size.x = 128
	card.add_child(back)

func _relay_lobby_action(action: String, value: String = "") -> void:
	if relay_session == null or relay_session.busy() or not _relay_available() or not _relay_identity().ready or not _legacy_redo_navigation_ready() or not await _prepare_ordinary_navigation():
		_settle_room_flow()
		return
	relay_menu_generation += 1
	var generation := relay_menu_generation
	_draw_room_progress(PlayerCopy.MAIN_6734074E99D4)
	var context := _friends_route_context()
	# After a cold start the hub opens rooms before anything read the service's
	# chapters, and a room opened without them cannot save a turn.
	if relay_session.capabilities.is_empty():
		var loaded: bool = await relay_session.load_lobby()
		if generation != relay_menu_generation or not _friends_route_current(context): return
		if not loaded:
			_return_to_room_hub(relay_session.last_error)
			return
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
		_return_to_room_hub(relay_session.last_error)
		return
	var hosted := {"api_version":2,"room_id":room_id}
	var sharing: bool = bool(saves.data.settings.get("share_online_status", true))
	var host: bool = relay_session.coordinator != null and relay_session.coordinator.snapshot().get("host_id") == api.player_id
	if action in ["create", "retry"] and host and room_hub_host_visibility == "friends" and sharing:
		# A Friends room is shared as soon as it exists and sends one hosting
		# alert. The alert is saved as owed first, so a restart keeps it.
		_friend_events().owe(hosted)
		_share_current_room.call_deferred(hosted)
	elif action == "open" and sharing and _friend_events().owes(hosted):
		# Reopened before its alert went out (e.g. after a restart): finish it.
		_share_current_room.call_deferred(hosted)
	_enter_online_relay()

## A room flow that stopped before drawing anything (the caller already left
## the hub or Friends) returns to the hub instead of leaving a bare screen.
func _settle_room_flow() -> void:
	# A toast sits under the hub, so its reason moves into the hub's notice.
	if mode in ["rooms", "relay_rooms"] and not is_instance_valid(room_hub_screen): _return_to_room_hub(toast_label.text if toast_label.visible else "")

func _friend_events() -> FriendRoomEventsClient:
	if friend_room_events == null: friend_room_events = FriendRoomEventsClient.new(api,_relay_identity)
	return friend_room_events as FriendRoomEventsClient

func _publish_room_availability(room: Dictionary) -> bool:
	if not _relay_identity().ready or not FriendRoomEventsClient.valid_room(room): return false
	var events: FriendRoomEventsClient = _friend_events()
	# A delivery failure never undoes the room or its share. The client keeps
	# the publication id after a failure, so a later retry cannot alert twice.
	var deadline := Time.get_ticks_msec() + 5000
	while events.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _relay_identity().ready: return false
	if events.busy: return false
	var result: Dictionary = await events.publish(room)
	return result.get("ok", false)

## Sends the one alert a shared room still owes, from any place that shared it.
func _send_owed_alert(room: Dictionary) -> void:
	if not _relay_identity().ready or not _friend_events().owes(room): return
	if not await _publish_room_availability(room): _retry_owed_alert(room)

## A few quiet retries with backoff, only while the room is still shared and
## still owes its alert; the saved id keeps every retry at one alert.
func _retry_owed_alert(room: Dictionary) -> void:
	var key := _room_share_key(room)
	if _owed_alert_retrying == key: return
	_owed_alert_retrying = key
	var identity := _tester_context()
	for delay: float in owed_alert_retry_s:
		await get_tree().create_timer(delay).timeout
		if identity != _tester_context() or not _relay_identity().ready or not _friend_events().owes(room): break
		if friends_client == null or not FriendsClient.same_room(friends_client.shared_room(), room): break
		if await _publish_room_availability(room): break
	if _owed_alert_retrying == key: _owed_alert_retrying = ""

func _friends_room_shared(room: Dictionary) -> void:
	_send_owed_alert(room)

func _enter_online_relay() -> void:
	if not _legacy_redo_navigation_ready(): return
	if relay_session == null or relay_session.coordinator == null or relay_session.busy() or is_instance_valid(relay_child):
		return
	lifecycle_generation += 1
	foreground_refresh_queued = false
	foreground_response = {}
	running = false
	_release_room_hub()
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
	relay_child.turn_notification_status = notification_flow.status
	relay_child.enable_turn_notifications = notification_flow.enable
	relay_child.share_current_room = _share_current_room
	relay_child.room_share_state = _room_share_view
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
	_sync_presence()
	_return_to_room_hub(relay_session.last_error if relay_session != null else "",false)
	_deliver_then_refresh_hub.call_deferred()

## The one replay delivery after leaving play goes first; the hub reads its
## rooms after, so neither request finds the API busy and gives up.
func _deliver_then_refresh_hub() -> void:
	await _deliver_completed_replay()
	if is_instance_valid(room_hub_screen) and mode == "rooms": _refresh_room_hub_when_idle(room_hub_screen)

func _deliver_completed_replay() -> void:
	# After leaving completed play, save that room's replay to this phone. It is
	# never a playback/tick poll: a few quiet retries cover a busy or offline
	# moment, then the next leave or Watch replay tries again.
	if relay_session == null or relay_session.coordinator == null or not _relay_identity().ready: return
	var room: Dictionary = relay_session.coordinator.snapshot()
	if not relay_session.coordinator.pending().is_empty(): return
	if room.get("active_role") != "complete":
		# With room history, a room still in play also keeps its finished attempts here.
		if _history_mode(relay_session) and int(room.get("branch", 0)) > 0: await replays_flow.save_finished_replay(str(room.room_id), int(room.revision), true)
		return
	await replays_flow.save_finished_replay(str(room.room_id), int(room.revision))

## Room history is on for this session (older test doubles have no such method).
static func _history_mode(session: RefCounted) -> bool:
	return session != null and session.has_method("history_mode") and session.history_mode()

func _ensure_identity(report: Callable = Callable()) -> bool:
	if saves.data.has(DeletedPhotos.MARKER_KEY) or not deleted_identity_owner.is_empty():
		_report(report,PlayerCopy.MAIN_A9AD59F7E952)
		return false
	if not pending_recovery.is_empty():
		_report(report,PlayerCopy.MAIN_0F8B4A22AEFC)
		return false
	if identity_restart_required:
		_report(report,PlayerCopy.MAIN_5BC549F4B951)
		return false
	if identity_loading:
		var deadline := Time.get_ticks_msec()+10000
		while identity_loading and Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
		if identity_loading:
			_report(report,PlayerCopy.MAIN_29B12DE56EEF)
			return false
	if not api.player_id.is_empty() and not api.device_token.is_empty():
		return true
	if identity_busy:
		_report(report,PlayerCopy.MAIN_21155817127A)
		return false
	if not secrets.is_available():
		_report(report,PlayerCopy.for_platform(PlayerCopy.MAIN_3E8E7DA4CEE6,PlayerCopy.MAIN_3E8E7DA4CEE6_IOS))
		return false
	if identity_read_state!=IdentityReadState.MISSING:
		_report(report,PlayerCopy.MAIN_F0A53024D858)
		return false
	identity_busy=true
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/identity")
	if not response.ok:
		identity_busy=false
		_report(report,response.error)
		return false
	var persisted: Dictionary=await _await_secret(secrets.put_secret("player_identity",JSON.stringify(response.data)))
	identity_busy=false
	if not persisted.ok:
		identity_read_state=IdentityReadState.FAILED
		_report(report,PlayerCopy.MAIN_71B742112D9F)
		return false
	identity_read_state=IdentityReadState.LOADED
	identity_data=response.data.duplicate(true)
	api.player_id=str(response.data.player_id)
	api.device_token=str(response.data.device_token)
	store_flow.configure_purchases()
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
	var response: Dictionary=await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms",{"idempotency_key":RoomsApi.new_key(),"simulation_version":Simulation.COMFORT_SIMULATION_VERSION})
	if not _friends_route_current(context): return
	_accept_room(response)

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
	var parsed := ShareCodes.parse(code,ShareCodes.ROOM)
	if not parsed.ok:
		_toast(ShareCodes.error_message(parsed,PlayerCopy.ROOMS_API_57B8AA801916))
		return
	var context := _friends_route_context()
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/join",{"invite_code":parsed.id,"simulation_version":Simulation.COMFORT_SIMULATION_VERSION})
	if _friends_route_current(context): _accept_room(response)

func _refresh_room() -> void:
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
		var invitation := ShareCodes.display(ShareCodes.ROOM,active_room.invite_code)
		card.add_child(_paragraph("Invitation code: "+invitation))
		card.add_child(_list_button("Copy invitation code",func(): DisplayServer.clipboard_set(invitation); _toast("Invitation code copied."),false))
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
		notification_flow.add_offer(card)
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
		queue_foreground_refresh()
		if not application_backgrounded: _refresh_room())
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
	if before != client.view(): _redraw_room_when_free(str(active_room.get("room_id","")))

## A poll's redraw of the room page waits for a tap in progress to finish, or
## the button under the finger would be freed and the tap lost.
func _redraw_room_when_free(room_id: String) -> void:
	await TouchInput.redraw_when_released(overlay,func() -> bool: return mode=="room" and str(active_room.get("room_id",""))==room_id,_show_room_detail)

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
	if submission_in_flight:
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

## Legacy room writes (a turn, its check, Next island, a fork, a reaction) run
## one at a time: submission_in_flight holds while one is out, so a second tap
## meanwhile does nothing and other flows wait for it. Returns the work's
## result; nothing when another write is already out.
func _one_room_write(work: Callable) -> Variant:
	if submission_in_flight: return {"ok": false, "status": 0, "code": "request_busy", "ignored": true}
	submission_in_flight = true
	var result: Variant = await work.call()
	submission_in_flight = false
	return result

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
	if submission_in_flight or not await _ensure_identity():
		return
	var pending: Dictionary=saves.data.get("pending_turn",{})
	if pending.is_empty():
		return
	if pending.has("owner_player_id") and pending.owner_player_id!=api.player_id:
		_toast(PlayerCopy.MAIN_ECBD713D8F0C)
		return
	var response: Dictionary=await _one_room_write(api.request_json.bind(HTTPClient.METHOD_GET,"/v1/rooms/"+str(pending.room_id)))
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
	card.add_child(_back_button("Back",_show_rooms,false))

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
	if submission_in_flight or not saves.data.get("pending_turn",{}).is_empty():
		return
	var context := _foreground_room_context(str(active_room.room_id))
	var response: Dictionary = await _one_room_write(api.request_json.bind(HTTPClient.METHOD_POST,"/v1/rooms/"+str(active_room.room_id)+"/fork",{"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key()}))
	if context == _foreground_room_context(str(active_room.get("room_id",""))): _accept_room(response)

func _advance_room() -> void:
	if not _relay_identity().ready or not _legacy_redo_navigation_ready(): return
	if not _campaign_depart_for_ordinary(): return
	if submission_in_flight or not saves.data.get("pending_turn",{}).is_empty():
		return
	var context := _foreground_room_context(str(active_room.room_id))
	var response: Dictionary = await _one_room_write(api.request_json.bind(HTTPClient.METHOD_POST,"/v1/rooms/"+str(active_room.room_id)+"/advance",{"base_revision":active_room.revision,"idempotency_key":RoomsApi.new_key()}))
	if context == _foreground_room_context(str(active_room.get("room_id",""))): _accept_room(response)

func _show_saved_rooms() -> void:
	if not _relay_available() or not await _ensure_identity():
		return
	if not await _prepare_ordinary_navigation(): return
	ensure_relay_session()
	if relay_session.busy(): return
	running = false
	mode = "recent_rooms"
	var loading := _card(760)
	loading.add_child(_label("Recent online rooms",34,CREAM,true))
	loading.add_child(_paragraph(PlayerCopy.MAIN_07713E9CC81E,680))
	loading.add_child(_back_button("Back",_show_rooms,false))
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
			var button := _list_button(RoomChapterTitle.legacy_title(room.get("level_id"),"Island")+" · "+("Ready to replay" if room.get("active_role")=="complete" else "In progress"),func(): _accept_room({"ok":true,"data":room}),false)
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
		var button := _back_button(entry[0],entry[1],false) if entry[0] == "Back" else _button(entry[0],entry[1],false)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)

func _show_online_collection() -> void:
	replays_flow.show_shared_replays()

func _scroll_list(card: VBoxContainer, scrolling: bool=true) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",10)
	if scrolling:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size=Vector2(600,270)
		# Every row passes drags up, including plain _button links.
		ControlTheme.touch_scroll(scroll)
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
	if application_backgrounded or not world.visible or _world_covered:
		if _suspended_world_id != world_id:
			_suspended_world_id = world_id
			_world_was_processing = world.is_processing()
		world.set_process(false)
	elif _suspended_world_id == world_id:
		world.set_process(_world_was_processing)
		_suspended_world_id = 0
	else:
		_suspended_world_id = 0

## Friends, the room hub, Safety and Redo requests are opaque full-screen layers, and full pages
## (chapters, Replays, Together) sit behind a 0.9 shade. Behind all of them the
## 3D Home world was still drawn (some 400 draw calls) and run every frame.
## Behind an opaque layer it is simply not drawn or run. Behind a page shade a
## still of it (one render through its own camera) takes its place under the
## shade, so the page looks the same. The live world returns when they close;
## its own visibility is left to its owners.
## The still lives while the world is frozen behind it: a page that redraws
## behind a new shade gets the same still back, with no new render or readback
## and the 3D pass left off. It is retaken when the world, its camera, the
## screen size or the render scale changed, and let go once the live world shows.
const FROZEN_SHADE_ALPHA := 0.85
var _backdrop_view: SubViewport
var _backdrop_shade_id := 0
var _backdrop_frames := 0
var _backdrop_ready := false
var _backdrop_still: Texture2D
var _backdrop_key: Array = []
## Reads the rendered still from its view; a test stands in here for a
## renderer that gives no image (headless).
var backdrop_reader: Callable

func _service_world_cover() -> void:
	var shade: ColorRect = overlay_shade if is_instance_valid(overlay_shade) and overlay_shade.color.a >= FROZEN_SHADE_ALPHA and overlay.visible and is_instance_valid(world) and world.visible and not application_backgrounded else null
	var shade_id := shade.get_instance_id() if shade != null else 0
	if shade_id != _backdrop_shade_id: _start_backdrop(shade)
	elif shade != null and not _backdrop_ready and is_instance_valid(_backdrop_view): _finish_backdrop(shade)
	var covered := is_instance_valid(friends_screen) or is_instance_valid(room_hub_screen) or is_instance_valid(safety_screen) or is_instance_valid(redo_screen) or (shade != null and _backdrop_ready)
	if not covered and _backdrop_still != null:
		_backdrop_still = null
		_backdrop_key = []
	if covered == _world_covered: return
	_world_covered = covered
	get_viewport().disable_3d = covered
	_sync_world_processing()

## How often this screen needs drawing (services/frame_policy.gd): chapters
## and replays answer for themselves; play, the completion moment and a
## chapter's loading card need full rate; every menu, card and page is calm
## (touching the screen, Home's camera included, brings full rate back).
func frame_demand() -> String:
	if not capture_path.is_empty(): return Frames.ACTIVE
	if is_instance_valid(relay_child): return relay_child.frame_demand() if relay_child.has_method("frame_demand") else Frames.ACTIVE
	if is_instance_valid(_chapter_opening): return Frames.ACTIVE
	if is_instance_valid(shared_replay_child): return Frames.ACTIVE if shared_replay_child.get("mode") in ["replay", "bloom"] else Frames.CALM
	if running or mode == "completion": return Frames.ACTIVE
	return Frames.CALM

## Renders the world once, through a copy of its camera, for the page shade.
func _start_backdrop(shade: ColorRect) -> void:
	if is_instance_valid(_backdrop_view): _backdrop_view.queue_free()
	_backdrop_view = null
	_backdrop_shade_id = shade.get_instance_id() if shade != null else 0
	_backdrop_ready = false
	_backdrop_frames = 0
	if shade == null or not is_instance_valid(world.get("camera")): return
	var source: Camera3D = world.camera
	if _backdrop_still != null and _backdrop_key_for(source) == _backdrop_key:
		_place_still(shade, _backdrop_still)
		return
	_backdrop_still = null
	_backdrop_key = []
	var view := SubViewport.new()
	view.size = get_viewport().size
	view.world_3d = get_viewport().world_3d
	# The same render scale as the live world (GraphicsPolicy), not native.
	view.scaling_3d_mode = get_viewport().scaling_3d_mode
	view.scaling_3d_scale = get_viewport().scaling_3d_scale
	view.msaa_3d = get_viewport().msaa_3d
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var lens := Camera3D.new()
	lens.projection = source.projection
	lens.keep_aspect = source.keep_aspect
	lens.fov = source.fov
	lens.size = source.size
	lens.near = source.near
	lens.far = source.far
	lens.h_offset = source.h_offset
	lens.v_offset = source.v_offset
	lens.cull_mask = source.cull_mask
	lens.environment = source.environment
	view.add_child(lens)
	add_child(view)
	lens.global_transform = source.global_transform
	lens.current = true
	_backdrop_view = view

## What a still shows: this world through this camera, at this size and scale.
func _backdrop_key_for(source: Camera3D) -> Array:
	var root := get_viewport()
	return [world.get_instance_id(), source.get_instance_id(), source.global_transform, source.fov, source.size,
		source.h_offset, source.v_offset, root.size, root.scaling_3d_scale, root.msaa_3d]

## Puts the still under the shade once it is rendered. A renderer that gives
## no image (headless) keeps the live world.
func _finish_backdrop(shade: ColorRect) -> void:
	_backdrop_frames += 1
	if _backdrop_frames < 2: return
	var image: Image = backdrop_reader.call(_backdrop_view) if backdrop_reader.is_valid() else _backdrop_view.get_texture().get_image()
	_backdrop_view.queue_free()
	_backdrop_view = null
	if image == null or image.is_empty(): return
	_backdrop_still = ImageTexture.create_from_image(image)
	# Keyed on the camera as the still freezes it: the live world ran on while
	# the still rendered and stops from here, so a redraw finds it unchanged.
	if is_instance_valid(world.get("camera")): _backdrop_key = _backdrop_key_for(world.camera)
	_place_still(shade, _backdrop_still)

func _place_still(shade: ColorRect, texture: Texture2D) -> void:
	var still := TextureRect.new()
	still.name = "FrozenWorld"
	still.texture = texture
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_SCALE
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["offset_left", "offset_top", "offset_right", "offset_bottom"]: still.set(side, shade.get(side))
	shade.get_parent().add_child(still)
	shade.get_parent().move_child(still, shade.get_index())
	_backdrop_ready = true

func _foreground_refresh_safe() -> bool:
	# A paused rehearsal is still active work. Do not swap its source recording,
	# revision or review screen behind the player's back.
	return not is_instance_valid(relay_child) and not application_backgrounded and not running and not submission_in_flight and mode in ["home","rooms","room","journey",ReplaysFlow.MODE_COLLECTION,"settings","saved"]

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
	store_flow.resume_purchase_access()
	if is_instance_valid(soundscape):
		soundscape.set_backgrounded(is_instance_valid(relay_child))
	lifecycle_generation+=1
	foreground_response={}
	foreground_refresh_queued=true
	if app_status != null and app_status.due(): _check_app_status()
	# Do not resume the simulation automatically. The player explicitly presses
	# Continue on the pause card, keeping the recording clock under their control.

## Asks whether this build must update before playing online: at launch, and on a
## resume once the last answer is six hours old. A later answer replaces an earlier
## one, so "off" or any error lifts a block.
func _check_app_status() -> void:
	if app_status == null or app_status.busy: return
	await app_status.check()
	if _update_gate_active(): return
	update_gate_dismissed = false
	if mode == "update_gate": _show_home()

## True while online play needs a newer build and there is a store page to get it from.
func _update_gate_active() -> bool:
	return app_status != null and app_status.required() and not UpdateGate.target(ClientIdentity.channel(), config).is_empty()

## Online entry points ask first: while gated they show the update screen instead.
func _online_gated() -> bool:
	if not _update_gate_active(): return false
	# A full-screen child (a room, a replay, Photo transfer, Safety, a redo request)
	# keeps its own Back; the screen then waits for Home instead of drawing beneath it.
	if is_instance_valid(relay_child) or is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen) or is_instance_valid(redo_screen):
		_toast(PlayerCopy.UPDATE_REQUIRED_ERROR)
		_request_update_gate()
		return true
	_show_update_gate()
	return true

## A notification or invite link that would open an online screen: the update screen
## shows on Home instead, once Home is free.
func _request_update_gate() -> void:
	update_gate_dismissed = false

## Replaces Home with the update screen when an answer says so. A turn, a chapter or
## any other screen is never interrupted; the screen waits for Home, and for a finger
## on a Home button to lift so that tap is not lost.
func _service_update_gate() -> void:
	if update_gate_dismissed or mode != "home" or not _update_gate_active(): return
	if application_backgrounded or running or is_instance_valid(relay_child) or is_instance_valid(_chapter_opening) or is_instance_valid(friends_screen) or is_instance_valid(room_hub_screen): return
	if is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen) or is_instance_valid(redo_screen): return
	# A card on Home (What's new, a confirmation) is read and closed first.
	if is_instance_valid(_whats_new_card): return
	for child: Node in ui.get_children():
		if child.get_script() == InGameModal: return
	if TouchInput.press_held(overlay): return
	_show_update_gate()

func _show_update_gate() -> void:
	running=false
	room_play=false
	hud.visible=false
	mode="update_gate"
	# Friends is a layer above the overlay: close it so the screen is never hidden.
	if is_instance_valid(friends_screen):
		var friends := friends_screen
		friends_screen = null
		friends.close()
	ui.visible=true
	var view := UpdateGate.view(str(app_status.result.get("min_version","")))
	var card := _card(600)
	card.add_child(_label(view.title,34,CREAM,true))
	card.add_child(_paragraph(view.body,560))
	var update := _button(view.update,_open_update_target)
	update.name = "UpdateGateUpdate"
	card.add_child(update)
	var solo := _button(view.solo,_play_solo_from_update_gate,false)
	solo.name = "UpdateGateSolo"
	card.add_child(solo)

func _open_update_target() -> void:
	var target := UpdateGate.target(ClientIdentity.channel(), config)
	if target.is_empty(): return
	if update_gate_open_url.is_valid(): update_gate_open_url.call(target)
	else: OS.shell_open(target)

func _play_solo_from_update_gate() -> void:
	update_gate_dismissed = true
	_show_journey()

## A route refused this build as too old: ask again, at most once a minute.
func _on_update_required() -> void:
	if app_status == null or app_status.busy: return
	if app_status.checked_at >= 0.0 and absf(app_status.now() - app_status.checked_at) < 60.0: return
	_request_update_gate()
	_check_app_status()

func _service_foreground_refresh() -> void:
	if not _foreground_refresh_safe() or foreground_refresh_running:
		return
	if not foreground_response.is_empty():
		var deferred := foreground_response
		foreground_response={}
		if int(deferred.get("generation",-1))==lifecycle_generation and str(deferred.get("context",""))==_foreground_room_context(str(deferred.room_id)):
			_apply_foreground_response(deferred.response,str(deferred.room_id))
	if api==null or identity_loading or identity_busy:
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
	var ticket: Dictionary=foreground_schedule.begin_if_due(now,true,false)
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
	return JSON.stringify([api.player_id,_token_digest(),relay_identity_epoch,lifecycle_generation,room_id])

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
			_redraw_room_when_free(requested_room)
	if confirmed:
		_toast(PlayerCopy.MAIN_A917FC21E486)
	# An unmatched pending request stays queued for explicit reconciliation.
	# Returning to the app never starts or retries a POST automatically.
	if mode == "room": _refresh_legacy_redo()

## A flow's reason for stopping goes where its caller shows reasons: Home's
## toast by default, the hub's notice (_hub_message) for a hub tap.
func _report(report: Callable, text: String) -> void:
	if report.is_valid(): report.call(text)
	else: _toast(text)

func _toast(text: String) -> void:
	toast_label.text=text
	toast_label.visible=true
	toast_time=6.0

func _process(delta: float) -> void:
	_service_world_cover()
	replays_flow.service_collection_replay()
	replays_flow.service_solo_collection()
	replays_flow.service_shared_replays()
	_service_home_keepsakes(delta)
	_sync_presence()
	_advance_completion_moment(delta)
	_service_foreground_refresh()
	if is_instance_valid(turn_notifications):
		turn_notifications.service(Time.get_ticks_msec(), not application_backgrounded, not submission_in_flight and not foreground_refresh_running and not running and (relay_session == null or not relay_session.busy()))
		notification_flow.service_route()
	_service_invite_link()
	_service_whats_new()
	_service_update_gate()
	_service_photo_resume()
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
	if mode not in ["home","journey"] or application_backgrounded or is_instance_valid(relay_child) or is_instance_valid(_chapter_opening): return
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
		_write_backup_plan()
	elif what==NOTIFICATION_APPLICATION_RESUMED:
		if is_instance_valid(turn_notifications): turn_notifications.queue_reconcile()
		_refresh_safe_area.call_deferred()
		_resume_application()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		# The update screen has no Back: the player updates or picks Play Solo.
		if account_flow.holds_back() or mode == "update_gate": return
		if _close_top_modal(): return
		if is_instance_valid(_whats_new_card): _whats_new_card.close()
		elif mode == ReplaysFlow.MODE_COLLECTION_LOADING: replays_flow.show_collection()
		elif mode == "story_lobby": _story_back()
		elif mode == "story_access": _draw_story_lobby()
		elif store_flow.handle_back(): pass
		elif mode in ["confirm_retry", "confirm_restart", ReplaysFlow.MODE_CONFIRM_DELETE]:
			if _retry_cancel.is_valid(): _retry_cancel.call()
		elif mode == "story_replay_chapters": _return_story_replay_lobby()
		elif mode == ReplaysFlow.MODE_SHARED_MEMORIES and not _story_replay_return.is_empty(): _back_to_story_replay_chapters()
		# Together replays: Android Back goes where their on-screen Back goes.
		elif mode in [ReplaysFlow.MODE_SHARED_REPLAYS, ReplaysFlow.MODE_SHARED_MEMORIES] and not is_instance_valid(shared_replay_child): _show_home()
		elif running or mode=="completion":
			_pause()
		elif mode=="license_text":
			_show_licenses()
		elif mode in ["licenses", StoreFlow.MODE_TESTER_ACCESS, "graphics_settings"]:
			_show_settings()
		elif mode=="recent_rooms":
			_show_rooms()
		elif mode=="relay_rooms":
			_return_to_room_hub()
		elif mode=="rooms" and is_instance_valid(room_hub_screen):
			room_hub_screen.go_back()
		elif mode=="rooms":
			# A room flow that left no hub behind: Back still goes Home.
			_close_room_hub()
		else:
			_back_on_screen()
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
	notification_flow.configure_service(turn_notifications, native)
	add_child(turn_notifications)

## The device token's SHA-256, kept until the token changes: several services
## build identity keys from it every frame.
var _digested_token := ""
var _token_sha := ""
func _token_digest() -> String:
	if api.device_token != _digested_token:
		_digested_token = api.device_token
		_token_sha = _digested_token.sha256_text()
	return _token_sha

## The online session, created on first use.
func ensure_relay_session() -> void:
	if relay_session == null: relay_session = _new_relay_session()

## The open legacy room is read again at the next foreground refresh.
func queue_foreground_refresh() -> void:
	foreground_refresh_queued = true

## A legacy room a notification named becomes the saved and shown room. False
## when the save cannot be written; nothing changes then.
func show_legacy_room(room: Dictionary, refresh_redo: bool) -> bool:
	if not saves.update_values({"room": room.duplicate(true)}): return false
	active_room = room.duplicate(true)
	friend_share_target = {"api_version":1,"room_id":active_room.room_id}
	_show_room_detail()
	if refresh_redo: _refresh_legacy_redo()
	return true

## Once a session, on Home: a turn that still waits for its photo because After You closed
## while the camera was open. Its room opens on request and offers that photo again.
func _service_photo_resume() -> void:
	if _photo_resume_checked or not _photo_resume_safe(): return
	_photo_resume_checked = true
	if not is_instance_valid(photo_resume_prompt):
		photo_resume_prompt = PhotoResumePrompt.new()
		photo_resume_prompt.open_requested.connect(_open_photo_resume_room)
		add_child(photo_resume_prompt)
	var owner := str(_relay_identity().player_id)
	var entry: Dictionary = await photo_resume_prompt.check(owner)
	if entry.is_empty() or not _photo_resume_safe() or str(_relay_identity().player_id) != owner: return
	photo_resume_prompt.show_prompt(ui, entry)

func _photo_resume_safe() -> bool:
	if mode != "home" or application_backgrounded or running or submission_in_flight or identity_loading or identity_busy or foreground_refresh_running or is_instance_valid(relay_child) or saves.read_only: return false
	if is_instance_valid(_whats_new_card): return false # One Home card at a time; this one waits.
	if _update_gate_active(): return false # The room cannot open until this build is updated.
	if not _relay_identity().ready or not saves.data.get("pending_turn", {}).is_empty() or not saves.data.get("room_draft", {}).is_empty(): return false
	if relay_session != null and (relay_session.busy() or not relay_session.can_leave_for_legacy() or (relay_session.coordinator != null and not relay_session.coordinator.draft().is_empty())): return false
	return _legacy_redo_navigation_ready("", false)

func _open_photo_resume_room(room_id: String) -> void:
	if _online_gated(): return
	if not _photo_resume_safe():
		_toast(PlayerCopy.MAIN_BE8E691311EE)
		return
	ensure_relay_session()
	if relay_session.capabilities.is_empty():
		if not await relay_session.load_lobby():
			_toast(PlayerCopy.MAIN_571E92F64ED1)
			return
		if not _photo_resume_safe(): return
	if not await relay_session.open_room(room_id):
		_toast(PlayerCopy.MAIN_BE8E691311EE)
		return
	# The room's first view finds the waiting photo and opens its card (relay_preview.gd).
	if _photo_resume_safe(): _enter_online_relay()

func _setup_invite_links() -> void:
	invite_link_bridge = InviteLinkBridge.new()
	invite_link_bridge._native = invite_link_native
	invite_link_bridge.received.connect(_invite_link_received)
	add_child(invite_link_bridge)
	# A link the last Main was holding when a solo chapter replaced it.
	var held := InviteLinkBridge.take_held()
	if not held.is_empty() and Time.get_ticks_msec() < int(held.expires_ms):
		invite_link_pending = str(held.id)
		invite_link_expires_ms = int(held.expires_ms)

func _invite_link_received(result: Dictionary) -> void:
	if not result.get("ok", false) or result.get("type") != ShareCodes.FRIEND:
		if is_instance_valid(toast_label): _toast(PlayerCopy.FRIEND_CODE_INVALID)
		return
	# A newer link replaces one that has not been shown yet.
	invite_link_pending = str(result.id)
	invite_link_expires_ms = Time.get_ticks_msec() + INVITE_LINK_TTL_MS
	invite_link_retry_ms = 0
	invite_link_attempts = 0
	invite_link_notice = false

## True while the player is in the middle of something a link must not interrupt.
func _invite_link_occupied() -> bool:
	if running or mode not in INVITE_LINK_MODES: return true
	if is_instance_valid(relay_child) or is_instance_valid(shared_replay_child) or is_instance_valid(photo_transfer_child) or is_instance_valid(safety_screen) or is_instance_valid(redo_screen): return true
	if not saves.data.get("pending_turn", {}).is_empty() or not saves.data.get("room_draft", {}).is_empty(): return true
	if relay_session != null and relay_session.coordinator != null and not relay_session.coordinator.draft().is_empty(): return true
	return false

## Short-lived work (requests, refreshes, identity reads) that only delays the link.
func _invite_link_settling() -> bool:
	if application_backgrounded or submission_in_flight or foreground_refresh_running or identity_loading or identity_busy: return true
	if identity_read_state in [IdentityReadState.UNCHECKED, IdentityReadState.LOADING]: return true
	return relay_session != null and relay_session.busy()

## At least as strict as NotificationFlow.route_safe. A link never creates an identity:
## without one it waits until the player opens Friends themselves.
func _invite_link_safe() -> bool:
	if saves.read_only or _invite_link_settling() or _invite_link_occupied(): return false
	if not _relay_identity().ready: return false
	if mode == "friends" and not is_instance_valid(friends_screen): return false
	if not _campaign_notification_unbound() or not _legacy_redo_navigation_ready("", false): return false
	return relay_session == null or relay_session.can_leave_for_legacy()

func _service_invite_link() -> void:
	if invite_link_pending.is_empty(): return
	var now := Time.get_ticks_msec()
	if now >= invite_link_expires_ms:
		invite_link_pending = ""
		return
	if invite_link_busy or now < invite_link_retry_ms: return
	if saves.read_only:
		# Friends cannot open with read-only saves; drop the link without a message.
		invite_link_pending = ""
		return
	if _update_gate_active():
		# Friends is online: the link is dropped at once (it could never open while
		# gated) and Home shows the update screen.
		invite_link_pending = ""
		_request_update_gate()
		return
	if not _invite_link_safe():
		# Only real activity gets the one short note; brief work and a missing identity wait quietly.
		if not invite_link_notice and not _invite_link_settling() and _invite_link_occupied():
			invite_link_notice = true
			_toast(PlayerCopy.INVITE_LINK_WAITING)
		return
	invite_link_busy = true
	var friend := invite_link_pending
	# Same authenticated entry as the Home Friends button; identity is already loaded here.
	if mode != "friends" or not is_instance_valid(friends_screen): await _show_friends()
	invite_link_busy = false
	if friend != invite_link_pending: return
	if mode == "friends" and is_instance_valid(friends_screen):
		invite_link_pending = ""
		friends_screen.confirm_invite_link(friend)
		return
	# _show_friends already showed the existing identity or availability message.
	invite_link_attempts += 1
	invite_link_retry_ms = Time.get_ticks_msec() + INVITE_LINK_RETRY_MS
	if invite_link_attempts >= INVITE_LINK_ATTEMPTS: invite_link_pending = ""

func _room_safety() -> void:
	if active_room.is_empty() or not _relay_identity().ready: return
	var peer: Variant = active_room.get("guest_id") if active_room.get("host_id") == api.player_id else active_room.get("host_id")
	if not Safety.Store.id(peer): return
	_open_safety({"room_family": "legacy", "room_id": active_room.room_id, "peer_id": peer}, "room")

func _open_safety(context: Dictionary = {}, return_to: String = "settings") -> void:
	if is_instance_valid(safety_screen): return
	if submission_in_flight or foreground_refresh_running or (relay_session != null and relay_session.busy()):
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
	elif safety_return == "account": account_flow.show_account()
	else: _show_settings()

func _blocked_safety() -> void:
	safety_screen = null
	ui.visible = true
	running = false
	_show_saved_rooms()


func _tester_checks_enabled() -> bool:
	return PlatformSupport.store_gated() or tester_access_factory.is_valid()

func _tester_context() -> String:
	if not _relay_identity().ready: return ""
	return JSON.stringify([api.base_url, api.player_id, _token_digest(), relay_identity_epoch])

func _tester_active() -> bool:
	return _tester_checks_enabled() and is_instance_valid(tester_access) and not _tester_context().is_empty() and tester_access.active(api.base_url, api.player_id, api.device_token)

func _full_journey_access() -> bool:
	return _tester_active() or purchases.has_entitlement()

## Paid gates wait on the one saved tester receipt read for this identity.
func _load_cached_tester() -> void:
	if not _tester_checks_enabled() or not is_instance_valid(tester_access): return
	await tester_access.check_cache_once(_tester_context(),_tester_context,api.base_url,api.player_id,api.device_token)

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

func _exit_tree() -> void:
	# The next scene draws 3D in this same root viewport.
	if is_instance_valid(_backdrop_view): _backdrop_view.queue_free()
	if _world_covered:
		_world_covered = false
		get_viewport().disable_3d = false
	replays_flow.release_workers()
	_campaign_generation += 1
	if is_instance_valid(campaign_flow): campaign_flow.invalidate()
	home_keepsakes.deactivate()
	# A waiting invite link outlives a scene change (a solo chapter); it never reaches disk.
	InviteLinkBridge.hold(invite_link_pending, invite_link_expires_ms)
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
	ensure_relay_session()
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

func _prepare_ordinary_navigation(report: Callable = Callable()) -> bool:
	if not _campaign_depart_for_ordinary(report) or relay_session == null: return false
	var session: RefCounted = relay_session
	var context := {"view":store_view_generation,"lifecycle":lifecycle_generation,"identity":_tester_context(),"mode":mode}
	var prepared: bool = await session.prepare_archived_navigation()
	if relay_session != session or application_backgrounded or not _relay_identity().ready or context != {"view":store_view_generation,"lifecycle":lifecycle_generation,"identity":_tester_context(),"mode":mode}: return false
	if not prepared: _report(report,session.last_error)
	return prepared

func _campaign_depart_for_ordinary(report: Callable = Callable()) -> bool:
	if not _campaign_recovery_context.is_empty(): return false
	# Local solo remains available without an online identity. A previously loaded
	# owner, however, cannot be discarded merely because identity is now unsettled.
	if not _relay_identity().ready:
		return campaign_owner == null
	if not _prepare_campaign_owner():
		_report(report,PlayerCopy.MAIN_6DE42F59590C if campaign_owner != null and campaign_owner.read_only else PlayerCopy.MAIN_52C04F6029F5)
		return false
	if not CampaignCatalog.PRODUCTION_ENABLED: return campaign_owner.ordinary_entry_allowed()
	# With no campaign ownership or admission intent, ordinary Online owns its
	# existing same-room recovery and cross-room pending lock independently.
	var bound: Dictionary = campaign_owner.bound_campaign()
	var pending: Dictionary = campaign_owner.pending_lobby()
	if bound.is_empty() and pending.is_empty() and not campaign_owner.read_only: return true
	if not campaign_owner.release_for_ordinary():
		_report(report,PlayerCopy.MAIN_6DE42F59590C if campaign_owner != null and campaign_owner.read_only else PlayerCopy.MAIN_52C04F6029F5)
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
				var typed_invitation := ShareCodes.display(ShareCodes.ROOM,publication.invite_code)
				body.add_child(_label("Invitation: "+typed_invitation,20,CREAM))
				body.add_child(_list_button("Copy invitation",func(): DisplayServer.clipboard_set(typed_invitation),false))
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
			invitation.max_length = ShareCodes.MAX_INPUT
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
	frame.add_child(_back_button("Back",_story_back,false))

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
		rows.append({"index":index,"title":RoomChapterTitle.title(ChapterRegistry.resolve(entry.chapter)),"selection":{"room_id":entry.room_id,"chapter":entry.chapter.duplicate(true),"host_id":publication.host_id,"guest_id":publication.guest_id}})
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
		button.disabled = shared_replays.busy()
		list.add_child(button)
	if not message.is_empty(): card.add_child(_paragraph(message,650))
	card.add_child(_back_button("Back",_return_story_replay_lobby,false))
	if shared_replays.busy(): _redraw_story_replay_after_idle(store_view_generation,shared_replays)

func _redraw_story_replay_after_idle(view: int, collection: RefCounted) -> void:
	if not CampaignCatalog.PRODUCTION_ENABLED: return
	# Back from a busy stage list may reveal this newer chooser. Repaint only
	# its own still-current generation; the old request cannot adopt its result.
	var identity := _relay_identity()
	while collection.busy() or application_backgrounded:
		await get_tree().process_frame
		if mode != "story_replay_chapters" or store_view_generation != view or shared_replays != collection or not CampaignCanonical.same(identity,_relay_identity()): return
	if mode == "story_replay_chapters" and store_view_generation == view and shared_replays == collection and _story_replay_current(): _draw_story_replay_chapters()

func _open_story_replay_chapter(selection: Dictionary) -> void:
	if not CampaignCatalog.PRODUCTION_ENABLED: return
	if mode != "story_replay_chapters" or shared_replays == null or shared_replays.busy() or not _story_replay_selection_current(selection): return
	var key: String = shared_replays.cached_story_chapter(selection)
	if key.is_empty():
		_draw_story_replay_chapters(PlayerCopy.MAIN_2CEDB8F94036)
		var view := store_view_generation
		key = await shared_replays.open_story_chapter(selection)
		if mode != "story_replay_chapters" or view != store_view_generation or not _story_replay_selection_current(selection): return
	if key.is_empty():
		_draw_story_replay_chapters(shared_replays.last_error)
		return
	_story_replay_return["selection"] = selection.duplicate(true)
	replays_flow.show_shared_replay_room(key)

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
	child.turn_notification_status = notification_flow.status
	child.enable_turn_notifications = notification_flow.enable
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
	target.turn_notification_status = notification_flow.status
	target.enable_turn_notifications = notification_flow.enable
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
	frame.add_child(_back_button("Back",_draw_story_lobby,false))

func _show_story_store() -> void:
	if not CampaignCatalog.PRODUCTION_ENABLED: return
	if mode != "story_access" or application_backgrounded or _campaign_action_busy or is_instance_valid(relay_child) or not _play_store_enabled(): return
	if campaign_owner == null or campaign_owner.busy() or relay_session == null: return
	var context := _campaign_context()
	if not context.identity.get("ready",false): return
	var return_context := {"owner":weakref(campaign_owner),"session":weakref(relay_session),
		"identity":context.identity,"generation":context.generation,"reference":campaign_owner.bound_campaign(),
		"selected_room":campaign_owner.selected_room(),"selection":relay_session.campaign_selection_generation(),"choice":_campaign_choice}
	store_flow.show_paywall(true,return_context)

func _story_store_current(story_return: Dictionary) -> bool:
	if not CampaignCatalog.PRODUCTION_ENABLED: return false
	if story_return.is_empty() or application_backgrounded: return false
	var owner: RefCounted = story_return.owner.get_ref()
	var session: RefCounted = story_return.session.get_ref()
	if owner == null or owner != campaign_owner or session == null or session != relay_session: return false
	if story_return.generation != _campaign_generation or not CampaignCanonical.same(story_return.identity,_relay_identity()): return false
	return CampaignCanonical.same(story_return.reference,owner.bound_campaign()) and story_return.selected_room == owner.selected_room() and story_return.selection == session.campaign_selection_generation() and story_return.choice == _campaign_choice

func _story_settings_done() -> void:
	if CampaignCatalog.PRODUCTION_ENABLED and _story_access_return:
		_story_access_return = false
		_draw_story_lobby()
	else: _show_home()
