extends Node3D
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const Frames = preload("res://services/frame_policy.gd")
const SoloReplayLaunch = preload("res://services/solo_replay_launch.gd")
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
const Secrets = preload("res://services/secure_store.gd")
const RecoveryDetails = preload("res://services/recovery_details.gd")
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
const ObjectivePanel = preload("res://presentation/objective_panel.gd")
const SeedTimerBar = preload("res://presentation/seed_timer_bar.gd")
const DeletedPhotos = preload("res://services/deleted_identity_photo_cleanup.gd")
const PhotoResumePrompt = preload("res://presentation/photo_resume_prompt.gd")
const DeletedCaches = preload("res://services/deleted_identity_cache_cleanup.gd")
const NativeFiles = preload("res://services/native_files.gd")
const HistoryStore = preload("res://services/history_store.gd")
const BackupPlan = preload("res://services/backup_plan.gd")
const DeletedAck = preload("res://services/deleted_identity_ack.gd")
const AuxiliaryContext = preload("res://services/campaign_auxiliary_context.gd")
const SharedReplays = preload("res://services/shared_replay_collection.gd")
const LighthouseMigration = preload("res://services/lighthouse_migration.gd")
const RoomStages = preload("res://services/room_stages.gd")
const SharedReplayView = preload("res://presentation/shared_replay_view.gd")
const WhenLabel = preload("res://presentation/when_label.gd")
const SoloReplayCollection = preload("res://services/solo_replay_collection.gd")
const SoloReplayVisibility = preload("res://services/solo_replay_visibility.gd")
const SoloReplayIndex = preload("res://services/solo_replay_index.gd")
# Optional hook so a friend-nickname lookup (which lives in the C client) can
# supply a saved partner's display name. Default playback shows a neutral label.
var replay_partner_label: Callable = Callable()
const ReplayLoadingBar = preload("res://presentation/replay_loading_bar.gd")
const ChapterLoadingCard = preload("res://presentation/chapter_loading_card.gd")
const ProofWarmup = preload("res://services/journey_proof_warmup.gd")
const ReplayLoadProgress = preload("res://services/replay_load_progress.gd")
var _shared_replay_loading_bar: VBoxContainer
## What's new: this version's notes have not been opened since an update.
var _whats_new_unseen := false
var _whats_new_card: Control
var _whats_new_card_mode := ""
## Tests set this to see a link instead of opening the browser.
var external_link_opener: Callable
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
var _replay_title_style: StyleBoxFlat
var _replay_hit_style: StyleBoxEmpty
var _replay_card_styles: Dictionary = {}
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
## Replay library shows the row list beside a fixed preview card once the safe
## width reaches this; narrower screens stack the preview under the list.
const REPLAY_SPLIT_MIN_WIDTH := 1000.0
const RECOVERY_ID_PATTERN := "^[A-Za-z0-9_-]{22}$"
const RECOVERY_SECRET_PATTERN := "^[A-Za-z0-9_-]{43}$"
const RECOVERY_KEY_PATTERN := "^[A-Za-z0-9_-]{16,80}$"
const COMPLETION_MOMENT_SECONDS := 3.0
const EMPTY_SOLO_COLLECTION := "Finish your first island to see your solo replays here."
const SOLO_COLLECTION_SCANNING := "Looking for more saved replays…"
## Newly settled solo rows are revealed at most this often during a scan.
const SOLO_COLLECTION_REDRAW_MS := 400
## Together waits this long for the startup account read before showing the
## sign-in explanation.
const SHARED_IDENTITY_WAIT_MS := 10000
## Most friend turn photos one Together photo fetch asks the server for.
const SHARED_PHOTO_FETCH_LIMIT := 16
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
var solo_replays: RefCounted
var solo_replay_visibility: RefCounted = SoloReplayVisibility.new()
## Display-only rows of the last finished scan, drawn unplayable at once.
var solo_replay_index: RefCounted
var _selected_solo_attempt: Dictionary = {}
var _solo_collection_message := ""
var _solo_collection_started := false
## Solo scan feedback: the bar in the open list, the settled row count drawn
## with it, and when newly settled rows may next be drawn.
var _solo_scan_bar: VBoxContainer
var _solo_scan_found := false
var _solo_collection_shown := ""
var _solo_collection_dirty := false
var _solo_collection_redraw_at := 0
## The open Solo list as drawn, so a check that only makes rows playable can
## update them where they are instead of rebuilding the screen.
var _solo_drawn_layout := ""
var _solo_row_views: Dictionary = {}
var _solo_entries_by_key: Dictionary = {}
var _solo_preview_box: VBoxContainer
var _solo_refresh_button: Button
## View generation of a Watch/Play wait in progress; -1 when none.
var _replay_launch_view := -1
var _shared_identity_wait_until := -1
var _shared_drawn_room := ""
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
var shared_replay_room := ""
var _shared_photo_sync := false
## The Together room a Watch replay tap asked for, shown as soon as this phone
## holds it; never another room in its place.
var _shared_wanted_room := ""
## Quiet retries (seconds) when saving a finished room's replay meets a busy or
## offline moment; then the next leave or Watch replay tries again.
var replay_save_retry_s: Array[float] = [2.0, 6.0, 20.0]
## Finished rooms whose replay is being saved now, by room id.
var replay_saves: Dictionary = {}
var _shared_archive_sync := false
var _shared_archive_attempts: Dictionary = {}
## Together rooms whose friend's photos this session already looked for.
var _shared_photo_checked: Dictionary = {}
## Together rooms whose parts this session already asked the server about.
var _shared_parts_checked: Dictionary = {}
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
## The current store offering: {"offering_id", "packages"} with the monthly and yearly packages.
var purchase_offer: Dictionary={}
## Store screens opened from Settings return there.
var store_from_settings := false
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
## Home prompt for a turn photo that After You closed under (photo_resume_prompt.gd).
var photo_resume_prompt: Node
var _photo_resume_checked := false
var deletion_cache_cleanup: RefCounted
var turn_notifications: Node
var hosting_notification_preferences := HostingNotificationPreferences.new()
var notification_route_busy := false
var notification_route_retry_ms := 0
var notification_deferred_event := ""
var notification_hint: Label
var notification_offer: Button
var notification_request_toggle: CheckButton
var notification_request_hint: Label
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
	_setup_invite_links()
	_proof_warmup = ProofWarmup.new()
	_proof_warmup.idle = func() -> bool: return mode == "home" and not application_backgrounded and not is_instance_valid(relay_child) and not is_instance_valid(_chapter_opening)
	add_child(_proof_warmup)
	world=World.new()
	add_child(world)
	_sync_world_processing()
	world.footstep.connect(func(spirit: String):
		if running and mode in ["play","preview"]: soundscape.play_footstep(spirit))
	world.reunion.connect(func():
		if mode=="home" or (running and mode in ["play","preview"]): soundscape.play_reunion())
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
	_home_action(actions,"Replays",preload("res://assets/ui/play-circle.svg"),_show_collection)
	var invite := _home_action(actions,PlayerCopy.HOME_INVITE,preload("res://assets/ui/social/share-network.svg"),_share_invite_from_home)
	invite.name = "HomeInvite"
	invite.tooltip_text = PlayerCopy.INVITE_LINK_SHARE
	var journey_offer := _button("Full Journey   →",_show_paywall,false)
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
	var back := _button("Back",back_callback,false)
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
		if key == ChapterRegistry.FIRST_STEPS or key == ChapterRegistry.RELAY or ChapterRegistry.is_cooperative(key): entries.append(ChapterPicker.entry(key))
	var owned := _full_journey_access()
	_grid_access_drawn = owned
	for item: Dictionary in entries: item.locked = item.premium and not owned
	picker.set_entries(entries,ChapterPicker.picture_for(ui.size.x))
	picker.chosen.connect(_open_solo_chapter)
	_journey_picker = picker
	_refresh_chapter_marks()

## Runs a Play Solo card's play button. Locked chapters keep their access and purchase gates.
func _open_solo_chapter(key: String) -> void:
	if key == ChapterThumbnailCatalog.SLEEPING_LIGHTHOUSE: _open_lighthouse()
	elif key == ChapterRegistry.FIRST_STEPS: _open_first_steps()
	elif key == ChapterRegistry.RELAY: _open_relay_preview()
	elif ChapterRegistry.is_cooperative(key): _open_cooperative_preview(key)

func _chapter_marks() -> Dictionary:
	return ChapterCompletion.chapters(home_keepsakes.earned_descriptors())

func _refresh_chapter_marks() -> void:
	if mode != "journey" or not is_instance_valid(_journey_picker): return
	_journey_picker.refresh_marks(_chapter_marks())

func _open_first_steps() -> void:
	_open_chapter_preview("res://first_steps_preview.tscn")

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
	card.add_child(_button("Back to chapters",_show_journey,false))

func _open_relay_preview() -> void:
	_open_chapter_preview("res://relay_preview.tscn")

const LIGHTHOUSE_SCENE := "res://lighthouse_preview.tscn"

func _open_lighthouse_preview() -> void:
	await _open_premium_chapter(LIGHTHOUSE_SCENE)

## The Lighthouse card plays sleeping-lighthouse@2 once it is offered. An
## unfinished @1 journey that could not be carried over continues in @1.
func _open_lighthouse() -> void:
	await _open_premium_chapter(lighthouse_scene())

static func lighthouse_scene() -> String:
	if ChapterRegistry.LIGHTHOUSE_V2 in ChapterRegistry.offered_keys() and LighthouseMigration.plan() != "v1":
		return ChapterRegistry.solo_scene(ChapterRegistry.LIGHTHOUSE_V2)
	return LIGHTHOUSE_SCENE

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
	if is_instance_valid(_chapter_opening): return
	# The chapter's own open proves what the warm-up has not reached yet.
	if is_instance_valid(_proof_warmup): _proof_warmup.stop()
	if _chapter_open_busy():
		_toast(PlayerCopy.MAIN_A776CD47C8D9)
		return
	# The chapter builds in one frame after the scene change; its card is
	# drawn first. Nothing changes until it is up.
	var opening := ChapterLoadingCard.new()
	_chapter_opening = opening
	var view := mode
	opening.start(get_tree(), scene, bool(saves.data.settings.get("reduced_motion", false)))
	await opening.drawn()
	# Home joins its keepsake check as it leaves; let it finish behind the card.
	await opening.prepare(scene, replay_context.is_empty(), func() -> bool: return home_keepsakes._worker != null and home_keepsakes._worker.is_alive())
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
	return submission_in_flight or api.busy or foreground_refresh_running or identity_loading or identity_busy or (relay_session != null and relay_session.busy())

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
			if mode == "identity_deleting" or deletion_cleanup_busy or mode == "update_gate":
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
	# Joined when done, or in _exit_tree before this screen is freed.
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
	# Redrawing the open list (scan results, selection) keeps its scroll offset.
	var kept_scroll: int=_bounded_card_scroll.scroll_vertical if mode == "collection" and is_instance_valid(_bounded_card_scroll) else 0
	running=false
	room_play=false
	mode="collection"
	_solo_collection_message=message
	if solo_replays == null: solo_replays=SoloReplayCollection.new()
	if not _solo_collection_started:
		_solo_collection_started=solo_replays.begin_scan()
	var scanning: bool=solo_replays.scan_pending()
	var entries := _solo_collection_entries()
	_solo_collection_shown=_solo_scan_signature(solo_replays.scan_progress()) if scanning else ""
	_solo_collection_dirty=false
	_solo_collection_redraw_at=Time.get_ticks_msec()+SOLO_COLLECTION_REDRAW_MS
	_select_solo_entry(entries)
	var shell := _begin_replay_split("solo")
	var wide: bool=shell.wide
	var left: VBoxContainer=shell.left
	_solo_row_views={}
	_solo_entries_by_key={}
	_solo_preview_box=null
	_solo_refresh_button=null
	_solo_drawn_layout=_solo_layout(entries,scanning,wide)
	left.add_child(_label("Your recordings",24,CREAM,true))
	left.add_child(_label("Completed turns",17,MUTED))
	_solo_scan_bar=null
	# "Looking for more" only once a playable row is listed; snapshot rows
	# still being checked keep the general loading text.
	_solo_scan_found=entries.any(func(entry: Dictionary) -> bool: return not entry.get("checking",false))
	if scanning:
		# Present from the first frame of the screen until the scan finishes.
		_solo_scan_bar=ReplayLoadingBar.new()
		_solo_scan_bar.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
		_add_replay_wait_bar(left,_solo_scan_bar,wide and (entries.is_empty() or _selected_solo_attempt.is_empty()))
		_solo_scan_bar.update_progress(_solo_scan_progress())
	for entry: Dictionary in entries:
		var selected: bool=wide and str(entry.get("key",""))==str(_selected_solo_attempt.get("key",""))
		_solo_entries_by_key[str(entry.get("key",""))]=entry
		left.add_child(_solo_collection_row(entry,selected,wide))
	# "Nothing saved" only after a finished scan has found nothing.
	if entries.is_empty() and not scanning:
		left.add_child(_paragraph(EMPTY_SOLO_COLLECTION,620))
	# Failed sources simply drop out; the error shows only when nothing could be checked.
	if not scanning and not solo_replays.last_error.is_empty() and solo_replays.items().is_empty(): left.add_child(_paragraph(solo_replays.last_error,620))
	if not _solo_collection_message.is_empty(): left.add_child(_paragraph(_solo_collection_message,620))
	if not wide:
		var refresh := _button("Refresh saved replays",func(): _solo_collection_started=false; _show_collection(),false)
		refresh.disabled=scanning
		left.add_child(refresh)
		_solo_refresh_button=refresh
	if wide and not entries.is_empty() and not _selected_solo_attempt.is_empty():
		_solo_preview_box=shell.right
		_fill_solo_preview(shell.right)
	else:
		shell.preview_panel.visible=false
	if kept_scroll>0: _restore_replay_scroll.call_deferred(shell.scroll,kept_scroll)

## What decides the screen's layout: every row's identity and text, the
## messages and the wait bar's placement. Rows turning playable change none
## of it.
func _solo_layout(entries: Array, scanning: bool, wide: bool) -> String:
	var parts := PackedStringArray([str(wide),_solo_collection_message,str(entries.is_empty() and not scanning),str(scanning and wide and _selected_solo_attempt.is_empty())])
	parts.append(solo_replays.last_error if not scanning and solo_replays.items(false).is_empty() else "")
	for entry: Dictionary in entries: parts.append("%s|%s|%d" % [entry.get("key",""),entry.get("title",""),int(entry.get("parts",1))])
	return "\n".join(parts)

## Applies a scan step to the open list. Rows already on screen become
## playable where they are; only a changed layout redraws the screen.
func _refresh_solo_collection() -> void:
	var scanning: bool=solo_replays.scan_pending()
	var entries := _solo_collection_entries()
	var wide: bool=is_instance_valid(_bounded_card_scroll) and ui.size.x>=REPLAY_SPLIT_MIN_WIDTH
	var previous_key := str(_selected_solo_attempt.get("key",""))
	_select_solo_entry(entries)
	if str(_selected_solo_attempt.get("key",""))!=previous_key or _solo_layout(entries,scanning,wide)!=_solo_drawn_layout:
		# New or removed rows redraw at most every SOLO_COLLECTION_REDRAW_MS.
		if Time.get_ticks_msec()>=_solo_collection_redraw_at: _show_collection(_solo_collection_message)
		return
	_solo_collection_shown=_solo_scan_signature(solo_replays.scan_progress()) if scanning else ""
	_solo_collection_dirty=false
	_solo_scan_found=entries.any(func(entry: Dictionary) -> bool: return not entry.get("checking",false))
	var preview_changed := false
	for entry: Dictionary in entries:
		var key := str(entry.get("key",""))
		var was: Dictionary=_solo_entries_by_key.get(key,{})
		_solo_entries_by_key[key]=entry
		if bool(was.get("checking",false))==bool(entry.get("checking",false)): continue
		if key==previous_key: preview_changed=true
		var view: Dictionary=_solo_row_views.get(key,{})
		if view.is_empty() or not is_instance_valid(view.play): continue
		var enabled: bool=wide or not entry.get("checking",false)
		view.title.disabled=not enabled
		view.hit.disabled=not enabled
		var play := _solo_watch_button("Play",entry,0,false,true)
		play.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var slot: int=view.play.get_index()
		var rowbox: Node=view.play.get_parent()
		rowbox.remove_child(view.play)
		view.play.queue_free()
		rowbox.add_child(play)
		rowbox.move_child(play,slot)
		view.play=play
	if preview_changed and is_instance_valid(_solo_preview_box):
		for child: Node in _solo_preview_box.get_children():
			_solo_preview_box.remove_child(child)
			child.queue_free()
		_solo_preview_box.remove_meta("thumbnail")
		_fill_solo_preview(_solo_preview_box)
	if is_instance_valid(_solo_scan_bar):
		if scanning: _solo_scan_bar.update_progress(_solo_scan_progress())
		else:
			# Its wide-screen wrapper row goes with it.
			var holder: Node=_solo_scan_bar.get_parent()
			var gone: Node=holder if holder is HBoxContainer else _solo_scan_bar
			gone.get_parent().remove_child(gone)
			gone.queue_free()
			_solo_scan_bar=null
	if is_instance_valid(_solo_refresh_button): _solo_refresh_button.disabled=scanning

## Writes the display snapshot as the list currently stands: checked rows of
## settled chapters, and the snapshot's own rows for chapters still pending.
func _store_solo_snapshot() -> void:
	if solo_replays == null: return
	if solo_replay_index == null: solo_replay_index=SoloReplayIndex.new()
	solo_replay_index.store_display(solo_replays.settled_items(false),solo_replays.pending_chapters())

func _add_replay_wait_bar(parent: VBoxContainer, bar: Control, without_preview: bool) -> void:
	# On a wide screen with no preview card the list spans the whole width;
	# keep the bar to the width the list has beside that card.
	if not without_preview:
		parent.add_child(bar)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	bar.size_flags_stretch_ratio=1.15
	row.add_child(bar)
	var rest := Control.new()
	rest.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rest.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(rest)
	parent.add_child(row)

func _solo_scan_signature(progress: Dictionary) -> String:
	return "%d:%d" % [int(progress.get("settled",0)),int(progress.get("pending",0))]

func _solo_scan_progress() -> Dictionary:
	var progress: Dictionary=solo_replays.scan_progress()
	if _solo_scan_found: progress["label"]=SOLO_COLLECTION_SCANNING
	return progress

func _restore_replay_scroll(scroll: ScrollContainer, value: int) -> void:
	if is_instance_valid(scroll) and scroll.is_inside_tree(): scroll.scroll_vertical=value

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
	# During a scan only chapters with every source checked are listed, so an
	# attempt keeps the number it is first shown with. Chapters still pending
	# show the last finished scan's display rows, which are never playable.
	var scanning: bool=solo_replays.scan_pending()
	# Scan rows are shared read-only; nothing here or in playback mutates them.
	var scanned: Array=solo_replays.settled_items(false) if scanning else solo_replays.items(false)
	if scanning:
		if solo_replay_index == null: solo_replay_index=SoloReplayIndex.new()
		var pending: Dictionary=solo_replays.pending_chapters()
		for row: Dictionary in solo_replay_index.rows():
			if pending.has(str(row.chapter_key)): scanned.append(row)
	var groups: Dictionary={}
	for row: Dictionary in scanned:
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
		var checking: bool=rows.any(func(row: Dictionary) -> bool: return row.get("checking",false))
		entries.append({"family":"chapter","key":"chapter:"+str(item.key),"rows":rows,"title":"%s · Attempt %d" % [str(rows[0].chapter_title),int(attempt_numbers[chapter_key])],"chapter_key":chapter_key,"parts":rows.size(),"checking":checking})
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
			_selected_solo_attempt=entry.duplicate()
			_selected_solo_attempt["part"]=part
			return
	_selected_solo_attempt=entries[0].duplicate()
	_selected_solo_attempt["part"]=0

func _solo_part_subtitle(parts: int) -> String:
	return "%d %s · Saved offline" % [parts,"part" if parts==1 else "parts"]

func _begin_replay_split(selected: String, back_text: String="Back", back_callback: Callable=Callable()) -> Dictionary:
	# Shared full-screen Replays shell for Solo and Together. A fixed header
	# (Back + title + Solo/Together tabs) sits above one bounded scroller. On
	# wide screens it holds only the row list, beside a fixed preview card whose
	# picture shrinks to keep every action visible; on narrow screens the list
	# and the stacked preview scroll together.
	_clear_overlay()
	var shade := ColorRect.new()
	shade.color=Color(0.025,0.10,0.10,0.9)
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
	var body := BoxContainer.new()
	body.vertical=not wide
	body.add_theme_constant_override("separation",18)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var list_column := VBoxContainer.new()
	list_column.add_theme_constant_override("separation",10)
	list_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if wide:
		# Side by side, only the list scrolls; the preview card stays put.
		body.size_flags_vertical=Control.SIZE_EXPAND_FILL
		outer.add_child(body)
		scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio=1.15
		body.add_child(scroll)
		scroll.add_child(list_column)
	else:
		outer.add_child(scroll)
		scroll.add_child(body)
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
	preview.add_theme_constant_override("separation",10)
	preview_margin.add_child(preview)
	var available: Control = body if wide else scroll
	preview.set_meta("available_scroll",available)
	preview.set_meta("preview_panel",preview_panel)
	available.resized.connect(_fit_replay_preview.bind(preview).call_deferred)
	ControlTheme.touch_scroll(scroll)
	_bounded_card_scroll=scroll
	_bounded_card_stack=null
	return {"outer":outer,"scroll":scroll,"body":body,"left":list_column,"right":preview,"preview_panel":preview_panel,"wide":wide}

func _fit_replay_preview(preview: VBoxContainer) -> void:
	if not is_instance_valid(preview) or not preview.has_meta("thumbnail"): return
	var available: Control=preview.get_meta("available_scroll")
	var panel: PanelContainer=preview.get_meta("preview_panel")
	var thumbnail: Control=preview.get_meta("thumbnail")
	if not is_instance_valid(available) or not is_instance_valid(panel) or not is_instance_valid(thumbnail): return
	# Spend remaining safe height on the picture after reserving every label,
	# part selector and action. A short viewport shrinks the picture first,
	# never touch targets, and stacked layouts still scroll.
	var controls_height: float=panel.get_combined_minimum_size().y-thumbnail.custom_minimum_size.y
	thumbnail.custom_minimum_size.y=clampf(available.size.y-controls_height-2.0,96.0,220.0)

func _replay_preview_thumb(key: String, min_size: Vector2, radius: int) -> Control:
	# One framed picture for every chapter view; the chapter picker owns it.
	return ChapterPicker.thumbnail(key,min_size,radius)

func _part_chip(label: String, selected: bool, callback: Callable) -> Button:
	var chip := _button(label,callback,false)
	chip.custom_minimum_size=Vector2(0,48)
	chip.disabled=selected
	if selected: _selected_look(chip)
	return chip

func _selected_look(button: Button) -> void:
	## The current tab or part can't be pressed again, but it should read as
	## selected rather than unavailable: the hub's lighter teal pill. Cream stays
	## reserved for the screen's primary action.
	ControlTheme.selected_tab(button)

func _replay_row_title(title: Button) -> void:
	## A row title reads as a heading that starts flush with its caption below.
	title.add_theme_font_override("font",title_font)
	title.add_theme_font_size_override("font_size",24)
	if _replay_title_style == null:
		_replay_title_style=_style(Color.TRANSPARENT,10)
		_replay_title_style.content_margin_left=0
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		title.add_theme_stylebox_override(state,_replay_title_style)
	title.add_theme_color_override("font_color",CREAM)
	title.add_theme_color_override("font_focus_color",CREAM)
	for state: String in ["hover","pressed","hover_pressed"]:
		title.add_theme_color_override("font_"+state+"_color",MINT)

func _replay_row_card(thumb_key: String, title_text: String, caption_text: String, selected: bool, open: Callable, enabled: bool=true) -> Dictionary:
	## Shared Solo/Together replay row. The whole card is one tap target: an
	## invisible full-card button sits under the art, title and caption, which
	## let presses through, so the caption, art and padding select the row like
	## the title does. Play and delete stay their own targets on top.
	var panel := PanelContainer.new()
	panel.mouse_filter=Control.MOUSE_FILTER_PASS
	# Two shared looks; the card's inset lives in the margin below so the tap
	# target reaches every edge.
	if not _replay_card_styles.has(selected):
		var look := _style(Color("27564e") if selected else Color("1b443e"),16,Color("6fb39d") if selected else Color.TRANSPARENT)
		for edge: String in ["left","top","right","bottom"]: look.set("content_margin_"+edge,0)
		_replay_card_styles[selected]=look
	panel.add_theme_stylebox_override("panel",_replay_card_styles[selected])
	var hit := Button.new()
	hit.name="RowTapTarget"
	hit.flat=true
	hit.focus_mode=Control.FOCUS_NONE
	hit.mouse_filter=Control.MOUSE_FILTER_PASS
	hit.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if _replay_hit_style == null: _replay_hit_style=StyleBoxEmpty.new()
	for state: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]: hit.add_theme_stylebox_override(state,_replay_hit_style)
	hit.disabled=not enabled
	hit.pressed.connect(open)
	panel.add_child(hit)
	var pad := MarginContainer.new()
	for side in ["left","right"]: pad.add_theme_constant_override("margin_"+side,28)
	for side in ["top","bottom"]: pad.add_theme_constant_override("margin_"+side,20)
	pad.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(pad)
	var rowbox := HBoxContainer.new()
	rowbox.add_theme_constant_override("separation",12)
	rowbox.mouse_filter=Control.MOUSE_FILTER_IGNORE
	pad.add_child(rowbox)
	rowbox.add_child(_replay_preview_thumb(thumb_key,Vector2(128,72),10))
	var textcol := VBoxContainer.new()
	textcol.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	textcol.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	textcol.add_theme_constant_override("separation",0)
	textcol.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var title := _list_button(title_text,open,false)
	title.set_meta("replay_row",true)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.alignment=HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text=true
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.y=48
	_replay_row_title(title)
	title.disabled=not enabled
	textcol.add_child(title)
	var caption := _paragraph(caption_text,260)
	caption.add_theme_font_size_override("font_size",17)
	if selected: caption.add_theme_color_override("font_color",MINT)
	textcol.add_child(caption)
	rowbox.add_child(textcol)
	return {"panel":panel,"rowbox":rowbox,"title":title,"hit":hit}

func _solo_collection_row(entry: Dictionary, selected: bool, wide: bool) -> Control:
	# One saved-recording row: real chapter art, a human title, a short "N parts
	# · Saved offline" caption and a quick Play. On wide screens the title selects
	# the row for the preview card; on narrow screens it opens the part preview.
	var key := str(entry.get("key",""))
	var open := func():
		# The row may have been checked since it was drawn.
		_selected_solo_attempt=_solo_entries_by_key.get(key,entry).duplicate()
		_selected_solo_attempt["part"]=0
		if wide: _show_collection()
		else: _show_solo_replay_attempt()
	# A row still being checked opens nothing that could play it.
	var card := _replay_row_card(str(entry.get("chapter_key","")),str(entry.get("title","Replay")),_solo_part_subtitle(int(entry.get("parts",1))),selected,open,wide or not entry.get("checking",false))
	var panel: PanelContainer=card.panel
	var rowbox: HBoxContainer=card.rowbox
	var play := _solo_watch_button("Play",entry,0,false,true)
	play.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	rowbox.add_child(play)
	_solo_row_views[key]={"title":card.title,"hit":card.hit,"play":play}
	if not wide and entry.get("family")=="legacy":
		rowbox.add_child(_collection_delete_button(func(): _confirm_delete_collection_replay(int(entry.get("level_index",-1)),entry.get("attempt",{})),str(entry.get("title",""))))
	return panel

func _fill_solo_preview(preview: VBoxContainer) -> void:
	var entry := _selected_solo_attempt
	var parts: int=int(entry.get("parts",1))
	var part: int=clampi(int(entry.get("part",0)),0,maxi(0,parts-1))
	var thumbnail := _replay_preview_thumb(str(entry.get("chapter_key","")),Vector2(0,220),16)
	preview.add_child(thumbnail)
	preview.set_meta("thumbnail",thumbnail)
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
	preview.add_child(_solo_watch_button("Watch replay",entry,part,true))
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation",10)
	if parts>1:
		var watch_all := _solo_watch_button("Watch all parts",entry,parts-1,false)
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
			var remove := _collection_delete_button(func(): _confirm_remove_solo_part(rows[part]),_part_title(rows[part]))
			remove.disabled=remove.disabled or entry.get("checking",false)
			secondary.add_child(remove)
	preview.add_child(secondary)
	_fit_replay_preview.call_deferred(preview)

func _play_solo_entry(entry: Dictionary, part: int) -> void:
	if entry.get("checking",false): return
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
		await _launch_modern_solo_replay(rows[chosen])

func _solo_watch_button(text: String, entry: Dictionary, part: int, primary: bool, row: bool=false) -> Button:
	## Chapter replays open another scene, so their wait shows before it loads.
	## Earlier-island replays open their own loading card at once.
	var launch := func(): await _play_solo_entry(entry,part)
	if entry.get("checking",false):
		var waiting := _list_button(text,launch,primary) if row else _button(text,launch,primary)
		waiting.disabled=true
		return waiting
	if entry.get("family")=="chapter": return _replay_launch_button(text,launch,primary,row)
	return _list_button(text,launch,primary) if row else _button(text,launch,primary)

func _replay_launch_button(text: String, launch: Callable, primary: bool, row: bool=false) -> Button:
	var button := _list_button(text,launch,primary) if row else _button(text,launch,primary)
	button.pressed.disconnect(launch)
	button.pressed.connect(_begin_replay_launch.bind(button,launch))
	button.set_meta("replay_launch",true)
	return button

func _begin_replay_launch(control: Button, launch: Callable) -> void:
	# One launch per screen: every Watch/Play control is disabled and a wait bar
	# sits under the tapped one until the replay opens or is refused.
	var view := store_view_generation
	if _replay_launch_view == view or not is_instance_valid(control) or control.disabled: return
	_replay_launch_view=view
	var paused: Array[Button]=[]
	for node: Node in overlay.find_children("*","Button",true,false):
		var button := node as Button
		if button.has_meta("replay_launch") and not button.disabled:
			button.disabled=true
			paused.append(button)
	var wait := ReplayLoadingBar.new()
	wait.name="ReplayLaunchWait"
	wait.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
	var anchor: Node=control
	while anchor.get_parent() != null and not anchor.get_parent() is VBoxContainer: anchor=anchor.get_parent()
	if anchor.get_parent() != null:
		anchor.get_parent().add_child(wait)
		anchor.get_parent().move_child(wait,anchor.get_index()+1)
	wait.update_progress({"phase":"preparing"})
	var preview := wait.get_parent() as VBoxContainer
	if preview != null and preview.has_meta("thumbnail"): _fit_replay_preview.call_deferred(preview)
	elif is_instance_valid(_bounded_card_scroll) and _bounded_card_scroll.is_ancestor_of(wait): _bounded_card_scroll.ensure_control_visible.call_deferred(wait)
	# Two frame boundaries put the disabled control and the bar on screen before
	# a scene load or store check can hold this thread.
	for frame in range(2):
		if not is_inside_tree(): return
		await get_tree().process_frame
	# The chapter opens at once even while the Solo scan's verifier is checking
	# a source: chapter rules are safe on both threads. Leaving this screen
	# hands that verifier to the reaper (see _exit_tree), so nothing waits on it.
	if view == store_view_generation: await launch.call()
	# A scene change removes this node and navigation redraws the screen; only a
	# refused launch on the same screen restores its controls.
	if not is_inside_tree() or view != store_view_generation: return
	_replay_launch_view=-1
	for button: Button in paused:
		if is_instance_valid(button): button.disabled=false
	if is_instance_valid(wait): wait.queue_free()

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
		_store_solo_snapshot()
		solo_replays.cancel_scan()
		_solo_collection_started=false

func _service_solo_collection() -> void:
	if mode != "collection": return
	# A Watch/Play wait owns the screen until the replay opens or is refused.
	if solo_replays == null or _replay_launch_view == store_view_generation: return
	if solo_replays.scan_pending():
		var finished: bool=not solo_replays.advance_scan()
		var progress: Dictionary=_solo_scan_progress()
		if is_instance_valid(_solo_scan_bar): _solo_scan_bar.update_progress(progress)
		if finished:
			_solo_collection_started=true
			_solo_collection_dirty=true
			_solo_collection_redraw_at=Time.get_ticks_msec()
			_store_solo_snapshot()
		elif _solo_scan_signature(progress) != _solo_collection_shown:
			_solo_collection_dirty=true
			# Each settled chapter is kept at once, so leaving early or closing
			# the app still opens the full list next time.
			_store_solo_snapshot()
	var now := Time.get_ticks_msec()
	if not _solo_collection_dirty: return
	# Do not change rows under a press or drag on the list; a stuck pointer
	# state can hold them back only briefly. A press on a button always waits.
	if TouchInput.press_held(overlay): return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and now < _solo_collection_redraw_at+2000: return
	_refresh_solo_collection()

func _show_solo_replay_attempt() -> void:
	if mode != "collection" or _selected_solo_attempt.is_empty() or _selected_solo_attempt.get("checking",false): return
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
			var watch := _replay_launch_button("Part %d · %s" % [part_index+1,_part_title(row)],func(): await _launch_modern_solo_replay(frozen),true,true)
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
	# The solo Lighthouse is outside the registry; its own scene checks the pairs.
	if ChapterRegistry.descriptor(chapter_key).is_empty() and chapter_key != SoloReplayCollection.LIGHTHOUSE_KEY: return {}
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
	if mode not in ["collection","solo_replay_attempt"] or _selected_solo_attempt.get("family")!="chapter" or _selected_solo_attempt.get("checking",false) or not selected.has("pair"): return
	var chapter_key := str(selected.get("chapter_key",""))
	var context := _solo_replay_context_from_rows(chapter_key,_selected_solo_attempt.get("rows",[]),selected)
	if context.is_empty(): return
	var lighthouse := chapter_key == SoloReplayCollection.LIGHTHOUSE_KEY
	var scene := LIGHTHOUSE_SCENE if lighthouse else ChapterRegistry.solo_scene(chapter_key)
	if scene.is_empty(): return
	if lighthouse or ChapterRegistry.descriptor(chapter_key).premium:
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

func _show_shared_replays(wanted: String = "") -> void:
	_shared_wanted_room = wanted
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
		var now := Time.get_ticks_msec()
		if identity_loading and (_shared_identity_wait_until < 0 or now < _shared_identity_wait_until):
			# The saved account is still being read after a cold start.
			if _shared_identity_wait_until < 0: _shared_identity_wait_until=now+SHARED_IDENTITY_WAIT_MS
			var shell := _begin_replay_split("together","Back",_show_home)
			var left: VBoxContainer=shell.left
			left.add_child(_label("Together",24,MINT,true))
			left.add_child(_paragraph(PlayerCopy.MAIN_529CFAE68DF1,630))
			_shared_replay_loading_bar=ReplayLoadingBar.new()
			_shared_replay_loading_bar.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
			_add_replay_wait_bar(left,_shared_replay_loading_bar,shell.wide)
			_shared_replay_loading_bar.update_progress({})
			var account := _button("Account & recovery",_show_account,false)
			account.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			left.add_child(account)
			shell.preview_panel.visible=false
			return
		_shared_identity_wait_until=-1
		var held := _card(700)
		held.add_child(_label("Your shared replays",34,CREAM,true))
		held.add_child(_paragraph(PlayerCopy.MAIN_1E12325B0B49,600))
		held.add_child(_button("Account & recovery",_show_account))
		held.add_child(_button("Back",_show_home,false))
		return
	_shared_identity_wait_until=-1
	if shared_replays==null: shared_replays=SharedReplays.new(api,_relay_identity)
	_wire_shared_history()
	shared_replays.configure_context_factory(_campaign_media_factory())
	# Queue the local check before the only draw, so the first frame already
	# carries its loading bar rather than an empty state.
	shared_replays.begin_local_load(saves.data.get("room",{}))
	_open_default_shared_room()

func _listed_shared_rooms() -> Array:
	# Rooms whose local verification still retains at least one saved replay and
	# that the player is allowed to open here.
	if shared_replays == null: return []
	var rooms: Array = shared_replays.rooms().filter(func(room: Dictionary): return not shared_replays.memories(SharedReplays._room_key(room),true).is_empty()).filter(_production_replay_room_allowed)
	# Newest first; rooms this phone has no time for keep their order after them.
	var order: Array = []
	for index in range(rooms.size()): order.append([shared_replays.updated_at(rooms[index]),index])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	return order.map(func(item: Array) -> Dictionary: return rooms[item[1]])

func _default_shared_replay_key() -> String:
	# Prefer the room viewed earlier this session; otherwise the first listed
	# room. Returns "" when nothing can be shown yet (still loading or empty).
	var rooms := _listed_shared_rooms()
	if rooms.is_empty(): return ""
	for room: Dictionary in rooms:
		if SharedReplays._room_key(room) == shared_replay_room: return shared_replay_room
	return SharedReplays._room_key(rooms[0])

func _open_default_shared_room() -> void:
	if not _shared_wanted_room.is_empty():
		_open_wanted_shared_room()
		return
	var key := _default_shared_replay_key()
	if key.is_empty():
		_draw_shared_replay_empty()
		return
	_show_shared_replay_room(key)

func _service_shared_replays() -> void:
	if _shared_identity_wait_until >= 0:
		if mode != "shared_replays": _shared_identity_wait_until=-1
		elif not identity_loading or Time.get_ticks_msec() >= _shared_identity_wait_until:
			_show_shared_replays(_shared_wanted_room)
			return
	if shared_replays == null or mode not in ["shared_replays", "shared_memories"] or not shared_replays.local_loading(): return
	# A step can redraw the page; it waits for a tap in progress to finish.
	if TouchInput.press_held(overlay): return
	if not shared_replays.advance_local_load():
		if is_instance_valid(_shared_replay_loading_bar): _shared_replay_loading_bar.update_progress(shared_replays.local_progress())
		return
	# Every open checks each saved room again; one that lists what is already
	# shown no longer rebuilds the whole page. The last one always redraws.
	var changed: bool = shared_replays.local_load_changed() or not shared_replays.local_loading()
	if not changed and is_instance_valid(_shared_replay_loading_bar): _shared_replay_loading_bar.update_progress(shared_replays.local_progress())
	if mode == "shared_replays":
		if changed: _open_default_shared_room()
	else:
		if changed: _draw_shared_replay_memories(shared_replays.listed(shared_replay_room))
		_check_shared_room_parts(shared_replay_room)
		_fetch_missing_shared_photos(shared_replay_room)

func _add_shared_replay_loading_bar(card: VBoxContainer, without_preview: bool = false) -> void:
	_shared_replay_loading_bar=null
	if not shared_replays.local_loading(): return
	_shared_replay_loading_bar=ReplayLoadingBar.new()
	_shared_replay_loading_bar.reduced_motion=bool(saves.data.settings.get("reduced_motion",false))
	_add_replay_wait_bar(card,_shared_replay_loading_bar,without_preview)
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

## One line that tells shared rooms apart: the chapter (when asked), the friend
## and when the room last changed, in local time.
func _shared_room_line(room: Dictionary, with_title: bool) -> String:
	var parts: Array[String] = []
	if with_title: parts.append(str(room.get("title","Shared room")))
	var partner := _room_partner_name(room)
	if not partner.is_empty(): parts.append("With "+partner)
	var when := WhenLabel.text(shared_replays.updated_at(room)) if shared_replays != null and not room.is_empty() else ""
	if not when.is_empty(): parts.append(when)
	return " · ".join(parts)

func _replay_partner_name() -> String:
	# "With <partner>" uses the saved partner's display name when a nickname
	# lookup (which lives in the C client) is wired in through the Callable; it
	# otherwise falls back to a neutral label.
	return _room_partner_name(_current_shared_room())

## The friend in a shared room, by the nickname this player gave them, or
## "a friend". Never a raw id.
func _room_partner_name(room: Dictionary) -> String:
	if room.is_empty(): return ""
	var shown := _room_partner_nickname(room)
	return shown if not shown.is_empty() else FriendNicknames.FALLBACK

## The nickname of the other player in a shared room, or "".
func _room_partner_nickname(room: Dictionary) -> String:
	var owner := str(_relay_identity().player_id)
	var friend := str(room.get("guest_id","")) if str(room.get("host_id",""))==owner else str(room.get("host_id",""))
	if friend.is_empty() or friend == "<null>": return ""
	if replay_partner_label.is_valid():
		var resolved := str(replay_partner_label.call(friend))
		if not resolved.is_empty(): return resolved
	if friend_nicknames == null: return ""
	return str(friend_nicknames.nickname(str(api.base_url),str(api.player_id),friend))

func _draw_shared_replay_empty(message: String="") -> void:
	# Shown only when there is no room to open yet: still loading, nothing saved,
	# or offline. Keeps the Together shell, loading bar, offline/error text and a
	# refresh, with Back leaving to Home like Solo's Back.
	var shell := _begin_replay_split("together","Back",_show_home)
	mode="shared_replays"
	var left: VBoxContainer=shell.left
	left.add_child(_label("Together",24,MINT,true))
	left.add_child(_paragraph(PlayerCopy.MAIN_529CFAE68DF1,630))
	_add_shared_replay_loading_bar(left,shell.wide)
	if not shared_replays.local_loading():
		left.add_child(_paragraph(PlayerCopy.MAIN_87534286A315,620))
	if not message.is_empty(): left.add_child(_paragraph(message,630))
	elif not shared_replays.last_error.is_empty(): left.add_child(_paragraph(shared_replays.last_error,630))
	var refresh := _button("Refresh shared rooms",_refresh_shared_replay_rooms,false)
	refresh.disabled=shared_replays.busy() or api.busy
	left.add_child(refresh)
	shell.preview_panel.visible=false

func _refresh_shared_replay_rooms() -> void:
	# Replays already on this phone stay; new downloads wait for the update.
	if _update_gate_active():
		_toast(UpdateGate.notice(str(app_status.result.get("min_version",""))))
		return
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
	_check_shared_room_parts(key)
	_fetch_missing_shared_photos(key)

func open_shared_replay_room(room_id: String) -> void:
	# Public entry for the room hub: open the Together library on one room.
	# While this phone is still checking its saved rooms the loading view
	# stays up; a room it does not hold yet is saved from the server first.
	# It never shows a different room in its place.
	_show_shared_replays("chapter:" + room_id if not room_id.is_empty() else "")

func _open_wanted_shared_room() -> void:
	var key := _shared_wanted_room
	var room_id := key.substr(8)
	if not key.begins_with("chapter:") or not _production_replay_room_allowed({"family": "chapter", "room_id": room_id}):
		_shared_wanted_room = ""
		_open_default_shared_room()
		return
	# A finished room this phone holds whole opens at once; one it holds only
	# part of (the friend finished it) is saved whole first.
	if not _shared_replay_key_for_room(room_id).is_empty() and not shared_replays.local_sequence(key).is_empty():
		_shared_wanted_room = ""
		_show_shared_replay_room(key)
		# Room history: the friend's phone may have asked for an attempt this phone keeps.
		if RoomsApi.history_supported: _save_finished_replay(room_id)
		return
	if shared_replays.local_loading():
		_draw_shared_replay_empty()
		return
	_draw_shared_replay_empty("Saving replays…")
	# A save already running (leaving that room's play) opens it when done.
	_save_finished_replay(room_id)

## A finished room's save ended: show it when a Watch replay tap is waiting.
func _finished_replay_saved(room_id: String, saved: bool) -> void:
	var key := "chapter:" + room_id
	if _shared_wanted_room != key or mode not in ["shared_replays","shared_memories"] or not _relay_identity().ready: return
	if shared_replays != null and not _shared_replay_key_for_room(room_id).is_empty():
		_shared_wanted_room = ""
		_show_shared_replay_room(key)
	elif not saved and replay_saves.is_empty():
		_shared_wanted_room = ""
		_draw_shared_replay_empty("Could not save replays")

func _shared_replay_key_for_room(room_id: String) -> String:
	if shared_replays==null or room_id.is_empty(): return ""
	for room: Dictionary in shared_replays.rooms():
		if str(room.get("room_id",""))!=room_id: continue
		var key: String=SharedReplays._room_key(room)
		if not shared_replays.memories(key,true).is_empty() and _production_replay_room_allowed(room): return key
	return ""

func _draw_shared_replay_memories(rows: Array, message: String="") -> void:
	if not _production_replay_key_allowed(shared_replay_room): return
	# A redraw of the same room (a checked room arriving) keeps the scroll offset.
	var kept_scroll: int=_bounded_card_scroll.scroll_vertical if mode == "shared_memories" and _shared_drawn_room == shared_replay_room and is_instance_valid(_bounded_card_scroll) else 0
	_shared_drawn_room=shared_replay_room
	var back_text := "Back"
	var back_callback := _back_to_story_replay_chapters if not _story_replay_return.is_empty() else _show_home
	var shell := _begin_replay_split("together",back_text,back_callback)
	mode="shared_memories"
	var wide: bool=shell.wide
	var left: VBoxContainer=shell.left
	var room := _current_shared_room()
	left.add_child(_label(str(room.get("title",PlayerCopy.MAIN_C8F7A8FDC485)) if not room.is_empty() else PlayerCopy.MAIN_C8F7A8FDC485,24,CREAM,true))
	var about := _shared_room_line(room, false)
	if not about.is_empty(): left.add_child(_label(about,17,MUTED))
	_add_shared_room_selector(left)
	_add_shared_replay_loading_bar(left,wide and rows.is_empty())
	_select_shared_memory(rows)
	for index in range(rows.size()):
		var row: Dictionary=rows[index].duplicate(true)
		var selected: bool=wide and str(row.get("id",""))==_shared_preview_id
		left.add_child(_shared_memory_row(row,_shared_part(row,index),selected,wide))
	if rows.is_empty() and not shared_replays.local_loading(): left.add_child(_paragraph(PlayerCopy.MAIN_DE8FFD26387B,640))
	if not message.is_empty(): left.add_child(_paragraph(message,650))
	elif not shared_replays.last_error.is_empty(): left.add_child(_paragraph(shared_replays.last_error,650))
	# The selection hint only makes sense once there is a stage to select.
	if not rows.is_empty(): left.add_child(_paragraph(PlayerCopy.MAIN_4CACA12BCD58,650))
	var has_preview: bool=wide and not rows.is_empty() and not _shared_preview_id.is_empty()
	if not has_preview:
		var options := _button("Options",_open_shared_options,false)
		options.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		left.add_child(options)
	if has_preview:
		_fill_shared_preview(shell.right,rows)
	else:
		shell.preview_panel.visible=false
	if kept_scroll>0: _restore_replay_scroll.call_deferred(shell.scroll,kept_scroll)

func _add_shared_room_selector(left: VBoxContainer) -> void:
	# "Choose another room" lists every shared room that still has a saved
	# replay by chapter title and partner, so switching stays on this view.
	var rooms: Array=_listed_shared_rooms()
	if rooms.size()<=1: return
	var option := OptionButton.new()
	# A selector is a secondary control; Watch replay stays the one cream action.
	ControlTheme.secondary(option)
	for state: String in ["hover","pressed","hover_pressed"]:
		option.add_theme_stylebox_override(state,ControlTheme.padded(ControlTheme.rounded(Color("2b5550"),14,Color("54766a"))))
		option.add_theme_color_override("font_"+state+"_color",CREAM)
	option.custom_minimum_size.y=48
	option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	option.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	var current := 0
	for i in range(rooms.size()):
		var room: Dictionary=rooms[i]
		var key: String=SharedReplays._room_key(room)
		option.add_item(_shared_room_line(room, true))
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
	var open := func():
		if wide:
			# A tap anywhere selects the part; one not saved yet starts saving.
			_shared_preview_id=str(row.get("id",""))
			_draw_shared_replay_memories(shared_replays.listed(key))
			if not row.get("cached",false): _save_shared_memory(key,row)
		else:
			_open_shared_memory(key,row)
	var card := _replay_row_card(_shared_room_thumb_key(row),str(row.get("title","Replay")),"Part %d · %s" % [part,"Saved offline" if row.get("cached",false) else "Download replay"],selected,open)
	var panel: PanelContainer=card.panel
	var rowbox: HBoxContainer=card.rowbox
	var play := _shared_watch_button("Play",key,row,false,true)
	play.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	rowbox.add_child(play)
	if not wide and row.get("cached",false):
		var remove := _collection_delete_button(func(): _confirm_delete_shared_memory(key,row),str(row.get("title","")))
		remove.disabled=not _can_delete_shared_memory(key)
		rowbox.add_child(remove)
	return panel

## A shared chapter memory's part is its stage; earlier-island rows (no stage)
## keep their place in the list.
static func _shared_part(row: Dictionary, index: int) -> int:
	return int(row.stage_index) + 1 if row.has("stage_index") else index + 1

## Parts in the current shared room's chapter, or the rows listed when it has none.
func _shared_part_count(rows: Array) -> int:
	var room := _current_shared_room()
	var stages := RoomStages.count(ChapterRegistry.definition(str(room.get("chapter_key","")))) if not room.is_empty() else 0
	return stages if stages > 0 else rows.size()

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
	var thumbnail := _replay_preview_thumb(_shared_room_thumb_key(current),Vector2(0,220),16)
	preview.add_child(thumbnail)
	preview.set_meta("thumbnail",thumbnail)
	preview.add_child(_label(str(current.get("title","Replay")),28,CREAM,true))
	preview.add_child(_label("Part %d / %d" % [_shared_part(current,part),_shared_part_count(rows)],17,MUTED))
	preview.add_child(_shared_watch_button("Watch replay",key,current,true))
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
	_fit_replay_preview.call_deferred(preview)

func _shared_watch_button(text: String, key: String, row: Dictionary, primary: bool, list_row: bool=false) -> Button:
	## A saved replay opens its viewer, with its own loading bar, at once; one
	## that must be downloaded first shows the launch wait while it arrives.
	var launch := func(): await _open_shared_memory(key,row)
	if not row.get("cached",false): return _replay_launch_button(text,launch,primary,list_row)
	return _list_button(text,launch,primary) if list_row else _button(text,launch,primary)

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
	row.add_theme_constant_override("separation",10)
	var solo := _button("Solo",_show_collection,false)
	var together := _button("Together",_show_shared_replays,false)
	solo.disabled=selected=="solo"
	together.disabled=selected=="together"
	_selected_look(solo if selected=="solo" else together)
	ControlTheme.plain_tab(together if selected=="solo" else solo)
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
		_draw_shared_replay_memories(shared_replays.listed(key),"Replay deleted" if removed else shared_replays.last_error),false))
	_retry_cancel = func():
		if not current.call(): return
		if owner == _relay_identity() and _relay_identity().ready and _story_replay_memory_current() and _production_replay_key_allowed(key): _show_shared_replay_room(key)
		else: _show_shared_replays()
	card.add_child(_button("Cancel",_retry_cancel))

## Opening a chapter room asks the server once a session for parts this phone
## has not saved, so a room the friend finished elsewhere lists every part.
func _check_shared_room_parts(key: String) -> void:
	if _update_gate_active(): return
	if _shared_parts_checked.has(key) or not key.begins_with("chapter:") or shared_replays == null or shared_replays.local_loading() or key != shared_replay_room: return
	if not shared_replays.local_sequence(key).is_empty(): return
	# The one API may be fetching photos for this room: wait for it briefly
	# rather than skip the check until the player refreshes by hand.
	_shared_parts_checked[key] = false
	var deadline := Time.get_ticks_msec() + 10000
	while (api.busy or shared_replays.busy()) and Time.get_ticks_msec() < deadline and key == shared_replay_room and mode == "shared_memories":
		await get_tree().create_timer(0.1).timeout
	if key == shared_replay_room and mode == "shared_memories" and await _refresh_shared_replay_memories(): _shared_parts_checked[key] = true
	else: _shared_parts_checked.erase(key)

func _refresh_shared_replay_memories() -> bool:
	if _update_gate_active(): return false
	if shared_replays==null or shared_replays.busy() or api.busy or not _relay_identity().ready or not _story_replay_memory_current() or not _production_replay_key_allowed(shared_replay_room): return false
	var key := shared_replay_room
	var view := store_view_generation
	var owner := _relay_identity()
	# A finger on the page lifts first; then the checks above hold again or nothing starts.
	await TouchInput.until_released(overlay)
	if key!=shared_replay_room or shared_replays.busy() or api.busy or view!=store_view_generation or owner!=_relay_identity() or not _story_replay_memory_current(): return false
	_draw_shared_replay_memories(shared_replays.memories(key),"Checking completed stages…")
	# Drawing the page starts a new view; the refresh belongs to that one.
	view = store_view_generation
	var rows: Array=await shared_replays.refresh_memories(key)
	if mode!="shared_memories" or view!=store_view_generation or owner!=_relay_identity() or key!=shared_replay_room or not _story_replay_memory_current(): return true
	await _redraw_shared_room(key,func() -> Array: return rows)
	return true

## Automatic Together-page redraws (parts or photos that landed, a check that
## starts) wait for a finger on the page to lift, then check again that the page
## still shows `key` before rebuilding it, so a row never rebuilds under a tap.
## False when the page moved on meanwhile.
func _redraw_shared_room(key: String, rows: Callable, message: String = "", still: Callable = Callable()) -> bool:
	await TouchInput.until_released(overlay)
	if mode != "shared_memories" or key != shared_replay_room or is_instance_valid(shared_replay_child) or not _story_replay_memory_current(): return false
	if still.is_valid() and not still.call(): return false
	_draw_shared_replay_memories(rows.call(), message)
	return true

func _sync_shared_photos() -> void:
	if _update_gate_active(): return
	if _shared_photo_sync or _shared_archive_sync or shared_replays == null or shared_replays.busy() or api.busy or not _relay_identity().ready or not _story_replay_memory_current() or not _production_replay_key_allowed(shared_replay_room): return
	var key := shared_replay_room
	var owner := _relay_identity()
	var view := store_view_generation
	_draw_shared_replay_memories(shared_replays.listed(key), "Syncing photos…")
	var result := await _fetch_shared_room_photos(key, false)
	if mode == "shared_memories" and view == store_view_generation and owner == _relay_identity() and key == shared_replay_room:
		await _redraw_shared_room(key,func() -> Array: return shared_replays.listed(key),str(result.get("error","")),func() -> bool: return view == store_view_generation and owner == _relay_identity())

## Looks once a session for the friend's photos of a Together room that are not
## on this phone yet, without holding up the room or its replay; photos that
## arrive show in the list and in a replay already playing.
func _fetch_missing_shared_photos(key: String) -> void:
	if _update_gate_active(): return
	if _shared_photo_checked.has(key) or _shared_photo_sync or not key.begins_with("chapter:") or shared_replays == null or not _relay_identity().ready or not _story_replay_return.is_empty() or not _production_replay_key_allowed(key): return
	if shared_replays.local_entries(key).is_empty(): return
	_shared_photo_checked[key] = true
	var owner := _relay_identity()
	var result := await _fetch_shared_room_photos(key, true)
	if int(result.get("fetched",0)) == 0 or owner != _relay_identity(): return
	if is_instance_valid(shared_replay_child): shared_replay_child.refresh_photos()
	elif mode == "shared_memories" and key == shared_replay_room:
		await _redraw_shared_room(key,func() -> Array: return shared_replays.listed(key),"",func() -> bool: return not _shared_archive_sync and not _shared_photo_sync and owner == _relay_identity())

## The one path that brings a friend's turn photos for a Together room into this
## phone's photo library. With missing_only it asks only for the friend's turns
## not saved here; the photo controller then downloads bytes only for a digest
## the library lacks, saves them durably, then sends the delivery ACK. Requests
## go one at a time when the API is free and stop at SHARED_PHOTO_FETCH_LIMIT
## turns. The server still checks membership and blocking for every request,
## and the replay's photo strip applies its own hiding rules when it shows them.
func _fetch_shared_room_photos(key: String, missing_only: bool) -> Dictionary:
	if _shared_photo_sync or shared_replays == null or not _relay_identity().ready or not key.begins_with("chapter:"): return {"fetched":0,"error":""}
	var owner := _relay_identity()
	var session := SharedReplayView.ReadSession.new(api, _relay_identity)
	session.photo_context_factory = _campaign_media_factory()
	var targets: Array = []
	for entry: Dictionary in shared_replays.local_entries(key):
		for target: Dictionary in SharedReplays._verified_photo_turns(entry, owner.player_id):
			if missing_only and target.own: continue
			if not targets.has(target): targets.append(target)
	session.photo_targets = targets
	_shared_photo_sync = true
	var wanted: Array = []
	if missing_only:
		var saved: RefCounted = session.create_photo_controller(Callable())
		for target: Dictionary in targets:
			if (await saved.read_shared(target.room_id, target.turn_id, target.recording_hash)).is_empty(): wanted.append(target)
	else: wanted = targets
	if wanted.size() > SHARED_PHOTO_FETCH_LIMIT: wanted.resize(SHARED_PHOTO_FETCH_LIMIT)
	session.local_replay_only = false
	var controller: RefCounted = session.create_photo_controller(Callable())
	var fetched := 0
	for target: Dictionary in wanted:
		# Share the one API owner with whatever the player does meanwhile.
		var deadline := Time.get_ticks_msec() + 10000
		while api.busy and Time.get_ticks_msec() < deadline and owner == _relay_identity(): await get_tree().create_timer(0.25).timeout
		if owner != _relay_identity() or api.busy: break
		var photo: Dictionary = await controller.read_shared(target.room_id, target.turn_id, target.recording_hash)
		if not photo.get("bytes", PackedByteArray()).is_empty(): fetched += 1
	var error := str(controller.last_error) if owner == _relay_identity() else ""
	session.invalidate_identity()
	_shared_photo_sync = false
	return {"fetched":fetched,"error":error}

func _sync_shared_archive() -> void:
	if _shared_archive_sync or _shared_photo_sync or shared_replays == null or shared_replays.busy() or api.busy or relay_session == null or relay_session.busy() or not _relay_identity().ready or not _story_replay_return.is_empty() or not shared_replay_room.begins_with("chapter:") or not _production_replay_key_allowed(shared_replay_room): return
	var key := shared_replay_room
	var owner := _relay_identity()
	var session := relay_session
	_shared_archive_sync = true
	_draw_shared_replay_memories(shared_replays.listed(key), "Saving replays…")
	var view := store_view_generation
	var result := {"ok": false}
	if await session.load_capabilities():
		if owner == _relay_identity() and mode == "shared_memories" and key == shared_replay_room and view == store_view_generation:
			result = await session.sync_complete_replay(key.substr(8))
	_shared_archive_sync = false
	if owner == _relay_identity() and mode == "shared_memories" and key == shared_replay_room and view == store_view_generation:
		await _redraw_shared_room(key,func() -> Array: return shared_replays.listed(key),"Saved offline" if result.get("ok", false) else "Could not save replays",func() -> bool: return owner == _relay_identity() and view == store_view_generation)
	if result.get("ok", false) and owner == _relay_identity():
		_shared_photo_checked.erase(key)
		_fetch_missing_shared_photos(key)

## Downloads and saves one listed part without playing it, then shows it saved.
func _save_shared_memory(key: String, row: Dictionary) -> void:
	if shared_replays==null or shared_replays.busy() or api.busy or not _relay_identity().ready or not _story_replay_memory_current() or not _production_replay_key_allowed(key): return
	var view := store_view_generation
	var owner := _relay_identity()
	var entry: Dictionary=await shared_replays.open_memory(key,str(row.id),row)
	if mode!="shared_memories" or view!=store_view_generation or owner!=_relay_identity() or key!=shared_replay_room or is_instance_valid(shared_replay_child): return
	if entry.is_empty(): _toast(shared_replays.last_error); return
	await _redraw_shared_room(key,func() -> Array: return shared_replays.listed(key),"",func() -> bool: return view == store_view_generation and owner == _relay_identity())
	_shared_photo_checked.erase(key)
	_fetch_missing_shared_photos(key)

func _open_shared_memory(key: String, row: Dictionary) -> void:
	if shared_replays==null or (shared_replays.busy() and not row.get("cached",false)) or not _relay_identity().ready or is_instance_valid(shared_replay_child) or not _story_replay_memory_current() or not _production_replay_key_allowed(key): return
	if api.busy and not row.get("cached",false): _toast(PlayerCopy.MAIN_6BB9D408ABAB); return
	var view := store_view_generation
	var owner := _relay_identity()
	var entry: Dictionary=await shared_replays.open_memory(key,str(row.id),row)
	if mode!="shared_memories" or view!=store_view_generation or owner!=_relay_identity() or key!=shared_replay_room or not _story_replay_memory_current() or not _production_replay_key_allowed(key): return
	if entry.is_empty(): _toast(shared_replays.last_error); return
	_play_shared_entries([entry])
	if not row.get("cached",false):
		# A part saved just now may bring the friend's photos; they appear as they arrive.
		_shared_photo_checked.erase(key)
		_fetch_missing_shared_photos(key)

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
	shared_replay_child.friend_name=_room_partner_nickname(_current_shared_room())
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
	if _online_gated(): return
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
	var display_entries: Array = [["Graphics",_show_graphics_settings],["Notifications",_show_notification_settings]]
	# Subscribers reach Manage subscription and Restore here once Home hides the offer.
	if _play_store_enabled(): display_entries.append(["Full Journey",_show_store_from_settings])
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
	var account_group: Array = [["Account & recovery",_show_account]]
	if PlatformSupport.tester_code_offered(): account_group.append(["Tester code",_show_tester_access])
	for group: Array in [account_group,[["Community & privacy",_open_safety],[PlayerCopy.WHATS_NEW,func(): _open_whats_new_card()],["Licenses",_show_licenses]]]:
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
	var unlimited := CheckButton.new()
	unlimited.name = "UnlimitedFrameRate"
	unlimited.text = "Unlimited frame rate"
	unlimited.mouse_filter = Control.MOUSE_FILTER_PASS
	unlimited.button_pressed = GraphicsPolicy.unlimited_frame_rate(saves.data.settings)
	unlimited.toggled.connect(func(value: bool): _set_unlimited_frame_rate(value, unlimited))
	card.add_child(unlimited)
	card.add_child(_paragraph("Plays at your screen's full refresh rate. Uses more battery and can warm your phone.",500))
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

func _show_paywall(manual_store: bool = false, story_return: Dictionary = {}) -> void:
	running=false
	mode="paywall"
	_story_store_return = story_return.duplicate(true) if CampaignCatalog.PRODUCTION_ENABLED else {}
	tester_store_manual = manual_store
	if not manual_store: store_from_settings = false
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
		_add_store_elsewhere(card)
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
	var label := "Back to settings" if store_from_settings else "Back to chapters"
	card.add_child(_button("Return to Story" if CampaignCatalog.PRODUCTION_ENABLED and not _story_store_return.is_empty() else label,func():
		if mode == "paywall" and view == store_view_generation: _leave_store(),primary))

func _leave_store() -> void:
	if mode != "paywall": return
	if not CampaignCatalog.PRODUCTION_ENABLED: _story_store_return = {}
	if _story_store_return.is_empty():
		if store_from_settings:
			store_from_settings = false
			_show_settings()
		else: _show_journey()
		return
	var current := _story_store_current()
	_story_store_return = {}
	if current: _draw_story_lobby()
	else: _show_home()

func _play_store_enabled() -> bool:
	return Purchases.store_enabled(config)

func _open_google_play() -> void:
	OS.shell_open(UpdateGate.PLAY_LISTING_URL)

## A build without a store points to the Google Play listing and to tester access. An iOS
## App Store build shows neither: no other store, and no code that unlocks paid content.
func _add_store_elsewhere(card: VBoxContainer) -> void:
	if PlatformSupport.play_listing_offered(): card.add_child(_button("Get it on Google Play",_open_google_play))
	if PlatformSupport.tester_code_offered(): card.add_child(_button("Tester code",_show_tester_access,false))

## Every store state shares this card: the paid chapters on the left, and on
## the right the title and what the subscription pays for. Callers add the
## state's own actions to the returned column.
func _full_journey_card() -> VBoxContainer:
	var card := _card(1120)
	var columns := HBoxContainer.new()
	columns.name = "FullJourneyCard"
	columns.add_theme_constant_override("separation",24)
	card.add_child(columns)
	var gallery := PaidThumbnails.gallery(clampf(overlay.size.y-160.0,300.0,560.0))
	gallery.custom_minimum_size.x = 470
	columns.add_child(gallery)
	var column := VBoxContainer.new()
	column.name = "FullJourneyDetails"
	column.add_theme_constant_override("separation",14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(column)
	column.add_child(_label("Full Journey",32,CREAM,true))
	column.add_child(_paragraph(PlayerCopy.SUBSCRIPTION_PURPOSE,0))
	column.add_child(_paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,0))
	if config.get("purchase_mode") == "test_store":
		column.add_child(_paragraph(PlayerCopy.MAIN_38EAC523F08C,0))
	return column

## The one subscription offer used by the store card and locked hosting: each
## store package with its store price and period, the renewal terms, Restore
## and the privacy policy. Prices always come from the store.
func _add_subscription_choices(card: VBoxContainer) -> void:
	var choices := HBoxContainer.new()
	choices.name = "SubscriptionChoices"
	choices.add_theme_constant_override("separation",12)
	card.add_child(choices)
	for package: Dictionary in purchase_offer.get("packages",[]):
		var option := _button(_subscription_price_text(package),_buy_full_journey.bind(package))
		option.name = "Subscribe_"+str(package.get("period",""))
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.add_child(option)
	var terms := _paragraph(_subscription_terms(),0)
	terms.name = "SubscriptionTerms"
	terms.add_theme_font_size_override("font_size",16)
	card.add_child(terms)
	_add_store_links(card)

func _subscription_terms() -> String:
	match config.get("purchase_mode"):
		"test_store": return PlayerCopy.SUBSCRIPTION_TERMS_TEST
		"app_store": return PlayerCopy.SUBSCRIPTION_TERMS_APP_STORE
	return PlayerCopy.SUBSCRIPTION_TERMS_PLAY

static func _subscription_price_text(package: Dictionary) -> String:
	return (PlayerCopy.SUBSCRIPTION_YEARLY if package.get("period") == "year" else PlayerCopy.SUBSCRIPTION_MONTHLY) % str(package.get("price",""))

## Restore, Manage subscription for a subscriber, the privacy policy and, on iOS, the
## Terms of Use that App Review asks every subscription screen to link.
func _add_store_links(card: VBoxContainer) -> void:
	var links := HBoxContainer.new()
	links.name = "StoreLinks"
	links.add_theme_constant_override("separation",12)
	card.add_child(links)
	var buttons: Array[Button] = [_button("Restore purchases",_restore_store,false)]
	if _manage_subscription_available():
		buttons.append(_button(PlayerCopy.SUBSCRIPTION_MANAGE,_open_subscription_management,false))
	if not _privacy_url().is_empty():
		buttons.append(_button(PlayerCopy.SUBSCRIPTION_PRIVACY,func(): OS.shell_open(_privacy_url()),false))
	if PlatformSupport.is_ios():
		var terms := _button(PlayerCopy.SUBSCRIPTION_TERMS_OF_USE,func(): OS.shell_open(PlatformSupport.APPLE_TERMS_URL),false)
		terms.name = "TermsOfUse"
		buttons.append(terms)
	for button: Button in buttons:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		links.add_child(button)

func _manage_subscription_available() -> bool:
	return config.get("purchase_mode") in ["google_play","app_store"] and not Purchases.subscriptions_url(config).is_empty() and purchases.has_method("has_subscription") and purchases.has_subscription()

func _open_subscription_management() -> void:
	OS.shell_open(Purchases.subscriptions_url(config))

func _privacy_url() -> String:
	var base := str(config.get("api_base_url","")).trim_suffix("/")
	return base+"/privacy" if base.begins_with("https://") else ""

func _show_store_from_settings() -> void:
	store_from_settings = true
	_show_paywall(true)

func _hosting_entitled() -> bool:
	return _hosting_lock_reason().is_empty()

## Why hosting a Full Journey chapter is locked, from the one shared rule: a
## tester code opens it in every build; in the GitHub Test Store build a
## purchase opens solo only, so hosting waits for a code; a Google Play purchase
## opens hosting too. Reads cached entitlement only, never a per-screen store query.
func _hosting_lock_reason() -> String:
	return Purchases.hosting_lock_reason(config,purchases.has_entitlement(),_tester_active())

func _show_hosting_locked(chapter_key: String) -> void:
	running = false
	mode = "paywall"
	var descriptor := ChapterRegistry.descriptor(chapter_key)
	var test_store := str(config.get("purchase_mode","")) == "test_store"
	var shell := _screen_shell("Host a room",_show_rooms)
	var body := HBoxContainer.new()
	body.name = "HostingLocked"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",24)
	shell.outer.add_child(body)
	# The chapter picture keeps a steady 16:9 cover crop in rounded corners.
	var picture_area := AspectRatioContainer.new()
	picture_area.ratio = 16.0/9.0
	picture_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture_area.size_flags_stretch_ratio = 1.15
	body.add_child(picture_area)
	var frame := _replay_preview_thumb(chapter_key,Vector2.ZERO,20)
	frame.get_child(0).name = "HostingLockedHero"
	picture_area.add_child(frame)
	# Details scroll on their own whenever a short screen cannot fit them.
	var details := ScrollContainer.new()
	details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.follow_focus = true
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ControlTheme.touch_scroll(details)
	body.add_child(details)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(column)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style := _style(Color("1b443e"),20)
	for edge: String in ["left","top","right","bottom"]: panel_style.set("content_margin_"+edge,26)
	panel.add_theme_stylebox_override("panel",panel_style)
	column.add_child(panel)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation",12)
	panel.add_child(card)
	var title := _label(str(descriptor.get("title",chapter_key)),32,CREAM,true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(title)
	card.add_child(_label("Full Journey",22,GOLD))
	# A Test Store build offers no purchase here, so it names none.
	if not test_store: card.add_child(_paragraph(PlayerCopy.SUBSCRIPTION_PURPOSE,0))
	# "Full Journey is only required for the host. A friend may join by invitation."
	card.add_child(_paragraph(PlayerCopy.COOPERATIVE_HOST_ACCESS,0))
	if test_store:
		# This build's purchase cannot unlock hosting, so point to tester access
		# instead of offering a checkout that would not grant it.
		var owned := _hosting_lock_reason() == Purchases.HOSTING_NEEDS_TESTER_CODE
		card.add_child(_paragraph(PlayerCopy.HOSTING_NEEDS_TESTER_CODE if owned else PlayerCopy.MAIN_FAD34E850ED9,0))
		if PlatformSupport.tester_code_offered():
			var code := _button("Tester code",_show_tester_access)
			code.name = "HostingLockedTester"
			card.add_child(code)
	elif _play_store_enabled() and purchases.is_available() and not purchase_offer.is_empty():
		# Show the real store prices only when the store actually provided them.
		_add_subscription_choices(card)
	else:
		var unlock := _button("Unlock Full Journey",_show_paywall)
		unlock.name = "HostingLockedUnlock"
		card.add_child(unlock)
		card.add_child(_button("Restore purchases",_restore_store,false))

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
	_add_subscription_choices(card)
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
	elif _manage_subscription_available():
		card.add_child(_paragraph(PlayerCopy.for_platform(PlayerCopy.SUBSCRIPTION_ACTIVE,PlayerCopy.SUBSCRIPTION_ACTIVE_IOS),620))
	if _story_store_return.is_empty(): card.add_child(_button("Enter the Lighthouse",_open_lighthouse_preview))
	else: _add_store_back(card,true)
	_add_store_links(card)
	if _story_store_return.is_empty(): _add_store_back(card)

func _buy_full_journey(package: Dictionary) -> void:
	if not _play_store_enabled(): return
	# Only a package from the offering on screen can be bought.
	if store_action_pending or mode!="paywall" or not package in purchase_offer.get("packages",[]): return
	if not _store_identity_ready():
		_toast(PlayerCopy.MAIN_5FE98B59E6BA)
		return
	if purchases.has_entitlement():
		_show_full_journey_unlocked()
		return
	store_action_pending=true
	var card := _full_journey_card()
	card.add_child(_paragraph(PlayerCopy.MAIN_8A2FF5596F1C,600))
	store_action_request=purchases.purchase(str(package.offering_id),str(package.id))

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
		purchase_offer=Purchases.select_subscription_offer(payload,config)
		if purchase_offer.is_empty():
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
			elif not purchase_offer.is_empty(): _show_store_offer()
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
		if mode=="paywall" and not purchase_offer.is_empty() and _store_identity_ready(): _show_store_offer()
	if mode == "paywall" and not store_action_pending and (operation in ["configure","get_customer_info","get_offerings"] or purchase_offer.is_empty()):
		_show_store_problem(PlayerCopy.MAIN_B621C76A2638 if cancelled else message)
	_toast(PlayerCopy.MAIN_B621C76A2638 if cancelled else message)

func _customer_info_changed(_payload: Dictionary) -> void:
	# The store may finish loading after the grid opens. Refresh the locks here;
	# button callbacks still check the current entitlement when pressed. The
	# store reports on every launch and resume, mostly with nothing new, and a
	# redraw frees the card under a finger, so only a change in access redraws,
	# after any tap in progress.
	if mode in ["journey","earlier_islands"]:
		if _full_journey_access() == _grid_access_drawn: return
		await TouchInput.until_released(overlay)
		if _full_journey_access() == _grid_access_drawn: return
		if mode=="journey": _show_journey()
		elif mode=="earlier_islands": _show_earlier_islands()
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
	if _online_gated(): return
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
	if not _tester_checks_enabled() or tester_checked_context == _tester_context(): return
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
	# One request at a time: a room save or replay delivery may still hold the
	# API. Reading then would report the rooms as offline, so the hub keeps its
	# saved list until the API is free.
	var deadline := Time.get_ticks_msec() + 20000
	while api.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not is_instance_valid(hub) or hub != room_hub_screen: return
	if api.busy or not is_instance_valid(hub) or hub != room_hub_screen: return
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
	if api.busy:
		hub.show_notice(PlayerCopy.ROOMS_API_DA75E6F7A674)
		return
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

func _open_friends_from_room_hub() -> void:
	if mode != "rooms": return
	# The hub stays up until Friends opens (_show_friends releases it then), so
	# a refused open leaves the hub with its reason instead of a blank screen.
	if not await _hub_wait_for_api(""): return
	await _show_friends()
	if is_instance_valid(friends_screen) or mode != "rooms": return
	_hub_message(toast_label.text if toast_label.visible else "")

## The hub's taps (Continue, Open, Host, Join, Friends) share one request slot
## with the hub's own room list, a replay delivery or a share. A tap made while
## it is busy waits here a few seconds, with the hub up and saying so, instead
## of being refused. A later tap replaces an earlier waiting one. True when the
## tap may go ahead now.
var hub_tap_wait_ms := 10000
var _hub_wait_generation := 0
func _hub_wait_for_api(waiting: String) -> bool:
	_hub_wait_generation += 1
	if _hub_api_free(): return true
	var generation := _hub_wait_generation
	var hub := room_hub_screen
	if not is_instance_valid(hub): return false
	if not waiting.is_empty(): hub.show_notice(waiting)
	var deadline := Time.get_ticks_msec() + hub_tap_wait_ms
	while not _hub_api_free() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if generation != _hub_wait_generation or not is_instance_valid(hub) or hub != room_hub_screen or mode != "rooms": return false
	if _hub_api_free(): return true
	hub.show_notice(PlayerCopy.MAIN_8184DEB41266)
	return false

## The transient work a hub tap can wait out. A saved legacy turn is not
## transient; the room flow reports it as before.
func _hub_api_free() -> bool:
	return not (submission_in_flight or api.busy or foreground_refresh_running or (relay_session != null and relay_session.busy()))

## A reason the hub tap stopped, on the hub when it is up, or on Home's toast
## after the room flow settles back to the hub.
func _hub_message(text: String) -> void:
	if mode == "rooms" and is_instance_valid(room_hub_screen):
		room_hub_screen.show_notice(text)
		return
	if not text.is_empty(): _toast(text)
	_settle_room_flow()

func _open_room_from_hub(room: Dictionary) -> void:
	if mode != "rooms" or not _relay_identity().ready: return
	var version := int(room.get("api_version",0))
	var room_id := str(room.get("room_id",""))
	if room_id.is_empty(): return
	if not await _hub_wait_for_api(PlayerCopy.HUB_OPENING_ROOM): return
	var inbox: RefCounted = room_inbox
	if is_instance_valid(room_hub_screen): room_hub_screen.queue_free()
	room_hub_screen = null
	ui.visible = true
	if room.get("status") == "completed":
		# Completed rooms open their exact shared replay, which also counts as
		# seeing the room's latest activity.
		if inbox != null: inbox.confirm_room_rendered(version,room_id)
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
		else: _settle_room_flow()
	else:
		_return_to_room_hub("This room can't be opened on this version of After You.")

func _host_from_room_hub(chapter_key: String, visibility: String) -> void:
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
		_show_hosting_locked(chapter_key)
		return
	selected_online_chapter = chapter_key
	room_hub_host_visibility = visibility
	if not await _hub_wait_for_api(PlayerCopy.HUB_OPENING_ROOM): return
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
	_show_tester_access()

func _join_from_room_hub(code: String) -> void:
	if mode != "rooms" or not _relay_identity().ready: return
	# Accept room-<code> and legacy input; a friend code gets a clear local error.
	var parsed := ShareCodes.parse(code,ShareCodes.ROOM)
	if not parsed.ok:
		_hub_message(ShareCodes.error_message(parsed,PlayerCopy.ROOMS_API_57B8AA801916))
		return
	code = parsed.id
	if not await _hub_wait_for_api(PlayerCopy.HUB_JOINING): return
	if not await _prepare_ordinary_navigation():
		_hub_message(toast_label.text if toast_label.visible else "")
		return
	if mode != "rooms": return
	_hub_message(PlayerCopy.HUB_JOINING)
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

func _show_friends() -> void:
	if _online_gated(): return
	var from_home := mode == "home"
	var view := store_view_generation
	var lifecycle := lifecycle_generation
	if not _relay_available() or not await _ensure_identity(): return
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
	friends_screen.hosting_view_ready.connect(_hosting_notification_view_ready)
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

## Friends requests use Main's one API node; wait briefly for one in flight.
func _friends_api_idle(context: Dictionary, client: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while (api.busy or client.busy) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _friends_route_current(context): return false
	return not api.busy and not client.busy and _friends_route_current(context)

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
	if relay_session == null: relay_session = _new_relay_session()
	return relay_session.history_pair(room_id, chapter_key, pair_id)

func _ask_for_attempt(room_id: String, position: int) -> void:
	if relay_session == null: relay_session = _new_relay_session()
	if relay_session.capabilities.is_empty(): await relay_session.load_capabilities()
	await relay_session.want_room_attempt(room_id, position)

func _invalidate_relay_identity(clear_notifications: bool = true) -> void:
	_shared_archive_attempts.clear()
	_shared_photo_checked.clear()
	_shared_parts_checked.clear()
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

func _relay_available() -> bool:
	if submission_in_flight or api.busy or foreground_refresh_running or not saves.data.get("pending_turn",{}).is_empty():
		_toast(PlayerCopy.MAIN_8184DEB41266)
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
	var back := _button("Back",_return_to_room_hub,false)
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
	while (api.busy or events.busy) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _relay_identity().ready: return false
	if api.busy or events.busy: return false
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
	relay_child.turn_notification_status = _turn_notification_status
	relay_child.enable_turn_notifications = _enable_turn_notifications
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
		if _history_mode(relay_session) and int(room.get("branch", 0)) > 0: await _save_finished_replay(str(room.room_id), int(room.revision), true)
		return
	await _save_finished_replay(str(room.room_id), int(room.revision))

## Brings a finished room's whole replay to this phone and, once both phones
## hold it, lets the server keep only a compact record; then fetches the
## friend's photos for it. Safe to repeat: the download and its ACK are keyed
## by the room's replay epoch, and a room already saved is not asked again.
## With a revision (leaving that room's play) it stops once the room moves
## on, such as a redo. Not while a turn or a replay plays: it runs on an idle
## screen. True when this phone holds the replay afterwards.
func _save_finished_replay(room_id: String, revision: int = -1, in_play: bool = false) -> bool:
	# One save per room at a time; a second caller is served by the first.
	if replay_saves.has(room_id): return false
	replay_saves[room_id] = true
	var saved: bool = await _save_finished_replay_once(room_id, revision, in_play)
	replay_saves.erase(room_id)
	_finished_replay_saved(room_id, saved)
	return saved

func _save_finished_replay_once(room_id: String, revision: int, in_play: bool = false) -> bool:
	var owner := _relay_identity()
	var key := str(owner.player_id) + ":" + room_id + ":" + str(revision)
	if not owner.ready or _shared_archive_attempts.has(key): return _shared_archive_attempts.get(key, false) == true
	if relay_session == null: relay_session = _new_relay_session()
	var session: RefCounted = relay_session
	var delays: Array[float] = [0.0]
	delays.append_array(replay_save_retry_s)
	for delay: float in delays:
		if delay > 0.0: await get_tree().create_timer(delay).timeout
		var deadline := Time.get_ticks_msec() + 5000
		while (api.busy or session.busy() or _shared_archive_sync or _shared_photo_sync) and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
		if owner != _relay_identity() or session != relay_session or application_backgrounded or not _replay_save_idle(): return false
		if revision >= 0:
			var bound: Dictionary = session.coordinator.snapshot() if session.coordinator != null else {}
			if bound.get("room_id") != room_id or int(bound.get("revision", -1)) != revision or (bound.get("active_role") != "complete" and not in_play) or not session.coordinator.pending().is_empty(): return false
		if api.busy or session.busy() or _shared_archive_sync or _shared_photo_sync: continue
		if session.capabilities.is_empty() and not await session.load_capabilities(): continue
		if owner != _relay_identity() or session != relay_session: return false
		if session.has_method("last_room"): session.last_room() # Loads the saved room index the proof below reads.
		if (session.capabilities.get("replay_transfer_version") != 1 and not _history_mode(session)) or (in_play and not _history_mode(session)) or (not _history_mode(session) and not session.standalone_room_proven(room_id)): return false
		if api.busy or session.busy() or _shared_archive_sync: continue
		_shared_archive_sync = true
		var result: Dictionary
		if in_play: result = await session.sync_room_history(room_id)
		else: result = await session.sync_complete_replay(room_id)
		_shared_archive_sync = false
		if owner != _relay_identity(): return false
		if result.get("ok", false):
			# A room history pass from Watch replay may run again on a later tap.
			if revision >= 0 or not _history_mode(session): _shared_archive_attempts[key] = true
			# The replay now plays from this phone, so bring the friend's photos with it.
			await _fetch_shared_room_photos("chapter:" + room_id, true)
			return true
		if not _replay_save_transient(result):
			_shared_archive_attempts[key] = false
			return false
	return false

## Room history is on for this session (older test doubles have no such method).
static func _history_mode(session: RefCounted) -> bool:
	return session != null and session.has_method("history_mode") and session.history_mode()

## Saving reads and verifies a whole replay: never during a turn or playback.
func _replay_save_idle() -> bool:
	return not running and mode != "shared_replay" and not is_instance_valid(shared_replay_child) and not (is_instance_valid(relay_child) and relay_child.running)

## A save that met a busy API, a lost connection or an outage; worth repeating.
static func _replay_save_transient(result: Dictionary) -> bool:
	var status := int(result.get("status", 0))
	return status == 0 or status == 429 or status >= 500 or str(result.get("code", "")) in ["request_busy", "connection_interrupted", "replay_transfer_busy", "replay_transfer_unavailable", "replay_transfer_context_changed", "rate_limited", "replay_transfer_rate_limited"]

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
		_toast(PlayerCopy.for_platform(PlayerCopy.MAIN_3E8E7DA4CEE6,PlayerCopy.MAIN_3E8E7DA4CEE6_IOS))
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
	if before != client.view(): _redraw_room_when_free(str(active_room.get("room_id","")))

## A poll's redraw of the room page waits for a tap in progress to finish, or
## the button under the finger would be freed and the tap lost.
func _redraw_room_when_free(room_id: String) -> void:
	await TouchInput.until_released(overlay)
	if mode=="room" and str(active_room.get("room_id",""))==room_id: _show_room_detail()

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
	card.add_child(_paragraph(PlayerCopy.for_platform(PlayerCopy.MAIN_F890477C65DE,PlayerCopy.MAIN_F890477C65DE_IOS)))
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
		elif PlatformSupport.tester_code_offered(): card.add_child(_button("Tester code",_show_tester_access,false))
		card.add_child(_button("Delete online identity…",_confirm_delete_identity,false))
		card.add_child(_button("Photo transfer",_open_photo_transfer,false))
		# Room history is never removed automatically, so show what it takes.
		if RoomsApi.history_supported: card.add_child(_paragraph(PlayerCopy.MAIN_ROOM_HISTORY_SPACE % HistoryStore.size_text(HistoryStore.new().usage_bytes())))
		card.add_child(_button("Reports & blocked players",func(): _open_safety({},"account"),false))
	elif api.configured() and secrets.is_available():
		if identity_read_state==IdentityReadState.MISSING:
			card.add_child(_button("Create anonymous identity",func(): if await _ensure_identity(): _show_account()))
		else:
			card.add_child(_paragraph(PlayerCopy.MAIN_3E50EF2B7ECB))
			card.add_child(_button("Check saved identity",_retry_saved_identity,false))
	else:
		card.add_child(_paragraph(PlayerCopy.for_platform(PlayerCopy.MAIN_570EC629872D,PlayerCopy.MAIN_570EC629872D_IOS)))
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
			if PlatformSupport.tester_code_offered(): card.add_child(_button("Tester code",_show_tester_access,false))
		elif _play_store_enabled():
			card.add_child(_paragraph(PlayerCopy.MAIN_5DCCD071AE03))
		else:
			_add_store_elsewhere(card)
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
	card.add_child(_paragraph(PlayerCopy.MAIN_C93C27D9AB17 if PlatformSupport.tester_code_offered() else PlayerCopy.MAIN_C93C27D9AB17_NO_TESTER))
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
	if not hosting_notification_preferences.clear_owner(owner,api.base_url):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_3820D398892A)
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
const FROZEN_SHADE_ALPHA := 0.85
var _backdrop_view: SubViewport
var _backdrop_shade_id := 0
var _backdrop_frames := 0
var _backdrop_ready := false

func _service_world_cover() -> void:
	var shade: ColorRect = overlay_shade if is_instance_valid(overlay_shade) and overlay_shade.color.a >= FROZEN_SHADE_ALPHA and overlay.visible and is_instance_valid(world) and world.visible and not application_backgrounded else null
	var shade_id := shade.get_instance_id() if shade != null else 0
	if shade_id != _backdrop_shade_id: _start_backdrop(shade)
	elif shade != null and not _backdrop_ready and is_instance_valid(_backdrop_view): _finish_backdrop(shade)
	var covered := is_instance_valid(friends_screen) or is_instance_valid(room_hub_screen) or is_instance_valid(safety_screen) or is_instance_valid(redo_screen) or (shade != null and _backdrop_ready)
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
	var view := SubViewport.new()
	view.size = get_viewport().size
	view.world_3d = get_viewport().world_3d
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

## Puts the still under the shade once it is rendered. A renderer that gives
## no image (headless) keeps the live world.
func _finish_backdrop(shade: ColorRect) -> void:
	_backdrop_frames += 1
	if _backdrop_frames < 2: return
	var image: Image = _backdrop_view.get_texture().get_image()
	_backdrop_view.queue_free()
	_backdrop_view = null
	if image == null or image.is_empty(): return
	var still := TextureRect.new()
	still.name = "FrozenWorld"
	still.texture = ImageTexture.create_from_image(image)
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

func _toast(text: String) -> void:
	toast_label.text=text
	toast_label.visible=true
	toast_time=6.0

func _process(delta: float) -> void:
	_service_world_cover()
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
		if mode == "identity_deleting" or deletion_cleanup_busy or mode == "update_gate": return
		if is_instance_valid(_whats_new_card): _whats_new_card.close()
		elif mode == "collection_loading": _show_collection()
		elif mode == "story_lobby": _story_back()
		elif mode == "story_access": _draw_story_lobby()
		elif mode == "paywall" and not _story_store_return.is_empty(): _leave_store()
		elif mode in ["confirm_retry", "confirm_restart", "confirm_delete_replay"]:
			if _retry_cancel.is_valid(): _retry_cancel.call()
		elif mode == "story_replay_chapters": _return_story_replay_lobby()
		elif mode == "shared_memories" and not _story_replay_return.is_empty(): _back_to_story_replay_chapters()
		# Together replays: Android Back goes where their on-screen Back goes.
		elif mode in ["shared_replays", "shared_memories"] and not is_instance_valid(shared_replay_child): _show_home()
		elif running or mode=="completion":
			_pause()
		elif mode=="license_text":
			_show_licenses()
		elif mode in ["licenses", "tester_access", "graphics_settings"]:
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
	turn_notifications.configure_hosting(hosting_notification_preferences.read,hosting_notification_preferences.save)
	turn_notifications.configure_requests(_turn_request_preference, _save_turn_request_preference)
	turn_notifications.changed.connect(_update_notification_offer)
	turn_notifications.foreground_hint.connect(_notification_foreground_hint)
	turn_notifications.route_available.connect(func():
		if is_instance_valid(toast_label): _toast(PlayerCopy.MAIN_6FE6B224FD24))
	add_child(turn_notifications)

func _notification_identity() -> Dictionary:
	return {"ready": _relay_identity().ready, "settled": not identity_loading and identity_read_state not in [IdentityReadState.UNCHECKED, IdentityReadState.LOADING], "owner": api.player_id if api != null else "", "credential_hash": _token_digest() if api != null and not api.device_token.is_empty() else ""}

## The device token's SHA-256, kept until the token changes: several services
## build identity keys from it every frame.
var _digested_token := ""
var _token_sha := ""
func _token_digest() -> String:
	if api.device_token != _digested_token:
		_digested_token = api.device_token
		_token_sha = _digested_token.sha256_text()
	return _token_sha

func _notification_preference() -> bool:
	return saves.data.settings.get("turn_notifications", false) == true

func _save_notification_preference(value: bool) -> bool:
	var next: Dictionary = saves.data.settings.duplicate(true)
	next.turn_notifications = value
	return saves.update_values({"settings": next})

func _turn_request_preference() -> bool:
	return saves.data.settings.get("turn_request_notifications", false) == true

func _save_turn_request_preference(value: bool) -> bool:
	var next: Dictionary = saves.data.settings.duplicate(true)
	next.turn_request_notifications = value
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
	card.add_child(_paragraph(PlayerCopy.for_platform(PlayerCopy.MAIN_EF43E19393E4,PlayerCopy.MAIN_EF43E19393E4_IOS), 560))
	_add_notification_offer(card)
	_add_turn_request_option(card)
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

func _add_turn_request_option(card: VBoxContainer) -> void:
	notification_request_toggle = CheckButton.new()
	notification_request_toggle.name = "TurnRequestNotifications"
	notification_request_toggle.text = PlayerCopy.TURN_REQUEST_NOTIFICATIONS
	# Wraps within the hint's width so the label never clips on a small screen.
	notification_request_toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notification_request_toggle.custom_minimum_size.x = 480
	notification_request_toggle.button_pressed = _turn_request_preference()
	notification_request_toggle.toggled.connect(_set_turn_request_notifications)
	card.add_child(notification_request_toggle)
	notification_request_hint = _paragraph(PlayerCopy.TURN_REQUEST_NOTIFICATIONS_NEEDS_TURNS, 480)
	notification_request_hint.name = "TurnRequestNotificationsHint"
	card.add_child(notification_request_hint)
	_update_notification_offer()

func _set_turn_request_notifications(value: bool) -> void:
	if turn_notifications.set_requests_enabled(value): return
	if is_instance_valid(notification_request_toggle): notification_request_toggle.set_pressed_no_signal(_turn_request_preference())
	_toast(PlayerCopy.MAIN_34B82590B663)

func _update_notification_offer() -> void:
	if not is_instance_valid(turn_notifications): return
	var state := _turn_notification_status()
	if is_instance_valid(notification_hint): notification_hint.text = state.message
	if is_instance_valid(notification_request_toggle): notification_request_toggle.disabled = not state.enabled
	if is_instance_valid(notification_request_hint): notification_request_hint.visible = not state.enabled
	if is_instance_valid(notification_offer):
		notification_offer.visible = not state.registered
		notification_offer.disabled = state.busy
	if is_instance_valid(relay_child): relay_child.update_notification_offer()

func _notification_foreground_hint(route: Dictionary) -> void:
	if not turn_notifications.accepts(route): return
	if route.get("kind") == "friend_room_available":
		# Android shows no banner while the app is open, so say it here. The toast
		# sits under the hidden main UI while a room is open; the room card shows it.
		var message := FriendNicknames.sentence_start(_friend_display_name(str(route.host_id))) + " has a room ready"
		if is_instance_valid(friends_screen): friends_screen.hosting_hint()
		elif is_instance_valid(relay_child): relay_child.notification_deferred(message)
		else: _toast(message)
		return
	if route.room_family == "relay" and is_instance_valid(relay_child):
		relay_child.notification_room_hint(route.room_id)
	elif route.room_family == "legacy" and str(saves.data.get("room", {}).get("room_id", "")) == route.room_id:
		foreground_refresh_queued = true
	# The ordinary refresh schedulers enforce mode, identity, busy and cooldown
	# guards. Receiving a hint never reconciles a POST or changes the open room.

func _hosting_notification_view_ready(_events: Array) -> void:
	var route: Dictionary = turn_notifications.pending_route()
	# A rendered authenticated inbox also resolves revoked or expired publications.
	if route.get("kind") == "friend_room_available" and turn_notifications.accepts(route):
		turn_notifications.acknowledge_route(str(route.event_id))

func _notification_route_safe(route: Dictionary) -> bool:
	if not _campaign_notification_unbound(): return false
	if application_backgrounded or running or submission_in_flight or identity_loading or identity_busy or foreground_refresh_running or is_instance_valid(relay_child) or saves.read_only: return false
	if mode not in ["home", "rooms", "room", "journey", "earlier_islands", "collection", "saved", "relay_rooms"] and not (mode == "friends" and route.get("kind") == "friend_room_available"): return false
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
	# While this build is too old, a tap on an alert brings up the update screen
	# on Home rather than opening a room or Friends. The alert is used up once.
	if _update_gate_active():
		turn_notifications.acknowledge_route(route.event_id)
		_request_update_gate()
		return
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
	if route.get("kind") == "friend_room_available":
		notification_route_retry_ms = Time.get_ticks_msec() + 15000
		if is_instance_valid(friends_screen): await friends_screen._refresh()
		else: await _show_friends()
		return
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
		# A room the friend closed says so; other failures keep the general note.
		_toast(PlayerCopy.ROOMS_API_A7ACF38988EE if RelayOnline._room_gone(response) else PlayerCopy.MAIN_15214ED7911C)
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
		if route.get("kind") == "redo_requested": _refresh_legacy_redo()
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
	if not _relay_identity().ready or api.busy or not saves.data.get("pending_turn", {}).is_empty() or not saves.data.get("room_draft", {}).is_empty(): return false
	if relay_session != null and (relay_session.busy() or not relay_session.can_leave_for_legacy() or (relay_session.coordinator != null and not relay_session.coordinator.draft().is_empty())): return false
	return _legacy_redo_navigation_ready("", false)

func _open_photo_resume_room(room_id: String) -> void:
	if _online_gated(): return
	if not _photo_resume_safe():
		_toast(PlayerCopy.MAIN_BE8E691311EE)
		return
	if relay_session == null: relay_session = _new_relay_session()
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

func _notification_owned_room(room: Variant, route: Dictionary) -> bool:
	return room is Dictionary and room.get("room_id") == route.room_id and api.player_id in [room.get("host_id"), room.get("guest_id")] and TurnNotifications._integer(room.get("revision")) and int(room.revision) >= int(route.revision)

func _setup_invite_links() -> void:
	invite_link_bridge = InviteLinkBridge.new()
	invite_link_bridge._native = invite_link_native
	invite_link_bridge.received.connect(_invite_link_received)
	add_child(invite_link_bridge)

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
	if application_backgrounded or submission_in_flight or foreground_refresh_running or identity_loading or identity_busy or api.busy: return true
	if identity_read_state in [IdentityReadState.UNCHECKED, IdentityReadState.LOADING]: return true
	return relay_session != null and relay_session.busy()

## At least as strict as _notification_route_safe. A link never creates an identity:
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
	return PlatformSupport.store_gated() or tester_access_factory.is_valid()

func _tester_context() -> String:
	if not _relay_identity().ready: return ""
	return JSON.stringify([api.base_url, api.player_id, _token_digest(), relay_identity_epoch])

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
		if mode == "tester_access" and view == store_view_generation: _tester_form(PlayerCopy.for_platform(PlayerCopy.MAIN_B39BBA0B04B0,PlayerCopy.MAIN_B39BBA0B04B0_IOS))
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
	if _play_store_enabled(): card.add_child(_button("Store purchases",_show_store_from_settings,false))
	elif PlatformSupport.play_listing_offered(): card.add_child(_button("Get it on Google Play",_open_google_play,false))
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
	# The next scene draws 3D in this same root viewport.
	if is_instance_valid(_backdrop_view): _backdrop_view.queue_free()
	if _world_covered:
		_world_covered = false
		get_viewport().disable_3d = false
	_cancel_collection_replay()
	if _collection_replay_worker != null and _collection_replay_worker.is_started():
		_collection_replay_worker.wait_to_finish()
		_collection_replay_worker=null
	# Opening a chapter from Solo replays changes scene mid-scan. Keep what the
	# scan has settled, then let the reaper join its verifier instead of this
	# frame (the service's own teardown would block on it).
	if solo_replays != null and solo_replays.has_method("release_workers"):
		_cancel_solo_collection_scan()
		solo_replays.release_workers()
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
